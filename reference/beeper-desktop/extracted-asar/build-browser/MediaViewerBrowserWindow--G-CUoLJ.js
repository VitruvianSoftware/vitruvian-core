import {
  cT as _,
  de as w,
  b5 as ae,
  cF as s,
  u as oe,
  v as k,
  aO as I,
  br as M,
  aI as L,
  d5 as re,
  w as Y,
  b_ as R,
  T as H,
  cb as K,
  Y as q,
  c$ as U,
  a5 as O,
  c8 as le,
  em as ce,
  dY as X,
  b1 as de,
  ch as he,
  aN as ue,
  G as me,
  eg as pe,
  c6 as fe,
  k as ge,
  aY as ye,
} from "./App-BHgTsVmv.js";
import { y as xe } from "./sentry-common-BNqrY_yc.js";
import {
  a1 as c,
  c as T,
  a5 as Z,
  aN as we,
  cA as y,
  aq as be,
  cX as _e,
  cK as V,
  a2 as S,
  ab as ve,
  y as Ie,
  bY as Me,
  c3 as je,
  aF as Q,
  aM as ke,
  c1 as v,
  n as Te,
  cB as A,
  a6 as x,
  am as D,
} from "./matrix-util-8DbIGEm-.js";
import "./index-Cw3pknxT.js";
import "./index-Ch31Akxs.js";
import "./index-5FBEE1WD.js";
import "./main-process-state-BDOn7dvV.js";
import "./report-dialog-C-g_klPx.js";
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
    var t = new e.Error().stack;
    t &&
      ((e._sentryDebugIds = e._sentryDebugIds || {}),
      (e._sentryDebugIds[t] = "20903b00-8352-420b-9c16-0bab5f836409"),
      (e._sentryDebugIdIdentifier =
        "sentry-dbid-20903b00-8352-420b-9c16-0bab5f836409"));
  } catch {}
})();
const Se = "_mediaViewer_18p94_1",
  Ce = "_titleBar_18p94_11",
  De = "_isMac_18p94_22",
  Ne = "_container_18p94_26",
  Be = "_header_18p94_36",
  Re = "_headerTabs_18p94_50",
  Ve = "_headerControls_18p94_61",
  Ae = "_iconButton_18p94_67",
  Le = "_active_18p94_81",
  Ee = "_searchRow_18p94_86",
  Ke = "_grid_18p94_112",
  $e = "_gridHidden_18p94_117",
  Fe = "_dateHeader_18p94_121",
  Ge = "_tileRow_18p94_139",
  Oe = "_tile_18p94_139",
  Pe = "_selected_18p94_161",
  ze = "_tileMedia_18p94_166",
  We = "_tileSender_18p94_177",
  Ye = "_tileBadge_18p94_196",
  He = "_tileCheck_18p94_214",
  qe = "_checked_18p94_229",
  Ue = "_listRow_18p94_234",
  Xe = "_listRowThumb_18p94_252",
  Ze = "_listRowText_18p94_273",
  Qe = "_listRowMeta_18p94_299",
  Je = "_footer_18p94_312",
  et = "_selectionBar_18p94_327",
  tt = "_selectionActions_18p94_341",
  st = "_selectionButton_18p94_348",
  nt = "_emptyState_18p94_366",
  it = "_filmstrip_18p94_380",
  at = "_filmstripList_18p94_392",
  ot = "_filmstripThumb_18p94_406",
  rt = "_current_18p94_432",
  lt = "_skeletonRow_18p94_436",
  ct = "_skeletonTile_18p94_442",
  o = {
    mediaViewer: Se,
    titleBar: Ce,
    isMac: De,
    container: Ne,
    header: Be,
    headerTabs: Re,
    headerControls: Ve,
    iconButton: Ae,
    active: Le,
    searchRow: Ee,
    grid: Ke,
    gridHidden: $e,
    dateHeader: Fe,
    tileRow: Ge,
    tile: Oe,
    selected: Pe,
    tileMedia: ze,
    tileSender: We,
    tileBadge: Ye,
    tileCheck: He,
    checked: qe,
    listRow: Ue,
    listRowThumb: Xe,
    listRowText: Ze,
    listRowMeta: Qe,
    footer: Je,
    selectionBar: et,
    selectionActions: tt,
    selectionButton: st,
    emptyState: nt,
    filmstrip: it,
    filmstripList: at,
    filmstripThumb: ot,
    current: rt,
    skeletonRow: lt,
    skeletonTile: ct,
  },
  P = ["media", "links", "docs"],
  dt = _(({ store: e }) => {
    const t = w.useContext(ae),
      [i, n] = w.useState(!1),
      [a, l] = w.useState("");
    w.useEffect(() => {
      const h = setTimeout(() => e.setSearchText(a.trim()), 300);
      return () => clearTimeout(h);
    }, [a, e]);
    const d = () => {
        const h = [
          { label: c("Sent By"), isSectionHeading: !0 },
          {
            label: c("All"),
            type: "radio",
            checked: e.sentBy === "all",
            action: () => e.setSentBy("all"),
          },
          {
            label: c("You"),
            type: "radio",
            checked: e.sentBy === "me",
            action: () => e.setSentBy("me"),
          },
          {
            label: c("Others"),
            type: "radio",
            checked: e.sentBy === "others",
            action: () => e.setSentBy("others"),
          },
          L,
          { label: c("Sort by"), isSectionHeading: !0 },
          {
            label: c("Newest"),
            type: "radio",
            checked: e.sort === "newest",
            action: () => e.setSort("newest"),
          },
          {
            label: c("Oldest"),
            type: "radio",
            checked: e.sort === "oldest",
            action: () => e.setSort("oldest"),
          },
        ];
        re(t, h.filter(Boolean), t.threadSelectionMode);
      },
      r = () => {
        (n(!1), l(""), e.setSearchText(""));
      };
    return s.jsxs(s.Fragment, {
      children: [
        s.jsxs("div", {
          className: o.header,
          children: [
            s.jsx("div", {
              className: o.headerTabs,
              children: s.jsx(oe, {
                labels: [c("Media"), c("Links"), c("Docs")],
                selectedIndex: P.indexOf(e.tab),
                onChange: (h) => e.setTab(P[h]),
              }),
            }),
            s.jsxs("div", {
              className: o.headerControls,
              children: [
                s.jsx(k, {
                  content: c("Select"),
                  position: "bottom",
                  children: s.jsx("button", {
                    type: "button",
                    className: M(o.iconButton, { [o.active]: e.selectMode }),
                    "aria-label": c("Select"),
                    onClick: () => e.setSelectMode(!e.selectMode),
                    children: s.jsx(I, { name: "done", width: 18, height: 18 }),
                  }),
                }),
                s.jsx(k, {
                  content: c("Filter"),
                  position: "bottom",
                  children: s.jsx("button", {
                    type: "button",
                    className: o.iconButton,
                    "aria-label": c("Filter"),
                    onClick: d,
                    children: s.jsx(I, { name: "tune", width: 18, height: 18 }),
                  }),
                }),
                s.jsx(k, {
                  content: c("Search"),
                  position: "bottom",
                  children: s.jsx("button", {
                    type: "button",
                    className: M(o.iconButton, { [o.active]: i }),
                    "aria-label": c("Search"),
                    onClick: () => (i ? r() : n(!0)),
                    children: s.jsx(I, {
                      name: "search",
                      width: 18,
                      height: 18,
                    }),
                  }),
                }),
              ],
            }),
          ],
        }),
        i &&
          s.jsxs("div", {
            className: o.searchRow,
            children: [
              s.jsx(I, { name: "search", width: 16, height: 16 }),
              s.jsx("input", {
                autoFocus: !0,
                value: a,
                placeholder: c("Search by caption"),
                onChange: (h) => l(h.target.value),
                onKeyDown: (h) => {
                  h.key === "Escape" && (h.stopPropagation(), a ? l("") : r());
                },
              }),
              s.jsx(k, {
                content: c("Close"),
                position: "bottom",
                children: s.jsx("button", {
                  type: "button",
                  className: o.iconButton,
                  "aria-label": c("Close"),
                  onClick: r,
                  children: s.jsx(I, { name: "close", width: 16, height: 16 }),
                }),
              }),
            ],
          }),
      ],
    });
  }),
  ht = _(({ item: e, store: t, onContextMenu: i }) => {
    const n = e.attachment,
      a = t.getThread(e),
      l = n.type === T.VIDEO,
      d = n.extra?.duration,
      r = t.selectedKeys.has(e.key),
      h = (f) => {
        if (t.selectMode || f.metaKey || f.ctrlKey) {
          (t.selectMode || t.setSelectMode(!0), t.toggleSelected(e.key));
          return;
        }
        t.openViewer(e.key);
      };
    return s.jsxs("button", {
      type: "button",
      className: M(o.tile, "redacted-region", { [o.selected]: r }),
      onClick: h,
      onContextMenu: (f) => i(f, e),
      children: [
        l
          ? s.jsx(Y, {
              isThumbnail: !0,
              videoSrc: R(n),
              size: n.size,
              containerClassName: o.tileMedia,
            })
          : s.jsx(H, {
              uniqueID: n.id,
              mimeType: n.mimeType,
              fileName: n.fileName,
              src: R(n),
              containerClassName: o.tileMedia,
              loading: "lazy",
              decoding: "async",
            }),
        n.isGif
          ? s.jsx("span", {
              className: o.tileBadge,
              children: Z("GIF", "media viewer badge for a GIF"),
            })
          : l &&
            s.jsxs("span", {
              className: o.tileBadge,
              children: [
                s.jsx(I, { name: "videocam", width: 12, height: 12 }),
                typeof d == "number" && we(d / 1e3),
              ],
            }),
        s.jsx("span", { className: o.tileSender, children: K(e.message, a) }),
        t.selectMode &&
          s.jsx("span", {
            className: M(o.tileCheck, { [o.checked]: r }),
            children: r && s.jsx(q, { width: 14, height: 14 }),
          }),
      ],
    });
  }),
  J = (e) => {
    ve.showMainWindow();
    const t = y.getThread(e.accountID, e.threadID)?.unionThread;
    t
      ? y.jumpToMessage(t.accountStore.accountID, t.id, e.message.id)
      : y.jumpToMessage(e.accountID, e.threadID, e.message.id);
  },
  $ = (e) => {
    if (!e.attachment) return;
    const t = y.getThread(e.accountID, e.threadID);
    return y.downloadAttachment(e.attachment, t?.computedTitle);
  },
  ut = (e) =>
    U(
      e.filter((t) => t.attachment),
      (t) => $(t),
      { concurrency: 1 },
    ),
  F = (e) => {
    const t = y.getThread(e.accountID, e.threadID);
    return !t || t.deletionMode !== Ie.DELETE_FOR_EVERYONE
      ? !1
      : !!e.message.isSender &&
          !e.message.isAction &&
          t.canDeleteMessageForEveryone(e.message);
  },
  G = (e, t) => {
    const i = t.filter(F),
      n = t.length - i.length;
    if (!i.length) {
      y.addToast({ text: c("These messages can’t be deleted") });
      return;
    }
    const a = new Set(),
      l = i.filter((d) => {
        const r = `${d.accountID}|${d.threadID}|${d.message.id}`;
        return a.has(r) ? !1 : (a.add(r), !0);
      });
    return _e(
      async () => {
        const d = new Set(
          (
            await U(
              l,
              async (r) => {
                const h = y.getThread(r.accountID, r.threadID);
                if (!h) return null;
                const f = `${r.accountID}|${r.threadID}|${r.message.id}`;
                try {
                  return (await h.deleteMessageAnywhere(r.message, !0), f);
                } catch {
                  return null;
                }
              },
              { concurrency: 1 },
            )
          ).filter((r) => !!r),
        );
        (e.removeItems(
          new Set(
            e.items
              .filter((r) =>
                d.has(`${r.accountID}|${r.threadID}|${r.message.id}`),
              )
              .map((r) => r.key),
          ),
        ),
          n > 0 &&
            y.addToast({
              text: V(
                S(
                  "Skipped %d item that can’t be deleted",
                  "Skipped %d items that can’t be deleted",
                  n,
                ),
                n,
              ),
            }));
      },
      {
        title: S("Delete message", "Delete messages", l.length),
        subtitle:
          l.length > 1
            ? V(
                S(
                  "Are you sure you want to delete %d message?",
                  "Are you sure you want to delete %d messages?",
                  l.length,
                ),
                l.length,
              )
            : c("Are you sure you want to delete this message?"),
        confirmButtonText: Z("Delete", "confirmation button"),
      },
    );
  },
  ee = (e, t, { includeMediaActions: i = !0 } = {}) => {
    const { attachment: n, link: a } = t;
    return [
      !i && L,
      { label: c("Go to Message"), action: () => J(t) },
      i && L,
      i && !!n && { label: c("Download"), action: () => $(t) },
      i &&
        n?.type === T.IMG && {
          label: c("Copy Image"),
          action: () => y.copyImage(n),
        },
      !!a && {
        label: c("Copy Link"),
        action: async () => {
          (await be(a.url), y.addToast({ text: c("Copied to clipboard!") }));
        },
      },
      F(t) && { label: c("Delete…"), action: () => G(e, [t]) },
    ].filter(Boolean);
  },
  te = (e, t) => ({
    selected: e.selectedKeys.has(t.key),
    onSelectClick: (a) =>
      !e.selectMode && !a.metaKey && !a.ctrlKey
        ? !1
        : (e.selectMode || e.setSelectMode(!0), e.toggleSelected(t.key), !0),
  }),
  se = _(({ item: e, store: t }) => {
    const i = t.getThread(e);
    return s.jsxs("span", {
      className: o.listRowMeta,
      children: [
        s.jsx("span", { children: K(e.message, i) }),
        s.jsx("span", { children: ke(e.timestamp) }),
      ],
    });
  }),
  ne = ({ store: e, selected: t }) =>
    e.selectMode
      ? s.jsx("span", {
          className: M(o.tileCheck, { [o.checked]: t }),
          style: { position: "static" },
          children: t && s.jsx(q, { width: 14, height: 14 }),
        })
      : null,
  mt = _(({ item: e, store: t, onContextMenu: i }) => {
    const n = e.link,
      { selected: a, onSelectClick: l } = te(t, e);
    return s.jsxs("button", {
      type: "button",
      className: M(o.listRow, { [o.selected]: a }),
      onClick: (d) => {
        l(d) || je(n.url);
      },
      onContextMenu: (d) => i(d, e),
      children: [
        s.jsx("span", {
          className: o.listRowThumb,
          children: n.img
            ? s.jsx(O, {
                src: n.img,
                loading: "lazy",
                decoding: "async",
                draggable: !1,
              })
            : n.favicon
              ? s.jsx(O, {
                  src: n.favicon,
                  loading: "lazy",
                  decoding: "async",
                  draggable: !1,
                  style: {
                    objectFit: "contain",
                    inset: "25%",
                    width: "50%",
                    height: "50%",
                  },
                })
              : s.jsx(I, { name: "link", width: 16, height: 16 }),
        }),
        s.jsxs("span", {
          className: o.listRowText,
          children: [
            s.jsx("strong", { children: n.title || Me(n.url).host || n.url }),
            s.jsx("span", { children: n.url }),
          ],
        }),
        s.jsx(se, { item: e, store: t }),
        s.jsx(ne, { store: t, selected: a }),
      ],
    });
  }),
  pt = _(({ item: e, store: t, onContextMenu: i }) => {
    const n = e.attachment,
      { selected: a, onSelectClick: l } = te(t, e),
      d = [le(n.mimeType), n.fileSize ? Q(n.fileSize) : void 0].filter(Boolean);
    return s.jsxs("button", {
      type: "button",
      className: M(o.listRow, { [o.selected]: a }),
      onClick: (r) => {
        l(r) || $(e);
      },
      onContextMenu: (r) => i(r, e),
      children: [
        s.jsx("span", {
          className: o.listRowThumb,
          children: s.jsx(I, { name: "file-default", width: 18, height: 18 }),
        }),
        s.jsxs("span", {
          className: o.listRowText,
          children: [
            s.jsx("strong", { children: n.fileName || c("Attachment") }),
            s.jsx("span", { children: d.join(" · ") }),
          ],
        }),
        s.jsx(se, { item: e, store: t }),
        s.jsx(ne, { store: t, selected: a }),
      ],
    });
  }),
  ft = 160,
  gt = _(({ store: e }) => {
    const t = w.useRef(null),
      [i, n] = w.useState(0);
    w.useLayoutEffect(() => {
      const p = t.current;
      if (!p) return;
      const g = () => {
        p.clientWidth && n(p.clientWidth);
      };
      g();
      const b = new ResizeObserver(g);
      return (b.observe(p), () => b.disconnect());
    }, []);
    const a = Math.max(3, Math.floor(i / ft)),
      { CustomContextMenu: l, onCustomContextMenu: d } = ce(),
      r = w.useCallback(
        (p, g) => {
          (p.preventDefault(), p.stopPropagation(), d(p, ee(e, g)));
        },
        [d, e],
      ),
      h = e.tab === "media",
      { dateGroups: f } = e,
      j = w.useMemo(() => {
        if (!i) return [];
        const p = [];
        for (const g of f)
          if (
            (p.push({
              key: `header-${g.label}`,
              kind: "header",
              label: g.label,
              subtitle: g.subtitle,
            }),
            h)
          )
            for (let b = 0; b < g.items.length; b += a) {
              const B = g.items.slice(b, b + a);
              p.push({ key: `tiles-${B[0].key}`, kind: "tiles", items: B });
            }
          else
            for (const b of g.items)
              p.push({ key: `list-${b.key}`, kind: "list", item: b });
        return p;
      }, [i, f, a, h]),
      N = e.isLoading && !j.length ? 3 : e.isLoading ? 1 : 0;
    return i && !j.length && !e.isLoading
      ? s.jsxs("div", {
          className: o.grid,
          ref: t,
          children: [
            s.jsx("div", {
              className: o.emptyState,
              children: s.jsx("p", { children: c("Nothing here") }),
            }),
            l,
          ],
        })
      : s.jsxs("div", {
          className: M(o.grid, { [o.gridHidden]: e.viewerIndex != null }),
          ref: t,
          children: [
            s.jsxs(X, {
              overscan: 1,
              onRangeChange: (p, g) => {
                j.length - g < 8 && e.hasMore && e.loadMore();
              },
              children: [
                j.map((p) => {
                  switch (p.kind) {
                    case "header":
                      return s.jsxs(
                        "div",
                        {
                          className: o.dateHeader,
                          children: [
                            s.jsx("h2", { children: p.label }),
                            s.jsx("span", { children: p.subtitle }),
                          ],
                        },
                        p.key,
                      );
                    case "tiles":
                      return s.jsx(
                        "div",
                        {
                          className: o.tileRow,
                          style: { gridTemplateColumns: `repeat(${a}, 1fr)` },
                          children: p.items.map((g) =>
                            s.jsx(
                              ht,
                              { item: g, store: e, onContextMenu: r },
                              g.key,
                            ),
                          ),
                        },
                        p.key,
                      );
                    case "list":
                      return e.tab === "links"
                        ? s.jsx(
                            mt,
                            { item: p.item, store: e, onContextMenu: r },
                            p.key,
                          )
                        : s.jsx(
                            pt,
                            { item: p.item, store: e, onContextMenu: r },
                            p.key,
                          );
                  }
                }),
                Array.from({ length: N }, (p, g) =>
                  s.jsx(
                    "div",
                    {
                      className: o.skeletonRow,
                      style: { gridTemplateColumns: `repeat(${a}, 1fr)` },
                      children: Array.from({ length: a }, (b, B) =>
                        s.jsx("div", { className: o.skeletonTile }, B),
                      ),
                    },
                    `skeleton-${g}`,
                  ),
                ),
              ],
            }),
            l,
          ],
        });
  }),
  yt = _(({ store: e }) => {
    if (!e.selectMode) return null;
    const t = e.selectedKeys.size,
      { bytes: i } = e.selectionSize,
      n = e.selectedItems.some((a) => a.attachment);
    return s.jsx("div", {
      className: o.footer,
      children: s.jsxs("div", {
        className: o.selectionBar,
        children: [
          s.jsx("strong", {
            children:
              i > 0
                ? V(
                    S("%1$d selected (%2$s)", "%1$d selected (%2$s)", t),
                    t,
                    Q(i),
                  )
                : V(S("%d selected", "%d selected", t), t),
          }),
          s.jsxs("div", {
            className: o.selectionActions,
            children: [
              s.jsx("button", {
                type: "button",
                className: o.selectionButton,
                disabled: !t,
                onClick: () => G(e, e.selectedItems),
                children: c("Delete"),
              }),
              s.jsx("button", {
                type: "button",
                className: o.selectionButton,
                disabled: !n,
                onClick: () => {
                  ut(e.selectedItems);
                },
                children: c("Save"),
              }),
              s.jsx("button", {
                type: "button",
                className: o.selectionButton,
                onClick: e.selectAll,
                children: c("Select all"),
              }),
              s.jsx("button", {
                type: "button",
                className: o.selectionButton,
                onClick: () => e.setSelectMode(!1),
                children: c("Cancel"),
              }),
            ],
          }),
        ],
      }),
    });
  }),
  xt = _(({ item: e, index: t, store: i }) => {
    const n = e.attachment;
    if (!n) return null;
    const a = n.type === T.VIDEO;
    return s.jsx("button", {
      type: "button",
      className: M(o.filmstripThumb, { [o.current]: i.viewerIndex === t }),
      onClick: (l) => {
        (l.stopPropagation(), i.openViewer(e.key));
      },
      children: a
        ? s.jsx(Y, {
            isThumbnail: !0,
            videoSrc: R(n),
            size: n.size,
            containerClassName: o.tileMedia,
          })
        : s.jsx(H, {
            uniqueID: n.id,
            mimeType: n.mimeType,
            fileName: n.fileName,
            src: R(n),
            containerClassName: o.tileMedia,
            loading: "lazy",
            decoding: "async",
          }),
    });
  }),
  wt = _(({ store: e }) => {
    const t = w.useRef(null),
      i = w.useRef(null);
    return (
      w.useEffect(() => {
        const { viewerIndex: n } = e;
        if (n != null) {
          const a = i.current != null && Math.abs(n - i.current) === 1;
          t.current?.scrollToIndex(n, { align: "center", smooth: a });
        }
        i.current = n;
      }, [e, e.viewerIndex]),
      s.jsx("div", {
        className: o.filmstrip,
        onClick: (n) => n.stopPropagation(),
        children: s.jsx("div", {
          className: o.filmstripList,
          children: s.jsx(X, {
            ref: t,
            horizontal: !0,
            overscan: 3,
            onRangeChange: (n, a) => {
              e.items.length - a < 10 && e.hasMore && e.loadMore();
            },
            children: e.items.map((n, a) =>
              s.jsx(xt, { item: n, index: a, store: e }, n.key),
            ),
          }),
        }),
      })
    );
  }),
  bt = _(({ store: e }) => {
    const t = e.viewerItem,
      i = t?.attachment;
    if (!t || !i) return null;
    const n = e.getThread(t),
      a = n?.getParticipant(t.message.senderID),
      l = s.jsxs(s.Fragment, {
        children: [
          a && s.jsx(de, { user: a, size: 28 }),
          s.jsx("span", {
            className: "carousel-thread-title",
            children: K(t.message, n),
          }),
          s.jsx("span", {
            className: "carousel-timestamp",
            children: he(t.timestamp),
          }),
        ],
      }),
      d = s.jsxs(s.Fragment, {
        children: [
          s.jsx(k, {
            content: c("Go to Message"),
            children: s.jsx("button", {
              type: "button",
              className: "carousel-control",
              "aria-label": c("Go to Message"),
              onClick: (r) => {
                (r.stopPropagation(), J(t));
              },
              children: s.jsx(I, { name: "sms", width: 20, height: 20 }),
            }),
          }),
          F(t) &&
            s.jsx(k, {
              content: c("Delete"),
              children: s.jsx("button", {
                type: "button",
                className: "carousel-control",
                "aria-label": c("Delete"),
                onClick: (r) => {
                  (r.stopPropagation(), G(e, [t]));
                },
                children: s.jsx(I, { name: "delete", width: 20, height: 20 }),
              }),
            }),
        ],
      });
    return s.jsx(ue, {
      fallback: null,
      children: s.jsx(me, {
        attachments: [i],
        index: 0,
        setIndex: (r) => {
          r === null && e.closeViewer();
        },
        selectNextMessage: e.hasNextViewerItem ? e.viewerNext : void 0,
        selectPreviousMessage: e.hasPreviousViewerItem ? e.viewerPrev : void 0,
        message: t.message,
        thread: n,
        header: l,
        extraToolbarButtons: d,
        extraMenuItems: () => ee(e, t, { includeMediaActions: !1 }),
        bottomBar: s.jsx(wt, { store: e }),
      }),
    });
  }),
  _t = _(
    ({ store: e }) => (
      w.useEffect(() => {
        e.loadMore();
      }, [e]),
      s.jsxs("div", {
        className: o.mediaViewer,
        children: [
          s.jsx("div", {
            className: M(o.titleBar, { [o.isMac]: xe }),
            children: c("Media"),
          }),
          s.jsxs("div", {
            className: o.container,
            children: [
              s.jsx(dt, { store: e }),
              s.jsx(gt, { store: e }),
              s.jsx(yt, { store: e }),
            ],
          }),
          e.viewerItem?.attachment && s.jsx(bt, { store: e }),
        ],
      })
    ),
  );
var vt = Object.defineProperty,
  It = Object.getOwnPropertyDescriptor,
  m = (e, t, i, n) => {
    for (
      var a = n > 1 ? void 0 : n ? It(t, i) : t, l = e.length - 1, d;
      l >= 0;
      l--
    )
      (d = e[l]) && (a = (n ? d(t, i, a) : d(a)) || a);
    return (n && a && vt(t, i, a), a);
  };
const Mt = 50,
  jt = 5,
  z = new Map(),
  C = (e) => {
    const t = new Date(e);
    return (t.setHours(0, 0, 0, 0), t);
  },
  kt = (e) => {
    const t = C(e),
      i = (t.getDay() + 6) % 7;
    return (t.setDate(t.getDate() - i), t);
  },
  W = (e = new Date()) => {
    const t = fe();
    let i = z.get(t);
    i ||
      ((i = {
        month: new Intl.DateTimeFormat(t, { month: "long" }),
        monthAndYear: new Intl.DateTimeFormat(t, {
          month: "long",
          year: "numeric",
        }),
        fullDate: new Intl.DateTimeFormat(t, {
          day: "numeric",
          month: "short",
          year: "numeric",
        }),
      }),
      z.set(t, i));
    const n = C(e),
      a = new Date(n);
    a.setDate(a.getDate() - 1);
    const l = kt(e),
      d = new Date(l);
    return (
      d.setDate(d.getDate() - 7),
      {
        key: `${t}:${n.getTime()}`,
        currentYear: e.getFullYear(),
        today: n.getTime(),
        yesterday: a.getTime(),
        thisWeek: l.getTime(),
        lastWeek: d.getTime(),
        ...i,
      }
    );
  },
  Tt = (e, t) => {
    const i = C(e).getTime();
    return i === t.today
      ? c("Today")
      : i === t.yesterday
        ? c("Yesterday")
        : i >= t.thisWeek
          ? c("This week")
          : i >= t.lastWeek
            ? c("Last week")
            : (e.getFullYear() === t.currentYear
                ? t.month
                : t.monthAndYear
              ).format(e);
  },
  ie = (e, t) => {
    const i = e.items[0].timestamp,
      n = e.items[e.items.length - 1].timestamp,
      [a, l] = i <= n ? [i, n] : [n, i];
    e.subtitle =
      C(a).getTime() === C(l).getTime()
        ? t.fullDate.format(a)
        : `${t.fullDate.format(a)} - ${t.fullDate.format(l)}`;
  },
  E = (e, t) => {
    const i = [];
    for (const n of e) {
      const a = Tt(n.timestamp, t),
        l = i[i.length - 1];
      l?.label === a
        ? l.items.push(n)
        : i.push({ label: a, subtitle: "", items: [n] });
    }
    for (const n of i) ie(n, t);
    return i;
  },
  St = (e, t, i) => {
    const n = E(t, i);
    if (!e.length) return n;
    if (!n.length) return e;
    const a = e[e.length - 1],
      l = n[0];
    if (a.label !== l.label) return [...e, ...n];
    const d = { ...a, items: [...a.items, ...l.items] };
    return (ie(d, i), [...e.slice(0, -1), d, ...n.slice(1)]);
  },
  Ct = (e, t) => {
    const i = e.accountID,
      { threadID: n } = e;
    if (!i || !n) return [];
    const a = { accountID: i, threadID: n, message: e, timestamp: e.timestamp };
    if (t === "links")
      return (e.links ?? []).map((r, h) => ({
        ...a,
        key: `${i}|${n}|${e.id}|link${h}`,
        link: r,
      }));
    const l = [
        ...(e.attachments ?? []),
        ...(e.tweets?.flatMap((r) => r.attachments ?? []) ?? []),
      ],
      d =
        t === "media"
          ? (r) => r.type === T.IMG || r.type === T.VIDEO
          : (r) => r.type === T.UNKNOWN;
    return l
      .filter(d)
      .map((r) => ({ ...a, key: `${i}|${n}|${e.id}|${r.id}`, attachment: r }));
  };
class u {
  constructor() {
    ((this.tab = "media"),
      (this.sentBy = "all"),
      (this.sort = "newest"),
      (this.searchText = ""),
      (this.items = []),
      (this.dateGroups = []),
      (this.hasMore = !0),
      (this.isLoading = !1),
      (this.viewerIndex = null),
      (this.selectMode = !1),
      (this.selectedKeys = v.map()),
      (this.cursor = void 0),
      (this.generation = 0),
      (this.seenKeys = new Set()),
      (this.dateGroupContextKey = ""),
      (this.advanceViewerAfterLoad = !1),
      (this.setTab = (t) => {
        this.tab !== t && ((this.tab = t), this.reset());
      }),
      (this.setSentBy = (t) => {
        this.sentBy !== t && ((this.sentBy = t), this.reset());
      }),
      (this.setSort = (t) => {
        this.sort !== t && ((this.sort = t), this.reset());
      }),
      (this.setSearchText = (t) => {
        this.searchText !== t && ((this.searchText = t), this.reset());
      }),
      (this.loadMore = async () => {
        if (this.isLoading || !this.hasMore) return;
        this.isLoading = !0;
        const t = this.generation;
        try {
          const i = [];
          let n = this.hasMore,
            a = this.cursor;
          for (let h = 0; h < jt; h++) {
            const f = await y.bapi.searchRoomMessages(
              this.searchText,
              a,
              this.buildOptions(),
            );
            if (t !== this.generation) return;
            const j = this.sort === "oldest" ? f.items : [...f.items].reverse();
            for (const p of j)
              for (const g of Ct(p, this.tab))
                this.seenKeys.has(g.key) ||
                  (this.seenKeys.add(g.key), i.push(g));
            n = f.hasMore;
            const N = this.sort === "oldest" ? f.newestCursor : f.oldestCursor;
            if (
              ((a = N
                ? {
                    cursor: N,
                    direction: this.sort === "oldest" ? "after" : "before",
                  }
                : void 0),
              !n || !a || i.length > 0)
            )
              break;
          }
          const l = new Map();
          for (const h of i) {
            const f = l.get(h.accountID) ?? [];
            (f.push(h.threadID), l.set(h.accountID, f));
          }
          if (
            (await Promise.all(
              Array.from(l, ([h, f]) =>
                y.accountsStore.getAccount(h)?.loadThreadsIfMissing(pe(f)),
              ),
            ),
            t !== this.generation)
          )
            return;
          const d = i.filter(
              (h) =>
                !y.accountsStore
                  .getAccount(h.accountID)
                  ?.inboxes[Te.REQUESTS].threadsMap.has(h.threadID),
            ),
            r = d.length === 0 && n && !!a;
          (A(() => {
            if (t !== this.generation) return;
            const h = [...this.items, ...d],
              f = W();
            ((this.dateGroups =
              this.dateGroupContextKey === f.key
                ? St(this.dateGroups, d, f)
                : E(h, f)),
              (this.dateGroupContextKey = f.key),
              (this.items = h),
              (this.hasMore = n),
              (this.cursor = a),
              (this.isLoading = r),
              this.advanceViewerAfterLoad &&
                (this.viewerIndex != null &&
                this.viewerIndex < this.items.length - 1
                  ? (this.viewerIndex++, (this.advanceViewerAfterLoad = !1))
                  : n || (this.advanceViewerAfterLoad = !1)));
          }),
            r &&
              setTimeout(() => {
                t === this.generation &&
                  (A(() => {
                    this.isLoading = !1;
                  }),
                  this.loadMore());
              }, 0));
        } catch (i) {
          (logger.error("MediaViewer: failed to load media", i),
            A(() => {
              t === this.generation && (this.isLoading = !1);
            }));
        }
      }),
      (this.getThread = (t) => y.getThread(t.accountID, t.threadID)),
      (this.openViewer = (t) => {
        const i = this.items.findIndex((n) => n.key === t);
        i !== -1 &&
          ((this.viewerIndex = i), (this.advanceViewerAfterLoad = !1));
      }),
      (this.closeViewer = () => {
        ((this.viewerIndex = null), (this.advanceViewerAfterLoad = !1));
      }),
      (this.viewerNext = () => {
        if (this.viewerIndex != null) {
          if (this.viewerIndex < this.items.length - 1) this.viewerIndex++;
          else if (this.hasMore) {
            ((this.advanceViewerAfterLoad = !0), this.loadMore());
            return;
          }
          this.items.length - this.viewerIndex < 10 &&
            this.hasMore &&
            this.loadMore();
        }
      }),
      (this.viewerPrev = () => {
        this.viewerIndex == null ||
          this.viewerIndex === 0 ||
          ((this.advanceViewerAfterLoad = !1), this.viewerIndex--);
      }),
      (this.setSelectMode = (t) => {
        ((this.selectMode = t), t || this.selectedKeys.clear());
      }),
      (this.toggleSelected = (t) => {
        this.selectedKeys.has(t)
          ? this.selectedKeys.delete(t)
          : this.selectedKeys.set(t, !0);
      }),
      (this.selectAll = () => {
        for (const t of this.items) this.selectedKeys.set(t.key, !0);
      }),
      (this.removeItems = (t) => {
        const i = this.viewerIndex,
          n =
            i == null
              ? 0
              : this.items.slice(0, i).filter((l) => t.has(l.key)).length;
        this.items = this.items.filter((l) => !t.has(l.key));
        const a = W();
        ((this.dateGroups = E(this.items, a)),
          (this.dateGroupContextKey = a.key));
        for (const l of t)
          (this.selectedKeys.delete(l), this.seenKeys.delete(l));
        i != null &&
          (this.viewerIndex = this.items.length
            ? Math.min(i - n, this.items.length - 1)
            : null);
      }));
  }
  reset() {
    (this.generation++,
      (this.items = []),
      (this.dateGroups = []),
      (this.dateGroupContextKey = ""),
      this.seenKeys.clear(),
      (this.cursor = void 0),
      (this.hasMore = !0),
      (this.isLoading = !1),
      (this.viewerIndex = null),
      (this.advanceViewerAfterLoad = !1),
      this.selectedKeys.clear(),
      this.loadMore());
  }
  buildOptions() {
    return {
      media:
        this.tab === "media"
          ? { image: !0, video: !0 }
          : this.tab === "links"
            ? { link: !0 }
            : { file: !0 },
      sender: this.sentBy === "all" ? void 0 : this.sentBy,
      sortOrder: this.sort === "oldest" ? "asc" : void 0,
      limit: Mt,
      partialMatchesEnabled: !0,
      excludeLowPriority: !0,
    };
  }
  get viewerItem() {
    return this.viewerIndex == null
      ? null
      : (this.items[this.viewerIndex] ?? null);
  }
  get hasNextViewerItem() {
    return (
      this.viewerIndex != null &&
      (this.viewerIndex < this.items.length - 1 || this.hasMore)
    );
  }
  get hasPreviousViewerItem() {
    return this.viewerIndex != null && this.viewerIndex > 0;
  }
  get selectedItems() {
    return this.items.filter((t) => this.selectedKeys.has(t.key));
  }
  get selectionSize() {
    let t = 0,
      i = 0;
    for (const { attachment: n, link: a } of this.selectedItems)
      a || (n?.fileSize ? (t += n.fileSize) : i++);
    return { bytes: t, unknownCount: i };
  }
}
m([v], u.prototype, "tab", 2);
m([v], u.prototype, "sentBy", 2);
m([v], u.prototype, "sort", 2);
m([v], u.prototype, "searchText", 2);
m([v.shallow], u.prototype, "items", 2);
m([v.shallow], u.prototype, "dateGroups", 2);
m([v], u.prototype, "hasMore", 2);
m([v], u.prototype, "isLoading", 2);
m([v], u.prototype, "viewerIndex", 2);
m([v], u.prototype, "selectMode", 2);
m([x], u.prototype, "setTab", 2);
m([x], u.prototype, "setSentBy", 2);
m([x], u.prototype, "setSort", 2);
m([x], u.prototype, "setSearchText", 2);
m([x], u.prototype, "reset", 1);
m([x], u.prototype, "loadMore", 2);
m([x], u.prototype, "openViewer", 2);
m([x], u.prototype, "closeViewer", 2);
m([D], u.prototype, "viewerItem", 1);
m([D], u.prototype, "hasNextViewerItem", 1);
m([D], u.prototype, "hasPreviousViewerItem", 1);
m([x], u.prototype, "viewerNext", 2);
m([x], u.prototype, "viewerPrev", 2);
m([x], u.prototype, "setSelectMode", 2);
m([x], u.prototype, "toggleSelected", 2);
m([x], u.prototype, "selectAll", 2);
m([D], u.prototype, "selectedItems", 1);
m([D], u.prototype, "selectionSize", 1);
m([x], u.prototype, "removeItems", 2);
class Kt extends ge {
  constructor() {
    (super(...arguments), (this.store = new u()));
  }
  get id() {
    return "media-viewer";
  }
  get title() {
    return c("Media");
  }
  get windowFeatures() {
    return {
      width: 1e3,
      height: 720,
      toolbar: !1,
      center: "parent",
      titleBarStyle: "hidden",
      trafficLightY: 9.5,
    };
  }
  render() {
    return s.jsxs(s.Fragment, {
      children: [
        s.jsx(_t, {
          store: this.store,
          "data-sentry-element": "MediaViewer",
          "data-sentry-source-file": "MediaViewerBrowserWindow.tsx",
        }),
        s.jsx(ye, {
          "data-sentry-element": "Toasts",
          "data-sentry-source-file": "MediaViewerBrowserWindow.tsx",
        }),
      ],
    });
  }
  onEscapePressed() {
    if (this.store.viewerIndex != null) {
      this.store.closeViewer();
      return;
    }
    if (this.store.selectMode) {
      this.store.setSelectMode(!1);
      return;
    }
    this.close();
  }
}
export { Kt as MediaViewerBrowserWindow };
//# sourceMappingURL=MediaViewerBrowserWindow--G-CUoLJ.js.map
