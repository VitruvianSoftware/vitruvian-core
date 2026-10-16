import * as V from "node:fs";
import * as X from "node:path";
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
      (e._sentryDebugIds[t] = "4027f597-91c5-48f0-badc-4491d7b1b50d"),
      (e._sentryDebugIdIdentifier =
        "sentry-dbid-4027f597-91c5-48f0-badc-4491d7b1b50d"));
  } catch {}
})();
var Z = new TextDecoder(),
  o = (e, t = 0, r = e.length) => Z.decode(e.slice(t, r)),
  m = (e, t = 0, r = e.length) =>
    e.slice(t, r).reduce((i, n) => i + `0${n.toString(16)}`.slice(-2), ""),
  v = (e, t) => new DataView(e.buffer, e.byteOffset + t),
  _ = (e, t = 0) => v(e, t).getInt16(0, !0),
  T = (e, t = 0) => v(e, t).getUint16(0, !1),
  l = (e, t = 0) => v(e, t).getUint16(0, !0),
  B = (e, t = 0) => {
    const r = v(e, t);
    return r.getUint16(0, !0) + (r.getUint8(2) << 16);
  },
  J = (e, t = 0) => v(e, t).getInt32(0, !0),
  c = (e, t = 0) => v(e, t).getUint32(0, !1),
  w = (e, t = 0) => v(e, t).getUint32(0, !0),
  O = (e, t, r) => v(e, t).getBigUint64(0, !r),
  W = { readUInt16BE: T, readUInt16LE: l, readUInt32BE: c, readUInt32LE: w };
function f(e, t, r = 0, i = !1) {
  const a = `readUInt${t}${i ? "BE" : "LE"}`;
  return W[a](e, r);
}
function $(e, t) {
  if (e.length - t < 4) return;
  const r = c(e, t);
  if (!(e.length - t < r))
    return { name: o(e, 4 + t, 8 + t), offset: t, size: r };
}
function u(e, t, r) {
  for (; r < e.length;) {
    const i = $(e, r);
    if (!i) break;
    if (i.name === t) return i;
    r += i.size > 0 ? i.size : 8;
  }
}
var K = {
    validate: (e) => o(e, 0, 2) === "BM",
    calculate: (e) => ({ height: Math.abs(J(e, 22)), width: w(e, 18) }),
  },
  q = 1,
  Q = 6,
  ee = 16;
function R(e, t) {
  const r = e[t];
  return r === 0 ? 256 : r;
}
function A(e, t) {
  const r = Q + t * ee;
  return { height: R(e, r + 1), width: R(e, r) };
}
var z = {
    validate(e) {
      const t = l(e, 0),
        r = l(e, 4);
      return t !== 0 || r === 0 ? !1 : l(e, 2) === q;
    },
    calculate(e) {
      const t = l(e, 4),
        r = A(e, 0);
      if (t === 1) return r;
      const i = [];
      for (let n = 0; n < t; n += 1) i.push(A(e, n));
      return { width: r.width, height: r.height, images: i };
    },
  },
  te = 2,
  re = {
    validate(e) {
      const t = l(e, 0),
        r = l(e, 4);
      return t !== 0 || r === 0 ? !1 : l(e, 2) === te;
    },
    calculate: (e) => z.calculate(e),
  },
  ie = {
    validate: (e) => w(e, 0) === 542327876,
    calculate: (e) => ({ height: w(e, 12), width: w(e, 16) }),
  },
  ne = /^GIF8[79]a/,
  ae = {
    validate: (e) => ne.test(o(e, 0, 6)),
    calculate: (e) => ({ height: l(e, 8), width: l(e, 6) }),
  },
  se = {
    avif: "avif",
    mif1: "heif",
    msf1: "heif",
    heic: "heic",
    heix: "heic",
    hevc: "heic",
    hevx: "heic",
  },
  oe = {
    validate(e) {
      if (o(e, 4, 8) !== "ftyp") return !1;
      const r = u(e, "ftyp", 0);
      return r ? o(e, r.offset + 8, r.offset + 12) in se : !1;
    },
    calculate(e) {
      const t = u(e, "meta", 0),
        r = t && u(e, "iprp", t.offset + 12),
        i = r && u(e, "ipco", r.offset + 8);
      if (!i) throw new TypeError("Invalid HEIF, no ipco box found");
      const n = o(e, 8, 12),
        a = [];
      let s = i.offset + 8;
      for (; s < i.offset + i.size;) {
        const h = u(e, "ispe", s);
        if (!h) break;
        const g = c(e, h.offset + 12),
          P = c(e, h.offset + 16),
          E = u(e, "clap", s);
        let p = g,
          U = P;
        if (E && E.offset < i.offset + i.size) {
          const j = c(e, E.offset + 12);
          p = g - j;
        }
        (a.push({ height: U, width: p }), (s = h.offset + h.size));
      }
      if (a.length === 0) throw new TypeError("Invalid HEIF, no sizes found");
      return {
        width: a[0].width,
        height: a[0].height,
        type: n,
        ...(a.length > 1 ? { images: a } : {}),
      };
    },
  },
  ce = 8,
  he = 4,
  fe = 4,
  le = {
    ICON: 32,
    "ICN#": 32,
    "icm#": 16,
    icm4: 16,
    icm8: 16,
    "ics#": 16,
    ics4: 16,
    ics8: 16,
    is32: 16,
    s8mk: 16,
    icp4: 16,
    icl4: 32,
    icl8: 32,
    il32: 32,
    l8mk: 32,
    icp5: 32,
    ic11: 32,
    ich4: 48,
    ich8: 48,
    ih32: 48,
    h8mk: 48,
    icp6: 64,
    ic12: 32,
    it32: 128,
    t8mk: 128,
    ic07: 128,
    ic08: 256,
    ic13: 256,
    ic09: 512,
    ic14: 512,
    ic10: 1024,
  };
function de(e, t) {
  const r = t + fe;
  return [o(e, t, r), c(e, r)];
}
function ge(e) {
  const t = le[e];
  return { width: t, height: t, type: e };
}
var ue = {
    validate: (e) => o(e, 0, 4) === "icns",
    calculate(e) {
      const t = e.length,
        r = c(e, he);
      let i = ce;
      const n = [];
      for (; i < r && i < t;) {
        const a = de(e, i),
          s = ge(a[0]);
        (n.push(s), (i += a[1]));
      }
      if (n.length === 0) throw new TypeError("Invalid ICNS, no sizes found");
      return {
        width: n[0].width,
        height: n[0].height,
        ...(n.length > 1 ? { images: n } : {}),
      };
    },
  },
  ve = {
    validate: (e) => c(e, 0) === 4283432785,
    calculate: (e) => ({ height: c(e, 12), width: c(e, 8) }),
  },
  we = {
    validate(e) {
      if (o(e, 4, 8) !== "jP  ") return !1;
      const r = u(e, "ftyp", 0);
      return r ? o(e, r.offset + 8, r.offset + 12) === "jp2 " : !1;
    },
    calculate(e) {
      const t = u(e, "jp2h", 0),
        r = t && u(e, "ihdr", t.offset + 8);
      if (r) return { height: c(e, r.offset + 8), width: c(e, r.offset + 12) };
      throw new TypeError("Unsupported JPEG 2000 format");
    },
  },
  me = "45786966",
  Ee = 2,
  N = 6,
  Ie = 2,
  Te = "4d4d",
  be = "4949",
  G = 12,
  ye = 2;
function pe(e) {
  return m(e, 2, 6) === me;
}
function Se(e, t) {
  return { height: T(e, t), width: T(e, t + 2) };
}
function Ne(e, t) {
  const i = N + 8,
    n = f(e, 16, i, t);
  for (let a = 0; a < n; a++) {
    const s = i + ye + a * G,
      h = s + G;
    if (s > e.length) return;
    const g = e.slice(s, h);
    if (f(g, 16, 0, t) === 274)
      return f(g, 16, 2, t) !== 3 || f(g, 32, 4, t) !== 1
        ? void 0
        : f(g, 16, 8, t);
  }
}
function xe(e, t) {
  const r = e.slice(Ee, t),
    i = m(r, N, N + Ie),
    n = i === Te;
  if (n || i === be) return Ne(r, n);
}
function Oe(e, t) {
  if (t > e.length) throw new TypeError("Corrupt JPG, exceeded buffer limits");
}
var Pe = {
    validate: (e) => m(e, 0, 2) === "ffd8",
    calculate(e) {
      let t = e.slice(4),
        r,
        i;
      for (; t.length;) {
        const n = T(t, 0);
        if ((Oe(t, n), t[n] !== 255)) {
          t = t.slice(1);
          continue;
        }
        if (
          (pe(t) && (r = xe(t, n)),
          (i = t[n + 1]),
          i === 192 || i === 193 || i === 194)
        ) {
          const a = Se(t, n + 5);
          return r ? { height: a.height, orientation: r, width: a.width } : a;
        }
        t = t.slice(n + 2);
      }
      throw new TypeError("Invalid JPG, no size found");
    },
  },
  _e = class {
    constructor(e, t) {
      ((this.input = e),
        (this.endianness = t),
        (this.byteOffset = 2),
        (this.bitOffset = 0));
    }
    getBits(e = 1) {
      let t = 0,
        r = 0;
      for (; r < e;) {
        if (this.byteOffset >= this.input.length)
          throw new Error("Reached end of input");
        const i = this.input[this.byteOffset],
          n = 8 - this.bitOffset,
          a = Math.min(e - r, n);
        if (this.endianness === "little-endian") {
          const s = (1 << a) - 1,
            h = (i >> this.bitOffset) & s;
          t |= h << r;
        } else {
          const s = ((1 << a) - 1) << (8 - this.bitOffset - a),
            h = (i & s) >> (8 - this.bitOffset - a);
          t = (t << a) | h;
        }
        ((r += a),
          (this.bitOffset += a),
          this.bitOffset === 8 && (this.byteOffset++, (this.bitOffset = 0)));
      }
      return t;
    }
  };
function D(e, t) {
  if (t) return 8 * (1 + e.getBits(5));
  const r = e.getBits(2),
    i = [9, 13, 18, 30][r];
  return 1 + e.getBits(i);
}
function Be(e, t, r, i) {
  if (t && r === 0) return 8 * (1 + e.getBits(5));
  if (r === 0) return D(e, !1);
  const n = [1, 1.2, 4 / 3, 1.5, 16 / 9, 5 / 4, 2];
  return Math.floor(i * n[r - 1]);
}
var H = {
  validate: (e) => m(e, 0, 2) === "ff0a",
  calculate(e) {
    const t = new _e(e, "little-endian"),
      r = t.getBits(1) === 1,
      i = D(t, r),
      n = t.getBits(3);
    return { width: Be(t, r, n, i), height: i };
  },
};
function Re(e) {
  const t = u(e, "jxlc", 0);
  if (t) return e.slice(t.offset + 8, t.offset + t.size);
  const r = Ae(e);
  if (r.length > 0) return Ge(r);
}
function Ae(e) {
  const t = [];
  let r = 0;
  for (; r < e.length;) {
    const i = u(e, "jxlp", r);
    if (!i) break;
    (t.push(e.slice(i.offset + 12, i.offset + i.size)),
      (r = i.offset + i.size));
  }
  return t;
}
function Ge(e) {
  const t = e.reduce((n, a) => n + a.length, 0),
    r = new Uint8Array(t);
  let i = 0;
  for (const n of e) (r.set(n, i), (i += n.length));
  return r;
}
var Le = {
    validate: (e) => {
      if (o(e, 4, 8) !== "JXL ") return !1;
      const r = u(e, "ftyp", 0);
      return r ? o(e, r.offset + 8, r.offset + 12) === "jxl " : !1;
    },
    calculate(e) {
      const t = Re(e);
      if (t) return H.calculate(t);
      throw new Error("No codestream found in JXL container");
    },
  },
  Fe = {
    validate: (e) => {
      const t = o(e, 1, 7);
      return ["KTX 11", "KTX 20"].includes(t);
    },
    calculate: (e) => {
      const t = e[5] === 49 ? "ktx" : "ktx2",
        r = t === "ktx" ? 36 : 20;
      return { height: w(e, r + 4), width: w(e, r), type: t };
    },
  },
  Ce = `PNG\r

`,
  ze = "IHDR",
  L = "CgBI",
  De = {
    validate(e) {
      if (Ce === o(e, 1, 8)) {
        let t = o(e, 12, 16);
        if ((t === L && (t = o(e, 28, 32)), t !== ze))
          throw new TypeError("Invalid PNG");
        return !0;
      }
      return !1;
    },
    calculate(e) {
      return o(e, 12, 16) === L
        ? { height: c(e, 36), width: c(e, 32) }
        : { height: c(e, 20), width: c(e, 16) };
    },
  },
  F = {
    P1: "pbm/ascii",
    P2: "pgm/ascii",
    P3: "ppm/ascii",
    P4: "pbm",
    P5: "pgm",
    P6: "ppm",
    P7: "pam",
    PF: "pfm",
  },
  C = {
    default: (e) => {
      let t = [];
      for (; e.length > 0;) {
        const r = e.shift();
        if (r[0] !== "#") {
          t = r.split(" ");
          break;
        }
      }
      if (t.length === 2)
        return {
          height: Number.parseInt(t[1], 10),
          width: Number.parseInt(t[0], 10),
        };
      throw new TypeError("Invalid PNM");
    },
    pam: (e) => {
      const t = {};
      for (; e.length > 0;) {
        const r = e.shift();
        if (r.length > 16 || r.charCodeAt(0) > 128) continue;
        const [i, n] = r.split(" ");
        if (
          (i && n && (t[i.toLowerCase()] = Number.parseInt(n, 10)),
          t.height && t.width)
        )
          break;
      }
      if (t.height && t.width) return { height: t.height, width: t.width };
      throw new TypeError("Invalid PAM");
    },
  },
  He = {
    validate: (e) => o(e, 0, 2) in F,
    calculate(e) {
      const t = o(e, 0, 2),
        r = F[t],
        i = o(e, 3).split(/[\r\n]+/);
      return (C[r] || C.default)(i);
    },
  },
  Me = {
    validate: (e) => o(e, 0, 4) === "8BPS",
    calculate: (e) => ({ height: c(e, 14), width: c(e, 18) }),
  },
  M = /<svg\s([^>"']|"[^"]*"|'[^']*')*>/,
  I = {
    height: /\sheight=(['"])([^%]+?)\1/,
    root: M,
    viewbox: /\sviewBox=(['"])(.+?)\1/i,
    width: /\swidth=(['"])([^%]+?)\1/,
  },
  S = 2.54,
  Y = {
    in: 96,
    cm: 96 / S,
    em: 16,
    ex: 8,
    m: (96 / S) * 100,
    mm: 96 / S / 10,
    pc: 96 / 72 / 12,
    pt: 96 / 72,
    px: 1,
  },
  Ye = new RegExp(`^([0-9.]+(?:e\\d+)?)(${Object.keys(Y).join("|")})?$`);
function b(e) {
  const t = Ye.exec(e);
  if (t) return Math.round(Number(t[1]) * (Y[t[2]] || 1));
}
function ke(e) {
  const t = e.split(" ");
  return { height: b(t[3]), width: b(t[2]) };
}
function Ue(e) {
  const t = e.match(I.width),
    r = e.match(I.height),
    i = e.match(I.viewbox);
  return { height: r && b(r[2]), viewbox: i && ke(i[2]), width: t && b(t[2]) };
}
function je(e) {
  return { height: e.height, width: e.width };
}
function Ve(e, t) {
  const r = t.width / t.height;
  return e.width
    ? { height: Math.floor(e.width / r), width: e.width }
    : e.height
      ? { height: e.height, width: Math.floor(e.height * r) }
      : { height: t.height, width: t.width };
}
var Xe = {
    validate: (e) => M.test(o(e, 0, 1e3)),
    calculate(e) {
      const t = o(e).match(I.root);
      if (t) {
        const r = Ue(t[0]);
        if (r.width && r.height) return je(r);
        if (r.viewbox) return Ve(r, r.viewbox);
      }
      throw new TypeError("Invalid SVG");
    },
  },
  Ze = {
    validate(e) {
      return l(e, 0) === 0 && l(e, 4) === 0;
    },
    calculate(e) {
      return { height: l(e, 14), width: l(e, 12) };
    },
  },
  d = {
    TAG: { WIDTH: 256, HEIGHT: 257, COMPRESSION: 259 },
    TYPE: { SHORT: 3, LONG: 4, LONG8: 16 },
    ENTRY_SIZE: { STANDARD: 12, BIG: 20 },
    COUNT_SIZE: { STANDARD: 2, BIG: 8 },
  };
function Je(e, { isBigEndian: t, isBigTiff: r }) {
  const i = r ? Number(O(e, 8, t)) : f(e, 32, 4, t),
    n = r ? d.COUNT_SIZE.BIG : d.COUNT_SIZE.STANDARD;
  return e.slice(i + n);
}
function We(e, t, r, i) {
  switch (t) {
    case d.TYPE.SHORT:
      return f(e, 16, r, i);
    case d.TYPE.LONG:
      return f(e, 32, r, i);
    case d.TYPE.LONG8: {
      const n = Number(O(e, r, i));
      if (n > Number.MAX_SAFE_INTEGER) throw new TypeError("Value too large");
      return n;
    }
    default:
      return 0;
  }
}
function $e(e, t) {
  const r = t ? d.ENTRY_SIZE.BIG : d.ENTRY_SIZE.STANDARD;
  if (e.length > r) return e.slice(r);
}
function Ke(e, { isBigEndian: t, isBigTiff: r }) {
  const i = {};
  let n = e;
  for (; n?.length;) {
    const a = f(n, 16, 0, t),
      s = f(n, 16, 2, t),
      h = r ? Number(O(n, 4, t)) : f(n, 32, 4, t);
    if (a === 0) break;
    if (
      h === 1 &&
      (s === d.TYPE.SHORT || s === d.TYPE.LONG || (r && s === d.TYPE.LONG8))
    ) {
      const g = r ? 12 : 8;
      i[a] = We(n, s, g, t);
    }
    n = $e(n, r);
  }
  return i;
}
function qe(e) {
  const t = o(e, 0, 2),
    r = f(e, 16, 2, t === "MM");
  return { isBigEndian: t === "MM", isBigTiff: r === 43 };
}
function Qe(e, t) {
  const r = f(e, 16, 4, t),
    i = f(e, 16, 6, t);
  if (r !== 8 || i !== 0) throw new TypeError("Invalid BigTIFF header");
}
var et = new Set(["49492a00", "4d4d002a", "49492b00", "4d4d002b"]),
  tt = {
    validate: (e) => {
      const t = m(e, 0, 4);
      return et.has(t);
    },
    calculate(e) {
      const t = qe(e);
      t.isBigTiff && Qe(e, t.isBigEndian);
      const r = Je(e, t),
        i = Ke(r, t),
        n = {
          height: i[d.TAG.HEIGHT],
          width: i[d.TAG.WIDTH],
          type: t.isBigTiff ? "bigtiff" : "tiff",
        };
      if (
        (i[d.TAG.COMPRESSION] && (n.compression = i[d.TAG.COMPRESSION]),
        !n.width || !n.height)
      )
        throw new TypeError("Invalid Tiff. Missing tags");
      return n;
    },
  };
function rt(e) {
  return { height: 1 + B(e, 7), width: 1 + B(e, 4) };
}
function it(e) {
  return {
    height: 1 + (((e[4] & 15) << 10) | (e[3] << 2) | ((e[2] & 192) >> 6)),
    width: 1 + (((e[2] & 63) << 8) | e[1]),
  };
}
function nt(e) {
  return { height: _(e, 8) & 16383, width: _(e, 6) & 16383 };
}
var at = {
    validate(e) {
      const t = o(e, 0, 4) === "RIFF",
        r = o(e, 8, 12) === "WEBP",
        i = o(e, 12, 15) === "VP8";
      return t && r && i;
    },
    calculate(e) {
      const t = o(e, 12, 16),
        r = e.slice(20, 30);
      if (t === "VP8X") {
        const n = r[0],
          a = (n & 192) === 0,
          s = (n & 1) === 0;
        if (a && s) return rt(r);
        throw new TypeError("Invalid WebP");
      }
      if (t === "VP8 " && r[0] !== 47) return nt(r);
      const i = m(r, 3, 6);
      if (t === "VP8L" && i !== "9d012a") return it(r);
      throw new TypeError("Invalid WebP");
    },
  },
  y = new Map([
    ["bmp", K],
    ["cur", re],
    ["dds", ie],
    ["gif", ae],
    ["heif", oe],
    ["icns", ue],
    ["ico", z],
    ["j2c", ve],
    ["jp2", we],
    ["jpg", Pe],
    ["jxl", Le],
    ["jxl-stream", H],
    ["ktx", Fe],
    ["png", De],
    ["pnm", He],
    ["psd", Me],
    ["svg", Xe],
    ["tga", Ze],
    ["tiff", tt],
    ["webp", at],
  ]),
  st = Array.from(y.keys()),
  ot = new Map([
    [0, "heif"],
    [56, "psd"],
    [66, "bmp"],
    [68, "dds"],
    [71, "gif"],
    [73, "tiff"],
    [77, "tiff"],
    [82, "webp"],
    [105, "icns"],
    [137, "png"],
    [255, "jpg"],
  ]);
function ct(e) {
  const t = e[0],
    r = ot.get(t);
  return r && y.get(r).validate(e) ? r : st.find((i) => y.get(i).validate(e));
}
var ht = { disabledTypes: [] };
function ft(e) {
  const t = ct(e);
  if (typeof t < "u") {
    if (ht.disabledTypes.indexOf(t) > -1)
      throw new TypeError(`disabled file type: ${t}`);
    const r = y.get(t).calculate(e);
    if (r !== void 0) {
      if (((r.type = r.type ?? t), r.images && r.images.length > 1)) {
        const i = r.images.reduce(
          (n, a) => (a.width * a.height > n.width * n.height ? a : n),
          r.images[0],
        );
        ((r.width = i.width), (r.height = i.height));
      }
      return r;
    }
  }
  throw new TypeError(`unsupported file type: ${t}`);
}
var lt = 512 * 1024,
  x = [],
  dt = 100,
  k = async () => {
    const t = x
      .splice(0, dt)
      .map(async ({ filePath: r, resolve: i, reject: n }) => {
        let a;
        try {
          a = await V.promises.open(X.resolve(r), "r");
        } catch (s) {
          return n(s);
        }
        try {
          const { size: s } = await a.stat();
          if (s <= 0) throw new Error("Empty file");
          const h = Math.min(s, lt),
            g = new Uint8Array(h);
          (await a.read(g, 0, h, 0), i(ft(g)));
        } catch (s) {
          n(s);
        } finally {
          await a.close();
        }
      });
    (await Promise.allSettled(t), x.length && setTimeout(k, 100));
  },
  gt = async (e) =>
    new Promise((t, r) => {
      (x.push({ filePath: e, resolve: t, reject: r }), k());
    });
export { gt as imageSizeFromFile };
//# sourceMappingURL=fromFile-Bd43zJBF.mjs.map
