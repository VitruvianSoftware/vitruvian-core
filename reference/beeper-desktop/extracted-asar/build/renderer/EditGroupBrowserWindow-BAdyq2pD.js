import {
  cY as V,
  dk as l,
  ew as Z,
  cK as t,
  am as U,
  y as ee,
  s as R,
  b1 as te,
  dL as ae,
  dK as re,
  a1 as oe,
  cS as se,
  e4 as _,
  eD as ie,
  aM as A,
  $ as ne,
  b6 as de,
  aX as le,
  aR as ce,
  dE as L,
  l as ue,
} from "./App-CsJiApxN.js";
import { a1 as B, a7 as pe } from "./sentry-common-BxRELKId.js";
import {
  cD as G,
  cP as z,
  a2 as o,
  a6 as g,
  q as me,
  ac as he,
} from "./matrix-util-Cr_UwXbj.js";
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
      (s._sentryDebugIds[c] = "2770e1e8-0819-4b84-9523-fde9fb7a1a68"),
      (s._sentryDebugIdIdentifier =
        "sentry-dbid-2770e1e8-0819-4b84-9523-fde9fb7a1a68"));
  } catch {}
})();
const fe = "EditGroupModal-module__container",
  ve = "EditGroupModal-module__dropzone",
  ge = "EditGroupModal-module__smallText",
  xe = "EditGroupModal-module__removePhoto",
  ye = "EditGroupModal-module__buttons",
  Ee = "EditGroupModal-module__savingButton",
  be = "EditGroupModal-module__avatar",
  we = "EditGroupModal-module__editAvatar",
  n = {
    container: fe,
    dropzone: ve,
    smallText: ge,
    removePhoto: xe,
    buttons: ye,
    savingButton: Ee,
    avatar: be,
    editAvatar: we,
  },
  F = (s) => {
    G.addToast(
      { text: s, visibleWindowName: G.windowsStore.focusedWindowName },
      2e3,
      void 0,
      !0,
    );
  },
  Te = V(
    ({ accountID: s, groupThreadID: c, mode: m = "everyone", onClose: p }) => {
      const e = G.accountsStore.getAccount(s)?.currentInbox.getThread(c),
        r = m === "personal",
        j = r ? (e?.personalTitle ?? "") : (e?.title ?? e?.computedTitle ?? ""),
        x = r ? e?.effectivePersonalImgURL : e?.imgURL,
        I = l.useRef(null),
        y = l.useRef(null),
        [S, E] = l.useState(!1),
        [h, P] = l.useState(j),
        [b, D] = l.useState(e?.description ?? ""),
        [u, f] = l.useState(x);
      l.useEffect(() => {
        (E(!1),
          P(r ? e?.personalTitle || "" : e?.title || e?.computedTitle || ""),
          D(e?.description || ""),
          f(r ? e?.effectivePersonalImgURL : e?.imgURL),
          r && I.current?.select());
      }, [e, r]);
      const w = h !== j,
        C = !r && b !== e?.description,
        T = u !== x,
        M = w || C || T,
        v = r || !!e?.canCurrentUserEditAvatar,
        k = r || !!e?.canCurrentUserEditTitle,
        N = async () => {
          try {
            await L(_, { recursive: !0, force: !0 });
          } catch (a) {
            logger.error("Failed to cleanup temp avatar directory", a);
          }
        },
        W = async () => {
          const a = y.current;
          if (a) {
            y.current = null;
            try {
              await L(a, { force: !0 });
            } catch (i) {
              logger.error("Failed to cleanup dropped avatar file", i);
            }
          }
        },
        O = async () => {
          (await N(), p());
        },
        H = async () => {
          if (!(!M || !e)) {
            if (r) {
              (w && ae(e, h.trim() || null, { source: "Edit Chat Modal" }),
                T &&
                  re(e, u || null, { source: "Edit Chat Modal" }).finally(() =>
                    W(),
                  ),
                p());
              return;
            }
            try {
              E(!0);
              const a = {};
              (w && (a.title = h),
                C && (a.description = b),
                T && (a.imgURL = u ?? ""),
                await e?.updateGroup(a),
                await N(),
                p());
            } catch (a) {
              (logger.error(a), F(o("Failed to update group")));
            } finally {
              E(!1);
            }
          }
        },
        $ = async () => {
          const { filePaths: a } = await he.showOpenDialog({
              properties: ["openFile"],
              filters: [{ name: o("Images"), extensions: oe }],
            }),
            i = a[0];
          if (!i) return;
          const d = B.pathToFileURL(i).href;
          f(d);
        },
        K = async (a) => {
          const i = a[0];
          if (i)
            try {
              await se(_, { recursive: !0 });
              const d = pe.join(_, i.name),
                J = await i.arrayBuffer();
              (await ie(d, new Uint8Array(J)), (y.current = d));
              const Q = B.pathToFileURL(d).href;
              f(Q);
            } catch (d) {
              (logger.error("Failed to save dropped avatar file", d),
                F(o("Failed to upload image")));
            }
        },
        { getRootProps: X, isDragActive: Y } = Z({
          onDrop: K,
          accept: { "image/*": [] },
          disabled: !v,
        });
      if (!e || (!r && !e.isGroup))
        return t.jsx(U, {
          children: t.jsx("div", {
            className: n.container,
            onClick: z,
            children: r ? o("Chat not found") : o("Group not found"),
          }),
        });
      const q = () => {
        if (u) return t.jsx(A, { isGroup: e.isGroup, src: u, size: 64 });
        if (x) {
          const a = r ? e.imgURL : void 0;
          return a
            ? t.jsx(A, { isGroup: e.isGroup, src: a, size: 64 })
            : e.isGroup
              ? t.jsx(ne, { participants: e.activeParticipants, size: 64 })
              : t.jsx(de, {
                  user: e.activeParticipants.find((i) => !i.isSelf),
                  size: 64,
                });
        }
        return t.jsx(le, {
          size: 64,
          thread: e,
          "data-sentry-element": "ThreadAvatar",
          "data-sentry-component": "avatarPreview",
          "data-sentry-source-file": "EditGroupModal.tsx",
        });
      };
      return t.jsxs(U, {
        children: [
          t.jsxs("div", {
            ...X(),
            className: n.container,
            onClick: z,
            children: [
              Y &&
                t.jsx("div", {
                  className: n.dropzone,
                  children: o("Drop image here to upload"),
                }),
              t.jsxs("div", {
                className: n.avatar,
                onClick: v ? $ : void 0,
                children: [
                  q(),
                  v &&
                    t.jsx("div", {
                      className: n.editAvatar,
                      children: g("Edit", "group avatar edit action"),
                    }),
                ],
              }),
              v &&
                u &&
                t.jsx(ee, {
                  link: !0,
                  size: "xs",
                  className: n.removePhoto,
                  onClick: () => f(void 0),
                  children: o("Remove Photo"),
                }),
              t.jsx("input", {
                ref: I,
                value: h,
                onChange: (a) => {
                  P(a.currentTarget.value);
                },
                placeholder: r
                  ? (e.canonicalTitle ?? o("Chat Name"))
                  : o("Group Title"),
                maxLength: r ? me : void 0,
                disabled: !k,
              }),
              r
                ? t.jsx("span", {
                    className: n.smallText,
                    children: o(
                      "This name and photo are only visible to you, on all your devices.",
                    ),
                  })
                : t.jsxs(t.Fragment, {
                    children: [
                      t.jsx("textarea", {
                        value: b,
                        onChange: (a) => {
                          D(a.currentTarget.value);
                        },
                        placeholder: o("Group Description"),
                        disabled: !e.canCurrentUserEditDescription,
                      }),
                      t.jsx("span", {
                        className: n.smallText,
                        children: o(
                          "The group description is visible to members of this group and people invited to this group.",
                        ),
                      }),
                    ],
                  }),
              t.jsxs("div", {
                className: n.buttons,
                children: [
                  t.jsx(R, {
                    size: "standard",
                    variant: "muted",
                    onClick: O,
                    disabled: S,
                    children: g("Cancel", "edit group modal button"),
                  }),
                  S
                    ? t.jsx(_e, {})
                    : t.jsx(R, {
                        size: "standard",
                        variant: "primary",
                        disabled: !M,
                        onClick: H,
                        children: g("Save", "edit group modal button"),
                      }),
                ],
              }),
            ],
          }),
          t.jsx(te, { matchWindowName: !0 }),
        ],
      });
    },
  ),
  _e = () =>
    t.jsx(R, {
      size: "standard",
      variant: "primary",
      disabled: !0,
      "data-sentry-element": "BrandButton",
      "data-sentry-component": "SavingButton",
      "data-sentry-source-file": "EditGroupModal.tsx",
      children: t.jsxs("div", {
        className: n.savingButton,
        children: [
          g("Saving", "edit group modal button"),
          " ",
          t.jsx(ce, {
            "data-sentry-element": "SpinnerIcon",
            "data-sentry-source-file": "EditGroupModal.tsx",
          }),
        ],
      }),
    });
class Ue extends ue {
  constructor(c, m, p = "everyone") {
    (super(), (this.accountID = c), (this.groupThreadID = m), (this.mode = p));
  }
  get id() {
    return `edit_group_${this.mode}_${this.accountID}_${this.groupThreadID}`;
  }
  get title() {
    return this.mode === "personal" ? o("Edit Chat for Me") : o("Edit Group");
  }
  get windowFeatures() {
    return {
      width: 313,
      height: this.mode === "personal" ? 358 : 447,
      resizable: !1,
      toolbar: !1,
      center: "parent",
    };
  }
  render() {
    return t.jsx(Te, {
      accountID: this.accountID,
      groupThreadID: this.groupThreadID,
      mode: this.mode,
      onClose: () => this.close(),
      "data-sentry-element": "EditGroupModal",
      "data-sentry-component": "EditGroupBrowserWindow",
      "data-sentry-source-file": "EditGroupBrowserWindow.tsx",
    });
  }
  onEscapePressed() {
    this.close();
  }
}
export { Ue as EditGroupBrowserWindow };
//# sourceMappingURL=EditGroupBrowserWindow-BAdyq2pD.js.map
