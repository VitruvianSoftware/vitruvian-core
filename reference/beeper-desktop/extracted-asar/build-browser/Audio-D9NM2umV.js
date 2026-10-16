import {
  cT as R,
  el as G,
  cF as t,
  as as K,
  at as J,
  de as a,
  b5 as Q,
  et as Z,
  a9 as ee,
  aO as te,
  au as se,
  br as N,
  q as ae,
  o as ne,
  ch as oe,
} from "./App-BHgTsVmv.js";
import { cA as j, a5 as W, aN as E, a1 as B } from "./matrix-util-8DbIGEm-.js";
import { r as re } from "./sentry-common-BNqrY_yc.js";
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
    var c = new s.Error().stack;
    c &&
      ((s._sentryDebugIds = s._sentryDebugIds || {}),
      (s._sentryDebugIds[c] = "de4aac26-8fa6-4892-b535-af57764fcc2f"),
      (s._sentryDebugIdIdentifier =
        "sentry-dbid-de4aac26-8fa6-4892-b535-af57764fcc2f"));
  } catch {}
})();
const ce = "_button_1wtoy_1",
  le = { button: ce },
  ie = R(({ onPlaybackRateChange: s, playbackRate: c, rates: n = re }) => {
    const { clickXY: d, setClickXY: o, eventHandler: i } = G(),
      p = (u) => {
        (u?.stopPropagation(), o(null));
      };
    return t.jsxs(t.Fragment, {
      children: [
        t.jsxs("button", {
          className: le.button,
          onClick: i,
          children: [c, "x"],
        }),
        d &&
          t.jsx(K, {
            top: d.top,
            left: d.left,
            onClose: p,
            children: t.jsx(J, {
              items: n.map((u) => ({
                label: `${u}x`,
                action: () => s(u),
                checked: c === u,
              })),
              className: "playback-speed",
            }),
          }),
      ],
    });
  }),
  ue = 40,
  T = R(
    ({
      message: s,
      dontShowTimestamp: c,
      float: n,
      isLastAttachment: d = !1,
    }) => {
      const o = !!s?.timestamp && !c,
        i = d && !!s?.isBookmarked,
        p = d && !!s?.isBlast && !!s.isSender;
      return !s || (!o && !i && !p)
        ? null
        : t.jsxs("span", {
            className: N(
              "audio-player-message-ts",
              n && "audio-player-message-ts-float",
            ),
            children: [
              i && t.jsx(ae, { message: s }),
              p && t.jsx(ne, { message: s }),
              o && oe(s.timestamp),
            ],
          });
    },
  ),
  de = ({
    result: s,
    message: c,
    dontShowTimestamp: n,
    isStale: d,
    isLastAttachment: o,
  }) => {
    const [i, p] = a.useState(!1),
      [u, r] = a.useState(!1),
      k = a.useRef(null);
    return (
      a.useEffect(() => {
        const m = k.current;
        if (!m) return;
        const y = parseFloat(getComputedStyle(m).lineHeight || "0") * ue;
        r(m.scrollHeight > y);
      }, [s]),
      t.jsxs("div", {
        "data-sentry-component": "Message",
        "data-sentry-source-file": "Audio.tsx",
        children: [
          t.jsxs("div", {
            ref: k,
            className: N("transcribed-message", i && "expanded", d && "stale"),
            children: [
              '"',
              s,
              '"',
              (!u || i) &&
                t.jsx(T, {
                  message: c,
                  dontShowTimestamp: n,
                  isLastAttachment: o,
                  float: !0,
                }),
            ],
          }),
          u &&
            t.jsxs("div", {
              className: "transcribed-message-footer",
              children: [
                t.jsx("button", {
                  className: "transcribed-message-btn",
                  onClick: () => p((m) => !m),
                  children: i ? B("Show less") : B("Show more"),
                }),
                !i &&
                  t.jsx(T, {
                    message: c,
                    dontShowTimestamp: n,
                    isLastAttachment: o,
                  }),
              ],
            }),
        ],
      })
    );
  },
  Se = R(
    ({
      src: s,
      attachment: c,
      messageIdentifier: n,
      stableID: d,
      thread: o,
      dontShowTimestamp: i,
      message: p,
      isLastAttachment: u,
    }) => {
      const r = d || c.id,
        k = a.useRef(s),
        m = a.useRef({ id: r, thread: o }),
        x = a.useRef({
          accountID: n?.accountID || "",
          threadID: n?.threadID || "",
          id: n?.id || "",
        });
      a.useEffect(() => {
        ((k.current = s),
          (m.current = { id: r, thread: o }),
          (x.current = {
            accountID: n?.accountID || "",
            threadID: n?.threadID || "",
            id: n?.id || "",
          }));
      }, [s, r, o, n]);
      const y = a.useRef(null),
        [b, H] = a.useState(null),
        v = a.useContext(Q),
        { audioStore: e } = v,
        F = o && n?.id && o.pendingMessages.has(n.id),
        l = e.currentPlayingId === r,
        I = l && e.playing,
        L = e.waveformManager.isReady(r),
        P = l && L && b !== null,
        Y = o ? e.getSavedPosition(o, r) : 0,
        _ = l ? e.progress : Y,
        S = l ? e.duration : e.waveformManager.getDuration(r),
        { transcriptionResult: C, isTranscribing: X } = Z(c, n, o),
        U = a.useCallback(
          (f) => {
            f && e.initializeWaveform(m.current, f, k.current, x.current);
          },
          [e],
        ),
        { colorScheme: $ } = j.layoutStore,
        q = j.localPrefsStore.prefs[ee.UI_THEME];
      (a.useEffect(() => {
        if (!o || !y.current) return;
        const f = getComputedStyle(y.current).getPropertyValue(
            "--waveform-color",
          ),
          h = getComputedStyle(y.current).getPropertyValue(
            "--waveform-progress-color",
          );
        e.updateWaveformColor(r, f, h);
      }, [$, q, e, o, r]),
        a.useEffect(() => {
          const f = requestAnimationFrame(() => {
            e.redrawWaveform(r);
          });
          return () => {
            cancelAnimationFrame(f);
          };
        }, [e, r, P, b]),
        a.useLayoutEffect(() => {
          y.current && b === null && H(y.current.offsetWidth);
        }, [b]));
      const z = a.useCallback(() => {
          e.toggleTrack(m.current, k.current, v.document, x.current);
        }, [e, v.document]),
        [g, A] = a.useState(null),
        w = a.useRef(!1);
      a.useEffect(() => {
        l && g !== null && A(null);
      }, [l, g]);
      const M = a.useCallback(() => {
          l ? e.startSeeking() : (w.current = !0);
        }, [e, l]),
        O = a.useCallback(
          (f) => {
            const h = f.target.valueAsNumber / 100;
            l ? e.seekTo(h) : (A(h), e.updateWaveformProgress(r, h));
          },
          [e, l, r],
        ),
        D = a.useCallback(() => {
          l
            ? e.endSeeking()
            : w.current &&
              g !== null &&
              ((w.current = !1), e.waveformManager.setPendingSeek(r, g));
        }, [e, l, g, r]),
        V = () => (P ? `${E(_)}/${E(S)}` : E(S));
      return t.jsxs("div", {
        className: N("audio-player", b && "width-locked"),
        ref: y,
        style: b ? { width: b } : void 0,
        children: [
          t.jsxs("div", {
            className: "player-contents",
            children: [
              t.jsx("button", {
                onClick: z,
                type: "button",
                "aria-label": I
                  ? W("Pause", "audio playback control")
                  : W("Play", "audio playback control"),
                disabled: F || (e.isLoading && l),
                children: t.jsx(te, {
                  width: 20,
                  height: 20,
                  "aria-hidden": !0,
                  name: I ? "pause-fill" : "play-fill",
                }),
              }),
              t.jsxs("div", {
                className: "waveform-container",
                children: [
                  t.jsx("div", { ref: U, className: "waveform" }),
                  t.jsx("input", {
                    type: "range",
                    min: "0",
                    max: "100",
                    value: g !== null ? g * 100 : S > 0 ? (_ / S) * 100 : 0,
                    onMouseDown: M,
                    onTouchStart: M,
                    onChange: O,
                    onMouseUp: D,
                    onTouchEnd: D,
                  }),
                ],
              }),
              t.jsx("span", { className: "audio-time", children: V() }),
              P &&
                t.jsx(ie, {
                  playbackRate: e.playbackRate,
                  onPlaybackRateChange: (f) => e.setPlaybackRate(f),
                }),
              !C?.transcription &&
                t.jsx(T, {
                  message: p,
                  dontShowTimestamp:
                    i || !j.prefsStore.prefs[se.MESSAGE_TIMESTAMPS],
                  isLastAttachment: u,
                }),
            ],
          }),
          C?.transcription &&
            t.jsx(de, {
              message: p,
              dontShowTimestamp: i,
              isLastAttachment: u,
              result: C.transcription,
              isStale: X,
            }),
        ],
      });
    },
  );
export { Se as default };
//# sourceMappingURL=Audio-D9NM2umV.js.map
