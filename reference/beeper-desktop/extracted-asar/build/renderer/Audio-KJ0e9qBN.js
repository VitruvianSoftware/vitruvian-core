import {
  cY as R,
  es as q,
  cK as t,
  aw as G,
  ax as J,
  dk as n,
  ba as Q,
  eA as Z,
  ac as ee,
  aT as te,
  ay as se,
  bw as I,
  r as ne,
  p as oe,
  cn as ae,
} from "./App-CsJiApxN.js";
import { cD as j, a6 as W, aO as E, a2 as B } from "./matrix-util-Cr_UwXbj.js";
import { r as re } from "./sentry-common-BxRELKId.js";
import "./index-Cw3pknxT.js";
import "./index-Dhe7xemD.js";
import "./index-CcYzEQCb.js";
import "./main-process-state-wkFhis-C.js";
import "./report-dialog-7bETf2vU.js";
import "./helpHubMessages-CXhGQ9cB.js";
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
      (s._sentryDebugIds[c] = "e48faae6-d4e6-46f9-8b88-f5c646d0ee9c"),
      (s._sentryDebugIdIdentifier =
        "sentry-dbid-e48faae6-d4e6-46f9-8b88-f5c646d0ee9c"));
  } catch {}
})();
const ce = "PlaybackControl-module__button",
  le = { button: ce },
  ie = R(({ onPlaybackRateChange: s, playbackRate: c, rates: o = re }) => {
    const { clickXY: d, setClickXY: a, eventHandler: i } = q(),
      p = (u) => {
        (u?.stopPropagation(), a(null));
      };
    return t.jsxs(t.Fragment, {
      children: [
        t.jsxs("button", {
          className: le.button,
          onClick: i,
          children: [c, "x"],
        }),
        d &&
          t.jsx(G, {
            top: d.top,
            left: d.left,
            onClose: p,
            children: t.jsx(J, {
              items: o.map((u) => ({
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
      float: o,
      isLastAttachment: d = !1,
    }) => {
      const a = !!s?.timestamp && !c,
        i = d && !!s?.isBookmarked,
        p = d && !!s?.isBlast && !!s.isSender;
      return !s || (!a && !i && !p)
        ? null
        : t.jsxs("span", {
            className: I(
              "audio-player-message-ts",
              o && "audio-player-message-ts-float",
            ),
            children: [
              i && t.jsx(ne, { message: s }),
              p && t.jsx(oe, { message: s }),
              a && ae(s.timestamp),
            ],
          });
    },
  ),
  de = ({
    result: s,
    message: c,
    dontShowTimestamp: o,
    isStale: d,
    isLastAttachment: a,
  }) => {
    const [i, p] = n.useState(!1),
      [u, r] = n.useState(!1),
      k = n.useRef(null);
    return (
      n.useEffect(() => {
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
            className: I("transcribed-message", i && "expanded", d && "stale"),
            children: [
              '"',
              s,
              '"',
              (!u || i) &&
                t.jsx(T, {
                  message: c,
                  dontShowTimestamp: o,
                  isLastAttachment: a,
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
                    dontShowTimestamp: o,
                    isLastAttachment: a,
                  }),
              ],
            }),
        ],
      })
    );
  },
  Pe = R(
    ({
      src: s,
      attachment: c,
      messageIdentifier: o,
      stableID: d,
      thread: a,
      dontShowTimestamp: i,
      message: p,
      isLastAttachment: u,
    }) => {
      const r = d || c.id,
        k = n.useRef(s),
        m = n.useRef({ id: r, thread: a }),
        S = n.useRef({
          accountID: o?.accountID || "",
          threadID: o?.threadID || "",
          id: o?.id || "",
        });
      n.useEffect(() => {
        ((k.current = s),
          (m.current = { id: r, thread: a }),
          (S.current = {
            accountID: o?.accountID || "",
            threadID: o?.threadID || "",
            id: o?.id || "",
          }));
      }, [s, r, a, o]);
      const y = n.useRef(null),
        [b, H] = n.useState(null),
        P = n.useContext(Q),
        { audioStore: e } = P,
        L = a && o?.id && a.pendingMessages.has(o.id),
        l = e.currentPlayingId === r,
        N = l && e.playing,
        Y = e.waveformManager.isReady(r),
        v = l && Y && b !== null,
        F = a ? e.getSavedPosition(a, r) : 0,
        A = l ? e.progress : F,
        h = l ? e.duration : e.waveformManager.getDuration(r),
        { transcriptionResult: C, isTranscribing: X } = Z(c, o, a),
        U = n.useCallback(
          (f) => {
            f && e.initializeWaveform(m.current, f, k.current, S.current);
          },
          [e],
        ),
        { colorScheme: $ } = j.layoutStore,
        z = j.localPrefsStore.prefs[ee.UI_THEME];
      (n.useEffect(() => {
        if (!a || !y.current) return;
        const f = getComputedStyle(y.current).getPropertyValue(
            "--waveform-color",
          ),
          x = getComputedStyle(y.current).getPropertyValue(
            "--waveform-progress-color",
          );
        e.updateWaveformColor(r, f, x);
      }, [$, z, e, a, r]),
        n.useEffect(() => {
          const f = requestAnimationFrame(() => {
            e.redrawWaveform(r);
          });
          return () => {
            cancelAnimationFrame(f);
          };
        }, [e, r, v, b]),
        n.useLayoutEffect(() => {
          y.current && b === null && H(y.current.offsetWidth);
        }, [b]));
      const K = n.useCallback(() => {
          e.toggleTrack(m.current, k.current, P.document, S.current);
        }, [e, P.document]),
        [g, D] = n.useState(null),
        w = n.useRef(!1);
      n.useEffect(() => {
        l && g !== null && D(null);
      }, [l, g]);
      const M = n.useCallback(() => {
          l ? e.startSeeking() : (w.current = !0);
        }, [e, l]),
        O = n.useCallback(
          (f) => {
            const x = f.target.valueAsNumber / 100;
            l ? e.seekTo(x) : (D(x), e.updateWaveformProgress(r, x));
          },
          [e, l, r],
        ),
        _ = n.useCallback(() => {
          l
            ? e.endSeeking()
            : w.current &&
              g !== null &&
              ((w.current = !1), e.waveformManager.setPendingSeek(r, g));
        }, [e, l, g, r]),
        V = () => (v ? `${E(A)}/${E(h)}` : E(h));
      return t.jsxs("div", {
        className: I("audio-player", b && "width-locked"),
        ref: y,
        style: b ? { width: b } : void 0,
        children: [
          t.jsxs("div", {
            className: "player-contents",
            children: [
              t.jsx("button", {
                onClick: K,
                type: "button",
                "aria-label": N
                  ? W("Pause", "audio playback control")
                  : W("Play", "audio playback control"),
                disabled: L || (e.isLoading && l),
                children: t.jsx(te, {
                  width: 20,
                  height: 20,
                  "aria-hidden": !0,
                  name: N ? "pause-fill" : "play-fill",
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
                    value: g !== null ? g * 100 : h > 0 ? (A / h) * 100 : 0,
                    onMouseDown: M,
                    onTouchStart: M,
                    onChange: O,
                    onMouseUp: _,
                    onTouchEnd: _,
                  }),
                ],
              }),
              t.jsx("span", { className: "audio-time", children: V() }),
              v &&
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
export { Pe as default };
//# sourceMappingURL=Audio-KJ0e9qBN.js.map
