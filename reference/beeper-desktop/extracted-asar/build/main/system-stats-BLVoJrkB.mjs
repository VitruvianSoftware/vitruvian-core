import { h as d } from "./index-DKkZ9dV1.mjs";
import "worker_threads";
import "./constants-BL_pdRyX.mjs";
import "path";
import "os";
import "url";
import "fs";
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
      (e._sentryDebugIds[t] = "9eeb685e-3e2b-4aa8-8c8c-ac5130416de0"),
      (e._sentryDebugIdIdentifier =
        "sentry-dbid-9eeb685e-3e2b-4aa8-8c8c-ac5130416de0"));
  } catch {}
})();
const p = [600 * 1e3, 3600 * 1e3, 360 * 60 * 1e3, 1440 * 60 * 1e3],
  u = [...p];
async function c(e) {
  const r = ~~(e.getProcessUptime() / 60),
    s = await e.getProcessMemoryInfo().catch(() => {});
  if (s) {
    const i = ~~(s.private / 1024),
      a = ~~(s.shared / 1024);
    (globalThis.rs && globalThis.rs.setHighMemoryUsage(i > 4e3),
      e.sendEvent([
        {
          event: "Renderer Memory",
          properties: {
            hwAccel: d,
            uptimeMinutes: r,
            privateMb: i,
            sharedMb: a,
          },
        },
      ]));
  }
  const n = u.shift();
  n && setTimeout(() => c(e), n);
}
const f = (e) => {
  const t = e.getProcessCpuUsage();
  if (!t) return;
  const r = "percentCPUUsage" in t ? t.percentCPUUsage : 0,
    s = "idleWakeupsPerSecond" in t ? t.idleWakeupsPerSecond : 0;
  r !== 0 &&
    e.sendEvent([
      {
        event: "Renderer Performance",
        properties: {
          uptimeMinutes: ~~(e.getProcessUptime() / 60),
          arch: process.arch,
          idleWakeupsPerSecond: s,
          percentCPUUsage: r,
        },
      },
    ]);
};
let o = !1;
function v(e) {
  o ||
    (e &&
      (setTimeout(() => c(e), 60 * 1e3),
      setInterval(() => f(e), 300 * 1e3),
      (o = !0)));
}
export { p as REPORT_INTERVALS_MS, v as registerSystemStatsReporting };
//# sourceMappingURL=system-stats-BLVoJrkB.mjs.map
