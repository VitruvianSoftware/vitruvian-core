import {
  cT as Q,
  de as c,
  ep as V,
  cF as t,
  ai as U,
  x as ee,
  r as R,
  aY as te,
  dF as ae,
  dE as re,
  a2 as se,
  cN as oe,
  dZ as E,
  ew as ne,
  aH as B,
  _ as ie,
  b1 as de,
  aS as ce,
  aM as le,
  dy as L,
  k as ue,
} from "./App-BHgTsVmv.js";
import { a3 as F, a9 as pe } from "./sentry-common-BNqrY_yc.js";
import {
  cA as j,
  cM as z,
  a1 as s,
  a5 as v,
  p as me,
  ab as he,
} from "./matrix-util-8DbIGEm-.js";
import "./index-Cw3pknxT.js";
import "./index-Ch31Akxs.js";
import "./index-5FBEE1WD.js";
import "./main-process-state-BDOn7dvV.js";
import "./report-dialog-C-g_klPx.js";
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
    var l = new o.Error().stack;
    l &&
      ((o._sentryDebugIds = o._sentryDebugIds || {}),
      (o._sentryDebugIds[l] = "77f98640-11ab-4f07-8e01-8a927dbf0fca"),
      (o._sentryDebugIdIdentifier =
        "sentry-dbid-77f98640-11ab-4f07-8e01-8a927dbf0fca"));
  } catch {}
})();
const fe = "_container_1w9ng_1",
  ge = "_dropzone_1w9ng_13",
  ve = "_smallText_1w9ng_52",
  xe = "_removePhoto_1w9ng_59",
  ye = "_buttons_1w9ng_63",
  we = "_savingButton_1w9ng_73",
  _e = "_avatar_1w9ng_80",
  be = "_editAvatar_1w9ng_87",
  i = {
    container: fe,
    dropzone: ge,
    smallText: ve,
    removePhoto: xe,
    buttons: ye,
    savingButton: we,
    avatar: _e,
    editAvatar: be,
  },
  M = (o) => {
    j.addToast(
      { text: o, visibleWindowName: j.windowsStore.focusedWindowName },
      2e3,
      void 0,
      !0,
    );
  },
  Te = Q(
    ({ accountID: o, groupThreadID: l, mode: m = "everyone", onClose: p }) => {
      const e = j.accountsStore.getAccount(o)?.currentInbox.getThread(l),
        r = m === "personal",
        I = r ? (e?.personalTitle ?? "") : (e?.title ?? e?.computedTitle ?? ""),
        x = r ? e?.effectivePersonalImgURL : e?.imgURL,
        S = c.useRef(null),
        y = c.useRef(null),
        [P, w] = c.useState(!1),
        [h, C] = c.useState(I),
        [_, D] = c.useState(e?.description ?? ""),
        [u, f] = c.useState(x);
      c.useEffect(() => {
        (w(!1),
          C(r ? e?.personalTitle || "" : e?.title || e?.computedTitle || ""),
          D(e?.description || ""),
          f(r ? e?.effectivePersonalImgURL : e?.imgURL),
          r && S.current?.select());
      }, [e, r]);
      const b = h !== I,
        G = !r && _ !== e?.description,
        T = u !== x,
        N = b || G || T,
        g = r || !!e?.canCurrentUserEditAvatar,
        k = r || !!e?.canCurrentUserEditTitle,
        A = async () => {
          try {
            await L(E, { recursive: !0, force: !0 });
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
            } catch (n) {
              logger.error("Failed to cleanup dropped avatar file", n);
            }
          }
        },
        H = async () => {
          (await A(), p());
        },
        O = async () => {
          if (!(!N || !e)) {
            if (r) {
              (b && ae(e, h.trim() || null, { source: "Edit Chat Modal" }),
                T &&
                  re(e, u || null, { source: "Edit Chat Modal" }).finally(() =>
                    W(),
                  ),
                p());
              return;
            }
            try {
              w(!0);
              const a = {};
              (b && (a.title = h),
                G && (a.description = _),
                T && (a.imgURL = u ?? ""),
                await e?.updateGroup(a),
                await A(),
                p());
            } catch (a) {
              (logger.error(a), M(s("Failed to update group")));
            } finally {
              w(!1);
            }
          }
        },
        $ = async () => {
          const { filePaths: a } = await he.showOpenDialog({
              properties: ["openFile"],
              filters: [{ name: s("Images"), extensions: se }],
            }),
            n = a[0];
          if (!n) return;
          const d = F.pathToFileURL(n).href;
          f(d);
        },
        X = async (a) => {
          const n = a[0];
          if (n)
            try {
              await oe(E, { recursive: !0 });
              const d = pe.join(E, n.name),
                q = await n.arrayBuffer();
              (await ne(d, new Uint8Array(q)), (y.current = d));
              const J = F.pathToFileURL(d).href;
              f(J);
            } catch (d) {
              (logger.error("Failed to save dropped avatar file", d),
                M(s("Failed to upload image")));
            }
        },
        { getRootProps: Y, isDragActive: K } = V({
          onDrop: X,
          accept: { "image/*": [] },
          disabled: !g,
        });
      if (!e || (!r && !e.isGroup))
        return t.jsx(U, {
          children: t.jsx("div", {
            className: i.container,
            onClick: z,
            children: r ? s("Chat not found") : s("Group not found"),
          }),
        });
      const Z = () => {
        if (u) return t.jsx(B, { isGroup: e.isGroup, src: u, size: 64 });
        if (x) {
          const a = r ? e.imgURL : void 0;
          return a
            ? t.jsx(B, { isGroup: e.isGroup, src: a, size: 64 })
            : e.isGroup
              ? t.jsx(ie, { participants: e.activeParticipants, size: 64 })
              : t.jsx(de, {
                  user: e.activeParticipants.find((n) => !n.isSelf),
                  size: 64,
                });
        }
        return t.jsx(ce, {
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
            ...Y(),
            className: i.container,
            onClick: z,
            children: [
              K &&
                t.jsx("div", {
                  className: i.dropzone,
                  children: s("Drop image here to upload"),
                }),
              t.jsxs("div", {
                className: i.avatar,
                onClick: g ? $ : void 0,
                children: [
                  Z(),
                  g &&
                    t.jsx("div", {
                      className: i.editAvatar,
                      children: v("Edit", "group avatar edit action"),
                    }),
                ],
              }),
              g &&
                u &&
                t.jsx(ee, {
                  link: !0,
                  size: "xs",
                  className: i.removePhoto,
                  onClick: () => f(void 0),
                  children: s("Remove Photo"),
                }),
              t.jsx("input", {
                ref: S,
                value: h,
                onChange: (a) => {
                  C(a.currentTarget.value);
                },
                placeholder: r
                  ? (e.canonicalTitle ?? s("Chat Name"))
                  : s("Group Title"),
                maxLength: r ? me : void 0,
                disabled: !k,
              }),
              r
                ? t.jsx("span", {
                    className: i.smallText,
                    children: s(
                      "This name and photo are only visible to you, on all your devices.",
                    ),
                  })
                : t.jsxs(t.Fragment, {
                    children: [
                      t.jsx("textarea", {
                        value: _,
                        onChange: (a) => {
                          D(a.currentTarget.value);
                        },
                        placeholder: s("Group Description"),
                        disabled: !e.canCurrentUserEditDescription,
                      }),
                      t.jsx("span", {
                        className: i.smallText,
                        children: s(
                          "The group description is visible to members of this group and people invited to this group.",
                        ),
                      }),
                    ],
                  }),
              t.jsxs("div", {
                className: i.buttons,
                children: [
                  t.jsx(R, {
                    size: "standard",
                    variant: "muted",
                    onClick: H,
                    disabled: P,
                    children: v("Cancel", "edit group modal button"),
                  }),
                  P
                    ? t.jsx(Ee, {})
                    : t.jsx(R, {
                        size: "standard",
                        variant: "primary",
                        disabled: !N,
                        onClick: O,
                        children: v("Save", "edit group modal button"),
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
  Ee = () =>
    t.jsx(R, {
      size: "standard",
      variant: "primary",
      disabled: !0,
      "data-sentry-element": "BrandButton",
      "data-sentry-component": "SavingButton",
      "data-sentry-source-file": "EditGroupModal.tsx",
      children: t.jsxs("div", {
        className: i.savingButton,
        children: [
          v("Saving", "edit group modal button"),
          " ",
          t.jsx(le, {
            "data-sentry-element": "SpinnerIcon",
            "data-sentry-source-file": "EditGroupModal.tsx",
          }),
        ],
      }),
    });
class Ae extends ue {
  constructor(l, m, p = "everyone") {
    (super(), (this.accountID = l), (this.groupThreadID = m), (this.mode = p));
  }
  get id() {
    return `edit_group_${this.mode}_${this.accountID}_${this.groupThreadID}`;
  }
  get title() {
    return this.mode === "personal" ? s("Edit Chat for Me") : s("Edit Group");
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
export { Ae as EditGroupBrowserWindow };
//# sourceMappingURL=EditGroupBrowserWindow-DAUkNHXs.js.map
