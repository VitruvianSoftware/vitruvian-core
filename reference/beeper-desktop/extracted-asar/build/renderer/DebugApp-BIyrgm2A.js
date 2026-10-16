import {
  dk as o,
  cK as e,
  aG as Ce,
  cY as de,
  a_ as De,
  c0 as je,
  ek as Ie,
  bw as Fe,
  K as Pe,
  J as $e,
  M as Oe,
  ba as ke,
  V as Re,
} from "./App-CsJiApxN.js";
import { a9 as Me, V as Be } from "./sentry-common-BxRELKId.js";
import {
  ar as ue,
  cU as Ae,
  cD as Q,
  av as Le,
} from "./matrix-util-Cr_UwXbj.js";
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
      (t._sentryDebugIds[s] = "4a5ad581-5a04-4db0-b26e-d89a1ddf189d"),
      (t._sentryDebugIdIdentifier =
        "sentry-dbid-4a5ad581-5a04-4db0-b26e-d89a1ddf189d"));
  } catch {}
})();
const He = "RoomStateExplorer-module__roomStateExplorer",
  Ve = "RoomStateExplorer-module__header",
  We = "RoomStateExplorer-module__headerContent",
  Ke = "RoomStateExplorer-module__headerInfo",
  Je = "RoomStateExplorer-module__headerText",
  ze = "RoomStateExplorer-module__headerTitle",
  Ge = "RoomStateExplorer-module__headerRoomId",
  Ue = "RoomStateExplorer-module__headerActions",
  qe = "RoomStateExplorer-module__actionButton",
  Qe = "RoomStateExplorer-module__primaryButton",
  Ye = "RoomStateExplorer-module__tabBar",
  Xe = "RoomStateExplorer-module__tabButton",
  Ze = "RoomStateExplorer-module__activeTab",
  et = "RoomStateExplorer-module__errorBar",
  tt = "RoomStateExplorer-module__errorIcon",
  st = "RoomStateExplorer-module__errorMessage",
  at = "RoomStateExplorer-module__statusBar",
  ot = "RoomStateExplorer-module__statusLoading",
  nt = "RoomStateExplorer-module__loadingSpinner",
  rt = "RoomStateExplorer-module__contentContainer",
  lt = "RoomStateExplorer-module__loadingState",
  ct = "RoomStateExplorer-module__emptyState",
  it = "RoomStateExplorer-module__emoji",
  J = {
    roomStateExplorer: He,
    header: Ve,
    headerContent: We,
    headerInfo: Ke,
    headerText: Je,
    headerTitle: ze,
    headerRoomId: Ge,
    headerActions: Ue,
    actionButton: qe,
    primaryButton: Qe,
    tabBar: Ye,
    tabButton: Xe,
    activeTab: Ze,
    errorBar: et,
    errorIcon: tt,
    errorMessage: st,
    statusBar: at,
    statusLoading: ot,
    loadingSpinner: nt,
    contentContainer: rt,
    loadingState: lt,
    emptyState: ct,
    emoji: it,
  },
  dt = "ObjectExplorer-module__viewer",
  mt = "ObjectExplorer-module__toolbar",
  ut = "ObjectExplorer-module__searchRow",
  ht = "ObjectExplorer-module__controlsRow",
  pt = "ObjectExplorer-module__searchContainer",
  xt = "ObjectExplorer-module__pathContainer",
  gt = "ObjectExplorer-module__searchInputWrapper",
  ft = "ObjectExplorer-module__searchHistoryButton",
  _t = "ObjectExplorer-module__searchHistoryDropdown",
  bt = "ObjectExplorer-module__searchHistoryItem",
  jt = "ObjectExplorer-module__pathNavigator",
  yt = "ObjectExplorer-module__searchInput",
  vt = "ObjectExplorer-module__searchInfo",
  Et = "ObjectExplorer-module__controls",
  Nt = "ObjectExplorer-module__autoExpandCheckbox",
  St = "ObjectExplorer-module__controlButton",
  wt = "ObjectExplorer-module__objectTree",
  Tt = "ObjectExplorer-module__emptyObject",
  Ct = "ObjectExplorer-module__noMatches",
  Dt = "ObjectExplorer-module__node",
  It = "ObjectExplorer-module__nodeHeader",
  Ft = "ObjectExplorer-module__actions",
  Pt = "ObjectExplorer-module__cmdKeyActive",
  $t = "ObjectExplorer-module__expandIcon",
  Ot = "ObjectExplorer-module__expanded",
  kt = "ObjectExplorer-module__expandIconPlaceholder",
  Rt = "ObjectExplorer-module__nodeName",
  Mt = "ObjectExplorer-module__nodeValue",
  Bt = "ObjectExplorer-module__valueString ObjectExplorer-module__nodeValue",
  At = "ObjectExplorer-module__valueNumber ObjectExplorer-module__nodeValue",
  Lt = "ObjectExplorer-module__valueBoolean ObjectExplorer-module__nodeValue",
  Ht = "ObjectExplorer-module__valueNull ObjectExplorer-module__nodeValue",
  Vt = "ObjectExplorer-module__valueFunction ObjectExplorer-module__nodeValue",
  Wt = "ObjectExplorer-module__valueObject ObjectExplorer-module__nodeValue",
  Kt = "ObjectExplorer-module__children",
  Jt = "ObjectExplorer-module__actionButton",
  zt = "ObjectExplorer-module__copied",
  Gt = "ObjectExplorer-module__matchHighlight",
  Ut = "ObjectExplorer-module__matchName",
  qt = "ObjectExplorer-module__matchValue",
  Qt = "ObjectExplorer-module__hasMatchingDescendant",
  Yt = "ObjectExplorer-module__hasMatches",
  Xt = "ObjectExplorer-module__matchCount",
  Zt = "ObjectExplorer-module__hiddenItemsCount",
  es = "ObjectExplorer-module__siblingOfMatch",
  ts = "ObjectExplorer-module__pinnedItem",
  ss = "ObjectExplorer-module__pinnedDescendant",
  as = "ObjectExplorer-module__pathSegment",
  os = "ObjectExplorer-module__active",
  ns = "ObjectExplorer-module__pathSeparator",
  rs = "ObjectExplorer-module__keyboardNavActive",
  ls = "ObjectExplorer-module__expandAction",
  cs = "ObjectExplorer-module__flashExpand",
  is = "ObjectExplorer-module__collapseAction",
  ds = "ObjectExplorer-module__flashCollapse",
  ms = "ObjectExplorer-module__pinAction",
  us = "ObjectExplorer-module__flashPin",
  hs = "ObjectExplorer-module__unpinAction",
  ps = "ObjectExplorer-module__flashUnpin",
  xs = "ObjectExplorer-module__flashActive",
  gs = "ObjectExplorer-module__flashActiveNode",
  fs = "ObjectExplorer-module__previewTooltip",
  _s = "ObjectExplorer-module__previewFadeIn",
  bs = "ObjectExplorer-module__previewContainer",
  js = "ObjectExplorer-module__previewNode",
  ys = "ObjectExplorer-module__previewNodeHeader",
  vs = "ObjectExplorer-module__previewNodeName",
  Es = "ObjectExplorer-module__previewNodeChildren",
  Ns = "ObjectExplorer-module__keyboardHelp",
  Ss = "ObjectExplorer-module__baseWindow",
  ws = "ObjectExplorer-module__windowFadeIn",
  Ts = "ObjectExplorer-module__windowTitleBar",
  Cs = "ObjectExplorer-module__windowTitle",
  Ds = "ObjectExplorer-module__windowCloseButton",
  Is = "ObjectExplorer-module__windowContent",
  Fs =
    "ObjectExplorer-module__keyboardHelpWindow ObjectExplorer-module__baseWindow",
  Ps = "ObjectExplorer-module__shortcutsGroup",
  $s = "ObjectExplorer-module__shortcutsNote",
  Os =
    "ObjectExplorer-module__dedicatedViewContainer ObjectExplorer-module__baseWindow",
  ks = "ObjectExplorer-module__dedicatedViewHeader",
  Rs = "ObjectExplorer-module__dedicatedViewTitle",
  Ms = "ObjectExplorer-module__dedicatedViewClose",
  Bs = "ObjectExplorer-module__dedicatedViewContent",
  As = "ObjectExplorer-module__dedicatedNode",
  Ls = "ObjectExplorer-module__dedicatedNodeHeader",
  Hs = "ObjectExplorer-module__dedicatedNodeName",
  Vs = "ObjectExplorer-module__dedicatedNodeChildren",
  Ws = "ObjectExplorer-module__tooltipFadeIn",
  g = {
    viewer: dt,
    toolbar: mt,
    searchRow: ut,
    controlsRow: ht,
    searchContainer: pt,
    pathContainer: xt,
    searchInputWrapper: gt,
    searchHistoryButton: ft,
    searchHistoryDropdown: _t,
    searchHistoryItem: bt,
    pathNavigator: jt,
    searchInput: yt,
    searchInfo: vt,
    controls: Et,
    autoExpandCheckbox: Nt,
    controlButton: St,
    objectTree: wt,
    emptyObject: Tt,
    noMatches: Ct,
    node: Dt,
    nodeHeader: It,
    actions: Ft,
    cmdKeyActive: Pt,
    expandIcon: $t,
    expanded: Ot,
    expandIconPlaceholder: kt,
    nodeName: Rt,
    nodeValue: Mt,
    valueString: Bt,
    valueNumber: At,
    valueBoolean: Lt,
    valueNull: Ht,
    valueFunction: Vt,
    valueObject: Wt,
    children: Kt,
    actionButton: Jt,
    copied: zt,
    matchHighlight: Gt,
    matchName: Ut,
    matchValue: qt,
    hasMatchingDescendant: Qt,
    hasMatches: Yt,
    matchCount: Xt,
    hiddenItemsCount: Zt,
    siblingOfMatch: es,
    pinnedItem: ts,
    pinnedDescendant: ss,
    pathSegment: as,
    active: os,
    pathSeparator: ns,
    keyboardNavActive: rs,
    expandAction: ls,
    flashExpand: cs,
    collapseAction: is,
    flashCollapse: ds,
    pinAction: ms,
    flashPin: us,
    unpinAction: hs,
    flashUnpin: ps,
    flashActive: xs,
    flashActiveNode: gs,
    previewTooltip: fs,
    previewFadeIn: _s,
    previewContainer: bs,
    previewNode: js,
    previewNodeHeader: ys,
    previewNodeName: vs,
    previewNodeChildren: Es,
    keyboardHelp: Ns,
    baseWindow: Ss,
    windowFadeIn: ws,
    windowTitleBar: Ts,
    windowTitle: Cs,
    windowCloseButton: Ds,
    windowContent: Is,
    keyboardHelpWindow: Fs,
    shortcutsGroup: Ps,
    shortcutsNote: $s,
    dedicatedViewContainer: Os,
    dedicatedViewHeader: ks,
    dedicatedViewTitle: Rs,
    dedicatedViewClose: Ms,
    dedicatedViewContent: Bs,
    dedicatedNode: As,
    dedicatedNodeHeader: Ls,
    dedicatedNodeName: Hs,
    dedicatedNodeChildren: Vs,
    tooltipFadeIn: Ws,
  },
  ve = o.createContext({ expandedPaths: new Set(), togglePath: () => {} }),
  Ks = () => o.useContext(ve),
  Js = ({
    name: t,
    value: s,
    depth: r,
    path: m,
    searchTerm: x,
    matchingPaths: h,
    matchCounts: c,
    autoExpandSearchResults: T,
    showSiblings: k,
    showOnlyPinned: P,
    pinnedPaths: F,
    onPin: q,
    activePath: W,
  }) => {
    const { expandedPaths: D, togglePath: $ } = Ks(),
      v = o.useMemo(() => {
        if (m.length === 0 && t === "") return "";
        if (t && t.startsWith("[") && t.endsWith("]")) {
          const i = m.join(".");
          return i ? `${i}${t}` : t;
        }
        return [...m, t].join(".");
      }, [m, t]),
      u = D.has(v),
      M = typeof s,
      N = s !== null && M === "object",
      K = Array.isArray(s),
      G = N && ((K && s.length > 0) || (!K && Object.keys(s).length > 0)),
      R = o.useMemo(
        () =>
          s === null
            ? "null"
            : s === void 0
              ? "undefined"
              : M === "string"
                ? `"${s}"`
                : M === "function"
                  ? "function() { ... }"
                  : K
                    ? `Array(${s.length})`
                    : N
                      ? `{${Object.keys(s).length} items}`
                      : String(s),
        [s, M, N, K],
      ),
      I = o.useMemo(
        () =>
          x
            ? h.has(v)
              ? !0
              : s !== null && typeof s != "object"
                ? String(s).toLowerCase().includes(x.toLowerCase())
                : !!(t && t.toLowerCase().includes(x.toLowerCase()))
            : !1,
        [h, v, x, s, t],
      ),
      f = o.useMemo(() => {
        if (!x) return !1;
        if (I) return !0;
        if (N) {
          if (v === "" || m.length === 0) return h.size > 0;
          const i = v === "" ? t : v;
          for (const n of h)
            if (
              n.startsWith(i + ".") ||
              n.startsWith(i + "[") ||
              (n.includes("[") && n.split("[")[0] === i)
            )
              return !0;
        }
        return !1;
      }, [h, v, t, m.length, x, N, I]),
      O = o.useMemo(
        () => (!x || !k || I || f ? !1 : h.has(v) && !I),
        [x, k, I, f, h, v],
      ),
      H = o.useMemo(() => F.has(v), [F, v]),
      z = o.useMemo(
        () =>
          H || !N
            ? !1
            : v === ""
              ? Array.from(F).some((i) => i.includes(".") || i.includes("["))
              : Array.from(F).some(
                  (i) =>
                    i.startsWith(v + ".") ||
                    (K && i.startsWith(v + "[")) ||
                    (i.includes("[") && i.split("[")[0] === v),
                ),
        [H, N, v, F, K],
      ),
      [B, V] = o.useState(""),
      [A, Y] = o.useState(""),
      ne = o.useCallback(
        (i) => {
          i.stopPropagation();
          const n = N ? JSON.stringify(s, null, 2) : String(s);
          (ue(n), V("copied"), setTimeout(() => V(""), 800));
        },
        [s, N],
      ),
      se = o.useCallback(
        (i) => {
          (i.stopPropagation(),
            ue(v),
            Y("copied"),
            setTimeout(() => Y(""), 800));
        },
        [v],
      ),
      Z = o.useMemo(
        () =>
          s == null
            ? g.valueNull
            : M === "boolean"
              ? g.valueBoolean
              : M === "number"
                ? g.valueNumber
                : M === "string"
                  ? g.valueString
                  : M === "function"
                    ? g.valueFunction
                    : g.valueObject,
        [s, M],
      ),
      ie = o.useCallback(
        (i) => {
          (i.stopPropagation(), q(v));
        },
        [v, q],
      ),
      me = o.useMemo(() => {
        if (!x || !N || !s) return 0;
        const i = K ? s.length : Object.keys(s).length;
        if (!u) return 0;
        let n = 0;
        if (K)
          for (let d = 0; d < s.length; d++) {
            const y = `${[...m, t].join(".")}[${d}]`,
              w = h.has(y),
              L = Array.from(h).some(
                (ee) => ee.startsWith(y + ".") || ee.startsWith(y + "["),
              );
            (w || L) && n++;
          }
        else
          for (const d of Object.keys(s)) {
            const _ = [...m, t, d].join("."),
              y = h.has(_),
              w = Array.from(h).some(
                (L) => L.startsWith(_ + ".") || L.startsWith(_ + "["),
              );
            (y || w) && n++;
          }
        return Math.max(0, i - n);
      }, [x, N, K, s, u, m, t, h]),
      he = o.useMemo(() => {
        if ((!x && !P) || H || r === 0 || m.length === 0 || I || f) return !0;
        if (k && m.length > 0) {
          const i = m.slice(0, -1).join(".");
          if (h.has(i)) return !0;
          if (v.includes("[")) {
            const n = v.split("[")[0];
            if (h.has(n)) return !0;
            for (const d of h) if (d.startsWith(n + "[") && d !== v) return !0;
          }
        }
        if (P) {
          if (z) return !0;
          if (m.length > 0) {
            const i = m.slice(0, -1).join(".");
            if (
              Array.from(F).some((d) => {
                const _ = d.split(".");
                return _.length === m.length && _.slice(0, -1).join(".") === i;
              })
            )
              return !0;
          }
          return !1;
        }
        return !1;
      }, [x, v, r, m, I, f, k, H, z, P, F, h]);
    (o.useMemo(() => (K ? s : []), [K, s]),
      o.useEffect(() => {
        x && T && f && !u && $(v);
      }, [x, f, u, v, T, $]));
    const l = o.useCallback(
        () =>
          !K || !u
            ? null
            : e.jsx("div", {
                className: g.children,
                children: s.map((i, n) => {
                  const d = `[${n}]`,
                    _ = m.join("."),
                    y = _ ? `${_}.${t}${d}` : `${t}${d}`;
                  return (
                    console.log(
                      `Array item: index=${n}, parentPath=${_}.${t}, fullPath=${y}`,
                    ),
                    e.jsx(
                      be,
                      {
                        name: d,
                        value: i,
                        depth: r + 1,
                        path: _ ? [...m, t] : [t],
                        searchTerm: x,
                        matchingPaths: h,
                        matchCounts: c,
                        autoExpandSearchResults: T,
                        showSiblings: k,
                        showOnlyPinned: P,
                        pinnedPaths: F,
                        onPin: q,
                        activePath: W,
                      },
                      y,
                    )
                  );
                }),
              }),
        [K, u, s, r, m, t, x, D, h, c, T, k, P, F, q, W],
      ),
      [E, b] = o.useState(!1),
      p = o.useRef(null);
    if (
      (o.useEffect(() => {
        const i = (d) => {
            (d.metaKey || d.ctrlKey) && b(!0);
          },
          n = (d) => {
            !d.metaKey && !d.ctrlKey && b(!1);
          };
        return (
          window.addEventListener("keydown", i),
          window.addEventListener("keyup", n),
          window.addEventListener("blur", () => b(!1)),
          () => {
            (window.removeEventListener("keydown", i),
              window.removeEventListener("keyup", n),
              window.removeEventListener("blur", () => b(!1)));
          }
        );
      }, []),
      !he)
    )
      return e.jsx(e.Fragment, {});
    const j = `path-${v.replace(/\./g, "-")}`,
      S = W === v;
    return e.jsxs("div", {
      id: j,
      ref: p,
      className: `${g.node}
      ${I ? g.matchHighlight : ""}
      ${f ? g.hasMatchingDescendant : ""}
      ${O ? g.siblingOfMatch : ""}
      ${H ? g.pinnedItem : ""}
      ${z ? g.pinnedDescendant : ""}
      ${S ? g.keyboardNavActive : ""}`,
      "data-sentry-component": "ObjectNode",
      "data-sentry-source-file": "ObjectExplorer.tsx",
      children: [
        e.jsxs("div", {
          className: `${g.nodeHeader} ${E && N ? g.cmdKeyActive : ""} ${I ? g.matchHighlight : ""}`,
          style: { paddingLeft: `${r * 16}px` },
          onClick: (i) => {
            (i.stopPropagation(),
              console.log(`Click on ${v}, hasChildren: ${G}, isExpanded: ${u}`),
              $(v));
          },
          onDoubleClick: (i) => {
            (i.stopPropagation(),
              W === v
                ? window.dispatchEvent(
                    new CustomEvent("set-active-path", {
                      detail: { path: "" },
                    }),
                  )
                : window.dispatchEvent(
                    new CustomEvent("set-active-path", { detail: { path: v } }),
                  ));
          },
          children: [
            e.jsxs("div", {
              style: {
                display: "flex",
                alignItems: "center",
                minWidth: "100px",
              },
              children: [
                G
                  ? e.jsxs("span", {
                      className: `${g.expandIcon} ${u ? g.expanded : ""} ${f ? g.hasMatches : ""}`,
                      onClick: (i) => {
                        (i.stopPropagation(),
                          console.log(`Icon click - toggle path: "${v}"`),
                          $(v));
                      },
                      title: u ? "Collapse" : "Expand",
                      children: [
                        "▶",
                        !u &&
                          f &&
                          e.jsx("span", {
                            className: g.matchCount,
                            children: "●",
                          }),
                      ],
                    })
                  : e.jsx("span", { className: g.expandIconPlaceholder }),
                e.jsxs("span", {
                  className: `${g.nodeName} ${I ? g.matchName : ""}`,
                  children: [t, ":"],
                }),
              ],
            }),
            (!u || !G) &&
              e.jsx("div", {
                style: { flex: 1 },
                children: e.jsx("span", {
                  className: `${Z} ${I && !N ? g.matchValue : ""}`,
                  children: R,
                }),
              }),
            x &&
              u &&
              G &&
              me > 0 &&
              e.jsxs("span", {
                className: g.hiddenItemsCount,
                onClick: (i) => {
                  (i.stopPropagation(),
                    window.dispatchEvent(
                      new CustomEvent("toggle-show-all", {
                        detail: { path: v },
                      }),
                    ));
                },
                title: "Click to toggle showing all hidden items",
                children: [me, " hidden ", me === 1 ? "item" : "items"],
              }),
            e.jsxs("div", {
              className: g.actions,
              onClick: (i) => i.stopPropagation(),
              children: [
                e.jsx("button", {
                  className: `${g.actionButton} ${H ? g.copied : ""}`,
                  onClick: ie,
                  title: H ? "Unpin this item" : "Pin this item",
                  children: H ? "📌" : "📍",
                }),
                e.jsx("button", {
                  className: g.actionButton,
                  onClick: (i) => {
                    (i.stopPropagation(),
                      window.dispatchEvent(
                        new CustomEvent("search-node-value", {
                          detail: {
                            path: v,
                            value: N ? JSON.stringify(s) : String(s),
                          },
                        }),
                      ));
                  },
                  title: "Search for this value",
                  children: "🔍",
                }),
                e.jsx("button", {
                  className: `${g.actionButton} ${A ? g[A] : ""}`,
                  onClick: se,
                  title: "Copy path",
                  children: "path",
                }),
                e.jsx("button", {
                  className: `${g.actionButton} ${B ? g[B] : ""}`,
                  onClick: ne,
                  title: "Copy value",
                  children: "copy",
                }),
              ],
            }),
          ],
        }),
        u &&
          G &&
          (K
            ? l()
            : e.jsx("div", {
                className: g.children,
                children: Object.entries(s).map(([i, n]) =>
                  e.jsx(
                    be,
                    {
                      name: i,
                      value: n,
                      depth: r + 1,
                      path: [...m, t],
                      searchTerm: x,
                      matchingPaths: h,
                      matchCounts: c,
                      autoExpandSearchResults: T,
                      showSiblings: k,
                      showOnlyPinned: P,
                      pinnedPaths: F,
                      onPin: q,
                      activePath: W,
                    },
                    `${v}.${i}`,
                  ),
                ),
              })),
      ],
    });
  },
  be = o.memo(Js, (t, s) => {
    const r = [...t.path, t.name].join("."),
      m = [...s.path, s.name].join(".");
    let x = "";
    t.path.length > 0 ? (x = t.path[0]) : t.name && (x = t.name);
    const h = (x && t.matchCounts?.[x]) || 0,
      c = (x && s.matchCounts?.[x]) || 0;
    return (
      t.value === s.value &&
      t.matchingPaths.has(r) === s.matchingPaths.has(m) &&
      t.pinnedPaths.has(r) === s.pinnedPaths.has(m) &&
      t.searchTerm === s.searchTerm &&
      h === c &&
      t.autoExpandSearchResults === s.autoExpandSearchResults &&
      t.showSiblings === s.showSiblings &&
      t.showOnlyPinned === s.showOnlyPinned &&
      t.activePath === s.activePath
    );
  }),
  zs = () => {
    try {
      const t = localStorage.getItem("objectExplorer.searchHistory");
      return t ? JSON.parse(t) : [];
    } catch (t) {
      return (
        console.error("Failed to load search history from localStorage", t),
        []
      );
    }
  },
  Gs = () => {
    try {
      const t = localStorage.getItem("objectExplorer.pinnedPaths");
      return t ? JSON.parse(t) : [];
    } catch (t) {
      return (
        console.error("Failed to load pinned paths from localStorage", t),
        []
      );
    }
  },
  Us = () => {
    try {
      const t = localStorage.getItem("objectExplorer.expandedPaths");
      return t ? JSON.parse(t) : [];
    } catch (t) {
      return (
        console.error("Failed to load expanded paths from localStorage", t),
        []
      );
    }
  },
  ce = ({ data: t, initialExpandLevel: s = "all" }) => {
    const [r, m] = o.useState(""),
      [x, h] = o.useState(zs),
      [c, T] = o.useState(!1),
      [k, P] = o.useState(new Set(Us())),
      [F, q] = o.useState(new Set()),
      [W, D] = o.useState(!0),
      [$, v] = o.useState(!0),
      [u, M] = o.useState(new Set(Gs())),
      [N, K] = o.useState(""),
      [G, R] = o.useState({}),
      [I, f] = o.useState(!1),
      O = o.useRef(null),
      H = o.useCallback((l) => {
        (console.log(`Toggle path called with: ${l}`),
          P((E) => {
            const b = new Set(E);
            return (
              b.has(l)
                ? (console.log(`Removing path from expanded: ${l}`),
                  b.delete(l))
                : (console.log(`Adding path to expanded: ${l}`), b.add(l)),
              b
            );
          }));
      }, []),
      z = o.useMemo(() => ({ expandedPaths: k, togglePath: H }), [k, H]),
      B = o.useMemo(() => {
        try {
          return Ae(t);
        } catch {
          return t;
        }
      }, [t]),
      V = o.useRef(B);
    (o.useEffect(() => {
      const l = new Set(),
        E = (p, j = []) => {
          const S = j.join(".");
          (S && l.add(S),
            p &&
              typeof p == "object" &&
              (Array.isArray(p)
                ? p.forEach((i, n) => {
                    const d = `[${n}]`,
                      _ = j.length
                        ? [...j.slice(0, -1), j[j.length - 1] + d]
                        : [d],
                      y = _.join(".");
                    (y && l.add(y),
                      typeof i == "object" && i !== null && E(i, _));
                  })
                : Object.entries(p).forEach(([i, n]) => {
                    const d = [...j, i],
                      _ = d.join(".");
                    (_ && l.add(_), n && typeof n == "object" && E(n, d));
                  })));
        },
        b = (p, j = [], S = 0) => {
          const i = typeof s == "number" ? s : 1 / 0;
          if (S >= i) return;
          const n = j.join(".");
          (n && l.add(n),
            p &&
              typeof p == "object" &&
              (Array.isArray(p)
                ? S < i - 1 &&
                  p.forEach((d, _) => {
                    const y = `[${_}]`,
                      w = j.length
                        ? [...j.slice(0, -1), j[j.length - 1] + y]
                        : [y],
                      L = w.join(".");
                    (L && l.add(L),
                      typeof d == "object" && d !== null && b(d, w, S + 1));
                  })
                : Object.entries(p).forEach(([d, _]) => {
                    const y = [...j, d],
                      w = y.join(".");
                    (w && l.add(w),
                      _ && typeof _ == "object" && b(_, y, S + 1));
                  })));
        };
      (s === "all" ? E(t) : b(t),
        console.log("Initial expanded paths:", Array.from(l)),
        P(l));
    }, [t, s]),
      o.useEffect(() => {
        if (!r || (x.length > 0 && x[0] === r)) return;
        const l = [r, ...x.filter((E) => E !== r)].slice(0, 10);
        h(l);
        try {
          localStorage.setItem(
            "objectExplorer.searchHistory",
            JSON.stringify(l),
          );
        } catch (E) {
          console.error("Failed to save search history to localStorage", E);
        }
      }, [r, x]),
      o.useEffect(() => {
        try {
          localStorage.setItem(
            "objectExplorer.pinnedPaths",
            JSON.stringify([...u]),
          );
        } catch (l) {
          console.error("Failed to save pinned paths to localStorage", l);
        }
      }, [u]),
      o.useEffect(() => {
        const l = setTimeout(() => {
          try {
            localStorage.setItem(
              "objectExplorer.expandedPaths",
              JSON.stringify([...k]),
            );
          } catch (E) {
            console.error("Failed to save expanded paths to localStorage", E);
          }
        }, 1e3);
        return () => clearTimeout(l);
      }, [k]),
      o.useEffect(() => {
        if (!r) {
          (q(new Set()), R({}));
          return;
        }
        const l = r.toLowerCase(),
          E = new Set(),
          b = new Set(),
          p = {},
          j = (n) => {
            if (!n) return;
            (E.add(n), b.add(n));
            let d = n.split(".")[0];
            (d.includes("[") && ((d = d.split("[")[0]), d || (d = "[0]")),
              d &&
                ((p[d] = (p[d] || 0) + 1),
                console.log(`Added match to ${d}, now has ${p[d]}`)));
            const _ = n.split(".");
            let y = "";
            for (let w = 0; w < _.length; w++) {
              const L = _[w];
              if (L.includes("[")) {
                const ee = L.split("[")[0];
                ((y = y ? `${y}.${ee}` : ee), b.add(y));
                const ae = L.match(/\[\d+\]/g) || [];
                for (const oe of ae) ((y += oe), b.add(y));
              } else ((y = y ? `${y}.${L}` : L), b.add(y));
            }
          },
          S = (n, d) => {
            if (!$ || !n || !d || typeof d != "object") return;
            const _ = n.lastIndexOf("."),
              y = _ > -1 ? n.substring(0, _) : "";
            if (Array.isArray(d)) {
              const w = n.lastIndexOf("["),
                L = n.lastIndexOf("]");
              if (w > -1 && L > w) {
                const ee = n.substring(w + 1, L),
                  ae = parseInt(ee);
                if (!isNaN(ae)) {
                  const oe = Math.max(0, ae - 2),
                    fe = Math.min(d.length, ae + 3);
                  for (let pe = oe; pe < fe; pe++)
                    if (pe !== ae) {
                      const Te = `${n.substring(0, w)}[${pe}]`;
                      b.add(Te);
                    }
                }
              }
            } else
              Object.keys(d).forEach((w) => {
                const L = y ? `${y}.${w}` : w;
                b.add(L);
              });
          },
          i = (n, d = "") => {
            if (n == null) return;
            let _ = "";
            if (
              (d &&
                ((_ = d.split(".")[0]),
                _.includes("[") &&
                  ((_ = _.split("[")[0]),
                  _ || (_ = /\[\d+\]/.exec(d)?.[0] || ""))),
              typeof n != "object")
            ) {
              String(n).toLowerCase().includes(l) &&
                (j(d),
                _ &&
                  !p[_] &&
                  ((p[_] = 1),
                  console.log(`Added first match for top-level key: ${_}`)));
              return;
            }
            Array.isArray(n)
              ? n.forEach((y, w) => {
                  const L = d ? `${d}[${w}]` : `[${w}]`;
                  if (
                    y !== null &&
                    typeof y != "object" &&
                    String(y).toLowerCase().includes(l) &&
                    (j(L),
                    d && b.add(d),
                    _ &&
                      !p[_] &&
                      ((p[_] = 1),
                      console.log(
                        `Added first match for top-level key from array: ${_}`,
                      )),
                    $)
                  ) {
                    const ee = Math.max(0, w - 2),
                      ae = Math.min(n.length, w + 3);
                    for (let oe = ee; oe < ae; oe++)
                      if (oe !== w) {
                        const fe = d ? `${d}[${oe}]` : `[${oe}]`;
                        b.add(fe);
                      }
                  }
                  i(y, L);
                })
              : Object.entries(n).forEach(([y, w]) => {
                  const L = d ? `${d}.${y}` : y;
                  (y.toLowerCase().includes(l) &&
                    (j(L),
                    _ &&
                      !p[_] &&
                      ((p[_] = 1),
                      console.log(
                        `Added first match for top-level key from key match: ${_}`,
                      )),
                    S(L, n)),
                    w !== null &&
                      typeof w != "object" &&
                      String(w).toLowerCase().includes(l) &&
                      (j(L),
                      _ &&
                        !p[_] &&
                        ((p[_] = 1),
                        console.log(
                          `Added first match for top-level key from value match: ${_}`,
                        )),
                      S(L, n)),
                    i(w, L));
                });
          };
        if (
          (Object.keys(B).forEach((n) => {
            n.toLowerCase().includes(l) &&
              (E.add(n),
              b.add(n),
              (p[n] = (p[n] || 0) + 1),
              console.log(`Root key "${n}" matches search term directly`));
          }),
          i(B),
          Object.keys(p).forEach((n) => {
            p[n] > 0 &&
              (b.add(n),
              console.log(
                `Ensuring root key "${n}" with ${p[n]} matches is in relevant paths`,
              ));
          }),
          console.log(
            `Search '${r}': ${E.size} direct matches, ${b.size} total paths to show, Top matches:`,
            p,
          ),
          q(b),
          R(p),
          W && E.size > 0)
        ) {
          const n = new Set(k);
          (Object.keys(p).forEach((d) => {
            p[d] > 0 && n.add(d);
          }),
            b.forEach((d) => {
              const _ = d.split(".");
              let y = "";
              for (let w = 0; w < _.length - 1; w++)
                if (_[w].includes("[")) {
                  const L = _[w].split("[")[0];
                  ((y = y ? `${y}.${L}` : L), n.add(y));
                  const ee = _[w].match(/\[\d+\]/g) || [];
                  for (const ae of ee) ((y += ae), n.add(y));
                } else ((y = y ? `${y}.${_[w]}` : _[w]), n.add(y));
            }),
            P(n));
        }
      }, [r, B, $, W, k]));
    const A = o.useCallback((l) => {
        M((E) => {
          const b = new Set(E);
          return (
            b.has(l)
              ? b.delete(l)
              : (b.add(l),
                P((p) => {
                  const j = new Set(p),
                    S = l.split(/\.|\[/);
                  let i = "";
                  for (let n = 0; n < S.length; n++)
                    (n === 0
                      ? (i = S[n])
                      : S[n].endsWith("]")
                        ? (i += S[n])
                        : (i += `.${S[n]}`),
                      i && j.add(i));
                  return j;
                })),
            b
          );
        });
      }, []),
      Y = o.useCallback(() => {
        const l = [],
          E = (b, p = []) => {
            const j = p.join(".");
            (j && l.push(j),
              b &&
                typeof b == "object" &&
                (Array.isArray(b)
                  ? b.forEach((S, i) => {
                      const n = [...p];
                      if (n.length > 0) {
                        const _ = n[n.length - 1];
                        n[n.length - 1] = `${_}[${i}]`;
                      } else n.push(`[${i}]`);
                      const d = n.join(".");
                      (d && l.push(d), S && typeof S == "object" && E(S, n));
                    })
                  : Object.entries(b).forEach(([S, i]) => {
                      const n = [...p, S],
                        d = n.join(".");
                      (d && l.push(d), i && typeof i == "object" && E(i, n));
                    })));
          };
        (E(B), P(new Set(l)));
      }, [B]),
      ne = o.useCallback(() => {
        P(new Set());
      }, []),
      se = o.useRef(null),
      [Z, ie] = o.useState(!1);
    o.useEffect(() => {
      const l = (p) => {
          p.detail &&
            p.detail.path !== void 0 &&
            (K(p.detail.path),
            setTimeout(() => {
              const j = document.getElementById(
                `path-${p.detail.path.replace(/\./g, "-")}`,
              );
              j &&
                (j.scrollIntoView({ behavior: "smooth", block: "center" }),
                j.classList.add("flashActive"),
                setTimeout(() => {
                  j.classList.remove("flashActive");
                }, 600));
            }, 50));
        },
        E = (p) => {
          if (p.detail?.value) {
            let j = p.detail.value;
            if (j.startsWith("{") || j.startsWith("["))
              try {
                const S = JSON.parse(j);
                if (typeof S == "object" && S !== null) {
                  for (const i in S)
                    if (typeof S[i] == "string" || typeof S[i] == "number") {
                      j = String(S[i]);
                      break;
                    }
                }
              } catch {
                j.length > 50 && (j = j.substring(0, 50));
              }
            (m(j), O.current && O.current.focus());
          }
        },
        b = (p) => {
          (ie((j) => !j), Z || Y());
        };
      return (
        window.addEventListener("set-active-path", l),
        window.addEventListener("search-node-value", E),
        window.addEventListener("toggle-show-all", b),
        () => {
          (window.removeEventListener("set-active-path", l),
            window.removeEventListener("search-node-value", E),
            window.removeEventListener("toggle-show-all", b));
        }
      );
    }, [Z, Y]);
    const me = o.useCallback(() => {
        (se.current &&
          (se.current.classList.add(g.copied),
          setTimeout(() => {
            se.current && se.current.classList.remove(g.copied);
          }, 800)),
          ue(JSON.stringify(B, null, 2)));
      }, [B]),
      he = o.useCallback(() => {
        if (!r) return;
        const l = new Set();
        (Object.keys(G).forEach((E) => {
          l.add(E);
        }),
          F.forEach((E) => {
            E && l.add(E);
            const b = E.split(".");
            let p = "";
            for (let j = 0; j < b.length; j++)
              if (b[j].includes("[")) {
                const S = b[j].split("[")[0];
                ((p = p ? `${p}.${S}` : S), l.add(p));
                const i = b[j].match(/\[\d+\]/g) || [];
                let n = p;
                for (const d of i) ((n += d), l.add(n));
              } else ((p = p ? `${p}.${b[j]}` : b[j]), l.add(p));
          }),
          console.log("Expanding paths for matches:", l.size),
          P(l));
      }, [r, F, G]);
    return (
      o.useEffect(() => {
        V.current = B;
      }, [B]),
      o.useEffect(() => {
        const l = Object.keys(V.current || {})
            .sort()
            .join(","),
          E = Object.keys(B || {})
            .sort()
            .join(",");
        if (l !== E && l !== "" && E !== "") {
          const b = new Set(),
            p = (j, S = [], i = 0) => {
              if (i >= (typeof s == "number" ? s : 2)) return;
              const d = S.join(".");
              (d && b.add(d),
                j &&
                  typeof j == "object" &&
                  Object.entries(j).forEach(([_, y]) => {
                    const w = [...S, _],
                      L = w.join(".");
                    (L && b.add(L),
                      y && typeof y == "object" && p(y, w, i + 1));
                  }));
            };
          (p(B), P(b));
        }
      }, [B, s]),
      e.jsx(ve.Provider, {
        value: z,
        "data-sentry-element": "ExpandedPathsContext.Provider",
        "data-sentry-component": "ObjectExplorer",
        "data-sentry-source-file": "ObjectExplorer.tsx",
        children: e.jsxs("div", {
          className: g.viewer,
          children: [
            e.jsxs("div", {
              className: g.toolbar,
              children: [
                e.jsx("div", {
                  className: g.searchRow,
                  children: e.jsxs("div", {
                    className: g.searchInputWrapper,
                    children: [
                      e.jsx("input", {
                        ref: O,
                        type: "text",
                        className: g.searchInput,
                        placeholder: "Search keys and values...",
                        value: r,
                        onChange: (l) => m(l.target.value),
                        onKeyDown: (l) => {
                          (l.key === "ArrowDown" &&
                            !c &&
                            x.length > 0 &&
                            (T(!0), l.preventDefault()),
                            l.key === "Escape" &&
                              (l.preventDefault(), m(""), O.current?.blur()));
                        },
                        onFocus: () => {
                          x.length > 0 && T(!0);
                        },
                        onBlur: (l) => {
                          (!l.relatedTarget ||
                            !l.relatedTarget.closest(
                              `.${g.searchHistoryDropdown}`,
                            )) &&
                            setTimeout(() => T(!1), 150);
                        },
                      }),
                      r &&
                        e.jsxs("div", {
                          className: g.searchInfo,
                          children: [
                            F.size,
                            " match",
                            F.size !== 1 ? "es" : "",
                            F.size > 0 &&
                              e.jsx("button", {
                                onClick: () => {
                                  (ie(!Z), Z || (W ? Y() : he()));
                                },
                                style: {
                                  marginLeft: "8px",
                                  background: Z ? "#2c71a7" : "#333",
                                  color: "#fff",
                                  border: "none",
                                  padding: "2px 6px",
                                  borderRadius: "2px",
                                  fontSize: "10px",
                                  cursor: "pointer",
                                },
                                title: Z
                                  ? "Hide non-matching items"
                                  : "Show all items including non-matches",
                                children: Z ? "Showing All" : "Filter View",
                              }),
                          ],
                        }),
                      x.length > 0 &&
                        e.jsx("button", {
                          className: g.searchHistoryButton,
                          onClick: () => T(!c),
                          title: "Search history",
                          children: "⌄",
                        }),
                      c &&
                        x.length > 0 &&
                        e.jsx("div", {
                          className: g.searchHistoryDropdown,
                          children: x.map((l, E) =>
                            e.jsx(
                              "div",
                              {
                                className: g.searchHistoryItem,
                                onClick: () => {
                                  (m(l), T(!1), O.current && O.current.focus());
                                },
                                children: l,
                              },
                              E,
                            ),
                          ),
                        }),
                    ],
                  }),
                }),
                e.jsxs("div", {
                  className: g.controlsRow,
                  children: [
                    e.jsx("div", {
                      className: g.pathContainer,
                      children:
                        N &&
                        e.jsxs("div", {
                          className: g.pathNavigator,
                          children: [
                            e.jsx("span", { children: "Path:" }),
                            N.split(/\.|\[/)
                              .filter(Boolean)
                              .map((l, E, b) =>
                                e.jsxs(
                                  Ce.Fragment,
                                  {
                                    children: [
                                      e.jsx("span", {
                                        className: `${g.pathSegment} ${E === b.length - 1 ? g.active : ""}`,
                                        onClick: () => {
                                          const p = b.slice(0, E + 1).join(".");
                                          (k.has(p) ||
                                            P((j) => {
                                              const S = new Set(j);
                                              return (S.add(p), S);
                                            }),
                                            setTimeout(() => {
                                              const j = document.getElementById(
                                                `path-${p.replace(/\./g, "-")}`,
                                              );
                                              j &&
                                                j.scrollIntoView({
                                                  behavior: "smooth",
                                                  block: "center",
                                                });
                                            }, 100));
                                        },
                                        onDoubleClick: () => {
                                          const p = b.slice(0, E + 1).join(".");
                                          if (N === p) {
                                            window.dispatchEvent(
                                              new CustomEvent(
                                                "set-active-path",
                                                { detail: { path: "" } },
                                              ),
                                            );
                                            return;
                                          }
                                          window.dispatchEvent(
                                            new CustomEvent("set-active-path", {
                                              detail: { path: p },
                                            }),
                                          );
                                        },
                                        children: l,
                                      }),
                                      E < b.length - 1 &&
                                        e.jsx("span", {
                                          className: g.pathSeparator,
                                          children: ".",
                                        }),
                                    ],
                                  },
                                  E,
                                ),
                              ),
                          ],
                        }),
                    }),
                    e.jsxs("div", {
                      className: g.controls,
                      children: [
                        e.jsxs("label", {
                          className: g.autoExpandCheckbox,
                          children: [
                            e.jsx("input", {
                              type: "checkbox",
                              checked: W,
                              onChange: () => D(!W),
                            }),
                            "Auto-expand",
                          ],
                        }),
                        e.jsxs("label", {
                          className: g.autoExpandCheckbox,
                          children: [
                            e.jsx("input", {
                              type: "checkbox",
                              checked: $,
                              onChange: () => v(!$),
                            }),
                            "Show Siblings",
                          ],
                        }),
                        e.jsxs("label", {
                          className: g.autoExpandCheckbox,
                          children: [
                            e.jsx("input", {
                              type: "checkbox",
                              checked: I,
                              onChange: () => f(!I),
                            }),
                            "Show Only Pinned",
                          ],
                        }),
                        r &&
                          e.jsx("button", {
                            className: g.controlButton,
                            onClick: he,
                            children: "Expand Matches",
                          }),
                        e.jsx("button", {
                          className: g.controlButton,
                          onClick: Y,
                          children: "Expand All",
                        }),
                        e.jsx("button", {
                          className: g.controlButton,
                          onClick: ne,
                          children: "Collapse All",
                        }),
                        e.jsx("button", {
                          ref: se,
                          className: g.controlButton,
                          onClick: me,
                          children: "Copy All",
                        }),
                        u.size > 0 &&
                          e.jsxs("button", {
                            className: g.controlButton,
                            onClick: () => M(new Set()),
                            title: "Clear all pinned items",
                            children: ["Clear Pins (", u.size, ")"],
                          }),
                      ],
                    }),
                  ],
                }),
              ],
            }),
            e.jsx("div", {
              className: g.objectTree,
              children:
                Object.keys(B).length === 0
                  ? e.jsx("div", {
                      className: g.emptyObject,
                      children: "Empty object",
                    })
                  : r && F.size === 0
                    ? e.jsxs("div", {
                        className: g.noMatches,
                        children: ['No matches found for "', r, '"'],
                      })
                    : e.jsxs("div", {
                        children: [
                          r &&
                            e.jsxs("div", {
                              className: g.matchDebug,
                              style: {
                                fontSize: "12px",
                                color: "#666",
                                padding: "8px",
                                background: "#f5f5f5",
                                borderBottom: "1px solid #ddd",
                                marginBottom: "8px",
                              },
                              children: [
                                e.jsxs("div", {
                                  children: [
                                    e.jsx("strong", { children: "Search:" }),
                                    ' "',
                                    r,
                                    '" - Found ',
                                    F.size,
                                    " paths",
                                  ],
                                }),
                                e.jsxs("div", {
                                  children: [
                                    e.jsx("strong", {
                                      children: "Matches per section:",
                                    }),
                                    " ",
                                    Object.entries(G)
                                      .map(([l, E]) =>
                                        E > 0 ? `${l}(${E})` : "",
                                      )
                                      .filter(Boolean)
                                      .join(", "),
                                  ],
                                }),
                                e.jsxs("div", {
                                  style: {
                                    fontSize: "10px",
                                    maxHeight: "80px",
                                    overflow: "auto",
                                  },
                                  children: [
                                    e.jsx("strong", {
                                      children: "First 10 matching paths:",
                                    }),
                                    " ",
                                    Array.from(F).slice(0, 10).join(", "),
                                  ],
                                }),
                              ],
                            }),
                          Object.entries(B).map(([l, E]) => {
                            if (
                              (console.log(
                                `Checking root key: ${l}, hasMatches: ${G[l] > 0}, inPaths: ${F.has(l)}`,
                              ),
                              r)
                            )
                              (G[l] > 0 || F.has(l)) &&
                                console.log(
                                  `Root key "${l}" has ${G[l] || 0} matches`,
                                );
                            else if (I) {
                              const j = u.has(l),
                                S = Array.from(u).some(
                                  (i) =>
                                    i.startsWith(`${l}.`) ||
                                    i.startsWith(`${l}[`),
                                );
                              if (!j && !S) return null;
                            }
                            const b = G[l] || 0,
                              p =
                                r && b > 0
                                  ? `${l} (${b} match${b !== 1 ? "es" : ""})`
                                  : l;
                            return e.jsx(
                              be,
                              {
                                name: p,
                                value: E,
                                depth: 0,
                                path: [],
                                searchTerm: r,
                                matchingPaths: F,
                                matchCounts: G,
                                autoExpandSearchResults: W,
                                showSiblings: $,
                                showOnlyPinned: I,
                                pinnedPaths: u,
                                onPin: A,
                                activePath: N,
                              },
                              l,
                            );
                          }),
                          r &&
                            F.size > 0 &&
                            Object.values(G).every((l) => l === 0) &&
                            e.jsxs("div", {
                              style: {
                                padding: "12px",
                                color: "#d32f2f",
                                background: "#ffebee",
                                borderRadius: "4px",
                              },
                              children: [
                                e.jsx("strong", { children: "Error:" }),
                                " Found ",
                                F.size,
                                " paths but no items were matched correctly. This is likely a bug in the path handling logic.",
                              ],
                            }),
                        ],
                      }),
            }),
          ],
        }),
      })
    );
  },
  xe = ({ tab: t, currentTab: s, onClick: r, label: m }) =>
    e.jsx("button", {
      type: "button",
      className: `${J.tabButton} ${s === t ? J.activeTab : ""}`,
      onClick: () => r(t),
      "data-sentry-component": "TabButton",
      "data-sentry-source-file": "RoomStateExplorer.tsx",
      children: m,
    }),
  qs = de(({ wss: t }) => {
    const [s, r] = o.useState("mobx"),
      [m, x] = o.useState(null),
      [h, c] = o.useState(!1),
      [T, k] = o.useState(null),
      [P, F] = o.useState(!1);
    o.useEffect(() => {
      if (!t?.selectedThread?.id) return;
      async function u() {
        try {
          (c(!0), k(null));
          const M = t?.selectedThread;
          if (!M) return;
          const N = M.id,
            [K, G] = await Promise.all([
              Q.bapi.debug_getRoom(N),
              Q.database.getUnreadMessages(
                N,
                Q.beeperClientStore.state.user_id,
              ),
            ]),
            R = M;
          x({
            matrixState: K?.state || {},
            mobxState: R.stringifiableDebugInfo || {},
            databaseState: { thread: K?.thread || {}, unreadMessages: G },
            messagesState: {},
          });
        } catch (M) {
          (console.error("Failed to load room state:", M),
            k(M.message || "Failed to load room state"));
        } finally {
          c(!1);
        }
      }
      u();
    }, [t?.selectedThread?.id]);
    const q = o.useCallback(async () => {
        if (t?.selectedThread)
          try {
            (c(!0),
              k(null),
              await Q.bapi.refetchRoomStates([t.selectedThread.id]),
              x(null));
          } catch (u) {
            (console.error("Error resyncing room state:", u),
              k(`Error resyncing: ${u.message}`));
          } finally {
            c(!1);
          }
      }, [t?.selectedThread]),
      W = o.useCallback(() => {
        t?.selectedThread &&
          (ue(t.selectedThread.id), F(!0), setTimeout(() => F(!1), 1e3));
      }, [t?.selectedThread]);
    if (!t?.selectedThread || !(t.selectedThread instanceof De))
      return e.jsx("div", {
        className: J.roomStateExplorer,
        children: e.jsxs("div", {
          className: J.emptyState,
          children: [
            e.jsx("span", { className: J.emoji, children: "🔍" }),
            e.jsx("h2", { children: "No thread selected" }),
            e.jsx("p", { children: "Select a thread to explore its state" }),
          ],
        }),
      });
    const D = t.selectedThread;
    function $(u) {
      return u
        ? {
            id: u.id,
            senderID: u.senderID,
            threadID: u.threadID,
            accountID: u.accountID,
            timestamp: u.timestamp,
            isSender: u.isSender,
            isAction: u.isAction,
            text: Ie(u.text, { length: 100 }),
            eventID: u.extra?.eventID,
            type: u.extra?.type,
            action: u.action,
            impersonator: u.impersonator,
            participant: u.senderID ? D.getParticipant(u.senderID) : void 0,
          }
        : null;
    }
    const v = () => {
      if (!m) return null;
      switch (s) {
        case "mobx":
          return e.jsx(ce, {
            data: {
              thread: D?.stringifiableDebugInfo,
              typedMessage: je(D?.roomFeatures.formatting, D?.typedJSON),
              participants: D?.debugParticipants,
            },
            initialExpandLevel: 3,
          });
        case "matrix":
          return e.jsx(ce, { data: m.matrixState, initialExpandLevel: 3 });
        case "database":
          return e.jsx(ce, { data: m.databaseState, initialExpandLevel: 3 });
        case "messages":
          return e.jsx(ce, {
            data: {
              input: je(D?.roomFeatures.formatting, D?.typedJSON),
              lastPendingMessage: D.lastPendingMessage
                ? $(D.lastPendingMessage)
                : null,
              lastNonSilentMessage: D.lastNonSilentMessage
                ? $(D.lastNonSilentMessage)
                : null,
              messagesLastItem: D.messages.lastItem
                ? $(D.messages.lastItem)
                : null,
              partialLastMessage: D.partialLastMessage
                ? $(D.partialLastMessage)
                : null,
              selectedMessages:
                Q?.mainWSS.selectedThread?.id === D.id
                  ? Q?.mainWSS.selectedMessagesList.map((u) => $(u))
                  : "Main window is not focused on this chat",
              pendingMessages:
                Q?.mainWSS.selectedThread?.id === D.id
                  ? Array.from(
                      Q?.mainWSS.selectedThread?.pendingMessages.values() || [],
                    ).map((u) => $(u))
                  : "Main window is not focused on this chat",
            },
            initialExpandLevel: 3,
          });
        default:
          return null;
      }
    };
    return e.jsxs("div", {
      className: J.roomStateExplorer,
      children: [
        e.jsxs("div", {
          className: `${J.header} app-region-drag`,
          children: [
            e.jsxs("div", {
              className: J.headerContent,
              children: [
                e.jsx("div", {
                  className: J.headerInfo,
                  children: e.jsxs("div", {
                    className: J.headerText,
                    children: [
                      e.jsxs("h1", {
                        className: J.headerTitle,
                        children: [
                          "🔍 Room: ",
                          e.jsx("span", {
                            title: D.computedTitle || "",
                            children: D.computedTitle || "No computed title",
                          }),
                        ],
                      }),
                      e.jsx("div", {
                        className: J.headerRoomId,
                        title: D.id,
                        children: D.id,
                      }),
                    ],
                  }),
                }),
                e.jsxs("div", {
                  className: J.headerActions,
                  children: [
                    e.jsx("button", {
                      className: J.actionButton,
                      onClick: W,
                      disabled: h,
                      title: "Copy room ID to clipboard",
                      style: P
                        ? { backgroundColor: "#2ecc71", color: "#ffffff" }
                        : void 0,
                      children: P ? "✓ Copied" : "Copy ID",
                    }),
                    e.jsx("button", {
                      className: `${J.actionButton} ${J.primaryButton}`,
                      onClick: q,
                      disabled: h,
                      title: "Re-sync room state from server",
                      children: h ? "Loading..." : "Re-sync",
                    }),
                  ],
                }),
              ],
            }),
            e.jsxs("div", {
              className: J.tabBar,
              children: [
                e.jsx(xe, {
                  tab: "mobx",
                  currentTab: s,
                  onClick: r,
                  label: "MobX",
                }),
                e.jsx(xe, {
                  tab: "database",
                  currentTab: s,
                  onClick: r,
                  label: "Database",
                }),
                e.jsx(xe, {
                  tab: "messages",
                  currentTab: s,
                  onClick: r,
                  label: "Messages",
                }),
                e.jsx(xe, {
                  tab: "matrix",
                  currentTab: s,
                  onClick: r,
                  label: "Matrix",
                }),
              ],
            }),
            T &&
              e.jsxs("div", {
                className: J.errorBar,
                children: [
                  e.jsx("span", { className: J.errorIcon, children: "⚠️" }),
                  e.jsx("span", { className: J.errorMessage, children: T }),
                ],
              }),
            h &&
              e.jsx("div", {
                className: J.statusBar,
                children: e.jsxs("div", {
                  className: J.statusLoading,
                  children: [
                    e.jsx("div", { className: J.loadingSpinner }),
                    e.jsx("span", { children: "Loading room state..." }),
                  ],
                }),
              }),
          ],
        }),
        e.jsx("div", {
          className: J.contentContainer,
          children:
            h && !m
              ? e.jsxs("div", {
                  className: J.loadingState,
                  children: [
                    e.jsx("div", { className: J.loadingSpinner }),
                    e.jsx("span", { children: "Loading room state..." }),
                  ],
                })
              : v(),
        }),
      ],
    });
  }),
  Qs = "EventExplorer-module__header",
  Ys = "EventExplorer-module__eventList",
  Xs = "EventExplorer-module__title",
  Zs = "EventExplorer-module__subtitle",
  ea = "EventExplorer-module__searchInput",
  ta = "EventExplorer-module__event",
  sa = "EventExplorer-module__wrapper",
  te = {
    header: Qs,
    eventList: Ys,
    title: Xs,
    subtitle: Zs,
    searchInput: ea,
    event: ta,
    wrapper: sa,
  },
  aa = ({ item: t, expanded: s, setExpanded: r }) => {
    const m = t.normalizedTimestamp,
      x = t.normalizedType;
    return e.jsxs("section", {
      className: Fe(te.event, { [te.isExpanded]: s }),
      "data-sentry-component": "ExpandableEvent",
      "data-sentry-source-file": "EventExplorer.tsx",
      children: [
        e.jsxs("header", {
          onClick: () => r(!s),
          children: [
            e.jsx("div", { children: x }),
            e.jsx("div", {
              className: te.timestamp,
              children: new Date(m ?? 0).toISOString().slice(0, -5),
            }),
          ],
        }),
        s && e.jsx(ce, { data: t }),
      ],
    });
  },
  oa = de(({ wss: t, eventID: s }) => {
    const [r, m] = o.useState([]),
      [x, h] = o.useState(!0),
      [c, T] = o.useState(null),
      [k, P] = o.useState(""),
      [F, q] = o.useState(new Set()),
      W = o.useCallback(
        async (u) => {
          if (!(!t?.selectedThread?.id || !u))
            try {
              const M = t.selectedThread.id,
                N = await Q.bapi.fetchEventExplorerData(M, u);
              m(N);
            } catch (M) {
              T(`Error fetching data: ${M.message}`);
            }
        },
        [t?.selectedThread?.id],
      );
    o.useEffect(() => {
      (h(!0), T(null), m([]), W(s).finally(() => h(!1)));
    }, [s, W]);
    const D = (u) => {
        q((M) => {
          const N = new Set(M);
          return (N.has(u) ? N.delete(u) : N.add(u), N);
        });
      },
      $ = o.useMemo(() => Le((u) => P(u), 300), [P]),
      v = o.useMemo(
        () =>
          r.filter(
            (u) =>
              u.normalizedType.toLowerCase().includes(k.toLowerCase()) ||
              JSON.stringify(u).toLowerCase().includes(k.toLowerCase()),
          ),
        [r, k],
      );
    return c
      ? e.jsxs("div", { className: te.error, children: ["Error: ", c] })
      : e.jsxs("div", {
          className: `${te.wrapper} app-region-drag`,
          children: [
            e.jsxs("header", {
              className: `${te.header}`,
              children: [
                e.jsx("h3", { className: te.title, children: "Debug Event" }),
                e.jsx("h3", { className: te.subtitle, children: s }),
                e.jsx("input", {
                  type: "text",
                  onChange: (u) => $(u.target.value),
                  className: te.searchInput,
                  placeholder: "Filter by type or content...",
                  autoFocus: !0,
                }),
              ],
            }),
            x &&
              e.jsx("div", {
                className: te.loading,
                children: "Loading events and messages...",
              }),
            e.jsx("div", {
              className: te.eventList,
              children: v.map((u) =>
                e.jsx(
                  aa,
                  {
                    item: u,
                    expanded: F.has(u.normalizedID),
                    setExpanded: () => D(u.normalizedID),
                  },
                  u.normalizedID,
                ),
              ),
            }),
          ],
        });
  }),
  na = "DebugApp-module__container",
  ra = { container: na },
  la = "DataExplorer-module__dataExplorer",
  ca = "DataExplorer-module__header",
  ia = "DataExplorer-module__headerContent",
  da = "DataExplorer-module__headerInfo",
  ma = "DataExplorer-module__headerIcon",
  ua = "DataExplorer-module__headerText",
  ha = "DataExplorer-module__headerTitle",
  pa = "DataExplorer-module__headerActions",
  xa = "DataExplorer-module__actionButton",
  ga = "DataExplorer-module__primaryButton",
  fa = "DataExplorer-module__dropdownMenu",
  _a = "DataExplorer-module__dropdownItem",
  ba = "DataExplorer-module__statusBar",
  ja = "DataExplorer-module__statusLoading",
  ya = "DataExplorer-module__loadingSpinner",
  va = "DataExplorer-module__errorBar",
  Ea = "DataExplorer-module__errorIcon",
  Na = "DataExplorer-module__errorMessage",
  Sa = "DataExplorer-module__contentContainer",
  wa = "DataExplorer-module__loadingState",
  Ta = "DataExplorer-module__emptyState",
  Ca = "DataExplorer-module__emoji",
  Da = "DataExplorer-module__actionResult",
  Ia = "DataExplorer-module__actionResultHeader",
  Fa = "DataExplorer-module__actionResultTitle",
  Pa = "DataExplorer-module__actionResultControls",
  $a = "DataExplorer-module__actionResultContent",
  Oa = "DataExplorer-module__collapseButton",
  C = {
    dataExplorer: la,
    header: ca,
    headerContent: ia,
    headerInfo: da,
    headerIcon: ma,
    headerText: ua,
    headerTitle: ha,
    headerActions: pa,
    actionButton: xa,
    primaryButton: ga,
    dropdownMenu: fa,
    dropdownItem: _a,
    statusBar: ba,
    statusLoading: ja,
    loadingSpinner: ya,
    errorBar: va,
    errorIcon: Ea,
    errorMessage: Na,
    contentContainer: Sa,
    loadingState: wa,
    emptyState: Ta,
    emoji: Ca,
    actionResult: Da,
    actionResultHeader: Ia,
    actionResultTitle: Fa,
    actionResultControls: Pa,
    actionResultContent: $a,
    collapseButton: Oa,
  },
  ka = de(() => {
    const [t, s] = o.useState(null),
      [r, m] = o.useState(null),
      [x, h] = o.useState(null),
      [c, T] = o.useState(!1),
      [k, P] = o.useState(null),
      [F, q] = o.useState(null),
      [W, D] = o.useState(!1),
      [$, v] = o.useState(null),
      [u, M] = o.useState(!1),
      [N, K] = o.useState(!1),
      [G, R] = o.useState(200);
    o.useEffect(() => {
      I();
    }, []);
    const I = async () => {
        (T(!0), P(null));
        try {
          const V = await Q.database.getAllKeyValues(),
            A = {};
          for (const [se, Z] of V)
            try {
              A[se] = Z ? JSON.parse(Z) : null;
            } catch (ie) {
              console.error(`Error parsing key value, key: ${se}`, ie);
            }
          const Y = await Q.database.debug_getDistinctAccountIDs();
          m(Y);
          const ne = await Q.database.debug_roomsWithoutBridgeEvents();
          (h(ne),
            s({ ...A, distinctAccountIDs: Y, roomsWithoutBridgeEvents: ne }));
        } catch (V) {
          (console.error("Error loading data:", V),
            P(V.message || "Failed to load data"));
        } finally {
          T(!1);
        }
      },
      f = async (V, A) => {
        (D(!1), T(!0), P(null), q(null));
        try {
          const Y = await V();
          (q({ action: A, timestamp: new Date().toISOString(), result: Y }),
            M(!0));
        } catch (Y) {
          (console.error("Error executing action:", Y),
            P(Y.message || "Failed to execute action"));
        } finally {
          T(!1);
        }
      },
      O = async () => {
        (D(!1), T(!0), P(null));
        try {
          const V = await Q.bapi.debug_fetchAllAccountData();
          (v(V), s((A) => (A ? { ...A, allAccountData: V } : null)));
        } catch (V) {
          (console.error("Error fetching account data:", V),
            P(V.message || "Failed to fetch account data"));
        } finally {
          T(!1);
        }
      },
      H = () => {
        D(!W);
      },
      z = () => {
        (q(null), M(!1));
      },
      B = () => {
        K(!N);
      };
    return c && !t
      ? e.jsxs("div", {
          className: C.dataExplorer,
          children: [
            e.jsx("div", {
              className: `${C.header} app-region-drag`,
              children: e.jsx("div", {
                className: C.headerContent,
                children: e.jsxs("div", {
                  className: C.headerInfo,
                  children: [
                    e.jsx("span", { className: C.headerIcon, children: "🔍" }),
                    e.jsx("div", {
                      className: C.headerText,
                      children: e.jsx("h1", {
                        className: C.headerTitle,
                        children: "Data Explorer",
                      }),
                    }),
                  ],
                }),
              }),
            }),
            e.jsx("div", {
              className: C.contentContainer,
              children: e.jsxs("div", {
                className: C.loadingState,
                children: [
                  e.jsx("div", { className: C.loadingSpinner }),
                  e.jsx("span", { children: "Loading data..." }),
                ],
              }),
            }),
          ],
        })
      : e.jsxs("div", {
          className: C.dataExplorer,
          children: [
            e.jsx("div", {
              className: `${C.header} app-region-drag`,
              children: e.jsxs("div", {
                className: C.headerContent,
                children: [
                  e.jsxs("div", {
                    className: C.headerInfo,
                    children: [
                      e.jsx("span", {
                        className: C.headerIcon,
                        children: "🔍",
                      }),
                      e.jsx("div", {
                        className: C.headerText,
                        children: e.jsx("h1", {
                          className: C.headerTitle,
                          children: "Data Explorer",
                        }),
                      }),
                    ],
                  }),
                  e.jsxs("div", {
                    className: C.headerActions,
                    children: [
                      e.jsx("button", {
                        className: C.actionButton,
                        onClick: O,
                        disabled: c || !!$,
                        title: "Fetch all account data from the server",
                        children: "Fetch Account Data",
                      }),
                      e.jsx("button", {
                        className: C.actionButton,
                        onClick: I,
                        disabled: c,
                        title: "Refresh all data",
                        children: "Refresh",
                      }),
                      e.jsx("button", {
                        className: `${C.actionButton} ${C.primaryButton}`,
                        onClick: H,
                        disabled: c,
                        title: "Show available actions",
                        children: "Actions",
                      }),
                      W &&
                        e.jsxs("div", {
                          className: C.dropdownMenu,
                          children: [
                            e.jsx("button", {
                              className: C.dropdownItem,
                              onClick: () =>
                                f(
                                  () =>
                                    Q.bapi.debug_refetchRoomStatesForRoomsWithoutBridgeEvents(),
                                  "Refetch Room States",
                                ),
                              children:
                                "Refetch Room States for Rooms Without Bridge Events",
                            }),
                            e.jsx("button", {
                              className: C.dropdownItem,
                              onClick: () =>
                                f(
                                  () => Q.bapi.debug_updateLocalBridgeStates(),
                                  "Update Local Bridge States",
                                ),
                              children: "Update Local Bridge States",
                            }),
                            e.jsx("button", {
                              className: C.dropdownItem,
                              onClick: () =>
                                Q.windowsStore.openCustomEventInNewWindow(
                                  Q.mainWSS,
                                ),
                              children: "Send Custom Event",
                            }),
                          ],
                        }),
                    ],
                  }),
                ],
              }),
            }),
            k &&
              e.jsxs("div", {
                className: C.errorBar,
                children: [
                  e.jsx("span", { className: C.errorIcon, children: "⚠️" }),
                  e.jsx("span", { className: C.errorMessage, children: k }),
                ],
              }),
            c &&
              e.jsx("div", {
                className: C.statusBar,
                children: e.jsxs("div", {
                  className: C.statusLoading,
                  children: [
                    e.jsx("div", { className: C.loadingSpinner }),
                    e.jsx("span", { children: "Loading..." }),
                  ],
                }),
              }),
            e.jsx("div", {
              className: C.contentContainer,
              style: { height: u && !N ? `calc(100% - ${G}px)` : "100%" },
              children: t
                ? e.jsx(ce, {
                    data: { ...t, state: Q.beeperClientStore.state },
                    initialExpandLevel: 0,
                  })
                : e.jsxs("div", {
                    className: C.emptyState,
                    children: [
                      e.jsx("span", { className: C.emoji, children: "📄" }),
                      e.jsx("h2", { children: "No data available" }),
                      e.jsx("p", { children: "Try refreshing to load data" }),
                    ],
                  }),
            }),
            u &&
              e.jsxs("div", {
                className: C.actionResult,
                style: { height: N ? "auto" : `${G}px` },
                children: [
                  e.jsxs("div", {
                    className: C.actionResultHeader,
                    onClick: B,
                    children: [
                      e.jsxs("h3", {
                        className: C.actionResultTitle,
                        children: ["Action Result: ", F?.action],
                      }),
                      e.jsxs("div", {
                        className: C.actionResultControls,
                        children: [
                          e.jsx("button", {
                            className: C.collapseButton,
                            onClick: (V) => {
                              (V.stopPropagation(), z());
                            },
                            title: "Clear result",
                            children: "Clear",
                          }),
                          e.jsx("span", {
                            className: C.collapseButton,
                            title: N ? "Expand" : "Collapse",
                            children: N ? e.jsx(Pe, {}) : e.jsx($e, {}),
                          }),
                        ],
                      }),
                    ],
                  }),
                  !N &&
                    e.jsx("div", {
                      className: C.actionResultContent,
                      children: e.jsx(ce, {
                        data: F,
                        initialExpandLevel: "all",
                      }),
                    }),
                ],
              }),
          ],
        });
  }),
  Ra = "CustomEvent-module__topContainer",
  Ma = "CustomEvent-module__container",
  Ba = "CustomEvent-module__card",
  Aa = "CustomEvent-module__form",
  La = "CustomEvent-module__inputGroup",
  Ha = "CustomEvent-module__label",
  Va = "CustomEvent-module__input",
  Wa = "CustomEvent-module__textarea",
  Ka = "CustomEvent-module__suggestions",
  Ja = "CustomEvent-module__suggestion",
  za = "CustomEvent-module__checkboxGroup",
  Ga = "CustomEvent-module__checkbox",
  Ua = "CustomEvent-module__button",
  qa = "CustomEvent-module__message",
  U = {
    topContainer: Ra,
    container: Ma,
    card: Ba,
    form: Aa,
    inputGroup: La,
    label: Ha,
    input: Va,
    textarea: Wa,
    suggestions: Ka,
    suggestion: Ja,
    checkboxGroup: za,
    checkbox: Ga,
    button: Ua,
    message: qa,
  },
  Qa = "CopyableDataViewer-module__markdownViewer",
  Ya = "CopyableDataViewer-module__markdownContent",
  Xa = "CopyableDataViewer-module__copyButton",
  _e = { markdownViewer: Qa, markdownContent: Ya, copyButton: Xa },
  Za = ({ data: t }) => {
    const [s, r] = o.useState(!1),
      m = typeof t == "object" ? JSON.stringify(t, null, 2) : t,
      x = () => {
        (ue(m), r(!0), setTimeout(() => r(!1), 2e3));
      };
    return e.jsxs("div", {
      className: _e.markdownViewer,
      "data-sentry-component": "CopyableDataViewer",
      "data-sentry-source-file": "CopyableDataViewer.tsx",
      children: [
        e.jsx("button", {
          type: "button",
          className: _e.copyButton,
          onClick: x,
          children: s ? "Copied!" : "Copy",
        }),
        e.jsx("div", {
          className: _e.markdownContent,
          children: e.jsx(Oe, {
            lang: "json",
            "data-sentry-element": "Code",
            "data-sentry-source-file": "CopyableDataViewer.tsx",
            children: m,
          }),
        }),
      ],
    });
  },
  eo = Me.version,
  to = [
    "m.room.message",
    "m.room.name",
    "m.room.topic",
    "m.room.avatar",
    "m.room.member",
    "m.room.power_levels",
    "m.room.join_rules",
    "m.room.history_visibility",
    "m.room.encryption",
    "m.room.redaction",
    "m.room.third_party_invite",
    "m.room.guest_access",
    "m.room.server_acl",
    "m.room.tombstone",
    "m.room.pinned_events",
  ],
  so = de(() => {
    const [t, s] = o.useState(""),
      [r, m] = o.useState(""),
      [x, h] = o.useState(""),
      [c, T] = o.useState(!0),
      [k, P] = o.useState({ type: "", content: "" }),
      [F, q] = o.useState([]),
      [W, D] = o.useState(() => `$adhoc.${Date.now()}`),
      $ = o.useRef(null),
      v = o.useMemo(() => {
        try {
          const R = JSON.parse(r);
          if (typeof R != "object")
            throw new Error("Event content must be a valid JSON object");
          c &&
            ((R["com.beeper.origin_client_ts"] = Date.now()),
            (R["com.beeper.origin_client_type"] = "desktop"),
            (R["com.beeper.origin_client_version"] = eo));
          const I = { type: t, content: R };
          return (x?.length > 0 && (I.room_id = x), I);
        } catch {
          return null;
        }
      }, [r, c, t, x]);
    o.useEffect(() => {
      ($.current &&
        (($.current.style.height = "auto"),
        ($.current.style.height = $.current.scrollHeight + "px")),
        D(`$adhoc.${Date.now()}`));
    }, [r]);
    const u = (R) => {
        const I = R.target.value;
        if ((s(I), I.startsWith("m.room") || h(""), I)) {
          const f = to.filter((O) => O.toLowerCase().includes(I.toLowerCase()));
          q(f);
        } else q([]);
      },
      M = (R) => {
        (s(R), q([]));
      },
      N = (R) => {
        const I = R.target.value;
        m(I);
        try {
          const f = JSON.parse(I),
            O = JSON.stringify(f, null, 2);
          O !== I && m(O);
        } catch {}
      },
      K = (R) => {
        try {
          return (JSON.parse(R), !0);
        } catch {
          return !1;
        }
      },
      G = async (R) => {
        if ((R.preventDefault(), P({ type: "", content: "" }), !K(r))) {
          P({ type: "error", content: "Invalid JSON in event content" });
          return;
        }
        if (t.startsWith("m.room") && !x) {
          P({ type: "error", content: "Room ID is required for room events" });
          return;
        }
        try {
          const I = await Q.bapi.debug_sendEvent(JSON.stringify(v), W);
          P({
            type: "success",
            content: `Event sent successfully: ${JSON.stringify(I, null, 2)}`,
          });
        } catch (I) {
          P({ type: "error", content: `Error sending event: ${I}` });
        }
      };
    return e.jsxs("div", {
      className: `${U.dbExplorer}`,
      children: [
        e.jsx("div", {
          className: `${U.topContainer} app-region-drag`,
          children: e.jsx("div", {
            className: U.headerContainer,
            children: e.jsx("h1", { children: "Send a custom event" }),
          }),
        }),
        e.jsx("div", {
          className: U.container,
          children: e.jsxs("div", {
            className: U.card,
            children: [
              e.jsxs("form", {
                onSubmit: G,
                className: U.form,
                children: [
                  e.jsxs("div", {
                    className: U.inputGroup,
                    children: [
                      e.jsx("input", {
                        id: "event-type",
                        name: "event-type",
                        type: "text",
                        className: U.input,
                        placeholder: " ",
                        value: t,
                        onChange: u,
                        required: !0,
                      }),
                      e.jsx("label", {
                        htmlFor: "event-type",
                        className: U.label,
                        children: "Event Type",
                      }),
                      F.length > 0 &&
                        e.jsx("ul", {
                          className: U.suggestions,
                          children: F.map((R, I) =>
                            e.jsx(
                              "li",
                              {
                                className: U.suggestion,
                                onClick: () => M(R),
                                children: R,
                              },
                              I,
                            ),
                          ),
                        }),
                    ],
                  }),
                  e.jsxs("div", {
                    className: U.inputGroup,
                    children: [
                      e.jsx("textarea", {
                        id: "event-content",
                        name: "event-content",
                        ref: $,
                        className: U.textarea,
                        placeholder: " ",
                        value: r,
                        onChange: N,
                        rows: 5,
                        required: !0,
                      }),
                      e.jsx("label", {
                        htmlFor: "event-content",
                        className: U.label,
                        children: "Event Content (JSON)",
                      }),
                    ],
                  }),
                  e.jsxs("div", {
                    className: `${U.inputGroup} ${t.startsWith("m.room") ? "" : "optional"}`,
                    children: [
                      e.jsx("input", {
                        id: "room-id",
                        name: "room-id",
                        type: "text",
                        className: U.input,
                        placeholder: " ",
                        value: x,
                        onChange: (R) => h(R.target.value),
                        required: t.startsWith("m.room"),
                      }),
                      e.jsx("label", {
                        htmlFor: "room-id",
                        className: U.label,
                        children: "Room ID",
                      }),
                    ],
                  }),
                  e.jsxs("div", {
                    className: U.inputGroup,
                    children: [
                      e.jsx("input", {
                        id: "transaction-id",
                        name: "transaction-id",
                        type: "text",
                        className: U.input,
                        placeholder: " ",
                        value: W,
                        onChange: (R) => D(R.target.value),
                        required: !0,
                      }),
                      e.jsx("label", {
                        htmlFor: "transaction-id",
                        className: U.label,
                        children: "Transaction ID",
                      }),
                    ],
                  }),
                  e.jsxs("div", {
                    className: U.checkboxGroup,
                    children: [
                      e.jsx("input", {
                        id: "add-checkpoint",
                        name: "add-checkpoint",
                        type: "checkbox",
                        className: U.checkbox,
                        checked: c,
                        onChange: (R) => T(R.target.checked),
                      }),
                      e.jsx("label", {
                        htmlFor: "add-checkpoint",
                        children: "Add checkpoint data",
                      }),
                    ],
                  }),
                  e.jsx("button", {
                    type: "submit",
                    className: U.button,
                    children: "Send Event",
                  }),
                ],
              }),
              k.content &&
                e.jsx("div", {
                  className: `${U.message} ${k.type}`,
                  children: k.content,
                }),
              v && e.jsx(Za, { data: v }),
            ],
          }),
        }),
      ],
    });
  }),
  ao = "FactsPromptTester-module__promptTester",
  oo = "FactsPromptTester-module__header",
  no = "FactsPromptTester-module__headerContent",
  ro = "FactsPromptTester-module__headerMeta",
  lo = "FactsPromptTester-module__messageMeta",
  co = "FactsPromptTester-module__messageEditorMeta",
  io = "FactsPromptTester-module__headerActions",
  mo = "FactsPromptTester-module__content",
  uo = "FactsPromptTester-module__inputPane",
  ho = "FactsPromptTester-module__outputPane",
  po = "FactsPromptTester-module__section",
  xo = "FactsPromptTester-module__messagesSection",
  go = "FactsPromptTester-module__sectionHeader",
  fo = "FactsPromptTester-module__sectionHeaderText",
  _o = "FactsPromptTester-module__sectionHint",
  bo = "FactsPromptTester-module__promptInput",
  jo = "FactsPromptTester-module__messageInput",
  yo = "FactsPromptTester-module__textInput",
  vo = "FactsPromptTester-module__messagesList",
  Eo = "FactsPromptTester-module__resultsList",
  No = "FactsPromptTester-module__messageEditor",
  So = "FactsPromptTester-module__messageResult",
  wo = "FactsPromptTester-module__factCard",
  To = "FactsPromptTester-module__stageCard",
  Co = "FactsPromptTester-module__persistCard",
  Do = "FactsPromptTester-module__targetMessageEditor",
  Io = "FactsPromptTester-module__contextMessageEditor",
  Fo = "FactsPromptTester-module__messageRunHeader",
  Po = "FactsPromptTester-module__messageRunTitle",
  $o = "FactsPromptTester-module__messageRunSubtitle",
  Oo = "FactsPromptTester-module__messageEditorHeader",
  ko = "FactsPromptTester-module__targetLock",
  Ro = "FactsPromptTester-module__primaryButton",
  Mo = "FactsPromptTester-module__secondaryButton",
  Bo = "FactsPromptTester-module__dangerButton",
  Ao = "FactsPromptTester-module__errorBar",
  Lo = "FactsPromptTester-module__warningBar",
  Ho = "FactsPromptTester-module__emptyState",
  Vo = "FactsPromptTester-module__emptyResult",
  Wo = "FactsPromptTester-module__emptyStage",
  Ko = "FactsPromptTester-module__timeline",
  Jo = "FactsPromptTester-module__timelineStage",
  zo = "FactsPromptTester-module__timelineRail",
  Go = "FactsPromptTester-module__timelineDot",
  Uo = "FactsPromptTester-module__timelineDot_default",
  qo = "FactsPromptTester-module__timelineDot_default",
  Qo = "FactsPromptTester-module__timelineDot_good",
  Yo = "FactsPromptTester-module__timelineDot_good",
  Xo = "FactsPromptTester-module__timelineDot_bad",
  Zo = "FactsPromptTester-module__timelineDot_bad",
  en = "FactsPromptTester-module__timelineDot_muted",
  tn = "FactsPromptTester-module__timelineDot_muted",
  sn = "FactsPromptTester-module__timelineDot_warn",
  an = "FactsPromptTester-module__timelineDot_warn",
  on = "FactsPromptTester-module__timelineLine",
  nn = "FactsPromptTester-module__stageHeader",
  rn = "FactsPromptTester-module__stageSummary",
  ln = "FactsPromptTester-module__stageBody",
  cn = "FactsPromptTester-module__messageResultHeader",
  dn = "FactsPromptTester-module__factHeader",
  mn = "FactsPromptTester-module__messageText",
  un = "FactsPromptTester-module__gates",
  hn = "FactsPromptTester-module__gateBadge",
  pn = "FactsPromptTester-module__gate_pass",
  xn = "FactsPromptTester-module__gate_pass",
  gn = "FactsPromptTester-module__gate_fail",
  fn = "FactsPromptTester-module__gate_fail",
  _n = "FactsPromptTester-module__gate_not_evaluated",
  bn = "FactsPromptTester-module__gate_not_evaluated",
  jn = "FactsPromptTester-module__gateLabel",
  yn = "FactsPromptTester-module__gateDetail",
  vn = "FactsPromptTester-module__resultSummary",
  En = "FactsPromptTester-module__factMeta",
  Nn = "FactsPromptTester-module__jsonGrid",
  Sn = "FactsPromptTester-module__badge",
  wn = "FactsPromptTester-module__badge_good",
  Tn = "FactsPromptTester-module__badge_good",
  Cn = "FactsPromptTester-module__badge_bad",
  Dn = "FactsPromptTester-module__badge_bad",
  In = "FactsPromptTester-module__badge_muted",
  Fn = "FactsPromptTester-module__badge_muted",
  Pn = "FactsPromptTester-module__badge_warn",
  $n = "FactsPromptTester-module__badge_warn",
  On = "FactsPromptTester-module__factsList",
  kn = "FactsPromptTester-module__templateReason",
  Rn = "FactsPromptTester-module__templateFields",
  Mn = "FactsPromptTester-module__templateFieldEmpty",
  Bn = "FactsPromptTester-module__templateFieldSource",
  An = "FactsPromptTester-module__splitStage",
  Ln = "FactsPromptTester-module__contextList",
  Hn = "FactsPromptTester-module__contextMessage",
  Vn = "FactsPromptTester-module__contextTarget",
  Wn = "FactsPromptTester-module__contextTargetBanner",
  Kn = "FactsPromptTester-module__contextMessageHeader",
  Jn = "FactsPromptTester-module__contextMessageText",
  zn = "FactsPromptTester-module__factType",
  Gn = "FactsPromptTester-module__factBody",
  Un = "FactsPromptTester-module__factSubject",
  qn = "FactsPromptTester-module__factContent",
  Qn = "FactsPromptTester-module__factValue",
  Yn = "FactsPromptTester-module__writePreview",
  Xn = "FactsPromptTester-module__enrichmentUrl",
  Zn = "FactsPromptTester-module__sourceQuote",
  er = "FactsPromptTester-module__enrichment",
  tr = "FactsPromptTester-module__enrichmentImage",
  sr = "FactsPromptTester-module__enrichmentContent",
  ar = "FactsPromptTester-module__enrichmentKind",
  or = "FactsPromptTester-module__enrichmentTitle",
  nr = "FactsPromptTester-module__enrichmentSubtitle",
  rr = "FactsPromptTester-module__enrichmentDescription",
  lr = "FactsPromptTester-module__persistSummary",
  cr = "FactsPromptTester-module__visibleJson",
  ir = "FactsPromptTester-module__jsonDetails",
  a = {
    promptTester: ao,
    header: oo,
    headerContent: no,
    headerMeta: ro,
    messageMeta: lo,
    messageEditorMeta: co,
    headerActions: io,
    content: mo,
    inputPane: uo,
    outputPane: ho,
    section: po,
    messagesSection: xo,
    sectionHeader: go,
    sectionHeaderText: fo,
    sectionHint: _o,
    promptInput: bo,
    messageInput: jo,
    textInput: yo,
    messagesList: vo,
    resultsList: Eo,
    messageEditor: No,
    messageResult: So,
    factCard: wo,
    stageCard: To,
    persistCard: Co,
    targetMessageEditor: Do,
    contextMessageEditor: Io,
    messageRunHeader: Fo,
    messageRunTitle: Po,
    messageRunSubtitle: $o,
    messageEditorHeader: Oo,
    targetLock: ko,
    primaryButton: Ro,
    secondaryButton: Mo,
    dangerButton: Bo,
    errorBar: Ao,
    warningBar: Lo,
    emptyState: Ho,
    emptyResult: Vo,
    emptyStage: Wo,
    timeline: Ko,
    timelineStage: Jo,
    timelineRail: zo,
    timelineDot: Go,
    timelineDot_default: Uo,
    timelineDotDefault: qo,
    timelineDot_good: Qo,
    timelineDotGood: Yo,
    timelineDot_bad: Xo,
    timelineDotBad: Zo,
    timelineDot_muted: en,
    timelineDotMuted: tn,
    timelineDot_warn: sn,
    timelineDotWarn: an,
    timelineLine: on,
    stageHeader: nn,
    stageSummary: rn,
    stageBody: ln,
    messageResultHeader: cn,
    factHeader: dn,
    messageText: mn,
    gates: un,
    gateBadge: hn,
    gate_pass: pn,
    gatePass: xn,
    gate_fail: gn,
    gateFail: fn,
    gate_not_evaluated: _n,
    gateNotEvaluated: bn,
    gateLabel: jn,
    gateDetail: yn,
    resultSummary: vn,
    factMeta: En,
    jsonGrid: Nn,
    badge: Sn,
    badge_good: wn,
    badgeGood: Tn,
    badge_bad: Cn,
    badgeBad: Dn,
    badge_muted: In,
    badgeMuted: Fn,
    badge_warn: Pn,
    badgeWarn: $n,
    factsList: On,
    templateReason: kn,
    templateFields: Rn,
    templateFieldEmpty: Mn,
    templateFieldSource: Bn,
    splitStage: An,
    contextList: Ln,
    contextMessage: Hn,
    contextTarget: Vn,
    contextTargetBanner: Wn,
    contextMessageHeader: Kn,
    contextMessageText: Jn,
    factType: zn,
    factBody: Gn,
    factSubject: Un,
    factContent: qn,
    factValue: Qn,
    writePreview: Yn,
    enrichmentUrl: Xn,
    sourceQuote: Zn,
    enrichment: er,
    enrichmentImage: tr,
    enrichmentContent: sr,
    enrichmentKind: ar,
    enrichmentTitle: or,
    enrichmentSubtitle: nr,
    enrichmentDescription: rr,
    persistSummary: lr,
    visibleJson: cr,
    jsonDetails: ir,
  },
  Ee = Date.now(),
  dr = () => `${Date.now()}-${Math.random().toString(36).slice(2)}`,
  Ne = (t = {}) => ({
    localID: dr(),
    roomID: "!debug-room:beeper.local",
    accountID: "debug_account",
    messageEventID: "$debug-message-1",
    senderContactID: "@sender:beeper.local",
    senderDisplayName: "Alice",
    timestamp: Date.now(),
    text: "You should watch Severance, the second season is excellent.",
    ...t,
  }),
  mr = () => {
    const t = Ne();
    return { targetLocalID: t.localID, messages: [t] };
  },
  ur = (t) => {
    const s = new Date(t),
      r = s.getTimezoneOffset() * 60 * 1e3;
    return new Date(s.getTime() - r).toISOString().slice(0, 16);
  },
  hr = (t) => {
    const s = new Date(t).getTime();
    return Number.isFinite(s) ? s : Ee;
  },
  pr = (t, s) => ({
    id: s + 1,
    hsOrder: s + 1,
    roomID: t.roomID || "!debug-room:beeper.local",
    accountID: t.accountID || "debug_account",
    messageEventID: t.messageEventID || `$debug-message-${s + 1}`,
    senderContactID: t.senderContactID || "@sender:beeper.local",
    senderDisplayName: t.senderDisplayName || null,
    timestamp: t.timestamp || Ee,
    text: t.text,
  }),
  xr = (t) => t.map((s, r) => pr(s, r)),
  Se = (t) => JSON.stringify(t, null, 2),
  we = (t) =>
    Number.isFinite(t) ? new Date(t).toLocaleString() : "Invalid time",
  gr = (t) => {
    if (!t.enrichmentData) return null;
    try {
      return JSON.parse(t.enrichmentData);
    } catch {
      return null;
    }
  },
  fr = (t) => {
    if (!t) return null;
    try {
      return JSON.parse(t);
    } catch {
      return null;
    }
  },
  _r = new Set(["book", "show", "movie", "music", "song", "album", "artist"]),
  br = new Set(["actor", "director", "writer", "musician"]);
function ye(t) {
  return t
    ? `https://www.google.com/maps/search/?api=1&query=${encodeURIComponent(t)}`
    : null;
}
function jr(t) {
  const s = fr(t.enrichmentData),
    r = t.category ?? "";
  if (t.factType === "recommendation" && _r.has(r) && s?.kind === "media")
    return {
      template: "media-card",
      reason: `recommendation/${r} + media enrichment`,
      fields: [
        {
          label: "title",
          value: s.title ?? t.subject,
          source: "enrichment",
          factField: "enrichment.title || subject",
        },
        {
          label: "subtitle",
          value: s.subtitle,
          source: "enrichment",
          factField: "enrichment.subtitle",
        },
        {
          label: "image",
          value: s.imageUrl,
          source: "enrichment",
          factField: "enrichment.imageUrl",
        },
        {
          label: "link",
          value: s.url,
          source: "enrichment",
          factField: "enrichment.url",
        },
      ],
    };
  if (t.factType === "recommendation" && br.has(r) && s?.kind === "person")
    return {
      template: "person-card",
      reason: `recommendation/${r} + person enrichment`,
      fields: [
        {
          label: "name",
          value: s.title ?? t.subject,
          source: "enrichment",
          factField: "enrichment.title || subject",
        },
        {
          label: "role",
          value: s.subtitle,
          source: "enrichment",
          factField: "enrichment.subtitle",
        },
        {
          label: "image",
          value: s.imageUrl,
          source: "enrichment",
          factField: "enrichment.imageUrl",
        },
        {
          label: "link",
          value: s.url,
          source: "enrichment",
          factField: "enrichment.url",
        },
      ],
    };
  if (s?.kind === "place") {
    const h = s.url ?? ye(s.description ?? t.subject);
    return {
      template: "place-card",
      reason: `${t.factType}/${r} + place enrichment`,
      fields: [
        { label: "title", value: s.title ?? t.subject, source: "enrichment" },
        { label: "subtitle", value: s.subtitle, source: "enrichment" },
        { label: "description", value: s.description, source: "enrichment" },
        { label: "image", value: s.imageUrl, source: "enrichment" },
        {
          label: "link",
          value: h,
          source: s.url ? "enrichment" : "derived",
          factField: s.url ? "enrichment.url" : "derived from place",
        },
      ],
    };
  }
  if (t.factType === "date_event" && t.eventDate) {
    const h = t.valueType === "venue" ? ye(t.value) : null;
    return {
      template: "date-event-card",
      reason: "date_event with eventDate",
      fields: [
        {
          label: "title",
          value: t.subject ?? t.content,
          source: "fact",
          factField: "subject || content",
        },
        {
          label: "eventDate",
          value: t.eventDate,
          source: "fact",
          factField: "eventDate",
        },
        {
          label: "datePrecision",
          value: t.datePrecision,
          source: "fact",
          factField: "datePrecision",
        },
        {
          label: "venue",
          value: t.valueType === "venue" ? t.value : null,
          source: "fact",
          factField: "value",
        },
        {
          label: "mapsLink",
          value: h,
          source: "derived",
          factField: "derived from venue",
        },
      ],
    };
  }
  if (s?.kind === "link_preview")
    return {
      template: "link-preview-card",
      reason: `${t.factType} with link_preview enrichment`,
      fields: [
        { label: "title", value: s.title ?? t.subject, source: "enrichment" },
        {
          label: "description",
          value: s.description ?? t.content,
          source: "enrichment",
        },
        { label: "image", value: s.imageUrl, source: "enrichment" },
        { label: "url", value: s.url ?? t.value, source: "enrichment" },
      ],
    };
  const m = t.category ? `/${t.category}` : "",
    x = [
      {
        label: "title",
        value: t.subject ?? null,
        source: "fact",
        factField: "subject",
      },
      {
        label: "description",
        value: t.content,
        source: "fact",
        factField: "content",
      },
      { label: "value", value: t.value, source: "fact", factField: "value" },
      {
        label: "link",
        value: t.valueType === "url" ? t.value : null,
        source: "fact",
        factField: "value",
      },
    ];
  return {
    template: "info-note",
    reason: `${t.factType}${m} (fallback)`,
    fields: x.filter((h) => h.value !== null && h.value !== ""),
  };
}
const X = ({ children: t, tone: s = "default" }) =>
    e.jsx("span", {
      className: `${a.badge} ${a[`badge_${s}`]}`,
      "data-sentry-component": "Badge",
      "data-sentry-source-file": "FactsPromptTester.tsx",
      children: t,
    }),
  yr = ({ title: t, data: s }) =>
    e.jsxs("details", {
      className: a.jsonDetails,
      "data-sentry-component": "JsonDetails",
      "data-sentry-source-file": "FactsPromptTester.tsx",
      children: [
        e.jsx("summary", { children: t }),
        e.jsx("pre", { children: Se(s) }),
      ],
    }),
  vr = ({ gate: t }) => {
    const s =
      t.status === "pass" ? "good" : t.status === "fail" ? "bad" : "muted";
    return e.jsxs("div", {
      className: `${a.gateBadge} ${a[`gate_${t.status}`]}`,
      "data-sentry-component": "GateBadge",
      "data-sentry-source-file": "FactsPromptTester.tsx",
      children: [
        e.jsx("div", { className: a.gateLabel, children: t.label }),
        e.jsx("div", { className: a.gateDetail, children: t.detail }),
        e.jsx(X, {
          tone: s,
          "data-sentry-element": "Badge",
          "data-sentry-source-file": "FactsPromptTester.tsx",
          children: t.status.replace("_", " "),
        }),
      ],
    });
  },
  re = ({
    title: t,
    status: s,
    tone: r = "default",
    summary: m,
    children: x,
  }) =>
    e.jsxs("section", {
      className: a.timelineStage,
      "data-sentry-component": "TimelineStage",
      "data-sentry-source-file": "FactsPromptTester.tsx",
      children: [
        e.jsxs("div", {
          className: a.timelineRail,
          children: [
            e.jsx("div", {
              className: `${a.timelineDot} ${a[`timelineDot_${r}`]}`,
            }),
            e.jsx("div", { className: a.timelineLine }),
          ],
        }),
        e.jsxs("div", {
          className: a.stageCard,
          children: [
            e.jsxs("div", {
              className: a.stageHeader,
              children: [
                e.jsxs("div", {
                  children: [
                    e.jsx("h3", { children: t }),
                    m &&
                      e.jsx("div", { className: a.stageSummary, children: m }),
                  ],
                }),
                e.jsx(X, {
                  tone: r,
                  "data-sentry-element": "Badge",
                  "data-sentry-source-file": "FactsPromptTester.tsx",
                  children: s,
                }),
              ],
            }),
            e.jsx("div", { className: a.stageBody, children: x }),
          ],
        }),
      ],
    }),
  le = ({ children: t }) =>
    e.jsx("div", {
      className: a.emptyStage,
      "data-sentry-component": "EmptyStage",
      "data-sentry-source-file": "FactsPromptTester.tsx",
      children: t,
    }),
  Er = ({ context: t }) =>
    e.jsx("div", {
      className: a.contextList,
      "data-sentry-component": "ContextMessageList",
      "data-sentry-source-file": "FactsPromptTester.tsx",
      children: t.map((s, r) => {
        const m = s.relativeIndex === 0,
          x = s.relativeIndex > 0 ? `+${s.relativeIndex}` : s.relativeIndex;
        return e.jsxs(
          "article",
          {
            className: `${a.contextMessage} ${m ? a.contextTarget : ""}`,
            children: [
              m &&
                e.jsxs("div", {
                  className: a.contextTargetBanner,
                  children: [
                    e.jsx("span", { children: "Extraction target" }),
                    e.jsx("span", {
                      children: "Facts must come from this message",
                    }),
                  ],
                }),
              e.jsxs("div", {
                className: a.contextMessageHeader,
                children: [
                  e.jsx(X, {
                    tone: m ? "good" : "muted",
                    children: m
                      ? "extract facts from this message"
                      : `context ${x}`,
                  }),
                  e.jsx("span", { children: s.senderDisplayName || s.sender }),
                  e.jsx("span", { children: we(s.sentAt) }),
                ],
              }),
              e.jsx("div", {
                className: a.contextMessageText,
                children: s.text,
              }),
            ],
          },
          `${s.relativeIndex}-${s.sender}-${s.sentAt}-${r}`,
        );
      }),
    }),
  Nr = ({ fact: t, index: s }) => {
    const r = [
      t.eventDate ? `date ${t.eventDate}` : null,
      t.value ? `${t.valueType ?? "value"} ${t.value}` : null,
    ].filter(Boolean);
    return e.jsxs("article", {
      className: a.factCard,
      "data-sentry-component": "RawFactCard",
      "data-sentry-source-file": "FactsPromptTester.tsx",
      children: [
        e.jsxs("div", {
          className: a.factHeader,
          children: [
            e.jsxs("div", {
              className: a.factType,
              children: [
                e.jsxs("span", { children: ["raw #", s + 1] }),
                e.jsx("span", { children: t.factType }),
                t.category && e.jsx("span", { children: t.category }),
              ],
            }),
            e.jsx(X, {
              "data-sentry-element": "Badge",
              "data-sentry-source-file": "FactsPromptTester.tsx",
              children: t.confidence,
            }),
          ],
        }),
        e.jsxs("div", {
          className: a.factBody,
          children: [
            t.subject &&
              e.jsx("div", { className: a.factSubject, children: t.subject }),
            e.jsx("div", { className: a.factContent, children: t.content }),
            r.length > 0 &&
              e.jsx("div", { className: a.factValue, children: r.join(" | ") }),
          ],
        }),
        e.jsxs("div", {
          className: a.factMeta,
          children: [
            t.datePrecision && e.jsx(X, { children: t.datePrecision }),
            t.valueType && e.jsx(X, { children: t.valueType }),
          ],
        }),
        e.jsx("blockquote", {
          className: a.sourceQuote,
          children: t.sourceQuote,
        }),
      ],
    });
  },
  ge = ({
    fact: t,
    enrichedFact: s,
    statusLabel: r,
    statusTone: m = "default",
    footer: x,
  }) => {
    const h = s ?? t,
      c = gr(h),
      T = [
        h.eventDate ? `date ${h.eventDate}` : null,
        h.datePrecision ? `precision ${h.datePrecision}` : null,
        h.value ? `${h.valueType ?? "value"} ${h.value}` : null,
      ].filter(Boolean);
    return e.jsxs("article", {
      className: a.factCard,
      "data-sentry-component": "FactCard",
      "data-sentry-source-file": "FactsPromptTester.tsx",
      children: [
        e.jsxs("div", {
          className: a.factHeader,
          children: [
            e.jsxs("div", {
              className: a.factType,
              children: [
                e.jsx("span", { children: h.factType }),
                h.category && e.jsx("span", { children: h.category }),
              ],
            }),
            r && e.jsx(X, { tone: m, children: r }),
          ],
        }),
        e.jsxs("div", {
          className: a.factBody,
          children: [
            h.subject &&
              e.jsx("div", { className: a.factSubject, children: h.subject }),
            e.jsx("div", { className: a.factContent, children: h.content }),
            T.length > 0 &&
              e.jsx("div", { className: a.factValue, children: T.join(" | ") }),
          ],
        }),
        e.jsxs("div", {
          className: a.factMeta,
          children: [
            h.valueType && e.jsx(X, { children: h.valueType }),
            h.datePrecision && e.jsx(X, { children: h.datePrecision }),
          ],
        }),
        e.jsx("blockquote", {
          className: a.sourceQuote,
          children: h.sourceQuote,
        }),
        c &&
          e.jsxs("div", {
            className: a.enrichment,
            children: [
              c.imageUrl &&
                e.jsx("img", {
                  src: c.imageUrl,
                  alt: "",
                  className: a.enrichmentImage,
                }),
              e.jsxs("div", {
                className: a.enrichmentContent,
                children: [
                  e.jsx("div", {
                    className: a.enrichmentKind,
                    children: c.kind,
                  }),
                  c.title &&
                    e.jsx("div", {
                      className: a.enrichmentTitle,
                      children: c.title,
                    }),
                  c.subtitle &&
                    e.jsx("div", {
                      className: a.enrichmentSubtitle,
                      children: c.subtitle,
                    }),
                  c.description &&
                    e.jsx("div", {
                      className: a.enrichmentDescription,
                      children: c.description,
                    }),
                  c.url &&
                    e.jsx("div", {
                      className: a.enrichmentUrl,
                      children: c.url,
                    }),
                ],
              }),
            ],
          }),
        x && e.jsx("div", { className: a.writePreview, children: x }),
      ],
    });
  },
  Sr = ({ fact: t, index: s }) =>
    e.jsxs("article", {
      className: a.persistCard,
      "data-sentry-component": "PersistableFactCard",
      "data-sentry-source-file": "FactsPromptTester.tsx",
      children: [
        e.jsxs("div", {
          className: a.factHeader,
          children: [
            e.jsxs("div", {
              className: a.factType,
              children: [
                e.jsxs("span", { children: ["row #", s + 1] }),
                e.jsx("span", { children: t.factType }),
                t.category && e.jsx("span", { children: t.category }),
              ],
            }),
            e.jsx(X, {
              tone: "good",
              "data-sentry-element": "Badge",
              "data-sentry-source-file": "FactsPromptTester.tsx",
              children: "mx_message_facts",
            }),
          ],
        }),
        e.jsxs("div", {
          className: a.persistSummary,
          children: [
            e.jsxs("div", {
              children: [e.jsx("span", { children: "factKey" }), t.factKey],
            }),
            e.jsxs("div", {
              children: [
                e.jsx("span", { children: "message" }),
                t.messageEventID,
              ],
            }),
            e.jsxs("div", {
              children: [
                e.jsx("span", { children: "sender" }),
                t.senderContactID,
              ],
            }),
            e.jsxs("div", {
              children: [
                e.jsx("span", { children: "enrichment" }),
                t.enrichmentData ? "yes" : "none",
              ],
            }),
          ],
        }),
        e.jsx("pre", { className: a.visibleJson, children: Se(t) }),
      ],
    }),
  wr = ({ fact: t, index: s }) => {
    const r = jr(t);
    return e.jsxs("article", {
      className: a.factCard,
      "data-sentry-component": "TemplateRenderCard",
      "data-sentry-source-file": "FactsPromptTester.tsx",
      children: [
        e.jsxs("div", {
          className: a.factHeader,
          children: [
            e.jsxs("div", {
              className: a.factType,
              children: [
                e.jsxs("span", { children: ["card #", s + 1] }),
                e.jsx("span", { children: r.template }),
                t.category &&
                  e.jsxs("span", { children: [t.factType, "/", t.category] }),
              ],
            }),
            e.jsx(X, {
              tone: "good",
              "data-sentry-element": "Badge",
              "data-sentry-source-file": "FactsPromptTester.tsx",
              children: r.template,
            }),
          ],
        }),
        e.jsx("div", { className: a.templateReason, children: r.reason }),
        e.jsx("table", {
          className: a.templateFields,
          children: e.jsx("tbody", {
            children: r.fields.map((m) =>
              e.jsxs(
                "tr",
                {
                  children: [
                    e.jsx("th", { children: m.label }),
                    e.jsxs("td", {
                      children: [
                        m.value
                          ? e.jsx("span", { children: m.value })
                          : e.jsx("em", {
                              className: a.templateFieldEmpty,
                              children: "—",
                            }),
                        m.factField &&
                          e.jsxs("div", {
                            className: a.templateFieldSource,
                            children: [m.source, " · ", m.factField],
                          }),
                      ],
                    }),
                  ],
                },
                m.label,
              ),
            ),
          }),
        }),
      ],
    });
  },
  Tr = ({ trace: t }) => {
    const s = new Set(t.honeycomb.map((c) => c.factKey)),
      r = t.normalized.filter((c) => !s.has(c.factKey)),
      m = new Map(t.enriched.map((c) => [c.factKey, c])),
      x = t.raw?.facts.length ?? 0,
      h = t.enriched.filter((c) => c.enrichmentData).length;
    return e.jsxs("section", {
      className: a.messageResult,
      "data-sentry-component": "MessageResult",
      "data-sentry-source-file": "FactsPromptTester.tsx",
      children: [
        e.jsxs("div", {
          className: a.messageResultHeader,
          children: [
            e.jsxs("div", {
              children: [
                e.jsx("h2", { children: "Target Message" }),
                e.jsxs("div", {
                  className: a.messageMeta,
                  children: [
                    t.message.senderDisplayName || t.message.senderContactID,
                    " | ",
                    t.message.senderContactID,
                    " | ",
                    we(t.message.timestamp),
                  ],
                }),
              ],
            }),
            e.jsx(X, {
              tone: t.passedGates ? "good" : "bad",
              "data-sentry-element": "Badge",
              "data-sentry-source-file": "FactsPromptTester.tsx",
              children: t.passedGates ? "sent to LLM" : "skipped before LLM",
            }),
          ],
        }),
        e.jsx("div", { className: a.messageText, children: t.message.text }),
        e.jsxs("div", {
          className: a.timeline,
          children: [
            e.jsx(re, {
              title: "Gates",
              status: t.passedGates ? "passed" : "stopped",
              tone: t.passedGates ? "good" : "bad",
              summary:
                "Typed-message gates plus DB gates that are not available from typed input.",
              "data-sentry-element": "TimelineStage",
              "data-sentry-source-file": "FactsPromptTester.tsx",
              children: e.jsx("div", {
                className: a.gates,
                children: t.gates.map((c) => e.jsx(vr, { gate: c }, c.key)),
              }),
            }),
            e.jsx(re, {
              title: "Context Window",
              status: t.llmInput ? `${t.context.length} messages` : "not sent",
              tone: t.llmInput ? "good" : "muted",
              summary:
                "The highlighted target card is the only message facts are extracted from. Other messages are context only.",
              "data-sentry-element": "TimelineStage",
              "data-sentry-source-file": "FactsPromptTester.tsx",
              children:
                t.context.length > 0
                  ? e.jsx(Er, { context: t.context })
                  : e.jsx(le, { children: "No context messages available." }),
            }),
            e.jsx(re, {
              title: "LLM Output",
              status: t.llmInput ? `${x} facts` : "not run",
              tone: t.llmInput ? (x > 0 ? "good" : "warn") : "muted",
              summary: t.llmInput
                ? "Raw structured facts returned by the model."
                : "Stopped before the model because a gate failed.",
              "data-sentry-element": "TimelineStage",
              "data-sentry-source-file": "FactsPromptTester.tsx",
              children: t.raw?.facts.length
                ? e.jsx("div", {
                    className: a.factsList,
                    children: t.raw.facts.map((c, T) =>
                      e.jsx(
                        Nr,
                        { fact: c, index: T },
                        `${c.factType}-${c.category}-${T}`,
                      ),
                    ),
                  })
                : e.jsx(le, {
                    children: t.llmInput
                      ? "The model returned no facts."
                      : "No LLM call was made.",
                  }),
            }),
            e.jsx(re, {
              title: "Normalized Output",
              status: `${t.normalized.length} facts`,
              tone: t.llmInput
                ? t.normalized.length > 0
                  ? "good"
                  : x > 0
                    ? "warn"
                    : "muted"
                : "muted",
              summary:
                "Facts that survived source quote, confidence, required-field, limit, and dedupe checks.",
              "data-sentry-element": "TimelineStage",
              "data-sentry-source-file": "FactsPromptTester.tsx",
              children:
                t.normalized.length > 0
                  ? e.jsx("div", {
                      className: a.factsList,
                      children: t.normalized.map((c) =>
                        e.jsx(
                          ge,
                          { fact: c, statusLabel: "normalized" },
                          c.factKey,
                        ),
                      ),
                    })
                  : e.jsx(le, {
                      children:
                        x > 0
                          ? "Raw facts were returned, but none survived normalization."
                          : "No normalized facts.",
                    }),
            }),
            e.jsx(re, {
              title: "Honeycomb Filter",
              status: `${t.honeycomb.length} kept, ${r.length} filtered`,
              tone:
                t.honeycomb.length > 0
                  ? "good"
                  : r.length > 0
                    ? "warn"
                    : "muted",
              summary:
                "Facts outside the recommendation/date-event contract stop here.",
              "data-sentry-element": "TimelineStage",
              "data-sentry-source-file": "FactsPromptTester.tsx",
              children: e.jsxs("div", {
                className: a.splitStage,
                children: [
                  e.jsxs("div", {
                    children: [
                      e.jsx("h4", { children: "Kept" }),
                      t.honeycomb.length > 0
                        ? e.jsx("div", {
                            className: a.factsList,
                            children: t.honeycomb.map((c) =>
                              e.jsx(
                                ge,
                                {
                                  fact: c,
                                  statusLabel: "Honeycomb",
                                  statusTone: "good",
                                },
                                c.factKey,
                              ),
                            ),
                          })
                        : e.jsx(le, { children: "No Honeycomb facts kept." }),
                    ],
                  }),
                  e.jsxs("div", {
                    children: [
                      e.jsx("h4", { children: "Filtered" }),
                      r.length > 0
                        ? e.jsx("div", {
                            className: a.factsList,
                            children: r.map((c) =>
                              e.jsx(
                                ge,
                                {
                                  fact: c,
                                  statusLabel: "non-Honeycomb",
                                  statusTone: "warn",
                                },
                                c.factKey,
                              ),
                            ),
                          })
                        : e.jsx(le, {
                            children: "No facts filtered at this stage.",
                          }),
                    ],
                  }),
                ],
              }),
            }),
            e.jsx(re, {
              title: "Enrichment",
              status: `${h}/${t.honeycomb.length} enriched`,
              tone:
                t.honeycomb.length === 0 ? "muted" : h > 0 ? "good" : "warn",
              summary:
                "Display metadata attached in memory for supported public facts.",
              "data-sentry-element": "TimelineStage",
              "data-sentry-source-file": "FactsPromptTester.tsx",
              children:
                t.enriched.length > 0
                  ? e.jsx("div", {
                      className: a.factsList,
                      children: t.enriched.map((c) =>
                        e.jsx(
                          ge,
                          {
                            fact: c,
                            enrichedFact: m.get(c.factKey),
                            statusLabel: c.enrichmentData
                              ? "enriched"
                              : "no metadata",
                            statusTone: c.enrichmentData ? "good" : "muted",
                          },
                          c.factKey,
                        ),
                      ),
                    })
                  : e.jsx(le, {
                      children:
                        t.honeycomb.length > 0
                          ? "No enrichment metadata returned."
                          : "No Honeycomb facts to enrich.",
                    }),
            }),
            e.jsx(re, {
              title: "Would Write",
              status: `${t.wouldPersist.length} rows`,
              tone: t.wouldPersist.length > 0 ? "good" : "muted",
              summary:
                "Exact row-shaped payloads that would be persisted later. This tester still writes nothing.",
              "data-sentry-element": "TimelineStage",
              "data-sentry-source-file": "FactsPromptTester.tsx",
              children:
                t.wouldPersist.length > 0
                  ? e.jsx("div", {
                      className: a.factsList,
                      children: t.wouldPersist.map((c, T) =>
                        e.jsx(Sr, { fact: c, index: T }, c.factKey),
                      ),
                    })
                  : e.jsx(le, {
                      children: "No DB rows would be written for this message.",
                    }),
            }),
            e.jsx(re, {
              title: "Template Render",
              status: `${t.wouldPersist.length} cards`,
              tone: t.wouldPersist.length > 0 ? "good" : "muted",
              summary:
                "Which honeycomb template each fact would render as, and the data that would populate each field.",
              "data-sentry-element": "TimelineStage",
              "data-sentry-source-file": "FactsPromptTester.tsx",
              children:
                t.wouldPersist.length > 0
                  ? e.jsx("div", {
                      className: a.factsList,
                      children: t.wouldPersist.map((c, T) =>
                        e.jsx(wr, { fact: c, index: T }, c.factKey),
                      ),
                    })
                  : e.jsx(le, { children: "No facts to render." }),
            }),
          ],
        }),
      ],
    });
  },
  Cr = de(() => {
    const [t, s] = o.useState(""),
      [r, m] = o.useState(""),
      [x, h] = o.useState(mr),
      [c, T] = o.useState(null),
      [k, P] = o.useState(!1),
      [F, q] = o.useState(!1),
      [W, D] = o.useState(null),
      { messages: $, targetLocalID: v } = x,
      u = $.findIndex((f) => f.localID === v),
      M = o.useCallback(async () => {
        (P(!0), D(null));
        try {
          const f = await Q.bapi.debug_getMessageFactsExtractionDefaults();
          (s(f.prompt), m(f.model));
        } catch (f) {
          (console.error("Failed to load message facts defaults:", f),
            D(f.message || "Failed to load message facts defaults"));
        } finally {
          P(!1);
        }
      }, []);
    o.useEffect(() => {
      M();
    }, [M]);
    const N = o.useCallback((f, O) => {
        (h((H) => ({
          ...H,
          messages: H.messages.map((z) =>
            z.localID === f ? { ...z, ...O } : z,
          ),
        })),
          T(null));
      }, []),
      K = o.useCallback((f) => {
        (h((O) => {
          const H = O.messages.findIndex(
              (ne) => ne.localID === O.targetLocalID,
            ),
            z = H >= 0 ? H : 0,
            B = O.messages[z],
            V = f === "above" ? z : z + 1,
            A = f === "above" ? -6e4 : 6e4,
            Y = Ne({
              roomID: B.roomID,
              accountID: B.accountID,
              senderContactID: B.senderContactID,
              senderDisplayName: B.senderDisplayName,
              timestamp: B.timestamp + A,
              messageEventID: `$debug-message-${O.messages.length + 1}`,
              text: "",
            });
          return {
            ...O,
            messages: [...O.messages.slice(0, V), Y, ...O.messages.slice(V)],
          };
        }),
          T(null));
      }, []),
      G = o.useCallback((f) => {
        (h((O) =>
          f === O.targetLocalID
            ? O
            : { ...O, messages: O.messages.filter((H) => H.localID !== f) },
        ),
          T(null));
      }, []),
      R = o.useCallback(async () => {
        const f = $.findIndex((A) => A.localID === v),
          O = f >= 0 ? $[f] : null;
        if (!O?.text.trim()) {
          D("Target message needs text");
          return;
        }
        const H = $.slice(0, f).filter((A) => A.text.trim()),
          z = $.slice(f + 1).filter((A) => A.text.trim()),
          B = xr([...H, O, ...z]),
          V = B[H.length];
        (q(!0), D(null));
        try {
          const A = await Q.bapi.debug_dryRunMessageFactsExtraction({
            prompt: t,
            model: r || void 0,
            messages: [V],
            targetMessage: V,
            contextBefore: B.slice(0, H.length),
            contextAfter: B.slice(H.length + 1),
          });
          T(A);
        } catch (A) {
          (console.error("Failed to dry-run message facts extraction:", A),
            D(A.message || "Failed to dry-run message facts extraction"));
        } finally {
          q(!1);
        }
      }, [$, r, t, v]),
      I = o.useMemo(() => {
        if (!c) return null;
        const f = c.enriched.filter((O) => O.enrichmentData).length;
        return `${c.honeycomb.length} Honeycomb facts, ${f} enriched, ${c.wouldPersist.length} would write`;
      }, [c]);
    return e.jsxs("div", {
      className: a.promptTester,
      children: [
        e.jsxs("header", {
          className: `${a.header} app-region-drag`,
          children: [
            e.jsxs("div", {
              className: a.headerContent,
              children: [
                e.jsxs("div", {
                  children: [
                    e.jsx("h1", { children: "Facts Flow Tester" }),
                    e.jsxs("div", {
                      className: a.headerMeta,
                      children: [
                        e.jsxs("span", {
                          children: [
                            "1 target, ",
                            Math.max(0, $.length - 1),
                            " context messages",
                          ],
                        }),
                        I && e.jsx("span", { children: I }),
                      ],
                    }),
                  ],
                }),
                e.jsxs("div", {
                  className: a.headerActions,
                  children: [
                    e.jsx("button", {
                      type: "button",
                      className: a.secondaryButton,
                      onClick: M,
                      disabled: k || F,
                      children: "Defaults",
                    }),
                    e.jsx("button", {
                      type: "button",
                      className: a.primaryButton,
                      onClick: R,
                      disabled: k || F || !t.trim(),
                      children: F ? "Running..." : "Run Flow",
                    }),
                  ],
                }),
              ],
            }),
            W && e.jsx("div", { className: a.errorBar, children: W }),
            c?.warnings.length
              ? e.jsx("div", {
                  className: a.warningBar,
                  children: c.warnings.join(" | "),
                })
              : null,
          ],
        }),
        e.jsxs("main", {
          className: a.content,
          children: [
            e.jsxs("section", {
              className: a.inputPane,
              children: [
                e.jsxs("div", {
                  className: a.section,
                  children: [
                    e.jsxs("div", {
                      className: a.sectionHeader,
                      children: [
                        e.jsx("span", { children: "Prompt" }),
                        e.jsx("input", {
                          className: a.textInput,
                          value: r,
                          onChange: (f) => m(f.target.value),
                          placeholder: "Model",
                        }),
                      ],
                    }),
                    e.jsx("textarea", {
                      className: a.promptInput,
                      value: t,
                      onChange: (f) => {
                        (s(f.target.value), T(null));
                      },
                      placeholder: k ? "Loading defaults..." : "System prompt",
                    }),
                  ],
                }),
                e.jsxs("div", {
                  className: `${a.section} ${a.messagesSection}`,
                  children: [
                    e.jsxs("div", {
                      className: a.sectionHeader,
                      children: [
                        e.jsxs("div", {
                          className: a.sectionHeaderText,
                          children: [
                            e.jsx("span", { children: "Conversation Window" }),
                            e.jsx("span", {
                              className: a.sectionHint,
                              children:
                                "Add messages above or below the target. Only the target is extracted; the rest are sent as context.",
                            }),
                          ],
                        }),
                        e.jsxs("div", {
                          className: a.headerActions,
                          children: [
                            e.jsx("button", {
                              type: "button",
                              className: a.secondaryButton,
                              onClick: () => K("above"),
                              children: "Add Above",
                            }),
                            e.jsx("button", {
                              type: "button",
                              className: a.secondaryButton,
                              onClick: () => K("below"),
                              children: "Add Below",
                            }),
                          ],
                        }),
                      ],
                    }),
                    e.jsx("div", {
                      className: a.messagesList,
                      children: $.map((f, O) => {
                        const H = O - u,
                          z = f.localID === v,
                          B = z
                            ? "Extraction target"
                            : H < 0
                              ? `Context ${Math.abs(H)} before target`
                              : `Context ${H} after target`,
                          V = z
                            ? "Facts are extracted from this message."
                            : "Sent to the LLM only to help interpret the target.";
                        return e.jsxs(
                          "article",
                          {
                            className: `${a.messageEditor} ${z ? a.targetMessageEditor : a.contextMessageEditor}`,
                            children: [
                              e.jsxs("div", {
                                className: a.messageRunHeader,
                                children: [
                                  e.jsxs("div", {
                                    children: [
                                      e.jsx("div", {
                                        className: a.messageRunTitle,
                                        children: B,
                                      }),
                                      e.jsx("div", {
                                        className: a.messageRunSubtitle,
                                        children: V,
                                      }),
                                    ],
                                  }),
                                  e.jsx(X, {
                                    tone: z ? "good" : "muted",
                                    children: z ? "target" : "context only",
                                  }),
                                ],
                              }),
                              e.jsxs("div", {
                                className: a.messageEditorHeader,
                                children: [
                                  e.jsx("input", {
                                    className: a.textInput,
                                    value: f.senderContactID,
                                    onChange: (A) =>
                                      N(f.localID, {
                                        senderContactID: A.target.value,
                                      }),
                                    placeholder: "senderContactID",
                                  }),
                                  e.jsx("input", {
                                    className: a.textInput,
                                    value: f.senderDisplayName,
                                    onChange: (A) =>
                                      N(f.localID, {
                                        senderDisplayName: A.target.value,
                                      }),
                                    placeholder: "Display name",
                                  }),
                                  e.jsx("input", {
                                    className: a.textInput,
                                    type: "datetime-local",
                                    value: ur(f.timestamp),
                                    onChange: (A) =>
                                      N(f.localID, {
                                        timestamp: hr(A.target.value),
                                      }),
                                  }),
                                  z
                                    ? e.jsx("span", {
                                        className: a.targetLock,
                                        children: "Target",
                                      })
                                    : e.jsx("button", {
                                        type: "button",
                                        className: a.dangerButton,
                                        onClick: () => G(f.localID),
                                        children: "Remove",
                                      }),
                                ],
                              }),
                              e.jsx("textarea", {
                                className: a.messageInput,
                                value: f.text,
                                onChange: (A) =>
                                  N(f.localID, { text: A.target.value }),
                                placeholder: z ? "Target message" : B,
                              }),
                              e.jsxs("div", {
                                className: a.messageEditorMeta,
                                children: [
                                  f.accountID,
                                  " | ",
                                  f.roomID,
                                  " | ",
                                  f.messageEventID,
                                ],
                              }),
                            ],
                          },
                          f.localID,
                        );
                      }),
                    }),
                  ],
                }),
              ],
            }),
            e.jsx("section", {
              className: a.outputPane,
              children: c
                ? e.jsxs("div", {
                    className: a.resultsList,
                    children: [
                      c.messages.map((f) =>
                        e.jsx(
                          Tr,
                          { trace: f },
                          `${f.message.messageEventID}-${f.messageIndex}`,
                        ),
                      ),
                      e.jsx(yr, { title: "Full response JSON", data: c }),
                    ],
                  })
                : e.jsx("div", {
                    className: a.emptyState,
                    children:
                      "Run the flow to see gates, facts, enrichment, and would-write output for the target message.",
                  }),
            }),
          ],
        }),
      ],
    });
  }),
  Ar = de(({ wss: t, ...s }) => {
    const r = t?.windowType;
    return e.jsx(ke.Provider, {
      value: t,
      children: e.jsx(o.StrictMode, {
        children: e.jsx(Re, {
          children: e.jsxs("div", {
            className: ra.container,
            children: [
              r === "devtools-room-explorer" && e.jsx(qs, { wss: t }),
              r === "devtools-event-explorer" &&
                e.jsx(oa, { wss: t, eventID: s.eventID }),
              r === "devtools-data-explorer" && e.jsx(ka, {}),
              r === "devtools-facts-prompt-tester" && e.jsx(Cr, {}),
              r === "devtools-custom-event" && e.jsx(so, { wss: t }),
              Be,
            ],
          }),
        }),
      }),
    });
  });
export { Ar as DebugApp };
//# sourceMappingURL=DebugApp-BIyrgm2A.js.map
