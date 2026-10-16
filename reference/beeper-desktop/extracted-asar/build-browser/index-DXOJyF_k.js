import { de as s, cF as l } from "./App-BHgTsVmv.js";
import "./sentry-common-BNqrY_yc.js";
import "./matrix-util-8DbIGEm-.js";
import "./index-Cw3pknxT.js";
import "./main-process-state-BDOn7dvV.js";
import "./index-5FBEE1WD.js";
import "./index-Ch31Akxs.js";
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
    var n = new e.Error().stack;
    n &&
      ((e._sentryDebugIds = e._sentryDebugIds || {}),
      (e._sentryDebugIds[n] = "9157f143-de71-4bcf-b786-dbc8f078ca4b"),
      (e._sentryDebugIdIdentifier =
        "sentry-dbid-9157f143-de71-4bcf-b786-dbc8f078ca4b"));
  } catch {}
})();
function I(e) {
  return e.constructor.name === "MessagePort";
}
function f(e) {
  I(e) && e.close();
}
function u(e) {
  return b(e, new Map(), { type: "RELEASE" }).then(() => {
    f(e);
  });
}
const d = new WeakMap();
"FinalizationRegistry" in globalThis &&
  new FinalizationRegistry((e) => {
    const n = (d.get(e) || 0) - 1;
    (d.set(e, n), n === 0 && u(e));
  });
const m = new WeakMap();
function g(e, n) {
  return (m.set(e, n), e);
}
function b(e, n, o, a) {
  return new Promise((t) => {
    const i = Z();
    (n.set(i, t),
      e.start && e.start(),
      e.postMessage(Object.assign({ id: i }, o), a));
  });
}
function Z() {
  return new Array(4)
    .fill(0)
    .map(() => Math.floor(Math.random() * Number.MAX_SAFE_INTEGER).toString(16))
    .join("-");
}
const h = "OffscreenCanvas" in window;
function y(e, n) {
  const o = e.getContext("2d");
  if (!o) {
    (typeof logger < "u" ? logger : console).error(
      "putImageData: canvas context is null, can't draw image data",
    );
    return;
  }
  const { width: a, height: t } = n;
  ((e.width = a),
    (e.height = t),
    requestAnimationFrame(() => {
      o?.putImageData(new ImageData(n.data, a, t), 0, 0);
    }));
}
const c = new ComlinkWorker(
  new URL(
    "data:video/mp2t;base64,aW1wb3J0IFVUSUYgZnJvbSAndXRpZicKaW1wb3J0IHsgcHV0SW1hZ2VEYXRhIH0gZnJvbSAnLi9kcmF3aW5nJwoKLy8gRklYTUU6IHNhbWUgYXMgSW1hZ2VEYXRhLCBidXQgbm8gY29sb3JzcGFjZT8KZXhwb3J0IHR5cGUgVElGRkltYWdlID0gewogIHJnYmE6IFVpbnQ4QXJyYXkKICB3aWR0aDogbnVtYmVyCiAgaGVpZ2h0OiBudW1iZXIKfQoKLy8gaHR0cHM6Ly9naXRodWIuY29tL3Bob3RvcGVhL1VUSUYuanMvYmxvYi84MjA1YzFmMDgxMWM1ZTFjMDFiMThlOTYxMTk0NTc4NjIxYTQ0MDZjL1VUSUYuanMjTDEwNjIKZXhwb3J0IGZ1bmN0aW9uIGRlY29kZVRJRkYoYnVmZmVyOiBBcnJheUJ1ZmZlcik6IFRJRkZJbWFnZSB7CiAgY29uc3QgaWZkcyA9IFVUSUYuZGVjb2RlKGJ1ZmZlcikKICBsZXQgbWEgPSAwCiAgbGV0IHZzbnMgPSBpZmRzCiAgbGV0IHBhZ2UgPSB2c25zWzBdCiAgLy8gQHRzLWV4cGVjdC1lcnJvcgogIGlmIChpZmRzWzBdLnN1YklGRCkgdnNucyA9IHZzbnMuY29uY2F0KGlmZHNbMF0uc3ViSUZEKQogIGZvciAoY29uc3QgaW1nIG9mIHZzbnMpIHsKICAgIC8vIEB0cy1leHBlY3QtZXJyb3IKICAgIGlmIChpbWcudDI1OCA9PSBudWxsIHx8IGltZy50MjU4Lmxlbmd0aCA8IDMpIGNvbnRpbnVlCiAgICAvLyBAdHMtZXhwZWN0LWVycm9yCiAgICBjb25zdCBhciA9IGltZy50MjU2ICogaW1nLnQyNTcKICAgIGlmIChhciA+IG1hKSB7CiAgICAgIG1hID0gYXIKICAgICAgcGFnZSA9IGltZwogICAgfQogIH0KICAvLyBAdHMtZXhwZWN0LWVycm9yCiAgVVRJRi5kZWNvZGVJbWFnZShidWZmZXIsIHBhZ2UsIGlmZHMpCiAgY29uc3QgcmdiYSA9IFVUSUYudG9SR0JBOChwYWdlKQogIGNvbnN0IHsgd2lkdGgsIGhlaWdodCB9ID0gcGFnZQogIHJldHVybiB7IHJnYmEsIHdpZHRoLCBoZWlnaHQgfQp9CgpleHBvcnQgZnVuY3Rpb24gZHJhdyh7IHJnYmEsIHdpZHRoLCBoZWlnaHQgfTogVElGRkltYWdlLCBjYW52YXM6IE9mZnNjcmVlbkNhbnZhcykgewogIHB1dEltYWdlRGF0YShjYW52YXMsIG5ldyBJbWFnZURhdGEobmV3IFVpbnQ4Q2xhbXBlZEFycmF5KHJnYmEuYnVmZmVyKSwgd2lkdGgsIGhlaWdodCkpCn0K",
    import.meta.url,
  ),
  { type: "module" },
);
async function C(e, n) {
  logger.debug("tiff fetch");
  const a = await (await fetch(e)).arrayBuffer();
  if ((logger.debug("tiff image fetched", a.byteLength, "bytes"), h)) {
    const t = n.transferControlToOffscreen();
    logger.debug("tiff worker decoding");
    const i = await c.decodeTIFF(g(a, [a]));
    (logger.debug("tiff worker transferring"),
      await c.draw(g(i, [i.rgba.buffer]), g(t, [t])));
  } else {
    const t = await c.decodeTIFF(g(a, [a]));
    y(n, new ImageData(new Uint8ClampedArray(t.rgba), t.width, t.height));
  }
  logger.debug("tiff worker completed");
}
const V = ({ src: e, ...n }) => {
  const o = s.useRef(!1),
    [a, t] = s.useState(!0),
    i = s.useCallback(
      (r) => {
        ((o.current = r == null),
          r &&
            (async () => {
              try {
                await C(e, r);
              } finally {
                o.current || t(!1);
              }
            })());
      },
      [e],
    );
  return l.jsx("canvas", {
    className: a ? "img loading" : "img",
    ref: i,
    ...n,
    "data-sentry-component": "TiffImg",
    "data-sentry-source-file": "index.tsx",
  });
};
export { V as default };
//# sourceMappingURL=index-DXOJyF_k.js.map
