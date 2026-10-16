import { e as execa } from "./index-CMOlVndj.mjs";
import { a as getDefaultExportFromCjs } from "./_commonjsHelpers-CBUqixCJ.mjs";
import fs from "fs";
import os from "os";
import path__default from "path";
import { PUBLIC_DIR_PATH_UNPACKED, IS_MAC_OS } from "./constants-BL_pdRyX.mjs";
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
      (e._sentryDebugIds[n] = "ec41f7a2-27ee-4f80-afe6-d5edfc88b5bb"),
      (e._sentryDebugIdIdentifier =
        "sentry-dbid-ec41f7a2-27ee-4f80-afe6-d5edfc88b5bb"));
  } catch {}
})();
function _mergeNamespaces(e, n) {
  for (var m = 0; m < n.length; m++) {
    const r = n[m];
    if (typeof r != "string" && !Array.isArray(r)) {
      for (const o in r)
        if (o !== "default" && !(o in e)) {
          const s = Object.getOwnPropertyDescriptor(r, o);
          s &&
            Object.defineProperty(
              e,
              o,
              s.get ? s : { enumerable: !0, get: () => r[o] },
            );
        }
    }
  }
  return Object.freeze(
    Object.defineProperty(e, Symbol.toStringTag, { value: "Module" }),
  );
}
var lib$2 = {},
  FsPromise = {},
  hasRequiredFsPromise;
function requireFsPromise() {
  if (hasRequiredFsPromise) return FsPromise;
  ((hasRequiredFsPromise = 1),
    Object.defineProperty(FsPromise, "__esModule", { value: !0 }),
    (FsPromise.readFile =
      FsPromise.writeFileSync =
      FsPromise.writeFile =
      FsPromise.read =
      FsPromise.open =
      FsPromise.close =
      FsPromise.stat =
      FsPromise.createReadStream =
      FsPromise.pathExists =
        void 0));
  const e = fs;
  ((FsPromise.pathExists = e.existsSync),
    (FsPromise.createReadStream = e.createReadStream));
  async function n(i) {
    return new Promise((t, a) => {
      e.stat(i, (x, c) => {
        x ? a(x) : t(c);
      });
    });
  }
  FsPromise.stat = n;
  async function m(i) {
    return new Promise((t, a) => {
      e.close(i, (x) => {
        x ? a(x) : t();
      });
    });
  }
  FsPromise.close = m;
  async function r(i, t) {
    return new Promise((a, x) => {
      e.open(i, t, (c, d) => {
        c ? x(c) : a(d);
      });
    });
  }
  FsPromise.open = r;
  async function o(i, t, a, x, c) {
    return new Promise((d, l) => {
      e.read(i, t, a, x, c, (h, p, g) => {
        h ? l(h) : d({ bytesRead: p, buffer: g });
      });
    });
  }
  FsPromise.read = o;
  async function s(i, t) {
    return new Promise((a, x) => {
      e.writeFile(i, t, (c) => {
        c ? x(c) : a();
      });
    });
  }
  FsPromise.writeFile = s;
  function f(i, t) {
    e.writeFileSync(i, t);
  }
  FsPromise.writeFileSync = f;
  async function u(i) {
    return new Promise((t, a) => {
      e.readFile(i, (x, c) => {
        x ? a(x) : t(c);
      });
    });
  }
  return ((FsPromise.readFile = u), FsPromise);
}
var core$1 = {},
  ReadStreamTokenizer = {},
  AbstractTokenizer = {},
  lib$1 = {},
  EndOfFileStream = {},
  hasRequiredEndOfFileStream;
function requireEndOfFileStream() {
  return (
    hasRequiredEndOfFileStream ||
      ((hasRequiredEndOfFileStream = 1),
      (function (e) {
        (Object.defineProperty(e, "__esModule", { value: !0 }),
          (e.EndOfStreamError = e.defaultMessages = void 0),
          (e.defaultMessages = "End-Of-Stream"));
        class n extends Error {
          constructor() {
            super(e.defaultMessages);
          }
        }
        e.EndOfStreamError = n;
      })(EndOfFileStream)),
    EndOfFileStream
  );
}
var StreamReader = {},
  Deferred = {},
  hasRequiredDeferred;
function requireDeferred() {
  if (hasRequiredDeferred) return Deferred;
  ((hasRequiredDeferred = 1),
    Object.defineProperty(Deferred, "__esModule", { value: !0 }),
    (Deferred.Deferred = void 0));
  let e = class {
    constructor() {
      ((this.resolve = () => null),
        (this.reject = () => null),
        (this.promise = new Promise((m, r) => {
          ((this.reject = r), (this.resolve = m));
        })));
    }
  };
  return ((Deferred.Deferred = e), Deferred);
}
var hasRequiredStreamReader;
function requireStreamReader() {
  return (
    hasRequiredStreamReader ||
      ((hasRequiredStreamReader = 1),
      (function (e) {
        (Object.defineProperty(e, "__esModule", { value: !0 }),
          (e.StreamReader = e.EndOfStreamError = void 0));
        const n = requireEndOfFileStream(),
          m = requireDeferred();
        var r = requireEndOfFileStream();
        Object.defineProperty(e, "EndOfStreamError", {
          enumerable: !0,
          get: function () {
            return r.EndOfStreamError;
          },
        });
        const o = 1 * 1024 * 1024;
        class s {
          constructor(u) {
            if (
              ((this.s = u),
              (this.deferred = null),
              (this.endOfStream = !1),
              (this.peekQueue = []),
              !u.read || !u.once)
            )
              throw new Error("Expected an instance of stream.Readable");
            (this.s.once("end", () => this.reject(new n.EndOfStreamError())),
              this.s.once("error", (i) => this.reject(i)),
              this.s.once("close", () =>
                this.reject(new Error("Stream closed")),
              ));
          }
          async peek(u, i, t) {
            const a = await this.read(u, i, t);
            return (this.peekQueue.push(u.subarray(i, i + a)), a);
          }
          async read(u, i, t) {
            if (t === 0) return 0;
            if (this.peekQueue.length === 0 && this.endOfStream)
              throw new n.EndOfStreamError();
            let a = t,
              x = 0;
            for (; this.peekQueue.length > 0 && a > 0;) {
              const c = this.peekQueue.pop();
              if (!c) throw new Error("peekData should be defined");
              const d = Math.min(c.length, a);
              (u.set(c.subarray(0, d), i + x),
                (x += d),
                (a -= d),
                d < c.length && this.peekQueue.push(c.subarray(d)));
            }
            for (; a > 0 && !this.endOfStream;) {
              const c = Math.min(a, o),
                d = await this.readFromStream(u, i + x, c);
              if (((x += d), d < c)) break;
              a -= d;
            }
            return x;
          }
          async readFromStream(u, i, t) {
            const a = this.s.read(t);
            if (a) return (u.set(a, i), a.length);
            {
              const x = {
                buffer: u,
                offset: i,
                length: t,
                deferred: new m.Deferred(),
              };
              return (
                (this.deferred = x.deferred),
                this.s.once("readable", () => {
                  this.readDeferred(x);
                }),
                x.deferred.promise
              );
            }
          }
          readDeferred(u) {
            const i = this.s.read(u.length);
            i
              ? (u.buffer.set(i, u.offset),
                u.deferred.resolve(i.length),
                (this.deferred = null))
              : this.s.once("readable", () => {
                  this.readDeferred(u);
                });
          }
          reject(u) {
            ((this.endOfStream = !0),
              this.deferred &&
                (this.deferred.reject(u), (this.deferred = null)));
          }
        }
        e.StreamReader = s;
      })(StreamReader)),
    StreamReader
  );
}
var hasRequiredLib$2;
function requireLib$2() {
  return (
    hasRequiredLib$2 ||
      ((hasRequiredLib$2 = 1),
      (function (e) {
        (Object.defineProperty(e, "__esModule", { value: !0 }),
          (e.StreamReader = e.EndOfStreamError = void 0));
        var n = requireEndOfFileStream();
        Object.defineProperty(e, "EndOfStreamError", {
          enumerable: !0,
          get: function () {
            return n.EndOfStreamError;
          },
        });
        var m = requireStreamReader();
        Object.defineProperty(e, "StreamReader", {
          enumerable: !0,
          get: function () {
            return m.StreamReader;
          },
        });
      })(lib$1)),
    lib$1
  );
}
var hasRequiredAbstractTokenizer;
function requireAbstractTokenizer() {
  if (hasRequiredAbstractTokenizer) return AbstractTokenizer;
  ((hasRequiredAbstractTokenizer = 1),
    Object.defineProperty(AbstractTokenizer, "__esModule", { value: !0 }),
    (AbstractTokenizer.AbstractTokenizer = void 0));
  const e = requireLib$2();
  let n = class {
    constructor(r) {
      ((this.position = 0),
        (this.numBuffer = new Uint8Array(8)),
        (this.fileInfo = r || {}));
    }
    async readToken(r, o = this.position) {
      const s = Buffer.alloc(r.len);
      if ((await this.readBuffer(s, { position: o })) < r.len)
        throw new e.EndOfStreamError();
      return r.get(s, 0);
    }
    async peekToken(r, o = this.position) {
      const s = Buffer.alloc(r.len);
      if ((await this.peekBuffer(s, { position: o })) < r.len)
        throw new e.EndOfStreamError();
      return r.get(s, 0);
    }
    async readNumber(r) {
      if ((await this.readBuffer(this.numBuffer, { length: r.len })) < r.len)
        throw new e.EndOfStreamError();
      return r.get(this.numBuffer, 0);
    }
    async peekNumber(r) {
      if ((await this.peekBuffer(this.numBuffer, { length: r.len })) < r.len)
        throw new e.EndOfStreamError();
      return r.get(this.numBuffer, 0);
    }
    async ignore(r) {
      if (this.fileInfo.size !== void 0) {
        const o = this.fileInfo.size - this.position;
        if (r > o) return ((this.position += o), o);
      }
      return ((this.position += r), r);
    }
    async close() {}
    normalizeOptions(r, o) {
      if (o && o.position !== void 0 && o.position < this.position)
        throw new Error(
          "`options.position` must be equal or greater than `tokenizer.position`",
        );
      return o
        ? {
            mayBeLess: o.mayBeLess === !0,
            offset: o.offset ? o.offset : 0,
            length: o.length ? o.length : r.length - (o.offset ? o.offset : 0),
            position: o.position ? o.position : this.position,
          }
        : {
            mayBeLess: !1,
            offset: 0,
            length: r.length,
            position: this.position,
          };
    }
  };
  return ((AbstractTokenizer.AbstractTokenizer = n), AbstractTokenizer);
}
var hasRequiredReadStreamTokenizer;
function requireReadStreamTokenizer() {
  if (hasRequiredReadStreamTokenizer) return ReadStreamTokenizer;
  ((hasRequiredReadStreamTokenizer = 1),
    Object.defineProperty(ReadStreamTokenizer, "__esModule", { value: !0 }),
    (ReadStreamTokenizer.ReadStreamTokenizer = void 0));
  const e = requireAbstractTokenizer(),
    n = requireLib$2(),
    m = 256e3;
  let r = class extends e.AbstractTokenizer {
    constructor(s, f) {
      (super(f), (this.streamReader = new n.StreamReader(s)));
    }
    async getFileInfo() {
      return this.fileInfo;
    }
    async readBuffer(s, f) {
      const u = this.normalizeOptions(s, f),
        i = u.position - this.position;
      if (i > 0) return (await this.ignore(i), this.readBuffer(s, f));
      if (i < 0)
        throw new Error(
          "`options.position` must be equal or greater than `tokenizer.position`",
        );
      if (u.length === 0) return 0;
      const t = await this.streamReader.read(s, u.offset, u.length);
      if (((this.position += t), (!f || !f.mayBeLess) && t < u.length))
        throw new n.EndOfStreamError();
      return t;
    }
    async peekBuffer(s, f) {
      const u = this.normalizeOptions(s, f);
      let i = 0;
      if (u.position) {
        const t = u.position - this.position;
        if (t > 0) {
          const a = new Uint8Array(u.length + t);
          return (
            (i = await this.peekBuffer(a, { mayBeLess: u.mayBeLess })),
            s.set(a.subarray(t), u.offset),
            i - t
          );
        } else if (t < 0)
          throw new Error("Cannot peek from a negative offset in a stream");
      }
      if (u.length > 0) {
        try {
          i = await this.streamReader.peek(s, u.offset, u.length);
        } catch (t) {
          if (f && f.mayBeLess && t instanceof n.EndOfStreamError) return 0;
          throw t;
        }
        if (!u.mayBeLess && i < u.length) throw new n.EndOfStreamError();
      }
      return i;
    }
    async ignore(s) {
      const f = Math.min(m, s),
        u = new Uint8Array(f);
      let i = 0;
      for (; i < s;) {
        const t = s - i,
          a = await this.readBuffer(u, { length: Math.min(f, t) });
        if (a < 0) return a;
        i += a;
      }
      return i;
    }
  };
  return ((ReadStreamTokenizer.ReadStreamTokenizer = r), ReadStreamTokenizer);
}
var BufferTokenizer = {},
  hasRequiredBufferTokenizer;
function requireBufferTokenizer() {
  if (hasRequiredBufferTokenizer) return BufferTokenizer;
  ((hasRequiredBufferTokenizer = 1),
    Object.defineProperty(BufferTokenizer, "__esModule", { value: !0 }),
    (BufferTokenizer.BufferTokenizer = void 0));
  const e = requireLib$2(),
    n = requireAbstractTokenizer();
  let m = class extends n.AbstractTokenizer {
    constructor(o, s) {
      (super(s),
        (this.uint8Array = o),
        (this.fileInfo.size = this.fileInfo.size
          ? this.fileInfo.size
          : o.length));
    }
    async readBuffer(o, s) {
      if (s && s.position) {
        if (s.position < this.position)
          throw new Error(
            "`options.position` must be equal or greater than `tokenizer.position`",
          );
        this.position = s.position;
      }
      const f = await this.peekBuffer(o, s);
      return ((this.position += f), f);
    }
    async peekBuffer(o, s) {
      const f = this.normalizeOptions(o, s),
        u = Math.min(this.uint8Array.length - f.position, f.length);
      if (!f.mayBeLess && u < f.length) throw new e.EndOfStreamError();
      return (
        o.set(this.uint8Array.subarray(f.position, f.position + u), f.offset),
        u
      );
    }
    async close() {}
  };
  return ((BufferTokenizer.BufferTokenizer = m), BufferTokenizer);
}
var hasRequiredCore$1;
function requireCore$1() {
  return (
    hasRequiredCore$1 ||
      ((hasRequiredCore$1 = 1),
      (function (e) {
        (Object.defineProperty(e, "__esModule", { value: !0 }),
          (e.fromBuffer = e.fromStream = e.EndOfStreamError = void 0));
        const n = requireReadStreamTokenizer(),
          m = requireBufferTokenizer();
        var r = requireLib$2();
        Object.defineProperty(e, "EndOfStreamError", {
          enumerable: !0,
          get: function () {
            return r.EndOfStreamError;
          },
        });
        function o(f, u) {
          return ((u = u || {}), new n.ReadStreamTokenizer(f, u));
        }
        e.fromStream = o;
        function s(f, u) {
          return new m.BufferTokenizer(f, u);
        }
        e.fromBuffer = s;
      })(core$1)),
    core$1
  );
}
var FileTokenizer = {},
  hasRequiredFileTokenizer;
function requireFileTokenizer() {
  if (hasRequiredFileTokenizer) return FileTokenizer;
  ((hasRequiredFileTokenizer = 1),
    Object.defineProperty(FileTokenizer, "__esModule", { value: !0 }),
    (FileTokenizer.fromFile = FileTokenizer.FileTokenizer = void 0));
  const e = requireAbstractTokenizer(),
    n = requireLib$2(),
    m = requireFsPromise();
  let r = class extends e.AbstractTokenizer {
    constructor(f, u) {
      (super(u), (this.fd = f));
    }
    async readBuffer(f, u) {
      const i = this.normalizeOptions(f, u);
      this.position = i.position;
      const t = await m.read(this.fd, f, i.offset, i.length, i.position);
      if (
        ((this.position += t.bytesRead),
        t.bytesRead < i.length && (!u || !u.mayBeLess))
      )
        throw new n.EndOfStreamError();
      return t.bytesRead;
    }
    async peekBuffer(f, u) {
      const i = this.normalizeOptions(f, u),
        t = await m.read(this.fd, f, i.offset, i.length, i.position);
      if (!i.mayBeLess && t.bytesRead < i.length)
        throw new n.EndOfStreamError();
      return t.bytesRead;
    }
    async close() {
      return m.close(this.fd);
    }
  };
  FileTokenizer.FileTokenizer = r;
  async function o(s) {
    const f = await m.stat(s);
    if (!f.isFile) throw new Error(`File not a file: ${s}`);
    const u = await m.open(s, "r");
    return new r(u, { path: s, size: f.size });
  }
  return ((FileTokenizer.fromFile = o), FileTokenizer);
}
var hasRequiredLib$1;
function requireLib$1() {
  return (
    hasRequiredLib$1 ||
      ((hasRequiredLib$1 = 1),
      (function (e) {
        (Object.defineProperty(e, "__esModule", { value: !0 }),
          (e.fromStream =
            e.fromBuffer =
            e.EndOfStreamError =
            e.fromFile =
              void 0));
        const n = requireFsPromise(),
          m = requireCore$1();
        var r = requireFileTokenizer();
        Object.defineProperty(e, "fromFile", {
          enumerable: !0,
          get: function () {
            return r.fromFile;
          },
        });
        var o = requireCore$1();
        (Object.defineProperty(e, "EndOfStreamError", {
          enumerable: !0,
          get: function () {
            return o.EndOfStreamError;
          },
        }),
          Object.defineProperty(e, "fromBuffer", {
            enumerable: !0,
            get: function () {
              return o.fromBuffer;
            },
          }));
        async function s(f, u) {
          if (((u = u || {}), f.path)) {
            const i = await n.stat(f.path);
            ((u.path = f.path), (u.size = i.size));
          }
          return m.fromStream(f, u);
        }
        e.fromStream = s;
      })(lib$2)),
    lib$2
  );
}
var lib = {},
  ieee754 = {};
var hasRequiredIeee754;
function requireIeee754() {
  return (
    hasRequiredIeee754 ||
      ((hasRequiredIeee754 = 1),
      (ieee754.read = function (e, n, m, r, o) {
        var s,
          f,
          u = o * 8 - r - 1,
          i = (1 << u) - 1,
          t = i >> 1,
          a = -7,
          x = m ? o - 1 : 0,
          c = m ? -1 : 1,
          d = e[n + x];
        for (
          x += c, s = d & ((1 << -a) - 1), d >>= -a, a += u;
          a > 0;
          s = s * 256 + e[n + x], x += c, a -= 8
        );
        for (
          f = s & ((1 << -a) - 1), s >>= -a, a += r;
          a > 0;
          f = f * 256 + e[n + x], x += c, a -= 8
        );
        if (s === 0) s = 1 - t;
        else {
          if (s === i) return f ? NaN : (d ? -1 : 1) * (1 / 0);
          ((f = f + Math.pow(2, r)), (s = s - t));
        }
        return (d ? -1 : 1) * f * Math.pow(2, s - r);
      }),
      (ieee754.write = function (e, n, m, r, o, s) {
        var f,
          u,
          i,
          t = s * 8 - o - 1,
          a = (1 << t) - 1,
          x = a >> 1,
          c = o === 23 ? Math.pow(2, -24) - Math.pow(2, -77) : 0,
          d = r ? 0 : s - 1,
          l = r ? 1 : -1,
          h = n < 0 || (n === 0 && 1 / n < 0) ? 1 : 0;
        for (
          n = Math.abs(n),
            isNaN(n) || n === 1 / 0
              ? ((u = isNaN(n) ? 1 : 0), (f = a))
              : ((f = Math.floor(Math.log(n) / Math.LN2)),
                n * (i = Math.pow(2, -f)) < 1 && (f--, (i *= 2)),
                f + x >= 1 ? (n += c / i) : (n += c * Math.pow(2, 1 - x)),
                n * i >= 2 && (f++, (i /= 2)),
                f + x >= a
                  ? ((u = 0), (f = a))
                  : f + x >= 1
                    ? ((u = (n * i - 1) * Math.pow(2, o)), (f = f + x))
                    : ((u = n * Math.pow(2, x - 1) * Math.pow(2, o)), (f = 0)));
          o >= 8;
          e[m + d] = u & 255, d += l, u /= 256, o -= 8
        );
        for (
          f = (f << o) | u, t += o;
          t > 0;
          e[m + d] = f & 255, d += l, f /= 256, t -= 8
        );
        e[m + d - l] |= h * 128;
      })),
    ieee754
  );
}
var hasRequiredLib;
function requireLib() {
  return (
    hasRequiredLib ||
      ((hasRequiredLib = 1),
      (function (e) {
        (Object.defineProperty(e, "__esModule", { value: !0 }),
          (e.AnsiStringType =
            e.StringType =
            e.BufferType =
            e.Uint8ArrayType =
            e.IgnoreType =
            e.Float80_LE =
            e.Float80_BE =
            e.Float64_LE =
            e.Float64_BE =
            e.Float32_LE =
            e.Float32_BE =
            e.Float16_LE =
            e.Float16_BE =
            e.INT64_BE =
            e.UINT64_BE =
            e.INT64_LE =
            e.UINT64_LE =
            e.INT32_LE =
            e.INT32_BE =
            e.INT24_BE =
            e.INT24_LE =
            e.INT16_LE =
            e.INT16_BE =
            e.INT8 =
            e.UINT32_BE =
            e.UINT32_LE =
            e.UINT24_BE =
            e.UINT24_LE =
            e.UINT16_BE =
            e.UINT16_LE =
            e.UINT8 =
              void 0));
        const n = requireIeee754();
        function m(i) {
          return new DataView(i.buffer, i.byteOffset);
        }
        ((e.UINT8 = {
          len: 1,
          get(i, t) {
            return m(i).getUint8(t);
          },
          put(i, t, a) {
            return (m(i).setUint8(t, a), t + 1);
          },
        }),
          (e.UINT16_LE = {
            len: 2,
            get(i, t) {
              return m(i).getUint16(t, !0);
            },
            put(i, t, a) {
              return (m(i).setUint16(t, a, !0), t + 2);
            },
          }),
          (e.UINT16_BE = {
            len: 2,
            get(i, t) {
              return m(i).getUint16(t);
            },
            put(i, t, a) {
              return (m(i).setUint16(t, a), t + 2);
            },
          }),
          (e.UINT24_LE = {
            len: 3,
            get(i, t) {
              const a = m(i);
              return a.getUint8(t) + (a.getUint16(t + 1, !0) << 8);
            },
            put(i, t, a) {
              const x = m(i);
              return (
                x.setUint8(t, a & 255),
                x.setUint16(t + 1, a >> 8, !0),
                t + 3
              );
            },
          }),
          (e.UINT24_BE = {
            len: 3,
            get(i, t) {
              const a = m(i);
              return (a.getUint16(t) << 8) + a.getUint8(t + 2);
            },
            put(i, t, a) {
              const x = m(i);
              return (
                x.setUint16(t, a >> 8),
                x.setUint8(t + 2, a & 255),
                t + 3
              );
            },
          }),
          (e.UINT32_LE = {
            len: 4,
            get(i, t) {
              return m(i).getUint32(t, !0);
            },
            put(i, t, a) {
              return (m(i).setUint32(t, a, !0), t + 4);
            },
          }),
          (e.UINT32_BE = {
            len: 4,
            get(i, t) {
              return m(i).getUint32(t);
            },
            put(i, t, a) {
              return (m(i).setUint32(t, a), t + 4);
            },
          }),
          (e.INT8 = {
            len: 1,
            get(i, t) {
              return m(i).getInt8(t);
            },
            put(i, t, a) {
              return (m(i).setInt8(t, a), t + 1);
            },
          }),
          (e.INT16_BE = {
            len: 2,
            get(i, t) {
              return m(i).getInt16(t);
            },
            put(i, t, a) {
              return (m(i).setInt16(t, a), t + 2);
            },
          }),
          (e.INT16_LE = {
            len: 2,
            get(i, t) {
              return m(i).getInt16(t, !0);
            },
            put(i, t, a) {
              return (m(i).setInt16(t, a, !0), t + 2);
            },
          }),
          (e.INT24_LE = {
            len: 3,
            get(i, t) {
              const a = e.UINT24_LE.get(i, t);
              return a > 8388607 ? a - 16777216 : a;
            },
            put(i, t, a) {
              const x = m(i);
              return (
                x.setUint8(t, a & 255),
                x.setUint16(t + 1, a >> 8, !0),
                t + 3
              );
            },
          }),
          (e.INT24_BE = {
            len: 3,
            get(i, t) {
              const a = e.UINT24_BE.get(i, t);
              return a > 8388607 ? a - 16777216 : a;
            },
            put(i, t, a) {
              const x = m(i);
              return (
                x.setUint16(t, a >> 8),
                x.setUint8(t + 2, a & 255),
                t + 3
              );
            },
          }),
          (e.INT32_BE = {
            len: 4,
            get(i, t) {
              return m(i).getInt32(t);
            },
            put(i, t, a) {
              return (m(i).setInt32(t, a), t + 4);
            },
          }),
          (e.INT32_LE = {
            len: 4,
            get(i, t) {
              return m(i).getInt32(t, !0);
            },
            put(i, t, a) {
              return (m(i).setInt32(t, a, !0), t + 4);
            },
          }),
          (e.UINT64_LE = {
            len: 8,
            get(i, t) {
              return m(i).getBigUint64(t, !0);
            },
            put(i, t, a) {
              return (m(i).setBigUint64(t, a, !0), t + 8);
            },
          }),
          (e.INT64_LE = {
            len: 8,
            get(i, t) {
              return m(i).getBigInt64(t, !0);
            },
            put(i, t, a) {
              return (m(i).setBigInt64(t, a, !0), t + 8);
            },
          }),
          (e.UINT64_BE = {
            len: 8,
            get(i, t) {
              return m(i).getBigUint64(t);
            },
            put(i, t, a) {
              return (m(i).setBigUint64(t, a), t + 8);
            },
          }),
          (e.INT64_BE = {
            len: 8,
            get(i, t) {
              return m(i).getBigInt64(t);
            },
            put(i, t, a) {
              return (m(i).setBigInt64(t, a), t + 8);
            },
          }),
          (e.Float16_BE = {
            len: 2,
            get(i, t) {
              return n.read(i, t, !1, 10, this.len);
            },
            put(i, t, a) {
              return (n.write(i, a, t, !1, 10, this.len), t + this.len);
            },
          }),
          (e.Float16_LE = {
            len: 2,
            get(i, t) {
              return n.read(i, t, !0, 10, this.len);
            },
            put(i, t, a) {
              return (n.write(i, a, t, !0, 10, this.len), t + this.len);
            },
          }),
          (e.Float32_BE = {
            len: 4,
            get(i, t) {
              return m(i).getFloat32(t);
            },
            put(i, t, a) {
              return (m(i).setFloat32(t, a), t + 4);
            },
          }),
          (e.Float32_LE = {
            len: 4,
            get(i, t) {
              return m(i).getFloat32(t, !0);
            },
            put(i, t, a) {
              return (m(i).setFloat32(t, a, !0), t + 4);
            },
          }),
          (e.Float64_BE = {
            len: 8,
            get(i, t) {
              return m(i).getFloat64(t);
            },
            put(i, t, a) {
              return (m(i).setFloat64(t, a), t + 8);
            },
          }),
          (e.Float64_LE = {
            len: 8,
            get(i, t) {
              return m(i).getFloat64(t, !0);
            },
            put(i, t, a) {
              return (m(i).setFloat64(t, a, !0), t + 8);
            },
          }),
          (e.Float80_BE = {
            len: 10,
            get(i, t) {
              return n.read(i, t, !1, 63, this.len);
            },
            put(i, t, a) {
              return (n.write(i, a, t, !1, 63, this.len), t + this.len);
            },
          }),
          (e.Float80_LE = {
            len: 10,
            get(i, t) {
              return n.read(i, t, !0, 63, this.len);
            },
            put(i, t, a) {
              return (n.write(i, a, t, !0, 63, this.len), t + this.len);
            },
          }));
        class r {
          constructor(t) {
            this.len = t;
          }
          get(t, a) {}
        }
        e.IgnoreType = r;
        class o {
          constructor(t) {
            this.len = t;
          }
          get(t, a) {
            return t.subarray(a, a + this.len);
          }
        }
        e.Uint8ArrayType = o;
        class s {
          constructor(t) {
            this.len = t;
          }
          get(t, a) {
            return Buffer.from(t.subarray(a, a + this.len));
          }
        }
        e.BufferType = s;
        class f {
          constructor(t, a) {
            ((this.len = t), (this.encoding = a));
          }
          get(t, a) {
            return Buffer.from(t).toString(this.encoding, a, a + this.len);
          }
        }
        e.StringType = f;
        class u {
          constructor(t) {
            this.len = t;
          }
          static decode(t, a, x) {
            let c = "";
            for (let d = a; d < x; ++d)
              c += u.codePointToString(u.singleByteDecoder(t[d]));
            return c;
          }
          static inRange(t, a, x) {
            return a <= t && t <= x;
          }
          static codePointToString(t) {
            return t <= 65535
              ? String.fromCharCode(t)
              : ((t -= 65536),
                String.fromCharCode((t >> 10) + 55296, (t & 1023) + 56320));
          }
          static singleByteDecoder(t) {
            if (u.inRange(t, 0, 127)) return t;
            const a = u.windows1252[t - 128];
            if (a === null) throw Error("invaliding encoding");
            return a;
          }
          get(t, a = 0) {
            return u.decode(t, a, a + this.len);
          }
        }
        ((e.AnsiStringType = u),
          (u.windows1252 = [
            8364, 129, 8218, 402, 8222, 8230, 8224, 8225, 710, 8240, 352, 8249,
            338, 141, 381, 143, 144, 8216, 8217, 8220, 8221, 8226, 8211, 8212,
            732, 8482, 353, 8250, 339, 157, 382, 376, 160, 161, 162, 163, 164,
            165, 166, 167, 168, 169, 170, 171, 172, 173, 174, 175, 176, 177,
            178, 179, 180, 181, 182, 183, 184, 185, 186, 187, 188, 189, 190,
            191, 192, 193, 194, 195, 196, 197, 198, 199, 200, 201, 202, 203,
            204, 205, 206, 207, 208, 209, 210, 211, 212, 213, 214, 215, 216,
            217, 218, 219, 220, 221, 222, 223, 224, 225, 226, 227, 228, 229,
            230, 231, 232, 233, 234, 235, 236, 237, 238, 239, 240, 241, 242,
            243, 244, 245, 246, 247, 248, 249, 250, 251, 252, 253, 254, 255,
          ]));
      })(lib)),
    lib
  );
}
var util = {},
  hasRequiredUtil;
function requireUtil() {
  return (
    hasRequiredUtil ||
      ((hasRequiredUtil = 1),
      (util.stringToBytes = (e) => [...e].map((n) => n.charCodeAt(0))),
      (util.tarHeaderChecksumMatches = (e, n = 0) => {
        const m = parseInt(
          e.toString("utf8", 148, 154).replace(/\0.*$/, "").trim(),
          8,
        );
        if (isNaN(m)) return !1;
        let r = 256;
        for (let o = n; o < n + 148; o++) r += e[o];
        for (let o = n + 156; o < n + 512; o++) r += e[o];
        return m === r;
      }),
      (util.uint32SyncSafeToken = {
        get: (e, n) =>
          (e[n + 3] & 127) | (e[n + 2] << 7) | (e[n + 1] << 14) | (e[n] << 21),
        len: 4,
      })),
    util
  );
}
var supported, hasRequiredSupported;
function requireSupported() {
  return (
    hasRequiredSupported ||
      ((hasRequiredSupported = 1),
      (supported = {
        extensions: [
          "jpg",
          "png",
          "apng",
          "gif",
          "webp",
          "flif",
          "xcf",
          "cr2",
          "cr3",
          "orf",
          "arw",
          "dng",
          "nef",
          "rw2",
          "raf",
          "tif",
          "bmp",
          "icns",
          "jxr",
          "psd",
          "indd",
          "zip",
          "tar",
          "rar",
          "gz",
          "bz2",
          "7z",
          "dmg",
          "mp4",
          "mid",
          "mkv",
          "webm",
          "mov",
          "avi",
          "mpg",
          "mp2",
          "mp3",
          "m4a",
          "oga",
          "ogg",
          "ogv",
          "opus",
          "flac",
          "wav",
          "spx",
          "amr",
          "pdf",
          "epub",
          "exe",
          "swf",
          "rtf",
          "wasm",
          "woff",
          "woff2",
          "eot",
          "ttf",
          "otf",
          "ico",
          "flv",
          "ps",
          "xz",
          "sqlite",
          "nes",
          "crx",
          "xpi",
          "cab",
          "deb",
          "ar",
          "rpm",
          "Z",
          "lz",
          "cfb",
          "mxf",
          "mts",
          "blend",
          "bpg",
          "docx",
          "pptx",
          "xlsx",
          "3gp",
          "3g2",
          "jp2",
          "jpm",
          "jpx",
          "mj2",
          "aif",
          "qcp",
          "odt",
          "ods",
          "odp",
          "xml",
          "mobi",
          "heic",
          "cur",
          "ktx",
          "ape",
          "wv",
          "dcm",
          "ics",
          "glb",
          "pcap",
          "dsf",
          "lnk",
          "alias",
          "voc",
          "ac3",
          "m4v",
          "m4p",
          "m4b",
          "f4v",
          "f4p",
          "f4b",
          "f4a",
          "mie",
          "asf",
          "ogm",
          "ogx",
          "mpc",
          "arrow",
          "shp",
          "aac",
          "mp1",
          "it",
          "s3m",
          "xm",
          "ai",
          "skp",
          "avif",
          "eps",
          "lzh",
          "pgp",
          "asar",
          "stl",
          "chm",
          "3mf",
          "zst",
          "jxl",
          "vcf",
        ],
        mimeTypes: [
          "image/jpeg",
          "image/png",
          "image/gif",
          "image/webp",
          "image/flif",
          "image/x-xcf",
          "image/x-canon-cr2",
          "image/x-canon-cr3",
          "image/tiff",
          "image/bmp",
          "image/vnd.ms-photo",
          "image/vnd.adobe.photoshop",
          "application/x-indesign",
          "application/epub+zip",
          "application/x-xpinstall",
          "application/vnd.oasis.opendocument.text",
          "application/vnd.oasis.opendocument.spreadsheet",
          "application/vnd.oasis.opendocument.presentation",
          "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
          "application/vnd.openxmlformats-officedocument.presentationml.presentation",
          "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
          "application/zip",
          "application/x-tar",
          "application/x-rar-compressed",
          "application/gzip",
          "application/x-bzip2",
          "application/x-7z-compressed",
          "application/x-apple-diskimage",
          "application/x-apache-arrow",
          "video/mp4",
          "audio/midi",
          "video/x-matroska",
          "video/webm",
          "video/quicktime",
          "video/vnd.avi",
          "audio/vnd.wave",
          "audio/qcelp",
          "audio/x-ms-asf",
          "video/x-ms-asf",
          "application/vnd.ms-asf",
          "video/mpeg",
          "video/3gpp",
          "audio/mpeg",
          "audio/mp4",
          "audio/opus",
          "video/ogg",
          "audio/ogg",
          "application/ogg",
          "audio/x-flac",
          "audio/ape",
          "audio/wavpack",
          "audio/amr",
          "application/pdf",
          "application/x-msdownload",
          "application/x-shockwave-flash",
          "application/rtf",
          "application/wasm",
          "font/woff",
          "font/woff2",
          "application/vnd.ms-fontobject",
          "font/ttf",
          "font/otf",
          "image/x-icon",
          "video/x-flv",
          "application/postscript",
          "application/eps",
          "application/x-xz",
          "application/x-sqlite3",
          "application/x-nintendo-nes-rom",
          "application/x-google-chrome-extension",
          "application/vnd.ms-cab-compressed",
          "application/x-deb",
          "application/x-unix-archive",
          "application/x-rpm",
          "application/x-compress",
          "application/x-lzip",
          "application/x-cfb",
          "application/x-mie",
          "application/mxf",
          "video/mp2t",
          "application/x-blender",
          "image/bpg",
          "image/jp2",
          "image/jpx",
          "image/jpm",
          "image/mj2",
          "audio/aiff",
          "application/xml",
          "application/x-mobipocket-ebook",
          "image/heif",
          "image/heif-sequence",
          "image/heic",
          "image/heic-sequence",
          "image/icns",
          "image/ktx",
          "application/dicom",
          "audio/x-musepack",
          "text/calendar",
          "text/vcard",
          "model/gltf-binary",
          "application/vnd.tcpdump.pcap",
          "audio/x-dsf",
          "application/x.ms.shortcut",
          "application/x.apple.alias",
          "audio/x-voc",
          "audio/vnd.dolby.dd-raw",
          "audio/x-m4a",
          "image/apng",
          "image/x-olympus-orf",
          "image/x-sony-arw",
          "image/x-adobe-dng",
          "image/x-nikon-nef",
          "image/x-panasonic-rw2",
          "image/x-fujifilm-raf",
          "video/x-m4v",
          "video/3gpp2",
          "application/x-esri-shape",
          "audio/aac",
          "audio/x-it",
          "audio/x-s3m",
          "audio/x-xm",
          "video/MP1S",
          "video/MP2P",
          "application/vnd.sketchup.skp",
          "image/avif",
          "application/x-lzh-compressed",
          "application/pgp-encrypted",
          "application/x-asar",
          "model/stl",
          "application/vnd.ms-htmlhelp",
          "model/3mf",
          "image/jxl",
          "application/zstd",
        ],
      })),
    supported
  );
}
var core, hasRequiredCore;
function requireCore() {
  if (hasRequiredCore) return core;
  hasRequiredCore = 1;
  const Token = requireLib(),
    strtok3 = requireCore$1(),
    { stringToBytes, tarHeaderChecksumMatches, uint32SyncSafeToken } =
      requireUtil(),
    supported = requireSupported(),
    minimumBytes = 4100;
  async function fromStream(e) {
    const n = await strtok3.fromStream(e);
    try {
      return await fromTokenizer(n);
    } finally {
      await n.close();
    }
  }
  async function fromBuffer(e) {
    if (!(
      e instanceof Uint8Array ||
      e instanceof ArrayBuffer ||
      Buffer.isBuffer(e)
    ))
      throw new TypeError(
        `Expected the \`input\` argument to be of type \`Uint8Array\` or \`Buffer\` or \`ArrayBuffer\`, got \`${typeof e}\``,
      );
    const n = e instanceof Buffer ? e : Buffer.from(e);
    if (!(n && n.length > 1)) return;
    const m = strtok3.fromBuffer(n);
    return fromTokenizer(m);
  }
  function _check(e, n, m) {
    m = { offset: 0, ...m };
    for (const [r, o] of n.entries())
      if (m.mask) {
        if (o !== (m.mask[r] & e[r + m.offset])) return !1;
      } else if (o !== e[r + m.offset]) return !1;
    return !0;
  }
  async function fromTokenizer(e) {
    try {
      return _fromTokenizer(e);
    } catch (n) {
      if (!(n instanceof strtok3.EndOfStreamError)) throw n;
    }
  }
  async function _fromTokenizer(e) {
    let n = Buffer.alloc(minimumBytes);
    const m = 12,
      r = (s, f) => _check(n, s, f),
      o = (s, f) => r(stringToBytes(s), f);
    if (
      (e.fileInfo.size || (e.fileInfo.size = Number.MAX_SAFE_INTEGER),
      await e.peekBuffer(n, { length: m, mayBeLess: !0 }),
      r([66, 77]))
    )
      return { ext: "bmp", mime: "image/bmp" };
    if (r([11, 119])) return { ext: "ac3", mime: "audio/vnd.dolby.dd-raw" };
    if (r([120, 1]))
      return { ext: "dmg", mime: "application/x-apple-diskimage" };
    if (r([77, 90])) return { ext: "exe", mime: "application/x-msdownload" };
    if (r([37, 33]))
      return (
        await e.peekBuffer(n, { length: 24, mayBeLess: !0 }),
        o("PS-Adobe-", { offset: 2 }) && o(" EPSF-", { offset: 14 })
          ? { ext: "eps", mime: "application/eps" }
          : { ext: "ps", mime: "application/postscript" }
      );
    if (r([31, 160]) || r([31, 157]))
      return { ext: "Z", mime: "application/x-compress" };
    if (r([255, 216, 255])) return { ext: "jpg", mime: "image/jpeg" };
    if (r([73, 73, 188])) return { ext: "jxr", mime: "image/vnd.ms-photo" };
    if (r([31, 139, 8])) return { ext: "gz", mime: "application/gzip" };
    if (r([66, 90, 104])) return { ext: "bz2", mime: "application/x-bzip2" };
    if (o("ID3")) {
      await e.ignore(6);
      const s = await e.readToken(uint32SyncSafeToken);
      return e.position + s > e.fileInfo.size
        ? { ext: "mp3", mime: "audio/mpeg" }
        : (await e.ignore(s), fromTokenizer(e));
    }
    if (o("MP+")) return { ext: "mpc", mime: "audio/x-musepack" };
    if ((n[0] === 67 || n[0] === 70) && r([87, 83], { offset: 1 }))
      return { ext: "swf", mime: "application/x-shockwave-flash" };
    if (r([71, 73, 70])) return { ext: "gif", mime: "image/gif" };
    if (o("FLIF")) return { ext: "flif", mime: "image/flif" };
    if (o("8BPS")) return { ext: "psd", mime: "image/vnd.adobe.photoshop" };
    if (o("WEBP", { offset: 8 })) return { ext: "webp", mime: "image/webp" };
    if (o("MPCK")) return { ext: "mpc", mime: "audio/x-musepack" };
    if (o("FORM")) return { ext: "aif", mime: "audio/aiff" };
    if (o("icns", { offset: 0 })) return { ext: "icns", mime: "image/icns" };
    if (r([80, 75, 3, 4])) {
      try {
        for (; e.position + 30 < e.fileInfo.size;) {
          await e.readBuffer(n, { length: 30 });
          const s = {
            compressedSize: n.readUInt32LE(18),
            uncompressedSize: n.readUInt32LE(22),
            filenameLength: n.readUInt16LE(26),
            extraFieldLength: n.readUInt16LE(28),
          };
          if (
            ((s.filename = await e.readToken(
              new Token.StringType(s.filenameLength, "utf-8"),
            )),
            await e.ignore(s.extraFieldLength),
            s.filename === "META-INF/mozilla.rsa")
          )
            return { ext: "xpi", mime: "application/x-xpinstall" };
          if (s.filename.endsWith(".rels") || s.filename.endsWith(".xml"))
            switch (s.filename.split("/")[0]) {
              case "_rels":
                break;
              case "word":
                return {
                  ext: "docx",
                  mime: "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
                };
              case "ppt":
                return {
                  ext: "pptx",
                  mime: "application/vnd.openxmlformats-officedocument.presentationml.presentation",
                };
              case "xl":
                return {
                  ext: "xlsx",
                  mime: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
                };
              default:
                break;
            }
          if (s.filename.startsWith("xl/"))
            return {
              ext: "xlsx",
              mime: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
            };
          if (s.filename.startsWith("3D/") && s.filename.endsWith(".model"))
            return { ext: "3mf", mime: "model/3mf" };
          if (
            s.filename === "mimetype" &&
            s.compressedSize === s.uncompressedSize
          )
            switch (
              await e.readToken(new Token.StringType(s.compressedSize, "utf-8"))
            ) {
              case "application/epub+zip":
                return { ext: "epub", mime: "application/epub+zip" };
              case "application/vnd.oasis.opendocument.text":
                return {
                  ext: "odt",
                  mime: "application/vnd.oasis.opendocument.text",
                };
              case "application/vnd.oasis.opendocument.spreadsheet":
                return {
                  ext: "ods",
                  mime: "application/vnd.oasis.opendocument.spreadsheet",
                };
              case "application/vnd.oasis.opendocument.presentation":
                return {
                  ext: "odp",
                  mime: "application/vnd.oasis.opendocument.presentation",
                };
              default:
            }
          if (s.compressedSize === 0) {
            let f = -1;
            for (; f < 0 && e.position < e.fileInfo.size;)
              (await e.peekBuffer(n, { mayBeLess: !0 }),
                (f = n.indexOf("504B0304", 0, "hex")),
                await e.ignore(f >= 0 ? f : n.length));
          } else await e.ignore(s.compressedSize);
        }
      } catch (s) {
        if (!(s instanceof strtok3.EndOfStreamError)) throw s;
      }
      return { ext: "zip", mime: "application/zip" };
    }
    if (o("OggS")) {
      await e.ignore(28);
      const s = Buffer.alloc(8);
      return (
        await e.readBuffer(s),
        _check(s, [79, 112, 117, 115, 72, 101, 97, 100])
          ? { ext: "opus", mime: "audio/opus" }
          : _check(s, [128, 116, 104, 101, 111, 114, 97])
            ? { ext: "ogv", mime: "video/ogg" }
            : _check(s, [1, 118, 105, 100, 101, 111, 0])
              ? { ext: "ogm", mime: "video/ogg" }
              : _check(s, [127, 70, 76, 65, 67])
                ? { ext: "oga", mime: "audio/ogg" }
                : _check(s, [83, 112, 101, 101, 120, 32, 32])
                  ? { ext: "spx", mime: "audio/ogg" }
                  : _check(s, [1, 118, 111, 114, 98, 105, 115])
                    ? { ext: "ogg", mime: "audio/ogg" }
                    : { ext: "ogx", mime: "application/ogg" }
      );
    }
    if (
      r([80, 75]) &&
      (n[2] === 3 || n[2] === 5 || n[2] === 7) &&
      (n[3] === 4 || n[3] === 6 || n[3] === 8)
    )
      return { ext: "zip", mime: "application/zip" };
    if (o("ftyp", { offset: 4 }) && (n[8] & 96) !== 0) {
      const s = n.toString("binary", 8, 12).replace("\0", " ").trim();
      switch (s) {
        case "avif":
          return { ext: "avif", mime: "image/avif" };
        case "mif1":
          return { ext: "heic", mime: "image/heif" };
        case "msf1":
          return { ext: "heic", mime: "image/heif-sequence" };
        case "heic":
        case "heix":
          return { ext: "heic", mime: "image/heic" };
        case "hevc":
        case "hevx":
          return { ext: "heic", mime: "image/heic-sequence" };
        case "qt":
          return { ext: "mov", mime: "video/quicktime" };
        case "M4V":
        case "M4VH":
        case "M4VP":
          return { ext: "m4v", mime: "video/x-m4v" };
        case "M4P":
          return { ext: "m4p", mime: "video/mp4" };
        case "M4B":
          return { ext: "m4b", mime: "audio/mp4" };
        case "M4A":
          return { ext: "m4a", mime: "audio/x-m4a" };
        case "F4V":
          return { ext: "f4v", mime: "video/mp4" };
        case "F4P":
          return { ext: "f4p", mime: "video/mp4" };
        case "F4A":
          return { ext: "f4a", mime: "audio/mp4" };
        case "F4B":
          return { ext: "f4b", mime: "audio/mp4" };
        case "crx":
          return { ext: "cr3", mime: "image/x-canon-cr3" };
        default:
          return s.startsWith("3g")
            ? s.startsWith("3g2")
              ? { ext: "3g2", mime: "video/3gpp2" }
              : { ext: "3gp", mime: "video/3gpp" }
            : { ext: "mp4", mime: "video/mp4" };
      }
    }
    if (o("MThd")) return { ext: "mid", mime: "audio/midi" };
    if (
      o("wOFF") &&
      (r([0, 1, 0, 0], { offset: 4 }) || o("OTTO", { offset: 4 }))
    )
      return { ext: "woff", mime: "font/woff" };
    if (
      o("wOF2") &&
      (r([0, 1, 0, 0], { offset: 4 }) || o("OTTO", { offset: 4 }))
    )
      return { ext: "woff2", mime: "font/woff2" };
    if (r([212, 195, 178, 161]) || r([161, 178, 195, 212]))
      return { ext: "pcap", mime: "application/vnd.tcpdump.pcap" };
    if (o("DSD ")) return { ext: "dsf", mime: "audio/x-dsf" };
    if (o("LZIP")) return { ext: "lz", mime: "application/x-lzip" };
    if (o("fLaC")) return { ext: "flac", mime: "audio/x-flac" };
    if (r([66, 80, 71, 251])) return { ext: "bpg", mime: "image/bpg" };
    if (o("wvpk")) return { ext: "wv", mime: "audio/wavpack" };
    if (o("%PDF")) {
      await e.ignore(1350);
      const s = 10 * 1024 * 1024,
        f = Buffer.alloc(Math.min(s, e.fileInfo.size));
      return (
        await e.readBuffer(f, { mayBeLess: !0 }),
        f.includes(Buffer.from("AIPrivateData"))
          ? { ext: "ai", mime: "application/postscript" }
          : { ext: "pdf", mime: "application/pdf" }
      );
    }
    if (r([0, 97, 115, 109])) return { ext: "wasm", mime: "application/wasm" };
    if (r([73, 73, 42, 0]))
      return o("CR", { offset: 8 })
        ? { ext: "cr2", mime: "image/x-canon-cr2" }
        : r([28, 0, 254, 0], { offset: 8 }) || r([31, 0, 11, 0], { offset: 8 })
          ? { ext: "nef", mime: "image/x-nikon-nef" }
          : r([8, 0, 0, 0], { offset: 4 }) &&
              (r([45, 0, 254, 0], { offset: 8 }) ||
                r([39, 0, 254, 0], { offset: 8 }))
            ? { ext: "dng", mime: "image/x-adobe-dng" }
            : ((n = Buffer.alloc(24)),
              await e.peekBuffer(n),
              (r([16, 251, 134, 1], { offset: 4 }) ||
                r([8, 0, 0, 0], { offset: 4 })) &&
              r([0, 254, 0, 4, 0, 1, 0, 0, 0, 1, 0, 0, 0, 3, 1], { offset: 9 })
                ? { ext: "arw", mime: "image/x-sony-arw" }
                : { ext: "tif", mime: "image/tiff" });
    if (r([77, 77, 0, 42])) return { ext: "tif", mime: "image/tiff" };
    if (o("MAC ")) return { ext: "ape", mime: "audio/ape" };
    if (r([26, 69, 223, 163])) {
      async function s() {
        const a = await e.peekNumber(Token.UINT8);
        let x = 128,
          c = 0;
        for (; (a & x) === 0 && x !== 0;) (++c, (x >>= 1));
        const d = Buffer.alloc(c + 1);
        return (await e.readBuffer(d), d);
      }
      async function f() {
        const a = await s(),
          x = await s();
        x[0] ^= 128 >> (x.length - 1);
        const c = Math.min(6, x.length);
        return {
          id: a.readUIntBE(0, a.length),
          len: x.readUIntBE(x.length - c, c),
        };
      }
      async function u(a, x) {
        for (; x > 0;) {
          const c = await f();
          if (c.id === 17026)
            return e.readToken(new Token.StringType(c.len, "utf-8"));
          (await e.ignore(c.len), --x);
        }
      }
      const i = await f();
      switch (await u(1, i.len)) {
        case "webm":
          return { ext: "webm", mime: "video/webm" };
        case "matroska":
          return { ext: "mkv", mime: "video/x-matroska" };
        default:
          return;
      }
    }
    if (r([82, 73, 70, 70])) {
      if (r([65, 86, 73], { offset: 8 }))
        return { ext: "avi", mime: "video/vnd.avi" };
      if (r([87, 65, 86, 69], { offset: 8 }))
        return { ext: "wav", mime: "audio/vnd.wave" };
      if (r([81, 76, 67, 77], { offset: 8 }))
        return { ext: "qcp", mime: "audio/qcelp" };
    }
    if (o("SQLi")) return { ext: "sqlite", mime: "application/x-sqlite3" };
    if (r([78, 69, 83, 26]))
      return { ext: "nes", mime: "application/x-nintendo-nes-rom" };
    if (o("Cr24"))
      return { ext: "crx", mime: "application/x-google-chrome-extension" };
    if (o("MSCF") || o("ISc("))
      return { ext: "cab", mime: "application/vnd.ms-cab-compressed" };
    if (r([237, 171, 238, 219]))
      return { ext: "rpm", mime: "application/x-rpm" };
    if (r([197, 208, 211, 198])) return { ext: "eps", mime: "application/eps" };
    if (r([40, 181, 47, 253])) return { ext: "zst", mime: "application/zstd" };
    if (r([79, 84, 84, 79, 0])) return { ext: "otf", mime: "font/otf" };
    if (o("#!AMR")) return { ext: "amr", mime: "audio/amr" };
    if (o("{\\rtf")) return { ext: "rtf", mime: "application/rtf" };
    if (r([70, 76, 86, 1])) return { ext: "flv", mime: "video/x-flv" };
    if (o("IMPM")) return { ext: "it", mime: "audio/x-it" };
    if (
      o("-lh0-", { offset: 2 }) ||
      o("-lh1-", { offset: 2 }) ||
      o("-lh2-", { offset: 2 }) ||
      o("-lh3-", { offset: 2 }) ||
      o("-lh4-", { offset: 2 }) ||
      o("-lh5-", { offset: 2 }) ||
      o("-lh6-", { offset: 2 }) ||
      o("-lh7-", { offset: 2 }) ||
      o("-lzs-", { offset: 2 }) ||
      o("-lz4-", { offset: 2 }) ||
      o("-lz5-", { offset: 2 }) ||
      o("-lhd-", { offset: 2 })
    )
      return { ext: "lzh", mime: "application/x-lzh-compressed" };
    if (r([0, 0, 1, 186])) {
      if (r([33], { offset: 4, mask: [241] }))
        return { ext: "mpg", mime: "video/MP1S" };
      if (r([68], { offset: 4, mask: [196] }))
        return { ext: "mpg", mime: "video/MP2P" };
    }
    if (o("ITSF")) return { ext: "chm", mime: "application/vnd.ms-htmlhelp" };
    if (r([253, 55, 122, 88, 90, 0]))
      return { ext: "xz", mime: "application/x-xz" };
    if (o("<?xml ")) return { ext: "xml", mime: "application/xml" };
    if (r([55, 122, 188, 175, 39, 28]))
      return { ext: "7z", mime: "application/x-7z-compressed" };
    if (r([82, 97, 114, 33, 26, 7]) && (n[6] === 0 || n[6] === 1))
      return { ext: "rar", mime: "application/x-rar-compressed" };
    if (o("solid ")) return { ext: "stl", mime: "model/stl" };
    if (o("BLENDER")) return { ext: "blend", mime: "application/x-blender" };
    if (o("!<arch>"))
      return (
        await e.ignore(8),
        (await e.readToken(new Token.StringType(13, "ascii"))) ===
        "debian-binary"
          ? { ext: "deb", mime: "application/x-deb" }
          : { ext: "ar", mime: "application/x-unix-archive" }
      );
    if (r([137, 80, 78, 71, 13, 10, 26, 10])) {
      await e.ignore(8);
      async function s() {
        return {
          length: await e.readToken(Token.INT32_BE),
          type: await e.readToken(new Token.StringType(4, "binary")),
        };
      }
      do {
        const f = await s();
        if (f.length < 0) return;
        switch (f.type) {
          case "IDAT":
            return { ext: "png", mime: "image/png" };
          case "acTL":
            return { ext: "apng", mime: "image/apng" };
          default:
            await e.ignore(f.length + 4);
        }
      } while (e.position + 8 < e.fileInfo.size);
      return { ext: "png", mime: "image/png" };
    }
    if (r([65, 82, 82, 79, 87, 49, 0, 0]))
      return { ext: "arrow", mime: "application/x-apache-arrow" };
    if (r([103, 108, 84, 70, 2, 0, 0, 0]))
      return { ext: "glb", mime: "model/gltf-binary" };
    if (
      r([102, 114, 101, 101], { offset: 4 }) ||
      r([109, 100, 97, 116], { offset: 4 }) ||
      r([109, 111, 111, 118], { offset: 4 }) ||
      r([119, 105, 100, 101], { offset: 4 })
    )
      return { ext: "mov", mime: "video/quicktime" };
    if (r([73, 73, 82, 79, 8, 0, 0, 0, 24]))
      return { ext: "orf", mime: "image/x-olympus-orf" };
    if (o("gimp xcf ")) return { ext: "xcf", mime: "image/x-xcf" };
    if (r([73, 73, 85, 0, 24, 0, 0, 0, 136, 231, 116, 216]))
      return { ext: "rw2", mime: "image/x-panasonic-rw2" };
    if (r([48, 38, 178, 117, 142, 102, 207, 17, 166, 217])) {
      async function s() {
        const f = Buffer.alloc(16);
        return (
          await e.readBuffer(f),
          { id: f, size: Number(await e.readToken(Token.UINT64_LE)) }
        );
      }
      for (await e.ignore(30); e.position + 24 < e.fileInfo.size;) {
        const f = await s();
        let u = f.size - 24;
        if (
          _check(
            f.id,
            [
              145, 7, 220, 183, 183, 169, 207, 17, 142, 230, 0, 192, 12, 32, 83,
              101,
            ],
          )
        ) {
          const i = Buffer.alloc(16);
          if (
            ((u -= await e.readBuffer(i)),
            _check(
              i,
              [
                64, 158, 105, 248, 77, 91, 207, 17, 168, 253, 0, 128, 95, 92,
                68, 43,
              ],
            ))
          )
            return { ext: "asf", mime: "audio/x-ms-asf" };
          if (
            _check(
              i,
              [
                192, 239, 25, 188, 77, 91, 207, 17, 168, 253, 0, 128, 95, 92,
                68, 43,
              ],
            )
          )
            return { ext: "asf", mime: "video/x-ms-asf" };
          break;
        }
        await e.ignore(u);
      }
      return { ext: "asf", mime: "application/vnd.ms-asf" };
    }
    if (r([171, 75, 84, 88, 32, 49, 49, 187, 13, 10, 26, 10]))
      return { ext: "ktx", mime: "image/ktx" };
    if (
      (r([126, 16, 4]) || r([126, 24, 4])) &&
      r([48, 77, 73, 69], { offset: 4 })
    )
      return { ext: "mie", mime: "application/x-mie" };
    if (r([39, 10, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0], { offset: 2 }))
      return { ext: "shp", mime: "application/x-esri-shape" };
    if (r([0, 0, 0, 12, 106, 80, 32, 32, 13, 10, 135, 10]))
      switch (
        (await e.ignore(20),
        await e.readToken(new Token.StringType(4, "ascii")))
      ) {
        case "jp2 ":
          return { ext: "jp2", mime: "image/jp2" };
        case "jpx ":
          return { ext: "jpx", mime: "image/jpx" };
        case "jpm ":
          return { ext: "jpm", mime: "image/jpm" };
        case "mjp2":
          return { ext: "mj2", mime: "image/mj2" };
        default:
          return;
      }
    if (r([255, 10]) || r([0, 0, 0, 12, 74, 88, 76, 32, 13, 10, 135, 10]))
      return { ext: "jxl", mime: "image/jxl" };
    if (r([0, 0, 1, 186]) || r([0, 0, 1, 179]))
      return { ext: "mpg", mime: "video/mpeg" };
    if (r([0, 1, 0, 0, 0])) return { ext: "ttf", mime: "font/ttf" };
    if (r([0, 0, 1, 0])) return { ext: "ico", mime: "image/x-icon" };
    if (r([0, 0, 2, 0])) return { ext: "cur", mime: "image/x-icon" };
    if (r([208, 207, 17, 224, 161, 177, 26, 225]))
      return { ext: "cfb", mime: "application/x-cfb" };
    if (
      (await e.peekBuffer(n, {
        length: Math.min(256, e.fileInfo.size),
        mayBeLess: !0,
      }),
      o("BEGIN:"))
    ) {
      if (o("VCARD", { offset: 6 })) return { ext: "vcf", mime: "text/vcard" };
      if (o("VCALENDAR", { offset: 6 }))
        return { ext: "ics", mime: "text/calendar" };
    }
    if (o("FUJIFILMCCD-RAW"))
      return { ext: "raf", mime: "image/x-fujifilm-raf" };
    if (o("Extended Module:")) return { ext: "xm", mime: "audio/x-xm" };
    if (o("Creative Voice File")) return { ext: "voc", mime: "audio/x-voc" };
    if (r([4, 0, 0, 0]) && n.length >= 16) {
      const s = n.readUInt32LE(12);
      if (s > 12 && n.length >= s + 16)
        try {
          const f = n.slice(16, s + 16).toString();
          if (JSON.parse(f).files)
            return { ext: "asar", mime: "application/x-asar" };
        } catch {}
    }
    if (r([6, 14, 43, 52, 2, 5, 1, 1, 13, 1, 2, 1, 1, 2]))
      return { ext: "mxf", mime: "application/mxf" };
    if (o("SCRM", { offset: 44 })) return { ext: "s3m", mime: "audio/x-s3m" };
    if (
      r([71], { offset: 4 }) &&
      (r([71], { offset: 192 }) || r([71], { offset: 196 }))
    )
      return { ext: "mts", mime: "video/mp2t" };
    if (r([66, 79, 79, 75, 77, 79, 66, 73], { offset: 60 }))
      return { ext: "mobi", mime: "application/x-mobipocket-ebook" };
    if (r([68, 73, 67, 77], { offset: 128 }))
      return { ext: "dcm", mime: "application/dicom" };
    if (r([76, 0, 0, 0, 1, 20, 2, 0, 0, 0, 0, 0, 192, 0, 0, 0, 0, 0, 0, 70]))
      return { ext: "lnk", mime: "application/x.ms.shortcut" };
    if (r([98, 111, 111, 107, 0, 0, 0, 0, 109, 97, 114, 107, 0, 0, 0, 0]))
      return { ext: "alias", mime: "application/x.apple.alias" };
    if (
      r([76, 80], { offset: 34 }) &&
      (r([0, 0, 1], { offset: 8 }) ||
        r([1, 0, 2], { offset: 8 }) ||
        r([2, 0, 2], { offset: 8 }))
    )
      return { ext: "eot", mime: "application/vnd.ms-fontobject" };
    if (
      r([
        6, 6, 237, 245, 216, 29, 70, 229, 189, 49, 239, 231, 254, 116, 183, 29,
      ])
    )
      return { ext: "indd", mime: "application/x-indesign" };
    if (
      (await e.peekBuffer(n, {
        length: Math.min(512, e.fileInfo.size),
        mayBeLess: !0,
      }),
      tarHeaderChecksumMatches(n))
    )
      return { ext: "tar", mime: "application/x-tar" };
    if (
      r([
        255, 254, 255, 14, 83, 0, 107, 0, 101, 0, 116, 0, 99, 0, 104, 0, 85, 0,
        112, 0, 32, 0, 77, 0, 111, 0, 100, 0, 101, 0, 108, 0,
      ])
    )
      return { ext: "skp", mime: "application/vnd.sketchup.skp" };
    if (o("-----BEGIN PGP MESSAGE-----"))
      return { ext: "pgp", mime: "application/pgp-encrypted" };
    if (n.length >= 2 && r([255, 224], { offset: 0, mask: [255, 224] })) {
      if (r([16], { offset: 1, mask: [22] }))
        return r([8], { offset: 1, mask: [8] })
          ? { ext: "aac", mime: "audio/aac" }
          : { ext: "aac", mime: "audio/aac" };
      if (r([2], { offset: 1, mask: [6] }))
        return { ext: "mp3", mime: "audio/mpeg" };
      if (r([4], { offset: 1, mask: [6] }))
        return { ext: "mp2", mime: "audio/mpeg" };
      if (r([6], { offset: 1, mask: [6] }))
        return { ext: "mp1", mime: "audio/mpeg" };
    }
  }
  const stream = (readableStream) =>
      new Promise((resolve, reject) => {
        const stream = eval("require")("stream");
        (readableStream.on("error", reject),
          readableStream.once("readable", async () => {
            const e = new stream.PassThrough();
            let n;
            stream.pipeline
              ? (n = stream.pipeline(readableStream, e, () => {}))
              : (n = readableStream.pipe(e));
            const m =
              readableStream.read(minimumBytes) ||
              readableStream.read() ||
              Buffer.alloc(0);
            try {
              const r = await fromBuffer(m);
              e.fileType = r;
            } catch (r) {
              reject(r);
            }
            resolve(n);
          }));
      }),
    fileType = { fromStream, fromTokenizer, fromBuffer, stream };
  return (
    Object.defineProperty(fileType, "extensions", {
      get() {
        return new Set(supported.extensions);
      },
    }),
    Object.defineProperty(fileType, "mimeTypes", {
      get() {
        return new Set(supported.mimeTypes);
      },
    }),
    (core = fileType),
    core
  );
}
var fileType_1, hasRequiredFileType;
function requireFileType() {
  if (hasRequiredFileType) return fileType_1;
  hasRequiredFileType = 1;
  const e = requireLib$1(),
    n = requireCore();
  async function m(o) {
    const s = await e.fromFile(o);
    try {
      return await n.fromTokenizer(s);
    } finally {
      await s.close();
    }
  }
  const r = { fromFile: m };
  return (
    Object.assign(r, n),
    Object.defineProperty(r, "extensions", {
      get() {
        return n.extensions;
      },
    }),
    Object.defineProperty(r, "mimeTypes", {
      get() {
        return n.mimeTypes;
      },
    }),
    (fileType_1 = r),
    fileType_1
  );
}
var fileTypeExports = requireFileType();
const FileType = getDefaultExportFromCjs(fileTypeExports),
  index = _mergeNamespaces({ __proto__: null, default: FileType }, [
    fileTypeExports,
  ]),
  AUDIO_MIME_TYPES_BY_EXTENSION = {
    ".aac": "audio/aac",
    ".amr": "audio/amr",
    ".caf": "audio/x-caf",
    ".flac": "audio/flac",
    ".m4a": "audio/mp4",
    ".mp3": "audio/mpeg",
    ".mp4": "audio/mp4",
    ".ogg": "audio/ogg",
    ".opus": "audio/opus",
    ".wav": "audio/wav",
  },
  audioMimeTypeByExtension = (e) => AUDIO_MIME_TYPES_BY_EXTENSION[e];
async function getMimeType(e, n) {
  let m = n || (await FileType.fromFile(e))?.mime;
  if (m !== "video/mp4") return m;
  try {
    const { stdout: r } = await execa(
        FFMPEG_CONFIG.ffprobeBinaryPath,
        [
          "-v",
          "error",
          "-protocol_whitelist",
          "file,pipe",
          "-show_entries",
          "stream=codec_type:stream_disposition=attached_pic",
          "-of",
          "json",
          e,
        ],
        { timeout: 5e3, maxBuffer: 1048576 },
      ),
      o = JSON.parse(r).streams ?? [];
    o.some((s) => s.codec_type === "audio") &&
      !o.some(
        (s) => s.codec_type === "video" && s.disposition?.attached_pic !== 1,
      ) &&
      (m = "audio/mp4");
  } catch {
    logger.warn("Could not inspect MP4 tracks; retaining detected MIME type");
  }
  return m;
}
var VideoCompressionType = ((e) => ((e.HD = "hd"), (e.STRONG = "strong"), e))(
  VideoCompressionType || {},
);
const VIDEO_COMPRESSION_CONFIG = {
    compressionSettings: {
      hd: {
        videoBitrate: "2500k",
        audioBitrate: "128k",
        maxDimension: 960,
        skipSizeThreshold: 50 * 1024 * 1024,
      },
      strong: {
        videoBitrate: "1700k",
        audioBitrate: "96k",
        maxDimension: 848,
        skipSizeThreshold: 5 * 1024 * 1024,
      },
    },
  },
  FFMPEG_CONFIG = {
    ffmpegBinaryPath: PUBLIC_DIR_PATH_UNPACKED + "/ffmpeg",
    ffprobeBinaryPath: PUBLIC_DIR_PATH_UNPACKED + "/ffprobe",
    transcoding: {
      videoCodec: IS_MAC_OS ? "h264_videotoolbox" : "h264",
      videoCodecFallback: "h264",
      compressionSettings: VIDEO_COMPRESSION_CONFIG.compressionSettings,
      videoQuality: "slow",
      audioCodec: "aac",
      containerFormat: "mp4",
      videoTag: "avc1",
      videoFormatMap: { h264: { extension: "mp4", mimeType: "video/mp4" } },
      faststart: !0,
    },
    audioTranscoding: {
      audioFormats: {
        mp3: {
          extension: ".mp3",
          mimeType: AUDIO_MIME_TYPES_BY_EXTENSION[".mp3"],
          args: [],
        },
        mp4: {
          extension: ".mp4",
          mimeType: AUDIO_MIME_TYPES_BY_EXTENSION[".mp4"],
          args: [],
        },
        h264: {
          extension: ".mp4",
          mimeType: "video/mp4",
          args: [
            "-loop",
            "1",
            "-i",
            path__default.join(PUBLIC_DIR_PATH_UNPACKED, "img", "blackbox.jpg"),
            "-c:v",
            IS_MAC_OS ? "h264_videotoolbox" : "h264",
            "-c:a",
            "aac",
            "-vf",
            "scale=size=400x300",
            "-b:v",
            "200k",
            "-g",
            "9999",
            "-shortest",
          ],
        },
        aac: {
          extension: ".aac",
          mimeType: AUDIO_MIME_TYPES_BY_EXTENSION[".aac"],
          args: ["-c:a", "aac"],
        },
        caf: {
          extension: ".caf",
          mimeType: AUDIO_MIME_TYPES_BY_EXTENSION[".caf"],
          args: ["-c:a", "libopus"],
        },
        ogg: {
          extension: ".ogg",
          mimeType: AUDIO_MIME_TYPES_BY_EXTENSION[".ogg"],
          args: ["-c:a", "copy"],
        },
      },
      defaultFormat: "mp3",
    },
  };
async function reportUnlaunchableFFmpegBinaries() {
  for (const e of [
    FFMPEG_CONFIG.ffmpegBinaryPath,
    FFMPEG_CONFIG.ffprobeBinaryPath,
  ])
    try {
      await execa(e, ["-version"]);
    } catch (n) {
      const { shortMessage: m, signal: r, exitCode: o, stderr: s } = n;
      globalThis.Sentry.captureException(
        new Error(`${path__default.basename(e)} failed to launch`),
        {
          tags: { os_release: os.release() },
          extra: {
            message: m,
            signal: r,
            exitCode: o,
            stderr: s?.slice(0, 2e3),
          },
        },
      );
    }
}
class FFmpegError extends Error {
  constructor(n, m, r) {
    (super(n),
      (this.exitCode = m),
      (this.stderr = r),
      (this.name = "FFmpegError"));
  }
}
function rotationFromDisplaymatrix(e) {
  let n, m;
  if (Array.isArray(e) && e.length >= 2) {
    if (
      ((n = Number(e[0])),
      (m = Number(e[1])),
      !Number.isFinite(n) || !Number.isFinite(m))
    )
      return null;
  } else if (typeof e == "string") {
    const r = e
      .split(
        `
`,
      )
      .map((f) => f.trim())
      .find(Boolean);
    if (!r) return null;
    const s = r.split(/\s+/).slice(1).map(Number).filter(Number.isFinite);
    if (s.length < 2) return null;
    ((n = s[0]), (m = s[1]));
  }
  return n === void 0 || m === void 0 || (n === 0 && m === 0)
    ? null
    : Math.round((-Math.atan2(m, n) * 180) / Math.PI);
}
async function getVideoMetadata(e) {
  try {
    const { stdout: n } = await execa(FFMPEG_CONFIG.ffprobeBinaryPath, [
        "-v",
        "error",
        "-select_streams",
        "v:0",
        "-show_streams",
        "-show_format",
        "-of",
        "json",
        e,
      ]),
      m = JSON.parse(n),
      r = m.streams[0] || {},
      o = m.format || {};
    let s = 30;
    if (r.r_frame_rate) {
      const [p, g] = r.r_frame_rate.split("/");
      s = Math.round((Number(p) / Number(g)) * 100) / 100;
    }
    const f = parseInt(r.bit_rate || o.bit_rate || "0", 10),
      u = parseFloat(r.duration || o.duration || "0"),
      i = path__default.extname(e).toLowerCase();
    let t = "video/mp4";
    i === ".webm"
      ? (t = "video/webm")
      : i === ".mov"
        ? (t = "video/quicktime")
        : i === ".avi"
          ? (t = "video/x-msvideo")
          : i === ".mkv" && (t = "video/x-matroska");
    let a = 0;
    if (r.rotation) a = parseInt(r.rotation, 10);
    else if (r.side_data_list)
      for (const p of r.side_data_list) {
        if (p.rotation) {
          a = parseInt(p.rotation, 10);
          break;
        }
        const g = rotationFromDisplaymatrix(p.displaymatrix);
        if (g != null) {
          a = g;
          break;
        }
      }
    let x = r.width || 0,
      c = r.height || 0;
    const d = Math.abs(a);
    (d === 90 || d === 270) && ((x = r.height || 0), (c = r.width || 0));
    const l = r.color_transfer || "",
      h =
        l.includes("smpte2084") ||
        l.includes("arib-std-b67") ||
        l.includes("bt2020");
    return {
      width: r.width || 0,
      height: r.height || 0,
      duration: u,
      fps: s,
      codec: r.codec_name || "unknown",
      bitrate: f,
      mimeType: t,
      rotation: a,
      displayWidth: x,
      displayHeight: c,
      colorProfile: r.color_primaries || void 0,
      isHDR: h,
    };
  } catch (n) {
    throw n instanceof Error && "stderr" in n
      ? new FFmpegError(
          `Failed to get video metadata: ${n.message}`,
          n.exitCode || 1,
          n.stderr,
        )
      : new Error(
          `Failed to get video metadata: ${n instanceof Error ? n.message : String(n)}`,
        );
  }
}
const utils = Object.freeze(
  Object.defineProperty(
    {
      __proto__: null,
      AUDIO_MIME_TYPES_BY_EXTENSION,
      FFMPEG_CONFIG,
      FFmpegError,
      VideoCompressionType,
      audioMimeTypeByExtension,
      getMimeType,
      getVideoMetadata,
      reportUnlaunchableFFmpegBinaries,
    },
    Symbol.toStringTag,
    { value: "Module" },
  ),
);
export {
  FFMPEG_CONFIG as F,
  VideoCompressionType as V,
  FFmpegError as a,
  audioMimeTypeByExtension as b,
  getVideoMetadata as c,
  getMimeType as g,
  index as i,
  reportUnlaunchableFFmpegBinaries as r,
  utils as u,
};
//# sourceMappingURL=utils-D8MokWSu.mjs.map
