import Ke, { homedir as gm } from "os";
import Or, {
  app as ye,
  dialog as Xe,
  session as fr,
  powerMonitor as st,
  screen as ur,
  ipcMain as wm,
  clipboard as or,
  ClipboardItem as Rs,
  Notification as ym,
  shell as Dt,
  autoUpdater as Ys,
  BrowserWindow as He,
  Tray as Em,
  nativeImage as Ks,
  Menu as lr,
  systemPreferences as Jr,
  nativeTheme as vm,
  TouchBar as Sh,
  globalShortcut as Yu,
  protocol as Cm,
} from "electron";
import Am from "electron-drag-click";
import {
  i as Ku,
  t as _h,
  f as Qr,
  k as kt,
  b as bm,
  j as Fm,
  s as Ju,
  c as Sm,
  g as Th,
  W as xh,
  w as _m,
} from "./AsyncSqlite-CpInlfQ-.mjs";
import Ve from "./package-CIHfweXK.mjs";
import {
  bQ as Tm,
  cl as xm,
  cf as Nm,
  b6 as Im,
  aD as Om,
  a2 as yt,
  b_ as Pm,
  bv as Re,
  a1 as Rm,
  bB as Lm,
  q as Qu,
  c0 as Bm,
  af as km,
  aY as Mm,
  bN as Um,
  a7 as qm,
  s as $m,
  bI as jm,
  v as Wm,
  u as Hm,
  bs as Gm,
  bE as Vm,
  t as zm,
  bG as Xm,
  r as Ym,
  G as Km,
  aM as Nh,
  a9 as Ih,
  a8 as No,
  aH as Jm,
  _ as Qm,
  K as Zm,
  bM as Ur,
  bK as eg,
  an as tg,
} from "./Keychain-CHHka2u7.mjs";
import { u as It, p as Xn, a as Io } from "./index-DKkZ9dV1.mjs";
import {
  S as rg,
  P as ng,
  B as Zu,
  b as ig,
  N as og,
  s as ag,
  U as sg,
  A as ug,
  n as lg,
  O as cg,
  g as Js,
} from "./util-CrY9x2BW.mjs";
import G, { join as ko } from "path";
import fg from "node:net";
import dg from "node:os";
import { D as Oh, r as Ls } from "./remote-method-Dje_9VSb.mjs";
import xt, {
  randomUUID as hg,
  randomBytes as Oo,
  createHash as pg,
} from "crypto";
import on, { promisify as Mo } from "util";
import {
  getDefaultLocalHostname as Dg,
  getDefaultExternalHostname as mg,
} from "./local-ips-64rTQJNz.mjs";
import gg, { access as wg } from "fs/promises";
import {
  getStartupCheckpoints as yg,
  markStartupCheckpoint as Qs,
} from "./startup-checkpoints-BQimOHWq.mjs";
import { e as Ie } from "./index-CMOlVndj.mjs";
import ze, {
  promises as Te,
  readFileSync as Eg,
  createWriteStream as vg,
  constants as Cg,
  existsSync as Ag,
} from "fs";
import {
  IS_MAC_OS as Ne,
  IS_WINDOWS as Kt,
  IS_LINUX as cr,
  resolveUserDataDir as bg,
  BUNDLE_ID as dr,
  ONBOARDING_SCREEN_HEIGHT as Fg,
  ONBOARDING_SCREEN_WIDTH as Sg,
  PUBLIC_DIR_PATH_UNPACKED as Uo,
  IS_MONTEREY_OR_UP as Ph,
  PUBLIC_DIR_PATH as _g,
  GOOGLE_OAUTH_CLIENT_ID as Tg,
  APPLE_SIGN_IN_SERVICES_ID as xg,
  GOOGLE_OAUTH_CLIENT_SECRET as Ng,
  APPLE_SIGN_IN_REDIRECT_URI as Ig,
  MAC_TRAFFIC_LIGHT_POSITION as Og,
  DEEP_LINK_PROTOCOL as Pg,
  BEEPER_CHANGELOG_LINK as Rg,
  PRIVACY_URL as Lg,
  IS_SEQUOIA_OR_UP as Bg,
  USER_AGENT as kg,
} from "./constants-BL_pdRyX.mjs";
import { setTimeout as Xi } from "timers/promises";
import { s as el } from "./index-B_PiTES1.mjs";
import { callAppAPI as Rh } from "./app-api-NqP9XGk0.mjs";
import { l as Mg, f as Ug } from "./macos-contacts-server-D9gt4gn9.mjs";
import { e as tt, q as Lh } from "./fs-xattr-D7o0ii7n.mjs";
import qg from "diskusage";
import { c as $g, R as Vr } from "./rolling-logger-C9NTeNo3.mjs";
import jg, { readdir as Wg, readFile as Hg } from "node:fs/promises";
import {
  resolve as Gg,
  join as Gn,
  relative as Vg,
  isAbsolute as zg,
  basename as Xg,
} from "node:path";
import Mt, { fileURLToPath as ni } from "url";
import { I as Pr, a as Yg } from "./sentry-enabled-COAVq6nC.mjs";
import {
  REPORT_INTERVALS_MS as Kg,
  registerSystemStatsReporting as Jg,
} from "./system-stats-BLVoJrkB.mjs";
import { l as ut, t as Bh } from "./logger-DoW0T1f3.mjs";
import { a as pr, c as Nt } from "./_commonjsHelpers-CBUqixCJ.mjs";
import { imageSizeFromFile as Qg } from "./fromFile-Bd43zJBF.mjs";
import { F as kh, g as Mh } from "./utils-D8MokWSu.mjs";
import { pipeline as Bs } from "stream/promises";
import { g as Ir, r as Zg, b as e0 } from "./got-_wC7Q_ix.mjs";
import { v as hr } from "./v4-BcIr5opf.mjs";
import Zs from "events";
import { fileURLToPath as Uh } from "node:url";
import { downloadFile as t0 } from "./download-DaM5ZnbT.mjs";
import qo, { execFile as qh, exec as $h } from "child_process";
import jh from "constants";
import ii from "stream";
import Wh from "assert";
import r0 from "tty";
import Hh from "string_decoder";
import { r as Gh } from "./index-BiHJsdYm.mjs";
import eu from "zlib";
import Vh from "http";
import { M as n0 } from "./machine-id-DFkLVgcU.mjs";
import { s as Kr, u as i0 } from "./sentry-common-CDPx3Glo.mjs";
import tl from "./SimpleHTMLParser-DYKa0uJQ.mjs";
import rl from "./SimpleTwitterClient-BlyQEWJV.mjs";
import { s as nl } from "./index-BE_LQecc.mjs";
import { b as Yn, r as zh } from "./readable-VMWn1OrG.mjs";
import o0 from "buffer";
import { s as a0 } from "./register-proxy-7lV9pun2.mjs";
import { l as s0 } from "./sentry-buffer-BdjgCKZo.mjs";
import { startCrashReporter as u0 } from "./crash-reporter-BlEAKQlO.mjs";
import l0 from "node:module";
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
      (e._sentryDebugIds[t] = "b6bb2043-6429-4808-847f-9723d2567a97"),
      (e._sentryDebugIdIdentifier =
        "sentry-dbid-b6bb2043-6429-4808-847f-9723d2567a97"));
  } catch {}
})();
const eF = import.meta.filename,
  tu = import.meta.dirname,
  c0 = l0.createRequire(import.meta.url),
  Po = process.env.BEEPER_PROFILE,
  f0 = Po ? `-${Po}` : "";
process.env.BEEPER_USER_DATA_DIR
  ? (logger.log(
      "Using custom user data dir:",
      process.env.BEEPER_USER_DATA_DIR,
    ),
    ye.setPath("userData", process.env.BEEPER_USER_DATA_DIR))
  : Po &&
    (logger.log("Using a non-default profile:", Po),
    ye.setPath("userData", ye.getPath("userData") + f0));
globalThis.texts ||= {
  log: Ku ? (...e) => logger.log(...e) : () => {},
  error: Ku ? (...e) => logger.error(...e) : () => {},
};
const Kn = rg ?? It.server_env ?? "production",
  lt = ye.getPath("userData"),
  Xh = ye.getPath("downloads"),
  Jn = ye.getPath("cache"),
  $o = ye.getAppPath(),
  ru = G.join(process.resourcesPath, "icon.icns"),
  d0 = Object.freeze(
    Object.defineProperty(
      {
        __proto__: null,
        appPath: $o,
        cacheDirPath: Jn,
        downloadsPath: Xh,
        icnsPath: ru,
        userDataDirPath: lt,
      },
      Symbol.toStringTag,
      { value: "Module" },
    ),
  );
class il extends Error {
  constructor(t) {
    super(`${t} is locked`);
  }
}
const qr = { old: new Set(), young: new Set() },
  h0 = 1e3 * 15;
let dn;
const p0 = () => {
    const e = dg.networkInterfaces(),
      t = new Set([void 0, "0.0.0.0"]);
    for (const o of Object.values(e)) for (const i of o) t.add(i.address);
    return t;
  },
  ol = (e) =>
    new Promise((t, o) => {
      const i = fg.createServer();
      (i.unref(),
        i.on("error", o),
        i.listen(e, () => {
          const { port: a } = i.address();
          i.close(() => {
            t(a);
          });
        }));
    }),
  al = async (e, t) => {
    if (e.host || e.port === 0) return ol(e);
    for (const o of t)
      try {
        await ol({ port: e.port, host: o });
      } catch (i) {
        if (!["EADDRNOTAVAIL", "EINVAL"].includes(i.code)) throw i;
      }
    return e.port;
  },
  D0 = function* (e) {
    (e && (yield* e), yield 0);
  };
async function m0(e) {
  let t,
    o = new Set();
  if (
    e &&
    (e.port && (t = typeof e.port == "number" ? [e.port] : e.port), e.exclude)
  ) {
    const a = e.exclude;
    if (typeof a[Symbol.iterator] != "function")
      throw new TypeError("The `exclude` option must be an iterable.");
    for (const n of a) {
      if (typeof n != "number")
        throw new TypeError(
          "Each item in the `exclude` option must be a number corresponding to the port you want excluded.",
        );
      if (!Number.isSafeInteger(n))
        throw new TypeError(
          `Number ${n} in the exclude option is not a safe integer and can't be used`,
        );
    }
    o = new Set(a);
  }
  dn === void 0 &&
    ((dn = setTimeout(() => {
      ((dn = void 0), (qr.old = qr.young), (qr.young = new Set()));
    }, h0)),
    dn.unref && dn.unref());
  const i = p0();
  for (const a of D0(t))
    try {
      if (o.has(a)) continue;
      let n = await al({ ...e, port: a }, i);
      for (; qr.old.has(n) || qr.young.has(n);) {
        if (a !== 0) throw new il(a);
        n = await al({ ...e, port: a }, i);
      }
      return (qr.young.add(n), n);
    } catch (n) {
      if (!["EADDRINUSE", "EACCES"].includes(n.code) && !(n instanceof il))
        throw n;
    }
  throw new Error("No available ports found");
}
function g0(e, t) {
  if (!Number.isInteger(e) || !Number.isInteger(t))
    throw new TypeError("`from` and `to` must be integer numbers");
  return (function* (i, a) {
    for (let n = i; n <= a; n++) yield n;
  })(e, t);
}
const Yh = on.promisify(xt.randomBytes),
  w0 = Oh + 50;
async function y0() {
  const e = ng?.trim(),
    t = !!It.desktop_api_remote_access,
    o = Dg(),
    i = e || (t ? Zu : void 0) || o,
    a = e || o,
    n = e || (t ? mg() : void 0) || i,
    r = Number(ig),
    s = Number.isFinite(r) && r > 0 ? r : g0(Oh, w0),
    u = m0({ port: s, ...(i !== Zu && { host: i }) }),
    f = Yh(16),
    d = await u,
    l = (await f).toString("hex");
  return {
    pasHostname: i,
    pasClientHostname: a,
    pasAdvertisedHostname: n,
    pasPort: d,
    transportNonce: l,
  };
}
const ks = y0();
function Qn(e) {
  (_h("app-relaunched", { reason: e }), ye.relaunch(), ye.quit());
}
const Ms = G.join(lt, "pending-storage-wipe");
function E0() {
  ze.writeFileSync(Ms, String(Date.now()));
}
async function v0() {
  ze.existsSync(Ms) &&
    (logger.log("[storage-wipe] marker found, clearing renderer storage"),
    await fr.defaultSession.clearStorageData(),
    await ze.promises.rm(G.join(lt, "Partitions"), {
      recursive: !0,
      force: !0,
    }),
    await ze.promises.rm(Ms, { force: !0 }),
    fr.defaultSession
      .clearCache()
      .catch((e) => logger.error("[storage-wipe] clearCache failed", e)));
}
async function jo(e) {
  if (
    (logger.error("Module not found after bundle replacement:", e),
    await ye.whenReady(),
    Xe.showMessageBoxSync({
      type: "error",
      message: "Restart required",
      detail: `Some of ${Ve.friendlyProductName}'s core files were changed while it was running. To avoid data loss, please relaunch the app before continuing.`,
      buttons: ["Relaunch", "Quit"],
      defaultId: 0,
      cancelId: 1,
    }) === 1)
  ) {
    ye.quit();
    return;
  }
  (ye.relaunch(), Qr());
}
const C0 = () => Ie("/usr/bin/killall", ["Dock"]);
function A0(e) {
  mainWindow?.sendMessage("deep-link", e);
}
const b0 = async () => {
    if (Ne)
      try {
        const e = `
        ObjC.import('AppKit');
        const ws  = $.NSWorkspace.sharedWorkspace;
        const url = $.NSURL.URLWithString('mailto:');
        const app = ws.URLForApplicationToOpenURL(url);
        app ? app.path.js : '';
      `
            .trim()
            .replace(/\n\s+/g, " "),
          { stdout: t } = await Ie("osascript", ["-l", "JavaScript", "-e", e]);
        return t.trim() || null;
      } catch (e) {
        return (logger.warn("Failed to detect mail client on macOS:", e), null);
      }
    if (Kt) {
      try {
        const { stdout: e } = await Ie("reg", [
            "query",
            "HKCU\\Software\\Clients\\Mail",
            "/ve",
          ]),
          t = /REG_SZ\s+(.*)/.exec(e)?.[1].trim();
        if (t) {
          const { stdout: o } = await Ie("reg", [
              "query",
              `HKCR\\${t}\\shell\\open\\command`,
              "/ve",
            ]),
            i = /REG_SZ\s+(.*)/.exec(o);
          if (i?.[1]) {
            const a = i[1].trim();
            return /^"([^"]+)"/.exec(a)?.[1] || a.split(" ")[0];
          }
        }
      } catch (e) {
        logger.debug?.("Classic mail client registry lookup failed:", e);
      }
      try {
        const { stdout: e } = await Ie("powershell", [
            "-Command",
            'Get-StartApps | Where-Object { $_.Name -like "*Outlook*" -or $_.Name -like "*Mail*" } | Select-Object -First 1 -ExpandProperty AppID',
          ]),
          t = e.trim();
        if (t) return `shell:AppsFolder\\${t}`;
      } catch (e) {
        logger.warn("UWP mail client detection failed:", e);
      }
      return null;
    }
    if (cr)
      try {
        const { stdout: e } = await Ie("xdg-settings", [
          "get",
          "default-url-scheme-handler",
          "mailto",
        ]);
        return e.trim() || null;
      } catch (e) {
        return (logger.warn("Failed to detect mail client on Linux:", e), null);
      }
    return null;
  },
  F0 = `// Inspirations
//
// https://searchcode.com/codesearch/view/847888/
// https://github.com/bitwarden/browser/blob/master/src/services/autofill.service.ts#L136

function __getUsernameField(collection) {
  for (const element of [...collection]) {
    if (!['text', 'email', 'url', 'tel', 'number'].includes(element.type)) continue

    if (element.disabled || element.readOnly) continue

    return element
  }
}

function __getPasswordField(collection) {
  for (const element of [...collection]) {
    if (element.type != 'password') continue

    if (element.disabled || element.readOnly) continue

    return element
  }
}

function __fillField(element, value) {
  if (element.value.length === 0 && value.length > 0) {
    element.focus()
    document.execCommand('insertText', false, value)
    return true
  }
}

let __usernameFilled = false
let __passwordFilled = false

function __runAutofill() {
  const username = '{{USERNAME}}'
  const password = '{{PASSWORD}}'

  if (username.length <= 0) __usernameFilled = true
  if (password.length <= 0) __passwordFilled = true

  if (__usernameFilled && __passwordFilled) return

  const usernameElement = document.querySelector('input[name="{{USERNAME_ELEMENT}}"]')
  const passwordElement = document.querySelector('input[name="{{PASSWORD_ELEMENT}}"]')

  const inputs = document.getElementsByTagName('input')

  const usernameField = __getUsernameField(inputs)
  const passwordField = __getPasswordField(inputs)

  if (!__usernameFilled) {
    if (usernameElement) {
      __usernameFilled = __fillField(usernameElement, username)
    } else if (usernameField) {
      __usernameFilled = __fillField(usernameField, username)
    }
  }

  if (!__passwordFilled) {
    if (passwordElement) {
      __passwordFilled = __fillField(passwordElement, password)
    } else if (passwordField) {
      __passwordFilled = __fillField(passwordField, password)
    }
  }

  setTimeout(__runAutofill, 100)
}

__runAutofill()
`;
async function Kh(e, t) {
  const o = await import("./index-D3oNihqp.mjs").then((i) => i.i);
  return new Promise((i, a) => {
    o.exec(e, t, (n, r, s) => {
      if (n) {
        a(n);
        return;
      }
      i({ stdout: r, stderr: s });
    });
  });
}
async function Jh(e) {
  const { available: t } = await qg.check(e);
  return t;
}
let sl = !1;
const S0 = "__BEEPER_SMOKE_TEST_OK_8f045uk2sdc__";
function _0() {
  sl ||
    ((sl = !0),
    console.log(
      `
`.repeat(5),
    ),
    console.log(S0),
    console.log(
      `
`.repeat(5),
    ));
}
function T0(e, t) {
  const o = Vg(e, t);
  return !!o && !o.startsWith("..") && !zg(o);
}
async function Qh(e, t = Xg(e)) {
  return { name: t, content: await Hg(e, "utf8") };
}
async function ul(...e) {
  try {
    return await Qh(...e);
  } catch (t) {
    return (
      logger.error(
        `tried to read log file ${e[0]} (filename: ${e[1]}), failed:`,
        t,
      ),
      null
    );
  }
}
async function x0() {
  if (!Ne) return [];
  const { cacheDirPath: e } = await Promise.resolve().then(() => d0),
    t = Gn(e, `${dr}.ShipIt`);
  return await Promise.all(
    [
      await ul(Gn(t, "ShipIt_stderr.log")),
      await ul(Gn(t, "ShipItState.plist"), "ShipItState.json.log"),
    ].filter((o) => o != null),
  );
}
async function N0(e) {
  const t = Gg(e);
  if (!T0(Gn(bg(), "dumps"), t))
    throw new Error("provided snapshot path was outside of user data dir");
  const i = (await Wg(e, { withFileTypes: !0 }))
    .filter((a) => a.isFile() && a.name.endsWith(".log"))
    .map((a) => Qh(Gn(e, a.name), a.name));
  return await Promise.all(i);
}
function I0() {
  if (
    Pr ||
    !Ne ||
    og ||
    It.no_enforce_app_location ||
    ye.isInApplicationsFolder()
  )
    return;
  const e = G.join(process.argv0, "../../.."),
    t = G.basename(e),
    o = G.join("/Applications", t),
    i = ze.statSync(o, { throwIfNoEntry: !1 });
  if (i?.isDirectory() || i?.isFile()) {
    if (
      Xe.showMessageBoxSync({
        type: "error",
        message: "Move to Applications folder?",
        detail: `${tt.APP_NAME} must live in the Applications folder to be able to run correctly.`,
        buttons: ["Move to Applications folder", `Quit ${tt.APP_NAME}`],
        defaultId: 0,
        cancelId: 1,
      }) === 1
    ) {
      ye.quit();
      return;
    }
    try {
      ze.rmSync(o, { recursive: !0 });
    } catch (r) {
      (logger.error(r), Sentry.captureException(r));
    }
  } else logger.log("Moving app to Applications folder");
  ye.moveToApplicationsFolder({
    conflictHandler: (n) => {
      if (n === "existsAndRunning") {
        const r = `Another version of ${tt.APP_NAME} is currently running. Quit it, then launch this version of the app again.`;
        (kt("app-location-macos", r),
          Xe.showMessageBoxSync({ type: "error", message: r, buttons: ["OK"] }),
          ye.quit());
      }
      return !0;
    },
  });
}
const Us = 3600 * 1e3,
  O0 = 6 * Us,
  ea = Kg.map((e) => ({
    ms: e,
    label: e >= Us ? `${e / Us}h` : `${e / 6e4}m`,
  })),
  P0 = {
    physicalMemoryGB: Math.round(Ke.totalmem() / 1024 / 1024 / 1024),
    cpuModel: Ke.cpus()[0]?.model ?? "Unknown",
    cpuCores: Ke.cpus().length,
    cpuArchitecture: Ke.arch(),
    osVersion: Ke.version(),
  };
function ll(e, t) {
  const o = ye.getAppMetrics(),
    i = o.map((a) => ({
      event: "System Resource Usage",
      properties: {
        ...P0,
        uptimeHours: Math.round((process.uptime() / 3600) * 10) / 10,
        processCount: o.length,
        processType: a.type,
        cpuPercentage: a.cpu.percentCPUUsage,
        workingSetSizeKB: a.memory.workingSetSize,
        peakWorkingSetSizeKB: a.memory.peakWorkingSetSize,
        interval: t,
      },
    }));
  e.sendMessage("system-resource-metrics", i);
}
function R0(e) {
  const { percentCPUUsage: t, idleWakeupsPerSecond: o } = process.getCPUUsage();
  t !== 0 &&
    e.sendMessage("system-resource-metrics", [
      {
        event: "Main Performance",
        properties: {
          uptimeMinutes: ~~(process.uptime() / 60),
          arch: process.arch,
          idleWakeupsPerSecond: o,
          percentCPUUsage: t,
        },
      },
    ]);
}
let cl = !1;
function L0(e) {
  if (cl) return;
  ((cl = !0), ye.getAppMetrics());
  const t = ea[ea.length - 1];
  for (const { ms: o, label: i } of ea)
    setTimeout(() => {
      (ll(e, i), o === t.ms && setInterval(() => ll(e, "6h-recurring"), O0));
    }, o);
  setInterval(() => R0(e), 300 * 1e3);
}
const B0 = 300;
function k0(e, t) {
  let o = st.getSystemIdleState(t);
  logger.info(
    `[PowerMonitor] Starting idle monitor with threshold: ${t}s, initial state: ${o}`,
  );
  const i = setInterval(() => {
    const a = st.getSystemIdleState(t);
    a !== o &&
      (logger.info(`[PowerMonitor] Idle state changed from ${o} to ${a}`),
      e?.rs.powerMonitorIdleStateChange(a),
      (o = a));
  }, 6e4);
  return () => {
    (logger.info("[PowerMonitor] Stopping idle monitor"), clearInterval(i));
  };
}
function M0(e) {
  (ut("[PowerMonitor] Registering power events"),
    st.on("resume", () => {
      (logger.info("[PowerMonitor] System resumed from suspend"),
        e?.sendMessage("powermonitor-on-resume"),
        bm("powermonitor-on-resume"));
    }),
    st.on("suspend", () => {
      (logger.info("[PowerMonitor] System suspending"),
        e?.sendMessage("powermonitor-on-suspend"));
    }),
    st.addListener("lock-screen", () => {
      (logger.info("[PowerMonitor] Screen locked"),
        e?.sendMessage("powermonitor-lock-screen"));
    }),
    st.addListener("unlock-screen", () => {
      (logger.info("[PowerMonitor] Screen unlocked"),
        e?.sendMessage("powermonitor-unlock-screen"));
    }),
    st.on("on-ac", () => {
      logger.info("[PowerMonitor] Changed to AC power");
    }),
    st.on("on-battery", () => {
      logger.info("[PowerMonitor] Changed to battery power");
    }),
    st.on("shutdown", () => {
      logger.info("[PowerMonitor] System shutting down");
    }),
    st.on("speed-limit-change", () => {
      logger.info("[PowerMonitor] Speed limit change detected");
    }),
    st.on("thermal-state-change", () => {
      logger.info(
        `[PowerMonitor] Thermal state changed to: ${st.getCurrentThermalState()}`,
      );
    }),
    st.on("user-did-become-active", () => {
      logger.info("[PowerMonitor] User became active");
    }),
    st.on("user-did-resign-active", () => {
      logger.info("[PowerMonitor] User resigned active");
    }));
  const t = +(It.idle_timeout ?? B0);
  t > 0
    ? (logger.info(
        `[PowerMonitor] Idle monitoring enabled with threshold: ${t}s`,
      ),
      k0(e, t))
    : logger.info("[PowerMonitor] Idle monitoring disabled");
}
var U0 = Tm();
const fl = pr(U0);
var ta, dl;
function q0() {
  if (dl) return ta;
  dl = 1;
  var e = Object.prototype,
    t = e.hasOwnProperty;
  function o(i, a) {
    return i != null && t.call(i, a);
  }
  return ((ta = o), ta);
}
var ra, hl;
function $0() {
  if (hl) return ra;
  hl = 1;
  var e = q0(),
    t = xm();
  function o(i, a) {
    return i != null && t(i, a, e);
  }
  return ((ra = o), ra);
}
var j0 = $0();
const W0 = pr(j0);
var na, pl;
function H0() {
  if (pl) return na;
  pl = 1;
  var e = Nm();
  function t(o, i) {
    return o == null ? !0 : e(o, i);
  }
  return ((na = t), na);
}
var G0 = H0();
const V0 = pr(G0);
var Tt = {},
  ke = {},
  Dl;
function oi() {
  if (Dl) return ke;
  ((Dl = 1),
    Object.defineProperty(ke, "__esModule", { value: !0 }),
    (ke.NOOP =
      ke.LIMIT_FILES_DESCRIPTORS =
      ke.LIMIT_BASENAME_LENGTH =
      ke.IS_USER_ROOT =
      ke.IS_POSIX =
      ke.DEFAULT_TIMEOUT_SYNC =
      ke.DEFAULT_TIMEOUT_ASYNC =
      ke.DEFAULT_WRITE_OPTIONS =
      ke.DEFAULT_READ_OPTIONS =
      ke.DEFAULT_FOLDER_MODE =
      ke.DEFAULT_FILE_MODE =
      ke.DEFAULT_ENCODING =
        void 0));
  const e = "utf8";
  ke.DEFAULT_ENCODING = e;
  const t = 438;
  ke.DEFAULT_FILE_MODE = t;
  const o = 511;
  ke.DEFAULT_FOLDER_MODE = o;
  const i = {};
  ke.DEFAULT_READ_OPTIONS = i;
  const a = {};
  ke.DEFAULT_WRITE_OPTIONS = a;
  const n = 5e3;
  ke.DEFAULT_TIMEOUT_ASYNC = n;
  const r = 100;
  ke.DEFAULT_TIMEOUT_SYNC = r;
  const s = !!process.getuid;
  ke.IS_POSIX = s;
  const u = process.getuid ? !process.getuid() : !1;
  ke.IS_USER_ROOT = u;
  const f = 128;
  ke.LIMIT_BASENAME_LENGTH = f;
  const d = 1e4;
  ke.LIMIT_FILES_DESCRIPTORS = d;
  const c = () => {};
  return ((ke.NOOP = c), ke);
}
var mi = {},
  Er = {},
  ml;
function z0() {
  if (ml) return Er;
  ((ml = 1),
    Object.defineProperty(Er, "__esModule", { value: !0 }),
    (Er.attemptifySync = Er.attemptifyAsync = void 0));
  const e = oi(),
    t = (i, a = e.NOOP) =>
      function () {
        return i.apply(void 0, arguments).catch(a);
      };
  Er.attemptifyAsync = t;
  const o = (i, a = e.NOOP) =>
    function () {
      try {
        return i.apply(void 0, arguments);
      } catch (n) {
        return a(n);
      }
    };
  return ((Er.attemptifySync = o), Er);
}
var gi = {},
  gl;
function X0() {
  if (gl) return gi;
  ((gl = 1), Object.defineProperty(gi, "__esModule", { value: !0 }));
  const e = oi(),
    t = {
      isChangeErrorOk: (o) => {
        const { code: i } = o;
        return (
          i === "ENOSYS" ||
          (!e.IS_USER_ROOT && (i === "EINVAL" || i === "EPERM"))
        );
      },
      isRetriableError: (o) => {
        const { code: i } = o;
        return (
          i === "EMFILE" ||
          i === "ENFILE" ||
          i === "EAGAIN" ||
          i === "EBUSY" ||
          i === "EACCESS" ||
          i === "EACCS" ||
          i === "EPERM"
        );
      },
      onChangeError: (o) => {
        if (!t.isChangeErrorOk(o)) throw o;
      },
    };
  return ((gi.default = t), gi);
}
var vr = {},
  wi = {},
  wl;
function Y0() {
  if (wl) return wi;
  ((wl = 1), Object.defineProperty(wi, "__esModule", { value: !0 }));
  const t = {
    interval: 25,
    intervalId: void 0,
    limit: oi().LIMIT_FILES_DESCRIPTORS,
    queueActive: new Set(),
    queueWaiting: new Set(),
    init: () => {
      t.intervalId || (t.intervalId = setInterval(t.tick, t.interval));
    },
    reset: () => {
      t.intervalId && (clearInterval(t.intervalId), delete t.intervalId);
    },
    add: (o) => {
      (t.queueWaiting.add(o),
        t.queueActive.size < t.limit / 2 ? t.tick() : t.init());
    },
    remove: (o) => {
      (t.queueWaiting.delete(o), t.queueActive.delete(o));
    },
    schedule: () =>
      new Promise((o) => {
        const i = () => t.remove(a),
          a = () => o(i);
        t.add(a);
      }),
    tick: () => {
      if (!(t.queueActive.size >= t.limit)) {
        if (!t.queueWaiting.size) return t.reset();
        for (const o of t.queueWaiting) {
          if (t.queueActive.size >= t.limit) break;
          (t.queueWaiting.delete(o), t.queueActive.add(o), o());
        }
      }
    },
  };
  return ((wi.default = t), wi);
}
var yl;
function K0() {
  if (yl) return vr;
  ((yl = 1),
    Object.defineProperty(vr, "__esModule", { value: !0 }),
    (vr.retryifySync = vr.retryifyAsync = void 0));
  const e = Y0(),
    t = (i, a) =>
      function (n) {
        return function r() {
          return e.default.schedule().then((s) =>
            i.apply(void 0, arguments).then(
              (u) => (s(), u),
              (u) => {
                if ((s(), Date.now() >= n)) throw u;
                if (a(u)) {
                  const f = Math.round(100 + 400 * Math.random());
                  return new Promise((c) => setTimeout(c, f)).then(() =>
                    r.apply(void 0, arguments),
                  );
                }
                throw u;
              },
            ),
          );
        };
      };
  vr.retryifyAsync = t;
  const o = (i, a) =>
    function (n) {
      return function r() {
        try {
          return i.apply(void 0, arguments);
        } catch (s) {
          if (Date.now() > n) throw s;
          if (a(s)) return r.apply(void 0, arguments);
          throw s;
        }
      };
    };
  return ((vr.retryifySync = o), vr);
}
var El;
function Zh() {
  if (El) return mi;
  ((El = 1), Object.defineProperty(mi, "__esModule", { value: !0 }));
  const e = ze,
    t = on,
    o = z0(),
    i = X0(),
    a = K0(),
    n = {
      chmodAttempt: o.attemptifyAsync(
        t.promisify(e.chmod),
        i.default.onChangeError,
      ),
      chownAttempt: o.attemptifyAsync(
        t.promisify(e.chown),
        i.default.onChangeError,
      ),
      closeAttempt: o.attemptifyAsync(t.promisify(e.close)),
      fsyncAttempt: o.attemptifyAsync(t.promisify(e.fsync)),
      mkdirAttempt: o.attemptifyAsync(t.promisify(e.mkdir)),
      realpathAttempt: o.attemptifyAsync(t.promisify(e.realpath)),
      statAttempt: o.attemptifyAsync(t.promisify(e.stat)),
      unlinkAttempt: o.attemptifyAsync(t.promisify(e.unlink)),
      closeRetry: a.retryifyAsync(
        t.promisify(e.close),
        i.default.isRetriableError,
      ),
      fsyncRetry: a.retryifyAsync(
        t.promisify(e.fsync),
        i.default.isRetriableError,
      ),
      openRetry: a.retryifyAsync(
        t.promisify(e.open),
        i.default.isRetriableError,
      ),
      readFileRetry: a.retryifyAsync(
        t.promisify(e.readFile),
        i.default.isRetriableError,
      ),
      renameRetry: a.retryifyAsync(
        t.promisify(e.rename),
        i.default.isRetriableError,
      ),
      statRetry: a.retryifyAsync(
        t.promisify(e.stat),
        i.default.isRetriableError,
      ),
      writeRetry: a.retryifyAsync(
        t.promisify(e.write),
        i.default.isRetriableError,
      ),
      chmodSyncAttempt: o.attemptifySync(e.chmodSync, i.default.onChangeError),
      chownSyncAttempt: o.attemptifySync(e.chownSync, i.default.onChangeError),
      closeSyncAttempt: o.attemptifySync(e.closeSync),
      mkdirSyncAttempt: o.attemptifySync(e.mkdirSync),
      realpathSyncAttempt: o.attemptifySync(e.realpathSync),
      statSyncAttempt: o.attemptifySync(e.statSync),
      unlinkSyncAttempt: o.attemptifySync(e.unlinkSync),
      closeSyncRetry: a.retryifySync(e.closeSync, i.default.isRetriableError),
      fsyncSyncRetry: a.retryifySync(e.fsyncSync, i.default.isRetriableError),
      openSyncRetry: a.retryifySync(e.openSync, i.default.isRetriableError),
      readFileSyncRetry: a.retryifySync(
        e.readFileSync,
        i.default.isRetriableError,
      ),
      renameSyncRetry: a.retryifySync(e.renameSync, i.default.isRetriableError),
      statSyncRetry: a.retryifySync(e.statSync, i.default.isRetriableError),
      writeSyncRetry: a.retryifySync(e.writeSync, i.default.isRetriableError),
    };
  return ((mi.default = n), mi);
}
var yi = {},
  vl;
function J0() {
  if (vl) return yi;
  ((vl = 1), Object.defineProperty(yi, "__esModule", { value: !0 }));
  const e = {
    isFunction: (t) => typeof t == "function",
    isString: (t) => typeof t == "string",
    isUndefined: (t) => typeof t > "u",
  };
  return ((yi.default = e), yi);
}
var Ei = {},
  Cl;
function Q0() {
  if (Cl) return Ei;
  ((Cl = 1), Object.defineProperty(Ei, "__esModule", { value: !0 }));
  const e = {},
    t = {
      next: (o) => {
        const i = e[o];
        if (!i) return;
        i.shift();
        const a = i[0];
        a ? a(() => t.next(o)) : delete e[o];
      },
      schedule: (o) =>
        new Promise((i) => {
          let a = e[o];
          (a || (a = e[o] = []),
            a.push(i),
            !(a.length > 1) && i(() => t.next(o)));
        }),
    };
  return ((Ei.default = t), Ei);
}
var vi = {},
  Al;
function Z0() {
  if (Al) return vi;
  ((Al = 1), Object.defineProperty(vi, "__esModule", { value: !0 }));
  const e = G,
    t = oi(),
    o = Zh(),
    i = {
      store: {},
      create: (a) => {
        const n =
            `000000${Math.floor(Math.random() * 16777215).toString(16)}`.slice(
              -6,
            ),
          r = Date.now().toString().slice(-10),
          s = "tmp-",
          u = `.${s}${r}${n}`;
        return `${a}${u}`;
      },
      get: (a, n, r = !0) => {
        const s = i.truncate(n(a));
        return s in i.store
          ? i.get(a, n, r)
          : ((i.store[s] = r), [s, () => delete i.store[s]]);
      },
      purge: (a) => {
        i.store[a] && (delete i.store[a], o.default.unlinkAttempt(a));
      },
      purgeSync: (a) => {
        i.store[a] && (delete i.store[a], o.default.unlinkSyncAttempt(a));
      },
      purgeSyncAll: () => {
        for (const a in i.store) i.purgeSync(a);
      },
      truncate: (a) => {
        const n = e.basename(a);
        if (n.length <= t.LIMIT_BASENAME_LENGTH) return a;
        const r = /^(\.?)(.*?)((?:\.[^.]+)?(?:\.tmp-\d{10}[a-f0-9]{6})?)$/.exec(
          n,
        );
        if (!r) return a;
        const s = n.length - t.LIMIT_BASENAME_LENGTH;
        return `${a.slice(0, -n.length)}${r[1]}${r[2].slice(0, -s)}${r[3]}`;
      },
    };
  return (process.on("exit", i.purgeSyncAll), (vi.default = i), vi);
}
var bl;
function ew() {
  if (bl) return Tt;
  ((bl = 1),
    Object.defineProperty(Tt, "__esModule", { value: !0 }),
    (Tt.writeFileSync = Tt.writeFile = Tt.readFileSync = Tt.readFile = void 0));
  const e = G,
    t = oi(),
    o = Zh(),
    i = J0(),
    a = Q0(),
    n = Z0();
  function r(c, l = t.DEFAULT_READ_OPTIONS) {
    var h;
    if (i.default.isString(l)) return r(c, { encoding: l });
    const y =
      Date.now() +
      ((h = l.timeout) !== null && h !== void 0 ? h : t.DEFAULT_TIMEOUT_ASYNC);
    return o.default.readFileRetry(y)(c, l);
  }
  Tt.readFile = r;
  function s(c, l = t.DEFAULT_READ_OPTIONS) {
    var h;
    if (i.default.isString(l)) return s(c, { encoding: l });
    const y =
      Date.now() +
      ((h = l.timeout) !== null && h !== void 0 ? h : t.DEFAULT_TIMEOUT_SYNC);
    return o.default.readFileSyncRetry(y)(c, l);
  }
  Tt.readFileSync = s;
  const u = (c, l, h, y) => {
    if (i.default.isFunction(h)) return u(c, l, t.DEFAULT_WRITE_OPTIONS, h);
    const F = f(c, l, h);
    return (y && F.then(y, y), F);
  };
  Tt.writeFile = u;
  const f = async (c, l, h = t.DEFAULT_WRITE_OPTIONS) => {
      var y;
      if (i.default.isString(h)) return f(c, l, { encoding: h });
      const F =
        Date.now() +
        ((y = h.timeout) !== null && y !== void 0
          ? y
          : t.DEFAULT_TIMEOUT_ASYNC);
      let m = null,
        S = null,
        E = null,
        b = null,
        w = null;
      try {
        (h.schedule && (m = await h.schedule(c)),
          (S = await a.default.schedule(c)),
          (c = (await o.default.realpathAttempt(c)) || c),
          ([b, E] = n.default.get(
            c,
            h.tmpCreate || n.default.create,
            h.tmpPurge !== !1,
          )));
        const A = t.IS_POSIX && i.default.isUndefined(h.chown),
          v = i.default.isUndefined(h.mode);
        if (A || v) {
          const g = await o.default.statAttempt(c);
          g &&
            ((h = { ...h }),
            A && (h.chown = { uid: g.uid, gid: g.gid }),
            v && (h.mode = g.mode));
        }
        const C = e.dirname(c);
        (await o.default.mkdirAttempt(C, {
          mode: t.DEFAULT_FOLDER_MODE,
          recursive: !0,
        }),
          (w = await o.default.openRetry(F)(
            b,
            "w",
            h.mode || t.DEFAULT_FILE_MODE,
          )),
          h.tmpCreated && h.tmpCreated(b),
          i.default.isString(l)
            ? await o.default.writeRetry(F)(
                w,
                l,
                0,
                h.encoding || t.DEFAULT_ENCODING,
              )
            : i.default.isUndefined(l) ||
              (await o.default.writeRetry(F)(w, l, 0, l.length, 0)),
          h.fsync !== !1 &&
            (h.fsyncWait !== !1
              ? await o.default.fsyncRetry(F)(w)
              : o.default.fsyncAttempt(w)),
          await o.default.closeRetry(F)(w),
          (w = null),
          h.chown &&
            (await o.default.chownAttempt(b, h.chown.uid, h.chown.gid)),
          h.mode && (await o.default.chmodAttempt(b, h.mode)));
        try {
          await o.default.renameRetry(F)(b, c);
        } catch (g) {
          if (g.code !== "ENAMETOOLONG") throw g;
          await o.default.renameRetry(F)(b, n.default.truncate(c));
        }
        (E(), (b = null));
      } finally {
        (w && (await o.default.closeAttempt(w)),
          b && n.default.purge(b),
          m && m(),
          S && S());
      }
    },
    d = (c, l, h = t.DEFAULT_WRITE_OPTIONS) => {
      var y;
      if (i.default.isString(h)) return d(c, l, { encoding: h });
      const F =
        Date.now() +
        ((y = h.timeout) !== null && y !== void 0 ? y : t.DEFAULT_TIMEOUT_SYNC);
      let m = null,
        S = null,
        E = null;
      try {
        ((c = o.default.realpathSyncAttempt(c) || c),
          ([S, m] = n.default.get(
            c,
            h.tmpCreate || n.default.create,
            h.tmpPurge !== !1,
          )));
        const b = t.IS_POSIX && i.default.isUndefined(h.chown),
          w = i.default.isUndefined(h.mode);
        if (b || w) {
          const v = o.default.statSyncAttempt(c);
          v &&
            ((h = { ...h }),
            b && (h.chown = { uid: v.uid, gid: v.gid }),
            w && (h.mode = v.mode));
        }
        const A = e.dirname(c);
        (o.default.mkdirSyncAttempt(A, {
          mode: t.DEFAULT_FOLDER_MODE,
          recursive: !0,
        }),
          (E = o.default.openSyncRetry(F)(
            S,
            "w",
            h.mode || t.DEFAULT_FILE_MODE,
          )),
          h.tmpCreated && h.tmpCreated(S),
          i.default.isString(l)
            ? o.default.writeSyncRetry(F)(
                E,
                l,
                0,
                h.encoding || t.DEFAULT_ENCODING,
              )
            : i.default.isUndefined(l) ||
              o.default.writeSyncRetry(F)(E, l, 0, l.length, 0),
          h.fsync !== !1 &&
            (h.fsyncWait !== !1
              ? o.default.fsyncSyncRetry(F)(E)
              : o.default.fsyncAttempt(E)),
          o.default.closeSyncRetry(F)(E),
          (E = null),
          h.chown && o.default.chownSyncAttempt(S, h.chown.uid, h.chown.gid),
          h.mode && o.default.chmodSyncAttempt(S, h.mode));
        try {
          o.default.renameSyncRetry(F)(S, c);
        } catch (v) {
          if (v.code !== "ENAMETOOLONG") throw v;
          o.default.renameSyncRetry(F)(S, n.default.truncate(c));
        }
        (m(), (S = null));
      } finally {
        (E && o.default.closeSyncAttempt(E), S && n.default.purge(S));
      }
    };
  return ((Tt.writeFileSync = d), Tt);
}
var tw = ew();
const hn = () => Object.create(null),
  ia = "aes-256-cbc",
  rw = (e, t) => {
    const o = ["undefined", "symbol", "function"],
      i = typeof t;
    if (o.includes(i))
      throw new TypeError(
        `Setting a value of type \`${i}\` for key \`${e}\` is not allowed as it's not supported by JSON`,
      );
  },
  nw = process.env.SNAP,
  oa = "__internal__",
  iw = (e) => {
    const t = typeof e;
    return e !== null && (t === "object" || t === "function");
  };
function Fl(e, t, o) {
  const i = e,
    a = t.split(".");
  for (let n = 0; n < a.length; n++) {
    const r = a[n];
    (iw(e[r]) || (e[r] = {}), n === a.length - 1 && (e[r] = o), (e = e[r]));
  }
  return i;
}
class nu {
  constructor(t) {
    ((this._options = {}), (this._defaultValues = {}));
    const o = {
      configName: "config",
      fileExtension: "json",
      projectSuffix: "nodejs",
      clearInvalidConfig: !0,
      serialize: (r) => {
        try {
          return JSON.stringify(r);
        } catch (s) {
          throw (Pr && (logger.error(r.length), logger.error(r, s)), s);
        }
      },
      deserialize: JSON.parse,
      accessPropertiesByDotNotation: !0,
      ...t,
    };
    if (!o.cwd) throw new Error("Specify the `cwd` option.");
    ((this._options = o),
      o.defaults &&
        (this._defaultValues = { ...this._defaultValues, ...o.defaults }),
      (this.encryptionKey = o.encryptionKey),
      (this.serialize = o.serialize),
      (this.deserialize = o.deserialize));
    const i = o.fileExtension ? `.${o.fileExtension}` : "";
    ((this.path = G.resolve(o.cwd, `${o.configName}${i}`)),
      (this.store = this.getInitialStore()));
    const a = this.store,
      n = Object.assign(hn(), o.defaults, a);
    Im(a, n) || this.setStore(n);
  }
  _ensureDirectory() {
    return Te.mkdir(G.dirname(this.path), { recursive: !0 });
  }
  async _write(t) {
    let o = this.serialize(t);
    if (this.encryptionKey) {
      const i = await Yh(16),
        a = xt.pbkdf2Sync(this.encryptionKey, i.toString(), 1e4, 32, "sha512"),
        n = xt.createCipheriv(ia, a, i);
      o = Buffer.concat([
        i,
        Buffer.from(":"),
        n.update(Buffer.from(o)),
        n.final(),
      ]);
    }
    if (nw) await Te.writeFile(this.path, o);
    else
      try {
        await tw.writeFile(this.path, o);
      } catch (i) {
        if (i.code === "EXDEV") {
          await Te.writeFile(this.path, o);
          return;
        }
        if (["ENOENT", "ECANCELED"].includes(i.code)) return;
        throw i;
      }
  }
  _containsReservedKey(t) {
    return typeof t == "object" && Object.keys(t)[0] === oa
      ? !0
      : typeof t != "string"
        ? !1
        : this._options.accessPropertiesByDotNotation
          ? !!t.startsWith(`${oa}.`)
          : !1;
  }
  _get(t, o) {
    return fl(this.store, t, o);
  }
  _set(t, o) {
    const { store: i } = this;
    (Fl(i, t, o), this.setStore(i));
  }
  get(t, o) {
    return this._options.accessPropertiesByDotNotation
      ? fl(this.store, t, o)
      : t in this.store
        ? this.store[t]
        : o;
  }
  set(t, o) {
    if (typeof t != "string" && typeof t != "object")
      throw new TypeError(
        `Expected \`key\` to be of type \`string\` or \`object\`, got ${typeof t}`,
      );
    if (typeof t != "object" && o === void 0)
      throw new TypeError("Use `delete()` to clear values");
    if (this._containsReservedKey(t))
      throw new TypeError(
        `Please don't use the ${oa} key, as it's used to manage this module internal operations.`,
      );
    const { store: i } = this,
      a = (n, r) => {
        (rw(n, r),
          this._options.accessPropertiesByDotNotation
            ? Fl(i, n, r)
            : (i[n] = r));
      };
    if (typeof t == "object") {
      const n = t;
      for (const [r, s] of Object.entries(n)) a(r, s);
    } else a(t, o);
    this.setStore(i);
  }
  has(t) {
    return this._options.accessPropertiesByDotNotation
      ? W0(this.store, t)
      : t in this.store;
  }
  reset(...t) {
    for (const o of t)
      this._defaultValues[o] && this.set(o, this._defaultValues[o]);
  }
  delete(t) {
    const { store: o } = this;
    (this._options.accessPropertiesByDotNotation ? V0(o, t) : delete o[t],
      this.setStore(o));
  }
  clear() {
    this.setStore(hn());
  }
  get size() {
    return Object.keys(this.store).length;
  }
  getInitialStore() {
    try {
      let t = Eg(this.path, this.encryptionKey ? null : "utf8");
      if (this.encryptionKey) {
        let o = t;
        try {
          if (o.subarray(16, 17).toString() === ":") {
            const i = o.subarray(0, 16),
              a = xt.pbkdf2Sync(
                this.encryptionKey,
                i.toString(),
                1e4,
                32,
                "sha512",
              ),
              n = xt.createDecipheriv(ia, a, i);
            o = Buffer.concat([n.update(o.subarray(17)), n.final()]);
          } else {
            const i = xt.createDecipheriv(
              ia,
              this.encryptionKey,
              Buffer.alloc(0),
            );
            o = Buffer.concat([i.update(o), i.final()]);
          }
          t = o;
        } catch (i) {
          throw (
            logger.error("error decrypting FastConf store at", this.path, i),
            i
          );
        }
      }
      return ((t = this.deserialize(t)), Object.assign(hn(), t));
    } catch (t) {
      if (t.code === "ENOENT") return (this._ensureDirectory(), hn());
      if (this._options.clearInvalidConfig && t.name === "SyntaxError")
        return hn();
      throw t;
    }
  }
  async setStore(t) {
    ((this.store = t), await this._ensureDirectory(), await this._write(t));
  }
  *[Symbol.iterator]() {
    for (const [t, o] of Object.entries(this.store)) yield [t, o];
  }
}
const Ro = { x: void 0, y: void 0, width: Sg, height: Fg },
  Ci = 50,
  ow = (e, t) =>
    e.x === void 0 ||
    e.y === void 0 ||
    e.width === void 0 ||
    e.height === void 0
      ? !1
      : e.x >= t.x - Ci &&
        e.y >= t.y - Ci &&
        e.x + e.width <= t.x + t.width + Ci &&
        e.y + e.height <= t.y + t.height + Ci,
  aw = (e) => ur.getAllDisplays().some((t) => ow(e, t.workArea)),
  sw = (e, t) =>
    !e || !t
      ? !1
      : e.x === t.x &&
        e.y === t.y &&
        e.width === t.width &&
        e.height === t.height,
  uw = (e) => ({ x: e.x ?? 0, y: e.y ?? 0, width: e.width, height: e.height }),
  lw = (e) => {
    const o = ur.getAllDisplays().find((i) => sw(i.bounds, e.displayBounds));
    return (
      o ||
      (e.x != null && e.y != null
        ? ur.getDisplayMatching(uw(e))
        : ur.getPrimaryDisplay())
    );
  },
  Sl = (e, t) => {
    const o = t.workArea,
      i = Math.max(1, Math.round(o.width)),
      a = Math.max(1, Math.round(o.height)),
      n =
        Number.isFinite(e.width) && e.width > 0
          ? Math.round(e.width)
          : Ro.width,
      r =
        Number.isFinite(e.height) && e.height > 0
          ? Math.round(e.height)
          : Ro.height,
      s = Math.max(1, Math.min(n, i)),
      u = Math.max(1, Math.min(r, a)),
      f =
        e.x == null
          ? o.x + Math.round((o.width - s) / 2)
          : Math.max(o.x, Math.min(o.x + o.width - s, e.x)),
      d =
        e.y == null
          ? o.y + Math.round((o.height - u) / 2)
          : Math.max(o.y, Math.min(o.y + o.height - u, e.y));
    return { ...e, x: f, y: d, width: s, height: u, displayBounds: t.bounds };
  };
function ep(e) {
  const t = new nu({ configName: "window", cwd: lt });
  let o;
  const i = t.has(`windowState.${e}`);
  let a = i ? t.get(`windowState.${e}`) : Ro;
  (logger.log(
    `[windowStateKeeper] ${e} ${i ? "initialized with saved store" : "initialized with default store"}. Loaded window state:`,
    a,
  ),
    i &&
      !aw(a) &&
      ((a = Sl(a, lw(a))),
      logger.log(
        `[windowStateKeeper] ${e} Clamped saved window state to visible work area. State:`,
        a,
      )));
  const n = Om(() => {
      (logger.log(`[windowStateKeeper] ${e} Saving state:`, a),
        t.set(`windowState.${e}`, a));
    }, 1e3),
    r = () => {
      const c = o.isMinimized(),
        l = o.isMaximized(),
        h = o.isFullScreen(),
        y = c || l || h ? o.getNormalBounds() : o.getBounds(),
        F = ur.getDisplayMatching(y);
      return Sl(
        {
          ...y,
          isMinimized: c,
          isMaximized: l,
          isFullScreen: h,
          isVisible: o.isVisible(),
        },
        F,
      );
    };
  function s() {
    ((a = r()), n());
  }
  function u(c, l = !0, h) {
    (l &&
      (h?.sizeOnly || a.x == null || a.y == null
        ? c.setContentSize(a.width, a.height)
        : c.setBounds({ width: a.width, height: a.height, x: a.x, y: a.y }),
      h?.deferMaximize || d()),
      (o = c),
      [
        "resize",
        "move",
        "close",
        "hide",
        "maximize",
        "unmaximize",
        "minimize",
        "enter-full-screen",
        "leave-full-screen",
      ].forEach((y) => {
        o.on(y, s);
      }));
  }
  function f() {
    (t.delete(`windowState.${e}`),
      (a = { ...Ro }),
      logger.log(`[windowStateKeeper] ${e} store reset`));
  }
  function d() {
    o && (a.isMaximized && o.maximize(), a.isFullScreen && o.setFullScreen(!0));
  }
  return {
    ...a,
    manage: u,
    getState: r,
    reset: f,
    hasSavedState: i,
    applyMaximizeState: d,
  };
}
const Bt = yt ? globalThis.ipcMainShim : wm;
let aa;
const cw = (e) => {
    const t = new Set();
    let o = !1;
    for (const i of e.split(`
`)) {
      if (!o) {
        /^\s*-+\s*$/.test(i) && (o = !0);
        continue;
      }
      const a = i.trim().split(/\s+/)[1];
      a && t.add(a);
    }
    return t;
  },
  fw = () => (
    (aa ??= Ie(kh.ffmpegBinaryPath, ["-hide_banner", "-decoders"])
      .then(({ stdout: e }) => cw(e))
      .catch(
        (e) => (
          logger.warn(
            `getDecodableCodecs: could not read decoders from ffmpeg: ${e instanceof Error ? e.message : String(e)}`,
          ),
          (aa = void 0),
          new Set()
        ),
      )),
    aa
  );
async function dw(e) {
  const t = await fw();
  if (t.size === 0) return { canDecode: !0 };
  let o;
  try {
    ({ stdout: o } = await Ie(kh.ffprobeBinaryPath, [
      "-v",
      "error",
      "-show_entries",
      "stream=codec_name,codec_type",
      "-of",
      "json",
      e,
    ]));
  } catch (r) {
    return (
      logger.warn(
        `canDecodeMedia: ffprobe could not read ${e}: ${r instanceof Error ? r.message : String(r)}`,
      ),
      { canDecode: !1 }
    );
  }
  let i;
  try {
    i = JSON.parse(o).streams ?? [];
  } catch {
    return { canDecode: !0 };
  }
  const a = i.filter(
    (r) => r.codec_type === "video" || r.codec_type === "audio",
  );
  if (a.length === 0) return { canDecode: !0 };
  const n = a.find((r) => r.codec_name && !t.has(r.codec_name));
  return n
    ? { canDecode: !1, undecodableCodec: n.codec_name }
    : { canDecode: !0 };
}
const _l = async (e, t, o) => {
    const { stdout: i } = await Ie("/usr/bin/sips", [
        "-g",
        "pixelWidth",
        "-g",
        "pixelHeight",
        e,
      ]),
      a = parseInt(/pixelWidth:\s+(\d+)/.exec(i)?.[1] ?? "0", 10),
      n = parseInt(/pixelHeight:\s+(\d+)/.exec(i)?.[1] ?? "0", 10);
    let r = e;
    if (a !== n) {
      const s = Math.min(a, n),
        u = t.replace(/\.png$/, ".cropped.png");
      (await Ie("/usr/bin/sips", [
        "--cropToHeightWidth",
        String(s),
        String(s),
        e,
        "--out",
        u,
      ]),
        (r = u));
    }
    await Ie("/usr/bin/sips", [
      "-s",
      "format",
      "png",
      "--resampleWidth",
      o,
      r,
      "--out",
      t,
    ]);
  },
  hw = (e, t) =>
    Ie("/usr/bin/iconutil", ["--convert", "icns", "--output", t, e]),
  pw = () =>
    Ie("/bin/bash", [
      "-c",
      "rm /var/folders/*/*/*/com.apple.dock.iconcache; true",
    ]);
async function Tl(e, t) {
  const o = G.join(Uo, "set-icon"),
    { exitCode: i, stdout: a, stderr: n } = await Ie(o, [t, e], { reject: !1 });
  if (i !== 0) throw Error(`setIcon forFile failed (exit ${i}): ${n || a}`);
  await pw();
}
const pn = G.join(lt, "icon.icns");
async function Dw(e, t) {
  const o = G.join(e, "icon.iconset"),
    i = G.join(e, "icon.icns"),
    a = [16, 32, 64, 128, 256, 512];
  return (
    await Te.mkdir(o, { recursive: !0 }),
    await Promise.all(
      a.flatMap((n) => [
        _l(t, G.join(o, `icon_${n}x${n}.png`), String(n)),
        _l(t, G.join(o, `icon_${n}x${n}@2x.png`), String(n * 2)),
      ]),
    ),
    await hw(o, i),
    i
  );
}
class tp {
  async setAppIconFromFile(t, o = !1) {
    if (!(await Xn(t))) throw Error(`imgPath does not exist: ${t}`);
    const i = `${$o.split(".app")[0]}.app`,
      a = G.join(Ke.tmpdir(), tt.APP_NAME, hr());
    try {
      t.endsWith(".icns") || ye.dock?.setIcon(t);
      const n = await Dw(a, t);
      (await Tl(n, i), await Te.copyFile(n, pn), o && (await Te.unlink(pn)));
    } catch (n) {
      throw (
        Sentry.captureException(n),
        logger.error("icon change error:", n),
        n
      );
    } finally {
      await Te.rm(a, { recursive: !0, force: !0 });
    }
  }
  async setAppIconFromLink(t) {
    const o = G.join(Ke.tmpdir(), `texts-${hr()}-icon.png`);
    (await Bs(Ir.stream(t), vg(o)), await this.setAppIconFromFile(o));
  }
  async setAppIcon(t, o = !1) {
    if (!Ne) {
      logger.warn("setAppIcon: not running macOS, skipping icon change");
      return;
    }
    t.startsWith("https://")
      ? await this.setAppIconFromLink(t)
      : await this.setAppIconFromFile(t, o);
  }
  static async restoreChangedAppIcon(t) {
    if (!Ne) {
      logger.warn(
        "restoreChangedAppIcon: not running macOS, skipping icon change",
      );
      return;
    }
    return (await Io(pn))
      ? (await Xn(t))
        ? Tl(pn, t)
        : logger.log(
            `restoreChangedAppIcon: skipping because newAppPath doesn't exist: ${t}`,
          )
      : logger.log(
          "restoreChangedAppIcon: skipping because UPDATED_ICNS_PATH doesn't exist",
        );
  }
  async applyAppIconOnStartup(t) {
    (await Io(pn)) ||
      logger.log(
        "[MacOSAppIcon::assertAppIcon]: saved icon file missing, applying icon",
      );
    try {
      (logger.log(
        "[MacOSAppIcon::applyAppIconOnStartup]: Applying app icon with path:",
        t,
      ),
        await this.setAppIcon(t));
    } catch (i) {
      logger.error("Failed to set app icon on startup:", i);
    }
  }
}
var mw = Pm();
const gw = pr(mw),
  qs = new Map(),
  xl =
    !Ph || !Re
      ? void 0
      : new Re.PushNotificationManager((e, t, o) => {
          if (!e) return;
          const i = JSON.parse(t),
            a = qs.get(i.id);
          a && a.processCallback(e, i, o);
        });
class ww extends Zs {
  constructor(t, o, i, a, n, r) {
    (super(),
      (this.options = t),
      (this.payload = o),
      (this.otp = i),
      (this.txnID = a),
      (this.showReminderActions = n),
      (this.showMarkReadAction = r),
      (this.id = hr()),
      qs.set(this.id, this));
  }
  show() {
    xl.sendNotification(JSON.stringify(this)).catch((t) =>
      logger.error("[UserNotification] sendNotification failed", t),
    );
  }
  close() {
    xl.dismissNotification(this.id);
  }
  processCallback(t, o, i) {
    (this.emit(t, o, i), t === Rm.close && qs.delete(this.id));
  }
  toJSON() {
    return {
      id: this.id,
      payload: this.payload,
      otp: this.otp,
      txnID: this.txnID,
      showReminderActions: this.showReminderActions,
      showMarkReadAction: this.showMarkReadAction,
      ...this.options,
    };
  }
}
function sa(e) {
  or.write([new Rs(e)]).catch((t) =>
    logger.error("[clipboard] write failed", t),
  );
}
function yw(e) {
  or.writeText(e).catch((t) => logger.error("[clipboard] writeText failed", t));
}
function ua(e, t) {
  return {
    "text/plain": e,
    "electron application/bookmark": { title: t, url: e },
  };
}
async function Ew(e) {
  const t = await ks,
    o = `http://${t.pasClientHostname}:${t.pasPort}/${t.transportNonce}/`,
    i = gw(async (a) => {
      if (!a.startsWith(o)) return a;
      try {
        const n = await Ir.head(a, {
          followRedirect: !1,
          throwHttpErrors: !1,
          timeout: { request: 3e3 },
        });
        if (n.statusCode === 301) {
          if (yt) {
            const r = `/${t.transportNonce}/fileProxy/`;
            if (n.headers.location?.startsWith(r))
              return Buffer.from(
                n.headers.location.slice(r.length),
                "base64",
              ).toString();
          }
          return n.headers.location?.replace("fileproxy://", "file://");
        }
      } catch (n) {
        logger.error(n);
      }
      return a;
    });
  return (
    await Promise.all([
      (async () => {
        e.thread.imgURL && (e.thread.imgURL = await i(e.thread.imgURL));
      })(),
      (async () => {
        e.sender.imgURL && (e.sender.imgURL = await i(e.sender.imgURL));
      })(),
      ...(e.participants?.map(async (a) => {
        a.imgURL && (a.imgURL = await i(a.imgURL));
      }) ?? []),
    ]),
    e
  );
}
const Nl = G.join(Uo, "sounds"),
  Il = G.join(gm(), "Library/Sounds"),
  vw = Lm(async () => {
    try {
      await Te.mkdir(Il, { recursive: !0 });
      for (const e of await Te.readdir(Nl)) {
        const t = G.join(Nl, e),
          o = G.join(Il, e);
        (await Te.realpath(o).catch(() => "")) !== t &&
          (await Te.rm(o, { force: !0 }), await Te.symlink(t, o));
      }
    } catch (e) {
      logger.error("[NotificationStore] linkNotificationSounds:", e);
    }
  });
class Cw {
  constructor(t, o) {
    ((this.window = t),
      (this.rs = o),
      (this.counter = 0),
      (this.notifsMap = new Map()));
  }
  async newNotification(t, o, i, a) {
    const {
      otp: n,
      messageID: r,
      replyThreadID: s,
      payload: u,
      txnID: f,
      showReminderActions: d,
      showMarkReadAction: c,
      actionIDs: l,
    } = a || {};
    try {
      await Re?.requestNotificationsAuthorization();
    } catch {
      return (
        logger.info(
          `[NotificationStore] newNotification: Notifications are not enabled accountID=${t} threadID=${o}`,
        ),
        -1
      );
    }
    Ne && i.sound && (await vw());
    const h = ++this.counter,
      y = Ph
        ? new ww(
            i,
            u ? await Ew(u) : void 0,
            n || void 0,
            f || void 0,
            d || void 0,
            c || void 0,
          )
        : new ym(i);
    return (
      this.notifsMap.set(h, y),
      y.once("click", () => {
        (r ? this.rs.jumpToMessage(t, o, r) : this.rs.selectThreadByID(t, o),
          this.window.show(),
          this.rs.incrementCounter(Qu.NOTIFICATION_CLICKED));
      }),
      y.once("close", () => {
        (this.notifsMap.delete(h), this.rs.deleteShownNotification(t, o, h, r));
      }),
      y.once("reply", (F, m) => {
        (this.rs.sendMessageInThread(t, o, m, "notification reply", s),
          this.rs.incrementCounter(Qu.NOTIFICATION_REPLIED));
      }),
      y.once("action", (F, m) => {
        if (n) (yw(n), this.rs.onOtpCopy(t, o));
        else if (f)
          m === 0 || m === "verificationAccept"
            ? this.rs.acceptVerificationRequest(f)
            : this.rs.declineVerificationRequest(f);
        else {
          const S = typeof m == "number" ? l?.[m] : m;
          S === "markRead"
            ? this.rs.markThreadReadFromNotification(t, o, r)
            : S === "remind1h"
              ? this.rs.setThreadReminderFromNotification(t, o, 1)
              : S === "remind8h" &&
                this.rs.setThreadReminderFromNotification(t, o, 8);
        }
      }),
      logger.info(
        `[NotificationStore] newNotification: Created with id=${h} accountID=${t} threadID=${o} replyThreadID=${s} hasReply=${i.hasReply} payload.platform.name=${u?.platform.name}`,
      ),
      h
    );
  }
  showNotification(t) {
    const o = this.notifsMap.get(t);
    if (!o) {
      logger.error(
        "[NotificationStore] showNotification: Notification not found",
        t,
      );
      return;
    }
    o.show();
  }
  closeNotification(...t) {
    (logger.info("[NotificationStore] closeNotification: ", t.join(",")),
      t.forEach((o) => {
        const i = this.notifsMap.get(o);
        if (!i) {
          logger.error(
            "[NotificationStore] closeNotification: Notification not found",
            o,
          );
          return;
        }
        (i.close(), this.notifsMap.delete(o));
      }));
  }
  closeAllNotifications() {
    (logger.info("[NotificationStore] closeAllNotifications"),
      Array.from(this.notifsMap.keys()).forEach((t) => {
        (this.notifsMap.get(t)?.close(), this.notifsMap.delete(t));
      }));
  }
}
function Aw(e, t) {}
const bw = {
    "text/vcard": "text/x-vcard",
    "video/x-m4v": "video/mp4",
    "text/x-markdown": "text/markdown",
  },
  Ol = (e) => {
    const t = e && e.split(";", 1)[0].trim().toLowerCase();
    return t && (bw[t] || t);
  },
  Pl = async (e, t) => {
    if (!t || t === "application/octet-stream") return e;
    const o = await import("./index-DaNOOrJg.mjs").then((n) => n.i);
    if (Ol(t) === Ol(o.lookup(e))) return e;
    const i = o.extension(t);
    return !i || (e.split(".").pop()?.toLowerCase() || "") === i
      ? e
      : `${e}.${i}`;
  },
  rp = G.join(lt, "quicklook"),
  Fw = /^\.[a-z0-9]{1,10}$/i,
  Sw = /^\.\d+$/,
  _w = 255,
  Yi = (e) => {
    const t = G.extname(e);
    return Fw.test(t) && !Sw.test(t);
  },
  Ai = (e) =>
    Buffer.byteLength(e) <= _w ? e : `Attachment${Yi(e) ? G.extname(e) : ""}`;
async function Tw(e, t, o) {
  const i = ag(t ?? "") || G.basename(e);
  if (Yi(i)) return Ai(i);
  if (Yi(e)) return Ai(`${i}${G.extname(e)}`);
  const a = await Pl(i, o);
  return Yi(a) ? Ai(a) : Ai(await Pl(i, await Mh(e)));
}
let Rl = Promise.resolve();
const np = (e) => {
    const t = Rl.then(e);
    return ((Rl = t.catch(() => {})), t);
  },
  ip = () => Te.rm(rp, { recursive: !0, force: !0 }),
  Ll = () => np(ip),
  xw = (e, t, o, i) =>
    np(async () => {
      const a = Uh(t);
      await Te.access(a);
      const n = await Tw(a, o, i);
      await ip();
      const r = G.join(rp, hg());
      await Te.mkdir(r, { recursive: !0 });
      const s = G.join(r, n);
      (await Te.copyFile(a, s, Cg.COPYFILE_FICLONE),
        await Lh(s),
        e.previewFile(s, o));
    });
var Cr = {},
  la = {},
  bi = {},
  Bl;
function Et() {
  return (
    Bl ||
      ((Bl = 1),
      (bi.fromCallback = function (e) {
        return Object.defineProperty(
          function (...t) {
            if (typeof t[t.length - 1] == "function") e.apply(this, t);
            else
              return new Promise((o, i) => {
                (t.push((a, n) => (a != null ? i(a) : o(n))), e.apply(this, t));
              });
          },
          "name",
          { value: e.name },
        );
      }),
      (bi.fromPromise = function (e) {
        return Object.defineProperty(
          function (...t) {
            const o = t[t.length - 1];
            if (typeof o != "function") return e.apply(this, t);
            (t.pop(), e.apply(this, t).then((i) => o(null, i), o));
          },
          "name",
          { value: e.name },
        );
      })),
    bi
  );
}
var ca, kl;
function Nw() {
  if (kl) return ca;
  kl = 1;
  var e = jh,
    t = process.cwd,
    o = null,
    i = process.env.GRACEFUL_FS_PLATFORM || process.platform;
  process.cwd = function () {
    return (o || (o = t.call(process)), o);
  };
  try {
    process.cwd();
  } catch {}
  if (typeof process.chdir == "function") {
    var a = process.chdir;
    ((process.chdir = function (r) {
      ((o = null), a.call(process, r));
    }),
      Object.setPrototypeOf && Object.setPrototypeOf(process.chdir, a));
  }
  ca = n;
  function n(r) {
    (e.hasOwnProperty("O_SYMLINK") &&
      process.version.match(/^v0\.6\.[0-2]|^v0\.5\./) &&
      s(r),
      r.lutimes || u(r),
      (r.chown = c(r.chown)),
      (r.fchown = c(r.fchown)),
      (r.lchown = c(r.lchown)),
      (r.chmod = f(r.chmod)),
      (r.fchmod = f(r.fchmod)),
      (r.lchmod = f(r.lchmod)),
      (r.chownSync = l(r.chownSync)),
      (r.fchownSync = l(r.fchownSync)),
      (r.lchownSync = l(r.lchownSync)),
      (r.chmodSync = d(r.chmodSync)),
      (r.fchmodSync = d(r.fchmodSync)),
      (r.lchmodSync = d(r.lchmodSync)),
      (r.stat = h(r.stat)),
      (r.fstat = h(r.fstat)),
      (r.lstat = h(r.lstat)),
      (r.statSync = y(r.statSync)),
      (r.fstatSync = y(r.fstatSync)),
      (r.lstatSync = y(r.lstatSync)),
      r.chmod &&
        !r.lchmod &&
        ((r.lchmod = function (m, S, E) {
          E && process.nextTick(E);
        }),
        (r.lchmodSync = function () {})),
      r.chown &&
        !r.lchown &&
        ((r.lchown = function (m, S, E, b) {
          b && process.nextTick(b);
        }),
        (r.lchownSync = function () {})),
      i === "win32" &&
        (r.rename =
          typeof r.rename != "function"
            ? r.rename
            : (function (m) {
                function S(E, b, w) {
                  var A = Date.now(),
                    v = 0;
                  m(E, b, function C(g) {
                    if (
                      g &&
                      (g.code === "EACCES" ||
                        g.code === "EPERM" ||
                        g.code === "EBUSY") &&
                      Date.now() - A < 6e4
                    ) {
                      (setTimeout(function () {
                        r.stat(b, function (D, N) {
                          D && D.code === "ENOENT" ? m(E, b, C) : w(g);
                        });
                      }, v),
                        v < 100 && (v += 10));
                      return;
                    }
                    w && w(g);
                  });
                }
                return (
                  Object.setPrototypeOf && Object.setPrototypeOf(S, m),
                  S
                );
              })(r.rename)),
      (r.read =
        typeof r.read != "function"
          ? r.read
          : (function (m) {
              function S(E, b, w, A, v, C) {
                var g;
                if (C && typeof C == "function") {
                  var D = 0;
                  g = function (N, P, R) {
                    if (N && N.code === "EAGAIN" && D < 10)
                      return (D++, m.call(r, E, b, w, A, v, g));
                    C.apply(this, arguments);
                  };
                }
                return m.call(r, E, b, w, A, v, g);
              }
              return (Object.setPrototypeOf && Object.setPrototypeOf(S, m), S);
            })(r.read)),
      (r.readSync =
        typeof r.readSync != "function"
          ? r.readSync
          : (function (m) {
              return function (S, E, b, w, A) {
                for (var v = 0; ;)
                  try {
                    return m.call(r, S, E, b, w, A);
                  } catch (C) {
                    if (C.code === "EAGAIN" && v < 10) {
                      v++;
                      continue;
                    }
                    throw C;
                  }
              };
            })(r.readSync)));
    function s(m) {
      ((m.lchmod = function (S, E, b) {
        m.open(S, e.O_WRONLY | e.O_SYMLINK, E, function (w, A) {
          if (w) {
            b && b(w);
            return;
          }
          m.fchmod(A, E, function (v) {
            m.close(A, function (C) {
              b && b(v || C);
            });
          });
        });
      }),
        (m.lchmodSync = function (S, E) {
          var b = m.openSync(S, e.O_WRONLY | e.O_SYMLINK, E),
            w = !0,
            A;
          try {
            ((A = m.fchmodSync(b, E)), (w = !1));
          } finally {
            if (w)
              try {
                m.closeSync(b);
              } catch {}
            else m.closeSync(b);
          }
          return A;
        }));
    }
    function u(m) {
      e.hasOwnProperty("O_SYMLINK") && m.futimes
        ? ((m.lutimes = function (S, E, b, w) {
            m.open(S, e.O_SYMLINK, function (A, v) {
              if (A) {
                w && w(A);
                return;
              }
              m.futimes(v, E, b, function (C) {
                m.close(v, function (g) {
                  w && w(C || g);
                });
              });
            });
          }),
          (m.lutimesSync = function (S, E, b) {
            var w = m.openSync(S, e.O_SYMLINK),
              A,
              v = !0;
            try {
              ((A = m.futimesSync(w, E, b)), (v = !1));
            } finally {
              if (v)
                try {
                  m.closeSync(w);
                } catch {}
              else m.closeSync(w);
            }
            return A;
          }))
        : m.futimes &&
          ((m.lutimes = function (S, E, b, w) {
            w && process.nextTick(w);
          }),
          (m.lutimesSync = function () {}));
    }
    function f(m) {
      return (
        m &&
        function (S, E, b) {
          return m.call(r, S, E, function (w) {
            (F(w) && (w = null), b && b.apply(this, arguments));
          });
        }
      );
    }
    function d(m) {
      return (
        m &&
        function (S, E) {
          try {
            return m.call(r, S, E);
          } catch (b) {
            if (!F(b)) throw b;
          }
        }
      );
    }
    function c(m) {
      return (
        m &&
        function (S, E, b, w) {
          return m.call(r, S, E, b, function (A) {
            (F(A) && (A = null), w && w.apply(this, arguments));
          });
        }
      );
    }
    function l(m) {
      return (
        m &&
        function (S, E, b) {
          try {
            return m.call(r, S, E, b);
          } catch (w) {
            if (!F(w)) throw w;
          }
        }
      );
    }
    function h(m) {
      return (
        m &&
        function (S, E, b) {
          typeof E == "function" && ((b = E), (E = null));
          function w(A, v) {
            (v &&
              (v.uid < 0 && (v.uid += 4294967296),
              v.gid < 0 && (v.gid += 4294967296)),
              b && b.apply(this, arguments));
          }
          return E ? m.call(r, S, E, w) : m.call(r, S, w);
        }
      );
    }
    function y(m) {
      return (
        m &&
        function (S, E) {
          var b = E ? m.call(r, S, E) : m.call(r, S);
          return (
            b &&
              (b.uid < 0 && (b.uid += 4294967296),
              b.gid < 0 && (b.gid += 4294967296)),
            b
          );
        }
      );
    }
    function F(m) {
      if (!m || m.code === "ENOSYS") return !0;
      var S = !process.getuid || process.getuid() !== 0;
      return !!(S && (m.code === "EINVAL" || m.code === "EPERM"));
    }
  }
  return ca;
}
var fa, Ml;
function Iw() {
  if (Ml) return fa;
  Ml = 1;
  var e = ii.Stream;
  fa = t;
  function t(o) {
    return { ReadStream: i, WriteStream: a };
    function i(n, r) {
      if (!(this instanceof i)) return new i(n, r);
      e.call(this);
      var s = this;
      ((this.path = n),
        (this.fd = null),
        (this.readable = !0),
        (this.paused = !1),
        (this.flags = "r"),
        (this.mode = 438),
        (this.bufferSize = 64 * 1024),
        (r = r || {}));
      for (var u = Object.keys(r), f = 0, d = u.length; f < d; f++) {
        var c = u[f];
        this[c] = r[c];
      }
      if (
        (this.encoding && this.setEncoding(this.encoding),
        this.start !== void 0)
      ) {
        if (typeof this.start != "number")
          throw TypeError("start must be a Number");
        if (this.end === void 0) this.end = 1 / 0;
        else if (typeof this.end != "number")
          throw TypeError("end must be a Number");
        if (this.start > this.end) throw new Error("start must be <= end");
        this.pos = this.start;
      }
      if (this.fd !== null) {
        process.nextTick(function () {
          s._read();
        });
        return;
      }
      o.open(this.path, this.flags, this.mode, function (l, h) {
        if (l) {
          (s.emit("error", l), (s.readable = !1));
          return;
        }
        ((s.fd = h), s.emit("open", h), s._read());
      });
    }
    function a(n, r) {
      if (!(this instanceof a)) return new a(n, r);
      (e.call(this),
        (this.path = n),
        (this.fd = null),
        (this.writable = !0),
        (this.flags = "w"),
        (this.encoding = "binary"),
        (this.mode = 438),
        (this.bytesWritten = 0),
        (r = r || {}));
      for (var s = Object.keys(r), u = 0, f = s.length; u < f; u++) {
        var d = s[u];
        this[d] = r[d];
      }
      if (this.start !== void 0) {
        if (typeof this.start != "number")
          throw TypeError("start must be a Number");
        if (this.start < 0) throw new Error("start must be >= zero");
        this.pos = this.start;
      }
      ((this.busy = !1),
        (this._queue = []),
        this.fd === null &&
          ((this._open = o.open),
          this._queue.push([
            this._open,
            this.path,
            this.flags,
            this.mode,
            void 0,
          ]),
          this.flush()));
    }
  }
  return fa;
}
var da, Ul;
function Ow() {
  if (Ul) return da;
  ((Ul = 1), (da = t));
  var e =
    Object.getPrototypeOf ||
    function (o) {
      return o.__proto__;
    };
  function t(o) {
    if (o === null || typeof o != "object") return o;
    if (o instanceof Object) var i = { __proto__: e(o) };
    else var i = Object.create(null);
    return (
      Object.getOwnPropertyNames(o).forEach(function (a) {
        Object.defineProperty(i, a, Object.getOwnPropertyDescriptor(o, a));
      }),
      i
    );
  }
  return da;
}
var Fi, ql;
function mt() {
  if (ql) return Fi;
  ql = 1;
  var e = ze,
    t = Nw(),
    o = Iw(),
    i = Ow(),
    a = on,
    n,
    r;
  typeof Symbol == "function" && typeof Symbol.for == "function"
    ? ((n = Symbol.for("graceful-fs.queue")),
      (r = Symbol.for("graceful-fs.previous")))
    : ((n = "___graceful-fs.queue"), (r = "___graceful-fs.previous"));
  function s() {}
  function u(m, S) {
    Object.defineProperty(m, n, {
      get: function () {
        return S;
      },
    });
  }
  var f = s;
  if (
    (a.debuglog
      ? (f = a.debuglog("gfs4"))
      : /\bgfs4\b/i.test(process.env.NODE_DEBUG || "") &&
        (f = function () {
          var m = a.format.apply(a, arguments);
          ((m =
            "GFS4: " +
            m.split(/\n/).join(`
GFS4: `)),
            console.error(m));
        }),
    !e[n])
  ) {
    var d = Nt[n] || [];
    (u(e, d),
      (e.close = (function (m) {
        function S(E, b) {
          return m.call(e, E, function (w) {
            (w || y(), typeof b == "function" && b.apply(this, arguments));
          });
        }
        return (Object.defineProperty(S, r, { value: m }), S);
      })(e.close)),
      (e.closeSync = (function (m) {
        function S(E) {
          (m.apply(e, arguments), y());
        }
        return (Object.defineProperty(S, r, { value: m }), S);
      })(e.closeSync)),
      /\bgfs4\b/i.test(process.env.NODE_DEBUG || "") &&
        process.on("exit", function () {
          (f(e[n]), Wh.equal(e[n].length, 0));
        }));
  }
  (Nt[n] || u(Nt, e[n]),
    (Fi = c(i(e))),
    process.env.TEST_GRACEFUL_FS_GLOBAL_PATCH &&
      !e.__patched &&
      ((Fi = c(e)), (e.__patched = !0)));
  function c(m) {
    (t(m),
      (m.gracefulify = c),
      (m.createReadStream = Y),
      (m.createWriteStream = Ce));
    var S = m.readFile;
    m.readFile = E;
    function E(Q, ge, I) {
      return (typeof ge == "function" && ((I = ge), (ge = null)), _(Q, ge, I));
      function _(W, M, le, he) {
        return S(W, M, function (we) {
          we && (we.code === "EMFILE" || we.code === "ENFILE")
            ? l([_, [W, M, le], we, he || Date.now(), Date.now()])
            : typeof le == "function" && le.apply(this, arguments);
        });
      }
    }
    var b = m.writeFile;
    m.writeFile = w;
    function w(Q, ge, I, _) {
      return (typeof I == "function" && ((_ = I), (I = null)), W(Q, ge, I, _));
      function W(M, le, he, we, be) {
        return b(M, le, he, function (Fe) {
          Fe && (Fe.code === "EMFILE" || Fe.code === "ENFILE")
            ? l([W, [M, le, he, we], Fe, be || Date.now(), Date.now()])
            : typeof we == "function" && we.apply(this, arguments);
        });
      }
    }
    var A = m.appendFile;
    A && (m.appendFile = v);
    function v(Q, ge, I, _) {
      return (typeof I == "function" && ((_ = I), (I = null)), W(Q, ge, I, _));
      function W(M, le, he, we, be) {
        return A(M, le, he, function (Fe) {
          Fe && (Fe.code === "EMFILE" || Fe.code === "ENFILE")
            ? l([W, [M, le, he, we], Fe, be || Date.now(), Date.now()])
            : typeof we == "function" && we.apply(this, arguments);
        });
      }
    }
    var C = m.copyFile;
    C && (m.copyFile = g);
    function g(Q, ge, I, _) {
      return (typeof I == "function" && ((_ = I), (I = 0)), W(Q, ge, I, _));
      function W(M, le, he, we, be) {
        return C(M, le, he, function (Fe) {
          Fe && (Fe.code === "EMFILE" || Fe.code === "ENFILE")
            ? l([W, [M, le, he, we], Fe, be || Date.now(), Date.now()])
            : typeof we == "function" && we.apply(this, arguments);
        });
      }
    }
    var D = m.readdir;
    m.readdir = P;
    var N = /^v[0-5]\./;
    function P(Q, ge, I) {
      typeof ge == "function" && ((I = ge), (ge = null));
      var _ = N.test(process.version)
        ? function (le, he, we, be) {
            return D(le, W(le, he, we, be));
          }
        : function (le, he, we, be) {
            return D(le, he, W(le, he, we, be));
          };
      return _(Q, ge, I);
      function W(M, le, he, we) {
        return function (be, Fe) {
          be && (be.code === "EMFILE" || be.code === "ENFILE")
            ? l([_, [M, le, he], be, we || Date.now(), Date.now()])
            : (Fe && Fe.sort && Fe.sort(),
              typeof he == "function" && he.call(this, be, Fe));
        };
      }
    }
    if (process.version.substr(0, 4) === "v0.8") {
      var R = o(m);
      ((V = R.ReadStream), (X = R.WriteStream));
    }
    var k = m.ReadStream;
    k && ((V.prototype = Object.create(k.prototype)), (V.prototype.open = re));
    var q = m.WriteStream;
    (q && ((X.prototype = Object.create(q.prototype)), (X.prototype.open = fe)),
      Object.defineProperty(m, "ReadStream", {
        get: function () {
          return V;
        },
        set: function (Q) {
          V = Q;
        },
        enumerable: !0,
        configurable: !0,
      }),
      Object.defineProperty(m, "WriteStream", {
        get: function () {
          return X;
        },
        set: function (Q) {
          X = Q;
        },
        enumerable: !0,
        configurable: !0,
      }));
    var U = V;
    Object.defineProperty(m, "FileReadStream", {
      get: function () {
        return U;
      },
      set: function (Q) {
        U = Q;
      },
      enumerable: !0,
      configurable: !0,
    });
    var $ = X;
    Object.defineProperty(m, "FileWriteStream", {
      get: function () {
        return $;
      },
      set: function (Q) {
        $ = Q;
      },
      enumerable: !0,
      configurable: !0,
    });
    function V(Q, ge) {
      return this instanceof V
        ? (k.apply(this, arguments), this)
        : V.apply(Object.create(V.prototype), arguments);
    }
    function re() {
      var Q = this;
      Ae(Q.path, Q.flags, Q.mode, function (ge, I) {
        ge
          ? (Q.autoClose && Q.destroy(), Q.emit("error", ge))
          : ((Q.fd = I), Q.emit("open", I), Q.read());
      });
    }
    function X(Q, ge) {
      return this instanceof X
        ? (q.apply(this, arguments), this)
        : X.apply(Object.create(X.prototype), arguments);
    }
    function fe() {
      var Q = this;
      Ae(Q.path, Q.flags, Q.mode, function (ge, I) {
        ge
          ? (Q.destroy(), Q.emit("error", ge))
          : ((Q.fd = I), Q.emit("open", I));
      });
    }
    function Y(Q, ge) {
      return new m.ReadStream(Q, ge);
    }
    function Ce(Q, ge) {
      return new m.WriteStream(Q, ge);
    }
    var ue = m.open;
    m.open = Ae;
    function Ae(Q, ge, I, _) {
      return (typeof I == "function" && ((_ = I), (I = null)), W(Q, ge, I, _));
      function W(M, le, he, we, be) {
        return ue(M, le, he, function (Fe, Oe) {
          Fe && (Fe.code === "EMFILE" || Fe.code === "ENFILE")
            ? l([W, [M, le, he, we], Fe, be || Date.now(), Date.now()])
            : typeof we == "function" && we.apply(this, arguments);
        });
      }
    }
    return m;
  }
  function l(m) {
    (f("ENQUEUE", m[0].name, m[1]), e[n].push(m), F());
  }
  var h;
  function y() {
    for (var m = Date.now(), S = 0; S < e[n].length; ++S)
      e[n][S].length > 2 && ((e[n][S][3] = m), (e[n][S][4] = m));
    F();
  }
  function F() {
    if ((clearTimeout(h), (h = void 0), e[n].length !== 0)) {
      var m = e[n].shift(),
        S = m[0],
        E = m[1],
        b = m[2],
        w = m[3],
        A = m[4];
      if (w === void 0) (f("RETRY", S.name, E), S.apply(null, E));
      else if (Date.now() - w >= 6e4) {
        f("TIMEOUT", S.name, E);
        var v = E.pop();
        typeof v == "function" && v.call(null, b);
      } else {
        var C = Date.now() - A,
          g = Math.max(A - w, 1),
          D = Math.min(g * 1.2, 100);
        C >= D
          ? (f("RETRY", S.name, E), S.apply(null, E.concat([w])))
          : e[n].push(m);
      }
      h === void 0 && (h = setTimeout(F, 0));
    }
  }
  return Fi;
}
var $l;
function an() {
  return (
    $l ||
      (($l = 1),
      (function (e) {
        const t = Et().fromCallback,
          o = mt(),
          i = [
            "access",
            "appendFile",
            "chmod",
            "chown",
            "close",
            "copyFile",
            "fchmod",
            "fchown",
            "fdatasync",
            "fstat",
            "fsync",
            "ftruncate",
            "futimes",
            "lchmod",
            "lchown",
            "link",
            "lstat",
            "mkdir",
            "mkdtemp",
            "open",
            "opendir",
            "readdir",
            "readFile",
            "readlink",
            "realpath",
            "rename",
            "rm",
            "rmdir",
            "stat",
            "symlink",
            "truncate",
            "unlink",
            "utimes",
            "writeFile",
          ].filter((a) => typeof o[a] == "function");
        (Object.assign(e, o),
          i.forEach((a) => {
            e[a] = t(o[a]);
          }),
          (e.exists = function (a, n) {
            return typeof n == "function"
              ? o.exists(a, n)
              : new Promise((r) => o.exists(a, r));
          }),
          (e.read = function (a, n, r, s, u, f) {
            return typeof f == "function"
              ? o.read(a, n, r, s, u, f)
              : new Promise((d, c) => {
                  o.read(a, n, r, s, u, (l, h, y) => {
                    if (l) return c(l);
                    d({ bytesRead: h, buffer: y });
                  });
                });
          }),
          (e.write = function (a, n, ...r) {
            return typeof r[r.length - 1] == "function"
              ? o.write(a, n, ...r)
              : new Promise((s, u) => {
                  o.write(a, n, ...r, (f, d, c) => {
                    if (f) return u(f);
                    s({ bytesWritten: d, buffer: c });
                  });
                });
          }),
          typeof o.writev == "function" &&
            (e.writev = function (a, n, ...r) {
              return typeof r[r.length - 1] == "function"
                ? o.writev(a, n, ...r)
                : new Promise((s, u) => {
                    o.writev(a, n, ...r, (f, d, c) => {
                      if (f) return u(f);
                      s({ bytesWritten: d, buffers: c });
                    });
                  });
            }),
          typeof o.realpath.native == "function"
            ? (e.realpath.native = t(o.realpath.native))
            : process.emitWarning(
                "fs.realpath.native is not a function. Is fs being monkey-patched?",
                "Warning",
                "fs-extra-WARN0003",
              ));
      })(la)),
    la
  );
}
var Si = {},
  ha = {},
  jl;
function Pw() {
  if (jl) return ha;
  jl = 1;
  const e = G;
  return (
    (ha.checkPath = function (o) {
      if (
        process.platform === "win32" &&
        /[<>:"|?*]/.test(o.replace(e.parse(o).root, ""))
      ) {
        const a = new Error(`Path contains invalid characters: ${o}`);
        throw ((a.code = "EINVAL"), a);
      }
    }),
    ha
  );
}
var Wl;
function Rw() {
  if (Wl) return Si;
  Wl = 1;
  const e = an(),
    { checkPath: t } = Pw(),
    o = (i) => {
      const a = { mode: 511 };
      return typeof i == "number" ? i : { ...a, ...i }.mode;
    };
  return (
    (Si.makeDir = async (i, a) => (
      t(i),
      e.mkdir(i, { mode: o(a), recursive: !0 })
    )),
    (Si.makeDirSync = (i, a) => (
      t(i),
      e.mkdirSync(i, { mode: o(a), recursive: !0 })
    )),
    Si
  );
}
var pa, Hl;
function Ut() {
  if (Hl) return pa;
  Hl = 1;
  const e = Et().fromPromise,
    { makeDir: t, makeDirSync: o } = Rw(),
    i = e(t);
  return (
    (pa = {
      mkdirs: i,
      mkdirsSync: o,
      mkdirp: i,
      mkdirpSync: o,
      ensureDir: i,
      ensureDirSync: o,
    }),
    pa
  );
}
var Da, Gl;
function Lr() {
  if (Gl) return Da;
  Gl = 1;
  const e = Et().fromPromise,
    t = an();
  function o(i) {
    return t
      .access(i)
      .then(() => !0)
      .catch(() => !1);
  }
  return ((Da = { pathExists: e(o), pathExistsSync: t.existsSync }), Da);
}
var ma, Vl;
function op() {
  if (Vl) return ma;
  Vl = 1;
  const e = mt();
  function t(i, a, n, r) {
    e.open(i, "r+", (s, u) => {
      if (s) return r(s);
      e.futimes(u, a, n, (f) => {
        e.close(u, (d) => {
          r && r(f || d);
        });
      });
    });
  }
  function o(i, a, n) {
    const r = e.openSync(i, "r+");
    return (e.futimesSync(r, a, n), e.closeSync(r));
  }
  return ((ma = { utimesMillis: t, utimesMillisSync: o }), ma);
}
var ga, zl;
function sn() {
  if (zl) return ga;
  zl = 1;
  const e = an(),
    t = G,
    o = on;
  function i(l, h, y) {
    const F = y.dereference
      ? (m) => e.stat(m, { bigint: !0 })
      : (m) => e.lstat(m, { bigint: !0 });
    return Promise.all([
      F(l),
      F(h).catch((m) => {
        if (m.code === "ENOENT") return null;
        throw m;
      }),
    ]).then(([m, S]) => ({ srcStat: m, destStat: S }));
  }
  function a(l, h, y) {
    let F;
    const m = y.dereference
        ? (E) => e.statSync(E, { bigint: !0 })
        : (E) => e.lstatSync(E, { bigint: !0 }),
      S = m(l);
    try {
      F = m(h);
    } catch (E) {
      if (E.code === "ENOENT") return { srcStat: S, destStat: null };
      throw E;
    }
    return { srcStat: S, destStat: F };
  }
  function n(l, h, y, F, m) {
    o.callbackify(i)(l, h, F, (S, E) => {
      if (S) return m(S);
      const { srcStat: b, destStat: w } = E;
      if (w) {
        if (f(b, w)) {
          const A = t.basename(l),
            v = t.basename(h);
          return y === "move" && A !== v && A.toLowerCase() === v.toLowerCase()
            ? m(null, { srcStat: b, destStat: w, isChangingCase: !0 })
            : m(new Error("Source and destination must not be the same."));
        }
        if (b.isDirectory() && !w.isDirectory())
          return m(
            new Error(
              `Cannot overwrite non-directory '${h}' with directory '${l}'.`,
            ),
          );
        if (!b.isDirectory() && w.isDirectory())
          return m(
            new Error(
              `Cannot overwrite directory '${h}' with non-directory '${l}'.`,
            ),
          );
      }
      return b.isDirectory() && d(l, h)
        ? m(new Error(c(l, h, y)))
        : m(null, { srcStat: b, destStat: w });
    });
  }
  function r(l, h, y, F) {
    const { srcStat: m, destStat: S } = a(l, h, F);
    if (S) {
      if (f(m, S)) {
        const E = t.basename(l),
          b = t.basename(h);
        if (y === "move" && E !== b && E.toLowerCase() === b.toLowerCase())
          return { srcStat: m, destStat: S, isChangingCase: !0 };
        throw new Error("Source and destination must not be the same.");
      }
      if (m.isDirectory() && !S.isDirectory())
        throw new Error(
          `Cannot overwrite non-directory '${h}' with directory '${l}'.`,
        );
      if (!m.isDirectory() && S.isDirectory())
        throw new Error(
          `Cannot overwrite directory '${h}' with non-directory '${l}'.`,
        );
    }
    if (m.isDirectory() && d(l, h)) throw new Error(c(l, h, y));
    return { srcStat: m, destStat: S };
  }
  function s(l, h, y, F, m) {
    const S = t.resolve(t.dirname(l)),
      E = t.resolve(t.dirname(y));
    if (E === S || E === t.parse(E).root) return m();
    e.stat(E, { bigint: !0 }, (b, w) =>
      b
        ? b.code === "ENOENT"
          ? m()
          : m(b)
        : f(h, w)
          ? m(new Error(c(l, y, F)))
          : s(l, h, E, F, m),
    );
  }
  function u(l, h, y, F) {
    const m = t.resolve(t.dirname(l)),
      S = t.resolve(t.dirname(y));
    if (S === m || S === t.parse(S).root) return;
    let E;
    try {
      E = e.statSync(S, { bigint: !0 });
    } catch (b) {
      if (b.code === "ENOENT") return;
      throw b;
    }
    if (f(h, E)) throw new Error(c(l, y, F));
    return u(l, h, S, F);
  }
  function f(l, h) {
    return h.ino && h.dev && h.ino === l.ino && h.dev === l.dev;
  }
  function d(l, h) {
    const y = t
        .resolve(l)
        .split(t.sep)
        .filter((m) => m),
      F = t
        .resolve(h)
        .split(t.sep)
        .filter((m) => m);
    return y.reduce((m, S, E) => m && F[E] === S, !0);
  }
  function c(l, h, y) {
    return `Cannot ${y} '${l}' to a subdirectory of itself, '${h}'.`;
  }
  return (
    (ga = {
      checkPaths: n,
      checkPathsSync: r,
      checkParentPaths: s,
      checkParentPathsSync: u,
      isSrcSubdir: d,
      areIdentical: f,
    }),
    ga
  );
}
var wa, Xl;
function Lw() {
  if (Xl) return wa;
  Xl = 1;
  const e = mt(),
    t = G,
    o = Ut().mkdirs,
    i = Lr().pathExists,
    a = op().utimesMillis,
    n = sn();
  function r(P, R, k, q) {
    (typeof k == "function" && !q
      ? ((q = k), (k = {}))
      : typeof k == "function" && (k = { filter: k }),
      (q = q || function () {}),
      (k = k || {}),
      (k.clobber = "clobber" in k ? !!k.clobber : !0),
      (k.overwrite = "overwrite" in k ? !!k.overwrite : k.clobber),
      k.preserveTimestamps &&
        process.arch === "ia32" &&
        process.emitWarning(
          `Using the preserveTimestamps option in 32-bit node is not recommended;

	see https://github.com/jprichardson/node-fs-extra/issues/269`,
          "Warning",
          "fs-extra-WARN0001",
        ),
      n.checkPaths(P, R, "copy", k, (U, $) => {
        if (U) return q(U);
        const { srcStat: V, destStat: re } = $;
        n.checkParentPaths(P, V, R, "copy", (X) =>
          X ? q(X) : k.filter ? u(s, re, P, R, k, q) : s(re, P, R, k, q),
        );
      }));
  }
  function s(P, R, k, q, U) {
    const $ = t.dirname(k);
    i($, (V, re) => {
      if (V) return U(V);
      if (re) return d(P, R, k, q, U);
      o($, (X) => (X ? U(X) : d(P, R, k, q, U)));
    });
  }
  function u(P, R, k, q, U, $) {
    Promise.resolve(U.filter(k, q)).then(
      (V) => (V ? P(R, k, q, U, $) : $()),
      (V) => $(V),
    );
  }
  function f(P, R, k, q, U) {
    return q.filter ? u(d, P, R, k, q, U) : d(P, R, k, q, U);
  }
  function d(P, R, k, q, U) {
    (q.dereference ? e.stat : e.lstat)(R, (V, re) =>
      V
        ? U(V)
        : re.isDirectory()
          ? w(re, P, R, k, q, U)
          : re.isFile() || re.isCharacterDevice() || re.isBlockDevice()
            ? c(re, P, R, k, q, U)
            : re.isSymbolicLink()
              ? D(P, R, k, q, U)
              : re.isSocket()
                ? U(new Error(`Cannot copy a socket file: ${R}`))
                : re.isFIFO()
                  ? U(new Error(`Cannot copy a FIFO pipe: ${R}`))
                  : U(new Error(`Unknown file: ${R}`)),
    );
  }
  function c(P, R, k, q, U, $) {
    return R ? l(P, k, q, U, $) : h(P, k, q, U, $);
  }
  function l(P, R, k, q, U) {
    if (q.overwrite) e.unlink(k, ($) => ($ ? U($) : h(P, R, k, q, U)));
    else return q.errorOnExist ? U(new Error(`'${k}' already exists`)) : U();
  }
  function h(P, R, k, q, U) {
    e.copyFile(R, k, ($) =>
      $ ? U($) : q.preserveTimestamps ? y(P.mode, R, k, U) : E(k, P.mode, U),
    );
  }
  function y(P, R, k, q) {
    return F(P) ? m(k, P, (U) => (U ? q(U) : S(P, R, k, q))) : S(P, R, k, q);
  }
  function F(P) {
    return (P & 128) === 0;
  }
  function m(P, R, k) {
    return E(P, R | 128, k);
  }
  function S(P, R, k, q) {
    b(R, k, (U) => (U ? q(U) : E(k, P, q)));
  }
  function E(P, R, k) {
    return e.chmod(P, R, k);
  }
  function b(P, R, k) {
    e.stat(P, (q, U) => (q ? k(q) : a(R, U.atime, U.mtime, k)));
  }
  function w(P, R, k, q, U, $) {
    return R ? v(k, q, U, $) : A(P.mode, k, q, U, $);
  }
  function A(P, R, k, q, U) {
    e.mkdir(k, ($) => {
      if ($) return U($);
      v(R, k, q, (V) => (V ? U(V) : E(k, P, U)));
    });
  }
  function v(P, R, k, q) {
    e.readdir(P, (U, $) => (U ? q(U) : C($, P, R, k, q)));
  }
  function C(P, R, k, q, U) {
    const $ = P.pop();
    return $ ? g(P, $, R, k, q, U) : U();
  }
  function g(P, R, k, q, U, $) {
    const V = t.join(k, R),
      re = t.join(q, R);
    n.checkPaths(V, re, "copy", U, (X, fe) => {
      if (X) return $(X);
      const { destStat: Y } = fe;
      f(Y, V, re, U, (Ce) => (Ce ? $(Ce) : C(P, k, q, U, $)));
    });
  }
  function D(P, R, k, q, U) {
    e.readlink(R, ($, V) => {
      if ($) return U($);
      if ((q.dereference && (V = t.resolve(process.cwd(), V)), P))
        e.readlink(k, (re, X) =>
          re
            ? re.code === "EINVAL" || re.code === "UNKNOWN"
              ? e.symlink(V, k, U)
              : U(re)
            : (q.dereference && (X = t.resolve(process.cwd(), X)),
              n.isSrcSubdir(V, X)
                ? U(
                    new Error(
                      `Cannot copy '${V}' to a subdirectory of itself, '${X}'.`,
                    ),
                  )
                : P.isDirectory() && n.isSrcSubdir(X, V)
                  ? U(new Error(`Cannot overwrite '${X}' with '${V}'.`))
                  : N(V, k, U)),
        );
      else return e.symlink(V, k, U);
    });
  }
  function N(P, R, k) {
    e.unlink(R, (q) => (q ? k(q) : e.symlink(P, R, k)));
  }
  return ((wa = r), wa);
}
var ya, Yl;
function Bw() {
  if (Yl) return ya;
  Yl = 1;
  const e = mt(),
    t = G,
    o = Ut().mkdirsSync,
    i = op().utimesMillisSync,
    a = sn();
  function n(C, g, D) {
    (typeof D == "function" && (D = { filter: D }),
      (D = D || {}),
      (D.clobber = "clobber" in D ? !!D.clobber : !0),
      (D.overwrite = "overwrite" in D ? !!D.overwrite : D.clobber),
      D.preserveTimestamps &&
        process.arch === "ia32" &&
        process.emitWarning(
          `Using the preserveTimestamps option in 32-bit node is not recommended;

	see https://github.com/jprichardson/node-fs-extra/issues/269`,
          "Warning",
          "fs-extra-WARN0002",
        ));
    const { srcStat: N, destStat: P } = a.checkPathsSync(C, g, "copy", D);
    return (a.checkParentPathsSync(C, N, g, "copy"), r(P, C, g, D));
  }
  function r(C, g, D, N) {
    if (N.filter && !N.filter(g, D)) return;
    const P = t.dirname(D);
    return (e.existsSync(P) || o(P), u(C, g, D, N));
  }
  function s(C, g, D, N) {
    if (!(N.filter && !N.filter(g, D))) return u(C, g, D, N);
  }
  function u(C, g, D, N) {
    const R = (N.dereference ? e.statSync : e.lstatSync)(g);
    if (R.isDirectory()) return S(R, C, g, D, N);
    if (R.isFile() || R.isCharacterDevice() || R.isBlockDevice())
      return f(R, C, g, D, N);
    if (R.isSymbolicLink()) return A(C, g, D, N);
    throw R.isSocket()
      ? new Error(`Cannot copy a socket file: ${g}`)
      : R.isFIFO()
        ? new Error(`Cannot copy a FIFO pipe: ${g}`)
        : new Error(`Unknown file: ${g}`);
  }
  function f(C, g, D, N, P) {
    return g ? d(C, D, N, P) : c(C, D, N, P);
  }
  function d(C, g, D, N) {
    if (N.overwrite) return (e.unlinkSync(D), c(C, g, D, N));
    if (N.errorOnExist) throw new Error(`'${D}' already exists`);
  }
  function c(C, g, D, N) {
    return (
      e.copyFileSync(g, D),
      N.preserveTimestamps && l(C.mode, g, D),
      F(D, C.mode)
    );
  }
  function l(C, g, D) {
    return (h(C) && y(D, C), m(g, D));
  }
  function h(C) {
    return (C & 128) === 0;
  }
  function y(C, g) {
    return F(C, g | 128);
  }
  function F(C, g) {
    return e.chmodSync(C, g);
  }
  function m(C, g) {
    const D = e.statSync(C);
    return i(g, D.atime, D.mtime);
  }
  function S(C, g, D, N, P) {
    return g ? b(D, N, P) : E(C.mode, D, N, P);
  }
  function E(C, g, D, N) {
    return (e.mkdirSync(D), b(g, D, N), F(D, C));
  }
  function b(C, g, D) {
    e.readdirSync(C).forEach((N) => w(N, C, g, D));
  }
  function w(C, g, D, N) {
    const P = t.join(g, C),
      R = t.join(D, C),
      { destStat: k } = a.checkPathsSync(P, R, "copy", N);
    return s(k, P, R, N);
  }
  function A(C, g, D, N) {
    let P = e.readlinkSync(g);
    if ((N.dereference && (P = t.resolve(process.cwd(), P)), C)) {
      let R;
      try {
        R = e.readlinkSync(D);
      } catch (k) {
        if (k.code === "EINVAL" || k.code === "UNKNOWN")
          return e.symlinkSync(P, D);
        throw k;
      }
      if (
        (N.dereference && (R = t.resolve(process.cwd(), R)),
        a.isSrcSubdir(P, R))
      )
        throw new Error(
          `Cannot copy '${P}' to a subdirectory of itself, '${R}'.`,
        );
      if (e.statSync(D).isDirectory() && a.isSrcSubdir(R, P))
        throw new Error(`Cannot overwrite '${R}' with '${P}'.`);
      return v(P, D);
    } else return e.symlinkSync(P, D);
  }
  function v(C, g) {
    return (e.unlinkSync(g), e.symlinkSync(C, g));
  }
  return ((ya = n), ya);
}
var Ea, Kl;
function iu() {
  if (Kl) return Ea;
  Kl = 1;
  const e = Et().fromCallback;
  return ((Ea = { copy: e(Lw()), copySync: Bw() }), Ea);
}
var va, Jl;
function kw() {
  if (Jl) return va;
  Jl = 1;
  const e = mt(),
    t = G,
    o = Wh,
    i = process.platform === "win32";
  function a(y) {
    (["unlink", "chmod", "stat", "lstat", "rmdir", "readdir"].forEach((m) => {
      ((y[m] = y[m] || e[m]), (m = m + "Sync"), (y[m] = y[m] || e[m]));
    }),
      (y.maxBusyTries = y.maxBusyTries || 3));
  }
  function n(y, F, m) {
    let S = 0;
    (typeof F == "function" && ((m = F), (F = {})),
      o(y, "rimraf: missing path"),
      o.strictEqual(typeof y, "string", "rimraf: path should be a string"),
      o.strictEqual(typeof m, "function", "rimraf: callback function required"),
      o(F, "rimraf: invalid options argument provided"),
      o.strictEqual(typeof F, "object", "rimraf: options should be object"),
      a(F),
      r(y, F, function E(b) {
        if (b) {
          if (
            (b.code === "EBUSY" ||
              b.code === "ENOTEMPTY" ||
              b.code === "EPERM") &&
            S < F.maxBusyTries
          ) {
            S++;
            const w = S * 100;
            return setTimeout(() => r(y, F, E), w);
          }
          b.code === "ENOENT" && (b = null);
        }
        m(b);
      }));
  }
  function r(y, F, m) {
    (o(y),
      o(F),
      o(typeof m == "function"),
      F.lstat(y, (S, E) => {
        if (S && S.code === "ENOENT") return m(null);
        if (S && S.code === "EPERM" && i) return s(y, F, S, m);
        if (E && E.isDirectory()) return f(y, F, S, m);
        F.unlink(y, (b) => {
          if (b) {
            if (b.code === "ENOENT") return m(null);
            if (b.code === "EPERM") return i ? s(y, F, b, m) : f(y, F, b, m);
            if (b.code === "EISDIR") return f(y, F, b, m);
          }
          return m(b);
        });
      }));
  }
  function s(y, F, m, S) {
    (o(y),
      o(F),
      o(typeof S == "function"),
      F.chmod(y, 438, (E) => {
        E
          ? S(E.code === "ENOENT" ? null : m)
          : F.stat(y, (b, w) => {
              b
                ? S(b.code === "ENOENT" ? null : m)
                : w.isDirectory()
                  ? f(y, F, m, S)
                  : F.unlink(y, S);
            });
      }));
  }
  function u(y, F, m) {
    let S;
    (o(y), o(F));
    try {
      F.chmodSync(y, 438);
    } catch (E) {
      if (E.code === "ENOENT") return;
      throw m;
    }
    try {
      S = F.statSync(y);
    } catch (E) {
      if (E.code === "ENOENT") return;
      throw m;
    }
    S.isDirectory() ? l(y, F, m) : F.unlinkSync(y);
  }
  function f(y, F, m, S) {
    (o(y),
      o(F),
      o(typeof S == "function"),
      F.rmdir(y, (E) => {
        E &&
        (E.code === "ENOTEMPTY" || E.code === "EEXIST" || E.code === "EPERM")
          ? d(y, F, S)
          : E && E.code === "ENOTDIR"
            ? S(m)
            : S(E);
      }));
  }
  function d(y, F, m) {
    (o(y),
      o(F),
      o(typeof m == "function"),
      F.readdir(y, (S, E) => {
        if (S) return m(S);
        let b = E.length,
          w;
        if (b === 0) return F.rmdir(y, m);
        E.forEach((A) => {
          n(t.join(y, A), F, (v) => {
            if (!w) {
              if (v) return m((w = v));
              --b === 0 && F.rmdir(y, m);
            }
          });
        });
      }));
  }
  function c(y, F) {
    let m;
    ((F = F || {}),
      a(F),
      o(y, "rimraf: missing path"),
      o.strictEqual(typeof y, "string", "rimraf: path should be a string"),
      o(F, "rimraf: missing options"),
      o.strictEqual(typeof F, "object", "rimraf: options should be object"));
    try {
      m = F.lstatSync(y);
    } catch (S) {
      if (S.code === "ENOENT") return;
      S.code === "EPERM" && i && u(y, F, S);
    }
    try {
      m && m.isDirectory() ? l(y, F, null) : F.unlinkSync(y);
    } catch (S) {
      if (S.code === "ENOENT") return;
      if (S.code === "EPERM") return i ? u(y, F, S) : l(y, F, S);
      if (S.code !== "EISDIR") throw S;
      l(y, F, S);
    }
  }
  function l(y, F, m) {
    (o(y), o(F));
    try {
      F.rmdirSync(y);
    } catch (S) {
      if (S.code === "ENOTDIR") throw m;
      if (S.code === "ENOTEMPTY" || S.code === "EEXIST" || S.code === "EPERM")
        h(y, F);
      else if (S.code !== "ENOENT") throw S;
    }
  }
  function h(y, F) {
    if ((o(y), o(F), F.readdirSync(y).forEach((m) => c(t.join(y, m), F)), i)) {
      const m = Date.now();
      do
        try {
          return F.rmdirSync(y, F);
        } catch {}
      while (Date.now() - m < 500);
    } else return F.rmdirSync(y, F);
  }
  return ((va = n), (n.sync = c), va);
}
var Ca, Ql;
function Wo() {
  if (Ql) return Ca;
  Ql = 1;
  const e = mt(),
    t = Et().fromCallback,
    o = kw();
  function i(n, r) {
    if (e.rm) return e.rm(n, { recursive: !0, force: !0 }, r);
    o(n, r);
  }
  function a(n) {
    if (e.rmSync) return e.rmSync(n, { recursive: !0, force: !0 });
    o.sync(n);
  }
  return ((Ca = { remove: t(i), removeSync: a }), Ca);
}
var Aa, Zl;
function Mw() {
  if (Zl) return Aa;
  Zl = 1;
  const e = Et().fromPromise,
    t = an(),
    o = G,
    i = Ut(),
    a = Wo(),
    n = e(async function (u) {
      let f;
      try {
        f = await t.readdir(u);
      } catch {
        return i.mkdirs(u);
      }
      return Promise.all(f.map((d) => a.remove(o.join(u, d))));
    });
  function r(s) {
    let u;
    try {
      u = t.readdirSync(s);
    } catch {
      return i.mkdirsSync(s);
    }
    u.forEach((f) => {
      ((f = o.join(s, f)), a.removeSync(f));
    });
  }
  return (
    (Aa = { emptyDirSync: r, emptydirSync: r, emptyDir: n, emptydir: n }),
    Aa
  );
}
var ba, ec;
function Uw() {
  if (ec) return ba;
  ec = 1;
  const e = Et().fromCallback,
    t = G,
    o = mt(),
    i = Ut();
  function a(r, s) {
    function u() {
      o.writeFile(r, "", (f) => {
        if (f) return s(f);
        s();
      });
    }
    o.stat(r, (f, d) => {
      if (!f && d.isFile()) return s();
      const c = t.dirname(r);
      o.stat(c, (l, h) => {
        if (l)
          return l.code === "ENOENT"
            ? i.mkdirs(c, (y) => {
                if (y) return s(y);
                u();
              })
            : s(l);
        h.isDirectory()
          ? u()
          : o.readdir(c, (y) => {
              if (y) return s(y);
            });
      });
    });
  }
  function n(r) {
    let s;
    try {
      s = o.statSync(r);
    } catch {}
    if (s && s.isFile()) return;
    const u = t.dirname(r);
    try {
      o.statSync(u).isDirectory() || o.readdirSync(u);
    } catch (f) {
      if (f && f.code === "ENOENT") i.mkdirsSync(u);
      else throw f;
    }
    o.writeFileSync(r, "");
  }
  return ((ba = { createFile: e(a), createFileSync: n }), ba);
}
var Fa, tc;
function qw() {
  if (tc) return Fa;
  tc = 1;
  const e = Et().fromCallback,
    t = G,
    o = mt(),
    i = Ut(),
    a = Lr().pathExists,
    { areIdentical: n } = sn();
  function r(u, f, d) {
    function c(l, h) {
      o.link(l, h, (y) => {
        if (y) return d(y);
        d(null);
      });
    }
    o.lstat(f, (l, h) => {
      o.lstat(u, (y, F) => {
        if (y)
          return ((y.message = y.message.replace("lstat", "ensureLink")), d(y));
        if (h && n(F, h)) return d(null);
        const m = t.dirname(f);
        a(m, (S, E) => {
          if (S) return d(S);
          if (E) return c(u, f);
          i.mkdirs(m, (b) => {
            if (b) return d(b);
            c(u, f);
          });
        });
      });
    });
  }
  function s(u, f) {
    let d;
    try {
      d = o.lstatSync(f);
    } catch {}
    try {
      const h = o.lstatSync(u);
      if (d && n(h, d)) return;
    } catch (h) {
      throw ((h.message = h.message.replace("lstat", "ensureLink")), h);
    }
    const c = t.dirname(f);
    return (o.existsSync(c) || i.mkdirsSync(c), o.linkSync(u, f));
  }
  return ((Fa = { createLink: e(r), createLinkSync: s }), Fa);
}
var Sa, rc;
function $w() {
  if (rc) return Sa;
  rc = 1;
  const e = G,
    t = mt(),
    o = Lr().pathExists;
  function i(n, r, s) {
    if (e.isAbsolute(n))
      return t.lstat(n, (u) =>
        u
          ? ((u.message = u.message.replace("lstat", "ensureSymlink")), s(u))
          : s(null, { toCwd: n, toDst: n }),
      );
    {
      const u = e.dirname(r),
        f = e.join(u, n);
      return o(f, (d, c) =>
        d
          ? s(d)
          : c
            ? s(null, { toCwd: f, toDst: n })
            : t.lstat(n, (l) =>
                l
                  ? ((l.message = l.message.replace("lstat", "ensureSymlink")),
                    s(l))
                  : s(null, { toCwd: n, toDst: e.relative(u, n) }),
              ),
      );
    }
  }
  function a(n, r) {
    let s;
    if (e.isAbsolute(n)) {
      if (((s = t.existsSync(n)), !s))
        throw new Error("absolute srcpath does not exist");
      return { toCwd: n, toDst: n };
    } else {
      const u = e.dirname(r),
        f = e.join(u, n);
      if (((s = t.existsSync(f)), s)) return { toCwd: f, toDst: n };
      if (((s = t.existsSync(n)), !s))
        throw new Error("relative srcpath does not exist");
      return { toCwd: n, toDst: e.relative(u, n) };
    }
  }
  return ((Sa = { symlinkPaths: i, symlinkPathsSync: a }), Sa);
}
var _a, nc;
function jw() {
  if (nc) return _a;
  nc = 1;
  const e = mt();
  function t(i, a, n) {
    if (
      ((n = typeof a == "function" ? a : n),
      (a = typeof a == "function" ? !1 : a),
      a)
    )
      return n(null, a);
    e.lstat(i, (r, s) => {
      if (r) return n(null, "file");
      ((a = s && s.isDirectory() ? "dir" : "file"), n(null, a));
    });
  }
  function o(i, a) {
    let n;
    if (a) return a;
    try {
      n = e.lstatSync(i);
    } catch {
      return "file";
    }
    return n && n.isDirectory() ? "dir" : "file";
  }
  return ((_a = { symlinkType: t, symlinkTypeSync: o }), _a);
}
var Ta, ic;
function Ww() {
  if (ic) return Ta;
  ic = 1;
  const e = Et().fromCallback,
    t = G,
    o = an(),
    i = Ut(),
    a = i.mkdirs,
    n = i.mkdirsSync,
    r = $w(),
    s = r.symlinkPaths,
    u = r.symlinkPathsSync,
    f = jw(),
    d = f.symlinkType,
    c = f.symlinkTypeSync,
    l = Lr().pathExists,
    { areIdentical: h } = sn();
  function y(S, E, b, w) {
    ((w = typeof b == "function" ? b : w),
      (b = typeof b == "function" ? !1 : b),
      o.lstat(E, (A, v) => {
        !A && v.isSymbolicLink()
          ? Promise.all([o.stat(S), o.stat(E)]).then(([C, g]) => {
              if (h(C, g)) return w(null);
              F(S, E, b, w);
            })
          : F(S, E, b, w);
      }));
  }
  function F(S, E, b, w) {
    s(S, E, (A, v) => {
      if (A) return w(A);
      ((S = v.toDst),
        d(v.toCwd, b, (C, g) => {
          if (C) return w(C);
          const D = t.dirname(E);
          l(D, (N, P) => {
            if (N) return w(N);
            if (P) return o.symlink(S, E, g, w);
            a(D, (R) => {
              if (R) return w(R);
              o.symlink(S, E, g, w);
            });
          });
        }));
    });
  }
  function m(S, E, b) {
    let w;
    try {
      w = o.lstatSync(E);
    } catch {}
    if (w && w.isSymbolicLink()) {
      const g = o.statSync(S),
        D = o.statSync(E);
      if (h(g, D)) return;
    }
    const A = u(S, E);
    ((S = A.toDst), (b = c(A.toCwd, b)));
    const v = t.dirname(E);
    return (o.existsSync(v) || n(v), o.symlinkSync(S, E, b));
  }
  return ((Ta = { createSymlink: e(y), createSymlinkSync: m }), Ta);
}
var xa, oc;
function Hw() {
  if (oc) return xa;
  oc = 1;
  const { createFile: e, createFileSync: t } = Uw(),
    { createLink: o, createLinkSync: i } = qw(),
    { createSymlink: a, createSymlinkSync: n } = Ww();
  return (
    (xa = {
      createFile: e,
      createFileSync: t,
      ensureFile: e,
      ensureFileSync: t,
      createLink: o,
      createLinkSync: i,
      ensureLink: o,
      ensureLinkSync: i,
      createSymlink: a,
      createSymlinkSync: n,
      ensureSymlink: a,
      ensureSymlinkSync: n,
    }),
    xa
  );
}
var Na, ac;
function ou() {
  if (ac) return Na;
  ac = 1;
  function e(
    o,
    {
      EOL: i = `
`,
      finalEOL: a = !0,
      replacer: n = null,
      spaces: r,
    } = {},
  ) {
    const s = a ? i : "";
    return JSON.stringify(o, n, r).replace(/\n/g, i) + s;
  }
  function t(o) {
    return (
      Buffer.isBuffer(o) && (o = o.toString("utf8")),
      o.replace(/^\uFEFF/, "")
    );
  }
  return ((Na = { stringify: e, stripBom: t }), Na);
}
var Ia, sc;
function Gw() {
  if (sc) return Ia;
  sc = 1;
  let e;
  try {
    e = mt();
  } catch {
    e = ze;
  }
  const t = Et(),
    { stringify: o, stripBom: i } = ou();
  async function a(c, l = {}) {
    typeof l == "string" && (l = { encoding: l });
    const h = l.fs || e,
      y = "throws" in l ? l.throws : !0;
    let F = await t.fromCallback(h.readFile)(c, l);
    F = i(F);
    let m;
    try {
      m = JSON.parse(F, l ? l.reviver : null);
    } catch (S) {
      if (y) throw ((S.message = `${c}: ${S.message}`), S);
      return null;
    }
    return m;
  }
  const n = t.fromPromise(a);
  function r(c, l = {}) {
    typeof l == "string" && (l = { encoding: l });
    const h = l.fs || e,
      y = "throws" in l ? l.throws : !0;
    try {
      let F = h.readFileSync(c, l);
      return ((F = i(F)), JSON.parse(F, l.reviver));
    } catch (F) {
      if (y) throw ((F.message = `${c}: ${F.message}`), F);
      return null;
    }
  }
  async function s(c, l, h = {}) {
    const y = h.fs || e,
      F = o(l, h);
    await t.fromCallback(y.writeFile)(c, F, h);
  }
  const u = t.fromPromise(s);
  function f(c, l, h = {}) {
    const y = h.fs || e,
      F = o(l, h);
    return y.writeFileSync(c, F, h);
  }
  return (
    (Ia = { readFile: n, readFileSync: r, writeFile: u, writeFileSync: f }),
    Ia
  );
}
var Oa, uc;
function Vw() {
  if (uc) return Oa;
  uc = 1;
  const e = Gw();
  return (
    (Oa = {
      readJson: e.readFile,
      readJsonSync: e.readFileSync,
      writeJson: e.writeFile,
      writeJsonSync: e.writeFileSync,
    }),
    Oa
  );
}
var Pa, lc;
function au() {
  if (lc) return Pa;
  lc = 1;
  const e = Et().fromCallback,
    t = mt(),
    o = G,
    i = Ut(),
    a = Lr().pathExists;
  function n(s, u, f, d) {
    typeof f == "function" && ((d = f), (f = "utf8"));
    const c = o.dirname(s);
    a(c, (l, h) => {
      if (l) return d(l);
      if (h) return t.writeFile(s, u, f, d);
      i.mkdirs(c, (y) => {
        if (y) return d(y);
        t.writeFile(s, u, f, d);
      });
    });
  }
  function r(s, ...u) {
    const f = o.dirname(s);
    if (t.existsSync(f)) return t.writeFileSync(s, ...u);
    (i.mkdirsSync(f), t.writeFileSync(s, ...u));
  }
  return ((Pa = { outputFile: e(n), outputFileSync: r }), Pa);
}
var Ra, cc;
function zw() {
  if (cc) return Ra;
  cc = 1;
  const { stringify: e } = ou(),
    { outputFile: t } = au();
  async function o(i, a, n = {}) {
    const r = e(a, n);
    await t(i, r, n);
  }
  return ((Ra = o), Ra);
}
var La, fc;
function Xw() {
  if (fc) return La;
  fc = 1;
  const { stringify: e } = ou(),
    { outputFileSync: t } = au();
  function o(i, a, n) {
    const r = e(a, n);
    t(i, r, n);
  }
  return ((La = o), La);
}
var Ba, dc;
function Yw() {
  if (dc) return Ba;
  dc = 1;
  const e = Et().fromPromise,
    t = Vw();
  return (
    (t.outputJson = e(zw())),
    (t.outputJsonSync = Xw()),
    (t.outputJSON = t.outputJson),
    (t.outputJSONSync = t.outputJsonSync),
    (t.writeJSON = t.writeJson),
    (t.writeJSONSync = t.writeJsonSync),
    (t.readJSON = t.readJson),
    (t.readJSONSync = t.readJsonSync),
    (Ba = t),
    Ba
  );
}
var ka, hc;
function Kw() {
  if (hc) return ka;
  hc = 1;
  const e = mt(),
    t = G,
    o = iu().copy,
    i = Wo().remove,
    a = Ut().mkdirp,
    n = Lr().pathExists,
    r = sn();
  function s(l, h, y, F) {
    (typeof y == "function" && ((F = y), (y = {})), (y = y || {}));
    const m = y.overwrite || y.clobber || !1;
    r.checkPaths(l, h, "move", y, (S, E) => {
      if (S) return F(S);
      const { srcStat: b, isChangingCase: w = !1 } = E;
      r.checkParentPaths(l, b, h, "move", (A) => {
        if (A) return F(A);
        if (u(h)) return f(l, h, m, w, F);
        a(t.dirname(h), (v) => (v ? F(v) : f(l, h, m, w, F)));
      });
    });
  }
  function u(l) {
    const h = t.dirname(l);
    return t.parse(h).root === h;
  }
  function f(l, h, y, F, m) {
    if (F) return d(l, h, y, m);
    if (y) return i(h, (S) => (S ? m(S) : d(l, h, y, m)));
    n(h, (S, E) =>
      S ? m(S) : E ? m(new Error("dest already exists.")) : d(l, h, y, m),
    );
  }
  function d(l, h, y, F) {
    e.rename(l, h, (m) =>
      m ? (m.code !== "EXDEV" ? F(m) : c(l, h, y, F)) : F(),
    );
  }
  function c(l, h, y, F) {
    o(l, h, { overwrite: y, errorOnExist: !0 }, (S) => (S ? F(S) : i(l, F)));
  }
  return ((ka = s), ka);
}
var Ma, pc;
function Jw() {
  if (pc) return Ma;
  pc = 1;
  const e = mt(),
    t = G,
    o = iu().copySync,
    i = Wo().removeSync,
    a = Ut().mkdirpSync,
    n = sn();
  function r(c, l, h) {
    h = h || {};
    const y = h.overwrite || h.clobber || !1,
      { srcStat: F, isChangingCase: m = !1 } = n.checkPathsSync(
        c,
        l,
        "move",
        h,
      );
    return (
      n.checkParentPathsSync(c, F, l, "move"),
      s(l) || a(t.dirname(l)),
      u(c, l, y, m)
    );
  }
  function s(c) {
    const l = t.dirname(c);
    return t.parse(l).root === l;
  }
  function u(c, l, h, y) {
    if (y) return f(c, l, h);
    if (h) return (i(l), f(c, l, h));
    if (e.existsSync(l)) throw new Error("dest already exists.");
    return f(c, l, h);
  }
  function f(c, l, h) {
    try {
      e.renameSync(c, l);
    } catch (y) {
      if (y.code !== "EXDEV") throw y;
      return d(c, l, h);
    }
  }
  function d(c, l, h) {
    return (o(c, l, { overwrite: h, errorOnExist: !0 }), i(c));
  }
  return ((Ma = r), Ma);
}
var Ua, Dc;
function Qw() {
  if (Dc) return Ua;
  Dc = 1;
  const e = Et().fromCallback;
  return ((Ua = { move: e(Kw()), moveSync: Jw() }), Ua);
}
var qa, mc;
function Dr() {
  return (
    mc ||
      ((mc = 1),
      (qa = {
        ...an(),
        ...iu(),
        ...Mw(),
        ...Hw(),
        ...Yw(),
        ...Ut(),
        ...Qw(),
        ...au(),
        ...Lr(),
        ...Wo(),
      })),
    qa
  );
}
var Dn = {},
  Ar = {},
  $a = {},
  br = {},
  gc;
function su() {
  if (gc) return br;
  ((gc = 1),
    Object.defineProperty(br, "__esModule", { value: !0 }),
    (br.CancellationError = br.CancellationToken = void 0));
  const e = Zs;
  let t = class extends e.EventEmitter {
    get cancelled() {
      return (
        this._cancelled || (this._parent != null && this._parent.cancelled)
      );
    }
    set parent(a) {
      (this.removeParentCancelHandler(),
        (this._parent = a),
        (this.parentCancelHandler = () => this.cancel()),
        this._parent.onCancel(this.parentCancelHandler));
    }
    constructor(a) {
      (super(),
        (this.parentCancelHandler = null),
        (this._parent = null),
        (this._cancelled = !1),
        a != null && (this.parent = a));
    }
    cancel() {
      ((this._cancelled = !0), this.emit("cancel"));
    }
    onCancel(a) {
      this.cancelled ? a() : this.once("cancel", a);
    }
    createPromise(a) {
      if (this.cancelled) return Promise.reject(new o());
      const n = () => {
        if (r != null)
          try {
            (this.removeListener("cancel", r), (r = null));
          } catch {}
      };
      let r = null;
      return new Promise((s, u) => {
        let f = null;
        if (
          ((r = () => {
            try {
              f != null && (f(), (f = null));
            } finally {
              u(new o());
            }
          }),
          this.cancelled)
        ) {
          r();
          return;
        }
        (this.onCancel(r),
          a(s, u, (d) => {
            f = d;
          }));
      })
        .then((s) => (n(), s))
        .catch((s) => {
          throw (n(), s);
        });
    }
    removeParentCancelHandler() {
      const a = this._parent;
      a != null &&
        this.parentCancelHandler != null &&
        (a.removeListener("cancel", this.parentCancelHandler),
        (this.parentCancelHandler = null));
    }
    dispose() {
      try {
        this.removeParentCancelHandler();
      } finally {
        (this.removeAllListeners(), (this._parent = null));
      }
    }
  };
  br.CancellationToken = t;
  class o extends Error {
    constructor() {
      super("cancelled");
    }
  }
  return ((br.CancellationError = o), br);
}
var _i = {},
  wc;
function Ho() {
  if (wc) return _i;
  ((wc = 1),
    Object.defineProperty(_i, "__esModule", { value: !0 }),
    (_i.newError = e));
  function e(t, o) {
    const i = new Error(t);
    return ((i.code = o), i);
  }
  return _i;
}
var ot = {},
  Ti = { exports: {} },
  xi = { exports: {} },
  ja,
  yc;
function Zw() {
  if (yc) return ja;
  yc = 1;
  var e = 1e3,
    t = e * 60,
    o = t * 60,
    i = o * 24,
    a = i * 7,
    n = i * 365.25;
  ja = function (d, c) {
    c = c || {};
    var l = typeof d;
    if (l === "string" && d.length > 0) return r(d);
    if (l === "number" && isFinite(d)) return c.long ? u(d) : s(d);
    throw new Error(
      "val is not a non-empty string or a valid number. val=" +
        JSON.stringify(d),
    );
  };
  function r(d) {
    if (((d = String(d)), !(d.length > 100))) {
      var c =
        /^(-?(?:\d+)?\.?\d+) *(milliseconds?|msecs?|ms|seconds?|secs?|s|minutes?|mins?|m|hours?|hrs?|h|days?|d|weeks?|w|years?|yrs?|y)?$/i.exec(
          d,
        );
      if (c) {
        var l = parseFloat(c[1]),
          h = (c[2] || "ms").toLowerCase();
        switch (h) {
          case "years":
          case "year":
          case "yrs":
          case "yr":
          case "y":
            return l * n;
          case "weeks":
          case "week":
          case "w":
            return l * a;
          case "days":
          case "day":
          case "d":
            return l * i;
          case "hours":
          case "hour":
          case "hrs":
          case "hr":
          case "h":
            return l * o;
          case "minutes":
          case "minute":
          case "mins":
          case "min":
          case "m":
            return l * t;
          case "seconds":
          case "second":
          case "secs":
          case "sec":
          case "s":
            return l * e;
          case "milliseconds":
          case "millisecond":
          case "msecs":
          case "msec":
          case "ms":
            return l;
          default:
            return;
        }
      }
    }
  }
  function s(d) {
    var c = Math.abs(d);
    return c >= i
      ? Math.round(d / i) + "d"
      : c >= o
        ? Math.round(d / o) + "h"
        : c >= t
          ? Math.round(d / t) + "m"
          : c >= e
            ? Math.round(d / e) + "s"
            : d + "ms";
  }
  function u(d) {
    var c = Math.abs(d);
    return c >= i
      ? f(d, c, i, "day")
      : c >= o
        ? f(d, c, o, "hour")
        : c >= t
          ? f(d, c, t, "minute")
          : c >= e
            ? f(d, c, e, "second")
            : d + " ms";
  }
  function f(d, c, l, h) {
    var y = c >= l * 1.5;
    return Math.round(d / l) + " " + h + (y ? "s" : "");
  }
  return ja;
}
var Wa, Ec;
function ap() {
  if (Ec) return Wa;
  Ec = 1;
  function e(t) {
    ((i.debug = i),
      (i.default = i),
      (i.coerce = f),
      (i.disable = r),
      (i.enable = n),
      (i.enabled = s),
      (i.humanize = Zw()),
      (i.destroy = d),
      Object.keys(t).forEach((c) => {
        i[c] = t[c];
      }),
      (i.names = []),
      (i.skips = []),
      (i.formatters = {}));
    function o(c) {
      let l = 0;
      for (let h = 0; h < c.length; h++)
        ((l = (l << 5) - l + c.charCodeAt(h)), (l |= 0));
      return i.colors[Math.abs(l) % i.colors.length];
    }
    i.selectColor = o;
    function i(c) {
      let l,
        h = null,
        y,
        F;
      function m(...S) {
        if (!m.enabled) return;
        const E = m,
          b = Number(new Date()),
          w = b - (l || b);
        ((E.diff = w),
          (E.prev = l),
          (E.curr = b),
          (l = b),
          (S[0] = i.coerce(S[0])),
          typeof S[0] != "string" && S.unshift("%O"));
        let A = 0;
        ((S[0] = S[0].replace(/%([a-zA-Z%])/g, (C, g) => {
          if (C === "%%") return "%";
          A++;
          const D = i.formatters[g];
          if (typeof D == "function") {
            const N = S[A];
            ((C = D.call(E, N)), S.splice(A, 1), A--);
          }
          return C;
        })),
          i.formatArgs.call(E, S),
          (E.log || i.log).apply(E, S));
      }
      return (
        (m.namespace = c),
        (m.useColors = i.useColors()),
        (m.color = i.selectColor(c)),
        (m.extend = a),
        (m.destroy = i.destroy),
        Object.defineProperty(m, "enabled", {
          enumerable: !0,
          configurable: !1,
          get: () =>
            h !== null
              ? h
              : (y !== i.namespaces && ((y = i.namespaces), (F = i.enabled(c))),
                F),
          set: (S) => {
            h = S;
          },
        }),
        typeof i.init == "function" && i.init(m),
        m
      );
    }
    function a(c, l) {
      const h = i(this.namespace + (typeof l > "u" ? ":" : l) + c);
      return ((h.log = this.log), h);
    }
    function n(c) {
      (i.save(c), (i.namespaces = c), (i.names = []), (i.skips = []));
      let l;
      const h = (typeof c == "string" ? c : "").split(/[\s,]+/),
        y = h.length;
      for (l = 0; l < y; l++)
        h[l] &&
          ((c = h[l].replace(/\*/g, ".*?")),
          c[0] === "-"
            ? i.skips.push(new RegExp("^" + c.slice(1) + "$"))
            : i.names.push(new RegExp("^" + c + "$")));
    }
    function r() {
      const c = [...i.names.map(u), ...i.skips.map(u).map((l) => "-" + l)].join(
        ",",
      );
      return (i.enable(""), c);
    }
    function s(c) {
      if (c[c.length - 1] === "*") return !0;
      let l, h;
      for (l = 0, h = i.skips.length; l < h; l++)
        if (i.skips[l].test(c)) return !1;
      for (l = 0, h = i.names.length; l < h; l++)
        if (i.names[l].test(c)) return !0;
      return !1;
    }
    function u(c) {
      return c
        .toString()
        .substring(2, c.toString().length - 2)
        .replace(/\.\*\?$/, "*");
    }
    function f(c) {
      return c instanceof Error ? c.stack || c.message : c;
    }
    function d() {
      console.warn(
        "Instance method `debug.destroy()` is deprecated and no longer does anything. It will be removed in the next major version of `debug`.",
      );
    }
    return (i.enable(i.load()), i);
  }
  return ((Wa = e), Wa);
}
var vc;
function e2() {
  return (
    vc ||
      ((vc = 1),
      (function (e, t) {
        ((t.formatArgs = i),
          (t.save = a),
          (t.load = n),
          (t.useColors = o),
          (t.storage = r()),
          (t.destroy = (() => {
            let u = !1;
            return () => {
              u ||
                ((u = !0),
                console.warn(
                  "Instance method `debug.destroy()` is deprecated and no longer does anything. It will be removed in the next major version of `debug`.",
                ));
            };
          })()),
          (t.colors = [
            "#0000CC",
            "#0000FF",
            "#0033CC",
            "#0033FF",
            "#0066CC",
            "#0066FF",
            "#0099CC",
            "#0099FF",
            "#00CC00",
            "#00CC33",
            "#00CC66",
            "#00CC99",
            "#00CCCC",
            "#00CCFF",
            "#3300CC",
            "#3300FF",
            "#3333CC",
            "#3333FF",
            "#3366CC",
            "#3366FF",
            "#3399CC",
            "#3399FF",
            "#33CC00",
            "#33CC33",
            "#33CC66",
            "#33CC99",
            "#33CCCC",
            "#33CCFF",
            "#6600CC",
            "#6600FF",
            "#6633CC",
            "#6633FF",
            "#66CC00",
            "#66CC33",
            "#9900CC",
            "#9900FF",
            "#9933CC",
            "#9933FF",
            "#99CC00",
            "#99CC33",
            "#CC0000",
            "#CC0033",
            "#CC0066",
            "#CC0099",
            "#CC00CC",
            "#CC00FF",
            "#CC3300",
            "#CC3333",
            "#CC3366",
            "#CC3399",
            "#CC33CC",
            "#CC33FF",
            "#CC6600",
            "#CC6633",
            "#CC9900",
            "#CC9933",
            "#CCCC00",
            "#CCCC33",
            "#FF0000",
            "#FF0033",
            "#FF0066",
            "#FF0099",
            "#FF00CC",
            "#FF00FF",
            "#FF3300",
            "#FF3333",
            "#FF3366",
            "#FF3399",
            "#FF33CC",
            "#FF33FF",
            "#FF6600",
            "#FF6633",
            "#FF9900",
            "#FF9933",
            "#FFCC00",
            "#FFCC33",
          ]));
        function o() {
          if (
            typeof window < "u" &&
            window.process &&
            (window.process.type === "renderer" || window.process.__nwjs)
          )
            return !0;
          if (
            typeof navigator < "u" &&
            navigator.userAgent &&
            navigator.userAgent.toLowerCase().match(/(edge|trident)\/(\d+)/)
          )
            return !1;
          let u;
          return (
            (typeof document < "u" &&
              document.documentElement &&
              document.documentElement.style &&
              document.documentElement.style.WebkitAppearance) ||
            (typeof window < "u" &&
              window.console &&
              (window.console.firebug ||
                (window.console.exception && window.console.table))) ||
            (typeof navigator < "u" &&
              navigator.userAgent &&
              (u = navigator.userAgent.toLowerCase().match(/firefox\/(\d+)/)) &&
              parseInt(u[1], 10) >= 31) ||
            (typeof navigator < "u" &&
              navigator.userAgent &&
              navigator.userAgent.toLowerCase().match(/applewebkit\/(\d+)/))
          );
        }
        function i(u) {
          if (
            ((u[0] =
              (this.useColors ? "%c" : "") +
              this.namespace +
              (this.useColors ? " %c" : " ") +
              u[0] +
              (this.useColors ? "%c " : " ") +
              "+" +
              e.exports.humanize(this.diff)),
            !this.useColors)
          )
            return;
          const f = "color: " + this.color;
          u.splice(1, 0, f, "color: inherit");
          let d = 0,
            c = 0;
          (u[0].replace(/%[a-zA-Z%]/g, (l) => {
            l !== "%%" && (d++, l === "%c" && (c = d));
          }),
            u.splice(c, 0, f));
        }
        t.log = console.debug || console.log || (() => {});
        function a(u) {
          try {
            u ? t.storage.setItem("debug", u) : t.storage.removeItem("debug");
          } catch {}
        }
        function n() {
          let u;
          try {
            u = t.storage.getItem("debug");
          } catch {}
          return (
            !u &&
              typeof process < "u" &&
              "env" in process &&
              (u = process.env.DEBUG),
            u
          );
        }
        function r() {
          try {
            return localStorage;
          } catch {}
        }
        e.exports = ap()(t);
        const { formatters: s } = e.exports;
        s.j = function (u) {
          try {
            return JSON.stringify(u);
          } catch (f) {
            return "[UnexpectedJSONParseError]: " + f.message;
          }
        };
      })(xi, xi.exports)),
    xi.exports
  );
}
var Ni = { exports: {} },
  Cc;
function t2() {
  return (
    Cc ||
      ((Cc = 1),
      (function (e, t) {
        const o = r0,
          i = on;
        ((t.init = d),
          (t.log = s),
          (t.formatArgs = n),
          (t.save = u),
          (t.load = f),
          (t.useColors = a),
          (t.destroy = i.deprecate(
            () => {},
            "Instance method `debug.destroy()` is deprecated and no longer does anything. It will be removed in the next major version of `debug`.",
          )),
          (t.colors = [6, 2, 3, 4, 5, 1]));
        try {
          const l = Bm();
          l &&
            (l.stderr || l).level >= 2 &&
            (t.colors = [
              20, 21, 26, 27, 32, 33, 38, 39, 40, 41, 42, 43, 44, 45, 56, 57,
              62, 63, 68, 69, 74, 75, 76, 77, 78, 79, 80, 81, 92, 93, 98, 99,
              112, 113, 128, 129, 134, 135, 148, 149, 160, 161, 162, 163, 164,
              165, 166, 167, 168, 169, 170, 171, 172, 173, 178, 179, 184, 185,
              196, 197, 198, 199, 200, 201, 202, 203, 204, 205, 206, 207, 208,
              209, 214, 215, 220, 221,
            ]);
        } catch {}
        t.inspectOpts = Object.keys(process.env)
          .filter((l) => /^debug_/i.test(l))
          .reduce((l, h) => {
            const y = h
              .substring(6)
              .toLowerCase()
              .replace(/_([a-z])/g, (m, S) => S.toUpperCase());
            let F = process.env[h];
            return (
              /^(yes|on|true|enabled)$/i.test(F)
                ? (F = !0)
                : /^(no|off|false|disabled)$/i.test(F)
                  ? (F = !1)
                  : F === "null"
                    ? (F = null)
                    : (F = Number(F)),
              (l[y] = F),
              l
            );
          }, {});
        function a() {
          return "colors" in t.inspectOpts
            ? !!t.inspectOpts.colors
            : o.isatty(process.stderr.fd);
        }
        function n(l) {
          const { namespace: h, useColors: y } = this;
          if (y) {
            const F = this.color,
              m = "\x1B[3" + (F < 8 ? F : "8;5;" + F),
              S = `  ${m};1m${h} \x1B[0m`;
            ((l[0] =
              S +
              l[0]
                .split(
                  `
`,
                )
                .join(
                  `
` + S,
                )),
              l.push(m + "m+" + e.exports.humanize(this.diff) + "\x1B[0m"));
          } else l[0] = r() + h + " " + l[0];
        }
        function r() {
          return t.inspectOpts.hideDate ? "" : new Date().toISOString() + " ";
        }
        function s(...l) {
          return process.stderr.write(
            i.formatWithOptions(t.inspectOpts, ...l) +
              `
`,
          );
        }
        function u(l) {
          l ? (process.env.DEBUG = l) : delete process.env.DEBUG;
        }
        function f() {
          return process.env.DEBUG;
        }
        function d(l) {
          l.inspectOpts = {};
          const h = Object.keys(t.inspectOpts);
          for (let y = 0; y < h.length; y++)
            l.inspectOpts[h[y]] = t.inspectOpts[h[y]];
        }
        e.exports = ap()(t);
        const { formatters: c } = e.exports;
        ((c.o = function (l) {
          return (
            (this.inspectOpts.colors = this.useColors),
            i
              .inspect(l, this.inspectOpts)
              .split(
                `
`,
              )
              .map((h) => h.trim())
              .join(" ")
          );
        }),
          (c.O = function (l) {
            return (
              (this.inspectOpts.colors = this.useColors),
              i.inspect(l, this.inspectOpts)
            );
          }));
      })(Ni, Ni.exports)),
    Ni.exports
  );
}
var Ac;
function r2() {
  return (
    Ac ||
      ((Ac = 1),
      typeof process > "u" ||
      process.type === "renderer" ||
      process.browser === !0 ||
      process.__nwjs
        ? (Ti.exports = e2())
        : (Ti.exports = t2())),
    Ti.exports
  );
}
var mn = {},
  bc;
function sp() {
  if (bc) return mn;
  ((bc = 1),
    Object.defineProperty(mn, "__esModule", { value: !0 }),
    (mn.ProgressCallbackTransform = void 0));
  const e = ii;
  let t = class extends e.Transform {
    constructor(i, a, n) {
      (super(),
        (this.total = i),
        (this.cancellationToken = a),
        (this.onProgress = n),
        (this.start = Date.now()),
        (this.transferred = 0),
        (this.delta = 0),
        (this.nextUpdate = this.start + 1e3));
    }
    _transform(i, a, n) {
      if (this.cancellationToken.cancelled) {
        n(new Error("cancelled"), null);
        return;
      }
      ((this.transferred += i.length), (this.delta += i.length));
      const r = Date.now();
      (r >= this.nextUpdate &&
        this.transferred !== this.total &&
        ((this.nextUpdate = r + 1e3),
        this.onProgress({
          total: this.total,
          delta: this.delta,
          transferred: this.transferred,
          percent: (this.transferred / this.total) * 100,
          bytesPerSecond: Math.round(
            this.transferred / ((r - this.start) / 1e3),
          ),
        }),
        (this.delta = 0)),
        n(null, i));
    }
    _flush(i) {
      if (this.cancellationToken.cancelled) {
        i(new Error("cancelled"));
        return;
      }
      (this.onProgress({
        total: this.total,
        delta: this.delta,
        transferred: this.total,
        percent: 100,
        bytesPerSecond: Math.round(
          this.transferred / ((Date.now() - this.start) / 1e3),
        ),
      }),
        (this.delta = 0),
        i(null));
    }
  };
  return ((mn.ProgressCallbackTransform = t), mn);
}
var Fc;
function n2() {
  if (Fc) return ot;
  ((Fc = 1),
    Object.defineProperty(ot, "__esModule", { value: !0 }),
    (ot.DigestTransform = ot.HttpExecutor = ot.HttpError = void 0),
    (ot.createHttpError = f),
    (ot.parseJson = l),
    (ot.configureRequestOptionsFromUrl = y),
    (ot.configureRequestUrl = F),
    (ot.safeGetHeader = E),
    (ot.configureRequestOptions = w),
    (ot.safeStringifyJson = A));
  const e = xt,
    t = r2(),
    o = ze,
    i = ii,
    a = Mt,
    n = su(),
    r = Ho(),
    s = sp(),
    u = (0, t.default)("electron-builder");
  function f(v, C = null) {
    return new c(
      v.statusCode || -1,
      `${v.statusCode} ${v.statusMessage}` +
        (C == null
          ? ""
          : `
` + JSON.stringify(C, null, "  ")) +
        `
Headers: ` +
        A(v.headers),
      C,
    );
  }
  const d = new Map([
    [429, "Too many requests"],
    [400, "Bad request"],
    [403, "Forbidden"],
    [404, "Not found"],
    [405, "Method not allowed"],
    [406, "Not acceptable"],
    [408, "Request timeout"],
    [413, "Request entity too large"],
    [500, "Internal server error"],
    [502, "Bad gateway"],
    [503, "Service unavailable"],
    [504, "Gateway timeout"],
    [505, "HTTP version not supported"],
  ]);
  class c extends Error {
    constructor(C, g = `HTTP error: ${d.get(C) || C}`, D = null) {
      (super(g),
        (this.statusCode = C),
        (this.description = D),
        (this.name = "HttpError"),
        (this.code = `HTTP_ERROR_${C}`));
    }
    isServerError() {
      return this.statusCode >= 500 && this.statusCode <= 599;
    }
  }
  ot.HttpError = c;
  function l(v) {
    return v.then((C) => (C == null || C.length === 0 ? null : JSON.parse(C)));
  }
  class h {
    constructor() {
      this.maxRedirects = 10;
    }
    request(C, g = new n.CancellationToken(), D) {
      w(C);
      const N = D == null ? void 0 : JSON.stringify(D),
        P = N ? Buffer.from(N) : void 0;
      if (P != null) {
        u(N);
        const { headers: R, ...k } = C;
        C = {
          method: "post",
          headers: {
            "Content-Type": "application/json",
            "Content-Length": P.length,
            ...R,
          },
          ...k,
        };
      }
      return this.doApiRequest(C, g, (R) => R.end(P));
    }
    doApiRequest(C, g, D, N = 0) {
      return (
        u.enabled && u(`Request: ${A(C)}`),
        g.createPromise((P, R, k) => {
          const q = this.createRequest(C, (U) => {
            try {
              this.handleResponse(U, C, g, P, R, N, D);
            } catch ($) {
              R($);
            }
          });
          (this.addErrorAndTimeoutHandlers(q, R, C.timeout),
            this.addRedirectHandlers(q, C, R, N, (U) => {
              this.doApiRequest(U, g, D, N).then(P).catch(R);
            }),
            D(q, R),
            k(() => q.abort()));
        })
      );
    }
    addRedirectHandlers(C, g, D, N, P) {}
    addErrorAndTimeoutHandlers(C, g, D = 60 * 1e3) {
      (this.addTimeOutHandler(C, g, D),
        C.on("error", g),
        C.on("aborted", () => {
          g(new Error("Request has been aborted by the server"));
        }));
    }
    handleResponse(C, g, D, N, P, R, k) {
      var q;
      if (
        (u.enabled &&
          u(
            `Response: ${C.statusCode} ${C.statusMessage}, request options: ${A(g)}`,
          ),
        C.statusCode === 404)
      ) {
        P(
          f(
            C,
            `method: ${g.method || "GET"} url: ${g.protocol || "https:"}//${g.hostname}${g.port ? `:${g.port}` : ""}${g.path}

Please double check that your authentication token is correct. Due to security reasons, actual status maybe not reported, but 404.
`,
          ),
        );
        return;
      } else if (C.statusCode === 204) {
        N();
        return;
      }
      const U = (q = C.statusCode) !== null && q !== void 0 ? q : 0,
        $ = U >= 300 && U < 400,
        V = E(C, "location");
      if ($ && V != null) {
        if (R > this.maxRedirects) {
          P(this.createMaxRedirectError());
          return;
        }
        this.doApiRequest(h.prepareRedirectUrlOptions(V, g), D, k, R)
          .then(N)
          .catch(P);
        return;
      }
      C.setEncoding("utf8");
      let re = "";
      (C.on("error", P),
        C.on("data", (X) => (re += X)),
        C.on("end", () => {
          try {
            if (C.statusCode != null && C.statusCode >= 400) {
              const X = E(C, "content-type"),
                fe =
                  X != null &&
                  (Array.isArray(X)
                    ? X.find((Y) => Y.includes("json")) != null
                    : X.includes("json"));
              P(
                f(
                  C,
                  `method: ${g.method || "GET"} url: ${g.protocol || "https:"}//${g.hostname}${g.port ? `:${g.port}` : ""}${g.path}

          Data:
          ${fe ? JSON.stringify(JSON.parse(re)) : re}
          `,
                ),
              );
            } else N(re.length === 0 ? null : re);
          } catch (X) {
            P(X);
          }
        }));
    }
    async downloadToBuffer(C, g) {
      return await g.cancellationToken.createPromise((D, N, P) => {
        const R = [],
          k = { headers: g.headers || void 0, redirect: "manual" };
        (F(C, k),
          w(k),
          this.doDownload(
            k,
            {
              destination: null,
              options: g,
              onCancel: P,
              callback: (q) => {
                q == null ? D(Buffer.concat(R)) : N(q);
              },
              responseHandler: (q, U) => {
                let $ = 0;
                (q.on("data", (V) => {
                  if ((($ += V.length), $ > 524288e3)) {
                    U(new Error("Maximum allowed size is 500 MB"));
                    return;
                  }
                  R.push(V);
                }),
                  q.on("end", () => {
                    U(null);
                  }));
              },
            },
            0,
          ));
      });
    }
    doDownload(C, g, D) {
      const N = this.createRequest(C, (P) => {
        if (P.statusCode >= 400) {
          g.callback(
            new Error(
              `Cannot download "${C.protocol || "https:"}//${C.hostname}${C.path}", status ${P.statusCode}: ${P.statusMessage}`,
            ),
          );
          return;
        }
        P.on("error", g.callback);
        const R = E(P, "location");
        if (R != null) {
          D < this.maxRedirects
            ? this.doDownload(h.prepareRedirectUrlOptions(R, C), g, D++)
            : g.callback(this.createMaxRedirectError());
          return;
        }
        g.responseHandler == null ? b(g, P) : g.responseHandler(P, g.callback);
      });
      (this.addErrorAndTimeoutHandlers(N, g.callback, C.timeout),
        this.addRedirectHandlers(N, C, g.callback, D, (P) => {
          this.doDownload(P, g, D++);
        }),
        N.end());
    }
    createMaxRedirectError() {
      return new Error(`Too many redirects (> ${this.maxRedirects})`);
    }
    addTimeOutHandler(C, g, D) {
      C.on("socket", (N) => {
        N.setTimeout(D, () => {
          (C.abort(), g(new Error("Request timed out")));
        });
      });
    }
    static prepareRedirectUrlOptions(C, g) {
      const D = y(C, { ...g }),
        N = D.headers;
      if (N?.authorization) {
        const P = new a.URL(C);
        (P.hostname.endsWith(".amazonaws.com") ||
          P.searchParams.has("X-Amz-Credential")) &&
          delete N.authorization;
      }
      return D;
    }
    static retryOnServerError(C, g = 3) {
      for (let D = 0; ; D++)
        try {
          return C();
        } catch (N) {
          if (
            D < g &&
            ((N instanceof c && N.isServerError()) || N.code === "EPIPE")
          )
            continue;
          throw N;
        }
    }
  }
  ot.HttpExecutor = h;
  function y(v, C) {
    const g = w(C);
    return (F(new a.URL(v), g), g);
  }
  function F(v, C) {
    ((C.protocol = v.protocol),
      (C.hostname = v.hostname),
      v.port ? (C.port = v.port) : C.port && delete C.port,
      (C.path = v.pathname + v.search));
  }
  class m extends i.Transform {
    get actual() {
      return this._actual;
    }
    constructor(C, g = "sha512", D = "base64") {
      (super(),
        (this.expected = C),
        (this.algorithm = g),
        (this.encoding = D),
        (this._actual = null),
        (this.isValidateOnEnd = !0),
        (this.digester = (0, e.createHash)(g)));
    }
    _transform(C, g, D) {
      (this.digester.update(C), D(null, C));
    }
    _flush(C) {
      if (
        ((this._actual = this.digester.digest(this.encoding)),
        this.isValidateOnEnd)
      )
        try {
          this.validate();
        } catch (g) {
          C(g);
          return;
        }
      C(null);
    }
    validate() {
      if (this._actual == null)
        throw (0, r.newError)("Not finished yet", "ERR_STREAM_NOT_FINISHED");
      if (this._actual !== this.expected)
        throw (0, r.newError)(
          `${this.algorithm} checksum mismatch, expected ${this.expected}, got ${this._actual}`,
          "ERR_CHECKSUM_MISMATCH",
        );
      return null;
    }
  }
  ot.DigestTransform = m;
  function S(v, C, g) {
    return v != null && C != null && v !== C
      ? (g(
          new Error(
            `checksum mismatch: expected ${C} but got ${v} (X-Checksum-Sha2 header)`,
          ),
        ),
        !1)
      : !0;
  }
  function E(v, C) {
    const g = v.headers[C];
    return g == null
      ? null
      : Array.isArray(g)
        ? g.length === 0
          ? null
          : g[g.length - 1]
        : g;
  }
  function b(v, C) {
    if (!S(E(C, "X-Checksum-Sha2"), v.options.sha2, v.callback)) return;
    const g = [];
    if (v.options.onProgress != null) {
      const R = E(C, "content-length");
      R != null &&
        g.push(
          new s.ProgressCallbackTransform(
            parseInt(R, 10),
            v.options.cancellationToken,
            v.options.onProgress,
          ),
        );
    }
    const D = v.options.sha512;
    D != null
      ? g.push(
          new m(
            D,
            "sha512",
            D.length === 128 &&
              !D.includes("+") &&
              !D.includes("Z") &&
              !D.includes("=")
              ? "hex"
              : "base64",
          ),
        )
      : v.options.sha2 != null &&
        g.push(new m(v.options.sha2, "sha256", "hex"));
    const N = (0, o.createWriteStream)(v.destination);
    g.push(N);
    let P = C;
    for (const R of g)
      (R.on("error", (k) => {
        (N.close(), v.options.cancellationToken.cancelled || v.callback(k));
      }),
        (P = P.pipe(R)));
    N.on("finish", () => {
      N.close(v.callback);
    });
  }
  function w(v, C, g) {
    (g != null && (v.method = g), (v.headers = { ...v.headers }));
    const D = v.headers;
    return (
      C != null &&
        (D.authorization =
          C.startsWith("Basic") || C.startsWith("Bearer") ? C : `token ${C}`),
      D["User-Agent"] == null && (D["User-Agent"] = "electron-builder"),
      (g == null || g === "GET" || D["Cache-Control"] == null) &&
        (D["Cache-Control"] = "no-cache"),
      v.protocol == null &&
        process.versions.electron != null &&
        (v.protocol = "https:"),
      v
    );
  }
  function A(v, C) {
    return JSON.stringify(
      v,
      (g, D) =>
        g.endsWith("Authorization") ||
        g.endsWith("authorization") ||
        g.endsWith("Password") ||
        g.endsWith("PASSWORD") ||
        g.endsWith("Token") ||
        g.includes("password") ||
        g.includes("token") ||
        (C != null && C.has(g))
          ? "<stripped sensitive data>"
          : D,
      2,
    );
  }
  return ot;
}
var gn = {},
  Sc;
function i2() {
  if (Sc) return gn;
  ((Sc = 1),
    Object.defineProperty(gn, "__esModule", { value: !0 }),
    (gn.MemoLazy = void 0));
  let e = class {
    constructor(i, a) {
      ((this.selector = i),
        (this.creator = a),
        (this.selected = void 0),
        (this._value = void 0));
    }
    get hasValue() {
      return this._value !== void 0;
    }
    get value() {
      const i = this.selector();
      if (this._value !== void 0 && t(this.selected, i)) return this._value;
      this.selected = i;
      const a = this.creator(i);
      return ((this.value = a), a);
    }
    set value(i) {
      this._value = i;
    }
  };
  gn.MemoLazy = e;
  function t(o, i) {
    if (
      typeof o == "object" &&
      o !== null &&
      typeof i == "object" &&
      i !== null
    ) {
      const r = Object.keys(o),
        s = Object.keys(i);
      return r.length === s.length && r.every((u) => t(o[u], i[u]));
    }
    return o === i;
  }
  return gn;
}
var wn = {},
  _c;
function o2() {
  if (_c) return wn;
  ((_c = 1),
    Object.defineProperty(wn, "__esModule", { value: !0 }),
    (wn.githubUrl = e),
    (wn.getS3LikeProviderBaseUrl = t));
  function e(n, r = "github.com") {
    return `${n.protocol || "https"}://${n.host || r}`;
  }
  function t(n) {
    const r = n.provider;
    if (r === "s3") return o(n);
    if (r === "spaces") return a(n);
    throw new Error(`Not supported provider: ${r}`);
  }
  function o(n) {
    let r;
    if (n.accelerate == !0)
      r = `https://${n.bucket}.s3-accelerate.amazonaws.com`;
    else if (n.endpoint != null) r = `${n.endpoint}/${n.bucket}`;
    else if (n.bucket.includes(".")) {
      if (n.region == null)
        throw new Error(
          `Bucket name "${n.bucket}" includes a dot, but S3 region is missing`,
        );
      n.region === "us-east-1"
        ? (r = `https://s3.amazonaws.com/${n.bucket}`)
        : (r = `https://s3-${n.region}.amazonaws.com/${n.bucket}`);
    } else
      n.region === "cn-north-1"
        ? (r = `https://${n.bucket}.s3.${n.region}.amazonaws.com.cn`)
        : (r = `https://${n.bucket}.s3.amazonaws.com`);
    return i(r, n.path);
  }
  function i(n, r) {
    return (
      r != null && r.length > 0 && (r.startsWith("/") || (n += "/"), (n += r)),
      n
    );
  }
  function a(n) {
    if (n.name == null) throw new Error("name is missing");
    if (n.region == null) throw new Error("region is missing");
    return i(`https://${n.name}.${n.region}.digitaloceanspaces.com`, n.path);
  }
  return wn;
}
var Ii = {},
  Tc;
function a2() {
  if (Tc) return Ii;
  ((Tc = 1),
    Object.defineProperty(Ii, "__esModule", { value: !0 }),
    (Ii.retry = t));
  const e = su();
  async function t(o, i, a, n = 0, r = 0, s) {
    var u;
    const f = new e.CancellationToken();
    try {
      return await o();
    } catch (d) {
      if (
        (!((u = s?.(d)) !== null && u !== void 0) || u) &&
        i > 0 &&
        !f.cancelled
      )
        return (
          await new Promise((c) => setTimeout(c, a + n * r)),
          await t(o, i - 1, a, n, r + 1, s)
        );
      throw d;
    }
  }
  return Ii;
}
var Oi = {},
  xc;
function s2() {
  if (xc) return Oi;
  ((xc = 1),
    Object.defineProperty(Oi, "__esModule", { value: !0 }),
    (Oi.parseDn = e));
  function e(t) {
    let o = !1,
      i = null,
      a = "",
      n = 0;
    t = t.trim();
    const r = new Map();
    for (let s = 0; s <= t.length; s++) {
      if (s === t.length) {
        i !== null && r.set(i, a);
        break;
      }
      const u = t[s];
      if (o) {
        if (u === '"') {
          o = !1;
          continue;
        }
      } else {
        if (u === '"') {
          o = !0;
          continue;
        }
        if (u === "\\") {
          s++;
          const f = parseInt(t.slice(s, s + 2), 16);
          Number.isNaN(f) ? (a += t[s]) : (s++, (a += String.fromCharCode(f)));
          continue;
        }
        if (i === null && u === "=") {
          ((i = a), (a = ""));
          continue;
        }
        if (u === "," || u === ";" || u === "+") {
          (i !== null && r.set(i, a), (i = null), (a = ""));
          continue;
        }
      }
      if (u === " " && !o) {
        if (a.length === 0) continue;
        if (s > n) {
          let f = s;
          for (; t[f] === " ";) f++;
          n = f;
        }
        if (
          n >= t.length ||
          t[n] === "," ||
          t[n] === ";" ||
          (i === null && t[n] === "=") ||
          (i !== null && t[n] === "+")
        ) {
          s = n - 1;
          continue;
        }
      }
      a += u;
    }
    return r;
  }
  return Oi;
}
var Fr = {},
  Nc;
function u2() {
  if (Nc) return Fr;
  ((Nc = 1),
    Object.defineProperty(Fr, "__esModule", { value: !0 }),
    (Fr.nil = Fr.UUID = void 0));
  const e = xt,
    t = Ho(),
    o = "options.name must be either a string or a Buffer",
    i = (0, e.randomBytes)(16);
  i[0] = i[0] | 1;
  const a = {},
    n = [];
  for (let c = 0; c < 256; c++) {
    const l = (c + 256).toString(16).substr(1);
    ((a[l] = c), (n[c] = l));
  }
  class r {
    constructor(l) {
      ((this.ascii = null), (this.binary = null));
      const h = r.check(l);
      if (!h) throw new Error("not a UUID");
      ((this.version = h.version),
        h.format === "ascii" ? (this.ascii = l) : (this.binary = l));
    }
    static v5(l, h) {
      return f(l, "sha1", 80, h);
    }
    toString() {
      return (this.ascii == null && (this.ascii = d(this.binary)), this.ascii);
    }
    inspect() {
      return `UUID v${this.version} ${this.toString()}`;
    }
    static check(l, h = 0) {
      if (typeof l == "string")
        return (
          (l = l.toLowerCase()),
          /^[a-f0-9]{8}(-[a-f0-9]{4}){3}-([a-f0-9]{12})$/.test(l)
            ? l === "00000000-0000-0000-0000-000000000000"
              ? { version: void 0, variant: "nil", format: "ascii" }
              : {
                  version: (a[l[14] + l[15]] & 240) >> 4,
                  variant: s((a[l[19] + l[20]] & 224) >> 5),
                  format: "ascii",
                }
            : !1
        );
      if (Buffer.isBuffer(l)) {
        if (l.length < h + 16) return !1;
        let y = 0;
        for (; y < 16 && l[h + y] === 0; y++);
        return y === 16
          ? { version: void 0, variant: "nil", format: "binary" }
          : {
              version: (l[h + 6] & 240) >> 4,
              variant: s((l[h + 8] & 224) >> 5),
              format: "binary",
            };
      }
      throw (0, t.newError)("Unknown type of uuid", "ERR_UNKNOWN_UUID_TYPE");
    }
    static parse(l) {
      const h = Buffer.allocUnsafe(16);
      let y = 0;
      for (let F = 0; F < 16; F++)
        ((h[F] = a[l[y++] + l[y++]]),
          (F === 3 || F === 5 || F === 7 || F === 9) && (y += 1));
      return h;
    }
  }
  ((Fr.UUID = r), (r.OID = r.parse("6ba7b812-9dad-11d1-80b4-00c04fd430c8")));
  function s(c) {
    switch (c) {
      case 0:
      case 1:
      case 3:
        return "ncs";
      case 4:
      case 5:
        return "rfc4122";
      case 6:
        return "microsoft";
      default:
        return "future";
    }
  }
  var u;
  (function (c) {
    ((c[(c.ASCII = 0)] = "ASCII"),
      (c[(c.BINARY = 1)] = "BINARY"),
      (c[(c.OBJECT = 2)] = "OBJECT"));
  })(u || (u = {}));
  function f(c, l, h, y, F = u.ASCII) {
    const m = (0, e.createHash)(l);
    if (typeof c != "string" && !Buffer.isBuffer(c))
      throw (0, t.newError)(o, "ERR_INVALID_UUID_NAME");
    (m.update(y), m.update(c));
    const E = m.digest();
    let b;
    switch (F) {
      case u.BINARY:
        ((E[6] = (E[6] & 15) | h), (E[8] = (E[8] & 63) | 128), (b = E));
        break;
      case u.OBJECT:
        ((E[6] = (E[6] & 15) | h), (E[8] = (E[8] & 63) | 128), (b = new r(E)));
        break;
      default:
        b =
          n[E[0]] +
          n[E[1]] +
          n[E[2]] +
          n[E[3]] +
          "-" +
          n[E[4]] +
          n[E[5]] +
          "-" +
          n[(E[6] & 15) | h] +
          n[E[7]] +
          "-" +
          n[(E[8] & 63) | 128] +
          n[E[9]] +
          "-" +
          n[E[10]] +
          n[E[11]] +
          n[E[12]] +
          n[E[13]] +
          n[E[14]] +
          n[E[15]];
        break;
    }
    return b;
  }
  function d(c) {
    return (
      n[c[0]] +
      n[c[1]] +
      n[c[2]] +
      n[c[3]] +
      "-" +
      n[c[4]] +
      n[c[5]] +
      "-" +
      n[c[6]] +
      n[c[7]] +
      "-" +
      n[c[8]] +
      n[c[9]] +
      "-" +
      n[c[10]] +
      n[c[11]] +
      n[c[12]] +
      n[c[13]] +
      n[c[14]] +
      n[c[15]]
    );
  }
  return ((Fr.nil = new r("00000000-0000-0000-0000-000000000000")), Fr);
}
var $r = {},
  Ha = {},
  Ic;
function l2() {
  return (
    Ic ||
      ((Ic = 1),
      (function (e) {
        (function (t) {
          ((t.parser = function (I, _) {
            return new i(I, _);
          }),
            (t.SAXParser = i),
            (t.SAXStream = d),
            (t.createStream = f),
            (t.MAX_BUFFER_LENGTH = 64 * 1024));
          var o = [
            "comment",
            "sgmlDecl",
            "textNode",
            "tagName",
            "doctype",
            "procInstName",
            "procInstBody",
            "entity",
            "attribName",
            "attribValue",
            "cdata",
            "script",
          ];
          t.EVENTS = [
            "text",
            "processinginstruction",
            "sgmldeclaration",
            "doctype",
            "comment",
            "opentagstart",
            "attribute",
            "opentag",
            "closetag",
            "opencdata",
            "cdata",
            "closecdata",
            "error",
            "end",
            "ready",
            "script",
            "opennamespace",
            "closenamespace",
          ];
          function i(I, _) {
            if (!(this instanceof i)) return new i(I, _);
            var W = this;
            (n(W),
              (W.q = W.c = ""),
              (W.bufferCheckPosition = t.MAX_BUFFER_LENGTH),
              (W.opt = _ || {}),
              (W.opt.lowercase = W.opt.lowercase || W.opt.lowercasetags),
              (W.looseCase = W.opt.lowercase ? "toLowerCase" : "toUpperCase"),
              (W.tags = []),
              (W.closed = W.closedRoot = W.sawRoot = !1),
              (W.tag = W.error = null),
              (W.strict = !!I),
              (W.noscript = !!(I || W.opt.noscript)),
              (W.state = D.BEGIN),
              (W.strictEntities = W.opt.strictEntities),
              (W.ENTITIES = W.strictEntities
                ? Object.create(t.XML_ENTITIES)
                : Object.create(t.ENTITIES)),
              (W.attribList = []),
              W.opt.xmlns && (W.ns = Object.create(F)),
              W.opt.unquotedAttributeValues === void 0 &&
                (W.opt.unquotedAttributeValues = !I),
              (W.trackPosition = W.opt.position !== !1),
              W.trackPosition && (W.position = W.line = W.column = 0),
              P(W, "onready"));
          }
          (Object.create ||
            (Object.create = function (I) {
              function _() {}
              _.prototype = I;
              var W = new _();
              return W;
            }),
            Object.keys ||
              (Object.keys = function (I) {
                var _ = [];
                for (var W in I) I.hasOwnProperty(W) && _.push(W);
                return _;
              }));
          function a(I) {
            for (
              var _ = Math.max(t.MAX_BUFFER_LENGTH, 10),
                W = 0,
                M = 0,
                le = o.length;
              M < le;
              M++
            ) {
              var he = I[o[M]].length;
              if (he > _)
                switch (o[M]) {
                  case "textNode":
                    k(I);
                    break;
                  case "cdata":
                    (R(I, "oncdata", I.cdata), (I.cdata = ""));
                    break;
                  case "script":
                    (R(I, "onscript", I.script), (I.script = ""));
                    break;
                  default:
                    U(I, "Max buffer length exceeded: " + o[M]);
                }
              W = Math.max(W, he);
            }
            var we = t.MAX_BUFFER_LENGTH - W;
            I.bufferCheckPosition = we + I.position;
          }
          function n(I) {
            for (var _ = 0, W = o.length; _ < W; _++) I[o[_]] = "";
          }
          function r(I) {
            (k(I),
              I.cdata !== "" && (R(I, "oncdata", I.cdata), (I.cdata = "")),
              I.script !== "" && (R(I, "onscript", I.script), (I.script = "")));
          }
          i.prototype = {
            end: function () {
              $(this);
            },
            write: ge,
            resume: function () {
              return ((this.error = null), this);
            },
            close: function () {
              return this.write(null);
            },
            flush: function () {
              r(this);
            },
          };
          var s;
          try {
            s = c0("stream").Stream;
          } catch {
            s = function () {};
          }
          s || (s = function () {});
          var u = t.EVENTS.filter(function (I) {
            return I !== "error" && I !== "end";
          });
          function f(I, _) {
            return new d(I, _);
          }
          function d(I, _) {
            if (!(this instanceof d)) return new d(I, _);
            (s.apply(this),
              (this._parser = new i(I, _)),
              (this.writable = !0),
              (this.readable = !0));
            var W = this;
            ((this._parser.onend = function () {
              W.emit("end");
            }),
              (this._parser.onerror = function (M) {
                (W.emit("error", M), (W._parser.error = null));
              }),
              (this._decoder = null),
              u.forEach(function (M) {
                Object.defineProperty(W, "on" + M, {
                  get: function () {
                    return W._parser["on" + M];
                  },
                  set: function (le) {
                    if (!le)
                      return (
                        W.removeAllListeners(M),
                        (W._parser["on" + M] = le),
                        le
                      );
                    W.on(M, le);
                  },
                  enumerable: !0,
                  configurable: !1,
                });
              }));
          }
          ((d.prototype = Object.create(s.prototype, {
            constructor: { value: d },
          })),
            (d.prototype.write = function (I) {
              if (
                typeof Buffer == "function" &&
                typeof Buffer.isBuffer == "function" &&
                Buffer.isBuffer(I)
              ) {
                if (!this._decoder) {
                  var _ = Hh.StringDecoder;
                  this._decoder = new _("utf8");
                }
                I = this._decoder.write(I);
              }
              return (
                this._parser.write(I.toString()),
                this.emit("data", I),
                !0
              );
            }),
            (d.prototype.end = function (I) {
              return (I && I.length && this.write(I), this._parser.end(), !0);
            }),
            (d.prototype.on = function (I, _) {
              var W = this;
              return (
                !W._parser["on" + I] &&
                  u.indexOf(I) !== -1 &&
                  (W._parser["on" + I] = function () {
                    var M =
                      arguments.length === 1
                        ? [arguments[0]]
                        : Array.apply(null, arguments);
                    (M.splice(0, 0, I), W.emit.apply(W, M));
                  }),
                s.prototype.on.call(W, I, _)
              );
            }));
          var c = "[CDATA[",
            l = "DOCTYPE",
            h = "http://www.w3.org/XML/1998/namespace",
            y = "http://www.w3.org/2000/xmlns/",
            F = { xml: h, xmlns: y },
            m =
              /[:_A-Za-z\u00C0-\u00D6\u00D8-\u00F6\u00F8-\u02FF\u0370-\u037D\u037F-\u1FFF\u200C-\u200D\u2070-\u218F\u2C00-\u2FEF\u3001-\uD7FF\uF900-\uFDCF\uFDF0-\uFFFD]/,
            S =
              /[:_A-Za-z\u00C0-\u00D6\u00D8-\u00F6\u00F8-\u02FF\u0370-\u037D\u037F-\u1FFF\u200C-\u200D\u2070-\u218F\u2C00-\u2FEF\u3001-\uD7FF\uF900-\uFDCF\uFDF0-\uFFFD\u00B7\u0300-\u036F\u203F-\u2040.\d-]/,
            E =
              /[#:_A-Za-z\u00C0-\u00D6\u00D8-\u00F6\u00F8-\u02FF\u0370-\u037D\u037F-\u1FFF\u200C-\u200D\u2070-\u218F\u2C00-\u2FEF\u3001-\uD7FF\uF900-\uFDCF\uFDF0-\uFFFD]/,
            b =
              /[#:_A-Za-z\u00C0-\u00D6\u00D8-\u00F6\u00F8-\u02FF\u0370-\u037D\u037F-\u1FFF\u200C-\u200D\u2070-\u218F\u2C00-\u2FEF\u3001-\uD7FF\uF900-\uFDCF\uFDF0-\uFFFD\u00B7\u0300-\u036F\u203F-\u2040.\d-]/;
          function w(I) {
            return (
              I === " " ||
              I ===
                `
` ||
              I === "\r" ||
              I === "	"
            );
          }
          function A(I) {
            return I === '"' || I === "'";
          }
          function v(I) {
            return I === ">" || w(I);
          }
          function C(I, _) {
            return I.test(_);
          }
          function g(I, _) {
            return !C(I, _);
          }
          var D = 0;
          ((t.STATE = {
            BEGIN: D++,
            BEGIN_WHITESPACE: D++,
            TEXT: D++,
            TEXT_ENTITY: D++,
            OPEN_WAKA: D++,
            SGML_DECL: D++,
            SGML_DECL_QUOTED: D++,
            DOCTYPE: D++,
            DOCTYPE_QUOTED: D++,
            DOCTYPE_DTD: D++,
            DOCTYPE_DTD_QUOTED: D++,
            COMMENT_STARTING: D++,
            COMMENT: D++,
            COMMENT_ENDING: D++,
            COMMENT_ENDED: D++,
            CDATA: D++,
            CDATA_ENDING: D++,
            CDATA_ENDING_2: D++,
            PROC_INST: D++,
            PROC_INST_BODY: D++,
            PROC_INST_ENDING: D++,
            OPEN_TAG: D++,
            OPEN_TAG_SLASH: D++,
            ATTRIB: D++,
            ATTRIB_NAME: D++,
            ATTRIB_NAME_SAW_WHITE: D++,
            ATTRIB_VALUE: D++,
            ATTRIB_VALUE_QUOTED: D++,
            ATTRIB_VALUE_CLOSED: D++,
            ATTRIB_VALUE_UNQUOTED: D++,
            ATTRIB_VALUE_ENTITY_Q: D++,
            ATTRIB_VALUE_ENTITY_U: D++,
            CLOSE_TAG: D++,
            CLOSE_TAG_SAW_WHITE: D++,
            SCRIPT: D++,
            SCRIPT_ENDING: D++,
          }),
            (t.XML_ENTITIES = {
              amp: "&",
              gt: ">",
              lt: "<",
              quot: '"',
              apos: "'",
            }),
            (t.ENTITIES = {
              amp: "&",
              gt: ">",
              lt: "<",
              quot: '"',
              apos: "'",
              AElig: 198,
              Aacute: 193,
              Acirc: 194,
              Agrave: 192,
              Aring: 197,
              Atilde: 195,
              Auml: 196,
              Ccedil: 199,
              ETH: 208,
              Eacute: 201,
              Ecirc: 202,
              Egrave: 200,
              Euml: 203,
              Iacute: 205,
              Icirc: 206,
              Igrave: 204,
              Iuml: 207,
              Ntilde: 209,
              Oacute: 211,
              Ocirc: 212,
              Ograve: 210,
              Oslash: 216,
              Otilde: 213,
              Ouml: 214,
              THORN: 222,
              Uacute: 218,
              Ucirc: 219,
              Ugrave: 217,
              Uuml: 220,
              Yacute: 221,
              aacute: 225,
              acirc: 226,
              aelig: 230,
              agrave: 224,
              aring: 229,
              atilde: 227,
              auml: 228,
              ccedil: 231,
              eacute: 233,
              ecirc: 234,
              egrave: 232,
              eth: 240,
              euml: 235,
              iacute: 237,
              icirc: 238,
              igrave: 236,
              iuml: 239,
              ntilde: 241,
              oacute: 243,
              ocirc: 244,
              ograve: 242,
              oslash: 248,
              otilde: 245,
              ouml: 246,
              szlig: 223,
              thorn: 254,
              uacute: 250,
              ucirc: 251,
              ugrave: 249,
              uuml: 252,
              yacute: 253,
              yuml: 255,
              copy: 169,
              reg: 174,
              nbsp: 160,
              iexcl: 161,
              cent: 162,
              pound: 163,
              curren: 164,
              yen: 165,
              brvbar: 166,
              sect: 167,
              uml: 168,
              ordf: 170,
              laquo: 171,
              not: 172,
              shy: 173,
              macr: 175,
              deg: 176,
              plusmn: 177,
              sup1: 185,
              sup2: 178,
              sup3: 179,
              acute: 180,
              micro: 181,
              para: 182,
              middot: 183,
              cedil: 184,
              ordm: 186,
              raquo: 187,
              frac14: 188,
              frac12: 189,
              frac34: 190,
              iquest: 191,
              times: 215,
              divide: 247,
              OElig: 338,
              oelig: 339,
              Scaron: 352,
              scaron: 353,
              Yuml: 376,
              fnof: 402,
              circ: 710,
              tilde: 732,
              Alpha: 913,
              Beta: 914,
              Gamma: 915,
              Delta: 916,
              Epsilon: 917,
              Zeta: 918,
              Eta: 919,
              Theta: 920,
              Iota: 921,
              Kappa: 922,
              Lambda: 923,
              Mu: 924,
              Nu: 925,
              Xi: 926,
              Omicron: 927,
              Pi: 928,
              Rho: 929,
              Sigma: 931,
              Tau: 932,
              Upsilon: 933,
              Phi: 934,
              Chi: 935,
              Psi: 936,
              Omega: 937,
              alpha: 945,
              beta: 946,
              gamma: 947,
              delta: 948,
              epsilon: 949,
              zeta: 950,
              eta: 951,
              theta: 952,
              iota: 953,
              kappa: 954,
              lambda: 955,
              mu: 956,
              nu: 957,
              xi: 958,
              omicron: 959,
              pi: 960,
              rho: 961,
              sigmaf: 962,
              sigma: 963,
              tau: 964,
              upsilon: 965,
              phi: 966,
              chi: 967,
              psi: 968,
              omega: 969,
              thetasym: 977,
              upsih: 978,
              piv: 982,
              ensp: 8194,
              emsp: 8195,
              thinsp: 8201,
              zwnj: 8204,
              zwj: 8205,
              lrm: 8206,
              rlm: 8207,
              ndash: 8211,
              mdash: 8212,
              lsquo: 8216,
              rsquo: 8217,
              sbquo: 8218,
              ldquo: 8220,
              rdquo: 8221,
              bdquo: 8222,
              dagger: 8224,
              Dagger: 8225,
              bull: 8226,
              hellip: 8230,
              permil: 8240,
              prime: 8242,
              Prime: 8243,
              lsaquo: 8249,
              rsaquo: 8250,
              oline: 8254,
              frasl: 8260,
              euro: 8364,
              image: 8465,
              weierp: 8472,
              real: 8476,
              trade: 8482,
              alefsym: 8501,
              larr: 8592,
              uarr: 8593,
              rarr: 8594,
              darr: 8595,
              harr: 8596,
              crarr: 8629,
              lArr: 8656,
              uArr: 8657,
              rArr: 8658,
              dArr: 8659,
              hArr: 8660,
              forall: 8704,
              part: 8706,
              exist: 8707,
              empty: 8709,
              nabla: 8711,
              isin: 8712,
              notin: 8713,
              ni: 8715,
              prod: 8719,
              sum: 8721,
              minus: 8722,
              lowast: 8727,
              radic: 8730,
              prop: 8733,
              infin: 8734,
              ang: 8736,
              and: 8743,
              or: 8744,
              cap: 8745,
              cup: 8746,
              int: 8747,
              there4: 8756,
              sim: 8764,
              cong: 8773,
              asymp: 8776,
              ne: 8800,
              equiv: 8801,
              le: 8804,
              ge: 8805,
              sub: 8834,
              sup: 8835,
              nsub: 8836,
              sube: 8838,
              supe: 8839,
              oplus: 8853,
              otimes: 8855,
              perp: 8869,
              sdot: 8901,
              lceil: 8968,
              rceil: 8969,
              lfloor: 8970,
              rfloor: 8971,
              lang: 9001,
              rang: 9002,
              loz: 9674,
              spades: 9824,
              clubs: 9827,
              hearts: 9829,
              diams: 9830,
            }),
            Object.keys(t.ENTITIES).forEach(function (I) {
              var _ = t.ENTITIES[I],
                W = typeof _ == "number" ? String.fromCharCode(_) : _;
              t.ENTITIES[I] = W;
            }));
          for (var N in t.STATE) t.STATE[t.STATE[N]] = N;
          D = t.STATE;
          function P(I, _, W) {
            I[_] && I[_](W);
          }
          function R(I, _, W) {
            (I.textNode && k(I), P(I, _, W));
          }
          function k(I) {
            ((I.textNode = q(I.opt, I.textNode)),
              I.textNode && P(I, "ontext", I.textNode),
              (I.textNode = ""));
          }
          function q(I, _) {
            return (
              I.trim && (_ = _.trim()),
              I.normalize && (_ = _.replace(/\s+/g, " ")),
              _
            );
          }
          function U(I, _) {
            return (
              k(I),
              I.trackPosition &&
                (_ +=
                  `
Line: ` +
                  I.line +
                  `
Column: ` +
                  I.column +
                  `
Char: ` +
                  I.c),
              (_ = new Error(_)),
              (I.error = _),
              P(I, "onerror", _),
              I
            );
          }
          function $(I) {
            return (
              I.sawRoot && !I.closedRoot && V(I, "Unclosed root tag"),
              I.state !== D.BEGIN &&
                I.state !== D.BEGIN_WHITESPACE &&
                I.state !== D.TEXT &&
                U(I, "Unexpected end"),
              k(I),
              (I.c = ""),
              (I.closed = !0),
              P(I, "onend"),
              i.call(I, I.strict, I.opt),
              I
            );
          }
          function V(I, _) {
            if (typeof I != "object" || !(I instanceof i))
              throw new Error("bad call to strictFail");
            I.strict && U(I, _);
          }
          function re(I) {
            I.strict || (I.tagName = I.tagName[I.looseCase]());
            var _ = I.tags[I.tags.length - 1] || I,
              W = (I.tag = { name: I.tagName, attributes: {} });
            (I.opt.xmlns && (W.ns = _.ns),
              (I.attribList.length = 0),
              R(I, "onopentagstart", W));
          }
          function X(I, _) {
            var W = I.indexOf(":"),
              M = W < 0 ? ["", I] : I.split(":"),
              le = M[0],
              he = M[1];
            return (
              _ && I === "xmlns" && ((le = "xmlns"), (he = "")),
              { prefix: le, local: he }
            );
          }
          function fe(I) {
            if (
              (I.strict || (I.attribName = I.attribName[I.looseCase]()),
              I.attribList.indexOf(I.attribName) !== -1 ||
                I.tag.attributes.hasOwnProperty(I.attribName))
            ) {
              I.attribName = I.attribValue = "";
              return;
            }
            if (I.opt.xmlns) {
              var _ = X(I.attribName, !0),
                W = _.prefix,
                M = _.local;
              if (W === "xmlns")
                if (M === "xml" && I.attribValue !== h)
                  V(
                    I,
                    "xml: prefix must be bound to " +
                      h +
                      `
Actual: ` +
                      I.attribValue,
                  );
                else if (M === "xmlns" && I.attribValue !== y)
                  V(
                    I,
                    "xmlns: prefix must be bound to " +
                      y +
                      `
Actual: ` +
                      I.attribValue,
                  );
                else {
                  var le = I.tag,
                    he = I.tags[I.tags.length - 1] || I;
                  (le.ns === he.ns && (le.ns = Object.create(he.ns)),
                    (le.ns[M] = I.attribValue));
                }
              I.attribList.push([I.attribName, I.attribValue]);
            } else
              ((I.tag.attributes[I.attribName] = I.attribValue),
                R(I, "onattribute", {
                  name: I.attribName,
                  value: I.attribValue,
                }));
            I.attribName = I.attribValue = "";
          }
          function Y(I, _) {
            if (I.opt.xmlns) {
              var W = I.tag,
                M = X(I.tagName);
              ((W.prefix = M.prefix),
                (W.local = M.local),
                (W.uri = W.ns[M.prefix] || ""),
                W.prefix &&
                  !W.uri &&
                  (V(
                    I,
                    "Unbound namespace prefix: " + JSON.stringify(I.tagName),
                  ),
                  (W.uri = M.prefix)));
              var le = I.tags[I.tags.length - 1] || I;
              W.ns &&
                le.ns !== W.ns &&
                Object.keys(W.ns).forEach(function (z) {
                  R(I, "onopennamespace", { prefix: z, uri: W.ns[z] });
                });
              for (var he = 0, we = I.attribList.length; he < we; he++) {
                var be = I.attribList[he],
                  Fe = be[0],
                  Oe = be[1],
                  Le = X(Fe, !0),
                  Ge = Le.prefix,
                  nt = Le.local,
                  ht = Ge === "" ? "" : W.ns[Ge] || "",
                  p = { name: Fe, value: Oe, prefix: Ge, local: nt, uri: ht };
                (Ge &&
                  Ge !== "xmlns" &&
                  !ht &&
                  (V(I, "Unbound namespace prefix: " + JSON.stringify(Ge)),
                  (p.uri = Ge)),
                  (I.tag.attributes[Fe] = p),
                  R(I, "onattribute", p));
              }
              I.attribList.length = 0;
            }
            ((I.tag.isSelfClosing = !!_),
              (I.sawRoot = !0),
              I.tags.push(I.tag),
              R(I, "onopentag", I.tag),
              _ ||
                (!I.noscript && I.tagName.toLowerCase() === "script"
                  ? (I.state = D.SCRIPT)
                  : (I.state = D.TEXT),
                (I.tag = null),
                (I.tagName = "")),
              (I.attribName = I.attribValue = ""),
              (I.attribList.length = 0));
          }
          function Ce(I) {
            if (!I.tagName) {
              (V(I, "Weird empty close tag."),
                (I.textNode += "</>"),
                (I.state = D.TEXT));
              return;
            }
            if (I.script) {
              if (I.tagName !== "script") {
                ((I.script += "</" + I.tagName + ">"),
                  (I.tagName = ""),
                  (I.state = D.SCRIPT));
                return;
              }
              (R(I, "onscript", I.script), (I.script = ""));
            }
            var _ = I.tags.length,
              W = I.tagName;
            I.strict || (W = W[I.looseCase]());
            for (var M = W; _--;) {
              var le = I.tags[_];
              if (le.name !== M) V(I, "Unexpected close tag");
              else break;
            }
            if (_ < 0) {
              (V(I, "Unmatched closing tag: " + I.tagName),
                (I.textNode += "</" + I.tagName + ">"),
                (I.state = D.TEXT));
              return;
            }
            I.tagName = W;
            for (var he = I.tags.length; he-- > _;) {
              var we = (I.tag = I.tags.pop());
              ((I.tagName = I.tag.name), R(I, "onclosetag", I.tagName));
              var be = {};
              for (var Fe in we.ns) be[Fe] = we.ns[Fe];
              var Oe = I.tags[I.tags.length - 1] || I;
              I.opt.xmlns &&
                we.ns !== Oe.ns &&
                Object.keys(we.ns).forEach(function (Le) {
                  var Ge = we.ns[Le];
                  R(I, "onclosenamespace", { prefix: Le, uri: Ge });
                });
            }
            (_ === 0 && (I.closedRoot = !0),
              (I.tagName = I.attribValue = I.attribName = ""),
              (I.attribList.length = 0),
              (I.state = D.TEXT));
          }
          function ue(I) {
            var _ = I.entity,
              W = _.toLowerCase(),
              M,
              le = "";
            return I.ENTITIES[_]
              ? I.ENTITIES[_]
              : I.ENTITIES[W]
                ? I.ENTITIES[W]
                : ((_ = W),
                  _.charAt(0) === "#" &&
                    (_.charAt(1) === "x"
                      ? ((_ = _.slice(2)),
                        (M = parseInt(_, 16)),
                        (le = M.toString(16)))
                      : ((_ = _.slice(1)),
                        (M = parseInt(_, 10)),
                        (le = M.toString(10)))),
                  (_ = _.replace(/^0+/, "")),
                  isNaN(M) || le.toLowerCase() !== _
                    ? (V(I, "Invalid character entity"), "&" + I.entity + ";")
                    : String.fromCodePoint(M));
          }
          function Ae(I, _) {
            _ === "<"
              ? ((I.state = D.OPEN_WAKA), (I.startTagPosition = I.position))
              : w(_) ||
                (V(I, "Non-whitespace before first tag."),
                (I.textNode = _),
                (I.state = D.TEXT));
          }
          function Q(I, _) {
            var W = "";
            return (_ < I.length && (W = I.charAt(_)), W);
          }
          function ge(I) {
            var _ = this;
            if (this.error) throw this.error;
            if (_.closed)
              return U(
                _,
                "Cannot write after close. Assign an onready handler.",
              );
            if (I === null) return $(_);
            typeof I == "object" && (I = I.toString());
            for (var W = 0, M = ""; (M = Q(I, W++)), (_.c = M), !!M;)
              switch (
                (_.trackPosition &&
                  (_.position++,
                  M ===
                  `
`
                    ? (_.line++, (_.column = 0))
                    : _.column++),
                _.state)
              ) {
                case D.BEGIN:
                  if (((_.state = D.BEGIN_WHITESPACE), M === "\uFEFF"))
                    continue;
                  Ae(_, M);
                  continue;
                case D.BEGIN_WHITESPACE:
                  Ae(_, M);
                  continue;
                case D.TEXT:
                  if (_.sawRoot && !_.closedRoot) {
                    for (var le = W - 1; M && M !== "<" && M !== "&";)
                      ((M = Q(I, W++)),
                        M &&
                          _.trackPosition &&
                          (_.position++,
                          M ===
                          `
`
                            ? (_.line++, (_.column = 0))
                            : _.column++));
                    _.textNode += I.substring(le, W - 1);
                  }
                  M === "<" && !(_.sawRoot && _.closedRoot && !_.strict)
                    ? ((_.state = D.OPEN_WAKA),
                      (_.startTagPosition = _.position))
                    : (!w(M) &&
                        (!_.sawRoot || _.closedRoot) &&
                        V(_, "Text data outside of root node."),
                      M === "&"
                        ? (_.state = D.TEXT_ENTITY)
                        : (_.textNode += M));
                  continue;
                case D.SCRIPT:
                  M === "<" ? (_.state = D.SCRIPT_ENDING) : (_.script += M);
                  continue;
                case D.SCRIPT_ENDING:
                  M === "/"
                    ? (_.state = D.CLOSE_TAG)
                    : ((_.script += "<" + M), (_.state = D.SCRIPT));
                  continue;
                case D.OPEN_WAKA:
                  if (M === "!") ((_.state = D.SGML_DECL), (_.sgmlDecl = ""));
                  else if (!w(M))
                    if (C(m, M)) ((_.state = D.OPEN_TAG), (_.tagName = M));
                    else if (M === "/")
                      ((_.state = D.CLOSE_TAG), (_.tagName = ""));
                    else if (M === "?")
                      ((_.state = D.PROC_INST),
                        (_.procInstName = _.procInstBody = ""));
                    else {
                      if (
                        (V(_, "Unencoded <"),
                        _.startTagPosition + 1 < _.position)
                      ) {
                        var he = _.position - _.startTagPosition;
                        M = new Array(he).join(" ") + M;
                      }
                      ((_.textNode += "<" + M), (_.state = D.TEXT));
                    }
                  continue;
                case D.SGML_DECL:
                  if (_.sgmlDecl + M === "--") {
                    ((_.state = D.COMMENT),
                      (_.comment = ""),
                      (_.sgmlDecl = ""));
                    continue;
                  }
                  _.doctype && _.doctype !== !0 && _.sgmlDecl
                    ? ((_.state = D.DOCTYPE_DTD),
                      (_.doctype += "<!" + _.sgmlDecl + M),
                      (_.sgmlDecl = ""))
                    : (_.sgmlDecl + M).toUpperCase() === c
                      ? (R(_, "onopencdata"),
                        (_.state = D.CDATA),
                        (_.sgmlDecl = ""),
                        (_.cdata = ""))
                      : (_.sgmlDecl + M).toUpperCase() === l
                        ? ((_.state = D.DOCTYPE),
                          (_.doctype || _.sawRoot) &&
                            V(_, "Inappropriately located doctype declaration"),
                          (_.doctype = ""),
                          (_.sgmlDecl = ""))
                        : M === ">"
                          ? (R(_, "onsgmldeclaration", _.sgmlDecl),
                            (_.sgmlDecl = ""),
                            (_.state = D.TEXT))
                          : (A(M) && (_.state = D.SGML_DECL_QUOTED),
                            (_.sgmlDecl += M));
                  continue;
                case D.SGML_DECL_QUOTED:
                  (M === _.q && ((_.state = D.SGML_DECL), (_.q = "")),
                    (_.sgmlDecl += M));
                  continue;
                case D.DOCTYPE:
                  M === ">"
                    ? ((_.state = D.TEXT),
                      R(_, "ondoctype", _.doctype),
                      (_.doctype = !0))
                    : ((_.doctype += M),
                      M === "["
                        ? (_.state = D.DOCTYPE_DTD)
                        : A(M) && ((_.state = D.DOCTYPE_QUOTED), (_.q = M)));
                  continue;
                case D.DOCTYPE_QUOTED:
                  ((_.doctype += M),
                    M === _.q && ((_.q = ""), (_.state = D.DOCTYPE)));
                  continue;
                case D.DOCTYPE_DTD:
                  M === "]"
                    ? ((_.doctype += M), (_.state = D.DOCTYPE))
                    : M === "<"
                      ? ((_.state = D.OPEN_WAKA),
                        (_.startTagPosition = _.position))
                      : A(M)
                        ? ((_.doctype += M),
                          (_.state = D.DOCTYPE_DTD_QUOTED),
                          (_.q = M))
                        : (_.doctype += M);
                  continue;
                case D.DOCTYPE_DTD_QUOTED:
                  ((_.doctype += M),
                    M === _.q && ((_.state = D.DOCTYPE_DTD), (_.q = "")));
                  continue;
                case D.COMMENT:
                  M === "-" ? (_.state = D.COMMENT_ENDING) : (_.comment += M);
                  continue;
                case D.COMMENT_ENDING:
                  M === "-"
                    ? ((_.state = D.COMMENT_ENDED),
                      (_.comment = q(_.opt, _.comment)),
                      _.comment && R(_, "oncomment", _.comment),
                      (_.comment = ""))
                    : ((_.comment += "-" + M), (_.state = D.COMMENT));
                  continue;
                case D.COMMENT_ENDED:
                  M !== ">"
                    ? (V(_, "Malformed comment"),
                      (_.comment += "--" + M),
                      (_.state = D.COMMENT))
                    : _.doctype && _.doctype !== !0
                      ? (_.state = D.DOCTYPE_DTD)
                      : (_.state = D.TEXT);
                  continue;
                case D.CDATA:
                  M === "]" ? (_.state = D.CDATA_ENDING) : (_.cdata += M);
                  continue;
                case D.CDATA_ENDING:
                  M === "]"
                    ? (_.state = D.CDATA_ENDING_2)
                    : ((_.cdata += "]" + M), (_.state = D.CDATA));
                  continue;
                case D.CDATA_ENDING_2:
                  M === ">"
                    ? (_.cdata && R(_, "oncdata", _.cdata),
                      R(_, "onclosecdata"),
                      (_.cdata = ""),
                      (_.state = D.TEXT))
                    : M === "]"
                      ? (_.cdata += "]")
                      : ((_.cdata += "]]" + M), (_.state = D.CDATA));
                  continue;
                case D.PROC_INST:
                  M === "?"
                    ? (_.state = D.PROC_INST_ENDING)
                    : w(M)
                      ? (_.state = D.PROC_INST_BODY)
                      : (_.procInstName += M);
                  continue;
                case D.PROC_INST_BODY:
                  if (!_.procInstBody && w(M)) continue;
                  M === "?"
                    ? (_.state = D.PROC_INST_ENDING)
                    : (_.procInstBody += M);
                  continue;
                case D.PROC_INST_ENDING:
                  M === ">"
                    ? (R(_, "onprocessinginstruction", {
                        name: _.procInstName,
                        body: _.procInstBody,
                      }),
                      (_.procInstName = _.procInstBody = ""),
                      (_.state = D.TEXT))
                    : ((_.procInstBody += "?" + M),
                      (_.state = D.PROC_INST_BODY));
                  continue;
                case D.OPEN_TAG:
                  C(S, M)
                    ? (_.tagName += M)
                    : (re(_),
                      M === ">"
                        ? Y(_)
                        : M === "/"
                          ? (_.state = D.OPEN_TAG_SLASH)
                          : (w(M) || V(_, "Invalid character in tag name"),
                            (_.state = D.ATTRIB)));
                  continue;
                case D.OPEN_TAG_SLASH:
                  M === ">"
                    ? (Y(_, !0), Ce(_))
                    : (V(_, "Forward-slash in opening tag not followed by >"),
                      (_.state = D.ATTRIB));
                  continue;
                case D.ATTRIB:
                  if (w(M)) continue;
                  M === ">"
                    ? Y(_)
                    : M === "/"
                      ? (_.state = D.OPEN_TAG_SLASH)
                      : C(m, M)
                        ? ((_.attribName = M),
                          (_.attribValue = ""),
                          (_.state = D.ATTRIB_NAME))
                        : V(_, "Invalid attribute name");
                  continue;
                case D.ATTRIB_NAME:
                  M === "="
                    ? (_.state = D.ATTRIB_VALUE)
                    : M === ">"
                      ? (V(_, "Attribute without value"),
                        (_.attribValue = _.attribName),
                        fe(_),
                        Y(_))
                      : w(M)
                        ? (_.state = D.ATTRIB_NAME_SAW_WHITE)
                        : C(S, M)
                          ? (_.attribName += M)
                          : V(_, "Invalid attribute name");
                  continue;
                case D.ATTRIB_NAME_SAW_WHITE:
                  if (M === "=") _.state = D.ATTRIB_VALUE;
                  else {
                    if (w(M)) continue;
                    (V(_, "Attribute without value"),
                      (_.tag.attributes[_.attribName] = ""),
                      (_.attribValue = ""),
                      R(_, "onattribute", { name: _.attribName, value: "" }),
                      (_.attribName = ""),
                      M === ">"
                        ? Y(_)
                        : C(m, M)
                          ? ((_.attribName = M), (_.state = D.ATTRIB_NAME))
                          : (V(_, "Invalid attribute name"),
                            (_.state = D.ATTRIB)));
                  }
                  continue;
                case D.ATTRIB_VALUE:
                  if (w(M)) continue;
                  A(M)
                    ? ((_.q = M), (_.state = D.ATTRIB_VALUE_QUOTED))
                    : (_.opt.unquotedAttributeValues ||
                        U(_, "Unquoted attribute value"),
                      (_.state = D.ATTRIB_VALUE_UNQUOTED),
                      (_.attribValue = M));
                  continue;
                case D.ATTRIB_VALUE_QUOTED:
                  if (M !== _.q) {
                    M === "&"
                      ? (_.state = D.ATTRIB_VALUE_ENTITY_Q)
                      : (_.attribValue += M);
                    continue;
                  }
                  (fe(_), (_.q = ""), (_.state = D.ATTRIB_VALUE_CLOSED));
                  continue;
                case D.ATTRIB_VALUE_CLOSED:
                  w(M)
                    ? (_.state = D.ATTRIB)
                    : M === ">"
                      ? Y(_)
                      : M === "/"
                        ? (_.state = D.OPEN_TAG_SLASH)
                        : C(m, M)
                          ? (V(_, "No whitespace between attributes"),
                            (_.attribName = M),
                            (_.attribValue = ""),
                            (_.state = D.ATTRIB_NAME))
                          : V(_, "Invalid attribute name");
                  continue;
                case D.ATTRIB_VALUE_UNQUOTED:
                  if (!v(M)) {
                    M === "&"
                      ? (_.state = D.ATTRIB_VALUE_ENTITY_U)
                      : (_.attribValue += M);
                    continue;
                  }
                  (fe(_), M === ">" ? Y(_) : (_.state = D.ATTRIB));
                  continue;
                case D.CLOSE_TAG:
                  if (_.tagName)
                    M === ">"
                      ? Ce(_)
                      : C(S, M)
                        ? (_.tagName += M)
                        : _.script
                          ? ((_.script += "</" + _.tagName),
                            (_.tagName = ""),
                            (_.state = D.SCRIPT))
                          : (w(M) || V(_, "Invalid tagname in closing tag"),
                            (_.state = D.CLOSE_TAG_SAW_WHITE));
                  else {
                    if (w(M)) continue;
                    g(m, M)
                      ? _.script
                        ? ((_.script += "</" + M), (_.state = D.SCRIPT))
                        : V(_, "Invalid tagname in closing tag.")
                      : (_.tagName = M);
                  }
                  continue;
                case D.CLOSE_TAG_SAW_WHITE:
                  if (w(M)) continue;
                  M === ">" ? Ce(_) : V(_, "Invalid characters in closing tag");
                  continue;
                case D.TEXT_ENTITY:
                case D.ATTRIB_VALUE_ENTITY_Q:
                case D.ATTRIB_VALUE_ENTITY_U:
                  var we, be;
                  switch (_.state) {
                    case D.TEXT_ENTITY:
                      ((we = D.TEXT), (be = "textNode"));
                      break;
                    case D.ATTRIB_VALUE_ENTITY_Q:
                      ((we = D.ATTRIB_VALUE_QUOTED), (be = "attribValue"));
                      break;
                    case D.ATTRIB_VALUE_ENTITY_U:
                      ((we = D.ATTRIB_VALUE_UNQUOTED), (be = "attribValue"));
                      break;
                  }
                  if (M === ";") {
                    var Fe = ue(_);
                    _.opt.unparsedEntities &&
                    !Object.values(t.XML_ENTITIES).includes(Fe)
                      ? ((_.entity = ""), (_.state = we), _.write(Fe))
                      : ((_[be] += Fe), (_.entity = ""), (_.state = we));
                  } else
                    C(_.entity.length ? b : E, M)
                      ? (_.entity += M)
                      : (V(_, "Invalid character in entity name"),
                        (_[be] += "&" + _.entity + M),
                        (_.entity = ""),
                        (_.state = we));
                  continue;
                default:
                  throw new Error(_, "Unknown state: " + _.state);
              }
            return (_.position >= _.bufferCheckPosition && a(_), _);
          }
          String.fromCodePoint ||
            (function () {
              var I = String.fromCharCode,
                _ = Math.floor,
                W = function () {
                  var M = 16384,
                    le = [],
                    he,
                    we,
                    be = -1,
                    Fe = arguments.length;
                  if (!Fe) return "";
                  for (var Oe = ""; ++be < Fe;) {
                    var Le = Number(arguments[be]);
                    if (!isFinite(Le) || Le < 0 || Le > 1114111 || _(Le) !== Le)
                      throw RangeError("Invalid code point: " + Le);
                    (Le <= 65535
                      ? le.push(Le)
                      : ((Le -= 65536),
                        (he = (Le >> 10) + 55296),
                        (we = (Le % 1024) + 56320),
                        le.push(he, we)),
                      (be + 1 === Fe || le.length > M) &&
                        ((Oe += I.apply(null, le)), (le.length = 0)));
                  }
                  return Oe;
                };
              Object.defineProperty
                ? Object.defineProperty(String, "fromCodePoint", {
                    value: W,
                    configurable: !0,
                    writable: !0,
                  })
                : (String.fromCodePoint = W);
            })();
        })(e);
      })(Ha)),
    Ha
  );
}
var Oc;
function c2() {
  if (Oc) return $r;
  ((Oc = 1),
    Object.defineProperty($r, "__esModule", { value: !0 }),
    ($r.XElement = void 0),
    ($r.parseXml = r));
  const e = l2(),
    t = Ho();
  class o {
    constructor(u) {
      if (
        ((this.name = u),
        (this.value = ""),
        (this.attributes = null),
        (this.isCData = !1),
        (this.elements = null),
        !u)
      )
        throw (0, t.newError)(
          "Element name cannot be empty",
          "ERR_XML_ELEMENT_NAME_EMPTY",
        );
      if (!a(u))
        throw (0, t.newError)(
          `Invalid element name: ${u}`,
          "ERR_XML_ELEMENT_INVALID_NAME",
        );
    }
    attribute(u) {
      const f = this.attributes === null ? null : this.attributes[u];
      if (f == null)
        throw (0, t.newError)(
          `No attribute "${u}"`,
          "ERR_XML_MISSED_ATTRIBUTE",
        );
      return f;
    }
    removeAttribute(u) {
      this.attributes !== null && delete this.attributes[u];
    }
    element(u, f = !1, d = null) {
      const c = this.elementOrNull(u, f);
      if (c === null)
        throw (0, t.newError)(
          d || `No element "${u}"`,
          "ERR_XML_MISSED_ELEMENT",
        );
      return c;
    }
    elementOrNull(u, f = !1) {
      if (this.elements === null) return null;
      for (const d of this.elements) if (n(d, u, f)) return d;
      return null;
    }
    getElements(u, f = !1) {
      return this.elements === null
        ? []
        : this.elements.filter((d) => n(d, u, f));
    }
    elementValueOrEmpty(u, f = !1) {
      const d = this.elementOrNull(u, f);
      return d === null ? "" : d.value;
    }
  }
  $r.XElement = o;
  const i = new RegExp(/^[A-Za-z_][:A-Za-z0-9_-]*$/i);
  function a(s) {
    return i.test(s);
  }
  function n(s, u, f) {
    const d = s.name;
    return (
      d === u ||
      (f === !0 && d.length === u.length && d.toLowerCase() === u.toLowerCase())
    );
  }
  function r(s) {
    let u = null;
    const f = e.parser(!0, {}),
      d = [];
    return (
      (f.onopentag = (c) => {
        const l = new o(c.name);
        if (((l.attributes = c.attributes), u === null)) u = l;
        else {
          const h = d[d.length - 1];
          (h.elements == null && (h.elements = []), h.elements.push(l));
        }
        d.push(l);
      }),
      (f.onclosetag = () => {
        d.pop();
      }),
      (f.ontext = (c) => {
        d.length > 0 && (d[d.length - 1].value = c);
      }),
      (f.oncdata = (c) => {
        const l = d[d.length - 1];
        ((l.value = c), (l.isCData = !0));
      }),
      (f.onerror = (c) => {
        throw c;
      }),
      f.write(s),
      u
    );
  }
  return $r;
}
var Pc;
function rt() {
  return (
    Pc ||
      ((Pc = 1),
      (function (e) {
        (Object.defineProperty(e, "__esModule", { value: !0 }),
          (e.CURRENT_APP_PACKAGE_FILE_NAME =
            e.CURRENT_APP_INSTALLER_FILE_NAME =
            e.XElement =
            e.parseXml =
            e.UUID =
            e.parseDn =
            e.retry =
            e.githubUrl =
            e.getS3LikeProviderBaseUrl =
            e.ProgressCallbackTransform =
            e.MemoLazy =
            e.safeStringifyJson =
            e.safeGetHeader =
            e.parseJson =
            e.HttpExecutor =
            e.HttpError =
            e.DigestTransform =
            e.createHttpError =
            e.configureRequestUrl =
            e.configureRequestOptionsFromUrl =
            e.configureRequestOptions =
            e.newError =
            e.CancellationToken =
            e.CancellationError =
              void 0),
          (e.asArray = c));
        var t = su();
        (Object.defineProperty(e, "CancellationError", {
          enumerable: !0,
          get: function () {
            return t.CancellationError;
          },
        }),
          Object.defineProperty(e, "CancellationToken", {
            enumerable: !0,
            get: function () {
              return t.CancellationToken;
            },
          }));
        var o = Ho();
        Object.defineProperty(e, "newError", {
          enumerable: !0,
          get: function () {
            return o.newError;
          },
        });
        var i = n2();
        (Object.defineProperty(e, "configureRequestOptions", {
          enumerable: !0,
          get: function () {
            return i.configureRequestOptions;
          },
        }),
          Object.defineProperty(e, "configureRequestOptionsFromUrl", {
            enumerable: !0,
            get: function () {
              return i.configureRequestOptionsFromUrl;
            },
          }),
          Object.defineProperty(e, "configureRequestUrl", {
            enumerable: !0,
            get: function () {
              return i.configureRequestUrl;
            },
          }),
          Object.defineProperty(e, "createHttpError", {
            enumerable: !0,
            get: function () {
              return i.createHttpError;
            },
          }),
          Object.defineProperty(e, "DigestTransform", {
            enumerable: !0,
            get: function () {
              return i.DigestTransform;
            },
          }),
          Object.defineProperty(e, "HttpError", {
            enumerable: !0,
            get: function () {
              return i.HttpError;
            },
          }),
          Object.defineProperty(e, "HttpExecutor", {
            enumerable: !0,
            get: function () {
              return i.HttpExecutor;
            },
          }),
          Object.defineProperty(e, "parseJson", {
            enumerable: !0,
            get: function () {
              return i.parseJson;
            },
          }),
          Object.defineProperty(e, "safeGetHeader", {
            enumerable: !0,
            get: function () {
              return i.safeGetHeader;
            },
          }),
          Object.defineProperty(e, "safeStringifyJson", {
            enumerable: !0,
            get: function () {
              return i.safeStringifyJson;
            },
          }));
        var a = i2();
        Object.defineProperty(e, "MemoLazy", {
          enumerable: !0,
          get: function () {
            return a.MemoLazy;
          },
        });
        var n = sp();
        Object.defineProperty(e, "ProgressCallbackTransform", {
          enumerable: !0,
          get: function () {
            return n.ProgressCallbackTransform;
          },
        });
        var r = o2();
        (Object.defineProperty(e, "getS3LikeProviderBaseUrl", {
          enumerable: !0,
          get: function () {
            return r.getS3LikeProviderBaseUrl;
          },
        }),
          Object.defineProperty(e, "githubUrl", {
            enumerable: !0,
            get: function () {
              return r.githubUrl;
            },
          }));
        var s = a2();
        Object.defineProperty(e, "retry", {
          enumerable: !0,
          get: function () {
            return s.retry;
          },
        });
        var u = s2();
        Object.defineProperty(e, "parseDn", {
          enumerable: !0,
          get: function () {
            return u.parseDn;
          },
        });
        var f = u2();
        Object.defineProperty(e, "UUID", {
          enumerable: !0,
          get: function () {
            return f.UUID;
          },
        });
        var d = c2();
        (Object.defineProperty(e, "parseXml", {
          enumerable: !0,
          get: function () {
            return d.parseXml;
          },
        }),
          Object.defineProperty(e, "XElement", {
            enumerable: !0,
            get: function () {
              return d.XElement;
            },
          }),
          (e.CURRENT_APP_INSTALLER_FILE_NAME = "installer.exe"),
          (e.CURRENT_APP_PACKAGE_FILE_NAME = "package.7z"));
        function c(l) {
          return l == null ? [] : Array.isArray(l) ? l : [l];
        }
      })($a)),
    $a
  );
}
var at = {},
  Pi = {},
  rr = {},
  Rc;
function ai() {
  if (Rc) return rr;
  Rc = 1;
  function e(r) {
    return typeof r > "u" || r === null;
  }
  function t(r) {
    return typeof r == "object" && r !== null;
  }
  function o(r) {
    return Array.isArray(r) ? r : e(r) ? [] : [r];
  }
  function i(r, s) {
    var u, f, d, c;
    if (s)
      for (c = Object.keys(s), u = 0, f = c.length; u < f; u += 1)
        ((d = c[u]), (r[d] = s[d]));
    return r;
  }
  function a(r, s) {
    var u = "",
      f;
    for (f = 0; f < s; f += 1) u += r;
    return u;
  }
  function n(r) {
    return r === 0 && Number.NEGATIVE_INFINITY === 1 / r;
  }
  return (
    (rr.isNothing = e),
    (rr.isObject = t),
    (rr.toArray = o),
    (rr.repeat = a),
    (rr.isNegativeZero = n),
    (rr.extend = i),
    rr
  );
}
var Ga, Lc;
function si() {
  if (Lc) return Ga;
  Lc = 1;
  function e(o, i) {
    var a = "",
      n = o.reason || "(unknown reason)";
    return o.mark
      ? (o.mark.name && (a += 'in "' + o.mark.name + '" '),
        (a += "(" + (o.mark.line + 1) + ":" + (o.mark.column + 1) + ")"),
        !i &&
          o.mark.snippet &&
          (a +=
            `

` + o.mark.snippet),
        n + " " + a)
      : n;
  }
  function t(o, i) {
    (Error.call(this),
      (this.name = "YAMLException"),
      (this.reason = o),
      (this.mark = i),
      (this.message = e(this, !1)),
      Error.captureStackTrace
        ? Error.captureStackTrace(this, this.constructor)
        : (this.stack = new Error().stack || ""));
  }
  return (
    (t.prototype = Object.create(Error.prototype)),
    (t.prototype.constructor = t),
    (t.prototype.toString = function (i) {
      return this.name + ": " + e(this, i);
    }),
    (Ga = t),
    Ga
  );
}
var Va, Bc;
function f2() {
  if (Bc) return Va;
  Bc = 1;
  var e = ai();
  function t(a, n, r, s, u) {
    var f = "",
      d = "",
      c = Math.floor(u / 2) - 1;
    return (
      s - n > c && ((f = " ... "), (n = s - c + f.length)),
      r - s > c && ((d = " ..."), (r = s + c - d.length)),
      { str: f + a.slice(n, r).replace(/\t/g, "→") + d, pos: s - n + f.length }
    );
  }
  function o(a, n) {
    return e.repeat(" ", n - a.length) + a;
  }
  function i(a, n) {
    if (((n = Object.create(n || null)), !a.buffer)) return null;
    (n.maxLength || (n.maxLength = 79),
      typeof n.indent != "number" && (n.indent = 1),
      typeof n.linesBefore != "number" && (n.linesBefore = 3),
      typeof n.linesAfter != "number" && (n.linesAfter = 2));
    for (
      var r = /\r?\n|\r|\0/g, s = [0], u = [], f, d = -1;
      (f = r.exec(a.buffer));
    )
      (u.push(f.index),
        s.push(f.index + f[0].length),
        a.position <= f.index && d < 0 && (d = s.length - 2));
    d < 0 && (d = s.length - 1);
    var c = "",
      l,
      h,
      y = Math.min(a.line + n.linesAfter, u.length).toString().length,
      F = n.maxLength - (n.indent + y + 3);
    for (l = 1; l <= n.linesBefore && !(d - l < 0); l++)
      ((h = t(a.buffer, s[d - l], u[d - l], a.position - (s[d] - s[d - l]), F)),
        (c =
          e.repeat(" ", n.indent) +
          o((a.line - l + 1).toString(), y) +
          " | " +
          h.str +
          `
` +
          c));
    for (
      h = t(a.buffer, s[d], u[d], a.position, F),
        c +=
          e.repeat(" ", n.indent) +
          o((a.line + 1).toString(), y) +
          " | " +
          h.str +
          `
`,
        c +=
          e.repeat("-", n.indent + y + 3 + h.pos) +
          `^
`,
        l = 1;
      l <= n.linesAfter && !(d + l >= u.length);
      l++
    )
      ((h = t(a.buffer, s[d + l], u[d + l], a.position - (s[d] - s[d + l]), F)),
        (c +=
          e.repeat(" ", n.indent) +
          o((a.line + l + 1).toString(), y) +
          " | " +
          h.str +
          `
`));
    return c.replace(/\n$/, "");
  }
  return ((Va = i), Va);
}
var za, kc;
function dt() {
  if (kc) return za;
  kc = 1;
  var e = si(),
    t = [
      "kind",
      "multi",
      "resolve",
      "construct",
      "instanceOf",
      "predicate",
      "represent",
      "representName",
      "defaultStyle",
      "styleAliases",
    ],
    o = ["scalar", "sequence", "mapping"];
  function i(n) {
    var r = {};
    return (
      n !== null &&
        Object.keys(n).forEach(function (s) {
          n[s].forEach(function (u) {
            r[String(u)] = s;
          });
        }),
      r
    );
  }
  function a(n, r) {
    if (
      ((r = r || {}),
      Object.keys(r).forEach(function (s) {
        if (t.indexOf(s) === -1)
          throw new e(
            'Unknown option "' +
              s +
              '" is met in definition of "' +
              n +
              '" YAML type.',
          );
      }),
      (this.options = r),
      (this.tag = n),
      (this.kind = r.kind || null),
      (this.resolve =
        r.resolve ||
        function () {
          return !0;
        }),
      (this.construct =
        r.construct ||
        function (s) {
          return s;
        }),
      (this.instanceOf = r.instanceOf || null),
      (this.predicate = r.predicate || null),
      (this.represent = r.represent || null),
      (this.representName = r.representName || null),
      (this.defaultStyle = r.defaultStyle || null),
      (this.multi = r.multi || !1),
      (this.styleAliases = i(r.styleAliases || null)),
      o.indexOf(this.kind) === -1)
    )
      throw new e(
        'Unknown kind "' +
          this.kind +
          '" is specified for "' +
          n +
          '" YAML type.',
      );
  }
  return ((za = a), za);
}
var Xa, Mc;
function up() {
  if (Mc) return Xa;
  Mc = 1;
  var e = si(),
    t = dt();
  function o(n, r) {
    var s = [];
    return (
      n[r].forEach(function (u) {
        var f = s.length;
        (s.forEach(function (d, c) {
          d.tag === u.tag &&
            d.kind === u.kind &&
            d.multi === u.multi &&
            (f = c);
        }),
          (s[f] = u));
      }),
      s
    );
  }
  function i() {
    var n = {
        scalar: {},
        sequence: {},
        mapping: {},
        fallback: {},
        multi: { scalar: [], sequence: [], mapping: [], fallback: [] },
      },
      r,
      s;
    function u(f) {
      f.multi
        ? (n.multi[f.kind].push(f), n.multi.fallback.push(f))
        : (n[f.kind][f.tag] = n.fallback[f.tag] = f);
    }
    for (r = 0, s = arguments.length; r < s; r += 1) arguments[r].forEach(u);
    return n;
  }
  function a(n) {
    return this.extend(n);
  }
  return (
    (a.prototype.extend = function (r) {
      var s = [],
        u = [];
      if (r instanceof t) u.push(r);
      else if (Array.isArray(r)) u = u.concat(r);
      else if (r && (Array.isArray(r.implicit) || Array.isArray(r.explicit)))
        (r.implicit && (s = s.concat(r.implicit)),
          r.explicit && (u = u.concat(r.explicit)));
      else
        throw new e(
          "Schema.extend argument should be a Type, [ Type ], or a schema definition ({ implicit: [...], explicit: [...] })",
        );
      (s.forEach(function (d) {
        if (!(d instanceof t))
          throw new e(
            "Specified list of YAML types (or a single Type object) contains a non-Type object.",
          );
        if (d.loadKind && d.loadKind !== "scalar")
          throw new e(
            "There is a non-scalar type in the implicit list of a schema. Implicit resolving of such types is not supported.",
          );
        if (d.multi)
          throw new e(
            "There is a multi type in the implicit list of a schema. Multi tags can only be listed as explicit.",
          );
      }),
        u.forEach(function (d) {
          if (!(d instanceof t))
            throw new e(
              "Specified list of YAML types (or a single Type object) contains a non-Type object.",
            );
        }));
      var f = Object.create(a.prototype);
      return (
        (f.implicit = (this.implicit || []).concat(s)),
        (f.explicit = (this.explicit || []).concat(u)),
        (f.compiledImplicit = o(f, "implicit")),
        (f.compiledExplicit = o(f, "explicit")),
        (f.compiledTypeMap = i(f.compiledImplicit, f.compiledExplicit)),
        f
      );
    }),
    (Xa = a),
    Xa
  );
}
var Ya, Uc;
function lp() {
  if (Uc) return Ya;
  Uc = 1;
  var e = dt();
  return (
    (Ya = new e("tag:yaml.org,2002:str", {
      kind: "scalar",
      construct: function (t) {
        return t !== null ? t : "";
      },
    })),
    Ya
  );
}
var Ka, qc;
function cp() {
  if (qc) return Ka;
  qc = 1;
  var e = dt();
  return (
    (Ka = new e("tag:yaml.org,2002:seq", {
      kind: "sequence",
      construct: function (t) {
        return t !== null ? t : [];
      },
    })),
    Ka
  );
}
var Ja, $c;
function fp() {
  if ($c) return Ja;
  $c = 1;
  var e = dt();
  return (
    (Ja = new e("tag:yaml.org,2002:map", {
      kind: "mapping",
      construct: function (t) {
        return t !== null ? t : {};
      },
    })),
    Ja
  );
}
var Qa, jc;
function dp() {
  if (jc) return Qa;
  jc = 1;
  var e = up();
  return ((Qa = new e({ explicit: [lp(), cp(), fp()] })), Qa);
}
var Za, Wc;
function hp() {
  if (Wc) return Za;
  Wc = 1;
  var e = dt();
  function t(a) {
    if (a === null) return !0;
    var n = a.length;
    return (
      (n === 1 && a === "~") ||
      (n === 4 && (a === "null" || a === "Null" || a === "NULL"))
    );
  }
  function o() {
    return null;
  }
  function i(a) {
    return a === null;
  }
  return (
    (Za = new e("tag:yaml.org,2002:null", {
      kind: "scalar",
      resolve: t,
      construct: o,
      predicate: i,
      represent: {
        canonical: function () {
          return "~";
        },
        lowercase: function () {
          return "null";
        },
        uppercase: function () {
          return "NULL";
        },
        camelcase: function () {
          return "Null";
        },
        empty: function () {
          return "";
        },
      },
      defaultStyle: "lowercase",
    })),
    Za
  );
}
var es, Hc;
function pp() {
  if (Hc) return es;
  Hc = 1;
  var e = dt();
  function t(a) {
    if (a === null) return !1;
    var n = a.length;
    return (
      (n === 4 && (a === "true" || a === "True" || a === "TRUE")) ||
      (n === 5 && (a === "false" || a === "False" || a === "FALSE"))
    );
  }
  function o(a) {
    return a === "true" || a === "True" || a === "TRUE";
  }
  function i(a) {
    return Object.prototype.toString.call(a) === "[object Boolean]";
  }
  return (
    (es = new e("tag:yaml.org,2002:bool", {
      kind: "scalar",
      resolve: t,
      construct: o,
      predicate: i,
      represent: {
        lowercase: function (a) {
          return a ? "true" : "false";
        },
        uppercase: function (a) {
          return a ? "TRUE" : "FALSE";
        },
        camelcase: function (a) {
          return a ? "True" : "False";
        },
      },
      defaultStyle: "lowercase",
    })),
    es
  );
}
var ts, Gc;
function Dp() {
  if (Gc) return ts;
  Gc = 1;
  var e = ai(),
    t = dt();
  function o(u) {
    return (
      (48 <= u && u <= 57) || (65 <= u && u <= 70) || (97 <= u && u <= 102)
    );
  }
  function i(u) {
    return 48 <= u && u <= 55;
  }
  function a(u) {
    return 48 <= u && u <= 57;
  }
  function n(u) {
    if (u === null) return !1;
    var f = u.length,
      d = 0,
      c = !1,
      l;
    if (!f) return !1;
    if (((l = u[d]), (l === "-" || l === "+") && (l = u[++d]), l === "0")) {
      if (d + 1 === f) return !0;
      if (((l = u[++d]), l === "b")) {
        for (d++; d < f; d++)
          if (((l = u[d]), l !== "_")) {
            if (l !== "0" && l !== "1") return !1;
            c = !0;
          }
        return c && l !== "_";
      }
      if (l === "x") {
        for (d++; d < f; d++)
          if (((l = u[d]), l !== "_")) {
            if (!o(u.charCodeAt(d))) return !1;
            c = !0;
          }
        return c && l !== "_";
      }
      if (l === "o") {
        for (d++; d < f; d++)
          if (((l = u[d]), l !== "_")) {
            if (!i(u.charCodeAt(d))) return !1;
            c = !0;
          }
        return c && l !== "_";
      }
    }
    if (l === "_") return !1;
    for (; d < f; d++)
      if (((l = u[d]), l !== "_")) {
        if (!a(u.charCodeAt(d))) return !1;
        c = !0;
      }
    return !(!c || l === "_");
  }
  function r(u) {
    var f = u,
      d = 1,
      c;
    if (
      (f.indexOf("_") !== -1 && (f = f.replace(/_/g, "")),
      (c = f[0]),
      (c === "-" || c === "+") &&
        (c === "-" && (d = -1), (f = f.slice(1)), (c = f[0])),
      f === "0")
    )
      return 0;
    if (c === "0") {
      if (f[1] === "b") return d * parseInt(f.slice(2), 2);
      if (f[1] === "x") return d * parseInt(f.slice(2), 16);
      if (f[1] === "o") return d * parseInt(f.slice(2), 8);
    }
    return d * parseInt(f, 10);
  }
  function s(u) {
    return (
      Object.prototype.toString.call(u) === "[object Number]" &&
      u % 1 === 0 &&
      !e.isNegativeZero(u)
    );
  }
  return (
    (ts = new t("tag:yaml.org,2002:int", {
      kind: "scalar",
      resolve: n,
      construct: r,
      predicate: s,
      represent: {
        binary: function (u) {
          return u >= 0 ? "0b" + u.toString(2) : "-0b" + u.toString(2).slice(1);
        },
        octal: function (u) {
          return u >= 0 ? "0o" + u.toString(8) : "-0o" + u.toString(8).slice(1);
        },
        decimal: function (u) {
          return u.toString(10);
        },
        hexadecimal: function (u) {
          return u >= 0
            ? "0x" + u.toString(16).toUpperCase()
            : "-0x" + u.toString(16).toUpperCase().slice(1);
        },
      },
      defaultStyle: "decimal",
      styleAliases: {
        binary: [2, "bin"],
        octal: [8, "oct"],
        decimal: [10, "dec"],
        hexadecimal: [16, "hex"],
      },
    })),
    ts
  );
}
var rs, Vc;
function mp() {
  if (Vc) return rs;
  Vc = 1;
  var e = ai(),
    t = dt(),
    o = new RegExp(
      "^(?:[-+]?(?:[0-9][0-9_]*)(?:\\.[0-9_]*)?(?:[eE][-+]?[0-9]+)?|\\.[0-9_]+(?:[eE][-+]?[0-9]+)?|[-+]?\\.(?:inf|Inf|INF)|\\.(?:nan|NaN|NAN))$",
    );
  function i(u) {
    return !(u === null || !o.test(u) || u[u.length - 1] === "_");
  }
  function a(u) {
    var f, d;
    return (
      (f = u.replace(/_/g, "").toLowerCase()),
      (d = f[0] === "-" ? -1 : 1),
      "+-".indexOf(f[0]) >= 0 && (f = f.slice(1)),
      f === ".inf"
        ? d === 1
          ? Number.POSITIVE_INFINITY
          : Number.NEGATIVE_INFINITY
        : f === ".nan"
          ? NaN
          : d * parseFloat(f, 10)
    );
  }
  var n = /^[-+]?[0-9]+e/;
  function r(u, f) {
    var d;
    if (isNaN(u))
      switch (f) {
        case "lowercase":
          return ".nan";
        case "uppercase":
          return ".NAN";
        case "camelcase":
          return ".NaN";
      }
    else if (Number.POSITIVE_INFINITY === u)
      switch (f) {
        case "lowercase":
          return ".inf";
        case "uppercase":
          return ".INF";
        case "camelcase":
          return ".Inf";
      }
    else if (Number.NEGATIVE_INFINITY === u)
      switch (f) {
        case "lowercase":
          return "-.inf";
        case "uppercase":
          return "-.INF";
        case "camelcase":
          return "-.Inf";
      }
    else if (e.isNegativeZero(u)) return "-0.0";
    return ((d = u.toString(10)), n.test(d) ? d.replace("e", ".e") : d);
  }
  function s(u) {
    return (
      Object.prototype.toString.call(u) === "[object Number]" &&
      (u % 1 !== 0 || e.isNegativeZero(u))
    );
  }
  return (
    (rs = new t("tag:yaml.org,2002:float", {
      kind: "scalar",
      resolve: i,
      construct: a,
      predicate: s,
      represent: r,
      defaultStyle: "lowercase",
    })),
    rs
  );
}
var ns, zc;
function gp() {
  return (
    zc ||
      ((zc = 1), (ns = dp().extend({ implicit: [hp(), pp(), Dp(), mp()] }))),
    ns
  );
}
var is, Xc;
function wp() {
  return (Xc || ((Xc = 1), (is = gp())), is);
}
var os, Yc;
function yp() {
  if (Yc) return os;
  Yc = 1;
  var e = dt(),
    t = new RegExp("^([0-9][0-9][0-9][0-9])-([0-9][0-9])-([0-9][0-9])$"),
    o = new RegExp(
      "^([0-9][0-9][0-9][0-9])-([0-9][0-9]?)-([0-9][0-9]?)(?:[Tt]|[ \\t]+)([0-9][0-9]?):([0-9][0-9]):([0-9][0-9])(?:\\.([0-9]*))?(?:[ \\t]*(Z|([-+])([0-9][0-9]?)(?::([0-9][0-9]))?))?$",
    );
  function i(r) {
    return r === null ? !1 : t.exec(r) !== null || o.exec(r) !== null;
  }
  function a(r) {
    var s,
      u,
      f,
      d,
      c,
      l,
      h,
      y = 0,
      F = null,
      m,
      S,
      E;
    if (((s = t.exec(r)), s === null && (s = o.exec(r)), s === null))
      throw new Error("Date resolve error");
    if (((u = +s[1]), (f = +s[2] - 1), (d = +s[3]), !s[4]))
      return new Date(Date.UTC(u, f, d));
    if (((c = +s[4]), (l = +s[5]), (h = +s[6]), s[7])) {
      for (y = s[7].slice(0, 3); y.length < 3;) y += "0";
      y = +y;
    }
    return (
      s[9] &&
        ((m = +s[10]),
        (S = +(s[11] || 0)),
        (F = (m * 60 + S) * 6e4),
        s[9] === "-" && (F = -F)),
      (E = new Date(Date.UTC(u, f, d, c, l, h, y))),
      F && E.setTime(E.getTime() - F),
      E
    );
  }
  function n(r) {
    return r.toISOString();
  }
  return (
    (os = new e("tag:yaml.org,2002:timestamp", {
      kind: "scalar",
      resolve: i,
      construct: a,
      instanceOf: Date,
      represent: n,
    })),
    os
  );
}
var as, Kc;
function Ep() {
  if (Kc) return as;
  Kc = 1;
  var e = dt();
  function t(o) {
    return o === "<<" || o === null;
  }
  return (
    (as = new e("tag:yaml.org,2002:merge", { kind: "scalar", resolve: t })),
    as
  );
}
var ss, Jc;
function vp() {
  if (Jc) return ss;
  Jc = 1;
  var e = dt(),
    t = `ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=
\r`;
  function o(r) {
    if (r === null) return !1;
    var s,
      u,
      f = 0,
      d = r.length,
      c = t;
    for (u = 0; u < d; u++)
      if (((s = c.indexOf(r.charAt(u))), !(s > 64))) {
        if (s < 0) return !1;
        f += 6;
      }
    return f % 8 === 0;
  }
  function i(r) {
    var s,
      u,
      f = r.replace(/[\r\n=]/g, ""),
      d = f.length,
      c = t,
      l = 0,
      h = [];
    for (s = 0; s < d; s++)
      (s % 4 === 0 &&
        s &&
        (h.push((l >> 16) & 255), h.push((l >> 8) & 255), h.push(l & 255)),
        (l = (l << 6) | c.indexOf(f.charAt(s))));
    return (
      (u = (d % 4) * 6),
      u === 0
        ? (h.push((l >> 16) & 255), h.push((l >> 8) & 255), h.push(l & 255))
        : u === 18
          ? (h.push((l >> 10) & 255), h.push((l >> 2) & 255))
          : u === 12 && h.push((l >> 4) & 255),
      new Uint8Array(h)
    );
  }
  function a(r) {
    var s = "",
      u = 0,
      f,
      d,
      c = r.length,
      l = t;
    for (f = 0; f < c; f++)
      (f % 3 === 0 &&
        f &&
        ((s += l[(u >> 18) & 63]),
        (s += l[(u >> 12) & 63]),
        (s += l[(u >> 6) & 63]),
        (s += l[u & 63])),
        (u = (u << 8) + r[f]));
    return (
      (d = c % 3),
      d === 0
        ? ((s += l[(u >> 18) & 63]),
          (s += l[(u >> 12) & 63]),
          (s += l[(u >> 6) & 63]),
          (s += l[u & 63]))
        : d === 2
          ? ((s += l[(u >> 10) & 63]),
            (s += l[(u >> 4) & 63]),
            (s += l[(u << 2) & 63]),
            (s += l[64]))
          : d === 1 &&
            ((s += l[(u >> 2) & 63]),
            (s += l[(u << 4) & 63]),
            (s += l[64]),
            (s += l[64])),
      s
    );
  }
  function n(r) {
    return Object.prototype.toString.call(r) === "[object Uint8Array]";
  }
  return (
    (ss = new e("tag:yaml.org,2002:binary", {
      kind: "scalar",
      resolve: o,
      construct: i,
      predicate: n,
      represent: a,
    })),
    ss
  );
}
var us, Qc;
function Cp() {
  if (Qc) return us;
  Qc = 1;
  var e = dt(),
    t = Object.prototype.hasOwnProperty,
    o = Object.prototype.toString;
  function i(n) {
    if (n === null) return !0;
    var r = [],
      s,
      u,
      f,
      d,
      c,
      l = n;
    for (s = 0, u = l.length; s < u; s += 1) {
      if (((f = l[s]), (c = !1), o.call(f) !== "[object Object]")) return !1;
      for (d in f)
        if (t.call(f, d))
          if (!c) c = !0;
          else return !1;
      if (!c) return !1;
      if (r.indexOf(d) === -1) r.push(d);
      else return !1;
    }
    return !0;
  }
  function a(n) {
    return n !== null ? n : [];
  }
  return (
    (us = new e("tag:yaml.org,2002:omap", {
      kind: "sequence",
      resolve: i,
      construct: a,
    })),
    us
  );
}
var ls, Zc;
function Ap() {
  if (Zc) return ls;
  Zc = 1;
  var e = dt(),
    t = Object.prototype.toString;
  function o(a) {
    if (a === null) return !0;
    var n,
      r,
      s,
      u,
      f,
      d = a;
    for (f = new Array(d.length), n = 0, r = d.length; n < r; n += 1) {
      if (
        ((s = d[n]),
        t.call(s) !== "[object Object]" ||
          ((u = Object.keys(s)), u.length !== 1))
      )
        return !1;
      f[n] = [u[0], s[u[0]]];
    }
    return !0;
  }
  function i(a) {
    if (a === null) return [];
    var n,
      r,
      s,
      u,
      f,
      d = a;
    for (f = new Array(d.length), n = 0, r = d.length; n < r; n += 1)
      ((s = d[n]), (u = Object.keys(s)), (f[n] = [u[0], s[u[0]]]));
    return f;
  }
  return (
    (ls = new e("tag:yaml.org,2002:pairs", {
      kind: "sequence",
      resolve: o,
      construct: i,
    })),
    ls
  );
}
var cs, ef;
function bp() {
  if (ef) return cs;
  ef = 1;
  var e = dt(),
    t = Object.prototype.hasOwnProperty;
  function o(a) {
    if (a === null) return !0;
    var n,
      r = a;
    for (n in r) if (t.call(r, n) && r[n] !== null) return !1;
    return !0;
  }
  function i(a) {
    return a !== null ? a : {};
  }
  return (
    (cs = new e("tag:yaml.org,2002:set", {
      kind: "mapping",
      resolve: o,
      construct: i,
    })),
    cs
  );
}
var fs, tf;
function uu() {
  return (
    tf ||
      ((tf = 1),
      (fs = wp().extend({
        implicit: [yp(), Ep()],
        explicit: [vp(), Cp(), Ap(), bp()],
      }))),
    fs
  );
}
var rf;
function d2() {
  if (rf) return Pi;
  rf = 1;
  var e = ai(),
    t = si(),
    o = f2(),
    i = uu(),
    a = Object.prototype.hasOwnProperty,
    n = 1,
    r = 2,
    s = 3,
    u = 4,
    f = 1,
    d = 2,
    c = 3,
    l =
      /[\x00-\x08\x0B\x0C\x0E-\x1F\x7F-\x84\x86-\x9F\uFFFE\uFFFF]|[\uD800-\uDBFF](?![\uDC00-\uDFFF])|(?:[^\uD800-\uDBFF]|^)[\uDC00-\uDFFF]/,
    h = /[\x85\u2028\u2029]/,
    y = /[,\[\]\{\}]/,
    F = /^(?:!|!!|![a-z\-]+!)$/i,
    m =
      /^(?:!|[^,\[\]\{\}])(?:%[0-9a-f]{2}|[0-9a-z\-#;\/\?:@&=\+\$,_\.!~\*'\(\)\[\]])*$/i;
  function S(p) {
    return Object.prototype.toString.call(p);
  }
  function E(p) {
    return p === 10 || p === 13;
  }
  function b(p) {
    return p === 9 || p === 32;
  }
  function w(p) {
    return p === 9 || p === 32 || p === 10 || p === 13;
  }
  function A(p) {
    return p === 44 || p === 91 || p === 93 || p === 123 || p === 125;
  }
  function v(p) {
    var z;
    return 48 <= p && p <= 57
      ? p - 48
      : ((z = p | 32), 97 <= z && z <= 102 ? z - 97 + 10 : -1);
  }
  function C(p) {
    return p === 120 ? 2 : p === 117 ? 4 : p === 85 ? 8 : 0;
  }
  function g(p) {
    return 48 <= p && p <= 57 ? p - 48 : -1;
  }
  function D(p) {
    return p === 48
      ? "\0"
      : p === 97
        ? "\x07"
        : p === 98
          ? "\b"
          : p === 116 || p === 9
            ? "	"
            : p === 110
              ? `
`
              : p === 118
                ? "\v"
                : p === 102
                  ? "\f"
                  : p === 114
                    ? "\r"
                    : p === 101
                      ? "\x1B"
                      : p === 32
                        ? " "
                        : p === 34
                          ? '"'
                          : p === 47
                            ? "/"
                            : p === 92
                              ? "\\"
                              : p === 78
                                ? ""
                                : p === 95
                                  ? " "
                                  : p === 76
                                    ? "\u2028"
                                    : p === 80
                                      ? "\u2029"
                                      : "";
  }
  function N(p) {
    return p <= 65535
      ? String.fromCharCode(p)
      : String.fromCharCode(
          ((p - 65536) >> 10) + 55296,
          ((p - 65536) & 1023) + 56320,
        );
  }
  for (var P = new Array(256), R = new Array(256), k = 0; k < 256; k++)
    ((P[k] = D(k) ? 1 : 0), (R[k] = D(k)));
  function q(p, z) {
    ((this.input = p),
      (this.filename = z.filename || null),
      (this.schema = z.schema || i),
      (this.onWarning = z.onWarning || null),
      (this.legacy = z.legacy || !1),
      (this.json = z.json || !1),
      (this.listener = z.listener || null),
      (this.implicitTypes = this.schema.compiledImplicit),
      (this.typeMap = this.schema.compiledTypeMap),
      (this.length = p.length),
      (this.position = 0),
      (this.line = 0),
      (this.lineStart = 0),
      (this.lineIndent = 0),
      (this.firstTabInLine = -1),
      (this.documents = []));
  }
  function U(p, z) {
    var J = {
      name: p.filename,
      buffer: p.input.slice(0, -1),
      position: p.position,
      line: p.line,
      column: p.position - p.lineStart,
    };
    return ((J.snippet = o(J)), new t(z, J));
  }
  function $(p, z) {
    throw U(p, z);
  }
  function V(p, z) {
    p.onWarning && p.onWarning.call(null, U(p, z));
  }
  var re = {
    YAML: function (z, J, de) {
      var ee, ce, ae;
      (z.version !== null && $(z, "duplication of %YAML directive"),
        de.length !== 1 && $(z, "YAML directive accepts exactly one argument"),
        (ee = /^([0-9]+)\.([0-9]+)$/.exec(de[0])),
        ee === null && $(z, "ill-formed argument of the YAML directive"),
        (ce = parseInt(ee[1], 10)),
        (ae = parseInt(ee[2], 10)),
        ce !== 1 && $(z, "unacceptable YAML version of the document"),
        (z.version = de[0]),
        (z.checkLineBreaks = ae < 2),
        ae !== 1 &&
          ae !== 2 &&
          V(z, "unsupported YAML version of the document"));
    },
    TAG: function (z, J, de) {
      var ee, ce;
      (de.length !== 2 && $(z, "TAG directive accepts exactly two arguments"),
        (ee = de[0]),
        (ce = de[1]),
        F.test(ee) ||
          $(z, "ill-formed tag handle (first argument) of the TAG directive"),
        a.call(z.tagMap, ee) &&
          $(
            z,
            'there is a previously declared suffix for "' + ee + '" tag handle',
          ),
        m.test(ce) ||
          $(z, "ill-formed tag prefix (second argument) of the TAG directive"));
      try {
        ce = decodeURIComponent(ce);
      } catch {
        $(z, "tag prefix is malformed: " + ce);
      }
      z.tagMap[ee] = ce;
    },
  };
  function X(p, z, J, de) {
    var ee, ce, ae, De;
    if (z < J) {
      if (((De = p.input.slice(z, J)), de))
        for (ee = 0, ce = De.length; ee < ce; ee += 1)
          ((ae = De.charCodeAt(ee)),
            ae === 9 ||
              (32 <= ae && ae <= 1114111) ||
              $(p, "expected valid JSON character"));
      else l.test(De) && $(p, "the stream contains non-printable characters");
      p.result += De;
    }
  }
  function fe(p, z, J, de) {
    var ee, ce, ae, De;
    for (
      e.isObject(J) ||
        $(
          p,
          "cannot merge mappings; the provided source object is unacceptable",
        ),
        ee = Object.keys(J),
        ae = 0,
        De = ee.length;
      ae < De;
      ae += 1
    )
      ((ce = ee[ae]), a.call(z, ce) || ((z[ce] = J[ce]), (de[ce] = !0)));
  }
  function Y(p, z, J, de, ee, ce, ae, De, Se) {
    var _e, Pe;
    if (Array.isArray(ee))
      for (
        ee = Array.prototype.slice.call(ee), _e = 0, Pe = ee.length;
        _e < Pe;
        _e += 1
      )
        (Array.isArray(ee[_e]) &&
          $(p, "nested arrays are not supported inside keys"),
          typeof ee == "object" &&
            S(ee[_e]) === "[object Object]" &&
            (ee[_e] = "[object Object]"));
    if (
      (typeof ee == "object" &&
        S(ee) === "[object Object]" &&
        (ee = "[object Object]"),
      (ee = String(ee)),
      z === null && (z = {}),
      de === "tag:yaml.org,2002:merge")
    )
      if (Array.isArray(ce))
        for (_e = 0, Pe = ce.length; _e < Pe; _e += 1) fe(p, z, ce[_e], J);
      else fe(p, z, ce, J);
    else
      (!p.json &&
        !a.call(J, ee) &&
        a.call(z, ee) &&
        ((p.line = ae || p.line),
        (p.lineStart = De || p.lineStart),
        (p.position = Se || p.position),
        $(p, "duplicated mapping key")),
        ee === "__proto__"
          ? Object.defineProperty(z, ee, {
              configurable: !0,
              enumerable: !0,
              writable: !0,
              value: ce,
            })
          : (z[ee] = ce),
        delete J[ee]);
    return z;
  }
  function Ce(p) {
    var z;
    ((z = p.input.charCodeAt(p.position)),
      z === 10
        ? p.position++
        : z === 13
          ? (p.position++,
            p.input.charCodeAt(p.position) === 10 && p.position++)
          : $(p, "a line break is expected"),
      (p.line += 1),
      (p.lineStart = p.position),
      (p.firstTabInLine = -1));
  }
  function ue(p, z, J) {
    for (var de = 0, ee = p.input.charCodeAt(p.position); ee !== 0;) {
      for (; b(ee);)
        (ee === 9 && p.firstTabInLine === -1 && (p.firstTabInLine = p.position),
          (ee = p.input.charCodeAt(++p.position)));
      if (z && ee === 35)
        do ee = p.input.charCodeAt(++p.position);
        while (ee !== 10 && ee !== 13 && ee !== 0);
      if (E(ee))
        for (
          Ce(p), ee = p.input.charCodeAt(p.position), de++, p.lineIndent = 0;
          ee === 32;
        )
          (p.lineIndent++, (ee = p.input.charCodeAt(++p.position)));
      else break;
    }
    return (
      J !== -1 && de !== 0 && p.lineIndent < J && V(p, "deficient indentation"),
      de
    );
  }
  function Ae(p) {
    var z = p.position,
      J;
    return (
      (J = p.input.charCodeAt(z)),
      !!(
        (J === 45 || J === 46) &&
        J === p.input.charCodeAt(z + 1) &&
        J === p.input.charCodeAt(z + 2) &&
        ((z += 3), (J = p.input.charCodeAt(z)), J === 0 || w(J))
      )
    );
  }
  function Q(p, z) {
    z === 1
      ? (p.result += " ")
      : z > 1 &&
        (p.result += e.repeat(
          `
`,
          z - 1,
        ));
  }
  function ge(p, z, J) {
    var de,
      ee,
      ce,
      ae,
      De,
      Se,
      _e,
      Pe,
      Ee = p.kind,
      je = p.result,
      O;
    if (
      ((O = p.input.charCodeAt(p.position)),
      w(O) ||
        A(O) ||
        O === 35 ||
        O === 38 ||
        O === 42 ||
        O === 33 ||
        O === 124 ||
        O === 62 ||
        O === 39 ||
        O === 34 ||
        O === 37 ||
        O === 64 ||
        O === 96 ||
        ((O === 63 || O === 45) &&
          ((ee = p.input.charCodeAt(p.position + 1)), w(ee) || (J && A(ee)))))
    )
      return !1;
    for (
      p.kind = "scalar", p.result = "", ce = ae = p.position, De = !1;
      O !== 0;
    ) {
      if (O === 58) {
        if (((ee = p.input.charCodeAt(p.position + 1)), w(ee) || (J && A(ee))))
          break;
      } else if (O === 35) {
        if (((de = p.input.charCodeAt(p.position - 1)), w(de))) break;
      } else {
        if ((p.position === p.lineStart && Ae(p)) || (J && A(O))) break;
        if (E(O))
          if (
            ((Se = p.line),
            (_e = p.lineStart),
            (Pe = p.lineIndent),
            ue(p, !1, -1),
            p.lineIndent >= z)
          ) {
            ((De = !0), (O = p.input.charCodeAt(p.position)));
            continue;
          } else {
            ((p.position = ae),
              (p.line = Se),
              (p.lineStart = _e),
              (p.lineIndent = Pe));
            break;
          }
      }
      (De &&
        (X(p, ce, ae, !1),
        Q(p, p.line - Se),
        (ce = ae = p.position),
        (De = !1)),
        b(O) || (ae = p.position + 1),
        (O = p.input.charCodeAt(++p.position)));
    }
    return (
      X(p, ce, ae, !1),
      p.result ? !0 : ((p.kind = Ee), (p.result = je), !1)
    );
  }
  function I(p, z) {
    var J, de, ee;
    if (((J = p.input.charCodeAt(p.position)), J !== 39)) return !1;
    for (
      p.kind = "scalar", p.result = "", p.position++, de = ee = p.position;
      (J = p.input.charCodeAt(p.position)) !== 0;
    )
      if (J === 39)
        if (
          (X(p, de, p.position, !0),
          (J = p.input.charCodeAt(++p.position)),
          J === 39)
        )
          ((de = p.position), p.position++, (ee = p.position));
        else return !0;
      else
        E(J)
          ? (X(p, de, ee, !0), Q(p, ue(p, !1, z)), (de = ee = p.position))
          : p.position === p.lineStart && Ae(p)
            ? $(
                p,
                "unexpected end of the document within a single quoted scalar",
              )
            : (p.position++, (ee = p.position));
    $(p, "unexpected end of the stream within a single quoted scalar");
  }
  function _(p, z) {
    var J, de, ee, ce, ae, De;
    if (((De = p.input.charCodeAt(p.position)), De !== 34)) return !1;
    for (
      p.kind = "scalar", p.result = "", p.position++, J = de = p.position;
      (De = p.input.charCodeAt(p.position)) !== 0;
    ) {
      if (De === 34) return (X(p, J, p.position, !0), p.position++, !0);
      if (De === 92) {
        if (
          (X(p, J, p.position, !0),
          (De = p.input.charCodeAt(++p.position)),
          E(De))
        )
          ue(p, !1, z);
        else if (De < 256 && P[De]) ((p.result += R[De]), p.position++);
        else if ((ae = C(De)) > 0) {
          for (ee = ae, ce = 0; ee > 0; ee--)
            ((De = p.input.charCodeAt(++p.position)),
              (ae = v(De)) >= 0
                ? (ce = (ce << 4) + ae)
                : $(p, "expected hexadecimal character"));
          ((p.result += N(ce)), p.position++);
        } else $(p, "unknown escape sequence");
        J = de = p.position;
      } else
        E(De)
          ? (X(p, J, de, !0), Q(p, ue(p, !1, z)), (J = de = p.position))
          : p.position === p.lineStart && Ae(p)
            ? $(
                p,
                "unexpected end of the document within a double quoted scalar",
              )
            : (p.position++, (de = p.position));
    }
    $(p, "unexpected end of the stream within a double quoted scalar");
  }
  function W(p, z) {
    var J = !0,
      de,
      ee,
      ce,
      ae = p.tag,
      De,
      Se = p.anchor,
      _e,
      Pe,
      Ee,
      je,
      O,
      K = Object.create(null),
      te,
      Z,
      oe,
      se;
    if (((se = p.input.charCodeAt(p.position)), se === 91))
      ((Pe = 93), (O = !1), (De = []));
    else if (se === 123) ((Pe = 125), (O = !0), (De = {}));
    else return !1;
    for (
      p.anchor !== null && (p.anchorMap[p.anchor] = De),
        se = p.input.charCodeAt(++p.position);
      se !== 0;
    ) {
      if ((ue(p, !0, z), (se = p.input.charCodeAt(p.position)), se === Pe))
        return (
          p.position++,
          (p.tag = ae),
          (p.anchor = Se),
          (p.kind = O ? "mapping" : "sequence"),
          (p.result = De),
          !0
        );
      (J
        ? se === 44 && $(p, "expected the node content, but found ','")
        : $(p, "missed comma between flow collection entries"),
        (Z = te = oe = null),
        (Ee = je = !1),
        se === 63 &&
          ((_e = p.input.charCodeAt(p.position + 1)),
          w(_e) && ((Ee = je = !0), p.position++, ue(p, !0, z))),
        (de = p.line),
        (ee = p.lineStart),
        (ce = p.position),
        Oe(p, z, n, !1, !0),
        (Z = p.tag),
        (te = p.result),
        ue(p, !0, z),
        (se = p.input.charCodeAt(p.position)),
        (je || p.line === de) &&
          se === 58 &&
          ((Ee = !0),
          (se = p.input.charCodeAt(++p.position)),
          ue(p, !0, z),
          Oe(p, z, n, !1, !0),
          (oe = p.result)),
        O
          ? Y(p, De, K, Z, te, oe, de, ee, ce)
          : Ee
            ? De.push(Y(p, null, K, Z, te, oe, de, ee, ce))
            : De.push(te),
        ue(p, !0, z),
        (se = p.input.charCodeAt(p.position)),
        se === 44
          ? ((J = !0), (se = p.input.charCodeAt(++p.position)))
          : (J = !1));
    }
    $(p, "unexpected end of the stream within a flow collection");
  }
  function M(p, z) {
    var J,
      de,
      ee = f,
      ce = !1,
      ae = !1,
      De = z,
      Se = 0,
      _e = !1,
      Pe,
      Ee;
    if (((Ee = p.input.charCodeAt(p.position)), Ee === 124)) de = !1;
    else if (Ee === 62) de = !0;
    else return !1;
    for (p.kind = "scalar", p.result = ""; Ee !== 0;)
      if (((Ee = p.input.charCodeAt(++p.position)), Ee === 43 || Ee === 45))
        f === ee
          ? (ee = Ee === 43 ? c : d)
          : $(p, "repeat of a chomping mode identifier");
      else if ((Pe = g(Ee)) >= 0)
        Pe === 0
          ? $(
              p,
              "bad explicit indentation width of a block scalar; it cannot be less than one",
            )
          : ae
            ? $(p, "repeat of an indentation width identifier")
            : ((De = z + Pe - 1), (ae = !0));
      else break;
    if (b(Ee)) {
      do Ee = p.input.charCodeAt(++p.position);
      while (b(Ee));
      if (Ee === 35)
        do Ee = p.input.charCodeAt(++p.position);
        while (!E(Ee) && Ee !== 0);
    }
    for (; Ee !== 0;) {
      for (
        Ce(p), p.lineIndent = 0, Ee = p.input.charCodeAt(p.position);
        (!ae || p.lineIndent < De) && Ee === 32;
      )
        (p.lineIndent++, (Ee = p.input.charCodeAt(++p.position)));
      if ((!ae && p.lineIndent > De && (De = p.lineIndent), E(Ee))) {
        Se++;
        continue;
      }
      if (p.lineIndent < De) {
        ee === c
          ? (p.result += e.repeat(
              `
`,
              ce ? 1 + Se : Se,
            ))
          : ee === f &&
            ce &&
            (p.result += `
`);
        break;
      }
      for (
        de
          ? b(Ee)
            ? ((_e = !0),
              (p.result += e.repeat(
                `
`,
                ce ? 1 + Se : Se,
              )))
            : _e
              ? ((_e = !1),
                (p.result += e.repeat(
                  `
`,
                  Se + 1,
                )))
              : Se === 0
                ? ce && (p.result += " ")
                : (p.result += e.repeat(
                    `
`,
                    Se,
                  ))
          : (p.result += e.repeat(
              `
`,
              ce ? 1 + Se : Se,
            )),
          ce = !0,
          ae = !0,
          Se = 0,
          J = p.position;
        !E(Ee) && Ee !== 0;
      )
        Ee = p.input.charCodeAt(++p.position);
      X(p, J, p.position, !1);
    }
    return !0;
  }
  function le(p, z) {
    var J,
      de = p.tag,
      ee = p.anchor,
      ce = [],
      ae,
      De = !1,
      Se;
    if (p.firstTabInLine !== -1) return !1;
    for (
      p.anchor !== null && (p.anchorMap[p.anchor] = ce),
        Se = p.input.charCodeAt(p.position);
      Se !== 0 &&
      (p.firstTabInLine !== -1 &&
        ((p.position = p.firstTabInLine),
        $(p, "tab characters must not be used in indentation")),
      !(Se !== 45 || ((ae = p.input.charCodeAt(p.position + 1)), !w(ae))));
    ) {
      if (((De = !0), p.position++, ue(p, !0, -1) && p.lineIndent <= z)) {
        (ce.push(null), (Se = p.input.charCodeAt(p.position)));
        continue;
      }
      if (
        ((J = p.line),
        Oe(p, z, s, !1, !0),
        ce.push(p.result),
        ue(p, !0, -1),
        (Se = p.input.charCodeAt(p.position)),
        (p.line === J || p.lineIndent > z) && Se !== 0)
      )
        $(p, "bad indentation of a sequence entry");
      else if (p.lineIndent < z) break;
    }
    return De
      ? ((p.tag = de),
        (p.anchor = ee),
        (p.kind = "sequence"),
        (p.result = ce),
        !0)
      : !1;
  }
  function he(p, z, J) {
    var de,
      ee,
      ce,
      ae,
      De,
      Se,
      _e = p.tag,
      Pe = p.anchor,
      Ee = {},
      je = Object.create(null),
      O = null,
      K = null,
      te = null,
      Z = !1,
      oe = !1,
      se;
    if (p.firstTabInLine !== -1) return !1;
    for (
      p.anchor !== null && (p.anchorMap[p.anchor] = Ee),
        se = p.input.charCodeAt(p.position);
      se !== 0;
    ) {
      if (
        (!Z &&
          p.firstTabInLine !== -1 &&
          ((p.position = p.firstTabInLine),
          $(p, "tab characters must not be used in indentation")),
        (de = p.input.charCodeAt(p.position + 1)),
        (ce = p.line),
        (se === 63 || se === 58) && w(de))
      )
        (se === 63
          ? (Z && (Y(p, Ee, je, O, K, null, ae, De, Se), (O = K = te = null)),
            (oe = !0),
            (Z = !0),
            (ee = !0))
          : Z
            ? ((Z = !1), (ee = !0))
            : $(
                p,
                "incomplete explicit mapping pair; a key node is missed; or followed by a non-tabulated empty line",
              ),
          (p.position += 1),
          (se = de));
      else {
        if (
          ((ae = p.line),
          (De = p.lineStart),
          (Se = p.position),
          !Oe(p, J, r, !1, !0))
        )
          break;
        if (p.line === ce) {
          for (se = p.input.charCodeAt(p.position); b(se);)
            se = p.input.charCodeAt(++p.position);
          if (se === 58)
            ((se = p.input.charCodeAt(++p.position)),
              w(se) ||
                $(
                  p,
                  "a whitespace character is expected after the key-value separator within a block mapping",
                ),
              Z && (Y(p, Ee, je, O, K, null, ae, De, Se), (O = K = te = null)),
              (oe = !0),
              (Z = !1),
              (ee = !1),
              (O = p.tag),
              (K = p.result));
          else if (oe)
            $(p, "can not read an implicit mapping pair; a colon is missed");
          else return ((p.tag = _e), (p.anchor = Pe), !0);
        } else if (oe)
          $(
            p,
            "can not read a block mapping entry; a multiline key may not be an implicit key",
          );
        else return ((p.tag = _e), (p.anchor = Pe), !0);
      }
      if (
        ((p.line === ce || p.lineIndent > z) &&
          (Z && ((ae = p.line), (De = p.lineStart), (Se = p.position)),
          Oe(p, z, u, !0, ee) && (Z ? (K = p.result) : (te = p.result)),
          Z || (Y(p, Ee, je, O, K, te, ae, De, Se), (O = K = te = null)),
          ue(p, !0, -1),
          (se = p.input.charCodeAt(p.position))),
        (p.line === ce || p.lineIndent > z) && se !== 0)
      )
        $(p, "bad indentation of a mapping entry");
      else if (p.lineIndent < z) break;
    }
    return (
      Z && Y(p, Ee, je, O, K, null, ae, De, Se),
      oe &&
        ((p.tag = _e), (p.anchor = Pe), (p.kind = "mapping"), (p.result = Ee)),
      oe
    );
  }
  function we(p) {
    var z,
      J = !1,
      de = !1,
      ee,
      ce,
      ae;
    if (((ae = p.input.charCodeAt(p.position)), ae !== 33)) return !1;
    if (
      (p.tag !== null && $(p, "duplication of a tag property"),
      (ae = p.input.charCodeAt(++p.position)),
      ae === 60
        ? ((J = !0), (ae = p.input.charCodeAt(++p.position)))
        : ae === 33
          ? ((de = !0), (ee = "!!"), (ae = p.input.charCodeAt(++p.position)))
          : (ee = "!"),
      (z = p.position),
      J)
    ) {
      do ae = p.input.charCodeAt(++p.position);
      while (ae !== 0 && ae !== 62);
      p.position < p.length
        ? ((ce = p.input.slice(z, p.position)),
          (ae = p.input.charCodeAt(++p.position)))
        : $(p, "unexpected end of the stream within a verbatim tag");
    } else {
      for (; ae !== 0 && !w(ae);)
        (ae === 33 &&
          (de
            ? $(p, "tag suffix cannot contain exclamation marks")
            : ((ee = p.input.slice(z - 1, p.position + 1)),
              F.test(ee) ||
                $(p, "named tag handle cannot contain such characters"),
              (de = !0),
              (z = p.position + 1))),
          (ae = p.input.charCodeAt(++p.position)));
      ((ce = p.input.slice(z, p.position)),
        y.test(ce) &&
          $(p, "tag suffix cannot contain flow indicator characters"));
    }
    ce && !m.test(ce) && $(p, "tag name cannot contain such characters: " + ce);
    try {
      ce = decodeURIComponent(ce);
    } catch {
      $(p, "tag name is malformed: " + ce);
    }
    return (
      J
        ? (p.tag = ce)
        : a.call(p.tagMap, ee)
          ? (p.tag = p.tagMap[ee] + ce)
          : ee === "!"
            ? (p.tag = "!" + ce)
            : ee === "!!"
              ? (p.tag = "tag:yaml.org,2002:" + ce)
              : $(p, 'undeclared tag handle "' + ee + '"'),
      !0
    );
  }
  function be(p) {
    var z, J;
    if (((J = p.input.charCodeAt(p.position)), J !== 38)) return !1;
    for (
      p.anchor !== null && $(p, "duplication of an anchor property"),
        J = p.input.charCodeAt(++p.position),
        z = p.position;
      J !== 0 && !w(J) && !A(J);
    )
      J = p.input.charCodeAt(++p.position);
    return (
      p.position === z &&
        $(p, "name of an anchor node must contain at least one character"),
      (p.anchor = p.input.slice(z, p.position)),
      !0
    );
  }
  function Fe(p) {
    var z, J, de;
    if (((de = p.input.charCodeAt(p.position)), de !== 42)) return !1;
    for (
      de = p.input.charCodeAt(++p.position), z = p.position;
      de !== 0 && !w(de) && !A(de);
    )
      de = p.input.charCodeAt(++p.position);
    return (
      p.position === z &&
        $(p, "name of an alias node must contain at least one character"),
      (J = p.input.slice(z, p.position)),
      a.call(p.anchorMap, J) || $(p, 'unidentified alias "' + J + '"'),
      (p.result = p.anchorMap[J]),
      ue(p, !0, -1),
      !0
    );
  }
  function Oe(p, z, J, de, ee) {
    var ce,
      ae,
      De,
      Se = 1,
      _e = !1,
      Pe = !1,
      Ee,
      je,
      O,
      K,
      te,
      Z;
    if (
      (p.listener !== null && p.listener("open", p),
      (p.tag = null),
      (p.anchor = null),
      (p.kind = null),
      (p.result = null),
      (ce = ae = De = u === J || s === J),
      de &&
        ue(p, !0, -1) &&
        ((_e = !0),
        p.lineIndent > z
          ? (Se = 1)
          : p.lineIndent === z
            ? (Se = 0)
            : p.lineIndent < z && (Se = -1)),
      Se === 1)
    )
      for (; we(p) || be(p);)
        ue(p, !0, -1)
          ? ((_e = !0),
            (De = ce),
            p.lineIndent > z
              ? (Se = 1)
              : p.lineIndent === z
                ? (Se = 0)
                : p.lineIndent < z && (Se = -1))
          : (De = !1);
    if (
      (De && (De = _e || ee),
      (Se === 1 || u === J) &&
        (n === J || r === J ? (te = z) : (te = z + 1),
        (Z = p.position - p.lineStart),
        Se === 1
          ? (De && (le(p, Z) || he(p, Z, te))) || W(p, te)
            ? (Pe = !0)
            : ((ae && M(p, te)) || I(p, te) || _(p, te)
                ? (Pe = !0)
                : Fe(p)
                  ? ((Pe = !0),
                    (p.tag !== null || p.anchor !== null) &&
                      $(p, "alias node should not have any properties"))
                  : ge(p, te, n === J) &&
                    ((Pe = !0), p.tag === null && (p.tag = "?")),
              p.anchor !== null && (p.anchorMap[p.anchor] = p.result))
          : Se === 0 && (Pe = De && le(p, Z))),
      p.tag === null)
    )
      p.anchor !== null && (p.anchorMap[p.anchor] = p.result);
    else if (p.tag === "?") {
      for (
        p.result !== null &&
          p.kind !== "scalar" &&
          $(
            p,
            'unacceptable node kind for !<?> tag; it should be "scalar", not "' +
              p.kind +
              '"',
          ),
          Ee = 0,
          je = p.implicitTypes.length;
        Ee < je;
        Ee += 1
      )
        if (((K = p.implicitTypes[Ee]), K.resolve(p.result))) {
          ((p.result = K.construct(p.result)),
            (p.tag = K.tag),
            p.anchor !== null && (p.anchorMap[p.anchor] = p.result));
          break;
        }
    } else if (p.tag !== "!") {
      if (a.call(p.typeMap[p.kind || "fallback"], p.tag))
        K = p.typeMap[p.kind || "fallback"][p.tag];
      else
        for (
          K = null,
            O = p.typeMap.multi[p.kind || "fallback"],
            Ee = 0,
            je = O.length;
          Ee < je;
          Ee += 1
        )
          if (p.tag.slice(0, O[Ee].tag.length) === O[Ee].tag) {
            K = O[Ee];
            break;
          }
      (K || $(p, "unknown tag !<" + p.tag + ">"),
        p.result !== null &&
          K.kind !== p.kind &&
          $(
            p,
            "unacceptable node kind for !<" +
              p.tag +
              '> tag; it should be "' +
              K.kind +
              '", not "' +
              p.kind +
              '"',
          ),
        K.resolve(p.result, p.tag)
          ? ((p.result = K.construct(p.result, p.tag)),
            p.anchor !== null && (p.anchorMap[p.anchor] = p.result))
          : $(p, "cannot resolve a node with !<" + p.tag + "> explicit tag"));
    }
    return (
      p.listener !== null && p.listener("close", p),
      p.tag !== null || p.anchor !== null || Pe
    );
  }
  function Le(p) {
    var z = p.position,
      J,
      de,
      ee,
      ce = !1,
      ae;
    for (
      p.version = null,
        p.checkLineBreaks = p.legacy,
        p.tagMap = Object.create(null),
        p.anchorMap = Object.create(null);
      (ae = p.input.charCodeAt(p.position)) !== 0 &&
      (ue(p, !0, -1),
      (ae = p.input.charCodeAt(p.position)),
      !(p.lineIndent > 0 || ae !== 37));
    ) {
      for (
        ce = !0, ae = p.input.charCodeAt(++p.position), J = p.position;
        ae !== 0 && !w(ae);
      )
        ae = p.input.charCodeAt(++p.position);
      for (
        de = p.input.slice(J, p.position),
          ee = [],
          de.length < 1 &&
            $(
              p,
              "directive name must not be less than one character in length",
            );
        ae !== 0;
      ) {
        for (; b(ae);) ae = p.input.charCodeAt(++p.position);
        if (ae === 35) {
          do ae = p.input.charCodeAt(++p.position);
          while (ae !== 0 && !E(ae));
          break;
        }
        if (E(ae)) break;
        for (J = p.position; ae !== 0 && !w(ae);)
          ae = p.input.charCodeAt(++p.position);
        ee.push(p.input.slice(J, p.position));
      }
      (ae !== 0 && Ce(p),
        a.call(re, de)
          ? re[de](p, de, ee)
          : V(p, 'unknown document directive "' + de + '"'));
    }
    if (
      (ue(p, !0, -1),
      p.lineIndent === 0 &&
      p.input.charCodeAt(p.position) === 45 &&
      p.input.charCodeAt(p.position + 1) === 45 &&
      p.input.charCodeAt(p.position + 2) === 45
        ? ((p.position += 3), ue(p, !0, -1))
        : ce && $(p, "directives end mark is expected"),
      Oe(p, p.lineIndent - 1, u, !1, !0),
      ue(p, !0, -1),
      p.checkLineBreaks &&
        h.test(p.input.slice(z, p.position)) &&
        V(p, "non-ASCII line breaks are interpreted as content"),
      p.documents.push(p.result),
      p.position === p.lineStart && Ae(p))
    ) {
      p.input.charCodeAt(p.position) === 46 &&
        ((p.position += 3), ue(p, !0, -1));
      return;
    }
    if (p.position < p.length - 1)
      $(p, "end of the stream or a document separator is expected");
    else return;
  }
  function Ge(p, z) {
    ((p = String(p)),
      (z = z || {}),
      p.length !== 0 &&
        (p.charCodeAt(p.length - 1) !== 10 &&
          p.charCodeAt(p.length - 1) !== 13 &&
          (p += `
`),
        p.charCodeAt(0) === 65279 && (p = p.slice(1))));
    var J = new q(p, z),
      de = p.indexOf("\0");
    for (
      de !== -1 &&
        ((J.position = de), $(J, "null byte is not allowed in input")),
        J.input += "\0";
      J.input.charCodeAt(J.position) === 32;
    )
      ((J.lineIndent += 1), (J.position += 1));
    for (; J.position < J.length - 1;) Le(J);
    return J.documents;
  }
  function nt(p, z, J) {
    z !== null &&
      typeof z == "object" &&
      typeof J > "u" &&
      ((J = z), (z = null));
    var de = Ge(p, J);
    if (typeof z != "function") return de;
    for (var ee = 0, ce = de.length; ee < ce; ee += 1) z(de[ee]);
  }
  function ht(p, z) {
    var J = Ge(p, z);
    if (J.length !== 0) {
      if (J.length === 1) return J[0];
      throw new t("expected a single document in the stream, but found more");
    }
  }
  return ((Pi.loadAll = nt), (Pi.load = ht), Pi);
}
var ds = {},
  nf;
function h2() {
  if (nf) return ds;
  nf = 1;
  var e = ai(),
    t = si(),
    o = uu(),
    i = Object.prototype.toString,
    a = Object.prototype.hasOwnProperty,
    n = 65279,
    r = 9,
    s = 10,
    u = 13,
    f = 32,
    d = 33,
    c = 34,
    l = 35,
    h = 37,
    y = 38,
    F = 39,
    m = 42,
    S = 44,
    E = 45,
    b = 58,
    w = 61,
    A = 62,
    v = 63,
    C = 64,
    g = 91,
    D = 93,
    N = 96,
    P = 123,
    R = 124,
    k = 125,
    q = {};
  ((q[0] = "\\0"),
    (q[7] = "\\a"),
    (q[8] = "\\b"),
    (q[9] = "\\t"),
    (q[10] = "\\n"),
    (q[11] = "\\v"),
    (q[12] = "\\f"),
    (q[13] = "\\r"),
    (q[27] = "\\e"),
    (q[34] = '\\"'),
    (q[92] = "\\\\"),
    (q[133] = "\\N"),
    (q[160] = "\\_"),
    (q[8232] = "\\L"),
    (q[8233] = "\\P"));
  var U = [
      "y",
      "Y",
      "yes",
      "Yes",
      "YES",
      "on",
      "On",
      "ON",
      "n",
      "N",
      "no",
      "No",
      "NO",
      "off",
      "Off",
      "OFF",
    ],
    $ = /^[-+]?[0-9_]+(?::[0-9_]+)+(?:\.[0-9_]*)?$/;
  function V(O, K) {
    var te, Z, oe, se, ve, T, x;
    if (K === null) return {};
    for (te = {}, Z = Object.keys(K), oe = 0, se = Z.length; oe < se; oe += 1)
      ((ve = Z[oe]),
        (T = String(K[ve])),
        ve.slice(0, 2) === "!!" && (ve = "tag:yaml.org,2002:" + ve.slice(2)),
        (x = O.compiledTypeMap.fallback[ve]),
        x && a.call(x.styleAliases, T) && (T = x.styleAliases[T]),
        (te[ve] = T));
    return te;
  }
  function re(O) {
    var K, te, Z;
    if (((K = O.toString(16).toUpperCase()), O <= 255)) ((te = "x"), (Z = 2));
    else if (O <= 65535) ((te = "u"), (Z = 4));
    else if (O <= 4294967295) ((te = "U"), (Z = 8));
    else
      throw new t(
        "code point within a string may not be greater than 0xFFFFFFFF",
      );
    return "\\" + te + e.repeat("0", Z - K.length) + K;
  }
  var X = 1,
    fe = 2;
  function Y(O) {
    ((this.schema = O.schema || o),
      (this.indent = Math.max(1, O.indent || 2)),
      (this.noArrayIndent = O.noArrayIndent || !1),
      (this.skipInvalid = O.skipInvalid || !1),
      (this.flowLevel = e.isNothing(O.flowLevel) ? -1 : O.flowLevel),
      (this.styleMap = V(this.schema, O.styles || null)),
      (this.sortKeys = O.sortKeys || !1),
      (this.lineWidth = O.lineWidth || 80),
      (this.noRefs = O.noRefs || !1),
      (this.noCompatMode = O.noCompatMode || !1),
      (this.condenseFlow = O.condenseFlow || !1),
      (this.quotingType = O.quotingType === '"' ? fe : X),
      (this.forceQuotes = O.forceQuotes || !1),
      (this.replacer = typeof O.replacer == "function" ? O.replacer : null),
      (this.implicitTypes = this.schema.compiledImplicit),
      (this.explicitTypes = this.schema.compiledExplicit),
      (this.tag = null),
      (this.result = ""),
      (this.duplicates = []),
      (this.usedDuplicates = null));
  }
  function Ce(O, K) {
    for (
      var te = e.repeat(" ", K), Z = 0, oe = -1, se = "", ve, T = O.length;
      Z < T;
    )
      ((oe = O.indexOf(
        `
`,
        Z,
      )),
        oe === -1
          ? ((ve = O.slice(Z)), (Z = T))
          : ((ve = O.slice(Z, oe + 1)), (Z = oe + 1)),
        ve.length &&
          ve !==
            `
` &&
          (se += te),
        (se += ve));
    return se;
  }
  function ue(O, K) {
    return (
      `
` + e.repeat(" ", O.indent * K)
    );
  }
  function Ae(O, K) {
    var te, Z, oe;
    for (te = 0, Z = O.implicitTypes.length; te < Z; te += 1)
      if (((oe = O.implicitTypes[te]), oe.resolve(K))) return !0;
    return !1;
  }
  function Q(O) {
    return O === f || O === r;
  }
  function ge(O) {
    return (
      (32 <= O && O <= 126) ||
      (161 <= O && O <= 55295 && O !== 8232 && O !== 8233) ||
      (57344 <= O && O <= 65533 && O !== n) ||
      (65536 <= O && O <= 1114111)
    );
  }
  function I(O) {
    return ge(O) && O !== n && O !== u && O !== s;
  }
  function _(O, K, te) {
    var Z = I(O),
      oe = Z && !Q(O);
    return (
      ((te ? Z : Z && O !== S && O !== g && O !== D && O !== P && O !== k) &&
        O !== l &&
        !(K === b && !oe)) ||
      (I(K) && !Q(K) && O === l) ||
      (K === b && oe)
    );
  }
  function W(O) {
    return (
      ge(O) &&
      O !== n &&
      !Q(O) &&
      O !== E &&
      O !== v &&
      O !== b &&
      O !== S &&
      O !== g &&
      O !== D &&
      O !== P &&
      O !== k &&
      O !== l &&
      O !== y &&
      O !== m &&
      O !== d &&
      O !== R &&
      O !== w &&
      O !== A &&
      O !== F &&
      O !== c &&
      O !== h &&
      O !== C &&
      O !== N
    );
  }
  function M(O) {
    return !Q(O) && O !== b;
  }
  function le(O, K) {
    var te = O.charCodeAt(K),
      Z;
    return te >= 55296 &&
      te <= 56319 &&
      K + 1 < O.length &&
      ((Z = O.charCodeAt(K + 1)), Z >= 56320 && Z <= 57343)
      ? (te - 55296) * 1024 + Z - 56320 + 65536
      : te;
  }
  function he(O) {
    var K = /^\n* /;
    return K.test(O);
  }
  var we = 1,
    be = 2,
    Fe = 3,
    Oe = 4,
    Le = 5;
  function Ge(O, K, te, Z, oe, se, ve, T) {
    var x,
      B = 0,
      H = null,
      ie = !1,
      pe = !1,
      Be = Z !== -1,
      Me = -1,
      Ze = W(le(O, 0)) && M(le(O, O.length - 1));
    if (K || ve)
      for (x = 0; x < O.length; B >= 65536 ? (x += 2) : x++) {
        if (((B = le(O, x)), !ge(B))) return Le;
        ((Ze = Ze && _(B, H, T)), (H = B));
      }
    else {
      for (x = 0; x < O.length; B >= 65536 ? (x += 2) : x++) {
        if (((B = le(O, x)), B === s))
          ((ie = !0),
            Be &&
              ((pe = pe || (x - Me - 1 > Z && O[Me + 1] !== " ")), (Me = x)));
        else if (!ge(B)) return Le;
        ((Ze = Ze && _(B, H, T)), (H = B));
      }
      pe = pe || (Be && x - Me - 1 > Z && O[Me + 1] !== " ");
    }
    return !ie && !pe
      ? Ze && !ve && !oe(O)
        ? we
        : se === fe
          ? Le
          : be
      : te > 9 && he(O)
        ? Le
        : ve
          ? se === fe
            ? Le
            : be
          : pe
            ? Oe
            : Fe;
  }
  function nt(O, K, te, Z, oe) {
    O.dump = (function () {
      if (K.length === 0) return O.quotingType === fe ? '""' : "''";
      if (!O.noCompatMode && (U.indexOf(K) !== -1 || $.test(K)))
        return O.quotingType === fe ? '"' + K + '"' : "'" + K + "'";
      var se = O.indent * Math.max(1, te),
        ve =
          O.lineWidth === -1
            ? -1
            : Math.max(Math.min(O.lineWidth, 40), O.lineWidth - se),
        T = Z || (O.flowLevel > -1 && te >= O.flowLevel);
      function x(B) {
        return Ae(O, B);
      }
      switch (
        Ge(K, T, O.indent, ve, x, O.quotingType, O.forceQuotes && !Z, oe)
      ) {
        case we:
          return K;
        case be:
          return "'" + K.replace(/'/g, "''") + "'";
        case Fe:
          return "|" + ht(K, O.indent) + p(Ce(K, se));
        case Oe:
          return ">" + ht(K, O.indent) + p(Ce(z(K, ve), se));
        case Le:
          return '"' + de(K) + '"';
        default:
          throw new t("impossible error: invalid scalar style");
      }
    })();
  }
  function ht(O, K) {
    var te = he(O) ? String(K) : "",
      Z =
        O[O.length - 1] ===
        `
`,
      oe =
        Z &&
        (O[O.length - 2] ===
          `
` ||
          O ===
            `
`),
      se = oe ? "+" : Z ? "" : "-";
    return (
      te +
      se +
      `
`
    );
  }
  function p(O) {
    return O[O.length - 1] ===
      `
`
      ? O.slice(0, -1)
      : O;
  }
  function z(O, K) {
    for (
      var te = /(\n+)([^\n]*)/g,
        Z = (function () {
          var B = O.indexOf(`
`);
          return (
            (B = B !== -1 ? B : O.length),
            (te.lastIndex = B),
            J(O.slice(0, B), K)
          );
        })(),
        oe =
          O[0] ===
            `
` || O[0] === " ",
        se,
        ve;
      (ve = te.exec(O));
    ) {
      var T = ve[1],
        x = ve[2];
      ((se = x[0] === " "),
        (Z +=
          T +
          (!oe && !se && x !== ""
            ? `
`
            : "") +
          J(x, K)),
        (oe = se));
    }
    return Z;
  }
  function J(O, K) {
    if (O === "" || O[0] === " ") return O;
    for (
      var te = / [^ ]/g, Z, oe = 0, se, ve = 0, T = 0, x = "";
      (Z = te.exec(O));
    )
      ((T = Z.index),
        T - oe > K &&
          ((se = ve > oe ? ve : T),
          (x +=
            `
` + O.slice(oe, se)),
          (oe = se + 1)),
        (ve = T));
    return (
      (x += `
`),
      O.length - oe > K && ve > oe
        ? (x +=
            O.slice(oe, ve) +
            `
` +
            O.slice(ve + 1))
        : (x += O.slice(oe)),
      x.slice(1)
    );
  }
  function de(O) {
    for (
      var K = "", te = 0, Z, oe = 0;
      oe < O.length;
      te >= 65536 ? (oe += 2) : oe++
    )
      ((te = le(O, oe)),
        (Z = q[te]),
        !Z && ge(te)
          ? ((K += O[oe]), te >= 65536 && (K += O[oe + 1]))
          : (K += Z || re(te)));
    return K;
  }
  function ee(O, K, te) {
    var Z = "",
      oe = O.tag,
      se,
      ve,
      T;
    for (se = 0, ve = te.length; se < ve; se += 1)
      ((T = te[se]),
        O.replacer && (T = O.replacer.call(te, String(se), T)),
        (_e(O, K, T, !1, !1) || (typeof T > "u" && _e(O, K, null, !1, !1))) &&
          (Z !== "" && (Z += "," + (O.condenseFlow ? "" : " ")),
          (Z += O.dump)));
    ((O.tag = oe), (O.dump = "[" + Z + "]"));
  }
  function ce(O, K, te, Z) {
    var oe = "",
      se = O.tag,
      ve,
      T,
      x;
    for (ve = 0, T = te.length; ve < T; ve += 1)
      ((x = te[ve]),
        O.replacer && (x = O.replacer.call(te, String(ve), x)),
        (_e(O, K + 1, x, !0, !0, !1, !0) ||
          (typeof x > "u" && _e(O, K + 1, null, !0, !0, !1, !0))) &&
          ((!Z || oe !== "") && (oe += ue(O, K)),
          O.dump && s === O.dump.charCodeAt(0) ? (oe += "-") : (oe += "- "),
          (oe += O.dump)));
    ((O.tag = se), (O.dump = oe || "[]"));
  }
  function ae(O, K, te) {
    var Z = "",
      oe = O.tag,
      se = Object.keys(te),
      ve,
      T,
      x,
      B,
      H;
    for (ve = 0, T = se.length; ve < T; ve += 1)
      ((H = ""),
        Z !== "" && (H += ", "),
        O.condenseFlow && (H += '"'),
        (x = se[ve]),
        (B = te[x]),
        O.replacer && (B = O.replacer.call(te, x, B)),
        _e(O, K, x, !1, !1) &&
          (O.dump.length > 1024 && (H += "? "),
          (H +=
            O.dump +
            (O.condenseFlow ? '"' : "") +
            ":" +
            (O.condenseFlow ? "" : " ")),
          _e(O, K, B, !1, !1) && ((H += O.dump), (Z += H))));
    ((O.tag = oe), (O.dump = "{" + Z + "}"));
  }
  function De(O, K, te, Z) {
    var oe = "",
      se = O.tag,
      ve = Object.keys(te),
      T,
      x,
      B,
      H,
      ie,
      pe;
    if (O.sortKeys === !0) ve.sort();
    else if (typeof O.sortKeys == "function") ve.sort(O.sortKeys);
    else if (O.sortKeys)
      throw new t("sortKeys must be a boolean or a function");
    for (T = 0, x = ve.length; T < x; T += 1)
      ((pe = ""),
        (!Z || oe !== "") && (pe += ue(O, K)),
        (B = ve[T]),
        (H = te[B]),
        O.replacer && (H = O.replacer.call(te, B, H)),
        _e(O, K + 1, B, !0, !0, !0) &&
          ((ie =
            (O.tag !== null && O.tag !== "?") ||
            (O.dump && O.dump.length > 1024)),
          ie &&
            (O.dump && s === O.dump.charCodeAt(0) ? (pe += "?") : (pe += "? ")),
          (pe += O.dump),
          ie && (pe += ue(O, K)),
          _e(O, K + 1, H, !0, ie) &&
            (O.dump && s === O.dump.charCodeAt(0) ? (pe += ":") : (pe += ": "),
            (pe += O.dump),
            (oe += pe))));
    ((O.tag = se), (O.dump = oe || "{}"));
  }
  function Se(O, K, te) {
    var Z, oe, se, ve, T, x;
    for (
      oe = te ? O.explicitTypes : O.implicitTypes, se = 0, ve = oe.length;
      se < ve;
      se += 1
    )
      if (
        ((T = oe[se]),
        (T.instanceOf || T.predicate) &&
          (!T.instanceOf ||
            (typeof K == "object" && K instanceof T.instanceOf)) &&
          (!T.predicate || T.predicate(K)))
      ) {
        if (
          (te
            ? T.multi && T.representName
              ? (O.tag = T.representName(K))
              : (O.tag = T.tag)
            : (O.tag = "?"),
          T.represent)
        ) {
          if (
            ((x = O.styleMap[T.tag] || T.defaultStyle),
            i.call(T.represent) === "[object Function]")
          )
            Z = T.represent(K, x);
          else if (a.call(T.represent, x)) Z = T.represent[x](K, x);
          else
            throw new t(
              "!<" + T.tag + '> tag resolver accepts not "' + x + '" style',
            );
          O.dump = Z;
        }
        return !0;
      }
    return !1;
  }
  function _e(O, K, te, Z, oe, se, ve) {
    ((O.tag = null), (O.dump = te), Se(O, te, !1) || Se(O, te, !0));
    var T = i.call(O.dump),
      x = Z,
      B;
    Z && (Z = O.flowLevel < 0 || O.flowLevel > K);
    var H = T === "[object Object]" || T === "[object Array]",
      ie,
      pe;
    if (
      (H && ((ie = O.duplicates.indexOf(te)), (pe = ie !== -1)),
      ((O.tag !== null && O.tag !== "?") || pe || (O.indent !== 2 && K > 0)) &&
        (oe = !1),
      pe && O.usedDuplicates[ie])
    )
      O.dump = "*ref_" + ie;
    else {
      if (
        (H && pe && !O.usedDuplicates[ie] && (O.usedDuplicates[ie] = !0),
        T === "[object Object]")
      )
        Z && Object.keys(O.dump).length !== 0
          ? (De(O, K, O.dump, oe), pe && (O.dump = "&ref_" + ie + O.dump))
          : (ae(O, K, O.dump), pe && (O.dump = "&ref_" + ie + " " + O.dump));
      else if (T === "[object Array]")
        Z && O.dump.length !== 0
          ? (O.noArrayIndent && !ve && K > 0
              ? ce(O, K - 1, O.dump, oe)
              : ce(O, K, O.dump, oe),
            pe && (O.dump = "&ref_" + ie + O.dump))
          : (ee(O, K, O.dump), pe && (O.dump = "&ref_" + ie + " " + O.dump));
      else if (T === "[object String]")
        O.tag !== "?" && nt(O, O.dump, K, se, x);
      else {
        if (T === "[object Undefined]") return !1;
        if (O.skipInvalid) return !1;
        throw new t("unacceptable kind of an object to dump " + T);
      }
      O.tag !== null &&
        O.tag !== "?" &&
        ((B = encodeURI(O.tag[0] === "!" ? O.tag.slice(1) : O.tag).replace(
          /!/g,
          "%21",
        )),
        O.tag[0] === "!"
          ? (B = "!" + B)
          : B.slice(0, 18) === "tag:yaml.org,2002:"
            ? (B = "!!" + B.slice(18))
            : (B = "!<" + B + ">"),
        (O.dump = B + " " + O.dump));
    }
    return !0;
  }
  function Pe(O, K) {
    var te = [],
      Z = [],
      oe,
      se;
    for (Ee(O, te, Z), oe = 0, se = Z.length; oe < se; oe += 1)
      K.duplicates.push(te[Z[oe]]);
    K.usedDuplicates = new Array(se);
  }
  function Ee(O, K, te) {
    var Z, oe, se;
    if (O !== null && typeof O == "object")
      if (((oe = K.indexOf(O)), oe !== -1))
        te.indexOf(oe) === -1 && te.push(oe);
      else if ((K.push(O), Array.isArray(O)))
        for (oe = 0, se = O.length; oe < se; oe += 1) Ee(O[oe], K, te);
      else
        for (Z = Object.keys(O), oe = 0, se = Z.length; oe < se; oe += 1)
          Ee(O[Z[oe]], K, te);
  }
  function je(O, K) {
    K = K || {};
    var te = new Y(K);
    te.noRefs || Pe(O, te);
    var Z = O;
    return (
      te.replacer && (Z = te.replacer.call({ "": Z }, "", Z)),
      _e(te, 0, Z, !0, !0)
        ? te.dump +
          `
`
        : ""
    );
  }
  return ((ds.dump = je), ds);
}
var of;
function lu() {
  if (of) return at;
  of = 1;
  var e = d2(),
    t = h2();
  function o(i, a) {
    return function () {
      throw new Error(
        "Function yaml." +
          i +
          " is removed in js-yaml 4. Use yaml." +
          a +
          " instead, which is now safe by default.",
      );
    };
  }
  return (
    (at.Type = dt()),
    (at.Schema = up()),
    (at.FAILSAFE_SCHEMA = dp()),
    (at.JSON_SCHEMA = gp()),
    (at.CORE_SCHEMA = wp()),
    (at.DEFAULT_SCHEMA = uu()),
    (at.load = e.load),
    (at.loadAll = e.loadAll),
    (at.dump = t.dump),
    (at.YAMLException = si()),
    (at.types = {
      binary: vp(),
      float: mp(),
      map: fp(),
      null: hp(),
      pairs: Ap(),
      set: bp(),
      timestamp: yp(),
      bool: pp(),
      int: Dp(),
      merge: Ep(),
      omap: Cp(),
      seq: cp(),
      str: lp(),
    }),
    (at.safeLoad = o("safeLoad", "load")),
    (at.safeLoadAll = o("safeLoadAll", "loadAll")),
    (at.safeDump = o("safeDump", "dump")),
    at
  );
}
var yn = {},
  af;
function p2() {
  if (af) return yn;
  ((af = 1),
    Object.defineProperty(yn, "__esModule", { value: !0 }),
    (yn.Lazy = void 0));
  class e {
    constructor(o) {
      ((this._value = null), (this.creator = o));
    }
    get hasValue() {
      return this.creator == null;
    }
    get value() {
      if (this.creator == null) return this._value;
      const o = this.creator();
      return ((this.value = o), o);
    }
    set value(o) {
      ((this._value = o), (this.creator = null));
    }
  }
  return ((yn.Lazy = e), yn);
}
var jr = {},
  jn = { exports: {} };
jn.exports;
var sf;
function D2() {
  return (
    sf ||
      ((sf = 1),
      (function (e, t) {
        var o = 200,
          i = "__lodash_hash_undefined__",
          a = 1,
          n = 2,
          r = 9007199254740991,
          s = "[object Arguments]",
          u = "[object Array]",
          f = "[object AsyncFunction]",
          d = "[object Boolean]",
          c = "[object Date]",
          l = "[object Error]",
          h = "[object Function]",
          y = "[object GeneratorFunction]",
          F = "[object Map]",
          m = "[object Number]",
          S = "[object Null]",
          E = "[object Object]",
          b = "[object Promise]",
          w = "[object Proxy]",
          A = "[object RegExp]",
          v = "[object Set]",
          C = "[object String]",
          g = "[object Symbol]",
          D = "[object Undefined]",
          N = "[object WeakMap]",
          P = "[object ArrayBuffer]",
          R = "[object DataView]",
          k = "[object Float32Array]",
          q = "[object Float64Array]",
          U = "[object Int8Array]",
          $ = "[object Int16Array]",
          V = "[object Int32Array]",
          re = "[object Uint8Array]",
          X = "[object Uint8ClampedArray]",
          fe = "[object Uint16Array]",
          Y = "[object Uint32Array]",
          Ce = /[\\^$.*+?()[\]{}|]/g,
          ue = /^\[object .+?Constructor\]$/,
          Ae = /^(?:0|[1-9]\d*)$/,
          Q = {};
        ((Q[k] = Q[q] = Q[U] = Q[$] = Q[V] = Q[re] = Q[X] = Q[fe] = Q[Y] = !0),
          (Q[s] =
            Q[u] =
            Q[P] =
            Q[d] =
            Q[R] =
            Q[c] =
            Q[l] =
            Q[h] =
            Q[F] =
            Q[m] =
            Q[E] =
            Q[A] =
            Q[v] =
            Q[C] =
            Q[N] =
              !1));
        var ge = typeof Nt == "object" && Nt && Nt.Object === Object && Nt,
          I = typeof self == "object" && self && self.Object === Object && self,
          _ = ge || I || Function("return this")(),
          W = t && !t.nodeType && t,
          M = W && !0 && e && !e.nodeType && e,
          le = M && M.exports === W,
          he = le && ge.process,
          we = (function () {
            try {
              return he && he.binding && he.binding("util");
            } catch {}
          })(),
          be = we && we.isTypedArray;
        function Fe(L, j) {
          for (
            var ne = -1, me = L == null ? 0 : L.length, Ue = 0, xe = [];
            ++ne < me;
          ) {
            var We = L[ne];
            j(We, ne, L) && (xe[Ue++] = We);
          }
          return xe;
        }
        function Oe(L, j) {
          for (var ne = -1, me = j.length, Ue = L.length; ++ne < me;)
            L[Ue + ne] = j[ne];
          return L;
        }
        function Le(L, j) {
          for (var ne = -1, me = L == null ? 0 : L.length; ++ne < me;)
            if (j(L[ne], ne, L)) return !0;
          return !1;
        }
        function Ge(L, j) {
          for (var ne = -1, me = Array(L); ++ne < L;) me[ne] = j(ne);
          return me;
        }
        function nt(L) {
          return function (j) {
            return L(j);
          };
        }
        function ht(L, j) {
          return L.has(j);
        }
        function p(L, j) {
          return L?.[j];
        }
        function z(L) {
          var j = -1,
            ne = Array(L.size);
          return (
            L.forEach(function (me, Ue) {
              ne[++j] = [Ue, me];
            }),
            ne
          );
        }
        function J(L, j) {
          return function (ne) {
            return L(j(ne));
          };
        }
        function de(L) {
          var j = -1,
            ne = Array(L.size);
          return (
            L.forEach(function (me) {
              ne[++j] = me;
            }),
            ne
          );
        }
        var ee = Array.prototype,
          ce = Function.prototype,
          ae = Object.prototype,
          De = _["__core-js_shared__"],
          Se = ce.toString,
          _e = ae.hasOwnProperty,
          Pe = (function () {
            var L = /[^.]+$/.exec((De && De.keys && De.keys.IE_PROTO) || "");
            return L ? "Symbol(src)_1." + L : "";
          })(),
          Ee = ae.toString,
          je = RegExp(
            "^" +
              Se.call(_e)
                .replace(Ce, "\\$&")
                .replace(
                  /hasOwnProperty|(function).*?(?=\\\()| for .+?(?=\\\])/g,
                  "$1.*?",
                ) +
              "$",
          ),
          O = le ? _.Buffer : void 0,
          K = _.Symbol,
          te = _.Uint8Array,
          Z = ae.propertyIsEnumerable,
          oe = ee.splice,
          se = K ? K.toStringTag : void 0,
          ve = Object.getOwnPropertySymbols,
          T = O ? O.isBuffer : void 0,
          x = J(Object.keys, Object),
          B = Mr(_, "DataView"),
          H = Mr(_, "Map"),
          ie = Mr(_, "Promise"),
          pe = Mr(_, "Set"),
          Be = Mr(_, "WeakMap"),
          Me = Mr(Object, "create"),
          Ze = wr(B),
          Ot = wr(H),
          St = wr(ie),
          qt = wr(pe),
          $t = wr(Be),
          Pt = K ? K.prototype : void 0,
          pt = Pt ? Pt.valueOf : void 0;
        function ct(L) {
          var j = -1,
            ne = L == null ? 0 : L.length;
          for (this.clear(); ++j < ne;) {
            var me = L[j];
            this.set(me[0], me[1]);
          }
        }
        function mr() {
          ((this.__data__ = Me ? Me(null) : {}), (this.size = 0));
        }
        function Je(L) {
          var j = this.has(L) && delete this.__data__[L];
          return ((this.size -= j ? 1 : 0), j);
        }
        function ui(L) {
          var j = this.__data__;
          if (Me) {
            var ne = j[L];
            return ne === i ? void 0 : ne;
          }
          return _e.call(j, L) ? j[L] : void 0;
        }
        function Qt(L) {
          var j = this.__data__;
          return Me ? j[L] !== void 0 : _e.call(j, L);
        }
        function li(L, j) {
          var ne = this.__data__;
          return (
            (this.size += this.has(L) ? 0 : 1),
            (ne[L] = Me && j === void 0 ? i : j),
            this
          );
        }
        ((ct.prototype.clear = mr),
          (ct.prototype.delete = Je),
          (ct.prototype.get = ui),
          (ct.prototype.has = Qt),
          (ct.prototype.set = li));
        function jt(L) {
          var j = -1,
            ne = L == null ? 0 : L.length;
          for (this.clear(); ++j < ne;) {
            var me = L[j];
            this.set(me[0], me[1]);
          }
        }
        function PD() {
          ((this.__data__ = []), (this.size = 0));
        }
        function RD(L) {
          var j = this.__data__,
            ne = fi(j, L);
          if (ne < 0) return !1;
          var me = j.length - 1;
          return (ne == me ? j.pop() : oe.call(j, ne, 1), --this.size, !0);
        }
        function LD(L) {
          var j = this.__data__,
            ne = fi(j, L);
          return ne < 0 ? void 0 : j[ne][1];
        }
        function BD(L) {
          return fi(this.__data__, L) > -1;
        }
        function kD(L, j) {
          var ne = this.__data__,
            me = fi(ne, L);
          return (
            me < 0 ? (++this.size, ne.push([L, j])) : (ne[me][1] = j),
            this
          );
        }
        ((jt.prototype.clear = PD),
          (jt.prototype.delete = RD),
          (jt.prototype.get = LD),
          (jt.prototype.has = BD),
          (jt.prototype.set = kD));
        function gr(L) {
          var j = -1,
            ne = L == null ? 0 : L.length;
          for (this.clear(); ++j < ne;) {
            var me = L[j];
            this.set(me[0], me[1]);
          }
        }
        function MD() {
          ((this.size = 0),
            (this.__data__ = {
              hash: new ct(),
              map: new (H || jt)(),
              string: new ct(),
            }));
        }
        function UD(L) {
          var j = di(this, L).delete(L);
          return ((this.size -= j ? 1 : 0), j);
        }
        function qD(L) {
          return di(this, L).get(L);
        }
        function $D(L) {
          return di(this, L).has(L);
        }
        function jD(L, j) {
          var ne = di(this, L),
            me = ne.size;
          return (ne.set(L, j), (this.size += ne.size == me ? 0 : 1), this);
        }
        ((gr.prototype.clear = MD),
          (gr.prototype.delete = UD),
          (gr.prototype.get = qD),
          (gr.prototype.has = $D),
          (gr.prototype.set = jD));
        function ci(L) {
          var j = -1,
            ne = L == null ? 0 : L.length;
          for (this.__data__ = new gr(); ++j < ne;) this.add(L[j]);
        }
        function WD(L) {
          return (this.__data__.set(L, i), this);
        }
        function HD(L) {
          return this.__data__.has(L);
        }
        ((ci.prototype.add = ci.prototype.push = WD), (ci.prototype.has = HD));
        function Zt(L) {
          var j = (this.__data__ = new jt(L));
          this.size = j.size;
        }
        function GD() {
          ((this.__data__ = new jt()), (this.size = 0));
        }
        function VD(L) {
          var j = this.__data__,
            ne = j.delete(L);
          return ((this.size = j.size), ne);
        }
        function zD(L) {
          return this.__data__.get(L);
        }
        function XD(L) {
          return this.__data__.has(L);
        }
        function YD(L, j) {
          var ne = this.__data__;
          if (ne instanceof jt) {
            var me = ne.__data__;
            if (!H || me.length < o - 1)
              return (me.push([L, j]), (this.size = ++ne.size), this);
            ne = this.__data__ = new gr(me);
          }
          return (ne.set(L, j), (this.size = ne.size), this);
        }
        ((Zt.prototype.clear = GD),
          (Zt.prototype.delete = VD),
          (Zt.prototype.get = zD),
          (Zt.prototype.has = XD),
          (Zt.prototype.set = YD));
        function KD(L, j) {
          var ne = hi(L),
            me = !ne && fm(L),
            Ue = !ne && !me && Zo(L),
            xe = !ne && !me && !Ue && zu(L),
            We = ne || me || Ue || xe,
            Qe = We ? Ge(L.length, String) : [],
            et = Qe.length;
          for (var $e in L)
            _e.call(L, $e) &&
              !(
                We &&
                ($e == "length" ||
                  (Ue && ($e == "offset" || $e == "parent")) ||
                  (xe &&
                    ($e == "buffer" ||
                      $e == "byteLength" ||
                      $e == "byteOffset")) ||
                  am($e, et))
              ) &&
              Qe.push($e);
          return Qe;
        }
        function fi(L, j) {
          for (var ne = L.length; ne--;) if (Wu(L[ne][0], j)) return ne;
          return -1;
        }
        function JD(L, j, ne) {
          var me = j(L);
          return hi(L) ? me : Oe(me, ne(L));
        }
        function cn(L) {
          return L == null
            ? L === void 0
              ? D
              : S
            : se && se in Object(L)
              ? im(L)
              : cm(L);
        }
        function Uu(L) {
          return fn(L) && cn(L) == s;
        }
        function qu(L, j, ne, me, Ue) {
          return L === j
            ? !0
            : L == null || j == null || (!fn(L) && !fn(j))
              ? L !== L && j !== j
              : QD(L, j, ne, me, qu, Ue);
        }
        function QD(L, j, ne, me, Ue, xe) {
          var We = hi(L),
            Qe = hi(j),
            et = We ? u : er(L),
            $e = Qe ? u : er(j);
          ((et = et == s ? E : et), ($e = $e == s ? E : $e));
          var gt = et == E,
            _t = $e == E,
            it = et == $e;
          if (it && Zo(L)) {
            if (!Zo(j)) return !1;
            ((We = !0), (gt = !1));
          }
          if (it && !gt)
            return (
              xe || (xe = new Zt()),
              We || zu(L)
                ? $u(L, j, ne, me, Ue, xe)
                : rm(L, j, et, ne, me, Ue, xe)
            );
          if (!(ne & a)) {
            var vt = gt && _e.call(L, "__wrapped__"),
              Ct = _t && _e.call(j, "__wrapped__");
            if (vt || Ct) {
              var tr = vt ? L.value() : L,
                Wt = Ct ? j.value() : j;
              return (xe || (xe = new Zt()), Ue(tr, Wt, ne, me, xe));
            }
          }
          return it ? (xe || (xe = new Zt()), nm(L, j, ne, me, Ue, xe)) : !1;
        }
        function ZD(L) {
          if (!Vu(L) || um(L)) return !1;
          var j = Hu(L) ? je : ue;
          return j.test(wr(L));
        }
        function em(L) {
          return fn(L) && Gu(L.length) && !!Q[cn(L)];
        }
        function tm(L) {
          if (!lm(L)) return x(L);
          var j = [];
          for (var ne in Object(L))
            _e.call(L, ne) && ne != "constructor" && j.push(ne);
          return j;
        }
        function $u(L, j, ne, me, Ue, xe) {
          var We = ne & a,
            Qe = L.length,
            et = j.length;
          if (Qe != et && !(We && et > Qe)) return !1;
          var $e = xe.get(L);
          if ($e && xe.get(j)) return $e == j;
          var gt = -1,
            _t = !0,
            it = ne & n ? new ci() : void 0;
          for (xe.set(L, j), xe.set(j, L); ++gt < Qe;) {
            var vt = L[gt],
              Ct = j[gt];
            if (me)
              var tr = We ? me(Ct, vt, gt, j, L, xe) : me(vt, Ct, gt, L, j, xe);
            if (tr !== void 0) {
              if (tr) continue;
              _t = !1;
              break;
            }
            if (it) {
              if (
                !Le(j, function (Wt, yr) {
                  if (!ht(it, yr) && (vt === Wt || Ue(vt, Wt, ne, me, xe)))
                    return it.push(yr);
                })
              ) {
                _t = !1;
                break;
              }
            } else if (!(vt === Ct || Ue(vt, Ct, ne, me, xe))) {
              _t = !1;
              break;
            }
          }
          return (xe.delete(L), xe.delete(j), _t);
        }
        function rm(L, j, ne, me, Ue, xe, We) {
          switch (ne) {
            case R:
              if (L.byteLength != j.byteLength || L.byteOffset != j.byteOffset)
                return !1;
              ((L = L.buffer), (j = j.buffer));
            case P:
              return !(
                L.byteLength != j.byteLength || !xe(new te(L), new te(j))
              );
            case d:
            case c:
            case m:
              return Wu(+L, +j);
            case l:
              return L.name == j.name && L.message == j.message;
            case A:
            case C:
              return L == j + "";
            case F:
              var Qe = z;
            case v:
              var et = me & a;
              if ((Qe || (Qe = de), L.size != j.size && !et)) return !1;
              var $e = We.get(L);
              if ($e) return $e == j;
              ((me |= n), We.set(L, j));
              var gt = $u(Qe(L), Qe(j), me, Ue, xe, We);
              return (We.delete(L), gt);
            case g:
              if (pt) return pt.call(L) == pt.call(j);
          }
          return !1;
        }
        function nm(L, j, ne, me, Ue, xe) {
          var We = ne & a,
            Qe = ju(L),
            et = Qe.length,
            $e = ju(j),
            gt = $e.length;
          if (et != gt && !We) return !1;
          for (var _t = et; _t--;) {
            var it = Qe[_t];
            if (!(We ? it in j : _e.call(j, it))) return !1;
          }
          var vt = xe.get(L);
          if (vt && xe.get(j)) return vt == j;
          var Ct = !0;
          (xe.set(L, j), xe.set(j, L));
          for (var tr = We; ++_t < et;) {
            it = Qe[_t];
            var Wt = L[it],
              yr = j[it];
            if (me)
              var Xu = We ? me(yr, Wt, it, j, L, xe) : me(Wt, yr, it, L, j, xe);
            if (!(Xu === void 0 ? Wt === yr || Ue(Wt, yr, ne, me, xe) : Xu)) {
              Ct = !1;
              break;
            }
            tr || (tr = it == "constructor");
          }
          if (Ct && !tr) {
            var pi = L.constructor,
              Di = j.constructor;
            pi != Di &&
              "constructor" in L &&
              "constructor" in j &&
              !(
                typeof pi == "function" &&
                pi instanceof pi &&
                typeof Di == "function" &&
                Di instanceof Di
              ) &&
              (Ct = !1);
          }
          return (xe.delete(L), xe.delete(j), Ct);
        }
        function ju(L) {
          return JD(L, pm, om);
        }
        function di(L, j) {
          var ne = L.__data__;
          return sm(j) ? ne[typeof j == "string" ? "string" : "hash"] : ne.map;
        }
        function Mr(L, j) {
          var ne = p(L, j);
          return ZD(ne) ? ne : void 0;
        }
        function im(L) {
          var j = _e.call(L, se),
            ne = L[se];
          try {
            L[se] = void 0;
            var me = !0;
          } catch {}
          var Ue = Ee.call(L);
          return (me && (j ? (L[se] = ne) : delete L[se]), Ue);
        }
        var om = ve
            ? function (L) {
                return L == null
                  ? []
                  : ((L = Object(L)),
                    Fe(ve(L), function (j) {
                      return Z.call(L, j);
                    }));
              }
            : Dm,
          er = cn;
        ((B && er(new B(new ArrayBuffer(1))) != R) ||
          (H && er(new H()) != F) ||
          (ie && er(ie.resolve()) != b) ||
          (pe && er(new pe()) != v) ||
          (Be && er(new Be()) != N)) &&
          (er = function (L) {
            var j = cn(L),
              ne = j == E ? L.constructor : void 0,
              me = ne ? wr(ne) : "";
            if (me)
              switch (me) {
                case Ze:
                  return R;
                case Ot:
                  return F;
                case St:
                  return b;
                case qt:
                  return v;
                case $t:
                  return N;
              }
            return j;
          });
        function am(L, j) {
          return (
            (j = j ?? r),
            !!j &&
              (typeof L == "number" || Ae.test(L)) &&
              L > -1 &&
              L % 1 == 0 &&
              L < j
          );
        }
        function sm(L) {
          var j = typeof L;
          return j == "string" ||
            j == "number" ||
            j == "symbol" ||
            j == "boolean"
            ? L !== "__proto__"
            : L === null;
        }
        function um(L) {
          return !!Pe && Pe in L;
        }
        function lm(L) {
          var j = L && L.constructor,
            ne = (typeof j == "function" && j.prototype) || ae;
          return L === ne;
        }
        function cm(L) {
          return Ee.call(L);
        }
        function wr(L) {
          if (L != null) {
            try {
              return Se.call(L);
            } catch {}
            try {
              return L + "";
            } catch {}
          }
          return "";
        }
        function Wu(L, j) {
          return L === j || (L !== L && j !== j);
        }
        var fm = Uu(
            (function () {
              return arguments;
            })(),
          )
            ? Uu
            : function (L) {
                return fn(L) && _e.call(L, "callee") && !Z.call(L, "callee");
              },
          hi = Array.isArray;
        function dm(L) {
          return L != null && Gu(L.length) && !Hu(L);
        }
        var Zo = T || mm;
        function hm(L, j) {
          return qu(L, j);
        }
        function Hu(L) {
          if (!Vu(L)) return !1;
          var j = cn(L);
          return j == h || j == y || j == f || j == w;
        }
        function Gu(L) {
          return typeof L == "number" && L > -1 && L % 1 == 0 && L <= r;
        }
        function Vu(L) {
          var j = typeof L;
          return L != null && (j == "object" || j == "function");
        }
        function fn(L) {
          return L != null && typeof L == "object";
        }
        var zu = be ? nt(be) : em;
        function pm(L) {
          return dm(L) ? KD(L) : tm(L);
        }
        function Dm() {
          return [];
        }
        function mm() {
          return !1;
        }
        e.exports = hm;
      })(jn, jn.exports)),
    jn.exports
  );
}
var uf;
function m2() {
  if (uf) return jr;
  ((uf = 1),
    Object.defineProperty(jr, "__esModule", { value: !0 }),
    (jr.DownloadedUpdateHelper = void 0),
    (jr.createTempUpdateFile = s));
  const e = xt,
    t = ze,
    o = D2(),
    i = Dr(),
    a = G;
  let n = class {
    constructor(f) {
      ((this.cacheDir = f),
        (this._file = null),
        (this._packageFile = null),
        (this.versionInfo = null),
        (this.fileInfo = null),
        (this._downloadedFileInfo = null));
    }
    get downloadedFileInfo() {
      return this._downloadedFileInfo;
    }
    get file() {
      return this._file;
    }
    get packageFile() {
      return this._packageFile;
    }
    get cacheDirForPendingUpdate() {
      return a.join(this.cacheDir, "pending");
    }
    async validateDownloadedPath(f, d, c, l) {
      if (this.versionInfo != null && this.file === f && this.fileInfo != null)
        return o(this.versionInfo, d) &&
          o(this.fileInfo.info, c.info) &&
          (await (0, i.pathExists)(f))
          ? f
          : null;
      const h = await this.getValidCachedUpdateFile(c, l);
      return h === null
        ? null
        : (l.info(`Update has already been downloaded to ${f}).`),
          (this._file = h),
          h);
    }
    async setDownloadedFile(f, d, c, l, h, y) {
      ((this._file = f),
        (this._packageFile = d),
        (this.versionInfo = c),
        (this.fileInfo = l),
        (this._downloadedFileInfo = {
          fileName: h,
          sha512: l.info.sha512,
          isAdminRightsRequired: l.info.isAdminRightsRequired === !0,
        }),
        y &&
          (await (0, i.outputJson)(
            this.getUpdateInfoFile(),
            this._downloadedFileInfo,
          )));
    }
    async clear() {
      ((this._file = null),
        (this._packageFile = null),
        (this.versionInfo = null),
        (this.fileInfo = null),
        await this.cleanCacheDirForPendingUpdate());
    }
    async cleanCacheDirForPendingUpdate() {
      try {
        await (0, i.emptyDir)(this.cacheDirForPendingUpdate);
      } catch {}
    }
    async getValidCachedUpdateFile(f, d) {
      const c = this.getUpdateInfoFile();
      if (!(await (0, i.pathExists)(c))) return null;
      let h;
      try {
        h = await (0, i.readJson)(c);
      } catch (S) {
        let E = "No cached update info available";
        return (
          S.code !== "ENOENT" &&
            (await this.cleanCacheDirForPendingUpdate(),
            (E += ` (error on read: ${S.message})`)),
          d.info(E),
          null
        );
      }
      if (!(h?.fileName !== null))
        return (
          d.warn(
            "Cached update info is corrupted: no fileName, directory for cached update will be cleaned",
          ),
          await this.cleanCacheDirForPendingUpdate(),
          null
        );
      if (f.info.sha512 !== h.sha512)
        return (
          d.info(
            `Cached update sha512 checksum doesn't match the latest available update. New update must be downloaded. Cached: ${h.sha512}, expected: ${f.info.sha512}. Directory for cached update will be cleaned`,
          ),
          await this.cleanCacheDirForPendingUpdate(),
          null
        );
      const F = a.join(this.cacheDirForPendingUpdate, h.fileName);
      if (!(await (0, i.pathExists)(F)))
        return (d.info("Cached update file doesn't exist"), null);
      const m = await r(F);
      return f.info.sha512 !== m
        ? (d.warn(
            `Sha512 checksum doesn't match the latest available update. New update must be downloaded. Cached: ${m}, expected: ${f.info.sha512}`,
          ),
          await this.cleanCacheDirForPendingUpdate(),
          null)
        : ((this._downloadedFileInfo = h), F);
    }
    getUpdateInfoFile() {
      return a.join(this.cacheDirForPendingUpdate, "update-info.json");
    }
  };
  jr.DownloadedUpdateHelper = n;
  function r(u, f = "sha512", d = "base64", c) {
    return new Promise((l, h) => {
      const y = (0, e.createHash)(f);
      (y.on("error", h).setEncoding(d),
        (0, t.createReadStream)(u, { ...c, highWaterMark: 1024 * 1024 })
          .on("error", h)
          .on("end", () => {
            (y.end(), l(y.read()));
          })
          .pipe(y, { end: !1 }));
    });
  }
  async function s(u, f, d) {
    let c = 0,
      l = a.join(f, u);
    for (let h = 0; h < 3; h++)
      try {
        return (await (0, i.unlink)(l), l);
      } catch (y) {
        if (y.code === "ENOENT") return l;
        (d.warn(`Error on remove temp update file: ${y}`),
          (l = a.join(f, `${c++}-${u}`)));
      }
    return l;
  }
  return jr;
}
var En = {},
  Ri = {},
  lf;
function g2() {
  if (lf) return Ri;
  ((lf = 1),
    Object.defineProperty(Ri, "__esModule", { value: !0 }),
    (Ri.getAppCacheDir = o));
  const e = G,
    t = Ke;
  function o() {
    const i = (0, t.homedir)();
    let a;
    return (
      process.platform === "win32"
        ? (a = process.env.LOCALAPPDATA || e.join(i, "AppData", "Local"))
        : process.platform === "darwin"
          ? (a = e.join(i, "Library", "Caches"))
          : (a = process.env.XDG_CACHE_HOME || e.join(i, ".cache")),
      a
    );
  }
  return Ri;
}
var cf;
function w2() {
  if (cf) return En;
  ((cf = 1),
    Object.defineProperty(En, "__esModule", { value: !0 }),
    (En.ElectronAppAdapter = void 0));
  const e = G,
    t = g2();
  let o = class {
    constructor(a = Or.app) {
      this.app = a;
    }
    whenReady() {
      return this.app.whenReady();
    }
    get version() {
      return this.app.getVersion();
    }
    get name() {
      return this.app.getName();
    }
    get isPackaged() {
      return this.app.isPackaged === !0;
    }
    get appUpdateConfigPath() {
      return this.isPackaged
        ? e.join(process.resourcesPath, "app-update.yml")
        : e.join(this.app.getAppPath(), "dev-app-update.yml");
    }
    get userDataPath() {
      return this.app.getPath("userData");
    }
    get baseCachePath() {
      return (0, t.getAppCacheDir)();
    }
    quit() {
      this.app.quit();
    }
    relaunch() {
      this.app.relaunch();
    }
    onQuit(a) {
      this.app.once("quit", (n, r) => a(r));
    }
  };
  return ((En.ElectronAppAdapter = o), En);
}
var hs = {},
  ff;
function y2() {
  return (
    ff ||
      ((ff = 1),
      (function (e) {
        (Object.defineProperty(e, "__esModule", { value: !0 }),
          (e.ElectronHttpExecutor = e.NET_SESSION_NAME = void 0),
          (e.getNetSession = o));
        const t = rt();
        e.NET_SESSION_NAME = "electron-updater";
        function o() {
          return Or.session.fromPartition(e.NET_SESSION_NAME, { cache: !1 });
        }
        class i extends t.HttpExecutor {
          constructor(n) {
            (super(),
              (this.proxyLoginCallback = n),
              (this.cachedSession = null));
          }
          async download(n, r, s) {
            return await s.cancellationToken.createPromise((u, f, d) => {
              const c = { headers: s.headers || void 0, redirect: "manual" };
              ((0, t.configureRequestUrl)(n, c),
                (0, t.configureRequestOptions)(c),
                this.doDownload(
                  c,
                  {
                    destination: r,
                    options: s,
                    onCancel: d,
                    callback: (l) => {
                      l == null ? u(r) : f(l);
                    },
                    responseHandler: null,
                  },
                  0,
                ));
            });
          }
          createRequest(n, r) {
            (n.headers &&
              n.headers.Host &&
              ((n.host = n.headers.Host), delete n.headers.Host),
              this.cachedSession == null && (this.cachedSession = o()));
            const s = Or.net.request({ ...n, session: this.cachedSession });
            return (
              s.on("response", r),
              this.proxyLoginCallback != null &&
                s.on("login", this.proxyLoginCallback),
              s
            );
          }
          addRedirectHandlers(n, r, s, u, f) {
            n.on("redirect", (d, c, l) => {
              (n.abort(),
                u > this.maxRedirects
                  ? s(this.createMaxRedirectError())
                  : f(t.HttpExecutor.prepareRedirectUrlOptions(l, r)));
            });
          }
        }
        e.ElectronHttpExecutor = i;
      })(hs)),
    hs
  );
}
var vn = {},
  Sr = {},
  ps,
  df;
function E2() {
  if (df) return ps;
  df = 1;
  var e = "[object Symbol]",
    t = /[\\^$.*+?()[\]{}|]/g,
    o = RegExp(t.source),
    i = typeof Nt == "object" && Nt && Nt.Object === Object && Nt,
    a = typeof self == "object" && self && self.Object === Object && self,
    n = i || a || Function("return this")(),
    r = Object.prototype,
    s = r.toString,
    u = n.Symbol,
    f = u ? u.prototype : void 0,
    d = f ? f.toString : void 0;
  function c(m) {
    if (typeof m == "string") return m;
    if (h(m)) return d ? d.call(m) : "";
    var S = m + "";
    return S == "0" && 1 / m == -1 / 0 ? "-0" : S;
  }
  function l(m) {
    return !!m && typeof m == "object";
  }
  function h(m) {
    return typeof m == "symbol" || (l(m) && s.call(m) == e);
  }
  function y(m) {
    return m == null ? "" : c(m);
  }
  function F(m) {
    return ((m = y(m)), m && o.test(m) ? m.replace(t, "\\$&") : m);
  }
  return ((ps = F), ps);
}
var hf;
function Br() {
  if (hf) return Sr;
  ((hf = 1),
    Object.defineProperty(Sr, "__esModule", { value: !0 }),
    (Sr.newBaseUrl = o),
    (Sr.newUrlFromBase = i),
    (Sr.getChannelFilename = a),
    (Sr.blockmapFiles = n));
  const e = Mt,
    t = E2();
  function o(r) {
    const s = new e.URL(r);
    return (s.pathname.endsWith("/") || (s.pathname += "/"), s);
  }
  function i(r, s, u = !1) {
    const f = new e.URL(r, s),
      d = s.search;
    return (
      d != null && d.length !== 0
        ? (f.search = d)
        : u && (f.search = `noCache=${Date.now().toString(32)}`),
      f
    );
  }
  function a(r) {
    return `${r}.yml`;
  }
  function n(r, s, u) {
    const f = i(`${r.pathname}.blockmap`, r);
    return [
      i(`${r.pathname.replace(new RegExp(t(u), "g"), s)}.blockmap`, r),
      f,
    ];
  }
  return Sr;
}
var Ht = {},
  pf;
function bt() {
  if (pf) return Ht;
  ((pf = 1),
    Object.defineProperty(Ht, "__esModule", { value: !0 }),
    (Ht.Provider = void 0),
    (Ht.findFile = a),
    (Ht.parseUpdateInfo = n),
    (Ht.getFileList = r),
    (Ht.resolveFiles = s));
  const e = rt(),
    t = lu(),
    o = Br();
  let i = class {
    constructor(f) {
      ((this.runtimeOptions = f),
        (this.requestHeaders = null),
        (this.executor = f.executor));
    }
    get isUseMultipleRangeRequest() {
      return this.runtimeOptions.isUseMultipleRangeRequest !== !1;
    }
    getChannelFilePrefix() {
      if (this.runtimeOptions.platform === "linux") {
        const f = process.env.TEST_UPDATER_ARCH || process.arch;
        return "-linux" + (f === "x64" ? "" : `-${f}`);
      } else return this.runtimeOptions.platform === "darwin" ? "-mac" : "";
    }
    getDefaultChannelName() {
      return this.getCustomChannelName("latest");
    }
    getCustomChannelName(f) {
      return `${f}${this.getChannelFilePrefix()}`;
    }
    get fileExtraDownloadHeaders() {
      return null;
    }
    setRequestHeaders(f) {
      this.requestHeaders = f;
    }
    httpRequest(f, d, c) {
      return this.executor.request(this.createRequestOptions(f, d), c);
    }
    createRequestOptions(f, d) {
      const c = {};
      return (
        this.requestHeaders == null
          ? d != null && (c.headers = d)
          : (c.headers =
              d == null
                ? this.requestHeaders
                : { ...this.requestHeaders, ...d }),
        (0, e.configureRequestUrl)(f, c),
        c
      );
    }
  };
  Ht.Provider = i;
  function a(u, f, d) {
    if (u.length === 0)
      throw (0, e.newError)(
        "No files provided",
        "ERR_UPDATER_NO_FILES_PROVIDED",
      );
    const c = u.find((l) =>
      l.url.pathname.toLowerCase().endsWith(`.${f.toLowerCase()}`),
    );
    return (
      c ??
      (d == null
        ? u[0]
        : u.find(
            (l) =>
              !d.some((h) =>
                l.url.pathname.toLowerCase().endsWith(`.${h.toLowerCase()}`),
              ),
          ))
    );
  }
  function n(u, f, d) {
    if (u == null)
      throw (0, e.newError)(
        `Cannot parse update info from ${f} in the latest release artifacts (${d}): rawData: null`,
        "ERR_UPDATER_INVALID_UPDATE_INFO",
      );
    let c;
    try {
      c = (0, t.load)(u);
    } catch (l) {
      throw (0, e.newError)(
        `Cannot parse update info from ${f} in the latest release artifacts (${d}): ${l.stack || l.message}, rawData: ${u}`,
        "ERR_UPDATER_INVALID_UPDATE_INFO",
      );
    }
    return c;
  }
  function r(u) {
    const f = u.files;
    if (f != null && f.length > 0) return f;
    if (u.path != null)
      return [{ url: u.path, sha2: u.sha2, sha512: u.sha512 }];
    throw (0, e.newError)(
      `No files provided: ${(0, e.safeStringifyJson)(u)}`,
      "ERR_UPDATER_NO_FILES_PROVIDED",
    );
  }
  function s(u, f, d = (c) => c) {
    const l = r(u).map((F) => {
        if (F.sha2 == null && F.sha512 == null)
          throw (0, e.newError)(
            `Update info doesn't contain nor sha256 neither sha512 checksum: ${(0, e.safeStringifyJson)(F)}`,
            "ERR_UPDATER_NO_CHECKSUM",
          );
        return { url: (0, o.newUrlFromBase)(d(F.url), f), info: F };
      }),
      h = u.packages,
      y = h == null ? null : h[process.arch] || h.ia32;
    return (
      y != null &&
        (l[0].packageInfo = {
          ...y,
          path: (0, o.newUrlFromBase)(d(y.path), f).href,
        }),
      l
    );
  }
  return Ht;
}
var Df;
function Fp() {
  if (Df) return vn;
  ((Df = 1),
    Object.defineProperty(vn, "__esModule", { value: !0 }),
    (vn.GenericProvider = void 0));
  const e = rt(),
    t = Br(),
    o = bt();
  let i = class extends o.Provider {
    constructor(n, r, s) {
      (super(s),
        (this.configuration = n),
        (this.updater = r),
        (this.baseUrl = (0, t.newBaseUrl)(this.configuration.url)));
    }
    get channel() {
      const n = this.updater.channel || this.configuration.channel;
      return n == null
        ? this.getDefaultChannelName()
        : this.getCustomChannelName(n);
    }
    async getLatestVersion() {
      const n = (0, t.getChannelFilename)(this.channel),
        r = (0, t.newUrlFromBase)(
          n,
          this.baseUrl,
          this.updater.isAddNoCacheQuery,
        );
      for (let s = 0; ; s++)
        try {
          return (0, o.parseUpdateInfo)(await this.httpRequest(r), n, r);
        } catch (u) {
          if (u instanceof e.HttpError && u.statusCode === 404)
            throw (0, e.newError)(
              `Cannot find channel "${n}" update info: ${u.stack || u.message}`,
              "ERR_UPDATER_CHANNEL_FILE_NOT_FOUND",
            );
          if (u.code === "ECONNREFUSED" && s < 3) {
            await new Promise((f, d) => {
              try {
                setTimeout(f, 1e3 * s);
              } catch (c) {
                d(c);
              }
            });
            continue;
          }
          throw u;
        }
    }
    resolveFiles(n) {
      return (0, o.resolveFiles)(n, this.baseUrl);
    }
  };
  return ((vn.GenericProvider = i), vn);
}
var Cn = {},
  An = {},
  mf;
function v2() {
  if (mf) return An;
  ((mf = 1),
    Object.defineProperty(An, "__esModule", { value: !0 }),
    (An.BitbucketProvider = void 0));
  const e = rt(),
    t = Br(),
    o = bt();
  let i = class extends o.Provider {
    constructor(n, r, s) {
      (super({ ...s, isUseMultipleRangeRequest: !1 }),
        (this.configuration = n),
        (this.updater = r));
      const { owner: u, slug: f } = n;
      this.baseUrl = (0, t.newBaseUrl)(
        `https://api.bitbucket.org/2.0/repositories/${u}/${f}/downloads`,
      );
    }
    get channel() {
      return this.updater.channel || this.configuration.channel || "latest";
    }
    async getLatestVersion() {
      const n = new e.CancellationToken(),
        r = (0, t.getChannelFilename)(this.getCustomChannelName(this.channel)),
        s = (0, t.newUrlFromBase)(
          r,
          this.baseUrl,
          this.updater.isAddNoCacheQuery,
        );
      try {
        const u = await this.httpRequest(s, void 0, n);
        return (0, o.parseUpdateInfo)(u, r, s);
      } catch (u) {
        throw (0, e.newError)(
          `Unable to find latest version on ${this.toString()}, please ensure release exists: ${u.stack || u.message}`,
          "ERR_UPDATER_LATEST_VERSION_NOT_FOUND",
        );
      }
    }
    resolveFiles(n) {
      return (0, o.resolveFiles)(n, this.baseUrl);
    }
    toString() {
      const { owner: n, slug: r } = this.configuration;
      return `Bitbucket (owner: ${n}, slug: ${r}, channel: ${this.channel})`;
    }
  };
  return ((An.BitbucketProvider = i), An);
}
var nr = {},
  gf;
function Sp() {
  if (gf) return nr;
  ((gf = 1),
    Object.defineProperty(nr, "__esModule", { value: !0 }),
    (nr.GitHubProvider = nr.BaseGitHubProvider = void 0),
    (nr.computeReleaseNotes = f));
  const e = rt(),
    t = Gh(),
    o = Mt,
    i = Br(),
    a = bt(),
    n = /\/tag\/([^/]+)$/;
  class r extends a.Provider {
    constructor(c, l, h) {
      (super({ ...h, isUseMultipleRangeRequest: !1 }),
        (this.options = c),
        (this.baseUrl = (0, i.newBaseUrl)((0, e.githubUrl)(c, l))));
      const y = l === "github.com" ? "api.github.com" : l;
      this.baseApiUrl = (0, i.newBaseUrl)((0, e.githubUrl)(c, y));
    }
    computeGithubBasePath(c) {
      const l = this.options.host;
      return l && !["github.com", "api.github.com"].includes(l)
        ? `/api/v3${c}`
        : c;
    }
  }
  nr.BaseGitHubProvider = r;
  let s = class extends r {
    constructor(c, l, h) {
      (super(c, "github.com", h), (this.options = c), (this.updater = l));
    }
    get channel() {
      const c = this.updater.channel || this.options.channel;
      return c == null
        ? this.getDefaultChannelName()
        : this.getCustomChannelName(c);
    }
    async getLatestVersion() {
      var c, l, h, y, F;
      const m = new e.CancellationToken(),
        S = await this.httpRequest(
          (0, i.newUrlFromBase)(`${this.basePath}.atom`, this.baseUrl),
          { accept: "application/xml, application/atom+xml, text/xml, */*" },
          m,
        ),
        E = (0, e.parseXml)(S);
      let b = E.element("entry", !1, "No published versions on GitHub"),
        w = null;
      try {
        if (this.updater.allowPrerelease) {
          const N =
            ((c = this.updater) === null || c === void 0
              ? void 0
              : c.channel) ||
            ((l = t.prerelease(this.updater.currentVersion)) === null ||
            l === void 0
              ? void 0
              : l[0]) ||
            null;
          if (N === null) w = n.exec(b.element("link").attribute("href"))[1];
          else
            for (const P of E.getElements("entry")) {
              const R = n.exec(P.element("link").attribute("href"));
              if (R === null) continue;
              const k = R[1],
                q =
                  ((h = t.prerelease(k)) === null || h === void 0
                    ? void 0
                    : h[0]) || null,
                U = !N || ["alpha", "beta"].includes(N),
                $ = q !== null && !["alpha", "beta"].includes(String(q));
              if (U && !$ && !(N === "beta" && q === "alpha")) {
                w = k;
                break;
              }
              if (q && q === N) {
                w = k;
                break;
              }
            }
        } else {
          w = await this.getLatestTagName(m);
          for (const N of E.getElements("entry"))
            if (n.exec(N.element("link").attribute("href"))[1] === w) {
              b = N;
              break;
            }
        }
      } catch (N) {
        throw (0, e.newError)(
          `Cannot parse releases feed: ${N.stack || N.message},
XML:
${S}`,
          "ERR_UPDATER_INVALID_RELEASE_FEED",
        );
      }
      if (w == null)
        throw (0, e.newError)(
          "No published versions on GitHub",
          "ERR_UPDATER_NO_PUBLISHED_VERSIONS",
        );
      let A,
        v = "",
        C = "";
      const g = async (N) => {
        ((v = (0, i.getChannelFilename)(N)),
          (C = (0, i.newUrlFromBase)(
            this.getBaseDownloadPath(String(w), v),
            this.baseUrl,
          )));
        const P = this.createRequestOptions(C);
        try {
          return await this.executor.request(P, m);
        } catch (R) {
          throw R instanceof e.HttpError && R.statusCode === 404
            ? (0, e.newError)(
                `Cannot find ${v} in the latest release artifacts (${C}): ${R.stack || R.message}`,
                "ERR_UPDATER_CHANNEL_FILE_NOT_FOUND",
              )
            : R;
        }
      };
      try {
        let N = this.channel;
        (this.updater.allowPrerelease &&
          !((y = t.prerelease(w)) === null || y === void 0) &&
          y[0] &&
          (N = this.getCustomChannelName(
            String(
              (F = t.prerelease(w)) === null || F === void 0 ? void 0 : F[0],
            ),
          )),
          (A = await g(N)));
      } catch (N) {
        if (this.updater.allowPrerelease)
          A = await g(this.getDefaultChannelName());
        else throw N;
      }
      const D = (0, a.parseUpdateInfo)(A, v, C);
      return (
        D.releaseName == null &&
          (D.releaseName = b.elementValueOrEmpty("title")),
        D.releaseNotes == null &&
          (D.releaseNotes = f(
            this.updater.currentVersion,
            this.updater.fullChangelog,
            E,
            b,
          )),
        { tag: w, ...D }
      );
    }
    async getLatestTagName(c) {
      const l = this.options,
        h =
          l.host == null || l.host === "github.com"
            ? (0, i.newUrlFromBase)(`${this.basePath}/latest`, this.baseUrl)
            : new o.URL(
                `${this.computeGithubBasePath(`/repos/${l.owner}/${l.repo}/releases`)}/latest`,
                this.baseApiUrl,
              );
      try {
        const y = await this.httpRequest(h, { Accept: "application/json" }, c);
        return y == null ? null : JSON.parse(y).tag_name;
      } catch (y) {
        throw (0, e.newError)(
          `Unable to find latest version on GitHub (${h}), please ensure a production release exists: ${y.stack || y.message}`,
          "ERR_UPDATER_LATEST_VERSION_NOT_FOUND",
        );
      }
    }
    get basePath() {
      return `/${this.options.owner}/${this.options.repo}/releases`;
    }
    resolveFiles(c) {
      return (0, a.resolveFiles)(c, this.baseUrl, (l) =>
        this.getBaseDownloadPath(c.tag, l.replace(/ /g, "-")),
      );
    }
    getBaseDownloadPath(c, l) {
      return `${this.basePath}/download/${c}/${l}`;
    }
  };
  nr.GitHubProvider = s;
  function u(d) {
    const c = d.elementValueOrEmpty("content");
    return c === "No content." ? "" : c;
  }
  function f(d, c, l, h) {
    if (!c) return u(h);
    const y = [];
    for (const F of l.getElements("entry")) {
      const m = /\/tag\/v?([^/]+)$/.exec(
        F.element("link").attribute("href"),
      )[1];
      t.lt(d, m) && y.push({ version: m, note: u(F) });
    }
    return y.sort((F, m) => t.rcompare(F.version, m.version));
  }
  return nr;
}
var bn = {},
  wf;
function C2() {
  if (wf) return bn;
  ((wf = 1),
    Object.defineProperty(bn, "__esModule", { value: !0 }),
    (bn.KeygenProvider = void 0));
  const e = rt(),
    t = Br(),
    o = bt();
  let i = class extends o.Provider {
    constructor(n, r, s) {
      (super({ ...s, isUseMultipleRangeRequest: !1 }),
        (this.configuration = n),
        (this.updater = r),
        (this.defaultHostname = "api.keygen.sh"));
      const u = this.configuration.host || this.defaultHostname;
      this.baseUrl = (0, t.newBaseUrl)(
        `https://${u}/v1/accounts/${this.configuration.account}/artifacts?product=${this.configuration.product}`,
      );
    }
    get channel() {
      return this.updater.channel || this.configuration.channel || "stable";
    }
    async getLatestVersion() {
      const n = new e.CancellationToken(),
        r = (0, t.getChannelFilename)(this.getCustomChannelName(this.channel)),
        s = (0, t.newUrlFromBase)(
          r,
          this.baseUrl,
          this.updater.isAddNoCacheQuery,
        );
      try {
        const u = await this.httpRequest(
          s,
          { Accept: "application/vnd.api+json", "Keygen-Version": "1.1" },
          n,
        );
        return (0, o.parseUpdateInfo)(u, r, s);
      } catch (u) {
        throw (0, e.newError)(
          `Unable to find latest version on ${this.toString()}, please ensure release exists: ${u.stack || u.message}`,
          "ERR_UPDATER_LATEST_VERSION_NOT_FOUND",
        );
      }
    }
    resolveFiles(n) {
      return (0, o.resolveFiles)(n, this.baseUrl);
    }
    toString() {
      const { account: n, product: r, platform: s } = this.configuration;
      return `Keygen (account: ${n}, product: ${r}, platform: ${s}, channel: ${this.channel})`;
    }
  };
  return ((bn.KeygenProvider = i), bn);
}
var Fn = {},
  yf;
function A2() {
  if (yf) return Fn;
  ((yf = 1),
    Object.defineProperty(Fn, "__esModule", { value: !0 }),
    (Fn.PrivateGitHubProvider = void 0));
  const e = rt(),
    t = lu(),
    o = G,
    i = Mt,
    a = Br(),
    n = Sp(),
    r = bt();
  let s = class extends n.BaseGitHubProvider {
    constructor(f, d, c, l) {
      (super(f, "api.github.com", l), (this.updater = d), (this.token = c));
    }
    createRequestOptions(f, d) {
      const c = super.createRequestOptions(f, d);
      return ((c.redirect = "manual"), c);
    }
    async getLatestVersion() {
      const f = new e.CancellationToken(),
        d = (0, a.getChannelFilename)(this.getDefaultChannelName()),
        c = await this.getLatestVersionInfo(f),
        l = c.assets.find((F) => F.name === d);
      if (l == null)
        throw (0, e.newError)(
          `Cannot find ${d} in the release ${c.html_url || c.name}`,
          "ERR_UPDATER_CHANNEL_FILE_NOT_FOUND",
        );
      const h = new i.URL(l.url);
      let y;
      try {
        y = (0, t.load)(
          await this.httpRequest(
            h,
            this.configureHeaders("application/octet-stream"),
            f,
          ),
        );
      } catch (F) {
        throw F instanceof e.HttpError && F.statusCode === 404
          ? (0, e.newError)(
              `Cannot find ${d} in the latest release artifacts (${h}): ${F.stack || F.message}`,
              "ERR_UPDATER_CHANNEL_FILE_NOT_FOUND",
            )
          : F;
      }
      return ((y.assets = c.assets), y);
    }
    get fileExtraDownloadHeaders() {
      return this.configureHeaders("application/octet-stream");
    }
    configureHeaders(f) {
      return { accept: f, authorization: `token ${this.token}` };
    }
    async getLatestVersionInfo(f) {
      const d = this.updater.allowPrerelease;
      let c = this.basePath;
      d || (c = `${c}/latest`);
      const l = (0, a.newUrlFromBase)(c, this.baseUrl);
      try {
        const h = JSON.parse(
          await this.httpRequest(
            l,
            this.configureHeaders("application/vnd.github.v3+json"),
            f,
          ),
        );
        return d ? h.find((y) => y.prerelease) || h[0] : h;
      } catch (h) {
        throw (0, e.newError)(
          `Unable to find latest version on GitHub (${l}), please ensure a production release exists: ${h.stack || h.message}`,
          "ERR_UPDATER_LATEST_VERSION_NOT_FOUND",
        );
      }
    }
    get basePath() {
      return this.computeGithubBasePath(
        `/repos/${this.options.owner}/${this.options.repo}/releases`,
      );
    }
    resolveFiles(f) {
      return (0, r.getFileList)(f).map((d) => {
        const c = o.posix.basename(d.url).replace(/ /g, "-"),
          l = f.assets.find((h) => h != null && h.name === c);
        if (l == null)
          throw (0, e.newError)(
            `Cannot find asset "${c}" in: ${JSON.stringify(f.assets, null, 2)}`,
            "ERR_UPDATER_ASSET_NOT_FOUND",
          );
        return { url: new i.URL(l.url), info: d };
      });
    }
  };
  return ((Fn.PrivateGitHubProvider = s), Fn);
}
var Ef;
function b2() {
  if (Ef) return Cn;
  ((Ef = 1),
    Object.defineProperty(Cn, "__esModule", { value: !0 }),
    (Cn.isUrlProbablySupportMultiRangeRequests = r),
    (Cn.createClient = s));
  const e = rt(),
    t = v2(),
    o = Fp(),
    i = Sp(),
    a = C2(),
    n = A2();
  function r(u) {
    return !u.includes("s3.amazonaws.com");
  }
  function s(u, f, d) {
    if (typeof u == "string")
      throw (0, e.newError)(
        "Please pass PublishConfiguration object",
        "ERR_UPDATER_INVALID_PROVIDER_CONFIGURATION",
      );
    const c = u.provider;
    switch (c) {
      case "github": {
        const l = u,
          h =
            (l.private
              ? process.env.GH_TOKEN || process.env.GITHUB_TOKEN
              : null) || l.token;
        return h == null
          ? new i.GitHubProvider(l, f, d)
          : new n.PrivateGitHubProvider(l, f, h, d);
      }
      case "bitbucket":
        return new t.BitbucketProvider(u, f, d);
      case "keygen":
        return new a.KeygenProvider(u, f, d);
      case "s3":
      case "spaces":
        return new o.GenericProvider(
          {
            provider: "generic",
            url: (0, e.getS3LikeProviderBaseUrl)(u),
            channel: u.channel || null,
          },
          f,
          { ...d, isUseMultipleRangeRequest: !1 },
        );
      case "generic": {
        const l = u;
        return new o.GenericProvider(l, f, {
          ...d,
          isUseMultipleRangeRequest:
            l.useMultipleRangeRequest !== !1 && r(l.url),
        });
      }
      case "custom": {
        const l = u,
          h = l.updateProvider;
        if (!h)
          throw (0, e.newError)(
            "Custom provider not specified",
            "ERR_UPDATER_INVALID_PROVIDER_CONFIGURATION",
          );
        return new h(l, f, d);
      }
      default:
        throw (0, e.newError)(
          `Unsupported provider: ${c}`,
          "ERR_UPDATER_UNSUPPORTED_PROVIDER",
        );
    }
  }
  return Cn;
}
var Sn = {},
  _n = {},
  Wr = {},
  Hr = {},
  vf;
function cu() {
  if (vf) return Hr;
  ((vf = 1),
    Object.defineProperty(Hr, "__esModule", { value: !0 }),
    (Hr.OperationKind = void 0),
    (Hr.computeOperations = t));
  var e;
  (function (r) {
    ((r[(r.COPY = 0)] = "COPY"), (r[(r.DOWNLOAD = 1)] = "DOWNLOAD"));
  })(e || (Hr.OperationKind = e = {}));
  function t(r, s, u) {
    const f = n(r.files),
      d = n(s.files);
    let c = null;
    const l = s.files[0],
      h = [],
      y = l.name,
      F = f.get(y);
    if (F == null) throw new Error(`no file ${y} in old blockmap`);
    const m = d.get(y);
    let S = 0;
    const { checksumToOffset: E, checksumToOldSize: b } = a(
      f.get(y),
      F.offset,
      u,
    );
    let w = l.offset;
    for (let A = 0; A < m.checksums.length; w += m.sizes[A], A++) {
      const v = m.sizes[A],
        C = m.checksums[A];
      let g = E.get(C);
      (g != null &&
        b.get(C) !== v &&
        (u.warn(
          `Checksum ("${C}") matches, but size differs (old: ${b.get(C)}, new: ${v})`,
        ),
        (g = void 0)),
        g === void 0
          ? (S++,
            c != null && c.kind === e.DOWNLOAD && c.end === w
              ? (c.end += v)
              : ((c = { kind: e.DOWNLOAD, start: w, end: w + v }),
                i(c, h, C, A)))
          : c != null && c.kind === e.COPY && c.end === g
            ? (c.end += v)
            : ((c = { kind: e.COPY, start: g, end: g + v }), i(c, h, C, A)));
    }
    return (
      S > 0 &&
        u.info(
          `File${l.name === "file" ? "" : " " + l.name} has ${S} changed blocks`,
        ),
      h
    );
  }
  const o =
    process.env.DIFFERENTIAL_DOWNLOAD_PLAN_BUILDER_VALIDATE_RANGES === "true";
  function i(r, s, u, f) {
    if (o && s.length !== 0) {
      const d = s[s.length - 1];
      if (d.kind === r.kind && r.start < d.end && r.start > d.start) {
        const c = [d.start, d.end, r.start, r.end].reduce((l, h) =>
          l < h ? l : h,
        );
        throw new Error(`operation (block index: ${f}, checksum: ${u}, kind: ${e[r.kind]}) overlaps previous operation (checksum: ${u}):
abs: ${d.start} until ${d.end} and ${r.start} until ${r.end}
rel: ${d.start - c} until ${d.end - c} and ${r.start - c} until ${r.end - c}`);
      }
    }
    s.push(r);
  }
  function a(r, s, u) {
    const f = new Map(),
      d = new Map();
    let c = s;
    for (let l = 0; l < r.checksums.length; l++) {
      const h = r.checksums[l],
        y = r.sizes[l],
        F = d.get(h);
      if (F === void 0) (f.set(h, c), d.set(h, y));
      else if (u.debug != null) {
        const m = F === y ? "(same size)" : `(size: ${F}, this size: ${y})`;
        u.debug(
          `${h} duplicated in blockmap ${m}, it doesn't lead to broken differential downloader, just corresponding block will be skipped)`,
        );
      }
      c += y;
    }
    return { checksumToOffset: f, checksumToOldSize: d };
  }
  function n(r) {
    const s = new Map();
    for (const u of r) s.set(u.name, u);
    return s;
  }
  return Hr;
}
var Cf;
function _p() {
  if (Cf) return Wr;
  ((Cf = 1),
    Object.defineProperty(Wr, "__esModule", { value: !0 }),
    (Wr.DataSplitter = void 0),
    (Wr.copyData = r));
  const e = rt(),
    t = ze,
    o = ii,
    i = cu(),
    a = Buffer.from(`\r
\r
`);
  var n;
  (function (u) {
    ((u[(u.INIT = 0)] = "INIT"),
      (u[(u.HEADER = 1)] = "HEADER"),
      (u[(u.BODY = 2)] = "BODY"));
  })(n || (n = {}));
  function r(u, f, d, c, l) {
    const h = (0, t.createReadStream)("", {
      fd: d,
      autoClose: !1,
      start: u.start,
      end: u.end - 1,
    });
    (h.on("error", c), h.once("end", l), h.pipe(f, { end: !1 }));
  }
  let s = class extends o.Writable {
    constructor(f, d, c, l, h, y) {
      (super(),
        (this.out = f),
        (this.options = d),
        (this.partIndexToTaskIndex = c),
        (this.partIndexToLength = h),
        (this.finishHandler = y),
        (this.partIndex = -1),
        (this.headerListBuffer = null),
        (this.readState = n.INIT),
        (this.ignoreByteCount = 0),
        (this.remainingPartDataCount = 0),
        (this.actualPartLength = 0),
        (this.boundaryLength = l.length + 4),
        (this.ignoreByteCount = this.boundaryLength - 2));
    }
    get isFinished() {
      return this.partIndex === this.partIndexToLength.length;
    }
    _write(f, d, c) {
      if (this.isFinished) {
        console.error(`Trailing ignored data: ${f.length} bytes`);
        return;
      }
      this.handleData(f).then(c).catch(c);
    }
    async handleData(f) {
      let d = 0;
      if (this.ignoreByteCount !== 0 && this.remainingPartDataCount !== 0)
        throw (0, e.newError)(
          "Internal error",
          "ERR_DATA_SPLITTER_BYTE_COUNT_MISMATCH",
        );
      if (this.ignoreByteCount > 0) {
        const c = Math.min(this.ignoreByteCount, f.length);
        ((this.ignoreByteCount -= c), (d = c));
      } else if (this.remainingPartDataCount > 0) {
        const c = Math.min(this.remainingPartDataCount, f.length);
        ((this.remainingPartDataCount -= c),
          await this.processPartData(f, 0, c),
          (d = c));
      }
      if (d !== f.length) {
        if (this.readState === n.HEADER) {
          const c = this.searchHeaderListEnd(f, d);
          if (c === -1) return;
          ((d = c), (this.readState = n.BODY), (this.headerListBuffer = null));
        }
        for (;;) {
          if (this.readState === n.BODY) this.readState = n.INIT;
          else {
            this.partIndex++;
            let y = this.partIndexToTaskIndex.get(this.partIndex);
            if (y == null)
              if (this.isFinished) y = this.options.end;
              else
                throw (0, e.newError)(
                  "taskIndex is null",
                  "ERR_DATA_SPLITTER_TASK_INDEX_IS_NULL",
                );
            const F =
              this.partIndex === 0
                ? this.options.start
                : this.partIndexToTaskIndex.get(this.partIndex - 1) + 1;
            if (F < y) await this.copyExistingData(F, y);
            else if (F > y)
              throw (0, e.newError)(
                "prevTaskIndex must be < taskIndex",
                "ERR_DATA_SPLITTER_TASK_INDEX_ASSERT_FAILED",
              );
            if (this.isFinished) {
              (this.onPartEnd(), this.finishHandler());
              return;
            }
            if (((d = this.searchHeaderListEnd(f, d)), d === -1)) {
              this.readState = n.HEADER;
              return;
            }
          }
          const c = this.partIndexToLength[this.partIndex],
            l = d + c,
            h = Math.min(l, f.length);
          if (
            (await this.processPartStarted(f, d, h),
            (this.remainingPartDataCount = c - (h - d)),
            this.remainingPartDataCount > 0)
          )
            return;
          if (((d = l + this.boundaryLength), d >= f.length)) {
            this.ignoreByteCount = this.boundaryLength - (f.length - l);
            return;
          }
        }
      }
    }
    copyExistingData(f, d) {
      return new Promise((c, l) => {
        const h = () => {
          if (f === d) {
            c();
            return;
          }
          const y = this.options.tasks[f];
          if (y.kind !== i.OperationKind.COPY) {
            l(new Error("Task kind must be COPY"));
            return;
          }
          r(y, this.out, this.options.oldFileFd, l, () => {
            (f++, h());
          });
        };
        h();
      });
    }
    searchHeaderListEnd(f, d) {
      const c = f.indexOf(a, d);
      if (c !== -1) return c + a.length;
      const l = d === 0 ? f : f.slice(d);
      return (
        this.headerListBuffer == null
          ? (this.headerListBuffer = l)
          : (this.headerListBuffer = Buffer.concat([this.headerListBuffer, l])),
        -1
      );
    }
    onPartEnd() {
      const f = this.partIndexToLength[this.partIndex - 1];
      if (this.actualPartLength !== f)
        throw (0, e.newError)(
          `Expected length: ${f} differs from actual: ${this.actualPartLength}`,
          "ERR_DATA_SPLITTER_LENGTH_MISMATCH",
        );
      this.actualPartLength = 0;
    }
    processPartStarted(f, d, c) {
      return (
        this.partIndex !== 0 && this.onPartEnd(),
        this.processPartData(f, d, c)
      );
    }
    processPartData(f, d, c) {
      this.actualPartLength += c - d;
      const l = this.out;
      return l.write(d === 0 && f.length === c ? f : f.slice(d, c))
        ? Promise.resolve()
        : new Promise((h, y) => {
            (l.on("error", y),
              l.once("drain", () => {
                (l.removeListener("error", y), h());
              }));
          });
    }
  };
  return ((Wr.DataSplitter = s), Wr);
}
var Tn = {},
  Af;
function F2() {
  if (Af) return Tn;
  ((Af = 1),
    Object.defineProperty(Tn, "__esModule", { value: !0 }),
    (Tn.executeTasksUsingMultipleRangeRequests = i),
    (Tn.checkIsRangesSupported = n));
  const e = rt(),
    t = _p(),
    o = cu();
  function i(r, s, u, f, d) {
    const c = (l) => {
      if (l >= s.length) {
        (r.fileMetadataBuffer != null && u.write(r.fileMetadataBuffer),
          u.end());
        return;
      }
      const h = l + 1e3;
      a(
        r,
        { tasks: s, start: l, end: Math.min(s.length, h), oldFileFd: f },
        u,
        () => c(h),
        d,
      );
    };
    return c;
  }
  function a(r, s, u, f, d) {
    let c = "bytes=",
      l = 0;
    const h = new Map(),
      y = [];
    for (let S = s.start; S < s.end; S++) {
      const E = s.tasks[S];
      E.kind === o.OperationKind.DOWNLOAD &&
        ((c += `${E.start}-${E.end - 1}, `),
        h.set(l, S),
        l++,
        y.push(E.end - E.start));
    }
    if (l <= 1) {
      const S = (E) => {
        if (E >= s.end) {
          f();
          return;
        }
        const b = s.tasks[E++];
        if (b.kind === o.OperationKind.COPY)
          (0, t.copyData)(b, u, s.oldFileFd, d, () => S(E));
        else {
          const w = r.createRequestOptions();
          w.headers.Range = `bytes=${b.start}-${b.end - 1}`;
          const A = r.httpExecutor.createRequest(w, (v) => {
            n(v, d) && (v.pipe(u, { end: !1 }), v.once("end", () => S(E)));
          });
          (r.httpExecutor.addErrorAndTimeoutHandlers(A, d), A.end());
        }
      };
      S(s.start);
      return;
    }
    const F = r.createRequestOptions();
    F.headers.Range = c.substring(0, c.length - 2);
    const m = r.httpExecutor.createRequest(F, (S) => {
      if (!n(S, d)) return;
      const E = (0, e.safeGetHeader)(S, "content-type"),
        b = /^multipart\/.+?(?:; boundary=(?:(?:"(.+)")|(?:([^\s]+))))$/i.exec(
          E,
        );
      if (b == null) {
        d(
          new Error(
            `Content-Type "multipart/byteranges" is expected, but got "${E}"`,
          ),
        );
        return;
      }
      const w = new t.DataSplitter(u, s, h, b[1] || b[2], y, f);
      (w.on("error", d),
        S.pipe(w),
        S.on("end", () => {
          setTimeout(() => {
            (m.abort(),
              d(new Error("Response ends without calling any handlers")));
          }, 1e4);
        }));
    });
    (r.httpExecutor.addErrorAndTimeoutHandlers(m, d), m.end());
  }
  function n(r, s) {
    if (r.statusCode >= 400) return (s((0, e.createHttpError)(r)), !1);
    if (r.statusCode !== 206) {
      const u = (0, e.safeGetHeader)(r, "accept-ranges");
      if (u == null || u === "none")
        return (
          s(
            new Error(
              `Server doesn't support Accept-Ranges (response code ${r.statusCode})`,
            ),
          ),
          !1
        );
    }
    return !0;
  }
  return Tn;
}
var xn = {},
  bf;
function S2() {
  if (bf) return xn;
  ((bf = 1),
    Object.defineProperty(xn, "__esModule", { value: !0 }),
    (xn.ProgressDifferentialDownloadCallbackTransform = void 0));
  const e = ii;
  var t;
  (function (i) {
    ((i[(i.COPY = 0)] = "COPY"), (i[(i.DOWNLOAD = 1)] = "DOWNLOAD"));
  })(t || (t = {}));
  let o = class extends e.Transform {
    constructor(a, n, r) {
      (super(),
        (this.progressDifferentialDownloadInfo = a),
        (this.cancellationToken = n),
        (this.onProgress = r),
        (this.start = Date.now()),
        (this.transferred = 0),
        (this.delta = 0),
        (this.expectedBytes = 0),
        (this.index = 0),
        (this.operationType = t.COPY),
        (this.nextUpdate = this.start + 1e3));
    }
    _transform(a, n, r) {
      if (this.cancellationToken.cancelled) {
        r(new Error("cancelled"), null);
        return;
      }
      if (this.operationType == t.COPY) {
        r(null, a);
        return;
      }
      ((this.transferred += a.length), (this.delta += a.length));
      const s = Date.now();
      (s >= this.nextUpdate &&
        this.transferred !== this.expectedBytes &&
        this.transferred !== this.progressDifferentialDownloadInfo.grandTotal &&
        ((this.nextUpdate = s + 1e3),
        this.onProgress({
          total: this.progressDifferentialDownloadInfo.grandTotal,
          delta: this.delta,
          transferred: this.transferred,
          percent:
            (this.transferred /
              this.progressDifferentialDownloadInfo.grandTotal) *
            100,
          bytesPerSecond: Math.round(
            this.transferred / ((s - this.start) / 1e3),
          ),
        }),
        (this.delta = 0)),
        r(null, a));
    }
    beginFileCopy() {
      this.operationType = t.COPY;
    }
    beginRangeDownload() {
      ((this.operationType = t.DOWNLOAD),
        (this.expectedBytes +=
          this.progressDifferentialDownloadInfo.expectedByteCounts[
            this.index++
          ]));
    }
    endRangeDownload() {
      this.transferred !== this.progressDifferentialDownloadInfo.grandTotal &&
        this.onProgress({
          total: this.progressDifferentialDownloadInfo.grandTotal,
          delta: this.delta,
          transferred: this.transferred,
          percent:
            (this.transferred /
              this.progressDifferentialDownloadInfo.grandTotal) *
            100,
          bytesPerSecond: Math.round(
            this.transferred / ((Date.now() - this.start) / 1e3),
          ),
        });
    }
    _flush(a) {
      if (this.cancellationToken.cancelled) {
        a(new Error("cancelled"));
        return;
      }
      (this.onProgress({
        total: this.progressDifferentialDownloadInfo.grandTotal,
        delta: this.delta,
        transferred: this.transferred,
        percent: 100,
        bytesPerSecond: Math.round(
          this.transferred / ((Date.now() - this.start) / 1e3),
        ),
      }),
        (this.delta = 0),
        (this.transferred = 0),
        a(null));
    }
  };
  return ((xn.ProgressDifferentialDownloadCallbackTransform = o), xn);
}
var Ff;
function Tp() {
  if (Ff) return _n;
  ((Ff = 1),
    Object.defineProperty(_n, "__esModule", { value: !0 }),
    (_n.DifferentialDownloader = void 0));
  const e = rt(),
    t = Dr(),
    o = ze,
    i = _p(),
    a = Mt,
    n = cu(),
    r = F2(),
    s = S2();
  let u = class {
    constructor(l, h, y) {
      ((this.blockAwareFileInfo = l),
        (this.httpExecutor = h),
        (this.options = y),
        (this.fileMetadataBuffer = null),
        (this.logger = y.logger));
    }
    createRequestOptions() {
      const l = { headers: { ...this.options.requestHeaders, accept: "*/*" } };
      return (
        (0, e.configureRequestUrl)(this.options.newUrl, l),
        (0, e.configureRequestOptions)(l),
        l
      );
    }
    doDownload(l, h) {
      if (l.version !== h.version)
        throw new Error(
          `version is different (${l.version} - ${h.version}), full download is required`,
        );
      const y = this.logger,
        F = (0, n.computeOperations)(l, h, y);
      y.debug != null && y.debug(JSON.stringify(F, null, 2));
      let m = 0,
        S = 0;
      for (const b of F) {
        const w = b.end - b.start;
        b.kind === n.OperationKind.DOWNLOAD ? (m += w) : (S += w);
      }
      const E = this.blockAwareFileInfo.size;
      if (
        m +
          S +
          (this.fileMetadataBuffer == null
            ? 0
            : this.fileMetadataBuffer.length) !==
        E
      )
        throw new Error(
          `Internal error, size mismatch: downloadSize: ${m}, copySize: ${S}, newSize: ${E}`,
        );
      return (
        y.info(
          `Full: ${f(E)}, To download: ${f(m)} (${Math.round(m / (E / 100))}%)`,
        ),
        this.downloadFile(F)
      );
    }
    downloadFile(l) {
      const h = [],
        y = () =>
          Promise.all(
            h.map((F) =>
              (0, t.close)(F.descriptor).catch((m) => {
                this.logger.error(`cannot close file "${F.path}": ${m}`);
              }),
            ),
          );
      return this.doDownloadFile(l, h)
        .then(y)
        .catch((F) =>
          y()
            .catch((m) => {
              try {
                this.logger.error(`cannot close files: ${m}`);
              } catch (S) {
                try {
                  console.error(S);
                } catch {}
              }
              throw F;
            })
            .then(() => {
              throw F;
            }),
        );
    }
    async doDownloadFile(l, h) {
      const y = await (0, t.open)(this.options.oldFile, "r");
      h.push({ descriptor: y, path: this.options.oldFile });
      const F = await (0, t.open)(this.options.newFile, "w");
      h.push({ descriptor: F, path: this.options.newFile });
      const m = (0, o.createWriteStream)(this.options.newFile, { fd: F });
      await new Promise((S, E) => {
        const b = [];
        let w;
        if (
          !this.options.isUseMultipleRangeRequest &&
          this.options.onProgress
        ) {
          const R = [];
          let k = 0;
          for (const U of l)
            U.kind === n.OperationKind.DOWNLOAD &&
              (R.push(U.end - U.start), (k += U.end - U.start));
          const q = { expectedByteCounts: R, grandTotal: k };
          ((w = new s.ProgressDifferentialDownloadCallbackTransform(
            q,
            this.options.cancellationToken,
            this.options.onProgress,
          )),
            b.push(w));
        }
        const A = new e.DigestTransform(this.blockAwareFileInfo.sha512);
        ((A.isValidateOnEnd = !1),
          b.push(A),
          m.on("finish", () => {
            m.close(() => {
              h.splice(1, 1);
              try {
                A.validate();
              } catch (R) {
                E(R);
                return;
              }
              S(void 0);
            });
          }),
          b.push(m));
        let v = null;
        for (const R of b)
          (R.on("error", E), v == null ? (v = R) : (v = v.pipe(R)));
        const C = b[0];
        let g;
        if (this.options.isUseMultipleRangeRequest) {
          ((g = (0, r.executeTasksUsingMultipleRangeRequests)(
            this,
            l,
            C,
            y,
            E,
          )),
            g(0));
          return;
        }
        let D = 0,
          N = null;
        this.logger.info(`Differential download: ${this.options.newUrl}`);
        const P = this.createRequestOptions();
        ((P.redirect = "manual"),
          (g = (R) => {
            var k, q;
            if (R >= l.length) {
              (this.fileMetadataBuffer != null &&
                C.write(this.fileMetadataBuffer),
                C.end());
              return;
            }
            const U = l[R++];
            if (U.kind === n.OperationKind.COPY) {
              (w && w.beginFileCopy(), (0, i.copyData)(U, C, y, E, () => g(R)));
              return;
            }
            const $ = `bytes=${U.start}-${U.end - 1}`;
            ((P.headers.range = $),
              (q =
                (k = this.logger) === null || k === void 0
                  ? void 0
                  : k.debug) === null ||
                q === void 0 ||
                q.call(k, `download range: ${$}`),
              w && w.beginRangeDownload());
            const V = this.httpExecutor.createRequest(P, (re) => {
              (re.on("error", E),
                re.on("aborted", () => {
                  E(new Error("response has been aborted by the server"));
                }),
                re.statusCode >= 400 && E((0, e.createHttpError)(re)),
                re.pipe(C, { end: !1 }),
                re.once("end", () => {
                  (w && w.endRangeDownload(),
                    ++D === 100
                      ? ((D = 0), setTimeout(() => g(R), 1e3))
                      : g(R));
                }));
            });
            (V.on("redirect", (re, X, fe) => {
              (this.logger.info(`Redirect to ${d(fe)}`),
                (N = fe),
                (0, e.configureRequestUrl)(new a.URL(N), P),
                V.followRedirect());
            }),
              this.httpExecutor.addErrorAndTimeoutHandlers(V, E),
              V.end());
          }),
          g(0));
      });
    }
    async readRemoteBytes(l, h) {
      const y = Buffer.allocUnsafe(h + 1 - l),
        F = this.createRequestOptions();
      F.headers.range = `bytes=${l}-${h}`;
      let m = 0;
      if (
        (await this.request(F, (S) => {
          (S.copy(y, m), (m += S.length));
        }),
        m !== y.length)
      )
        throw new Error(
          `Received data length ${m} is not equal to expected ${y.length}`,
        );
      return y;
    }
    request(l, h) {
      return new Promise((y, F) => {
        const m = this.httpExecutor.createRequest(l, (S) => {
          (0, r.checkIsRangesSupported)(S, F) &&
            (S.on("error", F),
            S.on("aborted", () => {
              F(new Error("response has been aborted by the server"));
            }),
            S.on("data", h),
            S.on("end", () => y()));
        });
        (this.httpExecutor.addErrorAndTimeoutHandlers(m, F), m.end());
      });
    }
  };
  _n.DifferentialDownloader = u;
  function f(c, l = " KB") {
    return new Intl.NumberFormat("en").format((c / 1024).toFixed(2)) + l;
  }
  function d(c) {
    const l = c.indexOf("?");
    return l < 0 ? c : c.substring(0, l);
  }
  return _n;
}
var Sf;
function _2() {
  if (Sf) return Sn;
  ((Sf = 1),
    Object.defineProperty(Sn, "__esModule", { value: !0 }),
    (Sn.GenericDifferentialDownloader = void 0));
  const e = Tp();
  let t = class extends e.DifferentialDownloader {
    download(i, a) {
      return this.doDownload(i, a);
    }
  };
  return ((Sn.GenericDifferentialDownloader = t), Sn);
}
var Ds = {},
  _f;
function kr() {
  return (
    _f ||
      ((_f = 1),
      (function (e) {
        (Object.defineProperty(e, "__esModule", { value: !0 }),
          (e.UpdaterSignal =
            e.UPDATE_DOWNLOADED =
            e.DOWNLOAD_PROGRESS =
            e.CancellationToken =
              void 0),
          (e.addHandler = i));
        const t = rt();
        (Object.defineProperty(e, "CancellationToken", {
          enumerable: !0,
          get: function () {
            return t.CancellationToken;
          },
        }),
          (e.DOWNLOAD_PROGRESS = "download-progress"),
          (e.UPDATE_DOWNLOADED = "update-downloaded"));
        class o {
          constructor(n) {
            this.emitter = n;
          }
          login(n) {
            i(this.emitter, "login", n);
          }
          progress(n) {
            i(this.emitter, e.DOWNLOAD_PROGRESS, n);
          }
          updateDownloaded(n) {
            i(this.emitter, e.UPDATE_DOWNLOADED, n);
          }
          updateCancelled(n) {
            i(this.emitter, "update-cancelled", n);
          }
        }
        e.UpdaterSignal = o;
        function i(a, n, r) {
          a.on(n, r);
        }
      })(Ds)),
    Ds
  );
}
var Tf;
function fu() {
  if (Tf) return Ar;
  ((Tf = 1),
    Object.defineProperty(Ar, "__esModule", { value: !0 }),
    (Ar.NoOpLogger = Ar.AppUpdater = void 0));
  const e = rt(),
    t = xt,
    o = Ke,
    i = Zs,
    a = Dr(),
    n = lu(),
    r = p2(),
    s = G,
    u = Gh(),
    f = m2(),
    d = w2(),
    c = y2(),
    l = Fp(),
    h = b2(),
    y = eu,
    F = Br(),
    m = _2(),
    S = kr();
  let E = class xp extends i.EventEmitter {
    get channel() {
      return this._channel;
    }
    set channel(v) {
      if (this._channel != null) {
        if (typeof v != "string")
          throw (0, e.newError)(
            `Channel must be a string, but got: ${v}`,
            "ERR_UPDATER_INVALID_CHANNEL",
          );
        if (v.length === 0)
          throw (0, e.newError)(
            "Channel must be not an empty string",
            "ERR_UPDATER_INVALID_CHANNEL",
          );
      }
      ((this._channel = v), (this.allowDowngrade = !0));
    }
    addAuthHeader(v) {
      this.requestHeaders = Object.assign({}, this.requestHeaders, {
        authorization: v,
      });
    }
    get netSession() {
      return (0, c.getNetSession)();
    }
    get logger() {
      return this._logger;
    }
    set logger(v) {
      this._logger = v ?? new w();
    }
    set updateConfigPath(v) {
      ((this.clientPromise = null),
        (this._appUpdateConfigPath = v),
        (this.configOnDisk = new r.Lazy(() => this.loadUpdateConfig())));
    }
    get isUpdateSupported() {
      return this._isUpdateSupported;
    }
    set isUpdateSupported(v) {
      v && (this._isUpdateSupported = v);
    }
    get isUserWithinRollout() {
      return this._isUserWithinRollout;
    }
    set isUserWithinRollout(v) {
      v && (this._isUserWithinRollout = v);
    }
    constructor(v, C) {
      (super(),
        (this.autoDownload = !0),
        (this.autoInstallOnAppQuit = !0),
        (this.autoRunAppAfterInstall = !0),
        (this.allowPrerelease = !1),
        (this.fullChangelog = !1),
        (this.allowDowngrade = !1),
        (this.disableWebInstaller = !1),
        (this.disableDifferentialDownload = !1),
        (this.forceDevUpdateConfig = !1),
        (this._channel = null),
        (this.downloadedUpdateHelper = null),
        (this.requestHeaders = null),
        (this._logger = console),
        (this.signals = new S.UpdaterSignal(this)),
        (this._appUpdateConfigPath = null),
        (this._isUpdateSupported = (N) => this.checkIfUpdateSupported(N)),
        (this._isUserWithinRollout = (N) => this.isStagingMatch(N)),
        (this.clientPromise = null),
        (this.stagingUserIdPromise = new r.Lazy(() =>
          this.getOrCreateStagingUserId(),
        )),
        (this.configOnDisk = new r.Lazy(() => this.loadUpdateConfig())),
        (this.checkForUpdatesPromise = null),
        (this.downloadPromise = null),
        (this.updateInfoAndProvider = null),
        (this._testOnlyOptions = null),
        this.on("error", (N) => {
          this._logger.error(`Error: ${N.stack || N.message}`);
        }),
        C == null
          ? ((this.app = new d.ElectronAppAdapter()),
            (this.httpExecutor = new c.ElectronHttpExecutor((N, P) =>
              this.emit("login", N, P),
            )))
          : ((this.app = C), (this.httpExecutor = null)));
      const g = this.app.version,
        D = (0, u.parse)(g);
      if (D == null)
        throw (0, e.newError)(
          `App version is not a valid semver version: "${g}"`,
          "ERR_UPDATER_INVALID_VERSION",
        );
      ((this.currentVersion = D),
        (this.allowPrerelease = b(D)),
        v != null &&
          (this.setFeedURL(v),
          typeof v != "string" &&
            v.requestHeaders &&
            (this.requestHeaders = v.requestHeaders)));
    }
    getFeedURL() {
      return "Deprecated. Do not use it.";
    }
    setFeedURL(v) {
      const C = this.createProviderRuntimeOptions();
      let g;
      (typeof v == "string"
        ? (g = new l.GenericProvider({ provider: "generic", url: v }, this, {
            ...C,
            isUseMultipleRangeRequest: (0,
            h.isUrlProbablySupportMultiRangeRequests)(v),
          }))
        : (g = (0, h.createClient)(v, this, C)),
        (this.clientPromise = Promise.resolve(g)));
    }
    checkForUpdates() {
      if (!this.isUpdaterActive()) return Promise.resolve(null);
      let v = this.checkForUpdatesPromise;
      if (v != null)
        return (
          this._logger.info("Checking for update (already in progress)"),
          v
        );
      const C = () => (this.checkForUpdatesPromise = null);
      return (
        this._logger.info("Checking for update"),
        (v = this.doCheckForUpdates()
          .then((g) => (C(), g))
          .catch((g) => {
            throw (
              C(),
              this.emit(
                "error",
                g,
                `Cannot check for updates: ${(g.stack || g).toString()}`,
              ),
              g
            );
          })),
        (this.checkForUpdatesPromise = v),
        v
      );
    }
    isUpdaterActive() {
      return this.app.isPackaged || this.forceDevUpdateConfig
        ? !0
        : (this._logger.info(
            "Skip checkForUpdates because application is not packed and dev update config is not forced",
          ),
          !1);
    }
    checkForUpdatesAndNotify(v) {
      return this.checkForUpdates().then((C) =>
        C?.downloadPromise
          ? (C.downloadPromise.then(() => {
              const g = xp.formatDownloadNotification(
                C.updateInfo.version,
                this.app.name,
                v,
              );
              new Or.Notification(g).show();
            }),
            C)
          : (this._logger.debug != null &&
              this._logger.debug(
                "checkForUpdatesAndNotify called, downloadPromise is null",
              ),
            C),
      );
    }
    static formatDownloadNotification(v, C, g) {
      return (
        g == null &&
          (g = {
            title: "A new update is ready to install",
            body: "{appName} version {version} has been downloaded and will be automatically installed on exit",
          }),
        (g = {
          title: g.title.replace("{appName}", C).replace("{version}", v),
          body: g.body.replace("{appName}", C).replace("{version}", v),
        }),
        g
      );
    }
    async isStagingMatch(v) {
      const C = v.stagingPercentage;
      let g = C;
      if (g == null) return !0;
      if (((g = parseInt(g, 10)), isNaN(g)))
        return (this._logger.warn(`Staging percentage is NaN: ${C}`), !0);
      g = g / 100;
      const D = await this.stagingUserIdPromise.value,
        P = e.UUID.parse(D).readUInt32BE(12) / 4294967295;
      return (
        this._logger.info(
          `Staging percentage: ${g}, percentage: ${P}, user id: ${D}`,
        ),
        P < g
      );
    }
    computeFinalHeaders(v) {
      return (
        this.requestHeaders != null && Object.assign(v, this.requestHeaders),
        v
      );
    }
    async isUpdateAvailable(v) {
      const C = (0, u.parse)(v.version);
      if (C == null)
        throw (0, e.newError)(
          `This file could not be downloaded, or the latest version (from update server) does not have a valid semver version: "${v.version}"`,
          "ERR_UPDATER_INVALID_VERSION",
        );
      const g = this.currentVersion;
      if (
        (0, u.eq)(C, g) ||
        !(await Promise.resolve(this.isUpdateSupported(v))) ||
        !(await Promise.resolve(this.isUserWithinRollout(v)))
      )
        return !1;
      const N = (0, u.gt)(C, g),
        P = (0, u.lt)(C, g);
      return N ? !0 : this.allowDowngrade && P;
    }
    checkIfUpdateSupported(v) {
      const C = v?.minimumSystemVersion,
        g = (0, o.release)();
      if (C)
        try {
          if ((0, u.lt)(g, C))
            return (
              this._logger.info(
                `Current OS version ${g} is less than the minimum OS version required ${C} for version ${g}`,
              ),
              !1
            );
        } catch (D) {
          this._logger.warn(
            `Failed to compare current OS version(${g}) with minimum OS version(${C}): ${(D.message || D).toString()}`,
          );
        }
      return !0;
    }
    async getUpdateInfoAndProvider() {
      (await this.app.whenReady(),
        this.clientPromise == null &&
          (this.clientPromise = this.configOnDisk.value.then((g) =>
            (0, h.createClient)(g, this, this.createProviderRuntimeOptions()),
          )));
      const v = await this.clientPromise,
        C = await this.stagingUserIdPromise.value;
      return (
        v.setRequestHeaders(
          this.computeFinalHeaders({ "x-user-staging-id": C }),
        ),
        { info: await v.getLatestVersion(), provider: v }
      );
    }
    createProviderRuntimeOptions() {
      return {
        isUseMultipleRangeRequest: !0,
        platform:
          this._testOnlyOptions == null
            ? process.platform
            : this._testOnlyOptions.platform,
        executor: this.httpExecutor,
      };
    }
    async doCheckForUpdates() {
      this.emit("checking-for-update");
      const v = await this.getUpdateInfoAndProvider(),
        C = v.info;
      if (!(await this.isUpdateAvailable(C)))
        return (
          this._logger.info(
            `Update for version ${this.currentVersion.format()} is not available (latest version: ${C.version}, downgrade is ${this.allowDowngrade ? "allowed" : "disallowed"}).`,
          ),
          this.emit("update-not-available", C),
          { isUpdateAvailable: !1, versionInfo: C, updateInfo: C }
        );
      ((this.updateInfoAndProvider = v), this.onUpdateAvailable(C));
      const g = new e.CancellationToken();
      return {
        isUpdateAvailable: !0,
        versionInfo: C,
        updateInfo: C,
        cancellationToken: g,
        downloadPromise: this.autoDownload ? this.downloadUpdate(g) : null,
      };
    }
    onUpdateAvailable(v) {
      (this._logger.info(
        `Found version ${v.version} (url: ${(0, e.asArray)(v.files)
          .map((C) => C.url)
          .join(", ")})`,
      ),
        this.emit("update-available", v));
    }
    downloadUpdate(v = new e.CancellationToken()) {
      const C = this.updateInfoAndProvider;
      if (C == null) {
        const D = new Error("Please check update first");
        return (this.dispatchError(D), Promise.reject(D));
      }
      if (this.downloadPromise != null)
        return (
          this._logger.info("Downloading update (already in progress)"),
          this.downloadPromise
        );
      this._logger.info(
        `Downloading update from ${(0, e.asArray)(C.info.files)
          .map((D) => D.url)
          .join(", ")}`,
      );
      const g = (D) => {
        if (!(D instanceof e.CancellationError))
          try {
            this.dispatchError(D);
          } catch (N) {
            this._logger.warn(`Cannot dispatch error event: ${N.stack || N}`);
          }
        return D;
      };
      return (
        (this.downloadPromise = this.doDownloadUpdate({
          updateInfoAndProvider: C,
          requestHeaders: this.computeRequestHeaders(C.provider),
          cancellationToken: v,
          disableWebInstaller: this.disableWebInstaller,
          disableDifferentialDownload: this.disableDifferentialDownload,
        })
          .catch((D) => {
            throw g(D);
          })
          .finally(() => {
            this.downloadPromise = null;
          })),
        this.downloadPromise
      );
    }
    dispatchError(v) {
      this.emit("error", v, (v.stack || v).toString());
    }
    dispatchUpdateDownloaded(v) {
      this.emit(S.UPDATE_DOWNLOADED, v);
    }
    async loadUpdateConfig() {
      return (
        this._appUpdateConfigPath == null &&
          (this._appUpdateConfigPath = this.app.appUpdateConfigPath),
        (0, n.load)(await (0, a.readFile)(this._appUpdateConfigPath, "utf-8"))
      );
    }
    computeRequestHeaders(v) {
      const C = v.fileExtraDownloadHeaders;
      if (C != null) {
        const g = this.requestHeaders;
        return g == null ? C : { ...C, ...g };
      }
      return this.computeFinalHeaders({ accept: "*/*" });
    }
    async getOrCreateStagingUserId() {
      const v = s.join(this.app.userDataPath, ".updaterId");
      try {
        const g = await (0, a.readFile)(v, "utf-8");
        if (e.UUID.check(g)) return g;
        this._logger.warn(
          `Staging user id file exists, but content was invalid: ${g}`,
        );
      } catch (g) {
        g.code !== "ENOENT" &&
          this._logger.warn(
            `Couldn't read staging user ID, creating a blank one: ${g}`,
          );
      }
      const C = e.UUID.v5((0, t.randomBytes)(4096), e.UUID.OID);
      this._logger.info(`Generated new staging user ID: ${C}`);
      try {
        await (0, a.outputFile)(v, C);
      } catch (g) {
        this._logger.warn(`Couldn't write out staging user ID: ${g}`);
      }
      return C;
    }
    get isAddNoCacheQuery() {
      const v = this.requestHeaders;
      if (v == null) return !0;
      for (const C of Object.keys(v)) {
        const g = C.toLowerCase();
        if (g === "authorization" || g === "private-token") return !1;
      }
      return !0;
    }
    async getOrCreateDownloadHelper() {
      let v = this.downloadedUpdateHelper;
      if (v == null) {
        const C = (await this.configOnDisk.value).updaterCacheDirName,
          g = this._logger;
        C == null &&
          g.error(
            "updaterCacheDirName is not specified in app-update.yml Was app build using at least electron-builder 20.34.0?",
          );
        const D = s.join(this.app.baseCachePath, C || this.app.name);
        (g.debug != null && g.debug(`updater cache dir: ${D}`),
          (v = new f.DownloadedUpdateHelper(D)),
          (this.downloadedUpdateHelper = v));
      }
      return v;
    }
    async executeDownload(v) {
      const C = v.fileInfo,
        g = {
          headers: v.downloadUpdateOptions.requestHeaders,
          cancellationToken: v.downloadUpdateOptions.cancellationToken,
          sha2: C.info.sha2,
          sha512: C.info.sha512,
        };
      this.listenerCount(S.DOWNLOAD_PROGRESS) > 0 &&
        (g.onProgress = (ue) => this.emit(S.DOWNLOAD_PROGRESS, ue));
      const D = v.downloadUpdateOptions.updateInfoAndProvider.info,
        N = D.version,
        P = C.packageInfo;
      function R() {
        const ue = decodeURIComponent(v.fileInfo.url.pathname);
        return ue.toLowerCase().endsWith(`.${v.fileExtension.toLowerCase()}`)
          ? s.basename(ue)
          : v.fileInfo.info.url;
      }
      const k = await this.getOrCreateDownloadHelper(),
        q = k.cacheDirForPendingUpdate;
      await (0, a.mkdir)(q, { recursive: !0 });
      const U = R();
      let $ = s.join(q, U);
      const V =
          P == null
            ? null
            : s.join(q, `package-${N}${s.extname(P.path) || ".7z"}`),
        re = async (ue) => (
          await k.setDownloadedFile($, V, D, C, U, ue),
          await v.done({ ...D, downloadedFile: $ }),
          V == null ? [$] : [$, V]
        ),
        X = this._logger,
        fe = await k.validateDownloadedPath($, D, C, X);
      if (fe != null) return (($ = fe), await re(!1));
      const Y = async () => (
          await k.clear().catch(() => {}),
          await (0, a.unlink)($).catch(() => {})
        ),
        Ce = await (0, f.createTempUpdateFile)(`temp-${U}`, q, X);
      try {
        (await v.task(Ce, g, V, Y),
          await (0, e.retry)(
            () => (0, a.rename)(Ce, $),
            60,
            500,
            0,
            0,
            (ue) => ue instanceof Error && /^EBUSY:/.test(ue.message),
          ));
      } catch (ue) {
        throw (
          await Y(),
          ue instanceof e.CancellationError &&
            (X.info("cancelled"), this.emit("update-cancelled", D)),
          ue
        );
      }
      return (
        X.info(`New version ${N} has been downloaded to ${$}`),
        await re(!0)
      );
    }
    async differentialDownloadInstaller(v, C, g, D, N) {
      try {
        if (
          this._testOnlyOptions != null &&
          !this._testOnlyOptions.isUseDifferentialDownload
        )
          return !0;
        const P = (0, F.blockmapFiles)(
          v.url,
          this.app.version,
          C.updateInfoAndProvider.info.version,
        );
        this._logger.info(`Download block maps (old: "${P[0]}", new: ${P[1]})`);
        const R = async (U) => {
            const $ = await this.httpExecutor.downloadToBuffer(U, {
              headers: C.requestHeaders,
              cancellationToken: C.cancellationToken,
            });
            if ($ == null || $.length === 0)
              throw new Error(`Blockmap "${U.href}" is empty`);
            try {
              return JSON.parse((0, y.gunzipSync)($).toString());
            } catch (V) {
              throw new Error(`Cannot parse blockmap "${U.href}", error: ${V}`);
            }
          },
          k = {
            newUrl: v.url,
            oldFile: s.join(this.downloadedUpdateHelper.cacheDir, N),
            logger: this._logger,
            newFile: g,
            isUseMultipleRangeRequest: D.isUseMultipleRangeRequest,
            requestHeaders: C.requestHeaders,
            cancellationToken: C.cancellationToken,
          };
        this.listenerCount(S.DOWNLOAD_PROGRESS) > 0 &&
          (k.onProgress = (U) => this.emit(S.DOWNLOAD_PROGRESS, U));
        const q = await Promise.all(P.map((U) => R(U)));
        return (
          await new m.GenericDifferentialDownloader(
            v.info,
            this.httpExecutor,
            k,
          ).download(q[0], q[1]),
          !1
        );
      } catch (P) {
        if (
          (this._logger.error(
            `Cannot download differentially, fallback to full download: ${P.stack || P}`,
          ),
          this._testOnlyOptions != null)
        )
          throw P;
        return !0;
      }
    }
  };
  Ar.AppUpdater = E;
  function b(A) {
    const v = (0, u.prerelease)(A);
    return v != null && v.length > 0;
  }
  class w {
    info(v) {}
    warn(v) {}
    error(v) {}
  }
  return ((Ar.NoOpLogger = w), Ar);
}
var xf;
function un() {
  if (xf) return Dn;
  ((xf = 1),
    Object.defineProperty(Dn, "__esModule", { value: !0 }),
    (Dn.BaseUpdater = void 0));
  const e = qo,
    t = fu();
  let o = class extends t.AppUpdater {
    constructor(a, n) {
      (super(a, n),
        (this.quitAndInstallCalled = !1),
        (this.quitHandlerAdded = !1));
    }
    quitAndInstall(a = !1, n = !1) {
      (this._logger.info("Install on explicit quitAndInstall"),
        this.install(a, a ? n : this.autoRunAppAfterInstall)
          ? setImmediate(() => {
              (Or.autoUpdater.emit("before-quit-for-update"), this.app.quit());
            })
          : (this.quitAndInstallCalled = !1));
    }
    executeDownload(a) {
      return super.executeDownload({
        ...a,
        done: (n) => (
          this.dispatchUpdateDownloaded(n),
          this.addQuitHandler(),
          Promise.resolve()
        ),
      });
    }
    get installerPath() {
      return this.downloadedUpdateHelper == null
        ? null
        : this.downloadedUpdateHelper.file;
    }
    install(a = !1, n = !1) {
      if (this.quitAndInstallCalled)
        return (
          this._logger.warn(
            "install call ignored: quitAndInstallCalled is set to true",
          ),
          !1
        );
      const r = this.downloadedUpdateHelper,
        s = this.installerPath,
        u = r == null ? null : r.downloadedFileInfo;
      if (s == null || u == null)
        return (
          this.dispatchError(
            new Error("No valid update available, can't quit and install"),
          ),
          !1
        );
      this.quitAndInstallCalled = !0;
      try {
        return (
          this._logger.info(`Install: isSilent: ${a}, isForceRunAfter: ${n}`),
          this.doInstall({
            isSilent: a,
            isForceRunAfter: n,
            isAdminRightsRequired: u.isAdminRightsRequired,
          })
        );
      } catch (f) {
        return (this.dispatchError(f), !1);
      }
    }
    addQuitHandler() {
      this.quitHandlerAdded ||
        !this.autoInstallOnAppQuit ||
        ((this.quitHandlerAdded = !0),
        this.app.onQuit((a) => {
          if (this.quitAndInstallCalled) {
            this._logger.info(
              "Update installer has already been triggered. Quitting application.",
            );
            return;
          }
          if (!this.autoInstallOnAppQuit) {
            this._logger.info(
              "Update will not be installed on quit because autoInstallOnAppQuit is set to false.",
            );
            return;
          }
          if (a !== 0) {
            this._logger.info(
              `Update will be not installed on quit because application is quitting with exit code ${a}`,
            );
            return;
          }
          (this._logger.info("Auto install update on quit"),
            this.install(!0, !1));
        }));
    }
    wrapSudo() {
      const { name: a } = this.app,
        n = `"${a} would like to update"`,
        r = this.spawnSyncLog(
          "which gksudo || which kdesudo || which pkexec || which beesu",
        ),
        s = [r];
      return (
        /kdesudo/i.test(r)
          ? (s.push("--comment", n), s.push("-c"))
          : /gksudo/i.test(r)
            ? s.push("--message", n)
            : /pkexec/i.test(r) && s.push("--disable-internal-agent"),
        s.join(" ")
      );
    }
    spawnSyncLog(a, n = [], r = {}) {
      this._logger.info(`Executing: ${a} with args: ${n}`);
      const s = (0, e.spawnSync)(a, n, {
          env: { ...process.env, ...r },
          encoding: "utf-8",
          shell: !0,
        }),
        { error: u, status: f, stdout: d, stderr: c } = s;
      if (u != null) throw (this._logger.error(c), u);
      if (f != null && f !== 0)
        throw (
          this._logger.error(c),
          new Error(`Command ${a} exited with code ${f}`)
        );
      return d.trim();
    }
    async spawnLog(a, n = [], r = void 0, s = "ignore") {
      return (
        this._logger.info(`Executing: ${a} with args: ${n}`),
        new Promise((u, f) => {
          try {
            const d = { stdio: s, env: r, detached: !0 },
              c = (0, e.spawn)(a, n, d);
            (c.on("error", (l) => {
              f(l);
            }),
              c.unref(),
              c.pid !== void 0 && u(!0));
          } catch (d) {
            f(d);
          }
        })
      );
    }
  };
  return ((Dn.BaseUpdater = o), Dn);
}
var Nn = {},
  In = {},
  Nf;
function Np() {
  if (Nf) return In;
  ((Nf = 1),
    Object.defineProperty(In, "__esModule", { value: !0 }),
    (In.FileWithEmbeddedBlockMapDifferentialDownloader = void 0));
  const e = Dr(),
    t = Tp(),
    o = eu;
  let i = class extends t.DifferentialDownloader {
    async download() {
      const s = this.blockAwareFileInfo,
        u = s.size,
        f = u - (s.blockMapSize + 4);
      this.fileMetadataBuffer = await this.readRemoteBytes(f, u - 1);
      const d = a(
        this.fileMetadataBuffer.slice(0, this.fileMetadataBuffer.length - 4),
      );
      await this.doDownload(await n(this.options.oldFile), d);
    }
  };
  In.FileWithEmbeddedBlockMapDifferentialDownloader = i;
  function a(r) {
    return JSON.parse((0, o.inflateRawSync)(r).toString());
  }
  async function n(r) {
    const s = await (0, e.open)(r, "r");
    try {
      const u = (await (0, e.fstat)(s)).size,
        f = Buffer.allocUnsafe(4);
      await (0, e.read)(s, f, 0, f.length, u - f.length);
      const d = Buffer.allocUnsafe(f.readUInt32BE(0));
      return (
        await (0, e.read)(s, d, 0, d.length, u - f.length - d.length),
        await (0, e.close)(s),
        a(d)
      );
    } catch (u) {
      throw (await (0, e.close)(s), u);
    }
  }
  return In;
}
var If;
function Of() {
  if (If) return Nn;
  ((If = 1),
    Object.defineProperty(Nn, "__esModule", { value: !0 }),
    (Nn.AppImageUpdater = void 0));
  const e = rt(),
    t = qo,
    o = Dr(),
    i = ze,
    a = G,
    n = un(),
    r = Np(),
    s = bt(),
    u = kr();
  let f = class extends n.BaseUpdater {
    constructor(c, l) {
      super(c, l);
    }
    isUpdaterActive() {
      return process.env.APPIMAGE == null
        ? (process.env.SNAP == null
            ? this._logger.warn(
                "APPIMAGE env is not defined, current application is not an AppImage",
              )
            : this._logger.info("SNAP env is defined, updater is disabled"),
          !1)
        : super.isUpdaterActive();
    }
    doDownloadUpdate(c) {
      const l = c.updateInfoAndProvider.provider,
        h = (0, s.findFile)(
          l.resolveFiles(c.updateInfoAndProvider.info),
          "AppImage",
          ["rpm", "deb", "pacman"],
        );
      return this.executeDownload({
        fileExtension: "AppImage",
        fileInfo: h,
        downloadUpdateOptions: c,
        task: async (y, F) => {
          const m = process.env.APPIMAGE;
          if (m == null)
            throw (0, e.newError)(
              "APPIMAGE env is not defined",
              "ERR_UPDATER_OLD_FILE_NOT_FOUND",
            );
          ((c.disableDifferentialDownload ||
            (await this.downloadDifferential(h, m, y, l, c))) &&
            (await this.httpExecutor.download(h.url, y, F)),
            await (0, o.chmod)(y, 493));
        },
      });
    }
    async downloadDifferential(c, l, h, y, F) {
      try {
        const m = {
          newUrl: c.url,
          oldFile: l,
          logger: this._logger,
          newFile: h,
          isUseMultipleRangeRequest: y.isUseMultipleRangeRequest,
          requestHeaders: F.requestHeaders,
          cancellationToken: F.cancellationToken,
        };
        return (
          this.listenerCount(u.DOWNLOAD_PROGRESS) > 0 &&
            (m.onProgress = (S) => this.emit(u.DOWNLOAD_PROGRESS, S)),
          await new r.FileWithEmbeddedBlockMapDifferentialDownloader(
            c.info,
            this.httpExecutor,
            m,
          ).download(),
          !1
        );
      } catch (m) {
        return (
          this._logger.error(
            `Cannot download differentially, fallback to full download: ${m.stack || m}`,
          ),
          process.platform === "linux"
        );
      }
    }
    doInstall(c) {
      const l = process.env.APPIMAGE;
      if (l == null)
        throw (0, e.newError)(
          "APPIMAGE env is not defined",
          "ERR_UPDATER_OLD_FILE_NOT_FOUND",
        );
      (0, i.unlinkSync)(l);
      let h;
      const y = a.basename(l),
        F = this.installerPath;
      if (F == null)
        return (
          this.dispatchError(
            new Error("No valid update available, can't quit and install"),
          ),
          !1
        );
      (a.basename(F) === y || !/\d+\.\d+\.\d+/.test(y)
        ? (h = l)
        : (h = a.join(a.dirname(l), a.basename(F))),
        (0, t.execFileSync)("mv", ["-f", F, h]),
        h !== l && this.emit("appimage-filename-updated", h));
      const m = { ...process.env, APPIMAGE_SILENT_INSTALL: "true" };
      return (
        c.isForceRunAfter
          ? this.spawnLog(h, [], m)
          : ((m.APPIMAGE_EXIT_AFTER_INSTALL = "true"),
            (0, t.execFileSync)(h, [], { env: m })),
        !0
      );
    }
  };
  return ((Nn.AppImageUpdater = f), Nn);
}
var On = {},
  Pf;
function Rf() {
  if (Pf) return On;
  ((Pf = 1),
    Object.defineProperty(On, "__esModule", { value: !0 }),
    (On.DebUpdater = void 0));
  const e = un(),
    t = bt(),
    o = kr();
  let i = class extends e.BaseUpdater {
    constructor(n, r) {
      super(n, r);
    }
    doDownloadUpdate(n) {
      const r = n.updateInfoAndProvider.provider,
        s = (0, t.findFile)(
          r.resolveFiles(n.updateInfoAndProvider.info),
          "deb",
          ["AppImage", "rpm", "pacman"],
        );
      return this.executeDownload({
        fileExtension: "deb",
        fileInfo: s,
        downloadUpdateOptions: n,
        task: async (u, f) => {
          (this.listenerCount(o.DOWNLOAD_PROGRESS) > 0 &&
            (f.onProgress = (d) => this.emit(o.DOWNLOAD_PROGRESS, d)),
            await this.httpExecutor.download(s.url, u, f));
        },
      });
    }
    get installerPath() {
      var n, r;
      return (r =
        (n = super.installerPath) === null || n === void 0
          ? void 0
          : n.replace(/ /g, "\\ ")) !== null && r !== void 0
        ? r
        : null;
    }
    doInstall(n) {
      const r = this.wrapSudo(),
        s = /pkexec/i.test(r) ? "" : '"',
        u = this.installerPath;
      if (u == null)
        return (
          this.dispatchError(
            new Error("No valid update available, can't quit and install"),
          ),
          !1
        );
      const f = ["dpkg", "-i", u, "||", "apt-get", "install", "-f", "-y"];
      return (
        this.spawnSyncLog(r, [`${s}/bin/bash`, "-c", `'${f.join(" ")}'${s}`]),
        n.isForceRunAfter && this.app.relaunch(),
        !0
      );
    }
  };
  return ((On.DebUpdater = i), On);
}
var Pn = {},
  Lf;
function Bf() {
  if (Lf) return Pn;
  ((Lf = 1),
    Object.defineProperty(Pn, "__esModule", { value: !0 }),
    (Pn.PacmanUpdater = void 0));
  const e = un(),
    t = kr(),
    o = bt();
  let i = class extends e.BaseUpdater {
    constructor(n, r) {
      super(n, r);
    }
    doDownloadUpdate(n) {
      const r = n.updateInfoAndProvider.provider,
        s = (0, o.findFile)(
          r.resolveFiles(n.updateInfoAndProvider.info),
          "pacman",
          ["AppImage", "deb", "rpm"],
        );
      return this.executeDownload({
        fileExtension: "pacman",
        fileInfo: s,
        downloadUpdateOptions: n,
        task: async (u, f) => {
          (this.listenerCount(t.DOWNLOAD_PROGRESS) > 0 &&
            (f.onProgress = (d) => this.emit(t.DOWNLOAD_PROGRESS, d)),
            await this.httpExecutor.download(s.url, u, f));
        },
      });
    }
    get installerPath() {
      var n, r;
      return (r =
        (n = super.installerPath) === null || n === void 0
          ? void 0
          : n.replace(/ /g, "\\ ")) !== null && r !== void 0
        ? r
        : null;
    }
    doInstall(n) {
      const r = this.wrapSudo(),
        s = /pkexec/i.test(r) ? "" : '"',
        u = this.installerPath;
      if (u == null)
        return (
          this.dispatchError(
            new Error("No valid update available, can't quit and install"),
          ),
          !1
        );
      const f = ["pacman", "-U", "--noconfirm", u];
      return (
        this.spawnSyncLog(r, [`${s}/bin/bash`, "-c", `'${f.join(" ")}'${s}`]),
        n.isForceRunAfter && this.app.relaunch(),
        !0
      );
    }
  };
  return ((Pn.PacmanUpdater = i), Pn);
}
var Rn = {},
  kf;
function Mf() {
  if (kf) return Rn;
  ((kf = 1),
    Object.defineProperty(Rn, "__esModule", { value: !0 }),
    (Rn.RpmUpdater = void 0));
  const e = un(),
    t = kr(),
    o = bt();
  let i = class extends e.BaseUpdater {
    constructor(n, r) {
      super(n, r);
    }
    doDownloadUpdate(n) {
      const r = n.updateInfoAndProvider.provider,
        s = (0, o.findFile)(
          r.resolveFiles(n.updateInfoAndProvider.info),
          "rpm",
          ["AppImage", "deb", "pacman"],
        );
      return this.executeDownload({
        fileExtension: "rpm",
        fileInfo: s,
        downloadUpdateOptions: n,
        task: async (u, f) => {
          (this.listenerCount(t.DOWNLOAD_PROGRESS) > 0 &&
            (f.onProgress = (d) => this.emit(t.DOWNLOAD_PROGRESS, d)),
            await this.httpExecutor.download(s.url, u, f));
        },
      });
    }
    get installerPath() {
      var n, r;
      return (r =
        (n = super.installerPath) === null || n === void 0
          ? void 0
          : n.replace(/ /g, "\\ ")) !== null && r !== void 0
        ? r
        : null;
    }
    doInstall(n) {
      const r = this.wrapSudo(),
        s = /pkexec/i.test(r) ? "" : '"',
        u = this.spawnSyncLog("which zypper"),
        f = this.installerPath;
      if (f == null)
        return (
          this.dispatchError(
            new Error("No valid update available, can't quit and install"),
          ),
          !1
        );
      let d;
      return (
        u
          ? (d = [
              u,
              "--no-refresh",
              "install",
              "--allow-unsigned-rpm",
              "-y",
              "-f",
              f,
            ])
          : (d = [
              this.spawnSyncLog("which dnf || which yum"),
              "-y",
              "install",
              f,
            ]),
        this.spawnSyncLog(r, [`${s}/bin/bash`, "-c", `'${d.join(" ")}'${s}`]),
        n.isForceRunAfter && this.app.relaunch(),
        !0
      );
    }
  };
  return ((Rn.RpmUpdater = i), Rn);
}
var Ln = {},
  Uf;
function qf() {
  if (Uf) return Ln;
  ((Uf = 1),
    Object.defineProperty(Ln, "__esModule", { value: !0 }),
    (Ln.MacUpdater = void 0));
  const e = rt(),
    t = Dr(),
    o = ze,
    i = G,
    a = Vh,
    n = fu(),
    r = bt(),
    s = qo,
    u = xt;
  let f = class extends n.AppUpdater {
    constructor(c, l) {
      (super(c, l),
        (this.nativeUpdater = Or.autoUpdater),
        (this.squirrelDownloadedUpdate = !1),
        this.nativeUpdater.on("error", (h) => {
          (this._logger.warn(h), this.emit("error", h));
        }),
        this.nativeUpdater.on("update-downloaded", () => {
          ((this.squirrelDownloadedUpdate = !0),
            this.debug("nativeUpdater.update-downloaded"));
        }));
    }
    debug(c) {
      this._logger.debug != null && this._logger.debug(c);
    }
    closeServerIfExists() {
      this.server &&
        (this.debug("Closing proxy server"),
        this.server.close((c) => {
          c &&
            this.debug(
              "proxy server wasn't already open, probably attempted closing again as a safety check before quit",
            );
        }));
    }
    async doDownloadUpdate(c) {
      let l = c.updateInfoAndProvider.provider.resolveFiles(
        c.updateInfoAndProvider.info,
      );
      const h = this._logger,
        y = "sysctl.proc_translated";
      let F = !1;
      try {
        (this.debug("Checking for macOS Rosetta environment"),
          (F = (0, s.execFileSync)("sysctl", [y], {
            encoding: "utf8",
          }).includes(`${y}: 1`)),
          h.info(`Checked for macOS Rosetta environment (isRosetta=${F})`));
      } catch (A) {
        h.warn(
          `sysctl shell command to check for macOS Rosetta environment failed: ${A}`,
        );
      }
      let m = !1;
      try {
        this.debug("Checking for arm64 in uname");
        const v = (0, s.execFileSync)("uname", ["-a"], {
          encoding: "utf8",
        }).includes("ARM");
        (h.info(`Checked 'uname -a': arm64=${v}`), (m = m || v));
      } catch (A) {
        h.warn(`uname shell command to check for arm64 failed: ${A}`);
      }
      m = m || process.arch === "arm64" || F;
      const S = (A) => {
        var v;
        return (
          A.url.pathname.includes("arm64") ||
          ((v = A.info.url) === null || v === void 0
            ? void 0
            : v.includes("arm64"))
        );
      };
      m && l.some(S)
        ? (l = l.filter((A) => m === S(A)))
        : (l = l.filter((A) => !S(A)));
      const E = (0, r.findFile)(l, "zip", ["pkg", "dmg"]);
      if (E == null)
        throw (0, e.newError)(
          `ZIP file not provided: ${(0, e.safeStringifyJson)(l)}`,
          "ERR_UPDATER_ZIP_FILE_NOT_FOUND",
        );
      const b = c.updateInfoAndProvider.provider,
        w = "update.zip";
      return this.executeDownload({
        fileExtension: "zip",
        fileInfo: E,
        downloadUpdateOptions: c,
        task: async (A, v) => {
          const C = i.join(this.downloadedUpdateHelper.cacheDir, w),
            g = () =>
              (0, t.pathExistsSync)(C)
                ? !c.disableDifferentialDownload
                : (h.info(
                    "Unable to locate previous update.zip for differential download (is this first install?), falling back to full download",
                  ),
                  !1);
          let D = !0;
          (g() && (D = await this.differentialDownloadInstaller(E, c, A, b, w)),
            D && (await this.httpExecutor.download(E.url, A, v)));
        },
        done: async (A) => {
          if (!c.disableDifferentialDownload)
            try {
              const v = i.join(this.downloadedUpdateHelper.cacheDir, w);
              await (0, t.copyFile)(A.downloadedFile, v);
            } catch (v) {
              this._logger.warn(
                `Unable to copy file for caching for future differential downloads: ${v.message}`,
              );
            }
          return this.updateDownloaded(E, A);
        },
      });
    }
    async updateDownloaded(c, l) {
      var h;
      const y = l.downloadedFile,
        F =
          (h = c.info.size) !== null && h !== void 0
            ? h
            : (await (0, t.stat)(y)).size,
        m = this._logger,
        S = `fileToProxy=${c.url.href}`;
      (this.closeServerIfExists(),
        this.debug(`Creating proxy server for native Squirrel.Mac (${S})`),
        (this.server = (0, a.createServer)()),
        this.debug(`Proxy server for native Squirrel.Mac is created (${S})`),
        this.server.on("close", () => {
          m.info(`Proxy server for native Squirrel.Mac is closed (${S})`);
        }));
      const E = (b) => {
        const w = b.address();
        return typeof w == "string" ? w : `http://127.0.0.1:${w?.port}`;
      };
      return await new Promise((b, w) => {
        const A = (0, u.randomBytes)(64)
            .toString("base64")
            .replace(/\//g, "_")
            .replace(/\+/g, "-"),
          v = Buffer.from(`autoupdater:${A}`, "ascii"),
          C = `/${(0, u.randomBytes)(64).toString("hex")}.zip`;
        (this.server.on("request", (g, D) => {
          const N = g.url;
          if ((m.info(`${N} requested`), N === "/")) {
            if (
              !g.headers.authorization ||
              g.headers.authorization.indexOf("Basic ") === -1
            ) {
              ((D.statusCode = 401),
                (D.statusMessage = "Invalid Authentication Credentials"),
                D.end(),
                m.warn("No authenthication info"));
              return;
            }
            const k = g.headers.authorization.split(" ")[1],
              q = Buffer.from(k, "base64").toString("ascii"),
              [U, $] = q.split(":");
            if (U !== "autoupdater" || $ !== A) {
              ((D.statusCode = 401),
                (D.statusMessage = "Invalid Authentication Credentials"),
                D.end(),
                m.warn("Invalid authenthication credentials"));
              return;
            }
            const V = Buffer.from(`{ "url": "${E(this.server)}${C}" }`);
            (D.writeHead(200, {
              "Content-Type": "application/json",
              "Content-Length": V.length,
            }),
              D.end(V));
            return;
          }
          if (!N.startsWith(C)) {
            (m.warn(`${N} requested, but not supported`),
              D.writeHead(404),
              D.end());
            return;
          }
          m.info(`${C} requested by Squirrel.Mac, pipe ${y}`);
          let P = !1;
          D.on("finish", () => {
            P || (this.nativeUpdater.removeListener("error", w), b([]));
          });
          const R = (0, o.createReadStream)(y);
          (R.on("error", (k) => {
            try {
              D.end();
            } catch (q) {
              m.warn(`cannot end response: ${q}`);
            }
            ((P = !0),
              this.nativeUpdater.removeListener("error", w),
              w(new Error(`Cannot pipe "${y}": ${k}`)));
          }),
            D.writeHead(200, {
              "Content-Type": "application/zip",
              "Content-Length": F,
            }),
            R.pipe(D));
        }),
          this.debug(
            `Proxy server for native Squirrel.Mac is starting to listen (${S})`,
          ),
          this.server.listen(0, "127.0.0.1", () => {
            (this.debug(
              `Proxy server for native Squirrel.Mac is listening (address=${E(this.server)}, ${S})`,
            ),
              this.nativeUpdater.setFeedURL({
                url: E(this.server),
                headers: {
                  "Cache-Control": "no-cache",
                  Authorization: `Basic ${v.toString("base64")}`,
                },
              }),
              this.dispatchUpdateDownloaded(l),
              this.autoInstallOnAppQuit
                ? (this.nativeUpdater.once("error", w),
                  this.nativeUpdater.checkForUpdates())
                : b([]));
          }));
      });
    }
    handleUpdateDownloaded() {
      (this.autoRunAppAfterInstall
        ? this.nativeUpdater.quitAndInstall()
        : this.app.quit(),
        this.closeServerIfExists());
    }
    quitAndInstall() {
      this.squirrelDownloadedUpdate
        ? this.handleUpdateDownloaded()
        : (this.nativeUpdater.on("update-downloaded", () =>
            this.handleUpdateDownloaded(),
          ),
          this.autoInstallOnAppQuit || this.nativeUpdater.checkForUpdates());
    }
  };
  return ((Ln.MacUpdater = f), Ln);
}
var Bn = {},
  Li = {},
  $f;
function T2() {
  if ($f) return Li;
  (($f = 1),
    Object.defineProperty(Li, "__esModule", { value: !0 }),
    (Li.verifySignature = a));
  const e = rt(),
    t = qo,
    o = Ke,
    i = G;
  function a(u, f, d) {
    return new Promise((c, l) => {
      const h = f.replace(/'/g, "''");
      (d.info(`Verifying signature ${h}`),
        (0, t.execFile)(
          'set "PSModulePath=" & chcp 65001 >NUL & powershell.exe',
          [
            "-NoProfile",
            "-NonInteractive",
            "-InputFormat",
            "None",
            "-Command",
            `"Get-AuthenticodeSignature -LiteralPath '${h}' | ConvertTo-Json -Compress"`,
          ],
          { shell: !0, timeout: 20 * 1e3 },
          (y, F, m) => {
            var S;
            try {
              if (y != null || m) {
                (r(d, y, m, l), c(null));
                return;
              }
              const E = n(F);
              if (E.Status === 0) {
                try {
                  const v = i.normalize(E.Path),
                    C = i.normalize(f);
                  if (
                    (d.info(`LiteralPath: ${v}. Update Path: ${C}`), v !== C)
                  ) {
                    (r(
                      d,
                      new Error(`LiteralPath of ${v} is different than ${C}`),
                      m,
                      l,
                    ),
                      c(null));
                    return;
                  }
                } catch (v) {
                  d.warn(
                    `Unable to verify LiteralPath of update asset due to missing data.Path. Skipping this step of validation. Message: ${(S = v.message) !== null && S !== void 0 ? S : v.stack}`,
                  );
                }
                const w = (0, e.parseDn)(E.SignerCertificate.Subject);
                let A = !1;
                for (const v of u) {
                  const C = (0, e.parseDn)(v);
                  if (
                    (C.size
                      ? (A = Array.from(C.keys()).every(
                          (D) => C.get(D) === w.get(D),
                        ))
                      : v === w.get("CN") &&
                        (d.warn(
                          `Signature validated using only CN ${v}. Please add your full Distinguished Name (DN) to publisherNames configuration`,
                        ),
                        (A = !0)),
                    A)
                  ) {
                    c(null);
                    return;
                  }
                }
              }
              const b =
                `publisherNames: ${u.join(" | ")}, raw info: ` +
                JSON.stringify(E, (w, A) => (w === "RawData" ? void 0 : A), 2);
              (d.warn(
                `Sign verification failed, installer signed with incorrect certificate: ${b}`,
              ),
                c(b));
            } catch (E) {
              (r(d, E, null, l), c(null));
              return;
            }
          },
        ));
    });
  }
  function n(u) {
    const f = JSON.parse(u);
    (delete f.PrivateKey, delete f.IsOSBinary, delete f.SignatureType);
    const d = f.SignerCertificate;
    return (
      d != null &&
        (delete d.Archived,
        delete d.Extensions,
        delete d.Handle,
        delete d.HasPrivateKey,
        delete d.SubjectName),
      f
    );
  }
  function r(u, f, d, c) {
    if (s()) {
      u.warn(
        `Cannot execute Get-AuthenticodeSignature: ${f || d}. Ignoring signature validation due to unsupported powershell version. Please upgrade to powershell 3 or higher.`,
      );
      return;
    }
    try {
      (0, t.execFileSync)(
        "powershell.exe",
        ["-NoProfile", "-NonInteractive", "-Command", "ConvertTo-Json test"],
        { timeout: 10 * 1e3 },
      );
    } catch (l) {
      u.warn(
        `Cannot execute ConvertTo-Json: ${l.message}. Ignoring signature validation due to unsupported powershell version. Please upgrade to powershell 3 or higher.`,
      );
      return;
    }
    (f != null && c(f),
      d &&
        c(
          new Error(
            `Cannot execute Get-AuthenticodeSignature, stderr: ${d}. Failing signature validation due to unknown stderr.`,
          ),
        ));
  }
  function s() {
    const u = o.release();
    return u.startsWith("6.") && !u.startsWith("6.3");
  }
  return Li;
}
var jf;
function Wf() {
  if (jf) return Bn;
  ((jf = 1),
    Object.defineProperty(Bn, "__esModule", { value: !0 }),
    (Bn.NsisUpdater = void 0));
  const e = rt(),
    t = G,
    o = un(),
    i = Np(),
    a = kr(),
    n = bt(),
    r = Dr(),
    s = T2(),
    u = Mt;
  let f = class extends o.BaseUpdater {
    constructor(c, l) {
      (super(c, l),
        (this._verifyUpdateCodeSignature = (h, y) =>
          (0, s.verifySignature)(h, y, this._logger)));
    }
    get verifyUpdateCodeSignature() {
      return this._verifyUpdateCodeSignature;
    }
    set verifyUpdateCodeSignature(c) {
      c && (this._verifyUpdateCodeSignature = c);
    }
    doDownloadUpdate(c) {
      const l = c.updateInfoAndProvider.provider,
        h = (0, n.findFile)(
          l.resolveFiles(c.updateInfoAndProvider.info),
          "exe",
        );
      return this.executeDownload({
        fileExtension: "exe",
        downloadUpdateOptions: c,
        fileInfo: h,
        task: async (y, F, m, S) => {
          const E = h.packageInfo,
            b = E != null && m != null;
          if (b && c.disableWebInstaller)
            throw (0, e.newError)(
              `Unable to download new version ${c.updateInfoAndProvider.info.version}. Web Installers are disabled`,
              "ERR_UPDATER_WEB_INSTALLER_DISABLED",
            );
          (!b &&
            !c.disableWebInstaller &&
            this._logger.warn(
              "disableWebInstaller is set to false, you should set it to true if you do not plan on using a web installer. This will default to true in a future version.",
            ),
            (b ||
              c.disableDifferentialDownload ||
              (await this.differentialDownloadInstaller(
                h,
                c,
                y,
                l,
                e.CURRENT_APP_INSTALLER_FILE_NAME,
              ))) &&
              (await this.httpExecutor.download(h.url, y, F)));
          const w = await this.verifySignature(y);
          if (w != null)
            throw (
              await S(),
              (0, e.newError)(
                `New version ${c.updateInfoAndProvider.info.version} is not signed by the application owner: ${w}`,
                "ERR_UPDATER_INVALID_SIGNATURE",
              )
            );
          if (b && (await this.differentialDownloadWebPackage(c, E, m, l)))
            try {
              await this.httpExecutor.download(new u.URL(E.path), m, {
                headers: c.requestHeaders,
                cancellationToken: c.cancellationToken,
                sha512: E.sha512,
              });
            } catch (A) {
              try {
                await (0, r.unlink)(m);
              } catch {}
              throw A;
            }
        },
      });
    }
    async verifySignature(c) {
      let l;
      try {
        if (((l = (await this.configOnDisk.value).publisherName), l == null))
          return null;
      } catch (h) {
        if (h.code === "ENOENT") return null;
        throw h;
      }
      return await this._verifyUpdateCodeSignature(
        Array.isArray(l) ? l : [l],
        c,
      );
    }
    doInstall(c) {
      const l = this.installerPath;
      if (l == null)
        return (
          this.dispatchError(
            new Error("No valid update available, can't quit and install"),
          ),
          !1
        );
      const h = ["--updated"];
      (c.isSilent && h.push("/S"),
        c.isForceRunAfter && h.push("--force-run"),
        this.installDirectory && h.push(`/D=${this.installDirectory}`));
      const y =
        this.downloadedUpdateHelper == null
          ? null
          : this.downloadedUpdateHelper.packageFile;
      y != null && h.push(`--package-file=${y}`);
      const F = () => {
        this.spawnLog(
          t.join(process.resourcesPath, "elevate.exe"),
          [l].concat(h),
        ).catch((m) => this.dispatchError(m));
      };
      return c.isAdminRightsRequired
        ? (this._logger.info(
            "isAdminRightsRequired is set to true, run installer using elevate.exe",
          ),
          F(),
          !0)
        : (this.spawnLog(l, h).catch((m) => {
            const S = m.code;
            (this._logger.info(
              `Cannot run installer: error code: ${S}, error message: "${m.message}", will be executed again using elevate if EACCES, and will try to use electron.shell.openItem if ENOENT`,
            ),
              S === "UNKNOWN" || S === "EACCES"
                ? F()
                : S === "ENOENT"
                  ? Or.shell.openPath(l).catch((E) => this.dispatchError(E))
                  : this.dispatchError(m));
          }),
          !0);
    }
    async differentialDownloadWebPackage(c, l, h, y) {
      if (l.blockMapSize == null) return !0;
      try {
        const F = {
          newUrl: new u.URL(l.path),
          oldFile: t.join(
            this.downloadedUpdateHelper.cacheDir,
            e.CURRENT_APP_PACKAGE_FILE_NAME,
          ),
          logger: this._logger,
          newFile: h,
          requestHeaders: this.requestHeaders,
          isUseMultipleRangeRequest: y.isUseMultipleRangeRequest,
          cancellationToken: c.cancellationToken,
        };
        (this.listenerCount(a.DOWNLOAD_PROGRESS) > 0 &&
          (F.onProgress = (m) => this.emit(a.DOWNLOAD_PROGRESS, m)),
          await new i.FileWithEmbeddedBlockMapDifferentialDownloader(
            l,
            this.httpExecutor,
            F,
          ).download());
      } catch (F) {
        return (
          this._logger.error(
            `Cannot download differentially, fallback to full download: ${F.stack || F}`,
          ),
          process.platform === "win32"
        );
      }
      return !1;
    }
  };
  return ((Bn.NsisUpdater = f), Bn);
}
var Hf;
function x2() {
  return (
    Hf ||
      ((Hf = 1),
      (function (e) {
        var t =
            (Cr && Cr.__createBinding) ||
            (Object.create
              ? function (m, S, E, b) {
                  b === void 0 && (b = E);
                  var w = Object.getOwnPropertyDescriptor(S, E);
                  ((!w ||
                    ("get" in w
                      ? !S.__esModule
                      : w.writable || w.configurable)) &&
                    (w = {
                      enumerable: !0,
                      get: function () {
                        return S[E];
                      },
                    }),
                    Object.defineProperty(m, b, w));
                }
              : function (m, S, E, b) {
                  (b === void 0 && (b = E), (m[b] = S[E]));
                }),
          o =
            (Cr && Cr.__exportStar) ||
            function (m, S) {
              for (var E in m)
                E !== "default" &&
                  !Object.prototype.hasOwnProperty.call(S, E) &&
                  t(S, m, E);
            };
        (Object.defineProperty(e, "__esModule", { value: !0 }),
          (e.NsisUpdater =
            e.MacUpdater =
            e.RpmUpdater =
            e.PacmanUpdater =
            e.DebUpdater =
            e.AppImageUpdater =
            e.Provider =
            e.NoOpLogger =
            e.AppUpdater =
            e.BaseUpdater =
              void 0));
        const i = Dr(),
          a = G;
        var n = un();
        Object.defineProperty(e, "BaseUpdater", {
          enumerable: !0,
          get: function () {
            return n.BaseUpdater;
          },
        });
        var r = fu();
        (Object.defineProperty(e, "AppUpdater", {
          enumerable: !0,
          get: function () {
            return r.AppUpdater;
          },
        }),
          Object.defineProperty(e, "NoOpLogger", {
            enumerable: !0,
            get: function () {
              return r.NoOpLogger;
            },
          }));
        var s = bt();
        Object.defineProperty(e, "Provider", {
          enumerable: !0,
          get: function () {
            return s.Provider;
          },
        });
        var u = Of();
        Object.defineProperty(e, "AppImageUpdater", {
          enumerable: !0,
          get: function () {
            return u.AppImageUpdater;
          },
        });
        var f = Rf();
        Object.defineProperty(e, "DebUpdater", {
          enumerable: !0,
          get: function () {
            return f.DebUpdater;
          },
        });
        var d = Bf();
        Object.defineProperty(e, "PacmanUpdater", {
          enumerable: !0,
          get: function () {
            return d.PacmanUpdater;
          },
        });
        var c = Mf();
        Object.defineProperty(e, "RpmUpdater", {
          enumerable: !0,
          get: function () {
            return c.RpmUpdater;
          },
        });
        var l = qf();
        Object.defineProperty(e, "MacUpdater", {
          enumerable: !0,
          get: function () {
            return l.MacUpdater;
          },
        });
        var h = Wf();
        (Object.defineProperty(e, "NsisUpdater", {
          enumerable: !0,
          get: function () {
            return h.NsisUpdater;
          },
        }),
          o(kr(), e));
        let y;
        function F() {
          if (process.platform === "win32") y = new (Wf().NsisUpdater)();
          else if (process.platform === "darwin") y = new (qf().MacUpdater)();
          else {
            y = new (Of().AppImageUpdater)();
            try {
              const m = a.join(process.resourcesPath, "package-type");
              if (!(0, i.existsSync)(m)) return y;
              console.info(
                "Checking for beta autoupdate feature for deb/rpm distributions",
              );
              const S = (0, i.readFileSync)(m).toString().trim();
              switch ((console.info("Found package-type:", S), S)) {
                case "deb":
                  y = new (Rf().DebUpdater)();
                  break;
                case "rpm":
                  y = new (Mf().RpmUpdater)();
                  break;
                case "pacman":
                  y = new (Bf().PacmanUpdater)();
                  break;
                default:
                  break;
              }
            } catch (m) {
              console.warn(
                "Unable to detect 'package-type' for autoUpdater (beta rpm/deb support). If you'd like to expand support, please consider contributing to electron-builder",
                m.message,
              );
            }
          }
          return y;
        }
        Object.defineProperty(e, "autoUpdater", {
          enumerable: !0,
          get: () => y || F(),
        });
      })(Cr)),
    Cr
  );
}
var Zn = x2();
function N2(e) {
  return km.conf.auto_update_disabled ?? e === "staging";
}
const I2 = Mo(qh),
  Gf = 3,
  Ip = G.join(ye.getPath("userData"), "ship-it-defer-count.json");
async function O2() {
  try {
    const e = await Te.readFile(Ip, "utf-8"),
      t = JSON.parse(e).count;
    return typeof t == "number" && t >= 0 ? t : 0;
  } catch {
    return 0;
  }
}
async function Vf(e) {
  try {
    await Te.writeFile(Ip, JSON.stringify({ count: e }));
  } catch (t) {
    logger.warn("[Updates] [Startup] Failed to persist ShipIt defer count:", t);
  }
}
const du = G.join(
  Ke.homedir(),
  `Library/Caches/${dr}.ShipIt/ShipItState.plist`,
);
async function Zr() {
  const e = await Te.readFile(du, "utf-8");
  return JSON.parse(e);
}
async function P2() {
  try {
    return await Zr();
  } catch {
    return null;
  }
}
async function R2(e) {
  try {
    return (await Te.access(ni(e)), !0);
  } catch {
    return !1;
  }
}
async function L2() {
  try {
    const { stdout: e } = await I2("pgrep", ["-fa", "ShipIt"], {
        timeout: 1500,
      }),
      t = `${dr}.ShipIt`;
    return e
      .split(
        `
`,
      )
      .some((o) => o.includes(t));
  } catch {
    return !1;
  }
}
async function B2() {
  const e = await P2();
  return !e?.launchAfterInstallation ||
    !e.updateBundleURL ||
    !(await R2(e.updateBundleURL))
    ? !1
    : L2();
}
async function k2() {
  if (!Ne) return !1;
  if (!(await B2())) return (Vf(0), !1);
  const t = await O2();
  return t >= Gf
    ? (logger.warn(
        `[Updates] [Startup] ShipIt has been mid-install across ${t} consecutive launches for label "${dr}.ShipIt"; proceeding with normal launch (likely wedged install)`,
      ),
      !1)
    : (await Vf(t + 1),
      logger.warn(
        `[Updates] [Startup] Deferring to in-progress ShipIt install for "${dr}.ShipIt" (consecutive defer ${t + 1}/${Gf}); exiting so ShipIt can finish and relaunch us`,
      ),
      !0);
}
async function M2() {
  try {
    const e = await Jh("/");
    return { freeDiskSpaceMB: Math.round(e / (1024 * 1024)) };
  } catch (e) {
    return {
      freeDiskSpaceMB: void 0,
      diskInfoError: `Failed to retrieve disk info: ${e?.message}`,
    };
  }
}
async function U2(e) {
  if (!Ne) {
    Sentry.captureException(e);
    return;
  }
  try {
    const t = await Zr();
    let o = [],
      i;
    try {
      ((i = ni(t.updateBundleURL)), (o = await Te.readdir(i)));
    } catch (n) {
      o = [`<error reading updateBundlePath: ${n?.message}>`];
    }
    const a = await M2();
    Sentry.captureException(e, {
      tags: { module: "autoUpdater", mac_update_failure: "true" },
      extra: {
        shipItState: {
          ...t,
          updateBundleURL: Kr(t.updateBundleURL),
          targetBundleURL: Kr(t.targetBundleURL),
        },
        updateBundlePath: i && Kr(i),
        updateBundleContents: o,
        diskInfo: a,
      },
    });
  } catch (t) {
    (Sentry.captureException(e),
      Sentry.captureException(t, {
        tags: { module: "autoUpdater", mac_shipit_read_failed: "true" },
        extra: {
          cause: "Failed to inspect ShipIt state while handling updater error",
        },
      }));
  }
}
const q2 = Ne && ye.runningUnderARM64Translation ? "arm64" : process.arch,
  zf = 200,
  Go = Ne && sg,
  $s = { isQuittingForUpdate: !1 },
  zr = Go ? Ys : Zn.autoUpdater,
  Op = { "x-device-id": n0 };
Go ||
  ((Zn.autoUpdater.requestHeaders = Op),
  (Zn.autoUpdater.logger = {
    info: (...e) => logger.log("[electron-updater]", ...e),
    warn: (...e) => logger.warn("[electron-updater]", ...e),
    error: (...e) => logger.error("[electron-updater]", ...e),
    debug: (...e) => logger.log("[electron-updater] [debug]", ...e),
  }));
function $2(e) {
  Go
    ? Ys.setFeedURL({ url: e, headers: Op })
    : ((Zn.autoUpdater.allowDowngrade = !!(
        ug ||
        (process.env.BEEPER_ALWAYS_UPDATE ?? !1)
      )),
      Zn.autoUpdater.setFeedURL({ provider: "generic", url: e }));
}
function j2() {
  zr.removeAllListeners("error")
    .removeAllListeners("checking-for-update")
    .removeAllListeners("update-available")
    .removeAllListeners("update-not-available")
    .removeAllListeners("update-downloaded")
    .removeAllListeners("download-progress");
}
async function W2() {
  const e = await Zr(),
    t = ni(e.updateBundleURL);
  t && (await tp.restoreChangedAppIcon(t));
}
const Xf = 300 * 1e3;
function Pp(e) {
  return !!e.startsWith("net::");
}
function H2(e) {
  return e
    ? e === "net::ERR_INTERNET_DISCONNECTED"
      ? "Offline. Try again after connecting to Internet."
      : Pp(e)
        ? `Network issue (${e}). Please try again.`
        : null
    : "";
}
const G2 = (e) =>
  e
    .map((t) =>
      /["\s]/.test(t) && !t.includes("'")
        ? "'" + t.replace(/(['\\])/g, "\\$1") + "'"
        : /["'\s]/.test(t)
          ? '"' + t.replace(/(["\\$`!])/g, "\\$1") + '"'
          : t.replace(/([A-Za-z]:)?([#!"$&'()*,:;<=>?@[\\\]^`{|}])/g, "$1\\$2"),
    )
    .join(" ");
async function V2(e) {
  try {
    await Te.access(e);
  } catch (t) {
    if (!t || t.code === "ENOENT") return !1;
    if (t.code === "EACCES") return !0;
    throw t;
  }
}
const Rp = G.dirname(du),
  z2 = G.join(Jn, "beepertexts-updater", "pending"),
  js = G.join(ye.getPath("userData"), "update-recovery-state.json"),
  X2 = 2,
  Y2 = 3,
  hu = Mo(qh);
async function K2() {
  try {
    return JSON.parse(await Te.readFile(js, "utf-8"));
  } catch {
    return null;
  }
}
async function ms(e) {
  try {
    e
      ? await Te.writeFile(js, JSON.stringify(e))
      : await Te.rm(js, { force: !0 });
  } catch (t) {
    logger.warn(
      "[Updates] [recovery] could not persist recovery state:",
      t instanceof Error ? t.message : String(t),
    );
  }
}
async function J2() {
  logger.warn(
    "[Updates] [recovery] purging wedged update state (ShipIt cache + pending download + launchd job)",
  );
  let e = !0;
  return (
    await Te.rm(Rp, { recursive: !0, force: !0 }).catch((t) => {
      ((e = !1),
        logger.error(
          "[Updates] [recovery] could not remove ShipIt dir (check ownership):",
          t instanceof Error ? t.message : String(t),
        ));
    }),
    await Te.rm(z2, { recursive: !0, force: !0 }).catch((t) =>
      logger.warn(
        "[Updates] [recovery] could not remove pending download dir:",
        t instanceof Error ? t.message : String(t),
      ),
    ),
    await hu("launchctl", ["remove", `${dr}.ShipIt`]).catch(() => {}),
    e
  );
}
const Lp = () => `gui/${process.getuid()}/${dr}.ShipIt`;
async function Q2() {
  const e = G.join(Rp, "ShipIt_stderr.log");
  let t = null,
    o = null;
  try {
    const [a, n] = await Promise.all([Te.stat(e), Te.readFile(e, "utf-8")]);
    ((t = a.mtime.toISOString()), (o = n.slice(-500)));
  } catch {}
  let i;
  try {
    const { stdout: a } = await hu("launchctl", ["print", Lp()], {
      timeout: 3e3,
    });
    i = /^\s*(state = .+)$/m.exec(a)?.[1] ?? "loaded (no state line)";
  } catch {
    i = "not loaded";
  }
  return { jobState: i, stderrMtime: t, stderrTail: o };
}
async function Z2(e) {
  try {
    const { response: t } = await Xe.showMessageBox({
      type: "warning",
      buttons: ["Download latest version", "Later"],
      defaultId: 0,
      cancelId: 1,
      message: "Beeper couldn’t finish updating automatically.",
      detail: `The update to v${e} didn’t apply after several attempts. Restarting your Mac usually fixes this; otherwise download and reinstall the latest version to keep getting updates.`,
    });
    t === 0 && (await Dt.openExternal("https://www.beeper.com/download"));
  } catch (t) {
    logger.error(
      "[Updates] [recovery] could not prompt manual reinstall:",
      t instanceof Error ? t.message : String(t),
    );
  }
}
async function ey() {
  if (!Ne) return;
  let e;
  try {
    e = await Zr();
  } catch (d) {
    d?.code === "ENOENT"
      ? logger.log(
          "[Updates] [Startup] No ShipItState.plist found (no pending update)",
        )
      : logger.error(
          "[Updates] [Startup] Failed to read ShipItState.plist:",
          d instanceof Error ? d.message : String(d),
        );
    return;
  }
  const t = e.updateBundleURL ? ni(e.updateBundleURL) : null;
  let o = !1;
  if (t)
    try {
      (await Te.access(t), (o = !0));
    } catch (d) {
      d?.code !== "ENOENT" &&
        logger.error(
          "[Updates] [Startup] Staged bundle access failed:",
          d instanceof Error ? d.message : String(d),
        );
    }
  if (
    (logger.log(
      `[Updates] [Startup] ShipItState: launchAfterInstallation=${e.launchAfterInstallation}, bundleExists=${o}, target=${e.targetBundleURL}`,
    ),
    !o || !t)
  )
    return;
  let i = null;
  try {
    const d = G.join(t, "Contents/Info.plist"),
      c = await Te.readFile(d, "utf-8");
    i =
      /<key>CFBundleShortVersionString<\/key>\s*<string>([^<]+)<\/string>/.exec(
        c,
      )?.[1] ?? null;
  } catch (d) {
    logger.error(
      "[Updates] Could not read staged app content: ",
      d instanceof Error ? d.message : String(d),
    );
    return;
  }
  if (!i) return;
  if (
    (logger.log(
      `[Updates] [Startup] Staged update version: ${i}, running version: ${Ve.version}`,
    ),
    i === Ve.version)
  ) {
    await ms(null);
    return;
  }
  logger.warn(
    `[Updates] [Startup] WARNING: Staged update v${i} was never applied (still running v${Ve.version})`,
  );
  const a = await K2(),
    n = !!a && a.version === i,
    r = (n ? a.failedRelaunches : 0) + 1;
  let s = n ? a.purged : !1,
    u = n ? a.prompted : !1;
  logger.warn(
    `[Updates] [recovery] staged v${i} unapplied across ${r} launch(es) (purged=${s}, prompted=${u})`,
  );
  const f = await Q2();
  if (
    (logger.warn(
      `[Updates] [recovery] ShipIt diagnostics: job ${f.jobState}; stderr ${f.stderrMtime ? `mtime=${f.stderrMtime}, tail=${JSON.stringify(f.stderrTail)}` : "never created — launchd did not spawn ShipIt"}`,
    ),
    !s && r >= X2 && (s = await J2()),
    r >= Y2 && !u)
  ) {
    (Sentry.captureMessage(
      `Auto-update wedged: staged v${i} unapplied after ${r} launches (purged=${s}, running v${Ve.version})`,
      {
        extra: {
          shipItJobState: f.jobState,
          shipItStderrMtime: f.stderrMtime,
          shipItStderrTail: f.stderrTail,
        },
      },
    ),
      kt("autoupdater-wedged", `Couldn’t finish updating to v${i}.`),
      (u = !0),
      await ms({ version: i, failedRelaunches: r, purged: s, prompted: u }),
      await Z2(i));
    return;
  }
  await ms({ version: i, failedRelaunches: r, purged: s, prompted: u });
}
class wt {
  constructor(t) {
    ((this.mainWindow = t),
      (this.checkForUpdatesDisabled = !1),
      (this.updateDownloaded = !1),
      (this.onError = (o) => {
        ((this.checkForUpdatesDisabled = !1),
          logger.error("[Updates] error occurred:", o));
        const i = Pp(o.message);
        if (i && this.lastCheckWasBackground) {
          ((this.networkRetryPending = !0),
            this.rs.setUpdateProgress(),
            kt("autoupdater-network", o.message),
            this.scheduleNextAutomaticCheck(Xf));
          return;
        }
        const a = H2(o.message),
          n = a
            ? `Update failed: ${a}`
            : "Beeper could not be updated automatically.";
        (this.rs.setUpdateProgress(n, !i), kt("autoupdater", n), U2(o));
      }),
      (this.lastCheckWasBackground = !1),
      (this.networkRetryPending = !1),
      (this.downloadedOutdatedCount = 0),
      (this.onUpdateDownloaded = async (o) => {
        this.checkForUpdatesDisabled = !1;
        const { releaseChannel: i } = await this.rs.getAutoUpdateConfig(),
          a = await wt.fetchUpdateFeedJSON(i);
        if (
          !process.env.BEEPER_ALWAYS_UPDATE &&
          o?.version &&
          a?.version &&
          a?.version !== o.version &&
          (Sentry.captureMessage(
            `Update downloaded: ${o.version}, expected: ${a.version}`,
          ),
          logger.warn(
            "[Updates] [onUpdateDownloaded] downloaded",
            o?.version,
            "instead of latest:",
            a.version,
          ),
          ++this.downloadedOutdatedCount < 3)
        )
          return this.runCheck(!0, this.lastCheckWasBackground);
        ((this.updateDownloaded = !0),
          this.rs.setUpdateDownloaded(o?.version),
          this.rs.setUpdateProgress("Relaunch app to finish updating"),
          logger.log(
            "[Updates] [onUpdateDownloaded] update to",
            o?.version,
            "is now prompting for user relaunch",
          ));
      }),
      (this.quitAndUpdate = async () => {
        if ((logger.log("[Updates] [quitAndUpdate] called"), Ne)) {
          await W2().catch((o) => logger.error(o));
          try {
            const o = await Zr();
            if (
              (logger.log(
                "[Updates] [quitAndUpdate] ShipItState:",
                JSON.stringify({
                  launchAfterInstallation: o.launchAfterInstallation,
                  useUpdateBundleName: o.useUpdateBundleName,
                  bundleIdentifier: o.bundleIdentifier,
                }),
              ),
              o.updateBundleURL)
            ) {
              const i = ni(o.updateBundleURL);
              try {
                (await Te.access(i),
                  logger.log(
                    "[Updates] [quitAndUpdate] Update bundle exists:",
                    G.basename(i),
                  ));
              } catch {
                logger.warn(
                  "[Updates] [quitAndUpdate] Update bundle NOT found:",
                  G.basename(i),
                );
              }
            }
          } catch {
            logger.warn(
              "[Updates] [quitAndUpdate] Could not read ShipItState.plist",
            );
          }
          try {
            const o = await Zr();
            ((o.launchAfterInstallation = !0),
              await Te.writeFile(du, JSON.stringify(o)));
          } catch (o) {
            logger.warn(
              "[Updates] [quitAndUpdate] Failed to set launchAfterInstallation:",
              o,
            );
          }
        }
        (($s.isQuittingForUpdate = !0),
          ye.releaseSingleInstanceLock(),
          logger.log(
            "[Updates] [quitAndUpdate] released single-instance lock for spawned successor",
          ));
        try {
          Ne ? Ys.quitAndInstall() : zr.quitAndInstall();
        } catch (o) {
          $s.isQuittingForUpdate = !1;
          const i = ye.requestSingleInstanceLock({ version: Ve.version });
          (logger.error(
            "[Updates] [quitAndUpdate] quitAndInstall threw; lock re-acquired:",
            i,
            "error:",
            o,
          ),
            i ||
              logger.error(
                "[Updates] [quitAndUpdate] failed to re-acquire single-instance lock after quitAndInstall failure — app may now be uncoordinated with new launches",
              ));
          return;
        }
        if (Ne)
          try {
            (await hu("launchctl", ["kickstart", Lp()], { timeout: 3e3 }),
              logger.log("[Updates] [quitAndUpdate] kickstarted ShipIt job"));
          } catch (o) {
            logger.warn(
              "[Updates] [quitAndUpdate] ShipIt kickstart failed (job not submitted, or already running):",
              o instanceof Error ? o.message : String(o),
            );
          }
        (setTimeout(() => {
          (logger.log(
            "[Updates] [quitAndUpdate] short timeout, calling app.quit()",
          ),
            ye.quit());
        }, 5e3),
          setTimeout(() => {
            (logger.log(
              "[Updates] [quitAndUpdate] long timeout, force exiting",
            ),
              Qr());
          }, 1e4));
      }),
      (this.window = this.mainWindow.window),
      (this.rs = this.mainWindow.rs));
  }
  async ensureFreeDiskSpace() {
    if ((await Jh(Jn)) / 1e6 > zf) return !0;
    this.rs.setLowDiskSpace(!0);
    const i = `free disk space is too low. Try clearing up some files and ensure ${zf} MB of free space.`;
    this.rs.setUpdateProgress(`Update failed: ${i}`);
    const a = `Update failed because ${i}`;
    (kt("autoupdater-low-disk-space", a),
      await Xe.showMessageBox({ message: a }));
  }
  static async getDirsRequiringOwnership() {
    const t = [];
    for (const o of [G.join(Jn, dr + ".ShipIt")])
      (await V2(o)) && (logger.log("[Updates] needs ownership", o), t.push(o));
    return t;
  }
  static async ensurePerms() {
    if (!Ne) return;
    const t = await wt.getDirsRequiringOwnership();
    if (t.length < 1) return;
    const o = G2(["chown", "-R", i0].concat(t));
    if ((logger.log("sudo", o), wt.sudoPromptedOnce))
      return logger.warn("sudo already prompted once");
    ((wt.sudoPromptedOnce = !0), await Kh(o, { name: tt.APP_NAME, icns: ru }));
    const i = await wt.getDirsRequiringOwnership();
    if (i.length !== 0) {
      const a = `requires ownership, prev=${t.length} new=${i.length}`;
      (logger.log(a), Sentry.captureMessage(a));
    }
  }
  static getQueryParams(t) {
    return `bundleID=com.automattic.beeper.desktop&version=${Ve.version}&platform=${process.platform}&arch=${q2}&channel=${t}`;
  }
  static get updateFeedEndpoint() {
    return `${Mm(Kn).url}/desktop/update-feed`;
  }
  static async fetchUpdateFeedJSON(t) {
    const o = `${this.updateFeedEndpoint}.json?${wt.getQueryParams(t)}`,
      i = await Rh("GET", o),
      a = i.body ? JSON.parse(i.body) : null;
    return (
      logger.log(
        `[AutoUpdater] fetchUpdateFeedJSON URL=${o} response=${JSON.stringify(a)}`,
      ),
      a
    );
  }
  scheduleNextAutomaticCheck(t) {
    (clearTimeout(this.checkUpdateTimeout),
      (this.checkUpdateTimeout = setTimeout(() => this.runCheck(!0, !0), t)));
  }
  static setFeedURL(t) {
    const i = `${Go ? `${this.updateFeedEndpoint}.json` : this.updateFeedEndpoint}?${wt.getQueryParams(t)}`;
    $2(i);
  }
  async checkForUpdates(t = !1) {
    return this.runCheck(t, !1);
  }
  async runCheck(t, o) {
    if (Ve.version.includes("wip") && !process.env.BEEPER_ALWAYS_UPDATE) {
      logger.log(
        "[Updates] NOT checking for updates as we are on a wip version",
      );
      return;
    }
    logger.log(
      `[Updates] [checkForUpdates] checking for updates (automatic? ${t}, background? ${o})`,
    );
    const { releaseChannel: i, appUpdateCheckInterval: a } =
      await this.rs.getAutoUpdateConfig();
    try {
      if (!(await this.ensureFreeDiskSpace())) {
        logger.warn(
          "[Updates] [checkForUpdates] not downloading updates, out of disk space",
        );
        return;
      }
      if ((wt.setFeedURL(i), this.checkForUpdatesDisabled)) return;
      if (
        ((this.checkForUpdatesDisabled = !0),
        (this.lastCheckWasBackground = o),
        (this.networkRetryPending = !1),
        !t)
      ) {
        if (this.updateDownloaded) {
          (logger.log(
            "[Updates] [checkForUpdates] manual checkForUpdates triggered, going to quitAndUpdate",
          ),
            this.quitAndUpdate());
          return;
        }
        _h("update-check", { version: Ve.version });
      }
      (await wt.ensurePerms().catch((n) => {
        (logger.error("AutoUpdater.ensurePerms", n),
          Sentry.captureException(n));
      }),
        zr.removeAllListeners("update-not-available"),
        zr.on("update-not-available", () => {
          if (
            (logger.log("[Updates] update-not-available"),
            (this.checkForUpdatesDisabled = !1),
            this.rs.setUpdateProgress(),
            !t)
          )
            return Xe.showMessageBox(yt ? void 0 : this.window, {
              message: `You're on the latest version v${Ve.version}!`,
            });
        }),
        await zr.checkForUpdates());
    } catch (n) {
      this.onError(n);
    } finally {
      t && this.scheduleNextAutomaticCheck(this.networkRetryPending ? Xf : a);
    }
  }
  autoInstallUpdate() {
    const { window: t } = this.mainWindow;
    (t.isMinimized() || !t.isVisible()) && this.quitAndUpdate();
  }
  register() {
    (j2(),
      zr
        .on("error", this.onError)
        .on("checking-for-update", () => {
          (logger.log("[Updates] [Event] checking-for-update"),
            this.rs.setUpdateProgress("Checking for updates..."));
        })
        .on("update-available", () => {
          (logger.log("[Updates] [Event] update-available"),
            (this.downloadStartTime = Date.now()),
            this.rs.setUpdateProgress("Downloading update..."));
        })
        .on("update-downloaded", (t) => {
          const o = ~~((Date.now() - this.downloadStartTime) / 1e3);
          (Fm("Update", "Download time", o),
            logger.log(
              "[Updates] [Event] update-downloaded:",
              t,
              "in",
              o,
              "seconds",
            ),
            this.onUpdateDownloaded(t));
        })
        .on("download-progress", (t) => {
          (logger.log("[Updates] [Event] download-progress", t),
            this.rs.setUpdateProgress(
              `Downloading update: ${t.percent.toFixed(2)}%`,
            ));
        }),
      N2(Kn) || setTimeout(() => this.runCheck(!0, !0), 6e4));
  }
}
function ty(e) {
  return e.startsWith("thread-info-") ||
    e.startsWith("modal-") ||
    e.startsWith("devtools-") ||
    e === "external" ||
    e.startsWith("event-explorer-") ||
    e.startsWith("room-explorer-") ||
    e === "data-explorer" ||
    e === "custom-event" ||
    e.startsWith("prefs-reauth-account-")
    ? !1
    : !!(
        e.startsWith("thread-") ||
        e === "prefs" ||
        e.startsWith("prefs-new-account-") ||
        e.startsWith("prefs-manage-account-") ||
        e.startsWith("prefs-")
      );
}
function ry(e) {
  return ty(e)
    ? e.startsWith("thread-") && !e.startsWith("thread-info-")
      ? { windowId: e, type: "thread", threadId: e.slice(7) }
      : e === "prefs"
        ? { windowId: e, type: "prefs" }
        : e.startsWith("prefs-new-account-")
          ? {
              windowId: e,
              type: "prefs-new-account",
              platformName: e.slice(18),
            }
          : e.startsWith("prefs-manage-account-")
            ? {
                windowId: e,
                type: "prefs-manage-account",
                accountId: e.slice(21),
              }
            : e.startsWith("prefs-")
              ? { windowId: e, type: "prefs-subview", subView: e.slice(6) }
              : null
    : null;
}
class ny {
  constructor() {
    this.store = new nu({ configName: "subwindow-state", cwd: lt });
  }
  save(t) {
    this.store.set("openSubwindows", t);
  }
  load() {
    return this.store.get("openSubwindows", []);
  }
  clear() {
    this.store.delete("openSubwindows");
  }
  saveFromWindowIds(t) {
    const o = [...t],
      i = [];
    for (const a of o) {
      const n = ry(a);
      n && i.push(n);
    }
    i.length > 0 ? this.save(i) : this.clear();
  }
}
const Wn = new ny();
function iy() {
  const e = G.join(tu, "../..");
  return Mt.pathToFileURL(G.join(e, "build/renderer/confetti/confetti.html"))
    .href;
}
async function oy() {
  const e = ur.getCursorScreenPoint(),
    t = ur.getDisplayNearestPoint(e),
    { x: o, y: i, width: a, height: n } = t.bounds,
    r = new He({
      x: o,
      y: i,
      width: a,
      height: n,
      frame: !1,
      transparent: !0,
      alwaysOnTop: !0,
      focusable: !1,
      hasShadow: !1,
      resizable: !1,
      fullscreenable: !1,
      skipTaskbar: !0,
      webPreferences: { contextIsolation: !0, nodeIntegration: !1 },
    });
  (r.setIgnoreMouseEvents(!0), r.setAlwaysOnTop(!0, "screen-saver"));
  const s = await iy();
  r.loadURL(s);
}
const Yf = (e) => (Ne ? "command+" : "ctrl+") + e,
  Kf = (e) => e.replaceAll("mod+", Ne ? "command+" : "ctrl+"),
  Bi = (e) => e.replaceAll("control", "ctrl");
function ay(e) {
  return typeof e == "string";
}
function sy(e) {
  return (
    typeof e == "object" && e != null && "keys" in e && Array.isArray(e.keys)
  );
}
function Jf(e, t, o = It) {
  const i = o.keybindings?.[e];
  return i
    ? ay(i)
      ? Bi(i === "default" ? t : Kf(i.toLowerCase()))
      : sy(i)
        ? i.disabled
          ? "disabled"
          : Bi(Kf(i.keys.join(", ")))
        : Bi(t)
    : Bi(t);
}
const Qf = {
    MINIMIZE_TO_TRAY: { key: Jf("MINIMIZE_TO_TRAY", Yf("alt+q")) },
    QUIT_APP: { key: Jf("QUIT_APP", Yf("q")) },
  },
  uy = ko(import.meta.dirname, "./chunks/trayIcon-BK3-sDyz.png"),
  ly = ko(import.meta.dirname, "./chunks/trayUnreadIcon-_8P0Jy4t.png");
let zt, Ws;
const Bp = Ne ? G.join(_g, "iconTemplate.png") : uy,
  cy = ly;
function fy(e = 0) {
  !Ne &&
    zt &&
    !zt.isDestroyed() &&
    (zt.setImage(Ks.createFromPath(e > 0 ? cy : Bp)),
    zt.setToolTip(`${tt.APP_NAME}${e > 0 ? ` [${e}]` : ""}`));
}
function kp() {
  (Ws?.(),
    (Ws = void 0),
    zt && !zt.isDestroyed() && zt.destroy(),
    (zt = void 0));
}
function Mp(e, t) {
  kp();
  const o = new Em(Ks.createFromPath(Bp));
  zt = o;
  let i;
  function a() {
    o.isDestroyed() || o.popUpContextMenu(i);
  }
  async function n(l) {
    if (!e) {
      await t();
      return;
    }
    (Ne && l.ctrlKey) || (e.isVisible && e.window.isFocused()) ? a() : vD();
  }
  const r = {
      label: "Minimize to " + tt.TRAY_NAME,
      accelerator: Qf.MINIMIZE_TO_TRAY.key,
      click: () => {
        bu();
      },
    },
    s = {
      label: "Show Window",
      click: () => {
        e?.show();
      },
    },
    u = {
      label: `Quit ${tt.APP_NAME}`,
      accelerator: Qf.QUIT_APP.key,
      click() {
        ye.quit();
      },
    },
    f = lr.buildFromTemplate([r, u]),
    d = lr.buildFromTemplate([cr ? s : null, u].filter((l) => !!l));
  function c() {
    o.isDestroyed() ||
      ((i = e.window.isMinimized() || !e.window.isVisible() ? d : f),
      Ne || o.setContextMenu(i));
  }
  (o.setToolTip(tt.APP_NAME),
    o.on("click", n),
    o.on("double-click", n),
    o.on("right-click", a),
    c(),
    e.window.on("minimize", c),
    e.window.on("hide", c),
    e.window.on("restore", c),
    e.window.on("show", c),
    (Ws = () => {
      (e.window.removeListener("minimize", c),
        e.window.removeListener("hide", c),
        e.window.removeListener("restore", c),
        e.window.removeListener("show", c));
    }));
}
function dy(e, t, o) {
  o ? Mp(e, t) : kp();
}
const Rr = "google",
  ln = "apple",
  hy = [ln, Rr],
  py = { [ln]: "Apple", [Rr]: "Google" },
  Vo = { [ln]: xg, [Rr]: Tg },
  Dy = (e) => !!Vo[e],
  my = "oidc-",
  gy = (e) => `${my}${e}`;
new Map(hy.map((e) => [gy(e), e]));
const ar = {
    NOT_CONFIGURED: "sign-in-not-configured",
    INVALID_CREDENTIALS: "sign-in-invalid-credentials",
    DECLINED: "sign-in-declined",
    TIMED_OUT: "sign-in-timed-out",
    LOOPBACK_FAILED: "sign-in-loopback-failed",
  },
  Hs = "/callback",
  wy = 300 * 1e3,
  Zf = 30 * 1e3,
  yy = 64 * 1024,
  ei = (e) => e.toString("base64url"),
  Up = (e) => {
    const t = e.split(".")[1],
      o = t ? Bh(Buffer.from(t, "base64url").toString("utf8")) : void 0;
    return o && typeof o == "object" ? o : {};
  },
  Ey = (e) => ({
    success: "You can close this window and return to Beeper.",
    declined: `Sign in with ${e} was cancelled. You can close this window and return to Beeper.`,
    failed: `Sign in with ${e} did not complete. You can close this window and try again in Beeper.`,
  }),
  ed = (e) => Um({ body: `<p class="message">${e}</p>` }),
  vy = async (e) => {
    let t;
    try {
      t = new URL(e.url ?? "", "http://127.0.0.1");
    } catch {
      return null;
    }
    if (t.pathname !== Hs) return null;
    if (e.method !== "POST") return t.searchParams;
    const o = [];
    let i = 0;
    try {
      for await (const a of e) {
        if (((i += a.length), i > yy)) return (e.destroy(), null);
        o.push(a);
      }
    } catch {
      return null;
    }
    return new URLSearchParams(Buffer.concat(o).toString("utf8"));
  };
let Nr = null;
const gs = (e) => (e instanceof Error ? e : new Error(String(e))),
  td = (e) => {
    (e.close(), e.closeAllConnections());
  },
  Gs = (e, t = 0) => {
    if (!e.listening) return;
    ((e.listening = !1), clearTimeout(e.timeout));
    const { server: o } = e;
    t ? setTimeout(() => td(o), t).unref() : td(o);
  },
  Vt = (e, t) => {
    Nr === e &&
      ((Nr = null), clearTimeout(e.timeout), Gs(e), t(), e.browser?.close());
  },
  qp = () => {
    const e = Nr;
    e && Vt(e, () => e.resolve(null));
  },
  Cy = (e, t) =>
    new Promise((o, i) => {
      if (!Dy(e.name)) {
        i(new Error(ar.NOT_CONFIGURED));
        return;
      }
      qp();
      const a = `[${e.name}-sign-in]`,
        n = Ey(py[e.name]),
        r = Vh.createServer(),
        s = {
          server: r,
          resolve: o,
          listening: !1,
          browser: t,
          timeout: setTimeout(
            () => Vt(s, () => i(new Error(ar.TIMED_OUT))),
            wy,
          ),
        };
      Nr = s;
      let u = null,
        f = null;
      const d = (l) => {
        if (!l || !u || l.get("state") !== u.state)
          return (
            l && logger.warn(a, "ignoring callback with an unexpected state"),
            null
          );
        if (f) return f;
        const h = l.get("error"),
          y = h ? null : u.accept(l);
        if (!y) {
          const F = h === u.declinedError;
          return (
            (f = ed(F ? n.declined : n.failed)),
            logger.warn(a, "callback rejected", h ?? "invalid_credential"),
            Gs(s, Zf),
            Vt(s, () => i(new Error(F ? ar.DECLINED : ar.INVALID_CREDENTIALS))),
            f
          );
        }
        return (
          (f = ed(n.success)),
          Gs(s, Zf),
          y().then(
            (F) => Vt(s, () => o(F)),
            (F) => Vt(s, () => i(gs(F))),
          ),
          f
        );
      };
      (r.on("error", (l) => {
        (logger.error(a, "loopback server error", l),
          Vt(s, () => i(u ? gs(l) : new Error(ar.LOOPBACK_FAILED))));
      }),
        r.on("request", (l, h) => {
          vy(l).then((y) => {
            const F = d(y);
            F
              ? l.method === "POST"
                ? h
                    .writeHead(303, {
                      location: `${Hs}?${new URLSearchParams({ state: u?.state ?? "" })}`,
                    })
                    .end()
                : h
                    .writeHead(200, {
                      "content-type": "text/html; charset=utf-8",
                    })
                    .end(F)
              : h.writeHead(404).end();
          });
        }));
      const c = () => {
        ((u = null),
          (s.listening = !0),
          r.listen(0, "127.0.0.1", () => {
            if (Nr !== s) return;
            const l = r.address(),
              h = l && typeof l == "object" ? l.port : 0,
              y = `http://127.0.0.1:${h}${Hs}`;
            ((u = e.begin({ port: h, uri: y })),
              logger.log(a, "waiting for callback on", y),
              Dt.openExternal(u.authorizeURL).catch((F) =>
                Vt(s, () => i(gs(F))),
              ));
          }));
      };
      if (!t || !e.beginInApp) {
        c();
        return;
      }
      ((u = e.beginInApp()),
        logger.log(a, "opening the sign-in window"),
        t.open(u.authorizeURL).then(
          (l) => {
            if (Nr !== s) return;
            if (!l) {
              (logger.log(a, "sign-in window closed without a result"),
                Vt(s, () => o(null)));
              return;
            }
            const h = URL.canParse(l) ? new URL(l).searchParams : null;
            d(h) || Vt(s, () => i(new Error(ar.INVALID_CREDENTIALS)));
          },
          (l) => {
            Nr === s &&
              (logger.warn(
                a,
                "sign-in window unavailable, using the default browser",
                l,
              ),
              c());
          },
        ));
    }),
  Ay = "https://accounts.google.com/o/oauth2/v2/auth",
  by = "https://oauth2.googleapis.com/token",
  Fy = 15 * 1e3,
  Sy = () => {
    const e = ei(Oo(32)),
      t = ei(pg("sha256").update(e).digest());
    return { verifier: e, challenge: t };
  },
  _y = async (e, t, o) => {
    const i = await Ir.post(by, {
        form: {
          client_id: Vo[Rr],
          client_secret: Ng,
          code: e,
          code_verifier: t,
          grant_type: "authorization_code",
          redirect_uri: o,
        },
        responseType: "json",
        throwHttpErrors: !1,
        timeout: Fy,
        https: { rejectUnauthorized: !0 },
      }),
      a = i.body;
    if (i.statusCode !== 200 || !a?.id_token)
      throw (
        logger.error(
          "[google-sign-in] token exchange failed",
          i.statusCode,
          a?.error,
        ),
        new Error(ar.INVALID_CREDENTIALS)
      );
    const n = Up(a.id_token);
    return {
      idToken: a.id_token,
      fullName: typeof n.name == "string" ? n.name : "",
    };
  },
  Ty = {
    name: Rr,
    begin: (e) => {
      const { verifier: t, challenge: o } = Sy(),
        i = ei(Oo(16)),
        a = new URLSearchParams({
          client_id: Vo[Rr],
          redirect_uri: e.uri,
          response_type: "code",
          scope: "openid email profile",
          code_challenge: o,
          code_challenge_method: "S256",
          state: i,
          prompt: "select_account",
        });
      return {
        state: i,
        authorizeURL: `${Ay}?${a}`,
        declinedError: "access_denied",
        accept: (n) => {
          const r = n.get("code");
          return r ? () => _y(r, t, e.uri) : null;
        },
      };
    },
  },
  xy = "https://appleid.apple.com/auth/authorize",
  Ny = (e) => {
    const t = e ? Bh(e)?.name : void 0;
    if (!t || typeof t != "object") return "";
    const { firstName: o, middleName: i, lastName: a } = t;
    return [o, i, a]
      .filter((n) => typeof n == "string" && n.length > 0)
      .join(" ");
  },
  rd = (e) => {
    const t = ei(Oo(16)),
      o = `${e}.${ei(Oo(16))}`,
      i = new URLSearchParams({
        client_id: Vo[ln],
        redirect_uri: Ig,
        response_type: "code id_token",
        response_mode: "form_post",
        scope: "name email",
        state: o,
        nonce: t,
      });
    return {
      state: o,
      authorizeURL: `${xy}?${i}`,
      declinedError: "user_cancelled_authorize",
      accept: (a) => {
        const n = a.get("id_token");
        if (!n) return null;
        if (Up(n).nonce !== t)
          return (
            logger.error("[apple-sign-in] id token nonce mismatch"),
            null
          );
        const r = Ny(a.get("user"));
        return async () => ({ idToken: n, fullName: r });
      },
    };
  },
  Iy = { name: ln, begin: (e) => rd(e.port), beginInApp: () => rd("app") },
  Oy = "beeper-sign-in",
  Py = () => {
    if (!Re?.WebAuthSession) return;
    const e = new Re.WebAuthSession();
    return { open: (t) => e.start(t, Oy), close: () => e.cancel() };
  },
  Ry = { [ln]: Iy, [Rr]: Ty };
async function Ly(e, t) {
  const o = new URL(e),
    i = await t0(o, t.directory, t.filename);
  return (
    t.dontBounceDock || ye.dock?.downloadFinished(i),
    await Lh(i),
    { savePath: i }
  );
}
const By = {
  launchBrowserWindow: ID,
  fireConfetti: oy,
  setNativeThemeSource(e) {
    vm.themeSource = e;
  },
  setTrayUnreadStatus: (e) => fy(e),
  setAppBadgeCount(e) {
    ye.badgeCount = e;
  },
  relaunchApp: Qn,
  handleBundleReplacementError: jo,
  async wipeStorageAndRelaunchForLogout() {
    try {
      E0();
    } catch (e) {
      (logger.error("logout: failed to write storage wipe marker", e),
        Sentry.captureException(e));
    }
    try {
      await Promise.race([
        fr.defaultSession.clearStorageData(),
        new Promise((e) => {
          setTimeout(e, 5e3);
        }),
      ]);
    } catch (e) {
      logger.error(
        "logout: clearStorageData failed, deferring to next boot",
        e,
      );
    }
    Qn("logout");
  },
  quitApp() {
    ye.quit();
  },
  exitApp() {
    Qr();
  },
  wasOpenedAtLogin: () =>
    Ne ? ye.getLoginItemSettings().wasOpenedAtLogin : void 0,
  isLoginItemEnabled: () => ye.getLoginItemSettings().openAtLogin,
  setLoginItemEnabled(e) {
    ye.setLoginItemSettings({ openAtLogin: e });
  },
  getMediaAccessStatus: (e) => Jr.getMediaAccessStatus(e),
  askForMediaAccess: (e) => Jr.askForMediaAccess(e),
};
function ws(e, t, o, i) {
  const { x: a, y: n, width: r, height: s } = e.getBounds(),
    { width: u, height: f } = ur.getDisplayNearestPoint({
      x: a,
      y: n,
    }).workAreaSize,
    d = Math.min(t, u),
    c = Math.min(o, f);
  e.setBounds(
    {
      x: Math.floor(Math.max(0, Math.min(u - d, a - (d - r) / 2))),
      y: Math.floor(Math.max(0, Math.min(f - c, n - (c - s) / 2))),
      width: d,
      height: c,
    },
    i,
  );
}
const ky = (e) => {
  const { window: t } = e,
    o = (s) =>
      yt
        ? Xe.showOpenDialog(s)
        : Xe.showOpenDialog(He.getFocusedWindow() ?? t, s),
    i = (s) =>
      yt
        ? Xe.showSaveDialog(s)
        : Xe.showSaveDialog(He.getFocusedWindow() ?? t, s),
    a = new tp(),
    n = new Cw(e, e.rs),
    r = new wt(e);
  return {
    ...By,
    newThreadNotification: n.newNotification.bind(n),
    showNotification: n.showNotification.bind(n),
    closeNotification: n.closeNotification.bind(n),
    closeAllNotifications: n.closeAllNotifications.bind(n),
    registerAutoUpdater: r.register.bind(r),
    checkForUpdates: r.checkForUpdates.bind(r),
    quitAndUpdate: r.quitAndUpdate,
    fetchUpdateFeedJSON: wt.fetchUpdateFeedJSON.bind(wt),
    setDockMenu(s) {
      ye.dock?.setMenu(
        lr.buildFromTemplate(
          s.flatMap((u, f) => [
            ...(f > 0 ? [{ type: "separator" }] : []),
            { label: u.title, enabled: !1 },
            ...u.chats.map(({ accountID: d, threadID: c, title: l }) => ({
              label: l,
              click: () => {
                t.isDestroyed() || (e.show(), e.rs.selectThreadByID(d, c));
              },
            })),
          ]),
        ),
      );
    },
    setAppIcon: a.setAppIcon.bind(a),
    applyAppIconOnStartup: a.applyAppIconOnStartup.bind(a),
    downloadFile: Ly,
    showOpenDialog: o,
    showSaveDialog: i,
    toggleFocusedWindowMaximize() {
      const s = He.getFocusedWindow() ?? t;
      s[s.isMaximized() ? "unmaximize" : "maximize"]();
    },
    setFocusedWindowResizable(s) {
      (He.getFocusedWindow() ?? t).setResizable(s);
    },
    setFocusedWindowMaximizable(s) {
      (He.getFocusedWindow() ?? t).setMaximizable(s);
    },
    mainWindowSetSize(s, u, f = !1) {
      ws(t, s, u, f);
    },
    setMainWindowResizable(s) {
      t.setResizable(s);
    },
    setMainWindowMaximizable(s) {
      t.setMaximizable(s);
    },
    focusedWindowSetSize(s, u, f = !1) {
      const d = He.getFocusedWindow() ?? t;
      ws(d, s, u, f);
    },
    setWindowMinSize(s, u, f) {
      const d = ft.get(s)?.window;
      if (!d) return;
      const [c, l] = d.getMinimumSize();
      d.setMinimumSize(u ?? c, f ?? l);
    },
    setWindowSize(s, u, f, d = !1) {
      const c = ft.get(s)?.window;
      c && ws(c, u, f, d);
    },
    focusedWindowMaximize() {
      (He.getFocusedWindow() ?? t).maximize();
    },
    focusedWindowMinimize() {
      (He.getFocusedWindow() ?? t).minimize();
    },
    closeFocusedWindow() {
      (He.getFocusedWindow() ?? t).close();
    },
    showMsgBox: (s) =>
      yt
        ? Xe.showMessageBox(s)
        : Xe.showMessageBox(He.getFocusedWindow() ?? t, s),
    openDevTools: () =>
      (He.getFocusedWindow() ?? t).webContents.openDevTools({ mode: "detach" }),
    crashMainProcess() {
      process.crash();
    },
    previewFile: (s, u) => (He.getFocusedWindow() ?? t).previewFile(s, u),
    previewAttachment: (s, u, f) => xw(He.getFocusedWindow() ?? t, s, u, f),
    sendActionToFirstResponder(s) {
      lr.sendActionToFirstResponder(s);
    },
    showMainWindow() {
      e.show();
    },
    hideAllWindows: bu,
    canPromptTouchID() {
      return Jr.canPromptTouchID();
    },
    setWindowOffsets: Aw,
    async promptTouchID() {
      try {
        return (await Jr.promptTouchID("unlock itself"), !0);
      } catch {
        return !1;
      }
    },
    openPath: Dt.openPath.bind(Dt),
    openExternal: Dt.openExternal.bind(Dt),
    showItemInFolder: Dt.showItemInFolder.bind(Dt),
    clipboardWriteText: or.writeText.bind(or),
    clipboardWriteRich: async (s, u) => {
      await or.write([
        new Rs({
          "text/plain": new Blob([s], { type: "text/plain" }),
          "text/html": new Blob([u], { type: "text/html" }),
        }),
      ]);
    },
    clipboardReadText: or.readText.bind(or),
    fetchWebContent: async (s) => {
      if (!s) throw new Error("URL is required");
      const u = rl.parseTweetURL(s);
      if (u) {
        const c = await rl.getClient().fetchTweet(u.username, u.tweetID);
        return c
          ? `URL: ${s}
Twitter User: ${c.user?.name} (@${c.user?.username})
Tweet: ${c.text}
`
          : `URL: ${s}`;
      }
      const f = [];
      return (
        new tl(await (await fetch(s)).text())
          .parseTags("h1", "h2", "h3", "p")
          .forEach((d) => f.push(d.join(" "))),
        tl.removeHtmlTags(
          f.join(`
`),
        )
      );
    },
    getMimeType: Mh,
    canDecodeMedia: (s) => dw(s),
    imageSizeAsync: Qg,
    isFullScreen: () => t.fullScreen,
    setWindowButtonPosition: (s) => Ne && t.setWindowButtonPosition(s),
    async copyImageToClipboard(s) {
      const u = Ks.createFromBuffer(Buffer.from(s));
      if (u.isEmpty())
        throw new Error("copyImageToClipboard: could not decode image");
      const f = u.toPNG();
      await or.write([
        new Rs({ "image/png": new Blob([f], { type: "image/png" }) }),
      ]);
    },
    getIdleState: () => st.getSystemIdleState(1),
    setWindowCloseConfirmation: (s, u) => {
      ft.get(s)?.setCloseConfirmation(u);
    },
    focusWindow: (s) => {
      const u = s ? ft.get(s)?.window : t;
      (u?.isMinimized() && u?.restore(), u?.focus());
    },
    stealFocus: () => ye.focus({ steal: !0 }),
    async startOIDCSignIn(s) {
      const u = He.getFocusedWindow() ?? t,
        f = () => {
          u.isDestroyed() ||
            (u === t ? e.show() : (u.isMinimized() && u.restore(), u.show()),
            ye.focus({ steal: !0 }));
        };
      try {
        const d = await Cy(Ry[s], Py());
        return (f(), d);
      } catch (d) {
        throw ((d instanceof Error && d.message === ar.TIMED_OUT) || f(), d);
      }
    },
    cancelOIDCSignIn: qp,
    getSavedSubwindowState: () => Wn.load(),
  };
};
var ki = {},
  ys,
  nd;
function My() {
  if (nd) return ys;
  nd = 1;
  const e = ze,
    t = G,
    o = e.lchown ? "lchown" : "chown",
    i = e.lchownSync ? "lchownSync" : "chownSync",
    a =
      e.lchown &&
      !process.version.match(/v1[1-9]+\./) &&
      !process.version.match(/v10\.[6-9]/),
    n = (S, E, b) => {
      try {
        return e[i](S, E, b);
      } catch (w) {
        if (w.code !== "ENOENT") throw w;
      }
    },
    r = (S, E, b) => {
      try {
        return e.chownSync(S, E, b);
      } catch (w) {
        if (w.code !== "ENOENT") throw w;
      }
    },
    s = a
      ? (S, E, b, w) => (A) => {
          !A || A.code !== "EISDIR" ? w(A) : e.chown(S, E, b, w);
        }
      : (S, E, b, w) => w,
    u = a
      ? (S, E, b) => {
          try {
            return n(S, E, b);
          } catch (w) {
            if (w.code !== "EISDIR") throw w;
            r(S, E, b);
          }
        }
      : (S, E, b) => n(S, E, b),
    f = process.version;
  let d = (S, E, b) => e.readdir(S, E, b),
    c = (S, E) => e.readdirSync(S, E);
  /^v4\./.test(f) && (d = (S, E, b) => e.readdir(S, b));
  const l = (S, E, b, w) => {
      e[o](
        S,
        E,
        b,
        s(S, E, b, (A) => {
          w(A && A.code !== "ENOENT" ? A : null);
        }),
      );
    },
    h = (S, E, b, w, A) => {
      if (typeof E == "string")
        return e.lstat(t.resolve(S, E), (v, C) => {
          if (v) return A(v.code !== "ENOENT" ? v : null);
          ((C.name = E), h(S, C, b, w, A));
        });
      if (E.isDirectory())
        y(t.resolve(S, E.name), b, w, (v) => {
          if (v) return A(v);
          const C = t.resolve(S, E.name);
          l(C, b, w, A);
        });
      else {
        const v = t.resolve(S, E.name);
        l(v, b, w, A);
      }
    },
    y = (S, E, b, w) => {
      d(S, { withFileTypes: !0 }, (A, v) => {
        if (A) {
          if (A.code === "ENOENT") return w();
          if (A.code !== "ENOTDIR" && A.code !== "ENOTSUP") return w(A);
        }
        if (A || !v.length) return l(S, E, b, w);
        let C = v.length,
          g = null;
        const D = (N) => {
          if (!g) {
            if (N) return w((g = N));
            if (--C === 0) return l(S, E, b, w);
          }
        };
        v.forEach((N) => h(S, N, E, b, D));
      });
    },
    F = (S, E, b, w) => {
      if (typeof E == "string")
        try {
          const A = e.lstatSync(t.resolve(S, E));
          ((A.name = E), (E = A));
        } catch (A) {
          if (A.code === "ENOENT") return;
          throw A;
        }
      (E.isDirectory() && m(t.resolve(S, E.name), b, w),
        u(t.resolve(S, E.name), b, w));
    },
    m = (S, E, b) => {
      let w;
      try {
        w = c(S, { withFileTypes: !0 });
      } catch (A) {
        if (A.code === "ENOENT") return;
        if (A.code === "ENOTDIR" || A.code === "ENOTSUP") return u(S, E, b);
        throw A;
      }
      return (w && w.length && w.forEach((A) => F(S, A, E, b)), u(S, E, b));
    };
  return ((ys = y), (y.sync = m), ys);
}
var Mi = {},
  kn = { exports: {} },
  Es,
  id;
function Uy() {
  if (id) return Es;
  id = 1;
  const { Buffer: e } = o0,
    t = Symbol.for("BufferList");
  function o(i) {
    if (!(this instanceof o)) return new o(i);
    o._init.call(this, i);
  }
  return (
    (o._init = function (a) {
      (Object.defineProperty(this, t, { value: !0 }),
        (this._bufs = []),
        (this.length = 0),
        a && this.append(a));
    }),
    (o.prototype._new = function (a) {
      return new o(a);
    }),
    (o.prototype._offset = function (a) {
      if (a === 0) return [0, 0];
      let n = 0;
      for (let r = 0; r < this._bufs.length; r++) {
        const s = n + this._bufs[r].length;
        if (a < s || r === this._bufs.length - 1) return [r, a - n];
        n = s;
      }
    }),
    (o.prototype._reverseOffset = function (i) {
      const a = i[0];
      let n = i[1];
      for (let r = 0; r < a; r++) n += this._bufs[r].length;
      return n;
    }),
    (o.prototype.get = function (a) {
      if (a > this.length || a < 0) return;
      const n = this._offset(a);
      return this._bufs[n[0]][n[1]];
    }),
    (o.prototype.slice = function (a, n) {
      return (
        typeof a == "number" && a < 0 && (a += this.length),
        typeof n == "number" && n < 0 && (n += this.length),
        this.copy(null, 0, a, n)
      );
    }),
    (o.prototype.copy = function (a, n, r, s) {
      if (
        ((typeof r != "number" || r < 0) && (r = 0),
        (typeof s != "number" || s > this.length) && (s = this.length),
        r >= this.length || s <= 0)
      )
        return a || e.alloc(0);
      const u = !!a,
        f = this._offset(r),
        d = s - r;
      let c = d,
        l = (u && n) || 0,
        h = f[1];
      if (r === 0 && s === this.length) {
        if (!u)
          return this._bufs.length === 1
            ? this._bufs[0]
            : e.concat(this._bufs, this.length);
        for (let y = 0; y < this._bufs.length; y++)
          (this._bufs[y].copy(a, l), (l += this._bufs[y].length));
        return a;
      }
      if (c <= this._bufs[f[0]].length - h)
        return u
          ? this._bufs[f[0]].copy(a, n, h, h + c)
          : this._bufs[f[0]].slice(h, h + c);
      u || (a = e.allocUnsafe(d));
      for (let y = f[0]; y < this._bufs.length; y++) {
        const F = this._bufs[y].length - h;
        if (c > F) (this._bufs[y].copy(a, l, h), (l += F));
        else {
          (this._bufs[y].copy(a, l, h, h + c), (l += F));
          break;
        }
        ((c -= F), h && (h = 0));
      }
      return a.length > l ? a.slice(0, l) : a;
    }),
    (o.prototype.shallowSlice = function (a, n) {
      if (
        ((a = a || 0),
        (n = typeof n != "number" ? this.length : n),
        a < 0 && (a += this.length),
        n < 0 && (n += this.length),
        a === n)
      )
        return this._new();
      const r = this._offset(a),
        s = this._offset(n),
        u = this._bufs.slice(r[0], s[0] + 1);
      return (
        s[1] === 0
          ? u.pop()
          : (u[u.length - 1] = u[u.length - 1].slice(0, s[1])),
        r[1] !== 0 && (u[0] = u[0].slice(r[1])),
        this._new(u)
      );
    }),
    (o.prototype.toString = function (a, n, r) {
      return this.slice(n, r).toString(a);
    }),
    (o.prototype.consume = function (a) {
      if (((a = Math.trunc(a)), Number.isNaN(a) || a <= 0)) return this;
      for (; this._bufs.length;)
        if (a >= this._bufs[0].length)
          ((a -= this._bufs[0].length),
            (this.length -= this._bufs[0].length),
            this._bufs.shift());
        else {
          ((this._bufs[0] = this._bufs[0].slice(a)), (this.length -= a));
          break;
        }
      return this;
    }),
    (o.prototype.duplicate = function () {
      const a = this._new();
      for (let n = 0; n < this._bufs.length; n++) a.append(this._bufs[n]);
      return a;
    }),
    (o.prototype.append = function (a) {
      if (a == null) return this;
      if (a.buffer)
        this._appendBuffer(e.from(a.buffer, a.byteOffset, a.byteLength));
      else if (Array.isArray(a))
        for (let n = 0; n < a.length; n++) this.append(a[n]);
      else if (this._isBufferList(a))
        for (let n = 0; n < a._bufs.length; n++) this.append(a._bufs[n]);
      else
        (typeof a == "number" && (a = a.toString()),
          this._appendBuffer(e.from(a)));
      return this;
    }),
    (o.prototype._appendBuffer = function (a) {
      (this._bufs.push(a), (this.length += a.length));
    }),
    (o.prototype.indexOf = function (i, a, n) {
      if (
        (n === void 0 && typeof a == "string" && ((n = a), (a = void 0)),
        typeof i == "function" || Array.isArray(i))
      )
        throw new TypeError(
          'The "value" argument must be one of type string, Buffer, BufferList, or Uint8Array.',
        );
      if (
        (typeof i == "number"
          ? (i = e.from([i]))
          : typeof i == "string"
            ? (i = e.from(i, n))
            : this._isBufferList(i)
              ? (i = i.slice())
              : Array.isArray(i.buffer)
                ? (i = e.from(i.buffer, i.byteOffset, i.byteLength))
                : e.isBuffer(i) || (i = e.from(i)),
        (a = Number(a || 0)),
        isNaN(a) && (a = 0),
        a < 0 && (a = this.length + a),
        a < 0 && (a = 0),
        i.length === 0)
      )
        return a > this.length ? this.length : a;
      const r = this._offset(a);
      let s = r[0],
        u = r[1];
      for (; s < this._bufs.length; s++) {
        const f = this._bufs[s];
        for (; u < f.length;)
          if (f.length - u >= i.length) {
            const c = f.indexOf(i, u);
            if (c !== -1) return this._reverseOffset([s, c]);
            u = f.length - i.length + 1;
          } else {
            const c = this._reverseOffset([s, u]);
            if (this._match(c, i)) return c;
            u++;
          }
        u = 0;
      }
      return -1;
    }),
    (o.prototype._match = function (i, a) {
      if (this.length - i < a.length) return !1;
      for (let n = 0; n < a.length; n++)
        if (this.get(i + n) !== a[n]) return !1;
      return !0;
    }),
    (function () {
      const i = {
        readDoubleBE: 8,
        readDoubleLE: 8,
        readFloatBE: 4,
        readFloatLE: 4,
        readInt32BE: 4,
        readInt32LE: 4,
        readUInt32BE: 4,
        readUInt32LE: 4,
        readInt16BE: 2,
        readInt16LE: 2,
        readUInt16BE: 2,
        readUInt16LE: 2,
        readInt8: 1,
        readUInt8: 1,
        readIntBE: null,
        readIntLE: null,
        readUIntBE: null,
        readUIntLE: null,
      };
      for (const a in i)
        (function (n) {
          i[n] === null
            ? (o.prototype[n] = function (r, s) {
                return this.slice(r, r + s)[n](0, s);
              })
            : (o.prototype[n] = function (r = 0) {
                return this.slice(r, r + i[n])[n](0);
              });
        })(a);
    })(),
    (o.prototype._isBufferList = function (a) {
      return a instanceof o || o.isBufferList(a);
    }),
    (o.isBufferList = function (a) {
      return a != null && a[t];
    }),
    (Es = o),
    Es
  );
}
var od;
function qy() {
  if (od) return kn.exports;
  od = 1;
  const e = Yn().Duplex,
    t = zh(),
    o = Uy();
  function i(a) {
    if (!(this instanceof i)) return new i(a);
    if (typeof a == "function") {
      this._callback = a;
      const n = function (s) {
        this._callback && (this._callback(s), (this._callback = null));
      }.bind(this);
      (this.on("pipe", function (s) {
        s.on("error", n);
      }),
        this.on("unpipe", function (s) {
          s.removeListener("error", n);
        }),
        (a = null));
    }
    (o._init.call(this, a), e.call(this));
  }
  return (
    t(i, e),
    Object.assign(i.prototype, o.prototype),
    (i.prototype._new = function (n) {
      return new i(n);
    }),
    (i.prototype._write = function (n, r, s) {
      (this._appendBuffer(n), typeof s == "function" && s());
    }),
    (i.prototype._read = function (n) {
      if (!this.length) return this.push(null);
      ((n = Math.min(n, this.length)),
        this.push(this.slice(0, n)),
        this.consume(n));
    }),
    (i.prototype.end = function (n) {
      (e.prototype.end.call(this, n),
        this._callback &&
          (this._callback(null, this.slice()), (this._callback = null)));
    }),
    (i.prototype._destroy = function (n, r) {
      ((this._bufs.length = 0), (this.length = 0), r(n));
    }),
    (i.prototype._isBufferList = function (n) {
      return n instanceof i || n instanceof o || i.isBufferList(n);
    }),
    (i.isBufferList = o.isBufferList),
    (kn.exports = i),
    (kn.exports.BufferListStream = i),
    (kn.exports.BufferList = o),
    kn.exports
  );
}
var _r = {},
  ad;
function $p() {
  if (ad) return _r;
  ad = 1;
  var e = Buffer.alloc,
    t = "0000000000000000000",
    o = "7777777777777777777",
    i = 48,
    a = Buffer.from("ustar\0", "binary"),
    n = Buffer.from("00", "binary"),
    r = Buffer.from("ustar ", "binary"),
    s = Buffer.from(" \0", "binary"),
    u = parseInt("7777", 8),
    f = 257,
    d = 263,
    c = function (A, v, C) {
      return typeof A != "number"
        ? C
        : ((A = ~~A), A >= v ? v : A >= 0 || ((A += v), A >= 0) ? A : 0);
    },
    l = function (A) {
      switch (A) {
        case 0:
          return "file";
        case 1:
          return "link";
        case 2:
          return "symlink";
        case 3:
          return "character-device";
        case 4:
          return "block-device";
        case 5:
          return "directory";
        case 6:
          return "fifo";
        case 7:
          return "contiguous-file";
        case 72:
          return "pax-header";
        case 55:
          return "pax-global-header";
        case 27:
          return "gnu-long-link-path";
        case 28:
        case 30:
          return "gnu-long-path";
      }
      return null;
    },
    h = function (A) {
      switch (A) {
        case "file":
          return 0;
        case "link":
          return 1;
        case "symlink":
          return 2;
        case "character-device":
          return 3;
        case "block-device":
          return 4;
        case "directory":
          return 5;
        case "fifo":
          return 6;
        case "contiguous-file":
          return 7;
        case "pax-header":
          return 72;
      }
      return 0;
    },
    y = function (A, v, C, g) {
      for (; C < g; C++) if (A[C] === v) return C;
      return g;
    },
    F = function (A) {
      for (var v = 256, C = 0; C < 148; C++) v += A[C];
      for (var g = 156; g < 512; g++) v += A[g];
      return v;
    },
    m = function (A, v) {
      return (
        (A = A.toString(8)),
        A.length > v ? o.slice(0, v) + " " : t.slice(0, v - A.length) + A + " "
      );
    };
  function S(A) {
    var v;
    if (A[0] === 128) v = !0;
    else if (A[0] === 255) v = !1;
    else return null;
    for (var C = [], g = A.length - 1; g > 0; g--) {
      var D = A[g];
      v ? C.push(D) : C.push(255 - D);
    }
    var N = 0,
      P = C.length;
    for (g = 0; g < P; g++) N += C[g] * Math.pow(256, g);
    return v ? N : -1 * N;
  }
  var E = function (A, v, C) {
      if (((A = A.slice(v, v + C)), (v = 0), A[v] & 128)) return S(A);
      for (; v < A.length && A[v] === 32;) v++;
      for (
        var g = c(y(A, 32, v, A.length), A.length, A.length);
        v < g && A[v] === 0;
      )
        v++;
      return g === v ? 0 : parseInt(A.slice(v, g).toString(), 8);
    },
    b = function (A, v, C, g) {
      return A.slice(v, y(A, 0, v, v + C)).toString(g);
    },
    w = function (A) {
      var v = Buffer.byteLength(A),
        C = Math.floor(Math.log(v) / Math.log(10)) + 1;
      return (v + C >= Math.pow(10, C) && C++, v + C + A);
    };
  return (
    (_r.decodeLongPath = function (A, v) {
      return b(A, 0, A.length, v);
    }),
    (_r.encodePax = function (A) {
      var v = "";
      (A.name &&
        (v += w(
          " path=" +
            A.name +
            `
`,
        )),
        A.linkname &&
          (v += w(
            " linkpath=" +
              A.linkname +
              `
`,
          )));
      var C = A.pax;
      if (C)
        for (var g in C)
          v += w(
            " " +
              g +
              "=" +
              C[g] +
              `
`,
          );
      return Buffer.from(v);
    }),
    (_r.decodePax = function (A) {
      for (var v = {}; A.length;) {
        for (var C = 0; C < A.length && A[C] !== 32;) C++;
        var g = parseInt(A.slice(0, C).toString(), 10);
        if (!g) return v;
        var D = A.slice(C + 1, g - 1).toString(),
          N = D.indexOf("=");
        if (N === -1) return v;
        ((v[D.slice(0, N)] = D.slice(N + 1)), (A = A.slice(g)));
      }
      return v;
    }),
    (_r.encode = function (A) {
      var v = e(512),
        C = A.name,
        g = "";
      if (
        (A.typeflag === 5 && C[C.length - 1] !== "/" && (C += "/"),
        Buffer.byteLength(C) !== C.length)
      )
        return null;
      for (; Buffer.byteLength(C) > 100;) {
        var D = C.indexOf("/");
        if (D === -1) return null;
        ((g += g ? "/" + C.slice(0, D) : C.slice(0, D)), (C = C.slice(D + 1)));
      }
      return Buffer.byteLength(C) > 100 ||
        Buffer.byteLength(g) > 155 ||
        (A.linkname && Buffer.byteLength(A.linkname) > 100)
        ? null
        : (v.write(C),
          v.write(m(A.mode & u, 6), 100),
          v.write(m(A.uid, 6), 108),
          v.write(m(A.gid, 6), 116),
          v.write(m(A.size, 11), 124),
          v.write(m((A.mtime.getTime() / 1e3) | 0, 11), 136),
          (v[156] = i + h(A.type)),
          A.linkname && v.write(A.linkname, 157),
          a.copy(v, f),
          n.copy(v, d),
          A.uname && v.write(A.uname, 265),
          A.gname && v.write(A.gname, 297),
          v.write(m(A.devmajor || 0, 6), 329),
          v.write(m(A.devminor || 0, 6), 337),
          g && v.write(g, 345),
          v.write(m(F(v), 6), 148),
          v);
    }),
    (_r.decode = function (A, v, C) {
      var g = A[156] === 0 ? 0 : A[156] - i,
        D = b(A, 0, 100, v),
        N = E(A, 100, 8),
        P = E(A, 108, 8),
        R = E(A, 116, 8),
        k = E(A, 124, 12),
        q = E(A, 136, 12),
        U = l(g),
        $ = A[157] === 0 ? null : b(A, 157, 100, v),
        V = b(A, 265, 32),
        re = b(A, 297, 32),
        X = E(A, 329, 8),
        fe = E(A, 337, 8),
        Y = F(A);
      if (Y === 256) return null;
      if (Y !== E(A, 148, 8))
        throw new Error(
          "Invalid tar header. Maybe the tar is corrupted or it needs to be gunzipped?",
        );
      if (a.compare(A, f, f + 6) === 0)
        A[345] && (D = b(A, 345, 155, v) + "/" + D);
      else if (!(
        r.compare(A, f, f + 6) === 0 && s.compare(A, d, d + 2) === 0
      )) {
        if (!C) throw new Error("Invalid tar header: unknown format.");
      }
      return (
        g === 0 && D && D[D.length - 1] === "/" && (g = 5),
        {
          name: D,
          mode: N,
          uid: P,
          gid: R,
          size: k,
          mtime: new Date(1e3 * q),
          type: U,
          linkname: $,
          uname: V,
          gname: re,
          devmajor: X,
          devminor: fe,
        }
      );
    }),
    _r
  );
}
var vs, sd;
function $y() {
  if (sd) return vs;
  sd = 1;
  var e = on,
    t = qy(),
    o = $p(),
    i = Yn().Writable,
    a = Yn().PassThrough,
    n = function () {},
    r = function (c) {
      return ((c &= 511), c && 512 - c);
    },
    s = function (c, l) {
      var h = new f(c, l);
      return (h.end(), h);
    },
    u = function (c, l) {
      return (
        l.path && (c.name = l.path),
        l.linkpath && (c.linkname = l.linkpath),
        l.size && (c.size = parseInt(l.size, 10)),
        (c.pax = l),
        c
      );
    },
    f = function (c, l) {
      ((this._parent = c),
        (this.offset = l),
        a.call(this, { autoDestroy: !1 }));
    };
  (e.inherits(f, a),
    (f.prototype.destroy = function (c) {
      this._parent.destroy(c);
    }));
  var d = function (c) {
    if (!(this instanceof d)) return new d(c);
    (i.call(this, c),
      (c = c || {}),
      (this._offset = 0),
      (this._buffer = t()),
      (this._missing = 0),
      (this._partial = !1),
      (this._onparse = n),
      (this._header = null),
      (this._stream = null),
      (this._overflow = null),
      (this._cb = null),
      (this._locked = !1),
      (this._destroyed = !1),
      (this._pax = null),
      (this._paxGlobal = null),
      (this._gnuLongPath = null),
      (this._gnuLongLinkPath = null));
    var l = this,
      h = l._buffer,
      y = function () {
        l._continue();
      },
      F = function (C) {
        if (((l._locked = !1), C)) return l.destroy(C);
        l._stream || y();
      },
      m = function () {
        l._stream = null;
        var C = r(l._header.size);
        (C ? l._parse(C, S) : l._parse(512, v), l._locked || y());
      },
      S = function () {
        (l._buffer.consume(r(l._header.size)), l._parse(512, v), y());
      },
      E = function () {
        var C = l._header.size;
        ((l._paxGlobal = o.decodePax(h.slice(0, C))), h.consume(C), m());
      },
      b = function () {
        var C = l._header.size;
        ((l._pax = o.decodePax(h.slice(0, C))),
          l._paxGlobal && (l._pax = Object.assign({}, l._paxGlobal, l._pax)),
          h.consume(C),
          m());
      },
      w = function () {
        var C = l._header.size;
        ((this._gnuLongPath = o.decodeLongPath(
          h.slice(0, C),
          c.filenameEncoding,
        )),
          h.consume(C),
          m());
      },
      A = function () {
        var C = l._header.size;
        ((this._gnuLongLinkPath = o.decodeLongPath(
          h.slice(0, C),
          c.filenameEncoding,
        )),
          h.consume(C),
          m());
      },
      v = function () {
        var C = l._offset,
          g;
        try {
          g = l._header = o.decode(
            h.slice(0, 512),
            c.filenameEncoding,
            c.allowUnknownFormat,
          );
        } catch (D) {
          l.emit("error", D);
        }
        if ((h.consume(512), !g)) {
          (l._parse(512, v), y());
          return;
        }
        if (g.type === "gnu-long-path") {
          (l._parse(g.size, w), y());
          return;
        }
        if (g.type === "gnu-long-link-path") {
          (l._parse(g.size, A), y());
          return;
        }
        if (g.type === "pax-global-header") {
          (l._parse(g.size, E), y());
          return;
        }
        if (g.type === "pax-header") {
          (l._parse(g.size, b), y());
          return;
        }
        if (
          (l._gnuLongPath &&
            ((g.name = l._gnuLongPath), (l._gnuLongPath = null)),
          l._gnuLongLinkPath &&
            ((g.linkname = l._gnuLongLinkPath), (l._gnuLongLinkPath = null)),
          l._pax && ((l._header = g = u(g, l._pax)), (l._pax = null)),
          (l._locked = !0),
          !g.size || g.type === "directory")
        ) {
          (l._parse(512, v), l.emit("entry", g, s(l, C), F));
          return;
        }
        ((l._stream = new f(l, C)),
          l.emit("entry", g, l._stream, F),
          l._parse(g.size, m),
          y());
      };
    ((this._onheader = v), this._parse(512, v));
  };
  return (
    e.inherits(d, i),
    (d.prototype.destroy = function (c) {
      this._destroyed ||
        ((this._destroyed = !0),
        c && this.emit("error", c),
        this.emit("close"),
        this._stream && this._stream.emit("close"));
    }),
    (d.prototype._parse = function (c, l) {
      this._destroyed ||
        ((this._offset += c),
        (this._missing = c),
        l === this._onheader && (this._partial = !1),
        (this._onparse = l));
    }),
    (d.prototype._continue = function () {
      if (!this._destroyed) {
        var c = this._cb;
        ((this._cb = n),
          this._overflow ? this._write(this._overflow, void 0, c) : c());
      }
    }),
    (d.prototype._write = function (c, l, h) {
      if (!this._destroyed) {
        var y = this._stream,
          F = this._buffer,
          m = this._missing;
        if ((c.length && (this._partial = !0), c.length < m))
          return (
            (this._missing -= c.length),
            (this._overflow = null),
            y ? y.write(c, h) : (F.append(c), h())
          );
        ((this._cb = h), (this._missing = 0));
        var S = null;
        (c.length > m && ((S = c.slice(m)), (c = c.slice(0, m))),
          y ? y.end(c) : F.append(c),
          (this._overflow = S),
          this._onparse());
      }
    }),
    (d.prototype._final = function (c) {
      if (this._partial)
        return this.destroy(new Error("Unexpected end of data"));
      c();
    }),
    (vs = d),
    vs
  );
}
var Cs, ud;
function jy() {
  return (ud || ((ud = 1), (Cs = ze.constants || jh)), Cs);
}
var As, ld;
function Wy() {
  if (ld) return As;
  ld = 1;
  var e = jy(),
    t = Zg(),
    o = zh(),
    i = Buffer.alloc,
    a = Yn().Readable,
    n = Yn().Writable,
    r = Hh.StringDecoder,
    s = $p(),
    u = parseInt("755", 8),
    f = parseInt("644", 8),
    d = i(1024),
    c = function () {},
    l = function (E, b) {
      ((b &= 511), b && E.push(d.slice(0, 512 - b)));
    };
  function h(E) {
    switch (E & e.S_IFMT) {
      case e.S_IFBLK:
        return "block-device";
      case e.S_IFCHR:
        return "character-device";
      case e.S_IFDIR:
        return "directory";
      case e.S_IFIFO:
        return "fifo";
      case e.S_IFLNK:
        return "symlink";
    }
    return "file";
  }
  var y = function (E) {
    (n.call(this), (this.written = 0), (this._to = E), (this._destroyed = !1));
  };
  (o(y, n),
    (y.prototype._write = function (E, b, w) {
      if (((this.written += E.length), this._to.push(E))) return w();
      this._to._drain = w;
    }),
    (y.prototype.destroy = function () {
      this._destroyed || ((this._destroyed = !0), this.emit("close"));
    }));
  var F = function () {
    (n.call(this),
      (this.linkname = ""),
      (this._decoder = new r("utf-8")),
      (this._destroyed = !1));
  };
  (o(F, n),
    (F.prototype._write = function (E, b, w) {
      ((this.linkname += this._decoder.write(E)), w());
    }),
    (F.prototype.destroy = function () {
      this._destroyed || ((this._destroyed = !0), this.emit("close"));
    }));
  var m = function () {
    (n.call(this), (this._destroyed = !1));
  };
  (o(m, n),
    (m.prototype._write = function (E, b, w) {
      w(new Error("No body allowed for this entry"));
    }),
    (m.prototype.destroy = function () {
      this._destroyed || ((this._destroyed = !0), this.emit("close"));
    }));
  var S = function (E) {
    if (!(this instanceof S)) return new S(E);
    (a.call(this, E),
      (this._drain = c),
      (this._finalized = !1),
      (this._finalizing = !1),
      (this._destroyed = !1),
      (this._stream = null));
  };
  return (
    o(S, a),
    (S.prototype.entry = function (E, b, w) {
      if (this._stream) throw new Error("already piping an entry");
      if (!(this._finalized || this._destroyed)) {
        (typeof b == "function" && ((w = b), (b = null)), w || (w = c));
        var A = this;
        if (
          ((!E.size || E.type === "symlink") && (E.size = 0),
          E.type || (E.type = h(E.mode)),
          E.mode || (E.mode = E.type === "directory" ? u : f),
          E.uid || (E.uid = 0),
          E.gid || (E.gid = 0),
          E.mtime || (E.mtime = new Date()),
          typeof b == "string" && (b = Buffer.from(b)),
          Buffer.isBuffer(b))
        ) {
          ((E.size = b.length), this._encode(E));
          var v = this.push(b);
          return (
            l(A, E.size),
            v ? process.nextTick(w) : (this._drain = w),
            new m()
          );
        }
        if (E.type === "symlink" && !E.linkname) {
          var C = new F();
          return (
            t(C, function (D) {
              if (D) return (A.destroy(), w(D));
              ((E.linkname = C.linkname), A._encode(E), w());
            }),
            C
          );
        }
        if (
          (this._encode(E), E.type !== "file" && E.type !== "contiguous-file")
        )
          return (process.nextTick(w), new m());
        var g = new y(this);
        return (
          (this._stream = g),
          t(g, function (D) {
            if (((A._stream = null), D)) return (A.destroy(), w(D));
            if (g.written !== E.size)
              return (A.destroy(), w(new Error("size mismatch")));
            (l(A, E.size), A._finalizing && A.finalize(), w());
          }),
          g
        );
      }
    }),
    (S.prototype.finalize = function () {
      if (this._stream) {
        this._finalizing = !0;
        return;
      }
      this._finalized ||
        ((this._finalized = !0), this.push(d), this.push(null));
    }),
    (S.prototype.destroy = function (E) {
      this._destroyed ||
        ((this._destroyed = !0),
        E && this.emit("error", E),
        this.emit("close"),
        this._stream && this._stream.destroy && this._stream.destroy());
    }),
    (S.prototype._encode = function (E) {
      if (!E.pax) {
        var b = s.encode(E);
        if (b) {
          this.push(b);
          return;
        }
      }
      this._encodePax(E);
    }),
    (S.prototype._encodePax = function (E) {
      var b = s.encodePax({ name: E.name, linkname: E.linkname, pax: E.pax }),
        w = {
          name: "PaxHeader",
          mode: E.mode,
          uid: E.uid,
          gid: E.gid,
          size: b.length,
          mtime: E.mtime,
          type: "pax-header",
          linkname: E.linkname && "PaxHeader",
          uname: E.uname,
          gname: E.gname,
          devmajor: E.devmajor,
          devminor: E.devminor,
        };
      (this.push(s.encode(w)),
        this.push(b),
        l(this, b.length),
        (w.size = E.size),
        (w.type = E.type),
        this.push(s.encode(w)));
    }),
    (S.prototype._read = function (E) {
      var b = this._drain;
      ((this._drain = c), b());
    }),
    (As = S),
    As
  );
}
var cd;
function Hy() {
  return (cd || ((cd = 1), (Mi.extract = $y()), (Mi.pack = Wy())), Mi);
}
var bs, fd;
function Gy() {
  if (fd) return bs;
  fd = 1;
  var e = G,
    t = ze,
    o = parseInt("0777", 8);
  bs = i.mkdirp = i.mkdirP = i;
  function i(a, n, r, s) {
    typeof n == "function"
      ? ((r = n), (n = {}))
      : (!n || typeof n != "object") && (n = { mode: n });
    var u = n.mode,
      f = n.fs || t;
    (u === void 0 && (u = o & ~process.umask()), s || (s = null));
    var d = r || function () {};
    ((a = e.resolve(a)),
      f.mkdir(a, u, function (c) {
        if (!c) return ((s = s || a), d(null, s));
        c.code === "ENOENT"
          ? i(e.dirname(a), n, function (l, h) {
              l ? d(l, h) : i(a, n, d, h);
            })
          : f.stat(a, function (l, h) {
              l || !h.isDirectory() ? d(c, s) : d(null, s);
            });
      }));
  }
  return (
    (i.sync = function a(n, r, s) {
      (!r || typeof r != "object") && (r = { mode: r });
      var u = r.mode,
        f = r.fs || t;
      (u === void 0 && (u = o & ~process.umask()),
        s || (s = null),
        (n = e.resolve(n)));
      try {
        (f.mkdirSync(n, u), (s = s || n));
      } catch (c) {
        switch (c.code) {
          case "ENOENT":
            ((s = a(e.dirname(n), r, s)), a(n, r, s));
            break;
          default:
            var d;
            try {
              d = f.statSync(n);
            } catch {
              throw c;
            }
            if (!d.isDirectory()) throw c;
            break;
        }
      }
      return s;
    }),
    bs
  );
}
var dd;
function Vy() {
  if (dd) return ki;
  dd = 1;
  var e = My(),
    t = Hy(),
    o = e0(),
    i = Gy(),
    a = ze,
    n = G,
    r = Ke,
    s = r.platform() === "win32",
    u = function () {},
    f = function (E) {
      return E;
    },
    d = s
      ? function (E) {
          return E.replace(/\\/g, "/").replace(/[:?<>|]/g, "_");
        }
      : f,
    c = function (E, b, w, A, v, C) {
      var g = v || ["."];
      return function (N) {
        if (!g.length) return N();
        var P = g.shift(),
          R = n.join(w, P);
        b.call(E, R, function (k, q) {
          if (k) return N(k);
          if (!q.isDirectory()) return N(null, P, q);
          E.readdir(R, function (U, $) {
            if (U) return N(U);
            C && $.sort();
            for (var V = 0; V < $.length; V++)
              A(n.join(w, P, $[V])) || g.push(n.join(P, $[V]));
            N(null, P, q);
          });
        });
      };
    },
    l = function (E, b) {
      return function (w) {
        w.name = w.name.split("/").slice(b).join("/");
        var A = w.linkname;
        return (
          A &&
            (w.type === "link" || n.isAbsolute(A)) &&
            (w.linkname = A.split("/").slice(b).join("/")),
          E(w)
        );
      };
    };
  ki.pack = function (E, b) {
    (E || (E = "."), b || (b = {}));
    var w = b.fs || a,
      A = b.ignore || b.filter || u,
      v = b.map || u,
      C = b.mapStream || f,
      g = c(w, b.dereference ? w.stat : w.lstat, E, A, b.entries, b.sort),
      D = b.strict !== !1,
      N = typeof b.umask == "number" ? ~b.umask : ~F(),
      P = typeof b.dmode == "number" ? b.dmode : 0,
      R = typeof b.fmode == "number" ? b.fmode : 0,
      k = b.pack || t.pack(),
      q = b.finish || u;
    (b.strip && (v = l(v, b.strip)),
      b.readable && ((P |= parseInt(555, 8)), (R |= parseInt(444, 8))),
      b.writable && ((P |= parseInt(333, 8)), (R |= parseInt(222, 8))));
    var U = function (re, X) {
        w.readlink(n.join(E, re), function (fe, Y) {
          if (fe) return k.destroy(fe);
          ((X.linkname = d(Y)), k.entry(X, V));
        });
      },
      $ = function (re, X, fe) {
        if (re) return k.destroy(re);
        if (!X) return (b.finalize !== !1 && k.finalize(), q(k));
        if (fe.isSocket()) return V();
        var Y = {
          name: d(X),
          mode: (fe.mode | (fe.isDirectory() ? P : R)) & N,
          mtime: fe.mtime,
          size: fe.size,
          type: "file",
          uid: fe.uid,
          gid: fe.gid,
        };
        if (fe.isDirectory())
          return (
            (Y.size = 0),
            (Y.type = "directory"),
            (Y = v(Y) || Y),
            k.entry(Y, V)
          );
        if (fe.isSymbolicLink())
          return ((Y.size = 0), (Y.type = "symlink"), (Y = v(Y) || Y), U(X, Y));
        if (((Y = v(Y) || Y), !fe.isFile()))
          return D ? k.destroy(new Error("unsupported type for " + X)) : V();
        var Ce = k.entry(Y, V);
        if (Ce) {
          var ue = C(
            w.createReadStream(n.join(E, X), {
              start: 0,
              end: Y.size > 0 ? Y.size - 1 : Y.size,
            }),
            Y,
          );
          (ue.on("error", function (Ae) {
            Ce.destroy(Ae);
          }),
            o(ue, Ce));
        }
      },
      V = function (re) {
        if (re) return k.destroy(re);
        g($);
      };
    return (V(), k);
  };
  var h = function (E) {
      return E.length ? E[E.length - 1] : null;
    },
    y = function () {
      return process.getuid ? process.getuid() : -1;
    },
    F = function () {
      return process.umask ? process.umask() : 0;
    };
  ki.extract = function (E, b) {
    (E || (E = "."), b || (b = {}));
    var w = b.fs || a,
      A = b.ignore || b.filter || u,
      v = b.map || u,
      C = b.mapStream || f,
      g = b.chown !== !1 && !s && y() === 0,
      D = b.extract || t.extract(),
      N = [],
      P = new Date(),
      R = typeof b.umask == "number" ? ~b.umask : ~F(),
      k = typeof b.dmode == "number" ? b.dmode : 0,
      q = typeof b.fmode == "number" ? b.fmode : 0,
      U = b.strict !== !1;
    (b.strip && (v = l(v, b.strip)),
      b.readable && ((k |= parseInt(555, 8)), (q |= parseInt(444, 8))),
      b.writable && ((k |= parseInt(333, 8)), (q |= parseInt(222, 8))));
    var $ = function (X, fe) {
        for (var Y; (Y = h(N)) && X.slice(0, Y[0].length) !== Y[0];) N.pop();
        if (!Y) return fe();
        w.utimes(Y[0], P, Y[1], fe);
      },
      V = function (X, fe, Y) {
        if (b.utimes === !1) return Y();
        if (fe.type === "directory") return w.utimes(X, P, fe.mtime, Y);
        if (fe.type === "symlink") return $(X, Y);
        w.utimes(X, P, fe.mtime, function (Ce) {
          if (Ce) return Y(Ce);
          $(X, Y);
        });
      },
      re = function (X, fe, Y) {
        var Ce = fe.type === "symlink",
          ue = Ce ? w.lchmod : w.chmod,
          Ae = Ce ? w.lchown : w.chown;
        if (!ue) return Y();
        var Q = (fe.mode | (fe.type === "directory" ? k : q)) & R;
        Ae && g ? Ae.call(w, X, fe.uid, fe.gid, ge) : ge(null);
        function ge(I) {
          if (I) return Y(I);
          if (!ue) return Y();
          ue.call(w, X, Q, Y);
        }
      };
    return (
      D.on("entry", function (X, fe, Y) {
        ((X = v(X) || X), (X.name = d(X.name)));
        var Ce = n.join(E, n.join("/", X.name));
        if (A(Ce, X)) return (fe.resume(), Y());
        var ue = function (_) {
            if (_) return Y(_);
            V(Ce, X, function (W) {
              if (W) return Y(W);
              if (s) return Y();
              re(Ce, X, Y);
            });
          },
          Ae = function () {
            if (s) return Y();
            w.unlink(Ce, function () {
              w.symlink(X.linkname, Ce, ue);
            });
          },
          Q = function () {
            if (s) return Y();
            w.unlink(Ce, function () {
              var _ = n.join(E, n.join("/", X.linkname));
              w.link(_, Ce, function (W) {
                if (W && W.code === "EPERM" && b.hardlinkAsFilesFallback)
                  return ((fe = w.createReadStream(_)), ge());
                ue(W);
              });
            });
          },
          ge = function () {
            var _ = w.createWriteStream(Ce),
              W = C(fe, X);
            (_.on("error", function (M) {
              W.destroy(M);
            }),
              o(W, _, function (M) {
                if (M) return Y(M);
                _.on("close", ue);
              }));
          };
        if (X.type === "directory")
          return (
            N.push([Ce, X.mtime]),
            S(Ce, { fs: w, own: g, uid: X.uid, gid: X.gid }, ue)
          );
        var I = n.dirname(Ce);
        m(w, I, n.join(E, "."), function (_, W) {
          if (_) return Y(_);
          if (!W) return Y(new Error(I + " is not a valid path"));
          S(I, { fs: w, own: g, uid: X.uid, gid: X.gid }, function (M) {
            if (M) return Y(M);
            switch (X.type) {
              case "file":
                return ge();
              case "link":
                return Q();
              case "symlink":
                return Ae();
            }
            if (U)
              return Y(
                new Error("unsupported type for " + Ce + " (" + X.type + ")"),
              );
            (fe.resume(), Y());
          });
        });
      }),
      b.finish && D.on("finish", b.finish),
      D
    );
  };
  function m(E, b, w, A) {
    if (b === w) return A(null, !0);
    E.lstat(b, function (v, C) {
      if (v && v.code !== "ENOENT") return A(v);
      if (v || C.isDirectory()) return m(E, n.join(b, ".."), w, A);
      A(null, !1);
    });
  }
  function S(E, b, w) {
    i(E, { fs: b.fs }, function (A, v) {
      !A && v && b.own ? e(v, b.uid, b.gid, w) : w(A);
    });
  }
  return ki;
}
var zy = Vy();
const Xy = pr(zy);
async function Yy(e, t) {
  try {
    t({ text: "Fetching..." });
    const o = await Ir(e, { resolveBodyOnly: !0 });
    t(null);
    const i = JSON.parse(o),
      {
        platformName: a,
        platformDisplayName: n,
        downloadURL: r,
        version: s,
        supportedAppVersion: u,
        untar: f,
        compression: d,
      } = i;
    if (!a || !r || !s)
      throw Error("Platform integration manifest is malformed");
    const c = `${n || a} v${s || "(unknown)"}`;
    if (nl.lte(Ve.version, u.min)) {
      t({
        text: `Cannot install ${c} because your app version is older than supported, try checking for updates`,
      });
      return;
    }
    if (nl.gte(Ve.version, u.max)) {
      t({
        text: `Cannot install ${c} because your app version is newer than supported`,
      });
      return;
    }
    t({ text: `Downloading ${c}...` });
    const l = G.join(lt, `platform-integration-${a}`);
    ze.existsSync(l) || (await Te.mkdir(l));
    const h = G.join(l, "manifest.json"),
      y = G.join(Ke.tmpdir(), Math.random().toString(36).replace(".", ""));
    if (f || d === "tar")
      await Bs(Ir.stream(r), eu.createGunzip(), Xy.extract(l));
    else if ((await Bs(Ir.stream(r), ze.createWriteStream(y)), d === "zip")) {
      const { default: F } = await import("./index-3ZIyHCQx.mjs").then(
          (S) => S.i,
        ),
        { default: m } = await import("./index-DybQu2_8.mjs").then((S) => S.i);
      (await F(y, l, { plugins: [m()] }), await Te.unlink(y));
    } else {
      const F = G.join(l, "index.js");
      await Te.rename(y, F);
    }
    return (
      await Te.writeFile(h, JSON.stringify(i)),
      { release: c, installDirPath: l }
    );
  } catch (o) {
    (logger.error(o), t({ text: `Something went wrong: ${o.message}` }));
  }
}
const { TouchBarButton: Ky } = Sh,
  Jy = 8;
async function Qy(e) {
  try {
    const t = await Ir.head(e, {
      followRedirect: !1,
      timeout: { request: 3e3 },
    });
    if (t.statusCode === 301 && t.headers.location)
      return t.headers.location.replace("fileproxy://", "file://");
  } catch {}
  return e;
}
function Gr(e, t) {
  const [, o] = e.getContentSize(),
    i = e.webContents.getZoomFactor(),
    a = t.x * i,
    n = t.y * i,
    r = t.width * i,
    s = t.height * i;
  return { x: a, y: o - n - s, width: r, height: s };
}
function Zy(e) {
  let t, o, i, a, n;
  const r = () => {
    const s = n;
    s && (s.dispose(), s.presenter.close());
  };
  return {
    setTouchBar(s) {
      if (!Ne) return;
      const u = [new Ky({ label: "⌘K", click: s })],
        f = new Sh({ items: [...u] });
      e.window.setTouchBar(f);
    },
    setMenuBar(s) {
      const u = lr.buildFromTemplate(s);
      lr.setApplicationMenu(u);
    },
    globalShortcutRegister: Yu.register.bind(Yu),
    installPlatformFromManifest: Yy,
    listenForContactsChanges: Mg,
    showSourcesPopover(s, u, f, d) {
      if (!Re) {
        d("dismiss");
        return;
      }
      const c = He.getFocusedWindow() ?? e.window,
        l = c.getNativeWindowHandle(),
        { x: h, y, width: F, height: m } = Gr(c, u);
      (t?.close(), o?.());
      const S = () => {
          ((t = void 0), (o = void 0), c.off("closed", S));
        },
        E = new Re.PopoverPresenter((b, w) => {
          (d(b, w), b === "dismiss" && S());
        });
      (E.show(l, JSON.stringify(s), h, y, F, m, f),
        (t = E),
        (o = S),
        c.once("closed", S));
    },
    closeSourcesPopover() {
      (t?.close(), o?.());
    },
    updateSourcesPopoverPosition(s) {
      if (!t) return;
      const u = He.getFocusedWindow() ?? e.window,
        { x: f, y: d, width: c, height: l } = Gr(u, s);
      t.updatePosition(f, d, c, l);
    },
    showVotesPopover(s, u, f, d) {
      if (!Re) {
        d("dismiss");
        return;
      }
      const c = He.getFocusedWindow() ?? e.window,
        l = c.getNativeWindowHandle(),
        { x: h, y, width: F, height: m } = Gr(c, u);
      (i?.close(), a?.());
      const S = () => {
          ((i = void 0), (a = void 0), c.off("closed", S));
        },
        E = new Set(),
        b = [];
      let w = 0;
      const A = () => {
          for (; w < Jy && b.length > 0;) {
            const g = b.shift();
            (w++,
              Qy(g)
                .then((D) => {
                  i === C && C.deliverAvatar(g, D);
                })
                .catch(() => {})
                .finally(() => {
                  (w--, A());
                }));
          }
        },
        v = (g) => {
          !g || E.has(g) || (E.add(g), b.push(g), A());
        },
        C = new Re.VotesPopoverPresenter((g, D) => {
          (d(g, D), g === "dismiss" && S());
        }, v);
      (C.show(l, JSON.stringify(s), h, y, F, m, f),
        (i = C),
        (a = S),
        c.once("closed", S));
    },
    showConnectionPopover(s, u, f, d, c) {
      if (!Re) {
        c("dismiss");
        return;
      }
      const l = He.getFocusedWindow() ?? e.window,
        h = l.getNativeWindowHandle(),
        { x: y, y: F, width: m, height: S } = Gr(l, f);
      r();
      let E = !1;
      const b = () => {
          E || ((E = !0), n?.id === s && (n = void 0), l.off("closed", b));
        },
        w = new Re.ConnectionPopoverPresenter((A, v) => {
          (c(A, v), (A === "select" || A === "dismiss") && b());
        });
      (w.show(h, JSON.stringify(u), y, F, m, S, d),
        (n = { id: s, presenter: w, win: l, dispose: b }),
        l.once("closed", b));
    },
    closeConnectionPopover(s) {
      n?.id === s && r();
    },
    updateConnectionPopoverPosition(s, u) {
      if (n?.id !== s) return;
      const { presenter: f, win: d } = n,
        { x: c, y: l, width: h, height: y } = Gr(d, u);
      f.updatePosition(c, l, h, y);
    },
    closeVotesPopover() {
      (i?.close(), a?.());
    },
    updateVotesPopoverPosition(s) {
      if (!i) return;
      const u = He.getFocusedWindow() ?? e.window,
        { x: f, y: d, width: c, height: l } = Gr(u, s);
      i.updatePosition(f, d, c, l);
    },
    popupContextMenu(s, u, f, d) {
      const c = lr.buildFromTemplate(s),
        l = e.window.webContents.getZoomFactor();
      (c.popup({
        window: e,
        callback: f,
        ...(d && {
          x: Math.round(d.x * l),
          y: Math.round(d.y * l),
          positioningItem: d.positioningItem,
        }),
      }),
        u && c.on("menu-will-close", () => u()));
    },
  };
}
function eE() {
  const e = new qm();
  let t = !1;
  try {
    (e.init(G.join(lt, "index.db"), { readonly: !0, fileMustExist: !0 }),
      (t = !0));
    const o = e.pluck_get($m, "startupThreadIDs"),
      i = JSON.parse(o ?? "null") ?? [],
      a = jm(e.prepareSQL(Wm).all()),
      n = [...new Set([...i, ...a.map((s) => s.threadID)])],
      r = n.length === 0 ? [] : e.prepareSQL(Hm(n.length)).all(...n);
    return {
      rawKeyValues: e.prepareSQL(Km).raw().all(),
      initialAccounts: Xm(e.prepareSQL(Ym).all()),
      initialLabels: Vm(e.prepareSQL(zm).all()),
      initialUnions: a,
      startupThreads: Gm(r),
    };
  } catch (o) {
    return (
      logger.error("[startup-bootstrap] failed to build bootstrap payload", o),
      null
    );
  } finally {
    if (t)
      try {
        e.dispose();
      } catch (o) {
        logger.error("[startup-bootstrap] failed to close sqlite handle", o);
      }
  }
}
const pu = lg(),
  jp = pu.promise;
jp.catch(() => {});
function tE() {
  pu.resolve();
}
function rE(e) {
  pu.reject(e);
}
function nE(e) {
  const t = ky(e),
    o = Zy(e),
    i = new Map(),
    a = new FinalizationRegistry((r) => {
      const s = i.get(r) ?? 0;
      s <= 1
        ? (i.delete(r), e.sendMessage("async-remote-fn-release-callback", r))
        : i.set(r, s - 1);
    });
  function n(r) {
    switch (r.type) {
      case "function": {
        const s = (...u) => {
          e.sendMessage("async-remote-fn-callback", {
            cbID: r.cbID,
            args: r.includeArgs ? u : void 0,
          });
        };
        return (
          i.set(r.cbID, (i.get(r.cbID) ?? 0) + 1),
          a.register(s, r.cbID),
          s
        );
      }
      case "object": {
        if (r.data === null) return null;
        const s = {};
        for (const [u, f] of Object.entries(r.data)) s[u] = n(f);
        return s;
      }
      case "array":
        return r.data.map(n);
      case "etc":
        return r.data;
    }
  }
  (Bt.handle("async-remote", (r, s) => {
    const { methodName: u, args: f } = s;
    return Ls(t, u)(...f);
  }),
    Bt.handle("async-remote-fn", (r, s) => {
      const { methodName: u, args: f } = s;
      return Ls(o, u)(...f.map(n));
    }));
}
function iE() {
  (Bt.on("renderer-bootstrap-sync", async (e) => {
    let t = null;
    try {
      (await jp,
        ut("renderer-bootstrap-sync: migrations ready, reading bootstrap"),
        (t = { initialState: Nh(), startupBootstrap: eE() }));
    } catch (o) {
      logger.error("renderer-bootstrap-sync failed", o);
    } finally {
      e.returnValue = t;
    }
  }),
    Bt.handle("native-remote", (e, t) => {
      const { methodName: o, args: i } = t;
      return Ls(ND, o)(...i);
    }),
    Bt.handle("startup-checkpoints", () => yg()),
    Bt.handle(
      "get-machine-id",
      async () => (
        globalThis.MACHINE_ID_PROMISE && (await globalThis.MACHINE_ID_PROMISE),
        globalThis.MACHINE_ID
      ),
    ));
}
function oE({ message: e, name: t, stack: o, methodName: i }) {
  const a = new Error(e || "Unknown renderer error");
  return (t && (a.name = t), i && (a.methodName = i), o && (a.stack = o), a);
}
function aE(e) {
  const t = new Map(),
    o = (s, u) => {
      if (s?.sender && s.sender !== e.webContents) return;
      const { reqID: f, result: d, error: c } = u ?? {};
      if (f == null) return;
      const l = t.get(f);
      l && (t.delete(f), c ? l.reject(oE(c)) : l.resolve(d));
    };
  Bt.on("root-store-result", o);
  const i = (s) => {
    const u = [...t.values()];
    t.clear();
    for (const { reject: f } of u) f(new Error(s));
  };
  (e.once("closed", () => {
    (Bt.off("root-store-result", o), i("Window was closed"));
  }),
    typeof e.webContents?.on == "function" &&
      e.webContents.on("render-process-gone", () =>
        i("Renderer process is gone"),
      ));
  const a = () => e.isDestroyed() || !!e.webContents?.isDestroyed?.();
  let n = 0;
  return new Proxy(
    {},
    {
      get:
        (s, u) =>
        (...f) =>
          new Promise((d, c) => {
            if (a()) return c(new Error("Window is destroyed"));
            const l = ++n;
            t.set(l, { resolve: d, reject: c });
            try {
              e.webContents.send("root-store-call", {
                reqID: l,
                methodName: u,
                args: f,
              });
            } catch (h) {
              (t.delete(l), c(h instanceof Error ? h : new Error(String(h))));
            }
          }),
    },
  );
}
const hd = 15e3,
  sE = 3e4;
let Xr, xr, uE;
const lE = 1e4,
  sr = new Map(),
  Wp = (e) =>
    e.replace(/^(https?:\/\/[^/]+\/)[^/]+/, "$1<nonce>").slice(0, 220),
  Hp = () => {
    if (!xr) return;
    const e = Pr ? ["http://*/*.ts*"] : ["file://*/*.js*"],
      t = { urls: Xr ? [...e, `${Xr}/*`] : e },
      o = (i) => !!Xr && i.startsWith(Xr);
    (Xr &&
      (xr.onBeforeRequest(t, (i, a) => {
        (o(i.url) &&
          sr.set(i.id, { url: i.url, method: i.method, start: Date.now() }),
          a({}));
      }),
      xr.onSendHeaders(t, (i) => {
        const a = sr.get(i.id);
        a && (a.sent = Date.now());
      }),
      xr.onResponseStarted(t, (i) => {
        const a = sr.get(i.id);
        a && (a.responseStarted = Date.now());
      })),
      xr.onErrorOccurred(t, (i) => {
        if (o(i.url)) {
          sr.delete(i.id);
          return;
        }
        dE(i);
      }),
      xr.onCompleted(t, (i) => {
        if (o(i.url)) {
          const r = sr.get(i.id);
          (sr.delete(i.id),
            r &&
              Date.now() - r.start > lE &&
              logger.warn(
                `pas-monitor: slow pas request completed in ${Math.round((Date.now() - r.start) / 1e3)}s`,
                `${r.method} ${Wp(r.url)}`,
              ));
          return;
        }
        const { url: a, statusCode: n } = i;
        if (n >= 400) {
          const r = Kr(a);
          (logger.error(`Failed to load module (${n}): ${Pr ? a : r}`),
            globalThis.Sentry?.captureException(
              new Error(`Failed to load module: HTTP ${n}`),
              {
                tags: {
                  module: "webRequest",
                  error_type: "http_error",
                  status_code: n.toString(),
                },
                extra: { url: r, statusCode: n },
              },
            ));
        }
      }));
  },
  cE = (e) => {
    ((xr = e), Hp());
  },
  fE = (e) => {
    ((Xr = e),
      Hp(),
      (uE ??= setInterval(() => {
        const t = Date.now(),
          o = [...sr.values()].filter(
            (i) => !i.responseStarted && t - i.start > hd,
          );
        o.length &&
          logger.warn(
            `pas-monitor: ${o.length}/${sr.size} pas request(s) stalled >${hd / 1e3}s`,
            o.map(
              (i) =>
                `${i.sent ? "sent-no-response" : "queued-in-pool"} ${Math.round((t - i.start) / 1e3)}s ${i.method} ${Wp(i.url)}`,
            ),
          );
      }, sE)));
  };
async function dE({ url: e, error: t }) {
  const o = await hE(e),
    i = Kr(e);
  (logger.error(
    `Failed to load module (${t}): ${Pr ? e : i}. Probe = ${JSON.stringify(o)}`,
  ),
    globalThis.Sentry?.captureException(
      new Error(`Failed to load module: ${t}`),
      {
        tags: {
          module: "webRequest",
          error_type: "load_error",
          web_request_error: t,
          probe_ok: o.ok.toString(),
        },
        extra: { url: i, error: t, probeResult: o },
      },
    ));
}
async function hE(e) {
  try {
    const t = Uh(new URL(e)),
      o = await jg.stat(t);
    return { ok: o.isFile(), path: Kr(t), isDir: o.isDirectory() };
  } catch (t) {
    return { ok: !1, path: "(unresolvable)", error: String(t) };
  }
}
const Ki = {
    minWidth: 330,
    minHeight: 400,
    show: !1,
    ...(Ne && { trafficLightPosition: Og, vibrancy: "sidebar" }),
    ...((Kt || cr) && { autoHideMenuBar: !0 }),
  },
  pE = { ...Ki, ...(Ne && { titleBarStyle: "hidden" }), fullscreenable: Ne },
  Yr = $g("renderer");
Yr.buddyOriginOverride = "renderer";
class DE {
  constructor() {
    ((this.wsk = ep("main")),
      (this.window = new He({
        ...pE,
        show: !1,
        webPreferences: {
          ...(Ne && { scrollBounce: !0 }),
          spellcheck: It.enable_spellcheck ?? !0,
          webSecurity: !0,
          sandbox: !0,
          nodeIntegration: !1,
          nodeIntegrationInWorker: !1,
          contextIsolation: !0,
          preload: G.join(tu, "..", "preload", "index.js"),
        },
      })),
      (this.rs = aE(this.window)),
      cE(this.window.webContents.session.webRequest),
      this.wsk.manage(this.window, !0, { deferMaximize: !0 }),
      this.initializeTrafficLightManager(),
      nE(this),
      this.window.on("close", (o) => {
        if (It.quit_on_close) return ye.quit();
        (o.preventDefault(),
          this.window.isFullScreen()
            ? (this.window.setFullScreen(!1),
              this.window.once("leave-full-screen", () => {
                this.window.hide();
              }))
            : this.window.hide());
      }),
      this.window.on("enter-full-screen", () => {
        this.rs.setFullScreened(!0);
      }),
      this.window.on("leave-full-screen", () => {
        this.rs.setFullScreened(!1);
      }));
    let t;
    (this.window.on("unresponsive", () => {
      t = new AbortController();
      const o = `${tt.APP_NAME} is unresponsive`;
      (kt("unresponsive", o),
        Xe.showMessageBox(this.window, {
          message: o,
          signal: t.signal,
          buttons: ["Keep Waiting", "Reload App", "Relaunch App"],
        }).then((i) => {
          switch (i.response) {
            case 1:
              this.window.reload();
              break;
            case 2:
              Qn("unresponsive dialog button clicked");
              break;
          }
        }));
    }),
      this.window.on("responsive", () => {
        t?.abort();
      }),
      this.window.webContents.on("console-message", (o, i, a, n, r) => {
        const s = ["debug", "log", "warn", "error"][i] || "log",
          u = "";
        switch (s) {
          case "debug":
            Yr.silently.debug(a, u);
            break;
          case "log":
            Yr.silently.log(a, u);
            break;
          case "warn":
            Yr.silently.warn(a, u);
            break;
          case "error":
            Yr.silently.error(a, u);
            break;
          default:
            Yr.silently.info(a, u);
        }
      }));
  }
  get fullScreen() {
    return this.window.fullScreen;
  }
  show() {
    (this.window.isMinimized() && this.window.restore(),
      this.window.show(),
      this.wsk.applyMaximizeState());
  }
  hide() {
    this.window.hide();
  }
  get isVisible() {
    return this.window.isVisible();
  }
  toggleVisible() {
    this.isVisible ? this.window.hide() : this.show();
  }
  sendMessage(t, ...o) {
    this.window.isDestroyed() || this.window.webContents.send(t, ...o);
  }
  moveTrafficLights(t, o, i) {
    this.trafficLightManager?.moveTrafficLights(t, o, i);
  }
  resetMainWSK() {
    this.wsk.reset();
  }
  loadURL(t) {
    (this.window.webContents.on("will-navigate", (o, i) => {
      i !== t &&
        (o.preventDefault(),
        logger.error("Prevented navigation to", i),
        Sentry.captureMessage(`Prevented navigation to ${i}`));
    }),
      this.window.loadURL(t));
  }
  initializeTrafficLightManager() {
    Re?.TrafficLightManager &&
      ((this.trafficLightManager = new Re.TrafficLightManager()),
      this.trafficLightManager.attachToWindow(
        this.window.getNativeWindowHandle(),
      ));
  }
}
function mE() {
  return new DE();
}
function gE() {
  fr.defaultSession.webRequest.onHeadersReceived(
    { urls: ["https://*/*"] },
    (e, t) => {
      ("cross-origin-resource-policy" in e.responseHeaders &&
        (e.responseHeaders["cross-origin-resource-policy"] = void 0),
        t({ responseHeaders: e.responseHeaders }));
    },
  );
}
function wE(e) {
  return Number.isInteger(e)
    ? e >= 4352 &&
        (e <= 4447 ||
          e === 9001 ||
          e === 9002 ||
          (11904 <= e && e <= 12871 && e !== 12351) ||
          (12880 <= e && e <= 19903) ||
          (19968 <= e && e <= 42182) ||
          (43360 <= e && e <= 43388) ||
          (44032 <= e && e <= 55203) ||
          (63744 <= e && e <= 64255) ||
          (65040 <= e && e <= 65049) ||
          (65072 <= e && e <= 65131) ||
          (65281 <= e && e <= 65376) ||
          (65504 <= e && e <= 65510) ||
          (110592 <= e && e <= 110593) ||
          (127488 <= e && e <= 127569) ||
          (131072 <= e && e <= 262141))
    : !1;
}
const Fs = 10,
  pd =
    (e = 0) =>
    (t) =>
      `\x1B[${t + e}m`,
  Dd =
    (e = 0) =>
    (t) =>
      `\x1B[${38 + e};5;${t}m`,
  md =
    (e = 0) =>
    (t, o, i) =>
      `\x1B[${38 + e};2;${t};${o};${i}m`,
  qe = {
    modifier: {
      reset: [0, 0],
      bold: [1, 22],
      dim: [2, 22],
      italic: [3, 23],
      underline: [4, 24],
      overline: [53, 55],
      inverse: [7, 27],
      hidden: [8, 28],
      strikethrough: [9, 29],
    },
    color: {
      black: [30, 39],
      red: [31, 39],
      green: [32, 39],
      yellow: [33, 39],
      blue: [34, 39],
      magenta: [35, 39],
      cyan: [36, 39],
      white: [37, 39],
      blackBright: [90, 39],
      gray: [90, 39],
      grey: [90, 39],
      redBright: [91, 39],
      greenBright: [92, 39],
      yellowBright: [93, 39],
      blueBright: [94, 39],
      magentaBright: [95, 39],
      cyanBright: [96, 39],
      whiteBright: [97, 39],
    },
    bgColor: {
      bgBlack: [40, 49],
      bgRed: [41, 49],
      bgGreen: [42, 49],
      bgYellow: [43, 49],
      bgBlue: [44, 49],
      bgMagenta: [45, 49],
      bgCyan: [46, 49],
      bgWhite: [47, 49],
      bgBlackBright: [100, 49],
      bgGray: [100, 49],
      bgGrey: [100, 49],
      bgRedBright: [101, 49],
      bgGreenBright: [102, 49],
      bgYellowBright: [103, 49],
      bgBlueBright: [104, 49],
      bgMagentaBright: [105, 49],
      bgCyanBright: [106, 49],
      bgWhiteBright: [107, 49],
    },
  };
Object.keys(qe.modifier);
const yE = Object.keys(qe.color),
  EE = Object.keys(qe.bgColor);
[...yE, ...EE];
function vE() {
  const e = new Map();
  for (const [t, o] of Object.entries(qe)) {
    for (const [i, a] of Object.entries(o))
      ((qe[i] = { open: `\x1B[${a[0]}m`, close: `\x1B[${a[1]}m` }),
        (o[i] = qe[i]),
        e.set(a[0], a[1]));
    Object.defineProperty(qe, t, { value: o, enumerable: !1 });
  }
  return (
    Object.defineProperty(qe, "codes", { value: e, enumerable: !1 }),
    (qe.color.close = "\x1B[39m"),
    (qe.bgColor.close = "\x1B[49m"),
    (qe.color.ansi = pd()),
    (qe.color.ansi256 = Dd()),
    (qe.color.ansi16m = md()),
    (qe.bgColor.ansi = pd(Fs)),
    (qe.bgColor.ansi256 = Dd(Fs)),
    (qe.bgColor.ansi16m = md(Fs)),
    Object.defineProperties(qe, {
      rgbToAnsi256: {
        value: (t, o, i) =>
          t === o && o === i
            ? t < 8
              ? 16
              : t > 248
                ? 231
                : Math.round(((t - 8) / 247) * 24) + 232
            : 16 +
              36 * Math.round((t / 255) * 5) +
              6 * Math.round((o / 255) * 5) +
              Math.round((i / 255) * 5),
        enumerable: !1,
      },
      hexToRgb: {
        value: (t) => {
          const o = /[a-f\d]{6}|[a-f\d]{3}/i.exec(t.toString(16));
          if (!o) return [0, 0, 0];
          let [i] = o;
          i.length === 3 && (i = [...i].map((n) => n + n).join(""));
          const a = Number.parseInt(i, 16);
          return [(a >> 16) & 255, (a >> 8) & 255, a & 255];
        },
        enumerable: !1,
      },
      hexToAnsi256: {
        value: (t) => qe.rgbToAnsi256(...qe.hexToRgb(t)),
        enumerable: !1,
      },
      ansi256ToAnsi: {
        value: (t) => {
          if (t < 8) return 30 + t;
          if (t < 16) return 90 + (t - 8);
          let o, i, a;
          if (t >= 232) ((o = ((t - 232) * 10 + 8) / 255), (i = o), (a = o));
          else {
            t -= 16;
            const s = t % 36;
            ((o = Math.floor(t / 36) / 5),
              (i = Math.floor(s / 6) / 5),
              (a = (s % 6) / 5));
          }
          const n = Math.max(o, i, a) * 2;
          if (n === 0) return 30;
          let r =
            30 + ((Math.round(a) << 2) | (Math.round(i) << 1) | Math.round(o));
          return (n === 2 && (r += 60), r);
        },
        enumerable: !1,
      },
      rgbToAnsi: {
        value: (t, o, i) => qe.ansi256ToAnsi(qe.rgbToAnsi256(t, o, i)),
        enumerable: !1,
      },
      hexToAnsi: {
        value: (t) => qe.ansi256ToAnsi(qe.hexToAnsi256(t)),
        enumerable: !1,
      },
    }),
    qe
  );
}
const gd = vE(),
  CE = /^[\uD800-\uDBFF][\uDC00-\uDFFF]$/,
  Gp = ["\x1B", ""],
  Ui = (e) => `${Gp[0]}[${e}m`,
  wd = (e, t, o) => {
    let i = [];
    e = [...e];
    for (let a of e) {
      const n = a;
      a.includes(";") && (a = a.split(";")[0][0] + "0");
      const r = gd.codes.get(Number.parseInt(a, 10));
      if (r) {
        const s = e.indexOf(r.toString());
        s === -1 ? i.push(Ui(t ? r : n)) : e.splice(s, 1);
      } else if (t) {
        i.push(Ui(0));
        break;
      } else i.push(Ui(n));
    }
    if (t && ((i = i.filter((a, n) => i.indexOf(a) === n)), o !== void 0)) {
      const a = Ui(gd.codes.get(Number.parseInt(o, 10)));
      i = i.reduce((n, r) => (r === a ? [r, ...n] : [...n, r]), []);
    }
    return i.join("");
  };
function ir(e, t, o) {
  const i = [...e],
    a = [];
  let n = typeof o == "number" ? o : i.length,
    r = !1,
    s,
    u = 0,
    f = "";
  for (const [d, c] of i.entries()) {
    let l = !1;
    if (Gp.includes(c)) {
      const h = /\d[^m]*/.exec(e.slice(d, d + 18));
      ((s = h && h.length > 0 ? h[0] : void 0),
        u < n && ((r = !0), s !== void 0 && a.push(s)));
    } else r && c === "m" && ((r = !1), (l = !0));
    if (
      (!r && !l && u++,
      !CE.test(c) && wE(c.codePointAt()) && (u++, typeof o != "number" && n++),
      u > t && u <= n)
    )
      f += c;
    else if (u === t && !r && s !== void 0) f = wd(a);
    else if (u >= n) {
      f += wd(a, !0, s);
      break;
    }
  }
  return f;
}
function AE({ onlyFirst: e = !1 } = {}) {
  const t = [
    "[\\u001B\\u009B][[\\]()#;?]*(?:(?:(?:(?:;[-a-zA-Z\\d\\/#&.:=?%@~_]+)*|[a-zA-Z\\d]+(?:;[-a-zA-Z\\d\\/#&.:=?%@~_]*)*)?\\u0007)",
    "(?:(?:\\d{1,4}(?:;\\d{0,4})*)?[\\dA-PR-TZcf-ntqry=><~]))",
  ].join("|");
  return new RegExp(t, e ? void 0 : "g");
}
const bE = AE();
function FE(e) {
  if (typeof e != "string")
    throw new TypeError(`Expected a \`string\`, got \`${typeof e}\``);
  return e.replace(bE, "");
}
var Ss = { exports: {} },
  yd;
function SE() {
  return (
    yd ||
      ((yd = 1),
      (function (e) {
        var t = {};
        ((e.exports = t),
          (t.eastAsianWidth = function (i) {
            var a = i.charCodeAt(0),
              n = i.length == 2 ? i.charCodeAt(1) : 0,
              r = a;
            return (
              55296 <= a &&
                a <= 56319 &&
                56320 <= n &&
                n <= 57343 &&
                ((a &= 1023), (n &= 1023), (r = (a << 10) | n), (r += 65536)),
              r == 12288 ||
              (65281 <= r && r <= 65376) ||
              (65504 <= r && r <= 65510)
                ? "F"
                : r == 8361 ||
                    (65377 <= r && r <= 65470) ||
                    (65474 <= r && r <= 65479) ||
                    (65482 <= r && r <= 65487) ||
                    (65490 <= r && r <= 65495) ||
                    (65498 <= r && r <= 65500) ||
                    (65512 <= r && r <= 65518)
                  ? "H"
                  : (4352 <= r && r <= 4447) ||
                      (4515 <= r && r <= 4519) ||
                      (4602 <= r && r <= 4607) ||
                      (9001 <= r && r <= 9002) ||
                      (11904 <= r && r <= 11929) ||
                      (11931 <= r && r <= 12019) ||
                      (12032 <= r && r <= 12245) ||
                      (12272 <= r && r <= 12283) ||
                      (12289 <= r && r <= 12350) ||
                      (12353 <= r && r <= 12438) ||
                      (12441 <= r && r <= 12543) ||
                      (12549 <= r && r <= 12589) ||
                      (12593 <= r && r <= 12686) ||
                      (12688 <= r && r <= 12730) ||
                      (12736 <= r && r <= 12771) ||
                      (12784 <= r && r <= 12830) ||
                      (12832 <= r && r <= 12871) ||
                      (12880 <= r && r <= 13054) ||
                      (13056 <= r && r <= 19903) ||
                      (19968 <= r && r <= 42124) ||
                      (42128 <= r && r <= 42182) ||
                      (43360 <= r && r <= 43388) ||
                      (44032 <= r && r <= 55203) ||
                      (55216 <= r && r <= 55238) ||
                      (55243 <= r && r <= 55291) ||
                      (63744 <= r && r <= 64255) ||
                      (65040 <= r && r <= 65049) ||
                      (65072 <= r && r <= 65106) ||
                      (65108 <= r && r <= 65126) ||
                      (65128 <= r && r <= 65131) ||
                      (110592 <= r && r <= 110593) ||
                      (127488 <= r && r <= 127490) ||
                      (127504 <= r && r <= 127546) ||
                      (127552 <= r && r <= 127560) ||
                      (127568 <= r && r <= 127569) ||
                      (131072 <= r && r <= 194367) ||
                      (177984 <= r && r <= 196605) ||
                      (196608 <= r && r <= 262141)
                    ? "W"
                    : (32 <= r && r <= 126) ||
                        (162 <= r && r <= 163) ||
                        (165 <= r && r <= 166) ||
                        r == 172 ||
                        r == 175 ||
                        (10214 <= r && r <= 10221) ||
                        (10629 <= r && r <= 10630)
                      ? "Na"
                      : r == 161 ||
                          r == 164 ||
                          (167 <= r && r <= 168) ||
                          r == 170 ||
                          (173 <= r && r <= 174) ||
                          (176 <= r && r <= 180) ||
                          (182 <= r && r <= 186) ||
                          (188 <= r && r <= 191) ||
                          r == 198 ||
                          r == 208 ||
                          (215 <= r && r <= 216) ||
                          (222 <= r && r <= 225) ||
                          r == 230 ||
                          (232 <= r && r <= 234) ||
                          (236 <= r && r <= 237) ||
                          r == 240 ||
                          (242 <= r && r <= 243) ||
                          (247 <= r && r <= 250) ||
                          r == 252 ||
                          r == 254 ||
                          r == 257 ||
                          r == 273 ||
                          r == 275 ||
                          r == 283 ||
                          (294 <= r && r <= 295) ||
                          r == 299 ||
                          (305 <= r && r <= 307) ||
                          r == 312 ||
                          (319 <= r && r <= 322) ||
                          r == 324 ||
                          (328 <= r && r <= 331) ||
                          r == 333 ||
                          (338 <= r && r <= 339) ||
                          (358 <= r && r <= 359) ||
                          r == 363 ||
                          r == 462 ||
                          r == 464 ||
                          r == 466 ||
                          r == 468 ||
                          r == 470 ||
                          r == 472 ||
                          r == 474 ||
                          r == 476 ||
                          r == 593 ||
                          r == 609 ||
                          r == 708 ||
                          r == 711 ||
                          (713 <= r && r <= 715) ||
                          r == 717 ||
                          r == 720 ||
                          (728 <= r && r <= 731) ||
                          r == 733 ||
                          r == 735 ||
                          (768 <= r && r <= 879) ||
                          (913 <= r && r <= 929) ||
                          (931 <= r && r <= 937) ||
                          (945 <= r && r <= 961) ||
                          (963 <= r && r <= 969) ||
                          r == 1025 ||
                          (1040 <= r && r <= 1103) ||
                          r == 1105 ||
                          r == 8208 ||
                          (8211 <= r && r <= 8214) ||
                          (8216 <= r && r <= 8217) ||
                          (8220 <= r && r <= 8221) ||
                          (8224 <= r && r <= 8226) ||
                          (8228 <= r && r <= 8231) ||
                          r == 8240 ||
                          (8242 <= r && r <= 8243) ||
                          r == 8245 ||
                          r == 8251 ||
                          r == 8254 ||
                          r == 8308 ||
                          r == 8319 ||
                          (8321 <= r && r <= 8324) ||
                          r == 8364 ||
                          r == 8451 ||
                          r == 8453 ||
                          r == 8457 ||
                          r == 8467 ||
                          r == 8470 ||
                          (8481 <= r && r <= 8482) ||
                          r == 8486 ||
                          r == 8491 ||
                          (8531 <= r && r <= 8532) ||
                          (8539 <= r && r <= 8542) ||
                          (8544 <= r && r <= 8555) ||
                          (8560 <= r && r <= 8569) ||
                          r == 8585 ||
                          (8592 <= r && r <= 8601) ||
                          (8632 <= r && r <= 8633) ||
                          r == 8658 ||
                          r == 8660 ||
                          r == 8679 ||
                          r == 8704 ||
                          (8706 <= r && r <= 8707) ||
                          (8711 <= r && r <= 8712) ||
                          r == 8715 ||
                          r == 8719 ||
                          r == 8721 ||
                          r == 8725 ||
                          r == 8730 ||
                          (8733 <= r && r <= 8736) ||
                          r == 8739 ||
                          r == 8741 ||
                          (8743 <= r && r <= 8748) ||
                          r == 8750 ||
                          (8756 <= r && r <= 8759) ||
                          (8764 <= r && r <= 8765) ||
                          r == 8776 ||
                          r == 8780 ||
                          r == 8786 ||
                          (8800 <= r && r <= 8801) ||
                          (8804 <= r && r <= 8807) ||
                          (8810 <= r && r <= 8811) ||
                          (8814 <= r && r <= 8815) ||
                          (8834 <= r && r <= 8835) ||
                          (8838 <= r && r <= 8839) ||
                          r == 8853 ||
                          r == 8857 ||
                          r == 8869 ||
                          r == 8895 ||
                          r == 8978 ||
                          (9312 <= r && r <= 9449) ||
                          (9451 <= r && r <= 9547) ||
                          (9552 <= r && r <= 9587) ||
                          (9600 <= r && r <= 9615) ||
                          (9618 <= r && r <= 9621) ||
                          (9632 <= r && r <= 9633) ||
                          (9635 <= r && r <= 9641) ||
                          (9650 <= r && r <= 9651) ||
                          (9654 <= r && r <= 9655) ||
                          (9660 <= r && r <= 9661) ||
                          (9664 <= r && r <= 9665) ||
                          (9670 <= r && r <= 9672) ||
                          r == 9675 ||
                          (9678 <= r && r <= 9681) ||
                          (9698 <= r && r <= 9701) ||
                          r == 9711 ||
                          (9733 <= r && r <= 9734) ||
                          r == 9737 ||
                          (9742 <= r && r <= 9743) ||
                          (9748 <= r && r <= 9749) ||
                          r == 9756 ||
                          r == 9758 ||
                          r == 9792 ||
                          r == 9794 ||
                          (9824 <= r && r <= 9825) ||
                          (9827 <= r && r <= 9829) ||
                          (9831 <= r && r <= 9834) ||
                          (9836 <= r && r <= 9837) ||
                          r == 9839 ||
                          (9886 <= r && r <= 9887) ||
                          (9918 <= r && r <= 9919) ||
                          (9924 <= r && r <= 9933) ||
                          (9935 <= r && r <= 9953) ||
                          r == 9955 ||
                          (9960 <= r && r <= 9983) ||
                          r == 10045 ||
                          r == 10071 ||
                          (10102 <= r && r <= 10111) ||
                          (11093 <= r && r <= 11097) ||
                          (12872 <= r && r <= 12879) ||
                          (57344 <= r && r <= 63743) ||
                          (65024 <= r && r <= 65039) ||
                          r == 65533 ||
                          (127232 <= r && r <= 127242) ||
                          (127248 <= r && r <= 127277) ||
                          (127280 <= r && r <= 127337) ||
                          (127344 <= r && r <= 127386) ||
                          (917760 <= r && r <= 917999) ||
                          (983040 <= r && r <= 1048573) ||
                          (1048576 <= r && r <= 1114109)
                        ? "A"
                        : "N"
            );
          }),
          (t.characterLength = function (i) {
            var a = this.eastAsianWidth(i);
            return a == "F" || a == "W" || a == "A" ? 2 : 1;
          }));
        function o(i) {
          return (
            i.match(/[\uD800-\uDBFF][\uDC00-\uDFFF]|[^\uD800-\uDFFF]/g) || []
          );
        }
        ((t.length = function (i) {
          for (var a = o(i), n = 0, r = 0; r < a.length; r++)
            n = n + this.characterLength(a[r]);
          return n;
        }),
          (t.slice = function (i, a, n) {
            ((textLen = t.length(i)),
              (a = a || 0),
              (n = n || 1),
              a < 0 && (a = textLen + a),
              n < 0 && (n = textLen + n));
            for (var r = "", s = 0, u = o(i), f = 0; f < u.length; f++) {
              var d = u[f],
                c = t.length(d);
              if (s >= a - (c == 2 ? 1 : 0))
                if (s + c <= n) r += d;
                else break;
              s += c;
            }
            return r;
          }));
      })(Ss)),
    Ss.exports
  );
}
var _E = SE();
const TE = pr(_E);
var _s, Ed;
function xE() {
  return (
    Ed ||
      ((Ed = 1),
      (_s = function () {
        return /\uD83C\uDFF4\uDB40\uDC67\uDB40\uDC62(?:\uDB40\uDC77\uDB40\uDC6C\uDB40\uDC73|\uDB40\uDC73\uDB40\uDC63\uDB40\uDC74|\uDB40\uDC65\uDB40\uDC6E\uDB40\uDC67)\uDB40\uDC7F|(?:\uD83E\uDDD1\uD83C\uDFFF\u200D\u2764\uFE0F\u200D(?:\uD83D\uDC8B\u200D)?\uD83E\uDDD1|\uD83D\uDC69\uD83C\uDFFF\u200D\uD83E\uDD1D\u200D(?:\uD83D[\uDC68\uDC69]))(?:\uD83C[\uDFFB-\uDFFE])|(?:\uD83E\uDDD1\uD83C\uDFFE\u200D\u2764\uFE0F\u200D(?:\uD83D\uDC8B\u200D)?\uD83E\uDDD1|\uD83D\uDC69\uD83C\uDFFE\u200D\uD83E\uDD1D\u200D(?:\uD83D[\uDC68\uDC69]))(?:\uD83C[\uDFFB-\uDFFD\uDFFF])|(?:\uD83E\uDDD1\uD83C\uDFFD\u200D\u2764\uFE0F\u200D(?:\uD83D\uDC8B\u200D)?\uD83E\uDDD1|\uD83D\uDC69\uD83C\uDFFD\u200D\uD83E\uDD1D\u200D(?:\uD83D[\uDC68\uDC69]))(?:\uD83C[\uDFFB\uDFFC\uDFFE\uDFFF])|(?:\uD83E\uDDD1\uD83C\uDFFC\u200D\u2764\uFE0F\u200D(?:\uD83D\uDC8B\u200D)?\uD83E\uDDD1|\uD83D\uDC69\uD83C\uDFFC\u200D\uD83E\uDD1D\u200D(?:\uD83D[\uDC68\uDC69]))(?:\uD83C[\uDFFB\uDFFD-\uDFFF])|(?:\uD83E\uDDD1\uD83C\uDFFB\u200D\u2764\uFE0F\u200D(?:\uD83D\uDC8B\u200D)?\uD83E\uDDD1|\uD83D\uDC69\uD83C\uDFFB\u200D\uD83E\uDD1D\u200D(?:\uD83D[\uDC68\uDC69]))(?:\uD83C[\uDFFC-\uDFFF])|\uD83D\uDC68(?:\uD83C\uDFFB(?:\u200D(?:\u2764\uFE0F\u200D(?:\uD83D\uDC8B\u200D\uD83D\uDC68(?:\uD83C[\uDFFB-\uDFFF])|\uD83D\uDC68(?:\uD83C[\uDFFB-\uDFFF]))|\uD83E\uDD1D\u200D\uD83D\uDC68(?:\uD83C[\uDFFC-\uDFFF])|[\u2695\u2696\u2708]\uFE0F|\uD83C[\uDF3E\uDF73\uDF7C\uDF93\uDFA4\uDFA8\uDFEB\uDFED]|\uD83D[\uDCBB\uDCBC\uDD27\uDD2C\uDE80\uDE92]|\uD83E[\uDDAF-\uDDB3\uDDBC\uDDBD]))?|(?:\uD83C[\uDFFC-\uDFFF])\u200D\u2764\uFE0F\u200D(?:\uD83D\uDC8B\u200D\uD83D\uDC68(?:\uD83C[\uDFFB-\uDFFF])|\uD83D\uDC68(?:\uD83C[\uDFFB-\uDFFF]))|\u200D(?:\u2764\uFE0F\u200D(?:\uD83D\uDC8B\u200D)?\uD83D\uDC68|(?:\uD83D[\uDC68\uDC69])\u200D(?:\uD83D\uDC66\u200D\uD83D\uDC66|\uD83D\uDC67\u200D(?:\uD83D[\uDC66\uDC67]))|\uD83D\uDC66\u200D\uD83D\uDC66|\uD83D\uDC67\u200D(?:\uD83D[\uDC66\uDC67])|\uD83C[\uDF3E\uDF73\uDF7C\uDF93\uDFA4\uDFA8\uDFEB\uDFED]|\uD83D[\uDCBB\uDCBC\uDD27\uDD2C\uDE80\uDE92]|\uD83E[\uDDAF-\uDDB3\uDDBC\uDDBD])|\uD83C\uDFFF\u200D(?:\uD83E\uDD1D\u200D\uD83D\uDC68(?:\uD83C[\uDFFB-\uDFFE])|\uD83C[\uDF3E\uDF73\uDF7C\uDF93\uDFA4\uDFA8\uDFEB\uDFED]|\uD83D[\uDCBB\uDCBC\uDD27\uDD2C\uDE80\uDE92]|\uD83E[\uDDAF-\uDDB3\uDDBC\uDDBD])|\uD83C\uDFFE\u200D(?:\uD83E\uDD1D\u200D\uD83D\uDC68(?:\uD83C[\uDFFB-\uDFFD\uDFFF])|\uD83C[\uDF3E\uDF73\uDF7C\uDF93\uDFA4\uDFA8\uDFEB\uDFED]|\uD83D[\uDCBB\uDCBC\uDD27\uDD2C\uDE80\uDE92]|\uD83E[\uDDAF-\uDDB3\uDDBC\uDDBD])|\uD83C\uDFFD\u200D(?:\uD83E\uDD1D\u200D\uD83D\uDC68(?:\uD83C[\uDFFB\uDFFC\uDFFE\uDFFF])|\uD83C[\uDF3E\uDF73\uDF7C\uDF93\uDFA4\uDFA8\uDFEB\uDFED]|\uD83D[\uDCBB\uDCBC\uDD27\uDD2C\uDE80\uDE92]|\uD83E[\uDDAF-\uDDB3\uDDBC\uDDBD])|\uD83C\uDFFC\u200D(?:\uD83E\uDD1D\u200D\uD83D\uDC68(?:\uD83C[\uDFFB\uDFFD-\uDFFF])|\uD83C[\uDF3E\uDF73\uDF7C\uDF93\uDFA4\uDFA8\uDFEB\uDFED]|\uD83D[\uDCBB\uDCBC\uDD27\uDD2C\uDE80\uDE92]|\uD83E[\uDDAF-\uDDB3\uDDBC\uDDBD])|(?:\uD83C\uDFFF\u200D[\u2695\u2696\u2708]|\uD83C\uDFFE\u200D[\u2695\u2696\u2708]|\uD83C\uDFFD\u200D[\u2695\u2696\u2708]|\uD83C\uDFFC\u200D[\u2695\u2696\u2708]|\u200D[\u2695\u2696\u2708])\uFE0F|\u200D(?:(?:\uD83D[\uDC68\uDC69])\u200D(?:\uD83D[\uDC66\uDC67])|\uD83D[\uDC66\uDC67])|\uD83C\uDFFF|\uD83C\uDFFE|\uD83C\uDFFD|\uD83C\uDFFC)?|(?:\uD83D\uDC69(?:\uD83C\uDFFB\u200D\u2764\uFE0F\u200D(?:\uD83D\uDC8B\u200D(?:\uD83D[\uDC68\uDC69])|\uD83D[\uDC68\uDC69])|(?:\uD83C[\uDFFC-\uDFFF])\u200D\u2764\uFE0F\u200D(?:\uD83D\uDC8B\u200D(?:\uD83D[\uDC68\uDC69])|\uD83D[\uDC68\uDC69]))|\uD83E\uDDD1(?:\uD83C[\uDFFB-\uDFFF])\u200D\uD83E\uDD1D\u200D\uD83E\uDDD1)(?:\uD83C[\uDFFB-\uDFFF])|\uD83D\uDC69\u200D\uD83D\uDC69\u200D(?:\uD83D\uDC66\u200D\uD83D\uDC66|\uD83D\uDC67\u200D(?:\uD83D[\uDC66\uDC67]))|\uD83D\uDC69(?:\u200D(?:\u2764\uFE0F\u200D(?:\uD83D\uDC8B\u200D(?:\uD83D[\uDC68\uDC69])|\uD83D[\uDC68\uDC69])|\uD83C[\uDF3E\uDF73\uDF7C\uDF93\uDFA4\uDFA8\uDFEB\uDFED]|\uD83D[\uDCBB\uDCBC\uDD27\uDD2C\uDE80\uDE92]|\uD83E[\uDDAF-\uDDB3\uDDBC\uDDBD])|\uD83C\uDFFF\u200D(?:\uD83C[\uDF3E\uDF73\uDF7C\uDF93\uDFA4\uDFA8\uDFEB\uDFED]|\uD83D[\uDCBB\uDCBC\uDD27\uDD2C\uDE80\uDE92]|\uD83E[\uDDAF-\uDDB3\uDDBC\uDDBD])|\uD83C\uDFFE\u200D(?:\uD83C[\uDF3E\uDF73\uDF7C\uDF93\uDFA4\uDFA8\uDFEB\uDFED]|\uD83D[\uDCBB\uDCBC\uDD27\uDD2C\uDE80\uDE92]|\uD83E[\uDDAF-\uDDB3\uDDBC\uDDBD])|\uD83C\uDFFD\u200D(?:\uD83C[\uDF3E\uDF73\uDF7C\uDF93\uDFA4\uDFA8\uDFEB\uDFED]|\uD83D[\uDCBB\uDCBC\uDD27\uDD2C\uDE80\uDE92]|\uD83E[\uDDAF-\uDDB3\uDDBC\uDDBD])|\uD83C\uDFFC\u200D(?:\uD83C[\uDF3E\uDF73\uDF7C\uDF93\uDFA4\uDFA8\uDFEB\uDFED]|\uD83D[\uDCBB\uDCBC\uDD27\uDD2C\uDE80\uDE92]|\uD83E[\uDDAF-\uDDB3\uDDBC\uDDBD])|\uD83C\uDFFB\u200D(?:\uD83C[\uDF3E\uDF73\uDF7C\uDF93\uDFA4\uDFA8\uDFEB\uDFED]|\uD83D[\uDCBB\uDCBC\uDD27\uDD2C\uDE80\uDE92]|\uD83E[\uDDAF-\uDDB3\uDDBC\uDDBD]))|\uD83E\uDDD1(?:\u200D(?:\uD83E\uDD1D\u200D\uD83E\uDDD1|\uD83C[\uDF3E\uDF73\uDF7C\uDF84\uDF93\uDFA4\uDFA8\uDFEB\uDFED]|\uD83D[\uDCBB\uDCBC\uDD27\uDD2C\uDE80\uDE92]|\uD83E[\uDDAF-\uDDB3\uDDBC\uDDBD])|\uD83C\uDFFF\u200D(?:\uD83C[\uDF3E\uDF73\uDF7C\uDF84\uDF93\uDFA4\uDFA8\uDFEB\uDFED]|\uD83D[\uDCBB\uDCBC\uDD27\uDD2C\uDE80\uDE92]|\uD83E[\uDDAF-\uDDB3\uDDBC\uDDBD])|\uD83C\uDFFE\u200D(?:\uD83C[\uDF3E\uDF73\uDF7C\uDF84\uDF93\uDFA4\uDFA8\uDFEB\uDFED]|\uD83D[\uDCBB\uDCBC\uDD27\uDD2C\uDE80\uDE92]|\uD83E[\uDDAF-\uDDB3\uDDBC\uDDBD])|\uD83C\uDFFD\u200D(?:\uD83C[\uDF3E\uDF73\uDF7C\uDF84\uDF93\uDFA4\uDFA8\uDFEB\uDFED]|\uD83D[\uDCBB\uDCBC\uDD27\uDD2C\uDE80\uDE92]|\uD83E[\uDDAF-\uDDB3\uDDBC\uDDBD])|\uD83C\uDFFC\u200D(?:\uD83C[\uDF3E\uDF73\uDF7C\uDF84\uDF93\uDFA4\uDFA8\uDFEB\uDFED]|\uD83D[\uDCBB\uDCBC\uDD27\uDD2C\uDE80\uDE92]|\uD83E[\uDDAF-\uDDB3\uDDBC\uDDBD])|\uD83C\uDFFB\u200D(?:\uD83C[\uDF3E\uDF73\uDF7C\uDF84\uDF93\uDFA4\uDFA8\uDFEB\uDFED]|\uD83D[\uDCBB\uDCBC\uDD27\uDD2C\uDE80\uDE92]|\uD83E[\uDDAF-\uDDB3\uDDBC\uDDBD]))|\uD83D\uDC69\u200D\uD83D\uDC66\u200D\uD83D\uDC66|\uD83D\uDC69\u200D\uD83D\uDC69\u200D(?:\uD83D[\uDC66\uDC67])|\uD83D\uDC69\u200D\uD83D\uDC67\u200D(?:\uD83D[\uDC66\uDC67])|(?:\uD83D\uDC41\uFE0F\u200D\uD83D\uDDE8|\uD83E\uDDD1(?:\uD83C\uDFFF\u200D[\u2695\u2696\u2708]|\uD83C\uDFFE\u200D[\u2695\u2696\u2708]|\uD83C\uDFFD\u200D[\u2695\u2696\u2708]|\uD83C\uDFFC\u200D[\u2695\u2696\u2708]|\uD83C\uDFFB\u200D[\u2695\u2696\u2708]|\u200D[\u2695\u2696\u2708])|\uD83D\uDC69(?:\uD83C\uDFFF\u200D[\u2695\u2696\u2708]|\uD83C\uDFFE\u200D[\u2695\u2696\u2708]|\uD83C\uDFFD\u200D[\u2695\u2696\u2708]|\uD83C\uDFFC\u200D[\u2695\u2696\u2708]|\uD83C\uDFFB\u200D[\u2695\u2696\u2708]|\u200D[\u2695\u2696\u2708])|\uD83D\uDE36\u200D\uD83C\uDF2B|\uD83C\uDFF3\uFE0F\u200D\u26A7|\uD83D\uDC3B\u200D\u2744|(?:(?:\uD83C[\uDFC3\uDFC4\uDFCA]|\uD83D[\uDC6E\uDC70\uDC71\uDC73\uDC77\uDC81\uDC82\uDC86\uDC87\uDE45-\uDE47\uDE4B\uDE4D\uDE4E\uDEA3\uDEB4-\uDEB6]|\uD83E[\uDD26\uDD35\uDD37-\uDD39\uDD3D\uDD3E\uDDB8\uDDB9\uDDCD-\uDDCF\uDDD4\uDDD6-\uDDDD])(?:\uD83C[\uDFFB-\uDFFF])|\uD83D\uDC6F|\uD83E[\uDD3C\uDDDE\uDDDF])\u200D[\u2640\u2642]|(?:\u26F9|\uD83C[\uDFCB\uDFCC]|\uD83D\uDD75)(?:\uFE0F|\uD83C[\uDFFB-\uDFFF])\u200D[\u2640\u2642]|\uD83C\uDFF4\u200D\u2620|(?:\uD83C[\uDFC3\uDFC4\uDFCA]|\uD83D[\uDC6E\uDC70\uDC71\uDC73\uDC77\uDC81\uDC82\uDC86\uDC87\uDE45-\uDE47\uDE4B\uDE4D\uDE4E\uDEA3\uDEB4-\uDEB6]|\uD83E[\uDD26\uDD35\uDD37-\uDD39\uDD3D\uDD3E\uDDB8\uDDB9\uDDCD-\uDDCF\uDDD4\uDDD6-\uDDDD])\u200D[\u2640\u2642]|[\xA9\xAE\u203C\u2049\u2122\u2139\u2194-\u2199\u21A9\u21AA\u2328\u23CF\u23ED-\u23EF\u23F1\u23F2\u23F8-\u23FA\u24C2\u25AA\u25AB\u25B6\u25C0\u25FB\u25FC\u2600-\u2604\u260E\u2611\u2618\u2620\u2622\u2623\u2626\u262A\u262E\u262F\u2638-\u263A\u2640\u2642\u265F\u2660\u2663\u2665\u2666\u2668\u267B\u267E\u2692\u2694-\u2697\u2699\u269B\u269C\u26A0\u26A7\u26B0\u26B1\u26C8\u26CF\u26D1\u26D3\u26E9\u26F0\u26F1\u26F4\u26F7\u26F8\u2702\u2708\u2709\u270F\u2712\u2714\u2716\u271D\u2721\u2733\u2734\u2744\u2747\u2763\u27A1\u2934\u2935\u2B05-\u2B07\u3030\u303D\u3297\u3299]|\uD83C[\uDD70\uDD71\uDD7E\uDD7F\uDE02\uDE37\uDF21\uDF24-\uDF2C\uDF36\uDF7D\uDF96\uDF97\uDF99-\uDF9B\uDF9E\uDF9F\uDFCD\uDFCE\uDFD4-\uDFDF\uDFF5\uDFF7]|\uD83D[\uDC3F\uDCFD\uDD49\uDD4A\uDD6F\uDD70\uDD73\uDD76-\uDD79\uDD87\uDD8A-\uDD8D\uDDA5\uDDA8\uDDB1\uDDB2\uDDBC\uDDC2-\uDDC4\uDDD1-\uDDD3\uDDDC-\uDDDE\uDDE1\uDDE3\uDDE8\uDDEF\uDDF3\uDDFA\uDECB\uDECD-\uDECF\uDEE0-\uDEE5\uDEE9\uDEF0\uDEF3])\uFE0F|\uD83C\uDFF3\uFE0F\u200D\uD83C\uDF08|\uD83D\uDC69\u200D\uD83D\uDC67|\uD83D\uDC69\u200D\uD83D\uDC66|\uD83D\uDE35\u200D\uD83D\uDCAB|\uD83D\uDE2E\u200D\uD83D\uDCA8|\uD83D\uDC15\u200D\uD83E\uDDBA|\uD83E\uDDD1(?:\uD83C\uDFFF|\uD83C\uDFFE|\uD83C\uDFFD|\uD83C\uDFFC|\uD83C\uDFFB)?|\uD83D\uDC69(?:\uD83C\uDFFF|\uD83C\uDFFE|\uD83C\uDFFD|\uD83C\uDFFC|\uD83C\uDFFB)?|\uD83C\uDDFD\uD83C\uDDF0|\uD83C\uDDF6\uD83C\uDDE6|\uD83C\uDDF4\uD83C\uDDF2|\uD83D\uDC08\u200D\u2B1B|\u2764\uFE0F\u200D(?:\uD83D\uDD25|\uD83E\uDE79)|\uD83D\uDC41\uFE0F|\uD83C\uDFF3\uFE0F|\uD83C\uDDFF(?:\uD83C[\uDDE6\uDDF2\uDDFC])|\uD83C\uDDFE(?:\uD83C[\uDDEA\uDDF9])|\uD83C\uDDFC(?:\uD83C[\uDDEB\uDDF8])|\uD83C\uDDFB(?:\uD83C[\uDDE6\uDDE8\uDDEA\uDDEC\uDDEE\uDDF3\uDDFA])|\uD83C\uDDFA(?:\uD83C[\uDDE6\uDDEC\uDDF2\uDDF3\uDDF8\uDDFE\uDDFF])|\uD83C\uDDF9(?:\uD83C[\uDDE6\uDDE8\uDDE9\uDDEB-\uDDED\uDDEF-\uDDF4\uDDF7\uDDF9\uDDFB\uDDFC\uDDFF])|\uD83C\uDDF8(?:\uD83C[\uDDE6-\uDDEA\uDDEC-\uDDF4\uDDF7-\uDDF9\uDDFB\uDDFD-\uDDFF])|\uD83C\uDDF7(?:\uD83C[\uDDEA\uDDF4\uDDF8\uDDFA\uDDFC])|\uD83C\uDDF5(?:\uD83C[\uDDE6\uDDEA-\uDDED\uDDF0-\uDDF3\uDDF7-\uDDF9\uDDFC\uDDFE])|\uD83C\uDDF3(?:\uD83C[\uDDE6\uDDE8\uDDEA-\uDDEC\uDDEE\uDDF1\uDDF4\uDDF5\uDDF7\uDDFA\uDDFF])|\uD83C\uDDF2(?:\uD83C[\uDDE6\uDDE8-\uDDED\uDDF0-\uDDFF])|\uD83C\uDDF1(?:\uD83C[\uDDE6-\uDDE8\uDDEE\uDDF0\uDDF7-\uDDFB\uDDFE])|\uD83C\uDDF0(?:\uD83C[\uDDEA\uDDEC-\uDDEE\uDDF2\uDDF3\uDDF5\uDDF7\uDDFC\uDDFE\uDDFF])|\uD83C\uDDEF(?:\uD83C[\uDDEA\uDDF2\uDDF4\uDDF5])|\uD83C\uDDEE(?:\uD83C[\uDDE8-\uDDEA\uDDF1-\uDDF4\uDDF6-\uDDF9])|\uD83C\uDDED(?:\uD83C[\uDDF0\uDDF2\uDDF3\uDDF7\uDDF9\uDDFA])|\uD83C\uDDEC(?:\uD83C[\uDDE6\uDDE7\uDDE9-\uDDEE\uDDF1-\uDDF3\uDDF5-\uDDFA\uDDFC\uDDFE])|\uD83C\uDDEB(?:\uD83C[\uDDEE-\uDDF0\uDDF2\uDDF4\uDDF7])|\uD83C\uDDEA(?:\uD83C[\uDDE6\uDDE8\uDDEA\uDDEC\uDDED\uDDF7-\uDDFA])|\uD83C\uDDE9(?:\uD83C[\uDDEA\uDDEC\uDDEF\uDDF0\uDDF2\uDDF4\uDDFF])|\uD83C\uDDE8(?:\uD83C[\uDDE6\uDDE8\uDDE9\uDDEB-\uDDEE\uDDF0-\uDDF5\uDDF7\uDDFA-\uDDFF])|\uD83C\uDDE7(?:\uD83C[\uDDE6\uDDE7\uDDE9-\uDDEF\uDDF1-\uDDF4\uDDF6-\uDDF9\uDDFB\uDDFC\uDDFE\uDDFF])|\uD83C\uDDE6(?:\uD83C[\uDDE8-\uDDEC\uDDEE\uDDF1\uDDF2\uDDF4\uDDF6-\uDDFA\uDDFC\uDDFD\uDDFF])|[#\*0-9]\uFE0F\u20E3|\u2764\uFE0F|(?:\uD83C[\uDFC3\uDFC4\uDFCA]|\uD83D[\uDC6E\uDC70\uDC71\uDC73\uDC77\uDC81\uDC82\uDC86\uDC87\uDE45-\uDE47\uDE4B\uDE4D\uDE4E\uDEA3\uDEB4-\uDEB6]|\uD83E[\uDD26\uDD35\uDD37-\uDD39\uDD3D\uDD3E\uDDB8\uDDB9\uDDCD-\uDDCF\uDDD4\uDDD6-\uDDDD])(?:\uD83C[\uDFFB-\uDFFF])|(?:\u26F9|\uD83C[\uDFCB\uDFCC]|\uD83D\uDD75)(?:\uFE0F|\uD83C[\uDFFB-\uDFFF])|\uD83C\uDFF4|(?:[\u270A\u270B]|\uD83C[\uDF85\uDFC2\uDFC7]|\uD83D[\uDC42\uDC43\uDC46-\uDC50\uDC66\uDC67\uDC6B-\uDC6D\uDC72\uDC74-\uDC76\uDC78\uDC7C\uDC83\uDC85\uDC8F\uDC91\uDCAA\uDD7A\uDD95\uDD96\uDE4C\uDE4F\uDEC0\uDECC]|\uD83E[\uDD0C\uDD0F\uDD18-\uDD1C\uDD1E\uDD1F\uDD30-\uDD34\uDD36\uDD77\uDDB5\uDDB6\uDDBB\uDDD2\uDDD3\uDDD5])(?:\uD83C[\uDFFB-\uDFFF])|(?:[\u261D\u270C\u270D]|\uD83D[\uDD74\uDD90])(?:\uFE0F|\uD83C[\uDFFB-\uDFFF])|[\u270A\u270B]|\uD83C[\uDF85\uDFC2\uDFC7]|\uD83D[\uDC08\uDC15\uDC3B\uDC42\uDC43\uDC46-\uDC50\uDC66\uDC67\uDC6B-\uDC6D\uDC72\uDC74-\uDC76\uDC78\uDC7C\uDC83\uDC85\uDC8F\uDC91\uDCAA\uDD7A\uDD95\uDD96\uDE2E\uDE35\uDE36\uDE4C\uDE4F\uDEC0\uDECC]|\uD83E[\uDD0C\uDD0F\uDD18-\uDD1C\uDD1E\uDD1F\uDD30-\uDD34\uDD36\uDD77\uDDB5\uDDB6\uDDBB\uDDD2\uDDD3\uDDD5]|\uD83C[\uDFC3\uDFC4\uDFCA]|\uD83D[\uDC6E\uDC70\uDC71\uDC73\uDC77\uDC81\uDC82\uDC86\uDC87\uDE45-\uDE47\uDE4B\uDE4D\uDE4E\uDEA3\uDEB4-\uDEB6]|\uD83E[\uDD26\uDD35\uDD37-\uDD39\uDD3D\uDD3E\uDDB8\uDDB9\uDDCD-\uDDCF\uDDD4\uDDD6-\uDDDD]|\uD83D\uDC6F|\uD83E[\uDD3C\uDDDE\uDDDF]|[\u231A\u231B\u23E9-\u23EC\u23F0\u23F3\u25FD\u25FE\u2614\u2615\u2648-\u2653\u267F\u2693\u26A1\u26AA\u26AB\u26BD\u26BE\u26C4\u26C5\u26CE\u26D4\u26EA\u26F2\u26F3\u26F5\u26FA\u26FD\u2705\u2728\u274C\u274E\u2753-\u2755\u2757\u2795-\u2797\u27B0\u27BF\u2B1B\u2B1C\u2B50\u2B55]|\uD83C[\uDC04\uDCCF\uDD8E\uDD91-\uDD9A\uDE01\uDE1A\uDE2F\uDE32-\uDE36\uDE38-\uDE3A\uDE50\uDE51\uDF00-\uDF20\uDF2D-\uDF35\uDF37-\uDF7C\uDF7E-\uDF84\uDF86-\uDF93\uDFA0-\uDFC1\uDFC5\uDFC6\uDFC8\uDFC9\uDFCF-\uDFD3\uDFE0-\uDFF0\uDFF8-\uDFFF]|\uD83D[\uDC00-\uDC07\uDC09-\uDC14\uDC16-\uDC3A\uDC3C-\uDC3E\uDC40\uDC44\uDC45\uDC51-\uDC65\uDC6A\uDC79-\uDC7B\uDC7D-\uDC80\uDC84\uDC88-\uDC8E\uDC90\uDC92-\uDCA9\uDCAB-\uDCFC\uDCFF-\uDD3D\uDD4B-\uDD4E\uDD50-\uDD67\uDDA4\uDDFB-\uDE2D\uDE2F-\uDE34\uDE37-\uDE44\uDE48-\uDE4A\uDE80-\uDEA2\uDEA4-\uDEB3\uDEB7-\uDEBF\uDEC1-\uDEC5\uDED0-\uDED2\uDED5-\uDED7\uDEEB\uDEEC\uDEF4-\uDEFC\uDFE0-\uDFEB]|\uD83E[\uDD0D\uDD0E\uDD10-\uDD17\uDD1D\uDD20-\uDD25\uDD27-\uDD2F\uDD3A\uDD3F-\uDD45\uDD47-\uDD76\uDD78\uDD7A-\uDDB4\uDDB7\uDDBA\uDDBC-\uDDCB\uDDD0\uDDE0-\uDDFF\uDE70-\uDE74\uDE78-\uDE7A\uDE80-\uDE86\uDE90-\uDEA8\uDEB0-\uDEB6\uDEC0-\uDEC2\uDED0-\uDED6]|(?:[\u231A\u231B\u23E9-\u23EC\u23F0\u23F3\u25FD\u25FE\u2614\u2615\u2648-\u2653\u267F\u2693\u26A1\u26AA\u26AB\u26BD\u26BE\u26C4\u26C5\u26CE\u26D4\u26EA\u26F2\u26F3\u26F5\u26FA\u26FD\u2705\u270A\u270B\u2728\u274C\u274E\u2753-\u2755\u2757\u2795-\u2797\u27B0\u27BF\u2B1B\u2B1C\u2B50\u2B55]|\uD83C[\uDC04\uDCCF\uDD8E\uDD91-\uDD9A\uDDE6-\uDDFF\uDE01\uDE1A\uDE2F\uDE32-\uDE36\uDE38-\uDE3A\uDE50\uDE51\uDF00-\uDF20\uDF2D-\uDF35\uDF37-\uDF7C\uDF7E-\uDF93\uDFA0-\uDFCA\uDFCF-\uDFD3\uDFE0-\uDFF0\uDFF4\uDFF8-\uDFFF]|\uD83D[\uDC00-\uDC3E\uDC40\uDC42-\uDCFC\uDCFF-\uDD3D\uDD4B-\uDD4E\uDD50-\uDD67\uDD7A\uDD95\uDD96\uDDA4\uDDFB-\uDE4F\uDE80-\uDEC5\uDECC\uDED0-\uDED2\uDED5-\uDED7\uDEEB\uDEEC\uDEF4-\uDEFC\uDFE0-\uDFEB]|\uD83E[\uDD0C-\uDD3A\uDD3C-\uDD45\uDD47-\uDD78\uDD7A-\uDDCB\uDDCD-\uDDFF\uDE70-\uDE74\uDE78-\uDE7A\uDE80-\uDE86\uDE90-\uDEA8\uDEB0-\uDEB6\uDEC0-\uDEC2\uDED0-\uDED6])|(?:[#\*0-9\xA9\xAE\u203C\u2049\u2122\u2139\u2194-\u2199\u21A9\u21AA\u231A\u231B\u2328\u23CF\u23E9-\u23F3\u23F8-\u23FA\u24C2\u25AA\u25AB\u25B6\u25C0\u25FB-\u25FE\u2600-\u2604\u260E\u2611\u2614\u2615\u2618\u261D\u2620\u2622\u2623\u2626\u262A\u262E\u262F\u2638-\u263A\u2640\u2642\u2648-\u2653\u265F\u2660\u2663\u2665\u2666\u2668\u267B\u267E\u267F\u2692-\u2697\u2699\u269B\u269C\u26A0\u26A1\u26A7\u26AA\u26AB\u26B0\u26B1\u26BD\u26BE\u26C4\u26C5\u26C8\u26CE\u26CF\u26D1\u26D3\u26D4\u26E9\u26EA\u26F0-\u26F5\u26F7-\u26FA\u26FD\u2702\u2705\u2708-\u270D\u270F\u2712\u2714\u2716\u271D\u2721\u2728\u2733\u2734\u2744\u2747\u274C\u274E\u2753-\u2755\u2757\u2763\u2764\u2795-\u2797\u27A1\u27B0\u27BF\u2934\u2935\u2B05-\u2B07\u2B1B\u2B1C\u2B50\u2B55\u3030\u303D\u3297\u3299]|\uD83C[\uDC04\uDCCF\uDD70\uDD71\uDD7E\uDD7F\uDD8E\uDD91-\uDD9A\uDDE6-\uDDFF\uDE01\uDE02\uDE1A\uDE2F\uDE32-\uDE3A\uDE50\uDE51\uDF00-\uDF21\uDF24-\uDF93\uDF96\uDF97\uDF99-\uDF9B\uDF9E-\uDFF0\uDFF3-\uDFF5\uDFF7-\uDFFF]|\uD83D[\uDC00-\uDCFD\uDCFF-\uDD3D\uDD49-\uDD4E\uDD50-\uDD67\uDD6F\uDD70\uDD73-\uDD7A\uDD87\uDD8A-\uDD8D\uDD90\uDD95\uDD96\uDDA4\uDDA5\uDDA8\uDDB1\uDDB2\uDDBC\uDDC2-\uDDC4\uDDD1-\uDDD3\uDDDC-\uDDDE\uDDE1\uDDE3\uDDE8\uDDEF\uDDF3\uDDFA-\uDE4F\uDE80-\uDEC5\uDECB-\uDED2\uDED5-\uDED7\uDEE0-\uDEE5\uDEE9\uDEEB\uDEEC\uDEF0\uDEF3-\uDEFC\uDFE0-\uDFEB]|\uD83E[\uDD0C-\uDD3A\uDD3C-\uDD45\uDD47-\uDD78\uDD7A-\uDDCB\uDDCD-\uDDFF\uDE70-\uDE74\uDE78-\uDE7A\uDE80-\uDE86\uDE90-\uDEA8\uDEB0-\uDEB6\uDEC0-\uDEC2\uDED0-\uDED6])\uFE0F|(?:[\u261D\u26F9\u270A-\u270D]|\uD83C[\uDF85\uDFC2-\uDFC4\uDFC7\uDFCA-\uDFCC]|\uD83D[\uDC42\uDC43\uDC46-\uDC50\uDC66-\uDC78\uDC7C\uDC81-\uDC83\uDC85-\uDC87\uDC8F\uDC91\uDCAA\uDD74\uDD75\uDD7A\uDD90\uDD95\uDD96\uDE45-\uDE47\uDE4B-\uDE4F\uDEA3\uDEB4-\uDEB6\uDEC0\uDECC]|\uD83E[\uDD0C\uDD0F\uDD18-\uDD1F\uDD26\uDD30-\uDD39\uDD3C-\uDD3E\uDD77\uDDB5\uDDB6\uDDB8\uDDB9\uDDBB\uDDCD-\uDDCF\uDDD1-\uDDDD])/g;
      })),
    _s
  );
}
var NE = xE();
const IE = pr(NE);
function qi(e, t = {}) {
  if (
    typeof e != "string" ||
    e.length === 0 ||
    ((t = { ambiguousIsNarrow: !0, ...t }), (e = FE(e)), e.length === 0)
  )
    return 0;
  e = e.replace(IE(), "  ");
  const o = t.ambiguousIsNarrow ? 1 : 2;
  let i = 0;
  for (const a of e) {
    const n = a.codePointAt(0);
    if (n <= 31 || (n >= 127 && n <= 159) || (n >= 768 && n <= 879)) continue;
    switch (TE.eastAsianWidth(a)) {
      case "F":
      case "W":
        i += 2;
        break;
      case "A":
        i += o;
        break;
      default:
        i += 1;
    }
  }
  return i;
}
function $i(e, t, o) {
  if (e.charAt(t) === " ") return t;
  for (let i = 1; i <= 3; i++)
    if (o) {
      if (e.charAt(t + i) === " ") return t + i;
    } else if (e.charAt(t - i) === " ") return t - i;
  return t;
}
function OE(e, t, o) {
  o = {
    position: "end",
    preferTruncationOnSpace: !1,
    truncationCharacter: "…",
    ...o,
  };
  const { position: i, space: a, preferTruncationOnSpace: n } = o;
  let { truncationCharacter: r } = o;
  if (typeof e != "string")
    throw new TypeError(`Expected \`input\` to be a string, got ${typeof e}`);
  const s = qi(e);
  if (s <= t) return e;
  if (i === "start") {
    if (n) {
      const u = $i(e, s - t + 1, !0);
      return r + ir(e, u, s).trim();
    }
    return (a === !0 && (r += " "), r + ir(e, s - t + qi(r), s));
  }
  if (i === "middle") {
    a === !0 && (r = ` ${r} `);
    const u = Math.floor(t / 2);
    if (n) {
      const f = $i(e, u),
        d = $i(e, s - (t - u) + 1, !0);
      return ir(e, 0, f) + r + ir(e, d, s).trim();
    }
    return ir(e, 0, u) + r + ir(e, s - (t - u) + qi(r), s);
  }
  if (i === "end") {
    if (n) {
      const u = $i(e, t - 1);
      return ir(e, 0, u) + r;
    }
    return (a === !0 && (r = ` ${r}`), ir(e, 0, t - qi(r)) + r);
  }
  throw new Error(
    `Expected \`options.position\` to be either \`start\`, \`middle\` or \`end\`, got ${i}`,
  );
}
const PE = (e) => {
    let t;
    return e
      .filter((o) => o && (o.visible ?? !0))
      .filter((o, i, a) => {
        const n =
          o.type === "separator" &&
          (!t || i === a.length - 1 || a[i + 1].type === "separator");
        return ((t = n ? t : o), !n);
      });
  },
  RE = (e, t) => {
    if (!e.webContents.on) return;
    const o = async (i, a) => {
      if (typeof t.shouldShowMenu == "function" && !t.shouldShowMenu(i, a))
        return;
      const { editFlags: n } = a,
        r = a.selectionText.length > 0,
        s = !!a.linkURL,
        u = (b) => n[`can${b}`] && r,
        f = {
          separator: () => ({ type: "separator" }),
          learnSpelling: () => ({
            id: "learnSpelling",
            label: "&Learn Spelling",
            visible: !!(a.isEditable && r && a.misspelledWord),
            click() {
              e.webContents.session.addWordToSpellCheckerDictionary(
                a.misspelledWord,
              );
            },
          }),
          lookUpSelection: () => ({
            id: "lookUpSelection",
            label: "Look Up “{selection}”",
            visible: process.platform === "darwin" && r && !s,
            click() {
              process.platform === "darwin" &&
                e.webContents.showDefinitionForSelection();
            },
          }),
          searchWithGoogle: () => ({
            id: "searchWithGoogle",
            label: "&Search with Google",
            visible: r,
            click() {
              const b = new URL("https://www.google.com/search");
              (b.searchParams.set("q", a.selectionText),
                Dt.openExternal(b.toString()));
            },
          }),
          cut: () => ({
            id: "cut",
            label: "Cu&t",
            enabled: u("Cut"),
            visible: a.isEditable,
            click() {
              e.webContents.cut();
            },
          }),
          copy: () => ({
            id: "copy",
            label: "&Copy",
            enabled: u("Copy"),
            visible: a.isEditable || r,
            click() {
              e.webContents.copy();
            },
          }),
          paste: () => ({
            id: "paste",
            label: "&Paste",
            enabled: n.canPaste,
            visible: a.isEditable,
            click() {
              e.webContents.paste();
            },
          }),
          selectAll: () => ({
            id: "selectAll",
            label: "Select &All",
            click() {
              e.webContents.selectAll();
            },
          }),
          saveImage: () => ({
            id: "saveImage",
            label: "Save I&mage",
            visible: a.mediaType === "image",
            click() {
              mainWindow?.rs.downloadFile(a.srcURL);
            },
          }),
          saveVideo: () => ({
            id: "saveVideo",
            label: "Save Vide&o",
            visible: a.mediaType === "video",
            click() {
              mainWindow?.rs.downloadFile(a.srcURL);
            },
          }),
          copyLink: () => ({
            id: "copyLink",
            label: "Copy Lin&k",
            visible: a.linkURL.length > 0 && a.mediaType === "none",
            click() {
              sa(ua(a.linkURL, a.linkText));
            },
          }),
          saveLinkAs: () => ({
            id: "saveLink",
            label: "Save Link",
            visible: a.linkURL.length > 0 && a.mediaType === "none",
            click() {
              mainWindow?.rs.downloadFile(a.linkURL);
            },
          }),
          copyImage: () => ({
            id: "copyImage",
            label: "Cop&y Image",
            visible: a.mediaType === "image",
            click() {
              e.webContents.copyImageAt(a.x, a.y);
            },
          }),
          copyImageAddress: () => ({
            id: "copyImageAddress",
            label: "C&opy Image Address",
            visible: a.mediaType === "image",
            click() {
              sa(ua(a.srcURL, a.srcURL));
            },
          }),
          copyVideoAddress: () => ({
            id: "copyVideoAddress",
            label: "Copy Video Ad&dress",
            visible: a.mediaType === "video",
            click() {
              sa(ua(a.srcURL, a.srcURL));
            },
          }),
          inspect: () => ({
            id: "inspect",
            label: "I&nspect Element",
            click() {
              (e.webContents.inspectElement(a.x, a.y),
                e.webContents.isDevToolsOpened() &&
                  e.webContents.devToolsWebContents?.focus());
            },
          }),
          services: () => ({
            id: "services",
            label: "Services",
            role: "services",
            visible: process.platform === "darwin" && (a.isEditable || r),
          }),
        },
        d =
          typeof t.showInspectElement == "boolean" ? t.showInspectElement : Pr,
        c =
          t.showSelectAll || (t.showSelectAll && process.platform !== "darwin");
      function l(b) {
        return {
          id: "dictionarySuggestions",
          label: b,
          visible: !!(a.isEditable && r && a.misspelledWord),
          click(w) {
            e.webContents.replaceMisspelling(w.label);
          },
        };
      }
      let h = [];
      r && a.misspelledWord && a.dictionarySuggestions.length > 0
        ? (h = a.dictionarySuggestions.map((b) => l(b)))
        : h.push({
            id: "dictionarySuggestions",
            label: "No Guesses Found",
            visible: !!(r && a.misspelledWord),
            enabled: !1,
          });
      const y = a.selectionText?.trim().length > 0,
        F = a.isEditable || r;
      let m = !1;
      if (y && F)
        try {
          m = !!(await mainWindow?.rs.canClearFormatting());
        } catch (b) {
          console.warn("Failed to check Tiptap formatting:", b);
        }
      const S = m
        ? [
            {
              id: "clearFormatting",
              label: "Clear Formatting",
              click() {
                mainWindow?.rs.clearFormatting();
              },
            },
            f.separator(),
          ]
        : [];
      let E = [
        h.length > 0 && f.separator(),
        ...S,
        ...h,
        f.separator(),
        f.learnSpelling(),
        f.separator(),
        f.lookUpSelection(),
        f.separator(),
        f.searchWithGoogle(),
        f.separator(),
        f.cut(),
        f.copy(),
        f.paste(),
        c && f.selectAll(),
        f.separator(),
        f.saveImage(),
        f.copyImage(),
        t.showCopyImageAddress && f.copyImageAddress(),
        f.saveVideo(),
        t.showCopyVideoAddress && f.copyVideoAddress(),
        f.separator(),
        f.copyLink(),
        t.showSaveLinkAs && f.saveLinkAs(),
        f.separator(),
        d && f.inspect(),
        t.showServices && f.services(),
        f.separator(),
      ];
      if ((t.menu && (E = t.menu(f, a, e, h, i)), t.prepend)) {
        const b = t.prepend(f, a, e, i);
        Array.isArray(b) && E.unshift(...b);
      }
      if (t.append) {
        const b = t.append(f, a, e, i);
        Array.isArray(b) && E.push(...b);
      }
      E = PE(E);
      for (const b of E)
        if (
          (b.id && t.labels?.[b.id] && (b.label = t.labels[b.id]),
          typeof b.label == "string" && b.label.includes("{selection}"))
        ) {
          const w =
            typeof a.selectionText == "string" ? a.selectionText.trim() : "";
          b.label = b.label.replace(
            "{selection}",
            OE(w, 25).replace(/&/g, "&&"),
          );
        }
      if (E.length > 0) {
        const b = lr.buildFromTemplate(E);
        (typeof t.onShow == "function" && b.on("menu-will-show", t.onShow),
          typeof t.onClose == "function" && b.on("menu-will-close", t.onClose),
          b.popup({ window: e, frame: a.frame ?? void 0 }));
      }
    };
    return (
      e.webContents.on("context-menu", o),
      () => {
        e.isDestroyed() || e.webContents.removeListener("context-menu", o);
      }
    );
  };
function vd(e) {
  let t = !1;
  const o = [],
    i = (r) => {
      if (t) return;
      const s = RE(r, e);
      s && o.push(s);
      const u = () => {
        if (!s) return;
        const f = o.indexOf(s);
        f !== -1 && o.splice(f, 1);
      };
      (typeof r.once < "u" && r.once("closed", u),
        o.push(() => {
          r.off("closed", u);
        }));
    },
    a = () => {
      for (const r of o) r();
      ((o.length = 0), (t = !0));
    },
    n = e.window;
  return (n && i(n), a);
}
ye.setAsDefaultProtocolClient(Pg.slice(0, -3));
const LE = ["thread-info-", "modal-", "prefs-"];
function BE(e) {
  return LE.some((t) => e.startsWith(t))
    ? null
    : e.startsWith("thread-")
      ? "pop-out-thread"
      : e === "media-viewer"
        ? "media-viewer"
        : null;
}
class kE {
  constructor(t, o) {
    ((this.windowId = t),
      (this.window = o),
      (this.closeConfirmation = null),
      (this.isConfirmingClose = !1),
      (this.wsk = (() => {
        const i = BE(this.windowId);
        return i ? ep(i) : null;
      })()),
      this.wsk &&
        this.wsk.manage(this.window, this.wsk.hasSavedState, { sizeOnly: !0 }),
      this.window.on("close", (i) => {
        const a = this.closeConfirmation;
        a &&
          (i.preventDefault(),
          !this.isConfirmingClose &&
            ((this.isConfirmingClose = !0),
            Xe.showMessageBox(this.window, {
              type: "warning",
              buttons: [a.cancelButtonText, a.confirmButtonText],
              defaultId: 1,
              cancelId: 0,
              message: a.title,
              detail: a.detail,
            })
              .then(({ response: n }) => {
                ((this.isConfirmingClose = !1),
                  n === 1 &&
                    ((this.closeConfirmation = null), this.window.close()));
              })
              .catch(() => {
                this.isConfirmingClose = !1;
              })));
      }),
      this.window.show(),
      Re?.TrafficLightManager &&
        ((this.trafficLightManager = new Re.TrafficLightManager()),
        this.trafficLightManager.attachToWindow(o.getNativeWindowHandle())));
  }
  moveTrafficLights(t, o, i) {
    this.trafficLightManager?.moveTrafficLights(t, o, i);
  }
  setCloseConfirmation(t) {
    this.closeConfirmation = t;
  }
  show() {
    (this.window.isMinimized() && this.window.restore(), this.window.show());
  }
  hide() {
    this.window.hide();
  }
}
const ME = Mo($h),
  UE = async () => {
    if (Ne) return Re?.is24HourFormat() ? Ih : No;
    if (Kt)
      try {
        const e = await qE();
        return (logger.log(`[getTimeFormat]: ${e}`), e);
      } catch (e) {
        logger.error("[getTimeFormat] Error fetching time format:", e);
      }
    return No;
  },
  qE = async () => {
    try {
      const { stdout: e } = await ME(
          'powershell -Command "(Get-Culture).DateTimeFormat.ShortTimePattern"',
        ),
        t = e.trim();
      return t.includes("H") && !t.includes("tt") ? Ih : No;
    } catch (e) {
      return (
        logger.error(
          "[getTimeFormat] Failed to detect time format from PowerShell:",
          e,
        ),
        No
      );
    }
  },
  Vp = "telegram-desktop",
  $E = "manual",
  Cd = { facebook: "messenger" },
  jE = 15e3,
  WE = {
    "User-Agent":
      "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36",
    Accept:
      "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8",
    "Accept-Language": "en-US,en;q=0.9",
    "sec-ch-ua": '"Chromium";v="140", "Not=A?Brand";v="24"',
    "sec-ch-ua-mobile": "?0",
    "sec-ch-ua-platform": '"macOS"',
    "sec-fetch-dest": "document",
    "sec-fetch-mode": "navigate",
    "sec-fetch-site": "none",
    "sec-fetch-user": "?1",
    "upgrade-insecure-requests": "1",
  },
  HE = { instagram: "ds_user_id", facebook: "c_user", twitter: "twid" },
  zp = {
    instagram: {
      url: "https://www.instagram.com/",
      patterns: (e) => [
        new RegExp(`"username":"([^"]{1,40})"[^{}]{0,400}?"id":"${e}"`),
        new RegExp(`"id":"${e}"[^{}]{0,400}?"username":"([^"]{1,40})"`),
      ],
    },
    twitter: {
      url: "https://x.com/",
      patterns: (e) => [
        new RegExp(`"screen_name":"([^"]{1,20})"[^{}]{0,600}?"id_str":"${e}"`),
        new RegExp(`"id_str":"${e}"[^{}]{0,600}?"screen_name":"([^"]{1,20})"`),
      ],
    },
    facebook: {
      url: "https://www.facebook.com/",
      patterns: (e) => [
        new RegExp(
          `"USER_ID":"${e}"[^{}]{0,600}?"NAME":"((?:[^"\\\\]|\\\\.){1,60})"`,
        ),
        new RegExp(
          `"NAME":"((?:[^"\\\\]|\\\\.){1,60})"[^{}]{0,600}?"USER_ID":"${e}"`,
        ),
      ],
    },
  };
function GE(e, t) {
  return e.find((o) => o.name === t)?.value;
}
function VE(e) {
  const t = new Set();
  return e
    .filter((o) => !t.has(o.name) && t.add(o.name))
    .map((o) => `${o.name}=${o.value}`)
    .join("; ");
}
function zE(e) {
  let t = e;
  if (e.startsWith("u%3D") || e.startsWith("u%3d"))
    try {
      t = decodeURIComponent(e);
    } catch {
      return;
    }
  const o = t.startsWith("u=") ? t.slice(2) : t;
  return /^\d+$/.test(o) ? o : void 0;
}
function XE(e, t) {
  const o = HE[e];
  if (!o) return;
  const i = GE(t, o);
  if (i) return e === "twitter" ? zE(i) : /^\d+$/.test(i) ? i : void 0;
}
function YE(e, t, o) {
  const i = zp[e];
  if (i)
    for (const a of i.patterns(t)) {
      const n = a.exec(o)?.[1];
      if (n)
        try {
          const r = JSON.parse(`"${n}"`);
          if (r.trim()) return r.trim();
        } catch {}
    }
}
async function KE(e, t, o) {
  const i = zp[e];
  if (!i) return;
  const a = await fetch(i.url, {
    headers: { ...WE, Cookie: VE(o) },
    redirect: "follow",
    signal: AbortSignal.timeout(jE),
  });
  if (!a.ok) throw new Error(`${e}_http_${a.status}`);
  return YE(e, t, await a.text());
}
async function JE(e, t, o) {
  try {
    return await KE(e, t, o);
  } catch (i) {
    logger.warn(
      "[BrowserSessionImport] Could not resolve candidate name",
      { network: e },
      i,
    );
    return;
  }
}
const Vs = G.join(lt, "telegram-desktop-pending-cleanup.json"),
  QE = 50 * 1024 * 1024,
  ZE = 12e4,
  ev = [100, 250, 500, 1e3, 2e3],
  Xp = 40,
  ti = 250,
  Du = Xp * ti,
  Yp = Du + 1e4,
  en = "safari",
  tv = "slack-desktop",
  Lo = "fi.mau.slack.auth_token",
  mu = "https://app.slack.com",
  gu = "localConfig_v2",
  rv = "https://slack.com/api/auth.test",
  nv = 1e4,
  iv = new Set([
    "invalid_auth",
    "not_authed",
    "account_inactive",
    "token_revoked",
    "token_expired",
  ]),
  ov = ["d", "x", "lc", "ec"],
  av = [
    G.join(
      "Library",
      "Containers",
      "com.apple.Safari",
      "Data",
      "Library",
      "Cookies",
      "Cookies.binarycookies",
    ),
    G.join("Library", "Cookies", "Cookies.binarycookies"),
  ],
  sv = "TelegramMessengerLLP.TelegramDesktop_",
  uv = [
    G.join("LocalCache", "Roaming", "Telegram Desktop UWP", "tdata"),
    G.join("LocalCache", "Roaming", "Telegram Desktop", "tdata"),
  ];
function Ad(e) {
  return e.filter((t) => !!t);
}
function Vn(e = process.platform, t = process.env) {
  if (e === "darwin")
    return [
      G.join("Library", "Application Support", "Telegram Desktop", "tdata"),
    ];
  if (e === "win32") {
    const o = t.LOCALAPPDATA,
      i = o ? uv.map((a) => G.join(o, "Packages", `${sv}*`, a)) : [];
    return Ad([
      t.APPDATA ? G.join(t.APPDATA, "Telegram Desktop", "tdata") : void 0,
      o ? G.join(o, "Telegram Desktop", "tdata") : void 0,
      ...i,
    ]);
  }
  return e === "linux"
    ? Ad([
        t.XDG_DATA_HOME
          ? G.join(t.XDG_DATA_HOME, "TelegramDesktop", "tdata")
          : void 0,
        G.join(".local", "share", "TelegramDesktop", "tdata"),
        G.join(
          ".var",
          "app",
          "org.telegram.desktop",
          "data",
          "TelegramDesktop",
          "tdata",
        ),
        G.join(
          "snap",
          "telegram-desktop",
          "current",
          ".local",
          "share",
          "TelegramDesktop",
          "tdata",
        ),
        G.join(
          "snap",
          "telegram-desktop",
          "common",
          ".local",
          "share",
          "TelegramDesktop",
          "tdata",
        ),
        G.join(".config", "TelegramDesktop", "tdata"),
        G.join(".TelegramDesktop", "tdata"),
      ])
    : [];
}
const lv = G.join(
    "Library",
    "Containers",
    "com.apple.Safari",
    "Data",
    "Library",
  ),
  cv = [
    G.join(
      "Library",
      "Containers",
      "com.apple.Safari",
      "Data",
      "Library",
      "WebKit",
      "com.apple.Safari",
      "WebsiteData",
    ),
    G.join("Library", "WebKit", "com.apple.Safari", "WebsiteData"),
  ],
  wu = [
    {
      network: "instagram",
      displayName: "Instagram",
      domains: ["instagram.com"],
      requiredCookieNames: [
        "sessionid",
        "csrftoken",
        "ds_user_id",
        "mid",
        "ig_did",
      ],
      deleteCookieNames: [
        "sessionid",
        "csrftoken",
        "ds_user_id",
        "mid",
        "ig_did",
      ],
      loginFlowID: "instagram",
    },
    {
      network: "facebook",
      displayName: "Messenger",
      domains: ["messenger.com"],
      requiredCookieNames: ["xs", "c_user", "datr"],
      deleteDomains: ["facebook.com", "messenger.com"],
      deleteCookieNames: ["xs", "c_user", "datr"],
      loginFlowID: "messenger",
    },
    {
      network: "facebook",
      displayName: "Messenger",
      domains: ["facebook.com"],
      requiredCookieNames: ["xs", "c_user", "datr"],
      deleteDomains: ["facebook.com", "messenger.com"],
      deleteCookieNames: ["xs", "c_user", "datr"],
      loginFlowID: "facebook",
    },
    {
      network: "twitter",
      displayName: "X",
      domains: ["x.com", "twitter.com"],
      requiredCookieNames: ["ct0", "auth_token"],
      deleteCookieNames: ["ct0", "auth_token"],
      loginFlowID: "cookies",
    },
    {
      network: "slack",
      displayName: "Slack",
      domains: ["slack.com"],
      requiredCookieNames: ["d"],
      deleteCookieNames: [],
      requiredLocalStorage: [{ origin: mu, keys: [gu] }],
      loginFlowID: "token",
    },
  ],
  Xt = new Map(),
  tn = new Map(),
  Bo = new Set();
function fv(e) {
  return [e.browserID, e.platformNetwork, e.sourceCookieFile].join(`
`);
}
function dv() {
  return [...new Set(wu.flatMap((e) => e.domains))];
}
function Kp() {
  const e = new Map();
  for (const t of wu)
    for (const o of t.requiredLocalStorage ?? []) {
      const i = e.get(o.origin) ?? new Set();
      for (const a of o.keys) i.add(a);
      e.set(o.origin, i);
    }
  return Array.from(e, ([t, o]) => ({ origin: t, keys: Array.from(o) }));
}
const zo = [
  {
    id: "chrome",
    name: "Google Chrome",
    appRoots: {
      darwin: [
        G.join("/Applications", "Google Chrome.app"),
        G.join("Applications", "Google Chrome.app"),
      ],
    },
    macOSBundleIDs: ["com.google.Chrome"],
    processNames: {
      win32: ["chrome.exe"],
      linux: ["chrome", "google-chrome", "google-chrome-stable"],
    },
    roots: {
      darwin: [G.join("Library", "Application Support", "Google", "Chrome")],
      win32: [
        G.join(process.env.LOCALAPPDATA ?? "", "Google", "Chrome", "User Data"),
        G.join(process.env.APPDATA ?? "", "Google", "Chrome", "User Data"),
      ],
      linux: [
        G.join(".config", "google-chrome"),
        G.join(".var", "app", "com.google.Chrome", "config", "google-chrome"),
      ],
    },
  },
  {
    id: "arc",
    name: "Arc",
    appRoots: {
      darwin: [
        G.join("/Applications", "Arc.app"),
        G.join("Applications", "Arc.app"),
      ],
    },
    macOSBundleIDs: ["company.thebrowser.Browser"],
    processNames: { win32: ["Arc.exe"], linux: ["arc"] },
    roots: {
      darwin: [G.join("Library", "Application Support", "Arc", "User Data")],
      win32: [
        G.join(
          process.env.LOCALAPPDATA ?? "",
          "Packages",
          "TheBrowserCompany.Arc",
        ),
      ],
      linux: [
        G.join(".config", "arc"),
        G.join(".var", "app", "org.arc.Arc", "config", "arc"),
        G.join("snap", "arc", "common", "arc"),
      ],
    },
  },
  {
    id: "brave",
    name: "Brave",
    appRoots: {
      darwin: [
        G.join("/Applications", "Brave Browser.app"),
        G.join("Applications", "Brave Browser.app"),
      ],
    },
    macOSBundleIDs: ["com.brave.Browser"],
    processNames: { win32: ["brave.exe"], linux: ["brave", "brave-browser"] },
    roots: {
      darwin: [
        G.join(
          "Library",
          "Application Support",
          "BraveSoftware",
          "Brave-Browser",
        ),
      ],
      win32: [
        G.join(
          process.env.LOCALAPPDATA ?? "",
          "BraveSoftware",
          "Brave-Browser",
          "User Data",
        ),
        G.join(
          process.env.APPDATA ?? "",
          "BraveSoftware",
          "Brave-Browser",
          "User Data",
        ),
      ],
      linux: [
        G.join(".config", "BraveSoftware", "Brave-Browser"),
        G.join(
          ".var",
          "app",
          "com.brave.Browser",
          "config",
          "BraveSoftware",
          "Brave-Browser",
        ),
        G.join(
          "snap",
          "brave",
          "*",
          ".config",
          "BraveSoftware",
          "Brave-Browser",
        ),
      ],
    },
  },
  {
    id: "edge",
    name: "Microsoft Edge",
    appRoots: {
      darwin: [
        G.join("/Applications", "Microsoft Edge.app"),
        G.join("Applications", "Microsoft Edge.app"),
      ],
    },
    macOSBundleIDs: ["com.microsoft.edgemac"],
    processNames: {
      win32: ["msedge.exe"],
      linux: ["msedge", "microsoft-edge", "microsoft-edge-stable"],
    },
    roots: {
      darwin: [G.join("Library", "Application Support", "Microsoft Edge")],
      win32: [
        G.join(
          process.env.LOCALAPPDATA ?? "",
          "Microsoft",
          "Edge",
          "User Data",
        ),
        G.join(process.env.APPDATA ?? "", "Microsoft", "Edge", "User Data"),
      ],
      linux: [
        G.join(".config", "microsoft-edge"),
        G.join(".var", "app", "com.microsoft.Edge", "config", "microsoft-edge"),
      ],
    },
  },
  {
    id: "firefox",
    name: "Firefox",
    appRoots: {
      darwin: [
        G.join("/Applications", "Firefox.app"),
        G.join("Applications", "Firefox.app"),
      ],
    },
    macOSBundleIDs: ["org.mozilla.firefox"],
    processNames: {
      win32: ["firefox.exe"],
      linux: ["firefox", "firefox-bin", "firefox-esr"],
    },
    roots: {
      darwin: [G.join("Library", "Application Support", "Firefox")],
      win32: [
        G.join(process.env.APPDATA ?? "", "Mozilla", "Firefox"),
        G.join(process.env.LOCALAPPDATA ?? "", "Mozilla", "Firefox"),
      ],
      linux: [
        G.join(".mozilla", "firefox"),
        G.join(".var", "app", "org.mozilla.firefox", ".mozilla", "firefox"),
        G.join("snap", "firefox", "common", ".mozilla", "firefox"),
      ],
    },
  },
  {
    id: en,
    name: "Safari",
    appRoots: {
      darwin: [
        G.join("/Applications", "Safari.app"),
        G.join("/System/Applications", "Safari.app"),
        G.join("Applications", "Safari.app"),
      ],
    },
    macOSBundleIDs: ["com.apple.Safari"],
    requiresAccess: !0,
    roots: {
      darwin: [
        G.join(
          "Library",
          "Containers",
          "com.apple.Safari",
          "Data",
          "Library",
          "Cookies",
        ),
        G.join("Library", "Cookies"),
      ],
    },
  },
  {
    id: Vp,
    name: "Telegram Desktop",
    appRoots: {
      darwin: [
        G.join("/Applications", "Telegram.app"),
        G.join("/Applications", "Telegram Desktop.app"),
        G.join("Applications", "Telegram.app"),
        G.join("Applications", "Telegram Desktop.app"),
      ],
    },
    macOSBundleIDs: ["com.tdesktop.Telegram"],
    processNames: {
      win32: ["Telegram.exe"],
      linux: ["Telegram", "telegram-desktop"],
    },
    windowsProcessDetection: "process",
    roots: { darwin: Vn("darwin"), win32: Vn("win32"), linux: Vn("linux") },
  },
  {
    id: tv,
    name: "Slack Desktop",
    appRoots: {
      darwin: [
        G.join("/Applications", "Slack.app"),
        G.join("Applications", "Slack.app"),
      ],
    },
    macOSBundleIDs: ["com.tinyspeck.slackmacgap"],
    processNames: { win32: ["Slack.exe"] },
    windowsProcessDetection: "process",
    roots: {
      darwin: [
        G.join("Library", "Application Support", "Slack"),
        G.join(
          "Library",
          "Containers",
          "com.tinyspeck.slackmacgap",
          "Data",
          "Library",
          "Application Support",
          "Slack",
        ),
      ],
      win32: [
        G.join(process.env.APPDATA ?? "", "Slack"),
        G.join(
          process.env.LOCALAPPDATA ?? "",
          "Packages",
          "com.tinyspeck.slackdesktop_*",
          "LocalCache",
          "Roaming",
          "Slack",
        ),
      ],
    },
  },
];
function bd(e) {
  return e.trim().replace(/^\./, "").toLowerCase();
}
function hv(e, t) {
  const o = bd(e.domain);
  return t.some((i) => {
    const a = bd(i);
    return o === a || o.endsWith(`.${a}`);
  });
}
function pv(e, t) {
  if (e.startsWith(".")) {
    const o = t.startsWith(".") ? t : `.${t}`;
    return e.endsWith(o);
  } else return e === t;
}
function Dv(e) {
  return e !== void 0 && e.getTime() <= Date.now();
}
function mv(e) {
  if (e) return G.isAbsolute(e) ? e : G.join(Ke.homedir(), e);
}
function gv(e) {
  const t = e.replace(/[.+?^${}()|[\]\\]/g, "\\$&");
  return new RegExp(`^${t.replace(/\*/g, ".*")}$`);
}
async function wv(e) {
  const t = e.split(G.sep),
    o = t.findIndex((r) => r.includes("*"));
  if (o === -1) return [e];
  const i = t.slice(0, o).join(G.sep) || G.parse(e).root,
    a = t.slice(o + 1),
    n = gv(t[o]);
  try {
    return (await Te.readdir(i, { withFileTypes: !0 }))
      .filter((s) => s.isDirectory() && n.test(s.name))
      .map((s) => G.join(i, s.name, ...a));
  } catch {
    return [];
  }
}
async function yu(e) {
  const t = mv(e);
  return t ? wv(t) : [];
}
function rn(e) {
  const t = G.resolve(e);
  return process.platform === "win32" ? t.toLowerCase() : t;
}
async function Jp(e) {
  const t = rn(e);
  for (const o of Vn()) for (const i of await yu(o)) if (rn(i) === t) return !0;
  return !1;
}
async function yv() {
  for (const e of Vn()) for (const t of await yu(e)) if (await Xn(t)) return t;
}
async function Qp(e) {
  const t = await yu(e);
  if (t.length === 0) return !1;
  if (
    process.platform === "win32" &&
    t.some((i) => i.endsWith(G.join("Packages", "TheBrowserCompany.Arc")))
  ) {
    const i = t.find((n) =>
        n.endsWith(G.join("Packages", "TheBrowserCompany.Arc")),
      ),
      a = G.dirname(i);
    try {
      return (await Te.readdir(a)).some((r) =>
        r.startsWith("TheBrowserCompany.Arc"),
      );
    } catch {
      return !1;
    }
  }
  return (await Promise.all(t.map(Xn))).some(Boolean);
}
async function Ev(e) {
  try {
    const { stdout: t } = await Ie("/usr/bin/mdfind", [
      `kMDItemCFBundleIdentifier == "${e}"`,
    ]);
    return t.trim().length > 0;
  } catch {
    return !1;
  }
}
async function vv(e) {
  try {
    return await Zp(e);
  } catch {
    return !1;
  }
}
async function Zp(e) {
  const t = `ObjC.import('AppKit'); $.NSRunningApplication.runningApplicationsWithBundleIdentifier('${e}').count > 0`,
    { stdout: o } = await Ie("osascript", ["-l", "JavaScript", "-e", t]);
  return o.trim() === "true";
}
async function eD(e, t = "visible-window") {
  try {
    return process.platform === "win32"
      ? t === "process"
        ? await tD(e)
        : await iD(e)
      : (await Ie("pgrep", ["-x", e]), !0);
  } catch {
    if (process.platform !== "linux") return !1;
  }
  try {
    return (await Ie("pgrep", ["-f", rD(e)]), !0);
  } catch {
    return !1;
  }
}
async function tD(e) {
  const t = Yo(e),
    o = [
      `$browserProcessNames = ${Xo([t])}`,
      "$processes = Get-Process -Name $browserProcessNames -ErrorAction SilentlyContinue",
      'if ($processes) { Write-Output "true" } else { Write-Output "false" }',
    ].join(`
`),
    { stdout: i } = await Ie("powershell.exe", [
      "-NoProfile",
      "-NonInteractive",
      "-Command",
      o,
    ]);
  return i.trim().toLowerCase() === "true";
}
async function Cv(e, t = "visible-window") {
  if (process.platform === "win32")
    return t === "process" ? await tD(e) : await iD(e);
  try {
    return (await Ie("pgrep", ["-x", e]), !0);
  } catch (o) {
    if (o && typeof o == "object" && o.exitCode === 1) return !1;
    throw o;
  }
}
function Av(e) {
  return `'${e.replace(/'/g, "''")}'`;
}
function Xo(e) {
  return `@(${e.map(Av).join(", ")})`;
}
function Yo(e) {
  return e.replace(/\.exe$/i, "");
}
function rD(e) {
  return `(^|/)${e.replace(/[.+?^${}()|[\]\\]/g, "\\$&")}([[:space:]]|$)`;
}
function nD() {
  return [
    "$source = @'",
    "using System;",
    "using System.Runtime.InteropServices;",
    "public static class BrowserSessionImportWindowCloser {",
    "  private delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);",
    '  [DllImport("user32.dll")] private static extern bool EnumWindows(EnumWindowsProc enumProc, IntPtr lParam);',
    '  [DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);',
    '  [DllImport("user32.dll")] private static extern bool IsWindowVisible(IntPtr hWnd);',
    '  [DllImport("user32.dll")] private static extern bool PostMessage(IntPtr hWnd, uint msg, IntPtr wParam, IntPtr lParam);',
    "  private const uint WM_CLOSE = 0x0010;",
    "  public static bool HasVisibleWindow(uint targetProcessId) {",
    "    bool found = false;",
    "    EnumWindows((hWnd, lParam) => {",
    "      uint processId;",
    "      GetWindowThreadProcessId(hWnd, out processId);",
    "      if (processId == targetProcessId && IsWindowVisible(hWnd)) {",
    "        found = true;",
    "        return false;",
    "      }",
    "      return true;",
    "    }, IntPtr.Zero);",
    "    return found;",
    "  }",
    "  public static bool CloseWindows(uint targetProcessId) {",
    "    bool found = false;",
    "    EnumWindows((hWnd, lParam) => {",
    "      uint processId;",
    "      GetWindowThreadProcessId(hWnd, out processId);",
    "      if (processId == targetProcessId && IsWindowVisible(hWnd)) {",
    "        found = true;",
    "        PostMessage(hWnd, WM_CLOSE, IntPtr.Zero, IntPtr.Zero);",
    "      }",
    "      return true;",
    "    }, IntPtr.Zero);",
    "    return found;",
    "  }",
    "}",
    "'@",
    "Add-Type -TypeDefinition $source",
  ].join(`
`);
}
function bv(e, t) {
  const o = Yo(e);
  return [
    `$browserProcessNames = ${Xo([o])}`,
    "$processes = Get-Process -Name $browserProcessNames -ErrorAction SilentlyContinue",
    'if (-not $processes) { Write-Output "false"; exit 0 }',
    nD(),
    t,
  ].join(`
`);
}
async function iD(e) {
  const t = bv(
      e,
      [
        "foreach ($process in $processes) {",
        '  if ([BrowserSessionImportWindowCloser]::HasVisibleWindow([uint32]$process.Id)) { Write-Output "true"; exit 0 }',
        "}",
        'Write-Output "false"',
      ].join(`
`),
    ),
    { stdout: o } = await Ie("powershell.exe", [
      "-NoProfile",
      "-NonInteractive",
      "-Command",
      t,
    ]);
  return o.trim().toLowerCase() === "true";
}
async function Fv(e) {
  try {
    await Ie("pkill", ["-TERM", "-x", e]);
  } catch {
    await Ie("pkill", ["-TERM", "-f", rD(e)]);
  }
}
async function Sv(e) {
  const t = e.map(Yo),
    o = [
      `$browserProcessNames = ${Xo(t)}`,
      nD(),
      "$closedAnyWindow = $false",
      "$processes = Get-Process -Name $browserProcessNames -ErrorAction SilentlyContinue",
      "foreach ($process in $processes) {",
      "  if ([BrowserSessionImportWindowCloser]::CloseWindows([uint32]$process.Id)) { $closedAnyWindow = $true }",
      "}",
      'if (-not $closedAnyWindow) { Write-Output "true"; exit 0 }',
      `$deadline = [DateTime]::UtcNow.AddMilliseconds(${Du})`,
      "do {",
      `  Start-Sleep -Milliseconds ${ti}`,
      "  $hasVisibleWindow = $false",
      "  $processes = Get-Process -Name $browserProcessNames -ErrorAction SilentlyContinue",
      "  foreach ($process in $processes) {",
      "    if ([BrowserSessionImportWindowCloser]::HasVisibleWindow([uint32]$process.Id)) { $hasVisibleWindow = $true; break }",
      "  }",
      '  if (-not $hasVisibleWindow) { Write-Output "true"; exit 0 }',
      "} while ([DateTime]::UtcNow -lt $deadline)",
      'Write-Output "false"',
    ].join(`
`),
    { stdout: i } = await Ie(
      "powershell.exe",
      ["-NoProfile", "-NonInteractive", "-Command", o],
      { timeout: Yp },
    );
  return i.trim().toLowerCase() === "true";
}
async function _v(e) {
  const t = e.map(Yo),
    o = [
      `$browserProcessNames = ${Xo(t)}`,
      "$processes = Get-Process -Name $browserProcessNames -ErrorAction SilentlyContinue",
      'if (-not $processes) { Write-Output "true"; exit 0 }',
      "foreach ($process in $processes) {",
      "  try { [void]$process.CloseMainWindow() } catch {}",
      "}",
      `$deadline = [DateTime]::UtcNow.AddMilliseconds(${Du})`,
      "do {",
      `  Start-Sleep -Milliseconds ${ti}`,
      "  $processes = Get-Process -Name $browserProcessNames -ErrorAction SilentlyContinue",
      '  if (-not $processes) { Write-Output "true"; exit 0 }',
      "} while ([DateTime]::UtcNow -lt $deadline)",
      "$processes = Get-Process -Name $browserProcessNames -ErrorAction SilentlyContinue",
      "foreach ($process in $processes) {",
      "  try { Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue } catch {}",
      "}",
      `Start-Sleep -Milliseconds ${ti}`,
      "$processes = Get-Process -Name $browserProcessNames -ErrorAction SilentlyContinue",
      'if ($processes) { Write-Output "false" } else { Write-Output "true" }',
    ].join(`
`),
    { stdout: i } = await Ie(
      "powershell.exe",
      ["-NoProfile", "-NonInteractive", "-Command", o],
      { timeout: Yp },
    );
  return i.trim().toLowerCase() === "true";
}
async function Fd(e) {
  for (let t = 0; t < Xp; t++) {
    if (!(await Yt(e))) return !0;
    await pD(ti);
  }
  return !1;
}
function oD(e = "Safari") {
  return `${e} import needs access to your Safari browser data.`;
}
async function aD(e) {
  let t;
  try {
    return ((t = await Te.open(e, "r")), !0);
  } catch {
    return !1;
  } finally {
    await t?.close().catch(() => {});
  }
}
async function sD(e) {
  try {
    return (await Te.readdir(e), !0);
  } catch {
    return !1;
  }
}
function Tv() {
  return av.map((e) => G.join(Ke.homedir(), e));
}
function uD() {
  return cv.map((e) => G.join(Ke.homedir(), e));
}
async function xv() {
  return (await Promise.all(Tv().map(aD))).some(Boolean);
}
async function Nv() {
  return (await Promise.all(uD().map(sD))).some(Boolean);
}
async function Iv() {
  for (const e of uD()) {
    if (await sD(e)) return !1;
    try {
      return (await Te.stat(e), !0);
    } catch (t) {
      if (t.code !== "ENOENT") return !0;
    }
  }
  return !1;
}
async function lD() {
  return !(await Nv()) && (await Iv());
}
async function Eu() {
  return process.platform !== "darwin"
    ? !1
    : (await xv())
      ? Kp().length === 0
        ? !1
        : lD()
      : !0;
}
async function Ov() {
  if (process.platform !== "darwin") return !0;
  const e = await Xe.showOpenDialog({
    title: "Allow access to Safari browser data",
    message:
      "Grant Beeper access to the Safari browser data folder. It should already be selected.",
    buttonLabel: "Grant Access",
    defaultPath: G.join(Ke.homedir(), lv),
    properties: ["openDirectory"],
  });
  return e.canceled || !e.filePaths[0] ? !1 : !(await Eu());
}
async function Yt(e, { failClosed: t = !1, authoritative: o = !1 } = {}) {
  const i = zo.find((a) => a.id === e);
  if (!i) return t;
  try {
    if (process.platform === "darwin") {
      const s = i.macOSBundleIDs ?? [],
        u = t ? Zp : vv;
      return (await Promise.all(s.map(u))).some(Boolean);
    }
    const a = i.processNames?.[process.platform] ?? [],
      n =
        o && process.platform === "win32"
          ? "process"
          : i.windowsProcessDetection;
    return (await Promise.all(a.map((s) => (t ? Cv(s, n) : eD(s, n))))).some(
      Boolean,
    );
  } catch {
    return t;
  }
}
async function Pv(e) {
  const t = zo.find((a) => a.id === e);
  if (!t) return !1;
  if (process.platform === "darwin") {
    const a = t.macOSBundleIDs ?? [];
    if (a.length === 0) return !(await Yt(e));
    for (const n of a)
      try {
        await Ie("/usr/bin/osascript", [
          "-e",
          `tell application id "${n}" to quit`,
        ]);
      } catch (r) {
        logger.warn(
          "[BrowserSessionImport] Failed to ask browser to quit",
          { browserID: e, bundleID: n },
          r,
        );
      }
    return Fd(e);
  }
  const o = t.processNames?.[process.platform] ?? [];
  if (o.length === 0) return !(await Yt(e));
  if (process.platform === "win32")
    try {
      return t.windowsProcessDetection === "process"
        ? await _v(o)
        : await Sv(o);
    } catch (a) {
      return (
        logger.warn(
          "[BrowserSessionImport] Failed to ask browser process to quit",
          { browserID: e, processNames: o },
          a,
        ),
        !1
      );
    }
  let i = !1;
  for (const a of o)
    if (await eD(a)) {
      i = !0;
      try {
        process.platform === "linux" && (await Fv(a));
      } catch (n) {
        logger.warn(
          "[BrowserSessionImport] Failed to ask browser process to quit",
          { browserID: e, processName: a },
          n,
        );
      }
    }
  return i ? Fd(e) : !(await Yt(e));
}
async function cD(e) {
  const t = e.appRoots?.[process.platform] ?? [];
  return t.length > 0 && (await Promise.all(t.map(Qp))).some(Boolean)
    ? !0
    : process.platform === "darwin" && e.macOSBundleIDs?.length
      ? (await Promise.all(e.macOSBundleIDs.map(Ev))).some(Boolean)
      : t.length === 0;
}
async function Rv() {
  process.platform === "darwin" &&
    (await Promise.all(
      ["nsurlstoraged", "cookied"].map((e) =>
        Ie("/usr/bin/killall", [e]).catch(() => {}),
      ),
    ));
}
async function Lv() {
  if (process.platform !== "darwin") return;
  const e = zo.find((t) => t.id === en);
  if (!(!e || !e.requiresAccess || !(await cD(e))) && (await Eu()))
    return {
      browserID: en,
      browserName: e.name,
      code: "access_required",
      message: oD(e.name),
    };
}
async function Bv() {
  const e = [];
  for (const t of zo) {
    const o = t.roots[process.platform] ?? [];
    if (!(await cD(t))) continue;
    const i = !!t.requiresAccess && (await Eu());
    if (i) {
      e.push({ id: t.id, name: t.name, requiresAccess: i });
      continue;
    }
    (await Promise.all(o.map(Qp))).some(Boolean) &&
      e.push({ id: t.id, name: t.name, requiresAccess: i });
  }
  return { browsers: e };
}
function kv() {
  const e = `beeper-browser-session-import${Kt ? ".exe" : ""}`,
    t = Uo;
  return G.join(t, "browser-session-import", e);
}
async function fD(e, t) {
  const o = kv();
  if (!(await Io(o)))
    throw new Error(
      "Browser session import helper is missing from this app build.",
    );
  let i;
  try {
    const a = await Ie(o, [e], {
      input: t ? JSON.stringify(t) : void 0,
      maxBuffer: QE,
      timeout: ZE,
    });
    (a.stderr.trim() &&
      logger.warn(
        "[BrowserSessionImport] Helper reported diagnostics on stderr",
      ),
      (i = a.stdout));
  } catch (a) {
    const n =
      a && typeof a == "object" && "shortMessage" in a
        ? String(a.shortMessage)
        : void 0;
    throw new Error(n || `Browser session import helper "${e}" failed`);
  }
  try {
    return JSON.parse(i);
  } catch {
    throw new Error(
      `Browser session import helper "${e}" returned malformed output`,
    );
  }
}
async function dD(e) {
  return fD("delete", {
    sourceType: e.sourceType,
    cookieFile: e.sourceCookieFile,
    domains: e.platformConfig.deleteDomains ?? e.platformConfig.domains,
    names: e.platformConfig.deleteCookieNames,
    localStorage: e.platformConfig.deleteLocalStorage,
  });
}
function hD(e) {
  return (
    e.deleteCookieNames.length > 0 ||
    (e.deleteLocalStorage ?? []).some((t) => t.keys.length > 0)
  );
}
function Sd(e) {
  return e.network !== "slack"
    ? e
    : {
        ...e,
        deleteCookieNames: ov,
        deleteLocalStorage: [{ origin: mu, keys: [gu] }],
      };
}
function pD(e) {
  return new Promise((t) => setTimeout(t, e));
}
function DD(e) {
  return e.code === "locked";
}
function Mv(e) {
  return e.code === "access_required";
}
function Uv(e) {
  return e.code === "browser_running";
}
function zs(e) {
  return e.browserID === en || e.sourceType === "safari";
}
function mD(e) {
  if (DD(e) || Uv(e)) return "browser-running";
  if (Mv(e)) return "access-required";
}
function qv(e) {
  return !!mD(e);
}
function gD(e) {
  return e ? /database (?:is |table is )?locked|SQLITE_BUSY/i.test(e) : !1;
}
function _d(e) {
  return e ? /operation not permitted|permission denied/i.test(e) : !1;
}
async function $v(e) {
  const t = (e.platformConfig.deleteLocalStorage?.length ?? 0) > 0;
  if (!(await aD(e.sourceCookieFile)) || (t && (await lD())))
    return { deleted: !1, code: "access_required", error: oD(e.browserName) };
  if (await Yt(en))
    return {
      deleted: !1,
      code: "browser_running",
      error:
        "Safari must be quit before source browser data can be cleaned up.",
    };
  const o = await dD(e);
  return (o.deleted && (await Rv()), o);
}
async function jv(e) {
  if (zs(e)) return $v(e);
  if (await Yt(e.browserID, { failClosed: !0, authoritative: !0 }))
    return {
      deleted: !1,
      code: "browser_running",
      error: `${e.browserName} must be quit before source browser data can be cleaned up.`,
    };
  let t;
  for (let o = 0; ; o++) {
    try {
      const a = await dD(e);
      if (a.deleted || !DD(a)) return a;
      t = a;
    } catch (a) {
      const n = a instanceof Error ? a.message : String(a);
      if (!gD(n)) throw a;
      t = { deleted: !1, error: n, code: "locked" };
    }
    const i = ev[o];
    if (i === void 0) break;
    await pD(i);
  }
  return t ?? { deleted: !1, error: "Source browser data is locked." };
}
function Wv(e) {
  if (!e) return;
  const t = new Date(e);
  return Number.isNaN(t.getTime()) ? void 0 : t;
}
function Hv(e) {
  if (!e.name || !e.value || !e.domain) return null;
  const t = Wv(e.expires);
  return Dv(t)
    ? null
    : {
        domain: e.domain,
        name: e.name,
        value: e.value,
        path: e.path || "/",
        secure: e.secure,
        httpOnly: e.httpOnly,
        expires: t,
      };
}
function Gv(e, t) {
  return e.filter((o) => hv(o, t.domains));
}
function Vv(e, t) {
  return e.filter((o) =>
    (t.requiredLocalStorage ?? []).some(
      (i) => i.origin === o.origin && i.keys.includes(o.key),
    ),
  );
}
function Td(e, t) {
  return t.requiredCookieNames.every((o) => e.some((i) => i.name === o));
}
function xd(e, t) {
  return (t.requiredLocalStorage ?? []).every((o) =>
    o.keys.every((i) =>
      e.some((a) => a.origin === o.origin && a.key === i && !!a.value),
    ),
  );
}
function zv(e) {
  try {
    return decodeURIComponent(e);
  } catch {
    return;
  }
}
function Xv(e, t) {
  return !(
    t.type !== "cookie" ||
    e.name !== t.name ||
    (t.cookie_domain && !pv(e.domain, t.cookie_domain))
  );
}
function Yv(e, t) {
  if (!t.pattern) return !0;
  try {
    return new RegExp(t.pattern).test(e);
  } catch {
    return !1;
  }
}
function Kv(e, t) {
  const o = e.find((i) => Xv(i, t));
  if (o) return zv(o.value);
}
function Jv(e, t) {
  if (t.type === "special" && t.name === Lo) return e.derivedFields?.[Lo];
}
function Qv(e, t) {
  for (const o of t.sources) {
    const i = o.type === "cookie" ? Kv(e.allCookies, o) : Jv(e, o);
    if (!(i === void 0 || !Yv(i, t))) return i;
  }
}
function Zv(e) {
  return e.sources.some(
    (t) => t.type === "cookie" || (t.type === "special" && t.name === Lo),
  );
}
function eC(e, t) {
  const o = {},
    i = [],
    a = [];
  for (const n of t) {
    const r = Zv(n),
      s = r ? Qv(e, n) : void 0;
    if (s !== void 0) {
      o[n.id] = s;
      continue;
    }
    n.required && (r ? i.push(n.id) : a.push(n.id));
  }
  return {
    canSubmit: i.length === 0 && a.length === 0,
    fields: o,
    missingRequiredFieldIDs: i,
    unsupportedRequiredFieldIDs: a,
  };
}
function At(e) {
  return typeof e == "string" && e.trim() ? e.trim() : void 0;
}
function tC(e, t) {
  const o = At(e.id) ?? t,
    i = At(e.user_id) ?? At(e.userId);
  return i ? `${o}-${i}` : o;
}
function rC(e) {
  const t = (n) => {
      try {
        const r = JSON.parse(n);
        return r && typeof r == "object" && !Array.isArray(r) ? r : void 0;
      } catch {
        return;
      }
    },
    o = t(e);
  if (o) return o;
  const i = e.indexOf("{"),
    a = e.lastIndexOf("}");
  return i >= 0 && a > i ? t(e.slice(i, a + 1)) : void 0;
}
function nC(e) {
  const t = e.find((r) => r.origin === mu && r.key === gu && r.value)?.value;
  if (!t) return [];
  const i = rC(t)?.teams;
  if (!i || typeof i != "object" || Array.isArray(i)) return [];
  const a = [],
    n = new Set();
  for (const [r, s] of Object.entries(i)) {
    if (!s || typeof s != "object") continue;
    const u = s,
      f = At(u.token);
    !f?.startsWith("xoxc-") ||
      n.has(f) ||
      (n.add(f),
      a.push({
        token: f,
        remoteID: tC(u, r),
        teamName:
          At(u.name) ?? At(u.teamName) ?? At(u.team_name) ?? At(u.domain),
        teamKey: r,
        source: "json",
      }));
  }
  return a;
}
async function iC(e, t) {
  try {
    const o = await fetch(rv, {
      method: "POST",
      headers: {
        "Content-Type": "application/x-www-form-urlencoded",
        Cookie: `d=${t}`,
      },
      body: new URLSearchParams({ token: e }).toString(),
      signal: AbortSignal.timeout(nv),
    });
    if (!o.ok) return { status: "unknown", error: `http_${o.status}` };
    const i = await o.json();
    if (i.ok)
      return {
        status: "valid",
        team: At(i.team),
        teamID: At(i.team_id),
        userID: At(i.user_id),
      };
    const a = At(i.error) ?? "unknown_error";
    return iv.has(a)
      ? { status: "invalid", error: a }
      : { status: "unknown", error: a };
  } catch (o) {
    return {
      status: "unknown",
      error: o instanceof Error ? o.message : String(o),
    };
  }
}
function oC(e) {
  return {
    id: e.id,
    browserID: e.browserID,
    browserName: e.browserName,
    profileName: e.profileName,
    platformNetwork: e.platformNetwork,
    platformDisplayName: e.platformDisplayName,
    userDisplayText: e.userDisplayText,
    remoteID: e.remoteID,
    loginFlowID: e.loginFlowID,
    requiresSourceQuit: hD(e.platformConfig),
  };
}
function Nd(e) {
  return (Xt.set(e.id, e), oC(e));
}
function aC(e) {
  return e.reduce(
    (t, o) => ((t[o.platformNetwork] = (t[o.platformNetwork] ?? 0) + 1), t),
    {},
  );
}
async function sC(e) {
  const t = e.cookies.map(Hv).filter((a) => !!a),
    o = e.localStorage ?? [],
    i = [];
  for (const a of wu) {
    const n = Gv(t, a),
      r = Vv(o, a);
    if (a.network === "slack") {
      const f = Td(n, a),
        d = xd(r, a),
        c = d ? nC(r) : [],
        l = n.find((F) => F.name === "d")?.value,
        h = l
          ? await Promise.all(c.map((F) => iC(F.token, l)))
          : c.map(() => ({ status: "unknown" })),
        y = Sd(a);
      if (
        (logger.info("[BrowserSessionImport] Slack profile scan result", {
          browserID: e.browserID,
          browserName: e.browserName,
          profileName: e.profileName,
          hasRequiredCookies: f,
          cookieNames: n.map((F) => F.name).sort(),
          hasRequiredLocalStorage: d,
          localStorageKeys: r.map((F) => F.key).sort(),
          tokenCount: c.length,
          tokenSources: [...new Set(c.map((F) => F.source))].sort(),
          validTokenCount: h.filter((F) => F.status === "valid").length,
          invalidTokenCount: h.filter((F) => F.status === "invalid").length,
          unknownTokenCount: h.filter((F) => F.status === "unknown").length,
        }),
        !f || !d || c.length === 0)
      )
        continue;
      for (const [F, m] of c.entries()) {
        const S = h[F];
        if (S.status === "invalid") continue;
        const E = S.status === "valid" ? S : void 0,
          b = E?.teamID && E.userID ? `${E.teamID}-${E.userID}` : void 0;
        i.push(
          Nd({
            id: hr(),
            browserID: e.browserID,
            browserName: e.browserName,
            profileName: e.profileName,
            platformNetwork: a.network,
            platformDisplayName: a.displayName,
            userDisplayText: E?.team ?? m.teamName ?? m.teamKey,
            remoteID: b ?? m.remoteID,
            loginFlowID: a.loginFlowID ?? Cd[a.network],
            allCookies: n,
            allLocalStorage: r,
            derivedFields: { [Lo]: m.token },
            sourceCookieFile: e.cookieFile,
            sourceType: e.sourceType,
            platformConfig: y,
          }),
        );
      }
      continue;
    }
    if (!Td(n, a) || !xd(r, a)) continue;
    const s = Sd(a),
      u = {
        id: hr(),
        browserID: e.browserID,
        browserName: e.browserName,
        profileName: e.profileName,
        platformNetwork: a.network,
        platformDisplayName: a.displayName,
        remoteID: XE(a.network, n),
        loginFlowID: a.loginFlowID ?? Cd[a.network],
        allCookies: n,
        allLocalStorage: r,
        sourceCookieFile: e.cookieFile,
        sourceType: e.sourceType,
        platformConfig: s,
      };
    i.push(Nd(u));
  }
  return i;
}
function Id(e) {
  return {
    id: e.id,
    browserID: e.browserID,
    browserName: e.browserName,
    profileName: e.profileName,
    platformNetwork: e.platformNetwork,
    platformDisplayName: e.platformDisplayName,
    userDisplayText: e.userDisplayText,
    loginFlowID: e.loginFlowID,
    tdataPath: e.tdataPath,
  };
}
async function uC() {
  const e = await yv();
  if (!e) return [];
  const t = Array.from(tn.values()).find((i) => i.tdataPath === e);
  if (t) return [Id(t)];
  const o = wD(e);
  return (tn.set(o.id, o), [Id(o)]);
}
async function lC() {
  (ED(), Bo.clear());
  const e = await uC();
  try {
    const t = await Lv(),
      o = await fD("scan", { domains: dv(), localStorage: Kp() });
    Xt.clear();
    const i = (o.errors ?? []).map((n) => ({
      browserID: n.browserID,
      browserName: n.browserName,
      profileName: n.profileName,
      code: n.code,
      message: n.message,
    }));
    t &&
      !i.some((n) => n.browserID === en && n.code === "access_required") &&
      i.push(t);
    const a = (await Promise.all((o.profiles ?? []).map(sC))).flat();
    return (
      logger.info("[BrowserSessionImport] Browser scan candidates resolved", {
        profileCount: o.profiles?.length ?? 0,
        profileBrowserIDs: (o.profiles ?? []).map((n) => n.browserID),
        errors: i.map((n) => ({ browserID: n.browserID, code: n.code })),
        candidateCountsByNetwork: aC(a),
      }),
      { candidates: [...e, ...a], errors: i }
    );
  } catch (t) {
    return (
      logger.warn("[BrowserSessionImport] Failed to scan browser sessions", t),
      {
        candidates: e,
        errors: [{ message: t instanceof Error ? t.message : String(t) }],
      }
    );
  }
}
function cC(e, t) {
  const o = Xt.get(e);
  if (!o)
    throw new Error(
      "Browser import candidate is no longer available. Scan browsers again.",
    );
  return eC(o, t);
}
async function fC(e) {
  const t = Xt.get(e);
  if (t?.remoteID) return JE(t.platformNetwork, t.remoteID, t.allCookies);
}
function wD(e) {
  return {
    id: hr(),
    browserID: Vp,
    browserName: "Telegram Desktop",
    profileName: "Default",
    platformNetwork: "telegram",
    platformDisplayName: "Telegram",
    userDisplayText: "Telegram Desktop",
    loginFlowID: $E,
    tdataPath: e,
  };
}
async function dC(e, t) {
  const o = tn.get(e);
  if (o) return Pd(o);
  if (t) return Pd(wD(t));
  const i = Xt.get(e);
  if (!i)
    return {
      deleted: !1,
      error:
        "Browser import candidate is no longer available, so source cookies could not be deleted.",
    };
  const a = { browserID: i.browserID, browserName: i.browserName };
  if (!hD(i.platformConfig))
    return (Xt.delete(e), { deleted: !1, kept: !0, ...a });
  const n = fv(i);
  if (Bo.has(n)) return (Xt.delete(e), { deleted: !0, ...a });
  try {
    const r = await jv(i);
    r.deleted && (Bo.add(n), Xt.delete(e));
    const s = qv(r);
    return {
      ...r,
      ...a,
      retryable: s,
      reason: mD(r) ?? (!r.deleted && zs(i) ? "manual-removal" : void 0),
    };
  } catch (r) {
    logger.warn(
      "[BrowserSessionImport] Failed to delete source browser data",
      r,
    );
    const s = r instanceof Error ? r.message : String(r),
      u = gD(s) || _d(s);
    return {
      deleted: !1,
      error: s,
      ...a,
      retryable: u,
      reason: _d(s)
        ? "access-required"
        : u
          ? "browser-running"
          : zs(i)
            ? "manual-removal"
            : void 0,
    };
  }
}
let Od = Promise.resolve();
function vu(e) {
  const t = Od.then(e, e);
  return (
    (Od = t.then(
      () => {},
      () => {},
    )),
    t
  );
}
async function Cu() {
  try {
    const e = await Te.readFile(Vs, "utf8"),
      t = JSON.parse(e);
    return Array.isArray(t)
      ? t.filter((o) => !!o && typeof o.tdataPath == "string")
      : [];
  } catch {
    return [];
  }
}
async function Au(e, { throwOnError: t = !1 } = {}) {
  try {
    if (e.length === 0) {
      await Te.rm(Vs, { force: !0 });
      return;
    }
    await Te.writeFile(Vs, JSON.stringify(e), "utf8");
  } catch (o) {
    if (
      (logger.warn(
        "[BrowserSessionImport] Failed to persist Telegram Desktop pending cleanup",
        o,
      ),
      t)
    )
      throw o;
  }
}
function hC(e) {
  return vu(async () => {
    const t = rn(e.tdataPath),
      o = await Cu();
    o.some((i) => rn(i.tdataPath) === t) ||
      (o.push({
        tdataPath: e.tdataPath,
        browserID: e.browserID,
        browserName: e.browserName,
      }),
      await Au(o, { throwOnError: !0 }));
  });
}
function pC(e) {
  return vu(async () => {
    const t = rn(e),
      o = await Cu(),
      i = o.filter((a) => rn(a.tdataPath) !== t);
    i.length !== o.length && (await Au(i));
  });
}
function yD(e) {
  for (const [t, o] of tn) o.tdataPath === e && tn.delete(t);
}
function ED() {
  return vu(async () => {
    const e = await Cu();
    if (e.length === 0) return;
    const t = [];
    for (const o of e)
      try {
        if (!(await Xn(o.tdataPath))) continue;
        if (!(await Jp(o.tdataPath))) {
          t.push(o);
          continue;
        }
        if (await Yt(o.browserID)) {
          t.push(o);
          continue;
        }
        (await Te.rm(o.tdataPath, { recursive: !0, force: !0 }),
          yD(o.tdataPath),
          logger.log(
            "[BrowserSessionImport] Removed leftover Telegram Desktop tdata on cleanup sweep",
          ));
      } catch (i) {
        (logger.warn(
          "[BrowserSessionImport] Failed to remove leftover Telegram Desktop tdata on sweep",
          i,
        ),
          t.push(o));
      }
    t.length !== e.length && (await Au(t));
  });
}
async function Pd(e) {
  const t = { browserID: e.browserID, browserName: e.browserName };
  if (!(await Jp(e.tdataPath)))
    return {
      deleted: !1,
      error: "Telegram Desktop tdata path is not in a known location.",
      ...t,
      reason: "source-data-removal",
    };
  try {
    await hC(e);
  } catch (o) {
    return (
      logger.warn(
        "[BrowserSessionImport] Could not persist Telegram Desktop cleanup record; refusing to delete",
        o,
      ),
      {
        deleted: !1,
        error:
          "Could not save a cleanup record, so the source session was not removed. Retry cleanup.",
        ...t,
        retryable: !0,
      }
    );
  }
  if (await Yt(e.browserID))
    return {
      deleted: !1,
      error:
        "Telegram Desktop must be quit before the source session can be cleaned up.",
      ...t,
      retryable: !0,
      reason: "browser-running",
    };
  try {
    return (
      await Te.rm(e.tdataPath, { recursive: !0, force: !0 }),
      yD(e.tdataPath),
      await pC(e.tdataPath),
      { deleted: !0, ...t }
    );
  } catch (o) {
    return (
      logger.warn(
        "[BrowserSessionImport] Failed to delete Telegram Desktop source session",
        o,
      ),
      {
        deleted: !1,
        error: o instanceof Error ? o.message : String(o),
        ...t,
        reason: "source-data-removal",
      }
    );
  }
}
function DC() {
  (Xt.clear(), tn.clear(), Bo.clear());
}
const ft = new Map(),
  Ts = () => {
    const e = ft.size > 0;
    try {
      mainWindow?.window.webContents.setBackgroundThrottling(!e);
    } catch (t) {
      logger.error("[app:updateMainBackgroundThrottling]", t);
    }
  };
function bu() {
  for (const e of ft.values()) e.hide();
  mainWindow?.hide();
}
function vD() {
  for (const e of ft.values()) e.show();
  mainWindow?.show();
}
const mC = () => {
    const e = ye.getSystemLocale();
    return /^[a-z]{2,3}(?:-[A-Z]{2,3})?/.exec(e)?.[0] ?? "en-US";
  },
  CD = G.join(lt, "linkpreviews"),
  gC = G.join(lt, "temp_avatar_uploads"),
  Xs = new nu({ configName: "app-state", cwd: lt }),
  Mn = () => Xs.set("lastAliveAt", Date.now()),
  Rd = (e) => (cr ? e : e.toLowerCase());
function wC(e) {
  const t = Rd(G.normalize(e));
  return [lt, Jn, $o].some((o) => {
    const i = G.relative(Rd(G.normalize(o)), t);
    return i === "" || (!i.startsWith("..") && !G.isAbsolute(i));
  });
}
function yC(e) {
  ut("launchApp()");
  const t = Xs.get("lastAliveAt", 0) || Xs.get("lastQuitAt", 0),
    o = Vr.wasGracefulExit(t);
  (Mn(), setInterval(Mn, 3e4));
  function i() {
    let l = !1;
    (Bt.once("renderer-ready", () => {
      (logger.log(
        "shown window in",
        Date.now() - globalThis.MAIN_BOOT_TIME,
        "ms",
      ),
        It.launch_app_minimized || mainWindow?.show(),
        (l = !0));
    }),
      setTimeout(() => {
        l ||
          (mainWindow
            ? logger.log("showing main window from fallback timeout")
            : logger.error(
                "tried to show main window from fallback timeout, but no main window yet",
              ),
          It.launch_app_minimized || mainWindow?.show());
      }, 3e3),
      setTimeout(() => {
        l || kt("launch", "frontend not ready after 10s, may have crashed");
      }, 1e4));
  }
  async function a() {
    ut("createMainWindow()");
    const {
        pasClientHostname: l,
        pasAdvertisedHostname: h,
        pasPort: y,
        transportNonce: F,
      } = await e,
      m = `${l}:${y}`,
      S = `http://${m}`;
    (Pr || Yg) && fE(S);
    const E = `${h}:${y}`,
      b = `http://${E}`;
    function w() {
      const C = G.join(tu, "../..");
      return yt
        ? Zm
          ? `${S}/_app/`
          : Mt.pathToFileURL(G.join(C, "build-browser/index.html")).href
        : Mt.pathToFileURL(G.join(C, "build/renderer/index.html")).href;
    }
    const v =
      `${w()}?appVersion=${ye.getVersion()}#` +
      new URLSearchParams({
        lastSessionAliveUntil: String(t),
        previousSessionExitedCleanly: String(o),
        osBootTime: String(Date.now() - Ke.uptime() * 1e3),
        appBootTime: String(globalThis.MAIN_BOOT_TIME),
        machineID: globalThis.MACHINE_ID,
        logLevel: globalThis.LOG_LEVEL,
        transportNonce: F,
        pasHost: m,
        pasOrigin: S,
        pasAdvertisedHost: E,
        pasAdvertisedOrigin: b,
        userDataDirPath: lt,
        appPath: $o,
        downloadsPath: Xh,
        systemLocale: mC(),
        timeFormat: await UE(),
        countryCode: ye.getLocaleCountryCode(),
        serverEnv: Kn,
        ...(process.env.BEEPER_SMOKE_TEST ? { smokeTest: "true" } : {}),
      }).toString();
    if (yt) {
      for (; !globalThis.pas;) await Xi(20);
      await globalThis.pas.initPromise;
      const { default: C } = await import("./main-window-shim-B_M14ZVI.mjs");
      mainWindow = C();
    } else mainWindow = mE();
    (Ts(),
      vd({ window: mainWindow.window }),
      i(),
      Qs("main loadURL"),
      mainWindow.loadURL(v),
      mainWindow.window,
      mainWindow.window.on("session-end", () => {
        (Mn(), Vr.markGracefulExit());
      }),
      mainWindow.window.webContents.on("will-navigate", (C) => {
        C.isMainFrame && Wn.saveFromWindowIds(ft.keys());
      }));
  }
  const n = new Set();
  function r() {
    Cm.registerFileProtocol("fileproxy", (l, h) => {
      const y = Mt.fileURLToPath(Jm(l.url));
      wC(y) || logger.warn("fileproxy: path outside app directories", y);
      const F = new URL(l.url).searchParams.get("mimeType");
      (h({ path: y, mimeType: F && Qm.has(F) ? F : void 0 }),
        Te.access(y).catch(() => {
          n.has(y) ||
            (n.size >= 200 && n.clear(),
            n.add(y),
            logger.warn("fileproxy: file missing", y));
        }));
    });
  }
  async function s() {
    if (
      (ut("onReady() app is ready"),
      st.on("suspend", Mn),
      Kt &&
        (logger.log(
          "Calling app.setAppUserModelId",
          "com.automattic.beeper.desktop",
        ),
        ye.setAppUserModelId("com.automattic.beeper.desktop"),
        process.env.APPDATA))
    ) {
      const l = ye.getName(),
        h = `${l}.lnk`,
        y = G.join(
          process.env.APPDATA,
          "Microsoft/Windows/Start Menu/Programs",
          h,
        );
      try {
        await Te.access(y);
      } catch {
        logger.log("Recreating Start Menu shortcut");
        try {
          Dt.writeShortcutLink(y, "create", {
            target: process.execPath,
            description: l,
          }) || logger.warn("Failed to create Start Menu shortcut");
        } catch (F) {
          logger.error("Error creating Start Menu shortcut:", F);
        }
      }
    }
    if (
      (ut(`Using process.resourcePath = ${process.resourcesPath}`),
      r(),
      I0(),
      iE(),
      gE(),
      ED(),
      Ne &&
        Ll().catch((l) =>
          logger.error("[quick-look] failed to clear links", l),
        ),
      await v0().catch((l) => {
        logger.error("[storage-wipe] failed, will retry next boot", l);
      }),
      await a(),
      !mainWindow)
    ) {
      const l = "still no mainWindow after exiting createMainWindow";
      throw (logger.error(l), new Error(l));
    }
    if (
      (It.tray_icon_hidden || Mp(mainWindow, a),
      ut("TextsSwift.addPreferredScrollerStyleChangeListener()"),
      Re?.addPreferredScrollerStyleChangeListener((l) => {
        mainWindow?.sendMessage("scroller-style-changed", l);
      }),
      ey().catch((l) =>
        logger.error("[Updates] [Startup] logPendingUpdateState error:", l),
      ),
      M0(mainWindow),
      Jg(),
      L0(mainWindow),
      Bt.on("show-tray-icon-toggled", (l, h) => {
        mainWindow && dy(mainWindow, a, h);
      }),
      cr)
    ) {
      const { registerLinuxConfig: l } = await import("./linux-CA0yDWdQ.mjs");
      await l();
    }
    cg && mainWindow.window.webContents.openDevTools({ mode: "detach" });
  }
  function u(l) {
    mainWindow
      ? mainWindow.sendMessage("deep-link", l)
      : setTimeout(() => {
          u(l);
        }, 3e3);
  }
  (ye.setName(tt.APP_NAME),
    cr && ye.setDesktopName?.(`${tt.APP_NAME}.desktop`),
    ye.setAboutPanelOptions({
      applicationName: tt.APP_NAME,
      version: Ve.version,
      applicationVersion: Ve.version,
    }),
    ut("Waiting for app to be ready"),
    ye.whenReady().then(s));
  function f(l) {
    const h = "https://www.beeper.com/";
    l.webRequest.onBeforeSendHeaders(
      {
        urls: [
          "https://www.youtube.com/embed/*",
          "https://*.youtube.com/embed/*",
          "https://www.youtube-nocookie.com/embed/*",
          "https://*.youtube-nocookie.com/embed/*",
        ],
      },
      (y, F) => {
        if (y.resourceType !== "subFrame") {
          F({ requestHeaders: y.requestHeaders });
          return;
        }
        ((y.requestHeaders.Referer = h),
          F({ requestHeaders: y.requestHeaders }));
      },
    );
  }
  (ye.whenReady().then(() => f(fr.defaultSession)),
    ye.on("second-instance", (l, h, y, F) => {
      const m = F?.version;
      if (
        (logger.log("second instance", { argv: h, otherVersion: m }),
        m !== Ve.version)
      ) {
        (logger.log(
          `Version mismatch: running v${Ve.version}, second instance is v${m}`,
        ),
          kt(
            "version-conflict",
            `Running v${Ve.version}, attempted launch of v${m}`,
          ),
          Xe.showMessageBox({
            type: "warning",
            message: "Restart required",
            detail: `A different version of ${tt.APP_NAME} (${m}) was installed while ${Ve.version} was running. Please restart to use the updated version.`,
            buttons: ["Restart Now", "Later"],
            defaultId: 0,
          }).then(({ response: S }) => {
            S === 0 && Qn("version-conflict-second-instance");
          }));
        return;
      }
      ((Kt || cr) && u(h[h.length - 1]), mainWindow?.show());
    }),
    ye.on("activate", () => {
      mainWindow?.show();
    }),
    ye.on("open-url", (l, h) => {
      (l.preventDefault(), u(h));
    }),
    ye.on("web-contents-created", (l, h) => {
      (h.on("did-create-window", (y, { frameName: F }) => {
        try {
          const m = F;
          if (!m) return;
          (ft.set(m, new kE(m, y)), Wn.saveFromWindowIds(ft.keys()), Ts());
          const S = vd({ window: y });
          (y.on("closed", () => {
            (ft.delete(m), Wn.saveFromWindowIds(ft.keys()), Ts(), S());
          }),
            y.on("enter-full-screen", () =>
              mainWindow?.rs.setFullScreened(!0, m),
            ),
            y.on("leave-full-screen", () =>
              mainWindow?.rs.setFullScreened(!1, m),
            ));
        } catch (m) {
          logger.error("[app:did-create-window]", m);
        }
      }),
        h.setWindowOpenHandler(({ url: y, frameName: F, features: m }) => {
          if (!["about:blank", Rg, Lg].includes(y))
            return (Dt.openExternal(y), { action: "deny" });
          if (F === "picture-in-picture")
            return {
              action: "allow",
              overrideBrowserWindowOptions: {
                show: !1,
                hasShadow: !1,
                minWidth: 150,
                minHeight: 150,
              },
            };
          const E = /trafficLightX=([\d.]+)/.exec(m),
            b = /trafficLightY=([\d.]+)/.exec(m),
            w = Ne && (E || b),
            A = m.includes("alwaysOnTop=true"),
            v = !m.includes("resizable=false") && !m.includes("resizable=no");
          return {
            action: "allow",
            overrideBrowserWindowOptions: {
              ...Ki,
              ...(w && {
                trafficLightPosition: {
                  x: E ? Number(E[1]) : Ki.trafficLightPosition.x,
                  y: b ? Number(b[1]) : Ki.trafficLightPosition.y,
                },
              }),
              ...(A && { alwaysOnTop: A }),
              resizable: v,
            },
          };
        }));
    }));
  let d = !1;
  async function c() {
    if ($s.isQuittingForUpdate) {
      d = !0;
      return;
    }
    if (!mainWindow) return;
    const l = await Promise.race([
      mainWindow.rs.getFirstThreadWithPendingMessages().catch(() => {}),
      Xi(500).then(() => {}),
    ]);
    if (
      l &&
      !(
        await Xe.showMessageBox({
          message: "Message sending is in progress",
          buttons: ["Show chat", "Save draft and quit"],
          defaultId: 0,
        })
      ).response
    )
      return (
        mainWindow.show(),
        mainWindow.rs.selectThreadByID(l.accountID, l.threadID),
        !0
      );
    d = !0;
  }
  (ye.on("before-quit", async (l) => {
    if (
      (logger.log("[App] before-quit fired"),
      yt || l.preventDefault(),
      Mn(),
      Wn.saveFromWindowIds(ft.keys()),
      Te.rm(CD, { recursive: !0, force: !0 }).catch((h) => {
        logger.error("Failed to remove link previews", h);
      }),
      Te.rm(gC, { recursive: !0, force: !0 }).catch((h) => {
        logger.error("Failed to remove temp avatar uploads", h);
      }),
      Ll().catch((h) => {
        logger.error("Failed to remove quick look links", h);
      }),
      Vr.markGracefulExit(),
      yt)
    ) {
      (await Vr.closeAll(), await Ju());
      return;
    }
    if (
      (logger.log("[App] before-quit: checking didUserCancelQuit"),
      !(await c()))
    ) {
      (Re?.removeAllDeliveredNotifications(),
        logger.log("[App] before-quit: starting cleanup"));
      try {
        fr.defaultSession.flushStorageData();
      } catch (y) {
        logger.error("[App] flushStorageData failed", y);
      }
      let h = !1;
      (await Promise.race([
        Promise.allSettled([
          Vr.closeAll().then(() => logger.log("[App] RollingLogger closed")),
          Ju().then(() => logger.log("[App] sendEvents done")),
          Sm().then(() => logger.log("[App] cleanupWorkers done")),
        ]),
        Xi(3e3).then(() => {
          ((h = !0),
            logger.log("[App] before-quit: cleanup timed out after 3s"));
        }),
      ]),
        logger.log("[App] before-quit cleanup complete, exiting"),
        await Qr(h));
    }
  }),
    ye.on("will-quit", async (l) => {
      d ||
        (l.preventDefault(),
        yt && !(await c()) && (Re?.removeAllDeliveredNotifications(), Qr()));
    }),
    ye.on("window-all-closed", () => {
      Ne || ye.quit();
    }));
}
const EC = Object.freeze(
    Object.defineProperty(
      {
        __proto__: null,
        childWindows: ft,
        default: yC,
        hideAllWindows: bu,
        linkPreviewAttachmentsPath: CD,
        showAllWindows: vD,
      },
      Symbol.toStringTag,
      { value: "Module" },
    ),
  ),
  vC = ko(import.meta.dirname, "./heic-worker-_2D1HbZ5.mjs");
let Hn,
  ji,
  CC = 0;
const nn = new Map(),
  AC = (e) => {
    for (const { reject: t } of nn.values()) t(e);
    nn.clear();
  },
  bC = () => (
    Hn ||
      (ji = new Promise((e, t) => {
        const o = Th(xh.HEIC_WORKER, void 0, vC),
          i = (a) => {
            (_m("heic_worker failWorker", {
              threadId: o.threadId,
              message: a.message,
            }),
              Hn === o && ((Hn = void 0), (ji = void 0)),
              t(a),
              AC(a));
          };
        ((Hn = o),
          o
            .on(
              "message",
              ({ reqID: a, width: n, height: r, errorMessage: s }) => {
                const u = nn.get(a);
                u &&
                  (nn.delete(a),
                  s != null
                    ? u.reject(new Error(s))
                    : u.resolve({ width: n, height: r }));
              },
            )
            .on("error", (a) =>
              i(a instanceof Error ? a : new Error(String(a))),
            )
            .once("exit", (a) => i(new Error(`HEIC worker exited (code ${a})`)))
            .once("online", () => e()));
      })),
    ji
  );
async function FC(e, t, o) {
  await bC();
  const i = ++CC;
  return new Promise((a, n) => {
    nn.set(i, { resolve: a, reject: n });
    try {
      Hn.postMessage({ reqID: i, inputFilePath: e, outputPath: t, format: o });
    } catch (r) {
      (nn.delete(i), n(r instanceof Error ? r : new Error(String(r))));
    }
  });
}
const SC = new Set([
  "image/heic",
  "image/heif",
  "image/heic-sequence",
  "image/heif-sequence",
]);
var xs = {},
  Ns = {},
  Un = {},
  Gt = {},
  Tr = {},
  Ld;
function Ko() {
  if (Ld) return Tr;
  Ld = 1;
  function e(n, r, s) {
    if (
      (s === void 0 && (s = Array.prototype), n && typeof s.find == "function")
    )
      return s.find.call(n, r);
    for (var u = 0; u < n.length; u++)
      if (Object.prototype.hasOwnProperty.call(n, u)) {
        var f = n[u];
        if (r.call(void 0, f, u, n)) return f;
      }
  }
  function t(n, r) {
    return (
      r === void 0 && (r = Object),
      r && typeof r.freeze == "function" ? r.freeze(n) : n
    );
  }
  function o(n, r) {
    if (n === null || typeof n != "object")
      throw new TypeError("target is not an object");
    for (var s in r)
      Object.prototype.hasOwnProperty.call(r, s) && (n[s] = r[s]);
    return n;
  }
  var i = t({
      HTML: "text/html",
      isHTML: function (n) {
        return n === i.HTML;
      },
      XML_APPLICATION: "application/xml",
      XML_TEXT: "text/xml",
      XML_XHTML_APPLICATION: "application/xhtml+xml",
      XML_SVG_IMAGE: "image/svg+xml",
    }),
    a = t({
      HTML: "http://www.w3.org/1999/xhtml",
      isHTML: function (n) {
        return n === a.HTML;
      },
      SVG: "http://www.w3.org/2000/svg",
      XML: "http://www.w3.org/XML/1998/namespace",
      XMLNS: "http://www.w3.org/2000/xmlns/",
    });
  return (
    (Tr.assign = o),
    (Tr.find = e),
    (Tr.freeze = t),
    (Tr.MIME_TYPE = i),
    (Tr.NAMESPACE = a),
    Tr
  );
}
var Bd;
function AD() {
  if (Bd) return Gt;
  Bd = 1;
  var e = Ko(),
    t = e.find,
    o = e.NAMESPACE;
  function i(T) {
    return T !== "";
  }
  function a(T) {
    return T ? T.split(/[\t\n\f\r ]+/).filter(i) : [];
  }
  function n(T, x) {
    return (T.hasOwnProperty(x) || (T[x] = !0), T);
  }
  function r(T) {
    if (!T) return [];
    var x = a(T);
    return Object.keys(x.reduce(n, {}));
  }
  function s(T) {
    return function (x) {
      return T && T.indexOf(x) !== -1;
    };
  }
  function u(T, x) {
    for (var B in T)
      Object.prototype.hasOwnProperty.call(T, B) && (x[B] = T[B]);
  }
  function f(T, x) {
    var B = T.prototype;
    if (!(B instanceof x)) {
      let H = function () {};
      ((H.prototype = x.prototype),
        (H = new H()),
        u(B, H),
        (T.prototype = B = H));
    }
    B.constructor != T &&
      (typeof T != "function" && console.error("unknown Class:" + T),
      (B.constructor = T));
  }
  var d = {},
    c = (d.ELEMENT_NODE = 1),
    l = (d.ATTRIBUTE_NODE = 2),
    h = (d.TEXT_NODE = 3),
    y = (d.CDATA_SECTION_NODE = 4),
    F = (d.ENTITY_REFERENCE_NODE = 5),
    m = (d.ENTITY_NODE = 6),
    S = (d.PROCESSING_INSTRUCTION_NODE = 7),
    E = (d.COMMENT_NODE = 8),
    b = (d.DOCUMENT_NODE = 9),
    w = (d.DOCUMENT_TYPE_NODE = 10),
    A = (d.DOCUMENT_FRAGMENT_NODE = 11),
    v = (d.NOTATION_NODE = 12),
    C = {},
    g = {};
  ((C.INDEX_SIZE_ERR = ((g[1] = "Index size error"), 1)),
    (C.DOMSTRING_SIZE_ERR = ((g[2] = "DOMString size error"), 2)));
  var D = (C.HIERARCHY_REQUEST_ERR = ((g[3] = "Hierarchy request error"), 3));
  ((C.WRONG_DOCUMENT_ERR = ((g[4] = "Wrong document"), 4)),
    (C.INVALID_CHARACTER_ERR = ((g[5] = "Invalid character"), 5)),
    (C.NO_DATA_ALLOWED_ERR = ((g[6] = "No data allowed"), 6)),
    (C.NO_MODIFICATION_ALLOWED_ERR = ((g[7] = "No modification allowed"), 7)));
  var N = (C.NOT_FOUND_ERR = ((g[8] = "Not found"), 8));
  C.NOT_SUPPORTED_ERR = ((g[9] = "Not supported"), 9);
  var P = (C.INUSE_ATTRIBUTE_ERR = ((g[10] = "Attribute in use"), 10));
  ((C.INVALID_STATE_ERR = ((g[11] = "Invalid state"), 11)),
    (C.SYNTAX_ERR = ((g[12] = "Syntax error"), 12)),
    (C.INVALID_MODIFICATION_ERR = ((g[13] = "Invalid modification"), 13)),
    (C.NAMESPACE_ERR = ((g[14] = "Invalid namespace"), 14)),
    (C.INVALID_ACCESS_ERR = ((g[15] = "Invalid access"), 15)));
  function R(T, x) {
    if (x instanceof Error) var B = x;
    else
      ((B = this),
        Error.call(this, g[T]),
        (this.message = g[T]),
        Error.captureStackTrace && Error.captureStackTrace(this, R));
    return ((B.code = T), x && (this.message = this.message + ": " + x), B);
  }
  ((R.prototype = Error.prototype), u(C, R));
  function k() {}
  k.prototype = {
    length: 0,
    item: function (T) {
      return T >= 0 && T < this.length ? this[T] : null;
    },
    toString: function (T, x) {
      for (var B = [], H = 0; H < this.length; H++) Z(this[H], B, T, x);
      return B.join("");
    },
    filter: function (T) {
      return Array.prototype.filter.call(this, T);
    },
    indexOf: function (T) {
      return Array.prototype.indexOf.call(this, T);
    },
  };
  function q(T, x) {
    ((this._node = T), (this._refresh = x), U(this));
  }
  function U(T) {
    var x = T._node._inc || T._node.ownerDocument._inc;
    if (T._inc !== x) {
      var B = T._refresh(T._node);
      if ((ve(T, "length", B.length), !T.$$length || B.length < T.$$length))
        for (var H = B.length; H in T; H++)
          Object.prototype.hasOwnProperty.call(T, H) && delete T[H];
      (u(B, T), (T._inc = x));
    }
  }
  ((q.prototype.item = function (T) {
    return (U(this), this[T] || null);
  }),
    f(q, k));
  function $() {}
  function V(T, x) {
    for (var B = T.length; B--;) if (T[B] === x) return B;
  }
  function re(T, x, B, H) {
    if ((H ? (x[V(x, H)] = B) : (x[x.length++] = B), T)) {
      B.ownerElement = T;
      var ie = T.ownerDocument;
      ie && (H && ge(ie, T, H), Q(ie, T, B));
    }
  }
  function X(T, x, B) {
    var H = V(x, B);
    if (H >= 0) {
      for (var ie = x.length - 1; H < ie;) x[H] = x[++H];
      if (((x.length = ie), T)) {
        var pe = T.ownerDocument;
        pe && (ge(pe, T, B), (B.ownerElement = null));
      }
    } else throw new R(N, new Error(T.tagName + "@" + B));
  }
  $.prototype = {
    length: 0,
    item: k.prototype.item,
    getNamedItem: function (T) {
      for (var x = this.length; x--;) {
        var B = this[x];
        if (B.nodeName == T) return B;
      }
    },
    setNamedItem: function (T) {
      var x = T.ownerElement;
      if (x && x != this._ownerElement) throw new R(P);
      var B = this.getNamedItem(T.nodeName);
      return (re(this._ownerElement, this, T, B), B);
    },
    setNamedItemNS: function (T) {
      var x = T.ownerElement,
        B;
      if (x && x != this._ownerElement) throw new R(P);
      return (
        (B = this.getNamedItemNS(T.namespaceURI, T.localName)),
        re(this._ownerElement, this, T, B),
        B
      );
    },
    removeNamedItem: function (T) {
      var x = this.getNamedItem(T);
      return (X(this._ownerElement, this, x), x);
    },
    removeNamedItemNS: function (T, x) {
      var B = this.getNamedItemNS(T, x);
      return (X(this._ownerElement, this, B), B);
    },
    getNamedItemNS: function (T, x) {
      for (var B = this.length; B--;) {
        var H = this[B];
        if (H.localName == x && H.namespaceURI == T) return H;
      }
      return null;
    },
  };
  function fe() {}
  fe.prototype = {
    hasFeature: function (T, x) {
      return !0;
    },
    createDocument: function (T, x, B) {
      var H = new Ae();
      if (
        ((H.implementation = this),
        (H.childNodes = new k()),
        (H.doctype = B || null),
        B && H.appendChild(B),
        x)
      ) {
        var ie = H.createElementNS(T, x);
        H.appendChild(ie);
      }
      return H;
    },
    createDocumentType: function (T, x, B) {
      var H = new ae();
      return (
        (H.name = T),
        (H.nodeName = T),
        (H.publicId = x || ""),
        (H.systemId = B || ""),
        H
      );
    },
  };
  function Y() {}
  Y.prototype = {
    firstChild: null,
    lastChild: null,
    previousSibling: null,
    nextSibling: null,
    attributes: null,
    parentNode: null,
    childNodes: null,
    ownerDocument: null,
    nodeValue: null,
    namespaceURI: null,
    prefix: null,
    localName: null,
    insertBefore: function (T, x) {
      return nt(this, T, x);
    },
    replaceChild: function (T, x) {
      (nt(this, T, x, Ge), x && this.removeChild(x));
    },
    removeChild: function (T) {
      return _(this, T);
    },
    appendChild: function (T) {
      return this.insertBefore(T, null);
    },
    hasChildNodes: function () {
      return this.firstChild != null;
    },
    cloneNode: function (T) {
      return se(this.ownerDocument || this, this, T);
    },
    normalize: function () {
      for (var T = this.firstChild; T;) {
        var x = T.nextSibling;
        x && x.nodeType == h && T.nodeType == h
          ? (this.removeChild(x), T.appendData(x.data))
          : (T.normalize(), (T = x));
      }
    },
    isSupported: function (T, x) {
      return this.ownerDocument.implementation.hasFeature(T, x);
    },
    hasAttributes: function () {
      return this.attributes.length > 0;
    },
    lookupPrefix: function (T) {
      for (var x = this; x;) {
        var B = x._nsMap;
        if (B) {
          for (var H in B)
            if (Object.prototype.hasOwnProperty.call(B, H) && B[H] === T)
              return H;
        }
        x = x.nodeType == l ? x.ownerDocument : x.parentNode;
      }
      return null;
    },
    lookupNamespaceURI: function (T) {
      for (var x = this; x;) {
        var B = x._nsMap;
        if (B && Object.prototype.hasOwnProperty.call(B, T)) return B[T];
        x = x.nodeType == l ? x.ownerDocument : x.parentNode;
      }
      return null;
    },
    isDefaultNamespace: function (T) {
      var x = this.lookupPrefix(T);
      return x == null;
    },
  };
  function Ce(T) {
    return (
      (T == "<" && "&lt;") ||
      (T == ">" && "&gt;") ||
      (T == "&" && "&amp;") ||
      (T == '"' && "&quot;") ||
      "&#" + T.charCodeAt() + ";"
    );
  }
  (u(d, Y), u(d, Y.prototype));
  function ue(T, x) {
    if (x(T)) return !0;
    if ((T = T.firstChild))
      do if (ue(T, x)) return !0;
      while ((T = T.nextSibling));
  }
  function Ae() {
    this.ownerDocument = this;
  }
  function Q(T, x, B) {
    T && T._inc++;
    var H = B.namespaceURI;
    H === o.XMLNS && (x._nsMap[B.prefix ? B.localName : ""] = B.value);
  }
  function ge(T, x, B, H) {
    T && T._inc++;
    var ie = B.namespaceURI;
    ie === o.XMLNS && delete x._nsMap[B.prefix ? B.localName : ""];
  }
  function I(T, x, B) {
    if (T && T._inc) {
      T._inc++;
      var H = x.childNodes;
      if (B) H[H.length++] = B;
      else {
        for (var ie = x.firstChild, pe = 0; ie;)
          ((H[pe++] = ie), (ie = ie.nextSibling));
        ((H.length = pe), delete H[H.length]);
      }
    }
  }
  function _(T, x) {
    var B = x.previousSibling,
      H = x.nextSibling;
    return (
      B ? (B.nextSibling = H) : (T.firstChild = H),
      H ? (H.previousSibling = B) : (T.lastChild = B),
      (x.parentNode = null),
      (x.previousSibling = null),
      (x.nextSibling = null),
      I(T.ownerDocument, T),
      x
    );
  }
  function W(T) {
    return (
      T &&
      (T.nodeType === Y.DOCUMENT_NODE ||
        T.nodeType === Y.DOCUMENT_FRAGMENT_NODE ||
        T.nodeType === Y.ELEMENT_NODE)
    );
  }
  function M(T) {
    return (
      T &&
      (he(T) ||
        we(T) ||
        le(T) ||
        T.nodeType === Y.DOCUMENT_FRAGMENT_NODE ||
        T.nodeType === Y.COMMENT_NODE ||
        T.nodeType === Y.PROCESSING_INSTRUCTION_NODE)
    );
  }
  function le(T) {
    return T && T.nodeType === Y.DOCUMENT_TYPE_NODE;
  }
  function he(T) {
    return T && T.nodeType === Y.ELEMENT_NODE;
  }
  function we(T) {
    return T && T.nodeType === Y.TEXT_NODE;
  }
  function be(T, x) {
    var B = T.childNodes || [];
    if (t(B, he) || le(x)) return !1;
    var H = t(B, le);
    return !(x && H && B.indexOf(H) > B.indexOf(x));
  }
  function Fe(T, x) {
    var B = T.childNodes || [];
    function H(pe) {
      return he(pe) && pe !== x;
    }
    if (t(B, H)) return !1;
    var ie = t(B, le);
    return !(x && ie && B.indexOf(ie) > B.indexOf(x));
  }
  function Oe(T, x, B) {
    if (!W(T)) throw new R(D, "Unexpected parent node type " + T.nodeType);
    if (B && B.parentNode !== T) throw new R(N, "child not in parent");
    if (!M(x) || (le(x) && T.nodeType !== Y.DOCUMENT_NODE))
      throw new R(
        D,
        "Unexpected node type " +
          x.nodeType +
          " for parent node type " +
          T.nodeType,
      );
  }
  function Le(T, x, B) {
    var H = T.childNodes || [],
      ie = x.childNodes || [];
    if (x.nodeType === Y.DOCUMENT_FRAGMENT_NODE) {
      var pe = ie.filter(he);
      if (pe.length > 1 || t(ie, we))
        throw new R(D, "More than one element or text in fragment");
      if (pe.length === 1 && !be(T, B))
        throw new R(
          D,
          "Element in fragment can not be inserted before doctype",
        );
    }
    if (he(x) && !be(T, B))
      throw new R(D, "Only one element can be added and only after doctype");
    if (le(x)) {
      if (t(H, le)) throw new R(D, "Only one doctype is allowed");
      var Be = t(H, he);
      if (B && H.indexOf(Be) < H.indexOf(B))
        throw new R(D, "Doctype can only be inserted before an element");
      if (!B && Be)
        throw new R(D, "Doctype can not be appended since element is present");
    }
  }
  function Ge(T, x, B) {
    var H = T.childNodes || [],
      ie = x.childNodes || [];
    if (x.nodeType === Y.DOCUMENT_FRAGMENT_NODE) {
      var pe = ie.filter(he);
      if (pe.length > 1 || t(ie, we))
        throw new R(D, "More than one element or text in fragment");
      if (pe.length === 1 && !Fe(T, B))
        throw new R(
          D,
          "Element in fragment can not be inserted before doctype",
        );
    }
    if (he(x) && !Fe(T, B))
      throw new R(D, "Only one element can be added and only after doctype");
    if (le(x)) {
      if (
        t(H, function (Ze) {
          return le(Ze) && Ze !== B;
        })
      )
        throw new R(D, "Only one doctype is allowed");
      var Be = t(H, he);
      if (B && H.indexOf(Be) < H.indexOf(B))
        throw new R(D, "Doctype can only be inserted before an element");
    }
  }
  function nt(T, x, B, H) {
    (Oe(T, x, B), T.nodeType === Y.DOCUMENT_NODE && (H || Le)(T, x, B));
    var ie = x.parentNode;
    if ((ie && ie.removeChild(x), x.nodeType === A)) {
      var pe = x.firstChild;
      if (pe == null) return x;
      var Be = x.lastChild;
    } else pe = Be = x;
    var Me = B ? B.previousSibling : T.lastChild;
    ((pe.previousSibling = Me),
      (Be.nextSibling = B),
      Me ? (Me.nextSibling = pe) : (T.firstChild = pe),
      B == null ? (T.lastChild = Be) : (B.previousSibling = Be));
    do pe.parentNode = T;
    while (pe !== Be && (pe = pe.nextSibling));
    return (
      I(T.ownerDocument || T, T),
      x.nodeType == A && (x.firstChild = x.lastChild = null),
      x
    );
  }
  function ht(T, x) {
    return (
      x.parentNode && x.parentNode.removeChild(x),
      (x.parentNode = T),
      (x.previousSibling = T.lastChild),
      (x.nextSibling = null),
      x.previousSibling
        ? (x.previousSibling.nextSibling = x)
        : (T.firstChild = x),
      (T.lastChild = x),
      I(T.ownerDocument, T, x),
      x
    );
  }
  ((Ae.prototype = {
    nodeName: "#document",
    nodeType: b,
    doctype: null,
    documentElement: null,
    _inc: 1,
    insertBefore: function (T, x) {
      if (T.nodeType == A) {
        for (var B = T.firstChild; B;) {
          var H = B.nextSibling;
          (this.insertBefore(B, x), (B = H));
        }
        return T;
      }
      return (
        nt(this, T, x),
        (T.ownerDocument = this),
        this.documentElement === null &&
          T.nodeType === c &&
          (this.documentElement = T),
        T
      );
    },
    removeChild: function (T) {
      return (
        this.documentElement == T && (this.documentElement = null),
        _(this, T)
      );
    },
    replaceChild: function (T, x) {
      (nt(this, T, x, Ge),
        (T.ownerDocument = this),
        x && this.removeChild(x),
        he(T) && (this.documentElement = T));
    },
    importNode: function (T, x) {
      return oe(this, T, x);
    },
    getElementById: function (T) {
      var x = null;
      return (
        ue(this.documentElement, function (B) {
          if (B.nodeType == c && B.getAttribute("id") == T)
            return ((x = B), !0);
        }),
        x
      );
    },
    getElementsByClassName: function (T) {
      var x = r(T);
      return new q(this, function (B) {
        var H = [];
        return (
          x.length > 0 &&
            ue(B.documentElement, function (ie) {
              if (ie !== B && ie.nodeType === c) {
                var pe = ie.getAttribute("class");
                if (pe) {
                  var Be = T === pe;
                  if (!Be) {
                    var Me = r(pe);
                    Be = x.every(s(Me));
                  }
                  Be && H.push(ie);
                }
              }
            }),
          H
        );
      });
    },
    createElement: function (T) {
      var x = new p();
      ((x.ownerDocument = this),
        (x.nodeName = T),
        (x.tagName = T),
        (x.localName = T),
        (x.childNodes = new k()));
      var B = (x.attributes = new $());
      return ((B._ownerElement = x), x);
    },
    createDocumentFragment: function () {
      var T = new Pe();
      return ((T.ownerDocument = this), (T.childNodes = new k()), T);
    },
    createTextNode: function (T) {
      var x = new de();
      return ((x.ownerDocument = this), x.appendData(T), x);
    },
    createComment: function (T) {
      var x = new ee();
      return ((x.ownerDocument = this), x.appendData(T), x);
    },
    createCDATASection: function (T) {
      var x = new ce();
      return ((x.ownerDocument = this), x.appendData(T), x);
    },
    createProcessingInstruction: function (T, x) {
      var B = new Ee();
      return (
        (B.ownerDocument = this),
        (B.tagName = B.nodeName = B.target = T),
        (B.nodeValue = B.data = x),
        B
      );
    },
    createAttribute: function (T) {
      var x = new z();
      return (
        (x.ownerDocument = this),
        (x.name = T),
        (x.nodeName = T),
        (x.localName = T),
        (x.specified = !0),
        x
      );
    },
    createEntityReference: function (T) {
      var x = new _e();
      return ((x.ownerDocument = this), (x.nodeName = T), x);
    },
    createElementNS: function (T, x) {
      var B = new p(),
        H = x.split(":"),
        ie = (B.attributes = new $());
      return (
        (B.childNodes = new k()),
        (B.ownerDocument = this),
        (B.nodeName = x),
        (B.tagName = x),
        (B.namespaceURI = T),
        H.length == 2
          ? ((B.prefix = H[0]), (B.localName = H[1]))
          : (B.localName = x),
        (ie._ownerElement = B),
        B
      );
    },
    createAttributeNS: function (T, x) {
      var B = new z(),
        H = x.split(":");
      return (
        (B.ownerDocument = this),
        (B.nodeName = x),
        (B.name = x),
        (B.namespaceURI = T),
        (B.specified = !0),
        H.length == 2
          ? ((B.prefix = H[0]), (B.localName = H[1]))
          : (B.localName = x),
        B
      );
    },
  }),
    f(Ae, Y));
  function p() {
    this._nsMap = {};
  }
  ((p.prototype = {
    nodeType: c,
    hasAttribute: function (T) {
      return this.getAttributeNode(T) != null;
    },
    getAttribute: function (T) {
      var x = this.getAttributeNode(T);
      return (x && x.value) || "";
    },
    getAttributeNode: function (T) {
      return this.attributes.getNamedItem(T);
    },
    setAttribute: function (T, x) {
      var B = this.ownerDocument.createAttribute(T);
      ((B.value = B.nodeValue = "" + x), this.setAttributeNode(B));
    },
    removeAttribute: function (T) {
      var x = this.getAttributeNode(T);
      x && this.removeAttributeNode(x);
    },
    appendChild: function (T) {
      return T.nodeType === A ? this.insertBefore(T, null) : ht(this, T);
    },
    setAttributeNode: function (T) {
      return this.attributes.setNamedItem(T);
    },
    setAttributeNodeNS: function (T) {
      return this.attributes.setNamedItemNS(T);
    },
    removeAttributeNode: function (T) {
      return this.attributes.removeNamedItem(T.nodeName);
    },
    removeAttributeNS: function (T, x) {
      var B = this.getAttributeNodeNS(T, x);
      B && this.removeAttributeNode(B);
    },
    hasAttributeNS: function (T, x) {
      return this.getAttributeNodeNS(T, x) != null;
    },
    getAttributeNS: function (T, x) {
      var B = this.getAttributeNodeNS(T, x);
      return (B && B.value) || "";
    },
    setAttributeNS: function (T, x, B) {
      var H = this.ownerDocument.createAttributeNS(T, x);
      ((H.value = H.nodeValue = "" + B), this.setAttributeNode(H));
    },
    getAttributeNodeNS: function (T, x) {
      return this.attributes.getNamedItemNS(T, x);
    },
    getElementsByTagName: function (T) {
      return new q(this, function (x) {
        var B = [];
        return (
          ue(x, function (H) {
            H !== x &&
              H.nodeType == c &&
              (T === "*" || H.tagName == T) &&
              B.push(H);
          }),
          B
        );
      });
    },
    getElementsByTagNameNS: function (T, x) {
      return new q(this, function (B) {
        var H = [];
        return (
          ue(B, function (ie) {
            ie !== B &&
              ie.nodeType === c &&
              (T === "*" || ie.namespaceURI === T) &&
              (x === "*" || ie.localName == x) &&
              H.push(ie);
          }),
          H
        );
      });
    },
  }),
    (Ae.prototype.getElementsByTagName = p.prototype.getElementsByTagName),
    (Ae.prototype.getElementsByTagNameNS = p.prototype.getElementsByTagNameNS),
    f(p, Y));
  function z() {}
  ((z.prototype.nodeType = l), f(z, Y));
  function J() {}
  ((J.prototype = {
    data: "",
    substringData: function (T, x) {
      return this.data.substring(T, T + x);
    },
    appendData: function (T) {
      ((T = this.data + T),
        (this.nodeValue = this.data = T),
        (this.length = T.length));
    },
    insertData: function (T, x) {
      this.replaceData(T, 0, x);
    },
    appendChild: function (T) {
      throw new Error(g[D]);
    },
    deleteData: function (T, x) {
      this.replaceData(T, x, "");
    },
    replaceData: function (T, x, B) {
      var H = this.data.substring(0, T),
        ie = this.data.substring(T + x);
      ((B = H + B + ie),
        (this.nodeValue = this.data = B),
        (this.length = B.length));
    },
  }),
    f(J, Y));
  function de() {}
  ((de.prototype = {
    nodeName: "#text",
    nodeType: h,
    splitText: function (T) {
      var x = this.data,
        B = x.substring(T);
      ((x = x.substring(0, T)),
        (this.data = this.nodeValue = x),
        (this.length = x.length));
      var H = this.ownerDocument.createTextNode(B);
      return (
        this.parentNode && this.parentNode.insertBefore(H, this.nextSibling),
        H
      );
    },
  }),
    f(de, J));
  function ee() {}
  ((ee.prototype = { nodeName: "#comment", nodeType: E }), f(ee, J));
  function ce() {}
  ((ce.prototype = { nodeName: "#cdata-section", nodeType: y }), f(ce, J));
  function ae() {}
  ((ae.prototype.nodeType = w), f(ae, Y));
  function De() {}
  ((De.prototype.nodeType = v), f(De, Y));
  function Se() {}
  ((Se.prototype.nodeType = m), f(Se, Y));
  function _e() {}
  ((_e.prototype.nodeType = F), f(_e, Y));
  function Pe() {}
  ((Pe.prototype.nodeName = "#document-fragment"),
    (Pe.prototype.nodeType = A),
    f(Pe, Y));
  function Ee() {}
  ((Ee.prototype.nodeType = S), f(Ee, Y));
  function je() {}
  ((je.prototype.serializeToString = function (T, x, B) {
    return O.call(T, x, B);
  }),
    (Y.prototype.toString = O));
  function O(T, x) {
    var B = [],
      H = (this.nodeType == 9 && this.documentElement) || this,
      ie = H.prefix,
      pe = H.namespaceURI;
    if (pe && ie == null) {
      var ie = H.lookupPrefix(pe);
      if (ie == null) var Be = [{ namespace: pe, prefix: null }];
    }
    return (Z(this, B, T, x, Be), B.join(""));
  }
  function K(T, x, B) {
    var H = T.prefix || "",
      ie = T.namespaceURI;
    if (!ie || (H === "xml" && ie === o.XML) || ie === o.XMLNS) return !1;
    for (var pe = B.length; pe--;) {
      var Be = B[pe];
      if (Be.prefix === H) return Be.namespace !== ie;
    }
    return !0;
  }
  function te(T, x, B) {
    T.push(" ", x, '="', B.replace(/[<>&"\t\n\r]/g, Ce), '"');
  }
  function Z(T, x, B, H, ie) {
    if ((ie || (ie = []), H))
      if (((T = H(T)), T)) {
        if (typeof T == "string") {
          x.push(T);
          return;
        }
      } else return;
    switch (T.nodeType) {
      case c:
        var pe = T.attributes,
          Be = pe.length,
          Je = T.firstChild,
          Me = T.tagName;
        B = o.isHTML(T.namespaceURI) || B;
        var Ze = Me;
        if (!B && !T.prefix && T.namespaceURI) {
          for (var Ot, St = 0; St < pe.length; St++)
            if (pe.item(St).name === "xmlns") {
              Ot = pe.item(St).value;
              break;
            }
          if (!Ot)
            for (var qt = ie.length - 1; qt >= 0; qt--) {
              var $t = ie[qt];
              if ($t.prefix === "" && $t.namespace === T.namespaceURI) {
                Ot = $t.namespace;
                break;
              }
            }
          if (Ot !== T.namespaceURI)
            for (var qt = ie.length - 1; qt >= 0; qt--) {
              var $t = ie[qt];
              if ($t.namespace === T.namespaceURI) {
                $t.prefix && (Ze = $t.prefix + ":" + Me);
                break;
              }
            }
        }
        x.push("<", Ze);
        for (var Pt = 0; Pt < Be; Pt++) {
          var pt = pe.item(Pt);
          pt.prefix == "xmlns"
            ? ie.push({ prefix: pt.localName, namespace: pt.value })
            : pt.nodeName == "xmlns" &&
              ie.push({ prefix: "", namespace: pt.value });
        }
        for (var Pt = 0; Pt < Be; Pt++) {
          var pt = pe.item(Pt);
          if (K(pt, B, ie)) {
            var ct = pt.prefix || "",
              mr = pt.namespaceURI;
            (te(x, ct ? "xmlns:" + ct : "xmlns", mr),
              ie.push({ prefix: ct, namespace: mr }));
          }
          Z(pt, x, B, H, ie);
        }
        if (Me === Ze && K(T, B, ie)) {
          var ct = T.prefix || "",
            mr = T.namespaceURI;
          (te(x, ct ? "xmlns:" + ct : "xmlns", mr),
            ie.push({ prefix: ct, namespace: mr }));
        }
        if (Je || (B && !/^(?:meta|link|img|br|hr|input)$/i.test(Me))) {
          if ((x.push(">"), B && /^script$/i.test(Me)))
            for (; Je;)
              (Je.data ? x.push(Je.data) : Z(Je, x, B, H, ie.slice()),
                (Je = Je.nextSibling));
          else for (; Je;) (Z(Je, x, B, H, ie.slice()), (Je = Je.nextSibling));
          x.push("</", Ze, ">");
        } else x.push("/>");
        return;
      case b:
      case A:
        for (var Je = T.firstChild; Je;)
          (Z(Je, x, B, H, ie.slice()), (Je = Je.nextSibling));
        return;
      case l:
        return te(x, T.name, T.value);
      case h:
        return x.push(T.data.replace(/[<&>]/g, Ce));
      case y:
        return x.push("<![CDATA[", T.data, "]]>");
      case E:
        return x.push("<!--", T.data, "-->");
      case w:
        var ui = T.publicId,
          Qt = T.systemId;
        if ((x.push("<!DOCTYPE ", T.name), ui))
          (x.push(" PUBLIC ", ui),
            Qt && Qt != "." && x.push(" ", Qt),
            x.push(">"));
        else if (Qt && Qt != ".") x.push(" SYSTEM ", Qt, ">");
        else {
          var li = T.internalSubset;
          (li && x.push(" [", li, "]"), x.push(">"));
        }
        return;
      case S:
        return x.push("<?", T.target, " ", T.data, "?>");
      case F:
        return x.push("&", T.nodeName, ";");
      default:
        x.push("??", T.nodeName);
    }
  }
  function oe(T, x, B) {
    var H;
    switch (x.nodeType) {
      case c:
        ((H = x.cloneNode(!1)), (H.ownerDocument = T));
      case A:
        break;
      case l:
        B = !0;
        break;
    }
    if (
      (H || (H = x.cloneNode(!1)),
      (H.ownerDocument = T),
      (H.parentNode = null),
      B)
    )
      for (var ie = x.firstChild; ie;)
        (H.appendChild(oe(T, ie, B)), (ie = ie.nextSibling));
    return H;
  }
  function se(T, x, B) {
    var H = new x.constructor();
    for (var ie in x)
      if (Object.prototype.hasOwnProperty.call(x, ie)) {
        var pe = x[ie];
        typeof pe != "object" && pe != H[ie] && (H[ie] = pe);
      }
    switch (
      (x.childNodes && (H.childNodes = new k()),
      (H.ownerDocument = T),
      H.nodeType)
    ) {
      case c:
        var Be = x.attributes,
          Me = (H.attributes = new $()),
          Ze = Be.length;
        Me._ownerElement = H;
        for (var Ot = 0; Ot < Ze; Ot++)
          H.setAttributeNode(se(T, Be.item(Ot), !0));
        break;
      case l:
        B = !0;
    }
    if (B)
      for (var St = x.firstChild; St;)
        (H.appendChild(se(T, St, B)), (St = St.nextSibling));
    return H;
  }
  function ve(T, x, B) {
    T[x] = B;
  }
  try {
    if (Object.defineProperty) {
      let T = function (x) {
        switch (x.nodeType) {
          case c:
          case A:
            var B = [];
            for (x = x.firstChild; x;)
              (x.nodeType !== 7 && x.nodeType !== 8 && B.push(T(x)),
                (x = x.nextSibling));
            return B.join("");
          default:
            return x.nodeValue;
        }
      };
      (Object.defineProperty(q.prototype, "length", {
        get: function () {
          return (U(this), this.$$length);
        },
      }),
        Object.defineProperty(Y.prototype, "textContent", {
          get: function () {
            return T(this);
          },
          set: function (x) {
            switch (this.nodeType) {
              case c:
              case A:
                for (; this.firstChild;) this.removeChild(this.firstChild);
                (x || String(x)) &&
                  this.appendChild(this.ownerDocument.createTextNode(x));
                break;
              default:
                ((this.data = x), (this.value = x), (this.nodeValue = x));
            }
          },
        }),
        (ve = function (x, B, H) {
          x["$$" + B] = H;
        }));
    }
  } catch {}
  return (
    (Gt.DocumentType = ae),
    (Gt.DOMException = R),
    (Gt.DOMImplementation = fe),
    (Gt.Element = p),
    (Gt.Node = Y),
    (Gt.NodeList = k),
    (Gt.XMLSerializer = je),
    Gt
  );
}
var qn = {},
  Is = {},
  kd;
function _C() {
  return (
    kd ||
      ((kd = 1),
      (function (e) {
        var t = Ko().freeze;
        ((e.XML_ENTITIES = t({
          amp: "&",
          apos: "'",
          gt: ">",
          lt: "<",
          quot: '"',
        })),
          (e.HTML_ENTITIES = t({
            Aacute: "Á",
            aacute: "á",
            Abreve: "Ă",
            abreve: "ă",
            ac: "∾",
            acd: "∿",
            acE: "∾̳",
            Acirc: "Â",
            acirc: "â",
            acute: "´",
            Acy: "А",
            acy: "а",
            AElig: "Æ",
            aelig: "æ",
            af: "⁡",
            Afr: "𝔄",
            afr: "𝔞",
            Agrave: "À",
            agrave: "à",
            alefsym: "ℵ",
            aleph: "ℵ",
            Alpha: "Α",
            alpha: "α",
            Amacr: "Ā",
            amacr: "ā",
            amalg: "⨿",
            AMP: "&",
            amp: "&",
            And: "⩓",
            and: "∧",
            andand: "⩕",
            andd: "⩜",
            andslope: "⩘",
            andv: "⩚",
            ang: "∠",
            ange: "⦤",
            angle: "∠",
            angmsd: "∡",
            angmsdaa: "⦨",
            angmsdab: "⦩",
            angmsdac: "⦪",
            angmsdad: "⦫",
            angmsdae: "⦬",
            angmsdaf: "⦭",
            angmsdag: "⦮",
            angmsdah: "⦯",
            angrt: "∟",
            angrtvb: "⊾",
            angrtvbd: "⦝",
            angsph: "∢",
            angst: "Å",
            angzarr: "⍼",
            Aogon: "Ą",
            aogon: "ą",
            Aopf: "𝔸",
            aopf: "𝕒",
            ap: "≈",
            apacir: "⩯",
            apE: "⩰",
            ape: "≊",
            apid: "≋",
            apos: "'",
            ApplyFunction: "⁡",
            approx: "≈",
            approxeq: "≊",
            Aring: "Å",
            aring: "å",
            Ascr: "𝒜",
            ascr: "𝒶",
            Assign: "≔",
            ast: "*",
            asymp: "≈",
            asympeq: "≍",
            Atilde: "Ã",
            atilde: "ã",
            Auml: "Ä",
            auml: "ä",
            awconint: "∳",
            awint: "⨑",
            backcong: "≌",
            backepsilon: "϶",
            backprime: "‵",
            backsim: "∽",
            backsimeq: "⋍",
            Backslash: "∖",
            Barv: "⫧",
            barvee: "⊽",
            Barwed: "⌆",
            barwed: "⌅",
            barwedge: "⌅",
            bbrk: "⎵",
            bbrktbrk: "⎶",
            bcong: "≌",
            Bcy: "Б",
            bcy: "б",
            bdquo: "„",
            becaus: "∵",
            Because: "∵",
            because: "∵",
            bemptyv: "⦰",
            bepsi: "϶",
            bernou: "ℬ",
            Bernoullis: "ℬ",
            Beta: "Β",
            beta: "β",
            beth: "ℶ",
            between: "≬",
            Bfr: "𝔅",
            bfr: "𝔟",
            bigcap: "⋂",
            bigcirc: "◯",
            bigcup: "⋃",
            bigodot: "⨀",
            bigoplus: "⨁",
            bigotimes: "⨂",
            bigsqcup: "⨆",
            bigstar: "★",
            bigtriangledown: "▽",
            bigtriangleup: "△",
            biguplus: "⨄",
            bigvee: "⋁",
            bigwedge: "⋀",
            bkarow: "⤍",
            blacklozenge: "⧫",
            blacksquare: "▪",
            blacktriangle: "▴",
            blacktriangledown: "▾",
            blacktriangleleft: "◂",
            blacktriangleright: "▸",
            blank: "␣",
            blk12: "▒",
            blk14: "░",
            blk34: "▓",
            block: "█",
            bne: "=⃥",
            bnequiv: "≡⃥",
            bNot: "⫭",
            bnot: "⌐",
            Bopf: "𝔹",
            bopf: "𝕓",
            bot: "⊥",
            bottom: "⊥",
            bowtie: "⋈",
            boxbox: "⧉",
            boxDL: "╗",
            boxDl: "╖",
            boxdL: "╕",
            boxdl: "┐",
            boxDR: "╔",
            boxDr: "╓",
            boxdR: "╒",
            boxdr: "┌",
            boxH: "═",
            boxh: "─",
            boxHD: "╦",
            boxHd: "╤",
            boxhD: "╥",
            boxhd: "┬",
            boxHU: "╩",
            boxHu: "╧",
            boxhU: "╨",
            boxhu: "┴",
            boxminus: "⊟",
            boxplus: "⊞",
            boxtimes: "⊠",
            boxUL: "╝",
            boxUl: "╜",
            boxuL: "╛",
            boxul: "┘",
            boxUR: "╚",
            boxUr: "╙",
            boxuR: "╘",
            boxur: "└",
            boxV: "║",
            boxv: "│",
            boxVH: "╬",
            boxVh: "╫",
            boxvH: "╪",
            boxvh: "┼",
            boxVL: "╣",
            boxVl: "╢",
            boxvL: "╡",
            boxvl: "┤",
            boxVR: "╠",
            boxVr: "╟",
            boxvR: "╞",
            boxvr: "├",
            bprime: "‵",
            Breve: "˘",
            breve: "˘",
            brvbar: "¦",
            Bscr: "ℬ",
            bscr: "𝒷",
            bsemi: "⁏",
            bsim: "∽",
            bsime: "⋍",
            bsol: "\\",
            bsolb: "⧅",
            bsolhsub: "⟈",
            bull: "•",
            bullet: "•",
            bump: "≎",
            bumpE: "⪮",
            bumpe: "≏",
            Bumpeq: "≎",
            bumpeq: "≏",
            Cacute: "Ć",
            cacute: "ć",
            Cap: "⋒",
            cap: "∩",
            capand: "⩄",
            capbrcup: "⩉",
            capcap: "⩋",
            capcup: "⩇",
            capdot: "⩀",
            CapitalDifferentialD: "ⅅ",
            caps: "∩︀",
            caret: "⁁",
            caron: "ˇ",
            Cayleys: "ℭ",
            ccaps: "⩍",
            Ccaron: "Č",
            ccaron: "č",
            Ccedil: "Ç",
            ccedil: "ç",
            Ccirc: "Ĉ",
            ccirc: "ĉ",
            Cconint: "∰",
            ccups: "⩌",
            ccupssm: "⩐",
            Cdot: "Ċ",
            cdot: "ċ",
            cedil: "¸",
            Cedilla: "¸",
            cemptyv: "⦲",
            cent: "¢",
            CenterDot: "·",
            centerdot: "·",
            Cfr: "ℭ",
            cfr: "𝔠",
            CHcy: "Ч",
            chcy: "ч",
            check: "✓",
            checkmark: "✓",
            Chi: "Χ",
            chi: "χ",
            cir: "○",
            circ: "ˆ",
            circeq: "≗",
            circlearrowleft: "↺",
            circlearrowright: "↻",
            circledast: "⊛",
            circledcirc: "⊚",
            circleddash: "⊝",
            CircleDot: "⊙",
            circledR: "®",
            circledS: "Ⓢ",
            CircleMinus: "⊖",
            CirclePlus: "⊕",
            CircleTimes: "⊗",
            cirE: "⧃",
            cire: "≗",
            cirfnint: "⨐",
            cirmid: "⫯",
            cirscir: "⧂",
            ClockwiseContourIntegral: "∲",
            CloseCurlyDoubleQuote: "”",
            CloseCurlyQuote: "’",
            clubs: "♣",
            clubsuit: "♣",
            Colon: "∷",
            colon: ":",
            Colone: "⩴",
            colone: "≔",
            coloneq: "≔",
            comma: ",",
            commat: "@",
            comp: "∁",
            compfn: "∘",
            complement: "∁",
            complexes: "ℂ",
            cong: "≅",
            congdot: "⩭",
            Congruent: "≡",
            Conint: "∯",
            conint: "∮",
            ContourIntegral: "∮",
            Copf: "ℂ",
            copf: "𝕔",
            coprod: "∐",
            Coproduct: "∐",
            COPY: "©",
            copy: "©",
            copysr: "℗",
            CounterClockwiseContourIntegral: "∳",
            crarr: "↵",
            Cross: "⨯",
            cross: "✗",
            Cscr: "𝒞",
            cscr: "𝒸",
            csub: "⫏",
            csube: "⫑",
            csup: "⫐",
            csupe: "⫒",
            ctdot: "⋯",
            cudarrl: "⤸",
            cudarrr: "⤵",
            cuepr: "⋞",
            cuesc: "⋟",
            cularr: "↶",
            cularrp: "⤽",
            Cup: "⋓",
            cup: "∪",
            cupbrcap: "⩈",
            CupCap: "≍",
            cupcap: "⩆",
            cupcup: "⩊",
            cupdot: "⊍",
            cupor: "⩅",
            cups: "∪︀",
            curarr: "↷",
            curarrm: "⤼",
            curlyeqprec: "⋞",
            curlyeqsucc: "⋟",
            curlyvee: "⋎",
            curlywedge: "⋏",
            curren: "¤",
            curvearrowleft: "↶",
            curvearrowright: "↷",
            cuvee: "⋎",
            cuwed: "⋏",
            cwconint: "∲",
            cwint: "∱",
            cylcty: "⌭",
            Dagger: "‡",
            dagger: "†",
            daleth: "ℸ",
            Darr: "↡",
            dArr: "⇓",
            darr: "↓",
            dash: "‐",
            Dashv: "⫤",
            dashv: "⊣",
            dbkarow: "⤏",
            dblac: "˝",
            Dcaron: "Ď",
            dcaron: "ď",
            Dcy: "Д",
            dcy: "д",
            DD: "ⅅ",
            dd: "ⅆ",
            ddagger: "‡",
            ddarr: "⇊",
            DDotrahd: "⤑",
            ddotseq: "⩷",
            deg: "°",
            Del: "∇",
            Delta: "Δ",
            delta: "δ",
            demptyv: "⦱",
            dfisht: "⥿",
            Dfr: "𝔇",
            dfr: "𝔡",
            dHar: "⥥",
            dharl: "⇃",
            dharr: "⇂",
            DiacriticalAcute: "´",
            DiacriticalDot: "˙",
            DiacriticalDoubleAcute: "˝",
            DiacriticalGrave: "`",
            DiacriticalTilde: "˜",
            diam: "⋄",
            Diamond: "⋄",
            diamond: "⋄",
            diamondsuit: "♦",
            diams: "♦",
            die: "¨",
            DifferentialD: "ⅆ",
            digamma: "ϝ",
            disin: "⋲",
            div: "÷",
            divide: "÷",
            divideontimes: "⋇",
            divonx: "⋇",
            DJcy: "Ђ",
            djcy: "ђ",
            dlcorn: "⌞",
            dlcrop: "⌍",
            dollar: "$",
            Dopf: "𝔻",
            dopf: "𝕕",
            Dot: "¨",
            dot: "˙",
            DotDot: "⃜",
            doteq: "≐",
            doteqdot: "≑",
            DotEqual: "≐",
            dotminus: "∸",
            dotplus: "∔",
            dotsquare: "⊡",
            doublebarwedge: "⌆",
            DoubleContourIntegral: "∯",
            DoubleDot: "¨",
            DoubleDownArrow: "⇓",
            DoubleLeftArrow: "⇐",
            DoubleLeftRightArrow: "⇔",
            DoubleLeftTee: "⫤",
            DoubleLongLeftArrow: "⟸",
            DoubleLongLeftRightArrow: "⟺",
            DoubleLongRightArrow: "⟹",
            DoubleRightArrow: "⇒",
            DoubleRightTee: "⊨",
            DoubleUpArrow: "⇑",
            DoubleUpDownArrow: "⇕",
            DoubleVerticalBar: "∥",
            DownArrow: "↓",
            Downarrow: "⇓",
            downarrow: "↓",
            DownArrowBar: "⤓",
            DownArrowUpArrow: "⇵",
            DownBreve: "̑",
            downdownarrows: "⇊",
            downharpoonleft: "⇃",
            downharpoonright: "⇂",
            DownLeftRightVector: "⥐",
            DownLeftTeeVector: "⥞",
            DownLeftVector: "↽",
            DownLeftVectorBar: "⥖",
            DownRightTeeVector: "⥟",
            DownRightVector: "⇁",
            DownRightVectorBar: "⥗",
            DownTee: "⊤",
            DownTeeArrow: "↧",
            drbkarow: "⤐",
            drcorn: "⌟",
            drcrop: "⌌",
            Dscr: "𝒟",
            dscr: "𝒹",
            DScy: "Ѕ",
            dscy: "ѕ",
            dsol: "⧶",
            Dstrok: "Đ",
            dstrok: "đ",
            dtdot: "⋱",
            dtri: "▿",
            dtrif: "▾",
            duarr: "⇵",
            duhar: "⥯",
            dwangle: "⦦",
            DZcy: "Џ",
            dzcy: "џ",
            dzigrarr: "⟿",
            Eacute: "É",
            eacute: "é",
            easter: "⩮",
            Ecaron: "Ě",
            ecaron: "ě",
            ecir: "≖",
            Ecirc: "Ê",
            ecirc: "ê",
            ecolon: "≕",
            Ecy: "Э",
            ecy: "э",
            eDDot: "⩷",
            Edot: "Ė",
            eDot: "≑",
            edot: "ė",
            ee: "ⅇ",
            efDot: "≒",
            Efr: "𝔈",
            efr: "𝔢",
            eg: "⪚",
            Egrave: "È",
            egrave: "è",
            egs: "⪖",
            egsdot: "⪘",
            el: "⪙",
            Element: "∈",
            elinters: "⏧",
            ell: "ℓ",
            els: "⪕",
            elsdot: "⪗",
            Emacr: "Ē",
            emacr: "ē",
            empty: "∅",
            emptyset: "∅",
            EmptySmallSquare: "◻",
            emptyv: "∅",
            EmptyVerySmallSquare: "▫",
            emsp: " ",
            emsp13: " ",
            emsp14: " ",
            ENG: "Ŋ",
            eng: "ŋ",
            ensp: " ",
            Eogon: "Ę",
            eogon: "ę",
            Eopf: "𝔼",
            eopf: "𝕖",
            epar: "⋕",
            eparsl: "⧣",
            eplus: "⩱",
            epsi: "ε",
            Epsilon: "Ε",
            epsilon: "ε",
            epsiv: "ϵ",
            eqcirc: "≖",
            eqcolon: "≕",
            eqsim: "≂",
            eqslantgtr: "⪖",
            eqslantless: "⪕",
            Equal: "⩵",
            equals: "=",
            EqualTilde: "≂",
            equest: "≟",
            Equilibrium: "⇌",
            equiv: "≡",
            equivDD: "⩸",
            eqvparsl: "⧥",
            erarr: "⥱",
            erDot: "≓",
            Escr: "ℰ",
            escr: "ℯ",
            esdot: "≐",
            Esim: "⩳",
            esim: "≂",
            Eta: "Η",
            eta: "η",
            ETH: "Ð",
            eth: "ð",
            Euml: "Ë",
            euml: "ë",
            euro: "€",
            excl: "!",
            exist: "∃",
            Exists: "∃",
            expectation: "ℰ",
            ExponentialE: "ⅇ",
            exponentiale: "ⅇ",
            fallingdotseq: "≒",
            Fcy: "Ф",
            fcy: "ф",
            female: "♀",
            ffilig: "ﬃ",
            fflig: "ﬀ",
            ffllig: "ﬄ",
            Ffr: "𝔉",
            ffr: "𝔣",
            filig: "ﬁ",
            FilledSmallSquare: "◼",
            FilledVerySmallSquare: "▪",
            fjlig: "fj",
            flat: "♭",
            fllig: "ﬂ",
            fltns: "▱",
            fnof: "ƒ",
            Fopf: "𝔽",
            fopf: "𝕗",
            ForAll: "∀",
            forall: "∀",
            fork: "⋔",
            forkv: "⫙",
            Fouriertrf: "ℱ",
            fpartint: "⨍",
            frac12: "½",
            frac13: "⅓",
            frac14: "¼",
            frac15: "⅕",
            frac16: "⅙",
            frac18: "⅛",
            frac23: "⅔",
            frac25: "⅖",
            frac34: "¾",
            frac35: "⅗",
            frac38: "⅜",
            frac45: "⅘",
            frac56: "⅚",
            frac58: "⅝",
            frac78: "⅞",
            frasl: "⁄",
            frown: "⌢",
            Fscr: "ℱ",
            fscr: "𝒻",
            gacute: "ǵ",
            Gamma: "Γ",
            gamma: "γ",
            Gammad: "Ϝ",
            gammad: "ϝ",
            gap: "⪆",
            Gbreve: "Ğ",
            gbreve: "ğ",
            Gcedil: "Ģ",
            Gcirc: "Ĝ",
            gcirc: "ĝ",
            Gcy: "Г",
            gcy: "г",
            Gdot: "Ġ",
            gdot: "ġ",
            gE: "≧",
            ge: "≥",
            gEl: "⪌",
            gel: "⋛",
            geq: "≥",
            geqq: "≧",
            geqslant: "⩾",
            ges: "⩾",
            gescc: "⪩",
            gesdot: "⪀",
            gesdoto: "⪂",
            gesdotol: "⪄",
            gesl: "⋛︀",
            gesles: "⪔",
            Gfr: "𝔊",
            gfr: "𝔤",
            Gg: "⋙",
            gg: "≫",
            ggg: "⋙",
            gimel: "ℷ",
            GJcy: "Ѓ",
            gjcy: "ѓ",
            gl: "≷",
            gla: "⪥",
            glE: "⪒",
            glj: "⪤",
            gnap: "⪊",
            gnapprox: "⪊",
            gnE: "≩",
            gne: "⪈",
            gneq: "⪈",
            gneqq: "≩",
            gnsim: "⋧",
            Gopf: "𝔾",
            gopf: "𝕘",
            grave: "`",
            GreaterEqual: "≥",
            GreaterEqualLess: "⋛",
            GreaterFullEqual: "≧",
            GreaterGreater: "⪢",
            GreaterLess: "≷",
            GreaterSlantEqual: "⩾",
            GreaterTilde: "≳",
            Gscr: "𝒢",
            gscr: "ℊ",
            gsim: "≳",
            gsime: "⪎",
            gsiml: "⪐",
            Gt: "≫",
            GT: ">",
            gt: ">",
            gtcc: "⪧",
            gtcir: "⩺",
            gtdot: "⋗",
            gtlPar: "⦕",
            gtquest: "⩼",
            gtrapprox: "⪆",
            gtrarr: "⥸",
            gtrdot: "⋗",
            gtreqless: "⋛",
            gtreqqless: "⪌",
            gtrless: "≷",
            gtrsim: "≳",
            gvertneqq: "≩︀",
            gvnE: "≩︀",
            Hacek: "ˇ",
            hairsp: " ",
            half: "½",
            hamilt: "ℋ",
            HARDcy: "Ъ",
            hardcy: "ъ",
            hArr: "⇔",
            harr: "↔",
            harrcir: "⥈",
            harrw: "↭",
            Hat: "^",
            hbar: "ℏ",
            Hcirc: "Ĥ",
            hcirc: "ĥ",
            hearts: "♥",
            heartsuit: "♥",
            hellip: "…",
            hercon: "⊹",
            Hfr: "ℌ",
            hfr: "𝔥",
            HilbertSpace: "ℋ",
            hksearow: "⤥",
            hkswarow: "⤦",
            hoarr: "⇿",
            homtht: "∻",
            hookleftarrow: "↩",
            hookrightarrow: "↪",
            Hopf: "ℍ",
            hopf: "𝕙",
            horbar: "―",
            HorizontalLine: "─",
            Hscr: "ℋ",
            hscr: "𝒽",
            hslash: "ℏ",
            Hstrok: "Ħ",
            hstrok: "ħ",
            HumpDownHump: "≎",
            HumpEqual: "≏",
            hybull: "⁃",
            hyphen: "‐",
            Iacute: "Í",
            iacute: "í",
            ic: "⁣",
            Icirc: "Î",
            icirc: "î",
            Icy: "И",
            icy: "и",
            Idot: "İ",
            IEcy: "Е",
            iecy: "е",
            iexcl: "¡",
            iff: "⇔",
            Ifr: "ℑ",
            ifr: "𝔦",
            Igrave: "Ì",
            igrave: "ì",
            ii: "ⅈ",
            iiiint: "⨌",
            iiint: "∭",
            iinfin: "⧜",
            iiota: "℩",
            IJlig: "Ĳ",
            ijlig: "ĳ",
            Im: "ℑ",
            Imacr: "Ī",
            imacr: "ī",
            image: "ℑ",
            ImaginaryI: "ⅈ",
            imagline: "ℐ",
            imagpart: "ℑ",
            imath: "ı",
            imof: "⊷",
            imped: "Ƶ",
            Implies: "⇒",
            in: "∈",
            incare: "℅",
            infin: "∞",
            infintie: "⧝",
            inodot: "ı",
            Int: "∬",
            int: "∫",
            intcal: "⊺",
            integers: "ℤ",
            Integral: "∫",
            intercal: "⊺",
            Intersection: "⋂",
            intlarhk: "⨗",
            intprod: "⨼",
            InvisibleComma: "⁣",
            InvisibleTimes: "⁢",
            IOcy: "Ё",
            iocy: "ё",
            Iogon: "Į",
            iogon: "į",
            Iopf: "𝕀",
            iopf: "𝕚",
            Iota: "Ι",
            iota: "ι",
            iprod: "⨼",
            iquest: "¿",
            Iscr: "ℐ",
            iscr: "𝒾",
            isin: "∈",
            isindot: "⋵",
            isinE: "⋹",
            isins: "⋴",
            isinsv: "⋳",
            isinv: "∈",
            it: "⁢",
            Itilde: "Ĩ",
            itilde: "ĩ",
            Iukcy: "І",
            iukcy: "і",
            Iuml: "Ï",
            iuml: "ï",
            Jcirc: "Ĵ",
            jcirc: "ĵ",
            Jcy: "Й",
            jcy: "й",
            Jfr: "𝔍",
            jfr: "𝔧",
            jmath: "ȷ",
            Jopf: "𝕁",
            jopf: "𝕛",
            Jscr: "𝒥",
            jscr: "𝒿",
            Jsercy: "Ј",
            jsercy: "ј",
            Jukcy: "Є",
            jukcy: "є",
            Kappa: "Κ",
            kappa: "κ",
            kappav: "ϰ",
            Kcedil: "Ķ",
            kcedil: "ķ",
            Kcy: "К",
            kcy: "к",
            Kfr: "𝔎",
            kfr: "𝔨",
            kgreen: "ĸ",
            KHcy: "Х",
            khcy: "х",
            KJcy: "Ќ",
            kjcy: "ќ",
            Kopf: "𝕂",
            kopf: "𝕜",
            Kscr: "𝒦",
            kscr: "𝓀",
            lAarr: "⇚",
            Lacute: "Ĺ",
            lacute: "ĺ",
            laemptyv: "⦴",
            lagran: "ℒ",
            Lambda: "Λ",
            lambda: "λ",
            Lang: "⟪",
            lang: "⟨",
            langd: "⦑",
            langle: "⟨",
            lap: "⪅",
            Laplacetrf: "ℒ",
            laquo: "«",
            Larr: "↞",
            lArr: "⇐",
            larr: "←",
            larrb: "⇤",
            larrbfs: "⤟",
            larrfs: "⤝",
            larrhk: "↩",
            larrlp: "↫",
            larrpl: "⤹",
            larrsim: "⥳",
            larrtl: "↢",
            lat: "⪫",
            lAtail: "⤛",
            latail: "⤙",
            late: "⪭",
            lates: "⪭︀",
            lBarr: "⤎",
            lbarr: "⤌",
            lbbrk: "❲",
            lbrace: "{",
            lbrack: "[",
            lbrke: "⦋",
            lbrksld: "⦏",
            lbrkslu: "⦍",
            Lcaron: "Ľ",
            lcaron: "ľ",
            Lcedil: "Ļ",
            lcedil: "ļ",
            lceil: "⌈",
            lcub: "{",
            Lcy: "Л",
            lcy: "л",
            ldca: "⤶",
            ldquo: "“",
            ldquor: "„",
            ldrdhar: "⥧",
            ldrushar: "⥋",
            ldsh: "↲",
            lE: "≦",
            le: "≤",
            LeftAngleBracket: "⟨",
            LeftArrow: "←",
            Leftarrow: "⇐",
            leftarrow: "←",
            LeftArrowBar: "⇤",
            LeftArrowRightArrow: "⇆",
            leftarrowtail: "↢",
            LeftCeiling: "⌈",
            LeftDoubleBracket: "⟦",
            LeftDownTeeVector: "⥡",
            LeftDownVector: "⇃",
            LeftDownVectorBar: "⥙",
            LeftFloor: "⌊",
            leftharpoondown: "↽",
            leftharpoonup: "↼",
            leftleftarrows: "⇇",
            LeftRightArrow: "↔",
            Leftrightarrow: "⇔",
            leftrightarrow: "↔",
            leftrightarrows: "⇆",
            leftrightharpoons: "⇋",
            leftrightsquigarrow: "↭",
            LeftRightVector: "⥎",
            LeftTee: "⊣",
            LeftTeeArrow: "↤",
            LeftTeeVector: "⥚",
            leftthreetimes: "⋋",
            LeftTriangle: "⊲",
            LeftTriangleBar: "⧏",
            LeftTriangleEqual: "⊴",
            LeftUpDownVector: "⥑",
            LeftUpTeeVector: "⥠",
            LeftUpVector: "↿",
            LeftUpVectorBar: "⥘",
            LeftVector: "↼",
            LeftVectorBar: "⥒",
            lEg: "⪋",
            leg: "⋚",
            leq: "≤",
            leqq: "≦",
            leqslant: "⩽",
            les: "⩽",
            lescc: "⪨",
            lesdot: "⩿",
            lesdoto: "⪁",
            lesdotor: "⪃",
            lesg: "⋚︀",
            lesges: "⪓",
            lessapprox: "⪅",
            lessdot: "⋖",
            lesseqgtr: "⋚",
            lesseqqgtr: "⪋",
            LessEqualGreater: "⋚",
            LessFullEqual: "≦",
            LessGreater: "≶",
            lessgtr: "≶",
            LessLess: "⪡",
            lesssim: "≲",
            LessSlantEqual: "⩽",
            LessTilde: "≲",
            lfisht: "⥼",
            lfloor: "⌊",
            Lfr: "𝔏",
            lfr: "𝔩",
            lg: "≶",
            lgE: "⪑",
            lHar: "⥢",
            lhard: "↽",
            lharu: "↼",
            lharul: "⥪",
            lhblk: "▄",
            LJcy: "Љ",
            ljcy: "љ",
            Ll: "⋘",
            ll: "≪",
            llarr: "⇇",
            llcorner: "⌞",
            Lleftarrow: "⇚",
            llhard: "⥫",
            lltri: "◺",
            Lmidot: "Ŀ",
            lmidot: "ŀ",
            lmoust: "⎰",
            lmoustache: "⎰",
            lnap: "⪉",
            lnapprox: "⪉",
            lnE: "≨",
            lne: "⪇",
            lneq: "⪇",
            lneqq: "≨",
            lnsim: "⋦",
            loang: "⟬",
            loarr: "⇽",
            lobrk: "⟦",
            LongLeftArrow: "⟵",
            Longleftarrow: "⟸",
            longleftarrow: "⟵",
            LongLeftRightArrow: "⟷",
            Longleftrightarrow: "⟺",
            longleftrightarrow: "⟷",
            longmapsto: "⟼",
            LongRightArrow: "⟶",
            Longrightarrow: "⟹",
            longrightarrow: "⟶",
            looparrowleft: "↫",
            looparrowright: "↬",
            lopar: "⦅",
            Lopf: "𝕃",
            lopf: "𝕝",
            loplus: "⨭",
            lotimes: "⨴",
            lowast: "∗",
            lowbar: "_",
            LowerLeftArrow: "↙",
            LowerRightArrow: "↘",
            loz: "◊",
            lozenge: "◊",
            lozf: "⧫",
            lpar: "(",
            lparlt: "⦓",
            lrarr: "⇆",
            lrcorner: "⌟",
            lrhar: "⇋",
            lrhard: "⥭",
            lrm: "‎",
            lrtri: "⊿",
            lsaquo: "‹",
            Lscr: "ℒ",
            lscr: "𝓁",
            Lsh: "↰",
            lsh: "↰",
            lsim: "≲",
            lsime: "⪍",
            lsimg: "⪏",
            lsqb: "[",
            lsquo: "‘",
            lsquor: "‚",
            Lstrok: "Ł",
            lstrok: "ł",
            Lt: "≪",
            LT: "<",
            lt: "<",
            ltcc: "⪦",
            ltcir: "⩹",
            ltdot: "⋖",
            lthree: "⋋",
            ltimes: "⋉",
            ltlarr: "⥶",
            ltquest: "⩻",
            ltri: "◃",
            ltrie: "⊴",
            ltrif: "◂",
            ltrPar: "⦖",
            lurdshar: "⥊",
            luruhar: "⥦",
            lvertneqq: "≨︀",
            lvnE: "≨︀",
            macr: "¯",
            male: "♂",
            malt: "✠",
            maltese: "✠",
            Map: "⤅",
            map: "↦",
            mapsto: "↦",
            mapstodown: "↧",
            mapstoleft: "↤",
            mapstoup: "↥",
            marker: "▮",
            mcomma: "⨩",
            Mcy: "М",
            mcy: "м",
            mdash: "—",
            mDDot: "∺",
            measuredangle: "∡",
            MediumSpace: " ",
            Mellintrf: "ℳ",
            Mfr: "𝔐",
            mfr: "𝔪",
            mho: "℧",
            micro: "µ",
            mid: "∣",
            midast: "*",
            midcir: "⫰",
            middot: "·",
            minus: "−",
            minusb: "⊟",
            minusd: "∸",
            minusdu: "⨪",
            MinusPlus: "∓",
            mlcp: "⫛",
            mldr: "…",
            mnplus: "∓",
            models: "⊧",
            Mopf: "𝕄",
            mopf: "𝕞",
            mp: "∓",
            Mscr: "ℳ",
            mscr: "𝓂",
            mstpos: "∾",
            Mu: "Μ",
            mu: "μ",
            multimap: "⊸",
            mumap: "⊸",
            nabla: "∇",
            Nacute: "Ń",
            nacute: "ń",
            nang: "∠⃒",
            nap: "≉",
            napE: "⩰̸",
            napid: "≋̸",
            napos: "ŉ",
            napprox: "≉",
            natur: "♮",
            natural: "♮",
            naturals: "ℕ",
            nbsp: " ",
            nbump: "≎̸",
            nbumpe: "≏̸",
            ncap: "⩃",
            Ncaron: "Ň",
            ncaron: "ň",
            Ncedil: "Ņ",
            ncedil: "ņ",
            ncong: "≇",
            ncongdot: "⩭̸",
            ncup: "⩂",
            Ncy: "Н",
            ncy: "н",
            ndash: "–",
            ne: "≠",
            nearhk: "⤤",
            neArr: "⇗",
            nearr: "↗",
            nearrow: "↗",
            nedot: "≐̸",
            NegativeMediumSpace: "​",
            NegativeThickSpace: "​",
            NegativeThinSpace: "​",
            NegativeVeryThinSpace: "​",
            nequiv: "≢",
            nesear: "⤨",
            nesim: "≂̸",
            NestedGreaterGreater: "≫",
            NestedLessLess: "≪",
            NewLine: `
`,
            nexist: "∄",
            nexists: "∄",
            Nfr: "𝔑",
            nfr: "𝔫",
            ngE: "≧̸",
            nge: "≱",
            ngeq: "≱",
            ngeqq: "≧̸",
            ngeqslant: "⩾̸",
            nges: "⩾̸",
            nGg: "⋙̸",
            ngsim: "≵",
            nGt: "≫⃒",
            ngt: "≯",
            ngtr: "≯",
            nGtv: "≫̸",
            nhArr: "⇎",
            nharr: "↮",
            nhpar: "⫲",
            ni: "∋",
            nis: "⋼",
            nisd: "⋺",
            niv: "∋",
            NJcy: "Њ",
            njcy: "њ",
            nlArr: "⇍",
            nlarr: "↚",
            nldr: "‥",
            nlE: "≦̸",
            nle: "≰",
            nLeftarrow: "⇍",
            nleftarrow: "↚",
            nLeftrightarrow: "⇎",
            nleftrightarrow: "↮",
            nleq: "≰",
            nleqq: "≦̸",
            nleqslant: "⩽̸",
            nles: "⩽̸",
            nless: "≮",
            nLl: "⋘̸",
            nlsim: "≴",
            nLt: "≪⃒",
            nlt: "≮",
            nltri: "⋪",
            nltrie: "⋬",
            nLtv: "≪̸",
            nmid: "∤",
            NoBreak: "⁠",
            NonBreakingSpace: " ",
            Nopf: "ℕ",
            nopf: "𝕟",
            Not: "⫬",
            not: "¬",
            NotCongruent: "≢",
            NotCupCap: "≭",
            NotDoubleVerticalBar: "∦",
            NotElement: "∉",
            NotEqual: "≠",
            NotEqualTilde: "≂̸",
            NotExists: "∄",
            NotGreater: "≯",
            NotGreaterEqual: "≱",
            NotGreaterFullEqual: "≧̸",
            NotGreaterGreater: "≫̸",
            NotGreaterLess: "≹",
            NotGreaterSlantEqual: "⩾̸",
            NotGreaterTilde: "≵",
            NotHumpDownHump: "≎̸",
            NotHumpEqual: "≏̸",
            notin: "∉",
            notindot: "⋵̸",
            notinE: "⋹̸",
            notinva: "∉",
            notinvb: "⋷",
            notinvc: "⋶",
            NotLeftTriangle: "⋪",
            NotLeftTriangleBar: "⧏̸",
            NotLeftTriangleEqual: "⋬",
            NotLess: "≮",
            NotLessEqual: "≰",
            NotLessGreater: "≸",
            NotLessLess: "≪̸",
            NotLessSlantEqual: "⩽̸",
            NotLessTilde: "≴",
            NotNestedGreaterGreater: "⪢̸",
            NotNestedLessLess: "⪡̸",
            notni: "∌",
            notniva: "∌",
            notnivb: "⋾",
            notnivc: "⋽",
            NotPrecedes: "⊀",
            NotPrecedesEqual: "⪯̸",
            NotPrecedesSlantEqual: "⋠",
            NotReverseElement: "∌",
            NotRightTriangle: "⋫",
            NotRightTriangleBar: "⧐̸",
            NotRightTriangleEqual: "⋭",
            NotSquareSubset: "⊏̸",
            NotSquareSubsetEqual: "⋢",
            NotSquareSuperset: "⊐̸",
            NotSquareSupersetEqual: "⋣",
            NotSubset: "⊂⃒",
            NotSubsetEqual: "⊈",
            NotSucceeds: "⊁",
            NotSucceedsEqual: "⪰̸",
            NotSucceedsSlantEqual: "⋡",
            NotSucceedsTilde: "≿̸",
            NotSuperset: "⊃⃒",
            NotSupersetEqual: "⊉",
            NotTilde: "≁",
            NotTildeEqual: "≄",
            NotTildeFullEqual: "≇",
            NotTildeTilde: "≉",
            NotVerticalBar: "∤",
            npar: "∦",
            nparallel: "∦",
            nparsl: "⫽⃥",
            npart: "∂̸",
            npolint: "⨔",
            npr: "⊀",
            nprcue: "⋠",
            npre: "⪯̸",
            nprec: "⊀",
            npreceq: "⪯̸",
            nrArr: "⇏",
            nrarr: "↛",
            nrarrc: "⤳̸",
            nrarrw: "↝̸",
            nRightarrow: "⇏",
            nrightarrow: "↛",
            nrtri: "⋫",
            nrtrie: "⋭",
            nsc: "⊁",
            nsccue: "⋡",
            nsce: "⪰̸",
            Nscr: "𝒩",
            nscr: "𝓃",
            nshortmid: "∤",
            nshortparallel: "∦",
            nsim: "≁",
            nsime: "≄",
            nsimeq: "≄",
            nsmid: "∤",
            nspar: "∦",
            nsqsube: "⋢",
            nsqsupe: "⋣",
            nsub: "⊄",
            nsubE: "⫅̸",
            nsube: "⊈",
            nsubset: "⊂⃒",
            nsubseteq: "⊈",
            nsubseteqq: "⫅̸",
            nsucc: "⊁",
            nsucceq: "⪰̸",
            nsup: "⊅",
            nsupE: "⫆̸",
            nsupe: "⊉",
            nsupset: "⊃⃒",
            nsupseteq: "⊉",
            nsupseteqq: "⫆̸",
            ntgl: "≹",
            Ntilde: "Ñ",
            ntilde: "ñ",
            ntlg: "≸",
            ntriangleleft: "⋪",
            ntrianglelefteq: "⋬",
            ntriangleright: "⋫",
            ntrianglerighteq: "⋭",
            Nu: "Ν",
            nu: "ν",
            num: "#",
            numero: "№",
            numsp: " ",
            nvap: "≍⃒",
            nVDash: "⊯",
            nVdash: "⊮",
            nvDash: "⊭",
            nvdash: "⊬",
            nvge: "≥⃒",
            nvgt: ">⃒",
            nvHarr: "⤄",
            nvinfin: "⧞",
            nvlArr: "⤂",
            nvle: "≤⃒",
            nvlt: "<⃒",
            nvltrie: "⊴⃒",
            nvrArr: "⤃",
            nvrtrie: "⊵⃒",
            nvsim: "∼⃒",
            nwarhk: "⤣",
            nwArr: "⇖",
            nwarr: "↖",
            nwarrow: "↖",
            nwnear: "⤧",
            Oacute: "Ó",
            oacute: "ó",
            oast: "⊛",
            ocir: "⊚",
            Ocirc: "Ô",
            ocirc: "ô",
            Ocy: "О",
            ocy: "о",
            odash: "⊝",
            Odblac: "Ő",
            odblac: "ő",
            odiv: "⨸",
            odot: "⊙",
            odsold: "⦼",
            OElig: "Œ",
            oelig: "œ",
            ofcir: "⦿",
            Ofr: "𝔒",
            ofr: "𝔬",
            ogon: "˛",
            Ograve: "Ò",
            ograve: "ò",
            ogt: "⧁",
            ohbar: "⦵",
            ohm: "Ω",
            oint: "∮",
            olarr: "↺",
            olcir: "⦾",
            olcross: "⦻",
            oline: "‾",
            olt: "⧀",
            Omacr: "Ō",
            omacr: "ō",
            Omega: "Ω",
            omega: "ω",
            Omicron: "Ο",
            omicron: "ο",
            omid: "⦶",
            ominus: "⊖",
            Oopf: "𝕆",
            oopf: "𝕠",
            opar: "⦷",
            OpenCurlyDoubleQuote: "“",
            OpenCurlyQuote: "‘",
            operp: "⦹",
            oplus: "⊕",
            Or: "⩔",
            or: "∨",
            orarr: "↻",
            ord: "⩝",
            order: "ℴ",
            orderof: "ℴ",
            ordf: "ª",
            ordm: "º",
            origof: "⊶",
            oror: "⩖",
            orslope: "⩗",
            orv: "⩛",
            oS: "Ⓢ",
            Oscr: "𝒪",
            oscr: "ℴ",
            Oslash: "Ø",
            oslash: "ø",
            osol: "⊘",
            Otilde: "Õ",
            otilde: "õ",
            Otimes: "⨷",
            otimes: "⊗",
            otimesas: "⨶",
            Ouml: "Ö",
            ouml: "ö",
            ovbar: "⌽",
            OverBar: "‾",
            OverBrace: "⏞",
            OverBracket: "⎴",
            OverParenthesis: "⏜",
            par: "∥",
            para: "¶",
            parallel: "∥",
            parsim: "⫳",
            parsl: "⫽",
            part: "∂",
            PartialD: "∂",
            Pcy: "П",
            pcy: "п",
            percnt: "%",
            period: ".",
            permil: "‰",
            perp: "⊥",
            pertenk: "‱",
            Pfr: "𝔓",
            pfr: "𝔭",
            Phi: "Φ",
            phi: "φ",
            phiv: "ϕ",
            phmmat: "ℳ",
            phone: "☎",
            Pi: "Π",
            pi: "π",
            pitchfork: "⋔",
            piv: "ϖ",
            planck: "ℏ",
            planckh: "ℎ",
            plankv: "ℏ",
            plus: "+",
            plusacir: "⨣",
            plusb: "⊞",
            pluscir: "⨢",
            plusdo: "∔",
            plusdu: "⨥",
            pluse: "⩲",
            PlusMinus: "±",
            plusmn: "±",
            plussim: "⨦",
            plustwo: "⨧",
            pm: "±",
            Poincareplane: "ℌ",
            pointint: "⨕",
            Popf: "ℙ",
            popf: "𝕡",
            pound: "£",
            Pr: "⪻",
            pr: "≺",
            prap: "⪷",
            prcue: "≼",
            prE: "⪳",
            pre: "⪯",
            prec: "≺",
            precapprox: "⪷",
            preccurlyeq: "≼",
            Precedes: "≺",
            PrecedesEqual: "⪯",
            PrecedesSlantEqual: "≼",
            PrecedesTilde: "≾",
            preceq: "⪯",
            precnapprox: "⪹",
            precneqq: "⪵",
            precnsim: "⋨",
            precsim: "≾",
            Prime: "″",
            prime: "′",
            primes: "ℙ",
            prnap: "⪹",
            prnE: "⪵",
            prnsim: "⋨",
            prod: "∏",
            Product: "∏",
            profalar: "⌮",
            profline: "⌒",
            profsurf: "⌓",
            prop: "∝",
            Proportion: "∷",
            Proportional: "∝",
            propto: "∝",
            prsim: "≾",
            prurel: "⊰",
            Pscr: "𝒫",
            pscr: "𝓅",
            Psi: "Ψ",
            psi: "ψ",
            puncsp: " ",
            Qfr: "𝔔",
            qfr: "𝔮",
            qint: "⨌",
            Qopf: "ℚ",
            qopf: "𝕢",
            qprime: "⁗",
            Qscr: "𝒬",
            qscr: "𝓆",
            quaternions: "ℍ",
            quatint: "⨖",
            quest: "?",
            questeq: "≟",
            QUOT: '"',
            quot: '"',
            rAarr: "⇛",
            race: "∽̱",
            Racute: "Ŕ",
            racute: "ŕ",
            radic: "√",
            raemptyv: "⦳",
            Rang: "⟫",
            rang: "⟩",
            rangd: "⦒",
            range: "⦥",
            rangle: "⟩",
            raquo: "»",
            Rarr: "↠",
            rArr: "⇒",
            rarr: "→",
            rarrap: "⥵",
            rarrb: "⇥",
            rarrbfs: "⤠",
            rarrc: "⤳",
            rarrfs: "⤞",
            rarrhk: "↪",
            rarrlp: "↬",
            rarrpl: "⥅",
            rarrsim: "⥴",
            Rarrtl: "⤖",
            rarrtl: "↣",
            rarrw: "↝",
            rAtail: "⤜",
            ratail: "⤚",
            ratio: "∶",
            rationals: "ℚ",
            RBarr: "⤐",
            rBarr: "⤏",
            rbarr: "⤍",
            rbbrk: "❳",
            rbrace: "}",
            rbrack: "]",
            rbrke: "⦌",
            rbrksld: "⦎",
            rbrkslu: "⦐",
            Rcaron: "Ř",
            rcaron: "ř",
            Rcedil: "Ŗ",
            rcedil: "ŗ",
            rceil: "⌉",
            rcub: "}",
            Rcy: "Р",
            rcy: "р",
            rdca: "⤷",
            rdldhar: "⥩",
            rdquo: "”",
            rdquor: "”",
            rdsh: "↳",
            Re: "ℜ",
            real: "ℜ",
            realine: "ℛ",
            realpart: "ℜ",
            reals: "ℝ",
            rect: "▭",
            REG: "®",
            reg: "®",
            ReverseElement: "∋",
            ReverseEquilibrium: "⇋",
            ReverseUpEquilibrium: "⥯",
            rfisht: "⥽",
            rfloor: "⌋",
            Rfr: "ℜ",
            rfr: "𝔯",
            rHar: "⥤",
            rhard: "⇁",
            rharu: "⇀",
            rharul: "⥬",
            Rho: "Ρ",
            rho: "ρ",
            rhov: "ϱ",
            RightAngleBracket: "⟩",
            RightArrow: "→",
            Rightarrow: "⇒",
            rightarrow: "→",
            RightArrowBar: "⇥",
            RightArrowLeftArrow: "⇄",
            rightarrowtail: "↣",
            RightCeiling: "⌉",
            RightDoubleBracket: "⟧",
            RightDownTeeVector: "⥝",
            RightDownVector: "⇂",
            RightDownVectorBar: "⥕",
            RightFloor: "⌋",
            rightharpoondown: "⇁",
            rightharpoonup: "⇀",
            rightleftarrows: "⇄",
            rightleftharpoons: "⇌",
            rightrightarrows: "⇉",
            rightsquigarrow: "↝",
            RightTee: "⊢",
            RightTeeArrow: "↦",
            RightTeeVector: "⥛",
            rightthreetimes: "⋌",
            RightTriangle: "⊳",
            RightTriangleBar: "⧐",
            RightTriangleEqual: "⊵",
            RightUpDownVector: "⥏",
            RightUpTeeVector: "⥜",
            RightUpVector: "↾",
            RightUpVectorBar: "⥔",
            RightVector: "⇀",
            RightVectorBar: "⥓",
            ring: "˚",
            risingdotseq: "≓",
            rlarr: "⇄",
            rlhar: "⇌",
            rlm: "‏",
            rmoust: "⎱",
            rmoustache: "⎱",
            rnmid: "⫮",
            roang: "⟭",
            roarr: "⇾",
            robrk: "⟧",
            ropar: "⦆",
            Ropf: "ℝ",
            ropf: "𝕣",
            roplus: "⨮",
            rotimes: "⨵",
            RoundImplies: "⥰",
            rpar: ")",
            rpargt: "⦔",
            rppolint: "⨒",
            rrarr: "⇉",
            Rrightarrow: "⇛",
            rsaquo: "›",
            Rscr: "ℛ",
            rscr: "𝓇",
            Rsh: "↱",
            rsh: "↱",
            rsqb: "]",
            rsquo: "’",
            rsquor: "’",
            rthree: "⋌",
            rtimes: "⋊",
            rtri: "▹",
            rtrie: "⊵",
            rtrif: "▸",
            rtriltri: "⧎",
            RuleDelayed: "⧴",
            ruluhar: "⥨",
            rx: "℞",
            Sacute: "Ś",
            sacute: "ś",
            sbquo: "‚",
            Sc: "⪼",
            sc: "≻",
            scap: "⪸",
            Scaron: "Š",
            scaron: "š",
            sccue: "≽",
            scE: "⪴",
            sce: "⪰",
            Scedil: "Ş",
            scedil: "ş",
            Scirc: "Ŝ",
            scirc: "ŝ",
            scnap: "⪺",
            scnE: "⪶",
            scnsim: "⋩",
            scpolint: "⨓",
            scsim: "≿",
            Scy: "С",
            scy: "с",
            sdot: "⋅",
            sdotb: "⊡",
            sdote: "⩦",
            searhk: "⤥",
            seArr: "⇘",
            searr: "↘",
            searrow: "↘",
            sect: "§",
            semi: ";",
            seswar: "⤩",
            setminus: "∖",
            setmn: "∖",
            sext: "✶",
            Sfr: "𝔖",
            sfr: "𝔰",
            sfrown: "⌢",
            sharp: "♯",
            SHCHcy: "Щ",
            shchcy: "щ",
            SHcy: "Ш",
            shcy: "ш",
            ShortDownArrow: "↓",
            ShortLeftArrow: "←",
            shortmid: "∣",
            shortparallel: "∥",
            ShortRightArrow: "→",
            ShortUpArrow: "↑",
            shy: "­",
            Sigma: "Σ",
            sigma: "σ",
            sigmaf: "ς",
            sigmav: "ς",
            sim: "∼",
            simdot: "⩪",
            sime: "≃",
            simeq: "≃",
            simg: "⪞",
            simgE: "⪠",
            siml: "⪝",
            simlE: "⪟",
            simne: "≆",
            simplus: "⨤",
            simrarr: "⥲",
            slarr: "←",
            SmallCircle: "∘",
            smallsetminus: "∖",
            smashp: "⨳",
            smeparsl: "⧤",
            smid: "∣",
            smile: "⌣",
            smt: "⪪",
            smte: "⪬",
            smtes: "⪬︀",
            SOFTcy: "Ь",
            softcy: "ь",
            sol: "/",
            solb: "⧄",
            solbar: "⌿",
            Sopf: "𝕊",
            sopf: "𝕤",
            spades: "♠",
            spadesuit: "♠",
            spar: "∥",
            sqcap: "⊓",
            sqcaps: "⊓︀",
            sqcup: "⊔",
            sqcups: "⊔︀",
            Sqrt: "√",
            sqsub: "⊏",
            sqsube: "⊑",
            sqsubset: "⊏",
            sqsubseteq: "⊑",
            sqsup: "⊐",
            sqsupe: "⊒",
            sqsupset: "⊐",
            sqsupseteq: "⊒",
            squ: "□",
            Square: "□",
            square: "□",
            SquareIntersection: "⊓",
            SquareSubset: "⊏",
            SquareSubsetEqual: "⊑",
            SquareSuperset: "⊐",
            SquareSupersetEqual: "⊒",
            SquareUnion: "⊔",
            squarf: "▪",
            squf: "▪",
            srarr: "→",
            Sscr: "𝒮",
            sscr: "𝓈",
            ssetmn: "∖",
            ssmile: "⌣",
            sstarf: "⋆",
            Star: "⋆",
            star: "☆",
            starf: "★",
            straightepsilon: "ϵ",
            straightphi: "ϕ",
            strns: "¯",
            Sub: "⋐",
            sub: "⊂",
            subdot: "⪽",
            subE: "⫅",
            sube: "⊆",
            subedot: "⫃",
            submult: "⫁",
            subnE: "⫋",
            subne: "⊊",
            subplus: "⪿",
            subrarr: "⥹",
            Subset: "⋐",
            subset: "⊂",
            subseteq: "⊆",
            subseteqq: "⫅",
            SubsetEqual: "⊆",
            subsetneq: "⊊",
            subsetneqq: "⫋",
            subsim: "⫇",
            subsub: "⫕",
            subsup: "⫓",
            succ: "≻",
            succapprox: "⪸",
            succcurlyeq: "≽",
            Succeeds: "≻",
            SucceedsEqual: "⪰",
            SucceedsSlantEqual: "≽",
            SucceedsTilde: "≿",
            succeq: "⪰",
            succnapprox: "⪺",
            succneqq: "⪶",
            succnsim: "⋩",
            succsim: "≿",
            SuchThat: "∋",
            Sum: "∑",
            sum: "∑",
            sung: "♪",
            Sup: "⋑",
            sup: "⊃",
            sup1: "¹",
            sup2: "²",
            sup3: "³",
            supdot: "⪾",
            supdsub: "⫘",
            supE: "⫆",
            supe: "⊇",
            supedot: "⫄",
            Superset: "⊃",
            SupersetEqual: "⊇",
            suphsol: "⟉",
            suphsub: "⫗",
            suplarr: "⥻",
            supmult: "⫂",
            supnE: "⫌",
            supne: "⊋",
            supplus: "⫀",
            Supset: "⋑",
            supset: "⊃",
            supseteq: "⊇",
            supseteqq: "⫆",
            supsetneq: "⊋",
            supsetneqq: "⫌",
            supsim: "⫈",
            supsub: "⫔",
            supsup: "⫖",
            swarhk: "⤦",
            swArr: "⇙",
            swarr: "↙",
            swarrow: "↙",
            swnwar: "⤪",
            szlig: "ß",
            Tab: "	",
            target: "⌖",
            Tau: "Τ",
            tau: "τ",
            tbrk: "⎴",
            Tcaron: "Ť",
            tcaron: "ť",
            Tcedil: "Ţ",
            tcedil: "ţ",
            Tcy: "Т",
            tcy: "т",
            tdot: "⃛",
            telrec: "⌕",
            Tfr: "𝔗",
            tfr: "𝔱",
            there4: "∴",
            Therefore: "∴",
            therefore: "∴",
            Theta: "Θ",
            theta: "θ",
            thetasym: "ϑ",
            thetav: "ϑ",
            thickapprox: "≈",
            thicksim: "∼",
            ThickSpace: "  ",
            thinsp: " ",
            ThinSpace: " ",
            thkap: "≈",
            thksim: "∼",
            THORN: "Þ",
            thorn: "þ",
            Tilde: "∼",
            tilde: "˜",
            TildeEqual: "≃",
            TildeFullEqual: "≅",
            TildeTilde: "≈",
            times: "×",
            timesb: "⊠",
            timesbar: "⨱",
            timesd: "⨰",
            tint: "∭",
            toea: "⤨",
            top: "⊤",
            topbot: "⌶",
            topcir: "⫱",
            Topf: "𝕋",
            topf: "𝕥",
            topfork: "⫚",
            tosa: "⤩",
            tprime: "‴",
            TRADE: "™",
            trade: "™",
            triangle: "▵",
            triangledown: "▿",
            triangleleft: "◃",
            trianglelefteq: "⊴",
            triangleq: "≜",
            triangleright: "▹",
            trianglerighteq: "⊵",
            tridot: "◬",
            trie: "≜",
            triminus: "⨺",
            TripleDot: "⃛",
            triplus: "⨹",
            trisb: "⧍",
            tritime: "⨻",
            trpezium: "⏢",
            Tscr: "𝒯",
            tscr: "𝓉",
            TScy: "Ц",
            tscy: "ц",
            TSHcy: "Ћ",
            tshcy: "ћ",
            Tstrok: "Ŧ",
            tstrok: "ŧ",
            twixt: "≬",
            twoheadleftarrow: "↞",
            twoheadrightarrow: "↠",
            Uacute: "Ú",
            uacute: "ú",
            Uarr: "↟",
            uArr: "⇑",
            uarr: "↑",
            Uarrocir: "⥉",
            Ubrcy: "Ў",
            ubrcy: "ў",
            Ubreve: "Ŭ",
            ubreve: "ŭ",
            Ucirc: "Û",
            ucirc: "û",
            Ucy: "У",
            ucy: "у",
            udarr: "⇅",
            Udblac: "Ű",
            udblac: "ű",
            udhar: "⥮",
            ufisht: "⥾",
            Ufr: "𝔘",
            ufr: "𝔲",
            Ugrave: "Ù",
            ugrave: "ù",
            uHar: "⥣",
            uharl: "↿",
            uharr: "↾",
            uhblk: "▀",
            ulcorn: "⌜",
            ulcorner: "⌜",
            ulcrop: "⌏",
            ultri: "◸",
            Umacr: "Ū",
            umacr: "ū",
            uml: "¨",
            UnderBar: "_",
            UnderBrace: "⏟",
            UnderBracket: "⎵",
            UnderParenthesis: "⏝",
            Union: "⋃",
            UnionPlus: "⊎",
            Uogon: "Ų",
            uogon: "ų",
            Uopf: "𝕌",
            uopf: "𝕦",
            UpArrow: "↑",
            Uparrow: "⇑",
            uparrow: "↑",
            UpArrowBar: "⤒",
            UpArrowDownArrow: "⇅",
            UpDownArrow: "↕",
            Updownarrow: "⇕",
            updownarrow: "↕",
            UpEquilibrium: "⥮",
            upharpoonleft: "↿",
            upharpoonright: "↾",
            uplus: "⊎",
            UpperLeftArrow: "↖",
            UpperRightArrow: "↗",
            Upsi: "ϒ",
            upsi: "υ",
            upsih: "ϒ",
            Upsilon: "Υ",
            upsilon: "υ",
            UpTee: "⊥",
            UpTeeArrow: "↥",
            upuparrows: "⇈",
            urcorn: "⌝",
            urcorner: "⌝",
            urcrop: "⌎",
            Uring: "Ů",
            uring: "ů",
            urtri: "◹",
            Uscr: "𝒰",
            uscr: "𝓊",
            utdot: "⋰",
            Utilde: "Ũ",
            utilde: "ũ",
            utri: "▵",
            utrif: "▴",
            uuarr: "⇈",
            Uuml: "Ü",
            uuml: "ü",
            uwangle: "⦧",
            vangrt: "⦜",
            varepsilon: "ϵ",
            varkappa: "ϰ",
            varnothing: "∅",
            varphi: "ϕ",
            varpi: "ϖ",
            varpropto: "∝",
            vArr: "⇕",
            varr: "↕",
            varrho: "ϱ",
            varsigma: "ς",
            varsubsetneq: "⊊︀",
            varsubsetneqq: "⫋︀",
            varsupsetneq: "⊋︀",
            varsupsetneqq: "⫌︀",
            vartheta: "ϑ",
            vartriangleleft: "⊲",
            vartriangleright: "⊳",
            Vbar: "⫫",
            vBar: "⫨",
            vBarv: "⫩",
            Vcy: "В",
            vcy: "в",
            VDash: "⊫",
            Vdash: "⊩",
            vDash: "⊨",
            vdash: "⊢",
            Vdashl: "⫦",
            Vee: "⋁",
            vee: "∨",
            veebar: "⊻",
            veeeq: "≚",
            vellip: "⋮",
            Verbar: "‖",
            verbar: "|",
            Vert: "‖",
            vert: "|",
            VerticalBar: "∣",
            VerticalLine: "|",
            VerticalSeparator: "❘",
            VerticalTilde: "≀",
            VeryThinSpace: " ",
            Vfr: "𝔙",
            vfr: "𝔳",
            vltri: "⊲",
            vnsub: "⊂⃒",
            vnsup: "⊃⃒",
            Vopf: "𝕍",
            vopf: "𝕧",
            vprop: "∝",
            vrtri: "⊳",
            Vscr: "𝒱",
            vscr: "𝓋",
            vsubnE: "⫋︀",
            vsubne: "⊊︀",
            vsupnE: "⫌︀",
            vsupne: "⊋︀",
            Vvdash: "⊪",
            vzigzag: "⦚",
            Wcirc: "Ŵ",
            wcirc: "ŵ",
            wedbar: "⩟",
            Wedge: "⋀",
            wedge: "∧",
            wedgeq: "≙",
            weierp: "℘",
            Wfr: "𝔚",
            wfr: "𝔴",
            Wopf: "𝕎",
            wopf: "𝕨",
            wp: "℘",
            wr: "≀",
            wreath: "≀",
            Wscr: "𝒲",
            wscr: "𝓌",
            xcap: "⋂",
            xcirc: "◯",
            xcup: "⋃",
            xdtri: "▽",
            Xfr: "𝔛",
            xfr: "𝔵",
            xhArr: "⟺",
            xharr: "⟷",
            Xi: "Ξ",
            xi: "ξ",
            xlArr: "⟸",
            xlarr: "⟵",
            xmap: "⟼",
            xnis: "⋻",
            xodot: "⨀",
            Xopf: "𝕏",
            xopf: "𝕩",
            xoplus: "⨁",
            xotime: "⨂",
            xrArr: "⟹",
            xrarr: "⟶",
            Xscr: "𝒳",
            xscr: "𝓍",
            xsqcup: "⨆",
            xuplus: "⨄",
            xutri: "△",
            xvee: "⋁",
            xwedge: "⋀",
            Yacute: "Ý",
            yacute: "ý",
            YAcy: "Я",
            yacy: "я",
            Ycirc: "Ŷ",
            ycirc: "ŷ",
            Ycy: "Ы",
            ycy: "ы",
            yen: "¥",
            Yfr: "𝔜",
            yfr: "𝔶",
            YIcy: "Ї",
            yicy: "ї",
            Yopf: "𝕐",
            yopf: "𝕪",
            Yscr: "𝒴",
            yscr: "𝓎",
            YUcy: "Ю",
            yucy: "ю",
            Yuml: "Ÿ",
            yuml: "ÿ",
            Zacute: "Ź",
            zacute: "ź",
            Zcaron: "Ž",
            zcaron: "ž",
            Zcy: "З",
            zcy: "з",
            Zdot: "Ż",
            zdot: "ż",
            zeetrf: "ℨ",
            ZeroWidthSpace: "​",
            Zeta: "Ζ",
            zeta: "ζ",
            Zfr: "ℨ",
            zfr: "𝔷",
            ZHcy: "Ж",
            zhcy: "ж",
            zigrarr: "⇝",
            Zopf: "ℤ",
            zopf: "𝕫",
            Zscr: "𝒵",
            zscr: "𝓏",
            zwj: "‍",
            zwnj: "‌",
          })),
          (e.entityMap = e.HTML_ENTITIES));
      })(Is)),
    Is
  );
}
var Wi = {},
  Md;
function TC() {
  if (Md) return Wi;
  Md = 1;
  var e = Ko().NAMESPACE,
    t =
      /[A-Z_a-z\xC0-\xD6\xD8-\xF6\u00F8-\u02FF\u0370-\u037D\u037F-\u1FFF\u200C-\u200D\u2070-\u218F\u2C00-\u2FEF\u3001-\uD7FF\uF900-\uFDCF\uFDF0-\uFFFD]/,
    o = new RegExp(
      "[\\-\\.0-9" +
        t.source.slice(1, -1) +
        "\\u00B7\\u0300-\\u036F\\u203F-\\u2040]",
    ),
    i = new RegExp(
      "^" + t.source + o.source + "*(?::" + t.source + o.source + "*)?$",
    ),
    a = 0,
    n = 1,
    r = 2,
    s = 3,
    u = 4,
    f = 5,
    d = 6,
    c = 7;
  function l(D, N) {
    ((this.message = D),
      (this.locator = N),
      Error.captureStackTrace && Error.captureStackTrace(this, l));
  }
  ((l.prototype = new Error()), (l.prototype.name = l.name));
  function h() {}
  h.prototype = {
    parse: function (D, N, P) {
      var R = this.domBuilder;
      (R.startDocument(),
        w(N, (N = {})),
        y(D, N, P, R, this.errorHandler),
        R.endDocument());
    },
  };
  function y(D, N, P, R, k) {
    function q(p) {
      if (p > 65535) {
        p -= 65536;
        var z = 55296 + (p >> 10),
          J = 56320 + (p & 1023);
        return String.fromCharCode(z, J);
      } else return String.fromCharCode(p);
    }
    function U(p) {
      var z = p.slice(1, -1);
      return Object.hasOwnProperty.call(P, z)
        ? P[z]
        : z.charAt(0) === "#"
          ? q(parseInt(z.substr(1).replace("x", "0x")))
          : (k.error("entity not found:" + p), p);
    }
    function $(p) {
      if (p > Ae) {
        var z = D.substring(Ae, p).replace(/&#?\w+;/g, U);
        (Y && V(Ae), R.characters(z, 0, p - Ae), (Ae = p));
      }
    }
    function V(p, z) {
      for (; p >= X && (z = fe.exec(D));)
        ((re = z.index), (X = re + z[0].length), Y.lineNumber++);
      Y.columnNumber = p - re + 1;
    }
    for (
      var re = 0,
        X = 0,
        fe = /.*(?:\r\n?|\n)|.*$/g,
        Y = R.locator,
        Ce = [{ currentNSMap: N }],
        ue = {},
        Ae = 0;
      ;
    ) {
      try {
        var Q = D.indexOf("<", Ae);
        if (Q < 0) {
          if (!D.substr(Ae).match(/^\s*$/)) {
            var ge = R.doc,
              I = ge.createTextNode(D.substr(Ae));
            (ge.appendChild(I), (R.currentElement = I));
          }
          return;
        }
        switch ((Q > Ae && $(Q), D.charAt(Q + 1))) {
          case "/":
            var Oe = D.indexOf(">", Q + 3),
              _ = D.substring(Q + 2, Oe).replace(/[ \t\n\r]+$/g, ""),
              W = Ce.pop();
            Oe < 0
              ? ((_ = D.substring(Q + 2).replace(/[\s<].*/, "")),
                k.error("end tag name: " + _ + " is not complete:" + W.tagName),
                (Oe = Q + 1 + _.length))
              : _.match(/\s</) &&
                ((_ = _.replace(/[\s<].*/, "")),
                k.error("end tag name: " + _ + " maybe not complete"),
                (Oe = Q + 1 + _.length));
            var M = W.localNSMap,
              le = W.tagName == _,
              he =
                le || (W.tagName && W.tagName.toLowerCase() == _.toLowerCase());
            if (he) {
              if ((R.endElement(W.uri, W.localName, _), M))
                for (var we in M)
                  Object.prototype.hasOwnProperty.call(M, we) &&
                    R.endPrefixMapping(we);
              le ||
                k.fatalError(
                  "end tag name: " +
                    _ +
                    " is not match the current start tagName:" +
                    W.tagName,
                );
            } else Ce.push(W);
            Oe++;
            break;
          case "?":
            (Y && V(Q), (Oe = v(D, Q, R)));
            break;
          case "!":
            (Y && V(Q), (Oe = A(D, Q, R, k)));
            break;
          default:
            Y && V(Q);
            var be = new C(),
              Fe = Ce[Ce.length - 1].currentNSMap,
              Oe = m(D, Q, be, Fe, U, k),
              Le = be.length;
            if (
              (!be.closed &&
                b(D, Oe, be.tagName, ue) &&
                ((be.closed = !0),
                P.nbsp || k.warning("unclosed xml attribute")),
              Y && Le)
            ) {
              for (var Ge = F(Y, {}), nt = 0; nt < Le; nt++) {
                var ht = be[nt];
                (V(ht.offset), (ht.locator = F(Y, {})));
              }
              ((R.locator = Ge), S(be, R, Fe) && Ce.push(be), (R.locator = Y));
            } else S(be, R, Fe) && Ce.push(be);
            e.isHTML(be.uri) && !be.closed
              ? (Oe = E(D, Oe, be.tagName, U, R))
              : Oe++;
        }
      } catch (p) {
        if (p instanceof l) throw p;
        (k.error("element parse error: " + p), (Oe = -1));
      }
      Oe > Ae ? (Ae = Oe) : $(Math.max(Q, Ae) + 1);
    }
  }
  function F(D, N) {
    return (
      (N.lineNumber = D.lineNumber),
      (N.columnNumber = D.columnNumber),
      N
    );
  }
  function m(D, N, P, R, k, q) {
    function U(Y, Ce, ue) {
      (P.attributeNames.hasOwnProperty(Y) &&
        q.fatalError("Attribute " + Y + " redefined"),
        P.addValue(Y, Ce.replace(/[\t\n\r]/g, " ").replace(/&#?\w+;/g, k), ue));
    }
    for (var $, V, re = ++N, X = a; ;) {
      var fe = D.charAt(re);
      switch (fe) {
        case "=":
          if (X === n) (($ = D.slice(N, re)), (X = s));
          else if (X === r) X = s;
          else throw new Error("attribute equal must after attrName");
          break;
        case "'":
        case '"':
          if (X === s || X === n)
            if (
              (X === n &&
                (q.warning('attribute value must after "="'),
                ($ = D.slice(N, re))),
              (N = re + 1),
              (re = D.indexOf(fe, N)),
              re > 0)
            )
              ((V = D.slice(N, re)), U($, V, N - 1), (X = f));
            else throw new Error("attribute value no end '" + fe + "' match");
          else if (X == u)
            ((V = D.slice(N, re)),
              U($, V, N),
              q.warning(
                'attribute "' + $ + '" missed start quot(' + fe + ")!!",
              ),
              (N = re + 1),
              (X = f));
          else throw new Error('attribute value must after "="');
          break;
        case "/":
          switch (X) {
            case a:
              P.setTagName(D.slice(N, re));
            case f:
            case d:
            case c:
              ((X = c), (P.closed = !0));
            case u:
            case n:
              break;
            case r:
              P.closed = !0;
              break;
            default:
              throw new Error("attribute invalid close char('/')");
          }
          break;
        case "":
          return (
            q.error("unexpected end of input"),
            X == a && P.setTagName(D.slice(N, re)),
            re
          );
        case ">":
          switch (X) {
            case a:
              P.setTagName(D.slice(N, re));
            case f:
            case d:
            case c:
              break;
            case u:
            case n:
              ((V = D.slice(N, re)),
                V.slice(-1) === "/" && ((P.closed = !0), (V = V.slice(0, -1))));
            case r:
              (X === r && (V = $),
                X == u
                  ? (q.warning('attribute "' + V + '" missed quot(")!'),
                    U($, V, N))
                  : ((!e.isHTML(R[""]) ||
                      !V.match(/^(?:disabled|checked|selected)$/i)) &&
                      q.warning(
                        'attribute "' +
                          V +
                          '" missed value!! "' +
                          V +
                          '" instead!!',
                      ),
                    U(V, V, N)));
              break;
            case s:
              throw new Error("attribute value missed!!");
          }
          return re;
        case "":
          fe = " ";
        default:
          if (fe <= " ")
            switch (X) {
              case a:
                (P.setTagName(D.slice(N, re)), (X = d));
                break;
              case n:
                (($ = D.slice(N, re)), (X = r));
                break;
              case u:
                var V = D.slice(N, re);
                (q.warning('attribute "' + V + '" missed quot(")!!'),
                  U($, V, N));
              case f:
                X = d;
                break;
            }
          else
            switch (X) {
              case r:
                (P.tagName,
                  (!e.isHTML(R[""]) ||
                    !$.match(/^(?:disabled|checked|selected)$/i)) &&
                    q.warning(
                      'attribute "' +
                        $ +
                        '" missed value!! "' +
                        $ +
                        '" instead2!!',
                    ),
                  U($, $, N),
                  (N = re),
                  (X = n));
                break;
              case f:
                q.warning('attribute space is required"' + $ + '"!!');
              case d:
                ((X = n), (N = re));
                break;
              case s:
                ((X = u), (N = re));
                break;
              case c:
                throw new Error(
                  "elements closed character '/' and '>' must be connected to",
                );
            }
      }
      re++;
    }
  }
  function S(D, N, P) {
    for (var R = D.tagName, k = null, fe = D.length; fe--;) {
      var q = D[fe],
        U = q.qName,
        $ = q.value,
        Y = U.indexOf(":");
      if (Y > 0)
        var V = (q.prefix = U.slice(0, Y)),
          re = U.slice(Y + 1),
          X = V === "xmlns" && re;
      else ((re = U), (V = null), (X = U === "xmlns" && ""));
      ((q.localName = re),
        X !== !1 &&
          (k == null && ((k = {}), w(P, (P = {}))),
          (P[X] = k[X] = $),
          (q.uri = e.XMLNS),
          N.startPrefixMapping(X, $)));
    }
    for (var fe = D.length; fe--;) {
      q = D[fe];
      var V = q.prefix;
      V &&
        (V === "xml" && (q.uri = e.XML), V !== "xmlns" && (q.uri = P[V || ""]));
    }
    var Y = R.indexOf(":");
    Y > 0
      ? ((V = D.prefix = R.slice(0, Y)), (re = D.localName = R.slice(Y + 1)))
      : ((V = null), (re = D.localName = R));
    var Ce = (D.uri = P[V || ""]);
    if ((N.startElement(Ce, re, R, D), D.closed)) {
      if ((N.endElement(Ce, re, R), k))
        for (V in k)
          Object.prototype.hasOwnProperty.call(k, V) && N.endPrefixMapping(V);
    } else return ((D.currentNSMap = P), (D.localNSMap = k), !0);
  }
  function E(D, N, P, R, k) {
    if (/^(?:script|textarea)$/i.test(P)) {
      var q = D.indexOf("</" + P + ">", N),
        U = D.substring(N + 1, q);
      if (/[&<]/.test(U))
        return /^script$/i.test(P)
          ? (k.characters(U, 0, U.length), q)
          : ((U = U.replace(/&#?\w+;/g, R)), k.characters(U, 0, U.length), q);
    }
    return N + 1;
  }
  function b(D, N, P, R) {
    var k = R[P];
    return (
      k == null &&
        ((k = D.lastIndexOf("</" + P + ">")),
        k < N && (k = D.lastIndexOf("</" + P)),
        (R[P] = k)),
      k < N
    );
  }
  function w(D, N) {
    for (var P in D)
      Object.prototype.hasOwnProperty.call(D, P) && (N[P] = D[P]);
  }
  function A(D, N, P, R) {
    var k = D.charAt(N + 2);
    switch (k) {
      case "-":
        if (D.charAt(N + 3) === "-") {
          var q = D.indexOf("-->", N + 4);
          return q > N
            ? (P.comment(D, N + 4, q - N - 4), q + 3)
            : (R.error("Unclosed comment"), -1);
        } else return -1;
      default:
        if (D.substr(N + 3, 6) == "CDATA[") {
          var q = D.indexOf("]]>", N + 9);
          return (
            P.startCDATA(),
            P.characters(D, N + 9, q - N - 9),
            P.endCDATA(),
            q + 3
          );
        }
        var U = g(D, N),
          $ = U.length;
        if ($ > 1 && /!doctype/i.test(U[0][0])) {
          var V = U[1][0],
            re = !1,
            X = !1;
          $ > 3 &&
            (/^public$/i.test(U[2][0])
              ? ((re = U[3][0]), (X = $ > 4 && U[4][0]))
              : /^system$/i.test(U[2][0]) && (X = U[3][0]));
          var fe = U[$ - 1];
          return (P.startDTD(V, re, X), P.endDTD(), fe.index + fe[0].length);
        }
    }
    return -1;
  }
  function v(D, N, P) {
    var R = D.indexOf("?>", N);
    if (R) {
      var k = D.substring(N, R).match(/^<\?(\S*)\s*([\s\S]*?)\s*$/);
      return k ? (k[0].length, P.processingInstruction(k[1], k[2]), R + 2) : -1;
    }
    return -1;
  }
  function C() {
    this.attributeNames = {};
  }
  C.prototype = {
    setTagName: function (D) {
      if (!i.test(D)) throw new Error("invalid tagName:" + D);
      this.tagName = D;
    },
    addValue: function (D, N, P) {
      if (!i.test(D)) throw new Error("invalid attribute:" + D);
      ((this.attributeNames[D] = this.length),
        (this[this.length++] = { qName: D, value: N, offset: P }));
    },
    length: 0,
    getLocalName: function (D) {
      return this[D].localName;
    },
    getLocator: function (D) {
      return this[D].locator;
    },
    getQName: function (D) {
      return this[D].qName;
    },
    getURI: function (D) {
      return this[D].uri;
    },
    getValue: function (D) {
      return this[D].value;
    },
  };
  function g(D, N) {
    var P,
      R = [],
      k = /'[^']+'|"[^"]+"|[^\s<>\/=]+=?|(\/?\s*>|<)/g;
    for (k.lastIndex = N, k.exec(D); (P = k.exec(D));)
      if ((R.push(P), P[1])) return R;
  }
  return ((Wi.XMLReader = h), (Wi.ParseError = l), Wi);
}
var Ud;
function xC() {
  if (Ud) return qn;
  Ud = 1;
  var e = Ko(),
    t = AD(),
    o = _C(),
    i = TC(),
    a = t.DOMImplementation,
    n = e.NAMESPACE,
    r = i.ParseError,
    s = i.XMLReader;
  function u(m) {
    return m
      .replace(
        /\r[\n\u0085]/g,
        `
`,
      )
      .replace(
        /[\r\u0085\u2028]/g,
        `
`,
      );
  }
  function f(m) {
    this.options = m || { locator: {} };
  }
  f.prototype.parseFromString = function (m, S) {
    var E = this.options,
      b = new s(),
      w = E.domBuilder || new c(),
      A = E.errorHandler,
      v = E.locator,
      C = E.xmlns || {},
      g = /\/x?html?$/.test(S),
      D = g ? o.HTML_ENTITIES : o.XML_ENTITIES;
    (v && w.setDocumentLocator(v),
      (b.errorHandler = d(A, w, v)),
      (b.domBuilder = E.domBuilder || w),
      g && (C[""] = n.HTML),
      (C.xml = C.xml || n.XML));
    var N = E.normalizeLineEndings || u;
    return (
      m && typeof m == "string"
        ? b.parse(N(m), C, D)
        : b.errorHandler.error("invalid doc source"),
      w.doc
    );
  };
  function d(m, S, E) {
    if (!m) {
      if (S instanceof c) return S;
      m = S;
    }
    var b = {},
      w = m instanceof Function;
    E = E || {};
    function A(v) {
      var C = m[v];
      (!C &&
        w &&
        (C =
          m.length == 2
            ? function (g) {
                m(v, g);
              }
            : m),
        (b[v] =
          (C &&
            function (g) {
              C("[xmldom " + v + "]	" + g + h(E));
            }) ||
          function () {}));
    }
    return (A("warning"), A("error"), A("fatalError"), b);
  }
  function c() {
    this.cdata = !1;
  }
  function l(m, S) {
    ((S.lineNumber = m.lineNumber), (S.columnNumber = m.columnNumber));
  }
  c.prototype = {
    startDocument: function () {
      ((this.doc = new a().createDocument(null, null, null)),
        this.locator && (this.doc.documentURI = this.locator.systemId));
    },
    startElement: function (m, S, E, b) {
      var w = this.doc,
        A = w.createElementNS(m, E || S),
        v = b.length;
      (F(this, A),
        (this.currentElement = A),
        this.locator && l(this.locator, A));
      for (var C = 0; C < v; C++) {
        var m = b.getURI(C),
          g = b.getValue(C),
          E = b.getQName(C),
          D = w.createAttributeNS(m, E);
        (this.locator && l(b.getLocator(C), D),
          (D.value = D.nodeValue = g),
          A.setAttributeNode(D));
      }
    },
    endElement: function (m, S, E) {
      var b = this.currentElement;
      (b.tagName, (this.currentElement = b.parentNode));
    },
    startPrefixMapping: function (m, S) {},
    endPrefixMapping: function (m) {},
    processingInstruction: function (m, S) {
      var E = this.doc.createProcessingInstruction(m, S);
      (this.locator && l(this.locator, E), F(this, E));
    },
    ignorableWhitespace: function (m, S, E) {},
    characters: function (m, S, E) {
      if (((m = y.apply(this, arguments)), m)) {
        if (this.cdata) var b = this.doc.createCDATASection(m);
        else var b = this.doc.createTextNode(m);
        (this.currentElement
          ? this.currentElement.appendChild(b)
          : /^\s*$/.test(m) && this.doc.appendChild(b),
          this.locator && l(this.locator, b));
      }
    },
    skippedEntity: function (m) {},
    endDocument: function () {
      this.doc.normalize();
    },
    setDocumentLocator: function (m) {
      (this.locator = m) && (m.lineNumber = 0);
    },
    comment: function (m, S, E) {
      m = y.apply(this, arguments);
      var b = this.doc.createComment(m);
      (this.locator && l(this.locator, b), F(this, b));
    },
    startCDATA: function () {
      this.cdata = !0;
    },
    endCDATA: function () {
      this.cdata = !1;
    },
    startDTD: function (m, S, E) {
      var b = this.doc.implementation;
      if (b && b.createDocumentType) {
        var w = b.createDocumentType(m, S, E);
        (this.locator && l(this.locator, w),
          F(this, w),
          (this.doc.doctype = w));
      }
    },
    warning: function (m) {
      console.warn("[xmldom warning]	" + m, h(this.locator));
    },
    error: function (m) {
      console.error("[xmldom error]	" + m, h(this.locator));
    },
    fatalError: function (m) {
      throw new r(m, this.locator);
    },
  };
  function h(m) {
    if (m)
      return (
        `
@` +
        (m.systemId || "") +
        "#[line:" +
        m.lineNumber +
        ",col:" +
        m.columnNumber +
        "]"
      );
  }
  function y(m, S, E) {
    return typeof m == "string"
      ? m.substr(S, E)
      : m.length >= S + E || S
        ? new java.lang.String(m, S, E) + ""
        : m;
  }
  "endDTD,startEntity,endEntity,attributeDecl,elementDecl,externalEntityDecl,internalEntityDecl,resolveEntity,getExternalSubset,notationDecl,unparsedEntityDecl".replace(
    /\w+/g,
    function (m) {
      c.prototype[m] = function () {
        return null;
      };
    },
  );
  function F(m, S) {
    m.currentElement ? m.currentElement.appendChild(S) : m.doc.appendChild(S);
  }
  return (
    (qn.__DOMHandler = c),
    (qn.normalizeLineEndings = u),
    (qn.DOMParser = f),
    qn
  );
}
var qd;
function NC() {
  if (qd) return Un;
  qd = 1;
  var e = AD();
  return (
    (Un.DOMImplementation = e.DOMImplementation),
    (Un.XMLSerializer = e.XMLSerializer),
    (Un.DOMParser = xC().DOMParser),
    Un
  );
}
var $d;
function IC() {
  if ($d) return Ns;
  $d = 1;
  const { DOMParser: e } = NC();
  Ns.parse = s;
  var t = 3,
    o = 4,
    i = 8;
  function a(f) {
    return f.nodeType === t || f.nodeType === i || f.nodeType === o;
  }
  function n(f) {
    return !f.childNodes || f.childNodes.length === 0;
  }
  function r(f, d) {
    if (!f) throw new Error(d);
  }
  function s(f) {
    var d = new e().parseFromString(f);
    r(
      d.documentElement.nodeName === "plist",
      "malformed document. First element should be <plist>",
    );
    var c = u(d.documentElement);
    return (c.length == 1 && (c = c[0]), c);
  }
  function u(f) {
    var d, c, l, h, y, F, m;
    if (!f) return null;
    if (f.nodeName === "plist") {
      if (((h = []), n(f))) return h;
      for (d = 0; d < f.childNodes.length; d++)
        a(f.childNodes[d]) || h.push(u(f.childNodes[d]));
      return h;
    } else if (f.nodeName === "dict") {
      if (((c = {}), (l = null), (F = 0), n(f))) return c;
      for (d = 0; d < f.childNodes.length; d++)
        a(f.childNodes[d]) ||
          (F % 2 === 0
            ? (r(
                f.childNodes[d].nodeName === "key",
                "Missing key while parsing <dict/>.",
              ),
              (l = u(f.childNodes[d])))
            : (r(
                f.childNodes[d].nodeName !== "key",
                'Unexpected key "' +
                  u(f.childNodes[d]) +
                  '" while parsing <dict/>.',
              ),
              (c[l] = u(f.childNodes[d]))),
          (F += 1));
      return (F % 2 === 1 && (c[l] = ""), c);
    } else if (f.nodeName === "array") {
      if (((h = []), n(f))) return h;
      for (d = 0; d < f.childNodes.length; d++)
        a(f.childNodes[d]) ||
          ((y = u(f.childNodes[d])), y != null && h.push(y));
      return h;
    } else if (f.nodeName !== "#text") {
      if (f.nodeName === "key")
        return n(f)
          ? ""
          : (r(
              f.childNodes[0].nodeValue !== "__proto__",
              "__proto__ keys can lead to prototype pollution. More details on CVE-2022-22912",
            ),
            f.childNodes[0].nodeValue);
      if (f.nodeName === "string") {
        if (((y = ""), n(f))) return y;
        for (d = 0; d < f.childNodes.length; d++) {
          var m = f.childNodes[d].nodeType;
          (m === t || m === o) && (y += f.childNodes[d].nodeValue);
        }
        return y;
      } else {
        if (f.nodeName === "integer")
          return (
            r(!n(f), 'Cannot parse "" as integer.'),
            parseInt(f.childNodes[0].nodeValue, 10)
          );
        if (f.nodeName === "real") {
          for (
            r(!n(f), 'Cannot parse "" as real.'), y = "", d = 0;
            d < f.childNodes.length;
            d++
          )
            f.childNodes[d].nodeType === t && (y += f.childNodes[d].nodeValue);
          return parseFloat(y);
        } else if (f.nodeName === "data") {
          if (((y = ""), n(f))) return Buffer.from(y, "base64");
          for (d = 0; d < f.childNodes.length; d++)
            f.childNodes[d].nodeType === t &&
              (y += f.childNodes[d].nodeValue.replace(/\s+/g, ""));
          return Buffer.from(y, "base64");
        } else {
          if (f.nodeName === "date")
            return (
              r(!n(f), 'Cannot parse "" as Date.'),
              new Date(f.childNodes[0].nodeValue)
            );
          if (f.nodeName === "null") return null;
          if (f.nodeName === "true") return !0;
          if (f.nodeName === "false") return !1;
          throw new Error("Invalid PLIST tag " + f.nodeName);
        }
      }
    }
  }
  return Ns;
}
var Os = {},
  $n = {},
  jd;
function OC() {
  if (jd) return $n;
  ((jd = 1), ($n.byteLength = s), ($n.toByteArray = f), ($n.fromByteArray = l));
  for (
    var e = [],
      t = [],
      o = typeof Uint8Array < "u" ? Uint8Array : Array,
      i = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/",
      a = 0,
      n = i.length;
    a < n;
    ++a
  )
    ((e[a] = i[a]), (t[i.charCodeAt(a)] = a));
  ((t[45] = 62), (t[95] = 63));
  function r(h) {
    var y = h.length;
    if (y % 4 > 0)
      throw new Error("Invalid string. Length must be a multiple of 4");
    var F = h.indexOf("=");
    F === -1 && (F = y);
    var m = F === y ? 0 : 4 - (F % 4);
    return [F, m];
  }
  function s(h) {
    var y = r(h),
      F = y[0],
      m = y[1];
    return ((F + m) * 3) / 4 - m;
  }
  function u(h, y, F) {
    return ((y + F) * 3) / 4 - F;
  }
  function f(h) {
    var y,
      F = r(h),
      m = F[0],
      S = F[1],
      E = new o(u(h, m, S)),
      b = 0,
      w = S > 0 ? m - 4 : m,
      A;
    for (A = 0; A < w; A += 4)
      ((y =
        (t[h.charCodeAt(A)] << 18) |
        (t[h.charCodeAt(A + 1)] << 12) |
        (t[h.charCodeAt(A + 2)] << 6) |
        t[h.charCodeAt(A + 3)]),
        (E[b++] = (y >> 16) & 255),
        (E[b++] = (y >> 8) & 255),
        (E[b++] = y & 255));
    return (
      S === 2 &&
        ((y = (t[h.charCodeAt(A)] << 2) | (t[h.charCodeAt(A + 1)] >> 4)),
        (E[b++] = y & 255)),
      S === 1 &&
        ((y =
          (t[h.charCodeAt(A)] << 10) |
          (t[h.charCodeAt(A + 1)] << 4) |
          (t[h.charCodeAt(A + 2)] >> 2)),
        (E[b++] = (y >> 8) & 255),
        (E[b++] = y & 255)),
      E
    );
  }
  function d(h) {
    return e[(h >> 18) & 63] + e[(h >> 12) & 63] + e[(h >> 6) & 63] + e[h & 63];
  }
  function c(h, y, F) {
    for (var m, S = [], E = y; E < F; E += 3)
      ((m =
        ((h[E] << 16) & 16711680) +
        ((h[E + 1] << 8) & 65280) +
        (h[E + 2] & 255)),
        S.push(d(m)));
    return S.join("");
  }
  function l(h) {
    for (
      var y, F = h.length, m = F % 3, S = [], E = 16383, b = 0, w = F - m;
      b < w;
      b += E
    )
      S.push(c(h, b, b + E > w ? w : b + E));
    return (
      m === 1
        ? ((y = h[F - 1]), S.push(e[y >> 2] + e[(y << 4) & 63] + "=="))
        : m === 2 &&
          ((y = (h[F - 2] << 8) + h[F - 1]),
          S.push(e[y >> 10] + e[(y >> 4) & 63] + e[(y << 2) & 63] + "=")),
      S.join("")
    );
  }
  return $n;
}
var Rt = {},
  Lt = {},
  Wd;
function Jt() {
  return (
    Wd ||
      ((Wd = 1),
      function () {
        var e,
          t,
          o,
          i,
          a,
          n,
          r,
          s = {}.hasOwnProperty;
        ((e = function (u, ...f) {
          var d, c, l, h;
          if (a(Object.assign)) Object.assign.apply(null, arguments);
          else
            for (d = 0, l = f.length; d < l; d++)
              if (((h = f[d]), h != null))
                for (c in h) s.call(h, c) && (u[c] = h[c]);
          return u;
        }),
          (a = function (u) {
            return (
              !!u && Object.prototype.toString.call(u) === "[object Function]"
            );
          }),
          (n = function (u) {
            var f;
            return !!u && ((f = typeof u) == "function" || f === "object");
          }),
          (o = function (u) {
            return a(Array.isArray)
              ? Array.isArray(u)
              : Object.prototype.toString.call(u) === "[object Array]";
          }),
          (i = function (u) {
            var f;
            if (o(u)) return !u.length;
            for (f in u) if (s.call(u, f)) return !1;
            return !0;
          }),
          (r = function (u) {
            var f, d;
            return (
              n(u) &&
              (d = Object.getPrototypeOf(u)) &&
              (f = d.constructor) &&
              typeof f == "function" &&
              f instanceof f &&
              Function.prototype.toString.call(f) ===
                Function.prototype.toString.call(Object)
            );
          }),
          (t = function (u) {
            return a(u.valueOf) ? u.valueOf() : u;
          }),
          (Lt.assign = e),
          (Lt.isFunction = a),
          (Lt.isObject = n),
          (Lt.isArray = o),
          (Lt.isEmpty = i),
          (Lt.isPlainObject = r),
          (Lt.getValue = t));
      }.call(Lt)),
    Lt
  );
}
var Ji = { exports: {} },
  PC = Ji.exports,
  Hd;
function bD() {
  return (
    Hd ||
      ((Hd = 1),
      function () {
        Ji.exports = class {
          hasFeature(t, o) {
            return !0;
          }
          createDocumentType(t, o, i) {
            throw new Error("This DOM method is not implemented.");
          }
          createDocument(t, o, i) {
            throw new Error("This DOM method is not implemented.");
          }
          createHTMLDocument(t) {
            throw new Error("This DOM method is not implemented.");
          }
          getFeature(t, o) {
            throw new Error("This DOM method is not implemented.");
          }
        };
      }.call(PC)),
    Ji.exports
  );
}
var Qi = { exports: {} },
  Zi = { exports: {} },
  eo = { exports: {} },
  RC = eo.exports,
  Gd;
function LC() {
  return (
    Gd ||
      ((Gd = 1),
      function () {
        eo.exports = class {
          constructor() {}
          handleError(t) {
            throw new Error(t);
          }
        };
      }.call(RC)),
    eo.exports
  );
}
var to = { exports: {} },
  BC = to.exports,
  Vd;
function kC() {
  return (
    Vd ||
      ((Vd = 1),
      function () {
        to.exports = function () {
          class e {
            constructor(o) {
              this.arr = o || [];
            }
            item(o) {
              return this.arr[o] || null;
            }
            contains(o) {
              return this.arr.indexOf(o) !== -1;
            }
          }
          return (
            Object.defineProperty(e.prototype, "length", {
              get: function () {
                return this.arr.length;
              },
            }),
            e
          );
        }.call(this);
      }.call(BC)),
    to.exports
  );
}
var MC = Zi.exports,
  zd;
function UC() {
  return (
    zd ||
      ((zd = 1),
      function () {
        var e, t;
        ((e = LC()),
          (t = kC()),
          (Zi.exports = function () {
            class o {
              constructor() {
                ((this.defaultParams = {
                  "canonical-form": !1,
                  "cdata-sections": !1,
                  comments: !1,
                  "datatype-normalization": !1,
                  "element-content-whitespace": !0,
                  entities: !0,
                  "error-handler": new e(),
                  infoset: !0,
                  "validate-if-schema": !1,
                  namespaces: !0,
                  "namespace-declarations": !0,
                  "normalize-characters": !1,
                  "schema-location": "",
                  "schema-type": "",
                  "split-cdata-sections": !0,
                  validate: !1,
                  "well-formed": !0,
                }),
                  (this.params = Object.create(this.defaultParams)));
              }
              getParameter(a) {
                return this.params.hasOwnProperty(a) ? this.params[a] : null;
              }
              canSetParameter(a, n) {
                return !0;
              }
              setParameter(a, n) {
                return n != null ? (this.params[a] = n) : delete this.params[a];
              }
            }
            return (
              Object.defineProperty(o.prototype, "parameterNames", {
                get: function () {
                  return new t(Object.keys(this.defaultParams));
                },
              }),
              o
            );
          }.call(this)));
      }.call(MC)),
    Zi.exports
  );
}
var ro = { exports: {} },
  no = { exports: {} },
  io = { exports: {} },
  qC = io.exports,
  Xd;
function Ye() {
  return (
    Xd ||
      ((Xd = 1),
      function () {
        io.exports = {
          Element: 1,
          Attribute: 2,
          Text: 3,
          CData: 4,
          EntityReference: 5,
          EntityDeclaration: 6,
          ProcessingInstruction: 7,
          Comment: 8,
          Document: 9,
          DocType: 10,
          DocumentFragment: 11,
          NotationDeclaration: 12,
          Declaration: 201,
          Raw: 202,
          AttributeDeclaration: 203,
          ElementDeclaration: 204,
          Dummy: 205,
        };
      }.call(qC)),
    io.exports
  );
}
var oo = { exports: {} },
  $C = oo.exports,
  Yd;
function FD() {
  return (
    Yd ||
      ((Yd = 1),
      function () {
        var e;
        ((e = Ye()),
          Ft(),
          (oo.exports = function () {
            class t {
              constructor(i, a, n) {
                if (
                  ((this.parent = i),
                  this.parent &&
                    ((this.options = this.parent.options),
                    (this.stringify = this.parent.stringify)),
                  a == null)
                )
                  throw new Error(
                    "Missing attribute name. " + this.debugInfo(a),
                  );
                ((this.name = this.stringify.name(a)),
                  (this.value = this.stringify.attValue(n)),
                  (this.type = e.Attribute),
                  (this.isId = !1),
                  (this.schemaTypeInfo = null));
              }
              clone() {
                return Object.create(this);
              }
              toString(i) {
                return this.options.writer.attribute(
                  this,
                  this.options.writer.filterOptions(i),
                );
              }
              debugInfo(i) {
                return (
                  (i = i || this.name),
                  i == null
                    ? "parent: <" + this.parent.name + ">"
                    : "attribute: {" +
                      i +
                      "}, parent: <" +
                      this.parent.name +
                      ">"
                );
              }
              isEqualNode(i) {
                return !(
                  i.namespaceURI !== this.namespaceURI ||
                  i.prefix !== this.prefix ||
                  i.localName !== this.localName ||
                  i.value !== this.value
                );
              }
            }
            return (
              Object.defineProperty(t.prototype, "nodeType", {
                get: function () {
                  return this.type;
                },
              }),
              Object.defineProperty(t.prototype, "ownerElement", {
                get: function () {
                  return this.parent;
                },
              }),
              Object.defineProperty(t.prototype, "textContent", {
                get: function () {
                  return this.value;
                },
                set: function (o) {
                  return (this.value = o || "");
                },
              }),
              Object.defineProperty(t.prototype, "namespaceURI", {
                get: function () {
                  return "";
                },
              }),
              Object.defineProperty(t.prototype, "prefix", {
                get: function () {
                  return "";
                },
              }),
              Object.defineProperty(t.prototype, "localName", {
                get: function () {
                  return this.name;
                },
              }),
              Object.defineProperty(t.prototype, "specified", {
                get: function () {
                  return !0;
                },
              }),
              t
            );
          }.call(this)));
      }.call($C)),
    oo.exports
  );
}
var ao = { exports: {} },
  jC = ao.exports,
  Kd;
function Fu() {
  return (
    Kd ||
      ((Kd = 1),
      function () {
        ao.exports = function () {
          class e {
            constructor(o) {
              this.nodes = o;
            }
            clone() {
              return (this.nodes = null);
            }
            getNamedItem(o) {
              return this.nodes[o];
            }
            setNamedItem(o) {
              var i;
              return (
                (i = this.nodes[o.nodeName]),
                (this.nodes[o.nodeName] = o),
                i || null
              );
            }
            removeNamedItem(o) {
              var i;
              return ((i = this.nodes[o]), delete this.nodes[o], i || null);
            }
            item(o) {
              return this.nodes[Object.keys(this.nodes)[o]] || null;
            }
            getNamedItemNS(o, i) {
              throw new Error("This DOM method is not implemented.");
            }
            setNamedItemNS(o) {
              throw new Error("This DOM method is not implemented.");
            }
            removeNamedItemNS(o, i) {
              throw new Error("This DOM method is not implemented.");
            }
          }
          return (
            Object.defineProperty(e.prototype, "length", {
              get: function () {
                return Object.keys(this.nodes).length || 0;
              },
            }),
            e
          );
        }.call(this);
      }.call(jC)),
    ao.exports
  );
}
var WC = no.exports,
  Jd;
function Su() {
  return (
    Jd ||
      ((Jd = 1),
      function () {
        var e,
          t,
          o,
          i,
          a,
          n,
          r,
          s = {}.hasOwnProperty;
        (({ isObject: r, isFunction: n, getValue: a } = Jt()),
          (i = Ft()),
          (e = Ye()),
          (t = FD()),
          (o = Fu()),
          (no.exports = function () {
            class u extends i {
              constructor(d, c, l) {
                var h, y, F, m;
                if ((super(d), c == null))
                  throw new Error("Missing element name. " + this.debugInfo());
                if (
                  ((this.name = this.stringify.name(c)),
                  (this.type = e.Element),
                  (this.attribs = {}),
                  (this.schemaTypeInfo = null),
                  l != null && this.attribute(l),
                  d.type === e.Document &&
                    ((this.isRoot = !0),
                    (this.documentObject = d),
                    (d.rootObject = this),
                    d.children))
                ) {
                  for (m = d.children, y = 0, F = m.length; y < F; y++)
                    if (((h = m[y]), h.type === e.DocType)) {
                      h.name = this.name;
                      break;
                    }
                }
              }
              clone() {
                var d, c, l, h;
                ((l = Object.create(this)),
                  l.isRoot && (l.documentObject = null),
                  (l.attribs = {}),
                  (h = this.attribs));
                for (c in h)
                  s.call(h, c) && ((d = h[c]), (l.attribs[c] = d.clone()));
                return (
                  (l.children = []),
                  this.children.forEach(function (y) {
                    var F;
                    return (
                      (F = y.clone()),
                      (F.parent = l),
                      l.children.push(F)
                    );
                  }),
                  l
                );
              }
              attribute(d, c) {
                var l, h;
                if ((d != null && (d = a(d)), r(d)))
                  for (l in d)
                    s.call(d, l) && ((h = d[l]), this.attribute(l, h));
                else
                  (n(c) && (c = c.apply()),
                    this.options.keepNullAttributes && c == null
                      ? (this.attribs[d] = new t(this, d, ""))
                      : c != null && (this.attribs[d] = new t(this, d, c)));
                return this;
              }
              removeAttribute(d) {
                var c, l, h;
                if (d == null)
                  throw new Error(
                    "Missing attribute name. " + this.debugInfo(),
                  );
                if (((d = a(d)), Array.isArray(d)))
                  for (l = 0, h = d.length; l < h; l++)
                    ((c = d[l]), delete this.attribs[c]);
                else delete this.attribs[d];
                return this;
              }
              toString(d) {
                return this.options.writer.element(
                  this,
                  this.options.writer.filterOptions(d),
                );
              }
              att(d, c) {
                return this.attribute(d, c);
              }
              a(d, c) {
                return this.attribute(d, c);
              }
              getAttribute(d) {
                return this.attribs.hasOwnProperty(d)
                  ? this.attribs[d].value
                  : null;
              }
              setAttribute(d, c) {
                throw new Error(
                  "This DOM method is not implemented." + this.debugInfo(),
                );
              }
              getAttributeNode(d) {
                return this.attribs.hasOwnProperty(d) ? this.attribs[d] : null;
              }
              setAttributeNode(d) {
                throw new Error(
                  "This DOM method is not implemented." + this.debugInfo(),
                );
              }
              removeAttributeNode(d) {
                throw new Error(
                  "This DOM method is not implemented." + this.debugInfo(),
                );
              }
              getElementsByTagName(d) {
                throw new Error(
                  "This DOM method is not implemented." + this.debugInfo(),
                );
              }
              getAttributeNS(d, c) {
                throw new Error(
                  "This DOM method is not implemented." + this.debugInfo(),
                );
              }
              setAttributeNS(d, c, l) {
                throw new Error(
                  "This DOM method is not implemented." + this.debugInfo(),
                );
              }
              removeAttributeNS(d, c) {
                throw new Error(
                  "This DOM method is not implemented." + this.debugInfo(),
                );
              }
              getAttributeNodeNS(d, c) {
                throw new Error(
                  "This DOM method is not implemented." + this.debugInfo(),
                );
              }
              setAttributeNodeNS(d) {
                throw new Error(
                  "This DOM method is not implemented." + this.debugInfo(),
                );
              }
              getElementsByTagNameNS(d, c) {
                throw new Error(
                  "This DOM method is not implemented." + this.debugInfo(),
                );
              }
              hasAttribute(d) {
                return this.attribs.hasOwnProperty(d);
              }
              hasAttributeNS(d, c) {
                throw new Error(
                  "This DOM method is not implemented." + this.debugInfo(),
                );
              }
              setIdAttribute(d, c) {
                return this.attribs.hasOwnProperty(d)
                  ? this.attribs[d].isId
                  : c;
              }
              setIdAttributeNS(d, c, l) {
                throw new Error(
                  "This DOM method is not implemented." + this.debugInfo(),
                );
              }
              setIdAttributeNode(d, c) {
                throw new Error(
                  "This DOM method is not implemented." + this.debugInfo(),
                );
              }
              getElementsByTagName(d) {
                throw new Error(
                  "This DOM method is not implemented." + this.debugInfo(),
                );
              }
              getElementsByTagNameNS(d, c) {
                throw new Error(
                  "This DOM method is not implemented." + this.debugInfo(),
                );
              }
              getElementsByClassName(d) {
                throw new Error(
                  "This DOM method is not implemented." + this.debugInfo(),
                );
              }
              isEqualNode(d) {
                var c, l, h;
                if (
                  !super.isEqualNode(d) ||
                  d.namespaceURI !== this.namespaceURI ||
                  d.prefix !== this.prefix ||
                  d.localName !== this.localName ||
                  d.attribs.length !== this.attribs.length
                )
                  return !1;
                for (
                  c = l = 0, h = this.attribs.length - 1;
                  0 <= h ? l <= h : l >= h;
                  c = 0 <= h ? ++l : --l
                )
                  if (!this.attribs[c].isEqualNode(d.attribs[c])) return !1;
                return !0;
              }
            }
            return (
              Object.defineProperty(u.prototype, "tagName", {
                get: function () {
                  return this.name;
                },
              }),
              Object.defineProperty(u.prototype, "namespaceURI", {
                get: function () {
                  return "";
                },
              }),
              Object.defineProperty(u.prototype, "prefix", {
                get: function () {
                  return "";
                },
              }),
              Object.defineProperty(u.prototype, "localName", {
                get: function () {
                  return this.name;
                },
              }),
              Object.defineProperty(u.prototype, "id", {
                get: function () {
                  throw new Error(
                    "This DOM method is not implemented." + this.debugInfo(),
                  );
                },
              }),
              Object.defineProperty(u.prototype, "className", {
                get: function () {
                  throw new Error(
                    "This DOM method is not implemented." + this.debugInfo(),
                  );
                },
              }),
              Object.defineProperty(u.prototype, "classList", {
                get: function () {
                  throw new Error(
                    "This DOM method is not implemented." + this.debugInfo(),
                  );
                },
              }),
              Object.defineProperty(u.prototype, "attributes", {
                get: function () {
                  return (
                    (!this.attributeMap || !this.attributeMap.nodes) &&
                      (this.attributeMap = new o(this.attribs)),
                    this.attributeMap
                  );
                },
              }),
              u
            );
          }.call(this)));
      }.call(WC)),
    no.exports
  );
}
var so = { exports: {} },
  uo = { exports: {} },
  HC = uo.exports,
  Qd;
function Jo() {
  return (
    Qd ||
      ((Qd = 1),
      function () {
        var e;
        ((e = Ft()),
          (uo.exports = function () {
            class t extends e {
              constructor(i) {
                (super(i), (this.value = ""));
              }
              clone() {
                return Object.create(this);
              }
              substringData(i, a) {
                throw new Error(
                  "This DOM method is not implemented." + this.debugInfo(),
                );
              }
              appendData(i) {
                throw new Error(
                  "This DOM method is not implemented." + this.debugInfo(),
                );
              }
              insertData(i, a) {
                throw new Error(
                  "This DOM method is not implemented." + this.debugInfo(),
                );
              }
              deleteData(i, a) {
                throw new Error(
                  "This DOM method is not implemented." + this.debugInfo(),
                );
              }
              replaceData(i, a, n) {
                throw new Error(
                  "This DOM method is not implemented." + this.debugInfo(),
                );
              }
              isEqualNode(i) {
                return !(!super.isEqualNode(i) || i.data !== this.data);
              }
            }
            return (
              Object.defineProperty(t.prototype, "data", {
                get: function () {
                  return this.value;
                },
                set: function (o) {
                  return (this.value = o || "");
                },
              }),
              Object.defineProperty(t.prototype, "length", {
                get: function () {
                  return this.value.length;
                },
              }),
              Object.defineProperty(t.prototype, "textContent", {
                get: function () {
                  return this.value;
                },
                set: function (o) {
                  return (this.value = o || "");
                },
              }),
              t
            );
          }.call(this)));
      }.call(HC)),
    uo.exports
  );
}
var GC = so.exports,
  Zd;
function _u() {
  return (
    Zd ||
      ((Zd = 1),
      function () {
        var e, t;
        ((e = Ye()),
          (t = Jo()),
          (so.exports = class extends t {
            constructor(i, a) {
              if ((super(i), a == null))
                throw new Error("Missing CDATA text. " + this.debugInfo());
              ((this.name = "#cdata-section"),
                (this.type = e.CData),
                (this.value = this.stringify.cdata(a)));
            }
            clone() {
              return Object.create(this);
            }
            toString(i) {
              return this.options.writer.cdata(
                this,
                this.options.writer.filterOptions(i),
              );
            }
          }));
      }.call(GC)),
    so.exports
  );
}
var lo = { exports: {} },
  VC = lo.exports,
  eh;
function Tu() {
  return (
    eh ||
      ((eh = 1),
      function () {
        var e, t;
        ((e = Ye()),
          (t = Jo()),
          (lo.exports = class extends t {
            constructor(i, a) {
              if ((super(i), a == null))
                throw new Error("Missing comment text. " + this.debugInfo());
              ((this.name = "#comment"),
                (this.type = e.Comment),
                (this.value = this.stringify.comment(a)));
            }
            clone() {
              return Object.create(this);
            }
            toString(i) {
              return this.options.writer.comment(
                this,
                this.options.writer.filterOptions(i),
              );
            }
          }));
      }.call(VC)),
    lo.exports
  );
}
var co = { exports: {} },
  zC = co.exports,
  th;
function xu() {
  return (
    th ||
      ((th = 1),
      function () {
        var e, t, o;
        (({ isObject: o } = Jt()),
          (t = Ft()),
          (e = Ye()),
          (co.exports = class extends t {
            constructor(a, n, r, s) {
              (super(a),
                o(n) && ({ version: n, encoding: r, standalone: s } = n),
                n || (n = "1.0"),
                (this.type = e.Declaration),
                (this.version = this.stringify.xmlVersion(n)),
                r != null && (this.encoding = this.stringify.xmlEncoding(r)),
                s != null &&
                  (this.standalone = this.stringify.xmlStandalone(s)));
            }
            toString(a) {
              return this.options.writer.declaration(
                this,
                this.options.writer.filterOptions(a),
              );
            }
          }));
      }.call(zC)),
    co.exports
  );
}
var fo = { exports: {} },
  ho = { exports: {} },
  XC = ho.exports,
  rh;
function Nu() {
  return (
    rh ||
      ((rh = 1),
      function () {
        var e, t;
        ((t = Ft()),
          (e = Ye()),
          (ho.exports = class extends t {
            constructor(i, a, n, r, s, u) {
              if ((super(i), a == null))
                throw new Error(
                  "Missing DTD element name. " + this.debugInfo(),
                );
              if (n == null)
                throw new Error(
                  "Missing DTD attribute name. " + this.debugInfo(a),
                );
              if (!r)
                throw new Error(
                  "Missing DTD attribute type. " + this.debugInfo(a),
                );
              if (!s)
                throw new Error(
                  "Missing DTD attribute default. " + this.debugInfo(a),
                );
              if (
                (s.indexOf("#") !== 0 && (s = "#" + s),
                !s.match(/^(#REQUIRED|#IMPLIED|#FIXED|#DEFAULT)$/))
              )
                throw new Error(
                  "Invalid default value type; expected: #REQUIRED, #IMPLIED, #FIXED or #DEFAULT. " +
                    this.debugInfo(a),
                );
              if (u && !s.match(/^(#FIXED|#DEFAULT)$/))
                throw new Error(
                  "Default value only applies to #FIXED or #DEFAULT. " +
                    this.debugInfo(a),
                );
              ((this.elementName = this.stringify.name(a)),
                (this.type = e.AttributeDeclaration),
                (this.attributeName = this.stringify.name(n)),
                (this.attributeType = this.stringify.dtdAttType(r)),
                u && (this.defaultValue = this.stringify.dtdAttDefault(u)),
                (this.defaultValueType = s));
            }
            toString(i) {
              return this.options.writer.dtdAttList(
                this,
                this.options.writer.filterOptions(i),
              );
            }
          }));
      }.call(XC)),
    ho.exports
  );
}
var po = { exports: {} },
  YC = po.exports,
  nh;
function Iu() {
  return (
    nh ||
      ((nh = 1),
      function () {
        var e, t, o;
        (({ isObject: o } = Jt()),
          (t = Ft()),
          (e = Ye()),
          (po.exports = function () {
            class i extends t {
              constructor(n, r, s, u) {
                if ((super(n), s == null))
                  throw new Error(
                    "Missing DTD entity name. " + this.debugInfo(s),
                  );
                if (u == null)
                  throw new Error(
                    "Missing DTD entity value. " + this.debugInfo(s),
                  );
                if (
                  ((this.pe = !!r),
                  (this.name = this.stringify.name(s)),
                  (this.type = e.EntityDeclaration),
                  !o(u))
                )
                  ((this.value = this.stringify.dtdEntityValue(u)),
                    (this.internal = !0));
                else {
                  if (!u.pubID && !u.sysID)
                    throw new Error(
                      "Public and/or system identifiers are required for an external entity. " +
                        this.debugInfo(s),
                    );
                  if (u.pubID && !u.sysID)
                    throw new Error(
                      "System identifier is required for a public external entity. " +
                        this.debugInfo(s),
                    );
                  if (
                    ((this.internal = !1),
                    u.pubID != null &&
                      (this.pubID = this.stringify.dtdPubID(u.pubID)),
                    u.sysID != null &&
                      (this.sysID = this.stringify.dtdSysID(u.sysID)),
                    u.nData != null &&
                      (this.nData = this.stringify.dtdNData(u.nData)),
                    this.pe && this.nData)
                  )
                    throw new Error(
                      "Notation declaration is not allowed in a parameter entity. " +
                        this.debugInfo(s),
                    );
                }
              }
              toString(n) {
                return this.options.writer.dtdEntity(
                  this,
                  this.options.writer.filterOptions(n),
                );
              }
            }
            return (
              Object.defineProperty(i.prototype, "publicId", {
                get: function () {
                  return this.pubID;
                },
              }),
              Object.defineProperty(i.prototype, "systemId", {
                get: function () {
                  return this.sysID;
                },
              }),
              Object.defineProperty(i.prototype, "notationName", {
                get: function () {
                  return this.nData || null;
                },
              }),
              Object.defineProperty(i.prototype, "inputEncoding", {
                get: function () {
                  return null;
                },
              }),
              Object.defineProperty(i.prototype, "xmlEncoding", {
                get: function () {
                  return null;
                },
              }),
              Object.defineProperty(i.prototype, "xmlVersion", {
                get: function () {
                  return null;
                },
              }),
              i
            );
          }.call(this)));
      }.call(YC)),
    po.exports
  );
}
var Do = { exports: {} },
  KC = Do.exports,
  ih;
function Ou() {
  return (
    ih ||
      ((ih = 1),
      function () {
        var e, t;
        ((t = Ft()),
          (e = Ye()),
          (Do.exports = class extends t {
            constructor(i, a, n) {
              if ((super(i), a == null))
                throw new Error(
                  "Missing DTD element name. " + this.debugInfo(),
                );
              (n || (n = "(#PCDATA)"),
                Array.isArray(n) && (n = "(" + n.join(",") + ")"),
                (this.name = this.stringify.name(a)),
                (this.type = e.ElementDeclaration),
                (this.value = this.stringify.dtdElementValue(n)));
            }
            toString(i) {
              return this.options.writer.dtdElement(
                this,
                this.options.writer.filterOptions(i),
              );
            }
          }));
      }.call(KC)),
    Do.exports
  );
}
var mo = { exports: {} },
  JC = mo.exports,
  oh;
function Pu() {
  return (
    oh ||
      ((oh = 1),
      function () {
        var e, t;
        ((t = Ft()),
          (e = Ye()),
          (mo.exports = function () {
            class o extends t {
              constructor(a, n, r) {
                if ((super(a), n == null))
                  throw new Error(
                    "Missing DTD notation name. " + this.debugInfo(n),
                  );
                if (!r.pubID && !r.sysID)
                  throw new Error(
                    "Public or system identifiers are required for an external entity. " +
                      this.debugInfo(n),
                  );
                ((this.name = this.stringify.name(n)),
                  (this.type = e.NotationDeclaration),
                  r.pubID != null &&
                    (this.pubID = this.stringify.dtdPubID(r.pubID)),
                  r.sysID != null &&
                    (this.sysID = this.stringify.dtdSysID(r.sysID)));
              }
              toString(a) {
                return this.options.writer.dtdNotation(
                  this,
                  this.options.writer.filterOptions(a),
                );
              }
            }
            return (
              Object.defineProperty(o.prototype, "publicId", {
                get: function () {
                  return this.pubID;
                },
              }),
              Object.defineProperty(o.prototype, "systemId", {
                get: function () {
                  return this.sysID;
                },
              }),
              o
            );
          }.call(this)));
      }.call(JC)),
    mo.exports
  );
}
var QC = fo.exports,
  ah;
function Ru() {
  return (
    ah ||
      ((ah = 1),
      function () {
        var e, t, o, i, a, n, r, s;
        (({ isObject: s } = Jt()),
          (r = Ft()),
          (e = Ye()),
          (t = Nu()),
          (i = Iu()),
          (o = Ou()),
          (a = Pu()),
          (n = Fu()),
          (fo.exports = function () {
            class u extends r {
              constructor(d, c, l) {
                var h, y, F, m;
                if ((super(d), (this.type = e.DocType), d.children)) {
                  for (m = d.children, y = 0, F = m.length; y < F; y++)
                    if (((h = m[y]), h.type === e.Element)) {
                      this.name = h.name;
                      break;
                    }
                }
                ((this.documentObject = d),
                  s(c) && ({ pubID: c, sysID: l } = c),
                  l == null && ([l, c] = [c, l]),
                  c != null && (this.pubID = this.stringify.dtdPubID(c)),
                  l != null && (this.sysID = this.stringify.dtdSysID(l)));
              }
              element(d, c) {
                var l;
                return ((l = new o(this, d, c)), this.children.push(l), this);
              }
              attList(d, c, l, h, y) {
                var F;
                return (
                  (F = new t(this, d, c, l, h, y)),
                  this.children.push(F),
                  this
                );
              }
              entity(d, c) {
                var l;
                return (
                  (l = new i(this, !1, d, c)),
                  this.children.push(l),
                  this
                );
              }
              pEntity(d, c) {
                var l;
                return (
                  (l = new i(this, !0, d, c)),
                  this.children.push(l),
                  this
                );
              }
              notation(d, c) {
                var l;
                return ((l = new a(this, d, c)), this.children.push(l), this);
              }
              toString(d) {
                return this.options.writer.docType(
                  this,
                  this.options.writer.filterOptions(d),
                );
              }
              ele(d, c) {
                return this.element(d, c);
              }
              att(d, c, l, h, y) {
                return this.attList(d, c, l, h, y);
              }
              ent(d, c) {
                return this.entity(d, c);
              }
              pent(d, c) {
                return this.pEntity(d, c);
              }
              not(d, c) {
                return this.notation(d, c);
              }
              up() {
                return this.root() || this.documentObject;
              }
              isEqualNode(d) {
                return !(
                  !super.isEqualNode(d) ||
                  d.name !== this.name ||
                  d.publicId !== this.publicId ||
                  d.systemId !== this.systemId
                );
              }
            }
            return (
              Object.defineProperty(u.prototype, "entities", {
                get: function () {
                  var f, d, c, l, h;
                  for (
                    l = {}, h = this.children, d = 0, c = h.length;
                    d < c;
                    d++
                  )
                    ((f = h[d]),
                      f.type === e.EntityDeclaration &&
                        !f.pe &&
                        (l[f.name] = f));
                  return new n(l);
                },
              }),
              Object.defineProperty(u.prototype, "notations", {
                get: function () {
                  var f, d, c, l, h;
                  for (
                    l = {}, h = this.children, d = 0, c = h.length;
                    d < c;
                    d++
                  )
                    ((f = h[d]),
                      f.type === e.NotationDeclaration && (l[f.name] = f));
                  return new n(l);
                },
              }),
              Object.defineProperty(u.prototype, "publicId", {
                get: function () {
                  return this.pubID;
                },
              }),
              Object.defineProperty(u.prototype, "systemId", {
                get: function () {
                  return this.sysID;
                },
              }),
              Object.defineProperty(u.prototype, "internalSubset", {
                get: function () {
                  throw new Error(
                    "This DOM method is not implemented." + this.debugInfo(),
                  );
                },
              }),
              u
            );
          }.call(this)));
      }.call(QC)),
    fo.exports
  );
}
var go = { exports: {} },
  ZC = go.exports,
  sh;
function Lu() {
  return (
    sh ||
      ((sh = 1),
      function () {
        var e, t;
        ((e = Ye()),
          (t = Ft()),
          (go.exports = class extends t {
            constructor(i, a) {
              if ((super(i), a == null))
                throw new Error("Missing raw text. " + this.debugInfo());
              ((this.type = e.Raw), (this.value = this.stringify.raw(a)));
            }
            clone() {
              return Object.create(this);
            }
            toString(i) {
              return this.options.writer.raw(
                this,
                this.options.writer.filterOptions(i),
              );
            }
          }));
      }.call(ZC)),
    go.exports
  );
}
var wo = { exports: {} },
  eA = wo.exports,
  uh;
function Bu() {
  return (
    uh ||
      ((uh = 1),
      function () {
        var e, t;
        ((e = Ye()),
          (t = Jo()),
          (wo.exports = function () {
            class o extends t {
              constructor(a, n) {
                if ((super(a), n == null))
                  throw new Error("Missing element text. " + this.debugInfo());
                ((this.name = "#text"),
                  (this.type = e.Text),
                  (this.value = this.stringify.text(n)));
              }
              clone() {
                return Object.create(this);
              }
              toString(a) {
                return this.options.writer.text(
                  this,
                  this.options.writer.filterOptions(a),
                );
              }
              splitText(a) {
                throw new Error(
                  "This DOM method is not implemented." + this.debugInfo(),
                );
              }
              replaceWholeText(a) {
                throw new Error(
                  "This DOM method is not implemented." + this.debugInfo(),
                );
              }
            }
            return (
              Object.defineProperty(o.prototype, "isElementContentWhitespace", {
                get: function () {
                  throw new Error(
                    "This DOM method is not implemented." + this.debugInfo(),
                  );
                },
              }),
              Object.defineProperty(o.prototype, "wholeText", {
                get: function () {
                  var i, a, n;
                  for (n = "", a = this.previousSibling; a;)
                    ((n = a.data + n), (a = a.previousSibling));
                  for (n += this.data, i = this.nextSibling; i;)
                    ((n = n + i.data), (i = i.nextSibling));
                  return n;
                },
              }),
              o
            );
          }.call(this)));
      }.call(eA)),
    wo.exports
  );
}
var yo = { exports: {} },
  tA = yo.exports,
  lh;
function ku() {
  return (
    lh ||
      ((lh = 1),
      function () {
        var e, t;
        ((e = Ye()),
          (t = Jo()),
          (yo.exports = class extends t {
            constructor(i, a, n) {
              if ((super(i), a == null))
                throw new Error(
                  "Missing instruction target. " + this.debugInfo(),
                );
              ((this.type = e.ProcessingInstruction),
                (this.target = this.stringify.insTarget(a)),
                (this.name = this.target),
                n && (this.value = this.stringify.insValue(n)));
            }
            clone() {
              return Object.create(this);
            }
            toString(i) {
              return this.options.writer.processingInstruction(
                this,
                this.options.writer.filterOptions(i),
              );
            }
            isEqualNode(i) {
              return !(!super.isEqualNode(i) || i.target !== this.target);
            }
          }));
      }.call(tA)),
    yo.exports
  );
}
var Eo = { exports: {} },
  rA = Eo.exports,
  ch;
function SD() {
  return (
    ch ||
      ((ch = 1),
      function () {
        var e, t;
        ((t = Ft()),
          (e = Ye()),
          (Eo.exports = class extends t {
            constructor(i) {
              (super(i), (this.type = e.Dummy));
            }
            clone() {
              return Object.create(this);
            }
            toString(i) {
              return "";
            }
          }));
      }.call(rA)),
    Eo.exports
  );
}
var vo = { exports: {} },
  nA = vo.exports,
  fh;
function iA() {
  return (
    fh ||
      ((fh = 1),
      function () {
        vo.exports = function () {
          class e {
            constructor(o) {
              this.nodes = o;
            }
            clone() {
              return (this.nodes = null);
            }
            item(o) {
              return this.nodes[o] || null;
            }
          }
          return (
            Object.defineProperty(e.prototype, "length", {
              get: function () {
                return this.nodes.length || 0;
              },
            }),
            e
          );
        }.call(this);
      }.call(nA)),
    vo.exports
  );
}
var Co = { exports: {} },
  oA = Co.exports,
  dh;
function aA() {
  return (
    dh ||
      ((dh = 1),
      function () {
        Co.exports = {
          Disconnected: 1,
          Preceding: 2,
          Following: 4,
          Contains: 8,
          ContainedBy: 16,
          ImplementationSpecific: 32,
        };
      }.call(oA)),
    Co.exports
  );
}
var sA = ro.exports,
  hh;
function Ft() {
  return (
    hh ||
      ((hh = 1),
      function () {
        var e,
          t,
          o,
          i,
          a,
          n,
          r,
          s,
          u,
          f,
          d,
          c,
          l,
          h,
          y,
          F,
          m = {}.hasOwnProperty,
          S = [].splice;
        (({ isObject: F, isFunction: y, isEmpty: h, getValue: l } = Jt()),
          (s = null),
          (o = null),
          (i = null),
          (a = null),
          (n = null),
          (d = null),
          (c = null),
          (f = null),
          (r = null),
          (t = null),
          (u = null),
          (e = null),
          (ro.exports = function () {
            class E {
              constructor(w) {
                ((this.parent = w),
                  this.parent &&
                    ((this.options = this.parent.options),
                    (this.stringify = this.parent.stringify)),
                  (this.value = null),
                  (this.children = []),
                  (this.baseURI = null),
                  s ||
                    ((s = Su()),
                    (o = _u()),
                    (i = Tu()),
                    (a = xu()),
                    (n = Ru()),
                    (d = Lu()),
                    (c = Bu()),
                    (f = ku()),
                    (r = SD()),
                    (t = Ye()),
                    (u = iA()),
                    Fu(),
                    (e = aA())));
              }
              setParent(w) {
                var A, v, C, g, D;
                for (
                  this.parent = w,
                    w &&
                      ((this.options = w.options),
                      (this.stringify = w.stringify)),
                    g = this.children,
                    D = [],
                    v = 0,
                    C = g.length;
                  v < C;
                  v++
                )
                  ((A = g[v]), D.push(A.setParent(this)));
                return D;
              }
              element(w, A, v) {
                var C, g, D, N, P, R, k, q, U;
                if (
                  ((R = null),
                  A === null && v == null && ([A, v] = [{}, null]),
                  A == null && (A = {}),
                  (A = l(A)),
                  F(A) || ([v, A] = [A, v]),
                  w != null && (w = l(w)),
                  Array.isArray(w))
                )
                  for (D = 0, k = w.length; D < k; D++)
                    ((g = w[D]), (R = this.element(g)));
                else if (y(w)) R = this.element(w.apply());
                else if (F(w)) {
                  for (P in w)
                    if (m.call(w, P))
                      if (
                        ((U = w[P]),
                        y(U) && (U = U.apply()),
                        !this.options.ignoreDecorators &&
                          this.stringify.convertAttKey &&
                          P.indexOf(this.stringify.convertAttKey) === 0)
                      )
                        R = this.attribute(
                          P.substr(this.stringify.convertAttKey.length),
                          U,
                        );
                      else if (
                        !this.options.separateArrayItems &&
                        Array.isArray(U) &&
                        h(U)
                      )
                        R = this.dummy();
                      else if (F(U) && h(U)) R = this.element(P);
                      else if (!this.options.keepNullNodes && U == null)
                        R = this.dummy();
                      else if (
                        !this.options.separateArrayItems &&
                        Array.isArray(U)
                      )
                        for (N = 0, q = U.length; N < q; N++)
                          ((g = U[N]),
                            (C = {}),
                            (C[P] = g),
                            (R = this.element(C)));
                      else
                        F(U)
                          ? !this.options.ignoreDecorators &&
                            this.stringify.convertTextKey &&
                            P.indexOf(this.stringify.convertTextKey) === 0
                            ? (R = this.element(U))
                            : ((R = this.element(P)), R.element(U))
                          : (R = this.element(P, U));
                } else
                  !this.options.keepNullNodes && v === null
                    ? (R = this.dummy())
                    : !this.options.ignoreDecorators &&
                        this.stringify.convertTextKey &&
                        w.indexOf(this.stringify.convertTextKey) === 0
                      ? (R = this.text(v))
                      : !this.options.ignoreDecorators &&
                          this.stringify.convertCDataKey &&
                          w.indexOf(this.stringify.convertCDataKey) === 0
                        ? (R = this.cdata(v))
                        : !this.options.ignoreDecorators &&
                            this.stringify.convertCommentKey &&
                            w.indexOf(this.stringify.convertCommentKey) === 0
                          ? (R = this.comment(v))
                          : !this.options.ignoreDecorators &&
                              this.stringify.convertRawKey &&
                              w.indexOf(this.stringify.convertRawKey) === 0
                            ? (R = this.raw(v))
                            : !this.options.ignoreDecorators &&
                                this.stringify.convertPIKey &&
                                w.indexOf(this.stringify.convertPIKey) === 0
                              ? (R = this.instruction(
                                  w.substr(this.stringify.convertPIKey.length),
                                  v,
                                ))
                              : (R = this.node(w, A, v));
                if (R == null)
                  throw new Error(
                    "Could not create any elements with: " +
                      w +
                      ". " +
                      this.debugInfo(),
                  );
                return R;
              }
              insertBefore(w, A, v) {
                var C, g, D, N, P;
                if (w?.type)
                  return (
                    (D = w),
                    (N = A),
                    D.setParent(this),
                    N
                      ? ((g = children.indexOf(N)),
                        (P = children.splice(g)),
                        children.push(D),
                        Array.prototype.push.apply(children, P))
                      : children.push(D),
                    D
                  );
                if (this.isRoot)
                  throw new Error(
                    "Cannot insert elements at root level. " +
                      this.debugInfo(w),
                  );
                return (
                  (g = this.parent.children.indexOf(this)),
                  (P = this.parent.children.splice(g)),
                  (C = this.parent.element(w, A, v)),
                  Array.prototype.push.apply(this.parent.children, P),
                  C
                );
              }
              insertAfter(w, A, v) {
                var C, g, D;
                if (this.isRoot)
                  throw new Error(
                    "Cannot insert elements at root level. " +
                      this.debugInfo(w),
                  );
                return (
                  (g = this.parent.children.indexOf(this)),
                  (D = this.parent.children.splice(g + 1)),
                  (C = this.parent.element(w, A, v)),
                  Array.prototype.push.apply(this.parent.children, D),
                  C
                );
              }
              remove() {
                var w;
                if (this.isRoot)
                  throw new Error(
                    "Cannot remove the root element. " + this.debugInfo(),
                  );
                return (
                  (w = this.parent.children.indexOf(this)),
                  S.apply(this.parent.children, [w, w - w + 1].concat([])),
                  this.parent
                );
              }
              node(w, A, v) {
                var C;
                return (
                  w != null && (w = l(w)),
                  A || (A = {}),
                  (A = l(A)),
                  F(A) || ([v, A] = [A, v]),
                  (C = new s(this, w, A)),
                  v != null && C.text(v),
                  this.children.push(C),
                  C
                );
              }
              text(w) {
                var A;
                return (
                  F(w) && this.element(w),
                  (A = new c(this, w)),
                  this.children.push(A),
                  this
                );
              }
              cdata(w) {
                var A;
                return ((A = new o(this, w)), this.children.push(A), this);
              }
              comment(w) {
                var A;
                return ((A = new i(this, w)), this.children.push(A), this);
              }
              commentBefore(w) {
                var A, v;
                return (
                  (A = this.parent.children.indexOf(this)),
                  (v = this.parent.children.splice(A)),
                  this.parent.comment(w),
                  Array.prototype.push.apply(this.parent.children, v),
                  this
                );
              }
              commentAfter(w) {
                var A, v;
                return (
                  (A = this.parent.children.indexOf(this)),
                  (v = this.parent.children.splice(A + 1)),
                  this.parent.comment(w),
                  Array.prototype.push.apply(this.parent.children, v),
                  this
                );
              }
              raw(w) {
                var A;
                return ((A = new d(this, w)), this.children.push(A), this);
              }
              dummy() {
                var w;
                return ((w = new r(this)), w);
              }
              instruction(w, A) {
                var v, C, g, D, N;
                if (
                  (w != null && (w = l(w)),
                  A != null && (A = l(A)),
                  Array.isArray(w))
                )
                  for (D = 0, N = w.length; D < N; D++)
                    ((v = w[D]), this.instruction(v));
                else if (F(w))
                  for (v in w)
                    m.call(w, v) && ((C = w[v]), this.instruction(v, C));
                else
                  (y(A) && (A = A.apply()),
                    (g = new f(this, w, A)),
                    this.children.push(g));
                return this;
              }
              instructionBefore(w, A) {
                var v, C;
                return (
                  (v = this.parent.children.indexOf(this)),
                  (C = this.parent.children.splice(v)),
                  this.parent.instruction(w, A),
                  Array.prototype.push.apply(this.parent.children, C),
                  this
                );
              }
              instructionAfter(w, A) {
                var v, C;
                return (
                  (v = this.parent.children.indexOf(this)),
                  (C = this.parent.children.splice(v + 1)),
                  this.parent.instruction(w, A),
                  Array.prototype.push.apply(this.parent.children, C),
                  this
                );
              }
              declaration(w, A, v) {
                var C, g;
                return (
                  (C = this.document()),
                  (g = new a(C, w, A, v)),
                  C.children.length === 0
                    ? C.children.unshift(g)
                    : C.children[0].type === t.Declaration
                      ? (C.children[0] = g)
                      : C.children.unshift(g),
                  C.root() || C
                );
              }
              dtd(w, A) {
                var v, C, g, D, N, P, R, k, q, U;
                for (
                  C = this.document(),
                    g = new n(C, w, A),
                    q = C.children,
                    D = N = 0,
                    R = q.length;
                  N < R;
                  D = ++N
                )
                  if (((v = q[D]), v.type === t.DocType))
                    return ((C.children[D] = g), g);
                for (U = C.children, D = P = 0, k = U.length; P < k; D = ++P)
                  if (((v = U[D]), v.isRoot))
                    return (C.children.splice(D, 0, g), g);
                return (C.children.push(g), g);
              }
              up() {
                if (this.isRoot)
                  throw new Error(
                    "The root node has no parent. Use doc() if you need to get the document object.",
                  );
                return this.parent;
              }
              root() {
                var w;
                for (w = this; w;) {
                  if (w.type === t.Document) return w.rootObject;
                  if (w.isRoot) return w;
                  w = w.parent;
                }
              }
              document() {
                var w;
                for (w = this; w;) {
                  if (w.type === t.Document) return w;
                  w = w.parent;
                }
              }
              end(w) {
                return this.document().end(w);
              }
              prev() {
                var w;
                if (((w = this.parent.children.indexOf(this)), w < 1))
                  throw new Error(
                    "Already at the first node. " + this.debugInfo(),
                  );
                return this.parent.children[w - 1];
              }
              next() {
                var w;
                if (
                  ((w = this.parent.children.indexOf(this)),
                  w === -1 || w === this.parent.children.length - 1)
                )
                  throw new Error(
                    "Already at the last node. " + this.debugInfo(),
                  );
                return this.parent.children[w + 1];
              }
              importDocument(w) {
                var A, v, C, g, D;
                if (
                  ((v = w.root().clone()),
                  (v.parent = this),
                  (v.isRoot = !1),
                  this.children.push(v),
                  this.type === t.Document &&
                    ((v.isRoot = !0),
                    (v.documentObject = this),
                    (this.rootObject = v),
                    this.children))
                ) {
                  for (D = this.children, C = 0, g = D.length; C < g; C++)
                    if (((A = D[C]), A.type === t.DocType)) {
                      A.name = v.name;
                      break;
                    }
                }
                return this;
              }
              debugInfo(w) {
                var A, v;
                return (
                  (w = w || this.name),
                  w == null && !((A = this.parent) != null && A.name)
                    ? ""
                    : w == null
                      ? "parent: <" + this.parent.name + ">"
                      : (v = this.parent) != null && v.name
                        ? "node: <" +
                          w +
                          ">, parent: <" +
                          this.parent.name +
                          ">"
                        : "node: <" + w + ">"
                );
              }
              ele(w, A, v) {
                return this.element(w, A, v);
              }
              nod(w, A, v) {
                return this.node(w, A, v);
              }
              txt(w) {
                return this.text(w);
              }
              dat(w) {
                return this.cdata(w);
              }
              com(w) {
                return this.comment(w);
              }
              ins(w, A) {
                return this.instruction(w, A);
              }
              doc() {
                return this.document();
              }
              dec(w, A, v) {
                return this.declaration(w, A, v);
              }
              e(w, A, v) {
                return this.element(w, A, v);
              }
              n(w, A, v) {
                return this.node(w, A, v);
              }
              t(w) {
                return this.text(w);
              }
              d(w) {
                return this.cdata(w);
              }
              c(w) {
                return this.comment(w);
              }
              r(w) {
                return this.raw(w);
              }
              i(w, A) {
                return this.instruction(w, A);
              }
              u() {
                return this.up();
              }
              importXMLBuilder(w) {
                return this.importDocument(w);
              }
              attribute(w, A) {
                throw new Error("attribute() applies to element nodes only.");
              }
              att(w, A) {
                return this.attribute(w, A);
              }
              a(w, A) {
                return this.attribute(w, A);
              }
              removeAttribute(w) {
                throw new Error("attribute() applies to element nodes only.");
              }
              replaceChild(w, A) {
                throw new Error(
                  "This DOM method is not implemented." + this.debugInfo(),
                );
              }
              removeChild(w) {
                throw new Error(
                  "This DOM method is not implemented." + this.debugInfo(),
                );
              }
              appendChild(w) {
                throw new Error(
                  "This DOM method is not implemented." + this.debugInfo(),
                );
              }
              hasChildNodes() {
                return this.children.length !== 0;
              }
              cloneNode(w) {
                throw new Error(
                  "This DOM method is not implemented." + this.debugInfo(),
                );
              }
              normalize() {
                throw new Error(
                  "This DOM method is not implemented." + this.debugInfo(),
                );
              }
              isSupported(w, A) {
                return !0;
              }
              hasAttributes() {
                return this.attribs.length !== 0;
              }
              compareDocumentPosition(w) {
                var A, v;
                return (
                  (A = this),
                  A === w
                    ? 0
                    : this.document() !== w.document()
                      ? ((v = e.Disconnected | e.ImplementationSpecific),
                        Math.random() < 0.5
                          ? (v |= e.Preceding)
                          : (v |= e.Following),
                        v)
                      : A.isAncestor(w)
                        ? e.Contains | e.Preceding
                        : A.isDescendant(w)
                          ? e.Contains | e.Following
                          : A.isPreceding(w)
                            ? e.Preceding
                            : e.Following
                );
              }
              isSameNode(w) {
                throw new Error(
                  "This DOM method is not implemented." + this.debugInfo(),
                );
              }
              lookupPrefix(w) {
                throw new Error(
                  "This DOM method is not implemented." + this.debugInfo(),
                );
              }
              isDefaultNamespace(w) {
                throw new Error(
                  "This DOM method is not implemented." + this.debugInfo(),
                );
              }
              lookupNamespaceURI(w) {
                throw new Error(
                  "This DOM method is not implemented." + this.debugInfo(),
                );
              }
              isEqualNode(w) {
                var A, v, C;
                if (
                  w.nodeType !== this.nodeType ||
                  w.children.length !== this.children.length
                )
                  return !1;
                for (
                  A = v = 0, C = this.children.length - 1;
                  0 <= C ? v <= C : v >= C;
                  A = 0 <= C ? ++v : --v
                )
                  if (!this.children[A].isEqualNode(w.children[A])) return !1;
                return !0;
              }
              getFeature(w, A) {
                throw new Error(
                  "This DOM method is not implemented." + this.debugInfo(),
                );
              }
              setUserData(w, A, v) {
                throw new Error(
                  "This DOM method is not implemented." + this.debugInfo(),
                );
              }
              getUserData(w) {
                throw new Error(
                  "This DOM method is not implemented." + this.debugInfo(),
                );
              }
              contains(w) {
                return w ? w === this || this.isDescendant(w) : !1;
              }
              isDescendant(w) {
                var A, v, C, g, D;
                for (D = this.children, C = 0, g = D.length; C < g; C++)
                  if (((A = D[C]), w === A || ((v = A.isDescendant(w)), v)))
                    return !0;
                return !1;
              }
              isAncestor(w) {
                return w.isDescendant(this);
              }
              isPreceding(w) {
                var A, v;
                return (
                  (A = this.treePosition(w)),
                  (v = this.treePosition(this)),
                  A === -1 || v === -1 ? !1 : A < v
                );
              }
              isFollowing(w) {
                var A, v;
                return (
                  (A = this.treePosition(w)),
                  (v = this.treePosition(this)),
                  A === -1 || v === -1 ? !1 : A > v
                );
              }
              treePosition(w) {
                var A, v;
                return (
                  (v = 0),
                  (A = !1),
                  this.foreachTreeNode(this.document(), function (C) {
                    if ((v++, !A && C === w)) return (A = !0);
                  }),
                  A ? v : -1
                );
              }
              foreachTreeNode(w, A) {
                var v, C, g, D, N;
                for (
                  w || (w = this.document()),
                    D = w.children,
                    C = 0,
                    g = D.length;
                  C < g;
                  C++
                ) {
                  if (((v = D[C]), (N = A(v)))) return N;
                  if (((N = this.foreachTreeNode(v, A)), N)) return N;
                }
              }
            }
            return (
              Object.defineProperty(E.prototype, "nodeName", {
                get: function () {
                  return this.name;
                },
              }),
              Object.defineProperty(E.prototype, "nodeType", {
                get: function () {
                  return this.type;
                },
              }),
              Object.defineProperty(E.prototype, "nodeValue", {
                get: function () {
                  return this.value;
                },
              }),
              Object.defineProperty(E.prototype, "parentNode", {
                get: function () {
                  return this.parent;
                },
              }),
              Object.defineProperty(E.prototype, "childNodes", {
                get: function () {
                  return (
                    (!this.childNodeList || !this.childNodeList.nodes) &&
                      (this.childNodeList = new u(this.children)),
                    this.childNodeList
                  );
                },
              }),
              Object.defineProperty(E.prototype, "firstChild", {
                get: function () {
                  return this.children[0] || null;
                },
              }),
              Object.defineProperty(E.prototype, "lastChild", {
                get: function () {
                  return this.children[this.children.length - 1] || null;
                },
              }),
              Object.defineProperty(E.prototype, "previousSibling", {
                get: function () {
                  var b;
                  return (
                    (b = this.parent.children.indexOf(this)),
                    this.parent.children[b - 1] || null
                  );
                },
              }),
              Object.defineProperty(E.prototype, "nextSibling", {
                get: function () {
                  var b;
                  return (
                    (b = this.parent.children.indexOf(this)),
                    this.parent.children[b + 1] || null
                  );
                },
              }),
              Object.defineProperty(E.prototype, "ownerDocument", {
                get: function () {
                  return this.document() || null;
                },
              }),
              Object.defineProperty(E.prototype, "textContent", {
                get: function () {
                  var b, w, A, v, C;
                  if (
                    this.nodeType === t.Element ||
                    this.nodeType === t.DocumentFragment
                  ) {
                    for (
                      C = "", v = this.children, w = 0, A = v.length;
                      w < A;
                      w++
                    )
                      ((b = v[w]), b.textContent && (C += b.textContent));
                    return C;
                  } else return null;
                },
                set: function (b) {
                  throw new Error(
                    "This DOM method is not implemented." + this.debugInfo(),
                  );
                },
              }),
              E
            );
          }.call(this)));
      }.call(sA)),
    ro.exports
  );
}
var Ao = { exports: {} },
  uA = Ao.exports,
  ph;
function _D() {
  return (
    ph ||
      ((ph = 1),
      function () {
        var e = {}.hasOwnProperty;
        Ao.exports = function () {
          class t {
            constructor(i) {
              var a, n, r;
              ((this.assertLegalChar = this.assertLegalChar.bind(this)),
                (this.assertLegalName = this.assertLegalName.bind(this)),
                i || (i = {}),
                (this.options = i),
                this.options.version || (this.options.version = "1.0"),
                (n = i.stringify || {}));
              for (a in n) e.call(n, a) && ((r = n[a]), (this[a] = r));
            }
            name(i) {
              return this.options.noValidation
                ? i
                : this.assertLegalName("" + i || "");
            }
            text(i) {
              return this.options.noValidation
                ? i
                : this.assertLegalChar(this.textEscape("" + i || ""));
            }
            cdata(i) {
              return this.options.noValidation
                ? i
                : ((i = "" + i || ""),
                  (i = i.replace("]]>", "]]]]><![CDATA[>")),
                  this.assertLegalChar(i));
            }
            comment(i) {
              if (this.options.noValidation) return i;
              if (((i = "" + i || ""), i.match(/--/)))
                throw new Error(
                  "Comment text cannot contain double-hypen: " + i,
                );
              return this.assertLegalChar(i);
            }
            raw(i) {
              return this.options.noValidation ? i : "" + i || "";
            }
            attValue(i) {
              return this.options.noValidation
                ? i
                : this.assertLegalChar(this.attEscape((i = "" + i || "")));
            }
            insTarget(i) {
              return this.options.noValidation
                ? i
                : this.assertLegalChar("" + i || "");
            }
            insValue(i) {
              if (this.options.noValidation) return i;
              if (((i = "" + i || ""), i.match(/\?>/)))
                throw new Error("Invalid processing instruction value: " + i);
              return this.assertLegalChar(i);
            }
            xmlVersion(i) {
              if (this.options.noValidation) return i;
              if (((i = "" + i || ""), !i.match(/1\.[0-9]+/)))
                throw new Error("Invalid version number: " + i);
              return i;
            }
            xmlEncoding(i) {
              if (this.options.noValidation) return i;
              if (
                ((i = "" + i || ""), !i.match(/^[A-Za-z](?:[A-Za-z0-9._-])*$/))
              )
                throw new Error("Invalid encoding: " + i);
              return this.assertLegalChar(i);
            }
            xmlStandalone(i) {
              return this.options.noValidation ? i : i ? "yes" : "no";
            }
            dtdPubID(i) {
              return this.options.noValidation
                ? i
                : this.assertLegalChar("" + i || "");
            }
            dtdSysID(i) {
              return this.options.noValidation
                ? i
                : this.assertLegalChar("" + i || "");
            }
            dtdElementValue(i) {
              return this.options.noValidation
                ? i
                : this.assertLegalChar("" + i || "");
            }
            dtdAttType(i) {
              return this.options.noValidation
                ? i
                : this.assertLegalChar("" + i || "");
            }
            dtdAttDefault(i) {
              return this.options.noValidation
                ? i
                : this.assertLegalChar("" + i || "");
            }
            dtdEntityValue(i) {
              return this.options.noValidation
                ? i
                : this.assertLegalChar("" + i || "");
            }
            dtdNData(i) {
              return this.options.noValidation
                ? i
                : this.assertLegalChar("" + i || "");
            }
            assertLegalChar(i) {
              var a, n;
              if (this.options.noValidation) return i;
              if (this.options.version === "1.0") {
                if (
                  ((a =
                    /[\0-\x08\x0B\f\x0E-\x1F\uFFFE\uFFFF]|[\uD800-\uDBFF](?![\uDC00-\uDFFF])|(?:[^\uD800-\uDBFF]|^)[\uDC00-\uDFFF]/g),
                  this.options.invalidCharReplacement !== void 0)
                )
                  i = i.replace(a, this.options.invalidCharReplacement);
                else if ((n = i.match(a)))
                  throw new Error(
                    `Invalid character in string: ${i} at index ${n.index}`,
                  );
              } else if (this.options.version === "1.1") {
                if (
                  ((a =
                    /[\0\uFFFE\uFFFF]|[\uD800-\uDBFF](?![\uDC00-\uDFFF])|(?:[^\uD800-\uDBFF]|^)[\uDC00-\uDFFF]/g),
                  this.options.invalidCharReplacement !== void 0)
                )
                  i = i.replace(a, this.options.invalidCharReplacement);
                else if ((n = i.match(a)))
                  throw new Error(
                    `Invalid character in string: ${i} at index ${n.index}`,
                  );
              }
              return i;
            }
            assertLegalName(i) {
              var a;
              if (this.options.noValidation) return i;
              if (
                ((i = this.assertLegalChar(i)),
                (a =
                  /^([:A-Z_a-z\xC0-\xD6\xD8-\xF6\xF8-\u02FF\u0370-\u037D\u037F-\u1FFF\u200C\u200D\u2070-\u218F\u2C00-\u2FEF\u3001-\uD7FF\uF900-\uFDCF\uFDF0-\uFFFD]|[\uD800-\uDB7F][\uDC00-\uDFFF])([\x2D\.0-:A-Z_a-z\xB7\xC0-\xD6\xD8-\xF6\xF8-\u037D\u037F-\u1FFF\u200C\u200D\u203F\u2040\u2070-\u218F\u2C00-\u2FEF\u3001-\uD7FF\uF900-\uFDCF\uFDF0-\uFFFD]|[\uD800-\uDB7F][\uDC00-\uDFFF])*$/),
                !i.match(a))
              )
                throw new Error(`Invalid character in name: ${i}`);
              return i;
            }
            textEscape(i) {
              var a;
              return this.options.noValidation
                ? i
                : ((a = this.options.noDoubleEncoding
                    ? /(?!&(lt|gt|amp|apos|quot);)&/g
                    : /&/g),
                  i
                    .replace(a, "&amp;")
                    .replace(/</g, "&lt;")
                    .replace(/>/g, "&gt;")
                    .replace(/\r/g, "&#xD;"));
            }
            attEscape(i) {
              var a;
              return this.options.noValidation
                ? i
                : ((a = this.options.noDoubleEncoding
                    ? /(?!&(lt|gt|amp|apos|quot);)&/g
                    : /&/g),
                  i
                    .replace(a, "&amp;")
                    .replace(/</g, "&lt;")
                    .replace(/"/g, "&quot;")
                    .replace(/\t/g, "&#x9;")
                    .replace(/\n/g, "&#xA;")
                    .replace(/\r/g, "&#xD;"));
            }
          }
          return (
            (t.prototype.convertAttKey = "@"),
            (t.prototype.convertPIKey = "?"),
            (t.prototype.convertTextKey = "#text"),
            (t.prototype.convertCDataKey = "#cdata"),
            (t.prototype.convertCommentKey = "#comment"),
            (t.prototype.convertRawKey = "#raw"),
            t
          );
        }.call(this);
      }.call(uA)),
    Ao.exports
  );
}
var bo = { exports: {} },
  Fo = { exports: {} },
  So = { exports: {} },
  lA = So.exports,
  Dh;
function Qo() {
  return (
    Dh ||
      ((Dh = 1),
      function () {
        So.exports = { None: 0, OpenTag: 1, InsideTag: 2, CloseTag: 3 };
      }.call(lA)),
    So.exports
  );
}
var cA = Fo.exports,
  mh;
function TD() {
  return (
    mh ||
      ((mh = 1),
      function () {
        var e,
          t,
          o,
          i = {}.hasOwnProperty;
        (({ assign: o } = Jt()),
          (e = Ye()),
          xu(),
          Ru(),
          _u(),
          Tu(),
          Su(),
          Lu(),
          Bu(),
          ku(),
          SD(),
          Nu(),
          Ou(),
          Iu(),
          Pu(),
          (t = Qo()),
          (Fo.exports = class {
            constructor(n) {
              var r, s, u;
              (n || (n = {}), (this.options = n), (s = n.writer || {}));
              for (r in s)
                i.call(s, r) &&
                  ((u = s[r]), (this["_" + r] = this[r]), (this[r] = u));
            }
            filterOptions(n) {
              var r, s, u, f, d, c, l, h, y;
              return (
                n || (n = {}),
                (n = o({}, this.options, n)),
                (r = { writer: this }),
                (r.pretty = n.pretty || !1),
                (r.allowEmpty = n.allowEmpty || !1),
                (r.indent = (s = n.indent) != null ? s : "  "),
                (r.newline =
                  (u = n.newline) != null
                    ? u
                    : `
`),
                (r.offset = (f = n.offset) != null ? f : 0),
                (r.width = (d = n.width) != null ? d : 0),
                (r.dontPrettyTextNodes =
                  (c =
                    (l = n.dontPrettyTextNodes) != null
                      ? l
                      : n.dontprettytextnodes) != null
                    ? c
                    : 0),
                (r.spaceBeforeSlash =
                  (h =
                    (y = n.spaceBeforeSlash) != null
                      ? y
                      : n.spacebeforeslash) != null
                    ? h
                    : ""),
                r.spaceBeforeSlash === !0 && (r.spaceBeforeSlash = " "),
                (r.suppressPrettyCount = 0),
                (r.user = {}),
                (r.state = t.None),
                r
              );
            }
            indent(n, r, s) {
              var u;
              return !r.pretty || r.suppressPrettyCount
                ? ""
                : r.pretty && ((u = (s || 0) + r.offset + 1), u > 0)
                  ? new Array(u).join(r.indent)
                  : "";
            }
            endline(n, r, s) {
              return !r.pretty || r.suppressPrettyCount ? "" : r.newline;
            }
            attribute(n, r, s) {
              var u;
              return (
                this.openAttribute(n, r, s),
                r.pretty && r.width > 0
                  ? (u = n.name + '="' + n.value + '"')
                  : (u = " " + n.name + '="' + n.value + '"'),
                this.closeAttribute(n, r, s),
                u
              );
            }
            cdata(n, r, s) {
              var u;
              return (
                this.openNode(n, r, s),
                (r.state = t.OpenTag),
                (u = this.indent(n, r, s) + "<![CDATA["),
                (r.state = t.InsideTag),
                (u += n.value),
                (r.state = t.CloseTag),
                (u += "]]>" + this.endline(n, r, s)),
                (r.state = t.None),
                this.closeNode(n, r, s),
                u
              );
            }
            comment(n, r, s) {
              var u;
              return (
                this.openNode(n, r, s),
                (r.state = t.OpenTag),
                (u = this.indent(n, r, s) + "<!-- "),
                (r.state = t.InsideTag),
                (u += n.value),
                (r.state = t.CloseTag),
                (u += " -->" + this.endline(n, r, s)),
                (r.state = t.None),
                this.closeNode(n, r, s),
                u
              );
            }
            declaration(n, r, s) {
              var u;
              return (
                this.openNode(n, r, s),
                (r.state = t.OpenTag),
                (u = this.indent(n, r, s) + "<?xml"),
                (r.state = t.InsideTag),
                (u += ' version="' + n.version + '"'),
                n.encoding != null && (u += ' encoding="' + n.encoding + '"'),
                n.standalone != null &&
                  (u += ' standalone="' + n.standalone + '"'),
                (r.state = t.CloseTag),
                (u += r.spaceBeforeSlash + "?>"),
                (u += this.endline(n, r, s)),
                (r.state = t.None),
                this.closeNode(n, r, s),
                u
              );
            }
            docType(n, r, s) {
              var u, f, d, c, l;
              if (
                (s || (s = 0),
                this.openNode(n, r, s),
                (r.state = t.OpenTag),
                (c = this.indent(n, r, s)),
                (c += "<!DOCTYPE " + n.root().name),
                n.pubID && n.sysID
                  ? (c += ' PUBLIC "' + n.pubID + '" "' + n.sysID + '"')
                  : n.sysID && (c += ' SYSTEM "' + n.sysID + '"'),
                n.children.length > 0)
              ) {
                for (
                  c += " [",
                    c += this.endline(n, r, s),
                    r.state = t.InsideTag,
                    l = n.children,
                    f = 0,
                    d = l.length;
                  f < d;
                  f++
                )
                  ((u = l[f]), (c += this.writeChildNode(u, r, s + 1)));
                ((r.state = t.CloseTag), (c += "]"));
              }
              return (
                (r.state = t.CloseTag),
                (c += r.spaceBeforeSlash + ">"),
                (c += this.endline(n, r, s)),
                (r.state = t.None),
                this.closeNode(n, r, s),
                c
              );
            }
            element(n, r, s) {
              var u, f, d, c, l, h, y, F, m, S, E, b, w, A, v, C, g, D, N;
              if (
                (s || (s = 0),
                (b = !1),
                this.openNode(n, r, s),
                (r.state = t.OpenTag),
                (w = this.indent(n, r, s) + "<" + n.name),
                r.pretty && r.width > 0)
              ) {
                ((F = w.length), (v = n.attribs));
                for (E in v)
                  i.call(v, E) &&
                    ((u = v[E]),
                    (A = this.attribute(u, r, s)),
                    (f = A.length),
                    F + f > r.width
                      ? ((N = this.indent(n, r, s + 1) + A),
                        (w += this.endline(n, r, s) + N),
                        (F = N.length))
                      : ((N = " " + A), (w += N), (F += N.length)));
              } else {
                C = n.attribs;
                for (E in C)
                  i.call(C, E) && ((u = C[E]), (w += this.attribute(u, r, s)));
              }
              if (
                ((c = n.children.length),
                (l = c === 0 ? null : n.children[0]),
                c === 0 ||
                  n.children.every(function (P) {
                    return (
                      (P.type === e.Text ||
                        P.type === e.Raw ||
                        P.type === e.CData) &&
                      P.value === ""
                    );
                  }))
              )
                r.allowEmpty
                  ? ((w += ">"),
                    (r.state = t.CloseTag),
                    (w += "</" + n.name + ">" + this.endline(n, r, s)))
                  : ((r.state = t.CloseTag),
                    (w += r.spaceBeforeSlash + "/>" + this.endline(n, r, s)));
              else if (
                r.pretty &&
                c === 1 &&
                (l.type === e.Text || l.type === e.Raw || l.type === e.CData) &&
                l.value != null
              )
                ((w += ">"),
                  (r.state = t.InsideTag),
                  r.suppressPrettyCount++,
                  (b = !0),
                  (w += this.writeChildNode(l, r, s + 1)),
                  r.suppressPrettyCount--,
                  (b = !1),
                  (r.state = t.CloseTag),
                  (w += "</" + n.name + ">" + this.endline(n, r, s)));
              else {
                if (r.dontPrettyTextNodes) {
                  for (g = n.children, h = 0, m = g.length; h < m; h++)
                    if (
                      ((d = g[h]),
                      (d.type === e.Text ||
                        d.type === e.Raw ||
                        d.type === e.CData) &&
                        d.value != null)
                    ) {
                      (r.suppressPrettyCount++, (b = !0));
                      break;
                    }
                }
                for (
                  w += ">" + this.endline(n, r, s),
                    r.state = t.InsideTag,
                    D = n.children,
                    y = 0,
                    S = D.length;
                  y < S;
                  y++
                )
                  ((d = D[y]), (w += this.writeChildNode(d, r, s + 1)));
                ((r.state = t.CloseTag),
                  (w += this.indent(n, r, s) + "</" + n.name + ">"),
                  b && r.suppressPrettyCount--,
                  (w += this.endline(n, r, s)),
                  (r.state = t.None));
              }
              return (this.closeNode(n, r, s), w);
            }
            writeChildNode(n, r, s) {
              switch (n.type) {
                case e.CData:
                  return this.cdata(n, r, s);
                case e.Comment:
                  return this.comment(n, r, s);
                case e.Element:
                  return this.element(n, r, s);
                case e.Raw:
                  return this.raw(n, r, s);
                case e.Text:
                  return this.text(n, r, s);
                case e.ProcessingInstruction:
                  return this.processingInstruction(n, r, s);
                case e.Dummy:
                  return "";
                case e.Declaration:
                  return this.declaration(n, r, s);
                case e.DocType:
                  return this.docType(n, r, s);
                case e.AttributeDeclaration:
                  return this.dtdAttList(n, r, s);
                case e.ElementDeclaration:
                  return this.dtdElement(n, r, s);
                case e.EntityDeclaration:
                  return this.dtdEntity(n, r, s);
                case e.NotationDeclaration:
                  return this.dtdNotation(n, r, s);
                default:
                  throw new Error(
                    "Unknown XML node type: " + n.constructor.name,
                  );
              }
            }
            processingInstruction(n, r, s) {
              var u;
              return (
                this.openNode(n, r, s),
                (r.state = t.OpenTag),
                (u = this.indent(n, r, s) + "<?"),
                (r.state = t.InsideTag),
                (u += n.target),
                n.value && (u += " " + n.value),
                (r.state = t.CloseTag),
                (u += r.spaceBeforeSlash + "?>"),
                (u += this.endline(n, r, s)),
                (r.state = t.None),
                this.closeNode(n, r, s),
                u
              );
            }
            raw(n, r, s) {
              var u;
              return (
                this.openNode(n, r, s),
                (r.state = t.OpenTag),
                (u = this.indent(n, r, s)),
                (r.state = t.InsideTag),
                (u += n.value),
                (r.state = t.CloseTag),
                (u += this.endline(n, r, s)),
                (r.state = t.None),
                this.closeNode(n, r, s),
                u
              );
            }
            text(n, r, s) {
              var u;
              return (
                this.openNode(n, r, s),
                (r.state = t.OpenTag),
                (u = this.indent(n, r, s)),
                (r.state = t.InsideTag),
                (u += n.value),
                (r.state = t.CloseTag),
                (u += this.endline(n, r, s)),
                (r.state = t.None),
                this.closeNode(n, r, s),
                u
              );
            }
            dtdAttList(n, r, s) {
              var u;
              return (
                this.openNode(n, r, s),
                (r.state = t.OpenTag),
                (u = this.indent(n, r, s) + "<!ATTLIST"),
                (r.state = t.InsideTag),
                (u +=
                  " " +
                  n.elementName +
                  " " +
                  n.attributeName +
                  " " +
                  n.attributeType),
                n.defaultValueType !== "#DEFAULT" &&
                  (u += " " + n.defaultValueType),
                n.defaultValue && (u += ' "' + n.defaultValue + '"'),
                (r.state = t.CloseTag),
                (u += r.spaceBeforeSlash + ">" + this.endline(n, r, s)),
                (r.state = t.None),
                this.closeNode(n, r, s),
                u
              );
            }
            dtdElement(n, r, s) {
              var u;
              return (
                this.openNode(n, r, s),
                (r.state = t.OpenTag),
                (u = this.indent(n, r, s) + "<!ELEMENT"),
                (r.state = t.InsideTag),
                (u += " " + n.name + " " + n.value),
                (r.state = t.CloseTag),
                (u += r.spaceBeforeSlash + ">" + this.endline(n, r, s)),
                (r.state = t.None),
                this.closeNode(n, r, s),
                u
              );
            }
            dtdEntity(n, r, s) {
              var u;
              return (
                this.openNode(n, r, s),
                (r.state = t.OpenTag),
                (u = this.indent(n, r, s) + "<!ENTITY"),
                (r.state = t.InsideTag),
                n.pe && (u += " %"),
                (u += " " + n.name),
                n.value
                  ? (u += ' "' + n.value + '"')
                  : (n.pubID && n.sysID
                      ? (u += ' PUBLIC "' + n.pubID + '" "' + n.sysID + '"')
                      : n.sysID && (u += ' SYSTEM "' + n.sysID + '"'),
                    n.nData && (u += " NDATA " + n.nData)),
                (r.state = t.CloseTag),
                (u += r.spaceBeforeSlash + ">" + this.endline(n, r, s)),
                (r.state = t.None),
                this.closeNode(n, r, s),
                u
              );
            }
            dtdNotation(n, r, s) {
              var u;
              return (
                this.openNode(n, r, s),
                (r.state = t.OpenTag),
                (u = this.indent(n, r, s) + "<!NOTATION"),
                (r.state = t.InsideTag),
                (u += " " + n.name),
                n.pubID && n.sysID
                  ? (u += ' PUBLIC "' + n.pubID + '" "' + n.sysID + '"')
                  : n.pubID
                    ? (u += ' PUBLIC "' + n.pubID + '"')
                    : n.sysID && (u += ' SYSTEM "' + n.sysID + '"'),
                (r.state = t.CloseTag),
                (u += r.spaceBeforeSlash + ">" + this.endline(n, r, s)),
                (r.state = t.None),
                this.closeNode(n, r, s),
                u
              );
            }
            openNode(n, r, s) {}
            closeNode(n, r, s) {}
            openAttribute(n, r, s) {}
            closeAttribute(n, r, s) {}
          }));
      }.call(cA)),
    Fo.exports
  );
}
var fA = bo.exports,
  gh;
function Mu() {
  return (
    gh ||
      ((gh = 1),
      function () {
        var e;
        ((e = TD()),
          (bo.exports = class extends e {
            constructor(o) {
              super(o);
            }
            document(o, i) {
              var a, n, r, s, u;
              for (
                i = this.filterOptions(i),
                  s = "",
                  u = o.children,
                  n = 0,
                  r = u.length;
                n < r;
                n++
              )
                ((a = u[n]), (s += this.writeChildNode(a, i, 0)));
              return (
                i.pretty &&
                  s.slice(-i.newline.length) === i.newline &&
                  (s = s.slice(0, -i.newline.length)),
                s
              );
            }
          }));
      }.call(fA)),
    bo.exports
  );
}
var dA = Qi.exports,
  wh;
function xD() {
  return (
    wh ||
      ((wh = 1),
      function () {
        var e, t, o, i, a, n, r;
        (({ isPlainObject: r } = Jt()),
          (o = bD()),
          (t = UC()),
          (i = Ft()),
          (e = Ye()),
          (n = _D()),
          (a = Mu()),
          (Qi.exports = function () {
            class s extends i {
              constructor(f) {
                (super(null),
                  (this.name = "#document"),
                  (this.type = e.Document),
                  (this.documentURI = null),
                  (this.domConfig = new t()),
                  f || (f = {}),
                  f.writer || (f.writer = new a()),
                  (this.options = f),
                  (this.stringify = new n(f)));
              }
              end(f) {
                var d;
                return (
                  (d = {}),
                  f
                    ? r(f) && ((d = f), (f = this.options.writer))
                    : (f = this.options.writer),
                  f.document(this, f.filterOptions(d))
                );
              }
              toString(f) {
                return this.options.writer.document(
                  this,
                  this.options.writer.filterOptions(f),
                );
              }
              createElement(f) {
                throw new Error(
                  "This DOM method is not implemented." + this.debugInfo(),
                );
              }
              createDocumentFragment() {
                throw new Error(
                  "This DOM method is not implemented." + this.debugInfo(),
                );
              }
              createTextNode(f) {
                throw new Error(
                  "This DOM method is not implemented." + this.debugInfo(),
                );
              }
              createComment(f) {
                throw new Error(
                  "This DOM method is not implemented." + this.debugInfo(),
                );
              }
              createCDATASection(f) {
                throw new Error(
                  "This DOM method is not implemented." + this.debugInfo(),
                );
              }
              createProcessingInstruction(f, d) {
                throw new Error(
                  "This DOM method is not implemented." + this.debugInfo(),
                );
              }
              createAttribute(f) {
                throw new Error(
                  "This DOM method is not implemented." + this.debugInfo(),
                );
              }
              createEntityReference(f) {
                throw new Error(
                  "This DOM method is not implemented." + this.debugInfo(),
                );
              }
              getElementsByTagName(f) {
                throw new Error(
                  "This DOM method is not implemented." + this.debugInfo(),
                );
              }
              importNode(f, d) {
                throw new Error(
                  "This DOM method is not implemented." + this.debugInfo(),
                );
              }
              createElementNS(f, d) {
                throw new Error(
                  "This DOM method is not implemented." + this.debugInfo(),
                );
              }
              createAttributeNS(f, d) {
                throw new Error(
                  "This DOM method is not implemented." + this.debugInfo(),
                );
              }
              getElementsByTagNameNS(f, d) {
                throw new Error(
                  "This DOM method is not implemented." + this.debugInfo(),
                );
              }
              getElementById(f) {
                throw new Error(
                  "This DOM method is not implemented." + this.debugInfo(),
                );
              }
              adoptNode(f) {
                throw new Error(
                  "This DOM method is not implemented." + this.debugInfo(),
                );
              }
              normalizeDocument() {
                throw new Error(
                  "This DOM method is not implemented." + this.debugInfo(),
                );
              }
              renameNode(f, d, c) {
                throw new Error(
                  "This DOM method is not implemented." + this.debugInfo(),
                );
              }
              getElementsByClassName(f) {
                throw new Error(
                  "This DOM method is not implemented." + this.debugInfo(),
                );
              }
              createEvent(f) {
                throw new Error(
                  "This DOM method is not implemented." + this.debugInfo(),
                );
              }
              createRange() {
                throw new Error(
                  "This DOM method is not implemented." + this.debugInfo(),
                );
              }
              createNodeIterator(f, d, c) {
                throw new Error(
                  "This DOM method is not implemented." + this.debugInfo(),
                );
              }
              createTreeWalker(f, d, c) {
                throw new Error(
                  "This DOM method is not implemented." + this.debugInfo(),
                );
              }
            }
            return (
              Object.defineProperty(s.prototype, "implementation", {
                value: new o(),
              }),
              Object.defineProperty(s.prototype, "doctype", {
                get: function () {
                  var u, f, d, c;
                  for (c = this.children, f = 0, d = c.length; f < d; f++)
                    if (((u = c[f]), u.type === e.DocType)) return u;
                  return null;
                },
              }),
              Object.defineProperty(s.prototype, "documentElement", {
                get: function () {
                  return this.rootObject || null;
                },
              }),
              Object.defineProperty(s.prototype, "inputEncoding", {
                get: function () {
                  return null;
                },
              }),
              Object.defineProperty(s.prototype, "strictErrorChecking", {
                get: function () {
                  return !1;
                },
              }),
              Object.defineProperty(s.prototype, "xmlEncoding", {
                get: function () {
                  return this.children.length !== 0 &&
                    this.children[0].type === e.Declaration
                    ? this.children[0].encoding
                    : null;
                },
              }),
              Object.defineProperty(s.prototype, "xmlStandalone", {
                get: function () {
                  return this.children.length !== 0 &&
                    this.children[0].type === e.Declaration
                    ? this.children[0].standalone === "yes"
                    : !1;
                },
              }),
              Object.defineProperty(s.prototype, "xmlVersion", {
                get: function () {
                  return this.children.length !== 0 &&
                    this.children[0].type === e.Declaration
                    ? this.children[0].version
                    : "1.0";
                },
              }),
              Object.defineProperty(s.prototype, "URL", {
                get: function () {
                  return this.documentURI;
                },
              }),
              Object.defineProperty(s.prototype, "origin", {
                get: function () {
                  return null;
                },
              }),
              Object.defineProperty(s.prototype, "compatMode", {
                get: function () {
                  return null;
                },
              }),
              Object.defineProperty(s.prototype, "characterSet", {
                get: function () {
                  return null;
                },
              }),
              Object.defineProperty(s.prototype, "contentType", {
                get: function () {
                  return null;
                },
              }),
              s
            );
          }.call(this)));
      }.call(dA)),
    Qi.exports
  );
}
var _o = { exports: {} },
  hA = _o.exports,
  yh;
function pA() {
  return (
    yh ||
      ((yh = 1),
      function () {
        var e,
          t,
          o,
          i,
          a,
          n,
          r,
          s,
          u,
          f,
          d,
          c,
          l,
          h,
          y,
          F,
          m,
          S,
          E,
          b,
          w,
          A,
          v = {}.hasOwnProperty;
        (({ isObject: w, isFunction: b, isPlainObject: A, getValue: E } = Jt()),
          (e = Ye()),
          (c = xD()),
          (l = Su()),
          (i = _u()),
          (a = Tu()),
          (y = Lu()),
          (S = Bu()),
          (h = ku()),
          (f = xu()),
          (d = Ru()),
          (n = Nu()),
          (s = Iu()),
          (r = Ou()),
          (u = Pu()),
          (o = FD()),
          (m = _D()),
          (F = Mu()),
          (t = Qo()),
          (_o.exports = class {
            constructor(g, D, N) {
              var P;
              ((this.name = "?xml"),
                (this.type = e.Document),
                g || (g = {}),
                (P = {}),
                g.writer
                  ? A(g.writer) && ((P = g.writer), (g.writer = new F()))
                  : (g.writer = new F()),
                (this.options = g),
                (this.writer = g.writer),
                (this.writerOptions = this.writer.filterOptions(P)),
                (this.stringify = new m(g)),
                (this.onDataCallback = D || function () {}),
                (this.onEndCallback = N || function () {}),
                (this.currentNode = null),
                (this.currentLevel = -1),
                (this.openTags = {}),
                (this.documentStarted = !1),
                (this.documentCompleted = !1),
                (this.root = null));
            }
            createChildNode(g) {
              var D, N, P, R, k, q, U, $;
              switch (g.type) {
                case e.CData:
                  this.cdata(g.value);
                  break;
                case e.Comment:
                  this.comment(g.value);
                  break;
                case e.Element:
                  ((P = {}), (U = g.attribs));
                  for (N in U) v.call(U, N) && ((D = U[N]), (P[N] = D.value));
                  this.node(g.name, P);
                  break;
                case e.Dummy:
                  this.dummy();
                  break;
                case e.Raw:
                  this.raw(g.value);
                  break;
                case e.Text:
                  this.text(g.value);
                  break;
                case e.ProcessingInstruction:
                  this.instruction(g.target, g.value);
                  break;
                default:
                  throw new Error(
                    "This XML node type is not supported in a JS object: " +
                      g.constructor.name,
                  );
              }
              for ($ = g.children, k = 0, q = $.length; k < q; k++)
                ((R = $[k]),
                  this.createChildNode(R),
                  R.type === e.Element && this.up());
              return this;
            }
            dummy() {
              return this;
            }
            node(g, D, N) {
              if (g == null) throw new Error("Missing node name.");
              if (this.root && this.currentLevel === -1)
                throw new Error(
                  "Document can only have one root node. " + this.debugInfo(g),
                );
              return (
                this.openCurrent(),
                (g = E(g)),
                D == null && (D = {}),
                (D = E(D)),
                w(D) || ([N, D] = [D, N]),
                (this.currentNode = new l(this, g, D)),
                (this.currentNode.children = !1),
                this.currentLevel++,
                (this.openTags[this.currentLevel] = this.currentNode),
                N != null && this.text(N),
                this
              );
            }
            element(g, D, N) {
              var P, R, k, q, U, $;
              if (this.currentNode && this.currentNode.type === e.DocType)
                this.dtdElement(...arguments);
              else if (Array.isArray(g) || w(g) || b(g))
                for (
                  q = this.options.noValidation,
                    this.options.noValidation = !0,
                    $ = new c(this.options).element("TEMP_ROOT"),
                    $.element(g),
                    this.options.noValidation = q,
                    U = $.children,
                    R = 0,
                    k = U.length;
                  R < k;
                  R++
                )
                  ((P = U[R]),
                    this.createChildNode(P),
                    P.type === e.Element && this.up());
              else this.node(g, D, N);
              return this;
            }
            attribute(g, D) {
              var N, P;
              if (!this.currentNode || this.currentNode.children)
                throw new Error(
                  "att() can only be used immediately after an ele() call in callback mode. " +
                    this.debugInfo(g),
                );
              if ((g != null && (g = E(g)), w(g)))
                for (N in g) v.call(g, N) && ((P = g[N]), this.attribute(N, P));
              else
                (b(D) && (D = D.apply()),
                  this.options.keepNullAttributes && D == null
                    ? (this.currentNode.attribs[g] = new o(this, g, ""))
                    : D != null &&
                      (this.currentNode.attribs[g] = new o(this, g, D)));
              return this;
            }
            text(g) {
              var D;
              return (
                this.openCurrent(),
                (D = new S(this, g)),
                this.onData(
                  this.writer.text(
                    D,
                    this.writerOptions,
                    this.currentLevel + 1,
                  ),
                  this.currentLevel + 1,
                ),
                this
              );
            }
            cdata(g) {
              var D;
              return (
                this.openCurrent(),
                (D = new i(this, g)),
                this.onData(
                  this.writer.cdata(
                    D,
                    this.writerOptions,
                    this.currentLevel + 1,
                  ),
                  this.currentLevel + 1,
                ),
                this
              );
            }
            comment(g) {
              var D;
              return (
                this.openCurrent(),
                (D = new a(this, g)),
                this.onData(
                  this.writer.comment(
                    D,
                    this.writerOptions,
                    this.currentLevel + 1,
                  ),
                  this.currentLevel + 1,
                ),
                this
              );
            }
            raw(g) {
              var D;
              return (
                this.openCurrent(),
                (D = new y(this, g)),
                this.onData(
                  this.writer.raw(D, this.writerOptions, this.currentLevel + 1),
                  this.currentLevel + 1,
                ),
                this
              );
            }
            instruction(g, D) {
              var N, P, R, k, q;
              if (
                (this.openCurrent(),
                g != null && (g = E(g)),
                D != null && (D = E(D)),
                Array.isArray(g))
              )
                for (N = 0, k = g.length; N < k; N++)
                  ((P = g[N]), this.instruction(P));
              else if (w(g))
                for (P in g)
                  v.call(g, P) && ((R = g[P]), this.instruction(P, R));
              else
                (b(D) && (D = D.apply()),
                  (q = new h(this, g, D)),
                  this.onData(
                    this.writer.processingInstruction(
                      q,
                      this.writerOptions,
                      this.currentLevel + 1,
                    ),
                    this.currentLevel + 1,
                  ));
              return this;
            }
            declaration(g, D, N) {
              var P;
              if ((this.openCurrent(), this.documentStarted))
                throw new Error("declaration() must be the first node.");
              return (
                (P = new f(this, g, D, N)),
                this.onData(
                  this.writer.declaration(
                    P,
                    this.writerOptions,
                    this.currentLevel + 1,
                  ),
                  this.currentLevel + 1,
                ),
                this
              );
            }
            doctype(g, D, N) {
              if ((this.openCurrent(), g == null))
                throw new Error("Missing root node name.");
              if (this.root)
                throw new Error("dtd() must come before the root node.");
              return (
                (this.currentNode = new d(this, D, N)),
                (this.currentNode.rootNodeName = g),
                (this.currentNode.children = !1),
                this.currentLevel++,
                (this.openTags[this.currentLevel] = this.currentNode),
                this
              );
            }
            dtdElement(g, D) {
              var N;
              return (
                this.openCurrent(),
                (N = new r(this, g, D)),
                this.onData(
                  this.writer.dtdElement(
                    N,
                    this.writerOptions,
                    this.currentLevel + 1,
                  ),
                  this.currentLevel + 1,
                ),
                this
              );
            }
            attList(g, D, N, P, R) {
              var k;
              return (
                this.openCurrent(),
                (k = new n(this, g, D, N, P, R)),
                this.onData(
                  this.writer.dtdAttList(
                    k,
                    this.writerOptions,
                    this.currentLevel + 1,
                  ),
                  this.currentLevel + 1,
                ),
                this
              );
            }
            entity(g, D) {
              var N;
              return (
                this.openCurrent(),
                (N = new s(this, !1, g, D)),
                this.onData(
                  this.writer.dtdEntity(
                    N,
                    this.writerOptions,
                    this.currentLevel + 1,
                  ),
                  this.currentLevel + 1,
                ),
                this
              );
            }
            pEntity(g, D) {
              var N;
              return (
                this.openCurrent(),
                (N = new s(this, !0, g, D)),
                this.onData(
                  this.writer.dtdEntity(
                    N,
                    this.writerOptions,
                    this.currentLevel + 1,
                  ),
                  this.currentLevel + 1,
                ),
                this
              );
            }
            notation(g, D) {
              var N;
              return (
                this.openCurrent(),
                (N = new u(this, g, D)),
                this.onData(
                  this.writer.dtdNotation(
                    N,
                    this.writerOptions,
                    this.currentLevel + 1,
                  ),
                  this.currentLevel + 1,
                ),
                this
              );
            }
            up() {
              if (this.currentLevel < 0)
                throw new Error("The document node has no parent.");
              return (
                this.currentNode
                  ? (this.currentNode.children
                      ? this.closeNode(this.currentNode)
                      : this.openNode(this.currentNode),
                    (this.currentNode = null))
                  : this.closeNode(this.openTags[this.currentLevel]),
                delete this.openTags[this.currentLevel],
                this.currentLevel--,
                this
              );
            }
            end() {
              for (; this.currentLevel >= 0;) this.up();
              return this.onEnd();
            }
            openCurrent() {
              if (this.currentNode)
                return (
                  (this.currentNode.children = !0),
                  this.openNode(this.currentNode)
                );
            }
            openNode(g) {
              var D, N, P, R;
              if (!g.isOpen) {
                if (
                  (!this.root &&
                    this.currentLevel === 0 &&
                    g.type === e.Element &&
                    (this.root = g),
                  (N = ""),
                  g.type === e.Element)
                ) {
                  ((this.writerOptions.state = t.OpenTag),
                    (N =
                      this.writer.indent(
                        g,
                        this.writerOptions,
                        this.currentLevel,
                      ) +
                      "<" +
                      g.name),
                    (R = g.attribs));
                  for (P in R)
                    v.call(R, P) &&
                      ((D = R[P]),
                      (N += this.writer.attribute(
                        D,
                        this.writerOptions,
                        this.currentLevel,
                      )));
                  ((N +=
                    (g.children ? ">" : "/>") +
                    this.writer.endline(
                      g,
                      this.writerOptions,
                      this.currentLevel,
                    )),
                    (this.writerOptions.state = t.InsideTag));
                } else
                  ((this.writerOptions.state = t.OpenTag),
                    (N =
                      this.writer.indent(
                        g,
                        this.writerOptions,
                        this.currentLevel,
                      ) +
                      "<!DOCTYPE " +
                      g.rootNodeName),
                    g.pubID && g.sysID
                      ? (N += ' PUBLIC "' + g.pubID + '" "' + g.sysID + '"')
                      : g.sysID && (N += ' SYSTEM "' + g.sysID + '"'),
                    g.children
                      ? ((N += " ["), (this.writerOptions.state = t.InsideTag))
                      : ((this.writerOptions.state = t.CloseTag), (N += ">")),
                    (N += this.writer.endline(
                      g,
                      this.writerOptions,
                      this.currentLevel,
                    )));
                return (this.onData(N, this.currentLevel), (g.isOpen = !0));
              }
            }
            closeNode(g) {
              var D;
              if (!g.isClosed)
                return (
                  (D = ""),
                  (this.writerOptions.state = t.CloseTag),
                  g.type === e.Element
                    ? (D =
                        this.writer.indent(
                          g,
                          this.writerOptions,
                          this.currentLevel,
                        ) +
                        "</" +
                        g.name +
                        ">" +
                        this.writer.endline(
                          g,
                          this.writerOptions,
                          this.currentLevel,
                        ))
                    : (D =
                        this.writer.indent(
                          g,
                          this.writerOptions,
                          this.currentLevel,
                        ) +
                        "]>" +
                        this.writer.endline(
                          g,
                          this.writerOptions,
                          this.currentLevel,
                        )),
                  (this.writerOptions.state = t.None),
                  this.onData(D, this.currentLevel),
                  (g.isClosed = !0)
                );
            }
            onData(g, D) {
              return (
                (this.documentStarted = !0),
                this.onDataCallback(g, D + 1)
              );
            }
            onEnd() {
              return ((this.documentCompleted = !0), this.onEndCallback());
            }
            debugInfo(g) {
              return g == null ? "" : "node: <" + g + ">";
            }
            ele() {
              return this.element(...arguments);
            }
            nod(g, D, N) {
              return this.node(g, D, N);
            }
            txt(g) {
              return this.text(g);
            }
            dat(g) {
              return this.cdata(g);
            }
            com(g) {
              return this.comment(g);
            }
            ins(g, D) {
              return this.instruction(g, D);
            }
            dec(g, D, N) {
              return this.declaration(g, D, N);
            }
            dtd(g, D, N) {
              return this.doctype(g, D, N);
            }
            e(g, D, N) {
              return this.element(g, D, N);
            }
            n(g, D, N) {
              return this.node(g, D, N);
            }
            t(g) {
              return this.text(g);
            }
            d(g) {
              return this.cdata(g);
            }
            c(g) {
              return this.comment(g);
            }
            r(g) {
              return this.raw(g);
            }
            i(g, D) {
              return this.instruction(g, D);
            }
            att() {
              return this.currentNode && this.currentNode.type === e.DocType
                ? this.attList(...arguments)
                : this.attribute(...arguments);
            }
            a() {
              return this.currentNode && this.currentNode.type === e.DocType
                ? this.attList(...arguments)
                : this.attribute(...arguments);
            }
            ent(g, D) {
              return this.entity(g, D);
            }
            pent(g, D) {
              return this.pEntity(g, D);
            }
            not(g, D) {
              return this.notation(g, D);
            }
          }));
      }.call(hA)),
    _o.exports
  );
}
var To = { exports: {} },
  DA = To.exports,
  Eh;
function mA() {
  return (
    Eh ||
      ((Eh = 1),
      function () {
        var e,
          t,
          o,
          i = {}.hasOwnProperty;
        ((e = Ye()),
          (o = TD()),
          (t = Qo()),
          (To.exports = class extends o {
            constructor(n, r) {
              (super(r), (this.stream = n));
            }
            endline(n, r, s) {
              return n.isLastRootNode && r.state === t.CloseTag
                ? ""
                : super.endline(n, r, s);
            }
            document(n, r) {
              var s, u, f, d, c, l, h, y, F;
              for (h = n.children, u = f = 0, c = h.length; f < c; u = ++f)
                ((s = h[u]), (s.isLastRootNode = u === n.children.length - 1));
              for (
                r = this.filterOptions(r),
                  y = n.children,
                  F = [],
                  d = 0,
                  l = y.length;
                d < l;
                d++
              )
                ((s = y[d]), F.push(this.writeChildNode(s, r, 0)));
              return F;
            }
            cdata(n, r, s) {
              return this.stream.write(super.cdata(n, r, s));
            }
            comment(n, r, s) {
              return this.stream.write(super.comment(n, r, s));
            }
            declaration(n, r, s) {
              return this.stream.write(super.declaration(n, r, s));
            }
            docType(n, r, s) {
              var u, f, d, c;
              if (
                (s || (s = 0),
                this.openNode(n, r, s),
                (r.state = t.OpenTag),
                this.stream.write(this.indent(n, r, s)),
                this.stream.write("<!DOCTYPE " + n.root().name),
                n.pubID && n.sysID
                  ? this.stream.write(
                      ' PUBLIC "' + n.pubID + '" "' + n.sysID + '"',
                    )
                  : n.sysID && this.stream.write(' SYSTEM "' + n.sysID + '"'),
                n.children.length > 0)
              ) {
                for (
                  this.stream.write(" ["),
                    this.stream.write(this.endline(n, r, s)),
                    r.state = t.InsideTag,
                    c = n.children,
                    f = 0,
                    d = c.length;
                  f < d;
                  f++
                )
                  ((u = c[f]), this.writeChildNode(u, r, s + 1));
                ((r.state = t.CloseTag), this.stream.write("]"));
              }
              return (
                (r.state = t.CloseTag),
                this.stream.write(r.spaceBeforeSlash + ">"),
                this.stream.write(this.endline(n, r, s)),
                (r.state = t.None),
                this.closeNode(n, r, s)
              );
            }
            element(n, r, s) {
              var u, f, d, c, l, h, y, F, m, S, E, b, w, A, v;
              if (
                (s || (s = 0),
                this.openNode(n, r, s),
                (r.state = t.OpenTag),
                (S = this.indent(n, r, s) + "<" + n.name),
                r.pretty && r.width > 0)
              ) {
                ((y = S.length), (b = n.attribs));
                for (m in b)
                  i.call(b, m) &&
                    ((u = b[m]),
                    (E = this.attribute(u, r, s)),
                    (f = E.length),
                    y + f > r.width
                      ? ((v = this.indent(n, r, s + 1) + E),
                        (S += this.endline(n, r, s) + v),
                        (y = v.length))
                      : ((v = " " + E), (S += v), (y += v.length)));
              } else {
                w = n.attribs;
                for (m in w)
                  i.call(w, m) && ((u = w[m]), (S += this.attribute(u, r, s)));
              }
              if (
                (this.stream.write(S),
                (c = n.children.length),
                (l = c === 0 ? null : n.children[0]),
                c === 0 ||
                  n.children.every(function (C) {
                    return (
                      (C.type === e.Text ||
                        C.type === e.Raw ||
                        C.type === e.CData) &&
                      C.value === ""
                    );
                  }))
              )
                r.allowEmpty
                  ? (this.stream.write(">"),
                    (r.state = t.CloseTag),
                    this.stream.write("</" + n.name + ">"))
                  : ((r.state = t.CloseTag),
                    this.stream.write(r.spaceBeforeSlash + "/>"));
              else if (
                r.pretty &&
                c === 1 &&
                (l.type === e.Text || l.type === e.Raw || l.type === e.CData) &&
                l.value != null
              )
                (this.stream.write(">"),
                  (r.state = t.InsideTag),
                  r.suppressPrettyCount++,
                  this.writeChildNode(l, r, s + 1),
                  r.suppressPrettyCount--,
                  (r.state = t.CloseTag),
                  this.stream.write("</" + n.name + ">"));
              else {
                for (
                  this.stream.write(">" + this.endline(n, r, s)),
                    r.state = t.InsideTag,
                    A = n.children,
                    h = 0,
                    F = A.length;
                  h < F;
                  h++
                )
                  ((d = A[h]), this.writeChildNode(d, r, s + 1));
                ((r.state = t.CloseTag),
                  this.stream.write(
                    this.indent(n, r, s) + "</" + n.name + ">",
                  ));
              }
              return (
                this.stream.write(this.endline(n, r, s)),
                (r.state = t.None),
                this.closeNode(n, r, s)
              );
            }
            processingInstruction(n, r, s) {
              return this.stream.write(super.processingInstruction(n, r, s));
            }
            raw(n, r, s) {
              return this.stream.write(super.raw(n, r, s));
            }
            text(n, r, s) {
              return this.stream.write(super.text(n, r, s));
            }
            dtdAttList(n, r, s) {
              return this.stream.write(super.dtdAttList(n, r, s));
            }
            dtdElement(n, r, s) {
              return this.stream.write(super.dtdElement(n, r, s));
            }
            dtdEntity(n, r, s) {
              return this.stream.write(super.dtdEntity(n, r, s));
            }
            dtdNotation(n, r, s) {
              return this.stream.write(super.dtdNotation(n, r, s));
            }
          }));
      }.call(DA)),
    To.exports
  );
}
var vh;
function gA() {
  return (
    vh ||
      ((vh = 1),
      function () {
        var e, t, o, i, a, n, r, s, u;
        (({ assign: s, isFunction: u } = Jt()),
          (o = bD()),
          (i = xD()),
          (a = pA()),
          (r = Mu()),
          (n = mA()),
          (e = Ye()),
          (t = Qo()),
          (Rt.create = function (f, d, c, l) {
            var h, y;
            if (f == null) throw new Error("Root element needs a name.");
            return (
              (l = s({}, d, c, l)),
              (h = new i(l)),
              (y = h.element(f)),
              l.headless ||
                (h.declaration(l),
                (l.pubID != null || l.sysID != null) && h.dtd(l)),
              y
            );
          }),
          (Rt.begin = function (f, d, c) {
            return (
              u(f) && (([d, c] = [f, d]), (f = {})),
              d ? new a(f, d, c) : new i(f)
            );
          }),
          (Rt.stringWriter = function (f) {
            return new r(f);
          }),
          (Rt.streamWriter = function (f, d) {
            return new n(f, d);
          }),
          (Rt.implementation = new o()),
          (Rt.nodeType = e),
          (Rt.writerState = t));
      }.call(Rt)),
    Rt
  );
}
var Ch;
function wA() {
  if (Ch) return Os;
  Ch = 1;
  var e = OC(),
    t = gA();
  Os.build = n;
  function o(s) {
    function u(f) {
      return f < 10 ? "0" + f : f;
    }
    return (
      s.getUTCFullYear() +
      "-" +
      u(s.getUTCMonth() + 1) +
      "-" +
      u(s.getUTCDate()) +
      "T" +
      u(s.getUTCHours()) +
      ":" +
      u(s.getUTCMinutes()) +
      ":" +
      u(s.getUTCSeconds()) +
      "Z"
    );
  }
  var i = Object.prototype.toString;
  function a(s) {
    var u = i.call(s).match(/\[object (.*)\]/);
    return u && u[1];
  }
  function n(s, u) {
    var f = { version: "1.0", encoding: "UTF-8" },
      d = {
        pubid: "-//Apple//DTD PLIST 1.0//EN",
        sysid: "http://www.apple.com/DTDs/PropertyList-1.0.dtd",
      },
      c = t.create("plist");
    return (
      c.dec(f.version, f.encoding, f.standalone),
      c.dtd(d.pubid, d.sysid),
      c.att("version", "1.0"),
      r(s, c),
      u || (u = {}),
      (u.pretty = u.pretty !== !1),
      c.end(u)
    );
  }
  function r(s, u) {
    var f,
      d,
      c,
      l = a(s);
    if (l != "Undefined")
      if (Array.isArray(s))
        for (u = u.ele("array"), d = 0; d < s.length; d++) r(s[d], u);
      else if (Buffer.isBuffer(s)) u.ele("data").raw(s.toString("base64"));
      else if (l == "Object") {
        u = u.ele("dict");
        for (c in s) s.hasOwnProperty(c) && (u.ele("key").txt(c), r(s[c], u));
      } else
        l == "Number"
          ? ((f = s % 1 === 0 ? "integer" : "real"), u.ele(f).txt(s.toString()))
          : l == "BigInt"
            ? u.ele("integer").txt(s)
            : l == "Date"
              ? u.ele("date").txt(o(new Date(s)))
              : l == "Boolean"
                ? u.ele(s ? "true" : "false")
                : l == "String"
                  ? u.ele("string").txt(s)
                  : l == "ArrayBuffer"
                    ? u.ele("data").raw(e.fromByteArray(s))
                    : s && s.buffer && a(s.buffer) == "ArrayBuffer"
                      ? u
                          .ele("data")
                          .raw(e.fromByteArray(new Uint8Array(s.buffer), u))
                      : l === "Null" && u.ele("null").txt("");
  }
  return Os;
}
var Ah;
function yA() {
  return (
    Ah ||
      ((Ah = 1),
      (function (e) {
        var t = IC();
        Object.keys(t).forEach(function (i) {
          e[i] = t[i];
        });
        var o = wA();
        Object.keys(o).forEach(function (i) {
          e[i] = o[i];
        });
      })(xs)),
    xs
  );
}
var EA = yA();
const vA = pr(EA),
  xo = Mo($h),
  CA = {
    whatsapp: {
      paths: ["/Applications/WhatsApp.app"],
      bundleIds: ["net.whatsapp.WhatsApp"],
    },
    tg: {
      paths: [
        "/Applications/Telegram.app",
        "/Applications/Telegram Desktop.app",
      ],
      bundleIds: ["com.tdesktop.Telegram", "ru.keepcoder.Telegram"],
    },
    sgnl: {
      paths: ["/Applications/Signal.app"],
      bundleIds: ["org.whispersystems.signal-desktop"],
    },
    mesh: {
      paths: ["/Applications/Mesh.app", "/Applications/Clay.app"],
      bundleIds: ["com.clay.mac"],
    },
  };
function AA(e) {
  const t = /REG_SZ\s+(.+)/.exec(e);
  if (!t) return;
  const o = t[1].trim();
  if (o.startsWith('"')) {
    const i = o.indexOf('"', 1);
    return i === -1 ? void 0 : o.substring(1, i);
  }
  return o.split(" ")[0];
}
async function bA(e) {
  const { stdout: t } = await xo(
    "defaults export com.apple.LaunchServices/com.apple.launchservices.secure - | plutil -convert xml1 - -o -",
  );
  return vA
    .parse(t)
    .LSHandlers.find(
      (n) => n.LSHandlerURLScheme?.toLowerCase() === e.toLowerCase(),
    )?.LSHandlerRoleAll;
}
async function FA(e) {
  if (!/^[a-zA-Z0-9\-.]+$/.test(e))
    return (logger.error(`Invalid protocol format: ${e}`), !1);
  try {
    if (Kt) {
      const { stdout: t } = await xo(
          `reg query "HKCR\\${e}\\shell\\open\\command" /ve`,
        ),
        o = AA(t);
      if (!o) return !1;
      try {
        return (await wg(o), !0);
      } catch {
        return (
          logger.error(
            `Protocol handler registered for ${e} but executable not found: ${o}`,
          ),
          !1
        );
      }
    }
    if (Ne) {
      const t = CA[e];
      if (t) {
        for (const a of t.paths) if (Ag(a)) return !0;
      }
      if (t)
        for (const a of t.bundleIds)
          try {
            const { stdout: n } = await xo(
              `mdfind "kMDItemCFBundleIdentifier == '${a}'"`,
            );
            if (n.trim().length > 0) return !0;
          } catch {}
      const o = await bA(e);
      if (!o) return !1;
      const { stdout: i } = await xo(
        `mdfind "kMDItemCFBundleIdentifier == '${o}'"`,
      );
      return i.trim().length > 0;
    }
  } catch (t) {
    logger.error(`isProtocolHandlerRegistered(${e}) error: ${t.message}`);
  }
  return !1;
}
const SA = 512,
  _A = 60,
  TA = new Set([
    "image/jpeg",
    "image/png",
    "image/gif",
    "image/webp",
    "image/avif",
    "image/bmp",
  ]);
async function Ps(e, t, o) {
  return (await e).default[t](...o);
}
Re && new Re.AudioTranscriber();
const Hi = Re ? new Re.ContactsManager() : void 0,
  Gi = Re ? new Re.CalendarManager() : void 0,
  Vi = Re?.FoundationModelsManager ? new Re.FoundationModelsManager() : void 0,
  ND = {
    callNMP: (e, t) =>
      Ps(
        import("./index-C21G-mNi.mjs").then((o) => o.i),
        e,
        t,
      ),
    callNMC: (e, t = []) =>
      Ps(
        import("./index-8JaOpgio.mjs").then((o) => o.i),
        e,
        t,
      ),
    nmcAddNewContact: (e) =>
      Ps(
        import("./index-8JaOpgio.mjs").then((t) => t.i),
        "addNewContact",
        [e],
      ),
    openContact: async (e) => {
      if (!Ne) {
        logger.warn("openContact is only supported on macOS");
        return;
      }
      try {
        await Dt.openExternal(`addressbook://${encodeURIComponent(e)}`);
      } catch (t) {
        logger.error("Failed to open contact:", t);
      }
    },
    async getBrowserLoginCredentials(e) {
      try {
        return (
          await import("credential-extractor")
        )?.default?.browserLoginCredentials(e);
      } catch {
        return [];
      }
    },
    async decryptBrowserPassword(e) {
      try {
        return (
          await import("credential-extractor")
        )?.default?.browserDecryptCredential(e);
      } catch {
        return null;
      }
    },
    scanBrowserSessionImports: lC,
    getBrowserSessionImportAvailability: Bv,
    getBrowserSessionImportFields: cC,
    resolveBrowserSessionImportUserDisplayText: fC,
    isBrowserSessionImportBrowserRunning: Yt,
    quitBrowserSessionImportBrowser: Pv,
    requestSafariCookieAccess: Ov,
    deleteBrowserSessionImportCookies: dC,
    clearBrowserSessionImportCache: DC,
    getArgv: () => process.argv,
    callAppAPI: Rh,
    fetchAllContacts: Ug,
    transcodeImage: async (e, t, o) => {
      const i = { outputPath: t, mimeType: `image/${o}` };
      if (!(await Io(e)))
        return {
          ...i,
          error: new Error(`Missing or empty image cannot be transcoded: ${e}`),
        };
      try {
        const { default: n } = await import("./utils-D8MokWSu.mjs").then(
            (u) => u.i,
          ),
          r = (await n.fromFile(e))?.mime;
        if (r && SC.has(r)) {
          if (Ne) {
            await Ie("/usr/bin/sips", ["-s", "format", o, e, "--out", t]);
            const { width: d, height: c } = await tg(e, t);
            return { ...i, height: c, width: d };
          }
          const { width: u, height: f } = await FC(e, t, o);
          return { ...i, height: f, width: u };
        }
        if (r && TA.has(r)) return { outputPath: e, mimeType: r };
        const s = await el(e).rotate()[o]().toFile(t);
        return { ...i, height: s.height, width: s.width };
      } catch (n) {
        return {
          ...i,
          error: new Error(
            "Failed to convert image: " +
              (n instanceof Error ? n.message : String(n)),
          ),
        };
      }
    },
    resizeImage: async (e, t, o) => {
      try {
        const i = o?.maxDimension ?? SA,
          a = o?.quality ?? _A;
        let n = el(e)
          .rotate()
          .resize({
            width: i,
            height: i,
            fit: "inside",
            withoutEnlargement: !0,
          });
        switch (t) {
          case "png":
            n = n.png();
            break;
          case "webp":
            n = n.webp({ quality: a, alphaQuality: a });
            break;
          default:
            n = n.jpeg({ quality: a });
            break;
        }
        const r = await n.toBuffer(),
          s = `image/${t}`;
        return { buffer: r, mimeType: s };
      } catch (i) {
        return (logger.error("Failed to resize image", i), null);
      }
    },
    async requiresDimensionInversion(e) {
      try {
        const { default: t } = await import("./exif-reader-Cjo5XPQp.mjs"),
          o =
            e instanceof Buffer
              ? await t.load(e, { async: !0 })
              : await t.load(e),
          { Orientation: i } = o ?? {};
        return i?.value === 6 || i?.value === 8;
      } catch (t) {
        return (logger.error("requiresDimensionInversion has failed", t), !1);
      }
    },
    afconvert: (e, t) =>
      Ie("/usr/bin/afconvert", ["-f", "mp4f", "-d", "aac", e, t]),
    afplay: (e) => Ie("/usr/bin/afplay", [e]),
    opusdec: (e, t) => Ie(G.join(Uo, "opusdec" + (Kt ? ".exe" : "")), [e, t]),
    async uninstallHelperTool() {
      const e = "com.automattic.beeper.pht",
        t = await Kh(
          `launchctl remove ${e}; rm -f /Library/PrivilegedHelperTools/${e} /Library/LaunchDaemons/${e}.plist`,
          { name: tt.APP_NAME, icns: ru },
        );
      logger.log(t);
    },
    unusedFileName: async (e) =>
      (await import("./index-DK5IumEI.mjs").then((t) => t.i)).default(e),
    async restartMacOSNotifCenter() {
      await Ie("/usr/bin/killall", ["NotificationCenter"]);
    },
    async queryMacSystemProfiler() {
      return await eg();
    },
    editContact: Hi?.editContact.bind(Hi) || (() => null),
    getMeContactID: Hi?.getMeContactID.bind(Hi) || (() => null),
    getEvents: Gi?.getEventsBetween.bind(Gi) || (() => null),
    addEvent: Gi?.addEvent.bind(Gi) || (() => null),
    isFoundationModelsAvailable: Vi?.isAvailable.bind(Vi) || (() => !1),
    generateTextWithFoundationModels: Vi?.generateText.bind(Vi) || (() => null),
    getRecoveryCode: process.env.DONT_USE_KEYCHAIN
      ? () => ({ recoveryCode: void 0 })
      : Ur.get.bind(Ur),
    setRecoveryCode: Ur.set.bind(Ur),
    removeRecoveryCode: Ur.remove.bind(Ur),
    moveTrafficLights: (e, t, o, i) => {
      (i ? ft.get(i) : mainWindow)?.moveTrafficLights?.(e, t, o);
    },
    resetMainWSK: () => {
      mainWindow?.resetMainWSK?.();
    },
    isAppInDock: Re?.isAppInDock?.bind(Re),
    removeAppFromDock: Re?.removeAppFromDock?.bind(Re),
    isLockdownModeEnabled: () => Re?.isLockdownModeEnabled?.() ?? !1,
    relaunchDock: C0,
    preferredScrollerStyle: () => Re?.preferredScrollerStyle() ?? "unknown",
    getInitialState: Nh,
    getDataFromDesktopV3: async () => {
      const { getDataFromBeeperDesktopV3LevelDB: e } =
        await import("./beeper-v3-importer-DEKH1wDX.mjs");
      return e();
    },
    getCwd: () => process.cwd(),
    smokeTestingPass: _0,
    snapshotLogs: () => Vr.snapshot(),
    readSnapshotLogs: async (e) => [...(await N0(e)), ...(await x0())],
    openEmailClient: async () => {
      const e = await b0();
      if (!e) {
        (logger.warn("No default mail client found."),
          Dt.openExternal("mailto:"));
        return;
      }
      try {
        if (Ne) await Ie("open", [e]);
        else if (Kt)
          if (e.startsWith("shell:AppsFolder"))
            await Ie("powershell", ["-Command", `Start-Process "${e}"`]);
          else {
            const o = /"([^"]+)"(?:\s+"?%1"?)?/.exec(e)?.[1] || e;
            await Ie(o);
          }
        else cr && (await Ie("gtk-launch", [e]));
      } catch (t) {
        (logger.error("Failed to open mail client, falling back to mailto:", t),
          Dt.openExternal("mailto:"));
      }
    },
    isProtocolHandlerRegistered: FA,
    async isPasswordsInstalled() {
      if (!Bg) return !1;
      try {
        const { stdout: e } = await Ie("/usr/bin/mdfind", [
          'kMDItemCFBundleIdentifier == "com.apple.Passwords"',
        ]);
        return e.trim().length > 0;
      } catch {
        return !1;
      }
    },
    async openPasswordsApp() {
      if (!Ne) return !1;
      try {
        return (await Ie("/usr/bin/open", ["-b", "com.apple.Passwords"]), !0);
      } catch (e) {
        return (logger.warn("Failed to open Passwords app", e), !1);
      }
    },
    renderSFSymbol: async (e, t, o) => Re?.renderSFSymbol?.(e, t, o) ?? null,
    detectData: async (e) => (await Re?.detectData?.(e)) ?? null,
  },
  zi = "[BrowserAuth]",
  xA = 3e4,
  NA = ["slack://", "sand://"];
function IA(e) {
  return new Proxy(e, {
    get(t, o) {
      const i = Object.keys(t).find((a) => a.toLowerCase() === o.toLowerCase());
      return i ? t[i] : void 0;
    },
  });
}
function OA(e, t) {
  if (e.startsWith(".")) {
    const o = t.startsWith(".") ? t : `.${t}`;
    return e.endsWith(o);
  } else return e === t;
}
function PA(e) {
  const t = ND.decryptBrowserPassword(e);
  return F0.replace("'{{USERNAME}}'", JSON.stringify(e.username || ""))
    .replace("'{{PASSWORD}}'", JSON.stringify(t || ""))
    .replace(
      '"{{USERNAME_ELEMENT}}"',
      JSON.stringify(e.usernameElement || "{{USERNAME_ELEMENT}}"),
    )
    .replace(
      '"{{PASSWORD_ELEMENT}}"',
      JSON.stringify(e.passwordElement || "{{PASSWORD_ELEMENT}}"),
    );
}
function RA(e) {
  return {
    url: "http" + (e.secure ? "s://" : "://") + e.domain + e.path,
    name: e.key,
    value: e.value,
    domain: e.key?.startsWith("__Host-") ? void 0 : e.domain,
    path: e.path,
    secure: e.secure,
    httpOnly: e.httpOnly,
    expirationDate: e.expires
      ? ~~(new Date(e.expires).getTime() / 1e3)
      : void 0,
    sameSite: e.sameSite === "none" ? "no_restriction" : e.sameSite || "lax",
  };
}
async function ID(e, t, o, i) {
  const {
      windowTitle: a,
      windowWidth: n,
      windowHeight: r,
      fields: s,
      runJSOnLaunch: u,
      runJSOnNavigate: f,
      runJSOnClose: d,
      expectedFinalURLRegex: c,
      isHidden: l,
      blockedRequestURLs: h,
      loginProcessID: y,
      bridgeID: F,
      stepID: m,
    } = t,
    S = (...ue) => logger.log(zi, e, ...ue),
    E = (...ue) => logger.error(zi, e, ...ue);
  S("launching browser window", e, t.url);
  const b = c ? new RegExp(c) : void 0,
    w = hr(),
    A = fr.fromPartition(w);
  await Promise.all(
    t.cookieJar?.cookies.map((ue) => {
      if (!ue.key) return S("undefined cookie key", ue);
      const Ae = RA(ue);
      return A.cookies.set(Ae);
    }) || [],
  );
  const v = 0,
    C = 0,
    g = Math.floor(v * 0.9),
    D = Math.floor(C * 0.9);
  let N = new He({
    title: a,
    width: n || g || 800,
    height: r || D || 800,
    minHeight: 300,
    minWidth: 300,
    show: !l && !0,
    webPreferences: {
      sandbox: !0,
      nodeIntegration: !1,
      nodeIntegrationInSubFrames: !1,
      nodeIntegrationInWorker: !1,
      contextIsolation: !0,
      partition: w,
      spellcheck: It.enable_spellcheck ?? !0,
    },
  });
  (N.webContents.on("console-message", (ue, Ae, Q, ge, I) => {
    Q.startsWith(zi)
      ? S(Q.replace(zi, ""))
      : Ae === 3 && E("Error from host page:", Q);
  }),
    process.env.BEEPER_LOGIN_DEVTOOLS &&
      (S("BEEPER_LOGIN_DEVTOOLS set, opening devtools for login window"),
      N.webContents.openDevTools({ mode: "detach" })));
  let P,
    R,
    k = !1,
    q;
  const U = {};
  function $() {
    ((k = !0), q && clearTimeout(q), N?.close());
  }
  let V;
  const re = hr(),
    X = [];
  function fe(ue) {
    if (ue !== V) {
      V = ue;
      try {
        let Ae = "unknown";
        if (ue !== "") {
          const ge = new URL(ue);
          Ae = ge.origin + ge.pathname;
        }
        const Q = { webview_session_id: re, url: Ae };
        (F && (Q.bridge_id = F),
          y && (Q.login_process_id = y),
          m && (Q.step_id = m),
          S(
            `Navigated to webviewSessionId:${re} bridgeID:${F} loginProcessID:${y} url:${Q.url}`,
          ),
          X.push({ properties: Q, timestamp: new Date() }));
      } catch {}
    }
  }
  const Y = s.filter((ue) =>
    ue.sources.find((Ae) => Ae.type === "request_header"),
  );
  Y.length > 0 &&
    A.webRequest.onBeforeSendHeaders((ue, Ae) => {
      const Q = IA(ue.requestHeaders);
      for (const ge of Y) {
        const I = ge.sources.find((W) => W.type === "request_header");
        if (!I) continue;
        const _ = Q[I.name.toLowerCase()];
        if (_ !== void 0)
          try {
            if (
              (ge.pattern && !new RegExp(ge.pattern).test(_)) ||
              (I.request_url_regex &&
                !new RegExp(I.request_url_regex).test(ue.url))
            )
              continue;
            U[ge.id] = _;
          } catch {
            continue;
          }
      }
      Ae({ requestHeaders: ue.requestHeaders });
    });
  async function Ce() {
    if (!N) return;
    try {
      await N.loadURL(t.url, {
        userAgent: t.userAgent === void 0 ? kg : t.userAgent,
      });
    } catch (_) {
      _("bw.loadURL error", _);
    }
    u && N.webContents.executeJavaScript(u).catch((_) => E(_));
    const ue = (_) => () => {
      (f && N?.webContents.executeJavaScript(f).catch((W) => E(W)),
        fe(N?.webContents.getURL() || ""));
    };
    if (
      (N.webContents.on("did-navigate-in-page", ue()),
      N.webContents.on("did-navigate", ue()),
      N.webContents.on("did-frame-navigate", ue()),
      fe(N.webContents.getURL() || ""),
      i)
    ) {
      const _ = PA(i);
      setTimeout(() => {
        _ && N?.webContents.executeJavaScript(_);
      }, 100);
    }
    const Ae = () =>
        N?.webContents.executeJavaScript(d ?? "").catch((_) => E(_)),
      Q = async () => {
        if (!N || N?.isDestroyed()) return;
        ((R = N?.webContents.getURL()),
          d && (P = (await Ae()) ?? {}),
          await ge(),
          await I(),
          s.forEach((M) => {
            if (!M.sources.find((he) => he.type === "special")) return;
            const le = P[M.id];
            le !== void 0 &&
              ((M.pattern && !new RegExp(M.pattern).test(le)) ||
                (U[M.id] = le));
          }),
          s
            .filter((M) => M.required)
            .map((M) => M.id)
            .every((M) => U[M] !== void 0) &&
            ((k = !0),
            b
              ? b.test(R) &&
                (S(
                  "All cookies found and final URL reached, closing window",
                  R,
                ),
                $())
              : (S("All cookies found, closing window"),
                N && (N.title = "Authenticating..."),
                await Xi(1e3),
                $())),
          setTimeout(Q, 100));
      };
    (setTimeout(Q, 1e3),
      l &&
        (q = setTimeout(() => {
          (k ||
            S(
              "Hidden login timed out; submitting collected fields for bridge to decide next step",
            ),
            $());
        }, xA)));
    const ge = async () => {
        for (const _ of s) {
          const W = _.sources.find((he) => he.type === "cookie");
          if (!W) continue;
          const M =
            (await N?.webContents.session.cookies.get({ name: W.name })) || [];
          if (M.length === 0) continue;
          const le = M.find((he) =>
            W.cookie_domain && he.domain && !OA(he.domain, W.cookie_domain)
              ? !1
              : he.name === W.name,
          );
          if (le?.value !== void 0)
            try {
              const he = decodeURIComponent(le.value);
              if (_.pattern && !new RegExp(_.pattern).test(he)) continue;
              U[_.id] = he;
            } catch {
              continue;
            }
        }
      },
      I = async () => {
        for (const _ of s) {
          const W = _.sources.find((le) => le.type === "local_storage");
          if (!W) continue;
          let M = null;
          try {
            M = await N?.webContents.executeJavaScript(
              `window.localStorage.getItem(${JSON.stringify(W.name)})`,
            );
          } catch {
            continue;
          }
          if (M != null)
            try {
              if (_.pattern && !new RegExp(_.pattern).test(M)) continue;
              U[_.id] = M;
            } catch {
              continue;
            }
        }
      };
    N.webContents.on("will-navigate", (_, W) => {
      NA.some((M) => W.startsWith(M)) && _.preventDefault();
    });
  }
  return (
    h?.length &&
      A.webRequest.onBeforeRequest((ue, Ae) => {
        h.some((Q) => ue.url.includes(Q))
          ? S("Blocked request to", ue.url)
          : Ae({});
      }),
    new Promise((ue, Ae) => {
      if (!N) {
        Ae(
          new Error("Browser window is in an unexpected state while launching"),
        );
        return;
      }
      (N.on("closed", () => {
        ((R ||= N?.webContents.getURL() || t.url),
          (N = null),
          ue({
            didFinish: k,
            lastURL: R,
            fields: Object.keys(U).length > 0 ? U : void 0,
            navigationEvents: X,
          }));
      }),
        Ce());
    })
  );
}
const bh = { PROXY: "http", HTTPS: "https", SOCKS5: "socks5" };
function LA(e) {
  for (const t of e.split(";")) {
    const [o, i] = t.trim().split(/\s+/);
    if (o === "DIRECT") break;
    if (bh[o] && i) return `${bh[o]}://${i}`;
  }
  return "";
}
async function BA(e) {
  const t = Date.now(),
    o = await fr.defaultSession.resolveProxy(e),
    i = LA(o);
  return (
    logger.log(
      "[system-proxy] resolved",
      e,
      "to",
      o,
      "in",
      Date.now() - t,
      "ms",
    ),
    a0(i),
    i
  );
}
async function kA(e) {
  const t = "The database has been corrupted and cannot be recovered";
  kt("db-corrupted", t);
  const o = Xe.showMessageBoxSync({
    type: "error",
    message: `${tt.APP_NAME} Database Corrupted`,
    detail: t,
    buttons: ["Reset Database & Relaunch", `Quit ${tt.APP_NAME}`],
    defaultId: 0,
    cancelId: 1,
  });
  if (o === 1) {
    ye.quit();
    return;
  }
  if (o === 0) {
    const i = e.message.slice(18);
    (await gg.rm(i), Qn("db corrupted"));
  }
}
function OD(e) {
  if (e?.message.startsWith("$TextsDbCorrupted$")) return kA(e);
  if (Js(e)) {
    jo(e);
    return;
  }
  const t = "Something went wrong",
    o =
      t +
      `

` +
      (e?.stack || JSON.stringify(e));
  (kt("main", o), Xe.showMessageBox({ title: t, message: o }));
}
const MA = {
    showMessageBox(e) {
      Xe.showMessageBox(e);
    },
    handleError({ errorMessage: e, errorStack: t }) {
      const o = new Error(e);
      ((o.stack = t), rE(o), OD(o));
    },
    openBrowserWindow: ID,
    handleDeepLink: A0,
    applySystemProxy: BA,
    startupCheckpoint({ name: e, at: t }) {
      (Qs(e, t), e === "renderer db ready" && tE());
    },
  },
  UA = "kCFTimeZoneSystemTimeZoneDidChangeNotification";
let ri = [],
  zn;
const qA = () => {
    zn === void 0 &&
      (zn = Jr.subscribeLocalNotification(UA, () => {
        ri.forEach((e) => e());
      }));
  },
  $A = () => {
    zn !== void 0 &&
      ri.length === 0 &&
      (Jr.unsubscribeLocalNotification(zn), (zn = void 0));
  },
  jA = (e) => {
    Ne && (qA(), !ri.includes(e) && ri.push(e));
  },
  WA = () => {
    Ne && ((ri = []), $A());
  },
  HA = ko(import.meta.dirname, "./platform-worker-BjTfLpXw.mjs");
u0();
Ne && Am();
const Fh = process.env.BEEPER_BENCH ? null : Promise.resolve().then(() => EC);
async function GA() {
  if (
    (ut(
      `You're running ${Ve.friendlyProductName} v${Ve.version} (production) on ${process.platform} ${Ke.release()} ${process.arch} (server env: ${Kn})`,
    ),
    await k2())
  ) {
    ye.exit(0);
    return;
  }
  if (!ye.requestSingleInstanceLock({ version: Ve.version }))
    if (process.env.ALLOW_MULTIPLE_INSTANCES === "true")
      ut(
        "Another instance is running but ALLOW_MULTIPLE_INSTANCES=true, so we continue",
      );
    else {
      (ut("Quitting because another instance is running"), ye.quit());
      return;
    }
  let e = () => {};
  const t = new Promise((i) => {
    e = i;
  });
  if (Fh) {
    const { default: i } = await Fh;
    (i(ks),
      s0({
        awaitBeforeImport: t,
        onSettled: () => {
          Qs("sentry init done");
        },
      }));
  } else
    (ut(
      "Benchmark mode — renderer skipped (sync processing measured in worker)",
    ),
      e());
  (Ne &&
    (jA(() => {
      mainWindow?.rs.onTimezoneChange();
    }),
    ye.on("quit", () => {
      WA();
    })),
    globalThis.MACHINE_ID_PROMISE && (await globalThis.MACHINE_ID_PROMISE));
  const o = await ks;
  if (yt) {
    ut("running in browser mode");
    const { default: i } = await import("./ipc-main-shim-DE4RL508.mjs");
    globalThis.ipcMainShim = new i();
    const { default: a } = await import("./pw-entry-D6IEoyuB.mjs");
    (a(o).catch(OD), e());
  } else {
    ut("running with electron");
    const i = Th(
      xh.PLATFORM_WORKER,
      {
        ...o,
        userDataDirPath: lt,
        serverEnv: Kn,
        userAgent: ye.userAgentFallback,
        preferredSystemLanguage: ye.getPreferredSystemLanguages()[0],
        RUN_IN_BROWSER_MODE: yt,
      },
      HA,
    );
    (i.on("message", async (n) => {
      if (n?.__breadcrumb)
        return globalThis.Sentry?.addBreadcrumb(n.__breadcrumb);
      if (n === "bench-complete") return Qr();
      const { reqID: r, methodName: s, args: u = {} } = n;
      try {
        const f = await MA[s]?.(...u);
        i.postMessage({ reqID: r, result: f });
      } catch (f) {
        (logger.error(f), i.postMessage({ reqID: r, error: f.message }));
      }
    }),
      i.on("error", (n) => {
        (mainWindow?.rs.testRelayerTransportConnection(),
          mainWindow?.rs.addToast(
            { text: "Platform worker errored: " + n.message },
            -1,
            void 0,
            !0,
          ));
      }),
      i.on("exit", () => {
        mainWindow?.rs.testRelayerTransportConnection();
      }));
    const a = (n) => {
      n === "PASInitComplete" &&
        (ut("Received PASInitComplete"), i.off("message", a), e());
    };
    i.on("message", a);
  }
}
process.on("uncaughtException", (e) => {
  Js(e) && jo(e);
});
process.on("unhandledRejection", (e) => {
  Js(e) && jo(e);
});
ut("main()");
GA();
const MF = Object.freeze(
  Object.defineProperty({ __proto__: null }, Symbol.toStringTag, {
    value: "Module",
  }),
);
export {
  Kn as S,
  MA as a,
  jy as b,
  aE as c,
  mt as d,
  ID as l,
  MF as m,
  nE as r,
  lt as u,
  ep as w,
};
//# sourceMappingURL=main-entry-CnfqTXzU.mjs.map
