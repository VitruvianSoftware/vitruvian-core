import {
  es as se,
  cF as s,
  br as F,
  ar as $,
  cT as G,
  b1 as te,
  de as i,
  b5 as q,
  eu as ne,
  K,
  cm as oe,
  d6 as g,
  bk as re,
  bj as ce,
  bO as ae,
  eq as ie,
  cG as le,
  aq as ue,
  aO as de,
  j as fe,
  dx as pe,
  ax as me,
  av as he,
  aw as Se,
  dK as ge,
} from "./App-BHgTsVmv.js";
import { y as Ee, aj as Pe } from "./sentry-common-BNqrY_yc.js";
import { cA as f, a1 as h, J as t } from "./matrix-util-8DbIGEm-.js";
import "./index-Cw3pknxT.js";
import "./index-Ch31Akxs.js";
import "./index-5FBEE1WD.js";
import "./main-process-state-BDOn7dvV.js";
import "./report-dialog-C-g_klPx.js";
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
    var a = new o.Error().stack;
    a &&
      ((o._sentryDebugIds = o._sentryDebugIds || {}),
      (o._sentryDebugIds[a] = "e44d5a81-406d-4a9a-8e8c-a36a9e437098"),
      (o._sentryDebugIdIdentifier =
        "sentry-dbid-e44d5a81-406d-4a9a-8e8c-a36a9e437098"));
  } catch {}
})();
const v = (o) => {
    const {
        onClick: a,
        onDoubleClick: l,
        onMouseDown: p,
        onMouseEnter: u,
        selected: d = !1,
        className: P,
        featureFlag: A,
      } = o,
      E = { "--content-anchor-name": se?.() || "" };
    if ("children" in o && o.children)
      return s.jsx("div", {
        style: E,
        className: F("pref-option", { selected: d }, P),
        onClick: a,
        onDoubleClick: l,
        onMouseDown: p,
        onMouseEnter: u,
        children: o.children,
      });
    const { icon: b, color: O, name: I, tag: x } = o;
    return s.jsxs("div", {
      style: E,
      className: F("pref-option", { selected: d }, P),
      onClick: a,
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
              style: { backgroundColor: O, color: "white" },
              children: b,
            }),
            s.jsx("span", { className: "pref-title", children: I }),
          ],
        }),
        x && s.jsx("span", { className: "tag", children: x }),
        A && s.jsx($, {}),
      ],
    });
  },
  be = G(() => {
    const {
        userProfileStore: o,
        beeperClientStore: a,
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
                  children: p.fullName || a.state.user_id,
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
  Ne = ({ suggestions: o, focusedIndex: a, onSelect: l, onHover: p }) =>
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
              className: F("suggestion-row", { selected: d === a }),
              onMouseDown: (P) => P.preventDefault(),
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
function X(o, a) {
  if (!a.trim()) return o;
  const l = o.toLowerCase().indexOf(a.toLowerCase());
  return l === -1
    ? o
    : s.jsxs(s.Fragment, {
        children: [
          o.slice(0, l),
          s.jsx("mark", { children: o.slice(l, l + a.length) }),
          o.slice(l + a.length),
        ],
      });
}
const Y = (o) => (typeof o == "function" ? o() : o && h(o)),
  Ie = G(() => {
    const o = i.useContext(q),
      { zoomFactor: a } = ne(),
      { cssVars: l } = f.layoutStore,
      p = l.prefsHeadingMinHeight / a,
      u = (!o.isFullScreened && Ee, l.prefsHeadingDefaultMarginLeft / a),
      [d, P] = i.useState(""),
      [A, y] = i.useState(!1),
      [E, b] = i.useState(0),
      [O, I] = i.useState(null),
      x = i.useRef(null),
      J = i.useRef(null),
      H = i.useRef(null),
      R = i.useRef(!1),
      T = i.useRef(),
      S = o.prefsViewStore,
      D = f.accountsStore.accountInstances.size > 0,
      Z = {
        [t.PROFILE]: {
          children: s.jsx(be, {}),
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
      W = f.addAccountStore.addableNetworks,
      L = g[t.ADD_ACCOUNT],
      z = i.useMemo(() => re(), []),
      Q = i.useMemo(
        () => [...z, ...ce(W, L?.icon, L?.color)],
        [z, W, L?.icon, L?.color],
      ),
      w = i.useMemo(() => {
        if (!d.trim()) return null;
        const e = ae(Q, d),
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
      C = i.useMemo(() => {
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
    i.useEffect(() => {
      (b(0), C.length === 0 && I(null));
    }, [C.length]);
    const M = i.useCallback(() => {
        requestAnimationFrame(() => {
          H.current
            ?.querySelector(".focused")
            ?.scrollIntoView({ block: "nearest" });
        });
      }, []),
      N = i.useCallback(
        (e, n) => {
          (S.setSubView(e), n && S.setHighlightedPrefName(n));
        },
        [S],
      ),
      U = i.useCallback(
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
      { subscriptionStore: V } = f,
      k = i.useMemo(() => {
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
          V.subscriptionAction === "subscribe"
            ? e.push({
                label: h("Subscribe to Beeper Plus"),
                sectionId: t.PREFS_BEEPER_PLUS,
              })
            : V.subscriptionAction === "upgrade" &&
              e.push({
                label: h("Subscribe to Beeper Plus Plus"),
                sectionId: t.PREFS_BEEPER_PLUS,
              }),
          e
        );
      }, [V.subscriptionAction, j]),
      B = i.useCallback(
        (e) => {
          const n = k[e];
          n &&
            (n.sectionId === t.PREFS_BEEPER_PLUS
              ? (f.subscriptionStore.handleUpgrade({
                  source: "Settings",
                  deprecatedTrigger: "settings-search",
                }),
                P(""))
              : N(n.sectionId, n.prefName),
            x.current?.blur(),
            y(!1));
        },
        [k, N],
      ),
      ee = i.useCallback(
        (e) => {
          if (!A) return;
          const n = C.length > 0,
            c = n ? C.length : k.length;
          if (!(c === 0 && e.key !== "Escape"))
            switch (e.key) {
              case "ArrowDown":
                (e.preventDefault(),
                  b((E + 1) % c),
                  (R.current = !0),
                  clearTimeout(T.current),
                  (T.current = setTimeout(() => {
                    R.current = !1;
                  }, 100)),
                  M());
                break;
              case "ArrowUp":
                (e.preventDefault(),
                  b((E - 1 + c) % c),
                  (R.current = !0),
                  clearTimeout(T.current),
                  (T.current = setTimeout(() => {
                    R.current = !1;
                  }, 100)),
                  M());
                break;
              case "Enter":
                if ((e.preventDefault(), n)) {
                  const r = C[E];
                  r?.kind === "header"
                    ? (I(r.sectionId), N(r.sectionId))
                    : r?.kind === "item" && (I(r.item.itemName), U(r.item));
                } else B(E);
                break;
              case "Escape":
                (e.preventDefault(),
                  e.stopPropagation(),
                  P(""),
                  x.current?.blur());
                break;
            }
        },
        [A, k.length, E, B, C, N, U, M],
      );
    return (
      ie(
        le.SEARCH_ROOM.key,
        () => {
          x.current?.focus();
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
                      ref: x,
                      type: "text",
                      placeholder: h("Search Settings"),
                      value: d,
                      onChange: (e) => P(e.target.value),
                      onFocus: () => {
                        (y(!0), b(0));
                      },
                      onBlur: () => y(!1),
                      onKeyDown: ee,
                    }),
                    d &&
                      s.jsx("button", {
                        className: "prefs-search-clear",
                        onMouseDown: (e) => {
                          (e.preventDefault(), P(""));
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
                  onSelect: B,
                  onHover: (e) => {
                    R.current || b(e);
                  },
                }),
              s.jsx("div", {
                className: "prefs-left-pane default-cursor",
                ref: H,
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
                              selected: O === e.sectionId,
                              className: F(
                                { focused: n === E },
                                r ? "search-match" : "search-no-match",
                              ),
                              onMouseDown: (_) => _.preventDefault(),
                              onMouseEnter: () => {
                                R.current || b(n);
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
                              selected: O === e.item.itemName,
                            }),
                            onMouseDown: (c) => c.preventDefault(),
                            onClick: () => {
                              (I(e.item.itemName), U(e.item));
                            },
                            onMouseEnter: () => {
                              R.current || b(n);
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
                              const n = Z[e.id],
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
                        Pe.show_hidden_features &&
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
  xe = G(() => {
    const a = i.useContext(q).prefsViewStore,
      l = (() => {
        const p = a.subView ? g[a.subView] : null;
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
            !a.subView ||
            [
              t.ACCOUNTS,
              t.ACCOUNT,
              t.PROFILE,
              t.STORAGE,
              t.PREFS_DEVICES,
            ].includes(a.subView),
        }),
        children: s.jsx("div", {
          className: "prefs-right-pane-scroll",
          children: l,
        }),
      },
      a.subView,
    );
  }),
  ye = () =>
    s.jsxs(s.Fragment, {
      children: [
        s.jsx(Ie, {
          "data-sentry-element": "PrefsLeftPane",
          "data-sentry-source-file": "PrefsPanes.tsx",
        }),
        s.jsx(xe, {
          "data-sentry-element": "PrefsRightPane",
          "data-sentry-source-file": "PrefsPanes.tsx",
        }),
      ],
    });
export { ye as default };
//# sourceMappingURL=PrefsPanes-wJ4fD792.js.map
