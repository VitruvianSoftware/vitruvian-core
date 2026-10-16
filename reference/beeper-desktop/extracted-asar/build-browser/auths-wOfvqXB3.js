import { cF as e, ek as g, de as j, dk as m, Z as w } from "./App-BHgTsVmv.js";
import { B as c, t as k } from "./load-stores-BlYvfTx9.js";
import { a1 as s } from "./matrix-util-8DbIGEm-.js";
import "./sentry-common-BNqrY_yc.js";
import "./index-Cw3pknxT.js";
import "./index-Ch31Akxs.js";
import "./index-5FBEE1WD.js";
import "./main-process-state-BDOn7dvV.js";
import "./report-dialog-C-g_klPx.js";
(function () {
  try {
    var n =
      typeof window < "u"
        ? window
        : typeof global < "u"
          ? global
          : typeof globalThis < "u"
            ? globalThis
            : typeof self < "u"
              ? self
              : {};
    n.SENTRY_RELEASE = { id: "4.3.209" };
    var i = new n.Error().stack;
    i &&
      ((n._sentryDebugIds = n._sentryDebugIds || {}),
      (n._sentryDebugIds[i] = "55dd211d-11fc-4c1e-909d-0c68a64a0467"),
      (n._sentryDebugIdIdentifier =
        "sentry-dbid-55dd211d-11fc-4c1e-909d-0c68a64a0467"));
  } catch {}
})();
const F = "_tablist_f0q5u_1",
  _ = "_tab_f0q5u_1",
  D = "_active_f0q5u_36",
  L = "_segmented_f0q5u_53",
  l = { tablist: F, tab: _, active: D, segmented: L },
  C = {},
  x = () =>
    e.jsxs(e.Fragment, {
      children: [
        e.jsx(c, {
          "data-sentry-element": "BridgeV2AuthComponent",
          "data-sentry-source-file": "auth.tsx",
        }),
        e.jsxs("footer", {
          children: [
            e.jsx("strong", {
              children: s("You are using a non-supported bridge."),
            }),
            " ",
            s("Connecting unofficial integrations may not work as expected."),
          ],
        }),
      ],
    }),
  b = () => {
    const {
        authProps: { loginState: n },
      } = g(),
      i = k(n?.stepId, "instructions", n?.instructions);
    return e.jsx(c, {
      "data-sentry-element": "BridgeV2AuthComponent",
      "data-sentry-component": "AuthForm",
      "data-sentry-source-file": "auth.tsx",
      children: e.jsxs("div", {
        className: "login-steps",
        children: [
          e.jsxs("div", {
            children: [
              e.jsx("span", { children: "1" }),
              s("Open Messages by Google on your Android phone"),
            ],
          }),
          e.jsxs("div", {
            children: [
              e.jsx("span", { children: "2" }),
              s("Open the side menu"),
            ],
          }),
          e.jsxs("div", {
            children: [
              e.jsx("span", { children: "3" }),
              s('Click "Device pairing"'),
            ],
          }),
          e.jsxs("div", { children: [e.jsx("span", { children: "4" }), i] }),
        ],
      }),
    });
  },
  f = (...n) => n.filter(Boolean).join(" "),
  u = ({
    tabs: n,
    activeTab: i,
    onTabChange: a,
    variant: d = "underline",
    "aria-label": r = "Tab navigation",
  }) =>
    e.jsx("div", {
      role: "tablist",
      "aria-label": r,
      className: f(l.tablist, d === "segmented" && l.segmented),
      "data-sentry-component": "TabList",
      "data-sentry-source-file": "TabList.tsx",
      children: n.map((t) =>
        e.jsx(
          "button",
          {
            type: "button",
            role: "tab",
            "aria-selected": i === t.id,
            className: f(l.tab, i === t.id && l.active),
            onClick: () => a(t.id),
            children: t.label,
          },
          t.id,
        ),
      ),
    }),
  y = () => {
    const {
        authProps: { loginState: n },
      } = g(),
      [i, a] = j.useState("iphone"),
      d = n?.stepId === "fi.mau.telegram.login.show_qr",
      r = n?.stepId === "fi.mau.telegram.login.password.incorrect",
      t = [
        { id: "iphone", label: "iPhone" },
        { id: "android", label: "Android" },
      ],
      h = e.jsx(u, {
        variant: "segmented",
        tabs: t,
        activeTab: i,
        onTabChange: (p) => a(p),
        "aria-label": s("Device tabs"),
      }),
      o = e.jsxs("div", {
        children: [
          e.jsx("span", { children: "4" }),
          e.jsxs("div", {
            children: [
              e.jsx("div", { children: s("Scan the QR code") }),
              e.jsx("div", {
                className: "login-step-hint",
                children: s("Grant Telegram camera access if prompted"),
              }),
            ],
          }),
        ],
      });
    return e.jsxs(e.Fragment, {
      children: [
        e.jsx(c, {
          "data-sentry-element": "BridgeV2AuthComponent",
          "data-sentry-source-file": "auth.tsx",
          children:
            d &&
            e.jsxs("div", {
              className: "login-steps",
              children: [
                e.jsxs("div", {
                  children: [
                    e.jsx("span", { children: "1" }),
                    e.jsx("span", {
                      children: m(s("Open Telegram on your <device/>"), {
                        device: h,
                      }),
                    }),
                  ],
                }),
                i === "iphone" &&
                  e.jsxs(e.Fragment, {
                    children: [
                      e.jsxs("div", {
                        children: [
                          e.jsx("span", { children: "2" }),
                          s('Tap "Settings" in the bottom right → "Devices"'),
                        ],
                      }),
                      e.jsxs("div", {
                        children: [
                          e.jsx("span", { children: "3" }),
                          s('Tap "Link Desktop Device"'),
                        ],
                      }),
                      o,
                    ],
                  }),
                i === "android" &&
                  e.jsxs(e.Fragment, {
                    children: [
                      e.jsxs("div", {
                        children: [
                          e.jsx("span", { children: "2" }),
                          s('Tap the top left (☰) → "Settings"'),
                        ],
                      }),
                      e.jsxs("div", {
                        children: [
                          e.jsx("span", { children: "3" }),
                          s('Tap "Devices" → "Link Desktop Device"'),
                        ],
                      }),
                      o,
                    ],
                  }),
              ],
            }),
        }),
        r &&
          e.jsxs("div", {
            style: { padding: "0 16px", textAlign: "left" },
            children: [
              e.jsx("p", {
                style: { margin: "0 0 4px", fontSize: "12px" },
                children: s(
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
                      s("Open the Telegram app."),
                    ],
                  }),
                  e.jsxs("div", {
                    children: [
                      e.jsx("span", { children: "2" }),
                      s(
                        "Go to Settings → Privacy and Security → Two-Step Verification → Forgot Password.",
                      ),
                    ],
                  }),
                  e.jsxs("div", {
                    children: [
                      e.jsx("span", { children: "3" }),
                      s(
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
  T = () => {
    const [n, i] = j.useState("iphone"),
      a = [
        { id: "iphone", label: "iPhone" },
        { id: "android", label: "Android" },
      ],
      d = e.jsx(u, {
        variant: "segmented",
        tabs: a,
        activeTab: n,
        onTabChange: (t) => i(t),
        "aria-label": s("Device tabs"),
      }),
      r = e.jsxs("div", {
        children: [
          e.jsx("span", { children: "4" }),
          e.jsxs("div", {
            children: [
              e.jsx("div", { children: s("Scan the QR code") }),
              e.jsx("div", {
                className: "login-step-hint",
                children: s("Grant Signal camera access if prompted"),
              }),
            ],
          }),
        ],
      });
    return e.jsx(e.Fragment, {
      children: e.jsx(c, {
        "data-sentry-element": "BridgeV2AuthComponent",
        "data-sentry-source-file": "auth.tsx",
        children: e.jsxs("div", {
          className: "login-steps",
          children: [
            e.jsxs("div", {
              children: [
                e.jsx("span", { children: "1" }),
                e.jsx("span", {
                  children: m(s("Open Signal on your <device/>"), {
                    device: d,
                  }),
                }),
              ],
            }),
            n === "iphone" &&
              e.jsxs(e.Fragment, {
                children: [
                  e.jsxs("div", {
                    children: [
                      e.jsx("span", { children: "2" }),
                      s('Tap your profile in the top left → "Settings"'),
                    ],
                  }),
                  e.jsxs("div", {
                    children: [
                      e.jsx("span", { children: "3" }),
                      s('Tap "Linked Devices" → "Link a New Device"'),
                    ],
                  }),
                  r,
                ],
              }),
            n === "android" &&
              e.jsxs(e.Fragment, {
                children: [
                  e.jsxs("div", {
                    children: [
                      e.jsx("span", { children: "2" }),
                      s("Tap your profile in the top left"),
                    ],
                  }),
                  e.jsxs("div", {
                    children: [
                      e.jsx("span", { children: "3" }),
                      s('Tap "Linked Devices" → "Link a new Device"'),
                    ],
                  }),
                  r,
                ],
              }),
          ],
        }),
      }),
    });
  },
  A = () => {
    const {
        authProps: { loginState: n, loginStage: i },
      } = g(),
      [a, d] = j.useState("iphone"),
      r =
        i === "display-and-wait" &&
        (n?.stepId === "fi.mau.whatsapp.login.code" || !!n?.code),
      t = [
        { id: "iphone", label: "iPhone" },
        { id: "android", label: "Android" },
      ],
      h = e.jsx(u, {
        variant: "segmented",
        tabs: t,
        activeTab: a,
        onTabChange: (S) => d(S),
        "aria-label": s("Device tabs"),
      }),
      o = e.jsxs("div", {
        children: [
          e.jsx("span", { children: "4" }),
          e.jsxs("div", {
            children: [
              e.jsx("div", { children: s("Scan the QR code") }),
              e.jsx("div", {
                className: "login-step-hint",
                children: s("Grant WhatsApp camera access if prompted"),
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
              s('Tap "Link with phone number instead"'),
            ],
          }),
          e.jsxs("div", {
            children: [
              e.jsx("span", { children: "5" }),
              s("Enter the code below"),
            ],
          }),
        ],
      }),
      v = r ? p : o;
    return e.jsx(e.Fragment, {
      children: e.jsx(c, {
        "data-sentry-element": "BridgeV2AuthComponent",
        "data-sentry-source-file": "auth.tsx",
        children: e.jsxs("div", {
          className: "login-steps",
          children: [
            e.jsxs("div", {
              children: [
                e.jsx("span", { children: "1" }),
                e.jsx("span", {
                  children: m(s("Open WhatsApp on your <device/>"), {
                    device: h,
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
                      s('Tap "Settings" in the bottom right'),
                    ],
                  }),
                  e.jsxs("div", {
                    children: [
                      e.jsx("span", { children: "3" }),
                      s('Tap "Linked Devices" → "Link device"'),
                    ],
                  }),
                  v,
                ],
              }),
            a === "android" &&
              e.jsxs(e.Fragment, {
                children: [
                  e.jsxs("div", {
                    children: [
                      e.jsx("span", { children: "2" }),
                      s("Tap the menu (⋮) in the top right"),
                    ],
                  }),
                  e.jsxs("div", {
                    children: [
                      e.jsx("span", { children: "3" }),
                      s('Tap "Linked devices" → "Link a device"'),
                    ],
                  }),
                  v,
                ],
              }),
          ],
        }),
      }),
    });
  },
  I = () =>
    e.jsxs(e.Fragment, {
      children: [
        e.jsx(c, {
          "data-sentry-element": "BridgeV2AuthComponent",
          "data-sentry-source-file": "auth.tsx",
        }),
        e.jsxs("footer", {
          children: [
            e.jsx("strong", {
              children: s("Bluesky integration is still work in progress."),
            }),
            " ",
            s("It might not work as expected."),
          ],
        }),
      ],
    }),
  $ = {
    imessage: C,
    [w]: x,
    "bridge-whatsapp": A,
    "bridge-telegram": y,
    "bridge-signal": T,
    "bridge-gmessages": b,
    "bridge-local-signal": T,
    "bridge-local-whatsapp": A,
    "bridge-local-telegram": y,
    "bridge-local-gmessages": b,
    "bridge-ai": x,
    "bridge-local-bluesky": I,
    "bridge-local-dummy": x,
  };
export { $ as default };
//# sourceMappingURL=auths-wOfvqXB3.js.map
