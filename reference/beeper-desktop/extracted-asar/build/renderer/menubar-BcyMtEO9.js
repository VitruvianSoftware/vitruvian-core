import { cL as a, al as r } from "./App-CsJiApxN.js";
import "./sentry-common-BxRELKId.js";
import { e as s } from "./index-Dhe7xemD.js";
import {
  c9 as m,
  ce as k,
  cd as w,
  a2 as l,
  cN as c,
  K as o,
  ac as E,
  a6 as y,
  ad as A,
} from "./matrix-util-Cr_UwXbj.js";
import { D as _ } from "./load-stores-B_4F31ws.js";
import "./index-Cw3pknxT.js";
import "./index-CcYzEQCb.js";
import "./main-process-state-wkFhis-C.js";
import "./report-dialog-7bETf2vU.js";
import "./helpHubMessages-CXhGQ9cB.js";
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
      (e._sentryDebugIds[i] = "844d4854-f04e-4259-afce-dca327dc28a4"),
      (e._sentryDebugIdIdentifier =
        "sentry-dbid-844d4854-f04e-4259-afce-dca327dc28a4"));
  } catch {}
})();
const h = {
  role: "windowMenu",
  submenu: [
    { role: "togglefullscreen" },
    { role: "zoom" },
    { role: "minimize" },
    { role: "front" },
  ],
};
function W(e) {
  const i = [
    { role: "toggleDevTools", visible: !1 },
    {
      label: l("Report a Problem"),
      accelerator: a.REPORT_A_PROBLEM.key,
      click: () => e.focusedWSS?.setVisibleModal(r.REPORT_PROBLEM),
    },
    { label: c(l("Open %s Help"), s.APP_NAME), click: m },
    { type: "separator" },
    { label: c(l("Open %s"), "Beeper.com"), click: k },
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
    t = n === _ ? l("Check for Updates…") : n,
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
    u = {
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
    b = { label: s.APP_NAME, submenu: p },
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
  return A.setMenuBar([b, f, { role: "editMenu" }, u, h, d]);
}
export { W as default };
//# sourceMappingURL=menubar-BcyMtEO9.js.map
