import {
  cF as a,
  aL as O,
  de as s,
  b5 as V,
  eh as B,
  en as Z,
  d$ as z,
  br as J,
} from "./App-BHgTsVmv.js";
import { a1 as _, cK as Q } from "./matrix-util-8DbIGEm-.js";
import "./sentry-common-BNqrY_yc.js";
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
    var n = new t.Error().stack;
    n &&
      ((t._sentryDebugIds = t._sentryDebugIds || {}),
      (t._sentryDebugIds[n] = "998f9d82-7837-4802-ba7b-001c528dc44f"),
      (t._sentryDebugIdIdentifier =
        "sentry-dbid-998f9d82-7837-4802-ba7b-001c528dc44f"));
  } catch {}
})();
const L = 10,
  X = "g8HMsExhORgAvpsm5uAcse04Y8hTtC5CAsvYxbFTU2Lw038lTWpmgg1R569ZEf4k",
  ee = (t) => ({
    id: t.id,
    title: t.title || t.content_description,
    thumbnail: {
      width: t.media_formats.tinymp4.dims[0],
      height: t.media_formats.tinymp4.dims[1],
      url: t.media_formats.tinymp4.url,
    },
    gif: {
      url: t.media_formats.gif.url,
      width: parseInt(t.media_formats.gif.dims[0]),
      height: parseInt(t.media_formats.gif.dims[1]),
    },
    mp4: {
      url: t.media_formats.mp4.url,
      width: parseInt(t.media_formats.mp4.dims[0]),
      height: parseInt(t.media_formats.mp4.dims[1]),
    },
  }),
  te = "https://api.klipy.com/v2",
  se = {
    key: X,
    limit: L.toString(),
    contentfilter: "high",
    media_filter: "gif,tinygif,mp4,tinymp4",
  };
async function F(t, n = {}) {
  const u = new URLSearchParams({ ...se, ...n }),
    i = `${te}${t}?${u}`,
    c = await (await fetch(i)).json();
  return [c.results, c.next];
}
async function ne({ filter: t, next: n }) {
  return t ? F("/search", { q: t, pos: n }) : [[], null];
}
async function re({ next: t }) {
  return F("/featured", { pos: t });
}
const ae = Array(L)
    .fill(0)
    .map((t, n) =>
      a.jsx(
        O,
        { height: 200, width: 300, style: { minWidth: 300 } },
        `skeleton-${n}`,
      ),
    ),
  he = ({ onSelect: t, onClose: n }) => {
    const u = s.useRef(null),
      i = s.useRef(null),
      w = s.useRef([]),
      [c, k] = s.useState(!1),
      [f, G] = s.useState([]),
      [P, v] = s.useState(""),
      [C, E] = s.useState(!0),
      [R, j] = s.useState(),
      [o, T] = s.useState(null),
      [d, N] = s.useState(""),
      M = s.useContext(V),
      A = () => {
        if (o === null) return;
        const e = f[o];
        e && (t(e), n());
      },
      m = s.useCallback(
        async ({
          filter: e,
          more: r = !0,
          paginationPos: l = null,
          existingGifs: y = [],
        }) => {
          if (!r) return y;
          k(!0);
          const S = e ? ne : re,
            h = { next: l ?? "" };
          e && (h.filter = e);
          try {
            const [p, b] = await S(h);
            v(b);
            const q = y.concat(p.map(ee));
            b || E(!1);
            const H = B(q, "id");
            G(H);
          } catch (p) {
            j(p);
          } finally {
            k(!1);
          }
        },
        [],
      ),
      [D, I] = Z((e) => m(e), 500),
      x = s.useCallback(
        z(function (e) {
          return m(e);
        }, 1e3),
        [m],
      );
    s.useEffect(
      () => (
        d ? D({ filter: d }) : (I(), m({})),
        () => {
          (I(), x.cancel?.());
        }
      ),
      [d, D, m, I, x],
    );
    const g = (e) => {
        (T(e), e != null && w.current[e]?.scrollIntoView());
      },
      K = (e) => {
        const r = u.current;
        switch (e.key) {
          case "ArrowUp": {
            e.preventDefault();
            const l = r?.value.length;
            (r?.setSelectionRange(l ?? null, l ?? null), r?.focus(), g(null));
            break;
          }
          case "ArrowDown":
            o === null && (e.preventDefault(), g(0));
            break;
          case "ArrowLeft":
            o !== null && (g(Math.max(0, o - 1)), e.preventDefault());
            break;
          case "ArrowRight":
            o !== null &&
              (g(Math.min(f.length - 1, o + 1)), e.preventDefault());
            break;
          case "Enter":
            A();
            break;
          case "Escape":
            (n(), M.focusMessageInput(), e.stopPropagation());
            break;
        }
      },
      W = (e) => () => {
        (T(e), i.current?.children[e]?.scrollIntoView());
      },
      U = () => {
        requestAnimationFrame(() => {
          const e = i.current;
          if (!e) return;
          const r = e.scrollWidth - e.clientWidth;
          e.scrollLeft >= r - 100 &&
            C &&
            x({ filter: d, paginationPos: P, existingGifs: f });
        });
      },
      Y = () => {
        if (f.length === 0) {
          if (!c && R)
            return a.jsx("div", {
              className: "gif-carousel empty",
              children: Q(
                _("Something went wrong (%s). Try searching something else?"),
                R.message,
              ),
            });
          if (!c)
            return a.jsx("div", {
              className: "gif-carousel empty",
              children: _("No results. Try searching something else?"),
            });
        }
        return a.jsxs("div", {
          ref: i,
          className: "gif-carousel",
          onScroll: U,
          "data-sentry-component": "renderCarousel",
          "data-sentry-source-file": "GifPicker.tsx",
          children: [
            f.map((e, r) => {
              const { width: l, height: y, url: S } = e.thumbnail,
                h = 215,
                p = (h / parseInt(y)) * parseInt(l);
              return a.jsx(
                "video",
                {
                  tabIndex: 0,
                  className: J("gif", { selected: r === o }),
                  height: h,
                  width: p,
                  src: S,
                  ref: (b) => {
                    w.current[r] = b ?? null;
                  },
                  autoPlay: !0,
                  loop: !0,
                  muted: !0,
                  controls: !1,
                  onClick: A,
                  onFocus: W(r),
                },
                e.id,
              );
            }),
            c &&
              a.jsx("div", {
                style: { paddingLeft: 14, display: "flex" },
                children: ae,
              }),
          ],
        });
      },
      $ = (e) => {
        (i.current && (i.current.scrollLeft = 0), N(e.target.value), E(!0));
      };
    return a.jsxs(a.Fragment, {
      children: [
        a.jsx("input", {
          ref: u,
          className: "gif-search-input",
          value: d,
          placeholder: _("Search KLIPY..."),
          autoFocus: !0,
          onChange: $,
          onKeyDown: K,
        }),
        Y(),
      ],
    });
  };
export { ae as SkeletonLoader, he as default };
//# sourceMappingURL=GifPicker-CAQ4lz2B.js.map
