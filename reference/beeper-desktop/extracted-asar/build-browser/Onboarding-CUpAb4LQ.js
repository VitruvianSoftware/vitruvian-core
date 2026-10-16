import {
  cT as g,
  de as r,
  eq as E,
  cF as e,
  br as h,
  bR as _,
  b5 as C,
  aj as S,
  cj as f,
  cG as i,
  aX as T,
} from "./App-BHgTsVmv.js";
import {
  a5 as x,
  cX as P,
  a1 as c,
  cK as y,
  cA as H,
} from "./matrix-util-8DbIGEm-.js";
import { e as v } from "./index-Ch31Akxs.js";
import "./sentry-common-BNqrY_yc.js";
import "./index-Cw3pknxT.js";
import "./index-5FBEE1WD.js";
import "./main-process-state-BDOn7dvV.js";
import "./report-dialog-C-g_klPx.js";
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
      (s._sentryDebugIds[t] = "90d444f4-1ab2-491e-b9bc-3a0ae1bbc100"),
      (s._sentryDebugIdIdentifier =
        "sentry-dbid-90d444f4-1ab2-491e-b9bc-3a0ae1bbc100"));
  } catch {}
})();
const B = g(({ className: s, pages: t, onEnd: n }) => {
    const [a, o] = r.useState(0),
      [l, m] = r.useState(!1),
      {
        Component: u,
        continueButton: d,
        afterLeaveCallback: p,
        onNext: j,
      } = t[a],
      N = r.useCallback(() => o((A) => Math.max(0, A - 1)), []),
      k = r.useCallback(() => {
        (m(!0),
          setTimeout(() => {
            (m(!1),
              p?.(),
              j?.(),
              a === t.length - 1 ? n() : o(Math.min(t.length - 1, a + 1)));
          }, 250));
      }, [a, p, n, j, t.length]);
    return (
      E("right", k, "onboarding-sidebar"),
      E("left", N, "onboarding-sidebar"),
      e.jsxs("div", {
        className: h("onboarding-sidebar cursor-default", s),
        children: [
          e.jsx("div", {
            className: h("sidebar-content", { fading: l }),
            children: e.jsx(u, { selectPrevPage: N, selectNextPage: k }),
          }),
          d !== !1 &&
            e.jsx("div", {
              className: "buttons",
              children: e.jsx("button", {
                type: "button",
                disabled: l,
                className: h("btn-solid btn-solid-md btn-solid-primary", {
                  initial: a === 0,
                }),
                onClick: k,
                children:
                  typeof d == "string" ? d : x("Continue →", "button label"),
              }),
            }),
          e.jsxs("div", {
            className: "onboarding-progress",
            children: [
              e.jsx("div", {
                className: "progress-bar-container",
                children: e.jsx("div", {
                  className: "progress-bar",
                  style: { width: `${((a + 1) / t.length) * 100}%` },
                }),
              }),
              e.jsx("button", {
                type: "button",
                onClick: () =>
                  P(() => {}, {
                    title: c("Are you sure you want to skip?"),
                    subtitle: c(
                      "It only takes a couple of seconds and you won't get the most out of the app if you skip.",
                    ),
                    confirmButtonText: x("Don't Skip", "button label"),
                    cancelButtonText: x("Skip", "button label"),
                    onCancel: n,
                  }),
                className: "progress-button",
                children: x("Skip", "button label"),
              }),
            ],
          }),
        ],
      })
    );
  }),
  w = { shift: "⇧", control: "⌃", ctrl: "⌃", alt: "⌥", command: "⌘" },
  M = ({ renderKey: s, pressed: t }) => {
    const n = w[s];
    return e.jsxs("div", {
      className: "keyboard-key",
      "data-sentry-component": "Key",
      "data-sentry-source-file": "Key.tsx",
      children: [
        e.jsx("div", { className: "keyboard-key-bottom" }),
        e.jsx("div", {
          className: h("keyboard-key-top", { pressed: t }),
          children: e.jsx("div", {
            className: "keyboard-key-top-contents",
            children: n
              ? e.jsxs("div", {
                  className: "contents-modifier",
                  children: [
                    e.jsx("span", { className: "modifier-glyph", children: n }),
                    e.jsx("span", { className: "modifier-name", children: s }),
                  ],
                })
              : e.jsx("div", { className: "contents-key", children: _(s) }),
          }),
        }),
      ],
    });
  },
  R = { command: "meta", ctrl: "control" },
  D = () => {
    const s = r.useContext(C),
      [t, n] = r.useState([]);
    return (
      r.useEffect(() => {
        const a = (o) => {
          const { character: l, type: m } = o.detail,
            u = l.toLowerCase();
          switch (m) {
            case "keyup":
              n(u === "meta" ? [] : (d) => d.filter((p) => p !== u));
              break;
            case "keydown":
              n((d) => (d.includes(u) ? d : d.concat(u)));
              break;
          }
        };
        return (
          s.window.addEventListener(S, a),
          () => s.window.removeEventListener(S, a)
        );
      }, []),
      t
    );
  },
  b = g(({ hotkey: s, onAllPressed: t }) => {
    const n = D(),
      a = r.useMemo(
        () =>
          s.split("+").map((o) => ({ key: o, pressed: n.includes(R[o] ?? o) })),
        [s, n],
      );
    return (
      r.useEffect(() => {
        a.every(({ pressed: o }) => o) && t?.();
      }, [a, t]),
      a.map(({ key: o, pressed: l }, m) =>
        e.jsx(M, { renderKey: o, pressed: l }, `${o}-${m}`),
      )
    );
  }),
  L = ({ selectNextPage: s }) => {
    const [t, n] = r.useState(!1);
    return (
      E(
        "enter, space",
        (a) => {
          (s(), a.stopPropagation());
        },
        "onboarding-keyboard",
      ),
      e.jsxs("main", {
        className: "onboarding-keyboard",
        "data-sentry-component": "KeyboardFirstPage",
        "data-sentry-source-file": "KeyboardFirstPage.tsx",
        children: [
          e.jsx("div", {
            className: h("success-badge", { visible: t }),
            children: e.jsx("span", {
              children: c("🤩 Check out that fancy fingerwork!"),
            }),
          }),
          e.jsx("div", {
            style: {
              display: "flex",
              justifyContent: "center",
              transform: "scale(0.75)",
            },
            children: e.jsx(b, {
              hotkey: "b+e+e+p+e+r",
              onAllPressed: () => n(!0),
              "data-sentry-element": "HotkeyButtons",
              "data-sentry-source-file": "KeyboardFirstPage.tsx",
            }),
          }),
          e.jsx("h1", {
            children: y(c("%(appName)s is keyboard-first"), {
              appName: v.APP_NAME,
            }),
          }),
          e.jsx("p", {
            children: c(
              "Let's go through some of the commonly used shortcuts.",
            ),
          }),
        ],
      })
    );
  },
  K = ({ selectNextPage: s }) =>
    e.jsxs("main", {
      className: "onboarding-second-page",
      "data-sentry-component": "CmdBarPage",
      "data-sentry-source-file": "CmdBarPage.tsx",
      children: [
        e.jsx("h1", { children: f.COMMAND_BAR }),
        e.jsx("p", {
          children: y(
            c(
              "Hit %(commandBarHotkey)s to access the Command Bar where you'll find everything you can do in %(appName)s along with their hotkeys.",
            ),
            { commandBarHotkey: f.COMMAND_BAR, appName: v.APP_NAME },
          ),
        }),
        e.jsx("div", {
          className: "onboarding-shortcut",
          children: e.jsx(b, {
            hotkey: i.TOGGLE_COMMAND_BAR.key,
            onAllPressed: s,
            "data-sentry-element": "HotkeyButtons",
            "data-sentry-source-file": "CmdBarPage.tsx",
          }),
        }),
      ],
    }),
  O = ({ selectNextPage: s }) =>
    e.jsxs("main", {
      className: "onboarding-second-page",
      "data-sentry-component": "ThreadSearchPage",
      "data-sentry-source-file": "ThreadSearchPage.tsx",
      children: [
        e.jsx("h1", { children: f.COMMAND_BAR_SEARCH_THREADS }),
        e.jsx("p", {
          children: y(
            c(
              "To find someone's chat, hit %(searchHotkey)s, type their name and hit Enter.",
            ),
            { searchHotkey: f.COMMAND_BAR_SEARCH_THREADS },
          ),
        }),
        e.jsx("div", {
          className: "onboarding-shortcut",
          children: e.jsx(b, {
            hotkey: i.SEARCH.key,
            onAllPressed: s,
            "data-sentry-element": "HotkeyButtons",
            "data-sentry-source-file": "ThreadSearchPage.tsx",
          }),
        }),
      ],
    }),
  G = g(({ selectNextPage: s }) => {
    const t = r.useContext(C),
      n = () => {
        (s(), t.cmdBarViewStore.isVisible && t.cmdBarViewStore.reset());
      };
    return e.jsxs("main", {
      className: "onboarding-second-page",
      children: [
        e.jsx("h1", { children: i.SELECT_NEXT_THREAD.humanized }),
        e.jsx("p", {
          children: y(
            c(
              "Hit %(nextHotkey)s to select the next chat. And %(previousHotkey)s to select the previous chat.",
            ),
            {
              nextHotkey: i.SELECT_NEXT_THREAD.humanized,
              previousHotkey: i.SELECT_PREV_THREAD.humanized,
            },
          ),
        }),
        e.jsx("div", {
          className: "onboarding-shortcut",
          children: e.jsx(b, {
            hotkey: i.SELECT_NEXT_THREAD.key.split(",", 1)[0],
            onAllPressed: n,
          }),
        }),
      ],
    });
  }),
  I = g(({ selectNextPage: s }) => {
    const [t, n] = r.useState(!1);
    return (
      r.useEffect(() => {
        t && setTimeout(s, 2e3);
      }, [t, s]),
      e.jsxs("main", {
        className: "onboarding-second-page",
        children: [
          e.jsx("h1", { children: i.SELECT_PREV_MESSAGE.humanized }),
          e.jsx("p", {
            children: y(
              c(
                "Hit %(previousHotkey)s to select the previous message. And %(nextHotkey)s to select the next one.",
              ),
              {
                previousHotkey: i.SELECT_PREV_MESSAGE.humanized,
                nextHotkey: i.SELECT_NEXT_MESSAGE.humanized,
              },
            ),
          }),
          e.jsx("div", {
            className: "onboarding-shortcut",
            children: e.jsx(b, {
              hotkey: i.SELECT_PREV_MESSAGE.key,
              onAllPressed: () => n(!0),
            }),
          }),
          e.jsxs("div", {
            className: h("success-badge", { visible: t }),
            children: [
              e.jsx(T, {}),
              e.jsx("span", { children: c("Nice work!") }),
            ],
          }),
        ],
      })
    );
  }),
  J = () =>
    e.jsx(B, {
      pages: [
        { Component: L, continueButton: !0 },
        { Component: K, continueButton: !1 },
        { Component: O, continueButton: !1 },
        { Component: G, continueButton: !1 },
        { Component: I, continueButton: !1 },
      ],
      onEnd: () => {
        H.layoutStore.setSecondOnboardingOpen(!1);
      },
      "data-sentry-element": "OnboardingSidebar",
      "data-sentry-component": "HotkeysOnboarding",
      "data-sentry-source-file": "Onboarding.tsx",
    });
export { J as HotkeysOnboarding };
//# sourceMappingURL=Onboarding-CUpAb4LQ.js.map
