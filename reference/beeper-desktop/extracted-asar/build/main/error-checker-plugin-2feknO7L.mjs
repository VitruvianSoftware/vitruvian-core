import { promises as S } from "fs";
import j from "path";
import { I as d, p as N } from "./index-BJhQkpW6.mjs";
import k from "util";
import "child_process";
import { a6 as M, e as T, g as w } from "./Keychain-CHHka2u7.mjs";
import { a as _ } from "./sentry-enabled-COAVq6nC.mjs";
import "crypto";
import "worker_threads";
import "http";
import "stream";
import "zlib";
import "buffer";
import "./_commonjsHelpers-CBUqixCJ.mjs";
import "events";
import "https";
import "net";
import "tls";
import "url";
import "perf_hooks";
import "./AsyncSqlite-CpInlfQ-.mjs";
import "os";
import "./index-DKkZ9dV1.mjs";
import "./constants-BL_pdRyX.mjs";
import "./machine-id-DFkLVgcU.mjs";
import "./package-CIHfweXK.mjs";
import "./sentry-common-CDPx3Glo.mjs";
import "./index-CNG_AM8w.mjs";
import "timers/promises";
import "./logger-DoW0T1f3.mjs";
import "async_hooks";
import "stream/promises";
import "node:fs/promises";
import "node:crypto";
import "./index-B_PiTES1.mjs";
import "node:util";
import "node:stream";
import "node:child_process";
import "node:path";
import "node:events";
import "node:os";
import "./index-C7dxdDjs.mjs";
import "node:url";
import "node:fs";
import "node:string_decoder";
import "./util-CrY9x2BW.mjs";
import "./index-DaNOOrJg.mjs";
import "fs/promises";
import "./index-CMOlVndj.mjs";
import "assert";
import "./utils-D8MokWSu.mjs";
import "./index-BiKiNEmj.mjs";
import "node:module";
import "./register-proxy-7lV9pun2.mjs";
import "domain";
import "./index-BiHJsdYm.mjs";
import "./rolling-logger-C9NTeNo3.mjs";
import "./startup-checkpoints-BQimOHWq.mjs";
import "./got-_wC7Q_ix.mjs";
import "dns";
import "http2";
import "module";
import "./index-8JaOpgio.mjs";
import "node:worker_threads";
import "tty";
import "better-sqlite3";
(function () {
  try {
    var f =
      typeof window < "u"
        ? window
        : typeof global < "u"
          ? global
          : typeof globalThis < "u"
            ? globalThis
            : typeof self < "u"
              ? self
              : {};
    f.SENTRY_RELEASE = { id: "4.3.209" };
    var u = new f.Error().stack;
    u &&
      ((f._sentryDebugIds = f._sentryDebugIds || {}),
      (f._sentryDebugIds[u] = "841fbcef-ed4c-4cb6-af6a-615ca76cf0aa"),
      (f._sentryDebugIdIdentifier =
        "sentry-dbid-841fbcef-ed4c-4cb6-af6a-615ca76cf0aa"));
  } catch {}
})();
function Be(f, u) {
  process.env.DONT_NOTIFY || _;
  const h = j.join(f, "error-checker.log");
  function a(i, s, o, ...r) {
    const t = k.format(i, o, ...r);
    (logger.log(N.red(t)),
      S.appendFile(
        h,
        `${new Date().toLocaleString()}: ${t}
`,
      ),
      globalThis.Sentry.captureEvent({ message: o, extra: { context: i } }));
  }
  function c(i, s, o) {
    const r = new Set(),
      t = new Set();
    if (
      (i?.forEach((e) => {
        (r.has(e.id) && t.add(e.id), r.add(e.id));
      }),
      t.size &&
        a(
          o,
          1,
          `found ${t.size} duplicate ${s}(s) in ${i.length} ${s}s`,
          [...t].join("|"),
          i.map((e) => e.id).join("|"),
        ),
      s === "message")
    )
      for (const e of i) e.reactions && c(e.reactions, "m.reactions", o);
  }
  function y(i, s) {
    i.some((r, t) => {
      const e = i[t - 1];
      if (!e) return;
      const m = r.sortKey ?? r.timestamp,
        n = e.sortKey ?? e.timestamp,
        p = m < n;
      return (p && logger.log(m, n, r.text, e.text), p);
    }) &&
      a(
        s,
        1,
        "wrong message sort",
        i.map((r) => [r.sortKey ?? r.timestamp, r.text]),
      );
  }
  function b(i, s) {
    (!i &&
      s.methodName !== "searchMessages" &&
      a(s, 0, "participants is falsey"),
      i?.forEach((o, r) => {
        (o || a(s, 0, `participants[${r}] is falsey`),
          o.id || a(s, 0, `invalid participants[${r}].id: ${o.id}`));
      }));
  }
  function v(i, s, o = !0) {
    (i?.id || a(s, 0, `invalid thread.id ${i.id}`),
      i.timestamp &&
        (!(i.timestamp instanceof Date) || isNaN(i.timestamp.getTime())) &&
        a(s, 0, `invalid thread.timestamp ${i.timestamp}`),
      o &&
        !i.messages?.items &&
        a(s, 0, "invalid thread.messages.items", i.messages));
  }
  const I = (i) => u[i]?.attributes.has(w.DEFINES_MESSAGE_CURSOR);
  function $(i, s) {
    const o =
        u[s.platformName]?.reactions?.allowsMultipleReactionsToSingleMessage,
      { participantID: r, reactionKey: t } = i,
      e = `${r}${t}`;
    if (o && i.id !== e)
      return a(
        s,
        1,
        `invalid message reaction id ${i.id}: should be \${participantID}\${reactionKey}`,
        i,
      );
    if (i.id !== e && i.id !== r)
      return a(
        s,
        1,
        `invalid message reaction id ${i.id}: should be \${participantID}\${reactionKey} or \${participantID}`,
        i,
      );
    if (!i.reactionKey)
      return a(s, 1, `invalid message reaction id ${i.id}: key is missing`, i);
  }
  function l(i, s) {
    (!i && s.methodName !== "searchMessages" && a(s, 0, "messages is falsey"),
      i?.forEach((o, r) => {
        (o || a(s, 0, `messages[${r}] is falsey`),
          o.id || a(s, 0, `invalid messages[${r}].id: ${o.id}`),
          I(s.platformName) &&
            !(s.objectName === "message" && s.mutationType === "update") &&
            !o.cursor &&
            a(
              s,
              0,
              `platform attributes include \`Attribute.DEFINES_MESSAGE_CURSOR\`, invalid messages[${r}].cursor: ${o.cursor}`,
            ),
          "timestamp" in o &&
            (!(o.timestamp instanceof Date) || isNaN(o.timestamp.getTime())) &&
            a(s, 0, `invalid message.timestamp ${o.id} ${o.timestamp}`, o),
          o.linkedMessageThreadID &&
            s.threadID &&
            o.linkedMessageThreadID === s.threadID &&
            a(
              s,
              1,
              `messages[${r}].linkedMessageThreadID is same as message threadID, should be null`,
              o,
            ),
          o.attachments?.forEach((t, e) => {
            (t || a(s, 0, `falsey messages[${r}].attachments[${e}]: ${t}`),
              t.id ||
                a(s, 1, `falsey messages[${r}].attachments[${e}].id: ${t.id}`),
              typeof t.id != "string" &&
                a(
                  s,
                  1,
                  `invalid messages[${r}].attachments[${e}].id: ${typeof t.id}`,
                ),
              (t.size?.height === 0 || t.size?.width === 0) &&
                a(
                  s,
                  1,
                  `invalid messages[${r}].attachments[${e}].size: ${t.size.width}x${t.size.height}`,
                  t.id,
                ),
              [T.IMG, T.VIDEO].includes(t.type) &&
                !t.size?.height &&
                a(
                  s,
                  2,
                  `invalid messages[${r}].attachments[${e}].size.height: ${t.size?.width}x${t.size?.height}`,
                  t.id,
                ));
          }),
          o.reactions?.forEach((t, e) => {
            (t || a(s, 0, `falsey messages[${r}].reactions[${e}]: ${t}`),
              $(t, s));
          }));
      }));
  }
  function D(i, s) {
    (v(s, i),
      l(s.messages.items, i),
      b(s.participants.items, i),
      y(s.messages.items, i),
      c(s.messages.items, "message", i),
      c(s.participants.items, "participant", i));
  }
  return {
    type: "output",
    hooks: {
      getCurrentUser(i, s, o, r) {
        return (
          r ||
            a(
              { methodName: "getCurrentUser", platformName: i, accountID: s },
              0,
              "user is falsey",
            ),
          d
        );
      },
      getThread(i, s, o, r) {
        if (typeof r == "object") {
          const t = r,
            e = {
              methodName: "getThread",
              platformName: i,
              accountID: s,
              threadID: r.id,
            };
          D(e, t);
        }
        return d;
      },
      getThreads(i, s, o, r) {
        const t = r.items;
        t.forEach((m) => {
          const n = {
            methodName: "getThreads",
            platformName: i,
            accountID: s,
            threadID: m.id,
          };
          D(n, m);
        });
        const e = { methodName: "getThreads", platformName: i, accountID: s };
        return (
          c(t, "thread", e),
          r.hasMore &&
            r.oldestCursor == null &&
            a(e, 0, "oldest cursor is null while hasMore is true"),
          d
        );
      },
      getMessages(i, s, o, r) {
        const t = {
          methodName: "getMessages",
          platformName: i,
          accountID: s,
          threadID: o[0],
        };
        return (c(r.items, "message", t), y(r.items, t), l(r.items, t), d);
      },
      searchMessages(i, s, o, r) {
        if (r) {
          const t = {
            methodName: "searchMessages",
            platformName: i,
            accountID: s,
            threadID: o[0],
          };
          (c(r.items, "message", t), l(r.items, t));
        }
        return d;
      },
      subscribeToEvents(i, s, o, r) {
        const t = {
          platformName: i,
          accountID: s,
          methodName: "subscribeToEvents",
        };
        return r
          ? r.length
            ? (r.forEach((e, m) => {
                if (
                  (e ||
                    a(
                      t,
                      0,
                      `invalid ServerEvent[${m}]: falsey`,
                      "subscribeToEvents",
                    ),
                  e.type === M.STATE_SYNC && e.mutationType !== "delete-all")
                ) {
                  if (
                    (e.entries?.length ||
                      a(
                        t,
                        1,
                        `invalid StateSyncEvent[${m}].entries for mutationType = '${e.mutationType}', should not be empty`,
                      ),
                    Array.isArray(e.entries) ||
                      a(
                        t,
                        0,
                        `invalid StateSyncEvent[${m}].entries for mutationType = '${e.mutationType}', should be an array:`,
                        e.entries,
                      ),
                    e.mutationType === "delete")
                  ) {
                    e.entries.every((n) => typeof n == "string") ||
                      a(
                        t,
                        0,
                        `invalid StateSyncEvent[${m}].entries for mutationType = 'delete', should be a string array:`,
                        e.entries,
                      );
                    return;
                  }
                  if (
                    (e.objectName !== "message_seen" &&
                      e.objectName !== "message_thread" &&
                      e.entries.forEach((n, p) => {
                        n.id ||
                          a(
                            t,
                            0,
                            `invalid StateSyncEvent[${m}].entries[${p}].id:`,
                            n,
                          );
                      }),
                    e.mutationType === "update")
                  )
                    for (const n of e.entries)
                      Object.keys(n).filter((E) => E !== "id").length === 0 &&
                        a(
                          t,
                          1,
                          `invalid StateSyncEvent[${m}].entries for mutationType = 'update': should not be empty`,
                          n,
                        );
                  switch (e.objectName) {
                    case "message": {
                      const n = {
                        ...t,
                        threadID: e.objectIDs.threadID,
                        mutationType: e.mutationType,
                        objectName: e.objectName,
                      };
                      (e.objectIDs.threadID ||
                        a(
                          n,
                          0,
                          `invalid StateSyncEvent[${m}]: objectIDs.threadID must be set`,
                        ),
                        e.objectIDs.eventID &&
                          a(
                            t,
                            1,
                            `invalid StateSyncEvent[${m}]: objectIDs.eventID must not be set on 'message' events`,
                          ),
                        l(e.entries, n),
                        c(e.entries, "message", n));
                      break;
                    }
                    case "message_reaction": {
                      e.objectIDs.eventID ||
                        a(
                          t,
                          1,
                          `invalid StateSyncEvent[${m}]: objectIDs.eventID must be set`,
                        );
                      const n = {
                        ...t,
                        threadID: e.objectIDs.threadID,
                        messageID: e.objectIDs.eventID,
                        mutationType: e.mutationType,
                        objectName: e.objectName,
                      };
                      e.entries.forEach((p) => {
                        $(p, n);
                      });
                      break;
                    }
                    case "message_seen": {
                      e.objectIDs.eventID ||
                        a(
                          t,
                          1,
                          `invalid StateSyncEvent[${m}]: objectIDs.eventID must be set`,
                        );
                      const n = {
                        ...t,
                        threadID: e.objectIDs.threadID,
                        mutationType: e.mutationType,
                        objectName: e.objectName,
                      };
                      e.entries.forEach((p) => {
                        p === !1 &&
                          a(
                            n,
                            1,
                            `invalid StateSyncEvent[${m}]: entry === false is redundant, message is never marked unseen`,
                          );
                      });
                      break;
                    }
                    case "thread": {
                      (e.objectIDs.threadID &&
                        a(
                          t,
                          1,
                          `invalid StateSyncEvent[${m}]: objectIDs.threadID must not be set`,
                        ),
                        e.entries.forEach((n) => {
                          const p = {
                            ...t,
                            threadID: n.id,
                            mutationType: e.mutationType,
                            objectName: e.objectName,
                          };
                          if (
                            ("participants" in n &&
                              (b(n.participants.items, p),
                              c(n.participants.items, "participant", p)),
                            "messages" in n)
                          ) {
                            const g = n.messages.items;
                            (l(g, p), y(g, p), c(g, "message", p));
                          }
                          v(n, p, e.mutationType === "upsert");
                        }));
                      break;
                    }
                    case "participant": {
                      e.objectIDs.eventID &&
                        a(
                          t,
                          1,
                          `invalid StateSyncEvent[${m}]: objectIDs.eventID must not be set on 'participant' events`,
                        );
                      const n = {
                        ...t,
                        threadID: e.objectIDs.threadID,
                        mutationType: e.mutationType,
                        objectName: e.objectName,
                      };
                      c(e.entries, "participant", n);
                      break;
                    }
                  }
                }
              }),
              d)
            : (a(t, 1, "`events` array is empty", "subscribeToEvents"), d)
          : (a(t, 0, "`events` is falsey", "subscribeToEvents"), d);
      },
    },
  };
}
export { Be as default };
//# sourceMappingURL=error-checker-plugin-2feknO7L.mjs.map
