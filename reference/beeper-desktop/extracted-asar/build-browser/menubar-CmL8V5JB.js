import { cG as a, ah as r } from "./App-BHgTsVmv.js";
import "./sentry-common-BNqrY_yc.js";
import { e as s } from "./index-Ch31Akxs.js";
import {
  c5 as k,
  ca as m,
  c9 as w,
  a1 as l,
  cK as c,
  J as o,
  ab as E,
  a5 as y,
  ac as A,
} from "./matrix-util-8DbIGEm-.js";
import { D as h } from "./load-stores-BlYvfTx9.js";
import "./index-Cw3pknxT.js";
import "./index-5FBEE1WD.js";
import "./main-process-state-BDOn7dvV.js";
import "./report-dialog-C-g_klPx.js";
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
    var i = new e.Error().stack;
    i &&
      ((e._sentryDebugIds = e._sentryDebugIds || {}),
      (e._sentryDebugIds[i] = "7e9be7ea-5d81-4137-b22f-b5dac78719cf"),
      (e._sentryDebugIdIdentifier =
        "sentry-dbid-7e9be7ea-5d81-4137-b22f-b5dac78719cf"));
  } catch {}
})();
const _ = {
  role: "windowMenu",
  submenu: [
    { role: "togglefullscreen" },
    { role: "zoom" },
    { role: "minimize" },
    { role: "front" },
  ],
};
function I(e) {
  const i = [
    { role: "toggleDevTools", visible: !1 },
    {
      label: l("Report a Problem"),
      accelerator: a.REPORT_A_PROBLEM.key,
      click: () => e.focusedWSS?.setVisibleModal(r.REPORT_PROBLEM),
    },
    { label: c(l("Open %s Help"), s.APP_NAME), click: k },
    { type: "separator" },
    { label: c(l("Open %s"), "Beeper.com"), click: m },
    { label: c(l("Follow %s on X"), "@Beeper"), click: w },
    { type: "separator" },
    { label: l("Changelog"), click: () => e.openChangelogWindow() },
    { label: l("Privacy && Security"), click: () => e.openPrivacyWindow() },
    {
      label: l("Keyboard Shortcuts"),
      accelerator: a.TOGGLE_HOTKEYS_MODAL.key,
      click: () => e.focusedWSS?.setVisibleModal(r.HOTKEYS, void 0, !1),
    },
  ];
  e.beeperClientStore.loggedInUser &&
    i.push(
      { type: "separator" },
      {
        label: c(l("Logout of %s..."), s.BRAND_NAME),
        click: () => e.beeperClientStore.logout(),
      },
    );
  const n = e.updateProgress.render,
    t = n === h ? l("Check for Updates…") : n,
    p = [
      {
        label: c(l("About %s"), s.APP_NAME),
        click: () => e.focusedWSS?.openPrefs(o.PREFS_ABOUT),
      },
      { label: t, click: () => e.autoUpdate.checkForUpdates() },
      { type: "separator" },
      ...(e.beeperClientStore.isAuthenticated
        ? [
            {
              label: l("Accounts…"),
              click: () => e.focusedWSS?.openPrefs(o.ACCOUNTS),
            },
            {
              label: l("Preferences"),
              click: () => e.windowsStore.openPrefsInNewWindow(e.mainWSS),
              accelerator: a.TOGGLE_PREFS_PANE.key,
            },
            { type: "separator" },
            {
              label: l("Command Bar…"),
              click: () => e.focusedWSS?.cmdBarViewStore.showInNormalMode(),
              accelerator: a.TOGGLE_COMMAND_BAR.key,
            },
            {
              label: l("Search..."),
              click: () => e.focusedWSS?.cmdBarViewStore.showSearch(),
              accelerator: a.SEARCH.key,
            },
          ]
        : []),
      { type: "separator" },
      {
        accelerator: "CmdOrCtrl+W",
        label: l("Close Window"),
        click: () => e.windowsStore.closeFocusedWindow(),
        visible: !1,
      },
      { role: "services" },
      { type: "separator" },
      { role: "hide" },
      { role: "hideothers" },
      { role: "unhide" },
      { type: "separator" },
      ...(e.touchIDSupported
        ? [{ label: l("Lock App"), click: () => e.setAppUnlocked(!1) }]
        : []),
      {
        label: c(l("Logout of %s..."), s.BRAND_NAME),
        click: e.beeperClientStore.logout,
      },
      {
        accelerator: a.QUIT_APP.key,
        click() {
          E.quitApp();
        },
        label: c(l("Quit %s"), s.APP_NAME),
      },
    ].filter(Boolean),
    d = { role: "help", submenu: i },
    b = {
      label: l("View"),
      submenu: [
        {
          label: e.prefsStore.showSpaceSwitcher
            ? l("Hide Space Bar")
            : l("Show Space Bar"),
          click: () => e.prefsStore.toggleSpaceSwitcher(),
          accelerator: a.TOGGLE_FILTER_BAR.key,
        },
        {
          label: e.mainWSS.sidebarHidden
            ? l("Show Sidebar")
            : l("Hide Sidebar"),
          click: e.mainWSS.toggleSidebar,
          accelerator: a.TOGGLE_SIDEBAR.key,
        },
      ],
    },
    u = { label: s.APP_NAME, submenu: p },
    f = {
      label: y("File", "desktop menu title"),
      submenu: [
        {
          label: l("Open..."),
          accelerator: a.SEND_FILE.key,
          click: e.openFile,
        },
        {
          label: l("New Chat"),
          accelerator: a.CREATE_NEW_CHAT.key,
          click: e.showCreateNewChatMode,
        },
        { type: "separator" },
        { role: "close" },
        { label: l("Open Chat in New Window"), click: e.openChatInNewWindow },
      ],
    };
  return A.setMenuBar([u, f, { role: "editMenu" }, b, _, d]);
}
export { I as default };
//# sourceMappingURL=menubar-CmL8V5JB.js.map
