import {
  cL as i,
  bV as U,
  a_ as O,
  ay as L,
  al as S,
  e8 as B,
  aL as M,
  e9 as V,
  d$ as x,
  N as b,
  T as W,
  cA as z,
  ag as H,
  an as C,
  ea as p,
  a$ as T,
  bt as N,
  dM as I,
  co as Y,
  dF as A,
  bT as Q,
  dc as Z,
  cu as $,
  dI as q,
  O as X,
  cr as j,
  bD as J,
  em as v,
  bW as ee,
  aY as K,
  dV as k,
} from "./App-CsJiApxN.js";
import {
  c7 as P,
  cD as m,
  d as se,
  a2 as te,
  cE as G,
  o as F,
  a7 as R,
} from "./matrix-util-Cr_UwXbj.js";
import "./sentry-common-BxRELKId.js";
import "./index-Cw3pknxT.js";
import "./index-Dhe7xemD.js";
import "./index-CcYzEQCb.js";
import "./main-process-state-wkFhis-C.js";
import "./report-dialog-7bETf2vU.js";
import "./helpHubMessages-CXhGQ9cB.js";
(function () {
  try {
    var d =
      typeof window < "u"
        ? window
        : typeof global < "u"
          ? global
          : typeof globalThis < "u"
            ? globalThis
            : typeof self < "u"
              ? self
              : {};
    d.SENTRY_RELEASE = { id: "4.3.209" };
    var l = new d.Error().stack;
    l &&
      ((d._sentryDebugIds = d._sentryDebugIds || {}),
      (d._sentryDebugIds[l] = "f0214d8c-ba5f-40fc-9054-f92261764a41"),
      (d._sentryDebugIdIdentifier =
        "sentry-dbid-f0214d8c-ba5f-40fc-9054-f92261764a41"));
  } catch {}
})();
function re(d) {
  const a = [
    "input",
    "select",
    "textarea",
    "a[href]",
    "button",
    "[tabindex]:not(slot)",
    "audio[controls]",
    "video[controls]",
    '[contenteditable]:not([contenteditable="false"])',
    "details>summary:first-of-type",
    "details",
  ].join(",");
  return !(
    !d.matches(a) ||
    d.disabled ||
    (d.tagName === "INPUT" && d.type === "hidden") ||
    getComputedStyle(d).visibility === "hidden" ||
    (d.tagName === "INPUT" && d.type === "radio" && !ie(d)) ||
    d.tabIndex < 0 ||
    ae(d)
  );
}
function ie(d) {
  if (!d.name) return !0;
  const a = (d.form || d.getRootNode()).querySelectorAll(
      `input[type="radio"][name="${d.name}"]`,
    ),
    e = Array.from(a).find((r) => r.checked && r.form === d.form);
  return !e || e === d;
}
function ae(d) {
  if (/^(INPUT|BUTTON|SELECT|TEXTAREA)$/.test(d.tagName)) {
    let l = d.parentElement;
    for (; l;) {
      if (l.tagName === "FIELDSET" && l.disabled) {
        for (let a = 0; a < l.children.length; a++) {
          const e = l.children.item(a);
          if (e && e.tagName === "LEGEND") return !e.contains(d);
        }
        return !0;
      }
      l = l.parentElement;
    }
  }
  return !1;
}
var oe = Object.defineProperty,
  ne = Object.getOwnPropertyDescriptor,
  D = (d, l, a, e) => {
    for (
      var r = e > 1 ? void 0 : e ? ne(l, a) : l, s = d.length - 1, t;
      s >= 0;
      s--
    )
      (t = d[s]) && (r = (e ? t(l, a, r) : t(r)) || r);
    return (e && r && oe(l, a, r), r);
  };
const de = k(i.NEW_LINE.key).includes("enter"),
  le = k(i.SEND_MESSAGE.key).includes("enter"),
  he = (d) =>
    d.key
      .toLowerCase()
      .replace("arrow", "")
      .replace("control", "ctrl")
      .replace("meta", "command"),
  ce = (d, l) => {
    if (!d || d === "disabled") return !1;
    const a = he(l);
    return k(d).some((e) => {
      const r = e.split("+"),
        s = r.filter((t) => !H.has(t));
      return s.length !== 1 || s[0] !== a
        ? !1
        : l.metaKey === r.includes("command") &&
            l.ctrlKey === r.includes("ctrl") &&
            l.shiftKey === r.includes("shift") &&
            l.altKey === r.includes("alt");
    });
  };
class _ {
  constructor(l, a) {
    ((this.rs = l),
      (this.wss = a),
      (this.bindHotkeys = () => {
        const { bindHotkey: e } = this.wss.mousetrap,
          r = this.wss.cmdBarViewStore.showWithSubMenu;
        (e(i.OPEN_FIRST_LINK.key, () => {
          if (this.wss.selectedMessagesList.length === 1) {
            const s = this.wss.selectedMessagesList[0];
            if (s.text) {
              const t = U(s.text);
              t.length > 0 && P(t[0].href);
            }
          }
        }),
          e(
            i.OPEN_REACTION_PICKER.key,
            () => {
              (!this.wss.messageInputRef?.isDestroyed &&
                this.wss.messageInputRef?.isFocused) ||
                (this.wss.selectedMessagesList.length === 1 &&
                  this.wss.openReactionMenuForSelectedMessage());
            },
            void 0,
            !1,
          ),
          e(i.QUICK_REACT_SELECTED.key, () => {
            if (
              (!this.wss.messageInputRef?.isDestroyed &&
                this.wss.messageInputRef?.isFocused) ||
              this.wss.selectedMessagesList.length !== 1
            )
              return;
            const s = this.wss.selectedMessagesList[0],
              t = this.wss.selectedThread;
            if (!(t instanceof O)) return;
            const o = this.rs.prefsStore.prefs[L.MESSAGE_DOUBLE_CLICK_REACTION];
            o && t.toggleReaction(s.id, o, "Quick React Keyboard Shortcut");
          }),
          e(i.REPORT_A_PROBLEM.key, () =>
            this.wss.setVisibleModal(S.REPORT_PROBLEM),
          ),
          e(i.TOGGLE_SIDEBAR.key, () => this.wss.toggleSidebar()),
          e(i.TOGGLE_INCOGNITO_MODE.key, () => {
            B(void 0, { source: "Keyboard Shortcut" });
          }),
          e(i.TOGGLE_FILTER_BAR.key, () =>
            this.rs.prefsStore.toggleSpaceSwitcher(),
          ),
          e(i.SEARCH.key, (s) => {
            (this.wss.cmdBarViewStore.showSearch(), s.stopPropagation());
          }),
          e(i.SEARCH_ROOM.key, (s) => {
            this.wss.rightPaneView !== M.PREFS &&
              (this.wss.cmdBarViewStore.showSearch(this.wss.selectedThread?.id),
              s.stopPropagation());
          }),
          e(i.SELECT_NEXT_THREAD.key, this.wss.selectNextThread),
          e(i.SEND_FEEDBACK.key, () => {
            this.wss.selectedThread && this.wss.toggleFeedbackWidget();
          }),
          e(i.SELECT_PREV_THREAD.key, this.wss.selectPrevThread),
          e(i.SELECT_NEXT_UNREAD_THREAD.key, this.wss.selectNextUnreadThread),
          e(i.TOGGLE_THREAD_READ.key, () =>
            this.wss.threadController.toggleThreadRead(
              this.wss.selectedOrCursorThread,
            ),
          ),
          e(i.TOGGLE_THREAD_PIN.key, () =>
            this.wss.threadController.toggleThreadPin(
              this.wss.selectedOrCursorThread,
            ),
          ),
          e(i.TOGGLE_THREAD_MUTE.key, () => {
            const s = this.wss.selectedOrCursorThread;
            s && V(s, void 0, { source: "keyboard-shortcut" });
          }),
          e(
            i.TOGGLE_THREAD_ARCHIVE.key,
            (s, t) => {
              (t === "e" &&
                (this.wss.selectedThread ||
                  ["INPUT", "TEXTAREA", "SELECT"].includes(
                    this.wss.document.activeElement?.nodeName ?? "",
                  ) ||
                  this.wss.document.activeElement?.attributes.getNamedItem(
                    "contenteditable",
                  ))) ||
                (s.preventDefault(),
                this.wss.threadController.toggleThreadArchive(
                  this.wss.selectedOrCursorThread,
                  "pressed keybindings.TOGGLE_THREAD_ARCHIVE",
                ));
            },
            "archive",
            !1,
          ),
          e(i.ARCHIVE_ALL_READ_THREADS.key, () =>
            this.wss.threadController.confirmArchiveAllReadThreads(),
          ),
          e(i.TOGGLE_HOTKEYS_MODAL.key, () =>
            this.wss.toggleVisibleModal(S.HOTKEYS, !1),
          ),
          e(i.TOGGLE_PREFS_PANE.key, () =>
            m.windowsStore.openPrefsInNewWindow(this.wss),
          ),
          e(i.DELETE_THREAD.key, () =>
            this.wss.threadController.confirmDeleteThread(
              this.wss.selectedOrCursorThread,
            ),
          ),
          e(i.RELOAD_APP.key, () => this.rs.windowsStore.reloadAllWindows()),
          e(
            i.QUOTE_AND_REPLY.key,
            () =>
              this.wss.selectedThread &&
              this.rs.quoteAndReply(this.wss, this.wss.selectedThread),
          ),
          e(
            i.QUOTE_INCOMING_MESSAGE_AND_EDIT_OUTGOING_MESSAGE.key,
            (s) => {
              const t = s.target;
              if (
                ["INPUT", "TEXTAREA", "SELECT"].includes(t.nodeName) ||
                t.isContentEditable
              )
                return;
              const o = this.wss.selectedMessagesList;
              !this.wss.selectedThread ||
                o.length !== 1 ||
                (o[0].isSender
                  ? this.wss.messageInputRef?.state.doc.content.size === 2 &&
                    this.wss.selectedThread?.canStartEditMessage(o[0]) &&
                    this.wss.selectedThread?.startEditMessage(o[0].id)
                  : this.rs.quoteAndReply(this.wss, this.wss.selectedThread),
                s.preventDefault());
            },
            void 0,
            !1,
          ),
          e(i.TOGGLE_THREAD_INFO.key, this.wss.toggleThreadInfoVisible),
          e(i.OPEN_PROFILE.key, () => {
            const s = this.wss.selectedThread?.userProfileLink;
            s && P(s);
          }),
          e(i.ZOOM_IN.key, this.rs.zoomManager.zoomIn),
          e(i.ZOOM_OUT.key, this.rs.zoomManager.zoomOut),
          e(i.ZOOM_RESET.key, this.rs.zoomManager.resetZoom));
        for (let s = 1; s <= 9; s++) {
          const t = i.SWITCH_FIRST_9_THREADS.key,
            o = i.SWITCH_FIRST_9_ACCOUNTS.key,
            n = i.SELECT_FIRST_9_COMMANDS.key;
          (o !== "disabled" &&
            e(`${o}+${s}`, () => {
              if (o === n && this.wss.cmdBarViewStore.isVisible) return;
              const { orderedSidebarSpaces: h } = this.rs.accountsStore,
                w = h.filter((u) =>
                  u.type === "account" || u.type === "account-network"
                    ? this.rs.accountsStore.getAccount(u.accountID)?.ai
                        ?.active === !0
                    : !0,
                )[s - 1];
              w && x(this.wss, w, { source: "Keyboard Shortcut" });
            }),
            t !== "disabled" &&
              e(`${t}+${s}`, () => {
                if (t === n && this.wss.cmdBarViewStore.isVisible) return;
                const h = this.wss.chatListItems[s - 1];
                h && this.wss.selectChatListItem(h);
              }));
        }
        (e(i.CREATE_NEW_GROUP.key, () =>
          this.wss.cmdBarViewStore.showCreateNewGroupChatMode(),
        ),
          e(i.CREATE_NEW_CHAT.key, () =>
            this.wss.cmdBarViewStore.showCreateNewChatMode(),
          ),
          e(i.EDIT_MESSAGE.key, () => {
            const { selectedMessagesList: s, selectedThread: t } = this.wss;
            if (!(
              !t ||
              !(
                s.length === 1 ? t.threadForMessage(s[0]) : t
              )?.accountStore.platform.attributes.has(se.SUPPORTS_EDIT_MESSAGE)
            ))
              if (s.length === 1 && t?.canStartEditMessage(s[0])) {
                const n = s[0].id;
                m.scheduledStore.getScheduledMessage(n)
                  ? t.startEditScheduledMessage(n)
                  : t.startEditMessage(n, this.replyThreadRootID);
              } else {
                const n =
                  t &&
                  this.selectableMessages(t).findLast(
                    (h) => h.isSender && (h.attachments?.length || 0) === 0,
                  );
                n &&
                  (t.startEditMessage(n.id, this.replyThreadRootID),
                  s.length === 0 && this.wss.selectMessages([n]));
              }
          }),
          e(i.FILTER_ACCOUNT.key, () => r(b.FILTER_ACCOUNT)),
          e(i.TOGGLE_COMMAND_BAR.key, (s) => {
            (this.wss.cmdBarViewStore.showInNormalMode(), s.stopPropagation());
          }),
          e(i.OPEN_REMIND_LATER_MENU.key, () => {
            const s = W.remindLaterThread(
              void 0,
              [this.wss.selectedThread].filter(Boolean),
            );
            s.canOpen?.() && r(s);
          }),
          e(i.FORWARD_MESSAGES.key, () => {
            b.FORWARD_MESSAGES.canOpen?.()
              ? r(b.FORWARD_MESSAGES)
              : this.rs.addToast(
                  { text: te("Only works when messages are selected") },
                  void 0,
                  "cant-open-forward",
                );
          }),
          e(i.DOWNLOAD_ATTACHMENTS.key, () => {
            this.rs.downloadSelectedMessageAttachments(
              this.wss,
              this.wss?.selectedThread?.computedTitle,
            );
          }),
          e(
            i.SHOW_REPLY_THREAD.key,
            (s) => {
              const {
                selectedThread: t,
                selectedMessagesList: o,
                messageInputRef: n,
              } = this.wss;
              !t ||
                this.wss.document.activeElement === n ||
                (s.stopPropagation(),
                s.preventDefault(),
                o.find((h) =>
                  z(h) && h.linkedMessageID
                    ? (t.showReplyThread(h.linkedMessageID), !0)
                    : t.canReplyInThread(h)
                      ? (t.showThreadedReplies(h.id), !0)
                      : t.replyThreads[h.id]
                        ? (t.showReplyThread(h.id), !0)
                        : !1,
                ));
            },
            void 0,
            !1,
          ),
          e(i.HISTORY_PREV_THREAD.key, () => this.wss.selectHistoryThread(1)),
          e(i.HISTORY_NEXT_THREAD.key, () => this.wss.selectHistoryThread(-1)),
          e(`${i.CYCLE_CHATS.key}, shift+${i.CYCLE_CHATS.key}`, (s) => {
            if (!this.wss.isCyclingChats) {
              G(() => (this.wss.isCyclingChats = !0));
              const t = i.CYCLE_CHATS.key.split("+").filter((n) => H.has(n)),
                o = (n) => {
                  const { modifiers: h, type: c } = n.detail;
                  c === "keyup" &&
                    (t.every((w) => h.includes(w)) ||
                      (this.wss.window.removeEventListener(C, o),
                      G(() => (this.wss.isCyclingChats = !1)),
                      this.wss.selectedThread instanceof O &&
                        this.rs.pushThreadHistory(this.wss.selectedThread)));
                };
              this.wss.window.addEventListener(C, o);
            }
            s.shiftKey
              ? this.wss.selectHistoryThread(-1)
              : this.wss.selectHistoryThread(1);
          }),
          e(i.TOGGLE_FILTER_UNREAD.key, () => {
            p(this.wss, T.UNREAD, { source: "Keyboard" });
          }),
          e(i.TOGGLE_FILTER_DRAFTS.key, () => {
            p(this.wss, T.DRAFTS, { source: "Keyboard" });
          }),
          e(i.TOGGLE_FILTER_UNANSWERED.key, () => {
            p(this.wss, T.UNRESPONDED, { source: "Keyboard" });
          }),
          e(i.TOGGLE_FILTER_DMS.key, () => {
            p(this.wss, T.DM, { source: "Keyboard" });
          }),
          e(i.TOGGLE_FILTER_GROUPS.key, () => {
            p(this.wss, T.GROUP, { source: "Keyboard" });
          }),
          e(i.CLEAR_FILTERS.key, () => {
            N(this.wss, { source: "Keyboard" });
          }),
          e(i.CYCLE_TABS.key, () => {
            const s = this.wss.threadsFilters,
              t = [T.UNREAD, T.DRAFTS, T.UNRESPONDED, T.DM, T.GROUP];
            if (s.size !== 1) {
              I(this.wss, t[0], { source: "Keyboard" });
              return;
            }
            const o = [...s][0],
              n = t.indexOf(o);
            if (n === -1) {
              I(this.wss, t[0], { source: "Keyboard" });
              return;
            }
            n === t.length - 1
              ? N(this.wss, { source: "Keyboard" })
              : I(this.wss, t[n + 1], { source: "Keyboard" });
          }));
      }),
      (this.handleThreadSelection = (e, r) => {
        if (this.wss.cmdBarViewStore.isVisible) return;
        const s = r && e.shiftKey,
          t = e.key.toLowerCase();
        if (t === "arrowup" || t === "k" || (s && t === "["))
          this.selectThreadKeyboard(e.shiftKey, -1);
        else if (t === "arrowdown" || t === "j" || (s && t === "]"))
          this.selectThreadKeyboard(e.shiftKey, 1);
        else if (r && t === "a") {
          e.preventDefault();
          const { filteredThreads: o, selectedSidebarThreads: n } = this.wss;
          (this.wss.setLastSelectedThread(o.at(-1)), n.setArray(o));
        }
      }),
      (this.defaultOnKeyDown = (e) => {
        if (!this.wss.mousetrap.enabled) return;
        const r = e.target;
        if (e.key === "Escape" && !r.closest("#message-input"))
          return this.handleEscape(e);
        if (this.wss.rightPaneView === M.PREFS) return;
        const s = e.metaKey,
          { selectedThread: t, threadSelectionMode: o } = this.wss;
        if (
          (o && this.handleThreadSelection(e, s),
          ["INPUT", "TEXTAREA", "SELECT"].includes(r.nodeName) ||
            r.isContentEditable ||
            o)
        )
          return;
        const n = () => {
          const c = this.wss.getPointedThread();
          (A.track("Chat Selection Begin Selecting", {
            source: "shift-keyboard",
            chatFilter: [...this.wss.spaceFilters],
          }),
            this.wss.toggleThreadSelectionMode(),
            c && this.wss.toggleThreadSelection(c));
        };
        switch (e.key) {
          case "a": {
            if (s && !e.shiftKey && !e.altKey) {
              if ((e.preventDefault(), e.stopPropagation(), t))
                this.wss.selectMessages(this.selectableMessages(t));
              else if (!this.wss.showRequests) {
                A.track("Chat Selection Begin Selecting", {
                  source: "select-all-keyboard",
                  chatFilter: [...this.wss.spaceFilters],
                });
                const { selectedSidebarThreads: c, filteredThreads: w } =
                  this.wss;
                (this.wss.toggleThreadSelectionMode(),
                  this.wss.setLastSelectedThread(w.at(-1)),
                  this.wss.setSelectedThread(w.at(0)),
                  c.setArray(w));
              }
            }
            break;
          }
          case " ": {
            const { carouselState: c, selectedMessagesList: w } = this.wss,
              u = w?.find((E) => (E.attachments?.length ?? -1) > 0 && !Y(E)),
              y = u && this.wss.getQuickLookAttachment(u);
            if (y && !c) {
              e.repeat || this.wss.previewInQuickLook(y, u.id);
              return;
            }
            const f = u?.attachments?.[0]?.id;
            if (f && !c && !this.wss.viewLimitedMediaViewer) {
              this.wss.setCarouselState(f, u.id);
              return;
            }
            break;
          }
          case "j":
          case "J":
          case "ArrowDown":
            if (!t)
              if ((e.preventDefault(), e.shiftKey))
                (n(), this.handleThreadSelection(e, s));
              else {
                this.wss.pointNextThread();
                return;
              }
            break;
          case "k":
          case "K":
          case "ArrowUp":
            if (!t)
              if ((e.preventDefault(), e.shiftKey))
                (n(), this.handleThreadSelection(e, s));
              else {
                this.wss.pointPrevThread();
                return;
              }
            break;
          case "x":
            t || n();
            break;
          case "Enter":
            if (this.wss.threadCursorID && !this.wss.sidebarDisabled) {
              e.preventDefault();
              const c = this.wss.getPointedChatListItem();
              c && this.wss.selectChatListItem(c);
              return;
            }
            break;
          case "z":
            s &&
              (e.shiftKey
                ? this.onModifierShiftZPress()
                : this.onModifierZPress(e));
            break;
        }
        if (t) {
          if (e.metaKey || e.ctrlKey) return;
          if (e.key === "ArrowUp") {
            (this.selectMsgKeyboard(t, e.shiftKey, -1),
              e.stopPropagation(),
              e.preventDefault());
            return;
          }
          if (e.key === "ArrowDown") {
            (this.selectMsgKeyboard(t, e.shiftKey, 1),
              e.stopPropagation(),
              e.preventDefault());
            return;
          }
        }
        if (
          e.metaKey ||
          e.ctrlKey ||
          e.altKey ||
          (e.shiftKey && e.key === "Shift") ||
          this.wss.carouselState ||
          this.wss.viewLimitedMediaViewer
        )
          return;
        const h = Q(Z(this.wss.document, this.wss.messageInputRef?.view.dom));
        h &&
          (h.commands.focus("end"),
          e.key.length === 1 &&
            h.isEditable &&
            (h.commands.insertContent(e.key), e.preventDefault()));
      }),
      (this.messageInputKeyDown = (e) => {
        if (e.key === "Escape") return this.handleEscape(e);
        const r = this.wss.selectedThread,
          s = this.wss.messageInputRef;
        if (r?.hasQueuedMessages && ce(i.UNDO_PENDING_SEND.key, e))
          return (e.preventDefault(), e.stopPropagation(), r.undoSend(), !0);
        if (
          r?.hasDraftAttachments &&
          ((e.key === "Backspace" && $(r?.typedJSON)) ||
            ((e.key === "ArrowLeft" || e.key === "ArrowUp") &&
              s?.state.selection.head === 0))
        )
          return (
            this.wss.selectedThread &&
              q(
                this.wss.document,
                this.wss.selectedThread.pendingAttachmentsMap.size - 1,
              ),
            !1
          );
        const t = r && !s?.getText();
        switch (e.key) {
          case "Enter":
            if (e.shiftKey || e.ctrlKey || e.altKey || e.metaKey) break;
            if (de && r && this.wss.messageInputRef)
              return (j(this.wss.messageInputRef), !0);
            if (le) {
              if ((e.preventDefault(), r?.hasDraft))
                (e.stopPropagation(),
                  this.rs.sendButtonClick(r, this.wss, !1, "hotkey"));
              else {
                const o = this.wss.selectedDraftChat;
                o?.intent === "new-blast"
                  ? o.composerStore.hasDraft &&
                    (e.stopPropagation(),
                    this.rs.startNewChatStore.sendBlast(o.id, this.wss))
                  : o?.composerStore.hasDraft &&
                    !o.composerStore.isCreatingThread &&
                    (e.preventDefault(),
                    e.stopPropagation(),
                    J(
                      o,
                      this.wss,
                      o.composerStore.getMessageContents(),
                      "hotkey",
                    ));
              }
              return !0;
            }
            break;
          case "ArrowUp":
            if (e.altKey || e.metaKey || e.ctrlKey || e.shiftKey) break;
            if (r && (t || s?.state.selection.head === 1)) {
              e.preventDefault();
              const o =
                m.prefsStore.prefs[L.COMPOSER_UP_ARROW_ACTION] ===
                  X.EDIT_LAST_MESSAGE &&
                this.wss.selectedMessagesList.length == 0;
              if ((this.selectMsgKeyboard(r, e.shiftKey, -1), o)) {
                const n = this.selectableMessages(r).findLast(
                  (h) =>
                    h.isSender &&
                    r.canStartEditMessage(h) &&
                    r.canEditMessage(h) &&
                    !r.pendingMessages.has(h.id),
                );
                n && r.startEditMessage(n.id, this.replyThreadRootID);
              }
              return !0;
            }
            break;
          case "ArrowDown":
            if (e.metaKey || e.ctrlKey) break;
            if (t)
              return (
                e.preventDefault(),
                this.selectMsgKeyboard(r, e.shiftKey, 1),
                !0
              );
            break;
          case "z":
            if (e.metaKey)
              return (
                e.shiftKey
                  ? this.onModifierShiftZPress()
                  : this.onModifierZPress(e),
                !1
              );
            break;
        }
      }),
      (this.onModifierZPress = async (e) => {
        (this.rs.undoLastToast() ||
          ((!(e.target instanceof HTMLElement) ||
            !e.target.closest(
              'input, textarea, select, [contenteditable="true"]',
            )) &&
            v()),
          this.wss.selectedThread?.undoSend());
      }),
      (this.onModifierShiftZPress = () => {
        this.wss.selectedThread?.sendQueuedMessages();
      }),
      a.window.addEventListener("keydown", this.defaultOnKeyDown),
      this.bindHotkeys());
  }
  selectThreadKeyboard(l, a) {
    const { filteredThreads: e, selectedSidebarThreads: r } = this.wss,
      s = e.findIndex((n) => r.has(n.uniqueThreadID)),
      t = ee(e, (n) => r.has(n.uniqueThreadID)),
      o = (n, h = !1) => {
        const c = e[n + a];
        c &&
          (h && r.clear(),
          r.upsertBottom(c),
          this.wss.scrollThreadsListToItem(
            this.wss.filteredThreadsIndexMap.get(c.uniqueThreadID),
          ));
      };
    if (r.length > 0)
      if (l) {
        const n = a > 0 ? t : s;
        o(n);
      } else o(t, !0);
    else o(r.length);
  }
  get replyThreadRootID() {
    return this.rs.windowsStore.getBaseBrowserWindowFromMap(this.wss.window)
      ?.replyThreadRootID;
  }
  selectableMessages(l) {
    const a = this.replyThreadRootID;
    return a ? l.getReplyThreadListData(a).messages : l.selectableMessages;
  }
  selectMsgKeyboard(l, a, e) {
    const { wss: r } = this,
      s = this.selectableMessages(l),
      t = s.findIndex((f) => r.selectedMessagesSet.has(f.id)),
      o = s.findLastIndex((f) => r.selectedMessagesSet.has(f.id)),
      n = (f) => r.messageListHandle?.galleryMessagesFor(f.id),
      h = s[o],
      c = h && n(h),
      w =
        !!c &&
        r.selectedMessagesSet.size === c.length &&
        c.every((f) => r.selectedMessagesSet.has(f.id));
    let u;
    const y = (f, E = !1) => {
      const g = s[f + e];
      g &&
        (E && r.unselectAllMessages(), r.selectMessages(n(g) ?? [g]), (u = g));
    };
    if (r.selectedMessagesSet.size > 0)
      if (a) {
        const f = e > 0 ? o : t;
        y(f);
      } else {
        if (e === 1 && o === s.length - 1) {
          (r.unselectAllMessages(), r.focusMessageInput());
          return;
        }
        y(w && e < 0 ? t : o, !0);
      }
    else {
      const f = l.unreadDividerMessageSortKey;
      if (e === 1 && f !== void 0) {
        const E = s.find((g) => g.sortKey && g.sortKey > f);
        E ? (r.selectMessages(n(E) ?? [E]), (u = E)) : y(s.length);
      } else y(s.length);
    }
    ((r.selectedMessagesSet.size === 0 && e === 1) || r.focusMessageInput(!1),
      u &&
        m.focusedWSS?.messageListHandle?.scrollToSortKey(
          u.sortKey,
          u.threadID,
          { align: "nearest" },
        ));
  }
  handleEscape(l) {
    l.preventDefault();
    const { wss: a } = this,
      { selectedThread: e } = a,
      r = this.rs.windowsStore.getBaseBrowserWindowFromMap(a.window);
    if (r) {
      if (e?.clearThreadedReplyEditing(r.replyThreadRootID)) return !0;
      r.onEscapePressed();
      return;
    }
    if (this.wss.cmdBarViewStore.isVisible)
      return this.wss.cmdBarViewStore.reset();
    if (this.wss.threadSelectionMode)
      return (
        A.track("Chat Selection Cancel", { source: "escape-key" }),
        a.setSelectedThread(null),
        this.wss.toggleThreadSelectionMode()
      );
    if (
      a.visibleModal !== null &&
      [S.HOTKEYS, S.REPORT_PROBLEM, S.SHOW_RECOVERY_KEY].includes(
        a.visibleModal,
      )
    )
      return a.hideVisibleModal();
    if (a.visibleModal !== S.SUBSCRIPTION_PROMPT_MODAL) {
      if (e)
        return a.popoverOpen
          ? !0
          : e?.quotedMessage
            ? (e.clearQuotedMessage(), !0)
            : e?.editingMessageID
              ? (e.clearEditingMessage(), this.wss.focusMessageInput(!1))
              : (e.clearThreadedReplyEditing(e.openThreadedRepliesRootID) ||
                  (a.selectedMessagesSet.size === 0 && e?.openReplyThread
                    ? e.hideReplyThread()
                    : a.selectedMessagesSet.size === 0 && e.openThreadedReplies
                      ? e.hideThreadedReplies()
                      : a.selectedMessagesSet.size === 0 &&
                        i.UNSELECT_THREAD.key !== "disabled" &&
                        !a.isSubWindow &&
                        (a.setSelectedThread(null), a.pointCurrentThread()),
                  a.unselectAllMessages(),
                  this.wss.focusMessageInput(!1)),
                !0);
      if (this.wss.rightPaneView === M.PREFS) {
        const s = a.document.activeElement;
        re(s) ? s.blur() : a.window.close();
      } else if (this.wss.rightPaneView === M.UNREAD_THREADS) {
        if (a.popoverOpen || a.cancelUnreadThreadEdit?.()) return !0;
        a.setRightPaneView(null);
      } else if (this.wss.selectedDraftChat) {
        const s = this.wss.selectedDraftChat;
        s.intent === "join-matrix-room"
          ? this.rs.startNewChatStore.exitMatrixRoomJoinMode(s.id) &&
            this.wss.setSelectedDraftChat(null)
          : this.wss.setSelectedDraftChat(null);
      } else if (this.rs.inboxName !== F.NORMAL) this.rs.setInboxName(F.NORMAL);
      else if (this.wss.visibleThreadPane !== K.NONE)
        this.wss.visibleThreadPane = K.NONE;
      else if (this.rs.toasts.firstItem?.id) {
        const s = this.rs.toasts.firstItem?.id;
        this.rs.removeToast(s);
      } else
        a.threadsForThreadList.threads[0]
          ? a.setThreadCursorIDByThread(a.threadsForThreadList.threads[0])
          : a.setThreadCursorID(0);
    }
  }
}
D([R], _.prototype, "selectThreadKeyboard", 1);
D([R], _.prototype, "selectMsgKeyboard", 1);
D([R], _.prototype, "handleThreadSelection", 2);
D([R], _.prototype, "handleEscape", 1);
export { _ as default };
//# sourceMappingURL=KeyboardHandlers-BqsA6rNb.js.map
