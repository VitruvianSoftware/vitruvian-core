import {
  de as _,
  cs as J,
  dg as Q,
  dp as W,
  cT as A,
  cF as e,
  ai as Z,
  br as S,
  aH as ee,
  R as te,
  aO as q,
  ae as se,
  b1 as oe,
} from "./App-BHgTsVmv.js";
import { y as ne } from "./sentry-common-BNqrY_yc.js";
import { ac as L, cK as g, a2 as C, a1 as m } from "./matrix-util-8DbIGEm-.js";
import "./index-Cw3pknxT.js";
import "./index-Ch31Akxs.js";
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
    var i = new s.Error().stack;
    i &&
      ((s._sentryDebugIds = s._sentryDebugIds || {}),
      (s._sentryDebugIds[i] = "68c543e7-36cb-4a0a-9af5-fa4540c83e43"),
      (s._sentryDebugIdIdentifier =
        "sentry-dbid-68c543e7-36cb-4a0a-9af5-fa4540c83e43"));
  } catch {}
})();
let N = 0,
  E = null,
  P = { x: 0, y: 0, width: 0, height: 0 },
  I = 0,
  b = null;
function k(s) {
  (s !== void 0 && s !== I) ||
    (N && (cancelAnimationFrame(N), (N = 0)), (E = null));
}
function B() {
  (k(), L.closeVotesPopover());
}
function ie(s) {
  const i = () => {
    if (s !== I) return;
    const t = E;
    if (!t) return;
    const n = t.getBoundingClientRect();
    if (J(n, window)) {
      B();
      return;
    }
    (Q(P, n) ||
      ((P = { x: n.x, y: n.y, width: n.width, height: n.height }),
      L.updateVotesPopoverPosition(P)),
      (N = requestAnimationFrame(i)));
  };
  N = requestAnimationFrame(i);
}
function ce({ preferredEdge: s = "bottom", onDismiss: i } = {}) {
  const [t, n] = _.useState(!1),
    r = _.useRef(i);
  r.current = i;
  const a = _.useCallback(() => n(!1), []),
    u = _.useCallback(
      (f, v) => {
        (k(), b && b !== a && b(), (b = a));
        const d = ++I,
          p = f.getBoundingClientRect(),
          w = { x: p.x, y: p.y, width: p.width, height: p.height };
        ((P = w),
          (E = f),
          L.showVotesPopover(v, w, s, (R) => {
            d === I &&
              R === "dismiss" &&
              (k(d), (b = null), n(!1), r.current?.());
          }),
          n(!0),
          ie(d));
      },
      [s, a],
    ),
    j = _.useCallback(() => {
      (B(), (b = null), n(!1));
    }, []);
  return { show: u, close: j, isOpen: t };
}
const ae = 100;
function U(s) {
  return new Set(s.answers.flatMap((i) => s.responses[i.id] ?? [])).size;
}
function D(s, i) {
  const t = (n) => {
    const r = i.getParticipant(n)?.imgURL;
    return {
      id: n,
      name: i.getParticipantDisplayName(n) ?? n,
      imgURL: r ? W(r) : void 0,
    };
  };
  return s.answers.map((n) => {
    const r = s.responses[n.id] ?? [];
    return {
      id: n.id,
      label: n.text,
      count: r.length,
      voters: r.slice(0, ae).map(t),
    };
  });
}
const le = "_modal_1pvrz_1",
  re = "_titleBar_1pvrz_11",
  de = "_isMac_1pvrz_22",
  pe = "_card_1pvrz_26",
  ue = "_container_1pvrz_36",
  _e = "_title_1pvrz_11",
  ve = "_section_1pvrz_56",
  me = "_sectionHeader_1pvrz_64",
  he = "_sectionLabel_1pvrz_75",
  fe = "_sectionCount_1pvrz_84",
  xe = "_voterList_1pvrz_94",
  be = "_voterRow_1pvrz_105",
  ge = "_voterAvatar_1pvrz_112",
  Ne = "_voterName_1pvrz_120",
  je = "_voterMore_1pvrz_129",
  l = {
    modal: le,
    titleBar: re,
    isMac: de,
    card: pe,
    container: ue,
    title: _e,
    section: ve,
    sectionHeader: me,
    sectionLabel: he,
    sectionCount: fe,
    voterList: xe,
    voterRow: be,
    voterAvatar: ge,
    voterName: Ne,
    voterMore: je,
  };
A(({ thread: s, messageID: i }) => {
  const t = s.messages.get(i)?.extra?.poll,
    n = _.useMemo(() => (t ? D(t, s) : []), [t, s]),
    r = _.useMemo(() => (t ? U(t) : 0), [t]);
  return t
    ? e.jsxs(Z, {
        className: l.modal,
        children: [
          e.jsx("div", {
            className: S(l.titleBar, { [l.isMac]: ne }),
            children: g(C("%d vote", "%d votes", r), r),
          }),
          e.jsx("div", {
            className: l.card,
            children: e.jsxs("div", {
              className: l.container,
              children: [
                e.jsx("span", {
                  className: l.title,
                  children: t.question || m("Poll"),
                }),
                n.map((a) =>
                  e.jsxs(
                    "div",
                    {
                      className: l.section,
                      children: [
                        e.jsxs("div", {
                          className: l.sectionHeader,
                          children: [
                            e.jsx("span", {
                              className: l.sectionLabel,
                              children: a.label,
                            }),
                            e.jsx("span", {
                              className: l.sectionCount,
                              children: a.count,
                            }),
                          ],
                        }),
                        a.voters.length > 0 &&
                          e.jsxs("div", {
                            className: l.voterList,
                            children: [
                              a.voters.map((u) =>
                                e.jsxs(
                                  "div",
                                  {
                                    className: l.voterRow,
                                    children: [
                                      e.jsx("div", {
                                        className: l.voterAvatar,
                                        children: u.imgURL
                                          ? e.jsx(ee, {
                                              src: u.imgURL,
                                              size: 28,
                                              loading: "lazy",
                                            })
                                          : e.jsx(te, {
                                              username: u.name,
                                              letterSpacing: "0.5px",
                                            }),
                                      }),
                                      e.jsx("span", {
                                        className: l.voterName,
                                        children: u.name,
                                      }),
                                    ],
                                  },
                                  u.id,
                                ),
                              ),
                              a.count > a.voters.length &&
                                e.jsx("span", {
                                  className: l.voterMore,
                                  children: g(
                                    m("+%d more"),
                                    a.count - a.voters.length,
                                  ),
                                }),
                            ],
                          }),
                      ],
                    },
                    a.id,
                  ),
                ),
              ],
            }),
          }),
        ],
      })
    : null;
});
const we = "_wrapper_19pi4_1",
  Re = "_out_19pi4_21",
  Ve = "_head_19pi4_31",
  ye = "_question_19pi4_38",
  Se = "_subtitle_19pi4_46",
  Pe = "_subtitleIcon_19pi4_57",
  Ie = "_options_19pi4_62",
  Me = "_spread_19pi4_71",
  ze = "_option_19pi4_62",
  Ce = "_closed_19pi4_94",
  ke = "_label_19pi4_98",
  Ae = "_fill_19pi4_102",
  Le = "_voted_19pi4_111",
  Ee = "_optRow_19pi4_122",
  Fe = "_check_19pi4_139",
  Te = "_multi_19pi4_147",
  Oe = "_name_19pi4_166",
  qe = "_rightGroup_19pi4_176",
  Be = "_voterStack_19pi4_183",
  Ue = "_voterAvatar_19pi4_188",
  De = "_count_19pi4_200",
  $e = "_foot_19pi4_209",
  He = "_footNote_19pi4_216",
  Ge = "_plainVotes_19pi4_223",
  Ke = "_hiddenResults_19pi4_231",
  Xe = "_viewVotesBtn_19pi4_239",
  Ye = "_viewVotesChevron_19pi4_252",
  o = {
    wrapper: we,
    out: Re,
    head: Ve,
    question: ye,
    subtitle: Se,
    subtitleIcon: Pe,
    options: Ie,
    spread: Me,
    option: ze,
    closed: Ce,
    label: ke,
    fill: Ae,
    voted: Le,
    optRow: Ee,
    check: Fe,
    multi: Te,
    name: Oe,
    rightGroup: qe,
    voterStack: Be,
    voterAvatar: Ue,
    count: De,
    foot: $e,
    footNote: He,
    plainVotes: Ge,
    hiddenResults: Ke,
    viewVotesBtn: Xe,
    viewVotesChevron: Ye,
  },
  Je = A(({ voterIDs: s, thread: i }) => {
    const t = s.slice(-3);
    return e.jsx("div", {
      className: o.voterStack,
      children: t.map((n) =>
        e.jsx(
          "div",
          {
            className: o.voterAvatar,
            children: e.jsx(oe, {
              user: i.getParticipant(n),
              size: 20,
              letterSpacing: "0.5px",
            }),
          },
          n,
        ),
      ),
    });
  }),
  it = A(({ message: s, thread: i }) => {
    const t = s.extra?.poll,
      [n, r] = _.useState(!1),
      a = _.useRef(null),
      u = ce({ preferredEdge: s.isSender ? "left" : "right" }),
      j = i.threadForMessage(s),
      f = j.currentUserID,
      v = _.useMemo(() => (t ? U(t) : 0), [t]),
      d = _.useMemo(
        () =>
          t && f
            ? Object.entries(t.responses)
                .filter(([, c]) => c.includes(f))
                .map(([c]) => c)
            : [],
        [t, f],
      );
    if (!t) return null;
    const p = t.kind === "disclosed" || t.isFinal,
      w = !s.extra?.eventID,
      R = !t.isFinal && !n && !w && j.canVoteOnPolls,
      V = t.maxSelections !== 1,
      M = t.question || m("Poll"),
      F = V && t.maxSelections != null && d.length >= t.maxSelections,
      $ = p ? v > 0 : d.length > 0,
      T = g(C("%d vote", "%d votes", v), v),
      H = t.isFinal
        ? m("Poll ended")
        : V
          ? m("Select one or more options")
          : m("Select one option"),
      G = async (c) => {
        if (R && !(F && !d.includes(c))) {
          r(!0);
          try {
            let x;
            (V
              ? (x = d.includes(c) ? d.filter((h) => h !== c) : [...d, c])
              : (x = d.includes(c) ? [] : [c]),
              await i.votePoll(s.id, x).catch(() => {}));
          } finally {
            r(!1);
          }
        }
      },
      K = () => {
        {
          const c = { question: M, totalVotes: v, sections: D(t, i) };
          u.isOpen ? u.close() : a.current && u.show(a.current, c);
        }
      };
    return e.jsxs("section", {
      className: S(o.wrapper, { [o.out]: s.isSender, [o.closed]: t.isFinal }),
      role: "group",
      "aria-label": M,
      children: [
        e.jsxs("header", {
          className: o.head,
          children: [
            e.jsx("span", { className: o.question, children: M }),
            e.jsxs("span", {
              className: o.subtitle,
              children: [
                e.jsx(q, {
                  name: t.isFinal ? "stop" : "poll-options",
                  width: 16,
                  height: 16,
                  className: o.subtitleIcon,
                }),
                H,
              ],
            }),
          ],
        }),
        e.jsx("ul", {
          className: S(o.options, { [o.spread]: $ }),
          children: t.answers.map((c) => {
            const x = t.responses[c.id] ?? [],
              h = x.length,
              O = v > 0 ? Math.trunc((h / v) * 100) : 0,
              y = d.includes(c.id),
              X = p ? h > 0 : y,
              Y = p ? O : 100,
              z = !R || (F && !y);
            return e.jsx(
              "li",
              {
                children: e.jsxs("button", {
                  type: "button",
                  "aria-pressed": y,
                  "aria-label": p
                    ? g(
                        m("Vote for %1$s, %2$d%%, %3$s"),
                        c.text,
                        O,
                        g(C("%d vote", "%d votes", h), h),
                      )
                    : g(m("Vote for %s, results hidden"), c.text),
                  "aria-disabled": z ? !0 : void 0,
                  tabIndex: z ? -1 : void 0,
                  disabled: z,
                  className: S(o.option, { [o.voted]: y, [o.multi]: V }),
                  onClick: () => G(c.id),
                  children: [
                    e.jsx("div", {
                      className: o.fill,
                      style: { width: X ? `${Y}%` : 0 },
                    }),
                    e.jsxs("div", {
                      className: o.optRow,
                      children: [
                        e.jsxs("div", {
                          className: o.label,
                          children: [
                            e.jsx("div", { className: o.check }),
                            e.jsx("span", {
                              className: o.name,
                              children: c.text,
                            }),
                          ],
                        }),
                        p &&
                          h > 0 &&
                          e.jsxs("div", {
                            className: o.rightGroup,
                            children: [
                              e.jsx(Je, { voterIDs: x, thread: i }),
                              e.jsx("span", {
                                className: o.count,
                                children: h,
                              }),
                            ],
                          }),
                      ],
                    }),
                  ],
                }),
              },
              c.id,
            );
          }),
        }),
        (s.isErrored || s.isRetrying) &&
          e.jsx("div", {
            className: o.foot,
            children: e.jsx(se, { mssError: s.sendStatus?.message }),
          }),
        p &&
          v > 0 &&
          e.jsx("div", {
            className: o.foot,
            children: e.jsxs("button", {
              ref: a,
              type: "button",
              className: o.viewVotesBtn,
              onClick: K,
              children: [
                T,
                e.jsx(q, {
                  name: "chevron-right",
                  width: 16,
                  height: 16,
                  className: o.viewVotesChevron,
                }),
              ],
            }),
          }),
        !p &&
          e.jsxs("div", {
            className: o.footNote,
            children: [
              v > 0 && e.jsx("span", { className: o.plainVotes, children: T }),
              e.jsx("span", {
                className: o.hiddenResults,
                children: m("Results will be displayed when the poll ends"),
              }),
            ],
          }),
      ],
    });
  });
export { it as Poll };
//# sourceMappingURL=Poll-C0teb1By.js.map
