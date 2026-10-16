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
      (e._sentryDebugIds[t] = "73f4d2f0-ea3b-4f4d-a00e-dc6c67b0bbe5"),
      (e._sentryDebugIdIdentifier =
        "sentry-dbid-73f4d2f0-ea3b-4f4d-a00e-dc6c67b0bbe5"));
  } catch {}
})();
let Bt = class {
  constructor(t) {
    if (Dn(t)) throw new Error("DataView: Passed buffer type is unsupported.");
    ((this.buffer = t), (this.byteLength = this.buffer.length));
  }
  getUint8(t) {
    return this.buffer.readUInt8(t);
  }
  getUint16(t, n) {
    return n ? this.buffer.readUInt16LE(t) : this.buffer.readUInt16BE(t);
  }
  getUint32(t, n) {
    return n ? this.buffer.readUInt32LE(t) : this.buffer.readUInt32BE(t);
  }
  getInt32(t, n) {
    return n ? this.buffer.readInt32LE(t) : this.buffer.readInt32BE(t);
  }
};
function Dn(e) {
  return (
    typeof e != "object" ||
    e.length === void 0 ||
    e.readUInt8 === void 0 ||
    e.readUInt16LE === void 0 ||
    e.readUInt16BE === void 0 ||
    e.readUInt32LE === void 0 ||
    e.readUInt32BE === void 0 ||
    e.readInt32LE === void 0 ||
    e.readInt32BE === void 0
  );
}
function je(e, t, n) {
  try {
    return new DataView(e, t, n);
  } catch {
    return new Bt(e, t, n);
  }
}
function E(e, t, n) {
  const r = [];
  for (let i = 0; i < n && t + i < e.byteLength; i++) r.push(e.getUint8(t + i));
  return W(r);
}
function Y(e, t) {
  const n = [];
  let r = 0;
  for (; t + r < e.byteLength;) {
    const i = e.getUint8(t + r);
    if (i === 0) break;
    (n.push(i), r++);
  }
  return W(n);
}
function Un(e, t, n) {
  const r = [];
  for (let i = 0; i < n && t + i < e.byteLength; i += 2)
    r.push(e.getUint16(t + i));
  return (r[r.length - 1] === 0 && r.pop(), W(r));
}
function Gt(e, t) {
  const n = e.getUint8(t),
    r = E(e, t + 1, n);
  return [n, r];
}
function W(e) {
  return e.map((t) => String.fromCharCode(t)).join("");
}
function x() {
  for (let e = 1; e < arguments.length; e++)
    for (const t in arguments[e]) arguments[0][t] = arguments[e][t];
  return arguments[0];
}
function kt(e, t, n) {
  let r = !1;
  Object.defineProperty(e, t, {
    get() {
      return (
        r ||
          ((r = !0),
          Object.defineProperty(e, t, {
            configurable: !0,
            enumerable: !0,
            value: n.apply(e),
            writable: !0,
          })),
        e[t]
      );
    },
    configurable: !0,
    enumerable: !0,
  });
}
function Zt(e) {
  if (typeof btoa < "u")
    return btoa(
      typeof e == "string"
        ? e
        : Array.prototype.reduce.call(
            new Uint8Array(e),
            (t, n) => t + String.fromCharCode(n),
            "",
          ),
    );
  if (!(typeof Buffer > "u"))
    return typeof Buffer.from < "u"
      ? Buffer.from(e).toString("base64")
      : new Buffer(e).toString("base64");
}
function Ln(e) {
  const t = e.substring(e.indexOf(",") + 1);
  if (e.indexOf(";base64") !== -1)
    return typeof atob < "u"
      ? Uint8Array.from(atob(t), (r) => r.charCodeAt(0)).buffer
      : typeof Buffer > "u"
        ? void 0
        : typeof Buffer.from < "u"
          ? Buffer.from(t, "base64")
          : new Buffer(t, "base64");
  const n = decodeURIComponent(t);
  return typeof Buffer < "u"
    ? typeof Buffer.from < "u"
      ? Buffer.from(n)
      : new Buffer(n)
    : Uint8Array.from(n, (r) => r.charCodeAt(0)).buffer;
}
function Mn(e, t, n) {
  return Ht(n, t - e.length) + e;
}
function Bn(e, t) {
  return (
    parseInt(e.replace(".", ""), t) /
    Math.pow(t, (e.split(".")[1] || "").length)
  );
}
function Ht(e, t) {
  return new Array(t + 1).join(e);
}
const ue = void 0,
  $t = 0;
function Xt(e, t, n, r = "string") {
  if (t === $t && typeof DecompressionStream == "function") {
    const i = new DecompressionStream("deflate"),
      o = new Blob([e]).stream().pipeThrough(i);
    return r === "dataview"
      ? new Response(o).arrayBuffer().then((s) => new DataView(s))
      : new Response(o).arrayBuffer().then((s) => new TextDecoder(n).decode(s));
  }
  return t !== void 0 ? Promise.reject(`Unknown compression method ${t}.`) : e;
}
const Je = {
  USE_FILE: !0,
  USE_JFIF: !0,
  USE_PNG_FILE: !0,
  USE_EXIF: !0,
  USE_IPTC: !0,
  USE_XMP: !0,
  USE_ICC: !0,
  USE_MPF: !0,
  USE_PHOTOSHOP: !0,
  USE_THUMBNAIL: !0,
  USE_TIFF: !0,
  USE_JPEG: !0,
  USE_PNG: !0,
  USE_HEIC: !0,
  USE_AVIF: !0,
  USE_WEBP: !0,
  USE_GIF: !0,
  USE_MAKER_NOTES: !0,
};
function h(e) {
  return e.map((t) => String.fromCharCode(t)).join("");
}
function Ce(e) {
  if (e.length >= 8) {
    const t = h(e.slice(0, 8));
    if (t === "ASCII\0\0\0") return h(e.slice(8));
    if (t === "JIS\0\0\0\0\0") return "[JIS encoded text]";
    if (t === "UNICODE\0") return "[Unicode encoded text]";
    if (t === "\0\0\0\0\0\0\0\0") return "[Undefined encoding]";
  }
  return "Undefined";
}
function ce(e) {
  return e[0][0] / e[0][1] + e[1][0] / e[1][1] / 60 + e[2][0] / e[2][1] / 3600;
}
const Pe = 18761,
  be = 19789,
  Z = { BIG_ENDIAN: be, LITTLE_ENDIAN: Pe, getByteOrder: Gn };
function Gn(e, t) {
  if (e.getUint16(t) === Pe) return Pe;
  if (e.getUint16(t) === be) return be;
  throw new Error("Illegal byte order value. Faulty image.");
}
const ve = { isTiffFile: kn, findTiffOffsets: Hn };
function kn(e) {
  return !!e && e.byteLength >= 4 && Zn(e);
}
function Zn(e) {
  const r = e.getUint16(0) === Z.LITTLE_ENDIAN;
  return e.getUint16(2, r) === 42;
}
function Hn() {
  return { hasAppMarkers: !0, tiffHeaderOffset: 0 };
}
const qe = { isJpegFile: nr, findJpegOffsets: rr },
  $n = 2,
  Xn = 65496,
  we = 2,
  P = 4,
  _ = 2,
  Yn = 2,
  Kn = 10,
  zn = 18,
  Qe = 33,
  Ve = 79,
  et = 18,
  Wn = 8,
  ye = "ICC_PROFILE\0",
  Yt = P + ye.length,
  jn = Yt + 1,
  tt = "MPF\0",
  Kt = 65472,
  zt = 65474,
  Jn = 65476,
  vn = 65499,
  qn = 65501,
  wn = 65498,
  Wt = 65504,
  He = 65505,
  jt = 65506,
  Qn = 65517,
  Vn = 65519,
  er = 65534,
  tr = 65535,
  nt = "JFIF",
  rt = "Exif",
  it = "http://ns.adobe.com/xap/1.0/\0",
  ot = "http://ns.adobe.com/xmp/extension/\0",
  st = "Photoshop 3.0";
function nr(e) {
  return !!e && e.byteLength >= $n && e.getUint16(0) === Xn;
}
function rr(e) {
  let t = we,
    n,
    r,
    i,
    o,
    s,
    u,
    f,
    l,
    a;
  for (; t + P + 5 <= e.byteLength;) {
    if (ir(e, t)) ((n = e.getUint16(t + _)), (r = t + _));
    else if (or(e, t)) ((n = e.getUint16(t + _)), (i = t + _));
    else if (cr(e, t)) ((n = e.getUint16(t + _)), (o = t + Yn));
    else if (fr(e, t)) ((n = e.getUint16(t + _)), (s = t + Kn));
    else if (ar(e, t))
      (f || (f = []), (n = e.getUint16(t + _)), f.push(gr(t, n)));
    else if (dr(e, t))
      (f || (f = []), (n = e.getUint16(t + _)), f.push(mr(t, n)));
    else if (Er(e, t)) ((n = e.getUint16(t + _)), (u = t + zn));
    else if (sr(e, t)) {
      n = e.getUint16(t + _);
      const p = t + et,
        g = n - (et - _),
        S = e.getUint8(t + Yt),
        F = e.getUint8(t + jn);
      (l || (l = []),
        l.push({ offset: p, length: g, chunkNumber: S, chunksTotal: F }));
    } else if (ur(e, t)) ((n = e.getUint16(t + _)), (a = t + Wn));
    else if (Sr(e, t)) n = e.getUint16(t + _);
    else if (xr(e, t)) {
      t++;
      continue;
    } else break;
    t += _ + n;
  }
  return {
    hasAppMarkers: t > we,
    fileDataOffset: r || i,
    jfifDataOffset: o,
    tiffHeaderOffset: s,
    iptcDataOffset: u,
    xmpChunks: f,
    iccChunks: l,
    mpfDataOffset: a,
  };
}
function ir(e, t) {
  return e.getUint16(t) === Kt;
}
function or(e, t) {
  return e.getUint16(t) === zt;
}
function sr(e, t) {
  const n = ye.length;
  return e.getUint16(t) === jt && E(e, t + P, n) === ye;
}
function ur(e, t) {
  const n = tt.length;
  return e.getUint16(t) === jt && E(e, t + P, n) === tt;
}
function cr(e, t) {
  const n = nt.length;
  return (
    e.getUint16(t) === Wt &&
    E(e, t + P, n) === nt &&
    e.getUint8(t + P + n) === 0
  );
}
function fr(e, t) {
  const n = rt.length;
  return (
    e.getUint16(t) === He &&
    E(e, t + P, n) === rt &&
    e.getUint8(t + P + n) === 0
  );
}
function ar(e, t) {
  return e.getUint16(t) === He && lr(e, t);
}
function lr(e, t) {
  const n = it.length;
  return E(e, t + P, n) === it;
}
function dr(e, t) {
  return e.getUint16(t) === He && pr(e, t);
}
function pr(e, t) {
  const n = ot.length;
  return E(e, t + P, n) === ot;
}
function gr(e, t) {
  return { dataOffset: e + Qe, length: t - (Qe - _) };
}
function mr(e, t) {
  return { dataOffset: e + Ve, length: t - (Ve - _) };
}
function Er(e, t) {
  const n = st.length;
  return (
    e.getUint16(t) === Qn &&
    E(e, t + P, n) === st &&
    e.getUint8(t + P + n) === 0
  );
}
function Sr(e, t) {
  const n = e.getUint16(t);
  return (
    (n >= Wt && n <= Vn) ||
    n === er ||
    n === Kt ||
    n === zt ||
    n === Jn ||
    n === vn ||
    n === qn ||
    n === wn
  );
}
function xr(e, t) {
  return e.getUint16(t) === tr;
}
const ut = { isPngFile: Tr, findPngOffsets: Fr },
  Ne = `PNG\r

`,
  fe = 4,
  y = 4,
  K = 0,
  B = fe,
  T = fe + y,
  Oe = "XML:com.adobe.xmp\0",
  $e = "tEXt",
  k = "iTXt",
  le = "zTXt",
  Jt = "pHYs",
  vt = "tIME",
  Ir = "eXIf",
  hr = "iCCP";
function Tr(e) {
  return !!e && E(e, 0, Ne.length) === Ne;
}
function Fr(e, t) {
  const r = { hasAppMarkers: !1 };
  let i = Ne.length;
  for (; i + fe + y <= e.byteLength;) {
    if (_r(e, i)) ((r.hasAppMarkers = !0), (r.pngHeaderOffset = i + T));
    else if (Ar(e, i)) {
      const o = Nr(e, i);
      o !== void 0 &&
        ((r.hasAppMarkers = !0),
        (r.xmpChunks = [
          { dataOffset: o, length: e.getUint32(i + K) - (o - (i + T)) },
        ]));
    } else if (Cr(e, i, t)) {
      r.hasAppMarkers = !0;
      const o = E(e, i + B, y);
      (r.pngTextChunks || (r.pngTextChunks = []),
        r.pngTextChunks.push({
          length: e.getUint32(i + K),
          type: o,
          offset: i + T,
        }));
    } else if (Pr(e, i)) ((r.hasAppMarkers = !0), (r.tiffHeaderOffset = i + T));
    else if (t && br(e, i)) {
      r.hasAppMarkers = !0;
      const o = e.getUint32(i + K),
        s = i + T,
        {
          profileName: u,
          compressionMethod: f,
          compressedProfileOffset: l,
        } = Or(e, s);
      (r.iccChunks || (r.iccChunks = []),
        r.iccChunks.push({
          offset: l,
          length: o - (l - s),
          chunkNumber: 1,
          chunksTotal: 1,
          profileName: u,
          compressionMethod: f,
        }));
    } else
      yr(e, i) &&
        ((r.hasAppMarkers = !0),
        r.pngChunkOffsets || (r.pngChunkOffsets = []),
        r.pngChunkOffsets.push(i + K));
    i += e.getUint32(i + K) + fe + y + 4;
  }
  return r;
}
function _r(e, t) {
  return E(e, t + B, y) === "IHDR";
}
function Ar(e, t) {
  return E(e, t + B, y) === k && E(e, t + T, Oe.length) === Oe;
}
function Cr(e, t, n) {
  const r = E(e, t + B, y);
  return r === $e || r === k || (r === le && n);
}
function Pr(e, t) {
  return E(e, t + B, y) === Ir;
}
function br(e, t) {
  return E(e, t + B, y) === hr;
}
function yr(e, t) {
  const n = [Jt, vt],
    r = E(e, t + B, y);
  return n.includes(r);
}
function Nr(e, t) {
  t += T + Oe.length + 1 + 1;
  let i = 0;
  for (; i < 2 && t < e.byteLength;) (e.getUint8(t) === 0 && i++, t++);
  if (!(i < 2)) return t;
}
function Or(e, t) {
  const i = Y(e, t);
  t += i.length + 1;
  const o = e.getUint8(t);
  return (
    (t += 1),
    { profileName: i, compressionMethod: o, compressedProfileOffset: t }
  );
}
function Rr(e, t) {
  return e.getUint32(t + 4);
}
function Dr(e, t, n, r) {
  const { offsets: o, sizes: s } = Ur(t, n + 3),
    u = e.getUint8(o.offsetSize) >> 4;
  s.item.extent.extentOffset = u;
  const f = e.getUint8(o.lengthSize) & 15;
  s.item.extent.extentLength = f;
  const l = e.getUint8(o.baseOffsetSize) >> 4;
  s.item.baseOffset = l;
  const a = Lr(e, o.indexSize, t);
  s.item.extent.extentIndex = a !== void 0 ? a : 0;
  const p = Mr(e, o.itemCount, t);
  return { type: "iloc", items: Br(e, t, o, s, u, f, a, p), length: r };
}
function Ur(e, t) {
  const n = { item: { dataReferenceIndex: 2, extentCount: 2, extent: {} } };
  (e < 2
    ? ((n.itemCount = 2), (n.item.itemId = 2))
    : e === 2 && ((n.itemCount = 4), (n.item.itemId = 4)),
    e === 1 || e === 2
      ? (n.item.constructionMethod = 2)
      : (n.item.constructionMethod = 0));
  const r = {
    offsetSize: t,
    lengthSize: t,
    baseOffsetSize: t + 1,
    indexSize: t + 1,
  };
  return (
    (r.itemCount = t + 2),
    (r.items = r.itemCount + n.itemCount),
    (r.item = { itemId: 0 }),
    (r.item.constructionMethod = r.item.itemId + n.item.itemId),
    (r.item.dataReferenceIndex =
      r.item.constructionMethod + n.item.constructionMethod),
    { offsets: r, sizes: n }
  );
}
function Lr(e, t, n) {
  if (n === 1 || n === 2) return e.getUint8(t) & 15;
}
function Mr(e, t, n) {
  if (n < 2) return e.getUint16(t);
  if (n === 2) return e.getUint32(t);
}
function Br(e, t, n, r, i, o, s, u) {
  if (u === void 0) return [];
  const f = [];
  let l = n.items;
  for (let a = 0; a < u; a++) {
    const p = { extents: [] };
    ((p.itemId = Gr(e, l, t)),
      (l += r.item.itemId),
      (p.constructionMethod =
        t === 1 || t === 2 ? e.getUint16(l) & 15 : void 0),
      (l += r.item.constructionMethod),
      (p.dataReferenceIndex = e.getUint16(l)),
      (l += r.item.dataReferenceIndex),
      (p.baseOffset = oe(e, l, r.item.baseOffset)),
      (l += r.item.baseOffset),
      (p.extentCount = e.getUint16(l)),
      (l += r.item.extentCount));
    for (let g = 0; g < p.extentCount; g++) {
      const S = {};
      ((S.extentIndex = kr(e, t, l, s)),
        (l += r.item.extent.extentIndex),
        (S.extentOffset = oe(e, l, i)),
        (l += r.item.extent.extentOffset),
        (S.extentLength = oe(e, l, o)),
        (l += r.item.extent.extentLength),
        p.extents.push(S));
    }
    f.push(p);
  }
  return f;
}
function Gr(e, t, n) {
  if (n < 2) return e.getUint16(t);
  if (n === 2) return e.getUint32(t);
}
function kr(e, t, n, r) {
  if ((t === 1 || t === 2) && r > 0) return oe(e, n, r);
}
function oe(e, t, n) {
  return n === 4
    ? e.getUint32(t)
    : n === 8
      ? (console.warn(
          "This file uses an 8-bit offset which is currently not supported by ExifReader. Contact the maintainer to get it fixed.",
        ),
        Rr(e, t))
      : 0;
}
const Zr = 1718909296,
  Hr = 1768977008,
  $r = 1835365473,
  Xr = 1768714083,
  Yr = 1768517222,
  Kr = 1768842853,
  zr = 1768973167,
  Wr = 1668246642,
  qt = 1165519206,
  Xe = 1835625829,
  jr = 1970432288;
function de(e, t) {
  const { length: o, contentOffset: s } = Jr(e, t);
  if (o < 8) return;
  const u = e.getUint32(t + 4);
  if (u === Zr) return oi(e, s, o);
  if (u === Hr) return si(e, t, s, o);
  if (u === zr) return ui(e, t, s, o);
  if (u === Wr) return ci(e, s, o);
  const f = e.getUint8(s);
  return u === $r
    ? ai(e, t, s + 1, o)
    : u === Xr
      ? Dr(e, f, s + 1, o)
      : u === Yr
        ? li(e, t, f, s + 1, o)
        : u === Kr
          ? pi(e, t, f, s + 1, o)
          : { type: void 0, length: o };
}
function Jr(e, t) {
  const s = e.getUint32(t);
  return vr(s)
    ? { length: e.byteLength - t, contentOffset: t + 4 + 4 }
    : qr(s) && wr(e, t)
      ? { length: e.getUint32(t + 12), contentOffset: t + 4 + 4 + 8 }
      : { length: s, contentOffset: t + 4 + 4 };
}
function vr(e) {
  return e === 0;
}
function qr(e) {
  return e === 1;
}
function wr(e, t) {
  return e.getUint32(t + 8) === 0;
}
function wt(e) {
  {
    const t = {},
      n = Qr(e);
    return n
      ? ((t.tiffHeaderOffset = Vr(e, n)),
        (t.xmpChunks = ni(n)),
        (t.iccChunks = ii(n)),
        (t.hasAppMarkers =
          t.tiffHeaderOffset !== void 0 ||
          t.xmpChunks !== void 0 ||
          t.iccChunks !== void 0),
        t)
      : { hasAppMarkers: !1 };
  }
}
function Qr(e) {
  let r = 0;
  for (; r + 4 + 4 <= e.byteLength;) {
    const i = de(e, r);
    if (i === void 0) break;
    if (i.type === "meta") return i;
    r += i.length;
  }
}
function Vr(e, t) {
  try {
    const n = ei(t).itemId,
      r = Re(t, n),
      i = r.baseOffset + r.extents[0].extentOffset;
    return ti(e, i);
  } catch {
    return;
  }
}
function ei(e) {
  return e.subBoxes
    .find((t) => t.type === "iinf")
    .itemInfos.find((t) => t.itemType === qt);
}
function Re(e, t) {
  return e.subBoxes
    .find((n) => n.type === "iloc")
    .items.find((n) => n.itemId === t);
}
function ti(e, t) {
  return t + 4 + e.getUint32(t);
}
function ni(e) {
  try {
    const t = ri(e).itemId,
      n = Re(e, t),
      r = Re(e, t).extents[0];
    return [
      { dataOffset: n.baseOffset + r.extentOffset, length: r.extentLength },
    ];
  } catch {
    return;
  }
}
function ri(e) {
  return e.subBoxes
    .find((t) => t.type === "iinf")
    .itemInfos.find(
      (t) => t.itemType === Xe && t.contentType === "application/rdf+xml",
    );
}
function ii(e) {
  try {
    const t = e.subBoxes
      .find((n) => n.type === "iprp")
      .subBoxes.find((n) => n.type === "ipco")
      .properties.find((n) => n.type === "colr").icc;
    if (t) return [t];
  } catch {}
}
function oi(e, t, n) {
  return { type: "ftyp", majorBrand: E(e, t, 4), length: n };
}
function si(e, t, n, r) {
  return { type: "iprp", subBoxes: pe(e, n, r - (n - t)), length: r };
}
function ui(e, t, n, r) {
  return { type: "ipco", properties: pe(e, n, r - (n - t)), length: r };
}
function ci(e, t, n) {
  return { type: "colr", icc: fi(e, t), length: n };
}
function fi(e, t) {
  const r = E(e, t, 4);
  if (!(r !== "prof" && r !== "rICC"))
    return {
      offset: t + 4,
      length: e.getUint32(t + 4),
      chunkNumber: 1,
      chunksTotal: 1,
    };
}
function ai(e, t, n, r) {
  return { type: "meta", subBoxes: pe(e, n + 3, r - (n + 3 - t)), length: r };
}
function pe(e, t, n) {
  const r = [qt, Xe],
    i = [];
  let o = t;
  for (; o < t + n;) {
    const s = de(e, o);
    if (s === void 0) break;
    (s.type !== void 0 &&
      (s.itemType === void 0 || r.indexOf(s.itemType) !== -1) &&
      i.push(s),
      (o += s.length));
  }
  return i;
}
function li(e, t, n, r, i) {
  const { offsets: o } = di(n, r);
  return {
    type: "iinf",
    itemInfos: pe(e, o.itemInfos, i - (o.itemInfos - t)),
    length: i,
  };
}
function di(e, t) {
  const r = { entryCount: t + 3 },
    i = {};
  return (
    e === 0 ? (i.entryCount = 2) : (i.entryCount = 4),
    (r.itemInfos = r.entryCount + i.entryCount),
    { offsets: r }
  );
}
function pi(e, t, n, r, i) {
  r += 3;
  const s = { type: "infe", length: i };
  return (
    (n === 0 || n === 1) &&
      ((s.itemId = e.getUint16(r)),
      (r += 2),
      (s.itemProtectionIndex = e.getUint16(r)),
      (r += 2),
      (s.itemName = Y(e, r)),
      (r += s.itemName.length + 1)),
    n >= 2 &&
      (n === 2
        ? ((s.itemId = e.getUint16(r)), (r += 2))
        : n === 3 && ((s.itemId = e.getUint32(r)), (r += 4)),
      (s.itemProtectionIndex = e.getUint16(r)),
      (r += 2),
      (s.itemType = e.getUint32(r)),
      (r += 4),
      (s.itemName = Y(e, r)),
      (r += s.itemName.length + 1),
      s.itemType === Xe
        ? ((s.contentType = Y(e, r)),
          (r += s.contentType.length + 1),
          t + i > r &&
            ((s.contentEncoding = Y(e, r)),
            (r += s.contentEncoding.length + 1)))
        : s.itemType === jr &&
          ((s.itemUri = Y(e, r)), (r += s.itemUri.length + 1))),
    s
  );
}
const ct = { isHeicFile: gi, findHeicOffsets: mi };
function gi(e) {
  if (!e) return !1;
  const t = [
    "heic",
    "heix",
    "hevc",
    "hevx",
    "heim",
    "heis",
    "hevm",
    "hevs",
    "mif1",
  ];
  try {
    const n = de(e, 0);
    return n && t.indexOf(n.majorBrand) !== -1;
  } catch {
    return !1;
  }
}
function mi(e) {
  return wt(e);
}
const ft = { isAvifFile: Ei, findAvifOffsets: Si };
function Ei(e) {
  if (!e) return !1;
  try {
    const t = de(e, 0);
    return t && t.majorBrand === "avif";
  } catch {
    return !1;
  }
}
function Si(e) {
  return wt(e);
}
const at = { isWebpFile: xi, findOffsets: Ii };
function xi(e) {
  const n = "RIFF",
    i = "WEBP";
  return !!e && E(e, 0, n.length) === n && E(e, 8, i.length) === i;
}
function Ii(e) {
  const r = "Exif\0\0";
  let o = 12,
    s = !1,
    u,
    f,
    l,
    a;
  for (; o + 8 < e.byteLength;) {
    const p = E(e, o, 4),
      g = e.getUint32(o + 4, !0);
    (p === "EXIF"
      ? ((s = !0),
        E(e, o + 8, r.length) === r ? (u = o + 8 + r.length) : (u = o + 8))
      : p === "XMP "
        ? ((s = !0), (f = [{ dataOffset: o + 8, length: g }]))
        : p === "ICCP"
          ? ((s = !0),
            (l = [
              { offset: o + 8, length: g, chunkNumber: 1, chunksTotal: 1 },
            ]))
          : p === "VP8X" && ((s = !0), (a = o + 8)),
      (o += 8 + (g % 2 === 0 ? g : g + 1)));
  }
  return {
    hasAppMarkers: s,
    tiffHeaderOffset: u,
    xmpChunks: f,
    iccChunks: l,
    vp8xChunkOffset: a,
  };
}
const lt = { isGifFile: Fi, findOffsets: _i },
  hi = 6,
  Ti = ["GIF87a", "GIF89a"];
function Fi(e) {
  return !!e && Ti.includes(E(e, 0, hi));
}
function _i() {
  return { gifHeaderOffset: 0 };
}
const dt = { isXMLFile: Ai, findOffsets: Ci },
  Qt = 0,
  pt = "<?xpacket begin";
function Ai(e) {
  return !!e && E(e, Qt, pt.length) === pt;
}
function Ci(e) {
  const t = [];
  return (t.push({ dataOffset: Qt, length: e.byteLength }), { xmpChunks: t });
}
const Pi = { parseAppMarkers: bi };
function bi(e, t) {
  if (ve.isTiffFile(e)) return U(ve.findTiffOffsets(), "tiff", "TIFF");
  if (qe.isJpegFile(e)) return U(qe.findJpegOffsets(e), "jpeg", "JPEG");
  if (ut.isPngFile(e)) return U(ut.findPngOffsets(e, t), "png", "PNG");
  if (ct.isHeicFile(e)) return U(ct.findHeicOffsets(e), "heic", "HEIC");
  if (ft.isAvifFile(e)) return U(ft.findAvifOffsets(e), "avif", "AVIF");
  if (at.isWebpFile(e)) return U(at.findOffsets(e), "webp", "WebP");
  if (lt.isGifFile(e)) return U(lt.findOffsets(e), "gif", "GIF");
  if (dt.isXMLFile(e)) return U(dt.findOffsets(e), "xml", "XML");
  throw new Error("Invalid image format");
}
function U(e, t, n) {
  return x({}, e, { fileType: { value: t, description: n } });
}
const m = {
    ApertureValue: (e) => Math.pow(Math.sqrt(2), e[0] / e[1]).toFixed(2),
    ColorSpace(e) {
      return e === 1 ? "sRGB" : e === 65535 ? "Uncalibrated" : "Unknown";
    },
    ComponentsConfiguration(e) {
      return e
        .map((t) => {
          if (t === 49) return "Y";
          if (t === 50) return "Cb";
          if (t === 51) return "Cr";
          if (t === 52) return "R";
          if (t === 53) return "G";
          if (t === 54) return "B";
        })
        .join("");
    },
    Contrast(e) {
      return e === 0
        ? "Normal"
        : e === 1
          ? "Soft"
          : e === 2
            ? "Hard"
            : "Unknown";
    },
    CustomRendered(e) {
      return e === 0
        ? "Normal process"
        : e === 1
          ? "Custom process"
          : "Unknown";
    },
    ExposureMode(e) {
      return e === 0
        ? "Auto exposure"
        : e === 1
          ? "Manual exposure"
          : e === 2
            ? "Auto bracket"
            : "Unknown";
    },
    ExposureProgram(e) {
      return e === 0
        ? "Undefined"
        : e === 1
          ? "Manual"
          : e === 2
            ? "Normal program"
            : e === 3
              ? "Aperture priority"
              : e === 4
                ? "Shutter priority"
                : e === 5
                  ? "Creative program"
                  : e === 6
                    ? "Action program"
                    : e === 7
                      ? "Portrait mode"
                      : e === 8
                        ? "Landscape mode"
                        : e === 9
                          ? "Bulb"
                          : "Unknown";
    },
    ExposureTime(e) {
      if (e[0] / e[1] > 0.25) {
        const t = e[0] / e[1];
        return Number.isInteger(t) ? "" + t : t.toFixed(1);
      }
      return e[0] !== 0 ? `1/${Math.round(e[1] / e[0])}` : `0/${e[1]}`;
    },
    FNumber: (e) => `f/${e[0] / e[1]}`,
    FocalLength: (e) => e[0] / e[1] + " mm",
    FocalPlaneResolutionUnit(e) {
      return e === 2 ? "inches" : e === 3 ? "centimeters" : "Unknown";
    },
    LightSource: (e) =>
      e === 1
        ? "Daylight"
        : e === 2
          ? "Fluorescent"
          : e === 3
            ? "Tungsten (incandescent light)"
            : e === 4
              ? "Flash"
              : e === 9
                ? "Fine weather"
                : e === 10
                  ? "Cloudy weather"
                  : e === 11
                    ? "Shade"
                    : e === 12
                      ? "Daylight fluorescent (D 5700 – 7100K)"
                      : e === 13
                        ? "Day white fluorescent (N 4600 – 5400K)"
                        : e === 14
                          ? "Cool white fluorescent (W 3900 – 4500K)"
                          : e === 15
                            ? "White fluorescent (WW 3200 – 3700K)"
                            : e === 17
                              ? "Standard light A"
                              : e === 18
                                ? "Standard light B"
                                : e === 19
                                  ? "Standard light C"
                                  : e === 20
                                    ? "D55"
                                    : e === 21
                                      ? "D65"
                                      : e === 22
                                        ? "D75"
                                        : e === 23
                                          ? "D50"
                                          : e === 24
                                            ? "ISO studio tungsten"
                                            : e === 255
                                              ? "Other light source"
                                              : "Unknown",
    MeteringMode(e) {
      return e === 1
        ? "Average"
        : e === 2
          ? "CenterWeightedAverage"
          : e === 3
            ? "Spot"
            : e === 4
              ? "MultiSpot"
              : e === 5
                ? "Pattern"
                : e === 6
                  ? "Partial"
                  : e === 255
                    ? "Other"
                    : "Unknown";
    },
    ResolutionUnit(e) {
      return e === 2 ? "inches" : e === 3 ? "centimeters" : "Unknown";
    },
    Saturation(e) {
      return e === 0
        ? "Normal"
        : e === 1
          ? "Low saturation"
          : e === 2
            ? "High saturation"
            : "Unknown";
    },
    SceneCaptureType(e) {
      return e === 0
        ? "Standard"
        : e === 1
          ? "Landscape"
          : e === 2
            ? "Portrait"
            : e === 3
              ? "Night scene"
              : "Unknown";
    },
    Sharpness(e) {
      return e === 0
        ? "Normal"
        : e === 1
          ? "Soft"
          : e === 2
            ? "Hard"
            : "Unknown";
    },
    ShutterSpeedValue(e) {
      const t = Math.pow(2, e[0] / e[1]);
      return t <= 1 ? `${Math.round(1 / t)}` : `1/${Math.round(t)}`;
    },
    WhiteBalance(e) {
      return e === 0
        ? "Auto white balance"
        : e === 1
          ? "Manual white balance"
          : "Unknown";
    },
    XResolution: (e) => "" + Math.round(e[0] / e[1]),
    YResolution: (e) => "" + Math.round(e[0] / e[1]),
  },
  Vt = {
    11: "ProcessingSoftware",
    254: {
      name: "SubfileType",
      description: (e) =>
        ({
          0: "Full-resolution image",
          1: "Reduced-resolution image",
          2: "Single page of multi-page image",
          3: "Single page of multi-page reduced-resolution image",
          4: "Transparency mask",
          5: "Transparency mask of reduced-resolution image",
          6: "Transparency mask of multi-page image",
          7: "Transparency mask of reduced-resolution multi-page image",
          65537: "Alternate reduced-resolution image",
          4294967295: "Invalid",
        })[e] || "Unknown",
    },
    255: {
      name: "OldSubfileType",
      description: (e) =>
        ({
          0: "Full-resolution image",
          1: "Reduced-resolution image",
          2: "Single page of multi-page image",
        })[e] || "Unknown",
    },
    256: "ImageWidth",
    257: "ImageLength",
    258: "BitsPerSample",
    259: "Compression",
    262: "PhotometricInterpretation",
    263: {
      name: "Thresholding",
      description: (e) =>
        ({
          1: "No dithering or halftoning",
          2: "Ordered dither or halfton",
          3: "Randomized dither",
        })[e] || "Unknown",
    },
    264: "CellWidth",
    265: "CellLength",
    266: {
      name: "FillOrder",
      description: (e) => ({ 1: "Normal", 2: "Reversed" })[e] || "Unknown",
    },
    269: "DocumentName",
    270: "ImageDescription",
    271: "Make",
    272: "Model",
    273: "StripOffsets",
    274: {
      name: "Orientation",
      description: (e) =>
        e === 1
          ? "top-left"
          : e === 2
            ? "top-right"
            : e === 3
              ? "bottom-right"
              : e === 4
                ? "bottom-left"
                : e === 5
                  ? "left-top"
                  : e === 6
                    ? "right-top"
                    : e === 7
                      ? "right-bottom"
                      : e === 8
                        ? "left-bottom"
                        : "Undefined",
    },
    277: "SamplesPerPixel",
    278: "RowsPerStrip",
    279: "StripByteCounts",
    280: "MinSampleValue",
    281: "MaxSampleValue",
    282: { name: "XResolution", description: m.XResolution },
    283: { name: "YResolution", description: m.YResolution },
    284: "PlanarConfiguration",
    285: "PageName",
    286: {
      name: "XPosition",
      description: (e) => "" + Math.round(e[0] / e[1]),
    },
    287: {
      name: "YPosition",
      description: (e) => "" + Math.round(e[0] / e[1]),
    },
    290: {
      name: "GrayResponseUnit",
      description: (e) =>
        ({ 1: "0.1", 2: "0.001", 3: "0.0001", 4: "1e-05", 5: "1e-06" })[e] ||
        "Unknown",
    },
    296: { name: "ResolutionUnit", description: m.ResolutionUnit },
    297: "PageNumber",
    301: "TransferFunction",
    305: "Software",
    306: "DateTime",
    315: "Artist",
    316: "HostComputer",
    317: "Predictor",
    318: {
      name: "WhitePoint",
      description: (e) => e.map((t) => `${t[0]}/${t[1]}`).join(", "),
    },
    319: {
      name: "PrimaryChromaticities",
      description: (e) => e.map((t) => `${t[0]}/${t[1]}`).join(", "),
    },
    321: "HalftoneHints",
    322: "TileWidth",
    323: "TileLength",
    330: "A100DataOffset",
    332: {
      name: "InkSet",
      description: (e) => ({ 1: "CMYK", 2: "Not CMYK" })[e] || "Unknown",
    },
    337: "TargetPrinter",
    338: {
      name: "ExtraSamples",
      description: (e) =>
        ({ 0: "Unspecified", 1: "Associated Alpha", 2: "Unassociated Alpha" })[
          e
        ] || "Unknown",
    },
    339: {
      name: "SampleFormat",
      description: (e) => {
        const t = {
          1: "Unsigned",
          2: "Signed",
          3: "Float",
          4: "Undefined",
          5: "Complex int",
          6: "Complex float",
        };
        return Array.isArray(e)
          ? e.map((n) => t[n] || "Unknown").join(", ")
          : "Unknown";
      },
    },
    513: "JPEGInterchangeFormat",
    514: "JPEGInterchangeFormatLength",
    529: {
      name: "YCbCrCoefficients",
      description: (e) => e.map((t) => "" + t[0] / t[1]).join("/"),
    },
    530: "YCbCrSubSampling",
    531: {
      name: "YCbCrPositioning",
      description: (e) =>
        e === 1 ? "centered" : e === 2 ? "co-sited" : "undefined " + e,
    },
    532: {
      name: "ReferenceBlackWhite",
      description: (e) => e.map((t) => "" + t[0] / t[1]).join(", "),
    },
    700: "ApplicationNotes",
    18246: "Rating",
    18249: "RatingPercent",
    33432: { name: "Copyright", description: (e) => e.join("; ") },
    33550: "PixelScale",
    33723: "IPTC-NAA",
    33920: "IntergraphMatrix",
    33922: "ModelTiePoint",
    34118: "SEMInfo",
    34264: "ModelTransform",
    34377: "PhotoshopSettings",
    34665: "Exif IFD Pointer",
    34675: "ICC_Profile",
    34735: "GeoTiffDirectory",
    34736: "GeoTiffDoubleParams",
    34737: "GeoTiffAsciiParams",
    34853: "GPS Info IFD Pointer",
    40091: { name: "XPTitle", description: j },
    40092: { name: "XPComment", description: j },
    40093: { name: "XPAuthor", description: j },
    40094: { name: "XPKeywords", description: j },
    40095: { name: "XPSubject", description: j },
    42112: "GDALMetadata",
    42113: "GDALNoData",
    50341: "PrintIM",
    50707: "DNGBackwardVersion",
    50708: "UniqueCameraModel",
    50709: "LocalizedCameraModel",
    50721: "ColorMatrix1",
    50722: "ColorMatrix2",
    50723: "CameraCalibration1",
    50724: "CameraCalibration2",
    50725: "ReductionMatrix1",
    50726: "ReductionMatrix2",
    50727: "AnalogBalance",
    50728: "AsShotNeutral",
    50729: "AsShotWhiteXY",
    50730: "BaselineExposure",
    50731: "BaselineNoise",
    50732: "BaselineSharpness",
    50734: "LinearResponseLimit",
    50735: "CameraSerialNumber",
    50736: "DNGLensInfo",
    50739: "ShadowScale",
    50741: {
      name: "MakerNoteSafety",
      description: (e) => ({ 0: "Unsafe", 1: "Safe" })[e] || "Unknown",
    },
    50778: { name: "CalibrationIlluminant1", description: m.LightSource },
    50779: { name: "CalibrationIlluminant2", description: m.LightSource },
    50781: "RawDataUniqueID",
    50827: "OriginalRawFileName",
    50828: "OriginalRawFileData",
    50831: "AsShotICCProfile",
    50832: "AsShotPreProfileMatrix",
    50833: "CurrentICCProfile",
    50834: "CurrentPreProfileMatrix",
    50879: "ColorimetricReference",
    50885: "SRawType",
    50898: "PanasonicTitle",
    50899: "PanasonicTitle2",
    50931: "CameraCalibrationSig",
    50932: "ProfileCalibrationSig",
    50933: "ProfileIFD",
    50934: "AsShotProfileName",
    50936: "ProfileName",
    50937: "ProfileHueSatMapDims",
    50938: "ProfileHueSatMapData1",
    50939: "ProfileHueSatMapData2",
    50940: "ProfileToneCurve",
    50941: {
      name: "ProfileEmbedPolicy",
      description: (e) =>
        ({
          0: "Allow Copying",
          1: "Embed if Used",
          2: "Never Embed",
          3: "No Restrictions",
        })[e] || "Unknown",
    },
    50942: "ProfileCopyright",
    50964: "ForwardMatrix1",
    50965: "ForwardMatrix2",
    50966: "PreviewApplicationName",
    50967: "PreviewApplicationVersion",
    50968: "PreviewSettingsName",
    50969: "PreviewSettingsDigest",
    50970: {
      name: "PreviewColorSpace",
      description: (e) =>
        ({ 1: "Gray Gamma 2.2", 2: "sRGB", 3: "Adobe RGB", 4: "ProPhoto RGB" })[
          e
        ] || "Unknown",
    },
    50971: "PreviewDateTime",
    50972: "RawImageDigest",
    50973: "OriginalRawFileDigest",
    50981: "ProfileLookTableDims",
    50982: "ProfileLookTableData",
    51043: "TimeCodes",
    51044: "FrameRate",
    51058: "TStop",
    51081: "ReelName",
    51089: "OriginalDefaultFinalSize",
    51090: "OriginalBestQualitySize",
    51091: "OriginalDefaultCropSize",
    51105: "CameraLabel",
    51107: {
      name: "ProfileHueSatMapEncoding",
      description: (e) => ({ 0: "Linear", 1: "sRGB" })[e] || "Unknown",
    },
    51108: {
      name: "ProfileLookTableEncoding",
      description: (e) => ({ 0: "Linear", 1: "sRGB" })[e] || "Unknown",
    },
    51109: "BaselineExposureOffset",
    51110: {
      name: "DefaultBlackRender",
      description: (e) => ({ 0: "Auto", 1: "None" })[e] || "Unknown",
    },
    51111: "NewRawImageDigest",
    51112: "RawToPreviewGain",
  };
function j(e) {
  return new TextDecoder("utf-16")
    .decode(new Uint8Array(e))
    .replace(/\u0000+$/, "");
}
const yi = {
    33434: { name: "ExposureTime", description: m.ExposureTime },
    33437: { name: "FNumber", description: m.FNumber },
    34850: { name: "ExposureProgram", description: m.ExposureProgram },
    34852: "SpectralSensitivity",
    34855: "ISOSpeedRatings",
    34856: { name: "OECF", description: () => "[Raw OECF table data]" },
    34858: "TimeZoneOffset",
    34859: "SelfTimerMode",
    34864: {
      name: "SensitivityType",
      description: (e) =>
        ({
          1: "Standard Output Sensitivity",
          2: "Recommended Exposure Index",
          3: "ISO Speed",
          4: "Standard Output Sensitivity and Recommended Exposure Index",
          5: "Standard Output Sensitivity and ISO Speed",
          6: "Recommended Exposure Index and ISO Speed",
          7: "Standard Output Sensitivity, Recommended Exposure Index and ISO Speed",
        })[e] || "Unknown",
    },
    34865: "StandardOutputSensitivity",
    34866: "RecommendedExposureIndex",
    34867: "ISOSpeed",
    34868: "ISOSpeedLatitudeyyy",
    34869: "ISOSpeedLatitudezzz",
    36864: { name: "ExifVersion", description: (e) => h(e) },
    36867: "DateTimeOriginal",
    36868: "DateTimeDigitized",
    36873: "GooglePlusUploadCode",
    36880: "OffsetTime",
    36881: "OffsetTimeOriginal",
    36882: "OffsetTimeDigitized",
    37121: {
      name: "ComponentsConfiguration",
      description: m.ComponentsConfiguration,
    },
    37122: "CompressedBitsPerPixel",
    37377: { name: "ShutterSpeedValue", description: m.ShutterSpeedValue },
    37378: { name: "ApertureValue", description: m.ApertureValue },
    37379: "BrightnessValue",
    37380: "ExposureBiasValue",
    37381: {
      name: "MaxApertureValue",
      description: (e) => Math.pow(Math.sqrt(2), e[0] / e[1]).toFixed(2),
    },
    37382: { name: "SubjectDistance", description: (e) => e[0] / e[1] + " m" },
    37383: { name: "MeteringMode", description: m.MeteringMode },
    37384: { name: "LightSource", description: m.LightSource },
    37385: {
      name: "Flash",
      description: (e) =>
        e === 0
          ? "Flash did not fire"
          : e === 1
            ? "Flash fired"
            : e === 5
              ? "Strobe return light not detected"
              : e === 7
                ? "Strobe return light detected"
                : e === 9
                  ? "Flash fired, compulsory flash mode"
                  : e === 13
                    ? "Flash fired, compulsory flash mode, return light not detected"
                    : e === 15
                      ? "Flash fired, compulsory flash mode, return light detected"
                      : e === 16
                        ? "Flash did not fire, compulsory flash mode"
                        : e === 24
                          ? "Flash did not fire, auto mode"
                          : e === 25
                            ? "Flash fired, auto mode"
                            : e === 29
                              ? "Flash fired, auto mode, return light not detected"
                              : e === 31
                                ? "Flash fired, auto mode, return light detected"
                                : e === 32
                                  ? "No flash function"
                                  : e === 65
                                    ? "Flash fired, red-eye reduction mode"
                                    : e === 69
                                      ? "Flash fired, red-eye reduction mode, return light not detected"
                                      : e === 71
                                        ? "Flash fired, red-eye reduction mode, return light detected"
                                        : e === 73
                                          ? "Flash fired, compulsory flash mode, red-eye reduction mode"
                                          : e === 77
                                            ? "Flash fired, compulsory flash mode, red-eye reduction mode, return light not detected"
                                            : e === 79
                                              ? "Flash fired, compulsory flash mode, red-eye reduction mode, return light detected"
                                              : e === 89
                                                ? "Flash fired, auto mode, red-eye reduction mode"
                                                : e === 93
                                                  ? "Flash fired, auto mode, return light not detected, red-eye reduction mode"
                                                  : e === 95
                                                    ? "Flash fired, auto mode, return light detected, red-eye reduction mode"
                                                    : "Unknown",
    },
    37386: { name: "FocalLength", description: m.FocalLength },
    37393: "ImageNumber",
    37394: {
      name: "SecurityClassification",
      description: (e) =>
        ({
          C: "Confidential",
          R: "Restricted",
          S: "Secret",
          T: "Top Secret",
          U: "Unclassified",
        })[e] || "Unknown",
    },
    37395: "ImageHistory",
    37396: {
      name: "SubjectArea",
      description: (e) =>
        e.length === 2
          ? `Location; X: ${e[0]}, Y: ${e[1]}`
          : e.length === 3
            ? `Circle; X: ${e[0]}, Y: ${e[1]}, diameter: ${e[2]}`
            : e.length === 4
              ? `Rectangle; X: ${e[0]}, Y: ${e[1]}, width: ${e[2]}, height: ${e[3]}`
              : "Unknown",
    },
    37500: { name: "MakerNote", description: () => "[Raw maker note data]" },
    37510: { name: "UserComment", description: Ce },
    37520: "SubSecTime",
    37521: "SubSecTimeOriginal",
    37522: "SubSecTimeDigitized",
    37724: "ImageSourceData",
    37888: {
      name: "AmbientTemperature",
      description: (e) => e[0] / e[1] + " °C",
    },
    37889: { name: "Humidity", description: (e) => e[0] / e[1] + " %" },
    37890: { name: "Pressure", description: (e) => e[0] / e[1] + " hPa" },
    37891: { name: "WaterDepth", description: (e) => e[0] / e[1] + " m" },
    37892: { name: "Acceleration", description: (e) => e[0] / e[1] + " mGal" },
    37893: {
      name: "CameraElevationAngle",
      description: (e) => e[0] / e[1] + " °",
    },
    40960: {
      name: "FlashpixVersion",
      description: (e) => e.map((t) => String.fromCharCode(t)).join(""),
    },
    40961: { name: "ColorSpace", description: m.ColorSpace },
    40962: "PixelXDimension",
    40963: "PixelYDimension",
    40964: "RelatedSoundFile",
    40965: "Interoperability IFD Pointer",
    41483: "FlashEnergy",
    41484: {
      name: "SpatialFrequencyResponse",
      description: () => "[Raw SFR table data]",
    },
    41486: "FocalPlaneXResolution",
    41487: "FocalPlaneYResolution",
    41488: {
      name: "FocalPlaneResolutionUnit",
      description: m.FocalPlaneResolutionUnit,
    },
    41492: {
      name: "SubjectLocation",
      description: ([e, t]) => `X: ${e}, Y: ${t}`,
    },
    41493: "ExposureIndex",
    41495: {
      name: "SensingMethod",
      description: (e) =>
        e === 1
          ? "Undefined"
          : e === 2
            ? "One-chip color area sensor"
            : e === 3
              ? "Two-chip color area sensor"
              : e === 4
                ? "Three-chip color area sensor"
                : e === 5
                  ? "Color sequential area sensor"
                  : e === 7
                    ? "Trilinear sensor"
                    : e === 8
                      ? "Color sequential linear sensor"
                      : "Unknown",
    },
    41728: {
      name: "FileSource",
      description: (e) => (e === 3 ? "DSC" : "Unknown"),
    },
    41729: {
      name: "SceneType",
      description: (e) =>
        e === 1 ? "A directly photographed image" : "Unknown",
    },
    41730: {
      name: "CFAPattern",
      description: () => "[Raw CFA pattern table data]",
    },
    41985: { name: "CustomRendered", description: m.CustomRendered },
    41986: { name: "ExposureMode", description: m.ExposureMode },
    41987: { name: "WhiteBalance", description: m.WhiteBalance },
    41988: {
      name: "DigitalZoomRatio",
      description: (e) =>
        e[0] === 0 ? "Digital zoom was not used" : "" + e[0] / e[1],
    },
    41989: {
      name: "FocalLengthIn35mmFilm",
      description: (e) => (e === 0 ? "Unknown" : e),
    },
    41990: { name: "SceneCaptureType", description: m.SceneCaptureType },
    41991: {
      name: "GainControl",
      description: (e) =>
        e === 0
          ? "None"
          : e === 1
            ? "Low gain up"
            : e === 2
              ? "High gain up"
              : e === 3
                ? "Low gain down"
                : e === 4
                  ? "High gain down"
                  : "Unknown",
    },
    41992: { name: "Contrast", description: m.Contrast },
    41993: { name: "Saturation", description: m.Saturation },
    41994: { name: "Sharpness", description: m.Sharpness },
    41995: {
      name: "DeviceSettingDescription",
      description: () => "[Raw device settings table data]",
    },
    41996: {
      name: "SubjectDistanceRange",
      description: (e) =>
        e === 1
          ? "Macro"
          : e === 2
            ? "Close view"
            : e === 3
              ? "Distant view"
              : "Unknown",
    },
    42016: "ImageUniqueID",
    42032: "CameraOwnerName",
    42033: "BodySerialNumber",
    42034: {
      name: "LensSpecification",
      description: (e) => {
        const t = parseFloat((e[0][0] / e[0][1]).toFixed(5)),
          n = parseFloat((e[1][0] / e[1][1]).toFixed(5)),
          r = `${t}-${n} mm`;
        if (e[3][1] === 0) return `${r} f/?`;
        const i = 1 / (e[2][1] / e[2][1] / (e[3][0] / e[3][1]));
        return `${r} f/${parseFloat(i.toFixed(5))}`;
      },
    },
    42035: "LensMake",
    42036: "LensModel",
    42037: "LensSerialNumber",
    42080: {
      name: "CompositeImage",
      description: (e) =>
        ({
          1: "Not a Composite Image",
          2: "General Composite Image",
          3: "Composite Image Captured While Shooting",
        })[e] || "Unknown",
    },
    42081: "SourceImageNumberOfCompositeImage",
    42082: "SourceExposureTimesOfCompositeImage",
    42240: "Gamma",
    59932: "Padding",
    59933: "OffsetSchema",
    65e3: "OwnerName",
    65001: "SerialNumber",
    65002: "Lens",
    65100: "RawFile",
    65101: "Converter",
    65102: "WhiteBalance",
    65105: "Exposure",
    65106: "Shadows",
    65107: "Brightness",
    65108: "Contrast",
    65109: "Saturation",
    65110: "Sharpness",
    65111: "Smoothness",
    65112: "MoireFilter",
  },
  Ni = {
    0: {
      name: "GPSVersionID",
      description: (e) =>
        e[0] === 2 && e[1] === 2 && e[2] === 0 && e[3] === 0
          ? "Version 2.2"
          : "Unknown",
    },
    1: {
      name: "GPSLatitudeRef",
      description: (e) => {
        const t = e.join("");
        return t === "N"
          ? "North latitude"
          : t === "S"
            ? "South latitude"
            : "Unknown";
      },
    },
    2: { name: "GPSLatitude", description: ce },
    3: {
      name: "GPSLongitudeRef",
      description: (e) => {
        const t = e.join("");
        return t === "E"
          ? "East longitude"
          : t === "W"
            ? "West longitude"
            : "Unknown";
      },
    },
    4: { name: "GPSLongitude", description: ce },
    5: {
      name: "GPSAltitudeRef",
      description: (e) =>
        e === 0
          ? "Sea level"
          : e === 1
            ? "Sea level reference (negative value)"
            : "Unknown",
    },
    6: { name: "GPSAltitude", description: (e) => e[0] / e[1] + " m" },
    7: {
      name: "GPSTimeStamp",
      description: (e) =>
        e
          .map(([t, n]) => {
            const r = t / n;
            return /^\d(\.|$)/.test(`${r}`) ? `0${r}` : r;
          })
          .join(":"),
    },
    8: "GPSSatellites",
    9: {
      name: "GPSStatus",
      description: (e) => {
        const t = e.join("");
        return t === "A"
          ? "Measurement in progress"
          : t === "V"
            ? "Measurement Interoperability"
            : "Unknown";
      },
    },
    10: {
      name: "GPSMeasureMode",
      description: (e) => {
        const t = e.join("");
        return t === "2"
          ? "2-dimensional measurement"
          : t === "3"
            ? "3-dimensional measurement"
            : "Unknown";
      },
    },
    11: "GPSDOP",
    12: {
      name: "GPSSpeedRef",
      description: (e) => {
        const t = e.join("");
        return t === "K"
          ? "Kilometers per hour"
          : t === "M"
            ? "Miles per hour"
            : t === "N"
              ? "Knots"
              : "Unknown";
      },
    },
    13: "GPSSpeed",
    14: {
      name: "GPSTrackRef",
      description: (e) => {
        const t = e.join("");
        return t === "T"
          ? "True direction"
          : t === "M"
            ? "Magnetic direction"
            : "Unknown";
      },
    },
    15: "GPSTrack",
    16: {
      name: "GPSImgDirectionRef",
      description: (e) => {
        const t = e.join("");
        return t === "T"
          ? "True direction"
          : t === "M"
            ? "Magnetic direction"
            : "Unknown";
      },
    },
    17: "GPSImgDirection",
    18: "GPSMapDatum",
    19: {
      name: "GPSDestLatitudeRef",
      description: (e) => {
        const t = e.join("");
        return t === "N"
          ? "North latitude"
          : t === "S"
            ? "South latitude"
            : "Unknown";
      },
    },
    20: {
      name: "GPSDestLatitude",
      description: (e) =>
        e[0][0] / e[0][1] + e[1][0] / e[1][1] / 60 + e[2][0] / e[2][1] / 3600,
    },
    21: {
      name: "GPSDestLongitudeRef",
      description: (e) => {
        const t = e.join("");
        return t === "E"
          ? "East longitude"
          : t === "W"
            ? "West longitude"
            : "Unknown";
      },
    },
    22: {
      name: "GPSDestLongitude",
      description: (e) =>
        e[0][0] / e[0][1] + e[1][0] / e[1][1] / 60 + e[2][0] / e[2][1] / 3600,
    },
    23: {
      name: "GPSDestBearingRef",
      description: (e) => {
        const t = e.join("");
        return t === "T"
          ? "True direction"
          : t === "M"
            ? "Magnetic direction"
            : "Unknown";
      },
    },
    24: "GPSDestBearing",
    25: {
      name: "GPSDestDistanceRef",
      description: (e) => {
        const t = e.join("");
        return t === "K"
          ? "Kilometers"
          : t === "M"
            ? "Miles"
            : t === "N"
              ? "Knots"
              : "Unknown";
      },
    },
    26: "GPSDestDistance",
    27: { name: "GPSProcessingMethod", description: Ce },
    28: { name: "GPSAreaInformation", description: Ce },
    29: "GPSDateStamp",
    30: {
      name: "GPSDifferential",
      description: (e) =>
        e === 0
          ? "Measurement without differential correction"
          : e === 1
            ? "Differential correction applied"
            : "Unknown",
    },
    31: "GPSHPositioningError",
  },
  Oi = {
    1: "InteroperabilityIndex",
    2: { name: "InteroperabilityVersion", description: (e) => h(e) },
    4096: "RelatedImageFileFormat",
    4097: "RelatedImageWidth",
    4098: "RelatedImageHeight",
  },
  Ri = {
    45056: { name: "MPFVersion", description: (e) => h(e) },
    45057: "NumberOfImages",
    45058: "MPEntry",
    45059: "ImageUIDList",
    45060: "TotalFrames",
  },
  Di = { 4: { name: "ShotInfo", description: (e) => e } },
  gt = x({}, Vt, yi),
  Ye = "0th",
  en = "1st",
  tn = "exif",
  nn = "gps",
  rn = "interoperability",
  on = "mpf",
  sn = "canon",
  L = { [Ye]: gt, [en]: Vt, [tn]: gt, [nn]: Ni, [rn]: Oi, [on]: Ri, [sn]: Di },
  un = { 1: 1, 2: 1, 3: 2, 4: 4, 5: 8, 7: 1, 9: 4, 10: 8, 13: 4 },
  De = {
    BYTE: 1,
    ASCII: 2,
    SHORT: 3,
    LONG: 4,
    RATIONAL: 5,
    UNDEFINED: 7,
    SLONG: 9,
    SRATIONAL: 10,
    IFD: 13,
  },
  c = {
    getAsciiValue: Ui,
    getByteAt: cn,
    getAsciiAt: Li,
    getShortAt: Mi,
    getLongAt: ae,
    getRationalAt: Bi,
    getUndefinedAt: Gi,
    getSlongAt: Ue,
    getSrationalAt: ki,
    getIfdPointerAt: Zi,
    typeSizes: un,
    tagTypes: De,
    getTypeSize: Hi,
  };
function Ui(e) {
  return e.map((t) => String.fromCharCode(t));
}
function cn(e, t) {
  return e.getUint8(t);
}
function Li(e, t) {
  return e.getUint8(t);
}
function Mi(e, t, n) {
  return e.getUint16(t, n === Z.LITTLE_ENDIAN);
}
function ae(e, t, n) {
  return e.getUint32(t, n === Z.LITTLE_ENDIAN);
}
function Bi(e, t, n) {
  return [ae(e, t, n), ae(e, t + 4, n)];
}
function Gi(e, t) {
  return cn(e, t);
}
function Ue(e, t, n) {
  return e.getInt32(t, n === Z.LITTLE_ENDIAN);
}
function ki(e, t, n) {
  return [Ue(e, t, n), Ue(e, t + 4, n)];
}
function Zi(e, t, n) {
  return ae(e, t, n);
}
function Hi(e) {
  if (De[e] === void 0) throw new Error("No such type found.");
  return un[De[e]];
}
const $i = {
  1: c.getByteAt,
  2: c.getAsciiAt,
  3: c.getShortAt,
  4: c.getLongAt,
  5: c.getRationalAt,
  7: c.getUndefinedAt,
  9: c.getSlongAt,
  10: c.getSrationalAt,
  13: c.getIfdPointerAt,
};
function fn(e, t, n) {
  return t + c.getLongAt(e, t + 4, n);
}
function H(e, t, n, r, i, o) {
  const s = c.getTypeSize("SHORT"),
    u = 12,
    f = {},
    l = Xi(e, r, i);
  r += s;
  for (let a = 0; a < l && !(r + u > e.byteLength); a++) {
    const p = Yi(e, t, n, r, i, o);
    (p !== void 0 &&
      ((f[p.name] = { id: p.id, value: p.value, description: p.description }),
      p.name === "MakerNote" && (f[p.name].__offset = p.__offset)),
      (r += u));
  }
  if (r < e.byteLength - c.getTypeSize("LONG")) {
    const a = c.getLongAt(e, r, i);
    a !== 0 && t === Ye && (f.Thumbnail = H(e, en, n, n + a, i, o));
  }
  return f;
}
function Xi(e, t, n) {
  return t + c.getTypeSize("SHORT") <= e.byteLength ? c.getShortAt(e, t, n) : 0;
}
function Yi(e, t, n, r, i, o) {
  const u = c.getTypeSize("SHORT"),
    f = u + c.getTypeSize("SHORT"),
    l = f + c.getTypeSize("LONG"),
    a = c.getShortAt(e, r, i),
    p = c.getShortAt(e, r + u, i),
    g = c.getLongAt(e, r + f, i);
  let S, F;
  if (c.typeSizes[p] === void 0 || (!o && L[t][a] === void 0)) return;
  if (Ki(p, g)) ((F = r + l), (S = mt(e, F, p, g, i)));
  else if (((F = c.getLongAt(e, r + l, i)), zi(e, n, F, p, g))) {
    const b = a === 33723;
    S = mt(e, n + F, p, g, i, b);
  } else S = "<faulty value>";
  p === c.tagTypes.ASCII && ((S = Wi(S)), (S = ji(S)));
  let C = `undefined-${a}`,
    A = S;
  if (L[t][a] !== void 0)
    if (L[t][a].name !== void 0 && L[t][a].description !== void 0) {
      C = L[t][a].name;
      try {
        A = L[t][a].description(S);
      } catch {
        A = Et(S);
      }
    } else
      p === c.tagTypes.RATIONAL || p === c.tagTypes.SRATIONAL
        ? ((C = L[t][a]), (A = "" + S[0] / S[1]))
        : ((C = L[t][a]), (A = Et(S)));
  return { id: a, name: C, value: S, description: A, __offset: F };
}
function Ki(e, t) {
  return c.typeSizes[e] * t <= c.getTypeSize("LONG");
}
function mt(e, t, n, r, i, o = !1) {
  let s = [];
  o && ((r = r * c.typeSizes[n]), (n = c.tagTypes.BYTE));
  for (let u = 0; u < r; u++) (s.push($i[n](e, t, i)), (t += c.typeSizes[n]));
  return (
    n === c.tagTypes.ASCII
      ? (s = c.getAsciiValue(s))
      : s.length === 1 && (s = s[0]),
    s
  );
}
function zi(e, t, n, r, i) {
  return t + n + c.typeSizes[r] * i <= e.byteLength;
}
function Wi(e) {
  const t = [];
  let n = 0;
  for (let r = 0; r < e.length; r++) {
    if (e[r] === "\0") {
      n++;
      continue;
    }
    (t[n] === void 0 && (t[n] = ""), (t[n] += e[r]));
  }
  return t;
}
function ji(e) {
  try {
    return e.map((t) => decodeURIComponent(escape(t)));
  } catch {
    return e;
  }
}
function Et(e) {
  return e instanceof Array ? e.join(", ") : e;
}
const St = "Exif IFD Pointer",
  xt = "GPS Info IFD Pointer",
  It = "Interoperability IFD Pointer",
  an = { read: Ji };
function Ji(e, t, n) {
  const r = Z.getByteOrder(e, t);
  let i = vi(e, t, r, n);
  return (
    (i = qi(i, e, t, r, n)),
    (i = wi(i, e, t, r, n)),
    (i = Qi(i, e, t, r, n)),
    { tags: i, byteOrder: r }
  );
}
function vi(e, t, n, r) {
  return H(e, Ye, t, fn(e, t, n), n, r);
}
function qi(e, t, n, r, i) {
  return e[St] !== void 0 ? x(e, H(t, tn, n, n + e[St].value, r, i)) : e;
}
function wi(e, t, n, r, i) {
  return e[xt] !== void 0 ? x(e, H(t, nn, n, n + e[xt].value, r, i)) : e;
}
function Qi(e, t, n, r, i) {
  return e[It] !== void 0 ? x(e, H(t, rn, n, n + e[It].value, r, i)) : e;
}
const Vi = { read: eo },
  z = 16;
function eo(e, t, n) {
  const r = Z.getByteOrder(e, t),
    i = H(e, on, t, fn(e, t, r), r, n);
  return to(e, t, i, r);
}
function to(e, t, n, r) {
  if (!n.MPEntry) return n;
  const i = [];
  for (let o = 0; o < Math.ceil(n.MPEntry.value.length / z); o++) {
    i[o] = {};
    const s = v(n.MPEntry.value, o * z, c.getTypeSize("LONG"), r);
    ((i[o].ImageFlags = no(s)),
      (i[o].ImageFormat = ro(s)),
      (i[o].ImageType = io(s)));
    const u = v(n.MPEntry.value, o * z + 4, c.getTypeSize("LONG"), r);
    i[o].ImageSize = { value: u, description: "" + u };
    const f = oo(o, n.MPEntry, r, t);
    i[o].ImageOffset = { value: f, description: "" + f };
    const l = v(n.MPEntry.value, o * z + 12, c.getTypeSize("SHORT"), r);
    i[o].DependentImage1EntryNumber = { value: l, description: "" + l };
    const a = v(n.MPEntry.value, o * z + 14, c.getTypeSize("SHORT"), r);
    ((i[o].DependentImage2EntryNumber = { value: a, description: "" + a }),
      (i[o].image = e.buffer.slice(f, f + u)),
      kt(i[o], "base64", function () {
        return Zt(this.image);
      }));
  }
  return ((n.Images = i), n);
}
function v(e, t, n, r) {
  if (r === Z.LITTLE_ENDIAN) {
    let o = 0;
    for (let s = 0; s < n; s++) o += e[t + s] << (8 * s);
    return o;
  }
  let i = 0;
  for (let o = 0; o < n; o++) i += e[t + o] << (8 * (n - 1 - o));
  return i;
}
function no(e) {
  const t = [(e >> 31) & 1, (e >> 30) & 1, (e >> 29) & 1],
    n = [];
  return (
    t[0] && n.push("Dependent Parent Image"),
    t[1] && n.push("Dependent Child Image"),
    t[2] && n.push("Representative Image"),
    { value: t, description: n.join(", ") || "None" }
  );
}
function ro(e) {
  const t = (e >> 24) & 7;
  return { value: t, description: t === 0 ? "JPEG" : "Unknown" };
}
function io(e) {
  const t = e & 16777215;
  return {
    value: t,
    description:
      {
        196608: "Baseline MP Primary Image",
        65537: "Large Thumbnail (VGA equivalent)",
        65538: "Large Thumbnail (Full HD equivalent)",
        131073: "Multi-Frame Image (Panorama)",
        131074: "Multi-Frame Image (Disparity)",
        131075: "Multi-Frame Image (Multi-Angle)",
        0: "Undefined",
      }[t] || "Unknown",
  };
}
function oo(e, t, n, r) {
  return so(e) ? 0 : v(t.value, e * z + 8, c.getTypeSize("LONG"), n) + r;
}
function so(e) {
  return e === 0;
}
const uo = { read: co };
function co(e, t) {
  const n = fo(e, t),
    r = go(e, t, n);
  return {
    "Bits Per Sample": ao(e, t, n),
    "Image Height": lo(e, t, n),
    "Image Width": po(e, t, n),
    "Color Components": r,
    Subsampling: r && mo(e, t, r.value, n),
  };
}
function fo(e, t) {
  return c.getShortAt(e, t);
}
function ao(e, t, n) {
  if (3 > n) return;
  const o = c.getByteAt(e, t + 2);
  return { value: o, description: "" + o };
}
function lo(e, t, n) {
  if (5 > n) return;
  const o = c.getShortAt(e, t + 3);
  return { value: o, description: `${o}px` };
}
function po(e, t, n) {
  if (7 > n) return;
  const o = c.getShortAt(e, t + 5);
  return { value: o, description: `${o}px` };
}
function go(e, t, n) {
  if (8 > n) return;
  const o = c.getByteAt(e, t + 7);
  return { value: o, description: "" + o };
}
function mo(e, t, n, r) {
  if (8 + 3 * n > r) return;
  const s = [];
  for (let u = 0; u < n; u++) {
    const f = t + 8 + u * 3;
    s.push([c.getByteAt(e, f), c.getByteAt(e, f + 1), c.getByteAt(e, f + 2)]);
  }
  return { value: s, description: s.length > 1 ? Eo(s) + So(s) : "" };
}
function Eo(e) {
  const t = { 1: "Y", 2: "Cb", 3: "Cr", 4: "I", 5: "Q" };
  return e.map((n) => t[n[0]]).join("");
}
function So(e) {
  const t = {
    17: "4:4:4 (1 1)",
    18: "4:4:0 (1 2)",
    20: "4:4:1 (1 4)",
    33: "4:2:2 (2 1)",
    34: "4:2:0 (2 2)",
    36: "4:2:1 (2 4)",
    65: "4:1:1 (4 1)",
    66: "4:1:0 (4 2)",
  };
  return e.length === 0 || e[0][1] === void 0 || t[e[0][1]] === void 0
    ? ""
    : t[e[0][1]];
}
const xo = { read: Io };
function Io(e, t) {
  const n = ho(e, t),
    r = Po(e, t, n),
    i = bo(e, t, n),
    o = {
      "JFIF Version": To(e, t, n),
      "Resolution Unit": Fo(e, t, n),
      XResolution: Ao(e, t, n),
      YResolution: Co(e, t, n),
      "JFIF Thumbnail Width": r,
      "JFIF Thumbnail Height": i,
    };
  if (r !== void 0 && i !== void 0) {
    const s = yo(e, t, 3 * r.value * i.value, n);
    s && (o["JFIF Thumbnail"] = s);
  }
  for (const s in o) o[s] === void 0 && delete o[s];
  return o;
}
function ho(e, t) {
  return c.getShortAt(e, t);
}
function To(e, t, n) {
  if (9 > n) return;
  const o = c.getByteAt(e, t + 7),
    s = c.getByteAt(e, t + 7 + 1);
  return { value: o * 256 + s, description: o + "." + s };
}
function Fo(e, t, n) {
  if (10 > n) return;
  const o = c.getByteAt(e, t + 9);
  return { value: o, description: _o(o) };
}
function _o(e) {
  return e === 0 ? "None" : e === 1 ? "inches" : e === 2 ? "cm" : "Unknown";
}
function Ao(e, t, n) {
  if (12 > n) return;
  const o = c.getShortAt(e, t + 10);
  return { value: o, description: "" + o };
}
function Co(e, t, n) {
  if (14 > n) return;
  const o = c.getShortAt(e, t + 12);
  return { value: o, description: "" + o };
}
function Po(e, t, n) {
  if (15 > n) return;
  const o = c.getByteAt(e, t + 14);
  return { value: o, description: `${o}px` };
}
function bo(e, t, n) {
  if (16 > n) return;
  const o = c.getByteAt(e, t + 15);
  return { value: o, description: `${o}px` };
}
function yo(e, t, n, r) {
  return n === 0 || 16 + n > r
    ? void 0
    : {
        value: e.buffer.slice(t + 16, t + 16 + n),
        description: "<24-bit RGB pixel data>",
      };
}
const M = {
  iptc: {
    256: {
      name: "Model Version",
      description: (e) => ((e[0] << 8) + e[1]).toString(),
    },
    261: { name: "Destination", repeatable: !0 },
    276: {
      name: "File Format",
      description: (e) => ((e[0] << 8) + e[1]).toString(),
    },
    278: {
      name: "File Format Version",
      description: (e) => ((e[0] << 8) + e[1]).toString(),
    },
    286: "Service Identifier",
    296: "Envelope Number",
    306: "Product ID",
    316: "Envelope Priority",
    326: { name: "Date Sent", description: Se },
    336: { name: "Time Sent", description: xe },
    346: { name: "Coded Character Set", description: ht, encoding_name: ht },
    356: "UNO",
    376: {
      name: "ARM Identifier",
      description: (e) => ((e[0] << 8) + e[1]).toString(),
    },
    378: {
      name: "ARM Version",
      description: (e) => ((e[0] << 8) + e[1]).toString(),
    },
    512: {
      name: "Record Version",
      description: (e) => ((e[0] << 8) + e[1]).toString(),
    },
    515: "Object Type Reference",
    516: "Object Attribute Reference",
    517: "Object Name",
    519: "Edit Status",
    520: {
      name: "Editorial Update",
      description: (e) => (h(e) === "01" ? "Additional Language" : "Unknown"),
    },
    522: "Urgency",
    524: {
      name: "Subject Reference",
      repeatable: !0,
      description: (e) => {
        const t = h(e).split(":");
        return t[2] + (t[3] ? "/" + t[3] : "") + (t[4] ? "/" + t[4] : "");
      },
    },
    527: "Category",
    532: { name: "Supplemental Category", repeatable: !0 },
    534: "Fixture Identifier",
    537: { name: "Keywords", repeatable: !0 },
    538: { name: "Content Location Code", repeatable: !0 },
    539: { name: "Content Location Name", repeatable: !0 },
    542: "Release Date",
    547: "Release Time",
    549: "Expiration Date",
    550: "Expiration Time",
    552: "Special Instructions",
    554: {
      name: "Action Advised",
      description: (e) => {
        const t = h(e);
        return t === "01"
          ? "Object Kill"
          : t === "02"
            ? "Object Replace"
            : t === "03"
              ? "Object Append"
              : t === "04"
                ? "Object Reference"
                : "Unknown";
      },
    },
    557: { name: "Reference Service", repeatable: !0 },
    559: { name: "Reference Date", repeatable: !0 },
    562: { name: "Reference Number", repeatable: !0 },
    567: { name: "Date Created", description: Se },
    572: { name: "Time Created", description: xe },
    574: { name: "Digital Creation Date", description: Se },
    575: { name: "Digital Creation Time", description: xe },
    577: "Originating Program",
    582: "Program Version",
    587: {
      name: "Object Cycle",
      description: (e) => {
        const t = h(e);
        return t === "a"
          ? "morning"
          : t === "p"
            ? "evening"
            : t === "b"
              ? "both"
              : "Unknown";
      },
    },
    592: { name: "By-line", repeatable: !0 },
    597: { name: "By-line Title", repeatable: !0 },
    602: "City",
    604: "Sub-location",
    607: "Province/State",
    612: "Country/Primary Location Code",
    613: "Country/Primary Location Name",
    615: "Original Transmission Reference",
    617: "Headline",
    622: "Credit",
    627: "Source",
    628: "Copyright Notice",
    630: { name: "Contact", repeatable: !0 },
    632: "Caption/Abstract",
    634: { name: "Writer/Editor", repeatable: !0 },
    637: { name: "Rasterized Caption", description: (e) => e },
    642: "Image Type",
    643: {
      name: "Image Orientation",
      description: (e) => {
        const t = h(e);
        return t === "P"
          ? "Portrait"
          : t === "L"
            ? "Landscape"
            : t === "S"
              ? "Square"
              : "Unknown";
      },
    },
    647: "Language Identifier",
    662: {
      name: "Audio Type",
      description: (e) => {
        const t = h(e),
          n = t.charAt(0),
          r = t.charAt(1);
        let i = "";
        return (
          n === "1" ? (i += "Mono") : n === "2" && (i += "Stereo"),
          r === "A"
            ? (i += ", actuality")
            : r === "C"
              ? (i += ", question and answer session")
              : r === "M"
                ? (i += ", music, transmitted by itself")
                : r === "Q"
                  ? (i += ", response to a question")
                  : r === "R"
                    ? (i += ", raw sound")
                    : r === "S"
                      ? (i += ", scener")
                      : r === "V"
                        ? (i += ", voicer")
                        : r === "W" && (i += ", wrap"),
          i !== "" ? i : t
        );
      },
    },
    663: {
      name: "Audio Sampling Rate",
      description: (e) => parseInt(h(e), 10) + " Hz",
    },
    664: {
      name: "Audio Sampling Resolution",
      description: (e) => {
        const t = parseInt(h(e), 10);
        return t + (t === 1 ? " bit" : " bits");
      },
    },
    665: {
      name: "Audio Duration",
      description: (e) => {
        const t = h(e);
        return t.length >= 6
          ? t.substr(0, 2) + ":" + t.substr(2, 2) + ":" + t.substr(4, 2)
          : t;
      },
    },
    666: "Audio Outcue",
    698: "Short Document ID",
    699: "Unique Document ID",
    700: "Owner ID",
    712: {
      name: (e) =>
        e.length === 2
          ? "ObjectData Preview File Format"
          : "Record 2 destination",
      description: (e) => {
        if (e.length === 2) {
          const t = (e[0] << 8) + e[1];
          return t === 0
            ? "No ObjectData"
            : t === 1
              ? "IPTC-NAA Digital Newsphoto Parameter Record"
              : t === 2
                ? "IPTC7901 Recommended Message Format"
                : t === 3
                  ? "Tagged Image File Format (Adobe/Aldus Image data)"
                  : t === 4
                    ? "Illustrator (Adobe Graphics data)"
                    : t === 5
                      ? "AppleSingle (Apple Computer Inc)"
                      : t === 6
                        ? "NAA 89-3 (ANPA 1312)"
                        : t === 7
                          ? "MacBinary II"
                          : t === 8
                            ? "IPTC Unstructured Character Oriented File Format (UCOFF)"
                            : t === 9
                              ? "United Press International ANPA 1312 variant"
                              : t === 10
                                ? "United Press International Down-Load Message"
                                : t === 11
                                  ? "JPEG File Interchange (JFIF)"
                                  : t === 12
                                    ? "Photo-CD Image-Pac (Eastman Kodak)"
                                    : t === 13
                                      ? "Microsoft Bit Mapped Graphics File [*.BMP]"
                                      : t === 14
                                        ? "Digital Audio File [*.WAV] (Microsoft & Creative Labs)"
                                        : t === 15
                                          ? "Audio plus Moving Video [*.AVI] (Microsoft)"
                                          : t === 16
                                            ? "PC DOS/Windows Executable Files [*.COM][*.EXE]"
                                            : t === 17
                                              ? "Compressed Binary File [*.ZIP] (PKWare Inc)"
                                              : t === 18
                                                ? "Audio Interchange File Format AIFF (Apple Computer Inc)"
                                                : t === 19
                                                  ? "RIFF Wave (Microsoft Corporation)"
                                                  : t === 20
                                                    ? "Freehand (Macromedia/Aldus)"
                                                    : t === 21
                                                      ? 'Hypertext Markup Language "HTML" (The Internet Society)'
                                                      : t === 22
                                                        ? "MPEG 2 Audio Layer 2 (Musicom), ISO/IEC"
                                                        : t === 23
                                                          ? "MPEG 2 Audio Layer 3, ISO/IEC"
                                                          : t === 24
                                                            ? "Portable Document File (*.PDF) Adobe"
                                                            : t === 25
                                                              ? "News Industry Text Format (NITF)"
                                                              : t === 26
                                                                ? "Tape Archive (*.TAR)"
                                                                : t === 27
                                                                  ? "Tidningarnas Telegrambyrå NITF version (TTNITF DTD)"
                                                                  : t === 28
                                                                    ? "Ritzaus Bureau NITF version (RBNITF DTD)"
                                                                    : t === 29
                                                                      ? "Corel Draw [*.CDR]"
                                                                      : `Unknown format ${t}`;
        }
        return h(e);
      },
    },
    713: {
      name: "ObjectData Preview File Format Version",
      description: (e, t) => {
        const n = {
            "00": { "00": "1" },
            "01": { "01": "1", "02": "2", "03": "3", "04": "4" },
            "02": { "04": "4" },
            "03": { "01": "5.0", "02": "6.0" },
            "04": { "01": "1.40" },
            "05": { "01": "2" },
            "06": { "01": "1" },
            11: { "01": "1.02" },
            20: { "01": "3.1", "02": "4.0", "03": "5.0", "04": "5.5" },
            21: { "02": "2.0" },
          },
          r = h(e);
        if (t["ObjectData Preview File Format"]) {
          const i = h(t["ObjectData Preview File Format"].value);
          if (n[i] && n[i][r]) return n[i][r];
        }
        return r;
      },
    },
    714: "ObjectData Preview Data",
    1802: { name: "Size Mode", description: (e) => e[0].toString() },
    1812: {
      name: "Max Subfile Size",
      description: (e) => {
        let t = 0;
        for (let n = 0; n < e.length; n++) t = (t << 8) + e[n];
        return t.toString();
      },
    },
    1882: {
      name: "ObjectData Size Announced",
      description: (e) => {
        let t = 0;
        for (let n = 0; n < e.length; n++) t = (t << 8) + e[n];
        return t.toString();
      },
    },
    1887: {
      name: "Maximum ObjectData Size",
      description: (e) => {
        let t = 0;
        for (let n = 0; n < e.length; n++) t = (t << 8) + e[n];
        return t.toString();
      },
    },
  },
};
function Se(e) {
  const t = h(e);
  return t.length >= 8
    ? t.substr(0, 4) + "-" + t.substr(4, 2) + "-" + t.substr(6, 2)
    : t;
}
function xe(e) {
  const t = h(e);
  let n = t;
  return (
    t.length >= 6 &&
      ((n = t.substr(0, 2) + ":" + t.substr(2, 2) + ":" + t.substr(4, 2)),
      t.length === 11 &&
        (n += t.substr(6, 1) + t.substr(7, 2) + ":" + t.substr(9, 2))),
    n
  );
}
function ht(e) {
  const t = h(e);
  return t === "\x1B%G"
    ? "UTF-8"
    : t === "\x1B%5"
      ? "Windows-1252"
      : t === "\x1B%/G"
        ? "UTF-8 Level 1"
        : t === "\x1B%/H"
          ? "UTF-8 Level 2"
          : t === "\x1B%/I"
            ? "UTF-8 Level 3"
            : t === "\x1B/A"
              ? "ISO-8859-1"
              : t === "\x1B/B"
                ? "ISO-8859-2"
                : t === "\x1B/C"
                  ? "ISO-8859-3"
                  : t === "\x1B/D"
                    ? "ISO-8859-4"
                    : t === "\x1B/@"
                      ? "ISO-8859-5"
                      : t === "\x1B/G"
                        ? "ISO-8859-6"
                        : t === "\x1B/F"
                          ? "ISO-8859-7"
                          : t === "\x1B/H"
                            ? "ISO-8859-8"
                            : "Unknown";
}
const No = { get: Oo };
function Oo() {
  if (typeof TextDecoder < "u") return TextDecoder;
}
const Ro = 5,
  ln = { decode: Do, TAG_HEADER_SIZE: Ro };
function Do(e, t) {
  const n = No.get();
  if (typeof n < "u" && e !== void 0)
    try {
      return new n(e).decode(
        t instanceof DataView ? t.buffer : Uint8Array.from(t),
      );
    } catch {}
  const r = t.map((i) => String.fromCharCode(i)).join("");
  return Uo(r);
}
function Uo(e) {
  try {
    return decodeURIComponent(escape(e));
  } catch {
    return e;
  }
}
const Lo = 943868237,
  dn = 4,
  Ie = dn + 8,
  Mo = 1028,
  pn = 5,
  Le = { read: Bo };
function Bo(e, t, n) {
  try {
    if (Array.isArray(e))
      return Tt(
        new DataView(Uint8Array.from(e).buffer),
        { size: e.length },
        0,
        n,
      );
    const { naaBlock: r, dataOffset: i } = Go(e, t);
    return Tt(e, r, i, n);
  } catch {
    return {};
  }
}
function Go(e, t) {
  for (; t + Ie <= e.byteLength;) {
    const n = ko(e, t);
    if (Zo(n)) return { naaBlock: n, dataOffset: t + Ie };
    t += Ie + n.size + Ho(n);
  }
  throw new Error("No IPTC NAA resource block.");
}
function ko(e, t) {
  if (e.getUint32(t, !1) !== Lo) throw new Error("Not an IPTC resource block.");
  return { type: e.getUint16(t + dn), size: e.getUint16(t + 10) };
}
function Zo(e) {
  return e.type === Mo;
}
function Ho(e) {
  return e.size % 2 !== 0 ? 1 : 0;
}
function Tt(e, t, n, r) {
  const i = {};
  let o;
  const s = n + t.size;
  for (; n < s && n < e.byteLength;) {
    const { tag: u, tagSize: f } = $o(e, n, i, o, r);
    if (u === null) break;
    (u &&
      ("encoding" in u && (o = u.encoding),
      i[u.name] === void 0 || u.repeatable === void 0
        ? (i[u.name] = { id: u.id, value: u.value, description: u.description })
        : (i[u.name] instanceof Array ||
            (i[u.name] = [
              {
                id: i[u.name].id,
                value: i[u.name].value,
                description: i[u.name].description,
              },
            ]),
          i[u.name].push({
            id: u.id,
            value: u.value,
            description: u.description,
          }))),
      (n += pn + f));
  }
  return i;
}
function $o(e, t, n, r, i) {
  if (Xo(e, t)) return { tag: null, tagSize: 0 };
  const u = e.getUint16(t + 1),
    f = e.getUint16(t + 3);
  if (!i && !M.iptc[u]) return { tag: void 0, tagSize: f };
  const l = Yo(e, t + pn, f),
    a = {
      id: u,
      name: Ko(M.iptc[u], u, l),
      value: l,
      description: jo(M.iptc[u], l, n, r),
    };
  return (
    qo(u) && (a.repeatable = !0),
    wo(u) && (a.encoding = M.iptc[u].encoding_name(l)),
    { tag: a, tagSize: f }
  );
}
function Xo(e, t) {
  return e.getUint8(t) !== 28;
}
function Yo(e, t, n) {
  const r = [];
  for (let i = 0; i < n; i++) r.push(e.getUint8(t + i));
  return r;
}
function Ko(e, t, n) {
  return e ? (zo(e) ? e : Wo(e) ? e.name(n) : e.name) : `undefined-${t}`;
}
function zo(e) {
  return typeof e == "string";
}
function Wo(e) {
  return typeof e.name == "function";
}
function jo(e, t, n, r) {
  if (vo(e))
    try {
      return e.description(t, n);
    } catch {}
  return Jo(e, t) ? ln.decode(r, t) : t;
}
function Jo(e, t) {
  return e && t instanceof Array;
}
function vo(e) {
  return e && e.description !== void 0;
}
function qo(e) {
  return M.iptc[e] && M.iptc[e].repeatable;
}
function wo(e) {
  return M.iptc[e] && M.iptc[e].encoding_name !== void 0;
}
const te = {
  "tiff:Orientation"(e) {
    return e === "1"
      ? "Horizontal (normal)"
      : e === "2"
        ? "Mirror horizontal"
        : e === "3"
          ? "Rotate 180"
          : e === "4"
            ? "Mirror vertical"
            : e === "5"
              ? "Mirror horizontal and rotate 270 CW"
              : e === "6"
                ? "Rotate 90 CW"
                : e === "7"
                  ? "Mirror horizontal and rotate 90 CW"
                  : e === "8"
                    ? "Rotate 270 CW"
                    : e;
  },
  "tiff:ResolutionUnit": (e) => m.ResolutionUnit(parseInt(e, 10)),
  "tiff:XResolution": (e) => $(m.XResolution, e),
  "tiff:YResolution": (e) => $(m.YResolution, e),
  "exif:ApertureValue": (e) => $(m.ApertureValue, e),
  "exif:GPSLatitude": Ft,
  "exif:GPSLongitude": Ft,
  "exif:FNumber": (e) => $(m.FNumber, e),
  "exif:FocalLength": (e) => $(m.FocalLength, e),
  "exif:FocalPlaneResolutionUnit": (e) =>
    m.FocalPlaneResolutionUnit(parseInt(e, 10)),
  "exif:ColorSpace": (e) => m.ColorSpace(Qo(e)),
  "exif:ComponentsConfiguration"(e, t) {
    if (/^\d, \d, \d, \d$/.test(t)) {
      const n = t.split(", ").map((r) => r.charCodeAt(0));
      return m.ComponentsConfiguration(n);
    }
    return t;
  },
  "exif:Contrast": (e) => m.Contrast(parseInt(e, 10)),
  "exif:CustomRendered": (e) => m.CustomRendered(parseInt(e, 10)),
  "exif:ExposureMode": (e) => m.ExposureMode(parseInt(e, 10)),
  "exif:ExposureProgram": (e) => m.ExposureProgram(parseInt(e, 10)),
  "exif:ExposureTime"(e) {
    return gn(e) ? m.ExposureTime(e.split("/").map((t) => parseInt(t, 10))) : e;
  },
  "exif:MeteringMode": (e) => m.MeteringMode(parseInt(e, 10)),
  "exif:Saturation": (e) => m.Saturation(parseInt(e, 10)),
  "exif:SceneCaptureType": (e) => m.SceneCaptureType(parseInt(e, 10)),
  "exif:Sharpness": (e) => m.Sharpness(parseInt(e, 10)),
  "exif:ShutterSpeedValue": (e) => $(m.ShutterSpeedValue, e),
  "exif:WhiteBalance": (e) => m.WhiteBalance(parseInt(e, 10)),
};
function $(e, t) {
  return gn(t) ? e(t.split("/")) : t;
}
function Qo(e) {
  return e.substring(0, 2) === "0x"
    ? parseInt(e.substring(2), 16)
    : parseInt(e, 10);
}
function gn(e) {
  return /^-?\d+\/-?\d+$/.test(e);
}
function Ft(e) {
  const [t, n] = e.split(",");
  if (t !== void 0 && n !== void 0) {
    const r = parseFloat(t),
      i = parseFloat(n),
      o = n.charAt(n.length - 1);
    if (!Number.isNaN(r) && !Number.isNaN(i)) return "" + (r + i / 60) + o;
  }
  return e;
}
const Vo = { get: es };
function es() {
  if (typeof DOMParser < "u") return new DOMParser();
  try {
    const { DOMParser: e, onErrorStopParsing: t } =
      __non_webpack_require__("@xmldom/xmldom");
    return new e({ onError: t });
  } catch {
    return;
  }
}
const _t = { read: ts };
function ts(e, t) {
  const n = {};
  if (typeof e == "string") return (ne(n, e), n);
  const [r, i] = ns(e, t),
    o = ne(n, r);
  if (i) {
    const s = ne(n, i);
    !o && !s && (delete n._raw, ne(n, Me(e, t)));
  }
  return n;
}
function ns(e, t) {
  if (t.length === 0) return [];
  const n = [Me(e, t.slice(0, 1))];
  return (t.length > 1 && n.push(Me(e, t.slice(1))), n);
}
function Me(e, t) {
  const n = t.reduce((o, s) => o + s.length, 0),
    r = new Uint8Array(n);
  let i = 0;
  for (let o = 0; o < t.length; o++) {
    const s = t[o],
      u = e.buffer.slice(s.dataOffset, s.dataOffset + s.length);
    (r.set(new Uint8Array(u), i), (i += s.length));
  }
  return new DataView(r.buffer);
}
function ne(e, t) {
  try {
    const { doc: n, raw: r } = rs(t);
    e._raw = (e._raw || "") + r;
    const i = mn(n);
    return (x(e, Sn(En(i, !0))), !0);
  } catch {
    return !1;
  }
}
function rs(e) {
  const t = Vo.get();
  if (!t)
    throw (
      console.warn(
        "Warning: DOMParser is not available. It is needed to be able to parse XMP tags.",
      ),
      new Error()
    );
  const n = typeof e == "string" ? e : E(e, 0, e.byteLength),
    r = t.parseFromString(is(n), "application/xml");
  if (r.documentElement.nodeName === "parsererror")
    throw new Error(r.documentElement.textContent);
  return { doc: r, raw: n };
}
function is(e) {
  return e
    .replace(/^.+(<\?xpacket begin)/, "$1")
    .replace(/(<\?xpacket end=".*"\?>).+$/, "$1");
}
function mn(e) {
  for (let t = 0; t < e.childNodes.length; t++) {
    if (e.childNodes[t].tagName === "x:xmpmeta") return mn(e.childNodes[t]);
    if (e.childNodes[t].tagName === "rdf:RDF") return e.childNodes[t];
  }
  throw new Error();
}
function En(e, t = !1) {
  const n = os(e);
  return ss(n) ? (t ? {} : us(n[0])) : cs(n);
}
function os(e) {
  const t = [];
  for (let n = 0; n < e.childNodes.length; n++) t.push(e.childNodes[n]);
  return t;
}
function ss(e) {
  return e.length === 1 && e[0].nodeName === "#text";
}
function us(e) {
  return e.nodeValue;
}
function cs(e) {
  const t = {};
  return (
    e.forEach((n) => {
      if (fs(n)) {
        const r = as(n);
        t[n.nodeName] !== void 0
          ? (Array.isArray(t[n.nodeName]) || (t[n.nodeName] = [t[n.nodeName]]),
            t[n.nodeName].push(r))
          : (t[n.nodeName] = r);
      }
    }),
    t
  );
}
function fs(e) {
  return e.nodeName && e.nodeName !== "#text";
}
function as(e) {
  return { attributes: ls(e), value: En(e) };
}
function ls(e) {
  const t = {};
  for (let n = 0; n < e.attributes.length; n++)
    t[e.attributes[n].nodeName] = decodeURIComponent(
      escape(e.attributes[n].value),
    );
  return t;
}
function Sn(e) {
  const t = {};
  if (typeof e == "string") return e;
  for (const n in e) {
    let r = e[n];
    (Array.isArray(r) || (r = [r]),
      r.forEach((i) => {
        (x(t, Ke(i.attributes)),
          typeof i.value == "object" && x(t, xn(i.value)));
      }));
  }
  return t;
}
function Ke(e) {
  const t = {};
  for (const n in e)
    try {
      ds(n) &&
        (t[me(n)] = { value: e[n], attributes: {}, description: R(e[n], n) });
    } catch {}
  return t;
}
function ds(e) {
  return e !== "rdf:parseType" && !ge(e);
}
function ge(e) {
  return e.split(":")[0] === "xmlns";
}
function me(e) {
  return /^MicrosoftPhoto(_\d+_)?:Rating$/i.test(e)
    ? "RatingPercent"
    : e.split(":")[1];
}
function R(e, t = void 0) {
  if (Array.isArray(e)) {
    const n = ps(e);
    return t && typeof te[t] == "function" ? te[t](e, n) : n;
  }
  if (typeof e == "object") return gs(e);
  try {
    return t && typeof te[t] == "function"
      ? te[t](e)
      : decodeURIComponent(escape(e));
  } catch {
    return e;
  }
}
function ps(e) {
  return e.map((t) => (t.value !== void 0 ? R(t.value) : R(t))).join(", ");
}
function gs(e) {
  const t = [];
  for (const n in e) t.push(`${ms(n)}: ${R(e[n].value)}`);
  return t.join("; ");
}
function ms(e) {
  return e === "CiAdrCity"
    ? "CreatorCity"
    : e === "CiAdrCtry"
      ? "CreatorCountry"
      : e === "CiAdrExtadr"
        ? "CreatorAddress"
        : e === "CiAdrPcode"
          ? "CreatorPostalCode"
          : e === "CiAdrRegion"
            ? "CreatorRegion"
            : e === "CiEmailWork"
              ? "CreatorWorkEmail"
              : e === "CiTelWork"
                ? "CreatorWorkPhone"
                : e === "CiUrlWork"
                  ? "CreatorWorkUrl"
                  : e;
}
function xn(e) {
  const t = {};
  for (const n in e)
    try {
      ge(n) || (t[me(n)] = Es(e[n], n));
    } catch {}
  return t;
}
function Es(e, t) {
  return xs(e)
    ? Is(e, t)
    : Ss(e)
      ? { value: "", attributes: {}, description: "" }
      : In(e)
        ? hn(e, t)
        : Tn(e)
          ? Fn(e, t)
          : _n(e)
            ? An(e, t)
            : Fs(e)
              ? _s(e, t)
              : ze(e, t);
}
function Ss(e) {
  return (
    e.attributes["rdf:parseType"] === "Resource" &&
    typeof e.value == "string" &&
    e.value.trim() === ""
  );
}
function xs(e) {
  return Array.isArray(e);
}
function Is(e, t) {
  return ze(e[e.length - 1], t);
}
function In(e) {
  return (
    (e.attributes["rdf:parseType"] === "Resource" &&
      e.value["rdf:value"] !== void 0) ||
    (e.value["rdf:Description"] !== void 0 &&
      e.value["rdf:Description"].value["rdf:value"] !== void 0)
  );
}
function hn(e, t) {
  const n = q(e);
  (e.value["rdf:Description"] !== void 0 && (e = e.value["rdf:Description"]),
    x(n, q(e), hs(e)));
  const r = Ts(e);
  return { value: r, attributes: n, description: R(r, t) };
}
function q(e) {
  const t = {};
  for (const n in e.attributes)
    n !== "rdf:parseType" &&
      n !== "rdf:resource" &&
      !ge(n) &&
      (t[me(n)] = e.attributes[n]);
  return t;
}
function hs(e) {
  const t = {};
  for (const n in e.value)
    n !== "rdf:value" && !ge(n) && (t[me(n)] = e.value[n].value);
  return t;
}
function Ts(e) {
  return Pn(e.value["rdf:value"]) || e.value["rdf:value"].value;
}
function Tn(e) {
  return (
    e.attributes["rdf:parseType"] === "Resource" ||
    (e.value["rdf:Description"] !== void 0 &&
      e.value["rdf:Description"].value["rdf:value"] === void 0)
  );
}
function Fn(e, t) {
  const n = { value: {}, attributes: {} };
  return (
    e.value["rdf:Description"] !== void 0 &&
      (x(n.value, Ke(e.value["rdf:Description"].attributes)),
      x(n.attributes, q(e)),
      (e = e.value["rdf:Description"])),
    x(n.value, xn(e.value)),
    (n.description = R(n.value, t)),
    n
  );
}
function _n(e) {
  return (
    Object.keys(e.value).length === 0 &&
    e.attributes["xml:lang"] === void 0 &&
    e.attributes["rdf:resource"] === void 0
  );
}
function An(e, t) {
  const n = Ke(e.attributes);
  return { value: n, attributes: {}, description: R(n, t) };
}
function Fs(e) {
  return Cn(e.value) !== void 0;
}
function Cn(e) {
  return e["rdf:Bag"] || e["rdf:Seq"] || e["rdf:Alt"];
}
function _s(e, t) {
  let n = Cn(e.value).value["rdf:li"];
  const r = q(e),
    i = [];
  return (
    n === void 0 ? (n = []) : Array.isArray(n) || (n = [n]),
    n.forEach((o) => {
      i.push(As(o));
    }),
    { value: i, attributes: r, description: R(i, t) }
  );
}
function As(e) {
  return In(e) ? hn(e) : Tn(e) ? Fn(e).value : _n(e) ? An(e).value : ze(e);
}
function ze(e, t) {
  const n = Pn(e) || Sn(e.value);
  return { value: n, attributes: q(e), description: R(n, t) };
}
function Pn(e) {
  return e.attributes && e.attributes["rdf:resource"];
}
const O = {
    CLOSED_SUBPATH_LENGTH: 0,
    CLOSED_SUBPATH_BEZIER_LINKED: 1,
    CLOSED_SUBPATH_BEZIER_UNLINKED: 2,
    OPEN_SUBPATH_LENGTH: 3,
    OPEN_SUBPATH_BEZIER_LINKED: 4,
    OPEN_SUBPATH_BEZIER_UNLINKED: 5,
    FILL_RULE: 6,
    CLIPBOARD: 7,
    INITIAL_FILL_RULE: 8,
  },
  bn = 24,
  he = {
    2e3: { name: "PathInformation", description: Cs },
    2999: {
      name: "ClippingPathName",
      description(e) {
        const [, t] = Gt(e, 0);
        return t;
      },
    },
  };
function Cs(e) {
  const n = {},
    r = [];
  for (let i = 0; i < e.byteLength; i += 2 + bn) {
    const o = c.getShortAt(e, i);
    Te[o] &&
      (n[o] || (n[o] = Te[o].description),
      r.push({ type: o, path: Te[o].path(e, i + 2) }));
  }
  return JSON.stringify({ types: n, paths: r });
}
const Te = {
  [O.CLOSED_SUBPATH_LENGTH]: {
    description: "Closed subpath length",
    path: (e, t) => [c.getShortAt(e, t)],
  },
  [O.CLOSED_SUBPATH_BEZIER_LINKED]: {
    description: "Closed subpath Bezier knot, linked",
    path: re,
  },
  [O.CLOSED_SUBPATH_BEZIER_UNLINKED]: {
    description: "Closed subpath Bezier knot, unlinked",
    path: re,
  },
  [O.OPEN_SUBPATH_LENGTH]: {
    description: "Open subpath length",
    path: (e, t) => [c.getShortAt(e, t)],
  },
  [O.OPEN_SUBPATH_BEZIER_LINKED]: {
    description: "Open subpath Bezier knot, linked",
    path: re,
  },
  [O.OPEN_SUBPATH_BEZIER_UNLINKED]: {
    description: "Open subpath Bezier knot, unlinked",
    path: re,
  },
  [O.FILL_RULE]: { description: "Path fill rule", path: () => [] },
  [O.INITIAL_FILL_RULE]: {
    description: "Initial fill rule",
    path: (e, t) => [c.getShortAt(e, t)],
  },
  [O.CLIPBOARD]: { description: "Clipboard", path: bs },
};
function re(e, t) {
  const r = [];
  for (let i = 0; i < bn; i += 8) r.push(Ps(e, t + i));
  return r;
}
function Ps(e, t) {
  const n = G(e, t, 8);
  return [G(e, t + 4, 8), n];
}
function bs(e, t) {
  return [
    [G(e, t, 8), G(e, t + 4, 8), G(e, t + 8, 8), G(e, t + 12, 8)],
    G(e, t + 16, 8),
  ];
}
function G(e, t, n) {
  const r = c.getLongAt(e, t),
    i = r >>> 31 ? -1 : 1,
    o = (r & 2130706432) >>> (32 - n),
    s = r & parseInt(Ht("1", 32 - n), 2);
  return i * Bn(o.toString(2) + "." + Mn(s.toString(2), 32 - n, "0"), 2);
}
const ys = { read: Rs },
  yn = "8BIM",
  Ns = 2,
  Os = 4,
  At = yn.length;
function Rs(e, t) {
  const n = je(new Uint8Array(e).buffer),
    r = {};
  let i = 0;
  for (; i < e.length;) {
    const o = E(n, i, At);
    i += At;
    const s = c.getShortAt(n, i);
    i += Ns;
    const { tagName: u, tagNameSize: f } = Ds(n, i);
    i += f;
    const l = c.getLongAt(n, i);
    if (((i += Os), o === yn)) {
      const a = je(n.buffer, i, l),
        p = { id: s, value: E(a, 0, l) };
      if (he[s]) {
        try {
          p.description = he[s].description(a);
        } catch {
          p.description = "<no description formatter>";
        }
        r[u || he[s].name] = p;
      } else t && (r[`undefined-${s}`] = p);
    }
    i += l + (l % 2);
  }
  return r;
}
function Ds(e, t) {
  const [n, r] = Gt(e, t);
  return { tagName: r, tagNameSize: 1 + n + (n % 2 === 0 ? 1 : 0) };
}
const Ct = {
    desc: { name: "ICC Description" },
    cprt: { name: "ICC Copyright" },
    dmdd: { name: "ICC Device Model Description" },
    vued: { name: "ICC Viewing Conditions Description" },
    dmnd: { name: "ICC Device Manufacturer for Display" },
    tech: { name: "Technology" },
  },
  Pt = {
    4: {
      name: "Preferred CMM type",
      value: (e, t) => E(e, t, 4),
      description: (e) => (e !== null ? Fe(e) : ""),
    },
    8: {
      name: "Profile Version",
      value: (e, t) =>
        e.getUint8(t).toString(10) +
        "." +
        (e.getUint8(t + 1) >> 4).toString(10) +
        "." +
        (e.getUint8(t + 1) % 16).toString(10),
    },
    12: {
      name: "Profile/Device class",
      value: (e, t) => E(e, t, 4),
      description: (e) => {
        switch (e.toLowerCase()) {
          case "scnr":
            return "Input Device profile";
          case "mntr":
            return "Display Device profile";
          case "prtr":
            return "Output Device profile";
          case "link":
            return "DeviceLink profile";
          case "abst":
            return "Abstract profile";
          case "spac":
            return "ColorSpace profile";
          case "nmcl":
            return "NamedColor profile";
          case "cenc":
            return "ColorEncodingSpace profile";
          case "mid ":
            return "MultiplexIdentification profile";
          case "mlnk":
            return "MultiplexLink profile";
          case "mvis":
            return "MultiplexVisualization profile";
          default:
            return e;
        }
      },
    },
    16: { name: "Color Space", value: (e, t) => E(e, t, 4) },
    20: { name: "Connection Space", value: (e, t) => E(e, t, 4) },
    24: { name: "ICC Profile Date", value: (e, t) => Us(e, t).toISOString() },
    36: {
      name: "ICC Signature",
      value: (e, t) => Ls(e.buffer.slice(t, t + 4)),
    },
    40: {
      name: "Primary Platform",
      value: (e, t) => E(e, t, 4),
      description: (e) => Fe(e),
    },
    48: {
      name: "Device Manufacturer",
      value: (e, t) => E(e, t, 4),
      description: (e) => Fe(e),
    },
    52: { name: "Device Model Number", value: (e, t) => E(e, t, 4) },
    64: {
      name: "Rendering Intent",
      value: (e, t) => e.getUint32(t),
      description: (e) => {
        switch (e) {
          case 0:
            return "Perceptual";
          case 1:
            return "Relative Colorimetric";
          case 2:
            return "Saturation";
          case 3:
            return "Absolute Colorimetric";
          default:
            return e;
        }
      },
    },
    80: { name: "Profile Creator", value: (e, t) => E(e, t, 4) },
  };
function Us(e, t) {
  const n = e.getUint16(t),
    r = e.getUint16(t + 2) - 1,
    i = e.getUint16(t + 4),
    o = e.getUint16(t + 6),
    s = e.getUint16(t + 8),
    u = e.getUint16(t + 10);
  return new Date(Date.UTC(n, r, i, o, s, u));
}
function Ls(e) {
  return String.fromCharCode.apply(null, new Uint8Array(e));
}
function Fe(e) {
  switch (e.toLowerCase()) {
    case "appl":
      return "Apple";
    case "adbe":
      return "Adobe";
    case "msft":
      return "Microsoft";
    case "sunw":
      return "Sun Microsystems";
    case "sgi":
      return "Silicon Graphics";
    case "tgnt":
      return "Taligent";
    default:
      return e;
  }
}
const bt = { read: Ys },
  Ms = 84,
  Bs = 128,
  Gs = "acsp",
  ks = "desc",
  Zs = "mluc",
  Hs = "text",
  $s = "sig ",
  Xs = 12;
function Ys(e, t, n) {
  return n && t[0].compressionMethod !== ue ? Ks(e, t) : Ws(e, t);
}
function Ks(e, t) {
  if (!zs(t[0].compressionMethod)) return {};
  const n = new DataView(
    e.buffer.slice(t[0].offset, t[0].offset + t[0].length),
  );
  return Xt(n, t[0].compressionMethod, "utf-8", "dataview")
    .then(Nn)
    .catch(() => ({}));
}
function zs(e) {
  return e === $t;
}
function Ws(e, t) {
  try {
    const n = t.reduce((s, u) => s + u.length, 0),
      r = new Uint8Array(n);
    let i = 0;
    const o = js(e);
    for (let s = 1; s <= t.length; s++) {
      const u = t.find((a) => a.chunkNumber === s);
      if (!u) throw new Error(`ICC chunk ${s} not found`);
      const f = o.slice(u.offset, u.offset + u.length),
        l = new Uint8Array(f);
      (r.set(l, i), (i += l.length));
    }
    return Nn(new DataView(r.buffer));
  } catch {
    return {};
  }
}
function js(e) {
  return Array.isArray(e)
    ? new DataView(Uint8Array.from(e).buffer).buffer
    : e.buffer;
}
function Js(e) {
  return e.length < Bs + 4;
}
function vs(e, t) {
  return e.length < t + Xs;
}
function Nn(e) {
  const t = e.buffer,
    n = e.getUint32();
  if (e.byteLength !== n) throw new Error("ICC profile length not matching");
  if (e.length < Ms) throw new Error("ICC profile too short");
  const r = {},
    i = Object.keys(Pt);
  for (let f = 0; f < i.length; f++) {
    const l = i[f],
      a = Pt[l],
      p = a.value(e, parseInt(l, 10));
    let g = p;
    (a.description && (g = a.description(p)),
      (r[a.name] = { value: p, description: g }));
  }
  if (ie(t.slice(36, 40)) !== Gs)
    throw new Error("ICC profile: missing signature");
  if (Js(t)) return r;
  const s = e.getUint32(128);
  let u = 132;
  for (let f = 0; f < s; f++) {
    if (vs(t, u)) return r;
    const l = E(e, u, 4),
      a = e.getUint32(u + 4),
      p = e.getUint32(u + 8);
    if (a > t.length) return r;
    const g = E(e, a, 4);
    if (g === ks) {
      const S = e.getUint32(a + 8);
      if (S > p) return r;
      const F = ie(t.slice(a + 12, a + S + 11));
      J(r, l, F);
    } else if (g === Zs) {
      const S = e.getUint32(a + 8),
        F = e.getUint32(a + 12);
      let C = a + 16;
      const A = [];
      for (let b = 0; b < S; b++) {
        const N = E(e, C + 0, 2),
          w = E(e, C + 2, 2),
          Q = e.getUint32(C + 4),
          V = e.getUint32(C + 8),
          ee = Un(e, a + V, Q);
        (A.push({ languageCode: N, countryCode: w, text: ee }), (C += F));
      }
      if (S === 1) J(r, l, A[0].text);
      else {
        const b = {};
        for (let N = 0; N < A.length; N++)
          b[`${A[N].languageCode}-${A[N].countryCode}`] = A[N].text;
        J(r, l, b);
      }
    } else if (g === Hs) {
      const S = ie(t.slice(a + 8, a + p - 7));
      J(r, l, S);
    } else if (g === $s) {
      const S = ie(t.slice(a + 8, a + 12));
      J(r, l, S);
    }
    u = u + 12;
  }
  return r;
}
function ie(e) {
  return String.fromCharCode.apply(null, new Uint8Array(e));
}
function J(e, t, n) {
  Ct[t]
    ? (e[Ct[t].name] = { value: n, description: n })
    : (e[t] = { value: n, description: n });
}
const se = 27,
  qs = { read: ws, SHOT_INFO_AUTO_ROTATE: se };
function ws(e, t, n, r, i) {
  let o = H(e, sn, t, t + n, r, i);
  return (
    o.ShotInfo && ((o = x({}, o, Qs(o.ShotInfo.value))), delete o.ShotInfo),
    o
  );
}
function Qs(e) {
  const t = {};
  return (
    e[se] !== void 0 &&
      (t.AutoRotate = { value: e[se], description: Vs(e[se]) }),
    t
  );
}
function Vs(e) {
  return e === 0
    ? "None"
    : e === 1
      ? "Rotate 90 CW"
      : e === 2
        ? "Rotate 180"
        : e === 3
          ? "Rotate 270 CW"
          : "Unknown";
}
const eu = { read: tu };
function tu(e, t) {
  return {
    "Image Width": nu(e, t),
    "Image Height": ru(e, t),
    "Bit Depth": iu(e, t),
    "Color Type": ou(e, t),
    Compression: su(e, t),
    Filter: uu(e, t),
    Interlace: cu(e, t),
  };
}
function nu(e, t) {
  if (t + 0 + 4 > e.byteLength) return;
  const i = c.getLongAt(e, t);
  return { value: i, description: `${i}px` };
}
function ru(e, t) {
  if (t + 4 + 4 > e.byteLength) return;
  const i = c.getLongAt(e, t + 4);
  return { value: i, description: `${i}px` };
}
function iu(e, t) {
  if (t + 8 + 1 > e.byteLength) return;
  const i = c.getByteAt(e, t + 8);
  return { value: i, description: `${i}` };
}
function ou(e, t) {
  const i = {
    0: "Grayscale",
    2: "RGB",
    3: "Palette",
    4: "Grayscale with Alpha",
    6: "RGB with Alpha",
  };
  if (t + 9 + 1 > e.byteLength) return;
  const o = c.getByteAt(e, t + 9);
  return { value: o, description: i[o] || "Unknown" };
}
function su(e, t) {
  if (t + 10 + 1 > e.byteLength) return;
  const i = c.getByteAt(e, t + 10);
  return { value: i, description: i === 0 ? "Deflate/Inflate" : "Unknown" };
}
function uu(e, t) {
  if (t + 11 + 1 > e.byteLength) return;
  const i = c.getByteAt(e, t + 11);
  return { value: i, description: i === 0 ? "Adaptive" : "Unknown" };
}
function cu(e, t) {
  const i = { 0: "Noninterlaced", 1: "Adam7 Interlace" };
  if (t + 12 + 1 > e.byteLength) return;
  const o = c.getByteAt(e, t + 12);
  return { value: o, description: i[o] || "Unknown" };
}
const fu = { read: gu },
  Be = "STATE_KEYWORD",
  Ge = "STATE_COMPRESSION",
  ke = "STATE_LANG",
  au = "STATE_TRANSLATED_KEYWORD",
  Ze = "STATE_TEXT",
  lu = 1,
  du = 1,
  pu = 6;
function gu(e, t, n, r) {
  const i = {},
    o = [];
  for (let s = 0; s < t.length; s++) {
    const { offset: u, length: f, type: l } = t[s],
      a = mu(e, u, f, l, n);
    if (a instanceof Promise)
      o.push(
        a.then(({ name: p, value: g, description: S }) => {
          try {
            if (Je.USE_EXIF && Nt(p, g))
              return { __exif: an.read(Rt(g), pu, r).tags };
            if (Je.USE_IPTC && Ot(p, g))
              return { __iptc: Le.read(Rt(g), 0, r) };
            if (p && !Nt(p, g) && !Ot(p, g))
              return { [p]: { value: g, description: S } };
          } catch {}
          return {};
        }),
      );
    else {
      const { name: p, value: g, description: S } = a;
      p && (i[p] = { value: g, description: S });
    }
  }
  return {
    readTags: i,
    readTagsPromise: o.length > 0 ? Promise.all(o) : void 0,
  };
}
function mu(e, t, n, r, i) {
  const o = [],
    s = [];
  let u,
    f = Be,
    l = ue;
  for (let p = 0; p < n && t + p < e.byteLength; p++) {
    if (f === Ge) {
      ((l = Eu({ type: r, dataView: e, offset: t + p })),
        r === k && (p += lu),
        (f = yt(r, f)));
      continue;
    } else if (f === Ze) {
      u = new DataView(e.buffer.slice(t + p, t + n));
      break;
    }
    const g = e.getUint8(t + p);
    g === 0 ? (f = yt(r, f)) : f === Be ? o.push(g) : f === ke && s.push(g);
  }
  if (l !== ue && !i) return {};
  const a = Xt(u, l, Su(r));
  return a instanceof Promise
    ? a
        .then((p) => _e(p, r, s, o))
        .catch(() => _e("<text using unknown compression>".split(""), r, s, o))
    : _e(a, r, s, o);
}
function Eu({ type: e, dataView: t, offset: n }) {
  if (e === k) {
    if (t.getUint8(n) === du) return t.getUint8(n + 1);
  } else if (e === le) return t.getUint8(n);
  return ue;
}
function yt(e, t) {
  return t === Be && [k, le].includes(e)
    ? Ge
    : t === Ge
      ? e === k
        ? ke
        : Ze
      : t === ke
        ? au
        : Ze;
}
function Su(e) {
  return e === $e || e === le ? "latin1" : "utf-8";
}
function _e(e, t, n, r) {
  const i = Iu(e);
  return { name: xu(t, n, r), value: i, description: t === k ? hu(e) : i };
}
function xu(e, t, n) {
  const r = W(n);
  if (e === $e || t.length === 0) return r;
  const i = W(t);
  return `${r} (${i})`;
}
function Iu(e) {
  return e instanceof DataView ? E(e, 0, e.byteLength) : e;
}
function hu(e) {
  return ln.decode("UTF-8", e);
}
function Nt(e, t) {
  return (
    e.toLowerCase() === "raw profile type exif" && t.substring(1, 5) === "exif"
  );
}
function Ot(e, t) {
  return (
    e.toLowerCase() === "raw profile type iptc" && t.substring(1, 5) === "iptc"
  );
}
function Rt(e) {
  const t = e.match(/\n(exif|iptc)\n\s*\d+\n([\s\S]*)$/);
  return Tu(t[2].replace(/\n/g, ""));
}
function Tu(e) {
  const t = new DataView(new ArrayBuffer(e.length / 2));
  for (let n = 0; n < e.length; n += 2)
    t.setUint8(n / 2, parseInt(e.substring(n, n + 2), 16));
  return t;
}
const Fu = { read: _u };
function _u(e, t) {
  const n = {};
  for (let r = 0; r < t.length; r++) {
    const i = c.getLongAt(e, t[r] + K),
      o = E(e, t[r] + B, y);
    o === Jt
      ? ((n["Pixels Per Unit X"] = Au(e, t[r], i)),
        (n["Pixels Per Unit Y"] = Cu(e, t[r], i)),
        (n["Pixel Units"] = Pu(e, t[r], i)))
      : o === vt && (n["Modify Date"] = bu(e, t[r], i));
  }
  return n;
}
function Au(e, t, n) {
  if (!Ee(e, t, n, 0, 4)) return;
  const o = c.getLongAt(e, t + T + 0);
  return { value: o, description: "" + o };
}
function Cu(e, t, n) {
  if (!Ee(e, t, n, 4, 4)) return;
  const o = c.getLongAt(e, t + T + 4);
  return { value: o, description: "" + o };
}
function Pu(e, t, n) {
  if (!Ee(e, t, n, 8, 1)) return;
  const o = c.getByteAt(e, t + T + 8);
  return { value: o, description: o === 1 ? "meters" : "Unknown" };
}
function bu(e, t, n) {
  if (!Ee(e, t, n, 0, 7)) return;
  const i = c.getShortAt(e, t + T),
    o = c.getByteAt(e, t + T + 2),
    s = c.getByteAt(e, t + T + 3),
    u = c.getByteAt(e, t + T + 4),
    f = c.getByteAt(e, t + T + 5),
    l = c.getByteAt(e, t + T + 6);
  return {
    value: [i, o, s, u, f, l],
    description: `${X(i, 4)}-${X(o, 2)}-${X(s, 2)} ${X(u, 2)}:${X(f, 2)}:${X(l, 2)}`,
  };
}
function Ee(e, t, n, r, i) {
  return r + i <= n && t + T + r + i <= e.byteLength;
}
function X(e, t) {
  return `${"0".repeat(t - ("" + e).length)}${e}`;
}
const yu = { read: Ru },
  Nu = 4,
  Ou = 7;
function Ru(e, t) {
  const n = {},
    r = c.getByteAt(e, t);
  return (
    (n.Alpha = Du(r)),
    (n.Animation = Uu(r)),
    (n.ImageWidth = Dt(e, t + Nu)),
    (n.ImageHeight = Dt(e, t + Ou)),
    n
  );
}
function Du(e) {
  const t = e & 16;
  return { value: t ? 1 : 0, description: t ? "Yes" : "No" };
}
function Uu(e) {
  const t = e & 2;
  return { value: t ? 1 : 0, description: t ? "Yes" : "No" };
}
function Dt(e, t) {
  const n =
    c.getByteAt(e, t) +
    256 * c.getByteAt(e, t + 1) +
    65536 * c.getByteAt(e, t + 2) +
    1;
  return { value: n, description: n + "px" };
}
const Lu = { read: Mu };
function Mu(e) {
  return {
    "GIF Version": Bu(e),
    "Image Width": Gu(e),
    "Image Height": ku(e),
    "Global Color Map": Zu(e),
    "Bits Per Pixel": $u(e),
    "Color Resolution Depth": Hu(e),
  };
}
function Bu(e) {
  if (6 > e.byteLength) return;
  const r = E(e, 3, 3);
  return { value: r, description: r };
}
function Gu(e) {
  if (8 > e.byteLength) return;
  const r = e.getUint16(6, !0);
  return { value: r, description: `${r}px` };
}
function ku(e) {
  if (10 > e.byteLength) return;
  const r = e.getUint16(8, !0);
  return { value: r, description: `${r}px` };
}
function Zu(e) {
  if (11 > e.byteLength) return;
  const i = (e.getUint8(10) & 128) >>> 7;
  return { value: i, description: i === 1 ? "Yes" : "No" };
}
function Hu(e) {
  if (11 > e.byteLength) return;
  const i = ((e.getUint8(10) & 112) >>> 4) + 1;
  return { value: i, description: `${i} ${i === 1 ? "bit" : "bits"}` };
}
function $u(e) {
  if (11 > e.byteLength) return;
  const i = (e.getUint8(10) & 7) + 1;
  return { value: i, description: `${i} ${i === 1 ? "bit" : "bits"}` };
}
const Xu = [6, 7, 99],
  Yu = { get: Ku };
function Ku(e, t, n) {
  if (zu(t)) {
    t.type = "image/jpeg";
    const r = n + t.JPEGInterchangeFormat.value;
    ((t.image = e.buffer.slice(r, r + t.JPEGInterchangeFormatLength.value)),
      kt(t, "base64", function () {
        return Zt(this.image);
      }));
  }
  return t;
}
function zu(e) {
  return (
    e &&
    (e.Compression === void 0 || Xu.includes(e.Compression.value)) &&
    e.JPEGInterchangeFormat &&
    e.JPEGInterchangeFormat.value &&
    e.JPEGInterchangeFormatLength &&
    e.JPEGInterchangeFormatLength.value
  );
}
function On(e) {
  ((this.name = "MetadataMissingError"),
    (this.message = e || "No Exif data"),
    (this.stack = new Error().stack));
}
On.prototype = new Error();
const We = { MetadataMissingError: On },
  Sc = { load: Wu, loadView: Rn, errors: We },
  xc = We;
function Wu(e, t = {}) {
  return ju(e)
    ? ((t.async = !0), Ju(e, t).then((n) => Ae(n, t)))
    : tc(e)
      ? ((t.async = !0), nc(e).then((n) => Ae(n, t)))
      : Ae(e, t);
}
function ju(e) {
  return typeof e == "string";
}
function Ju(e, t) {
  return /^\w+:\/\//.test(e)
    ? typeof fetch < "u"
      ? vu(e, t)
      : qu(e, t)
    : Qu(e)
      ? Promise.resolve(Ln(e))
      : Vu(e, t);
}
function vu(e, { length: t } = {}) {
  const n = { method: "GET" };
  return (
    Number.isInteger(t) &&
      t >= 0 &&
      (n.headers = { range: `bytes=0-${t - 1}` }),
    fetch(e, n).then((r) => r.arrayBuffer())
  );
}
function qu(e, { length: t } = {}) {
  return new Promise((n, r) => {
    const i = {};
    (Number.isInteger(t) &&
      t >= 0 &&
      (i.headers = { range: `bytes=0-${t - 1}` }),
      wu(e)(e, i, (s) => {
        if (s.statusCode >= 200 && s.statusCode <= 299) {
          const u = [];
          (s.on("data", (f) => u.push(Buffer.from(f))),
            s.on("error", (f) => r(f)),
            s.on("end", () => n(Buffer.concat(u))));
        } else
          (r(`Could not fetch file: ${s.statusCode} ${s.statusMessage}`),
            s.resume());
      }).on("error", (s) => r(s)));
  });
}
function wu(e) {
  return /^https:\/\//.test(e)
    ? __non_webpack_require__("https").get
    : __non_webpack_require__("http").get;
}
function Qu(e) {
  return /^data:[^;,]*(;base64)?,/.test(e);
}
function Vu(e, { length: t } = {}) {
  return new Promise((n, r) => {
    const i = ec();
    i.open(e, (o, s) => {
      o
        ? r(o)
        : i.stat(e, (u, f) => {
            if (u) r(u);
            else {
              const l = Math.min(f.size, t !== void 0 ? t : f.size),
                a = Buffer.alloc(l),
                p = { buffer: a, length: l };
              i.read(s, p, (g) => {
                g
                  ? r(g)
                  : i.close(s, (S) => {
                      (S && console.warn(`Could not close file ${e}:`, S),
                        n(a));
                    });
              });
            }
          });
    });
  });
}
function ec() {
  try {
    return __non_webpack_require__("fs");
  } catch {
    return;
  }
}
function tc(e) {
  return typeof window < "u" && typeof File < "u" && e instanceof File;
}
function nc(e) {
  return new Promise((t, n) => {
    const r = new FileReader();
    ((r.onload = (i) => t(i.target.result)),
      (r.onerror = () => n(r.error)),
      r.readAsArrayBuffer(e));
  });
}
function Ae(e, t) {
  return (rc(e) && (e = new Uint8Array(e).buffer), Rn(ic(e), t));
}
function rc(e) {
  try {
    return Buffer.isBuffer(e);
  } catch {
    return !1;
  }
}
function ic(e) {
  try {
    return new DataView(e);
  } catch {
    return new Bt(e);
  }
}
function Rn(
  e,
  { expanded: t = !1, async: n = !1, includeUnknown: r = !1 } = {
    expanded: !1,
    async: !1,
    includeUnknown: !1,
  },
) {
  let i = !1,
    o = {};
  const s = [],
    {
      fileType: u,
      fileDataOffset: f,
      jfifDataOffset: l,
      tiffHeaderOffset: a,
      iptcDataOffset: p,
      xmpChunks: g,
      iccChunks: S,
      mpfDataOffset: F,
      pngHeaderOffset: C,
      pngTextChunks: A,
      pngChunkOffsets: b,
      vp8xChunkOffset: N,
      gifHeaderOffset: w,
    } = Pi.parseAppMarkers(e, n);
  if (oc(f)) {
    i = !0;
    const d = uo.read(e, f);
    t ? (o.file = d) : (o = x({}, o, d));
  }
  if (sc(l)) {
    i = !0;
    const d = xo.read(e, l);
    t ? (o.jfif = d) : (o = x({}, o, d));
  }
  if (uc(a)) {
    i = !0;
    const { tags: d, byteOrder: D } = an.read(e, a, r);
    if (
      (d.Thumbnail && ((o.Thumbnail = d.Thumbnail), delete d.Thumbnail),
      t ? ((o.exif = d), cc(o)) : (o = x({}, o, d)),
      d["IPTC-NAA"] && !Ut(p))
    ) {
      const I = Le.read(d["IPTC-NAA"].value, 0, r);
      t ? (o.iptc = I) : (o = x({}, o, I));
    }
    if (d.ApplicationNotes && !Lt(g)) {
      const I = _t.read(W(d.ApplicationNotes.value));
      t ? (o.xmp = I) : (delete I._raw, (o = x({}, o, I)));
    }
    if (d.ImageSourceData) {
      const I = ys.read(d.PhotoshopSettings.value, r);
      t ? (o.photoshop = I) : (o = x({}, o, I));
    }
    if (d.ICC_Profile && !Mt(S)) {
      const I = bt.read(d.ICC_Profile.value, [
        {
          offset: 0,
          length: d.ICC_Profile.value.length,
          chunkNumber: 1,
          chunksTotal: 1,
        },
      ]);
      t ? (o.icc = I) : (o = x({}, o, I));
    }
    if (fc(d)) {
      const I = qs.read(e, a, d.MakerNote.__offset, D, r);
      t ? (o.makerNotes = I) : (o = x({}, o, I));
    }
    d.MakerNote && delete d.MakerNote.__offset;
  }
  if (Ut(p)) {
    i = !0;
    const d = Le.read(e, p, r);
    t ? (o.iptc = d) : (o = x({}, o, d));
  }
  if (Lt(g)) {
    i = !0;
    const d = _t.read(e, g);
    t ? (o.xmp = d) : (delete d._raw, (o = x({}, o, d)));
  }
  if (Mt(S)) {
    i = !0;
    const d = bt.read(e, S, n);
    d instanceof Promise ? s.push(d.then(V)) : V(d);
  }
  if (ac(F)) {
    i = !0;
    const d = Vi.read(e, F, r);
    t ? (o.mpf = d) : (o = x({}, o, d));
  }
  if (lc(C)) {
    i = !0;
    const d = eu.read(e, C);
    t
      ? ((o.png = o.png ? x({}, o.png, d) : d), (o.pngFile = d))
      : (o = x({}, o, d));
  }
  if (dc(A)) {
    i = !0;
    const { readTags: d, readTagsPromise: D } = fu.read(e, A, n, r);
    (ee(d), D && s.push(D.then((I) => I.forEach(ee))));
  }
  if (pc(b)) {
    i = !0;
    const d = Fu.read(e, b);
    t ? (o.png = o.png ? x({}, o.png, d) : d) : (o = x({}, o, d));
  }
  if (gc(N)) {
    i = !0;
    const d = yu.read(e, N);
    t ? (o.riff = o.riff ? x({}, o.riff, d) : d) : (o = x({}, o, d));
  }
  if (mc(w)) {
    i = !0;
    const d = Lu.read(e, w);
    t ? (o.gif = o.gif ? x({}, o.gif, d) : d) : (o = x({}, o, d));
  }
  const Q = Yu.get(e, o.Thumbnail, a);
  if (
    (Q ? ((i = !0), (o.Thumbnail = Q)) : delete o.Thumbnail,
    u &&
      (t ? (o.file || (o.file = {}), (o.file.FileType = u)) : (o.FileType = u),
      (i = !0)),
    !i)
  )
    throw new We.MetadataMissingError();
  if (n) return Promise.all(s).then(() => o);
  return o;
  function V(d) {
    t ? (o.icc = d) : (o = x({}, o, d));
  }
  function ee(d) {
    if (t) {
      for (const D of ["exif", "iptc"]) {
        const I = `__${D}`;
        d[I] && ((o[D] = o[D] ? x({}, o.exif, d[I]) : d[I]), delete d[I]);
      }
      ((o.png = o.png ? x({}, o.png, d) : d),
        (o.pngText = o.pngText ? x({}, o.png, d) : d));
    } else
      ((o = x({}, o, d.__exif ? d.__exif : {}, d.__iptc ? d.__iptc : {}, d)),
        delete o.__exif,
        delete o.__iptc);
  }
}
function oc(e) {
  return e !== void 0;
}
function sc(e) {
  return e !== void 0;
}
function uc(e) {
  return e !== void 0;
}
function cc(e) {
  if (e.exif) {
    if (e.exif.GPSLatitude && e.exif.GPSLatitudeRef)
      try {
        ((e.gps = e.gps || {}),
          (e.gps.Latitude = ce(e.exif.GPSLatitude.value)),
          e.exif.GPSLatitudeRef.value.join("") === "S" &&
            (e.gps.Latitude = -e.gps.Latitude));
      } catch {}
    if (e.exif.GPSLongitude && e.exif.GPSLongitudeRef)
      try {
        ((e.gps = e.gps || {}),
          (e.gps.Longitude = ce(e.exif.GPSLongitude.value)),
          e.exif.GPSLongitudeRef.value.join("") === "W" &&
            (e.gps.Longitude = -e.gps.Longitude));
      } catch {}
    if (e.exif.GPSAltitude && e.exif.GPSAltitudeRef)
      try {
        ((e.gps = e.gps || {}),
          (e.gps.Altitude =
            e.exif.GPSAltitude.value[0] / e.exif.GPSAltitude.value[1]),
          e.exif.GPSAltitudeRef.value === 1 &&
            (e.gps.Altitude = -e.gps.Altitude));
      } catch {}
  }
}
function Ut(e) {
  return e !== void 0;
}
function Lt(e) {
  return Array.isArray(e) && e.length > 0;
}
function Mt(e) {
  return Array.isArray(e) && e.length > 0;
}
function fc(e) {
  return (
    e.Make &&
    e.Make.value &&
    Array.isArray(e.Make.value) &&
    e.Make.value[0] === "Canon" &&
    e.MakerNote &&
    e.MakerNote.__offset
  );
}
function ac(e) {
  return e !== void 0;
}
function lc(e) {
  return e !== void 0;
}
function dc(e) {
  return e !== void 0;
}
function pc(e) {
  return e !== void 0;
}
function gc(e) {
  return e !== void 0;
}
function mc(e) {
  return e !== void 0;
}
export { Sc as default, xc as errors, Wu as load, Rn as loadView };
//# sourceMappingURL=exif-reader-Cjo5XPQp.mjs.map
