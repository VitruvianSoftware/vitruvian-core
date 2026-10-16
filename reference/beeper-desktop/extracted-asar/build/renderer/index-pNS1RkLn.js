import { cM as J, h as Z, aO as O, cD as $ } from "./matrix-util-Cr_UwXbj.js";
import {
  cY as ee,
  dk as r,
  ba as re,
  c5 as z,
  bQ as te,
  ex as T,
  cK as a,
  aT as j,
  w as H,
  bw as ne,
  c6 as ae,
  ac as se,
  aq as oe,
  b9 as ue,
  ap as ce,
  dt as le,
  br as ie,
} from "./App-CsJiApxN.js";
import { W as de } from "./wavesurfer-BKkjGfSC.js";
import "./sentry-common-BxRELKId.js";
import "./index-Cw3pknxT.js";
import "./main-process-state-wkFhis-C.js";
import "./index-Dhe7xemD.js";
import "./index-CcYzEQCb.js";
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
    var f = new s.Error().stack;
    f &&
      ((s._sentryDebugIds = s._sentryDebugIds || {}),
      (s._sentryDebugIds[f] = "1f9b59bd-79bb-4a53-aaaa-2cc9fb0e8b6c"),
      (s._sentryDebugIdIdentifier =
        "sentry-dbid-1f9b59bd-79bb-4a53-aaaa-2cc9fb0e8b6c"));
  } catch {}
})();
const fe = "AudioBar-module__cancelButton",
  pe = "AudioBar-module__recorder",
  me = "AudioBar-module__paused",
  ge = "AudioBar-module__progressWrapper",
  be = "AudioBar-module__waveform",
  he = "AudioBar-module__seekSlider",
  ve = "AudioBar-module__time",
  we = "AudioBar-module__playPauseButton",
  ye = "AudioBar-module__actionButton",
  l = {
    cancelButton: fe,
    recorder: pe,
    paused: me,
    progressWrapper: ge,
    waveform: be,
    seekSlider: he,
    time: ve,
    playPauseButton: we,
    actionButton: ye,
  },
  x = "audio/ogg",
  I = 100;
function Re(s) {
  if (!s.length) return;
  const f = s.length > I ? s.length / I : 1,
    b = f === 1 ? s.length : I,
    S = new Array(b);
  for (let w = 0; w < b; w++) {
    const d = s[Math.min(s.length - 1, Math.floor(w * f))];
    S[w] = ie(Math.round(d * 1024), 0, 1024);
  }
  return S;
}
const Ce = ee(
  ({
    composerStore: s,
    onRecordingDone: f,
    onRecordingStop: b,
    onClose: S,
    onSend: w,
  }) => {
    const [d, B] = r.useState("idle"),
      [p, _] = r.useState(null),
      [C, m] = r.useState(!1),
      [N, M] = r.useState(0),
      [K, P] = r.useState(0),
      [Y, D] = r.useState(0),
      G = r.useContext(re),
      A = d === "paused",
      h = r.useRef(null),
      g = r.useRef(null),
      y = r.useRef([]),
      R = r.useRef(null),
      v = r.useRef(null),
      t = r.useRef(null),
      E = r.useRef(0),
      k = r.useRef(!1),
      c = r.useRef(null),
      W = r.useRef([]),
      L = r.useRef(null);
    (r.useEffect(() => {
      if (d !== "recording") return;
      const e = setInterval(() => {
        ((E.current += 1), M(E.current));
      }, 1e3);
      return () => clearInterval(e);
    }, [d]),
      r.useEffect(() => {
        if (p) return () => URL.revokeObjectURL(p);
      }, [p]),
      r.useEffect(() => {
        if (v.current)
          return (
            (t.current = de.create({
              container: v.current,
              waveColor: "#787D87",
              progressColor: "#007aff",
              cursorColor: "transparent",
              cursorWidth: 0,
              barWidth: 3,
              barRadius: 3,
              responsive: !0,
              height: 24,
              barMinHeight: 6,
              normalize: !0,
              audioContext: z(),
            })),
            t.current.on("ready", () => {
              (t.current?.setVolume(1), D(t.current?.getDuration() || 0));
            }),
            t.current.on("finish", () => {
              (t.current?.seekTo(0), P(0), m(!1));
            }),
            t.current.on("audioprocess", (e) => {
              P(e);
            }),
            t.current.on("play", () => {
              m(!0);
            }),
            t.current.on("pause", () => {
              m(!1);
            }),
            () => {
              (te(t.current), (t.current = null));
            }
          );
      }, []),
      r.useEffect(() => {
        let e = !0;
        return (
          (async () => {
            try {
              ((y.current = []),
                (R.current = null),
                (k.current = !1),
                _(null),
                m(!1),
                (E.current = 0),
                M(0));
              const o = await ae(
                $.localPrefsStore.prefs[se.AUDIO_INPUT_DEVICE_ID],
              );
              if (!e) {
                o.getTracks().forEach((u) => u.stop());
                return;
              }
              h.current = o;
              const i = new oe(
                o,
                { mimeType: x, audioBitsPerSecond: 128e3 },
                {
                  encoderWorkerFactory: () =>
                    new Worker(
                      new URL(
                        "" +
                          new URL("encoderWorker-Cva7vKEb.js", import.meta.url)
                            .href,
                        import.meta.url,
                      ),
                      { type: "module" },
                    ),
                  OggOpusEncoderWasmPath: ce,
                  WebMOpusEncoderWasmPath: ue,
                },
              );
              if (
                ((g.current = i),
                i.addEventListener("dataavailable", (u) => {
                  !e ||
                    k.current ||
                    (u.data && u.data.size > 0 && y.current.push(u.data));
                }),
                i.addEventListener("stop", () => {
                  if (!e || k.current) return;
                  const u = new Blob(y.current, { type: x });
                  R.current = u;
                  const X = URL.createObjectURL(u);
                  (_(X),
                    m(!1),
                    P(0),
                    D(0),
                    B("paused"),
                    t.current?.loadBlob(u));
                }),
                i.start(500),
                B("recording"),
                v.current)
              ) {
                L.current = document.createElement("canvas");
                const u = le({
                  canvas: L.current,
                  container: v.current,
                  stream: o,
                  audioContext: z(),
                  realtimeWaveColor: () =>
                    (v.current &&
                      getComputedStyle(v.current)
                        .getPropertyValue("--waveform-color")
                        .trim()) ||
                    "#787D87",
                });
                c.current = u ?? null;
              }
            } catch (o) {
              logger.error("AudioBar recording error", o);
            }
          })(),
          () => {
            ((e = !1),
              g.current?.state !== "inactive" && g.current?.stop(),
              h.current?.getTracks().forEach((o) => o.stop()),
              (h.current = null),
              c.current?.destroy(),
              (c.current = null),
              (L.current = null));
          }
        );
      }, []));
    const F = (e) => {
        (e?.preventDefault(),
          e?.stopPropagation(),
          (k.current = !0),
          g.current?.state !== "inactive" && g.current?.stop(),
          h.current?.getTracks().forEach((n) => n.stop()),
          (h.current = null),
          (y.current = []),
          (R.current = null),
          c.current?.destroy(),
          (c.current = null),
          (W.current = []),
          p && URL.revokeObjectURL(p),
          _(null),
          m(!1),
          B("idle"),
          b?.(),
          S(),
          setTimeout(() => {
            G.focusMessageInput();
          }, 10));
      },
      U = (e) => {
        (e?.preventDefault(), e?.stopPropagation());
        const n = g.current;
        if (!n || n.state !== "recording") return;
        n.pause();
        try {
          n.requestData();
        } catch (i) {
          logger.error("[AudioBar]::handlePause", i);
        }
        c.current && (W.current = c.current.pause());
        const o = new Blob(y.current, { type: x });
        ((R.current = o),
          p && URL.revokeObjectURL(p),
          _(URL.createObjectURL(o)),
          m(!1),
          P(0),
          D(0),
          B("paused"),
          t.current?.loadBlob(o));
      },
      q = (e) => {
        (e?.preventDefault(), e?.stopPropagation());
        const n = g.current;
        !n ||
          n.state !== "paused" ||
          (t.current?.pause(),
          n.resume(),
          c.current && c.current.resume(W.current),
          m(!1),
          B("recording"));
      },
      V = r.useCallback(async () => {
        const e = c.current?.pause() ?? W.current;
        (c.current?.destroy(), (c.current = null));
        const n = g.current;
        if (n?.state !== "inactive") {
          try {
            n?.requestData();
          } catch (u) {
            logger.error("[AudioBar]::prepareAudioForSend", u);
          }
          n?.stop();
        }
        (h.current?.getTracks().forEach((u) => u.stop()), (h.current = null));
        const o = Date.now();
        for (; !R.current && Date.now() - o < 5e3;) await J(10);
        const i = R.current ?? new Blob(y.current, { type: x });
        !i ||
          i.size === 0 ||
          (await f({
            buffer: Z.from(await i.arrayBuffer()),
            mimeType: x,
            fileName: "voice-note.ogg",
            audioDurationSeconds: E.current,
            audioWaveform: Re(e),
          }),
          b?.());
      }, [f, b]);
    (r.useEffect(
      () => (s.setAudioSendPrepare(V), () => s.setAudioSendPrepare(null)),
      [V, s],
    ),
      T("esc", F, "audio-bar-esc"),
      T(
        "space",
        () => {
          d === "recording" ? U() : d === "paused" && q();
        },
        "audio-bar-space",
        !0,
      ),
      T(
        "enter",
        () => {
          d === "recording" ? U() : d === "paused" && w();
        },
        "audio-bar-enter",
        !0,
      ));
    const Q = (e) => {
      (e?.preventDefault(),
        e?.stopPropagation(),
        !(!t.current || !p) && (C ? t.current.pause() : t.current.play()));
    };
    return a.jsxs(a.Fragment, {
      children: [
        a.jsx("button", {
          "aria-label": "Cancel Record",
          type: "button",
          className: l.cancelButton,
          onClick: F,
          children: a.jsx(j, { width: 20, height: 20, name: "close" }),
        }),
        a.jsxs("div", {
          className: ne(l.recorder, { [l.paused]: A }),
          children: [
            A &&
              a.jsx("button", {
                "aria-label": C ? "Pause Preview" : "Play Preview",
                type: "button",
                className: l.playPauseButton,
                onClick: Q,
                children: a.jsx(j, {
                  name: C ? "pause-fill" : "play-fill",
                  width: 20,
                  height: 20,
                }),
              }),
            a.jsxs("div", {
              className: l.progressWrapper,
              children: [
                a.jsx("div", { ref: v, className: l.waveform }),
                a.jsx("input", {
                  type: "range",
                  min: "0",
                  max: "100",
                  className: l.seekSlider,
                  onChange: (e) => {
                    requestAnimationFrame(() => {
                      const n = e.target.valueAsNumber / 100;
                      t.current?.seekTo(n);
                      const o = t.current?.getDuration() || 0;
                      P(n * o);
                    });
                  },
                }),
              ],
            }),
            A
              ? a.jsxs("span", {
                  className: l.time,
                  children: [O(K), "/", O(Y || N)],
                })
              : a.jsx("span", { className: l.time, children: O(N) }),
            A
              ? a.jsx(H, {
                  content: "Resume Recording",
                  children: a.jsx("button", {
                    "aria-label": "Resume Recording",
                    type: "button",
                    className: l.actionButton,
                    onClick: q,
                    children: a.jsx(j, {
                      name: "record",
                      width: 20,
                      height: 20,
                    }),
                  }),
                })
              : a.jsx(H, {
                  content: "Pause Recording",
                  children: a.jsx("button", {
                    "aria-label": "Pause Recording",
                    type: "button",
                    className: l.actionButton,
                    onClick: U,
                    children: a.jsx(j, {
                      name: "pause-fill",
                      width: 20,
                      height: 20,
                    }),
                  }),
                }),
          ],
        }),
      ],
    });
  },
);
export { Ce as default };
//# sourceMappingURL=index-pNS1RkLn.js.map
