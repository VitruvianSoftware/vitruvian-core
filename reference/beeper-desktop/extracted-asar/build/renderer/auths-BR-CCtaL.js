import {
  dk as r,
  a3 as ne,
  cK as e,
  af as ie,
  aF as b,
  j as ae,
  bR as re,
  a6 as ce,
  bw as oe,
  er as M,
  dr as N,
  _ as le,
} from "./App-CsJiApxN.js";
import { a7 as de, a1 as he } from "./sentry-common-BxRELKId.js";
import { B as x, t as pe } from "./load-stores-B_4F31ws.js";
import { a2 as n } from "./matrix-util-Cr_UwXbj.js";
import "./index-Cw3pknxT.js";
import "./index-Dhe7xemD.js";
import "./index-CcYzEQCb.js";
import "./main-process-state-wkFhis-C.js";
import "./report-dialog-7bETf2vU.js";
import "./helpHubMessages-CXhGQ9cB.js";
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
    var s = new t.Error().stack;
    s &&
      ((t._sentryDebugIds = t._sentryDebugIds || {}),
      (t._sentryDebugIds[s] = "a88069a0-b671-472b-8a98-06c8c44021ec"),
      (t._sentryDebugIdIdentifier =
        "sentry-dbid-a88069a0-b671-472b-8a98-06c8c44021ec"));
  } catch {}
})();
const ue = "TabList-module__tablist",
  me = "TabList-module__tab",
  ge = "TabList-module__active",
  xe = "TabList-module__segmented",
  A = { tablist: ue, tab: me, active: ge, segmented: xe },
  $ = (t, s = !0) => {
    const [a, i] = r.useState(!1),
      [l, c] = r.useState(null),
      [d, o] = r.useState(null),
      p = r.useCallback(
        async (...m) => {
          (i(!0), c(null), o(null));
          try {
            const g = await t(...m);
            c(g);
          } catch (g) {
            o(g);
          } finally {
            i(!1);
          }
        },
        [t],
      );
    return (
      r.useEffect(() => {
        s && p();
      }, [p, s]),
      { execute: p, pending: a, value: l, error: d }
    );
  },
  je = (t) =>
    new Promise((s) => {
      setTimeout(s, t);
    }),
  S = ce ? "System Settings" : "System Preferences",
  fe = he.pathToFileURL(ae).href,
  z = de.join(fe, "imessage-auth.css"),
  L = (t) => {
    window.open("x-apple.systempreferences:com.apple.preference.security?" + t);
  },
  D = () => {
    L("Privacy_Contacts");
  },
  B = () => {
    L("Privacy_Accessibility");
  },
  R = () => {
    L("Privacy_Automation");
  },
  ve = {
    accessibility: "getAccessibilityAuthStatus",
    contacts: "getContactsAuthStatus",
    "full-disk-access": "getFullDiskAccessAuthStatus",
  },
  k = (t, s) => {
    const a = r.useCallback(
        () =>
          s === "messages-data"
            ? t("canAccessMessagesDir")
            : t(ve[s]).then((o) => o === "authorized"),
        [t, s],
      ),
      { execute: i, value: l, pending: c, error: d } = $(a);
    if (d) throw d;
    return (
      r.useEffect(
        () => (
          window.addEventListener("focus", i),
          () => window.removeEventListener("focus", i)
        ),
        [i],
      ),
      r.useEffect(() => {
        let o;
        async function p() {
          (await a()) ? i() : (o = setTimeout(p, 1e3));
        }
        return (p(), () => clearTimeout(o));
      }, []),
      console.log(s, "authorized", l),
      { refreshAuthorization: i, authorized: l, pending: c }
    );
  },
  ye = () =>
    e.jsxs("details", {
      open: !0,
      children: [
        e.jsx("summary", {
          children: e.jsx("h4", { children: "Setup Messages.app" }),
        }),
        e.jsxs("div", {
          className: "imessage-auth-well",
          children: [
            e.jsx("div", {
              children:
                "Messages.app isn't setup. Beeper requires Messages.app to be setup first to connect iMessage.",
            }),
            e.jsx("br", {}),
            e.jsx("div", {
              children: e.jsx("button", {
                className: "primary",
                onClick: () => window.open("imessage://"),
                children: "Open Messages.app",
              }),
            }),
          ],
        }),
      ],
    }),
  be = e.jsx("svg", {
    width: "1em",
    height: "1em",
    viewBox: "0 0 24 24",
    fill: "none",
    children: e.jsx("path", {
      d: "M20.285 2L9 13.567L3.714 8.556L0 12.272L9 21L24 5.715L20.285 2Z",
      fill: "white",
    }),
  }),
  Ae = e.jsx("svg", {
    width: "13",
    height: "13",
    viewBox: "0 0 13 13",
    fill: "none",
    children: e.jsx("path", {
      opacity: "0.498",
      d: "M6.10205 12.822C9.41205 12.822 12.1541 10.086 12.1541 6.76999C12.1541 3.45899 9.41195 0.71701 6.09595 0.71701C2.78595 0.71701 0.0489502 3.45899 0.0489502 6.76999C0.0489502 10.086 2.79105 12.822 6.10205 12.822ZM5.96704 7.98801C5.59204 7.98801 5.38696 7.807 5.38696 7.461V7.396C5.38696 6.84 5.70298 6.52901 6.13098 6.22501C6.65198 5.86701 6.90405 5.68 6.90405 5.293C6.90405 4.883 6.57598 4.59601 6.08398 4.59601C5.72098 4.59601 5.439 4.76601 5.229 5.10001L5.13501 5.229C5.07895 5.30847 5.0042 5.37292 4.91736 5.41669C4.83051 5.46046 4.73419 5.48222 4.63696 5.48001C4.57407 5.48135 4.51157 5.47005 4.45312 5.44678C4.39468 5.42351 4.34152 5.38875 4.29675 5.34454C4.25199 5.30034 4.21651 5.24757 4.1925 5.18942C4.1685 5.13127 4.15643 5.06892 4.15698 5.00601C4.15698 4.88901 4.17997 4.78899 4.21497 4.68399C4.40797 4.11499 5.11103 3.64099 6.16003 3.64099C7.24403 3.64099 8.15796 4.21501 8.15796 5.23401C8.15796 5.94401 7.76597 6.29401 7.16797 6.68201C6.76997 6.93901 6.55803 7.15001 6.53503 7.46701V7.53699C6.51803 7.78899 6.30104 7.98801 5.96704 7.98801V7.98801ZM5.95496 9.85199C5.56796 9.85199 5.23999 9.56399 5.23999 9.18399C5.23999 8.80299 5.56196 8.51001 5.95496 8.51001C6.35396 8.51001 6.67505 8.79699 6.67505 9.18399C6.67505 9.56999 6.34796 9.85199 5.95496 9.85199Z",
      fill: "currentColor",
    }),
  }),
  we = ({
    icon: t,
    title: s,
    info: a,
    subtitle: i,
    completed: l,
    action: c,
    more: d,
    showMore: o,
    Tooltip: p,
    children: m,
  }) =>
    e.jsxs("article", {
      children: [
        e.jsxs("div", {
          onClick: () => c(),
          className: "main",
          children: [
            t,
            e.jsxs("div", {
              className: "title",
              children: [
                s,
                e.jsx(p, {
                  position: "top",
                  tip: !1,
                  maxWidth: 420,
                  content: a,
                  children: e.jsx("span", {
                    className: "info-icon",
                    children: Ae,
                  }),
                }),
              ],
            }),
            i && e.jsx("div", { className: "subtitle", children: i }),
            e.jsx("div", {
              className: oe("check", { completed: l }),
              children: l && be,
            }),
          ],
        }),
        o && e.jsx("div", { className: "more", children: d }),
        m,
      ],
    }),
  Ce = (t) => {
    const { callProxiedFn: s } = t,
      [a, i] = r.useState(!1),
      l = r.useRef(!1),
      { authorized: c } = k(s, "contacts"),
      { authorized: d } = k(s, "accessibility"),
      { authorized: o, refreshAuthorization: p } = k(
        s,
        b ? "full-disk-access" : "messages-data",
      ),
      [m, g] = r.useState(!1),
      [H, Q] = r.useState(!1),
      [j, q] = r.useState(!1),
      K = r.useCallback(
        async () => o === !0 && s("isMessagesAppSetup"),
        [s, o],
      ),
      { execute: w, value: P, pending: _ } = $(K),
      W = o === !0 && !_ && P === !0;
    r.useEffect(
      () => (
        window.addEventListener("focus", w),
        () => window.removeEventListener("focus", w)
      ),
      [w],
    );
    const X = async () => {
        if (l.current) return D();
        (d && setTimeout(() => s("confirmUNCPrompt"), 1),
          await s("askForContactsAccess"),
          (l.current = !0));
      },
      F = () => s("askForFullDiskAccess"),
      Y = async () => {
        (await s("askForMessagesDirAccess"), await p());
      },
      J = async () => {
        if (H) return R();
        d && s("confirmUNCPrompt");
        try {
          const h = await s("askForAutomationAccess");
          (g(h), Q(!0));
        } catch (h) {
          (console.error(h),
            re.texts.Sentry.captureException(h),
            alert(`Something went wrong:

${h}`));
        }
      },
      ee = () => {
        (B(), d || s("startSysPrefsOnboarding"));
      },
      f = e.jsx("strong", { children: "Beeper Desktop" }),
      v = [
        {
          icon: e.jsxs("svg", {
            className: "icon",
            style: { translate: "0 1px" },
            viewBox: "0 0 16 16",
            height: "1em",
            width: "1em",
            children: [
              e.jsx("path", {
                d: "M8 4.143A1.071 1.071 0 1 0 8 2a1.071 1.071 0 0 0 0 2.143Zm-4.668 1.47 3.24.316v2.5l-.323 4.585A.383.383 0 0 0 7 13.14l.826-4.017c.045-.18.301-.18.346 0L9 13.139a.383.383 0 0 0 .752-.125L9.43 8.43v-2.5l3.239-.316a.38.38 0 0 0-.047-.756H3.379a.38.38 0 0 0-.047.756Z",
              }),
              e.jsx("path", {
                d: "M8 0a8 8 0 1 0 0 16A8 8 0 0 0 8 0ZM1 8a7 7 0 1 1 14 0A7 7 0 0 1 1 8Z",
              }),
            ],
          }),
          title: "Accessibility",
          completed: d ?? !1,
          action: ee,
          info: "To connect with iMessage, Beeper briefly takes control of the Messages app when necessary.",
          subtitle: "Also used to guide setup automatically.",
          more: e.jsxs("div", {
            onClick: B,
            children: [
              "Try adding ",
              f,
              " manually by clicking the + button and selecting it from your Applications folder →",
            ],
          }),
          showMore: j,
        },
        {
          icon: e.jsx("svg", {
            className: "icon",
            viewBox: "0 0 496 512",
            height: "1em",
            width: "1em",
            children: e.jsx("path", {
              d: "M248 104c-53 0-96 43-96 96s43 96 96 96 96-43 96-96-43-96-96-96zm0 144c-26.5 0-48-21.5-48-48s21.5-48 48-48 48 21.5 48 48-21.5 48-48 48zm0-240C111 8 0 119 0 256s111 248 248 248 248-111 248-248S385 8 248 8zm0 448c-49.7 0-95.1-18.3-130.1-48.4 14.9-23 40.4-38.6 69.6-39.5 20.8 6.4 40.6 9.6 60.5 9.6s39.7-3.1 60.5-9.6c29.2 1 54.7 16.5 69.6 39.5-35 30.1-80.4 48.4-130.1 48.4zm162.7-84.1c-24.4-31.4-62.1-51.9-105.1-51.9-10.2 0-26 9.6-57.6 9.6-31.5 0-47.4-9.6-57.6-9.6-42.9 0-80.6 20.5-105.1 51.9C61.9 339.2 48 299.2 48 256c0-110.3 89.7-200 200-200s200 89.7 200 200c0 43.2-13.9 83.2-37.3 115.9z",
            }),
          }),
          title: "Contacts",
          completed: c ?? !1,
          action: X,
          info: "Beeper can display names instead of phone numbers and email addresses.",
          more: e.jsxs("div", {
            onClick: D,
            children: [
              "Try opening ",
              S,
              " and manually checking ",
              f,
              " in the list →",
            ],
          }),
          showMore: j,
        },
        {
          icon: e.jsx("svg", {
            className: "icon",
            viewBox: "0 0 16 16",
            height: "1em",
            width: "1em",
            children: e.jsx("path", {
              d: "M4 7V5a4 4 0 0 1 8 0v2h1a1 1 0 0 1 1 1v7H2V8a1 1 0 0 1 1-1h1Zm2 0h4V5a2 2 0 1 0-4 0v2Z",
            }),
          }),
          title: b ? "Full Disk Access" : "Messages Data",
          completed: o ?? !1,
          action: b ? F : Y,
          info: b
            ? "Beeper needs Full Disk Access to read Messages data and attachments."
            : "To connect with iMessage, Beeper needs to be able to read your messages.",
          more: e.jsxs("div", {
            onClick: F,
            children: ["Try granting Full Disk Access to ", f, " in ", S, " →"],
          }),
          showMore: j,
        },
        {
          icon: e.jsx("svg", {
            className: "icon",
            viewBox: "0 0 16 16",
            height: "1em",
            width: "1em",
            children: e.jsx("path", {
              d: "M9.405 1.05c-.413-1.4-2.397-1.4-2.81 0l-.1.34a1.464 1.464 0 0 1-2.105.872l-.31-.17c-1.283-.698-2.686.705-1.987 1.987l.169.311c.446.82.023 1.841-.872 2.105l-.34.1c-1.4.413-1.4 2.397 0 2.81l.34.1a1.464 1.464 0 0 1 .872 2.105l-.17.31c-.698 1.283.705 2.686 1.987 1.987l.311-.169a1.464 1.464 0 0 1 2.105.872l.1.34c.413 1.4 2.397 1.4 2.81 0l.1-.34a1.464 1.464 0 0 1 2.105-.872l.31.17c1.283.698 2.686-.705 1.987-1.987l-.169-.311a1.464 1.464 0 0 1 .872-2.105l.34-.1c1.4-.413 1.4-2.397 0-2.81l-.34-.1a1.464 1.464 0 0 1-.872-2.105l.17-.31c.698-1.283-.705-2.686-1.987-1.987l-.311.169a1.464 1.464 0 0 1-2.105-.872l-.1-.34zM8 10.93a2.929 2.929 0 1 1 0-5.86 2.929 2.929 0 0 1 0 5.858z",
            }),
          }),
          title: "Automation",
          completed: m,
          action: J,
          info: "To connect with iMessage, Beeper briefly takes control of the Messages app when necessary.",
          more: e.jsxs("div", {
            onClick: R,
            children: [
              "Try opening ",
              S,
              " and manually checking ",
              f,
              " in the list →",
            ],
          }),
          showMore: j,
        },
      ],
      C = W && v.every((h) => h.completed),
      y = v.find((h) => !h.completed);
    (r.useEffect(() => {
      d && s("stopSysPrefsOnboarding");
    }, [d]),
      r.useEffect(() => {
        const h = (u) => {
          ["Enter", " ", "ArrowRight"].includes(u.key) &&
            (u.preventDefault(), y?.action());
        };
        return (
          window.addEventListener("keydown", h),
          () => window.removeEventListener("keydown", h)
        );
      }, [y]));
    const I = () => {
      (i(!0), a || t.login?.());
    };
    r.useEffect(() => {
      C && I();
    }, [C]);
    const se = async () => {
        const h = v.filter((u) => !u.completed);
        for (const u of h) (await u.action(), await je(50));
      },
      te = () => {
        const { Tooltip: h } = t;
        if (!h) throw new Error("Tooltip component required for ChecklistPage");
        return e.jsxs("div", {
          className: "fake-details permissions-section",
          children: [
            e.jsxs("div", {
              className: "fake-summary",
              children: [
                e.jsxs("h4", {
                  children: [
                    e.jsx("svg", {
                      fill: "currentColor",
                      viewBox: "0 0 448 512",
                      height: "1em",
                      width: "1em",
                      children: e.jsx("path", {
                        d: "M400 224h-24v-72C376 68.2 307.8 0 224 0S72 68.2 72 152v72H48c-26.5 0-48 21.5-48 48v192c0 26.5 21.5 48 48 48h352c26.5 0 48-21.5 48-48V272c0-26.5-21.5-48-48-48zm-104 0H152v-72c0-39.7 32.3-72 72-72s72 32.3 72 72v72z",
                      }),
                    }),
                    "Permissions",
                  ],
                }),
                !j &&
                  e.jsx("div", {
                    onClick: () => q(!0),
                    className: "show-more-button",
                    children: "Need help?",
                  }),
              ],
            }),
            e.jsx("div", {
              className: "imessage-auth-well",
              children: v.map((u) =>
                e.jsx(e.Fragment, {
                  children: e.jsx(
                    we,
                    {
                      ...u,
                      Tooltip: h,
                      children:
                        y === u &&
                        e.jsx("div", {
                          className: "authorize",
                          children: e.jsx("button", {
                            className: "primary",
                            onClick: d ? se : () => y.action(),
                            children: "Allow",
                          }),
                        }),
                    },
                    u.title,
                  ),
                }),
              ),
            }),
          ],
        });
      };
    return e.jsxs("div", {
      children: [
        o && !_ && P === !1 && e.jsx(ye, {}),
        C
          ? a
            ? "Adding..."
            : e.jsx("button", {
                className: "primary",
                onClick: I,
                children: "Add iMessage",
              })
          : te(),
      ],
    });
  },
  Se = (t) => {
    const { api: s } = t,
      a = r.useCallback(
        async (i) => {
          if (!s)
            throw new Error(
              `Couldn't call proxied function "${i}", API is falsy`,
            );
          return JSON.parse(await s.getAsset?.(void 0, "proxied", i));
        },
        [s],
      );
    return ne
      ? e.jsxs("div", {
          className: "auth imessage-auth styled-inputs",
          children: [
            e.jsx("link", { rel: "stylesheet", href: z }),
            e.jsx(Ce, { ...t, callProxiedFn: a }),
          ],
        })
      : e.jsxs("div", {
          className: "auth imessage-auth styled-inputs",
          children: [
            e.jsx("link", { rel: "stylesheet", href: z }),
            e.jsx("div", {
              className: "imessage-auth-well",
              children: e.jsxs("div", {
                children: [ie, ". Update your Mac to continue."],
              }),
            }),
          ],
        });
  },
  T = () =>
    e.jsxs(e.Fragment, {
      children: [
        e.jsx(x, {
          "data-sentry-element": "BridgeV2AuthComponent",
          "data-sentry-source-file": "auth.tsx",
        }),
        e.jsxs("footer", {
          children: [
            e.jsx("strong", {
              children: n("You are using a non-supported bridge."),
            }),
            " ",
            n("Connecting unofficial integrations may not work as expected."),
          ],
        }),
      ],
    }),
  V = () => {
    const {
        authProps: { loginState: t },
      } = M(),
      s = pe(t?.stepId, "instructions", t?.instructions);
    return e.jsx(x, {
      "data-sentry-element": "BridgeV2AuthComponent",
      "data-sentry-component": "AuthForm",
      "data-sentry-source-file": "auth.tsx",
      children: e.jsxs("div", {
        className: "login-steps",
        children: [
          e.jsxs("div", {
            children: [
              e.jsx("span", { children: "1" }),
              n("Open Messages by Google on your Android phone"),
            ],
          }),
          e.jsxs("div", {
            children: [
              e.jsx("span", { children: "2" }),
              n("Open the side menu"),
            ],
          }),
          e.jsxs("div", {
            children: [
              e.jsx("span", { children: "3" }),
              n('Click "Device pairing"'),
            ],
          }),
          e.jsxs("div", { children: [e.jsx("span", { children: "4" }), s] }),
        ],
      }),
    });
  },
  O = (...t) => t.filter(Boolean).join(" "),
  E = ({
    tabs: t,
    activeTab: s,
    onTabChange: a,
    variant: i = "underline",
    "aria-label": l = "Tab navigation",
  }) =>
    e.jsx("div", {
      role: "tablist",
      "aria-label": l,
      className: O(A.tablist, i === "segmented" && A.segmented),
      "data-sentry-component": "TabList",
      "data-sentry-source-file": "TabList.tsx",
      children: t.map((c) =>
        e.jsx(
          "button",
          {
            type: "button",
            role: "tab",
            "aria-selected": s === c.id,
            className: O(A.tab, s === c.id && A.active),
            onClick: () => a(c.id),
            children: c.label,
          },
          c.id,
        ),
      ),
    }),
  U = () => {
    const {
        authProps: { loginState: t },
      } = M(),
      [s, a] = r.useState("iphone"),
      i = t?.stepId === "fi.mau.telegram.login.show_qr",
      l = t?.stepId === "fi.mau.telegram.login.password.incorrect",
      c = [
        { id: "iphone", label: "iPhone" },
        { id: "android", label: "Android" },
      ],
      d = e.jsx(E, {
        variant: "segmented",
        tabs: c,
        activeTab: s,
        onTabChange: (p) => a(p),
        "aria-label": n("Device tabs"),
      }),
      o = e.jsxs("div", {
        children: [
          e.jsx("span", { children: "4" }),
          e.jsxs("div", {
            children: [
              e.jsx("div", { children: n("Scan the QR code") }),
              e.jsx("div", {
                className: "login-step-hint",
                children: n("Grant Telegram camera access if prompted"),
              }),
            ],
          }),
        ],
      });
    return e.jsxs(e.Fragment, {
      children: [
        e.jsx(x, {
          "data-sentry-element": "BridgeV2AuthComponent",
          "data-sentry-source-file": "auth.tsx",
          children:
            i &&
            e.jsxs("div", {
              className: "login-steps",
              children: [
                e.jsxs("div", {
                  children: [
                    e.jsx("span", { children: "1" }),
                    e.jsx("span", {
                      children: N(n("Open Telegram on your <device/>"), {
                        device: d,
                      }),
                    }),
                  ],
                }),
                s === "iphone" &&
                  e.jsxs(e.Fragment, {
                    children: [
                      e.jsxs("div", {
                        children: [
                          e.jsx("span", { children: "2" }),
                          n('Tap "Settings" in the bottom right → "Devices"'),
                        ],
                      }),
                      e.jsxs("div", {
                        children: [
                          e.jsx("span", { children: "3" }),
                          n('Tap "Link Desktop Device"'),
                        ],
                      }),
                      o,
                    ],
                  }),
                s === "android" &&
                  e.jsxs(e.Fragment, {
                    children: [
                      e.jsxs("div", {
                        children: [
                          e.jsx("span", { children: "2" }),
                          n('Tap the top left (☰) → "Settings"'),
                        ],
                      }),
                      e.jsxs("div", {
                        children: [
                          e.jsx("span", { children: "3" }),
                          n('Tap "Devices" → "Link Desktop Device"'),
                        ],
                      }),
                      o,
                    ],
                  }),
              ],
            }),
        }),
        l &&
          e.jsxs("div", {
            style: { padding: "0 16px", textAlign: "left" },
            children: [
              e.jsx("p", {
                style: { margin: "0 0 4px", fontSize: "12px" },
                children: n(
                  "If you've forgotten your password, reset it in Telegram:",
                ),
              }),
              e.jsxs("div", {
                className: "list",
                style: { textAlign: "left" },
                children: [
                  e.jsxs("div", {
                    children: [
                      e.jsx("span", { children: "1" }),
                      n("Open the Telegram app."),
                    ],
                  }),
                  e.jsxs("div", {
                    children: [
                      e.jsx("span", { children: "2" }),
                      n(
                        "Go to Settings → Privacy and Security → Two-Step Verification → Forgot Password.",
                      ),
                    ],
                  }),
                  e.jsxs("div", {
                    children: [
                      e.jsx("span", { children: "3" }),
                      n(
                        "Follow the prompts to reset your password, then return to Beeper.",
                      ),
                    ],
                  }),
                ],
              }),
            ],
          }),
      ],
    });
  },
  Z = () => {
    const [t, s] = r.useState("iphone"),
      a = [
        { id: "iphone", label: "iPhone" },
        { id: "android", label: "Android" },
      ],
      i = e.jsx(E, {
        variant: "segmented",
        tabs: a,
        activeTab: t,
        onTabChange: (c) => s(c),
        "aria-label": n("Device tabs"),
      }),
      l = e.jsxs("div", {
        children: [
          e.jsx("span", { children: "4" }),
          e.jsxs("div", {
            children: [
              e.jsx("div", { children: n("Scan the QR code") }),
              e.jsx("div", {
                className: "login-step-hint",
                children: n("Grant Signal camera access if prompted"),
              }),
            ],
          }),
        ],
      });
    return e.jsx(e.Fragment, {
      children: e.jsx(x, {
        "data-sentry-element": "BridgeV2AuthComponent",
        "data-sentry-source-file": "auth.tsx",
        children: e.jsxs("div", {
          className: "login-steps",
          children: [
            e.jsxs("div", {
              children: [
                e.jsx("span", { children: "1" }),
                e.jsx("span", {
                  children: N(n("Open Signal on your <device/>"), {
                    device: i,
                  }),
                }),
              ],
            }),
            t === "iphone" &&
              e.jsxs(e.Fragment, {
                children: [
                  e.jsxs("div", {
                    children: [
                      e.jsx("span", { children: "2" }),
                      n('Tap your profile in the top left → "Settings"'),
                    ],
                  }),
                  e.jsxs("div", {
                    children: [
                      e.jsx("span", { children: "3" }),
                      n('Tap "Linked Devices" → "Link a New Device"'),
                    ],
                  }),
                  l,
                ],
              }),
            t === "android" &&
              e.jsxs(e.Fragment, {
                children: [
                  e.jsxs("div", {
                    children: [
                      e.jsx("span", { children: "2" }),
                      n("Tap your profile in the top left"),
                    ],
                  }),
                  e.jsxs("div", {
                    children: [
                      e.jsx("span", { children: "3" }),
                      n('Tap "Linked Devices" → "Link a new Device"'),
                    ],
                  }),
                  l,
                ],
              }),
          ],
        }),
      }),
    });
  },
  G = () => {
    const {
        authProps: { loginState: t, loginStage: s },
      } = M(),
      [a, i] = r.useState("iphone"),
      l =
        s === "display-and-wait" &&
        (t?.stepId === "fi.mau.whatsapp.login.code" || !!t?.code),
      c = [
        { id: "iphone", label: "iPhone" },
        { id: "android", label: "Android" },
      ],
      d = e.jsx(E, {
        variant: "segmented",
        tabs: c,
        activeTab: a,
        onTabChange: (g) => i(g),
        "aria-label": n("Device tabs"),
      }),
      o = e.jsxs("div", {
        children: [
          e.jsx("span", { children: "4" }),
          e.jsxs("div", {
            children: [
              e.jsx("div", { children: n("Scan the QR code") }),
              e.jsx("div", {
                className: "login-step-hint",
                children: n("Grant WhatsApp camera access if prompted"),
              }),
            ],
          }),
        ],
      }),
      p = e.jsxs(e.Fragment, {
        children: [
          e.jsxs("div", {
            children: [
              e.jsx("span", { children: "4" }),
              n('Tap "Link with phone number instead"'),
            ],
          }),
          e.jsxs("div", {
            children: [
              e.jsx("span", { children: "5" }),
              n("Enter the code below"),
            ],
          }),
        ],
      }),
      m = l ? p : o;
    return e.jsx(e.Fragment, {
      children: e.jsx(x, {
        "data-sentry-element": "BridgeV2AuthComponent",
        "data-sentry-source-file": "auth.tsx",
        children: e.jsxs("div", {
          className: "login-steps",
          children: [
            e.jsxs("div", {
              children: [
                e.jsx("span", { children: "1" }),
                e.jsx("span", {
                  children: N(n("Open WhatsApp on your <device/>"), {
                    device: d,
                  }),
                }),
              ],
            }),
            a === "iphone" &&
              e.jsxs(e.Fragment, {
                children: [
                  e.jsxs("div", {
                    children: [
                      e.jsx("span", { children: "2" }),
                      n('Tap "Settings" in the bottom right'),
                    ],
                  }),
                  e.jsxs("div", {
                    children: [
                      e.jsx("span", { children: "3" }),
                      n('Tap "Linked Devices" → "Link device"'),
                    ],
                  }),
                  m,
                ],
              }),
            a === "android" &&
              e.jsxs(e.Fragment, {
                children: [
                  e.jsxs("div", {
                    children: [
                      e.jsx("span", { children: "2" }),
                      n("Tap the menu (⋮) in the top right"),
                    ],
                  }),
                  e.jsxs("div", {
                    children: [
                      e.jsx("span", { children: "3" }),
                      n('Tap "Linked devices" → "Link a device"'),
                    ],
                  }),
                  m,
                ],
              }),
          ],
        }),
      }),
    });
  },
  ke = () =>
    e.jsxs(e.Fragment, {
      children: [
        e.jsx(x, {
          "data-sentry-element": "BridgeV2AuthComponent",
          "data-sentry-source-file": "auth.tsx",
        }),
        e.jsxs("footer", {
          children: [
            e.jsx("strong", {
              children: n("Bluesky integration is still work in progress."),
            }),
            " ",
            n("It might not work as expected."),
          ],
        }),
      ],
    }),
  De = {
    imessage: Se,
    [le]: T,
    "bridge-whatsapp": G,
    "bridge-telegram": U,
    "bridge-signal": Z,
    "bridge-gmessages": V,
    "bridge-local-signal": Z,
    "bridge-local-whatsapp": G,
    "bridge-local-telegram": U,
    "bridge-local-gmessages": V,
    "bridge-ai": T,
    "bridge-local-bluesky": ke,
    "bridge-local-dummy": T,
  };
export { De as default };
//# sourceMappingURL=auths-BR-CCtaL.js.map
