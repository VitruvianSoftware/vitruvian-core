import { dk as n, aG as p, cY as g, cK as u, o as j } from "./App-CsJiApxN.js";
import { cD as m, bH as y, bu as E, b1 as h } from "./matrix-util-Cr_UwXbj.js";
import { Picker as v } from "./module-CyRk-uWw.js";
import "./sentry-common-BxRELKId.js";
import "./index-Cw3pknxT.js";
import "./index-Dhe7xemD.js";
import "./index-CcYzEQCb.js";
import "./main-process-state-wkFhis-C.js";
import "./report-dialog-7bETf2vU.js";
import "./helpHubMessages-CXhGQ9cB.js";
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
      (t._sentryDebugIds[o] = "3b82341b-42d5-4749-bb61-d137e35ffa92"),
      (t._sentryDebugIdIdentifier =
        "sentry-dbid-3b82341b-42d5-4749-bb61-d137e35ffa92"));
  } catch {}
})();
function D(t) {
  const o = n.useRef(null),
    e = n.useRef(null);
  return (
    e.current && e.current.update(t),
    n.useEffect(
      () => (
        (e.current = new v({ ...t, ref: o })),
        () => {
          e.current = null;
        }
      ),
      [],
    ),
    p.createElement("div", { ref: o })
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
    const i = t?.emojis ?? [];
    if (i.length !== 0) {
      (e.categories.splice(0, 0, { id: c, emojis: i.map((r) => r.id) }),
        (o.I18n.categories[c] = t?.name ?? "Defaults"));
      for (const r of i) e.emojis[r.id] = r;
    }
  },
  A = g(({ onEmojiSelect: t, style: o, customEmojis: e, defaultEmojis: a }) => {
    const { transformedRecentEmoji: i } = m.emojiStore,
      [r, f] = n.useState(!1),
      d = e?.some((s) => s.emojis.length > 0),
      l = n.useMemo(() => {
        if (i) return d ? i : i.filter((s) => !y(s));
      }, [i, d]);
    return (
      n.useEffect(() => {
        let s = !1;
        return (
          f(!1),
          E(e ?? [])
            .then(() => R(a))
            .then(() => {
              s || f(!0);
            })
            .catch((b) => {
              (Sentry.captureException(b), s || f(!0));
            }),
          () => {
            s = !0;
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
            onSkinChange: (s) => m.emojiStore.setSkinTone(s),
            customFrequentlyUsed: { enabled: !0, values: l },
          })
    );
  });
export { A as default };
//# sourceMappingURL=EmojiPicker-B3NwrEhI.js.map
