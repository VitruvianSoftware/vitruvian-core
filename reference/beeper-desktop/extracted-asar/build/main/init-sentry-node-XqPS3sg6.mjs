import { isMainThread as i } from "worker_threads";
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
      (e._sentryDebugIds[n] = "3744326c-67af-4e0b-b2e4-43079aaa7abf"),
      (e._sentryDebugIdIdentifier =
        "sentry-dbid-3744326c-67af-4e0b-b2e4-43079aaa7abf"));
  } catch {}
})();
const s = (e, n, r) => {
    const t = e[n];
    return t
      ? typeof t == "function"
        ? t()
        : Promise.resolve(t)
      : new Promise((d, o) => {
          (typeof queueMicrotask == "function" ? queueMicrotask : setTimeout)(
            o.bind(
              null,
              new Error(
                "Unknown variable dynamic import: " +
                  n +
                  (n.split("/").length !== r
                    ? ". Note that variables only represent file names one level deep."
                    : ""),
              ),
            ),
          );
        });
  },
  a =
    i && !globalThis.USE_SENTRY_NODE
      ? "init-sentry-electron"
      : "init-sentry-nonbrowser",
  l = await s(
    Object.assign({
      "./sentry/crash-reporter.ts": () =>
        import("./crash-reporter-BlEAKQlO.mjs"),
      "./sentry/init-sentry-electron.ts": () =>
        import("./init-sentry-electron-Zoq1-mpg.mjs"),
      "./sentry/init-sentry-nonbrowser.ts": () =>
        import("./init-sentry-nonbrowser-5rM0FBXA.mjs"),
    }),
    `./sentry/${a}.ts`,
    3,
  ),
  y = l.default;
export { y as default };
//# sourceMappingURL=init-sentry-node-XqPS3sg6.mjs.map
