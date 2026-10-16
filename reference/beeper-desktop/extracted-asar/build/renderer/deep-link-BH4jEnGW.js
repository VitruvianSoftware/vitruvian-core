const __vite__mapDeps = (
  i,
  m = __vite__mapDeps,
  d = m.f ||
    (m.f = [
      "./load-stores-B_4F31ws.js",
      "./matrix-util-Cr_UwXbj.js",
      "./sentry-common-BxRELKId.js",
      "./index-Cw3pknxT.js",
      "./main-process-state-wkFhis-C.js",
      "./index-Dhe7xemD.js",
      "./index-CcYzEQCb.js",
      "./App-CsJiApxN.js",
      "./report-dialog-7bETf2vU.js",
      "./helpHubMessages-CXhGQ9cB.js",
      "./App-BKmiiN0s.css",
      "./load-stores-B2Yvv-OZ.css",
    ]),
) => i.map((i) => d[i]);
import { _ as D } from "./index-CcYzEQCb.js";
import {
  ac as y,
  cD as e,
  K as E,
  bI as P,
  a2 as S,
  b9 as k,
  cb as _,
  cX as N,
  cN as W,
  h as R,
  e as O,
} from "./matrix-util-Cr_UwXbj.js";
import { b as v } from "./index-Dhe7xemD.js";
import { D as T } from "./sentry-common-BxRELKId.js";
import "./index-Cw3pknxT.js";
import "./main-process-state-wkFhis-C.js";
(function () {
  try {
    var t =
      typeof window < "u"
        ? window
        : typeof global < "u"
          ? global
          : typeof globalThis < "u"
            ? globalThis
            : typeof self < "u"
              ? self
              : {};
    t.SENTRY_RELEASE = { id: "4.3.209" };
    var r = new t.Error().stack;
    r &&
      ((t._sentryDebugIds = t._sentryDebugIds || {}),
      (t._sentryDebugIds[r] = "d5079c63-2be0-4569-8b47-08f1eb7667b1"),
      (t._sentryDebugIdIdentifier =
        "sentry-dbid-d5079c63-2be0-4569-8b47-08f1eb7667b1"));
  } catch {}
})();
function C(t) {
  const r = t.slice(T.length),
    a = r.indexOf("?"),
    o = a === -1 ? r : r.slice(0, a),
    s =
      a === -1
        ? {}
        : Object.fromEntries(new URLSearchParams(r.slice(a + 1)).entries()),
    d = o.split("/");
  return {
    query: s,
    parts: d[0] === "join-matrix-room" ? d : d.map(decodeURIComponent),
  };
}
async function L({
  platform: t,
  account: r,
  parts: a,
  text: o,
  attachmentPath: s,
}) {
  const [, , d, i] = a;
  let c;
  switch (d) {
    case "id":
      c = (await r.createThreadWithID(i, e.mainWSS)) ?? null;
      break;
    case "username":
      c = (await r.createThreadWithUsername(i, e.mainWSS)) ?? null;
      break;
    case "email":
      c = (await r.createThreadWithEmail(i, e.mainWSS)) ?? null;
      break;
    case "phone":
      c = (await r.createThreadWithPhoneNumber(i, e.mainWSS)) ?? null;
      break;
  }
  if (!c) {
    e.addToast(
      { text: `Could not compose ${t.displayName} chat` },
      void 0,
      void 0,
      !0,
    );
    return;
  }
  const m = c.unionThread ?? c;
  (e.mainWSS.setSelectedThread(c),
    o != null && m.setTypedPlainText(o, { propagate: !0 }),
    s && m.attachFiles([{ filePath: s }]));
}
function x(t, r) {
  for (const a of t) {
    const o = r(a);
    if (o) return o;
  }
}
function M(t) {
  const r = t.replaceAll("-", "+").replaceAll("_", "/"),
    a = (4 - (r.length % 4)) % 4;
  return r + "=".repeat(a);
}
const j = {
  facebook: "messenger",
  twitter: "cookies",
  instagram: "instagram",
  slack: "token",
  discord: "token",
};
async function A(t, r) {
  const a = N(),
    o = e.addAccountStore.addableNetworks.find((i) => i.network === t);
  if (!o) {
    e.addToast({ text: `Platform ${t} not found` }, -1, a, !0);
    return;
  }
  const s = o.connectPlatform;
  if (!s) {
    if (o.isUpgradable) {
      e.subscriptionStore.openSubscriptionInfo({
        source: "Add Account",
        deprecatedTrigger: "max-account-per-bridge-upgrade",
      });
      return;
    }
    e.addToast(
      {
        text: W(
          S("You can’t connect another %s account right now."),
          o.platform.displayName,
        ),
      },
      -1,
      a,
      !0,
    );
    return;
  }
  let d;
  try {
    const i = R.from(M(r), "base64").toString();
    if (((d = JSON.parse(i).fields), !d))
      throw Error("Login tokens are missing");
  } catch (i) {
    (Sentry.captureException(i),
      e.addToast(
        {
          text: `Error parsing login data: ${i instanceof Error ? i.message : String(i)}`,
        },
        -1,
        a,
        !0,
      ));
    return;
  }
  e.addAccountStore.openNewAccountInNewWindow(s, !1, {
    fields: d,
    loginFlowID: j[t],
  });
}
async function $(t) {
  if (t === T || !t.startsWith(T)) return;
  const { loadStoresPromise: r } = await D(
    async () => {
      const { loadStoresPromise: n } =
        await import("./load-stores-B_4F31ws.js").then((f) => f.l);
      return { loadStoresPromise: n };
    },
    __vite__mapDeps([0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11]),
    import.meta.url,
  );
  if (
    (await r,
    v && logger.log("deep link", t),
    y.showMainWindow(),
    t.startsWith(`${T}auth`))
  ) {
    const n = decodeURIComponent(t.split("?token=").pop());
    e.beeperClientStore.login({ jwtToken: n });
    return;
  }
  const { parts: a, query: o } = C(t),
    s = typeof o.text == "string" ? o.text : void 0,
    d = typeof o.attachmentPath == "string" ? o.attachmentPath : void 0,
    i = typeof o.accountID == "string" ? o.accountID : void 0,
    c = o.accountID ? e.accountsStore.getAccount(i) : void 0;
  if (!a) return;
  v && logger.log(a);
  const [m, u, ...I] = a,
    h = u && Object.hasOwn(e.platformStore.platforms, u) ? u : `bridge-${u}`;
  switch (m) {
    case "refresh-user":
      e.refreshUser();
      return;
    case "fill-textarea":
      (s != null &&
        e.mainWSS.selectedThread?.setTypedPlainText(s, { propagate: !0 }),
        e.mainWSS.focusMessageInput());
      return;
    case "join-matrix-room": {
      if (!u) {
        e.addToast(
          { text: S("No Matrix room ID was provided in the link.") },
          void 0,
          void 0,
          !0,
        );
        return;
      }
      let n;
      try {
        n = decodeURIComponent(u);
      } catch {
        e.addToast(
          { text: S("The link contains an invalid Matrix room ID.") },
          void 0,
          void 0,
          !0,
        );
        return;
      }
      await _(n, O, !1);
      return;
    }
    case "platform-callback": {
      const n = u,
        f = e.accountsStore.getAccount(n);
      if (!f) {
        e.addToast({ text: "Could not find the account" }, void 0, void 0, !0);
        return;
      }
      const [l, p] = I;
      try {
        await f.api.handleDeepLink?.(t);
      } catch (b) {
        if (l !== "join-room") throw b;
        (console.warn("Failed to join Matrix room from deep link", b),
          P(b)
            ? (e.addToast(
                {
                  text: S(
                    "You are no longer invited to this chat or it no longer exists.",
                  ),
                },
                void 0,
                `joinRoomByID-failure-${p}`,
              ),
              p && (await e.bapi.deletePendingInvite(p)))
            : e.addToast(
                { text: k({ status: "join-failed" }) },
                void 0,
                void 0,
                !0,
              ));
      }
      return;
    }
    case "subscriptions":
      e.subscriptionStore.handleDeepLink(t);
      break;
    case "otp":
      e.beeperClientStore.setOneTimePassword(u);
      return;
    case "focus": {
      y.stealFocus();
      const n = typeof o.windowID == "string" ? o.windowID : "main";
      y.focusWindow(n);
      return;
    }
    case "connect": {
      e.windowsStore.openPrefsInNewWindow(e.mainWSS, E.PREFS_BEEPER_CONNECT);
      return;
    }
    case "bridgev2-login":
      A(u, I.join("/"));
      return;
  }
  if (!h) {
    (e.addToast({ text: "Invalid deep link" }, void 0, void 0, !0),
      logger.warn("missing platformName", h));
    return;
  }
  const g = e.platformStore.platforms[h];
  if (!g) {
    (e.addToast({ text: "Invalid deep link" }, void 0, void 0, !0),
      logger.warn("unknown platform", h));
    return;
  }
  const w = e.accountsStore.findPlatforms(h);
  if (!w.length) {
    e.addToast(
      { text: `Could not find any ${g.displayName} accounts` },
      void 0,
      void 0,
      !0,
    );
    return;
  }
  switch (m) {
    case "compose":
      L({ platform: g, account: w[0], parts: a, text: s, attachmentPath: d });
      return;
    case "select-thread": {
      const [, , n, f] = a,
        l = c?.getThread(n) ?? x(w, (b) => b.getThread(n));
      if (!l) {
        e.addToast(
          { text: `Could not find ${g.displayName} thread` },
          void 0,
          void 0,
          !0,
        );
        return;
      }
      const p = l.unionThread ?? l;
      (e.mainWSS.setSelectedThread(l, {
        sortKey: f,
        sortKeyRoomID: n,
        selectMessage: !0,
      }),
        s != null && p.setTypedPlainText(s, { propagate: !0 }),
        d && p.attachFiles([{ filePath: d }]));
      return;
    }
    case "highlight-message": {
      const [, , n, f] = a,
        l = c?.getThread(n) ?? x(w, (p) => p.getThread(n));
      if (!l) {
        e.addToast(
          { text: `Could not find ${g.displayName} thread` },
          void 0,
          void 0,
          !0,
        );
        return;
      }
      (e.mainWSS.setSelectedThread(l), l.selectMessageByID(f));
      return;
    }
    default:
      e.addToast(
        { text: `Unrecognized deep link: ${t}` },
        void 0,
        void 0,
        !0,
        t,
      );
  }
}
globalThis.handleDeepLink = $;
export { $ as default };
//# sourceMappingURL=deep-link-BH4jEnGW.js.map
