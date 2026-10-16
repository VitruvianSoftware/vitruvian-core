import {
  de as n,
  cF as e,
  aB as Ie,
  cT as de,
  aV as $e,
  bW as je,
  ed as Te,
  br as Ee,
  J as De,
  I as Be,
  L as Me,
  b5 as Re,
  U as Ae,
} from "./App-BHgTsVmv.js";
import { ab as Le, X as Fe } from "./sentry-common-BNqrY_yc.js";
import {
  aq as me,
  cR as Pe,
  cA as Q,
  au as qe,
} from "./matrix-util-8DbIGEm-.js";
import "./index-Cw3pknxT.js";
import "./index-Ch31Akxs.js";
import "./index-5FBEE1WD.js";
import "./main-process-state-BDOn7dvV.js";
import "./report-dialog-C-g_klPx.js";
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
      (t._sentryDebugIds[s] = "cdda12f4-df98-4484-8d4d-7003d5f30a71"),
      (t._sentryDebugIdIdentifier =
        "sentry-dbid-cdda12f4-df98-4484-8d4d-7003d5f30a71"));
  } catch {}
})();
const He = "_roomStateExplorer_e3abv_2",
  Oe = "_header_e3abv_13",
  ze = "_headerContent_e3abv_22",
  Ve = "_headerInfo_e3abv_30",
  We = "_headerText_e3abv_38",
  Ke = "_headerTitle_e3abv_43",
  Je = "_headerRoomId_e3abv_57",
  Ge = "_headerActions_e3abv_66",
  Ue = "_actionButton_e3abv_73",
  Qe = "_primaryButton_e3abv_99",
  Xe = "_tabBar_e3abv_111",
  Ye = "_tabButton_e3abv_117",
  Ze = "_activeTab_e3abv_136",
  et = "_errorBar_e3abv_157",
  tt = "_errorIcon_e3abv_168",
  st = "_errorMessage_e3abv_172",
  at = "_statusBar_e3abv_178",
  nt = "_statusLoading_e3abv_191",
  ot = "_loadingSpinner_e3abv_197",
  rt = "_contentContainer_e3abv_212",
  ct = "_loadingState_e3abv_221",
  it = "_emptyState_e3abv_234",
  lt = "_emoji_e3abv_244",
  W = {
    roomStateExplorer: He,
    header: Oe,
    headerContent: ze,
    headerInfo: Ve,
    headerText: We,
    headerTitle: Ke,
    headerRoomId: Je,
    headerActions: Ge,
    actionButton: Ue,
    primaryButton: Qe,
    tabBar: Xe,
    tabButton: Ye,
    activeTab: Ze,
    errorBar: et,
    errorIcon: tt,
    errorMessage: st,
    statusBar: at,
    statusLoading: nt,
    loadingSpinner: ot,
    contentContainer: rt,
    loadingState: ct,
    emptyState: it,
    emoji: lt,
  },
  dt = "_viewer_1yjak_2",
  ut = "_toolbar_1yjak_14",
  mt = "_searchRow_1yjak_25",
  ht = "_controlsRow_1yjak_31",
  pt = "_searchContainer_1yjak_38",
  _t = "_pathContainer_1yjak_46",
  gt = "_searchInputWrapper_1yjak_50",
  xt = "_searchHistoryButton_1yjak_57",
  ft = "_searchHistoryDropdown_1yjak_70",
  yt = "_searchHistoryItem_1yjak_84",
  jt = "_pathNavigator_1yjak_96",
  vt = "_searchInput_1yjak_50",
  bt = "_searchInfo_1yjak_120",
  Nt = "_controls_1yjak_31",
  wt = "_autoExpandCheckbox_1yjak_138",
  St = "_controlButton_1yjak_150",
  Ct = "_objectTree_1yjak_165",
  kt = "_emptyObject_1yjak_171",
  It = "_noMatches_1yjak_171",
  $t = "_node_1yjak_178",
  Tt = "_nodeHeader_1yjak_185",
  Et = "_actions_1yjak_214",
  Dt = "_cmdKeyActive_1yjak_217",
  Bt = "_expandIcon_1yjak_232",
  Mt = "_expanded_1yjak_247",
  Rt = "_expandIconPlaceholder_1yjak_251",
  At = "_nodeName_1yjak_258",
  Lt = "_nodeValue_1yjak_264",
  Ft = "_valueString_1yjak_272 _nodeValue_1yjak_264",
  Pt = "_valueNumber_1yjak_277 _nodeValue_1yjak_264",
  qt = "_valueBoolean_1yjak_282 _nodeValue_1yjak_264",
  Ht = "_valueNull_1yjak_287 _nodeValue_1yjak_264",
  Ot = "_valueFunction_1yjak_293 _nodeValue_1yjak_264",
  zt = "_valueObject_1yjak_299 _nodeValue_1yjak_264",
  Vt = "_children_1yjak_305",
  Wt = "_actionButton_1yjak_321",
  Kt = "_copied_1yjak_338",
  Jt = "_matchHighlight_1yjak_343",
  Gt = "_matchName_1yjak_352",
  Ut = "_matchValue_1yjak_358",
  Qt = "_hasMatchingDescendant_1yjak_364",
  Xt = "_hasMatches_1yjak_369",
  Yt = "_matchCount_1yjak_372",
  Zt = "_hiddenItemsCount_1yjak_381",
  es = "_siblingOfMatch_1yjak_395",
  ts = "_pinnedItem_1yjak_400",
  ss = "_pinnedDescendant_1yjak_408",
  as = "_pathSegment_1yjak_413",
  ns = "_active_1yjak_423",
  os = "_pathSeparator_1yjak_428",
  rs = "_keyboardNavActive_1yjak_433",
  cs = "_expandAction_1yjak_449",
  is = "_flashExpand_1yjak_1",
  ls = "_collapseAction_1yjak_453",
  ds = "_flashCollapse_1yjak_1",
  us = "_pinAction_1yjak_457",
  ms = "_flashPin_1yjak_1",
  hs = "_unpinAction_1yjak_461",
  ps = "_flashUnpin_1yjak_1",
  _s = "_flashActive_1yjak_530",
  gs = "_flashActiveNode_1yjak_1",
  xs = "_previewTooltip_1yjak_534",
  fs = "_previewFadeIn_1yjak_1",
  ys = "_previewContainer_1yjak_559",
  js = "_previewNode_1yjak_565",
  vs = "_previewNodeHeader_1yjak_569",
  bs = "_previewNodeName_1yjak_576",
  Ns = "_previewNodeChildren_1yjak_582",
  ws = "_keyboardHelp_1yjak_606",
  Ss = "_baseWindow_1yjak_617",
  Cs = "_windowFadeIn_1yjak_1",
  ks = "_windowTitleBar_1yjak_630",
  Is = "_windowTitle_1yjak_630",
  $s = "_windowCloseButton_1yjak_648",
  Ts = "_windowContent_1yjak_667",
  Es = "_keyboardHelpWindow_1yjak_673 _baseWindow_1yjak_617",
  Ds = "_shortcutsGroup_1yjak_677",
  Bs = "_shortcutsNote_1yjak_695",
  Ms = "_dedicatedViewContainer_1yjak_719 _baseWindow_1yjak_617",
  Rs = "_dedicatedViewHeader_1yjak_727",
  As = "_dedicatedViewTitle_1yjak_739",
  Ls = "_dedicatedViewClose_1yjak_751",
  Fs = "_dedicatedViewContent_1yjak_770",
  Ps = "_dedicatedNode_1yjak_779",
  qs = "_dedicatedNodeHeader_1yjak_783",
  Hs = "_dedicatedNodeName_1yjak_789",
  Os = "_dedicatedNodeChildren_1yjak_795",
  zs = "_tooltipFadeIn_1yjak_1",
  g = {
    viewer: dt,
    toolbar: ut,
    searchRow: mt,
    controlsRow: ht,
    searchContainer: pt,
    pathContainer: _t,
    searchInputWrapper: gt,
    searchHistoryButton: xt,
    searchHistoryDropdown: ft,
    searchHistoryItem: yt,
    pathNavigator: jt,
    searchInput: vt,
    searchInfo: bt,
    controls: Nt,
    autoExpandCheckbox: wt,
    controlButton: St,
    objectTree: Ct,
    emptyObject: kt,
    noMatches: It,
    node: $t,
    nodeHeader: Tt,
    actions: Et,
    cmdKeyActive: Dt,
    expandIcon: Bt,
    expanded: Mt,
    expandIconPlaceholder: Rt,
    nodeName: At,
    nodeValue: Lt,
    valueString: Ft,
    valueNumber: Pt,
    valueBoolean: qt,
    valueNull: Ht,
    valueFunction: Ot,
    valueObject: zt,
    children: Vt,
    actionButton: Wt,
    copied: Kt,
    matchHighlight: Jt,
    matchName: Gt,
    matchValue: Ut,
    hasMatchingDescendant: Qt,
    hasMatches: Xt,
    matchCount: Yt,
    hiddenItemsCount: Zt,
    siblingOfMatch: es,
    pinnedItem: ts,
    pinnedDescendant: ss,
    pathSegment: as,
    active: ns,
    pathSeparator: os,
    keyboardNavActive: rs,
    expandAction: cs,
    flashExpand: is,
    collapseAction: ls,
    flashCollapse: ds,
    pinAction: us,
    flashPin: ms,
    unpinAction: hs,
    flashUnpin: ps,
    flashActive: _s,
    flashActiveNode: gs,
    previewTooltip: xs,
    previewFadeIn: fs,
    previewContainer: ys,
    previewNode: js,
    previewNodeHeader: vs,
    previewNodeName: bs,
    previewNodeChildren: Ns,
    keyboardHelp: ws,
    baseWindow: Ss,
    windowFadeIn: Cs,
    windowTitleBar: ks,
    windowTitle: Is,
    windowCloseButton: $s,
    windowContent: Ts,
    keyboardHelpWindow: Es,
    shortcutsGroup: Ds,
    shortcutsNote: Bs,
    dedicatedViewContainer: Ms,
    dedicatedViewHeader: Rs,
    dedicatedViewTitle: As,
    dedicatedViewClose: Ls,
    dedicatedViewContent: Fs,
    dedicatedNode: Ps,
    dedicatedNodeHeader: qs,
    dedicatedNodeName: Hs,
    dedicatedNodeChildren: Os,
    tooltipFadeIn: zs,
  },
  be = n.createContext({ expandedPaths: new Set(), togglePath: () => {} }),
  Vs = () => n.useContext(be),
  Ws = ({
    name: t,
    value: s,
    depth: r,
    path: u,
    searchTerm: _,
    matchingPaths: h,
    matchCounts: i,
    autoExpandSearchResults: k,
    showSiblings: R,
    showOnlyPinned: D,
    pinnedPaths: E,
    onPin: U,
    activePath: z,
  }) => {
    const { expandedPaths: $, togglePath: B } = Vs(),
      b = n.useMemo(() => {
        if (u.length === 0 && t === "") return "";
        if (t && t.startsWith("[") && t.endsWith("]")) {
          const l = u.join(".");
          return l ? `${l}${t}` : t;
        }
        return [...u, t].join(".");
      }, [u, t]),
      m = $.has(b),
      L = typeof s,
      w = s !== null && L === "object",
      V = Array.isArray(s),
      J = w && ((V && s.length > 0) || (!V && Object.keys(s).length > 0)),
      A = n.useMemo(
        () =>
          s === null
            ? "null"
            : s === void 0
              ? "undefined"
              : L === "string"
                ? `"${s}"`
                : L === "function"
                  ? "function() { ... }"
                  : V
                    ? `Array(${s.length})`
                    : w
                      ? `{${Object.keys(s).length} items}`
                      : String(s),
        [s, L, w, V],
      ),
      T = n.useMemo(
        () =>
          _
            ? h.has(b)
              ? !0
              : s !== null && typeof s != "object"
                ? String(s).toLowerCase().includes(_.toLowerCase())
                : !!(t && t.toLowerCase().includes(_.toLowerCase()))
            : !1,
        [h, b, _, s, t],
      ),
      x = n.useMemo(() => {
        if (!_) return !1;
        if (T) return !0;
        if (w) {
          if (b === "" || u.length === 0) return h.size > 0;
          const l = b === "" ? t : b;
          for (const o of h)
            if (
              o.startsWith(l + ".") ||
              o.startsWith(l + "[") ||
              (o.includes("[") && o.split("[")[0] === l)
            )
              return !0;
        }
        return !1;
      }, [h, b, t, u.length, _, w, T]),
      M = n.useMemo(
        () => (!_ || !R || T || x ? !1 : h.has(b) && !T),
        [_, R, T, x, h, b],
      ),
      H = n.useMemo(() => E.has(b), [E, b]),
      K = n.useMemo(
        () =>
          H || !w
            ? !1
            : b === ""
              ? Array.from(E).some((l) => l.includes(".") || l.includes("["))
              : Array.from(E).some(
                  (l) =>
                    l.startsWith(b + ".") ||
                    (V && l.startsWith(b + "[")) ||
                    (l.includes("[") && l.split("[")[0] === b),
                ),
        [H, w, b, E, V],
      ),
      [F, O] = n.useState(""),
      [P, X] = n.useState(""),
      oe = n.useCallback(
        (l) => {
          l.stopPropagation();
          const o = w ? JSON.stringify(s, null, 2) : String(s);
          (me(o), O("copied"), setTimeout(() => O(""), 800));
        },
        [s, w],
      ),
      se = n.useCallback(
        (l) => {
          (l.stopPropagation(),
            me(b),
            X("copied"),
            setTimeout(() => X(""), 800));
        },
        [b],
      ),
      Z = n.useMemo(
        () =>
          s == null
            ? g.valueNull
            : L === "boolean"
              ? g.valueBoolean
              : L === "number"
                ? g.valueNumber
                : L === "string"
                  ? g.valueString
                  : L === "function"
                    ? g.valueFunction
                    : g.valueObject,
        [s, L],
      ),
      le = n.useCallback(
        (l) => {
          (l.stopPropagation(), U(b));
        },
        [b, U],
      ),
      ue = n.useMemo(() => {
        if (!_ || !w || !s) return 0;
        const l = V ? s.length : Object.keys(s).length;
        if (!m) return 0;
        let o = 0;
        if (V)
          for (let d = 0; d < s.length; d++) {
            const v = `${[...u, t].join(".")}[${d}]`,
              C = h.has(v),
              q = Array.from(h).some(
                (ee) => ee.startsWith(v + ".") || ee.startsWith(v + "["),
              );
            (C || q) && o++;
          }
        else
          for (const d of Object.keys(s)) {
            const f = [...u, t, d].join("."),
              v = h.has(f),
              C = Array.from(h).some(
                (q) => q.startsWith(f + ".") || q.startsWith(f + "["),
              );
            (v || C) && o++;
          }
        return Math.max(0, l - o);
      }, [_, w, V, s, m, u, t, h]),
      he = n.useMemo(() => {
        if ((!_ && !D) || H || r === 0 || u.length === 0 || T || x) return !0;
        if (R && u.length > 0) {
          const l = u.slice(0, -1).join(".");
          if (h.has(l)) return !0;
          if (b.includes("[")) {
            const o = b.split("[")[0];
            if (h.has(o)) return !0;
            for (const d of h) if (d.startsWith(o + "[") && d !== b) return !0;
          }
        }
        if (D) {
          if (K) return !0;
          if (u.length > 0) {
            const l = u.slice(0, -1).join(".");
            if (
              Array.from(E).some((d) => {
                const f = d.split(".");
                return f.length === u.length && f.slice(0, -1).join(".") === l;
              })
            )
              return !0;
          }
          return !1;
        }
        return !1;
      }, [_, b, r, u, T, x, R, H, K, D, E, h]);
    (n.useMemo(() => (V ? s : []), [V, s]),
      n.useEffect(() => {
        _ && k && x && !m && B(b);
      }, [_, x, m, b, k, B]));
    const c = n.useCallback(
        () =>
          !V || !m
            ? null
            : e.jsx("div", {
                className: g.children,
                children: s.map((l, o) => {
                  const d = `[${o}]`,
                    f = u.join("."),
                    v = f ? `${f}.${t}${d}` : `${t}${d}`;
                  return (
                    console.log(
                      `Array item: index=${o}, parentPath=${f}.${t}, fullPath=${v}`,
                    ),
                    e.jsx(
                      ye,
                      {
                        name: d,
                        value: l,
                        depth: r + 1,
                        path: f ? [...u, t] : [t],
                        searchTerm: _,
                        matchingPaths: h,
                        matchCounts: i,
                        autoExpandSearchResults: k,
                        showSiblings: R,
                        showOnlyPinned: D,
                        pinnedPaths: E,
                        onPin: U,
                        activePath: z,
                      },
                      v,
                    )
                  );
                }),
              }),
        [V, m, s, r, u, t, _, $, h, i, k, R, D, E, U, z],
      ),
      [N, y] = n.useState(!1),
      p = n.useRef(null);
    if (
      (n.useEffect(() => {
        const l = (d) => {
            (d.metaKey || d.ctrlKey) && y(!0);
          },
          o = (d) => {
            !d.metaKey && !d.ctrlKey && y(!1);
          };
        return (
          window.addEventListener("keydown", l),
          window.addEventListener("keyup", o),
          window.addEventListener("blur", () => y(!1)),
          () => {
            (window.removeEventListener("keydown", l),
              window.removeEventListener("keyup", o),
              window.removeEventListener("blur", () => y(!1)));
          }
        );
      }, []),
      !he)
    )
      return e.jsx(e.Fragment, {});
    const j = `path-${b.replace(/\./g, "-")}`,
      S = z === b;
    return e.jsxs("div", {
      id: j,
      ref: p,
      className: `${g.node}
      ${T ? g.matchHighlight : ""}
      ${x ? g.hasMatchingDescendant : ""}
      ${M ? g.siblingOfMatch : ""}
      ${H ? g.pinnedItem : ""}
      ${K ? g.pinnedDescendant : ""}
      ${S ? g.keyboardNavActive : ""}`,
      "data-sentry-component": "ObjectNode",
      "data-sentry-source-file": "ObjectExplorer.tsx",
      children: [
        e.jsxs("div", {
          className: `${g.nodeHeader} ${N && w ? g.cmdKeyActive : ""} ${T ? g.matchHighlight : ""}`,
          style: { paddingLeft: `${r * 16}px` },
          onClick: (l) => {
            (l.stopPropagation(),
              console.log(`Click on ${b}, hasChildren: ${J}, isExpanded: ${m}`),
              B(b));
          },
          onDoubleClick: (l) => {
            (l.stopPropagation(),
              z === b
                ? window.dispatchEvent(
                    new CustomEvent("set-active-path", {
                      detail: { path: "" },
                    }),
                  )
                : window.dispatchEvent(
                    new CustomEvent("set-active-path", { detail: { path: b } }),
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
                J
                  ? e.jsxs("span", {
                      className: `${g.expandIcon} ${m ? g.expanded : ""} ${x ? g.hasMatches : ""}`,
                      onClick: (l) => {
                        (l.stopPropagation(),
                          console.log(`Icon click - toggle path: "${b}"`),
                          B(b));
                      },
                      title: m ? "Collapse" : "Expand",
                      children: [
                        "▶",
                        !m &&
                          x &&
                          e.jsx("span", {
                            className: g.matchCount,
                            children: "●",
                          }),
                      ],
                    })
                  : e.jsx("span", { className: g.expandIconPlaceholder }),
                e.jsxs("span", {
                  className: `${g.nodeName} ${T ? g.matchName : ""}`,
                  children: [t, ":"],
                }),
              ],
            }),
            (!m || !J) &&
              e.jsx("div", {
                style: { flex: 1 },
                children: e.jsx("span", {
                  className: `${Z} ${T && !w ? g.matchValue : ""}`,
                  children: A,
                }),
              }),
            _ &&
              m &&
              J &&
              ue > 0 &&
              e.jsxs("span", {
                className: g.hiddenItemsCount,
                onClick: (l) => {
                  (l.stopPropagation(),
                    window.dispatchEvent(
                      new CustomEvent("toggle-show-all", {
                        detail: { path: b },
                      }),
                    ));
                },
                title: "Click to toggle showing all hidden items",
                children: [ue, " hidden ", ue === 1 ? "item" : "items"],
              }),
            e.jsxs("div", {
              className: g.actions,
              onClick: (l) => l.stopPropagation(),
              children: [
                e.jsx("button", {
                  className: `${g.actionButton} ${H ? g.copied : ""}`,
                  onClick: le,
                  title: H ? "Unpin this item" : "Pin this item",
                  children: H ? "📌" : "📍",
                }),
                e.jsx("button", {
                  className: g.actionButton,
                  onClick: (l) => {
                    (l.stopPropagation(),
                      window.dispatchEvent(
                        new CustomEvent("search-node-value", {
                          detail: {
                            path: b,
                            value: w ? JSON.stringify(s) : String(s),
                          },
                        }),
                      ));
                  },
                  title: "Search for this value",
                  children: "🔍",
                }),
                e.jsx("button", {
                  className: `${g.actionButton} ${P ? g[P] : ""}`,
                  onClick: se,
                  title: "Copy path",
                  children: "path",
                }),
                e.jsx("button", {
                  className: `${g.actionButton} ${F ? g[F] : ""}`,
                  onClick: oe,
                  title: "Copy value",
                  children: "copy",
                }),
              ],
            }),
          ],
        }),
        m &&
          J &&
          (V
            ? c()
            : e.jsx("div", {
                className: g.children,
                children: Object.entries(s).map(([l, o]) =>
                  e.jsx(
                    ye,
                    {
                      name: l,
                      value: o,
                      depth: r + 1,
                      path: [...u, t],
                      searchTerm: _,
                      matchingPaths: h,
                      matchCounts: i,
                      autoExpandSearchResults: k,
                      showSiblings: R,
                      showOnlyPinned: D,
                      pinnedPaths: E,
                      onPin: U,
                      activePath: z,
                    },
                    `${b}.${l}`,
                  ),
                ),
              })),
      ],
    });
  },
  ye = n.memo(Ws, (t, s) => {
    const r = [...t.path, t.name].join("."),
      u = [...s.path, s.name].join(".");
    let _ = "";
    t.path.length > 0 ? (_ = t.path[0]) : t.name && (_ = t.name);
    const h = (_ && t.matchCounts?.[_]) || 0,
      i = (_ && s.matchCounts?.[_]) || 0;
    return (
      t.value === s.value &&
      t.matchingPaths.has(r) === s.matchingPaths.has(u) &&
      t.pinnedPaths.has(r) === s.pinnedPaths.has(u) &&
      t.searchTerm === s.searchTerm &&
      h === i &&
      t.autoExpandSearchResults === s.autoExpandSearchResults &&
      t.showSiblings === s.showSiblings &&
      t.showOnlyPinned === s.showOnlyPinned &&
      t.activePath === s.activePath
    );
  }),
  Ks = () => {
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
  Js = () => {
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
  Gs = () => {
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
  ie = ({ data: t, initialExpandLevel: s = "all" }) => {
    const [r, u] = n.useState(""),
      [_, h] = n.useState(Ks),
      [i, k] = n.useState(!1),
      [R, D] = n.useState(new Set(Gs())),
      [E, U] = n.useState(new Set()),
      [z, $] = n.useState(!0),
      [B, b] = n.useState(!0),
      [m, L] = n.useState(new Set(Js())),
      [w, V] = n.useState(""),
      [J, A] = n.useState({}),
      [T, x] = n.useState(!1),
      M = n.useRef(null),
      H = n.useCallback((c) => {
        (console.log(`Toggle path called with: ${c}`),
          D((N) => {
            const y = new Set(N);
            return (
              y.has(c)
                ? (console.log(`Removing path from expanded: ${c}`),
                  y.delete(c))
                : (console.log(`Adding path to expanded: ${c}`), y.add(c)),
              y
            );
          }));
      }, []),
      K = n.useMemo(() => ({ expandedPaths: R, togglePath: H }), [R, H]),
      F = n.useMemo(() => {
        try {
          return Pe(t);
        } catch {
          return t;
        }
      }, [t]),
      O = n.useRef(F);
    (n.useEffect(() => {
      const c = new Set(),
        N = (p, j = []) => {
          const S = j.join(".");
          (S && c.add(S),
            p &&
              typeof p == "object" &&
              (Array.isArray(p)
                ? p.forEach((l, o) => {
                    const d = `[${o}]`,
                      f = j.length
                        ? [...j.slice(0, -1), j[j.length - 1] + d]
                        : [d],
                      v = f.join(".");
                    (v && c.add(v),
                      typeof l == "object" && l !== null && N(l, f));
                  })
                : Object.entries(p).forEach(([l, o]) => {
                    const d = [...j, l],
                      f = d.join(".");
                    (f && c.add(f), o && typeof o == "object" && N(o, d));
                  })));
        },
        y = (p, j = [], S = 0) => {
          const l = typeof s == "number" ? s : 1 / 0;
          if (S >= l) return;
          const o = j.join(".");
          (o && c.add(o),
            p &&
              typeof p == "object" &&
              (Array.isArray(p)
                ? S < l - 1 &&
                  p.forEach((d, f) => {
                    const v = `[${f}]`,
                      C = j.length
                        ? [...j.slice(0, -1), j[j.length - 1] + v]
                        : [v],
                      q = C.join(".");
                    (q && c.add(q),
                      typeof d == "object" && d !== null && y(d, C, S + 1));
                  })
                : Object.entries(p).forEach(([d, f]) => {
                    const v = [...j, d],
                      C = v.join(".");
                    (C && c.add(C),
                      f && typeof f == "object" && y(f, v, S + 1));
                  })));
        };
      (s === "all" ? N(t) : y(t),
        console.log("Initial expanded paths:", Array.from(c)),
        D(c));
    }, [t, s]),
      n.useEffect(() => {
        if (!r || (_.length > 0 && _[0] === r)) return;
        const c = [r, ..._.filter((N) => N !== r)].slice(0, 10);
        h(c);
        try {
          localStorage.setItem(
            "objectExplorer.searchHistory",
            JSON.stringify(c),
          );
        } catch (N) {
          console.error("Failed to save search history to localStorage", N);
        }
      }, [r, _]),
      n.useEffect(() => {
        try {
          localStorage.setItem(
            "objectExplorer.pinnedPaths",
            JSON.stringify([...m]),
          );
        } catch (c) {
          console.error("Failed to save pinned paths to localStorage", c);
        }
      }, [m]),
      n.useEffect(() => {
        const c = setTimeout(() => {
          try {
            localStorage.setItem(
              "objectExplorer.expandedPaths",
              JSON.stringify([...R]),
            );
          } catch (N) {
            console.error("Failed to save expanded paths to localStorage", N);
          }
        }, 1e3);
        return () => clearTimeout(c);
      }, [R]),
      n.useEffect(() => {
        if (!r) {
          (U(new Set()), A({}));
          return;
        }
        const c = r.toLowerCase(),
          N = new Set(),
          y = new Set(),
          p = {},
          j = (o) => {
            if (!o) return;
            (N.add(o), y.add(o));
            let d = o.split(".")[0];
            (d.includes("[") && ((d = d.split("[")[0]), d || (d = "[0]")),
              d &&
                ((p[d] = (p[d] || 0) + 1),
                console.log(`Added match to ${d}, now has ${p[d]}`)));
            const f = o.split(".");
            let v = "";
            for (let C = 0; C < f.length; C++) {
              const q = f[C];
              if (q.includes("[")) {
                const ee = q.split("[")[0];
                ((v = v ? `${v}.${ee}` : ee), y.add(v));
                const ae = q.match(/\[\d+\]/g) || [];
                for (const ne of ae) ((v += ne), y.add(v));
              } else ((v = v ? `${v}.${q}` : q), y.add(v));
            }
          },
          S = (o, d) => {
            if (!B || !o || !d || typeof d != "object") return;
            const f = o.lastIndexOf("."),
              v = f > -1 ? o.substring(0, f) : "";
            if (Array.isArray(d)) {
              const C = o.lastIndexOf("["),
                q = o.lastIndexOf("]");
              if (C > -1 && q > C) {
                const ee = o.substring(C + 1, q),
                  ae = parseInt(ee);
                if (!isNaN(ae)) {
                  const ne = Math.max(0, ae - 2),
                    xe = Math.min(d.length, ae + 3);
                  for (let pe = ne; pe < xe; pe++)
                    if (pe !== ae) {
                      const ke = `${o.substring(0, C)}[${pe}]`;
                      y.add(ke);
                    }
                }
              }
            } else
              Object.keys(d).forEach((C) => {
                const q = v ? `${v}.${C}` : C;
                y.add(q);
              });
          },
          l = (o, d = "") => {
            if (o == null) return;
            let f = "";
            if (
              (d &&
                ((f = d.split(".")[0]),
                f.includes("[") &&
                  ((f = f.split("[")[0]),
                  f || (f = /\[\d+\]/.exec(d)?.[0] || ""))),
              typeof o != "object")
            ) {
              String(o).toLowerCase().includes(c) &&
                (j(d),
                f &&
                  !p[f] &&
                  ((p[f] = 1),
                  console.log(`Added first match for top-level key: ${f}`)));
              return;
            }
            Array.isArray(o)
              ? o.forEach((v, C) => {
                  const q = d ? `${d}[${C}]` : `[${C}]`;
                  if (
                    v !== null &&
                    typeof v != "object" &&
                    String(v).toLowerCase().includes(c) &&
                    (j(q),
                    d && y.add(d),
                    f &&
                      !p[f] &&
                      ((p[f] = 1),
                      console.log(
                        `Added first match for top-level key from array: ${f}`,
                      )),
                    B)
                  ) {
                    const ee = Math.max(0, C - 2),
                      ae = Math.min(o.length, C + 3);
                    for (let ne = ee; ne < ae; ne++)
                      if (ne !== C) {
                        const xe = d ? `${d}[${ne}]` : `[${ne}]`;
                        y.add(xe);
                      }
                  }
                  l(v, q);
                })
              : Object.entries(o).forEach(([v, C]) => {
                  const q = d ? `${d}.${v}` : v;
                  (v.toLowerCase().includes(c) &&
                    (j(q),
                    f &&
                      !p[f] &&
                      ((p[f] = 1),
                      console.log(
                        `Added first match for top-level key from key match: ${f}`,
                      )),
                    S(q, o)),
                    C !== null &&
                      typeof C != "object" &&
                      String(C).toLowerCase().includes(c) &&
                      (j(q),
                      f &&
                        !p[f] &&
                        ((p[f] = 1),
                        console.log(
                          `Added first match for top-level key from value match: ${f}`,
                        )),
                      S(q, o)),
                    l(C, q));
                });
          };
        if (
          (Object.keys(F).forEach((o) => {
            o.toLowerCase().includes(c) &&
              (N.add(o),
              y.add(o),
              (p[o] = (p[o] || 0) + 1),
              console.log(`Root key "${o}" matches search term directly`));
          }),
          l(F),
          Object.keys(p).forEach((o) => {
            p[o] > 0 &&
              (y.add(o),
              console.log(
                `Ensuring root key "${o}" with ${p[o]} matches is in relevant paths`,
              ));
          }),
          console.log(
            `Search '${r}': ${N.size} direct matches, ${y.size} total paths to show, Top matches:`,
            p,
          ),
          U(y),
          A(p),
          z && N.size > 0)
        ) {
          const o = new Set(R);
          (Object.keys(p).forEach((d) => {
            p[d] > 0 && o.add(d);
          }),
            y.forEach((d) => {
              const f = d.split(".");
              let v = "";
              for (let C = 0; C < f.length - 1; C++)
                if (f[C].includes("[")) {
                  const q = f[C].split("[")[0];
                  ((v = v ? `${v}.${q}` : q), o.add(v));
                  const ee = f[C].match(/\[\d+\]/g) || [];
                  for (const ae of ee) ((v += ae), o.add(v));
                } else ((v = v ? `${v}.${f[C]}` : f[C]), o.add(v));
            }),
            D(o));
        }
      }, [r, F, B, z, R]));
    const P = n.useCallback((c) => {
        L((N) => {
          const y = new Set(N);
          return (
            y.has(c)
              ? y.delete(c)
              : (y.add(c),
                D((p) => {
                  const j = new Set(p),
                    S = c.split(/\.|\[/);
                  let l = "";
                  for (let o = 0; o < S.length; o++)
                    (o === 0
                      ? (l = S[o])
                      : S[o].endsWith("]")
                        ? (l += S[o])
                        : (l += `.${S[o]}`),
                      l && j.add(l));
                  return j;
                })),
            y
          );
        });
      }, []),
      X = n.useCallback(() => {
        const c = [],
          N = (y, p = []) => {
            const j = p.join(".");
            (j && c.push(j),
              y &&
                typeof y == "object" &&
                (Array.isArray(y)
                  ? y.forEach((S, l) => {
                      const o = [...p];
                      if (o.length > 0) {
                        const f = o[o.length - 1];
                        o[o.length - 1] = `${f}[${l}]`;
                      } else o.push(`[${l}]`);
                      const d = o.join(".");
                      (d && c.push(d), S && typeof S == "object" && N(S, o));
                    })
                  : Object.entries(y).forEach(([S, l]) => {
                      const o = [...p, S],
                        d = o.join(".");
                      (d && c.push(d), l && typeof l == "object" && N(l, o));
                    })));
          };
        (N(F), D(new Set(c)));
      }, [F]),
      oe = n.useCallback(() => {
        D(new Set());
      }, []),
      se = n.useRef(null),
      [Z, le] = n.useState(!1);
    n.useEffect(() => {
      const c = (p) => {
          p.detail &&
            p.detail.path !== void 0 &&
            (V(p.detail.path),
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
        N = (p) => {
          if (p.detail?.value) {
            let j = p.detail.value;
            if (j.startsWith("{") || j.startsWith("["))
              try {
                const S = JSON.parse(j);
                if (typeof S == "object" && S !== null) {
                  for (const l in S)
                    if (typeof S[l] == "string" || typeof S[l] == "number") {
                      j = String(S[l]);
                      break;
                    }
                }
              } catch {
                j.length > 50 && (j = j.substring(0, 50));
              }
            (u(j), M.current && M.current.focus());
          }
        },
        y = (p) => {
          (le((j) => !j), Z || X());
        };
      return (
        window.addEventListener("set-active-path", c),
        window.addEventListener("search-node-value", N),
        window.addEventListener("toggle-show-all", y),
        () => {
          (window.removeEventListener("set-active-path", c),
            window.removeEventListener("search-node-value", N),
            window.removeEventListener("toggle-show-all", y));
        }
      );
    }, [Z, X]);
    const ue = n.useCallback(() => {
        (se.current &&
          (se.current.classList.add(g.copied),
          setTimeout(() => {
            se.current && se.current.classList.remove(g.copied);
          }, 800)),
          me(JSON.stringify(F, null, 2)));
      }, [F]),
      he = n.useCallback(() => {
        if (!r) return;
        const c = new Set();
        (Object.keys(J).forEach((N) => {
          c.add(N);
        }),
          E.forEach((N) => {
            N && c.add(N);
            const y = N.split(".");
            let p = "";
            for (let j = 0; j < y.length; j++)
              if (y[j].includes("[")) {
                const S = y[j].split("[")[0];
                ((p = p ? `${p}.${S}` : S), c.add(p));
                const l = y[j].match(/\[\d+\]/g) || [];
                let o = p;
                for (const d of l) ((o += d), c.add(o));
              } else ((p = p ? `${p}.${y[j]}` : y[j]), c.add(p));
          }),
          console.log("Expanding paths for matches:", c.size),
          D(c));
      }, [r, E, J]);
    return (
      n.useEffect(() => {
        O.current = F;
      }, [F]),
      n.useEffect(() => {
        const c = Object.keys(O.current || {})
            .sort()
            .join(","),
          N = Object.keys(F || {})
            .sort()
            .join(",");
        if (c !== N && c !== "" && N !== "") {
          const y = new Set(),
            p = (j, S = [], l = 0) => {
              if (l >= (typeof s == "number" ? s : 2)) return;
              const d = S.join(".");
              (d && y.add(d),
                j &&
                  typeof j == "object" &&
                  Object.entries(j).forEach(([f, v]) => {
                    const C = [...S, f],
                      q = C.join(".");
                    (q && y.add(q),
                      v && typeof v == "object" && p(v, C, l + 1));
                  }));
            };
          (p(F), D(y));
        }
      }, [F, s]),
      e.jsx(be.Provider, {
        value: K,
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
                        ref: M,
                        type: "text",
                        className: g.searchInput,
                        placeholder: "Search keys and values...",
                        value: r,
                        onChange: (c) => u(c.target.value),
                        onKeyDown: (c) => {
                          (c.key === "ArrowDown" &&
                            !i &&
                            _.length > 0 &&
                            (k(!0), c.preventDefault()),
                            c.key === "Escape" &&
                              (c.preventDefault(), u(""), M.current?.blur()));
                        },
                        onFocus: () => {
                          _.length > 0 && k(!0);
                        },
                        onBlur: (c) => {
                          (!c.relatedTarget ||
                            !c.relatedTarget.closest(
                              `.${g.searchHistoryDropdown}`,
                            )) &&
                            setTimeout(() => k(!1), 150);
                        },
                      }),
                      r &&
                        e.jsxs("div", {
                          className: g.searchInfo,
                          children: [
                            E.size,
                            " match",
                            E.size !== 1 ? "es" : "",
                            E.size > 0 &&
                              e.jsx("button", {
                                onClick: () => {
                                  (le(!Z), Z || (z ? X() : he()));
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
                      _.length > 0 &&
                        e.jsx("button", {
                          className: g.searchHistoryButton,
                          onClick: () => k(!i),
                          title: "Search history",
                          children: "⌄",
                        }),
                      i &&
                        _.length > 0 &&
                        e.jsx("div", {
                          className: g.searchHistoryDropdown,
                          children: _.map((c, N) =>
                            e.jsx(
                              "div",
                              {
                                className: g.searchHistoryItem,
                                onClick: () => {
                                  (u(c), k(!1), M.current && M.current.focus());
                                },
                                children: c,
                              },
                              N,
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
                        w &&
                        e.jsxs("div", {
                          className: g.pathNavigator,
                          children: [
                            e.jsx("span", { children: "Path:" }),
                            w
                              .split(/\.|\[/)
                              .filter(Boolean)
                              .map((c, N, y) =>
                                e.jsxs(
                                  Ie.Fragment,
                                  {
                                    children: [
                                      e.jsx("span", {
                                        className: `${g.pathSegment} ${N === y.length - 1 ? g.active : ""}`,
                                        onClick: () => {
                                          const p = y.slice(0, N + 1).join(".");
                                          (R.has(p) ||
                                            D((j) => {
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
                                          const p = y.slice(0, N + 1).join(".");
                                          if (w === p) {
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
                                        children: c,
                                      }),
                                      N < y.length - 1 &&
                                        e.jsx("span", {
                                          className: g.pathSeparator,
                                          children: ".",
                                        }),
                                    ],
                                  },
                                  N,
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
                              checked: z,
                              onChange: () => $(!z),
                            }),
                            "Auto-expand",
                          ],
                        }),
                        e.jsxs("label", {
                          className: g.autoExpandCheckbox,
                          children: [
                            e.jsx("input", {
                              type: "checkbox",
                              checked: B,
                              onChange: () => b(!B),
                            }),
                            "Show Siblings",
                          ],
                        }),
                        e.jsxs("label", {
                          className: g.autoExpandCheckbox,
                          children: [
                            e.jsx("input", {
                              type: "checkbox",
                              checked: T,
                              onChange: () => x(!T),
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
                          onClick: X,
                          children: "Expand All",
                        }),
                        e.jsx("button", {
                          className: g.controlButton,
                          onClick: oe,
                          children: "Collapse All",
                        }),
                        e.jsx("button", {
                          ref: se,
                          className: g.controlButton,
                          onClick: ue,
                          children: "Copy All",
                        }),
                        m.size > 0 &&
                          e.jsxs("button", {
                            className: g.controlButton,
                            onClick: () => L(new Set()),
                            title: "Clear all pinned items",
                            children: ["Clear Pins (", m.size, ")"],
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
                Object.keys(F).length === 0
                  ? e.jsx("div", {
                      className: g.emptyObject,
                      children: "Empty object",
                    })
                  : r && E.size === 0
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
                                    E.size,
                                    " paths",
                                  ],
                                }),
                                e.jsxs("div", {
                                  children: [
                                    e.jsx("strong", {
                                      children: "Matches per section:",
                                    }),
                                    " ",
                                    Object.entries(J)
                                      .map(([c, N]) =>
                                        N > 0 ? `${c}(${N})` : "",
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
                                    Array.from(E).slice(0, 10).join(", "),
                                  ],
                                }),
                              ],
                            }),
                          Object.entries(F).map(([c, N]) => {
                            if (
                              (console.log(
                                `Checking root key: ${c}, hasMatches: ${J[c] > 0}, inPaths: ${E.has(c)}`,
                              ),
                              r)
                            )
                              (J[c] > 0 || E.has(c)) &&
                                console.log(
                                  `Root key "${c}" has ${J[c] || 0} matches`,
                                );
                            else if (T) {
                              const j = m.has(c),
                                S = Array.from(m).some(
                                  (l) =>
                                    l.startsWith(`${c}.`) ||
                                    l.startsWith(`${c}[`),
                                );
                              if (!j && !S) return null;
                            }
                            const y = J[c] || 0,
                              p =
                                r && y > 0
                                  ? `${c} (${y} match${y !== 1 ? "es" : ""})`
                                  : c;
                            return e.jsx(
                              ye,
                              {
                                name: p,
                                value: N,
                                depth: 0,
                                path: [],
                                searchTerm: r,
                                matchingPaths: E,
                                matchCounts: J,
                                autoExpandSearchResults: z,
                                showSiblings: B,
                                showOnlyPinned: T,
                                pinnedPaths: m,
                                onPin: P,
                                activePath: w,
                              },
                              c,
                            );
                          }),
                          r &&
                            E.size > 0 &&
                            Object.values(J).every((c) => c === 0) &&
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
                                E.size,
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
  _e = ({ tab: t, currentTab: s, onClick: r, label: u }) =>
    e.jsx("button", {
      type: "button",
      className: `${W.tabButton} ${s === t ? W.activeTab : ""}`,
      onClick: () => r(t),
      "data-sentry-component": "TabButton",
      "data-sentry-source-file": "RoomStateExplorer.tsx",
      children: u,
    }),
  Us = de(({ wss: t }) => {
    const [s, r] = n.useState("mobx"),
      [u, _] = n.useState(null),
      [h, i] = n.useState(!1),
      [k, R] = n.useState(null),
      [D, E] = n.useState(!1);
    n.useEffect(() => {
      if (!t?.selectedThread?.id) return;
      async function m() {
        try {
          (i(!0), R(null));
          const L = t?.selectedThread;
          if (!L) return;
          const w = L.id,
            [V, J] = await Promise.all([
              Q.bapi.debug_getRoom(w),
              Q.database.getUnreadMessages(
                w,
                Q.beeperClientStore.state.user_id,
              ),
            ]),
            A = L;
          _({
            matrixState: V?.state || {},
            mobxState: A.stringifiableDebugInfo || {},
            databaseState: { thread: V?.thread || {}, unreadMessages: J },
            messagesState: {},
          });
        } catch (L) {
          (console.error("Failed to load room state:", L),
            R(L.message || "Failed to load room state"));
        } finally {
          i(!1);
        }
      }
      m();
    }, [t?.selectedThread?.id]);
    const U = n.useCallback(async () => {
        if (t?.selectedThread)
          try {
            (i(!0),
              R(null),
              await Q.bapi.refetchRoomStates([t.selectedThread.id]),
              _(null));
          } catch (m) {
            (console.error("Error resyncing room state:", m),
              R(`Error resyncing: ${m.message}`));
          } finally {
            i(!1);
          }
      }, [t?.selectedThread]),
      z = n.useCallback(() => {
        t?.selectedThread &&
          (me(t.selectedThread.id), E(!0), setTimeout(() => E(!1), 1e3));
      }, [t?.selectedThread]);
    if (!t?.selectedThread || !(t.selectedThread instanceof $e))
      return e.jsx("div", {
        className: W.roomStateExplorer,
        children: e.jsxs("div", {
          className: W.emptyState,
          children: [
            e.jsx("span", { className: W.emoji, children: "🔍" }),
            e.jsx("h2", { children: "No thread selected" }),
            e.jsx("p", { children: "Select a thread to explore its state" }),
          ],
        }),
      });
    const $ = t.selectedThread;
    function B(m) {
      return m
        ? {
            id: m.id,
            senderID: m.senderID,
            threadID: m.threadID,
            accountID: m.accountID,
            timestamp: m.timestamp,
            isSender: m.isSender,
            isAction: m.isAction,
            text: Te(m.text, { length: 100 }),
            eventID: m.extra?.eventID,
            type: m.extra?.type,
            action: m.action,
            impersonator: m.impersonator,
            participant: m.senderID ? $.getParticipant(m.senderID) : void 0,
          }
        : null;
    }
    const b = () => {
      if (!u) return null;
      switch (s) {
        case "mobx":
          return e.jsx(ie, {
            data: {
              thread: $?.stringifiableDebugInfo,
              typedMessage: je($?.roomFeatures.formatting, $?.typedJSON),
              participants: $?.debugParticipants,
            },
            initialExpandLevel: 3,
          });
        case "matrix":
          return e.jsx(ie, { data: u.matrixState, initialExpandLevel: 3 });
        case "database":
          return e.jsx(ie, { data: u.databaseState, initialExpandLevel: 3 });
        case "messages":
          return e.jsx(ie, {
            data: {
              input: je($?.roomFeatures.formatting, $?.typedJSON),
              lastPendingMessage: $.lastPendingMessage
                ? B($.lastPendingMessage)
                : null,
              lastNonSilentMessage: $.lastNonSilentMessage
                ? B($.lastNonSilentMessage)
                : null,
              messagesLastItem: $.messages.lastItem
                ? B($.messages.lastItem)
                : null,
              partialLastMessage: $.partialLastMessage
                ? B($.partialLastMessage)
                : null,
              selectedMessages:
                Q?.mainWSS.selectedThread?.id === $.id
                  ? Q?.mainWSS.selectedMessagesList.map((m) => B(m))
                  : "Main window is not focused on this chat",
              pendingMessages:
                Q?.mainWSS.selectedThread?.id === $.id
                  ? Array.from(
                      Q?.mainWSS.selectedThread?.pendingMessages.values() || [],
                    ).map((m) => B(m))
                  : "Main window is not focused on this chat",
            },
            initialExpandLevel: 3,
          });
        default:
          return null;
      }
    };
    return e.jsxs("div", {
      className: W.roomStateExplorer,
      children: [
        e.jsxs("div", {
          className: `${W.header} app-region-drag`,
          children: [
            e.jsxs("div", {
              className: W.headerContent,
              children: [
                e.jsx("div", {
                  className: W.headerInfo,
                  children: e.jsxs("div", {
                    className: W.headerText,
                    children: [
                      e.jsxs("h1", {
                        className: W.headerTitle,
                        children: [
                          "🔍 Room: ",
                          e.jsx("span", {
                            title: $.computedTitle || "",
                            children: $.computedTitle || "No computed title",
                          }),
                        ],
                      }),
                      e.jsx("div", {
                        className: W.headerRoomId,
                        title: $.id,
                        children: $.id,
                      }),
                    ],
                  }),
                }),
                e.jsxs("div", {
                  className: W.headerActions,
                  children: [
                    e.jsx("button", {
                      className: W.actionButton,
                      onClick: z,
                      disabled: h,
                      title: "Copy room ID to clipboard",
                      style: D
                        ? { backgroundColor: "#2ecc71", color: "#ffffff" }
                        : void 0,
                      children: D ? "✓ Copied" : "Copy ID",
                    }),
                    e.jsx("button", {
                      className: `${W.actionButton} ${W.primaryButton}`,
                      onClick: U,
                      disabled: h,
                      title: "Re-sync room state from server",
                      children: h ? "Loading..." : "Re-sync",
                    }),
                  ],
                }),
              ],
            }),
            e.jsxs("div", {
              className: W.tabBar,
              children: [
                e.jsx(_e, {
                  tab: "mobx",
                  currentTab: s,
                  onClick: r,
                  label: "MobX",
                }),
                e.jsx(_e, {
                  tab: "database",
                  currentTab: s,
                  onClick: r,
                  label: "Database",
                }),
                e.jsx(_e, {
                  tab: "messages",
                  currentTab: s,
                  onClick: r,
                  label: "Messages",
                }),
                e.jsx(_e, {
                  tab: "matrix",
                  currentTab: s,
                  onClick: r,
                  label: "Matrix",
                }),
              ],
            }),
            k &&
              e.jsxs("div", {
                className: W.errorBar,
                children: [
                  e.jsx("span", { className: W.errorIcon, children: "⚠️" }),
                  e.jsx("span", { className: W.errorMessage, children: k }),
                ],
              }),
            h &&
              e.jsx("div", {
                className: W.statusBar,
                children: e.jsxs("div", {
                  className: W.statusLoading,
                  children: [
                    e.jsx("div", { className: W.loadingSpinner }),
                    e.jsx("span", { children: "Loading room state..." }),
                  ],
                }),
              }),
          ],
        }),
        e.jsx("div", {
          className: W.contentContainer,
          children:
            h && !u
              ? e.jsxs("div", {
                  className: W.loadingState,
                  children: [
                    e.jsx("div", { className: W.loadingSpinner }),
                    e.jsx("span", { children: "Loading room state..." }),
                  ],
                })
              : b(),
        }),
      ],
    });
  }),
  Qs = "_header_nqi8m_1",
  Xs = "_eventList_nqi8m_12",
  Ys = "_title_nqi8m_20",
  Zs = "_subtitle_nqi8m_21",
  ea = "_searchInput_nqi8m_36",
  ta = "_event_nqi8m_12",
  sa = "_wrapper_nqi8m_65",
  te = {
    header: Qs,
    eventList: Xs,
    title: Ys,
    subtitle: Zs,
    searchInput: ea,
    event: ta,
    wrapper: sa,
  },
  aa = ({ item: t, expanded: s, setExpanded: r }) => {
    const u = t.normalizedTimestamp,
      _ = t.normalizedType;
    return e.jsxs("section", {
      className: Ee(te.event, { [te.isExpanded]: s }),
      "data-sentry-component": "ExpandableEvent",
      "data-sentry-source-file": "EventExplorer.tsx",
      children: [
        e.jsxs("header", {
          onClick: () => r(!s),
          children: [
            e.jsx("div", { children: _ }),
            e.jsx("div", {
              className: te.timestamp,
              children: new Date(u ?? 0).toISOString().slice(0, -5),
            }),
          ],
        }),
        s && e.jsx(ie, { data: t }),
      ],
    });
  },
  na = de(({ wss: t, eventID: s }) => {
    const [r, u] = n.useState([]),
      [_, h] = n.useState(!0),
      [i, k] = n.useState(null),
      [R, D] = n.useState(""),
      [E, U] = n.useState(new Set()),
      z = n.useCallback(
        async (m) => {
          if (!(!t?.selectedThread?.id || !m))
            try {
              const L = t.selectedThread.id,
                w = await Q.bapi.fetchEventExplorerData(L, m);
              u(w);
            } catch (L) {
              k(`Error fetching data: ${L.message}`);
            }
        },
        [t?.selectedThread?.id],
      );
    n.useEffect(() => {
      (h(!0), k(null), u([]), z(s).finally(() => h(!1)));
    }, [s, z]);
    const $ = (m) => {
        U((L) => {
          const w = new Set(L);
          return (w.has(m) ? w.delete(m) : w.add(m), w);
        });
      },
      B = n.useMemo(() => qe((m) => D(m), 300), [D]),
      b = n.useMemo(
        () =>
          r.filter(
            (m) =>
              m.normalizedType.toLowerCase().includes(R.toLowerCase()) ||
              JSON.stringify(m).toLowerCase().includes(R.toLowerCase()),
          ),
        [r, R],
      );
    return i
      ? e.jsxs("div", { className: te.error, children: ["Error: ", i] })
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
                  onChange: (m) => B(m.target.value),
                  className: te.searchInput,
                  placeholder: "Filter by type or content...",
                  autoFocus: !0,
                }),
              ],
            }),
            _ &&
              e.jsx("div", {
                className: te.loading,
                children: "Loading events and messages...",
              }),
            e.jsx("div", {
              className: te.eventList,
              children: b.map((m) =>
                e.jsx(
                  aa,
                  {
                    item: m,
                    expanded: E.has(m.normalizedID),
                    setExpanded: () => $(m.normalizedID),
                  },
                  m.normalizedID,
                ),
              ),
            }),
          ],
        });
  }),
  oa = "_container_8rae1_1",
  ra = { container: oa },
  ca = "_dataExplorer_zu21g_2",
  ia = "_header_zu21g_13",
  la = "_headerContent_zu21g_22",
  da = "_headerInfo_zu21g_30",
  ua = "_headerIcon_zu21g_38",
  ma = "_headerText_zu21g_43",
  ha = "_headerTitle_zu21g_48",
  pa = "_headerActions_zu21g_62",
  _a = "_actionButton_zu21g_70",
  ga = "_primaryButton_zu21g_96",
  xa = "_dropdownMenu_zu21g_108",
  fa = "_dropdownItem_zu21g_124",
  ya = "_statusBar_zu21g_145",
  ja = "_statusLoading_zu21g_164",
  va = "_loadingSpinner_zu21g_170",
  ba = "_errorBar_zu21g_185",
  Na = "_errorIcon_zu21g_196",
  wa = "_errorMessage_zu21g_200",
  Sa = "_contentContainer_zu21g_206",
  Ca = "_loadingState_zu21g_215",
  ka = "_emptyState_zu21g_228",
  Ia = "_emoji_zu21g_238",
  $a = "_actionResult_zu21g_253",
  Ta = "_actionResultHeader_zu21g_266",
  Ea = "_actionResultTitle_zu21g_276",
  Da = "_actionResultControls_zu21g_283",
  Ba = "_actionResultContent_zu21g_288",
  Ma = "_collapseButton_zu21g_294",
  I = {
    dataExplorer: ca,
    header: ia,
    headerContent: la,
    headerInfo: da,
    headerIcon: ua,
    headerText: ma,
    headerTitle: ha,
    headerActions: pa,
    actionButton: _a,
    primaryButton: ga,
    dropdownMenu: xa,
    dropdownItem: fa,
    statusBar: ya,
    statusLoading: ja,
    loadingSpinner: va,
    errorBar: ba,
    errorIcon: Na,
    errorMessage: wa,
    contentContainer: Sa,
    loadingState: Ca,
    emptyState: ka,
    emoji: Ia,
    actionResult: $a,
    actionResultHeader: Ta,
    actionResultTitle: Ea,
    actionResultControls: Da,
    actionResultContent: Ba,
    collapseButton: Ma,
  },
  Ra = de(() => {
    const [t, s] = n.useState(null),
      [r, u] = n.useState(null),
      [_, h] = n.useState(null),
      [i, k] = n.useState(!1),
      [R, D] = n.useState(null),
      [E, U] = n.useState(null),
      [z, $] = n.useState(!1),
      [B, b] = n.useState(null),
      [m, L] = n.useState(!1),
      [w, V] = n.useState(!1),
      [J, A] = n.useState(200);
    n.useEffect(() => {
      T();
    }, []);
    const T = async () => {
        (k(!0), D(null));
        try {
          const O = await Q.database.getAllKeyValues(),
            P = {};
          for (const [se, Z] of O)
            try {
              P[se] = Z ? JSON.parse(Z) : null;
            } catch (le) {
              console.error(`Error parsing key value, key: ${se}`, le);
            }
          const X = await Q.database.debug_getDistinctAccountIDs();
          u(X);
          const oe = await Q.database.debug_roomsWithoutBridgeEvents();
          (h(oe),
            s({ ...P, distinctAccountIDs: X, roomsWithoutBridgeEvents: oe }));
        } catch (O) {
          (console.error("Error loading data:", O),
            D(O.message || "Failed to load data"));
        } finally {
          k(!1);
        }
      },
      x = async (O, P) => {
        ($(!1), k(!0), D(null), U(null));
        try {
          const X = await O();
          (U({ action: P, timestamp: new Date().toISOString(), result: X }),
            L(!0));
        } catch (X) {
          (console.error("Error executing action:", X),
            D(X.message || "Failed to execute action"));
        } finally {
          k(!1);
        }
      },
      M = async () => {
        ($(!1), k(!0), D(null));
        try {
          const O = await Q.bapi.debug_fetchAllAccountData();
          (b(O), s((P) => (P ? { ...P, allAccountData: O } : null)));
        } catch (O) {
          (console.error("Error fetching account data:", O),
            D(O.message || "Failed to fetch account data"));
        } finally {
          k(!1);
        }
      },
      H = () => {
        $(!z);
      },
      K = () => {
        (U(null), L(!1));
      },
      F = () => {
        V(!w);
      };
    return i && !t
      ? e.jsxs("div", {
          className: I.dataExplorer,
          children: [
            e.jsx("div", {
              className: `${I.header} app-region-drag`,
              children: e.jsx("div", {
                className: I.headerContent,
                children: e.jsxs("div", {
                  className: I.headerInfo,
                  children: [
                    e.jsx("span", { className: I.headerIcon, children: "🔍" }),
                    e.jsx("div", {
                      className: I.headerText,
                      children: e.jsx("h1", {
                        className: I.headerTitle,
                        children: "Data Explorer",
                      }),
                    }),
                  ],
                }),
              }),
            }),
            e.jsx("div", {
              className: I.contentContainer,
              children: e.jsxs("div", {
                className: I.loadingState,
                children: [
                  e.jsx("div", { className: I.loadingSpinner }),
                  e.jsx("span", { children: "Loading data..." }),
                ],
              }),
            }),
          ],
        })
      : e.jsxs("div", {
          className: I.dataExplorer,
          children: [
            e.jsx("div", {
              className: `${I.header} app-region-drag`,
              children: e.jsxs("div", {
                className: I.headerContent,
                children: [
                  e.jsxs("div", {
                    className: I.headerInfo,
                    children: [
                      e.jsx("span", {
                        className: I.headerIcon,
                        children: "🔍",
                      }),
                      e.jsx("div", {
                        className: I.headerText,
                        children: e.jsx("h1", {
                          className: I.headerTitle,
                          children: "Data Explorer",
                        }),
                      }),
                    ],
                  }),
                  e.jsxs("div", {
                    className: I.headerActions,
                    children: [
                      e.jsx("button", {
                        className: I.actionButton,
                        onClick: M,
                        disabled: i || !!B,
                        title: "Fetch all account data from the server",
                        children: "Fetch Account Data",
                      }),
                      e.jsx("button", {
                        className: I.actionButton,
                        onClick: T,
                        disabled: i,
                        title: "Refresh all data",
                        children: "Refresh",
                      }),
                      e.jsx("button", {
                        className: `${I.actionButton} ${I.primaryButton}`,
                        onClick: H,
                        disabled: i,
                        title: "Show available actions",
                        children: "Actions",
                      }),
                      z &&
                        e.jsxs("div", {
                          className: I.dropdownMenu,
                          children: [
                            e.jsx("button", {
                              className: I.dropdownItem,
                              onClick: () =>
                                x(
                                  () =>
                                    Q.bapi.debug_refetchRoomStatesForRoomsWithoutBridgeEvents(),
                                  "Refetch Room States",
                                ),
                              children:
                                "Refetch Room States for Rooms Without Bridge Events",
                            }),
                            e.jsx("button", {
                              className: I.dropdownItem,
                              onClick: () =>
                                x(
                                  () => Q.bapi.debug_updateLocalBridgeStates(),
                                  "Update Local Bridge States",
                                ),
                              children: "Update Local Bridge States",
                            }),
                            e.jsx("button", {
                              className: I.dropdownItem,
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
            R &&
              e.jsxs("div", {
                className: I.errorBar,
                children: [
                  e.jsx("span", { className: I.errorIcon, children: "⚠️" }),
                  e.jsx("span", { className: I.errorMessage, children: R }),
                ],
              }),
            i &&
              e.jsx("div", {
                className: I.statusBar,
                children: e.jsxs("div", {
                  className: I.statusLoading,
                  children: [
                    e.jsx("div", { className: I.loadingSpinner }),
                    e.jsx("span", { children: "Loading..." }),
                  ],
                }),
              }),
            e.jsx("div", {
              className: I.contentContainer,
              style: { height: m && !w ? `calc(100% - ${J}px)` : "100%" },
              children: t
                ? e.jsx(ie, {
                    data: { ...t, state: Q.beeperClientStore.state },
                    initialExpandLevel: 0,
                  })
                : e.jsxs("div", {
                    className: I.emptyState,
                    children: [
                      e.jsx("span", { className: I.emoji, children: "📄" }),
                      e.jsx("h2", { children: "No data available" }),
                      e.jsx("p", { children: "Try refreshing to load data" }),
                    ],
                  }),
            }),
            m &&
              e.jsxs("div", {
                className: I.actionResult,
                style: { height: w ? "auto" : `${J}px` },
                children: [
                  e.jsxs("div", {
                    className: I.actionResultHeader,
                    onClick: F,
                    children: [
                      e.jsxs("h3", {
                        className: I.actionResultTitle,
                        children: ["Action Result: ", E?.action],
                      }),
                      e.jsxs("div", {
                        className: I.actionResultControls,
                        children: [
                          e.jsx("button", {
                            className: I.collapseButton,
                            onClick: (O) => {
                              (O.stopPropagation(), K());
                            },
                            title: "Clear result",
                            children: "Clear",
                          }),
                          e.jsx("span", {
                            className: I.collapseButton,
                            title: w ? "Expand" : "Collapse",
                            children: w ? e.jsx(De, {}) : e.jsx(Be, {}),
                          }),
                        ],
                      }),
                    ],
                  }),
                  !w &&
                    e.jsx("div", {
                      className: I.actionResultContent,
                      children: e.jsx(ie, {
                        data: E,
                        initialExpandLevel: "all",
                      }),
                    }),
                ],
              }),
          ],
        });
  }),
  Aa = "_topContainer_181gv_1",
  La = "_container_181gv_16",
  Fa = "_card_181gv_22",
  Pa = "_form_181gv_39",
  qa = "_inputGroup_181gv_45",
  Ha = "_label_181gv_48",
  Oa = "_input_181gv_45",
  za = "_textarea_181gv_54",
  Va = "_suggestions_181gv_97",
  Wa = "_suggestion_181gv_97",
  Ka = "_checkboxGroup_181gv_121",
  Ja = "_checkbox_181gv_121",
  Ga = "_button_181gv_137",
  Ua = "_message_181gv_155",
  G = {
    topContainer: Aa,
    container: La,
    card: Fa,
    form: Pa,
    inputGroup: qa,
    label: Ha,
    input: Oa,
    textarea: za,
    suggestions: Va,
    suggestion: Wa,
    checkboxGroup: Ka,
    checkbox: Ja,
    button: Ga,
    message: Ua,
  },
  Qa = "_markdownViewer_1ow3k_1",
  Xa = "_markdownContent_1ow3k_4",
  Ya = "_copyButton_1ow3k_14",
  fe = { markdownViewer: Qa, markdownContent: Xa, copyButton: Ya },
  Za = ({ data: t }) => {
    const [s, r] = n.useState(!1),
      u = typeof t == "object" ? JSON.stringify(t, null, 2) : t,
      _ = () => {
        (me(u), r(!0), setTimeout(() => r(!1), 2e3));
      };
    return e.jsxs("div", {
      className: fe.markdownViewer,
      "data-sentry-component": "CopyableDataViewer",
      "data-sentry-source-file": "CopyableDataViewer.tsx",
      children: [
        e.jsx("button", {
          type: "button",
          className: fe.copyButton,
          onClick: _,
          children: s ? "Copied!" : "Copy",
        }),
        e.jsx("div", {
          className: fe.markdownContent,
          children: e.jsx(Me, {
            lang: "json",
            "data-sentry-element": "Code",
            "data-sentry-source-file": "CopyableDataViewer.tsx",
            children: u,
          }),
        }),
      ],
    });
  },
  en = Le.version,
  tn = [
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
  sn = de(() => {
    const [t, s] = n.useState(""),
      [r, u] = n.useState(""),
      [_, h] = n.useState(""),
      [i, k] = n.useState(!0),
      [R, D] = n.useState({ type: "", content: "" }),
      [E, U] = n.useState([]),
      [z, $] = n.useState(() => `$adhoc.${Date.now()}`),
      B = n.useRef(null),
      b = n.useMemo(() => {
        try {
          const A = JSON.parse(r);
          if (typeof A != "object")
            throw new Error("Event content must be a valid JSON object");
          i &&
            ((A["com.beeper.origin_client_ts"] = Date.now()),
            (A["com.beeper.origin_client_type"] = "desktop"),
            (A["com.beeper.origin_client_version"] = en));
          const T = { type: t, content: A };
          return (_?.length > 0 && (T.room_id = _), T);
        } catch {
          return null;
        }
      }, [r, i, t, _]);
    n.useEffect(() => {
      (B.current &&
        ((B.current.style.height = "auto"),
        (B.current.style.height = B.current.scrollHeight + "px")),
        $(`$adhoc.${Date.now()}`));
    }, [r]);
    const m = (A) => {
        const T = A.target.value;
        if ((s(T), T.startsWith("m.room") || h(""), T)) {
          const x = tn.filter((M) => M.toLowerCase().includes(T.toLowerCase()));
          U(x);
        } else U([]);
      },
      L = (A) => {
        (s(A), U([]));
      },
      w = (A) => {
        const T = A.target.value;
        u(T);
        try {
          const x = JSON.parse(T),
            M = JSON.stringify(x, null, 2);
          M !== T && u(M);
        } catch {}
      },
      V = (A) => {
        try {
          return (JSON.parse(A), !0);
        } catch {
          return !1;
        }
      },
      J = async (A) => {
        if ((A.preventDefault(), D({ type: "", content: "" }), !V(r))) {
          D({ type: "error", content: "Invalid JSON in event content" });
          return;
        }
        if (t.startsWith("m.room") && !_) {
          D({ type: "error", content: "Room ID is required for room events" });
          return;
        }
        try {
          const T = await Q.bapi.debug_sendEvent(JSON.stringify(b), z);
          D({
            type: "success",
            content: `Event sent successfully: ${JSON.stringify(T, null, 2)}`,
          });
        } catch (T) {
          D({ type: "error", content: `Error sending event: ${T}` });
        }
      };
    return e.jsxs("div", {
      className: `${G.dbExplorer}`,
      children: [
        e.jsx("div", {
          className: `${G.topContainer} app-region-drag`,
          children: e.jsx("div", {
            className: G.headerContainer,
            children: e.jsx("h1", { children: "Send a custom event" }),
          }),
        }),
        e.jsx("div", {
          className: G.container,
          children: e.jsxs("div", {
            className: G.card,
            children: [
              e.jsxs("form", {
                onSubmit: J,
                className: G.form,
                children: [
                  e.jsxs("div", {
                    className: G.inputGroup,
                    children: [
                      e.jsx("input", {
                        id: "event-type",
                        name: "event-type",
                        type: "text",
                        className: G.input,
                        placeholder: " ",
                        value: t,
                        onChange: m,
                        required: !0,
                      }),
                      e.jsx("label", {
                        htmlFor: "event-type",
                        className: G.label,
                        children: "Event Type",
                      }),
                      E.length > 0 &&
                        e.jsx("ul", {
                          className: G.suggestions,
                          children: E.map((A, T) =>
                            e.jsx(
                              "li",
                              {
                                className: G.suggestion,
                                onClick: () => L(A),
                                children: A,
                              },
                              T,
                            ),
                          ),
                        }),
                    ],
                  }),
                  e.jsxs("div", {
                    className: G.inputGroup,
                    children: [
                      e.jsx("textarea", {
                        id: "event-content",
                        name: "event-content",
                        ref: B,
                        className: G.textarea,
                        placeholder: " ",
                        value: r,
                        onChange: w,
                        rows: 5,
                        required: !0,
                      }),
                      e.jsx("label", {
                        htmlFor: "event-content",
                        className: G.label,
                        children: "Event Content (JSON)",
                      }),
                    ],
                  }),
                  e.jsxs("div", {
                    className: `${G.inputGroup} ${t.startsWith("m.room") ? "" : "optional"}`,
                    children: [
                      e.jsx("input", {
                        id: "room-id",
                        name: "room-id",
                        type: "text",
                        className: G.input,
                        placeholder: " ",
                        value: _,
                        onChange: (A) => h(A.target.value),
                        required: t.startsWith("m.room"),
                      }),
                      e.jsx("label", {
                        htmlFor: "room-id",
                        className: G.label,
                        children: "Room ID",
                      }),
                    ],
                  }),
                  e.jsxs("div", {
                    className: G.inputGroup,
                    children: [
                      e.jsx("input", {
                        id: "transaction-id",
                        name: "transaction-id",
                        type: "text",
                        className: G.input,
                        placeholder: " ",
                        value: z,
                        onChange: (A) => $(A.target.value),
                        required: !0,
                      }),
                      e.jsx("label", {
                        htmlFor: "transaction-id",
                        className: G.label,
                        children: "Transaction ID",
                      }),
                    ],
                  }),
                  e.jsxs("div", {
                    className: G.checkboxGroup,
                    children: [
                      e.jsx("input", {
                        id: "add-checkpoint",
                        name: "add-checkpoint",
                        type: "checkbox",
                        className: G.checkbox,
                        checked: i,
                        onChange: (A) => k(A.target.checked),
                      }),
                      e.jsx("label", {
                        htmlFor: "add-checkpoint",
                        children: "Add checkpoint data",
                      }),
                    ],
                  }),
                  e.jsx("button", {
                    type: "submit",
                    className: G.button,
                    children: "Send Event",
                  }),
                ],
              }),
              R.content &&
                e.jsx("div", {
                  className: `${G.message} ${R.type}`,
                  children: R.content,
                }),
              b && e.jsx(Za, { data: b }),
            ],
          }),
        }),
      ],
    });
  }),
  an = "_promptTester_q66am_1",
  nn = "_header_q66am_11",
  on = "_headerContent_q66am_17",
  rn = "_headerMeta_q66am_32",
  cn = "_messageMeta_q66am_33",
  ln = "_messageEditorMeta_q66am_34",
  dn = "_headerActions_q66am_43",
  un = "_content_q66am_49",
  mn = "_inputPane_q66am_56",
  hn = "_outputPane_q66am_57",
  pn = "_section_q66am_73",
  _n = "_messagesSection_q66am_80",
  gn = "_sectionHeader_q66am_84",
  xn = "_sectionHeaderText_q66am_98",
  fn = "_sectionHint_q66am_104",
  yn = "_promptInput_q66am_111",
  jn = "_messageInput_q66am_112",
  vn = "_textInput_q66am_113",
  bn = "_messagesList_q66am_146",
  Nn = "_resultsList_q66am_147",
  wn = "_messageEditor_q66am_34",
  Sn = "_messageResult_q66am_155",
  Cn = "_factCard_q66am_156",
  kn = "_stageCard_q66am_157",
  In = "_persistCard_q66am_158",
  $n = "_targetMessageEditor_q66am_173",
  Tn = "_contextMessageEditor_q66am_179",
  En = "_messageRunHeader_q66am_184",
  Dn = "_messageRunTitle_q66am_192",
  Bn = "_messageRunSubtitle_q66am_200",
  Mn = "_messageEditorHeader_q66am_207",
  Rn = "_targetLock_q66am_214",
  An = "_primaryButton_q66am_235",
  Ln = "_secondaryButton_q66am_236",
  Fn = "_dangerButton_q66am_237",
  Pn = "_errorBar_q66am_276",
  qn = "_warningBar_q66am_277",
  Hn = "_emptyState_q66am_294",
  On = "_emptyResult_q66am_295",
  zn = "_emptyStage_q66am_296",
  Vn = "_timeline_q66am_317",
  Wn = "_timelineStage_q66am_323",
  Kn = "_timelineRail_q66am_329",
  Jn = "_timelineDot_q66am_335",
  Gn = "_timelineDot_default_q66am_344",
  Un = "_timelineDot_good_q66am_348",
  Qn = "_timelineDot_bad_q66am_353",
  Xn = "_timelineDot_muted_q66am_358",
  Yn = "_timelineDot_warn_q66am_363",
  Zn = "_timelineLine_q66am_368",
  eo = "_stageHeader_q66am_385",
  to = "_stageSummary_q66am_401",
  so = "_stageBody_q66am_408",
  ao = "_messageResultHeader_q66am_412",
  no = "_factHeader_q66am_413",
  oo = "_messageText_q66am_427",
  ro = "_gates_q66am_439",
  co = "_gateBadge_q66am_446",
  io = "_gate_pass_q66am_454",
  lo = "_gate_fail_q66am_458",
  uo = "_gate_not_evaluated_q66am_462",
  mo = "_gateLabel_q66am_466",
  ho = "_gateDetail_q66am_472",
  po = "_resultSummary_q66am_480",
  _o = "_factMeta_q66am_481",
  go = "_jsonGrid_q66am_482",
  xo = "_badge_q66am_489",
  fo = "_badge_good_q66am_504",
  yo = "_badge_bad_q66am_510",
  jo = "_badge_muted_q66am_516",
  vo = "_badge_warn_q66am_522",
  bo = "_factsList_q66am_528",
  No = "_templateReason_q66am_538",
  wo = "_templateFields_q66am_545",
  So = "_templateFieldEmpty_q66am_569",
  Co = "_templateFieldSource_q66am_574",
  ko = "_splitStage_q66am_581",
  Io = "_contextList_q66am_594",
  $o = "_contextMessage_q66am_179",
  To = "_contextTarget_q66am_606",
  Eo = "_contextTargetBanner_q66am_613",
  Do = "_contextMessageHeader_q66am_637",
  Bo = "_contextMessageText_q66am_650",
  Mo = "_factType_q66am_659",
  Ro = "_factBody_q66am_672",
  Ao = "_factSubject_q66am_676",
  Lo = "_factContent_q66am_683",
  Fo = "_factValue_q66am_691",
  Po = "_writePreview_q66am_692",
  qo = "_enrichmentUrl_q66am_693",
  Ho = "_sourceQuote_q66am_700",
  Oo = "_enrichment_q66am_693",
  zo = "_enrichmentImage_q66am_721",
  Vo = "_enrichmentContent_q66am_730",
  Wo = "_enrichmentKind_q66am_734",
  Ko = "_enrichmentTitle_q66am_740",
  Jo = "_enrichmentSubtitle_q66am_741",
  Go = "_enrichmentDescription_q66am_742",
  Uo = "_persistSummary_q66am_779",
  Qo = "_visibleJson_q66am_803",
  Xo = "_jsonDetails_q66am_817",
  a = {
    promptTester: an,
    header: nn,
    headerContent: on,
    headerMeta: rn,
    messageMeta: cn,
    messageEditorMeta: ln,
    headerActions: dn,
    content: un,
    inputPane: mn,
    outputPane: hn,
    section: pn,
    messagesSection: _n,
    sectionHeader: gn,
    sectionHeaderText: xn,
    sectionHint: fn,
    promptInput: yn,
    messageInput: jn,
    textInput: vn,
    messagesList: bn,
    resultsList: Nn,
    messageEditor: wn,
    messageResult: Sn,
    factCard: Cn,
    stageCard: kn,
    persistCard: In,
    targetMessageEditor: $n,
    contextMessageEditor: Tn,
    messageRunHeader: En,
    messageRunTitle: Dn,
    messageRunSubtitle: Bn,
    messageEditorHeader: Mn,
    targetLock: Rn,
    primaryButton: An,
    secondaryButton: Ln,
    dangerButton: Fn,
    errorBar: Pn,
    warningBar: qn,
    emptyState: Hn,
    emptyResult: On,
    emptyStage: zn,
    timeline: Vn,
    timelineStage: Wn,
    timelineRail: Kn,
    timelineDot: Jn,
    timelineDot_default: Gn,
    timelineDot_good: Un,
    timelineDot_bad: Qn,
    timelineDot_muted: Xn,
    timelineDot_warn: Yn,
    timelineLine: Zn,
    stageHeader: eo,
    stageSummary: to,
    stageBody: so,
    messageResultHeader: ao,
    factHeader: no,
    messageText: oo,
    gates: ro,
    gateBadge: co,
    gate_pass: io,
    gate_fail: lo,
    gate_not_evaluated: uo,
    gateLabel: mo,
    gateDetail: ho,
    resultSummary: po,
    factMeta: _o,
    jsonGrid: go,
    badge: xo,
    badge_good: fo,
    badge_bad: yo,
    badge_muted: jo,
    badge_warn: vo,
    factsList: bo,
    templateReason: No,
    templateFields: wo,
    templateFieldEmpty: So,
    templateFieldSource: Co,
    splitStage: ko,
    contextList: Io,
    contextMessage: $o,
    contextTarget: To,
    contextTargetBanner: Eo,
    contextMessageHeader: Do,
    contextMessageText: Bo,
    factType: Mo,
    factBody: Ro,
    factSubject: Ao,
    factContent: Lo,
    factValue: Fo,
    writePreview: Po,
    enrichmentUrl: qo,
    sourceQuote: Ho,
    enrichment: Oo,
    enrichmentImage: zo,
    enrichmentContent: Vo,
    enrichmentKind: Wo,
    enrichmentTitle: Ko,
    enrichmentSubtitle: Jo,
    enrichmentDescription: Go,
    persistSummary: Uo,
    visibleJson: Qo,
    jsonDetails: Xo,
  },
  Ne = Date.now(),
  Yo = () => `${Date.now()}-${Math.random().toString(36).slice(2)}`,
  we = (t = {}) => ({
    localID: Yo(),
    roomID: "!debug-room:beeper.local",
    accountID: "debug_account",
    messageEventID: "$debug-message-1",
    senderContactID: "@sender:beeper.local",
    senderDisplayName: "Alice",
    timestamp: Date.now(),
    text: "You should watch Severance, the second season is excellent.",
    ...t,
  }),
  Zo = () => {
    const t = we();
    return { targetLocalID: t.localID, messages: [t] };
  },
  er = (t) => {
    const s = new Date(t),
      r = s.getTimezoneOffset() * 60 * 1e3;
    return new Date(s.getTime() - r).toISOString().slice(0, 16);
  },
  tr = (t) => {
    const s = new Date(t).getTime();
    return Number.isFinite(s) ? s : Ne;
  },
  sr = (t, s) => ({
    id: s + 1,
    hsOrder: s + 1,
    roomID: t.roomID || "!debug-room:beeper.local",
    accountID: t.accountID || "debug_account",
    messageEventID: t.messageEventID || `$debug-message-${s + 1}`,
    senderContactID: t.senderContactID || "@sender:beeper.local",
    senderDisplayName: t.senderDisplayName || null,
    timestamp: t.timestamp || Ne,
    text: t.text,
  }),
  ar = (t) => t.map((s, r) => sr(s, r)),
  Se = (t) => JSON.stringify(t, null, 2),
  Ce = (t) =>
    Number.isFinite(t) ? new Date(t).toLocaleString() : "Invalid time",
  nr = (t) => {
    if (!t.enrichmentData) return null;
    try {
      return JSON.parse(t.enrichmentData);
    } catch {
      return null;
    }
  },
  or = (t) => {
    if (!t) return null;
    try {
      return JSON.parse(t);
    } catch {
      return null;
    }
  },
  rr = new Set(["book", "show", "movie", "music", "song", "album", "artist"]),
  cr = new Set(["actor", "director", "writer", "musician"]);
function ve(t) {
  return t
    ? `https://www.google.com/maps/search/?api=1&query=${encodeURIComponent(t)}`
    : null;
}
function ir(t) {
  const s = or(t.enrichmentData),
    r = t.category ?? "";
  if (t.factType === "recommendation" && rr.has(r) && s?.kind === "media")
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
  if (t.factType === "recommendation" && cr.has(r) && s?.kind === "person")
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
    const h = s.url ?? ve(s.description ?? t.subject);
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
    const h = t.valueType === "venue" ? ve(t.value) : null;
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
  const u = t.category ? `/${t.category}` : "",
    _ = [
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
    reason: `${t.factType}${u} (fallback)`,
    fields: _.filter((h) => h.value !== null && h.value !== ""),
  };
}
const Y = ({ children: t, tone: s = "default" }) =>
    e.jsx("span", {
      className: `${a.badge} ${a[`badge_${s}`]}`,
      "data-sentry-component": "Badge",
      "data-sentry-source-file": "FactsPromptTester.tsx",
      children: t,
    }),
  lr = ({ title: t, data: s }) =>
    e.jsxs("details", {
      className: a.jsonDetails,
      "data-sentry-component": "JsonDetails",
      "data-sentry-source-file": "FactsPromptTester.tsx",
      children: [
        e.jsx("summary", { children: t }),
        e.jsx("pre", { children: Se(s) }),
      ],
    }),
  dr = ({ gate: t }) => {
    const s =
      t.status === "pass" ? "good" : t.status === "fail" ? "bad" : "muted";
    return e.jsxs("div", {
      className: `${a.gateBadge} ${a[`gate_${t.status}`]}`,
      "data-sentry-component": "GateBadge",
      "data-sentry-source-file": "FactsPromptTester.tsx",
      children: [
        e.jsx("div", { className: a.gateLabel, children: t.label }),
        e.jsx("div", { className: a.gateDetail, children: t.detail }),
        e.jsx(Y, {
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
    summary: u,
    children: _,
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
                    u &&
                      e.jsx("div", { className: a.stageSummary, children: u }),
                  ],
                }),
                e.jsx(Y, {
                  tone: r,
                  "data-sentry-element": "Badge",
                  "data-sentry-source-file": "FactsPromptTester.tsx",
                  children: s,
                }),
              ],
            }),
            e.jsx("div", { className: a.stageBody, children: _ }),
          ],
        }),
      ],
    }),
  ce = ({ children: t }) =>
    e.jsx("div", {
      className: a.emptyStage,
      "data-sentry-component": "EmptyStage",
      "data-sentry-source-file": "FactsPromptTester.tsx",
      children: t,
    }),
  ur = ({ context: t }) =>
    e.jsx("div", {
      className: a.contextList,
      "data-sentry-component": "ContextMessageList",
      "data-sentry-source-file": "FactsPromptTester.tsx",
      children: t.map((s, r) => {
        const u = s.relativeIndex === 0,
          _ = s.relativeIndex > 0 ? `+${s.relativeIndex}` : s.relativeIndex;
        return e.jsxs(
          "article",
          {
            className: `${a.contextMessage} ${u ? a.contextTarget : ""}`,
            children: [
              u &&
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
                  e.jsx(Y, {
                    tone: u ? "good" : "muted",
                    children: u
                      ? "extract facts from this message"
                      : `context ${_}`,
                  }),
                  e.jsx("span", { children: s.senderDisplayName || s.sender }),
                  e.jsx("span", { children: Ce(s.sentAt) }),
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
  mr = ({ fact: t, index: s }) => {
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
            e.jsx(Y, {
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
            t.datePrecision && e.jsx(Y, { children: t.datePrecision }),
            t.valueType && e.jsx(Y, { children: t.valueType }),
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
    statusTone: u = "default",
    footer: _,
  }) => {
    const h = s ?? t,
      i = nr(h),
      k = [
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
            r && e.jsx(Y, { tone: u, children: r }),
          ],
        }),
        e.jsxs("div", {
          className: a.factBody,
          children: [
            h.subject &&
              e.jsx("div", { className: a.factSubject, children: h.subject }),
            e.jsx("div", { className: a.factContent, children: h.content }),
            k.length > 0 &&
              e.jsx("div", { className: a.factValue, children: k.join(" | ") }),
          ],
        }),
        e.jsxs("div", {
          className: a.factMeta,
          children: [
            h.valueType && e.jsx(Y, { children: h.valueType }),
            h.datePrecision && e.jsx(Y, { children: h.datePrecision }),
          ],
        }),
        e.jsx("blockquote", {
          className: a.sourceQuote,
          children: h.sourceQuote,
        }),
        i &&
          e.jsxs("div", {
            className: a.enrichment,
            children: [
              i.imageUrl &&
                e.jsx("img", {
                  src: i.imageUrl,
                  alt: "",
                  className: a.enrichmentImage,
                }),
              e.jsxs("div", {
                className: a.enrichmentContent,
                children: [
                  e.jsx("div", {
                    className: a.enrichmentKind,
                    children: i.kind,
                  }),
                  i.title &&
                    e.jsx("div", {
                      className: a.enrichmentTitle,
                      children: i.title,
                    }),
                  i.subtitle &&
                    e.jsx("div", {
                      className: a.enrichmentSubtitle,
                      children: i.subtitle,
                    }),
                  i.description &&
                    e.jsx("div", {
                      className: a.enrichmentDescription,
                      children: i.description,
                    }),
                  i.url &&
                    e.jsx("div", {
                      className: a.enrichmentUrl,
                      children: i.url,
                    }),
                ],
              }),
            ],
          }),
        _ && e.jsx("div", { className: a.writePreview, children: _ }),
      ],
    });
  },
  hr = ({ fact: t, index: s }) =>
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
            e.jsx(Y, {
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
  pr = ({ fact: t, index: s }) => {
    const r = ir(t);
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
            e.jsx(Y, {
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
            children: r.fields.map((u) =>
              e.jsxs(
                "tr",
                {
                  children: [
                    e.jsx("th", { children: u.label }),
                    e.jsxs("td", {
                      children: [
                        u.value
                          ? e.jsx("span", { children: u.value })
                          : e.jsx("em", {
                              className: a.templateFieldEmpty,
                              children: "—",
                            }),
                        u.factField &&
                          e.jsxs("div", {
                            className: a.templateFieldSource,
                            children: [u.source, " · ", u.factField],
                          }),
                      ],
                    }),
                  ],
                },
                u.label,
              ),
            ),
          }),
        }),
      ],
    });
  },
  _r = ({ trace: t }) => {
    const s = new Set(t.honeycomb.map((i) => i.factKey)),
      r = t.normalized.filter((i) => !s.has(i.factKey)),
      u = new Map(t.enriched.map((i) => [i.factKey, i])),
      _ = t.raw?.facts.length ?? 0,
      h = t.enriched.filter((i) => i.enrichmentData).length;
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
                    Ce(t.message.timestamp),
                  ],
                }),
              ],
            }),
            e.jsx(Y, {
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
                children: t.gates.map((i) => e.jsx(dr, { gate: i }, i.key)),
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
                  ? e.jsx(ur, { context: t.context })
                  : e.jsx(ce, { children: "No context messages available." }),
            }),
            e.jsx(re, {
              title: "LLM Output",
              status: t.llmInput ? `${_} facts` : "not run",
              tone: t.llmInput ? (_ > 0 ? "good" : "warn") : "muted",
              summary: t.llmInput
                ? "Raw structured facts returned by the model."
                : "Stopped before the model because a gate failed.",
              "data-sentry-element": "TimelineStage",
              "data-sentry-source-file": "FactsPromptTester.tsx",
              children: t.raw?.facts.length
                ? e.jsx("div", {
                    className: a.factsList,
                    children: t.raw.facts.map((i, k) =>
                      e.jsx(
                        mr,
                        { fact: i, index: k },
                        `${i.factType}-${i.category}-${k}`,
                      ),
                    ),
                  })
                : e.jsx(ce, {
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
                  : _ > 0
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
                      children: t.normalized.map((i) =>
                        e.jsx(
                          ge,
                          { fact: i, statusLabel: "normalized" },
                          i.factKey,
                        ),
                      ),
                    })
                  : e.jsx(ce, {
                      children:
                        _ > 0
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
                            children: t.honeycomb.map((i) =>
                              e.jsx(
                                ge,
                                {
                                  fact: i,
                                  statusLabel: "Honeycomb",
                                  statusTone: "good",
                                },
                                i.factKey,
                              ),
                            ),
                          })
                        : e.jsx(ce, { children: "No Honeycomb facts kept." }),
                    ],
                  }),
                  e.jsxs("div", {
                    children: [
                      e.jsx("h4", { children: "Filtered" }),
                      r.length > 0
                        ? e.jsx("div", {
                            className: a.factsList,
                            children: r.map((i) =>
                              e.jsx(
                                ge,
                                {
                                  fact: i,
                                  statusLabel: "non-Honeycomb",
                                  statusTone: "warn",
                                },
                                i.factKey,
                              ),
                            ),
                          })
                        : e.jsx(ce, {
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
                      children: t.enriched.map((i) =>
                        e.jsx(
                          ge,
                          {
                            fact: i,
                            enrichedFact: u.get(i.factKey),
                            statusLabel: i.enrichmentData
                              ? "enriched"
                              : "no metadata",
                            statusTone: i.enrichmentData ? "good" : "muted",
                          },
                          i.factKey,
                        ),
                      ),
                    })
                  : e.jsx(ce, {
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
                      children: t.wouldPersist.map((i, k) =>
                        e.jsx(hr, { fact: i, index: k }, i.factKey),
                      ),
                    })
                  : e.jsx(ce, {
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
                      children: t.wouldPersist.map((i, k) =>
                        e.jsx(pr, { fact: i, index: k }, i.factKey),
                      ),
                    })
                  : e.jsx(ce, { children: "No facts to render." }),
            }),
          ],
        }),
      ],
    });
  },
  gr = de(() => {
    const [t, s] = n.useState(""),
      [r, u] = n.useState(""),
      [_, h] = n.useState(Zo),
      [i, k] = n.useState(null),
      [R, D] = n.useState(!1),
      [E, U] = n.useState(!1),
      [z, $] = n.useState(null),
      { messages: B, targetLocalID: b } = _,
      m = B.findIndex((x) => x.localID === b),
      L = n.useCallback(async () => {
        (D(!0), $(null));
        try {
          const x = await Q.bapi.debug_getMessageFactsExtractionDefaults();
          (s(x.prompt), u(x.model));
        } catch (x) {
          (console.error("Failed to load message facts defaults:", x),
            $(x.message || "Failed to load message facts defaults"));
        } finally {
          D(!1);
        }
      }, []);
    n.useEffect(() => {
      L();
    }, [L]);
    const w = n.useCallback((x, M) => {
        (h((H) => ({
          ...H,
          messages: H.messages.map((K) =>
            K.localID === x ? { ...K, ...M } : K,
          ),
        })),
          k(null));
      }, []),
      V = n.useCallback((x) => {
        (h((M) => {
          const H = M.messages.findIndex(
              (oe) => oe.localID === M.targetLocalID,
            ),
            K = H >= 0 ? H : 0,
            F = M.messages[K],
            O = x === "above" ? K : K + 1,
            P = x === "above" ? -6e4 : 6e4,
            X = we({
              roomID: F.roomID,
              accountID: F.accountID,
              senderContactID: F.senderContactID,
              senderDisplayName: F.senderDisplayName,
              timestamp: F.timestamp + P,
              messageEventID: `$debug-message-${M.messages.length + 1}`,
              text: "",
            });
          return {
            ...M,
            messages: [...M.messages.slice(0, O), X, ...M.messages.slice(O)],
          };
        }),
          k(null));
      }, []),
      J = n.useCallback((x) => {
        (h((M) =>
          x === M.targetLocalID
            ? M
            : { ...M, messages: M.messages.filter((H) => H.localID !== x) },
        ),
          k(null));
      }, []),
      A = n.useCallback(async () => {
        const x = B.findIndex((P) => P.localID === b),
          M = x >= 0 ? B[x] : null;
        if (!M?.text.trim()) {
          $("Target message needs text");
          return;
        }
        const H = B.slice(0, x).filter((P) => P.text.trim()),
          K = B.slice(x + 1).filter((P) => P.text.trim()),
          F = ar([...H, M, ...K]),
          O = F[H.length];
        (U(!0), $(null));
        try {
          const P = await Q.bapi.debug_dryRunMessageFactsExtraction({
            prompt: t,
            model: r || void 0,
            messages: [O],
            targetMessage: O,
            contextBefore: F.slice(0, H.length),
            contextAfter: F.slice(H.length + 1),
          });
          k(P);
        } catch (P) {
          (console.error("Failed to dry-run message facts extraction:", P),
            $(P.message || "Failed to dry-run message facts extraction"));
        } finally {
          U(!1);
        }
      }, [B, r, t, b]),
      T = n.useMemo(() => {
        if (!i) return null;
        const x = i.enriched.filter((M) => M.enrichmentData).length;
        return `${i.honeycomb.length} Honeycomb facts, ${x} enriched, ${i.wouldPersist.length} would write`;
      }, [i]);
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
                            Math.max(0, B.length - 1),
                            " context messages",
                          ],
                        }),
                        T && e.jsx("span", { children: T }),
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
                      onClick: L,
                      disabled: R || E,
                      children: "Defaults",
                    }),
                    e.jsx("button", {
                      type: "button",
                      className: a.primaryButton,
                      onClick: A,
                      disabled: R || E || !t.trim(),
                      children: E ? "Running..." : "Run Flow",
                    }),
                  ],
                }),
              ],
            }),
            z && e.jsx("div", { className: a.errorBar, children: z }),
            i?.warnings.length
              ? e.jsx("div", {
                  className: a.warningBar,
                  children: i.warnings.join(" | "),
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
                          onChange: (x) => u(x.target.value),
                          placeholder: "Model",
                        }),
                      ],
                    }),
                    e.jsx("textarea", {
                      className: a.promptInput,
                      value: t,
                      onChange: (x) => {
                        (s(x.target.value), k(null));
                      },
                      placeholder: R ? "Loading defaults..." : "System prompt",
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
                              onClick: () => V("above"),
                              children: "Add Above",
                            }),
                            e.jsx("button", {
                              type: "button",
                              className: a.secondaryButton,
                              onClick: () => V("below"),
                              children: "Add Below",
                            }),
                          ],
                        }),
                      ],
                    }),
                    e.jsx("div", {
                      className: a.messagesList,
                      children: B.map((x, M) => {
                        const H = M - m,
                          K = x.localID === b,
                          F = K
                            ? "Extraction target"
                            : H < 0
                              ? `Context ${Math.abs(H)} before target`
                              : `Context ${H} after target`,
                          O = K
                            ? "Facts are extracted from this message."
                            : "Sent to the LLM only to help interpret the target.";
                        return e.jsxs(
                          "article",
                          {
                            className: `${a.messageEditor} ${K ? a.targetMessageEditor : a.contextMessageEditor}`,
                            children: [
                              e.jsxs("div", {
                                className: a.messageRunHeader,
                                children: [
                                  e.jsxs("div", {
                                    children: [
                                      e.jsx("div", {
                                        className: a.messageRunTitle,
                                        children: F,
                                      }),
                                      e.jsx("div", {
                                        className: a.messageRunSubtitle,
                                        children: O,
                                      }),
                                    ],
                                  }),
                                  e.jsx(Y, {
                                    tone: K ? "good" : "muted",
                                    children: K ? "target" : "context only",
                                  }),
                                ],
                              }),
                              e.jsxs("div", {
                                className: a.messageEditorHeader,
                                children: [
                                  e.jsx("input", {
                                    className: a.textInput,
                                    value: x.senderContactID,
                                    onChange: (P) =>
                                      w(x.localID, {
                                        senderContactID: P.target.value,
                                      }),
                                    placeholder: "senderContactID",
                                  }),
                                  e.jsx("input", {
                                    className: a.textInput,
                                    value: x.senderDisplayName,
                                    onChange: (P) =>
                                      w(x.localID, {
                                        senderDisplayName: P.target.value,
                                      }),
                                    placeholder: "Display name",
                                  }),
                                  e.jsx("input", {
                                    className: a.textInput,
                                    type: "datetime-local",
                                    value: er(x.timestamp),
                                    onChange: (P) =>
                                      w(x.localID, {
                                        timestamp: tr(P.target.value),
                                      }),
                                  }),
                                  K
                                    ? e.jsx("span", {
                                        className: a.targetLock,
                                        children: "Target",
                                      })
                                    : e.jsx("button", {
                                        type: "button",
                                        className: a.dangerButton,
                                        onClick: () => J(x.localID),
                                        children: "Remove",
                                      }),
                                ],
                              }),
                              e.jsx("textarea", {
                                className: a.messageInput,
                                value: x.text,
                                onChange: (P) =>
                                  w(x.localID, { text: P.target.value }),
                                placeholder: K ? "Target message" : F,
                              }),
                              e.jsxs("div", {
                                className: a.messageEditorMeta,
                                children: [
                                  x.accountID,
                                  " | ",
                                  x.roomID,
                                  " | ",
                                  x.messageEventID,
                                ],
                              }),
                            ],
                          },
                          x.localID,
                        );
                      }),
                    }),
                  ],
                }),
              ],
            }),
            e.jsx("section", {
              className: a.outputPane,
              children: i
                ? e.jsxs("div", {
                    className: a.resultsList,
                    children: [
                      i.messages.map((x) =>
                        e.jsx(
                          _r,
                          { trace: x },
                          `${x.message.messageEventID}-${x.messageIndex}`,
                        ),
                      ),
                      e.jsx(lr, { title: "Full response JSON", data: i }),
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
  Cr = de(({ wss: t, ...s }) => {
    const r = t?.windowType;
    return e.jsx(Re.Provider, {
      value: t,
      children: e.jsx(n.StrictMode, {
        children: e.jsx(Ae, {
          children: e.jsxs("div", {
            className: ra.container,
            children: [
              r === "devtools-room-explorer" && e.jsx(Us, { wss: t }),
              r === "devtools-event-explorer" &&
                e.jsx(na, { wss: t, eventID: s.eventID }),
              r === "devtools-data-explorer" && e.jsx(Ra, {}),
              r === "devtools-facts-prompt-tester" && e.jsx(gr, {}),
              r === "devtools-custom-event" && e.jsx(sn, { wss: t }),
              Fe,
            ],
          }),
        }),
      }),
    });
  });
export { Cr as DebugApp };
//# sourceMappingURL=DebugApp-KgaSQ2i5.js.map
