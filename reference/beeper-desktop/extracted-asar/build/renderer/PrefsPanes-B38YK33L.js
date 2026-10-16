import {
  ez as se,
  cK as s,
  bw as F,
  av as $,
  cY as H,
  b6 as te,
  dk as a,
  ba as Z,
  eB as ne,
  L as K,
  cs as oe,
  db as g,
  bp as re,
  bo as ce,
  bU as ie,
  ex as ae,
  cL as le,
  au as ue,
  aT as de,
  k as fe,
  dD as pe,
  aB as me,
  az as he,
  aA as Se,
  dQ as ge,
} from "./App-CsJiApxN.js";
import { w as Ee, ah as be } from "./sentry-common-BxRELKId.js";
import { cD as f, a2 as h, K as t } from "./matrix-util-Cr_UwXbj.js";
import "./index-Cw3pknxT.js";
import "./index-Dhe7xemD.js";
import "./index-CcYzEQCb.js";
import "./main-process-state-wkFhis-C.js";
import "./report-dialog-7bETf2vU.js";
import "./helpHubMessages-CXhGQ9cB.js";
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
    var i = new o.Error().stack;
    i &&
      ((o._sentryDebugIds = o._sentryDebugIds || {}),
      (o._sentryDebugIds[i] = "2b0d08ce-a1ce-4e24-979e-0d26c339532e"),
      (o._sentryDebugIdIdentifier =
        "sentry-dbid-2b0d08ce-a1ce-4e24-979e-0d26c339532e"));
  } catch {}
})();
const v = (o) => {
    const {
        onClick: i,
        onDoubleClick: l,
        onMouseDown: p,
        onMouseEnter: u,
        selected: d = !1,
        className: b,
        featureFlag: A,
      } = o,
      E = { "--content-anchor-name": se?.() || "" };
    if ("children" in o && o.children)
      return s.jsx("div", {
        style: E,
        className: F("pref-option", { selected: d }, b),
        onClick: i,
        onDoubleClick: l,
        onMouseDown: p,
        onMouseEnter: u,
        children: o.children,
      });
    const { icon: P, color: T, name: I, tag: R } = o;
    return s.jsxs("div", {
      style: E,
      className: F("pref-option", { selected: d }, b),
      onClick: i,
      onDoubleClick: l,
      onMouseDown: p,
      onMouseEnter: u,
      "data-sentry-component": "PrefOption",
      "data-sentry-source-file": "PrefOption.tsx",
      children: [
        s.jsxs("div", {
          className: "pref-option-info",
          children: [
            s.jsx("span", {
              className: "pref-icon",
              style: { backgroundColor: T, color: "white" },
              children: P,
            }),
            s.jsx("span", { className: "pref-title", children: I }),
          ],
        }),
        R && s.jsx("span", { className: "tag", children: R }),
        A && s.jsx($, {}),
      ],
    });
  },
  Pe = H(() => {
    const {
        userProfileStore: o,
        beeperClientStore: i,
        subscriptionStore: l,
      } = f,
      p = o.profile,
      u = l.subscriptionPlanId;
    return s.jsxs(s.Fragment, {
      children: [
        s.jsx(te, { size: 34, user: p }),
        s.jsxs("div", {
          className: "pref-option-user",
          children: [
            s.jsxs("div", {
              className: "pref-option-user-details",
              children: [
                s.jsx("p", {
                  className: "pref-option-title",
                  children: p.fullName || i.state.user_id,
                }),
                s.jsx("p", {
                  className: "pref-option-subtitle",
                  children: p.email,
                }),
              ],
            }),
            s.jsx($, {
              variant: "standard",
              className: "pref-account-pill",
              type:
                u === "PLUS_PLUS"
                  ? "plus-plus"
                  : u === "PLUS"
                    ? "plus"
                    : "free",
              compact: !0,
            }),
          ],
        }),
      ],
    });
  }),
  Ne = ({ suggestions: o, focusedIndex: i, onSelect: l, onHover: p }) =>
    s.jsxs("div", {
      className: "prefs-search-suggestions",
      "data-sentry-component": "SearchSuggestions",
      "data-sentry-source-file": "SearchSuggestions.tsx",
      children: [
        s.jsxs("div", {
          className: "suggestions-header",
          children: [
            s.jsx("span", { className: "suggestions-header-spacer" }),
            s.jsx("span", {
              className: "suggestions-header-label",
              children: h("Suggestions"),
            }),
          ],
        }),
        o.map((u, d) =>
          s.jsxs(
            "div",
            {
              className: F("suggestion-row", { selected: d === i }),
              onMouseDown: (b) => b.preventDefault(),
              onClick: () => l(d),
              onMouseEnter: () => p(d),
              children: [
                u.icon && u.color
                  ? s.jsx("span", {
                      className: "suggestion-icon",
                      style: { backgroundColor: u.color, color: "white" },
                      children: u.icon,
                    })
                  : s.jsx("span", { className: "suggestion-icon-spacer" }),
                s.jsx("span", {
                  className: "suggestion-label",
                  children: u.label,
                }),
              ],
            },
            u.label,
          ),
        ),
      ],
    });
function X(o, i) {
  if (!i.trim()) return o;
  const l = o.toLowerCase().indexOf(i.toLowerCase());
  return l === -1
    ? o
    : s.jsxs(s.Fragment, {
        children: [
          o.slice(0, l),
          s.jsx("mark", { children: o.slice(l, l + i.length) }),
          o.slice(l + i.length),
        ],
      });
}
const Y = (o) => (typeof o == "function" ? o() : o && h(o)),
  Ie = H(() => {
    const o = a.useContext(Z),
      { zoomFactor: i } = ne(),
      { cssVars: l } = f.layoutStore,
      p = l.prefsHeadingMinHeight / i,
      u =
        (!o.isFullScreened && Ee
          ? l.macTrafficLightsWidth + 20
          : l.prefsHeadingDefaultMarginLeft) / i,
      [d, b] = a.useState(""),
      [A, y] = a.useState(!1),
      [E, P] = a.useState(0),
      [T, I] = a.useState(null),
      R = a.useRef(null),
      J = a.useRef(null),
      G = a.useRef(null),
      x = a.useRef(!1),
      O = a.useRef(),
      S = o.prefsViewStore,
      D = f.accountsStore.accountInstances.size > 0,
      q = {
        [t.PROFILE]: {
          children: s.jsx(Pe, {}),
          className: "pref-option-profile",
        },
        [t.PREFS_BEEPER_PLUS]: {
          onClick: () => {
            (f.subscriptionStore.trackPremiumCTA({
              source: "Settings",
              deprecatedTrigger: "pref-beeper-plus",
            }),
              S.setSubView(t.PREFS_BEEPER_PLUS));
          },
        },
        [t.PREFS_HELP]: {
          onClick: () => {
            ge();
          },
        },
      },
      j = [
        t.PROFILE,
        t.ACCOUNTS,
        ...(D
          ? [
              t.PREFS_GENERAL,
              t.PREFS_UI,
              t.PREFS_NOTIFICATIONS,
              t.PREFS_HOTKEYS,
              t.PREFS_DEVICES,
              t.PREFS_AI,
            ]
          : []),
        ...(f.subscriptionStore.subscriptionAction === "subscribe"
          ? [t.PREFS_BEEPER_PLUS]
          : []),
        ...(D
          ? [
              ...(f.features[K.QUICK_REPLIES].show
                ? [t.PREFS_QUICK_REPLIES]
                : []),
              ...(oe() ? [t.PREFS_BRIDGES] : []),
              ...(f.features[K.DESKTOP_LABS_BEEPER_CONNECT].show
                ? [t.PREFS_BEEPER_CONNECT]
                : []),
            ]
          : []),
        t.STORAGE,
        t.PREFS_HELP,
        t.PREFS_ABOUT,
      ]
        .map((e) => g[e])
        .filter(Boolean)
        .filter(
          (e) =>
            !(
              e.featureFlag &&
              !(
                typeof e.featureFlag == "function"
                  ? e.featureFlag()
                  : e.featureFlag
              ).show
            ),
        ),
      z = f.addAccountStore.addableNetworks,
      L = g[t.ADD_ACCOUNT],
      W = a.useMemo(() => re(), []),
      Q = a.useMemo(
        () => [...W, ...ce(z, L?.icon, L?.color)],
        [W, z, L?.icon, L?.color],
      ),
      w = a.useMemo(() => {
        if (!d.trim()) return null;
        const e = ie(Q, d),
          n = new Map();
        for (const c of e) {
          if (c.isTopLevel) {
            n.has(c.sectionKey) || n.set(c.sectionKey, []);
            continue;
          }
          const r = n.get(c.sectionKey);
          r ? r.push(c) : n.set(c.sectionKey, [c]);
        }
        return n;
      }, [Q, d]),
      C = a.useMemo(() => {
        if (!w) return [];
        const e = [],
          n = new Set();
        for (const r of j) {
          const m = w.get(r.id);
          if (m) {
            (n.add(r.id), e.push({ kind: "header", sectionId: r.id }));
            for (const _ of m) e.push({ kind: "item", item: _ });
          }
        }
        for (const [r, m] of w)
          if (!(n.has(r) || m.length === 0)) {
            (n.add(r), e.push({ kind: "header", sectionId: r }));
            for (const _ of m) e.push({ kind: "item", item: _ });
          }
        if ([...w.values()].some((r) => r.length > 0))
          for (const r of j)
            n.has(r.id) || e.push({ kind: "header", sectionId: r.id });
        return e;
      }, [w, j]);
    a.useEffect(() => {
      (P(0), C.length === 0 && I(null));
    }, [C.length]);
    const B = a.useCallback(() => {
        requestAnimationFrame(() => {
          G.current
            ?.querySelector(".focused")
            ?.scrollIntoView({ block: "nearest" });
        });
      }, []),
      N = a.useCallback(
        (e, n) => {
          (S.setSubView(e), n && S.setHighlightedPrefName(n));
        },
        [S],
      ),
      M = a.useCallback(
        (e) => {
          const { platform: n } = e;
          if (!n) {
            N(e.sectionKey, e.itemName);
            return;
          }
          const { addAccountStore: c, accountsStore: r } = f,
            m = r.allProperAccounts.find((_) => _.platformName === n.name);
          if (m) {
            S.selectAccount(m.accountID);
            return;
          }
          (c.openNewAccountInNewWindow(n), N(t.ACCOUNTS));
        },
        [N, S],
      ),
      { subscriptionStore: U } = f,
      k = a.useMemo(() => {
        const e = [
          {
            label: h("Add an Account"),
            sectionId: t.ACCOUNTS,
            icon: g[t.ACCOUNTS]?.icon,
            color: g[t.ACCOUNTS]?.color ?? "",
          },
          {
            label: h("Incognito Mode"),
            sectionId: t.PREFS_GENERAL,
            prefName: "Incognito mode",
            icon: g[t.PREFS_GENERAL]?.icon,
            color: g[t.PREFS_GENERAL]?.color ?? "",
          },
          {
            label: h("Show Recipients I'm Typing"),
            sectionId: t.PREFS_GENERAL,
            prefName: "Show recipients I'm typing",
            icon: g[t.PREFS_GENERAL]?.icon,
            color: g[t.PREFS_GENERAL]?.color ?? "",
          },
          {
            label: h("Group Message Notifications"),
            sectionId: t.PREFS_NOTIFICATIONS,
            prefName: "Group message notifications",
            icon: g[t.PREFS_NOTIFICATIONS]?.icon,
            color: g[t.PREFS_NOTIFICATIONS]?.color ?? "",
          },
        ].filter((n) => j.some((c) => c.id === n.sectionId));
        return (
          U.subscriptionAction === "subscribe"
            ? e.push({
                label: h("Subscribe to Beeper Plus"),
                sectionId: t.PREFS_BEEPER_PLUS,
              })
            : U.subscriptionAction === "upgrade" &&
              e.push({
                label: h("Subscribe to Beeper Plus Plus"),
                sectionId: t.PREFS_BEEPER_PLUS,
              }),
          e
        );
      }, [U.subscriptionAction, j]),
      V = a.useCallback(
        (e) => {
          const n = k[e];
          n &&
            (n.sectionId === t.PREFS_BEEPER_PLUS
              ? (f.subscriptionStore.handleUpgrade({
                  source: "Settings",
                  deprecatedTrigger: "settings-search",
                }),
                b(""))
              : N(n.sectionId, n.prefName),
            R.current?.blur(),
            y(!1));
        },
        [k, N],
      ),
      ee = a.useCallback(
        (e) => {
          if (!A) return;
          const n = C.length > 0,
            c = n ? C.length : k.length;
          if (!(c === 0 && e.key !== "Escape"))
            switch (e.key) {
              case "ArrowDown":
                (e.preventDefault(),
                  P((E + 1) % c),
                  (x.current = !0),
                  clearTimeout(O.current),
                  (O.current = setTimeout(() => {
                    x.current = !1;
                  }, 100)),
                  B());
                break;
              case "ArrowUp":
                (e.preventDefault(),
                  P((E - 1 + c) % c),
                  (x.current = !0),
                  clearTimeout(O.current),
                  (O.current = setTimeout(() => {
                    x.current = !1;
                  }, 100)),
                  B());
                break;
              case "Enter":
                if ((e.preventDefault(), n)) {
                  const r = C[E];
                  r?.kind === "header"
                    ? (I(r.sectionId), N(r.sectionId))
                    : r?.kind === "item" && (I(r.item.itemName), M(r.item));
                } else V(E);
                break;
              case "Escape":
                (e.preventDefault(),
                  e.stopPropagation(),
                  b(""),
                  R.current?.blur());
                break;
            }
        },
        [A, k.length, E, V, C, N, M, B],
      );
    return (
      ae(
        le.SEARCH_ROOM.key,
        () => {
          R.current?.focus();
        },
        "prefs-search-focus",
      ),
      o.windowType.startsWith("prefs-")
        ? null
        : s.jsxs("div", {
            className: "prefs-left-pane-container",
            children: [
              s.jsx("div", {
                className: "prefs-left-pane-heading",
                style: { minHeight: p, marginLeft: u },
                children: s.jsx("h2", { children: h("Settings") }),
              }),
              s.jsx("div", {
                className: "prefs-search-gutter",
                children: s.jsxs("div", {
                  className: "prefs-search-input",
                  children: [
                    s.jsx(ue, { iconId: "search", size: 16 }),
                    s.jsx("input", {
                      ref: R,
                      type: "text",
                      placeholder: h("Search Settings"),
                      value: d,
                      onChange: (e) => b(e.target.value),
                      onFocus: () => {
                        (y(!0), P(0));
                      },
                      onBlur: () => y(!1),
                      onKeyDown: ee,
                    }),
                    d &&
                      s.jsx("button", {
                        className: "prefs-search-clear",
                        onMouseDown: (e) => {
                          (e.preventDefault(), b(""));
                        },
                        children: s.jsx(de, {
                          name: "close-small",
                          width: 16,
                          height: 16,
                        }),
                      }),
                  ],
                }),
              }),
              A &&
                !d.trim() &&
                s.jsx(Ne, {
                  suggestions: k,
                  focusedIndex: E,
                  onSelect: V,
                  onHover: (e) => {
                    x.current || P(e);
                  },
                }),
              s.jsx("div", {
                className: "prefs-left-pane default-cursor",
                ref: G,
                children: w
                  ? s.jsx("div", {
                      className: "pref-category pref-search-results",
                      children: C.map((e, n) => {
                        if (e.kind === "header") {
                          const c = g[e.sectionId];
                          if (!c) return null;
                          const r = w.has(e.sectionId),
                            m = Y(c.displayName) ?? "";
                          return s.jsx(
                            v,
                            {
                              name: r ? X(m, d) : m,
                              icon: c.icon,
                              color: c.color,
                              onClick: () => {
                                (I(e.sectionId), N(e.sectionId));
                              },
                              selected: T === e.sectionId,
                              className: F(
                                { focused: n === E },
                                r ? "search-match" : "search-no-match",
                              ),
                              onMouseDown: (_) => _.preventDefault(),
                              onMouseEnter: () => {
                                x.current || P(n);
                              },
                            },
                            `header-${e.sectionId}`,
                          );
                        }
                        return s.jsx(
                          "div",
                          {
                            className: F("search-result-item", {
                              focused: n === E,
                              selected: T === e.item.itemName,
                            }),
                            onMouseDown: (c) => c.preventDefault(),
                            onClick: () => {
                              (I(e.item.itemName), M(e.item));
                            },
                            onMouseEnter: () => {
                              x.current || P(n);
                            },
                            children: s.jsx("span", {
                              className: "search-result-label",
                              children: X(e.item.itemName, d),
                            }),
                          },
                          `item-${n}`,
                        );
                      }),
                    })
                  : s.jsxs(s.Fragment, {
                      children: [
                        s.jsxs("div", {
                          className: "pref-category",
                          ref: J,
                          children: [
                            s.jsx(fe, { className: "pref-option-backup" }),
                            j.map((e) => {
                              const n = q[e.id],
                                c = e.tag ? pe(e.tag) : void 0,
                                r = n?.onClick || (() => S.setSubView(e.id)),
                                m = Y(e.displayName) ?? "";
                              return s.jsx(
                                v,
                                {
                                  name: m,
                                  icon: e.icon,
                                  color: e.color,
                                  tag: c,
                                  className: n?.className,
                                  onClick: r,
                                  selected: S.subView === e.id,
                                  children: n?.children,
                                },
                                e.id,
                              );
                            }),
                          ],
                        }),
                        be.show_hidden_features &&
                          D &&
                          s.jsxs("div", {
                            className: "pref-category",
                            children: [
                              s.jsx(v, {
                                name: h("Hotkey Tutorial"),
                                icon: s.jsx(me, {}),
                                color: "rgb(52, 183, 244)",
                                onClick: () =>
                                  f.layoutStore.startSecondOnboarding(),
                                selected: f.layoutStore.secondOnboardingOpen,
                              }),
                              f.features[K.BROWSER_EXTENSION].show &&
                                s.jsx(v, {
                                  name: h("Browser Extension"),
                                  icon: s.jsx(he, {}),
                                  color: "rgb(244, 183, 52)",
                                  onClick: () =>
                                    S.setSubView(t.PREFS_BROWSER_EXT),
                                  selected: S.subView === t.PREFS_BROWSER_EXT,
                                }),
                              (f.beeperClientStore.isInternalUser || !1) &&
                                s.jsx(v, {
                                  name: h("Mobile Apps"),
                                  icon: s.jsx(Se, {}),
                                  color: "rgb(183, 52, 244)",
                                  onClick: () =>
                                    S.setSubView(t.PREFS_MOBILE_APPS),
                                  selected: S.subView === t.PREFS_MOBILE_APPS,
                                }),
                            ],
                          }),
                      ],
                    }),
              }),
            ],
          })
    );
  }),
  Re = H(() => {
    const i = a.useContext(Z).prefsViewStore,
      l = (() => {
        const p = i.subView ? g[i.subView] : null;
        if (p?.component) {
          const u = p.component;
          return s.jsx(u, {});
        }
        return null;
      })();
    return s.jsx(
      "div",
      {
        className: F("prefs-right-pane", {
          "account-pref-pane":
            !i.subView ||
            [
              t.ACCOUNTS,
              t.ACCOUNT,
              t.PROFILE,
              t.STORAGE,
              t.PREFS_DEVICES,
            ].includes(i.subView),
        }),
        children: s.jsx("div", {
          className: "prefs-right-pane-scroll",
          children: l,
        }),
      },
      i.subView,
    );
  }),
  Te = () =>
    s.jsxs(s.Fragment, {
      children: [
        s.jsx(Ie, {
          "data-sentry-element": "PrefsLeftPane",
          "data-sentry-source-file": "PrefsPanes.tsx",
        }),
        s.jsx(Re, {
          "data-sentry-element": "PrefsRightPane",
          "data-sentry-source-file": "PrefsPanes.tsx",
        }),
      ],
    });
export { Te as default };
//# sourceMappingURL=PrefsPanes-B38YK33L.js.map
