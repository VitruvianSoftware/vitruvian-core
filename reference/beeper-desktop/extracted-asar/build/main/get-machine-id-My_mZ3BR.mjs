import { exec as f, execSync as u } from "child_process";
import { createHash as p } from "crypto";
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
    var r = new e.Error().stack;
    r &&
      ((e._sentryDebugIds = e._sentryDebugIds || {}),
      (e._sentryDebugIds[r] = "aa7c4e68-5e80-4c26-8fb0-79e6f5d9c0f6"),
      (e._sentryDebugIdIdentifier =
        "sentry-dbid-aa7c4e68-5e80-4c26-8fb0-79e6f5d9c0f6"));
  } catch {}
})();
const { platform: n } = process,
  l = {
    native: "%windir%\\System32",
    mixed: "%windir%\\sysnative\\cmd.exe /c %windir%\\System32",
  },
  o = {
    darwin: "ioreg -rd1 -c IOPlatformExpertDevice",
    win32: `${l[w()]}\\REG.exe QUERY HKEY_LOCAL_MACHINE\\SOFTWARE\\Microsoft\\Cryptography /v MachineGuid`,
    linux:
      "( cat /var/lib/dbus/machine-id /etc/machine-id 2> /dev/null || hostname ) | head -n 1 || :",
    freebsd: "kenv -q smbios.system.uuid || sysctl -n kern.hostuuid",
  };
function w() {
  return process.platform !== "win32"
    ? ""
    : process.arch === "ia32" && "PROCESSOR_ARCHITEW6432" in process.env
      ? "mixed"
      : "native";
}
function a(e) {
  return p("sha256").update(e).digest("hex");
}
function c(e) {
  switch (n) {
    case "darwin":
      return e
        .split("IOPlatformUUID")[1]
        .split(
          `
`,
        )[0]
        .replace(/=|\s+|"/gi, "")
        .toLowerCase();
    case "win32":
      return e
        .toString()
        .split("REG_SZ")[1]
        .replace(/\r+|\n+|\s+/gi, "")
        .toLowerCase();
    case "linux":
      return e
        .toString()
        .replace(/\r+|\n+|\s+/gi, "")
        .toLowerCase();
    case "freebsd":
      return e
        .toString()
        .replace(/\r+|\n+|\s+/gi, "")
        .toLowerCase();
    default:
      throw new Error(`Unsupported platform: ${process.platform}`);
  }
}
function y(e) {
  const r = c(u(o[n]).toString());
  return e ? r : a(r);
}
function b(e) {
  return new Promise((r, i) =>
    f(o[n], {}, (t, d, h) => {
      if (t)
        return i(new Error(`Error while obtaining machine id: ${t.stack}`));
      const s = c(d.toString());
      return r(e ? s : a(s));
    }),
  );
}
export { b as machineId, y as machineIdSync };
//# sourceMappingURL=get-machine-id-My_mZ3BR.mjs.map
