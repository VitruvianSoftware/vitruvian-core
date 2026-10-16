import o from "path";
import E from "os";
import { fileURLToPath as a } from "url";
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
      (e._sentryDebugIds[t] = "9f807674-fec6-41c4-a3cc-c05649e6066a"),
      (e._sentryDebugIdIdentifier =
        "sentry-dbid-9f807674-fec6-41c4-a3cc-c05649e6066a"));
  } catch {}
})();
const O = process.env.BEEPER_SERVER_EDITION === "1",
  d = process.env.BEEPER_BENCH === "true",
  n = process.platform === "win32",
  r = process.platform === "linux",
  s = process.platform === "darwin",
  A = "config.json",
  R = ".texts-conf.json";
function c() {
  if (process.env.BEEPER_USER_DATA_DIR) return process.env.BEEPER_USER_DATA_DIR;
  const e = process.env.BEEPER_PROFILE || void 0,
    t = "BeeperTexts" + (e ? `-${e}` : "");
  return s
    ? o.join(E.homedir(), "Library", "Application Support", t)
    : n
      ? process.env.APPDATA
        ? o.join(process.env.APPDATA, t)
        : o.join(E.homedir(), t)
      : o.join(
          process.env.XDG_CONFIG_HOME ?? o.join(E.homedir(), ".config"),
          t,
        );
}
function i() {
  const e = c();
  return n && !process.env.APPDATA ? o.join(c(), "..", R) : o.join(e, A);
}
const b = globalThis.INITIAL_STATE?.userConfPath ?? i(),
  _ = +E.release().split(".")[0],
  U = s && _ >= 19,
  C = s && _ >= 20,
  G = s && _ >= 21,
  B = s && _ >= 22,
  h = s && _ >= 24,
  I = s && _ >= 25,
  g = { x: I ? 12 : 18, y: 18 },
  p = 140;
function S() {
  const e = ` AppleWebKit/537.36 (KHTML, like Gecko) Chrome/${p}.0.0.0 Safari/537.36`;
  if (s) return "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)" + e;
  if (n) return "Mozilla/5.0 (Windows NT 10.0; Win64; x64)" + e;
  if (r) return "Mozilla/5.0 (X11; Linux x86_64)" + e;
}
const T = S(),
  N = "Beeper/3.110.1",
  v = T?.replace(/ Chrome\/\d+\.\d+\.\d+\.\d+/, ` ${N}$&`);
function l() {
  return s ? " (macOS)" : n ? " (Windows)" : r ? " (Linux)" : "";
}
const k = `${O ? "Beeper Server" : "Beeper Desktop v4"}${l()}`.trim(),
  w = "beeper://",
  H =
    "<REDACTED_GOOGLE_OAUTH_CLIENT_ID>",
  V = "<REDACTED_GOOGLE_OAUTH_CLIENT_SECRET>",
  K = "com.automattic.beeper.siwa",
  y = "https://www.beeper.com/auth/apple/callback",
  P = "https://www.beeper.com",
  j = `${P}/privacy`,
  x = "com.automattic.beeper.desktop",
  F = "BEEPER-PRIVATE-API-PLEASE-DONT-USE",
  Y = "https://www.beeper.com/changelog/desktop",
  D = a(new URL("..", import.meta.url)),
  f = D,
  $ = f.replace(`app.asar${o.sep}`, `app.asar.unpacked${o.sep}`),
  W = !1,
  X = "beeper_8a5da52ed126447d359e70c05721a8aa",
  z = 100,
  J = "!transcriptions:beeper.local",
  q = "!bookmarks:beeper.local",
  Q = "bookmarks",
  Z = "com.beeper.bookmark",
  ee = "com.beeper.bookmark",
  oe = "!blasts:beeper.local",
  se = "blasts",
  te = "com.beeper.blast",
  _e = "com.beeper.blast.batch",
  Ee = "!removed-messages:beeper.local",
  ne = "removed-messages",
  ce = "com.beeper.removed_message",
  re = "com.beeper.removed_message",
  ae = "@room",
  Oe = 330,
  Ae = 620,
  Re = [0, 30, 90, 120];
export {
  Re as AGE_DAYS,
  y as APPLE_SIGN_IN_REDIRECT_URI,
  K as APPLE_SIGN_IN_SERVICES_ID,
  X as BEEPER_API_ACCOUNT_ID,
  Y as BEEPER_CHANGELOG_LINK,
  P as BEEPER_DOMAIN,
  F as BEEPER_GUEST_TOKEN,
  se as BLASTS_MANAGED_ROOM,
  oe as BLASTS_ROOM_ID,
  _e as BLAST_BATCH_EVENT_TYPE,
  te as BLAST_EVENT_TYPE,
  Q as BOOKMARKS_MANAGED_ROOM,
  q as BOOKMARKS_ROOM_ID,
  Z as BOOKMARK_EVENT_TYPE,
  ee as BOOKMARK_REL_TYPE,
  D as BUILD_DIR_PATH,
  x as BUNDLE_ID,
  w as DEEP_LINK_PROTOCOL,
  k as DEFAULT_DEVICE_NAME,
  H as GOOGLE_OAUTH_CLIENT_ID,
  V as GOOGLE_OAUTH_CLIENT_SECRET,
  v as GOOGLE_SAFE_USER_AGENT,
  d as IS_BENCH,
  C as IS_BIG_SUR_OR_UP,
  U as IS_CATALINA_OR_UP,
  r as IS_LINUX,
  s as IS_MAC_OS,
  G as IS_MONTEREY_OR_UP,
  h as IS_SEQUOIA_OR_UP,
  O as IS_SERVER_EDITION,
  I as IS_TAHOE_OR_UP,
  B as IS_VENTURA_OR_UP,
  n as IS_WINDOWS,
  z as LARGE_GROUP_THRESHOLD,
  _ as MACOS_MAJOR_VERSION,
  g as MAC_TRAFFIC_LIGHT_POSITION,
  Ae as ONBOARDING_SCREEN_HEIGHT,
  Oe as ONBOARDING_SCREEN_WIDTH,
  j as PRIVACY_URL,
  f as PUBLIC_DIR_PATH,
  $ as PUBLIC_DIR_PATH_UNPACKED,
  ne as REMOVED_MESSAGES_MANAGED_ROOM,
  Ee as REMOVED_MESSAGES_ROOM_ID,
  ce as REMOVED_MESSAGE_EVENT_TYPE,
  re as REMOVED_MESSAGE_REL_TYPE,
  ae as ROOM_MENTION,
  J as TRANSCRIPTIONS_ROOM_ID,
  T as USER_AGENT,
  b as USER_CONF_PATH,
  W as rejectUnauthorizedCerts,
  i as resolveUserConfPath,
  c as resolveUserDataDir,
};
//# sourceMappingURL=constants-BL_pdRyX.mjs.map
