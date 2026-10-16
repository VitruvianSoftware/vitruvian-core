import s from "events";
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
    var e = new d.Error().stack;
    e &&
      ((d._sentryDebugIds = d._sentryDebugIds || {}),
      (d._sentryDebugIds[e] = "b52675fe-e0fd-4490-b838-3dbc29210a7d"),
      (d._sentryDebugIdIdentifier =
        "sentry-dbid-b52675fe-e0fd-4490-b838-3dbc29210a7d"));
  } catch {}
})();
class i extends s {
  constructor() {
    (super(...arguments),
      (this.handlers = new Map()),
      (this.invoke = (e, ...n) => this.handlers.get(e)?.(null, ...n)));
  }
  handle(e, n) {
    this.handlers.set(e, n);
  }
  send(e, ...n) {
    this.emit(e, null, ...n);
  }
}
export { i as default };
//# sourceMappingURL=ipc-main-shim-DE4RL508.mjs.map
