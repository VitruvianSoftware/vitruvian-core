import { w as n, c as p, r as d } from "./main-entry-CnfqTXzU.mjs";
import { bv as a, aN as l, K as e } from "./Keychain-CHHka2u7.mjs";
import s from "events";
import { session as m } from "electron";
import { I as h } from "./sentry-enabled-COAVq6nC.mjs";
import w from "child_process";
import "os";
import "electron-drag-click";
import "./AsyncSqlite-CpInlfQ-.mjs";
import "./index-DKkZ9dV1.mjs";
import "worker_threads";
import "./constants-BL_pdRyX.mjs";
import "path";
import "url";
import "fs";
import "./machine-id-DFkLVgcU.mjs";
import "./package-CIHfweXK.mjs";
import "./sentry-common-CDPx3Glo.mjs";
import "./_commonjsHelpers-CBUqixCJ.mjs";
import "perf_hooks";
import "./index-CNG_AM8w.mjs";
import "timers/promises";
import "./logger-DoW0T1f3.mjs";
import "async_hooks";
import "./util-CrY9x2BW.mjs";
import "node:net";
import "node:os";
import "./remote-method-Dje_9VSb.mjs";
import "crypto";
import "util";
import "./local-ips-64rTQJNz.mjs";
import "fs/promises";
import "./startup-checkpoints-BQimOHWq.mjs";
import "./index-CMOlVndj.mjs";
import "assert";
import "buffer";
import "stream";
import "./index-B_PiTES1.mjs";
import "node:util";
import "node:stream";
import "node:child_process";
import "node:crypto";
import "node:path";
import "node:events";
import "./app-api-NqP9XGk0.mjs";
import "./got-fetch-BkprknxZ.mjs";
import "./got-_wC7Q_ix.mjs";
import "http";
import "https";
import "dns";
import "zlib";
import "http2";
import "tls";
import "net";
import "./macos-contacts-server-D9gt4gn9.mjs";
import "./fs-xattr-D7o0ii7n.mjs";
import "diskusage";
import "./rolling-logger-C9NTeNo3.mjs";
import "node:fs/promises";
import "./system-stats-BLVoJrkB.mjs";
import "./fromFile-Bd43zJBF.mjs";
import "node:fs";
import "./utils-D8MokWSu.mjs";
import "stream/promises";
import "./v4-BcIr5opf.mjs";
import "node:url";
import "./download-DaM5ZnbT.mjs";
import "constants";
import "tty";
import "string_decoder";
import "./index-BiHJsdYm.mjs";
import "./SimpleHTMLParser-DYKa0uJQ.mjs";
import "./SimpleTwitterClient-BlyQEWJV.mjs";
import "./index-BE_LQecc.mjs";
import "./readable-VMWn1OrG.mjs";
import "./register-proxy-7lV9pun2.mjs";
import "domain";
import "./sentry-buffer-BdjgCKZo.mjs";
import "./crash-reporter-BlEAKQlO.mjs";
import "better-sqlite3";
import "node:module";
(function () {
  try {
    var o =
      typeof window < "u"
        ? window
        : typeof global < "u"
          ? global
          : typeof globalThis < "u"
            ? globalThis
            : typeof self < "u"
              ? self
              : {};
    o.SENTRY_RELEASE = { id: "4.3.209" };
    var t = new o.Error().stack;
    t &&
      ((o._sentryDebugIds = o._sentryDebugIds || {}),
      (o._sentryDebugIds[t] = "1ce5ade8-a88d-4961-9763-6a067f4a28f8"),
      (o._sentryDebugIdIdentifier =
        "sentry-dbid-1ce5ade8-a88d-4961-9763-6a067f4a28f8"));
  } catch {}
})();
const u = [
    "loadURL",
    "show",
    "hide",
    "isMaximized",
    "isMinimized",
    "isVisible",
    "isFocused",
    "maximize",
    "unmaximize",
    "minimize",
    "restore",
    "isFullScreen",
    "toggleFullScreen",
    "getBounds",
    "setBounds",
  ],
  c = class extends s {
    constructor(t) {
      (super(),
        (this.webContents = {
          send(i, ...r) {
            globalThis.pas.defaultTransports.tranportSend({
              type: "ipc-message",
              channel: i,
              args: r,
            });
          },
          session: m.defaultSession,
          downloadURL(i) {
            throw Error("unimplemented");
          },
        }),
        (this.setTouchBar = () => {}),
        (this.isDestroyed = () => !1),
        (this.nsWin = new a.NativeWebView(h, l())));
      for (const i of u) this[i] = (...r) => this.nsWin[i](...r);
    }
    get fullScreen() {
      return this.isFullScreen();
    }
  },
  f = class extends s {
    constructor(t) {
      (super(),
        (this.webContents = {
          send(i, ...r) {
            globalThis.pas.defaultTransports.tranportSend({
              type: "ipc-message",
              channel: i,
              args: r,
            });
          },
          session: m.defaultSession,
          downloadURL(i) {
            throw Error("unimplemented");
          },
        }),
        (this.setTouchBar = () => {}),
        (this.isDestroyed = () => !1),
        (this.loadURL = (i) => {
          const r = e || "Google Chrome";
          w.spawn("open", ["-a", r, i]);
        }),
        (this.isMaximized = () => {}),
        (this.isMinimized = () => {}),
        (this.unmaximize = () => {}),
        (this.maximize = () => {}),
        (this.minimize = () => {}),
        (this.show = () => {}),
        (this.hide = () => {}),
        (this.restore = () => {}),
        (this.isVisible = () => {}),
        (this.isFocused = () => {}),
        (this.isFullScreen = () => {}),
        (this.toggleFullScreen = () => {}));
    }
  };
class g {
  constructor() {
    ((this.wsk = n("main")),
      (this.window = new (e ? f : c)({})),
      (this.rs = p(this.window)),
      d(this));
  }
  get fullScreen() {
    return this.window.isFullScreen();
  }
  show() {
    (this.window.isMinimized() && this.window.restore(), this.window.show());
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
  sendMessage(t, ...i) {
    this.window.webContents.send(t, ...i);
  }
  loadURL(t) {
    (logger.log({ url: t }), this.window.loadURL(t));
  }
}
function Gi() {
  return new g();
}
export { g as MainWindowShim, Gi as default };
//# sourceMappingURL=main-window-shim-B_M14ZVI.mjs.map
