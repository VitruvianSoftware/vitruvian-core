import { c as he, g as dt, a as ht } from "./_commonjsHelpers-CBUqixCJ.mjs";
import ir from "path";
import { b as pt, d as mt } from "./main-entry-CnfqTXzU.mjs";
import te from "util";
import nr from "stream";
import bt from "events";
import ar from "buffer";
import { r as fe, a as gt, c as vt } from "./readable-VMWn1OrG.mjs";
import { r as yt } from "./immutable-XCMBOkhu.mjs";
import { r as wt } from "./got-_wC7Q_ix.mjs";
import _t from "string_decoder";
import Bt from "zlib";
import { r as Et } from "./index-BbIDQpmR.mjs";
import St from "fs";
import At from "node:module";
(function () {
  try {
    var m =
      typeof window < "u"
        ? window
        : typeof global < "u"
          ? global
          : typeof globalThis < "u"
            ? globalThis
            : typeof self < "u"
              ? self
              : {};
    m.SENTRY_RELEASE = { id: "4.3.209" };
    var x = new m.Error().stack;
    x &&
      ((m._sentryDebugIds = m._sentryDebugIds || {}),
      (m._sentryDebugIds[x] = "b30071cb-8fa6-4369-8e5a-21de83932651"),
      (m._sentryDebugIdIdentifier =
        "sentry-dbid-b30071cb-8fa6-4369-8e5a-21de83932651"));
  } catch {}
})();
const Si = import.meta.filename,
  Ai = import.meta.dirname,
  ki = At.createRequire(import.meta.url);
function kt(m, x) {
  for (var e = 0; e < x.length; e++) {
    const f = x[e];
    if (typeof f != "string" && !Array.isArray(f)) {
      for (const s in f)
        if (s !== "default" && !(s in m)) {
          const t = Object.getOwnPropertyDescriptor(f, s);
          t &&
            Object.defineProperty(
              m,
              s,
              t.get ? t : { enumerable: !0, get: () => f[s] },
            );
        }
    }
  }
  return Object.freeze(
    Object.defineProperty(m, Symbol.toStringTag, { value: "Module" }),
  );
}
var ye, lr;
function Dt() {
  return (
    lr ||
      ((lr = 1),
      (ye = (m) => {
        const x = new Uint8Array(m);
        if (!(x && x.length > 1)) return null;
        const e = (f, s) => {
          s = Object.assign({ offset: 0 }, s);
          for (let t = 0; t < f.length; t++)
            if (f[t] !== x[t + s.offset]) return !1;
          return !0;
        };
        if (e([255, 216, 255])) return { ext: "jpg", mime: "image/jpeg" };
        if (e([137, 80, 78, 71, 13, 10, 26, 10]))
          return { ext: "png", mime: "image/png" };
        if (e([71, 73, 70])) return { ext: "gif", mime: "image/gif" };
        if (e([87, 69, 66, 80], { offset: 8 }))
          return { ext: "webp", mime: "image/webp" };
        if (e([70, 76, 73, 70])) return { ext: "flif", mime: "image/flif" };
        if (
          (e([73, 73, 42, 0]) || e([77, 77, 0, 42])) &&
          e([67, 82], { offset: 8 })
        )
          return { ext: "cr2", mime: "image/x-canon-cr2" };
        if (e([73, 73, 42, 0]) || e([77, 77, 0, 42]))
          return { ext: "tif", mime: "image/tiff" };
        if (e([66, 77])) return { ext: "bmp", mime: "image/bmp" };
        if (e([73, 73, 188])) return { ext: "jxr", mime: "image/vnd.ms-photo" };
        if (e([56, 66, 80, 83]))
          return { ext: "psd", mime: "image/vnd.adobe.photoshop" };
        if (
          e([80, 75, 3, 4]) &&
          e(
            [
              109, 105, 109, 101, 116, 121, 112, 101, 97, 112, 112, 108, 105,
              99, 97, 116, 105, 111, 110, 47, 101, 112, 117, 98, 43, 122, 105,
              112,
            ],
            { offset: 30 },
          )
        )
          return { ext: "epub", mime: "application/epub+zip" };
        if (
          e([80, 75, 3, 4]) &&
          e(
            [
              77, 69, 84, 65, 45, 73, 78, 70, 47, 109, 111, 122, 105, 108, 108,
              97, 46, 114, 115, 97,
            ],
            { offset: 30 },
          )
        )
          return { ext: "xpi", mime: "application/x-xpinstall" };
        if (
          e([80, 75]) &&
          (x[2] === 3 || x[2] === 5 || x[2] === 7) &&
          (x[3] === 4 || x[3] === 6 || x[3] === 8)
        )
          return { ext: "zip", mime: "application/zip" };
        if (e([117, 115, 116, 97, 114], { offset: 257 }))
          return { ext: "tar", mime: "application/x-tar" };
        if (e([82, 97, 114, 33, 26, 7]) && (x[6] === 0 || x[6] === 1))
          return { ext: "rar", mime: "application/x-rar-compressed" };
        if (e([31, 139, 8])) return { ext: "gz", mime: "application/gzip" };
        if (e([66, 90, 104]))
          return { ext: "bz2", mime: "application/x-bzip2" };
        if (e([55, 122, 188, 175, 39, 28]))
          return { ext: "7z", mime: "application/x-7z-compressed" };
        if (e([120, 1]))
          return { ext: "dmg", mime: "application/x-apple-diskimage" };
        if (
          (e([0, 0, 0]) &&
            (x[3] === 24 || x[3] === 32) &&
            e([102, 116, 121, 112], { offset: 4 })) ||
          e([51, 103, 112, 53]) ||
          (e([0, 0, 0, 28, 102, 116, 121, 112, 109, 112, 52, 50]) &&
            e([109, 112, 52, 49, 109, 112, 52, 50, 105, 115, 111, 109], {
              offset: 16,
            })) ||
          e([0, 0, 0, 28, 102, 116, 121, 112, 105, 115, 111, 109]) ||
          e([0, 0, 0, 28, 102, 116, 121, 112, 109, 112, 52, 50, 0, 0, 0, 0])
        )
          return { ext: "mp4", mime: "video/mp4" };
        if (e([0, 0, 0, 28, 102, 116, 121, 112, 77, 52, 86]))
          return { ext: "m4v", mime: "video/x-m4v" };
        if (e([77, 84, 104, 100])) return { ext: "mid", mime: "audio/midi" };
        if (e([26, 69, 223, 163])) {
          const f = x.subarray(4, 4100),
            s = f.findIndex((t, r, n) => n[r] === 66 && n[r + 1] === 130);
          if (s >= 0) {
            const t = s + 3,
              r = (n) =>
                Array.from(n).every((l, p) => f[t + p] === l.charCodeAt(0));
            if (r("matroska")) return { ext: "mkv", mime: "video/x-matroska" };
            if (r("webm")) return { ext: "webm", mime: "video/webm" };
          }
        }
        return e([0, 0, 0, 20, 102, 116, 121, 112, 113, 116, 32, 32]) ||
          e([102, 114, 101, 101], { offset: 4 }) ||
          e([102, 116, 121, 112, 113, 116, 32, 32], { offset: 4 }) ||
          e([109, 100, 97, 116], { offset: 4 }) ||
          e([119, 105, 100, 101], { offset: 4 })
          ? { ext: "mov", mime: "video/quicktime" }
          : e([82, 73, 70, 70]) && e([65, 86, 73], { offset: 8 })
            ? { ext: "avi", mime: "video/x-msvideo" }
            : e([48, 38, 178, 117, 142, 102, 207, 17, 166, 217])
              ? { ext: "wmv", mime: "video/x-ms-wmv" }
              : e([0, 0, 1, 186])
                ? { ext: "mpg", mime: "video/mpeg" }
                : e([73, 68, 51]) || e([255, 251])
                  ? { ext: "mp3", mime: "audio/mpeg" }
                  : e([102, 116, 121, 112, 77, 52, 65], { offset: 4 }) ||
                      e([77, 52, 65, 32])
                    ? { ext: "m4a", mime: "audio/m4a" }
                    : e([79, 112, 117, 115, 72, 101, 97, 100], { offset: 28 })
                      ? { ext: "opus", mime: "audio/opus" }
                      : e([79, 103, 103, 83])
                        ? { ext: "ogg", mime: "audio/ogg" }
                        : e([102, 76, 97, 67])
                          ? { ext: "flac", mime: "audio/x-flac" }
                          : e([82, 73, 70, 70]) &&
                              e([87, 65, 86, 69], { offset: 8 })
                            ? { ext: "wav", mime: "audio/x-wav" }
                            : e([35, 33, 65, 77, 82, 10])
                              ? { ext: "amr", mime: "audio/amr" }
                              : e([37, 80, 68, 70])
                                ? { ext: "pdf", mime: "application/pdf" }
                                : e([77, 90])
                                  ? {
                                      ext: "exe",
                                      mime: "application/x-msdownload",
                                    }
                                  : (x[0] === 67 || x[0] === 70) &&
                                      e([87, 83], { offset: 1 })
                                    ? {
                                        ext: "swf",
                                        mime: "application/x-shockwave-flash",
                                      }
                                    : e([123, 92, 114, 116, 102])
                                      ? { ext: "rtf", mime: "application/rtf" }
                                      : e([0, 97, 115, 109])
                                        ? {
                                            ext: "wasm",
                                            mime: "application/wasm",
                                          }
                                        : e([119, 79, 70, 70]) &&
                                            (e([0, 1, 0, 0], { offset: 4 }) ||
                                              e([79, 84, 84, 79], {
                                                offset: 4,
                                              }))
                                          ? { ext: "woff", mime: "font/woff" }
                                          : e([119, 79, 70, 50]) &&
                                              (e([0, 1, 0, 0], { offset: 4 }) ||
                                                e([79, 84, 84, 79], {
                                                  offset: 4,
                                                }))
                                            ? {
                                                ext: "woff2",
                                                mime: "font/woff2",
                                              }
                                            : e([76, 80], { offset: 34 }) &&
                                                (e([0, 0, 1], { offset: 8 }) ||
                                                  e([1, 0, 2], { offset: 8 }) ||
                                                  e([2, 0, 2], { offset: 8 }))
                                              ? {
                                                  ext: "eot",
                                                  mime: "application/octet-stream",
                                                }
                                              : e([0, 1, 0, 0, 0])
                                                ? {
                                                    ext: "ttf",
                                                    mime: "font/ttf",
                                                  }
                                                : e([79, 84, 84, 79, 0])
                                                  ? {
                                                      ext: "otf",
                                                      mime: "font/otf",
                                                    }
                                                  : e([0, 0, 1, 0])
                                                    ? {
                                                        ext: "ico",
                                                        mime: "image/x-icon",
                                                      }
                                                    : e([70, 76, 86, 1])
                                                      ? {
                                                          ext: "flv",
                                                          mime: "video/x-flv",
                                                        }
                                                      : e([37, 33])
                                                        ? {
                                                            ext: "ps",
                                                            mime: "application/postscript",
                                                          }
                                                        : e([
                                                              253, 55, 122, 88,
                                                              90, 0,
                                                            ])
                                                          ? {
                                                              ext: "xz",
                                                              mime: "application/x-xz",
                                                            }
                                                          : e([83, 81, 76, 105])
                                                            ? {
                                                                ext: "sqlite",
                                                                mime: "application/x-sqlite3",
                                                              }
                                                            : e([
                                                                  78, 69, 83,
                                                                  26,
                                                                ])
                                                              ? {
                                                                  ext: "nes",
                                                                  mime: "application/x-nintendo-nes-rom",
                                                                }
                                                              : e([
                                                                    67, 114, 50,
                                                                    52,
                                                                  ])
                                                                ? {
                                                                    ext: "crx",
                                                                    mime: "application/x-google-chrome-extension",
                                                                  }
                                                                : e([
                                                                      77, 83,
                                                                      67, 70,
                                                                    ]) ||
                                                                    e([
                                                                      73, 83,
                                                                      99, 40,
                                                                    ])
                                                                  ? {
                                                                      ext: "cab",
                                                                      mime: "application/vnd.ms-cab-compressed",
                                                                    }
                                                                  : e([
                                                                        33, 60,
                                                                        97, 114,
                                                                        99, 104,
                                                                        62, 10,
                                                                        100,
                                                                        101, 98,
                                                                        105, 97,
                                                                        110, 45,
                                                                        98, 105,
                                                                        110, 97,
                                                                        114,
                                                                        121,
                                                                      ])
                                                                    ? {
                                                                        ext: "deb",
                                                                        mime: "application/x-deb",
                                                                      }
                                                                    : e([
                                                                          33,
                                                                          60,
                                                                          97,
                                                                          114,
                                                                          99,
                                                                          104,
                                                                          62,
                                                                        ])
                                                                      ? {
                                                                          ext: "ar",
                                                                          mime: "application/x-unix-archive",
                                                                        }
                                                                      : e([
                                                                            237,
                                                                            171,
                                                                            238,
                                                                            219,
                                                                          ])
                                                                        ? {
                                                                            ext: "rpm",
                                                                            mime: "application/x-rpm",
                                                                          }
                                                                        : e([
                                                                              31,
                                                                              160,
                                                                            ]) ||
                                                                            e([
                                                                              31,
                                                                              157,
                                                                            ])
                                                                          ? {
                                                                              ext: "Z",
                                                                              mime: "application/x-compress",
                                                                            }
                                                                          : e([
                                                                                76,
                                                                                90,
                                                                                73,
                                                                                80,
                                                                              ])
                                                                            ? {
                                                                                ext: "lz",
                                                                                mime: "application/x-lzip",
                                                                              }
                                                                            : e(
                                                                                  [
                                                                                    208,
                                                                                    207,
                                                                                    17,
                                                                                    224,
                                                                                    161,
                                                                                    177,
                                                                                    26,
                                                                                    225,
                                                                                  ],
                                                                                )
                                                                              ? {
                                                                                  ext: "msi",
                                                                                  mime: "application/x-msi",
                                                                                }
                                                                              : e(
                                                                                    [
                                                                                      6,
                                                                                      14,
                                                                                      43,
                                                                                      52,
                                                                                      2,
                                                                                      5,
                                                                                      1,
                                                                                      1,
                                                                                      13,
                                                                                      1,
                                                                                      2,
                                                                                      1,
                                                                                      1,
                                                                                      2,
                                                                                    ],
                                                                                  )
                                                                                ? {
                                                                                    ext: "mxf",
                                                                                    mime: "application/mxf",
                                                                                  }
                                                                                : e(
                                                                                      [
                                                                                        71,
                                                                                      ],
                                                                                      {
                                                                                        offset: 4,
                                                                                      },
                                                                                    ) &&
                                                                                    (e(
                                                                                      [
                                                                                        71,
                                                                                      ],
                                                                                      {
                                                                                        offset: 192,
                                                                                      },
                                                                                    ) ||
                                                                                      e(
                                                                                        [
                                                                                          71,
                                                                                        ],
                                                                                        {
                                                                                          offset: 196,
                                                                                        },
                                                                                      ))
                                                                                  ? {
                                                                                      ext: "mts",
                                                                                      mime: "video/mp2t",
                                                                                    }
                                                                                  : e(
                                                                                        [
                                                                                          66,
                                                                                          76,
                                                                                          69,
                                                                                          78,
                                                                                          68,
                                                                                          69,
                                                                                          82,
                                                                                        ],
                                                                                      )
                                                                                    ? {
                                                                                        ext: "blend",
                                                                                        mime: "application/x-blender",
                                                                                      }
                                                                                    : e(
                                                                                          [
                                                                                            66,
                                                                                            80,
                                                                                            71,
                                                                                            251,
                                                                                          ],
                                                                                        )
                                                                                      ? {
                                                                                          ext: "bpg",
                                                                                          mime: "image/bpg",
                                                                                        }
                                                                                      : null;
      })),
    ye
  );
}
var we = { exports: {} },
  cr;
function fr() {
  if (cr) return we.exports;
  cr = 1;
  var m = (we.exports = function (x) {
    return x !== null && typeof x == "object" && typeof x.pipe == "function";
  });
  return (
    (m.writable = function (x) {
      return (
        m(x) &&
        x.writable !== !1 &&
        typeof x._write == "function" &&
        typeof x._writableState == "object"
      );
    }),
    (m.readable = function (x) {
      return (
        m(x) &&
        x.readable !== !1 &&
        typeof x._read == "function" &&
        typeof x._readableState == "object"
      );
    }),
    (m.duplex = function (x) {
      return m.writable(x) && m.readable(x);
    }),
    (m.transform = function (x) {
      return (
        m.duplex(x) &&
        typeof x._transform == "function" &&
        typeof x._transformState == "object"
      );
    }),
    we.exports
  );
}
var xe = {},
  se = { exports: {} },
  ue = { exports: {} },
  dr;
function pe() {
  if (dr) return ue.exports;
  ((dr = 1),
    typeof process > "u" ||
    !process.version ||
    process.version.indexOf("v0.") === 0 ||
    (process.version.indexOf("v1.") === 0 &&
      process.version.indexOf("v1.8.") !== 0)
      ? (ue.exports = { nextTick: m })
      : (ue.exports = process));
  function m(x, e, f, s) {
    if (typeof x != "function")
      throw new TypeError('"callback" argument must be a function');
    var t = arguments.length,
      r,
      n;
    switch (t) {
      case 0:
      case 1:
        return process.nextTick(x);
      case 2:
        return process.nextTick(function () {
          x.call(null, e);
        });
      case 3:
        return process.nextTick(function () {
          x.call(null, e, f);
        });
      case 4:
        return process.nextTick(function () {
          x.call(null, e, f, s);
        });
      default:
        for (r = new Array(t - 1), n = 0; n < r.length;) r[n++] = arguments[n];
        return process.nextTick(function () {
          x.apply(null, r);
        });
    }
  }
  return ue.exports;
}
var _e, hr;
function Tt() {
  if (hr) return _e;
  hr = 1;
  var m = {}.toString;
  return (
    (_e =
      Array.isArray ||
      function (x) {
        return m.call(x) == "[object Array]";
      }),
    _e
  );
}
var Be, pr;
function it() {
  return (pr || ((pr = 1), (Be = nr)), Be);
}
var le = { exports: {} },
  mr;
function or() {
  return (
    mr ||
      ((mr = 1),
      (function (m, x) {
        var e = ar,
          f = e.Buffer;
        function s(r, n) {
          for (var l in r) n[l] = r[l];
        }
        f.from && f.alloc && f.allocUnsafe && f.allocUnsafeSlow
          ? (m.exports = e)
          : (s(e, x), (x.Buffer = t));
        function t(r, n, l) {
          return f(r, n, l);
        }
        (s(f, t),
          (t.from = function (r, n, l) {
            if (typeof r == "number")
              throw new TypeError("Argument must not be a number");
            return f(r, n, l);
          }),
          (t.alloc = function (r, n, l) {
            if (typeof r != "number")
              throw new TypeError("Argument must be a number");
            var p = f(r);
            return (
              n !== void 0
                ? typeof l == "string"
                  ? p.fill(n, l)
                  : p.fill(n)
                : p.fill(0),
              p
            );
          }),
          (t.allocUnsafe = function (r) {
            if (typeof r != "number")
              throw new TypeError("Argument must be a number");
            return f(r);
          }),
          (t.allocUnsafeSlow = function (r) {
            if (typeof r != "number")
              throw new TypeError("Argument must be a number");
            return e.SlowBuffer(r);
          }));
      })(le, le.exports)),
    le.exports
  );
}
var X = {},
  br;
function oe() {
  if (br) return X;
  br = 1;
  function m(c) {
    return Array.isArray ? Array.isArray(c) : _(c) === "[object Array]";
  }
  X.isArray = m;
  function x(c) {
    return typeof c == "boolean";
  }
  X.isBoolean = x;
  function e(c) {
    return c === null;
  }
  X.isNull = e;
  function f(c) {
    return c == null;
  }
  X.isNullOrUndefined = f;
  function s(c) {
    return typeof c == "number";
  }
  X.isNumber = s;
  function t(c) {
    return typeof c == "string";
  }
  X.isString = t;
  function r(c) {
    return typeof c == "symbol";
  }
  X.isSymbol = r;
  function n(c) {
    return c === void 0;
  }
  X.isUndefined = n;
  function l(c) {
    return _(c) === "[object RegExp]";
  }
  X.isRegExp = l;
  function p(c) {
    return typeof c == "object" && c !== null;
  }
  X.isObject = p;
  function A(c) {
    return _(c) === "[object Date]";
  }
  X.isDate = A;
  function b(c) {
    return _(c) === "[object Error]" || c instanceof Error;
  }
  X.isError = b;
  function B(c) {
    return typeof c == "function";
  }
  X.isFunction = B;
  function w(c) {
    return (
      c === null ||
      typeof c == "boolean" ||
      typeof c == "number" ||
      typeof c == "string" ||
      typeof c == "symbol" ||
      typeof c > "u"
    );
  }
  ((X.isPrimitive = w), (X.isBuffer = ar.Buffer.isBuffer));
  function _(c) {
    return Object.prototype.toString.call(c);
  }
  return X;
}
var Ee = { exports: {} },
  gr;
function Rt() {
  return (
    gr ||
      ((gr = 1),
      (function (m) {
        function x(t, r) {
          if (!(t instanceof r))
            throw new TypeError("Cannot call a class as a function");
        }
        var e = or().Buffer,
          f = te;
        function s(t, r, n) {
          t.copy(r, n);
        }
        ((m.exports = (function () {
          function t() {
            (x(this, t),
              (this.head = null),
              (this.tail = null),
              (this.length = 0));
          }
          return (
            (t.prototype.push = function (n) {
              var l = { data: n, next: null };
              (this.length > 0 ? (this.tail.next = l) : (this.head = l),
                (this.tail = l),
                ++this.length);
            }),
            (t.prototype.unshift = function (n) {
              var l = { data: n, next: this.head };
              (this.length === 0 && (this.tail = l),
                (this.head = l),
                ++this.length);
            }),
            (t.prototype.shift = function () {
              if (this.length !== 0) {
                var n = this.head.data;
                return (
                  this.length === 1
                    ? (this.head = this.tail = null)
                    : (this.head = this.head.next),
                  --this.length,
                  n
                );
              }
            }),
            (t.prototype.clear = function () {
              ((this.head = this.tail = null), (this.length = 0));
            }),
            (t.prototype.join = function (n) {
              if (this.length === 0) return "";
              for (var l = this.head, p = "" + l.data; (l = l.next);)
                p += n + l.data;
              return p;
            }),
            (t.prototype.concat = function (n) {
              if (this.length === 0) return e.alloc(0);
              for (var l = e.allocUnsafe(n >>> 0), p = this.head, A = 0; p;)
                (s(p.data, l, A), (A += p.data.length), (p = p.next));
              return l;
            }),
            t
          );
        })()),
          f &&
            f.inspect &&
            f.inspect.custom &&
            (m.exports.prototype[f.inspect.custom] = function () {
              var t = f.inspect({ length: this.length });
              return this.constructor.name + " " + t;
            }));
      })(Ee)),
    Ee.exports
  );
}
var Se, vr;
function nt() {
  if (vr) return Se;
  vr = 1;
  var m = pe();
  function x(s, t) {
    var r = this,
      n = this._readableState && this._readableState.destroyed,
      l = this._writableState && this._writableState.destroyed;
    return n || l
      ? (t
          ? t(s)
          : s &&
            (this._writableState
              ? this._writableState.errorEmitted ||
                ((this._writableState.errorEmitted = !0),
                m.nextTick(f, this, s))
              : m.nextTick(f, this, s)),
        this)
      : (this._readableState && (this._readableState.destroyed = !0),
        this._writableState && (this._writableState.destroyed = !0),
        this._destroy(s || null, function (p) {
          !t && p
            ? r._writableState
              ? r._writableState.errorEmitted ||
                ((r._writableState.errorEmitted = !0), m.nextTick(f, r, p))
              : m.nextTick(f, r, p)
            : t && t(p);
        }),
        this);
  }
  function e() {
    (this._readableState &&
      ((this._readableState.destroyed = !1),
      (this._readableState.reading = !1),
      (this._readableState.ended = !1),
      (this._readableState.endEmitted = !1)),
      this._writableState &&
        ((this._writableState.destroyed = !1),
        (this._writableState.ended = !1),
        (this._writableState.ending = !1),
        (this._writableState.finalCalled = !1),
        (this._writableState.prefinished = !1),
        (this._writableState.finished = !1),
        (this._writableState.errorEmitted = !1)));
  }
  function f(s, t) {
    s.emit("error", t);
  }
  return ((Se = { destroy: x, undestroy: e }), Se);
}
var Ae, yr;
function at() {
  if (yr) return Ae;
  yr = 1;
  var m = pe();
  Ae = c;
  function x(v) {
    var g = this;
    ((this.next = null),
      (this.entry = null),
      (this.finish = function () {
        G(g, v);
      }));
  }
  var e =
      !process.browser &&
      ["v0.10", "v0.9."].indexOf(process.version.slice(0, 5)) > -1
        ? setImmediate
        : m.nextTick,
    f;
  c.WritableState = w;
  var s = Object.create(oe());
  s.inherits = fe();
  var t = { deprecate: gt() },
    r = it(),
    n = or().Buffer,
    l =
      (typeof he < "u"
        ? he
        : typeof window < "u"
          ? window
          : typeof self < "u"
            ? self
            : {}
      ).Uint8Array || function () {};
  function p(v) {
    return n.from(v);
  }
  function A(v) {
    return n.isBuffer(v) || v instanceof l;
  }
  var b = nt();
  s.inherits(c, r);
  function B() {}
  function w(v, g) {
    ((f = f || re()), (v = v || {}));
    var E = g instanceof f;
    ((this.objectMode = !!v.objectMode),
      E && (this.objectMode = this.objectMode || !!v.writableObjectMode));
    var C = v.highWaterMark,
      M = v.writableHighWaterMark,
      j = this.objectMode ? 16 : 16 * 1024;
    (C || C === 0
      ? (this.highWaterMark = C)
      : E && (M || M === 0)
        ? (this.highWaterMark = M)
        : (this.highWaterMark = j),
      (this.highWaterMark = Math.floor(this.highWaterMark)),
      (this.finalCalled = !1),
      (this.needDrain = !1),
      (this.ending = !1),
      (this.ended = !1),
      (this.finished = !1),
      (this.destroyed = !1));
    var P = v.decodeStrings === !1;
    ((this.decodeStrings = !P),
      (this.defaultEncoding = v.defaultEncoding || "utf8"),
      (this.length = 0),
      (this.writing = !1),
      (this.corked = 0),
      (this.sync = !0),
      (this.bufferProcessing = !1),
      (this.onwrite = function (W) {
        k(g, W);
      }),
      (this.writecb = null),
      (this.writelen = 0),
      (this.bufferedRequest = null),
      (this.lastBufferedRequest = null),
      (this.pendingcb = 0),
      (this.prefinished = !1),
      (this.errorEmitted = !1),
      (this.bufferedRequestCount = 0),
      (this.corkedRequestsFree = new x(this)));
  }
  ((w.prototype.getBuffer = function () {
    for (var g = this.bufferedRequest, E = []; g;) (E.push(g), (g = g.next));
    return E;
  }),
    (function () {
      try {
        Object.defineProperty(w.prototype, "buffer", {
          get: t.deprecate(
            function () {
              return this.getBuffer();
            },
            "_writableState.buffer is deprecated. Use _writableState.getBuffer instead.",
            "DEP0003",
          ),
        });
      } catch {}
    })());
  var _;
  typeof Symbol == "function" &&
  Symbol.hasInstance &&
  typeof Function.prototype[Symbol.hasInstance] == "function"
    ? ((_ = Function.prototype[Symbol.hasInstance]),
      Object.defineProperty(c, Symbol.hasInstance, {
        value: function (v) {
          return _.call(this, v)
            ? !0
            : this !== c
              ? !1
              : v && v._writableState instanceof w;
        },
      }))
    : (_ = function (v) {
        return v instanceof this;
      });
  function c(v) {
    if (((f = f || re()), !_.call(c, this) && !(this instanceof f)))
      return new c(v);
    ((this._writableState = new w(v, this)),
      (this.writable = !0),
      v &&
        (typeof v.write == "function" && (this._write = v.write),
        typeof v.writev == "function" && (this._writev = v.writev),
        typeof v.destroy == "function" && (this._destroy = v.destroy),
        typeof v.final == "function" && (this._final = v.final)),
      r.call(this));
  }
  c.prototype.pipe = function () {
    this.emit("error", new Error("Cannot pipe, not readable"));
  };
  function R(v, g) {
    var E = new Error("write after end");
    (v.emit("error", E), m.nextTick(g, E));
  }
  function i(v, g, E, C) {
    var M = !0,
      j = !1;
    return (
      E === null
        ? (j = new TypeError("May not write null values to stream"))
        : typeof E != "string" &&
          E !== void 0 &&
          !g.objectMode &&
          (j = new TypeError("Invalid non-string/buffer chunk")),
      j && (v.emit("error", j), m.nextTick(C, j), (M = !1)),
      M
    );
  }
  ((c.prototype.write = function (v, g, E) {
    var C = this._writableState,
      M = !1,
      j = !C.objectMode && A(v);
    return (
      j && !n.isBuffer(v) && (v = p(v)),
      typeof g == "function" && ((E = g), (g = null)),
      j ? (g = "buffer") : g || (g = C.defaultEncoding),
      typeof E != "function" && (E = B),
      C.ended
        ? R(this, E)
        : (j || i(this, C, v, E)) &&
          (C.pendingcb++, (M = h(this, C, j, v, g, E))),
      M
    );
  }),
    (c.prototype.cork = function () {
      var v = this._writableState;
      v.corked++;
    }),
    (c.prototype.uncork = function () {
      var v = this._writableState;
      v.corked &&
        (v.corked--,
        !v.writing &&
          !v.corked &&
          !v.bufferProcessing &&
          v.bufferedRequest &&
          q(this, v));
    }),
    (c.prototype.setDefaultEncoding = function (g) {
      if (
        (typeof g == "string" && (g = g.toLowerCase()),
        !(
          [
            "hex",
            "utf8",
            "utf-8",
            "ascii",
            "binary",
            "base64",
            "ucs2",
            "ucs-2",
            "utf16le",
            "utf-16le",
            "raw",
          ].indexOf((g + "").toLowerCase()) > -1
        ))
      )
        throw new TypeError("Unknown encoding: " + g);
      return ((this._writableState.defaultEncoding = g), this);
    }));
  function u(v, g, E) {
    return (
      !v.objectMode &&
        v.decodeStrings !== !1 &&
        typeof g == "string" &&
        (g = n.from(g, E)),
      g
    );
  }
  Object.defineProperty(c.prototype, "writableHighWaterMark", {
    enumerable: !1,
    get: function () {
      return this._writableState.highWaterMark;
    },
  });
  function h(v, g, E, C, M, j) {
    if (!E) {
      var P = u(g, C, M);
      C !== P && ((E = !0), (M = "buffer"), (C = P));
    }
    var W = g.objectMode ? 1 : C.length;
    g.length += W;
    var H = g.length < g.highWaterMark;
    if ((H || (g.needDrain = !0), g.writing || g.corked)) {
      var K = g.lastBufferedRequest;
      ((g.lastBufferedRequest = {
        chunk: C,
        encoding: M,
        isBuf: E,
        callback: j,
        next: null,
      }),
        K
          ? (K.next = g.lastBufferedRequest)
          : (g.bufferedRequest = g.lastBufferedRequest),
        (g.bufferedRequestCount += 1));
    } else d(v, g, !1, W, C, M, j);
    return H;
  }
  function d(v, g, E, C, M, j, P) {
    ((g.writelen = C),
      (g.writecb = P),
      (g.writing = !0),
      (g.sync = !0),
      E ? v._writev(M, g.onwrite) : v._write(M, j, g.onwrite),
      (g.sync = !1));
  }
  function y(v, g, E, C, M) {
    (--g.pendingcb,
      E
        ? (m.nextTick(M, C),
          m.nextTick($, v, g),
          (v._writableState.errorEmitted = !0),
          v.emit("error", C))
        : (M(C),
          (v._writableState.errorEmitted = !0),
          v.emit("error", C),
          $(v, g)));
  }
  function T(v) {
    ((v.writing = !1),
      (v.writecb = null),
      (v.length -= v.writelen),
      (v.writelen = 0));
  }
  function k(v, g) {
    var E = v._writableState,
      C = E.sync,
      M = E.writecb;
    if ((T(E), g)) y(v, E, C, g, M);
    else {
      var j = L(E);
      (!j && !E.corked && !E.bufferProcessing && E.bufferedRequest && q(v, E),
        C ? e(F, v, E, j, M) : F(v, E, j, M));
    }
  }
  function F(v, g, E, C) {
    (E || O(v, g), g.pendingcb--, C(), $(v, g));
  }
  function O(v, g) {
    g.length === 0 && g.needDrain && ((g.needDrain = !1), v.emit("drain"));
  }
  function q(v, g) {
    g.bufferProcessing = !0;
    var E = g.bufferedRequest;
    if (v._writev && E && E.next) {
      var C = g.bufferedRequestCount,
        M = new Array(C),
        j = g.corkedRequestsFree;
      j.entry = E;
      for (var P = 0, W = !0; E;)
        ((M[P] = E), E.isBuf || (W = !1), (E = E.next), (P += 1));
      ((M.allBuffers = W),
        d(v, g, !0, g.length, M, "", j.finish),
        g.pendingcb++,
        (g.lastBufferedRequest = null),
        j.next
          ? ((g.corkedRequestsFree = j.next), (j.next = null))
          : (g.corkedRequestsFree = new x(g)),
        (g.bufferedRequestCount = 0));
    } else {
      for (; E;) {
        var H = E.chunk,
          K = E.encoding,
          a = E.callback,
          o = g.objectMode ? 1 : H.length;
        if (
          (d(v, g, !1, o, H, K, a),
          (E = E.next),
          g.bufferedRequestCount--,
          g.writing)
        )
          break;
      }
      E === null && (g.lastBufferedRequest = null);
    }
    ((g.bufferedRequest = E), (g.bufferProcessing = !1));
  }
  ((c.prototype._write = function (v, g, E) {
    E(new Error("_write() is not implemented"));
  }),
    (c.prototype._writev = null),
    (c.prototype.end = function (v, g, E) {
      var C = this._writableState;
      (typeof v == "function"
        ? ((E = v), (v = null), (g = null))
        : typeof g == "function" && ((E = g), (g = null)),
        v != null && this.write(v, g),
        C.corked && ((C.corked = 1), this.uncork()),
        C.ending || Y(this, C, E));
    }));
  function L(v) {
    return (
      v.ending &&
      v.length === 0 &&
      v.bufferedRequest === null &&
      !v.finished &&
      !v.writing
    );
  }
  function N(v, g) {
    v._final(function (E) {
      (g.pendingcb--,
        E && v.emit("error", E),
        (g.prefinished = !0),
        v.emit("prefinish"),
        $(v, g));
    });
  }
  function Z(v, g) {
    !g.prefinished &&
      !g.finalCalled &&
      (typeof v._final == "function"
        ? (g.pendingcb++, (g.finalCalled = !0), m.nextTick(N, v, g))
        : ((g.prefinished = !0), v.emit("prefinish")));
  }
  function $(v, g) {
    var E = L(g);
    return (
      E &&
        (Z(v, g), g.pendingcb === 0 && ((g.finished = !0), v.emit("finish"))),
      E
    );
  }
  function Y(v, g, E) {
    ((g.ending = !0),
      $(v, g),
      E && (g.finished ? m.nextTick(E) : v.once("finish", E)),
      (g.ended = !0),
      (v.writable = !1));
  }
  function G(v, g, E) {
    var C = v.entry;
    for (v.entry = null; C;) {
      var M = C.callback;
      (g.pendingcb--, M(E), (C = C.next));
    }
    g.corkedRequestsFree.next = v;
  }
  return (
    Object.defineProperty(c.prototype, "destroyed", {
      get: function () {
        return this._writableState === void 0
          ? !1
          : this._writableState.destroyed;
      },
      set: function (v) {
        this._writableState && (this._writableState.destroyed = v);
      },
    }),
    (c.prototype.destroy = b.destroy),
    (c.prototype._undestroy = b.undestroy),
    (c.prototype._destroy = function (v, g) {
      (this.end(), g(v));
    }),
    Ae
  );
}
var ke, wr;
function re() {
  if (wr) return ke;
  wr = 1;
  var m = pe(),
    x =
      Object.keys ||
      function (b) {
        var B = [];
        for (var w in b) B.push(w);
        return B;
      };
  ke = l;
  var e = Object.create(oe());
  e.inherits = fe();
  var f = ft(),
    s = at();
  e.inherits(l, f);
  for (var t = x(s.prototype), r = 0; r < t.length; r++) {
    var n = t[r];
    l.prototype[n] || (l.prototype[n] = s.prototype[n]);
  }
  function l(b) {
    if (!(this instanceof l)) return new l(b);
    (f.call(this, b),
      s.call(this, b),
      b && b.readable === !1 && (this.readable = !1),
      b && b.writable === !1 && (this.writable = !1),
      (this.allowHalfOpen = !0),
      b && b.allowHalfOpen === !1 && (this.allowHalfOpen = !1),
      this.once("end", p));
  }
  Object.defineProperty(l.prototype, "writableHighWaterMark", {
    enumerable: !1,
    get: function () {
      return this._writableState.highWaterMark;
    },
  });
  function p() {
    this.allowHalfOpen || this._writableState.ended || m.nextTick(A, this);
  }
  function A(b) {
    b.end();
  }
  return (
    Object.defineProperty(l.prototype, "destroyed", {
      get: function () {
        return this._readableState === void 0 || this._writableState === void 0
          ? !1
          : this._readableState.destroyed && this._writableState.destroyed;
      },
      set: function (b) {
        this._readableState === void 0 ||
          this._writableState === void 0 ||
          ((this._readableState.destroyed = b),
          (this._writableState.destroyed = b));
      },
    }),
    (l.prototype._destroy = function (b, B) {
      (this.push(null), this.end(), m.nextTick(B, b));
    }),
    ke
  );
}
var De = {},
  ce = { exports: {} },
  _r;
function Ct() {
  return (
    _r ||
      ((_r = 1),
      (function (m, x) {
        var e = ar,
          f = e.Buffer;
        function s(r, n) {
          for (var l in r) n[l] = r[l];
        }
        f.from && f.alloc && f.allocUnsafe && f.allocUnsafeSlow
          ? (m.exports = e)
          : (s(e, x), (x.Buffer = t));
        function t(r, n, l) {
          return f(r, n, l);
        }
        (s(f, t),
          (t.from = function (r, n, l) {
            if (typeof r == "number")
              throw new TypeError("Argument must not be a number");
            return f(r, n, l);
          }),
          (t.alloc = function (r, n, l) {
            if (typeof r != "number")
              throw new TypeError("Argument must be a number");
            var p = f(r);
            return (
              n !== void 0
                ? typeof l == "string"
                  ? p.fill(n, l)
                  : p.fill(n)
                : p.fill(0),
              p
            );
          }),
          (t.allocUnsafe = function (r) {
            if (typeof r != "number")
              throw new TypeError("Argument must be a number");
            return f(r);
          }),
          (t.allocUnsafeSlow = function (r) {
            if (typeof r != "number")
              throw new TypeError("Argument must be a number");
            return e.SlowBuffer(r);
          }));
      })(ce, ce.exports)),
    ce.exports
  );
}
var Br;
function Er() {
  if (Br) return De;
  Br = 1;
  var m = Ct().Buffer,
    x =
      m.isEncoding ||
      function (i) {
        switch (((i = "" + i), i && i.toLowerCase())) {
          case "hex":
          case "utf8":
          case "utf-8":
          case "ascii":
          case "binary":
          case "base64":
          case "ucs2":
          case "ucs-2":
          case "utf16le":
          case "utf-16le":
          case "raw":
            return !0;
          default:
            return !1;
        }
      };
  function e(i) {
    if (!i) return "utf8";
    for (var u; ;)
      switch (i) {
        case "utf8":
        case "utf-8":
          return "utf8";
        case "ucs2":
        case "ucs-2":
        case "utf16le":
        case "utf-16le":
          return "utf16le";
        case "latin1":
        case "binary":
          return "latin1";
        case "base64":
        case "ascii":
        case "hex":
          return i;
        default:
          if (u) return;
          ((i = ("" + i).toLowerCase()), (u = !0));
      }
  }
  function f(i) {
    var u = e(i);
    if (typeof u != "string" && (m.isEncoding === x || !x(i)))
      throw new Error("Unknown encoding: " + i);
    return u || i;
  }
  De.StringDecoder = s;
  function s(i) {
    this.encoding = f(i);
    var u;
    switch (this.encoding) {
      case "utf16le":
        ((this.text = b), (this.end = B), (u = 4));
        break;
      case "utf8":
        ((this.fillLast = l), (u = 4));
        break;
      case "base64":
        ((this.text = w), (this.end = _), (u = 3));
        break;
      default:
        ((this.write = c), (this.end = R));
        return;
    }
    ((this.lastNeed = 0),
      (this.lastTotal = 0),
      (this.lastChar = m.allocUnsafe(u)));
  }
  ((s.prototype.write = function (i) {
    if (i.length === 0) return "";
    var u, h;
    if (this.lastNeed) {
      if (((u = this.fillLast(i)), u === void 0)) return "";
      ((h = this.lastNeed), (this.lastNeed = 0));
    } else h = 0;
    return h < i.length ? (u ? u + this.text(i, h) : this.text(i, h)) : u || "";
  }),
    (s.prototype.end = A),
    (s.prototype.text = p),
    (s.prototype.fillLast = function (i) {
      if (this.lastNeed <= i.length)
        return (
          i.copy(
            this.lastChar,
            this.lastTotal - this.lastNeed,
            0,
            this.lastNeed,
          ),
          this.lastChar.toString(this.encoding, 0, this.lastTotal)
        );
      (i.copy(this.lastChar, this.lastTotal - this.lastNeed, 0, i.length),
        (this.lastNeed -= i.length));
    }));
  function t(i) {
    return i <= 127
      ? 0
      : i >> 5 === 6
        ? 2
        : i >> 4 === 14
          ? 3
          : i >> 3 === 30
            ? 4
            : i >> 6 === 2
              ? -1
              : -2;
  }
  function r(i, u, h) {
    var d = u.length - 1;
    if (d < h) return 0;
    var y = t(u[d]);
    return y >= 0
      ? (y > 0 && (i.lastNeed = y - 1), y)
      : --d < h || y === -2
        ? 0
        : ((y = t(u[d])),
          y >= 0
            ? (y > 0 && (i.lastNeed = y - 2), y)
            : --d < h || y === -2
              ? 0
              : ((y = t(u[d])),
                y >= 0
                  ? (y > 0 && (y === 2 ? (y = 0) : (i.lastNeed = y - 3)), y)
                  : 0));
  }
  function n(i, u, h) {
    if ((u[0] & 192) !== 128) return ((i.lastNeed = 0), "�");
    if (i.lastNeed > 1 && u.length > 1) {
      if ((u[1] & 192) !== 128) return ((i.lastNeed = 1), "�");
      if (i.lastNeed > 2 && u.length > 2 && (u[2] & 192) !== 128)
        return ((i.lastNeed = 2), "�");
    }
  }
  function l(i) {
    var u = this.lastTotal - this.lastNeed,
      h = n(this, i);
    if (h !== void 0) return h;
    if (this.lastNeed <= i.length)
      return (
        i.copy(this.lastChar, u, 0, this.lastNeed),
        this.lastChar.toString(this.encoding, 0, this.lastTotal)
      );
    (i.copy(this.lastChar, u, 0, i.length), (this.lastNeed -= i.length));
  }
  function p(i, u) {
    var h = r(this, i, u);
    if (!this.lastNeed) return i.toString("utf8", u);
    this.lastTotal = h;
    var d = i.length - (h - this.lastNeed);
    return (i.copy(this.lastChar, 0, d), i.toString("utf8", u, d));
  }
  function A(i) {
    var u = i && i.length ? this.write(i) : "";
    return this.lastNeed ? u + "�" : u;
  }
  function b(i, u) {
    if ((i.length - u) % 2 === 0) {
      var h = i.toString("utf16le", u);
      if (h) {
        var d = h.charCodeAt(h.length - 1);
        if (d >= 55296 && d <= 56319)
          return (
            (this.lastNeed = 2),
            (this.lastTotal = 4),
            (this.lastChar[0] = i[i.length - 2]),
            (this.lastChar[1] = i[i.length - 1]),
            h.slice(0, -1)
          );
      }
      return h;
    }
    return (
      (this.lastNeed = 1),
      (this.lastTotal = 2),
      (this.lastChar[0] = i[i.length - 1]),
      i.toString("utf16le", u, i.length - 1)
    );
  }
  function B(i) {
    var u = i && i.length ? this.write(i) : "";
    if (this.lastNeed) {
      var h = this.lastTotal - this.lastNeed;
      return u + this.lastChar.toString("utf16le", 0, h);
    }
    return u;
  }
  function w(i, u) {
    var h = (i.length - u) % 3;
    return h === 0
      ? i.toString("base64", u)
      : ((this.lastNeed = 3 - h),
        (this.lastTotal = 3),
        h === 1
          ? (this.lastChar[0] = i[i.length - 1])
          : ((this.lastChar[0] = i[i.length - 2]),
            (this.lastChar[1] = i[i.length - 1])),
        i.toString("base64", u, i.length - h));
  }
  function _(i) {
    var u = i && i.length ? this.write(i) : "";
    return this.lastNeed
      ? u + this.lastChar.toString("base64", 0, 3 - this.lastNeed)
      : u;
  }
  function c(i) {
    return i.toString(this.encoding);
  }
  function R(i) {
    return i && i.length ? this.write(i) : "";
  }
  return De;
}
var Te, Sr;
function ft() {
  if (Sr) return Te;
  Sr = 1;
  var m = pe();
  Te = u;
  var x = Tt(),
    e;
  ((u.ReadableState = i), bt.EventEmitter);
  var f = function (a, o) {
      return a.listeners(o).length;
    },
    s = it(),
    t = or().Buffer,
    r =
      (typeof he < "u"
        ? he
        : typeof window < "u"
          ? window
          : typeof self < "u"
            ? self
            : {}
      ).Uint8Array || function () {};
  function n(a) {
    return t.from(a);
  }
  function l(a) {
    return t.isBuffer(a) || a instanceof r;
  }
  var p = Object.create(oe());
  p.inherits = fe();
  var A = te,
    b = void 0;
  A && A.debuglog ? (b = A.debuglog("stream")) : (b = function () {});
  var B = Rt(),
    w = nt(),
    _;
  p.inherits(u, s);
  var c = ["error", "close", "destroy", "pause", "resume"];
  function R(a, o, S) {
    if (typeof a.prependListener == "function") return a.prependListener(o, S);
    !a._events || !a._events[o]
      ? a.on(o, S)
      : x(a._events[o])
        ? a._events[o].unshift(S)
        : (a._events[o] = [S, a._events[o]]);
  }
  function i(a, o) {
    ((e = e || re()), (a = a || {}));
    var S = o instanceof e;
    ((this.objectMode = !!a.objectMode),
      S && (this.objectMode = this.objectMode || !!a.readableObjectMode));
    var D = a.highWaterMark,
      I = a.readableHighWaterMark,
      z = this.objectMode ? 16 : 16 * 1024;
    (D || D === 0
      ? (this.highWaterMark = D)
      : S && (I || I === 0)
        ? (this.highWaterMark = I)
        : (this.highWaterMark = z),
      (this.highWaterMark = Math.floor(this.highWaterMark)),
      (this.buffer = new B()),
      (this.length = 0),
      (this.pipes = null),
      (this.pipesCount = 0),
      (this.flowing = null),
      (this.ended = !1),
      (this.endEmitted = !1),
      (this.reading = !1),
      (this.sync = !0),
      (this.needReadable = !1),
      (this.emittedReadable = !1),
      (this.readableListening = !1),
      (this.resumeScheduled = !1),
      (this.destroyed = !1),
      (this.defaultEncoding = a.defaultEncoding || "utf8"),
      (this.awaitDrain = 0),
      (this.readingMore = !1),
      (this.decoder = null),
      (this.encoding = null),
      a.encoding &&
        (_ || (_ = Er().StringDecoder),
        (this.decoder = new _(a.encoding)),
        (this.encoding = a.encoding)));
  }
  function u(a) {
    if (((e = e || re()), !(this instanceof u))) return new u(a);
    ((this._readableState = new i(a, this)),
      (this.readable = !0),
      a &&
        (typeof a.read == "function" && (this._read = a.read),
        typeof a.destroy == "function" && (this._destroy = a.destroy)),
      s.call(this));
  }
  (Object.defineProperty(u.prototype, "destroyed", {
    get: function () {
      return this._readableState === void 0
        ? !1
        : this._readableState.destroyed;
    },
    set: function (a) {
      this._readableState && (this._readableState.destroyed = a);
    },
  }),
    (u.prototype.destroy = w.destroy),
    (u.prototype._undestroy = w.undestroy),
    (u.prototype._destroy = function (a, o) {
      (this.push(null), o(a));
    }),
    (u.prototype.push = function (a, o) {
      var S = this._readableState,
        D;
      return (
        S.objectMode
          ? (D = !0)
          : typeof a == "string" &&
            ((o = o || S.defaultEncoding),
            o !== S.encoding && ((a = t.from(a, o)), (o = "")),
            (D = !0)),
        h(this, a, o, !1, D)
      );
    }),
    (u.prototype.unshift = function (a) {
      return h(this, a, null, !0, !1);
    }));
  function h(a, o, S, D, I) {
    var z = a._readableState;
    if (o === null) ((z.reading = !1), q(a, z));
    else {
      var U;
      (I || (U = y(z, o)),
        U
          ? a.emit("error", U)
          : z.objectMode || (o && o.length > 0)
            ? (typeof o != "string" &&
                !z.objectMode &&
                Object.getPrototypeOf(o) !== t.prototype &&
                (o = n(o)),
              D
                ? z.endEmitted
                  ? a.emit(
                      "error",
                      new Error("stream.unshift() after end event"),
                    )
                  : d(a, z, o, !0)
                : z.ended
                  ? a.emit("error", new Error("stream.push() after EOF"))
                  : ((z.reading = !1),
                    z.decoder && !S
                      ? ((o = z.decoder.write(o)),
                        z.objectMode || o.length !== 0
                          ? d(a, z, o, !1)
                          : Z(a, z))
                      : d(a, z, o, !1)))
            : D || (z.reading = !1));
    }
    return T(z);
  }
  function d(a, o, S, D) {
    (o.flowing && o.length === 0 && !o.sync
      ? (a.emit("data", S), a.read(0))
      : ((o.length += o.objectMode ? 1 : S.length),
        D ? o.buffer.unshift(S) : o.buffer.push(S),
        o.needReadable && L(a)),
      Z(a, o));
  }
  function y(a, o) {
    var S;
    return (
      !l(o) &&
        typeof o != "string" &&
        o !== void 0 &&
        !a.objectMode &&
        (S = new TypeError("Invalid non-string/buffer chunk")),
      S
    );
  }
  function T(a) {
    return (
      !a.ended &&
      (a.needReadable || a.length < a.highWaterMark || a.length === 0)
    );
  }
  ((u.prototype.isPaused = function () {
    return this._readableState.flowing === !1;
  }),
    (u.prototype.setEncoding = function (a) {
      return (
        _ || (_ = Er().StringDecoder),
        (this._readableState.decoder = new _(a)),
        (this._readableState.encoding = a),
        this
      );
    }));
  var k = 8388608;
  function F(a) {
    return (
      a >= k
        ? (a = k)
        : (a--,
          (a |= a >>> 1),
          (a |= a >>> 2),
          (a |= a >>> 4),
          (a |= a >>> 8),
          (a |= a >>> 16),
          a++),
      a
    );
  }
  function O(a, o) {
    return a <= 0 || (o.length === 0 && o.ended)
      ? 0
      : o.objectMode
        ? 1
        : a !== a
          ? o.flowing && o.length
            ? o.buffer.head.data.length
            : o.length
          : (a > o.highWaterMark && (o.highWaterMark = F(a)),
            a <= o.length
              ? a
              : o.ended
                ? o.length
                : ((o.needReadable = !0), 0));
  }
  u.prototype.read = function (a) {
    (b("read", a), (a = parseInt(a, 10)));
    var o = this._readableState,
      S = a;
    if (
      (a !== 0 && (o.emittedReadable = !1),
      a === 0 && o.needReadable && (o.length >= o.highWaterMark || o.ended))
    )
      return (
        b("read: emitReadable", o.length, o.ended),
        o.length === 0 && o.ended ? W(this) : L(this),
        null
      );
    if (((a = O(a, o)), a === 0 && o.ended))
      return (o.length === 0 && W(this), null);
    var D = o.needReadable;
    (b("need readable", D),
      (o.length === 0 || o.length - a < o.highWaterMark) &&
        ((D = !0), b("length less than watermark", D)),
      o.ended || o.reading
        ? ((D = !1), b("reading or ended", D))
        : D &&
          (b("do read"),
          (o.reading = !0),
          (o.sync = !0),
          o.length === 0 && (o.needReadable = !0),
          this._read(o.highWaterMark),
          (o.sync = !1),
          o.reading || (a = O(S, o))));
    var I;
    return (
      a > 0 ? (I = C(a, o)) : (I = null),
      I === null ? ((o.needReadable = !0), (a = 0)) : (o.length -= a),
      o.length === 0 &&
        (o.ended || (o.needReadable = !0), S !== a && o.ended && W(this)),
      I !== null && this.emit("data", I),
      I
    );
  };
  function q(a, o) {
    if (!o.ended) {
      if (o.decoder) {
        var S = o.decoder.end();
        S &&
          S.length &&
          (o.buffer.push(S), (o.length += o.objectMode ? 1 : S.length));
      }
      ((o.ended = !0), L(a));
    }
  }
  function L(a) {
    var o = a._readableState;
    ((o.needReadable = !1),
      o.emittedReadable ||
        (b("emitReadable", o.flowing),
        (o.emittedReadable = !0),
        o.sync ? m.nextTick(N, a) : N(a)));
  }
  function N(a) {
    (b("emit readable"), a.emit("readable"), E(a));
  }
  function Z(a, o) {
    o.readingMore || ((o.readingMore = !0), m.nextTick($, a, o));
  }
  function $(a, o) {
    for (
      var S = o.length;
      !o.reading &&
      !o.flowing &&
      !o.ended &&
      o.length < o.highWaterMark &&
      (b("maybeReadMore read 0"), a.read(0), S !== o.length);
    )
      S = o.length;
    o.readingMore = !1;
  }
  ((u.prototype._read = function (a) {
    this.emit("error", new Error("_read() is not implemented"));
  }),
    (u.prototype.pipe = function (a, o) {
      var S = this,
        D = this._readableState;
      switch (D.pipesCount) {
        case 0:
          D.pipes = a;
          break;
        case 1:
          D.pipes = [D.pipes, a];
          break;
        default:
          D.pipes.push(a);
          break;
      }
      ((D.pipesCount += 1), b("pipe count=%d opts=%j", D.pipesCount, o));
      var I =
          (!o || o.end !== !1) && a !== process.stdout && a !== process.stderr,
        z = I ? V : ie;
      (D.endEmitted ? m.nextTick(z) : S.once("end", z), a.on("unpipe", U));
      function U(ee, ne) {
        (b("onunpipe"),
          ee === S &&
            ne &&
            ne.hasUnpiped === !1 &&
            ((ne.hasUnpiped = !0), ct()));
      }
      function V() {
        (b("onend"), a.end());
      }
      var J = Y(S);
      a.on("drain", J);
      var sr = !1;
      function ct() {
        (b("cleanup"),
          a.removeListener("close", ge),
          a.removeListener("finish", ve),
          a.removeListener("drain", J),
          a.removeListener("error", be),
          a.removeListener("unpipe", U),
          S.removeListener("end", V),
          S.removeListener("end", ie),
          S.removeListener("data", ur),
          (sr = !0),
          D.awaitDrain &&
            (!a._writableState || a._writableState.needDrain) &&
            J());
      }
      var me = !1;
      S.on("data", ur);
      function ur(ee) {
        (b("ondata"), (me = !1));
        var ne = a.write(ee);
        ne === !1 &&
          !me &&
          (((D.pipesCount === 1 && D.pipes === a) ||
            (D.pipesCount > 1 && K(D.pipes, a) !== -1)) &&
            !sr &&
            (b("false write response, pause", D.awaitDrain),
            D.awaitDrain++,
            (me = !0)),
          S.pause());
      }
      function be(ee) {
        (b("onerror", ee),
          ie(),
          a.removeListener("error", be),
          f(a, "error") === 0 && a.emit("error", ee));
      }
      R(a, "error", be);
      function ge() {
        (a.removeListener("finish", ve), ie());
      }
      a.once("close", ge);
      function ve() {
        (b("onfinish"), a.removeListener("close", ge), ie());
      }
      a.once("finish", ve);
      function ie() {
        (b("unpipe"), S.unpipe(a));
      }
      return (
        a.emit("pipe", S),
        D.flowing || (b("pipe resume"), S.resume()),
        a
      );
    }));
  function Y(a) {
    return function () {
      var o = a._readableState;
      (b("pipeOnDrain", o.awaitDrain),
        o.awaitDrain && o.awaitDrain--,
        o.awaitDrain === 0 && f(a, "data") && ((o.flowing = !0), E(a)));
    };
  }
  ((u.prototype.unpipe = function (a) {
    var o = this._readableState,
      S = { hasUnpiped: !1 };
    if (o.pipesCount === 0) return this;
    if (o.pipesCount === 1)
      return a && a !== o.pipes
        ? this
        : (a || (a = o.pipes),
          (o.pipes = null),
          (o.pipesCount = 0),
          (o.flowing = !1),
          a && a.emit("unpipe", this, S),
          this);
    if (!a) {
      var D = o.pipes,
        I = o.pipesCount;
      ((o.pipes = null), (o.pipesCount = 0), (o.flowing = !1));
      for (var z = 0; z < I; z++) D[z].emit("unpipe", this, { hasUnpiped: !1 });
      return this;
    }
    var U = K(o.pipes, a);
    return U === -1
      ? this
      : (o.pipes.splice(U, 1),
        (o.pipesCount -= 1),
        o.pipesCount === 1 && (o.pipes = o.pipes[0]),
        a.emit("unpipe", this, S),
        this);
  }),
    (u.prototype.on = function (a, o) {
      var S = s.prototype.on.call(this, a, o);
      if (a === "data") this._readableState.flowing !== !1 && this.resume();
      else if (a === "readable") {
        var D = this._readableState;
        !D.endEmitted &&
          !D.readableListening &&
          ((D.readableListening = D.needReadable = !0),
          (D.emittedReadable = !1),
          D.reading ? D.length && L(this) : m.nextTick(G, this));
      }
      return S;
    }),
    (u.prototype.addListener = u.prototype.on));
  function G(a) {
    (b("readable nexttick read 0"), a.read(0));
  }
  u.prototype.resume = function () {
    var a = this._readableState;
    return (a.flowing || (b("resume"), (a.flowing = !0), v(this, a)), this);
  };
  function v(a, o) {
    o.resumeScheduled || ((o.resumeScheduled = !0), m.nextTick(g, a, o));
  }
  function g(a, o) {
    (o.reading || (b("resume read 0"), a.read(0)),
      (o.resumeScheduled = !1),
      (o.awaitDrain = 0),
      a.emit("resume"),
      E(a),
      o.flowing && !o.reading && a.read(0));
  }
  u.prototype.pause = function () {
    return (
      b("call pause flowing=%j", this._readableState.flowing),
      this._readableState.flowing !== !1 &&
        (b("pause"), (this._readableState.flowing = !1), this.emit("pause")),
      this
    );
  };
  function E(a) {
    var o = a._readableState;
    for (b("flow", o.flowing); o.flowing && a.read() !== null;);
  }
  ((u.prototype.wrap = function (a) {
    var o = this,
      S = this._readableState,
      D = !1;
    (a.on("end", function () {
      if ((b("wrapped end"), S.decoder && !S.ended)) {
        var U = S.decoder.end();
        U && U.length && o.push(U);
      }
      o.push(null);
    }),
      a.on("data", function (U) {
        if (
          (b("wrapped data"),
          S.decoder && (U = S.decoder.write(U)),
          !(S.objectMode && U == null) && !(!S.objectMode && (!U || !U.length)))
        ) {
          var V = o.push(U);
          V || ((D = !0), a.pause());
        }
      }));
    for (var I in a)
      this[I] === void 0 &&
        typeof a[I] == "function" &&
        (this[I] = (function (U) {
          return function () {
            return a[U].apply(a, arguments);
          };
        })(I));
    for (var z = 0; z < c.length; z++) a.on(c[z], this.emit.bind(this, c[z]));
    return (
      (this._read = function (U) {
        (b("wrapped _read", U), D && ((D = !1), a.resume()));
      }),
      this
    );
  }),
    Object.defineProperty(u.prototype, "readableHighWaterMark", {
      enumerable: !1,
      get: function () {
        return this._readableState.highWaterMark;
      },
    }),
    (u._fromList = C));
  function C(a, o) {
    if (o.length === 0) return null;
    var S;
    return (
      o.objectMode
        ? (S = o.buffer.shift())
        : !a || a >= o.length
          ? (o.decoder
              ? (S = o.buffer.join(""))
              : o.buffer.length === 1
                ? (S = o.buffer.head.data)
                : (S = o.buffer.concat(o.length)),
            o.buffer.clear())
          : (S = M(a, o.buffer, o.decoder)),
      S
    );
  }
  function M(a, o, S) {
    var D;
    return (
      a < o.head.data.length
        ? ((D = o.head.data.slice(0, a)), (o.head.data = o.head.data.slice(a)))
        : a === o.head.data.length
          ? (D = o.shift())
          : (D = S ? j(a, o) : P(a, o)),
      D
    );
  }
  function j(a, o) {
    var S = o.head,
      D = 1,
      I = S.data;
    for (a -= I.length; (S = S.next);) {
      var z = S.data,
        U = a > z.length ? z.length : a;
      if (
        (U === z.length ? (I += z) : (I += z.slice(0, a)), (a -= U), a === 0)
      ) {
        U === z.length
          ? (++D, S.next ? (o.head = S.next) : (o.head = o.tail = null))
          : ((o.head = S), (S.data = z.slice(U)));
        break;
      }
      ++D;
    }
    return ((o.length -= D), I);
  }
  function P(a, o) {
    var S = t.allocUnsafe(a),
      D = o.head,
      I = 1;
    for (D.data.copy(S), a -= D.data.length; (D = D.next);) {
      var z = D.data,
        U = a > z.length ? z.length : a;
      if ((z.copy(S, S.length - a, 0, U), (a -= U), a === 0)) {
        U === z.length
          ? (++I, D.next ? (o.head = D.next) : (o.head = o.tail = null))
          : ((o.head = D), (D.data = z.slice(U)));
        break;
      }
      ++I;
    }
    return ((o.length -= I), S);
  }
  function W(a) {
    var o = a._readableState;
    if (o.length > 0)
      throw new Error('"endReadable()" called on non-empty stream');
    o.endEmitted || ((o.ended = !0), m.nextTick(H, o, a));
  }
  function H(a, o) {
    !a.endEmitted &&
      a.length === 0 &&
      ((a.endEmitted = !0), (o.readable = !1), o.emit("end"));
  }
  function K(a, o) {
    for (var S = 0, D = a.length; S < D; S++) if (a[S] === o) return S;
    return -1;
  }
  return Te;
}
var Re, Ar;
function ot() {
  if (Ar) return Re;
  ((Ar = 1), (Re = f));
  var m = re(),
    x = Object.create(oe());
  ((x.inherits = fe()), x.inherits(f, m));
  function e(r, n) {
    var l = this._transformState;
    l.transforming = !1;
    var p = l.writecb;
    if (!p)
      return this.emit(
        "error",
        new Error("write callback called multiple times"),
      );
    ((l.writechunk = null),
      (l.writecb = null),
      n != null && this.push(n),
      p(r));
    var A = this._readableState;
    ((A.reading = !1),
      (A.needReadable || A.length < A.highWaterMark) &&
        this._read(A.highWaterMark));
  }
  function f(r) {
    if (!(this instanceof f)) return new f(r);
    (m.call(this, r),
      (this._transformState = {
        afterTransform: e.bind(this),
        needTransform: !1,
        transforming: !1,
        writecb: null,
        writechunk: null,
        writeencoding: null,
      }),
      (this._readableState.needReadable = !0),
      (this._readableState.sync = !1),
      r &&
        (typeof r.transform == "function" && (this._transform = r.transform),
        typeof r.flush == "function" && (this._flush = r.flush)),
      this.on("prefinish", s));
  }
  function s() {
    var r = this;
    typeof this._flush == "function"
      ? this._flush(function (n, l) {
          t(r, n, l);
        })
      : t(this, null, null);
  }
  ((f.prototype.push = function (r, n) {
    return (
      (this._transformState.needTransform = !1),
      m.prototype.push.call(this, r, n)
    );
  }),
    (f.prototype._transform = function (r, n, l) {
      throw new Error("_transform() is not implemented");
    }),
    (f.prototype._write = function (r, n, l) {
      var p = this._transformState;
      if (
        ((p.writecb = l),
        (p.writechunk = r),
        (p.writeencoding = n),
        !p.transforming)
      ) {
        var A = this._readableState;
        (p.needTransform || A.needReadable || A.length < A.highWaterMark) &&
          this._read(A.highWaterMark);
      }
    }),
    (f.prototype._read = function (r) {
      var n = this._transformState;
      n.writechunk !== null && n.writecb && !n.transforming
        ? ((n.transforming = !0),
          this._transform(n.writechunk, n.writeencoding, n.afterTransform))
        : (n.needTransform = !0);
    }),
    (f.prototype._destroy = function (r, n) {
      var l = this;
      m.prototype._destroy.call(this, r, function (p) {
        (n(p), l.emit("close"));
      });
    }));
  function t(r, n, l) {
    if (n) return r.emit("error", n);
    if ((l != null && r.push(l), r._writableState.length))
      throw new Error("Calling transform done when ws.length != 0");
    if (r._transformState.transforming)
      throw new Error("Calling transform done when still transforming");
    return r.push(null);
  }
  return Re;
}
var Ce, kr;
function Ft() {
  if (kr) return Ce;
  ((kr = 1), (Ce = e));
  var m = ot(),
    x = Object.create(oe());
  ((x.inherits = fe()), x.inherits(e, m));
  function e(f) {
    if (!(this instanceof e)) return new e(f);
    m.call(this, f);
  }
  return (
    (e.prototype._transform = function (f, s, t) {
      t(null, f);
    }),
    Ce
  );
}
var Dr;
function ae() {
  return (
    Dr ||
      ((Dr = 1),
      (function (m, x) {
        var e = nr;
        process.env.READABLE_STREAM === "disable" && e
          ? ((m.exports = e),
            (x = m.exports = e.Readable),
            (x.Readable = e.Readable),
            (x.Writable = e.Writable),
            (x.Duplex = e.Duplex),
            (x.Transform = e.Transform),
            (x.PassThrough = e.PassThrough),
            (x.Stream = e))
          : ((x = m.exports = ft()),
            (x.Stream = e || x),
            (x.Readable = x),
            (x.Writable = at()),
            (x.Duplex = re()),
            (x.Transform = ot()),
            (x.PassThrough = Ft()));
      })(se, se.exports)),
    se.exports
  );
}
var Fe, Tr;
function Ot() {
  return (Tr || ((Tr = 1), (Fe = ae().Duplex)), Fe);
}
var Oe, Rr;
function qt() {
  if (Rr) return Oe;
  Rr = 1;
  var m = Ot(),
    x = te,
    e = vt().Buffer;
  function f(s) {
    if (!(this instanceof f)) return new f(s);
    if (((this._bufs = []), (this.length = 0), typeof s == "function")) {
      this._callback = s;
      var t = function (n) {
        this._callback && (this._callback(n), (this._callback = null));
      }.bind(this);
      (this.on("pipe", function (n) {
        n.on("error", t);
      }),
        this.on("unpipe", function (n) {
          n.removeListener("error", t);
        }));
    } else this.append(s);
    m.call(this);
  }
  return (
    x.inherits(f, m),
    (f.prototype._offset = function (t) {
      var r = 0,
        n = 0,
        l;
      if (t === 0) return [0, 0];
      for (; n < this._bufs.length; n++) {
        if (
          ((l = r + this._bufs[n].length), t < l || n == this._bufs.length - 1)
        )
          return [n, t - r];
        r = l;
      }
    }),
    (f.prototype.append = function (t) {
      var r = 0;
      if (e.isBuffer(t)) this._appendBuffer(t);
      else if (Array.isArray(t)) for (; r < t.length; r++) this.append(t[r]);
      else if (t instanceof f)
        for (; r < t._bufs.length; r++) this.append(t._bufs[r]);
      else
        t != null &&
          (typeof t == "number" && (t = t.toString()),
          this._appendBuffer(e.from(t)));
      return this;
    }),
    (f.prototype._appendBuffer = function (t) {
      (this._bufs.push(t), (this.length += t.length));
    }),
    (f.prototype._write = function (t, r, n) {
      (this._appendBuffer(t), typeof n == "function" && n());
    }),
    (f.prototype._read = function (t) {
      if (!this.length) return this.push(null);
      ((t = Math.min(t, this.length)),
        this.push(this.slice(0, t)),
        this.consume(t));
    }),
    (f.prototype.end = function (t) {
      (m.prototype.end.call(this, t),
        this._callback &&
          (this._callback(null, this.slice()), (this._callback = null)));
    }),
    (f.prototype.get = function (t) {
      return this.slice(t, t + 1)[0];
    }),
    (f.prototype.slice = function (t, r) {
      return (
        typeof t == "number" && t < 0 && (t += this.length),
        typeof r == "number" && r < 0 && (r += this.length),
        this.copy(null, 0, t, r)
      );
    }),
    (f.prototype.copy = function (t, r, n, l) {
      if (
        ((typeof n != "number" || n < 0) && (n = 0),
        (typeof l != "number" || l > this.length) && (l = this.length),
        n >= this.length || l <= 0)
      )
        return t || e.alloc(0);
      var p = !!t,
        A = this._offset(n),
        b = l - n,
        B = b,
        w = (p && r) || 0,
        _ = A[1],
        c,
        R;
      if (n === 0 && l == this.length) {
        if (!p)
          return this._bufs.length === 1
            ? this._bufs[0]
            : e.concat(this._bufs, this.length);
        for (R = 0; R < this._bufs.length; R++)
          (this._bufs[R].copy(t, w), (w += this._bufs[R].length));
        return t;
      }
      if (B <= this._bufs[A[0]].length - _)
        return p
          ? this._bufs[A[0]].copy(t, r, _, _ + B)
          : this._bufs[A[0]].slice(_, _ + B);
      for (p || (t = e.allocUnsafe(b)), R = A[0]; R < this._bufs.length; R++) {
        if (((c = this._bufs[R].length - _), B > c))
          (this._bufs[R].copy(t, w, _), (w += c));
        else {
          (this._bufs[R].copy(t, w, _, _ + B), (w += c));
          break;
        }
        ((B -= c), _ && (_ = 0));
      }
      return t.length > w ? t.slice(0, w) : t;
    }),
    (f.prototype.shallowSlice = function (t, r) {
      ((t = t || 0),
        (r = r || this.length),
        t < 0 && (t += this.length),
        r < 0 && (r += this.length));
      var n = this._offset(t),
        l = this._offset(r),
        p = this._bufs.slice(n[0], l[0] + 1);
      return (
        l[1] == 0
          ? p.pop()
          : (p[p.length - 1] = p[p.length - 1].slice(0, l[1])),
        n[1] != 0 && (p[0] = p[0].slice(n[1])),
        new f(p)
      );
    }),
    (f.prototype.toString = function (t, r, n) {
      return this.slice(r, n).toString(t);
    }),
    (f.prototype.consume = function (t) {
      if (((t = Math.trunc(t)), Number.isNaN(t) || t <= 0)) return this;
      for (; this._bufs.length;)
        if (t >= this._bufs[0].length)
          ((t -= this._bufs[0].length),
            (this.length -= this._bufs[0].length),
            this._bufs.shift());
        else {
          ((this._bufs[0] = this._bufs[0].slice(t)), (this.length -= t));
          break;
        }
      return this;
    }),
    (f.prototype.duplicate = function () {
      for (var t = 0, r = new f(); t < this._bufs.length; t++)
        r.append(this._bufs[t]);
      return r;
    }),
    (f.prototype.destroy = function () {
      ((this._bufs.length = 0), (this.length = 0), this.push(null));
    }),
    (function () {
      var s = {
        readDoubleBE: 8,
        readDoubleLE: 8,
        readFloatBE: 4,
        readFloatLE: 4,
        readInt32BE: 4,
        readInt32LE: 4,
        readUInt32BE: 4,
        readUInt32LE: 4,
        readInt16BE: 2,
        readInt16LE: 2,
        readUInt16BE: 2,
        readUInt16LE: 2,
        readInt8: 1,
        readUInt8: 1,
      };
      for (var t in s)
        (function (r) {
          f.prototype[r] = function (n) {
            return this.slice(n, n + s[r])[r](0);
          };
        })(t);
    })(),
    (Oe = f),
    Oe
  );
}
var Q = {},
  qe,
  Cr;
function xt() {
  if (Cr) return qe;
  ((Cr = 1), (qe = e));
  var m = Buffer.from && Buffer.from !== Uint8Array.from ? Buffer.from : x;
  function x(f, s) {
    return new Buffer(f, s);
  }
  function e(f, s) {
    if (Buffer.isBuffer(f)) return f;
    if (typeof f == "string") return m(f, s);
    if (Array.isArray(f)) return m(f);
    throw new Error("Input should be a buffer or a string");
  }
  return qe;
}
var ze, Fr;
function zt() {
  if (Fr) return ze;
  Fr = 1;
  var m = (function () {
    try {
      if (!Buffer.isEncoding("latin1")) return !1;
      var t = Buffer.alloc ? Buffer.alloc(4) : new Buffer(4);
      return (t.fill("ab", "ucs2"), t.toString("hex") === "61006200");
    } catch {
      return !1;
    }
  })();
  function x(t) {
    return t.length === 1 && t.charCodeAt(0) < 256;
  }
  function e(t, r, n, l) {
    if (n < 0 || l > t.length) throw new RangeError("Out of range index");
    return (
      (n = n >>> 0),
      (l = l === void 0 ? t.length : l >>> 0),
      l > n && t.fill(r, n, l),
      t
    );
  }
  function f(t, r, n, l) {
    if (n < 0 || l > t.length) throw new RangeError("Out of range index");
    if (l <= n) return t;
    ((n = n >>> 0), (l = l === void 0 ? t.length : l >>> 0));
    for (var p = n, A = r.length; p <= l - A;) (r.copy(t, p), (p += A));
    return (p !== l && r.copy(t, p, 0, l - p), t);
  }
  function s(t, r, n, l, p) {
    if (m) return t.fill(r, n, l, p);
    if (typeof r == "number") return e(t, r, n, l);
    if (typeof r == "string") {
      if (
        (typeof n == "string"
          ? ((p = n), (n = 0), (l = t.length))
          : typeof l == "string" && ((p = l), (l = t.length)),
        p !== void 0 && typeof p != "string")
      )
        throw new TypeError("encoding must be a string");
      if (
        (p === "latin1" && (p = "binary"),
        typeof p == "string" && !Buffer.isEncoding(p))
      )
        throw new TypeError("Unknown encoding: " + p);
      if (r === "") return e(t, 0, n, l);
      if (x(r)) return e(t, r.charCodeAt(0), n, l);
      r = new Buffer(r, p);
    }
    return Buffer.isBuffer(r) ? f(t, r, n, l) : e(t, 0, n, l);
  }
  return ((ze = s), ze);
}
var Me, Or;
function Mt() {
  if (Or) return Me;
  Or = 1;
  function m(x) {
    if (typeof x != "number")
      throw new TypeError('"size" argument must be a number');
    if (x < 0) throw new RangeError('"size" argument must not be negative');
    return Buffer.allocUnsafe ? Buffer.allocUnsafe(x) : new Buffer(x);
  }
  return ((Me = m), Me);
}
var Pe, qr;
function st() {
  if (qr) return Pe;
  qr = 1;
  var m = zt(),
    x = Mt();
  return (
    (Pe = function (f, s, t) {
      if (typeof f != "number")
        throw new TypeError('"size" argument must be a number');
      if (f < 0) throw new RangeError('"size" argument must not be negative');
      if (Buffer.alloc) return Buffer.alloc(f, s, t);
      var r = x(f);
      return f === 0
        ? r
        : s === void 0
          ? m(r, 0)
          : (typeof t != "string" && (t = void 0), m(r, s, t));
    }),
    Pe
  );
}
var zr;
function ut() {
  if (zr) return Q;
  zr = 1;
  var m = xt(),
    x = st(),
    e = "0000000000000000000",
    f = "7777777777777777777",
    s = 48,
    t = "ustar\x0000",
    r = parseInt("7777", 8),
    n = function (i, u, h) {
      return typeof i != "number"
        ? h
        : ((i = ~~i), i >= u ? u : i >= 0 || ((i += u), i >= 0) ? i : 0);
    },
    l = function (i) {
      switch (i) {
        case 0:
          return "file";
        case 1:
          return "link";
        case 2:
          return "symlink";
        case 3:
          return "character-device";
        case 4:
          return "block-device";
        case 5:
          return "directory";
        case 6:
          return "fifo";
        case 7:
          return "contiguous-file";
        case 72:
          return "pax-header";
        case 55:
          return "pax-global-header";
        case 27:
          return "gnu-long-link-path";
        case 28:
        case 30:
          return "gnu-long-path";
      }
      return null;
    },
    p = function (i) {
      switch (i) {
        case "file":
          return 0;
        case "link":
          return 1;
        case "symlink":
          return 2;
        case "character-device":
          return 3;
        case "block-device":
          return 4;
        case "directory":
          return 5;
        case "fifo":
          return 6;
        case "contiguous-file":
          return 7;
        case "pax-header":
          return 72;
      }
      return 0;
    },
    A = function (i, u, h, d) {
      for (; h < d; h++) if (i[h] === u) return h;
      return d;
    },
    b = function (i) {
      for (var u = 256, h = 0; h < 148; h++) u += i[h];
      for (var d = 156; d < 512; d++) u += i[d];
      return u;
    },
    B = function (i, u) {
      return (
        (i = i.toString(8)),
        i.length > u ? f.slice(0, u) + " " : e.slice(0, u - i.length) + i + " "
      );
    };
  function w(i) {
    var u;
    if (i[0] === 128) u = !0;
    else if (i[0] === 255) u = !1;
    else return null;
    for (var h = [], d = i.length - 1; d > 0; d--) {
      var y = i[d];
      u ? h.push(y) : h.push(255 - y);
    }
    var T = 0,
      k = h.length;
    for (d = 0; d < k; d++) T += h[d] * Math.pow(256, d);
    return u ? T : -1 * T;
  }
  var _ = function (i, u, h) {
      if (((i = i.slice(u, u + h)), (u = 0), i[u] & 128)) return w(i);
      for (; u < i.length && i[u] === 32;) u++;
      for (
        var d = n(A(i, 32, u, i.length), i.length, i.length);
        u < d && i[u] === 0;
      )
        u++;
      return d === u ? 0 : parseInt(i.slice(u, d).toString(), 8);
    },
    c = function (i, u, h, d) {
      return i.slice(u, A(i, 0, u, u + h)).toString(d);
    },
    R = function (i) {
      var u = Buffer.byteLength(i),
        h = Math.floor(Math.log(u) / Math.log(10)) + 1;
      return (u + h >= Math.pow(10, h) && h++, u + h + i);
    };
  return (
    (Q.decodeLongPath = function (i, u) {
      return c(i, 0, i.length, u);
    }),
    (Q.encodePax = function (i) {
      var u = "";
      (i.name &&
        (u += R(
          " path=" +
            i.name +
            `
`,
        )),
        i.linkname &&
          (u += R(
            " linkpath=" +
              i.linkname +
              `
`,
          )));
      var h = i.pax;
      if (h)
        for (var d in h)
          u += R(
            " " +
              d +
              "=" +
              h[d] +
              `
`,
          );
      return m(u);
    }),
    (Q.decodePax = function (i) {
      for (var u = {}; i.length;) {
        for (var h = 0; h < i.length && i[h] !== 32;) h++;
        var d = parseInt(i.slice(0, h).toString(), 10);
        if (!d) return u;
        var y = i.slice(h + 1, d - 1).toString(),
          T = y.indexOf("=");
        if (T === -1) return u;
        ((u[y.slice(0, T)] = y.slice(T + 1)), (i = i.slice(d)));
      }
      return u;
    }),
    (Q.encode = function (i) {
      var u = x(512),
        h = i.name,
        d = "";
      if (
        (i.typeflag === 5 && h[h.length - 1] !== "/" && (h += "/"),
        Buffer.byteLength(h) !== h.length)
      )
        return null;
      for (; Buffer.byteLength(h) > 100;) {
        var y = h.indexOf("/");
        if (y === -1) return null;
        ((d += d ? "/" + h.slice(0, y) : h.slice(0, y)), (h = h.slice(y + 1)));
      }
      return Buffer.byteLength(h) > 100 ||
        Buffer.byteLength(d) > 155 ||
        (i.linkname && Buffer.byteLength(i.linkname) > 100)
        ? null
        : (u.write(h),
          u.write(B(i.mode & r, 6), 100),
          u.write(B(i.uid, 6), 108),
          u.write(B(i.gid, 6), 116),
          u.write(B(i.size, 11), 124),
          u.write(B((i.mtime.getTime() / 1e3) | 0, 11), 136),
          (u[156] = s + p(i.type)),
          i.linkname && u.write(i.linkname, 157),
          u.write(t, 257),
          i.uname && u.write(i.uname, 265),
          i.gname && u.write(i.gname, 297),
          u.write(B(i.devmajor || 0, 6), 329),
          u.write(B(i.devminor || 0, 6), 337),
          d && u.write(d, 345),
          u.write(B(b(u), 6), 148),
          u);
    }),
    (Q.decode = function (i, u) {
      var h = i[156] === 0 ? 0 : i[156] - s,
        d = c(i, 0, 100, u),
        y = _(i, 100, 8),
        T = _(i, 108, 8),
        k = _(i, 116, 8),
        F = _(i, 124, 12),
        O = _(i, 136, 12),
        q = l(h),
        L = i[157] === 0 ? null : c(i, 157, 100, u),
        N = c(i, 265, 32),
        Z = c(i, 297, 32),
        $ = _(i, 329, 8),
        Y = _(i, 337, 8);
      (i[345] && (d = c(i, 345, 155, u) + "/" + d),
        h === 0 && d && d[d.length - 1] === "/" && (h = 5));
      var G = b(i);
      if (G === 256) return null;
      if (G !== _(i, 148, 8))
        throw new Error(
          "Invalid tar header. Maybe the tar is corrupted or it needs to be gunzipped?",
        );
      return {
        name: d,
        mode: y,
        uid: T,
        gid: k,
        size: F,
        mtime: new Date(1e3 * O),
        type: q,
        linkname: L,
        uname: N,
        gname: Z,
        devmajor: $,
        devminor: Y,
      };
    }),
    Q
  );
}
var je, Mr;
function Pt() {
  if (Mr) return je;
  Mr = 1;
  var m = te,
    x = qt(),
    e = yt(),
    f = ut(),
    s = ae().Writable,
    t = ae().PassThrough,
    r = function () {},
    n = function (B) {
      return ((B &= 511), B && 512 - B);
    },
    l = function (B, w) {
      var _ = new A(B, w);
      return (_.end(), _);
    },
    p = function (B, w) {
      return (
        w.path && (B.name = w.path),
        w.linkpath && (B.linkname = w.linkpath),
        w.size && (B.size = parseInt(w.size, 10)),
        (B.pax = w),
        B
      );
    },
    A = function (B, w) {
      ((this._parent = B), (this.offset = w), t.call(this));
    };
  (m.inherits(A, t),
    (A.prototype.destroy = function (B) {
      this._parent.destroy(B);
    }));
  var b = function (B) {
    if (!(this instanceof b)) return new b(B);
    (s.call(this, B),
      (B = B || {}),
      (this._offset = 0),
      (this._buffer = x()),
      (this._missing = 0),
      (this._partial = !1),
      (this._onparse = r),
      (this._header = null),
      (this._stream = null),
      (this._overflow = null),
      (this._cb = null),
      (this._locked = !1),
      (this._destroyed = !1),
      (this._pax = null),
      (this._paxGlobal = null),
      (this._gnuLongPath = null),
      (this._gnuLongLinkPath = null));
    var w = this,
      _ = w._buffer,
      c = function () {
        w._continue();
      },
      R = function (F) {
        if (((w._locked = !1), F)) return w.destroy(F);
        w._stream || c();
      },
      i = function () {
        w._stream = null;
        var F = n(w._header.size);
        (F ? w._parse(F, u) : w._parse(512, k), w._locked || c());
      },
      u = function () {
        (w._buffer.consume(n(w._header.size)), w._parse(512, k), c());
      },
      h = function () {
        var F = w._header.size;
        ((w._paxGlobal = f.decodePax(_.slice(0, F))), _.consume(F), i());
      },
      d = function () {
        var F = w._header.size;
        ((w._pax = f.decodePax(_.slice(0, F))),
          w._paxGlobal && (w._pax = e(w._paxGlobal, w._pax)),
          _.consume(F),
          i());
      },
      y = function () {
        var F = w._header.size;
        ((this._gnuLongPath = f.decodeLongPath(
          _.slice(0, F),
          B.filenameEncoding,
        )),
          _.consume(F),
          i());
      },
      T = function () {
        var F = w._header.size;
        ((this._gnuLongLinkPath = f.decodeLongPath(
          _.slice(0, F),
          B.filenameEncoding,
        )),
          _.consume(F),
          i());
      },
      k = function () {
        var F = w._offset,
          O;
        try {
          O = w._header = f.decode(_.slice(0, 512), B.filenameEncoding);
        } catch (q) {
          w.emit("error", q);
        }
        if ((_.consume(512), !O)) {
          (w._parse(512, k), c());
          return;
        }
        if (O.type === "gnu-long-path") {
          (w._parse(O.size, y), c());
          return;
        }
        if (O.type === "gnu-long-link-path") {
          (w._parse(O.size, T), c());
          return;
        }
        if (O.type === "pax-global-header") {
          (w._parse(O.size, h), c());
          return;
        }
        if (O.type === "pax-header") {
          (w._parse(O.size, d), c());
          return;
        }
        if (
          (w._gnuLongPath &&
            ((O.name = w._gnuLongPath), (w._gnuLongPath = null)),
          w._gnuLongLinkPath &&
            ((O.linkname = w._gnuLongLinkPath), (w._gnuLongLinkPath = null)),
          w._pax && ((w._header = O = p(O, w._pax)), (w._pax = null)),
          (w._locked = !0),
          !O.size || O.type === "directory")
        ) {
          (w._parse(512, k), w.emit("entry", O, l(w, F), R));
          return;
        }
        ((w._stream = new A(w, F)),
          w.emit("entry", O, w._stream, R),
          w._parse(O.size, i),
          c());
      };
    ((this._onheader = k), this._parse(512, k));
  };
  return (
    m.inherits(b, s),
    (b.prototype.destroy = function (B) {
      this._destroyed ||
        ((this._destroyed = !0),
        B && this.emit("error", B),
        this.emit("close"),
        this._stream && this._stream.emit("close"));
    }),
    (b.prototype._parse = function (B, w) {
      this._destroyed ||
        ((this._offset += B),
        (this._missing = B),
        w === this._onheader && (this._partial = !1),
        (this._onparse = w));
    }),
    (b.prototype._continue = function () {
      if (!this._destroyed) {
        var B = this._cb;
        ((this._cb = r),
          this._overflow ? this._write(this._overflow, void 0, B) : B());
      }
    }),
    (b.prototype._write = function (B, w, _) {
      if (!this._destroyed) {
        var c = this._stream,
          R = this._buffer,
          i = this._missing;
        if ((B.length && (this._partial = !0), B.length < i))
          return (
            (this._missing -= B.length),
            (this._overflow = null),
            c ? c.write(B, _) : (R.append(B), _())
          );
        ((this._cb = _), (this._missing = 0));
        var u = null;
        (B.length > i && ((u = B.slice(i)), (B = B.slice(0, i))),
          c ? c.end(B) : R.append(B),
          (this._overflow = u),
          this._onparse());
      }
    }),
    (b.prototype._final = function (B) {
      if (this._partial)
        return this.destroy(new Error("Unexpected end of data"));
      B();
    }),
    (je = b),
    je
  );
}
var Ue, Pr;
function jt() {
  if (Pr) return Ue;
  Pr = 1;
  var m = pt(),
    x = wt(),
    e = te,
    f = st(),
    s = xt(),
    t = ae().Readable,
    r = ae().Writable,
    n = _t.StringDecoder,
    l = ut(),
    p = parseInt("755", 8),
    A = parseInt("644", 8),
    b = f(1024),
    B = function () {},
    w = function (h, d) {
      ((d &= 511), d && h.push(b.slice(0, 512 - d)));
    };
  function _(h) {
    switch (h & m.S_IFMT) {
      case m.S_IFBLK:
        return "block-device";
      case m.S_IFCHR:
        return "character-device";
      case m.S_IFDIR:
        return "directory";
      case m.S_IFIFO:
        return "fifo";
      case m.S_IFLNK:
        return "symlink";
    }
    return "file";
  }
  var c = function (h) {
    (r.call(this), (this.written = 0), (this._to = h), (this._destroyed = !1));
  };
  (e.inherits(c, r),
    (c.prototype._write = function (h, d, y) {
      if (((this.written += h.length), this._to.push(h))) return y();
      this._to._drain = y;
    }),
    (c.prototype.destroy = function () {
      this._destroyed || ((this._destroyed = !0), this.emit("close"));
    }));
  var R = function () {
    (r.call(this),
      (this.linkname = ""),
      (this._decoder = new n("utf-8")),
      (this._destroyed = !1));
  };
  (e.inherits(R, r),
    (R.prototype._write = function (h, d, y) {
      ((this.linkname += this._decoder.write(h)), y());
    }),
    (R.prototype.destroy = function () {
      this._destroyed || ((this._destroyed = !0), this.emit("close"));
    }));
  var i = function () {
    (r.call(this), (this._destroyed = !1));
  };
  (e.inherits(i, r),
    (i.prototype._write = function (h, d, y) {
      y(new Error("No body allowed for this entry"));
    }),
    (i.prototype.destroy = function () {
      this._destroyed || ((this._destroyed = !0), this.emit("close"));
    }));
  var u = function (h) {
    if (!(this instanceof u)) return new u(h);
    (t.call(this, h),
      (this._drain = B),
      (this._finalized = !1),
      (this._finalizing = !1),
      (this._destroyed = !1),
      (this._stream = null));
  };
  return (
    e.inherits(u, t),
    (u.prototype.entry = function (h, d, y) {
      if (this._stream) throw new Error("already piping an entry");
      if (!(this._finalized || this._destroyed)) {
        (typeof d == "function" && ((y = d), (d = null)), y || (y = B));
        var T = this;
        if (
          ((!h.size || h.type === "symlink") && (h.size = 0),
          h.type || (h.type = _(h.mode)),
          h.mode || (h.mode = h.type === "directory" ? p : A),
          h.uid || (h.uid = 0),
          h.gid || (h.gid = 0),
          h.mtime || (h.mtime = new Date()),
          typeof d == "string" && (d = s(d)),
          Buffer.isBuffer(d))
        )
          return (
            (h.size = d.length),
            this._encode(h),
            this.push(d),
            w(T, h.size),
            process.nextTick(y),
            new i()
          );
        if (h.type === "symlink" && !h.linkname) {
          var k = new R();
          return (
            x(k, function (O) {
              if (O) return (T.destroy(), y(O));
              ((h.linkname = k.linkname), T._encode(h), y());
            }),
            k
          );
        }
        if (
          (this._encode(h), h.type !== "file" && h.type !== "contiguous-file")
        )
          return (process.nextTick(y), new i());
        var F = new c(this);
        return (
          (this._stream = F),
          x(F, function (O) {
            if (((T._stream = null), O)) return (T.destroy(), y(O));
            if (F.written !== h.size)
              return (T.destroy(), y(new Error("size mismatch")));
            (w(T, h.size), T._finalizing && T.finalize(), y());
          }),
          F
        );
      }
    }),
    (u.prototype.finalize = function () {
      if (this._stream) {
        this._finalizing = !0;
        return;
      }
      this._finalized ||
        ((this._finalized = !0), this.push(b), this.push(null));
    }),
    (u.prototype.destroy = function (h) {
      this._destroyed ||
        ((this._destroyed = !0),
        h && this.emit("error", h),
        this.emit("close"),
        this._stream && this._stream.destroy && this._stream.destroy());
    }),
    (u.prototype._encode = function (h) {
      if (!h.pax) {
        var d = l.encode(h);
        if (d) {
          this.push(d);
          return;
        }
      }
      this._encodePax(h);
    }),
    (u.prototype._encodePax = function (h) {
      var d = l.encodePax({ name: h.name, linkname: h.linkname, pax: h.pax }),
        y = {
          name: "PaxHeader",
          mode: h.mode,
          uid: h.uid,
          gid: h.gid,
          size: d.length,
          mtime: h.mtime,
          type: "pax-header",
          linkname: h.linkname && "PaxHeader",
          uname: h.uname,
          gname: h.gname,
          devmajor: h.devmajor,
          devminor: h.devminor,
        };
      (this.push(l.encode(y)),
        this.push(d),
        w(this, d.length),
        (y.size = h.size),
        (y.type = h.type),
        this.push(l.encode(y)));
    }),
    (u.prototype._read = function (h) {
      var d = this._drain;
      ((this._drain = B), d());
    }),
    (Ue = u),
    Ue
  );
}
var jr;
function Ut() {
  return (jr || ((jr = 1), (xe.extract = Pt()), (xe.pack = jt())), xe);
}
var Ie, Ur;
function xr() {
  if (Ur) return Ie;
  Ur = 1;
  const m = Dt(),
    x = fr(),
    e = Ut();
  return (
    (Ie = () => (f) => {
      if (!Buffer.isBuffer(f) && !x(f))
        return Promise.reject(
          new TypeError(`Expected a Buffer or Stream, got ${typeof f}`),
        );
      if (Buffer.isBuffer(f) && (!m(f) || m(f).ext !== "tar"))
        return Promise.resolve([]);
      const s = e.extract(),
        t = [];
      s.on("entry", (n, l, p) => {
        const A = [];
        (l.on("data", (b) => A.push(b)),
          l.on("end", () => {
            const b = {
              data: Buffer.concat(A),
              mode: n.mode,
              mtime: n.mtime,
              path: n.name,
              type: n.type,
            };
            ((n.type === "symlink" || n.type === "link") &&
              (b.linkname = n.linkname),
              t.push(b),
              p());
          }));
      });
      const r = new Promise((n, l) => {
        (Buffer.isBuffer(f) || f.on("error", l),
          s.on("finish", () => n(t)),
          s.on("error", l));
      });
      return (
        (s.then = r.then.bind(r)),
        (s.catch = r.catch.bind(r)),
        Buffer.isBuffer(f) ? s.end(f) : f.pipe(s),
        s
      );
    }),
    Ie
  );
}
var Ne, Ir;
function It() {
  if (Ir) return Ne;
  Ir = 1;
  const m = (s) => Array.from(s).map((t) => t.charCodeAt(0)),
    x = m("META-INF/mozilla.rsa"),
    e = m("[Content_Types].xml"),
    f = m("_rels/.rels");
  return (
    (Ne = (s) => {
      const t = new Uint8Array(s);
      if (!(t && t.length > 1)) return null;
      const r = (n, l) => {
        l = Object.assign({ offset: 0 }, l);
        for (let p = 0; p < n.length; p++)
          if (l.mask) {
            if (n[p] !== (l.mask[p] & t[p + l.offset])) return !1;
          } else if (n[p] !== t[p + l.offset]) return !1;
        return !0;
      };
      if (r([255, 216, 255])) return { ext: "jpg", mime: "image/jpeg" };
      if (r([137, 80, 78, 71, 13, 10, 26, 10]))
        return { ext: "png", mime: "image/png" };
      if (r([71, 73, 70])) return { ext: "gif", mime: "image/gif" };
      if (r([87, 69, 66, 80], { offset: 8 }))
        return { ext: "webp", mime: "image/webp" };
      if (r([70, 76, 73, 70])) return { ext: "flif", mime: "image/flif" };
      if (
        (r([73, 73, 42, 0]) || r([77, 77, 0, 42])) &&
        r([67, 82], { offset: 8 })
      )
        return { ext: "cr2", mime: "image/x-canon-cr2" };
      if (r([73, 73, 42, 0]) || r([77, 77, 0, 42]))
        return { ext: "tif", mime: "image/tiff" };
      if (r([66, 77])) return { ext: "bmp", mime: "image/bmp" };
      if (r([73, 73, 188])) return { ext: "jxr", mime: "image/vnd.ms-photo" };
      if (r([56, 66, 80, 83]))
        return { ext: "psd", mime: "image/vnd.adobe.photoshop" };
      if (r([80, 75, 3, 4])) {
        if (
          r(
            [
              109, 105, 109, 101, 116, 121, 112, 101, 97, 112, 112, 108, 105,
              99, 97, 116, 105, 111, 110, 47, 101, 112, 117, 98, 43, 122, 105,
              112,
            ],
            { offset: 30 },
          )
        )
          return { ext: "epub", mime: "application/epub+zip" };
        if (r(x, { offset: 30 }))
          return { ext: "xpi", mime: "application/x-xpinstall" };
        if (r(e, { offset: 30 }) || r(f, { offset: 30 })) {
          const n = t.subarray(4, 2004),
            l = (A) =>
              A.findIndex(
                (b, B, w) =>
                  w[B] === 80 &&
                  w[B + 1] === 75 &&
                  w[B + 2] === 3 &&
                  w[B + 3] === 4,
              ),
            p = l(n);
          if (p !== -1) {
            const A = t.subarray(p + 8, p + 8 + 1e3),
              b = l(A);
            if (b !== -1) {
              const B = 8 + p + b + 30;
              if (r(m("word/"), { offset: B }))
                return {
                  ext: "docx",
                  mime: "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
                };
              if (r(m("ppt/"), { offset: B }))
                return {
                  ext: "pptx",
                  mime: "application/vnd.openxmlformats-officedocument.presentationml.presentation",
                };
              if (r(m("xl/"), { offset: B }))
                return {
                  ext: "xlsx",
                  mime: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
                };
            }
          }
        }
      }
      if (
        r([80, 75]) &&
        (t[2] === 3 || t[2] === 5 || t[2] === 7) &&
        (t[3] === 4 || t[3] === 6 || t[3] === 8)
      )
        return { ext: "zip", mime: "application/zip" };
      if (r([117, 115, 116, 97, 114], { offset: 257 }))
        return { ext: "tar", mime: "application/x-tar" };
      if (r([82, 97, 114, 33, 26, 7]) && (t[6] === 0 || t[6] === 1))
        return { ext: "rar", mime: "application/x-rar-compressed" };
      if (r([31, 139, 8])) return { ext: "gz", mime: "application/gzip" };
      if (r([66, 90, 104])) return { ext: "bz2", mime: "application/x-bzip2" };
      if (r([55, 122, 188, 175, 39, 28]))
        return { ext: "7z", mime: "application/x-7z-compressed" };
      if (r([120, 1]))
        return { ext: "dmg", mime: "application/x-apple-diskimage" };
      if (
        r([51, 103, 112, 53]) ||
        (r([0, 0, 0]) &&
          r([102, 116, 121, 112], { offset: 4 }) &&
          (r([109, 112, 52, 49], { offset: 8 }) ||
            r([109, 112, 52, 50], { offset: 8 }) ||
            r([105, 115, 111, 109], { offset: 8 }) ||
            r([105, 115, 111, 50], { offset: 8 }) ||
            r([109, 109, 112, 52], { offset: 8 }) ||
            r([77, 52, 86], { offset: 8 }) ||
            r([100, 97, 115, 104], { offset: 8 })))
      )
        return { ext: "mp4", mime: "video/mp4" };
      if (r([77, 84, 104, 100])) return { ext: "mid", mime: "audio/midi" };
      if (r([26, 69, 223, 163])) {
        const n = t.subarray(4, 4100),
          l = n.findIndex((p, A, b) => b[A] === 66 && b[A + 1] === 130);
        if (l !== -1) {
          const p = l + 3,
            A = (b) =>
              Array.from(b).every((B, w) => n[p + w] === B.charCodeAt(0));
          if (A("matroska")) return { ext: "mkv", mime: "video/x-matroska" };
          if (A("webm")) return { ext: "webm", mime: "video/webm" };
        }
      }
      if (
        r([0, 0, 0, 20, 102, 116, 121, 112, 113, 116, 32, 32]) ||
        r([102, 114, 101, 101], { offset: 4 }) ||
        r([102, 116, 121, 112, 113, 116, 32, 32], { offset: 4 }) ||
        r([109, 100, 97, 116], { offset: 4 }) ||
        r([119, 105, 100, 101], { offset: 4 })
      )
        return { ext: "mov", mime: "video/quicktime" };
      if (r([82, 73, 70, 70]) && r([65, 86, 73], { offset: 8 }))
        return { ext: "avi", mime: "video/x-msvideo" };
      if (r([48, 38, 178, 117, 142, 102, 207, 17, 166, 217]))
        return { ext: "wmv", mime: "video/x-ms-wmv" };
      if (r([0, 0, 1, 186])) return { ext: "mpg", mime: "video/mpeg" };
      for (let n = 0; n < 2 && n < t.length - 16; n++)
        if (
          r([73, 68, 51], { offset: n }) ||
          r([255, 226], { offset: n, mask: [255, 226] })
        )
          return { ext: "mp3", mime: "audio/mpeg" };
      return r([102, 116, 121, 112, 77, 52, 65], { offset: 4 }) ||
        r([77, 52, 65, 32])
        ? { ext: "m4a", mime: "audio/m4a" }
        : r([79, 112, 117, 115, 72, 101, 97, 100], { offset: 28 })
          ? { ext: "opus", mime: "audio/opus" }
          : r([79, 103, 103, 83])
            ? { ext: "ogg", mime: "audio/ogg" }
            : r([102, 76, 97, 67])
              ? { ext: "flac", mime: "audio/x-flac" }
              : r([82, 73, 70, 70]) && r([87, 65, 86, 69], { offset: 8 })
                ? { ext: "wav", mime: "audio/x-wav" }
                : r([35, 33, 65, 77, 82, 10])
                  ? { ext: "amr", mime: "audio/amr" }
                  : r([37, 80, 68, 70])
                    ? { ext: "pdf", mime: "application/pdf" }
                    : r([77, 90])
                      ? { ext: "exe", mime: "application/x-msdownload" }
                      : (t[0] === 67 || t[0] === 70) &&
                          r([87, 83], { offset: 1 })
                        ? { ext: "swf", mime: "application/x-shockwave-flash" }
                        : r([123, 92, 114, 116, 102])
                          ? { ext: "rtf", mime: "application/rtf" }
                          : r([0, 97, 115, 109])
                            ? { ext: "wasm", mime: "application/wasm" }
                            : r([119, 79, 70, 70]) &&
                                (r([0, 1, 0, 0], { offset: 4 }) ||
                                  r([79, 84, 84, 79], { offset: 4 }))
                              ? { ext: "woff", mime: "font/woff" }
                              : r([119, 79, 70, 50]) &&
                                  (r([0, 1, 0, 0], { offset: 4 }) ||
                                    r([79, 84, 84, 79], { offset: 4 }))
                                ? { ext: "woff2", mime: "font/woff2" }
                                : r([76, 80], { offset: 34 }) &&
                                    (r([0, 0, 1], { offset: 8 }) ||
                                      r([1, 0, 2], { offset: 8 }) ||
                                      r([2, 0, 2], { offset: 8 }))
                                  ? {
                                      ext: "eot",
                                      mime: "application/octet-stream",
                                    }
                                  : r([0, 1, 0, 0, 0])
                                    ? { ext: "ttf", mime: "font/ttf" }
                                    : r([79, 84, 84, 79, 0])
                                      ? { ext: "otf", mime: "font/otf" }
                                      : r([0, 0, 1, 0])
                                        ? { ext: "ico", mime: "image/x-icon" }
                                        : r([70, 76, 86, 1])
                                          ? { ext: "flv", mime: "video/x-flv" }
                                          : r([37, 33])
                                            ? {
                                                ext: "ps",
                                                mime: "application/postscript",
                                              }
                                            : r([253, 55, 122, 88, 90, 0])
                                              ? {
                                                  ext: "xz",
                                                  mime: "application/x-xz",
                                                }
                                              : r([83, 81, 76, 105])
                                                ? {
                                                    ext: "sqlite",
                                                    mime: "application/x-sqlite3",
                                                  }
                                                : r([78, 69, 83, 26])
                                                  ? {
                                                      ext: "nes",
                                                      mime: "application/x-nintendo-nes-rom",
                                                    }
                                                  : r([67, 114, 50, 52])
                                                    ? {
                                                        ext: "crx",
                                                        mime: "application/x-google-chrome-extension",
                                                      }
                                                    : r([77, 83, 67, 70]) ||
                                                        r([73, 83, 99, 40])
                                                      ? {
                                                          ext: "cab",
                                                          mime: "application/vnd.ms-cab-compressed",
                                                        }
                                                      : r([
                                                            33, 60, 97, 114, 99,
                                                            104, 62, 10, 100,
                                                            101, 98, 105, 97,
                                                            110, 45, 98, 105,
                                                            110, 97, 114, 121,
                                                          ])
                                                        ? {
                                                            ext: "deb",
                                                            mime: "application/x-deb",
                                                          }
                                                        : r([
                                                              33, 60, 97, 114,
                                                              99, 104, 62,
                                                            ])
                                                          ? {
                                                              ext: "ar",
                                                              mime: "application/x-unix-archive",
                                                            }
                                                          : r([
                                                                237, 171, 238,
                                                                219,
                                                              ])
                                                            ? {
                                                                ext: "rpm",
                                                                mime: "application/x-rpm",
                                                              }
                                                            : r([31, 160]) ||
                                                                r([31, 157])
                                                              ? {
                                                                  ext: "Z",
                                                                  mime: "application/x-compress",
                                                                }
                                                              : r([
                                                                    76, 90, 73,
                                                                    80,
                                                                  ])
                                                                ? {
                                                                    ext: "lz",
                                                                    mime: "application/x-lzip",
                                                                  }
                                                                : r([
                                                                      208, 207,
                                                                      17, 224,
                                                                      161, 177,
                                                                      26, 225,
                                                                    ])
                                                                  ? {
                                                                      ext: "msi",
                                                                      mime: "application/x-msi",
                                                                    }
                                                                  : r([
                                                                        6, 14,
                                                                        43, 52,
                                                                        2, 5, 1,
                                                                        1, 13,
                                                                        1, 2, 1,
                                                                        1, 2,
                                                                      ])
                                                                    ? {
                                                                        ext: "mxf",
                                                                        mime: "application/mxf",
                                                                      }
                                                                    : r([71], {
                                                                          offset: 4,
                                                                        }) &&
                                                                        (r(
                                                                          [71],
                                                                          {
                                                                            offset: 192,
                                                                          },
                                                                        ) ||
                                                                          r(
                                                                            [
                                                                              71,
                                                                            ],
                                                                            {
                                                                              offset: 196,
                                                                            },
                                                                          ))
                                                                      ? {
                                                                          ext: "mts",
                                                                          mime: "video/mp2t",
                                                                        }
                                                                      : r([
                                                                            66,
                                                                            76,
                                                                            69,
                                                                            78,
                                                                            68,
                                                                            69,
                                                                            82,
                                                                          ])
                                                                        ? {
                                                                            ext: "blend",
                                                                            mime: "application/x-blender",
                                                                          }
                                                                        : r([
                                                                              66,
                                                                              80,
                                                                              71,
                                                                              251,
                                                                            ])
                                                                          ? {
                                                                              ext: "bpg",
                                                                              mime: "image/bpg",
                                                                            }
                                                                          : null;
    }),
    Ne
  );
}
var Le, Nr;
function Nt() {
  if (Nr) return Le;
  Nr = 1;
  var m = [0, 1, 3, 7, 15, 31, 63, 127, 255],
    x = function (e) {
      ((this.stream = e),
        (this.bitOffset = 0),
        (this.curByte = 0),
        (this.hasByte = !1));
    };
  return (
    (x.prototype._ensureByte = function () {
      this.hasByte ||
        ((this.curByte = this.stream.readByte()), (this.hasByte = !0));
    }),
    (x.prototype.read = function (e) {
      for (var f = 0; e > 0;) {
        this._ensureByte();
        var s = 8 - this.bitOffset;
        if (e >= s)
          ((f <<= s),
            (f |= m[s] & this.curByte),
            (this.hasByte = !1),
            (this.bitOffset = 0),
            (e -= s));
        else {
          f <<= e;
          var t = s - e;
          ((f |= (this.curByte & (m[e] << t)) >> t),
            (this.bitOffset += e),
            (e = 0));
        }
      }
      return f;
    }),
    (x.prototype.seek = function (e) {
      var f = e % 8,
        s = (e - f) / 8;
      ((this.bitOffset = f), this.stream.seek(s), (this.hasByte = !1));
    }),
    (x.prototype.pi = function () {
      var e = new Buffer(6),
        f;
      for (f = 0; f < e.length; f++) e[f] = this.read(8);
      return e.toString("hex");
    }),
    (Le = x),
    Le
  );
}
var We, Lr;
function Lt() {
  if (Lr) return We;
  Lr = 1;
  var m = function () {};
  return (
    (m.prototype.readByte = function () {
      throw new Error("abstract method readByte() not implemented");
    }),
    (m.prototype.read = function (x, e, f) {
      for (var s = 0; s < f;) {
        var t = this.readByte();
        if (t < 0) return s === 0 ? -1 : s;
        ((x[e++] = t), s++);
      }
      return s;
    }),
    (m.prototype.seek = function (x) {
      throw new Error("abstract method seek() not implemented");
    }),
    (m.prototype.writeByte = function (x) {
      throw new Error("abstract method readByte() not implemented");
    }),
    (m.prototype.write = function (x, e, f) {
      var s;
      for (s = 0; s < f; s++) this.writeByte(x[e++]);
      return f;
    }),
    (m.prototype.flush = function () {}),
    (We = m),
    We
  );
}
var $e, Wr;
function Wt() {
  return (
    Wr ||
      ((Wr = 1),
      ($e = (function () {
        var m = new Uint32Array([
            0, 79764919, 159529838, 222504665, 319059676, 398814059, 445009330,
            507990021, 638119352, 583659535, 797628118, 726387553, 890018660,
            835552979, 1015980042, 944750013, 1276238704, 1221641927,
            1167319070, 1095957929, 1595256236, 1540665371, 1452775106,
            1381403509, 1780037320, 1859660671, 1671105958, 1733955601,
            2031960084, 2111593891, 1889500026, 1952343757, 2552477408,
            2632100695, 2443283854, 2506133561, 2334638140, 2414271883,
            2191915858, 2254759653, 3190512472, 3135915759, 3081330742,
            3009969537, 2905550212, 2850959411, 2762807018, 2691435357,
            3560074640, 3505614887, 3719321342, 3648080713, 3342211916,
            3287746299, 3467911202, 3396681109, 4063920168, 4143685023,
            4223187782, 4286162673, 3779000052, 3858754371, 3904687514,
            3967668269, 881225847, 809987520, 1023691545, 969234094, 662832811,
            591600412, 771767749, 717299826, 311336399, 374308984, 453813921,
            533576470, 25881363, 88864420, 134795389, 214552010, 2023205639,
            2086057648, 1897238633, 1976864222, 1804852699, 1867694188,
            1645340341, 1724971778, 1587496639, 1516133128, 1461550545,
            1406951526, 1302016099, 1230646740, 1142491917, 1087903418,
            2896545431, 2825181984, 2770861561, 2716262478, 3215044683,
            3143675388, 3055782693, 3001194130, 2326604591, 2389456536,
            2200899649, 2280525302, 2578013683, 2640855108, 2418763421,
            2498394922, 3769900519, 3832873040, 3912640137, 3992402750,
            4088425275, 4151408268, 4197601365, 4277358050, 3334271071,
            3263032808, 3476998961, 3422541446, 3585640067, 3514407732,
            3694837229, 3640369242, 1762451694, 1842216281, 1619975040,
            1682949687, 2047383090, 2127137669, 1938468188, 2001449195,
            1325665622, 1271206113, 1183200824, 1111960463, 1543535498,
            1489069629, 1434599652, 1363369299, 622672798, 568075817, 748617968,
            677256519, 907627842, 853037301, 1067152940, 995781531, 51762726,
            131386257, 177728840, 240578815, 269590778, 349224269, 429104020,
            491947555, 4046411278, 4126034873, 4172115296, 4234965207,
            3794477266, 3874110821, 3953728444, 4016571915, 3609705398,
            3555108353, 3735388376, 3664026991, 3290680682, 3236090077,
            3449943556, 3378572211, 3174993278, 3120533705, 3032266256,
            2961025959, 2923101090, 2868635157, 2813903052, 2742672763,
            2604032198, 2683796849, 2461293480, 2524268063, 2284983834,
            2364738477, 2175806836, 2238787779, 1569362073, 1498123566,
            1409854455, 1355396672, 1317987909, 1246755826, 1192025387,
            1137557660, 2072149281, 2135122070, 1912620623, 1992383480,
            1753615357, 1816598090, 1627664531, 1707420964, 295390185,
            358241886, 404320391, 483945776, 43990325, 106832002, 186451547,
            266083308, 932423249, 861060070, 1041341759, 986742920, 613929101,
            542559546, 756411363, 701822548, 3316196985, 3244833742, 3425377559,
            3370778784, 3601682597, 3530312978, 3744426955, 3689838204,
            3819031489, 3881883254, 3928223919, 4007849240, 4037393693,
            4100235434, 4180117107, 4259748804, 2310601993, 2373574846,
            2151335527, 2231098320, 2596047829, 2659030626, 2470359227,
            2550115596, 2947551409, 2876312838, 2788305887, 2733848168,
            3165939309, 3094707162, 3040238851, 2985771188,
          ]),
          x = function () {
            var e = 4294967295;
            ((this.getCRC = function () {
              return ~e >>> 0;
            }),
              (this.updateCRC = function (f) {
                e = (e << 8) ^ m[((e >>> 24) ^ f) & 255];
              }),
              (this.updateCRCRun = function (f, s) {
                for (; s-- > 0;) e = (e << 8) ^ m[((e >>> 24) ^ f) & 255];
              }));
          };
        return x;
      })())),
    $e
  );
}
const $t = "1.0.6",
  Ht = "MIT",
  Zt = { version: $t, license: Ht };
var He, $r;
function Gt() {
  if ($r) return He;
  $r = 1;
  var m = Nt(),
    x = Lt(),
    e = Wt(),
    f = Zt,
    s = 20,
    t = 258,
    r = 0,
    n = 1,
    l = 2,
    p = 6,
    A = 50,
    b = "314159265359",
    B = "177245385090",
    w = function (d, y) {
      var T = d[y],
        k;
      for (k = y; k > 0; k--) d[k] = d[k - 1];
      return ((d[0] = T), T);
    },
    _ = {
      OK: 0,
      LAST_BLOCK: -1,
      NOT_BZIP_DATA: -2,
      UNEXPECTED_INPUT_EOF: -3,
      UNEXPECTED_OUTPUT_EOF: -4,
      DATA_ERROR: -5,
      OUT_OF_MEMORY: -6,
      OBSOLETE_INPUT: -7,
      END_OF_BLOCK: -8,
    },
    c = {};
  ((c[_.LAST_BLOCK] = "Bad file checksum"),
    (c[_.NOT_BZIP_DATA] = "Not bzip data"),
    (c[_.UNEXPECTED_INPUT_EOF] = "Unexpected input EOF"),
    (c[_.UNEXPECTED_OUTPUT_EOF] = "Unexpected output EOF"),
    (c[_.DATA_ERROR] = "Data error"),
    (c[_.OUT_OF_MEMORY] = "Out of memory"),
    (c[_.OBSOLETE_INPUT] = "Obsolete (pre 0.9.5) bzip format not supported."));
  var R = function (d, y) {
      var T = c[d] || "unknown error";
      y && (T += ": " + y);
      var k = new TypeError(T);
      throw ((k.errorCode = d), k);
    },
    i = function (d, y) {
      ((this.writePos = this.writeCurrent = this.writeCount = 0),
        this._start_bunzip(d, y));
    };
  ((i.prototype._init_block = function () {
    var d = this._get_next_block();
    return d ? ((this.blockCRC = new e()), !0) : ((this.writeCount = -1), !1);
  }),
    (i.prototype._start_bunzip = function (d, y) {
      var T = new Buffer(4);
      (d.read(T, 0, 4) !== 4 ||
        String.fromCharCode(T[0], T[1], T[2]) !== "BZh") &&
        R(_.NOT_BZIP_DATA, "bad magic");
      var k = T[3] - 48;
      ((k < 1 || k > 9) && R(_.NOT_BZIP_DATA, "level out of range"),
        (this.reader = new m(d)),
        (this.dbufSize = 1e5 * k),
        (this.nextoutput = 0),
        (this.outputStream = y),
        (this.streamCRC = 0));
    }),
    (i.prototype._get_next_block = function () {
      var d,
        y,
        T,
        k = this.reader,
        F = k.pi();
      if (F === B) return !1;
      (F !== b && R(_.NOT_BZIP_DATA),
        (this.targetBlockCRC = k.read(32) >>> 0),
        (this.streamCRC =
          (this.targetBlockCRC ^
            ((this.streamCRC << 1) | (this.streamCRC >>> 31))) >>>
          0),
        k.read(1) && R(_.OBSOLETE_INPUT));
      var O = k.read(24);
      O > this.dbufSize && R(_.DATA_ERROR, "initial position out of bounds");
      var q = k.read(16),
        L = new Buffer(256),
        N = 0;
      for (d = 0; d < 16; d++)
        if (q & (1 << (15 - d))) {
          var Z = d * 16;
          for (T = k.read(16), y = 0; y < 16; y++)
            T & (1 << (15 - y)) && (L[N++] = Z + y);
        }
      var $ = k.read(3);
      ($ < l || $ > p) && R(_.DATA_ERROR);
      var Y = k.read(15);
      Y === 0 && R(_.DATA_ERROR);
      var G = new Buffer(256);
      for (d = 0; d < $; d++) G[d] = d;
      var v = new Buffer(Y);
      for (d = 0; d < Y; d++) {
        for (y = 0; k.read(1); y++) y >= $ && R(_.DATA_ERROR);
        v[d] = w(G, y);
      }
      var g = N + 2,
        E = [],
        C;
      for (y = 0; y < $; y++) {
        var M = new Buffer(g),
          j = new Uint16Array(s + 1);
        for (q = k.read(5), d = 0; d < g; d++) {
          for (; (q < 1 || q > s) && R(_.DATA_ERROR), !!k.read(1);)
            k.read(1) ? q-- : q++;
          M[d] = q;
        }
        var P, W;
        for (P = W = M[0], d = 1; d < g; d++)
          M[d] > W ? (W = M[d]) : M[d] < P && (P = M[d]);
        ((C = {}),
          E.push(C),
          (C.permute = new Uint16Array(t)),
          (C.limit = new Uint32Array(s + 2)),
          (C.base = new Uint32Array(s + 1)),
          (C.minLen = P),
          (C.maxLen = W));
        var H = 0;
        for (d = P; d <= W; d++)
          for (j[d] = C.limit[d] = 0, q = 0; q < g; q++)
            M[q] === d && (C.permute[H++] = q);
        for (d = 0; d < g; d++) j[M[d]]++;
        for (H = q = 0, d = P; d < W; d++)
          ((H += j[d]),
            (C.limit[d] = H - 1),
            (H <<= 1),
            (q += j[d]),
            (C.base[d + 1] = H - q));
        ((C.limit[W + 1] = Number.MAX_VALUE),
          (C.limit[W] = H + j[W] - 1),
          (C.base[P] = 0));
      }
      var K = new Uint32Array(256);
      for (d = 0; d < 256; d++) G[d] = d;
      var a = 0,
        o = 0,
        S = 0,
        D,
        I = (this.dbuf = new Uint32Array(this.dbufSize));
      for (g = 0; ;) {
        for (
          g-- || ((g = A - 1), S >= Y && R(_.DATA_ERROR), (C = E[v[S++]])),
            d = C.minLen,
            y = k.read(d);
          d > C.maxLen && R(_.DATA_ERROR), !(y <= C.limit[d]);
          d++
        )
          y = (y << 1) | k.read(1);
        ((y -= C.base[d]), (y < 0 || y >= t) && R(_.DATA_ERROR));
        var z = C.permute[y];
        if (z === r || z === n) {
          (a || ((a = 1), (q = 0)),
            z === r ? (q += a) : (q += 2 * a),
            (a <<= 1));
          continue;
        }
        if (a)
          for (
            a = 0,
              o + q > this.dbufSize && R(_.DATA_ERROR),
              D = L[G[0]],
              K[D] += q;
            q--;
          )
            I[o++] = D;
        if (z > N) break;
        (o >= this.dbufSize && R(_.DATA_ERROR),
          (d = z - 1),
          (D = w(G, d)),
          (D = L[D]),
          K[D]++,
          (I[o++] = D));
      }
      for ((O < 0 || O >= o) && R(_.DATA_ERROR), y = 0, d = 0; d < 256; d++)
        ((T = y + K[d]), (K[d] = y), (y = T));
      for (d = 0; d < o; d++) ((D = I[d] & 255), (I[K[D]] |= d << 8), K[D]++);
      var U = 0,
        V = 0,
        J = 0;
      return (
        o && ((U = I[O]), (V = U & 255), (U >>= 8), (J = -1)),
        (this.writePos = U),
        (this.writeCurrent = V),
        (this.writeCount = o),
        (this.writeRun = J),
        !0
      );
    }),
    (i.prototype._read_bunzip = function (d, y) {
      var T, k, F;
      if (this.writeCount < 0) return 0;
      var O = this.dbuf,
        q = this.writePos,
        L = this.writeCurrent,
        N = this.writeCount;
      this.outputsize;
      for (var Z = this.writeRun; N;) {
        for (
          N--,
            k = L,
            q = O[q],
            L = q & 255,
            q >>= 8,
            Z++ === 3 ? ((T = L), (F = k), (L = -1)) : ((T = 1), (F = L)),
            this.blockCRC.updateCRCRun(F, T);
          T--;
        )
          (this.outputStream.writeByte(F), this.nextoutput++);
        L != k && (Z = 0);
      }
      return (
        (this.writeCount = N),
        this.blockCRC.getCRC() !== this.targetBlockCRC &&
          R(
            _.DATA_ERROR,
            "Bad block CRC (got " +
              this.blockCRC.getCRC().toString(16) +
              " expected " +
              this.targetBlockCRC.toString(16) +
              ")",
          ),
        this.nextoutput
      );
    }));
  var u = function (d) {
      if ("readByte" in d) return d;
      var y = new x();
      return (
        (y.pos = 0),
        (y.readByte = function () {
          return d[this.pos++];
        }),
        (y.seek = function (T) {
          this.pos = T;
        }),
        (y.eof = function () {
          return this.pos >= d.length;
        }),
        y
      );
    },
    h = function (d) {
      var y = new x(),
        T = !0;
      if (d)
        if (typeof d == "number") ((y.buffer = new Buffer(d)), (T = !1));
        else {
          if ("writeByte" in d) return d;
          ((y.buffer = d), (T = !1));
        }
      else y.buffer = new Buffer(16384);
      return (
        (y.pos = 0),
        (y.writeByte = function (k) {
          if (T && this.pos >= this.buffer.length) {
            var F = new Buffer(this.buffer.length * 2);
            (this.buffer.copy(F), (this.buffer = F));
          }
          this.buffer[this.pos++] = k;
        }),
        (y.getBuffer = function () {
          if (this.pos !== this.buffer.length) {
            if (!T)
              throw new TypeError("outputsize does not match decoded input");
            var k = new Buffer(this.pos);
            (this.buffer.copy(k, 0, 0, this.pos), (this.buffer = k));
          }
          return this.buffer;
        }),
        (y._coerced = !0),
        y
      );
    };
  return (
    (i.Err = _),
    (i.decode = function (d, y, T) {
      for (var k = u(d), F = h(y), O = new i(k, F); !("eof" in k && k.eof());)
        if (O._init_block()) O._read_bunzip();
        else {
          var q = O.reader.read(32) >>> 0;
          if (
            (q !== O.streamCRC &&
              R(
                _.DATA_ERROR,
                "Bad stream CRC (got " +
                  O.streamCRC.toString(16) +
                  " expected " +
                  q.toString(16) +
                  ")",
              ),
            T && "eof" in k && !k.eof())
          )
            O._start_bunzip(k, F);
          else break;
        }
      if ("getBuffer" in F) return F.getBuffer();
    }),
    (i.decodeBlock = function (d, y, T) {
      var k = u(d),
        F = h(T),
        O = new i(k, F);
      O.reader.seek(y);
      var q = O._get_next_block();
      if (
        (q && ((O.blockCRC = new e()), (O.writeCopies = 0), O._read_bunzip()),
        "getBuffer" in F)
      )
        return F.getBuffer();
    }),
    (i.table = function (d, y, T) {
      var k = new x();
      ((k.delegate = u(d)),
        (k.pos = 0),
        (k.readByte = function () {
          return (this.pos++, this.delegate.readByte());
        }),
        k.delegate.eof && (k.eof = k.delegate.eof.bind(k.delegate)));
      var F = new x();
      ((F.pos = 0),
        (F.writeByte = function () {
          this.pos++;
        }));
      for (var O = new i(k, F), q = O.dbufSize; !("eof" in k && k.eof());) {
        var L = k.pos * 8 + O.reader.bitOffset;
        if ((O.reader.hasByte && (L -= 8), O._init_block())) {
          var N = F.pos;
          (O._read_bunzip(), y(L, F.pos - N));
        } else if ((O.reader.read(32), T && "eof" in k && !k.eof()))
          (O._start_bunzip(k, F),
            console.assert(
              O.dbufSize === q,
              "shouldn't change block size within multistream file",
            ));
        else break;
      }
    }),
    (i.Stream = x),
    (i.version = f.version),
    (i.license = f.license),
    (He = i),
    He
  );
}
var Ze = { exports: {} },
  Hr;
function Kt() {
  return (
    Hr ||
      ((Hr = 1),
      (function (m, x) {
        var e = nr;
        ((m.exports = f), (f.through = f));
        function f(s, t, r) {
          ((s =
            s ||
            function (_) {
              this.queue(_);
            }),
            (t =
              t ||
              function () {
                this.queue(null);
              }));
          var n = !1,
            l = !1,
            p = [],
            A = !1,
            b = new e();
          ((b.readable = b.writable = !0),
            (b.paused = !1),
            (b.autoDestroy = !(r && r.autoDestroy === !1)),
            (b.write = function (_) {
              return (s.call(this, _), !b.paused);
            }));
          function B() {
            for (; p.length && !b.paused;) {
              var _ = p.shift();
              if (_ === null) return b.emit("end");
              b.emit("data", _);
            }
          }
          ((b.queue = b.push =
            function (_) {
              return (A || (_ === null && (A = !0), p.push(_), B()), b);
            }),
            b.on("end", function () {
              ((b.readable = !1),
                !b.writable &&
                  b.autoDestroy &&
                  process.nextTick(function () {
                    b.destroy();
                  }));
            }));
          function w() {
            ((b.writable = !1),
              t.call(b),
              !b.readable && b.autoDestroy && b.destroy());
          }
          return (
            (b.end = function (_) {
              if (!n) return ((n = !0), arguments.length && b.write(_), w(), b);
            }),
            (b.destroy = function () {
              if (!l)
                return (
                  (l = !0),
                  (n = !0),
                  (p.length = 0),
                  (b.writable = b.readable = !1),
                  b.emit("close"),
                  b
                );
            }),
            (b.pause = function () {
              if (!b.paused) return ((b.paused = !0), b);
            }),
            (b.resume = function () {
              return (
                b.paused && ((b.paused = !1), b.emit("resume")),
                B(),
                b.paused || b.emit("drain"),
                b
              );
            }),
            b
          );
        }
      })(Ze)),
    Ze.exports
  );
}
var Ge, Zr;
function Xt() {
  if (Zr) return Ge;
  Zr = 1;
  function m(f) {
    ((this.name = "Bzip2Error"),
      (this.message = f),
      (this.stack = new Error().stack));
  }
  m.prototype = new Error();
  var x = {
      Error: function (f) {
        throw new m(f);
      },
    },
    e = {};
  return (
    (e.Bzip2Error = m),
    (e.crcTable = [
      0, 79764919, 159529838, 222504665, 319059676, 398814059, 445009330,
      507990021, 638119352, 583659535, 797628118, 726387553, 890018660,
      835552979, 1015980042, 944750013, 1276238704, 1221641927, 1167319070,
      1095957929, 1595256236, 1540665371, 1452775106, 1381403509, 1780037320,
      1859660671, 1671105958, 1733955601, 2031960084, 2111593891, 1889500026,
      1952343757, 2552477408, 2632100695, 2443283854, 2506133561, 2334638140,
      2414271883, 2191915858, 2254759653, 3190512472, 3135915759, 3081330742,
      3009969537, 2905550212, 2850959411, 2762807018, 2691435357, 3560074640,
      3505614887, 3719321342, 3648080713, 3342211916, 3287746299, 3467911202,
      3396681109, 4063920168, 4143685023, 4223187782, 4286162673, 3779000052,
      3858754371, 3904687514, 3967668269, 881225847, 809987520, 1023691545,
      969234094, 662832811, 591600412, 771767749, 717299826, 311336399,
      374308984, 453813921, 533576470, 25881363, 88864420, 134795389, 214552010,
      2023205639, 2086057648, 1897238633, 1976864222, 1804852699, 1867694188,
      1645340341, 1724971778, 1587496639, 1516133128, 1461550545, 1406951526,
      1302016099, 1230646740, 1142491917, 1087903418, 2896545431, 2825181984,
      2770861561, 2716262478, 3215044683, 3143675388, 3055782693, 3001194130,
      2326604591, 2389456536, 2200899649, 2280525302, 2578013683, 2640855108,
      2418763421, 2498394922, 3769900519, 3832873040, 3912640137, 3992402750,
      4088425275, 4151408268, 4197601365, 4277358050, 3334271071, 3263032808,
      3476998961, 3422541446, 3585640067, 3514407732, 3694837229, 3640369242,
      1762451694, 1842216281, 1619975040, 1682949687, 2047383090, 2127137669,
      1938468188, 2001449195, 1325665622, 1271206113, 1183200824, 1111960463,
      1543535498, 1489069629, 1434599652, 1363369299, 622672798, 568075817,
      748617968, 677256519, 907627842, 853037301, 1067152940, 995781531,
      51762726, 131386257, 177728840, 240578815, 269590778, 349224269,
      429104020, 491947555, 4046411278, 4126034873, 4172115296, 4234965207,
      3794477266, 3874110821, 3953728444, 4016571915, 3609705398, 3555108353,
      3735388376, 3664026991, 3290680682, 3236090077, 3449943556, 3378572211,
      3174993278, 3120533705, 3032266256, 2961025959, 2923101090, 2868635157,
      2813903052, 2742672763, 2604032198, 2683796849, 2461293480, 2524268063,
      2284983834, 2364738477, 2175806836, 2238787779, 1569362073, 1498123566,
      1409854455, 1355396672, 1317987909, 1246755826, 1192025387, 1137557660,
      2072149281, 2135122070, 1912620623, 1992383480, 1753615357, 1816598090,
      1627664531, 1707420964, 295390185, 358241886, 404320391, 483945776,
      43990325, 106832002, 186451547, 266083308, 932423249, 861060070,
      1041341759, 986742920, 613929101, 542559546, 756411363, 701822548,
      3316196985, 3244833742, 3425377559, 3370778784, 3601682597, 3530312978,
      3744426955, 3689838204, 3819031489, 3881883254, 3928223919, 4007849240,
      4037393693, 4100235434, 4180117107, 4259748804, 2310601993, 2373574846,
      2151335527, 2231098320, 2596047829, 2659030626, 2470359227, 2550115596,
      2947551409, 2876312838, 2788305887, 2733848168, 3165939309, 3094707162,
      3040238851, 2985771188,
    ]),
    (e.array = function (f) {
      var s = 0,
        t = 0,
        r = [0, 1, 3, 7, 15, 31, 63, 127, 255];
      return function (n) {
        for (var l = 0; n > 0;) {
          var p = 8 - s;
          n >= p
            ? ((l <<= p), (l |= r[p] & f[t++]), (s = 0), (n -= p))
            : ((l <<= n),
              (l |= (f[t] & (r[n] << (8 - n - s))) >> (8 - n - s)),
              (s += n),
              (n = 0));
        }
        return l;
      };
    }),
    (e.simple = function (f, s) {
      var t = e.array(f),
        r = e.header(t),
        n = !1,
        l = 1e5 * r,
        p = new Int32Array(l);
      do n = e.decompress(t, s, p, l);
      while (!n);
    }),
    (e.header = function (f) {
      ((this.byteCount = new Int32Array(256)),
        (this.symToByte = new Uint8Array(256)),
        (this.mtfSymbol = new Int32Array(256)),
        (this.selectors = new Uint8Array(32768)),
        f(24) != 4348520 && x.Error("No magic number found"));
      var s = f(8) - 48;
      return ((s < 1 || s > 9) && x.Error("Not a BZIP archive"), s);
    }),
    (e.decompress = function (f, s, t, r, n) {
      for (
        var l = 20, p = 258, A = 0, b = 1, B = 50, w = -1, _ = "", c = 0;
        c < 6;
        c++
      )
        _ += f(8).toString(16);
      if (_ == "177245385090") {
        var R = f(32) | 0;
        return (
          R !== n && x.Error("Error in bzip2: crc32 do not match"),
          f(null),
          null
        );
      }
      _ != "314159265359" && x.Error("eek not valid bzip data");
      var i = f(32) | 0;
      f(1) && x.Error("unsupported obsolete version");
      var u = f(24);
      u > r && x.Error("Initial position larger than buffer size");
      var h = f(16),
        d = 0;
      for (c = 0; c < 16; c++)
        if (h & (1 << (15 - c))) {
          var y = f(16);
          for (P = 0; P < 16; P++)
            y & (1 << (15 - P)) && (this.symToByte[d++] = 16 * c + P);
        }
      var T = f(3);
      (T < 2 || T > 6) && x.Error("another error");
      var k = f(15);
      k == 0 && x.Error("meh");
      for (var c = 0; c < T; c++) this.mtfSymbol[c] = c;
      for (var c = 0; c < k; c++) {
        for (var P = 0; f(1); P++) P >= T && x.Error("whoops another error");
        for (var F = this.mtfSymbol[P], y = P - 1; y >= 0; y--)
          this.mtfSymbol[y + 1] = this.mtfSymbol[y];
        ((this.mtfSymbol[0] = F), (this.selectors[c] = F));
      }
      for (
        var C = d + 2,
          O = [],
          q = new Uint8Array(p),
          L = new Uint16Array(l + 1),
          N,
          P = 0;
        P < T;
        P++
      ) {
        h = f(5);
        for (var c = 0; c < C; c++) {
          for (
            ;
            (h < 1 || h > l) &&
              x.Error("I gave up a while ago on writing error messages"),
              !!f(1);
          )
            f(1) ? h-- : h++;
          q[c] = h;
        }
        var Z, $;
        Z = $ = q[0];
        for (var c = 1; c < C; c++)
          q[c] > $ ? ($ = q[c]) : q[c] < Z && (Z = q[c]);
        ((N = O[P] = {}),
          (N.permute = new Int32Array(p)),
          (N.limit = new Int32Array(l + 1)),
          (N.base = new Int32Array(l + 1)),
          (N.minLen = Z),
          (N.maxLen = $));
        for (var Y = N.base, G = N.limit, v = 0, c = Z; c <= $; c++)
          for (var h = 0; h < C; h++) q[h] == c && (N.permute[v++] = h);
        for (c = Z; c <= $; c++) L[c] = G[c] = 0;
        for (c = 0; c < C; c++) L[q[c]]++;
        for (v = h = 0, c = Z; c < $; c++)
          ((v += L[c]),
            (G[c] = v - 1),
            (v <<= 1),
            (Y[c + 1] = v - (h += L[c])));
        ((G[$] = v + L[$] - 1), (Y[Z] = 0));
      }
      for (var c = 0; c < 256; c++)
        ((this.mtfSymbol[c] = c), (this.byteCount[c] = 0));
      var g, E, C, M;
      for (g = E = C = M = 0; ;) {
        for (
          C-- ||
            ((C = B - 1),
            M >= k && x.Error("meow i'm a kitty, that's an error"),
            (N = O[this.selectors[M++]]),
            (Y = N.base),
            (G = N.limit)),
            c = N.minLen,
            P = f(c);
          c > N.maxLen && x.Error("rawr i'm a dinosaur"), !(P <= G[c]);
        )
          (c++, (P = (P << 1) | f(1)));
        ((P -= Y[c]), (P < 0 || P >= p) && x.Error("moo i'm a cow"));
        var j = N.permute[P];
        if (j == A || j == b) {
          (g || ((g = 1), (h = 0)),
            j == A ? (h += g) : (h += 2 * g),
            (g <<= 1));
          continue;
        }
        if (g)
          for (
            g = 0,
              E + h > r && x.Error("Boom."),
              F = this.symToByte[this.mtfSymbol[0]],
              this.byteCount[F] += h;
            h--;
          )
            t[E++] = F;
        if (j > d) break;
        (E >= r && x.Error("I can't think of anything. Error"),
          (c = j - 1),
          (F = this.mtfSymbol[c]));
        for (var y = c - 1; y >= 0; y--)
          this.mtfSymbol[y + 1] = this.mtfSymbol[y];
        ((this.mtfSymbol[0] = F),
          (F = this.symToByte[F]),
          this.byteCount[F]++,
          (t[E++] = F));
      }
      (u < 0 || u >= E) &&
        x.Error(
          "I'm a monkey and I'm throwing something at someone, namely you",
        );
      for (var P = 0, c = 0; c < 256; c++)
        ((y = P + this.byteCount[c]), (this.byteCount[c] = P), (P = y));
      for (var c = 0; c < E; c++)
        ((F = t[c] & 255),
          (t[this.byteCount[F]] |= c << 8),
          this.byteCount[F]++);
      var W = 0,
        H = 0,
        K = 0;
      (E && ((W = t[u]), (H = W & 255), (W >>= 8), (K = -1)), (E = E));
      for (var a, o, S; E;) {
        for (
          E--,
            o = H,
            W = t[W],
            H = W & 255,
            W >>= 8,
            K++ == 3 ? ((a = H), (S = o), (H = -1)) : ((a = 1), (S = H));
          a--;
        )
          ((w = ((w << 8) ^ this.crcTable[((w >> 24) ^ S) & 255]) & 4294967295),
            s(S));
        H != o && (K = 0);
      }
      return (
        (w = (w ^ -1) >>> 0),
        (w | 0) != (i | 0) && x.Error("Error in bzip2: crc32 do not match"),
        (n = (w ^ ((n << 1) | (n >>> 31))) & 4294967295),
        n
      );
    }),
    (Ge = e),
    Ge
  );
}
var Ke, Gr;
function Yt() {
  if (Gr) return Ke;
  Gr = 1;
  var m = [0, 1, 3, 7, 15, 31, 63, 127, 255];
  return (
    (Ke = function (e) {
      var f = 0,
        s = 0,
        t = e(),
        r = function (n) {
          if (n === null && f != 0) {
            ((f = 0), s++);
            return;
          }
          for (var l = 0; n > 0;) {
            s >= t.length && ((s = 0), (t = e()));
            var p = 8 - f;
            (f === 0 && n > 0 && r.bytesRead++,
              n >= p
                ? ((l <<= p), (l |= m[p] & t[s++]), (f = 0), (n -= p))
                : ((l <<= n),
                  (l |= (t[s] & (m[n] << (8 - n - f))) >> (8 - n - f)),
                  (f += n),
                  (n = 0)));
          }
          return l;
        };
      return ((r.bytesRead = 0), r);
    }),
    Ke
  );
}
var Xe, Kr;
function Vt() {
  if (Kr) return Xe;
  Kr = 1;
  var m = Kt(),
    x = Xt(),
    e = Yt();
  Xe = f;
  function f() {
    var s = [],
      t = 0,
      r = 0,
      n = !1,
      l = null,
      p = null;
    function A(w) {
      if (r) {
        var _ = 1e5 * r,
          c = new Int32Array(_),
          R = [],
          i = function (u) {
            R.push(u);
          };
        return (
          (p = x.decompress(l, i, c, _, p)),
          p === null ? ((r = 0), !1) : (w(Buffer.from(R)), !0)
        );
      } else return ((r = x.header(l)), (p = 0), !0);
    }
    var b = 0;
    function B(w) {
      if (!n)
        try {
          return A(function (_) {
            (w.queue(_), _ !== null && (b += _.length));
          });
        } catch (_) {
          return (w.emit("error", _), (n = !0), !1);
        }
    }
    return m(
      function (_) {
        for (
          s.push(_),
            t += _.length,
            l === null &&
              (l = e(function () {
                return s.shift();
              }));
          !n && t - l.bytesRead + 1 >= (25e3 + 1e5 * r || 4);
        )
          B(this);
      },
      function (_) {
        for (; !n && l && t > l.bytesRead;) B(this);
        n ||
          (p !== null &&
            this.emit("error", new Error("input stream ended prematurely")),
          this.queue(null));
      },
    );
  }
  return Xe;
}
var Ye, Xr;
function Qt() {
  if (Xr) return Ye;
  Xr = 1;
  const m = xr(),
    x = It(),
    e = fr(),
    f = Gt(),
    s = Vt();
  return (
    (Ye = () => (t) =>
      !Buffer.isBuffer(t) && !e(t)
        ? Promise.reject(
            new TypeError(`Expected a Buffer or Stream, got ${typeof t}`),
          )
        : Buffer.isBuffer(t) && (!x(t) || x(t).ext !== "bz2")
          ? Promise.resolve([])
          : Buffer.isBuffer(t)
            ? m()(f.decode(t))
            : m()(t.pipe(s()))),
    Ye
  );
}
var Ve, Yr;
function Jt() {
  return (
    Yr ||
      ((Yr = 1),
      (Ve = (m) => {
        const x = new Uint8Array(m);
        if (!(x && x.length > 1)) return null;
        const e = (f, s) => {
          s = Object.assign({ offset: 0 }, s);
          for (let t = 0; t < f.length; t++)
            if (f[t] !== x[t + s.offset]) return !1;
          return !0;
        };
        if (e([255, 216, 255])) return { ext: "jpg", mime: "image/jpeg" };
        if (e([137, 80, 78, 71, 13, 10, 26, 10]))
          return { ext: "png", mime: "image/png" };
        if (e([71, 73, 70])) return { ext: "gif", mime: "image/gif" };
        if (e([87, 69, 66, 80], { offset: 8 }))
          return { ext: "webp", mime: "image/webp" };
        if (e([70, 76, 73, 70])) return { ext: "flif", mime: "image/flif" };
        if (
          (e([73, 73, 42, 0]) || e([77, 77, 0, 42])) &&
          e([67, 82], { offset: 8 })
        )
          return { ext: "cr2", mime: "image/x-canon-cr2" };
        if (e([73, 73, 42, 0]) || e([77, 77, 0, 42]))
          return { ext: "tif", mime: "image/tiff" };
        if (e([66, 77])) return { ext: "bmp", mime: "image/bmp" };
        if (e([73, 73, 188])) return { ext: "jxr", mime: "image/vnd.ms-photo" };
        if (e([56, 66, 80, 83]))
          return { ext: "psd", mime: "image/vnd.adobe.photoshop" };
        if (
          e([80, 75, 3, 4]) &&
          e(
            [
              109, 105, 109, 101, 116, 121, 112, 101, 97, 112, 112, 108, 105,
              99, 97, 116, 105, 111, 110, 47, 101, 112, 117, 98, 43, 122, 105,
              112,
            ],
            { offset: 30 },
          )
        )
          return { ext: "epub", mime: "application/epub+zip" };
        if (
          e([80, 75, 3, 4]) &&
          e(
            [
              77, 69, 84, 65, 45, 73, 78, 70, 47, 109, 111, 122, 105, 108, 108,
              97, 46, 114, 115, 97,
            ],
            { offset: 30 },
          )
        )
          return { ext: "xpi", mime: "application/x-xpinstall" };
        if (
          e([80, 75]) &&
          (x[2] === 3 || x[2] === 5 || x[2] === 7) &&
          (x[3] === 4 || x[3] === 6 || x[3] === 8)
        )
          return { ext: "zip", mime: "application/zip" };
        if (e([117, 115, 116, 97, 114], { offset: 257 }))
          return { ext: "tar", mime: "application/x-tar" };
        if (e([82, 97, 114, 33, 26, 7]) && (x[6] === 0 || x[6] === 1))
          return { ext: "rar", mime: "application/x-rar-compressed" };
        if (e([31, 139, 8])) return { ext: "gz", mime: "application/gzip" };
        if (e([66, 90, 104]))
          return { ext: "bz2", mime: "application/x-bzip2" };
        if (e([55, 122, 188, 175, 39, 28]))
          return { ext: "7z", mime: "application/x-7z-compressed" };
        if (e([120, 1]))
          return { ext: "dmg", mime: "application/x-apple-diskimage" };
        if (
          (e([0, 0, 0]) &&
            (x[3] === 24 || x[3] === 32) &&
            e([102, 116, 121, 112], { offset: 4 })) ||
          e([51, 103, 112, 53]) ||
          (e([0, 0, 0, 28, 102, 116, 121, 112, 109, 112, 52, 50]) &&
            e([109, 112, 52, 49, 109, 112, 52, 50, 105, 115, 111, 109], {
              offset: 16,
            })) ||
          e([0, 0, 0, 28, 102, 116, 121, 112, 105, 115, 111, 109]) ||
          e([0, 0, 0, 28, 102, 116, 121, 112, 109, 112, 52, 50, 0, 0, 0, 0])
        )
          return { ext: "mp4", mime: "video/mp4" };
        if (e([0, 0, 0, 28, 102, 116, 121, 112, 77, 52, 86]))
          return { ext: "m4v", mime: "video/x-m4v" };
        if (e([77, 84, 104, 100])) return { ext: "mid", mime: "audio/midi" };
        if (e([26, 69, 223, 163])) {
          const f = x.subarray(4, 4100),
            s = f.findIndex((t, r, n) => n[r] === 66 && n[r + 1] === 130);
          if (s >= 0) {
            const t = s + 3,
              r = (n) =>
                Array.from(n).every((l, p) => f[t + p] === l.charCodeAt(0));
            if (r("matroska")) return { ext: "mkv", mime: "video/x-matroska" };
            if (r("webm")) return { ext: "webm", mime: "video/webm" };
          }
        }
        return e([0, 0, 0, 20, 102, 116, 121, 112, 113, 116, 32, 32]) ||
          e([102, 114, 101, 101], { offset: 4 }) ||
          e([102, 116, 121, 112, 113, 116, 32, 32], { offset: 4 }) ||
          e([109, 100, 97, 116], { offset: 4 }) ||
          e([119, 105, 100, 101], { offset: 4 })
          ? { ext: "mov", mime: "video/quicktime" }
          : e([82, 73, 70, 70]) && e([65, 86, 73], { offset: 8 })
            ? { ext: "avi", mime: "video/x-msvideo" }
            : e([48, 38, 178, 117, 142, 102, 207, 17, 166, 217])
              ? { ext: "wmv", mime: "video/x-ms-wmv" }
              : e([0, 0, 1, 186])
                ? { ext: "mpg", mime: "video/mpeg" }
                : e([73, 68, 51]) || e([255, 251])
                  ? { ext: "mp3", mime: "audio/mpeg" }
                  : e([102, 116, 121, 112, 77, 52, 65], { offset: 4 }) ||
                      e([77, 52, 65, 32])
                    ? { ext: "m4a", mime: "audio/m4a" }
                    : e([79, 112, 117, 115, 72, 101, 97, 100], { offset: 28 })
                      ? { ext: "opus", mime: "audio/opus" }
                      : e([79, 103, 103, 83])
                        ? { ext: "ogg", mime: "audio/ogg" }
                        : e([102, 76, 97, 67])
                          ? { ext: "flac", mime: "audio/x-flac" }
                          : e([82, 73, 70, 70]) &&
                              e([87, 65, 86, 69], { offset: 8 })
                            ? { ext: "wav", mime: "audio/x-wav" }
                            : e([35, 33, 65, 77, 82, 10])
                              ? { ext: "amr", mime: "audio/amr" }
                              : e([37, 80, 68, 70])
                                ? { ext: "pdf", mime: "application/pdf" }
                                : e([77, 90])
                                  ? {
                                      ext: "exe",
                                      mime: "application/x-msdownload",
                                    }
                                  : (x[0] === 67 || x[0] === 70) &&
                                      e([87, 83], { offset: 1 })
                                    ? {
                                        ext: "swf",
                                        mime: "application/x-shockwave-flash",
                                      }
                                    : e([123, 92, 114, 116, 102])
                                      ? { ext: "rtf", mime: "application/rtf" }
                                      : e([0, 97, 115, 109])
                                        ? {
                                            ext: "wasm",
                                            mime: "application/wasm",
                                          }
                                        : e([119, 79, 70, 70]) &&
                                            (e([0, 1, 0, 0], { offset: 4 }) ||
                                              e([79, 84, 84, 79], {
                                                offset: 4,
                                              }))
                                          ? { ext: "woff", mime: "font/woff" }
                                          : e([119, 79, 70, 50]) &&
                                              (e([0, 1, 0, 0], { offset: 4 }) ||
                                                e([79, 84, 84, 79], {
                                                  offset: 4,
                                                }))
                                            ? {
                                                ext: "woff2",
                                                mime: "font/woff2",
                                              }
                                            : e([76, 80], { offset: 34 }) &&
                                                (e([0, 0, 1], { offset: 8 }) ||
                                                  e([1, 0, 2], { offset: 8 }) ||
                                                  e([2, 0, 2], { offset: 8 }))
                                              ? {
                                                  ext: "eot",
                                                  mime: "application/octet-stream",
                                                }
                                              : e([0, 1, 0, 0, 0])
                                                ? {
                                                    ext: "ttf",
                                                    mime: "font/ttf",
                                                  }
                                                : e([79, 84, 84, 79, 0])
                                                  ? {
                                                      ext: "otf",
                                                      mime: "font/otf",
                                                    }
                                                  : e([0, 0, 1, 0])
                                                    ? {
                                                        ext: "ico",
                                                        mime: "image/x-icon",
                                                      }
                                                    : e([70, 76, 86, 1])
                                                      ? {
                                                          ext: "flv",
                                                          mime: "video/x-flv",
                                                        }
                                                      : e([37, 33])
                                                        ? {
                                                            ext: "ps",
                                                            mime: "application/postscript",
                                                          }
                                                        : e([
                                                              253, 55, 122, 88,
                                                              90, 0,
                                                            ])
                                                          ? {
                                                              ext: "xz",
                                                              mime: "application/x-xz",
                                                            }
                                                          : e([83, 81, 76, 105])
                                                            ? {
                                                                ext: "sqlite",
                                                                mime: "application/x-sqlite3",
                                                              }
                                                            : e([
                                                                  78, 69, 83,
                                                                  26,
                                                                ])
                                                              ? {
                                                                  ext: "nes",
                                                                  mime: "application/x-nintendo-nes-rom",
                                                                }
                                                              : e([
                                                                    67, 114, 50,
                                                                    52,
                                                                  ])
                                                                ? {
                                                                    ext: "crx",
                                                                    mime: "application/x-google-chrome-extension",
                                                                  }
                                                                : e([
                                                                      77, 83,
                                                                      67, 70,
                                                                    ]) ||
                                                                    e([
                                                                      73, 83,
                                                                      99, 40,
                                                                    ])
                                                                  ? {
                                                                      ext: "cab",
                                                                      mime: "application/vnd.ms-cab-compressed",
                                                                    }
                                                                  : e([
                                                                        33, 60,
                                                                        97, 114,
                                                                        99, 104,
                                                                        62, 10,
                                                                        100,
                                                                        101, 98,
                                                                        105, 97,
                                                                        110, 45,
                                                                        98, 105,
                                                                        110, 97,
                                                                        114,
                                                                        121,
                                                                      ])
                                                                    ? {
                                                                        ext: "deb",
                                                                        mime: "application/x-deb",
                                                                      }
                                                                    : e([
                                                                          33,
                                                                          60,
                                                                          97,
                                                                          114,
                                                                          99,
                                                                          104,
                                                                          62,
                                                                        ])
                                                                      ? {
                                                                          ext: "ar",
                                                                          mime: "application/x-unix-archive",
                                                                        }
                                                                      : e([
                                                                            237,
                                                                            171,
                                                                            238,
                                                                            219,
                                                                          ])
                                                                        ? {
                                                                            ext: "rpm",
                                                                            mime: "application/x-rpm",
                                                                          }
                                                                        : e([
                                                                              31,
                                                                              160,
                                                                            ]) ||
                                                                            e([
                                                                              31,
                                                                              157,
                                                                            ])
                                                                          ? {
                                                                              ext: "Z",
                                                                              mime: "application/x-compress",
                                                                            }
                                                                          : e([
                                                                                76,
                                                                                90,
                                                                                73,
                                                                                80,
                                                                              ])
                                                                            ? {
                                                                                ext: "lz",
                                                                                mime: "application/x-lzip",
                                                                              }
                                                                            : e(
                                                                                  [
                                                                                    208,
                                                                                    207,
                                                                                    17,
                                                                                    224,
                                                                                    161,
                                                                                    177,
                                                                                    26,
                                                                                    225,
                                                                                  ],
                                                                                )
                                                                              ? {
                                                                                  ext: "msi",
                                                                                  mime: "application/x-msi",
                                                                                }
                                                                              : e(
                                                                                    [
                                                                                      6,
                                                                                      14,
                                                                                      43,
                                                                                      52,
                                                                                      2,
                                                                                      5,
                                                                                      1,
                                                                                      1,
                                                                                      13,
                                                                                      1,
                                                                                      2,
                                                                                      1,
                                                                                      1,
                                                                                      2,
                                                                                    ],
                                                                                  )
                                                                                ? {
                                                                                    ext: "mxf",
                                                                                    mime: "application/mxf",
                                                                                  }
                                                                                : e(
                                                                                      [
                                                                                        71,
                                                                                      ],
                                                                                      {
                                                                                        offset: 4,
                                                                                      },
                                                                                    ) &&
                                                                                    (e(
                                                                                      [
                                                                                        71,
                                                                                      ],
                                                                                      {
                                                                                        offset: 192,
                                                                                      },
                                                                                    ) ||
                                                                                      e(
                                                                                        [
                                                                                          71,
                                                                                        ],
                                                                                        {
                                                                                          offset: 196,
                                                                                        },
                                                                                      ))
                                                                                  ? {
                                                                                      ext: "mts",
                                                                                      mime: "video/mp2t",
                                                                                    }
                                                                                  : e(
                                                                                        [
                                                                                          66,
                                                                                          76,
                                                                                          69,
                                                                                          78,
                                                                                          68,
                                                                                          69,
                                                                                          82,
                                                                                        ],
                                                                                      )
                                                                                    ? {
                                                                                        ext: "blend",
                                                                                        mime: "application/x-blender",
                                                                                      }
                                                                                    : e(
                                                                                          [
                                                                                            66,
                                                                                            80,
                                                                                            71,
                                                                                            251,
                                                                                          ],
                                                                                        )
                                                                                      ? {
                                                                                          ext: "bpg",
                                                                                          mime: "image/bpg",
                                                                                        }
                                                                                      : null;
      })),
    Ve
  );
}
var Qe, Vr;
function ei() {
  if (Vr) return Qe;
  Vr = 1;
  const m = Bt,
    x = xr(),
    e = Jt(),
    f = fr();
  return (
    (Qe = () => (s) => {
      if (!Buffer.isBuffer(s) && !f(s))
        return Promise.reject(
          new TypeError(`Expected a Buffer or Stream, got ${typeof s}`),
        );
      if (Buffer.isBuffer(s) && (!e(s) || e(s).ext !== "gz"))
        return Promise.resolve([]);
      const t = m.createGunzip(),
        r = x()(t);
      return (Buffer.isBuffer(s) ? t.end(s) : s.pipe(t), r);
    }),
    Qe
  );
}
var de = { exports: {} },
  Je,
  Qr;
function ri() {
  if (Qr) return Je;
  Qr = 1;
  const m = (x, e) =>
    function () {
      const f = e.promiseModule,
        s = new Array(arguments.length);
      for (let t = 0; t < arguments.length; t++) s[t] = arguments[t];
      return new f((t, r) => {
        (e.errorFirst
          ? s.push(function (n, l) {
              if (e.multiArgs) {
                const p = new Array(arguments.length - 1);
                for (let A = 1; A < arguments.length; A++)
                  p[A - 1] = arguments[A];
                n ? (p.unshift(n), r(p)) : t(p);
              } else n ? r(n) : t(l);
            })
          : s.push(function (n) {
              if (e.multiArgs) {
                const l = new Array(arguments.length - 1);
                for (let p = 0; p < arguments.length; p++) l[p] = arguments[p];
                t(l);
              } else t(n);
            }),
          x.apply(this, s));
      });
    };
  return (
    (Je = (x, e) => {
      e = Object.assign(
        {
          exclude: [/.+(Sync|Stream)$/],
          errorFirst: !0,
          promiseModule: Promise,
        },
        e,
      );
      const f = (t) => {
        const r = (n) => (typeof n == "string" ? t === n : n.test(t));
        return e.include ? e.include.some(r) : !e.exclude.some(r);
      };
      let s;
      typeof x == "function"
        ? (s = function () {
            return e.excludeMain
              ? x.apply(this, arguments)
              : m(x, e).apply(this, arguments);
          })
        : (s = Object.create(Object.getPrototypeOf(x)));
      for (const t in x) {
        const r = x[t];
        s[t] = typeof r == "function" && f(t) ? m(r, e) : r;
      }
      return s;
    }),
    Je
  );
}
var Jr;
function ti() {
  if (Jr) return de.exports;
  Jr = 1;
  const m = St,
    x = ir,
    e = ri(),
    f = { mode: 511 & ~process.umask(), fs: m },
    s = (t) => {
      if (
        process.platform === "win32" &&
        /[<>:"|?*]/.test(t.replace(x.parse(t).root, ""))
      ) {
        const n = new Error(`Path contains invalid characters: ${t}`);
        throw ((n.code = "EINVAL"), n);
      }
    };
  return (
    (de.exports = (t, r) =>
      Promise.resolve().then(() => {
        (s(t), (r = Object.assign({}, f, r)));
        const n = e(r.fs.mkdir),
          l = e(r.fs.stat),
          p = (A) =>
            n(A, r.mode)
              .then(() => A)
              .catch((b) => {
                if (b.code === "ENOENT") {
                  if (b.message.includes("null bytes") || x.dirname(A) === A)
                    throw b;
                  return p(x.dirname(A)).then(() => p(A));
                }
                return l(A)
                  .then((B) => (B.isDirectory() ? A : Promise.reject()))
                  .catch(() => {
                    throw b;
                  });
              });
        return p(x.resolve(t));
      })),
    (de.exports.sync = (t, r) => {
      (s(t), (r = Object.assign({}, f, r)));
      const n = (l) => {
        try {
          r.fs.mkdirSync(l, r.mode);
        } catch (p) {
          if (p.code === "ENOENT") {
            if (p.message.includes("null bytes") || x.dirname(l) === l) throw p;
            return (n(x.dirname(l)), n(l));
          }
          try {
            if (!r.fs.statSync(l).isDirectory())
              throw new Error("The path is not a directory");
          } catch {
            throw p;
          }
        }
        return l;
      };
      return n(x.resolve(t));
    }),
    de.exports
  );
}
var er = { exports: {} },
  et;
function ii() {
  if (et) return er.exports;
  et = 1;
  var m = function (e, f, s) {
      return function () {
        for (
          var t = this, r = new Array(arguments.length), n = 0;
          n < arguments.length;
          n++
        )
          r[n] = arguments[n];
        return new f(function (l, p) {
          (r.push(function (A, b) {
            if (A) p(A);
            else if (s.multiArgs) {
              for (
                var B = new Array(arguments.length - 1), w = 1;
                w < arguments.length;
                w++
              )
                B[w - 1] = arguments[w];
              l(B);
            } else l(b);
          }),
            e.apply(t, r));
        });
      };
    },
    x = (er.exports = function (e, f, s) {
      (typeof f != "function" && ((s = f), (f = Promise)),
        (s = s || {}),
        (s.exclude = s.exclude || [/.+Sync$/]));
      var t = function (n) {
          var l = function (p) {
            return typeof p == "string" ? n === p : p.test(n);
          };
          return s.include ? s.include.some(l) : !s.exclude.some(l);
        },
        r =
          typeof e == "function"
            ? function () {
                return s.excludeMain
                  ? e.apply(this, arguments)
                  : m(e, f, s).apply(this, arguments);
              }
            : {};
      return Object.keys(e).reduce(function (n, l) {
        var p = e[l];
        return ((n[l] = typeof p == "function" && t(l) ? m(p, f, s) : p), n);
      }, r);
    });
  return ((x.all = x), er.exports);
}
function ni(m, x) {
  if (x) {
    if (typeof x != "object")
      throw new TypeError(
        String(x) +
          " is not an object. Expected an object that has boolean `includeZero` property.",
      );
    if ("includeZero" in x) {
      if (typeof x.includeZero != "boolean")
        throw new TypeError(
          String(x.includeZero) +
            " is neither true nor false. `includeZero` option must be a Boolean value.",
        );
      if (x.includeZero && m === 0) return !0;
    }
  }
  return Number.isSafeInteger(m) && m >= 1;
}
const ai = Object.freeze(
    Object.defineProperty(
      { __proto__: null, default: ni },
      Symbol.toStringTag,
      { value: "Module" },
    ),
  ),
  fi = dt(ai);
var rr, rt;
function oi() {
  if (rt) return rr;
  rt = 1;
  const m = ir,
    x = te,
    e = fi;
  return (
    (rr = function (s, t, r) {
      if (typeof s != "string")
        throw new TypeError(
          x.inspect(s) +
            " is not a string. First argument to strip-dirs must be a path string.",
        );
      if (m.posix.isAbsolute(s) || m.win32.isAbsolute(s))
        throw new Error(
          `${s} is an absolute path. strip-dirs requires a relative path.`,
        );
      if (!e(t, { includeZero: !0 }))
        throw new Error(
          "The Second argument of strip-dirs must be a natural number or 0, but received " +
            x.inspect(t) +
            ".",
        );
      if (r) {
        if (typeof r != "object")
          throw new TypeError(
            x.inspect(r) +
              " is not an object. Expected an object with a boolean `disallowOverflow` property.",
          );
        if (Array.isArray(r))
          throw new TypeError(
            x.inspect(r) +
              " is an array. Expected an object with a boolean `disallowOverflow` property.",
          );
        if ("disallowOverflow" in r && typeof r.disallowOverflow != "boolean")
          throw new TypeError(
            x.inspect(r.disallowOverflow) +
              " is neither true nor false. `disallowOverflow` option must be a Boolean value.",
          );
      } else r = { disallowOverflow: !1 };
      const n = m.normalize(s).split(m.sep);
      if ((n.length > 1 && n[0] === "." && n.shift(), t > n.length - 1)) {
        if (r.disallowOverflow)
          throw new RangeError("Cannot strip more directories than there are.");
        t = n.length - 1;
      }
      return m.join.apply(null, n.slice(t));
    }),
    rr
  );
}
var tr, tt;
function xi() {
  if (tt) return tr;
  tt = 1;
  const m = ir,
    x = mt(),
    e = xr(),
    f = Qt(),
    s = ei(),
    t = Et(),
    r = ti(),
    n = ii(),
    l = oi(),
    p = n(x),
    A = (_, c) =>
      c.plugins.length === 0
        ? Promise.resolve([])
        : Promise.all(c.plugins.map((R) => R(_, c))).then((R) =>
            R.reduce((i, u) => i.concat(u)),
          ),
    b = (_, c) =>
      p
        .realpath(_)
        .catch((R) => {
          const i = m.dirname(_);
          return b(i, c);
        })
        .then((R) => {
          if (R.indexOf(c) !== 0)
            throw new Error(
              "Refusing to create a directory outside the output path.",
            );
          return r(_).then(p.realpath);
        }),
    B = (_, c) =>
      p
        .readlink(_)
        .catch((R) => null)
        .then((R) => {
          if (R) throw new Error("Refusing to write into a symlink");
          return c;
        }),
    w = (_, c, R) =>
      A(_, R).then(
        (i) => (
          R.strip > 0 &&
            (i = i
              .map((u) => ((u.path = l(u.path, R.strip)), u))
              .filter((u) => u.path !== ".")),
          typeof R.filter == "function" && (i = i.filter(R.filter)),
          typeof R.map == "function" && (i = i.map(R.map)),
          c
            ? Promise.all(
                i.map((u) => {
                  const h = m.join(c, u.path),
                    d = u.mode & ~process.umask(),
                    y = new Date();
                  return u.type === "directory"
                    ? r(c)
                        .then((T) => p.realpath(T))
                        .then((T) => b(h, T))
                        .then(() => p.utimes(h, y, u.mtime))
                        .then(() => u)
                    : r(c)
                        .then((T) => p.realpath(T))
                        .then((T) => b(m.dirname(h), T).then(() => T))
                        .then((T) => (u.type === "file" ? B(h, T) : T))
                        .then((T) =>
                          p.realpath(m.dirname(h)).then((k) => {
                            if (k.indexOf(T) !== 0)
                              throw new Error(
                                "Refusing to write outside output directory: " +
                                  k,
                              );
                          }),
                        )
                        .then(() =>
                          u.type === "link" ||
                          (u.type === "symlink" && process.platform === "win32")
                            ? p.link(u.linkname, h)
                            : u.type === "symlink"
                              ? p.symlink(u.linkname, h)
                              : p.writeFile(h, u.data, { mode: d }),
                        )
                        .then(
                          () => u.type === "file" && p.utimes(h, y, u.mtime),
                        )
                        .then(() => u);
                }),
              )
            : i
        ),
      );
  return (
    (tr = (_, c, R) =>
      typeof _ != "string" && !Buffer.isBuffer(_)
        ? Promise.reject(new TypeError("Input file required"))
        : (typeof c == "object" && ((R = c), (c = null)),
          (R = Object.assign({ plugins: [e(), f(), s(), t()] }, R)),
          (typeof _ == "string" ? p.readFile(_) : Promise.resolve(_)).then(
            (u) => w(u, c, R),
          ))),
    tr
  );
}
var lt = xi();
const si = ht(lt),
  Di = kt({ __proto__: null, default: si }, [lt]);
export { Di as i };
//# sourceMappingURL=index-3ZIyHCQx.mjs.map
