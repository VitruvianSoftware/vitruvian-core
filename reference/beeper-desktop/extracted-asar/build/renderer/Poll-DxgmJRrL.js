import {
  dk as p,
  cx as J,
  dm as Q,
  dv as W,
  cY as L,
  cK as e,
  am as Z,
  bw as y,
  aM as ee,
  S as te,
  aT as O,
  ai as oe,
  b6 as se,
} from "./App-CsJiApxN.js";
import { w as le } from "./sentry-common-BxRELKId.js";
import { ad as E, cN as b, a3 as C, a2 as h } from "./matrix-util-Cr_UwXbj.js";
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
    var n = new o.Error().stack;
    n &&
      ((o._sentryDebugIds = o._sentryDebugIds || {}),
      (o._sentryDebugIds[n] = "58590b9e-de18-4dd1-ab86-469c78a45b94"),
      (o._sentryDebugIdIdentifier =
        "sentry-dbid-58590b9e-de18-4dd1-ab86-469c78a45b94"));
  } catch {}
})();
let N = 0,
  T = null,
  S = { x: 0, y: 0, width: 0, height: 0 },
  M = 0,
  P = null;
function A(o) {
  (o !== void 0 && o !== M) ||
    (N && (cancelAnimationFrame(N), (N = 0)), (T = null));
}
function U() {
  (A(), E.closeVotesPopover());
}
function ne(o) {
  const n = () => {
    if (o !== M) return;
    const t = T;
    if (!t) return;
    const l = t.getBoundingClientRect();
    if (J(l, window)) {
      U();
      return;
    }
    (Q(S, l) ||
      ((S = { x: l.x, y: l.y, width: l.width, height: l.height }),
      E.updateVotesPopoverPosition(S)),
      (N = requestAnimationFrame(n)));
  };
  N = requestAnimationFrame(n);
}
function ie({ preferredEdge: o = "bottom", onDismiss: n } = {}) {
  const [t, l] = p.useState(!1),
    r = p.useRef(n);
  r.current = n;
  const c = p.useCallback(() => l(!1), []),
    m = p.useCallback(
      (f, v) => {
        (A(), P && P !== c && P(), (P = c));
        const d = ++M,
          u = f.getBoundingClientRect(),
          V = { x: u.x, y: u.y, width: u.width, height: u.height };
        ((S = V),
          (T = f),
          E.showVotesPopover(v, V, o, (j) => {
            d === M &&
              j === "dismiss" &&
              (A(d), (P = null), l(!1), r.current?.());
          }),
          l(!0),
          ne(d));
      },
      [o, c],
    ),
    g = p.useCallback(() => {
      (U(), (P = null), l(!1));
    }, []);
  return { show: m, close: g, isOpen: t };
}
const ce = 100;
function D(o) {
  return new Set(o.answers.flatMap((n) => o.responses[n.id] ?? [])).size;
}
function $(o, n) {
  const t = (l) => {
    const r = n.getParticipant(l)?.imgURL;
    return {
      id: l,
      name: n.getParticipantDisplayName(l) ?? l,
      imgURL: r ? W(r) : void 0,
    };
  };
  return o.answers.map((l) => {
    const r = o.responses[l.id] ?? [];
    return {
      id: l.id,
      label: l.text,
      count: r.length,
      voters: r.slice(0, ce).map(t),
    };
  });
}
const ae = "PollVotes-module__modal",
  re = "PollVotes-module__titleBar",
  de = "PollVotes-module__isMac",
  ue = "PollVotes-module__card",
  me = "PollVotes-module__container",
  pe = "PollVotes-module__title",
  ve = "PollVotes-module__section",
  he = "PollVotes-module__sectionHeader",
  _e = "PollVotes-module__sectionLabel",
  fe = "PollVotes-module__sectionCount",
  xe = "PollVotes-module__voterList",
  Pe = "PollVotes-module__voterRow",
  be = "PollVotes-module__voterAvatar",
  Ne = "PollVotes-module__voterName",
  ge = "PollVotes-module__voterMore",
  a = {
    modal: ae,
    titleBar: re,
    isMac: de,
    card: ue,
    container: me,
    title: pe,
    section: ve,
    sectionHeader: he,
    sectionLabel: _e,
    sectionCount: fe,
    voterList: xe,
    voterRow: Pe,
    voterAvatar: be,
    voterName: Ne,
    voterMore: ge,
  };
L(({ thread: o, messageID: n }) => {
  const t = o.messages.get(n)?.extra?.poll,
    l = p.useMemo(() => (t ? $(t, o) : []), [t, o]),
    r = p.useMemo(() => (t ? D(t) : 0), [t]);
  return t
    ? e.jsxs(Z, {
        className: a.modal,
        children: [
          e.jsx("div", {
            className: y(a.titleBar, { [a.isMac]: le }),
            children: b(C("%d vote", "%d votes", r), r),
          }),
          e.jsx("div", {
            className: a.card,
            children: e.jsxs("div", {
              className: a.container,
              children: [
                e.jsx("span", {
                  className: a.title,
                  children: t.question || h("Poll"),
                }),
                l.map((c) =>
                  e.jsxs(
                    "div",
                    {
                      className: a.section,
                      children: [
                        e.jsxs("div", {
                          className: a.sectionHeader,
                          children: [
                            e.jsx("span", {
                              className: a.sectionLabel,
                              children: c.label,
                            }),
                            e.jsx("span", {
                              className: a.sectionCount,
                              children: c.count,
                            }),
                          ],
                        }),
                        c.voters.length > 0 &&
                          e.jsxs("div", {
                            className: a.voterList,
                            children: [
                              c.voters.map((m) =>
                                e.jsxs(
                                  "div",
                                  {
                                    className: a.voterRow,
                                    children: [
                                      e.jsx("div", {
                                        className: a.voterAvatar,
                                        children: m.imgURL
                                          ? e.jsx(ee, {
                                              src: m.imgURL,
                                              size: 28,
                                              loading: "lazy",
                                            })
                                          : e.jsx(te, {
                                              username: m.name,
                                              letterSpacing: "0.5px",
                                            }),
                                      }),
                                      e.jsx("span", {
                                        className: a.voterName,
                                        children: m.name,
                                      }),
                                    ],
                                  },
                                  m.id,
                                ),
                              ),
                              c.count > c.voters.length &&
                                e.jsx("span", {
                                  className: a.voterMore,
                                  children: b(
                                    h("+%d more"),
                                    c.count - c.voters.length,
                                  ),
                                }),
                            ],
                          }),
                      ],
                    },
                    c.id,
                  ),
                ),
              ],
            }),
          }),
        ],
      })
    : null;
});
const Ve = "Poll-module__wrapper",
  je = "Poll-module__out",
  we = "Poll-module__head",
  Re = "Poll-module__question",
  ye = "Poll-module__subtitle",
  Se = "Poll-module__subtitleIcon",
  Me = "Poll-module__options",
  Ie = "Poll-module__spread",
  ke = "Poll-module__option",
  Ce = "Poll-module__closed",
  Ae = "Poll-module__label",
  Le = "Poll-module__fill",
  Ee = "Poll-module__voted",
  Te = "Poll-module__optRow",
  Fe = "Poll-module__check",
  qe = "Poll-module__multi",
  Be = "Poll-module__name",
  Oe = "Poll-module__rightGroup",
  Ue = "Poll-module__voterStack",
  De = "Poll-module__voterAvatar",
  $e = "Poll-module__count",
  ze = "Poll-module__foot",
  Ge = "Poll-module__footNote",
  He = "Poll-module__plainVotes",
  Ye = "Poll-module__hiddenResults",
  Ke = "Poll-module__viewVotesBtn",
  Xe = "Poll-module__viewVotesChevron",
  s = {
    wrapper: Ve,
    out: je,
    head: we,
    question: Re,
    subtitle: ye,
    subtitleIcon: Se,
    options: Me,
    spread: Ie,
    option: ke,
    closed: Ce,
    label: Ae,
    fill: Le,
    voted: Ee,
    optRow: Te,
    check: Fe,
    multi: qe,
    name: Be,
    rightGroup: Oe,
    voterStack: Ue,
    voterAvatar: De,
    count: $e,
    foot: ze,
    footNote: Ge,
    plainVotes: He,
    hiddenResults: Ye,
    viewVotesBtn: Ke,
    viewVotesChevron: Xe,
  },
  Je = L(({ voterIDs: o, thread: n }) => {
    const t = o.slice(-3);
    return e.jsx("div", {
      className: s.voterStack,
      children: t.map((l) =>
        e.jsx(
          "div",
          {
            className: s.voterAvatar,
            children: e.jsx(se, {
              user: n.getParticipant(l),
              size: 20,
              letterSpacing: "0.5px",
            }),
          },
          l,
        ),
      ),
    });
  }),
  it = L(({ message: o, thread: n }) => {
    const t = o.extra?.poll,
      [l, r] = p.useState(!1),
      c = p.useRef(null),
      m = ie({ preferredEdge: o.isSender ? "left" : "right" }),
      g = n.threadForMessage(o),
      f = g.currentUserID,
      v = p.useMemo(() => (t ? D(t) : 0), [t]),
      d = p.useMemo(
        () =>
          t && f
            ? Object.entries(t.responses)
                .filter(([, i]) => i.includes(f))
                .map(([i]) => i)
            : [],
        [t, f],
      );
    if (!t) return null;
    const u = t.kind === "disclosed" || t.isFinal,
      V = !o.extra?.eventID,
      j = !t.isFinal && !l && !V && g.canVoteOnPolls,
      w = t.maxSelections !== 1,
      I = t.question || h("Poll"),
      F = w && t.maxSelections != null && d.length >= t.maxSelections,
      z = u ? v > 0 : d.length > 0,
      q = b(C("%d vote", "%d votes", v), v),
      G = t.isFinal
        ? h("Poll ended")
        : w
          ? h("Select one or more options")
          : h("Select one option"),
      H = async (i) => {
        if (j && !(F && !d.includes(i))) {
          r(!0);
          try {
            let x;
            (w
              ? (x = d.includes(i) ? d.filter((_) => _ !== i) : [...d, i])
              : (x = d.includes(i) ? [] : [i]),
              await n.votePoll(o.id, x).catch(() => {}));
          } finally {
            r(!1);
          }
        }
      },
      Y = () => {
        {
          const i = { question: I, totalVotes: v, sections: $(t, n) };
          m.isOpen ? m.close() : c.current && m.show(c.current, i);
        }
      };
    return e.jsxs("section", {
      className: y(s.wrapper, { [s.out]: o.isSender, [s.closed]: t.isFinal }),
      role: "group",
      "aria-label": I,
      children: [
        e.jsxs("header", {
          className: s.head,
          children: [
            e.jsx("span", { className: s.question, children: I }),
            e.jsxs("span", {
              className: s.subtitle,
              children: [
                e.jsx(O, {
                  name: t.isFinal ? "stop" : "poll-options",
                  width: 16,
                  height: 16,
                  className: s.subtitleIcon,
                }),
                G,
              ],
            }),
          ],
        }),
        e.jsx("ul", {
          className: y(s.options, { [s.spread]: z }),
          children: t.answers.map((i) => {
            const x = t.responses[i.id] ?? [],
              _ = x.length,
              B = v > 0 ? Math.trunc((_ / v) * 100) : 0,
              R = d.includes(i.id),
              K = u ? _ > 0 : R,
              X = u ? B : 100,
              k = !j || (F && !R);
            return e.jsx(
              "li",
              {
                children: e.jsxs("button", {
                  type: "button",
                  "aria-pressed": R,
                  "aria-label": u
                    ? b(
                        h("Vote for %1$s, %2$d%%, %3$s"),
                        i.text,
                        B,
                        b(C("%d vote", "%d votes", _), _),
                      )
                    : b(h("Vote for %s, results hidden"), i.text),
                  "aria-disabled": k ? !0 : void 0,
                  tabIndex: k ? -1 : void 0,
                  disabled: k,
                  className: y(s.option, { [s.voted]: R, [s.multi]: w }),
                  onClick: () => H(i.id),
                  children: [
                    e.jsx("div", {
                      className: s.fill,
                      style: { width: K ? `${X}%` : 0 },
                    }),
                    e.jsxs("div", {
                      className: s.optRow,
                      children: [
                        e.jsxs("div", {
                          className: s.label,
                          children: [
                            e.jsx("div", { className: s.check }),
                            e.jsx("span", {
                              className: s.name,
                              children: i.text,
                            }),
                          ],
                        }),
                        u &&
                          _ > 0 &&
                          e.jsxs("div", {
                            className: s.rightGroup,
                            children: [
                              e.jsx(Je, { voterIDs: x, thread: n }),
                              e.jsx("span", {
                                className: s.count,
                                children: _,
                              }),
                            ],
                          }),
                      ],
                    }),
                  ],
                }),
              },
              i.id,
            );
          }),
        }),
        (o.isErrored || o.isRetrying) &&
          e.jsx("div", {
            className: s.foot,
            children: e.jsx(oe, { mssError: o.sendStatus?.message }),
          }),
        u &&
          v > 0 &&
          e.jsx("div", {
            className: s.foot,
            children: e.jsxs("button", {
              ref: c,
              type: "button",
              className: s.viewVotesBtn,
              onClick: Y,
              children: [
                q,
                e.jsx(O, {
                  name: "chevron-right",
                  width: 16,
                  height: 16,
                  className: s.viewVotesChevron,
                }),
              ],
            }),
          }),
        !u &&
          e.jsxs("div", {
            className: s.footNote,
            children: [
              v > 0 && e.jsx("span", { className: s.plainVotes, children: q }),
              e.jsx("span", {
                className: s.hiddenResults,
                children: h("Results will be displayed when the poll ends"),
              }),
            ],
          }),
      ],
    });
  });
export { it as Poll };
//# sourceMappingURL=Poll-DxgmJRrL.js.map
