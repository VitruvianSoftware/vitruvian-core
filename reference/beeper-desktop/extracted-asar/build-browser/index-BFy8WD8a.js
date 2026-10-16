import { cJ as K, h as Q, aN as N, cA as Z } from "./matrix-util-8DbIGEm-.js";
import {
  cT as ee,
  de as r,
  b5 as re,
  b$ as z,
  bL as te,
  eq as O,
  cF as s,
  aO as C,
  v as H,
  br as ne,
  c0 as se,
  a9 as ae,
  am as oe,
  b4 as ce,
  al as ue,
  dm as le,
  bm as ie,
} from "./App-BHgTsVmv.js";
import { W as de } from "./wavesurfer-C3DYPLwL.js";
import "./sentry-common-BNqrY_yc.js";
import "./index-Cw3pknxT.js";
import "./main-process-state-BDOn7dvV.js";
import "./index-5FBEE1WD.js";
import "./index-Ch31Akxs.js";
import "./report-dialog-C-g_klPx.js";
(function () {
  try {
    var a =
      typeof window < "u"
        ? window
        : typeof global < "u"
          ? global
          : typeof globalThis < "u"
            ? globalThis
            : typeof self < "u"
              ? self
              : {};
    a.SENTRY_RELEASE = { id: "4.3.209" };
    var f = new a.Error().stack;
    f &&
      ((a._sentryDebugIds = a._sentryDebugIds || {}),
      (a._sentryDebugIds[f] = "2c89b882-3b4f-4383-8e97-6f8a4ca60516"),
      (a._sentryDebugIdIdentifier =
        "sentry-dbid-2c89b882-3b4f-4383-8e97-6f8a4ca60516"));
  } catch {}
})();
const fe = "_cancelButton_ctbs0_1",
  pe = "_recorder_ctbs0_8",
  me = "_paused_ctbs0_27",
  ge = "_progressWrapper_ctbs0_39",
  be = "_waveform_ctbs0_50",
  he = "_seekSlider_ctbs0_74",
  ve = "_time_ctbs0_84",
  ye = "_playPauseButton_ctbs0_94",
  we = "_actionButton_ctbs0_99",
  l = {
    cancelButton: fe,
    recorder: pe,
    paused: me,
    progressWrapper: ge,
    waveform: be,
    seekSlider: he,
    time: ve,
    playPauseButton: ye,
    actionButton: we,
  },
  B = "audio/ogg",
  T = 100;
function Re(a) {
  if (!a.length) return;
  const f = a.length > T ? a.length / T : 1,
    b = f === 1 ? a.length : T,
    S = new Array(b);
  for (let y = 0; y < b; y++) {
    const d = a[Math.min(a.length - 1, Math.floor(y * f))];
    S[y] = ie(Math.round(d * 1024), 0, 1024);
  }
  return S;
}
const Ce = ee(
  ({
    composerStore: a,
    onRecordingDone: f,
    onRecordingStop: b,
    onClose: S,
    onSend: y,
  }) => {
    const [d, P] = r.useState("idle"),
      [p, x] = r.useState(null),
      [D, m] = r.useState(!1),
      [I, M] = r.useState(0),
      [G, _] = r.useState(0),
      [J, A] = r.useState(0),
      X = r.useContext(re),
      E = d === "paused",
      h = r.useRef(null),
      g = r.useRef(null),
      w = r.useRef([]),
      R = r.useRef(null),
      v = r.useRef(null),
      t = r.useRef(null),
      W = r.useRef(0),
      k = r.useRef(!1),
      u = r.useRef(null),
      j = r.useRef([]),
      L = r.useRef(null);
    (r.useEffect(() => {
      if (d !== "recording") return;
      const e = setInterval(() => {
        ((W.current += 1), M(W.current));
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
              (t.current?.setVolume(1), A(t.current?.getDuration() || 0));
            }),
            t.current.on("finish", () => {
              (t.current?.seekTo(0), _(0), m(!1));
            }),
            t.current.on("audioprocess", (e) => {
              _(e);
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
              ((w.current = []),
                (R.current = null),
                (k.current = !1),
                x(null),
                m(!1),
                (W.current = 0),
                M(0));
              const o = await se(
                Z.localPrefsStore.prefs[ae.AUDIO_INPUT_DEVICE_ID],
              );
              if (!e) {
                o.getTracks().forEach((c) => c.stop());
                return;
              }
              h.current = o;
              const i = new oe(
                o,
                { mimeType: B, audioBitsPerSecond: 128e3 },
                {
                  encoderWorkerFactory: () =>
                    new Worker(
                      new URL(
                        "" +
                          new URL("encoderWorker-CUWBHtlr.js", import.meta.url)
                            .href,
                        import.meta.url,
                      ),
                      { type: "module" },
                    ),
                  OggOpusEncoderWasmPath: ue,
                  WebMOpusEncoderWasmPath: ce,
                },
              );
              if (
                ((g.current = i),
                i.addEventListener("dataavailable", (c) => {
                  !e ||
                    k.current ||
                    (c.data && c.data.size > 0 && w.current.push(c.data));
                }),
                i.addEventListener("stop", () => {
                  if (!e || k.current) return;
                  const c = new Blob(w.current, { type: B });
                  R.current = c;
                  const $ = URL.createObjectURL(c);
                  (x($),
                    m(!1),
                    _(0),
                    A(0),
                    P("paused"),
                    t.current?.loadBlob(c));
                }),
                i.start(500),
                P("recording"),
                v.current)
              ) {
                L.current = document.createElement("canvas");
                const c = le({
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
                u.current = c ?? null;
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
              u.current?.destroy(),
              (u.current = null),
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
          (w.current = []),
          (R.current = null),
          u.current?.destroy(),
          (u.current = null),
          (j.current = []),
          p && URL.revokeObjectURL(p),
          x(null),
          m(!1),
          P("idle"),
          b?.(),
          S(),
          setTimeout(() => {
            X.focusMessageInput();
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
        u.current && (j.current = u.current.pause());
        const o = new Blob(w.current, { type: B });
        ((R.current = o),
          p && URL.revokeObjectURL(p),
          x(URL.createObjectURL(o)),
          m(!1),
          _(0),
          A(0),
          P("paused"),
          t.current?.loadBlob(o));
      },
      q = (e) => {
        (e?.preventDefault(), e?.stopPropagation());
        const n = g.current;
        !n ||
          n.state !== "paused" ||
          (t.current?.pause(),
          n.resume(),
          u.current && u.current.resume(j.current),
          m(!1),
          P("recording"));
      },
      V = r.useCallback(async () => {
        const e = u.current?.pause() ?? j.current;
        (u.current?.destroy(), (u.current = null));
        const n = g.current;
        if (n?.state !== "inactive") {
          try {
            n?.requestData();
          } catch (c) {
            logger.error("[AudioBar]::prepareAudioForSend", c);
          }
          n?.stop();
        }
        (h.current?.getTracks().forEach((c) => c.stop()), (h.current = null));
        const o = Date.now();
        for (; !R.current && Date.now() - o < 5e3;) await K(10);
        const i = R.current ?? new Blob(w.current, { type: B });
        !i ||
          i.size === 0 ||
          (await f({
            buffer: Q.from(await i.arrayBuffer()),
            mimeType: B,
            fileName: "voice-note.ogg",
            audioDurationSeconds: W.current,
            audioWaveform: Re(e),
          }),
          b?.());
      }, [f, b]);
    (r.useEffect(
      () => (a.setAudioSendPrepare(V), () => a.setAudioSendPrepare(null)),
      [V, a],
    ),
      O("esc", F, "audio-bar-esc"),
      O(
        "space",
        () => {
          d === "recording" ? U() : d === "paused" && q();
        },
        "audio-bar-space",
        !0,
      ),
      O(
        "enter",
        () => {
          d === "recording" ? U() : d === "paused" && y();
        },
        "audio-bar-enter",
        !0,
      ));
    const Y = (e) => {
      (e?.preventDefault(),
        e?.stopPropagation(),
        !(!t.current || !p) && (D ? t.current.pause() : t.current.play()));
    };
    return s.jsxs(s.Fragment, {
      children: [
        s.jsx("button", {
          "aria-label": "Cancel Record",
          type: "button",
          className: l.cancelButton,
          onClick: F,
          children: s.jsx(C, { width: 20, height: 20, name: "close" }),
        }),
        s.jsxs("div", {
          className: ne(l.recorder, { [l.paused]: E }),
          children: [
            E &&
              s.jsx("button", {
                "aria-label": D ? "Pause Preview" : "Play Preview",
                type: "button",
                className: l.playPauseButton,
                onClick: Y,
                children: s.jsx(C, {
                  name: D ? "pause-fill" : "play-fill",
                  width: 20,
                  height: 20,
                }),
              }),
            s.jsxs("div", {
              className: l.progressWrapper,
              children: [
                s.jsx("div", { ref: v, className: l.waveform }),
                s.jsx("input", {
                  type: "range",
                  min: "0",
                  max: "100",
                  className: l.seekSlider,
                  onChange: (e) => {
                    requestAnimationFrame(() => {
                      const n = e.target.valueAsNumber / 100;
                      t.current?.seekTo(n);
                      const o = t.current?.getDuration() || 0;
                      _(n * o);
                    });
                  },
                }),
              ],
            }),
            E
              ? s.jsxs("span", {
                  className: l.time,
                  children: [N(G), "/", N(J || I)],
                })
              : s.jsx("span", { className: l.time, children: N(I) }),
            E
              ? s.jsx(H, {
                  content: "Resume Recording",
                  children: s.jsx("button", {
                    "aria-label": "Resume Recording",
                    type: "button",
                    className: l.actionButton,
                    onClick: q,
                    children: s.jsx(C, {
                      name: "record",
                      width: 20,
                      height: 20,
                    }),
                  }),
                })
              : s.jsx(H, {
                  content: "Pause Recording",
                  children: s.jsx("button", {
                    "aria-label": "Pause Recording",
                    type: "button",
                    className: l.actionButton,
                    onClick: U,
                    children: s.jsx(C, {
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
//# sourceMappingURL=index-BFy8WD8a.js.map
