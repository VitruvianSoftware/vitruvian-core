import { de as i, aB as b, cT as g, cF as u, n as j } from "./App-BHgTsVmv.js";
import { cA as m, bD as y, bq as E, b0 as h } from "./matrix-util-8DbIGEm-.js";
import { Picker as v } from "./module-CyRk-uWw.js";
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
    var o = new t.Error().stack;
    o &&
      ((t._sentryDebugIds = t._sentryDebugIds || {}),
      (t._sentryDebugIds[o] = "e39b8eaf-4f77-417e-bc03-e1d75c7019a7"),
      (t._sentryDebugIdIdentifier =
        "sentry-dbid-e39b8eaf-4f77-417e-bc03-e1d75c7019a7"));
  } catch {}
})();
function D(t) {
  const o = i.useRef(null),
    e = i.useRef(null);
  return (
    e.current && e.current.update(t),
    i.useEffect(
      () => (
        (e.current = new v({ ...t, ref: o })),
        () => {
          e.current = null;
        }
      ),
      [],
    ),
    b.createElement("div", { ref: o })
  );
}
const c = "defaults",
  R = async (t) => {
    const o = await h(),
      e = o.Data;
    if (!e) return;
    const a = e.categories?.find((r) => r.id === c);
    for (const r of a?.emojis ?? []) delete e.emojis[r];
    e.categories = e.categories?.filter((r) => r.id !== c) ?? [];
    const s = t?.emojis ?? [];
    if (s.length !== 0) {
      (e.categories.splice(0, 0, { id: c, emojis: s.map((r) => r.id) }),
        (o.I18n.categories[c] = t?.name ?? "Defaults"));
      for (const r of s) e.emojis[r.id] = r;
    }
  },
  $ = g(({ onEmojiSelect: t, style: o, customEmojis: e, defaultEmojis: a }) => {
    const { transformedRecentEmoji: s } = m.emojiStore,
      [r, f] = i.useState(!1),
      d = e?.some((n) => n.emojis.length > 0),
      l = i.useMemo(() => {
        if (s) return d ? s : s.filter((n) => !y(n));
      }, [s, d]);
    return (
      i.useEffect(() => {
        let n = !1;
        return (
          f(!1),
          E(e ?? [])
            .then(() => R(a))
            .then(() => {
              n || f(!0);
            })
            .catch((p) => {
              (Sentry.captureException(p), n || f(!0));
            }),
          () => {
            n = !0;
          }
        );
      }, [e, a]),
      l === void 0 || !r
        ? u.jsx("div", {
            className: "emoji-mart suspense-placeholder",
            style: {
              width: 338,
              height: 446,
              backgroundColor: "var(--color-bg)",
              borderColor: "var(--color-bg)",
            },
            children: u.jsx(j, {}),
          })
        : u.jsx(D, {
            native: !0,
            onEmojiSelect: t,
            theme: "auto",
            title: "",
            autoFocus: !0,
            style: o,
            custom: e,
            onSkinChange: (n) => m.emojiStore.setSkinTone(n),
            customFrequentlyUsed: { enabled: !0, values: l },
          })
    );
  });
export { $ as default };
//# sourceMappingURL=EmojiPicker-DQvK_Vyi.js.map
