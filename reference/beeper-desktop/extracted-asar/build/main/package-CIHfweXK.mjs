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
    var t = new e.Error().stack;
    t &&
      ((e._sentryDebugIds = e._sentryDebugIds || {}),
      (e._sentryDebugIds[t] = "402b1d8f-8374-4f42-a1ae-dd164c8f7983"),
      (e._sentryDebugIdIdentifier =
        "sentry-dbid-402b1d8f-8374-4f42-a1ae-dd164c8f7983"));
  } catch {}
})();
const n = "BeeperTexts",
  s = "Beeper",
  d = "4.3.209",
  i = "The ultimate messaging app",
  o = "build/main/index.mjs",
  c = {
    "@beeper/beeper-client-sdk": "3.0.0-latest",
    "better-sqlite3": "^13.0.3",
    "cbor-extract": "^2.2.0",
    "classic-level": "^2.0.0",
    diskusage:
      "https://github.com/TextsHQ/diskusage#6a3e1d186ba3b406c3525bcaff0ed8d77c6ec4f7",
    "electron-drag-click": "^1.0.6",
    keytar: "^7.9.0",
  },
  a = {
    bufferutil: "^4.0.7",
    "global-mouse-events": "^1.2.0",
    "node-mac-contacts":
      "https://github.com/TextsHQ/node-mac-contacts.git#main",
    "node-mac-permissions":
      "https://github.com/TextsHQ/node-mac-permissions.git#main",
    "utf-8-validate": "^5.0.10",
    "credential-extractor": "https://github.com/TextsHQ/credential-extractor",
  },
  r = { "node-gyp": "^10.0.1" },
  l = { nan: "^2.17.0", "node-gyp": "^10.0.1" },
  b = {
    name: n,
    friendlyProductName: s,
    version: d,
    description: i,
    main: o,
    dependencies: c,
    optionalDependencies: a,
    devDependencies: r,
    resolutions: l,
  };
export {
  b as default,
  c as dependencies,
  i as description,
  r as devDependencies,
  s as friendlyProductName,
  o as main,
  n as name,
  a as optionalDependencies,
  l as resolutions,
  d as version,
};
//# sourceMappingURL=package-CIHfweXK.mjs.map
