import { a as m } from "./_commonjsHelpers-CBUqixCJ.mjs";
import b from "node:module";
(function () {
  try {
    var s =
      typeof window < "u"
        ? window
        : typeof global < "u"
          ? global
          : typeof globalThis < "u"
            ? globalThis
            : typeof self < "u"
              ? self
              : {};
    s.SENTRY_RELEASE = { id: "4.3.209" };
    var t = new s.Error().stack;
    t &&
      ((s._sentryDebugIds = s._sentryDebugIds || {}),
      (s._sentryDebugIds[t] = "521c2e17-cafc-42b4-a2ba-0bdab11a95f6"),
      (s._sentryDebugIdIdentifier =
        "sentry-dbid-521c2e17-cafc-42b4-a2ba-0bdab11a95f6"));
  } catch {}
})();
const x = import.meta.filename,
  y = import.meta.dirname,
  F = b.createRequire(import.meta.url);
function h(s, t) {
  for (var c = 0; c < t.length; c++) {
    const a = t[c];
    if (typeof a != "string" && !Array.isArray(a)) {
      for (const r in a)
        if (r !== "default" && !(r in s)) {
          const n = Object.getOwnPropertyDescriptor(a, r);
          n &&
            Object.defineProperty(
              s,
              r,
              n.get ? n : { enumerable: !0, get: () => a[r] },
            );
        }
    }
  }
  return Object.freeze(
    Object.defineProperty(s, Symbol.toStringTag, { value: "Module" }),
  );
}
var d = { exports: {} },
  l;
function g() {
  return (
    l ||
      ((l = 1),
      (() => {
        var s = {
            557: (r, n, i) => {
              const e = F(i.ab + "build/Release/permissions.node");
              function f(o) {
                if (
                  ![
                    "accessibility",
                    "bluetooth",
                    "calendar",
                    "camera",
                    "contacts",
                    "full-disk-access",
                    "input-monitoring",
                    "location",
                    "microphone",
                    "music-library",
                    "photos-add-only",
                    "photos-read-write",
                    "reminders",
                    "speech-recognition",
                    "screen",
                  ].includes(o)
                )
                  throw new TypeError(`${o} is not a valid type`);
                return e.getAuthStatus.call(this, o);
              }
              function p(o) {
                if (!["desktop", "documents", "downloads"].includes(o))
                  throw new TypeError(`${o} is not a valid protected folder`);
                return e.askForFoldersAccess.call(this, o);
              }
              function A(o = "add-only") {
                if (!["add-only", "read-write"].includes(o))
                  throw new TypeError(
                    `${o} must be one of either 'add-only' or 'read-write'`,
                  );
                return e.askForPhotosAccess.call(this, o);
              }
              r.exports = {
                askForAccessibilityAccess: e.askForAccessibilityAccess,
                askForCalendarAccess: e.askForCalendarAccess,
                askForCameraAccess: e.askForCameraAccess,
                askForContactsAccess: e.askForContactsAccess,
                askForFoldersAccess: p,
                askForFullDiskAccess: e.askForFullDiskAccess,
                askForInputMonitoringAccess: e.askForInputMonitoringAccess,
                askForRemindersAccess: e.askForRemindersAccess,
                askForMicrophoneAccess: e.askForMicrophoneAccess,
                askForMusicLibraryAccess: e.askForMusicLibraryAccess,
                askForPhotosAccess: A,
                askForSpeechRecognitionAccess: e.askForSpeechRecognitionAccess,
                askForScreenCaptureAccess: e.askForScreenCaptureAccess,
                getAuthStatus: f,
              };
            },
          },
          t = {};
        function c(r) {
          var n = t[r];
          if (n !== void 0) return n.exports;
          var i = (t[r] = { exports: {} }),
            e = !0;
          try {
            (s[r](i, i.exports, c), (e = !1));
          } finally {
            e && delete t[r];
          }
          return i.exports;
        }
        typeof c < "u" && (c.ab = y + "/");
        var a = c(557);
        d.exports = a;
      })()),
    d.exports
  );
}
var u = g();
const _ = m(u),
  M = h({ __proto__: null, default: _ }, [u]);
export { M as i };
//# sourceMappingURL=index-C21G-mNi.mjs.map
