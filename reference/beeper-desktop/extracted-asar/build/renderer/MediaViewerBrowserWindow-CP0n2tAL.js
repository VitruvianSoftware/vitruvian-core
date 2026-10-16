import {
  cY as M,
  dk as x,
  ba as ae,
  cK as s,
  v as oe,
  w as T,
  aT as I,
  bw as j,
  aN as L,
  da as re,
  x as H,
  c4 as B,
  U as Y,
  ch as K,
  Z as q,
  d4 as U,
  a8 as O,
  ce as le,
  et as ce,
  e3 as Z,
  b6 as de,
  cn as he,
  aS as ue,
  H as me,
  en as pe,
  cc as fe,
  l as we,
  b1 as ge,
} from "./App-CsJiApxN.js";
import { w as ye } from "./sentry-common-BxRELKId.js";
import {
  a2 as c,
  c as _,
  a6 as Q,
  aO as xe,
  cD as g,
  ar as be,
  c_ as Me,
  cN as R,
  a3 as S,
  ac as ve,
  z as Ie,
  c0 as je,
  c7 as ke,
  aG as X,
  aN as Te,
  c5 as v,
  o as _e,
  cE as A,
  a7 as y,
  an as C,
} from "./matrix-util-Cr_UwXbj.js";
import "./index-Cw3pknxT.js";
import "./index-Dhe7xemD.js";
import "./index-CcYzEQCb.js";
import "./main-process-state-wkFhis-C.js";
import "./report-dialog-7bETf2vU.js";
import "./helpHubMessages-CXhGQ9cB.js";
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
      (e._sentryDebugIds[t] = "58dc5ae6-a493-4fd4-bdb3-a2586504b4b2"),
      (e._sentryDebugIdIdentifier =
        "sentry-dbid-58dc5ae6-a493-4fd4-bdb3-a2586504b4b2"));
  } catch {}
})();
const Se = "MediaViewer-module__mediaViewer",
  Ve = "MediaViewer-module__titleBar",
  Ce = "MediaViewer-module__isMac",
  De = "MediaViewer-module__container",
  Ne = "MediaViewer-module__header",
  Be = "MediaViewer-module__headerTabs",
  Re = "MediaViewer-module__headerControls",
  Ae = "MediaViewer-module__iconButton",
  Le = "MediaViewer-module__active",
  Ee = "MediaViewer-module__searchRow",
  Ke = "MediaViewer-module__grid",
  $e = "MediaViewer-module__gridHidden",
  Ge = "MediaViewer-module__dateHeader",
  Fe = "MediaViewer-module__tileRow",
  Oe = "MediaViewer-module__tile",
  Pe = "MediaViewer-module__selected",
  ze = "MediaViewer-module__tileMedia",
  We = "MediaViewer-module__tileSender",
  He = "MediaViewer-module__tileBadge",
  Ye = "MediaViewer-module__tileCheck",
  qe = "MediaViewer-module__checked",
  Ue = "MediaViewer-module__listRow",
  Ze = "MediaViewer-module__listRowThumb",
  Qe = "MediaViewer-module__listRowText",
  Xe = "MediaViewer-module__listRowMeta",
  Je = "MediaViewer-module__footer",
  et = "MediaViewer-module__selectionBar",
  tt = "MediaViewer-module__selectionActions",
  st = "MediaViewer-module__selectionButton",
  it = "MediaViewer-module__emptyState",
  nt = "MediaViewer-module__filmstrip",
  at = "MediaViewer-module__filmstripList",
  ot = "MediaViewer-module__filmstripThumb",
  rt = "MediaViewer-module__current",
  lt = "MediaViewer-module__skeletonRow",
  ct = "MediaViewer-module__skeletonTile",
  o = {
    mediaViewer: Se,
    titleBar: Ve,
    isMac: Ce,
    container: De,
    header: Ne,
    headerTabs: Be,
    headerControls: Re,
    iconButton: Ae,
    active: Le,
    searchRow: Ee,
    grid: Ke,
    gridHidden: $e,
    dateHeader: Ge,
    tileRow: Fe,
    tile: Oe,
    selected: Pe,
    tileMedia: ze,
    tileSender: We,
    tileBadge: He,
    tileCheck: Ye,
    checked: qe,
    listRow: Ue,
    listRowThumb: Ze,
    listRowText: Qe,
    listRowMeta: Xe,
    footer: Je,
    selectionBar: et,
    selectionActions: tt,
    selectionButton: st,
    emptyState: it,
    filmstrip: nt,
    filmstripList: at,
    filmstripThumb: ot,
    current: rt,
    skeletonRow: lt,
    skeletonTile: ct,
  },
  P = ["media", "links", "docs"],
  dt = M(({ store: e }) => {
    const t = x.useContext(ae),
      [n, i] = x.useState(!1),
      [a, l] = x.useState("");
    x.useEffect(() => {
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
        (i(!1), l(""), e.setSearchText(""));
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
                s.jsx(T, {
                  content: c("Select"),
                  position: "bottom",
                  children: s.jsx("button", {
                    type: "button",
                    className: j(o.iconButton, { [o.active]: e.selectMode }),
                    "aria-label": c("Select"),
                    onClick: () => e.setSelectMode(!e.selectMode),
                    children: s.jsx(I, { name: "done", width: 18, height: 18 }),
                  }),
                }),
                s.jsx(T, {
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
                s.jsx(T, {
                  content: c("Search"),
                  position: "bottom",
                  children: s.jsx("button", {
                    type: "button",
                    className: j(o.iconButton, { [o.active]: n }),
                    "aria-label": c("Search"),
                    onClick: () => (n ? r() : i(!0)),
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
        n &&
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
              s.jsx(T, {
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
  ht = M(({ item: e, store: t, onContextMenu: n }) => {
    const i = e.attachment,
      a = t.getThread(e),
      l = i.type === _.VIDEO,
      d = i.extra?.duration,
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
      className: j(o.tile, "redacted-region", { [o.selected]: r }),
      onClick: h,
      onContextMenu: (f) => n(f, e),
      children: [
        l
          ? s.jsx(H, {
              isThumbnail: !0,
              videoSrc: B(i),
              size: i.size,
              containerClassName: o.tileMedia,
            })
          : s.jsx(Y, {
              uniqueID: i.id,
              mimeType: i.mimeType,
              fileName: i.fileName,
              src: B(i),
              containerClassName: o.tileMedia,
              loading: "lazy",
              decoding: "async",
            }),
        i.isGif
          ? s.jsx("span", {
              className: o.tileBadge,
              children: Q("GIF", "media viewer badge for a GIF"),
            })
          : l &&
            s.jsxs("span", {
              className: o.tileBadge,
              children: [
                s.jsx(I, { name: "videocam", width: 12, height: 12 }),
                typeof d == "number" && xe(d / 1e3),
              ],
            }),
        s.jsx("span", { className: o.tileSender, children: K(e.message, a) }),
        t.selectMode &&
          s.jsx("span", {
            className: j(o.tileCheck, { [o.checked]: r }),
            children: r && s.jsx(q, { width: 14, height: 14 }),
          }),
      ],
    });
  }),
  J = (e) => {
    ve.showMainWindow();
    const t = g.getThread(e.accountID, e.threadID)?.unionThread;
    t
      ? g.jumpToMessage(t.accountStore.accountID, t.id, e.message.id)
      : g.jumpToMessage(e.accountID, e.threadID, e.message.id);
  },
  $ = (e) => {
    if (!e.attachment) return;
    const t = g.getThread(e.accountID, e.threadID);
    return g.downloadAttachment(e.attachment, t?.computedTitle);
  },
  ut = (e) =>
    U(
      e.filter((t) => t.attachment),
      (t) => $(t),
      { concurrency: 1 },
    ),
  G = (e) => {
    const t = g.getThread(e.accountID, e.threadID);
    return !t || t.deletionMode !== Ie.DELETE_FOR_EVERYONE
      ? !1
      : !!e.message.isSender &&
          !e.message.isAction &&
          t.canDeleteMessageForEveryone(e.message);
  },
  F = (e, t) => {
    const n = t.filter(G),
      i = t.length - n.length;
    if (!n.length) {
      g.addToast({ text: c("These messages can’t be deleted") });
      return;
    }
    const a = new Set(),
      l = n.filter((d) => {
        const r = `${d.accountID}|${d.threadID}|${d.message.id}`;
        return a.has(r) ? !1 : (a.add(r), !0);
      });
    return Me(
      async () => {
        const d = new Set(
          (
            await U(
              l,
              async (r) => {
                const h = g.getThread(r.accountID, r.threadID);
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
          i > 0 &&
            g.addToast({
              text: R(
                S(
                  "Skipped %d item that can’t be deleted",
                  "Skipped %d items that can’t be deleted",
                  i,
                ),
                i,
              ),
            }));
      },
      {
        title: S("Delete message", "Delete messages", l.length),
        subtitle:
          l.length > 1
            ? R(
                S(
                  "Are you sure you want to delete %d message?",
                  "Are you sure you want to delete %d messages?",
                  l.length,
                ),
                l.length,
              )
            : c("Are you sure you want to delete this message?"),
        confirmButtonText: Q("Delete", "confirmation button"),
      },
    );
  },
  ee = (e, t, { includeMediaActions: n = !0 } = {}) => {
    const { attachment: i, link: a } = t;
    return [
      !n && L,
      { label: c("Go to Message"), action: () => J(t) },
      n && L,
      n && !!i && { label: c("Download"), action: () => $(t) },
      n &&
        i?.type === _.IMG && {
          label: c("Copy Image"),
          action: () => g.copyImage(i),
        },
      !!a && {
        label: c("Copy Link"),
        action: async () => {
          (await be(a.url), g.addToast({ text: c("Copied to clipboard!") }));
        },
      },
      G(t) && { label: c("Delete…"), action: () => F(e, [t]) },
    ].filter(Boolean);
  },
  te = (e, t) => ({
    selected: e.selectedKeys.has(t.key),
    onSelectClick: (a) =>
      !e.selectMode && !a.metaKey && !a.ctrlKey
        ? !1
        : (e.selectMode || e.setSelectMode(!0), e.toggleSelected(t.key), !0),
  }),
  se = M(({ item: e, store: t }) => {
    const n = t.getThread(e);
    return s.jsxs("span", {
      className: o.listRowMeta,
      children: [
        s.jsx("span", { children: K(e.message, n) }),
        s.jsx("span", { children: Te(e.timestamp) }),
      ],
    });
  }),
  ie = ({ store: e, selected: t }) =>
    e.selectMode
      ? s.jsx("span", {
          className: j(o.tileCheck, { [o.checked]: t }),
          style: { position: "static" },
          children: t && s.jsx(q, { width: 14, height: 14 }),
        })
      : null,
  mt = M(({ item: e, store: t, onContextMenu: n }) => {
    const i = e.link,
      { selected: a, onSelectClick: l } = te(t, e);
    return s.jsxs("button", {
      type: "button",
      className: j(o.listRow, { [o.selected]: a }),
      onClick: (d) => {
        l(d) || ke(i.url);
      },
      onContextMenu: (d) => n(d, e),
      children: [
        s.jsx("span", {
          className: o.listRowThumb,
          children: i.img
            ? s.jsx(O, {
                src: i.img,
                loading: "lazy",
                decoding: "async",
                draggable: !1,
              })
            : i.favicon
              ? s.jsx(O, {
                  src: i.favicon,
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
            s.jsx("strong", { children: i.title || je(i.url).host || i.url }),
            s.jsx("span", { children: i.url }),
          ],
        }),
        s.jsx(se, { item: e, store: t }),
        s.jsx(ie, { store: t, selected: a }),
      ],
    });
  }),
  pt = M(({ item: e, store: t, onContextMenu: n }) => {
    const i = e.attachment,
      { selected: a, onSelectClick: l } = te(t, e),
      d = [le(i.mimeType), i.fileSize ? X(i.fileSize) : void 0].filter(Boolean);
    return s.jsxs("button", {
      type: "button",
      className: j(o.listRow, { [o.selected]: a }),
      onClick: (r) => {
        l(r) || $(e);
      },
      onContextMenu: (r) => n(r, e),
      children: [
        s.jsx("span", {
          className: o.listRowThumb,
          children: s.jsx(I, { name: "file-default", width: 18, height: 18 }),
        }),
        s.jsxs("span", {
          className: o.listRowText,
          children: [
            s.jsx("strong", { children: i.fileName || c("Attachment") }),
            s.jsx("span", { children: d.join(" · ") }),
          ],
        }),
        s.jsx(se, { item: e, store: t }),
        s.jsx(ie, { store: t, selected: a }),
      ],
    });
  }),
  ft = 160,
  wt = M(({ store: e }) => {
    const t = x.useRef(null),
      [n, i] = x.useState(0);
    x.useLayoutEffect(() => {
      const p = t.current;
      if (!p) return;
      const w = () => {
        p.clientWidth && i(p.clientWidth);
      };
      w();
      const b = new ResizeObserver(w);
      return (b.observe(p), () => b.disconnect());
    }, []);
    const a = Math.max(3, Math.floor(n / ft)),
      { CustomContextMenu: l, onCustomContextMenu: d } = ce(),
      r = x.useCallback(
        (p, w) => {
          (p.preventDefault(), p.stopPropagation(), d(p, ee(e, w)));
        },
        [d, e],
      ),
      h = e.tab === "media",
      { dateGroups: f } = e,
      k = x.useMemo(() => {
        if (!n) return [];
        const p = [];
        for (const w of f)
          if (
            (p.push({
              key: `header-${w.label}`,
              kind: "header",
              label: w.label,
              subtitle: w.subtitle,
            }),
            h)
          )
            for (let b = 0; b < w.items.length; b += a) {
              const N = w.items.slice(b, b + a);
              p.push({ key: `tiles-${N[0].key}`, kind: "tiles", items: N });
            }
          else
            for (const b of w.items)
              p.push({ key: `list-${b.key}`, kind: "list", item: b });
        return p;
      }, [n, f, a, h]),
      D = e.isLoading && !k.length ? 3 : e.isLoading ? 1 : 0;
    return n && !k.length && !e.isLoading
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
          className: j(o.grid, { [o.gridHidden]: e.viewerIndex != null }),
          ref: t,
          children: [
            s.jsxs(Z, {
              overscan: 1,
              onRangeChange: (p, w) => {
                k.length - w < 8 && e.hasMore && e.loadMore();
              },
              children: [
                k.map((p) => {
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
                          children: p.items.map((w) =>
                            s.jsx(
                              ht,
                              { item: w, store: e, onContextMenu: r },
                              w.key,
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
                Array.from({ length: D }, (p, w) =>
                  s.jsx(
                    "div",
                    {
                      className: o.skeletonRow,
                      style: { gridTemplateColumns: `repeat(${a}, 1fr)` },
                      children: Array.from({ length: a }, (b, N) =>
                        s.jsx("div", { className: o.skeletonTile }, N),
                      ),
                    },
                    `skeleton-${w}`,
                  ),
                ),
              ],
            }),
            l,
          ],
        });
  }),
  gt = M(({ store: e }) => {
    if (!e.selectMode) return null;
    const t = e.selectedKeys.size,
      { bytes: n } = e.selectionSize,
      i = e.selectedItems.some((a) => a.attachment);
    return s.jsx("div", {
      className: o.footer,
      children: s.jsxs("div", {
        className: o.selectionBar,
        children: [
          s.jsx("strong", {
            children:
              n > 0
                ? R(
                    S("%1$d selected (%2$s)", "%1$d selected (%2$s)", t),
                    t,
                    X(n),
                  )
                : R(S("%d selected", "%d selected", t), t),
          }),
          s.jsxs("div", {
            className: o.selectionActions,
            children: [
              s.jsx("button", {
                type: "button",
                className: o.selectionButton,
                disabled: !t,
                onClick: () => F(e, e.selectedItems),
                children: c("Delete"),
              }),
              s.jsx("button", {
                type: "button",
                className: o.selectionButton,
                disabled: !i,
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
  yt = M(({ item: e, index: t, store: n }) => {
    const i = e.attachment;
    if (!i) return null;
    const a = i.type === _.VIDEO;
    return s.jsx("button", {
      type: "button",
      className: j(o.filmstripThumb, { [o.current]: n.viewerIndex === t }),
      onClick: (l) => {
        (l.stopPropagation(), n.openViewer(e.key));
      },
      children: a
        ? s.jsx(H, {
            isThumbnail: !0,
            videoSrc: B(i),
            size: i.size,
            containerClassName: o.tileMedia,
          })
        : s.jsx(Y, {
            uniqueID: i.id,
            mimeType: i.mimeType,
            fileName: i.fileName,
            src: B(i),
            containerClassName: o.tileMedia,
            loading: "lazy",
            decoding: "async",
          }),
    });
  }),
  xt = M(({ store: e }) => {
    const t = x.useRef(null),
      n = x.useRef(null);
    return (
      x.useEffect(() => {
        const { viewerIndex: i } = e;
        if (i != null) {
          const a = n.current != null && Math.abs(i - n.current) === 1;
          t.current?.scrollToIndex(i, { align: "center", smooth: a });
        }
        n.current = i;
      }, [e, e.viewerIndex]),
      s.jsx("div", {
        className: o.filmstrip,
        onClick: (i) => i.stopPropagation(),
        children: s.jsx("div", {
          className: o.filmstripList,
          children: s.jsx(Z, {
            ref: t,
            horizontal: !0,
            overscan: 3,
            onRangeChange: (i, a) => {
              e.items.length - a < 10 && e.hasMore && e.loadMore();
            },
            children: e.items.map((i, a) =>
              s.jsx(yt, { item: i, index: a, store: e }, i.key),
            ),
          }),
        }),
      })
    );
  }),
  bt = M(({ store: e }) => {
    const t = e.viewerItem,
      n = t?.attachment;
    if (!t || !n) return null;
    const i = e.getThread(t),
      a = i?.getParticipant(t.message.senderID),
      l = s.jsxs(s.Fragment, {
        children: [
          a && s.jsx(de, { user: a, size: 28 }),
          s.jsx("span", {
            className: "carousel-thread-title",
            children: K(t.message, i),
          }),
          s.jsx("span", {
            className: "carousel-timestamp",
            children: he(t.timestamp),
          }),
        ],
      }),
      d = s.jsxs(s.Fragment, {
        children: [
          s.jsx(T, {
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
          G(t) &&
            s.jsx(T, {
              content: c("Delete"),
              children: s.jsx("button", {
                type: "button",
                className: "carousel-control",
                "aria-label": c("Delete"),
                onClick: (r) => {
                  (r.stopPropagation(), F(e, [t]));
                },
                children: s.jsx(I, { name: "delete", width: 20, height: 20 }),
              }),
            }),
        ],
      });
    return s.jsx(ue, {
      fallback: null,
      children: s.jsx(me, {
        attachments: [n],
        index: 0,
        setIndex: (r) => {
          r === null && e.closeViewer();
        },
        selectNextMessage: e.hasNextViewerItem ? e.viewerNext : void 0,
        selectPreviousMessage: e.hasPreviousViewerItem ? e.viewerPrev : void 0,
        message: t.message,
        thread: i,
        header: l,
        extraToolbarButtons: d,
        extraMenuItems: () => ee(e, t, { includeMediaActions: !1 }),
        bottomBar: s.jsx(xt, { store: e }),
      }),
    });
  }),
  Mt = M(
    ({ store: e }) => (
      x.useEffect(() => {
        e.loadMore();
      }, [e]),
      s.jsxs("div", {
        className: o.mediaViewer,
        children: [
          s.jsx("div", {
            className: j(o.titleBar, { [o.isMac]: ye }),
            children: c("Media"),
          }),
          s.jsxs("div", {
            className: o.container,
            children: [
              s.jsx(dt, { store: e }),
              s.jsx(wt, { store: e }),
              s.jsx(gt, { store: e }),
            ],
          }),
          e.viewerItem?.attachment && s.jsx(bt, { store: e }),
        ],
      })
    ),
  );
var vt = Object.defineProperty,
  It = Object.getOwnPropertyDescriptor,
  m = (e, t, n, i) => {
    for (
      var a = i > 1 ? void 0 : i ? It(t, n) : t, l = e.length - 1, d;
      l >= 0;
      l--
    )
      (d = e[l]) && (a = (i ? d(t, n, a) : d(a)) || a);
    return (i && a && vt(t, n, a), a);
  };
const jt = 50,
  kt = 5,
  z = new Map(),
  V = (e) => {
    const t = new Date(e);
    return (t.setHours(0, 0, 0, 0), t);
  },
  Tt = (e) => {
    const t = V(e),
      n = (t.getDay() + 6) % 7;
    return (t.setDate(t.getDate() - n), t);
  },
  W = (e = new Date()) => {
    const t = fe();
    let n = z.get(t);
    n ||
      ((n = {
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
      z.set(t, n));
    const i = V(e),
      a = new Date(i);
    a.setDate(a.getDate() - 1);
    const l = Tt(e),
      d = new Date(l);
    return (
      d.setDate(d.getDate() - 7),
      {
        key: `${t}:${i.getTime()}`,
        currentYear: e.getFullYear(),
        today: i.getTime(),
        yesterday: a.getTime(),
        thisWeek: l.getTime(),
        lastWeek: d.getTime(),
        ...n,
      }
    );
  },
  _t = (e, t) => {
    const n = V(e).getTime();
    return n === t.today
      ? c("Today")
      : n === t.yesterday
        ? c("Yesterday")
        : n >= t.thisWeek
          ? c("This week")
          : n >= t.lastWeek
            ? c("Last week")
            : (e.getFullYear() === t.currentYear
                ? t.month
                : t.monthAndYear
              ).format(e);
  },
  ne = (e, t) => {
    const n = e.items[0].timestamp,
      i = e.items[e.items.length - 1].timestamp,
      [a, l] = n <= i ? [n, i] : [i, n];
    e.subtitle =
      V(a).getTime() === V(l).getTime()
        ? t.fullDate.format(a)
        : `${t.fullDate.format(a)} - ${t.fullDate.format(l)}`;
  },
  E = (e, t) => {
    const n = [];
    for (const i of e) {
      const a = _t(i.timestamp, t),
        l = n[n.length - 1];
      l?.label === a
        ? l.items.push(i)
        : n.push({ label: a, subtitle: "", items: [i] });
    }
    for (const i of n) ne(i, t);
    return n;
  },
  St = (e, t, n) => {
    const i = E(t, n);
    if (!e.length) return i;
    if (!i.length) return e;
    const a = e[e.length - 1],
      l = i[0];
    if (a.label !== l.label) return [...e, ...i];
    const d = { ...a, items: [...a.items, ...l.items] };
    return (ne(d, n), [...e.slice(0, -1), d, ...i.slice(1)]);
  },
  Vt = (e, t) => {
    const n = e.accountID,
      { threadID: i } = e;
    if (!n || !i) return [];
    const a = { accountID: n, threadID: i, message: e, timestamp: e.timestamp };
    if (t === "links")
      return (e.links ?? []).map((r, h) => ({
        ...a,
        key: `${n}|${i}|${e.id}|link${h}`,
        link: r,
      }));
    const l = [
        ...(e.attachments ?? []),
        ...(e.tweets?.flatMap((r) => r.attachments ?? []) ?? []),
      ],
      d =
        t === "media"
          ? (r) => r.type === _.IMG || r.type === _.VIDEO
          : (r) => r.type === _.UNKNOWN;
    return l
      .filter(d)
      .map((r) => ({ ...a, key: `${n}|${i}|${e.id}|${r.id}`, attachment: r }));
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
          const n = [];
          let i = this.hasMore,
            a = this.cursor;
          for (let h = 0; h < kt; h++) {
            const f = await g.bapi.searchRoomMessages(
              this.searchText,
              a,
              this.buildOptions(),
            );
            if (t !== this.generation) return;
            const k = this.sort === "oldest" ? f.items : [...f.items].reverse();
            for (const p of k)
              for (const w of Vt(p, this.tab))
                this.seenKeys.has(w.key) ||
                  (this.seenKeys.add(w.key), n.push(w));
            i = f.hasMore;
            const D = this.sort === "oldest" ? f.newestCursor : f.oldestCursor;
            if (
              ((a = D
                ? {
                    cursor: D,
                    direction: this.sort === "oldest" ? "after" : "before",
                  }
                : void 0),
              !i || !a || n.length > 0)
            )
              break;
          }
          const l = new Map();
          for (const h of n) {
            const f = l.get(h.accountID) ?? [];
            (f.push(h.threadID), l.set(h.accountID, f));
          }
          if (
            (await Promise.all(
              Array.from(l, ([h, f]) =>
                g.accountsStore.getAccount(h)?.loadThreadsIfMissing(pe(f)),
              ),
            ),
            t !== this.generation)
          )
            return;
          const d = n.filter(
              (h) =>
                !g.accountsStore
                  .getAccount(h.accountID)
                  ?.inboxes[_e.REQUESTS].threadsMap.has(h.threadID),
            ),
            r = d.length === 0 && i && !!a;
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
              (this.hasMore = i),
              (this.cursor = a),
              (this.isLoading = r),
              this.advanceViewerAfterLoad &&
                (this.viewerIndex != null &&
                this.viewerIndex < this.items.length - 1
                  ? (this.viewerIndex++, (this.advanceViewerAfterLoad = !1))
                  : i || (this.advanceViewerAfterLoad = !1)));
          }),
            r &&
              setTimeout(() => {
                t === this.generation &&
                  (A(() => {
                    this.isLoading = !1;
                  }),
                  this.loadMore());
              }, 0));
        } catch (n) {
          (logger.error("MediaViewer: failed to load media", n),
            A(() => {
              t === this.generation && (this.isLoading = !1);
            }));
        }
      }),
      (this.getThread = (t) => g.getThread(t.accountID, t.threadID)),
      (this.openViewer = (t) => {
        const n = this.items.findIndex((i) => i.key === t);
        n !== -1 &&
          ((this.viewerIndex = n), (this.advanceViewerAfterLoad = !1));
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
        const n = this.viewerIndex,
          i =
            n == null
              ? 0
              : this.items.slice(0, n).filter((l) => t.has(l.key)).length;
        this.items = this.items.filter((l) => !t.has(l.key));
        const a = W();
        ((this.dateGroups = E(this.items, a)),
          (this.dateGroupContextKey = a.key));
        for (const l of t)
          (this.selectedKeys.delete(l), this.seenKeys.delete(l));
        n != null &&
          (this.viewerIndex = this.items.length
            ? Math.min(n - i, this.items.length - 1)
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
      limit: jt,
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
      n = 0;
    for (const { attachment: i, link: a } of this.selectedItems)
      a || (i?.fileSize ? (t += i.fileSize) : n++);
    return { bytes: t, unknownCount: n };
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
m([y], u.prototype, "setTab", 2);
m([y], u.prototype, "setSentBy", 2);
m([y], u.prototype, "setSort", 2);
m([y], u.prototype, "setSearchText", 2);
m([y], u.prototype, "reset", 1);
m([y], u.prototype, "loadMore", 2);
m([y], u.prototype, "openViewer", 2);
m([y], u.prototype, "closeViewer", 2);
m([C], u.prototype, "viewerItem", 1);
m([C], u.prototype, "hasNextViewerItem", 1);
m([C], u.prototype, "hasPreviousViewerItem", 1);
m([y], u.prototype, "viewerNext", 2);
m([y], u.prototype, "viewerPrev", 2);
m([y], u.prototype, "setSelectMode", 2);
m([y], u.prototype, "toggleSelected", 2);
m([y], u.prototype, "selectAll", 2);
m([C], u.prototype, "selectedItems", 1);
m([C], u.prototype, "selectionSize", 1);
m([y], u.prototype, "removeItems", 2);
class $t extends we {
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
        s.jsx(Mt, {
          store: this.store,
          "data-sentry-element": "MediaViewer",
          "data-sentry-source-file": "MediaViewerBrowserWindow.tsx",
        }),
        s.jsx(ge, {
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
export { $t as MediaViewerBrowserWindow };
//# sourceMappingURL=MediaViewerBrowserWindow-CP0n2tAL.js.map
