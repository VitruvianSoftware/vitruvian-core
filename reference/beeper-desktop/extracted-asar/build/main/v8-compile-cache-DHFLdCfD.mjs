import { c as A } from "./_commonjsHelpers-CBUqixCJ.mjs";
import j from "module";
import I from "crypto";
import K from "fs";
import L from "path";
import x from "vm";
import N from "os";
import R from "node:module";
(function () {
  try {
    var i =
      typeof window < "u"
        ? window
        : typeof global < "u"
          ? global
          : typeof globalThis < "u"
            ? globalThis
            : typeof self < "u"
              ? self
              : {};
    i.SENTRY_RELEASE = { id: "4.3.209" };
    var u = new i.Error().stack;
    u &&
      ((i._sentryDebugIds = i._sentryDebugIds || {}),
      (i._sentryDebugIds[u] = "bde3b3a2-8100-40cd-ba15-62b8a40dbeb5"),
      (i._sentryDebugIdIdentifier =
        "sentry-dbid-bde3b3a2-8100-40cd-ba15-62b8a40dbeb5"));
  } catch {}
})();
const W = import.meta.filename,
  U = import.meta.dirname,
  _ = R.createRequire(import.meta.url);
var C = {},
  F;
function T() {
  if (F) return C;
  F = 1;
  const i = j,
    u = I,
    l = K,
    p = L,
    S = x,
    P = N,
    h = Object.prototype.hasOwnProperty;
  class g {
    constructor(e, t) {
      const s = t ? w(t + ".") : "";
      ((this._blobFilename = p.join(e, s + "BLOB")),
        (this._mapFilename = p.join(e, s + "MAP")),
        (this._lockFilename = p.join(e, s + "LOCK")),
        (this._directory = e),
        this._load());
    }
    has(e, t) {
      return h.call(this._memoryBlobs, e)
        ? this._invalidationKeys[e] === t
        : h.call(this._storedMap, e)
          ? this._storedMap[e][0] === t
          : !1;
    }
    get(e, t) {
      if (h.call(this._memoryBlobs, e)) {
        if (this._invalidationKeys[e] === t) return this._memoryBlobs[e];
      } else if (h.call(this._storedMap, e)) {
        const s = this._storedMap[e];
        if (s[0] === t) return this._storedBlob.slice(s[1], s[2]);
      }
    }
    set(e, t, s) {
      ((this._invalidationKeys[e] = t),
        (this._memoryBlobs[e] = s),
        (this._dirty = !0));
    }
    delete(e) {
      (h.call(this._memoryBlobs, e) &&
        ((this._dirty = !0), delete this._memoryBlobs[e]),
        h.call(this._invalidationKeys, e) &&
          ((this._dirty = !0), delete this._invalidationKeys[e]),
        h.call(this._storedMap, e) &&
          ((this._dirty = !0), delete this._storedMap[e]));
    }
    isDirty() {
      return this._dirty;
    }
    save() {
      const e = this._getDump(),
        t = Buffer.concat(e[0]),
        s = JSON.stringify(e[1]);
      try {
        (E(this._directory),
          l.writeFileSync(this._lockFilename, "LOCK", { flag: "wx" }));
      } catch {
        return !1;
      }
      try {
        (l.writeFileSync(this._blobFilename, t),
          l.writeFileSync(this._mapFilename, s));
      } finally {
        l.unlinkSync(this._lockFilename);
      }
      return !0;
    }
    _load() {
      try {
        ((this._storedBlob = l.readFileSync(this._blobFilename)),
          (this._storedMap = JSON.parse(l.readFileSync(this._mapFilename))));
      } catch {
        ((this._storedBlob = Buffer.alloc(0)), (this._storedMap = {}));
      }
      ((this._dirty = !1),
        (this._memoryBlobs = {}),
        (this._invalidationKeys = {}));
    }
    _getDump() {
      const e = [],
        t = {};
      let s = 0;
      function c(r, a, n) {
        (e.push(n), (t[r] = [a, s, s + n.length]), (s += n.length));
      }
      for (const r of Object.keys(this._memoryBlobs)) {
        const a = this._memoryBlobs[r],
          n = this._invalidationKeys[r];
        c(r, n, a);
      }
      for (const r of Object.keys(this._storedMap)) {
        if (h.call(t, r)) continue;
        const a = this._storedMap[r],
          n = this._storedBlob.slice(a[1], a[2]);
        c(r, a[0], n);
      }
      return [e, t];
    }
  }
  class D {
    constructor() {
      ((this._cacheStore = null), (this._previousModuleCompile = null));
    }
    setCacheStore(e) {
      this._cacheStore = e;
    }
    install() {
      const e = this,
        t = typeof _.resolve.paths == "function";
      ((this._previousModuleCompile = i.prototype._compile),
        (i.prototype._compile = function (s, c) {
          const r = this;
          function a(m) {
            return r.require(m);
          }
          function n(m, v) {
            return i._resolveFilename(m, r, !1, v);
          }
          ((a.resolve = n),
            t &&
              (n.paths = function (v) {
                return i._resolveLookupPaths(v, r, !0);
              }),
            (a.main = process.mainModule),
            (a.extensions = i._extensions),
            (a.cache = i._cache));
          const y = p.dirname(c),
            d = e._moduleCompile(c, s),
            b = [r.exports, a, r, c, y, process, A, Buffer];
          return d.apply(r.exports, b);
        }));
    }
    uninstall() {
      i.prototype._compile = this._previousModuleCompile;
    }
    _moduleCompile(e, t) {
      var s = t.length;
      if (s >= 2 && t.charCodeAt(0) === 35 && t.charCodeAt(1) === 33)
        if (s === 2) t = "";
        else {
          for (var c = 2; c < s; ++c) {
            var r = t.charCodeAt(c);
            if (r === 10 || r === 13) break;
          }
          c === s ? (t = "") : (t = t.slice(c));
        }
      var a = i.wrap(t),
        n = u.createHash("sha1").update(t, "utf8").digest("hex"),
        y = this._cacheStore.get(e, n),
        d = new S.Script(a, {
          filename: e,
          lineOffset: 0,
          displayErrors: !0,
          cachedData: y,
          produceCachedData: !0,
        });
      d.cachedDataProduced
        ? this._cacheStore.set(e, n, d.cachedData)
        : d.cachedDataRejected && this._cacheStore.delete(e);
      var b = d.runInThisContext({
        filename: e,
        lineOffset: 0,
        columnOffset: 0,
        displayErrors: !0,
      });
      return b;
    }
  }
  function E(o) {
    f(p.resolve(o), 511);
  }
  function f(o, e) {
    try {
      l.mkdirSync(o, e);
    } catch (t) {
      if (t.code === "ENOENT") (f(p.dirname(o)), f(o));
      else
        try {
          if (!l.statSync(o).isDirectory()) throw t;
        } catch {
          throw t;
        }
    }
  }
  function w(o) {
    const e = { "\\": "zB", ":": "zC", "/": "zS", "\0": "z0", z: "zZ" },
      t = /[\\:/\x00z]/g;
    return o.replace(t, (s) => e[s]);
  }
  function B() {
    return (
      new S.Script('""', { produceCachedData: !0 }).cachedDataProduced === !0
    );
  }
  function M() {
    const o = process.env.V8_COMPILE_CACHE_CACHE_DIR;
    if (o) return o;
    const e =
        typeof process.getuid == "function"
          ? "v8-compile-cache-" + process.getuid()
          : "v8-compile-cache",
      t = process.arch,
      s =
        typeof process.versions.v8 == "string"
          ? process.versions.v8
          : typeof process.versions.chakracore == "string"
            ? "chakracore-" + process.versions.chakracore
            : "node-" + process.version;
    return p.join(P.tmpdir(), e, t, s);
  }
  function O() {
    return _.main && typeof _.main.filename == "string"
      ? _.main.filename
      : process.cwd();
  }
  if (!process.env.DISABLE_V8_COMPILE_CACHE && B()) {
    const o = M(),
      e = O(),
      t = new g(o, e),
      s = new D();
    (s.setCacheStore(t),
      s.install(),
      process.once("exit", () => {
        (t.isDirty() && t.save(), s.uninstall());
      }));
  }
  return (
    (C.__TEST__ = {
      FileSystemBlobStore: g,
      NativeCompileCache: D,
      mkdirpSync: E,
      slashEscape: w,
      supportsCachedData: B,
      getCacheDir: M,
      getMainName: O,
    }),
    C
  );
}
T();
//# sourceMappingURL=v8-compile-cache-DHFLdCfD.mjs.map
