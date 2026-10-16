const __vite__mapDeps = (
  i,
  m = __vite__mapDeps,
  d = m.f ||
    (m.f = [
      "./load-stores-BlYvfTx9.js",
      "./matrix-util-8DbIGEm-.js",
      "./sentry-common-BNqrY_yc.js",
      "./index-Cw3pknxT.js",
      "./main-process-state-BDOn7dvV.js",
      "./index-5FBEE1WD.js",
      "./index-Ch31Akxs.js",
      "./App-BHgTsVmv.js",
      "./report-dialog-C-g_klPx.js",
      "./App-9NsBNeXQ.css",
      "./load-stores-B2Yvv-OZ.css",
    ]),
) => i.map((i) => d[i]);
import { _ as D } from "./index-5FBEE1WD.js";
import {
  ab as y,
  cA as e,
  J as E,
  bE as P,
  a1 as b,
  b8 as k,
  c7 as _,
  cU as W,
  cK as N,
  h as R,
  e as O,
} from "./matrix-util-8DbIGEm-.js";
import { b as v } from "./index-Ch31Akxs.js";
import { D as T } from "./sentry-common-BNqrY_yc.js";
import "./index-Cw3pknxT.js";
import "./main-process-state-BDOn7dvV.js";
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
      (t._sentryDebugIds[r] = "996a3f5c-ed05-4b8a-a86a-99e3759adf9f"),
      (t._sentryDebugIdIdentifier =
        "sentry-dbid-996a3f5c-ed05-4b8a-a86a-99e3759adf9f"));
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
function A(t) {
  const r = t.replaceAll("-", "+").replaceAll("_", "/"),
    a = (4 - (r.length % 4)) % 4;
  return r + "=".repeat(a);
}
const M = {
  facebook: "messenger",
  twitter: "cookies",
  instagram: "instagram",
  slack: "token",
  discord: "token",
};
async function j(t, r) {
  const a = W(),
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
        text: N(
          b("You can’t connect another %s account right now."),
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
    const i = R.from(A(r), "base64").toString();
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
    loginFlowID: M[t],
  });
}
async function U(t) {
  if (t === T || !t.startsWith(T)) return;
  const { loadStoresPromise: r } = await D(
    async () => {
      const { loadStoresPromise: n } =
        await import("./load-stores-BlYvfTx9.js").then((f) => f.l);
      return { loadStoresPromise: n };
    },
    __vite__mapDeps([0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10]),
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
          { text: b("No Matrix room ID was provided in the link.") },
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
          { text: b("The link contains an invalid Matrix room ID.") },
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
      } catch (w) {
        if (l !== "join-room") throw w;
        (console.warn("Failed to join Matrix room from deep link", w),
          P(w)
            ? (e.addToast(
                {
                  text: b(
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
      j(u, I.join("/"));
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
  const S = e.accountsStore.findPlatforms(h);
  if (!S.length) {
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
      L({ platform: g, account: S[0], parts: a, text: s, attachmentPath: d });
      return;
    case "select-thread": {
      const [, , n, f] = a,
        l = c?.getThread(n) ?? x(S, (w) => w.getThread(n));
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
        l = c?.getThread(n) ?? x(S, (p) => p.getThread(n));
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
globalThis.handleDeepLink = U;
export { U as default };
//# sourceMappingURL=deep-link-BFauSXrQ.js.map
