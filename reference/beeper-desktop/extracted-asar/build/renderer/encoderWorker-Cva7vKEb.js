function At(_) {
  return _ && _.__esModule && Object.prototype.hasOwnProperty.call(_, "default")
    ? _.default
    : _;
}
function Dt(_) {
  if (Object.prototype.hasOwnProperty.call(_, "__esModule")) return _;
  var v = _.default;
  if (typeof v == "function") {
    var E = function w() {
      var p = !1;
      try {
        p = this instanceof w;
      } catch {}
      return p
        ? Reflect.construct(v, arguments, this.constructor)
        : v.apply(this, arguments);
    };
    E.prototype = v.prototype;
  } else E = {};
  return (
    Object.defineProperty(E, "__esModule", { value: !0 }),
    Object.keys(_).forEach(function (w) {
      var p = Object.getOwnPropertyDescriptor(_, w);
      Object.defineProperty(
        E,
        w,
        p.get
          ? p
          : {
              enumerable: !0,
              get: function () {
                return _[w];
              },
            },
      );
    }),
    E
  );
}
var ht, Ct;
function Pt() {
  if (Ct) return ht;
  Ct = 1;
  function _(l, c, a) {
    for (let m = 0; m < a.length; m++) l.setUint8(c + m, a.charCodeAt(m));
  }
  class v {
    constructor(c, a, m, y) {
      switch (((this._size = a), (this._module = c), this._size)) {
        case 1:
          this._heapArray = m ? this._module.HEAP8 : this._module.HEAPU8;
          break;
        case 2:
          this._heapArray = m ? this._module.HEAP16 : this._module.HEAPU16;
          break;
        case 4:
          this._heapArray = m ? this._module.HEAP32 : this._module.HEAPU32;
          break;
        default:
          this._heapArray = this._module.HEAPU8;
      }
      (y && ((this._size = 4), (this._heapArray = this._module.HEAPF32)),
        (this._pointer = this._module._malloc(a)));
    }
    free() {
      this._module._free(this.pointer);
    }
    get pointer() {
      return this._pointer;
    }
    get value() {
      let c = 0;
      switch (this._size) {
        case 2:
          c = 1;
          break;
        case 4:
          c = 2;
          break;
        default:
          throw new Error("Pointer can be only deferenced as integer-sized");
      }
      return this._heapArray[this.pointer >> c];
    }
    set value(c) {
      let a = 0;
      switch (this._size) {
        case 2:
          a = 1;
          break;
        case 4:
          a = 2;
          break;
        default:
          throw new Error("Pointer can be only deferenced as integer-sized");
      }
      this._heapArray[this.pointer >> a] = c;
    }
  }
  class E extends v {
    constructor(c, a) {
      (super(c, 4, !0, !1), typeof a < "u" && (this.value = a));
    }
  }
  class w extends v {
    constructor(c, a) {
      (super(c, 4, !1, !1), typeof a < "u" && (this.value = a));
    }
  }
  class p extends v {
    constructor(c, a, m, y, T) {
      super(c, a * m, y, T);
      let R = 0;
      switch (m) {
        case 1:
          ((this._heapArray = y ? this._module.HEAP8 : this._module.HEAPU8),
            (R = 0));
          break;
        case 2:
          ((this._heapArray = y ? this._module.HEAP16 : this._module.HEAPU16),
            (R = 1));
          break;
        case 4:
          ((this._heapArray = y ? this._module.HEAP32 : this._module.HEAPU32),
            (R = 2));
          break;
        default:
          throw new Error("Unit size must be an integer-size");
      }
      T && ((this._heapArray = this._module.HEAPF32), (R = 2));
      let b = this._pointer >> R;
      ((this._buffer = this._heapArray.subarray(b, b + a)), (this._length = a));
    }
    set(c, a) {
      this._buffer.set(c, a);
    }
    subarray(c, a) {
      return this._buffer.subarray(c, a);
    }
    get length() {
      return this._length;
    }
  }
  class e extends p {
    constructor(c, a) {
      super(c, a, 4, !0, !0);
    }
  }
  class i extends p {
    constructor(c, a) {
      super(c, a, 1, !1, !1);
    }
  }
  class f {
    constructor(c) {
      this._module = c;
    }
    mallocInt32(c) {
      return new E(this._module, c);
    }
    mallocUint32(c) {
      return new w(this._module, c);
    }
    mallocUint8Buffer(c) {
      return new i(this._module, c);
    }
    mallocFloat32Buffer(c) {
      return new e(this._module, c);
    }
  }
  return ((ht = { writeString: _, EmscriptenMemoryAllocator: f }), ht);
}
var yt, Rt;
function jt() {
  if (Rt) return yt;
  Rt = 1;
  const { writeString: _ } = Pt(),
    v = Int16Array.BYTES_PER_ELEMENT;
  class E {
    constructor(e, i, f) {
      ((this.config = { inputSampleRate: e, channelCount: i }),
        (this.encodedBuffers = []));
    }
    encode(e) {
      const i = e[0].length,
        f = new ArrayBuffer(i * v * this.config.channelCount),
        l = new DataView(f);
      for (let c = 0; c < this.config.channelCount; c++) {
        let a = e[c];
        for (let m = 0; m < i; m++) {
          let y = (a[m] * 32767) | 0;
          y > 32767 ? (y = 32767) : y < -32768 && (y = -32768);
          const T = (m * this.config.channelCount + c) * v;
          l.setInt16(T, y | 0, !0);
        }
      }
      this.encodedBuffers.push(f);
    }
    getHeader() {
      let e = this.encodedBuffers.reduce((l, c) => l + c.byteLength, 0),
        i = new ArrayBuffer(44),
        f = new DataView(i);
      return (
        _(f, 0, "RIFF"),
        f.setUint32(4, 36 + e, !0),
        _(f, 8, "WAVE"),
        _(f, 12, "fmt "),
        f.setUint32(16, 16, !0),
        f.setUint16(20, 1, !0),
        f.setUint16(22, this.config.channelCount, !0),
        f.setUint32(24, this.config.inputSampleRate, !0),
        f.setUint32(
          28,
          this.config.inputSampleRate * v * this.config.channelCount,
          !0,
        ),
        f.setUint16(32, v * this.config.channelCount, !0),
        f.setUint16(34, 8 * v, !0),
        _(f, 36, "data"),
        f.setUint32(40, e, !0),
        i
      );
    }
  }
  function w(p) {
    return new Promise(function (e, i) {
      ((p = typeof p < "u" ? p || {} : {}),
        (p.init = function (f, l, c) {
          p.encoder = new E(f, l, c);
        }),
        (p.encode = function (f) {
          p.encoder.encode(f);
        }),
        (p.flush = function () {
          let f = p.encoder.getHeader(),
            l = p.encoder.encodedBuffers.splice(
              0,
              p.encoder.encodedBuffers.length,
            );
          return [f, ...l];
        }),
        (p.close = function () {}),
        e(p));
    });
  }
  return ((yt = w), yt);
}
var Wt = jt(),
  Ht = At(Wt);
function kt(_) {
  return _ && _.__esModule && Object.prototype.hasOwnProperty.call(_, "default")
    ? _.default
    : _;
}
var Bt = { exports: {} },
  O = (Bt.exports = {}),
  Q,
  K;
function bt() {
  throw new Error("setTimeout has not been defined");
}
function Et() {
  throw new Error("clearTimeout has not been defined");
}
(function () {
  try {
    typeof setTimeout == "function" ? (Q = setTimeout) : (Q = bt);
  } catch {
    Q = bt;
  }
  try {
    typeof clearTimeout == "function" ? (K = clearTimeout) : (K = Et);
  } catch {
    K = Et;
  }
})();
function xt(_) {
  if (Q === setTimeout) return setTimeout(_, 0);
  if ((Q === bt || !Q) && setTimeout)
    return ((Q = setTimeout), setTimeout(_, 0));
  try {
    return Q(_, 0);
  } catch {
    try {
      return Q.call(null, _, 0);
    } catch {
      return Q.call(this, _, 0);
    }
  }
}
function qt(_) {
  if (K === clearTimeout) return clearTimeout(_);
  if ((K === Et || !K) && clearTimeout)
    return ((K = clearTimeout), clearTimeout(_));
  try {
    return K(_);
  } catch {
    try {
      return K.call(null, _);
    } catch {
      return K.call(this, _);
    }
  }
}
var oe = [],
  ve = !1,
  pe,
  ke = -1;
function zt() {
  !ve ||
    !pe ||
    ((ve = !1),
    pe.length ? (oe = pe.concat(oe)) : (ke = -1),
    oe.length && Ut());
}
function Ut() {
  if (!ve) {
    var _ = xt(zt);
    ve = !0;
    for (var v = oe.length; v;) {
      for (pe = oe, oe = []; ++ke < v;) pe && pe[ke].run();
      ((ke = -1), (v = oe.length));
    }
    ((pe = null), (ve = !1), qt(_));
  }
}
O.nextTick = function (_) {
  var v = new Array(arguments.length - 1);
  if (arguments.length > 1)
    for (var E = 1; E < arguments.length; E++) v[E - 1] = arguments[E];
  (oe.push(new Ft(_, v)), oe.length === 1 && !ve && xt(Ut));
};
function Ft(_, v) {
  ((this.fun = _), (this.array = v));
}
Ft.prototype.run = function () {
  this.fun.apply(null, this.array);
};
O.title = "browser";
O.browser = !0;
O.env = {};
O.argv = [];
O.version = "";
O.versions = {};
function se() {}
O.on = se;
O.addListener = se;
O.once = se;
O.off = se;
O.removeListener = se;
O.removeAllListeners = se;
O.emit = se;
O.prependListener = se;
O.prependOnceListener = se;
O.listeners = function (_) {
  return [];
};
O.binding = function (_) {
  throw new Error("process.binding is not supported");
};
O.cwd = function () {
  return "/";
};
O.chdir = function (_) {
  throw new Error("process.chdir is not supported");
};
O.umask = function () {
  return 0;
};
var Vt = Bt.exports;
const x = kt(Vt);
var vt = { exports: {} },
  gt,
  It;
function qe() {
  if (It) return gt;
  It = 1;
  function _(p) {
    if (typeof p != "string")
      throw new TypeError(
        "Path must be a string. Received " + JSON.stringify(p),
      );
  }
  function v(p, e) {
    for (var i = "", f = 0, l = -1, c = 0, a, m = 0; m <= p.length; ++m) {
      if (m < p.length) a = p.charCodeAt(m);
      else {
        if (a === 47) break;
        a = 47;
      }
      if (a === 47) {
        if (!(l === m - 1 || c === 1))
          if (l !== m - 1 && c === 2) {
            if (
              i.length < 2 ||
              f !== 2 ||
              i.charCodeAt(i.length - 1) !== 46 ||
              i.charCodeAt(i.length - 2) !== 46
            ) {
              if (i.length > 2) {
                var y = i.lastIndexOf("/");
                if (y !== i.length - 1) {
                  (y === -1
                    ? ((i = ""), (f = 0))
                    : ((i = i.slice(0, y)),
                      (f = i.length - 1 - i.lastIndexOf("/"))),
                    (l = m),
                    (c = 0));
                  continue;
                }
              } else if (i.length === 2 || i.length === 1) {
                ((i = ""), (f = 0), (l = m), (c = 0));
                continue;
              }
            }
            e && (i.length > 0 ? (i += "/..") : (i = ".."), (f = 2));
          } else
            (i.length > 0
              ? (i += "/" + p.slice(l + 1, m))
              : (i = p.slice(l + 1, m)),
              (f = m - l - 1));
        ((l = m), (c = 0));
      } else a === 46 && c !== -1 ? ++c : (c = -1);
    }
    return i;
  }
  function E(p, e) {
    var i = e.dir || e.root,
      f = e.base || (e.name || "") + (e.ext || "");
    return i ? (i === e.root ? i + f : i + p + f) : f;
  }
  var w = {
    resolve: function () {
      for (
        var e = "", i = !1, f, l = arguments.length - 1;
        l >= -1 && !i;
        l--
      ) {
        var c;
        (l >= 0 ? (c = arguments[l]) : (f === void 0 && (f = x.cwd()), (c = f)),
          _(c),
          c.length !== 0 && ((e = c + "/" + e), (i = c.charCodeAt(0) === 47)));
      }
      return (
        (e = v(e, !i)),
        i ? (e.length > 0 ? "/" + e : "/") : e.length > 0 ? e : "."
      );
    },
    normalize: function (e) {
      if ((_(e), e.length === 0)) return ".";
      var i = e.charCodeAt(0) === 47,
        f = e.charCodeAt(e.length - 1) === 47;
      return (
        (e = v(e, !i)),
        e.length === 0 && !i && (e = "."),
        e.length > 0 && f && (e += "/"),
        i ? "/" + e : e
      );
    },
    isAbsolute: function (e) {
      return (_(e), e.length > 0 && e.charCodeAt(0) === 47);
    },
    join: function () {
      if (arguments.length === 0) return ".";
      for (var e, i = 0; i < arguments.length; ++i) {
        var f = arguments[i];
        (_(f), f.length > 0 && (e === void 0 ? (e = f) : (e += "/" + f)));
      }
      return e === void 0 ? "." : w.normalize(e);
    },
    relative: function (e, i) {
      if (
        (_(e),
        _(i),
        e === i || ((e = w.resolve(e)), (i = w.resolve(i)), e === i))
      )
        return "";
      for (var f = 1; f < e.length && e.charCodeAt(f) === 47; ++f);
      for (
        var l = e.length, c = l - f, a = 1;
        a < i.length && i.charCodeAt(a) === 47;
        ++a
      );
      for (
        var m = i.length, y = m - a, T = c < y ? c : y, R = -1, b = 0;
        b <= T;
        ++b
      ) {
        if (b === T) {
          if (y > T) {
            if (i.charCodeAt(a + b) === 47) return i.slice(a + b + 1);
            if (b === 0) return i.slice(a + b);
          } else
            c > T &&
              (e.charCodeAt(f + b) === 47 ? (R = b) : b === 0 && (R = 0));
          break;
        }
        var de = e.charCodeAt(f + b),
          k = i.charCodeAt(a + b);
        if (de !== k) break;
        de === 47 && (R = b);
      }
      var I = "";
      for (b = f + R + 1; b <= l; ++b)
        (b === l || e.charCodeAt(b) === 47) &&
          (I.length === 0 ? (I += "..") : (I += "/.."));
      return I.length > 0
        ? I + i.slice(a + R)
        : ((a += R), i.charCodeAt(a) === 47 && ++a, i.slice(a));
    },
    _makeLong: function (e) {
      return e;
    },
    dirname: function (e) {
      if ((_(e), e.length === 0)) return ".";
      for (
        var i = e.charCodeAt(0), f = i === 47, l = -1, c = !0, a = e.length - 1;
        a >= 1;
        --a
      )
        if (((i = e.charCodeAt(a)), i === 47)) {
          if (!c) {
            l = a;
            break;
          }
        } else c = !1;
      return l === -1 ? (f ? "/" : ".") : f && l === 1 ? "//" : e.slice(0, l);
    },
    basename: function (e, i) {
      if (i !== void 0 && typeof i != "string")
        throw new TypeError('"ext" argument must be a string');
      _(e);
      var f = 0,
        l = -1,
        c = !0,
        a;
      if (i !== void 0 && i.length > 0 && i.length <= e.length) {
        if (i.length === e.length && i === e) return "";
        var m = i.length - 1,
          y = -1;
        for (a = e.length - 1; a >= 0; --a) {
          var T = e.charCodeAt(a);
          if (T === 47) {
            if (!c) {
              f = a + 1;
              break;
            }
          } else
            (y === -1 && ((c = !1), (y = a + 1)),
              m >= 0 &&
                (T === i.charCodeAt(m)
                  ? --m === -1 && (l = a)
                  : ((m = -1), (l = y))));
        }
        return (f === l ? (l = y) : l === -1 && (l = e.length), e.slice(f, l));
      } else {
        for (a = e.length - 1; a >= 0; --a)
          if (e.charCodeAt(a) === 47) {
            if (!c) {
              f = a + 1;
              break;
            }
          } else l === -1 && ((c = !1), (l = a + 1));
        return l === -1 ? "" : e.slice(f, l);
      }
    },
    extname: function (e) {
      _(e);
      for (
        var i = -1, f = 0, l = -1, c = !0, a = 0, m = e.length - 1;
        m >= 0;
        --m
      ) {
        var y = e.charCodeAt(m);
        if (y === 47) {
          if (!c) {
            f = m + 1;
            break;
          }
          continue;
        }
        (l === -1 && ((c = !1), (l = m + 1)),
          y === 46
            ? i === -1
              ? (i = m)
              : a !== 1 && (a = 1)
            : i !== -1 && (a = -1));
      }
      return i === -1 ||
        l === -1 ||
        a === 0 ||
        (a === 1 && i === l - 1 && i === f + 1)
        ? ""
        : e.slice(i, l);
    },
    format: function (e) {
      if (e === null || typeof e != "object")
        throw new TypeError(
          'The "pathObject" argument must be of type Object. Received type ' +
            typeof e,
        );
      return E("/", e);
    },
    parse: function (e) {
      _(e);
      var i = { root: "", dir: "", base: "", ext: "", name: "" };
      if (e.length === 0) return i;
      var f = e.charCodeAt(0),
        l = f === 47,
        c;
      l ? ((i.root = "/"), (c = 1)) : (c = 0);
      for (
        var a = -1, m = 0, y = -1, T = !0, R = e.length - 1, b = 0;
        R >= c;
        --R
      ) {
        if (((f = e.charCodeAt(R)), f === 47)) {
          if (!T) {
            m = R + 1;
            break;
          }
          continue;
        }
        (y === -1 && ((T = !1), (y = R + 1)),
          f === 46
            ? a === -1
              ? (a = R)
              : b !== 1 && (b = 1)
            : a !== -1 && (b = -1));
      }
      return (
        a === -1 ||
        y === -1 ||
        b === 0 ||
        (b === 1 && a === y - 1 && a === m + 1)
          ? y !== -1 &&
            (m === 0 && l
              ? (i.base = i.name = e.slice(1, y))
              : (i.base = i.name = e.slice(m, y)))
          : (m === 0 && l
              ? ((i.name = e.slice(1, a)), (i.base = e.slice(1, y)))
              : ((i.name = e.slice(m, a)), (i.base = e.slice(m, y))),
            (i.ext = e.slice(a, y))),
        m > 0 ? (i.dir = e.slice(0, m - 1)) : l && (i.dir = "/"),
        i
      );
    },
    sep: "/",
    delimiter: ":",
    win32: null,
    posix: null,
  };
  return ((w.posix = w), (gt = w), gt);
}
const Mt = new Proxy(
    {},
    {
      get:
        (_, v) =>
        (...E) =>
          globalThis.rt.callObjProxyMethod({
            objName: "fsp",
            methodName: v,
            args: E,
          }),
    },
  ),
  Lt = new Proxy(
    {},
    {
      get: (_, v) => (E, w) => {
        Mt[v](E)
          .then((p) => {
            w(null, p);
          })
          .catch((p) => {
            w(p, void 0);
          });
      },
    },
  ),
  {
    access: Gt,
    copyFile: Yt,
    cp: $t,
    link: Xt,
    mkdir: Qt,
    readFile: Kt,
    readdir: Zt,
    realpath: Jt,
    rename: er,
    rm: tr,
    stat: rr,
    symlink: nr,
    unlink: ir,
    writeFile: or,
  } = Mt;
var sr = Object.freeze({
  __proto__: null,
  access: Gt,
  copyFile: Yt,
  cp: $t,
  fsCallbackProxy: Lt,
  link: Xt,
  mkdir: Qt,
  readFile: Kt,
  readdir: Zt,
  realpath: Jt,
  rename: er,
  rm: tr,
  stat: rr,
  symlink: nr,
  unlink: ir,
  writeFile: or,
});
const ar = new Proxy(
    {},
    {
      get:
        (_, v) =>
        (...E) => {
          throw Error(`fs.${String(v)} cannot be proxied`);
        },
    },
  ),
  ur = (..._) => {
    throw Error("fs.readFileSync cannot be proxied");
  },
  fr = () => {
    throw Error("fs.watch cannot be proxied");
  },
  { stat: cr } = Lt;
var lr = Object.freeze({
    __proto__: null,
    default: ar,
    promises: sr,
    readFileSync: ur,
    stat: cr,
    watch: fr,
  }),
  Nt = Dt(lr),
  Ot;
function _r() {
  return (
    Ot ||
      ((Ot = 1),
      (function (_, v) {
        var E = (function () {
          var w =
            typeof document < "u" && document.currentScript
              ? document.currentScript.src
              : void 0;
          return (
            typeof __filename < "u" && (w = w || __filename),
            function (e) {
              e = e || {};
              var e = typeof e < "u" ? e : {};
              const { EmscriptenMemoryAllocator: i } = Pt(),
                f = 2049,
                l = 48e3,
                c = 4e3,
                a = 20,
                m = 6,
                y = 4096,
                T = 0,
                R = 4002,
                b = 0;
              class de {
                constructor(r, o, d = void 0) {
                  ((this.config = { inputSampleRate: r, channelCount: o }),
                    (this.memory = new i(e)),
                    (this._opus_encoder_create = e._opus_encoder_create),
                    (this._opus_encoder_ctl = e._opus_encoder_ctl),
                    (this._opus_encode_float = e._opus_encode_float),
                    (this._opus_encoder_destroy = e._opus_encoder_destroy),
                    (this._speex_resampler_init = e._speex_resampler_init),
                    (this._speex_resampler_process_interleaved_float =
                      e._speex_resampler_process_interleaved_float),
                    (this._speex_resampler_destroy =
                      e._speex_resampler_destroy),
                    (this._container = new e.Container()),
                    this._container.init(
                      l,
                      o,
                      Math.floor(Math.random() * 4294967295),
                    ),
                    this.OpusInitCodec(l, o, d),
                    this.SpeexInitResampler(r, l, o),
                    (this.inputSamplesPerChannel = (r * a) / 1e3),
                    (this.outputSamplePerChannel = (l * a) / 1e3),
                    (this.inputBufferIndex = 0),
                    (this.mInputBuffer = this.memory.mallocFloat32Buffer(
                      this.inputSamplesPerChannel * o,
                    )),
                    (this.mResampledBuffer = this.memory.mallocFloat32Buffer(
                      this.outputSamplePerChannel * o,
                    )),
                    (this.mOutputBuffer = this.memory.mallocUint8Buffer(c)),
                    (this.interleavedBuffers =
                      o !== 1 ? new Float32Array(y * o) : void 0));
                }
                encode(r) {
                  let o = this.interleave(r),
                    d = 0;
                  for (; d < o.length;) {
                    let A = Math.min(
                      this.mInputBuffer.length - this.inputBufferIndex,
                      o.length - d,
                    );
                    if (
                      (this.mInputBuffer.set(
                        o.subarray(d, d + A),
                        this.inputBufferIndex,
                      ),
                      (this.inputBufferIndex += A),
                      this.inputBufferIndex >= this.mInputBuffer.length)
                    ) {
                      let C = this.memory.mallocUint32(
                          this.inputSamplesPerChannel,
                        ),
                        S = this.memory.mallocUint32(
                          this.outputSamplePerChannel,
                        ),
                        F = this._speex_resampler_process_interleaved_float(
                          this.resampler,
                          this.mInputBuffer.pointer,
                          C.pointer,
                          this.mResampledBuffer.pointer,
                          S.pointer,
                        );
                      if ((C.free(), S.free(), F !== b))
                        throw new Error("Resampling error.");
                      let q = this._opus_encode_float(
                        this.encoder,
                        this.mResampledBuffer.pointer,
                        this.outputSamplePerChannel,
                        this.mOutputBuffer.pointer,
                        this.mOutputBuffer.length,
                      );
                      if (q < 0) throw new Error("Opus encoding error.");
                      (this._container.writeFrame(
                        this.mOutputBuffer.pointer,
                        q,
                        this.outputSamplePerChannel,
                      ),
                        (this.inputBufferIndex = 0));
                    }
                    d += A;
                  }
                }
                close() {
                  const { channelCount: r } = this.config;
                  let o = [];
                  for (let d = 0; d < r; ++d)
                    o.push(new Float32Array(y - this.inputBufferIndex / r));
                  (this.encode(o),
                    e.destroy(this._container),
                    this.mInputBuffer.free(),
                    this.mResampledBuffer.free(),
                    this.mOutputBuffer.free(),
                    this._opus_encoder_destroy(this.encoder),
                    this._speex_resampler_destroy(this.resampler));
                }
                interleave(r) {
                  const o = r.length;
                  if (o === 1) return r[0];
                  for (let d = 0; d < o; d++) {
                    let A = r[d];
                    for (let C = 0; C < A.length; C++)
                      this.interleavedBuffers[C * o + d] = A[C];
                  }
                  return this.interleavedBuffers;
                }
                OpusInitCodec(r, o, d = void 0) {
                  let A = this.memory.mallocUint32(void 0);
                  this.encoder = this._opus_encoder_create(r, o, f, A.pointer);
                  let C = A.value;
                  if ((A.free(), C !== T))
                    throw new Error("Opus encodor initialization failed.");
                  d && this.OpusSetOpusControl(R, d);
                }
                OpusSetOpusControl(r, o) {
                  let d = this.memory.mallocInt32(o);
                  (this._opus_encoder_ctl(this.encoder, r, d.pointer),
                    d.free());
                }
                SpeexInitResampler(r, o, d) {
                  let A = this.memory.mallocUint32(void 0);
                  this.resampler = this._speex_resampler_init(
                    d,
                    r,
                    o,
                    m,
                    A.pointer,
                  );
                  let C = A.value;
                  if ((A.free(), C !== b))
                    throw new Error("Initializing resampler failed.");
                }
              }
              ((e.init = function (t, r, o) {
                ((e.encodedBuffers = []), (e.encoder = new de(t, r, o)));
              }),
                (e.encode = function (t) {
                  e.encoder.encode(t);
                }),
                (e.flush = function () {
                  return e.encodedBuffers.splice(0, e.encodedBuffers.length);
                }),
                (e.close = function () {
                  e.encoder.close();
                }));
              var k = {},
                I;
              for (I in e) e.hasOwnProperty(I) && (k[I] = e[I]);
              var Z = !1,
                M = !1,
                ue = !1,
                ge = !1;
              ((Z = typeof window == "object"),
                (M = typeof importScripts == "function"),
                (ue =
                  typeof x == "object" &&
                  typeof x.versions == "object" &&
                  typeof x.versions.node == "string"),
                (ge = !Z && !ue && !M));
              var P = "";
              function ze(t) {
                return e.locateFile ? e.locateFile(t, P) : P + t;
              }
              var J, z, fe, ce;
              ue
                ? (M
                    ? (P = qe().dirname(P) + "/")
                    : (P = "/opt/ci/builds/builder/automattic/beeper/desktop/"),
                  (J = function (r, o) {
                    return (
                      fe || (fe = Nt),
                      ce || (ce = qe()),
                      (r = ce.normalize(r)),
                      fe.readFileSync(r, o ? null : "utf8")
                    );
                  }),
                  (z = function (r) {
                    var o = J(r, !0);
                    return (
                      o.buffer || (o = new Uint8Array(o)),
                      Ee(o.buffer),
                      o
                    );
                  }),
                  x.argv.length > 1 && x.argv[1].replace(/\\/g, "/"),
                  x.argv.slice(2),
                  x.on("uncaughtException", function (t) {
                    if (!(t instanceof mt)) throw t;
                  }),
                  x.on("unhandledRejection", j),
                  (e.inspect = function () {
                    return "[Emscripten Module object]";
                  }))
                : ge
                  ? (typeof read < "u" &&
                      (J = function (r) {
                        return read(r);
                      }),
                    (z = function (r) {
                      var o;
                      return typeof readbuffer == "function"
                        ? new Uint8Array(readbuffer(r))
                        : ((o = read(r, "binary")),
                          Ee(typeof o == "object"),
                          o);
                    }),
                    typeof scriptArgs < "u" && scriptArgs,
                    typeof print < "u" &&
                      (typeof console > "u" && (console = {}),
                      (console.log = print),
                      (console.warn = console.error =
                        typeof printErr < "u" ? printErr : print)))
                  : (Z || M) &&
                    (M
                      ? (P = self.location.href)
                      : document.currentScript &&
                        (P = document.currentScript.src),
                    w && (P = w),
                    P.indexOf("blob:") !== 0
                      ? (P = P.substr(0, P.lastIndexOf("/") + 1))
                      : (P = ""),
                    (J = function (r) {
                      var o = new XMLHttpRequest();
                      return (
                        o.open("GET", r, !1),
                        o.send(null),
                        o.responseText
                      );
                    }),
                    M &&
                      (z = function (r) {
                        var o = new XMLHttpRequest();
                        return (
                          o.open("GET", r, !1),
                          (o.responseType = "arraybuffer"),
                          o.send(null),
                          new Uint8Array(o.response)
                        );
                      }));
              var we = e.print || console.log.bind(console),
                L = e.printErr || console.warn.bind(console);
              for (I in k) k.hasOwnProperty(I) && (e[I] = k[I]);
              ((k = null),
                e.arguments && e.arguments,
                e.thisProgram && e.thisProgram,
                e.quit && e.quit);
              var V;
              (e.wasmBinary && (V = e.wasmBinary),
                e.noExitRuntime && e.noExitRuntime,
                typeof WebAssembly != "object" &&
                  L("no native wasm support detected"));
              var G,
                Ve = new WebAssembly.Table({
                  initial: 60,
                  maximum: 60,
                  element: "anyfunc",
                }),
                be = !1;
              function Ee(t, r) {
                t || j("Assertion failed: " + r);
              }
              var Ae =
                typeof TextDecoder < "u" ? new TextDecoder("utf8") : void 0;
              function Pe(t, r, o) {
                for (var d = r + o, A = r; t[A] && !(A >= d);) ++A;
                if (A - r > 16 && t.subarray && Ae)
                  return Ae.decode(t.subarray(r, A));
                for (var C = ""; r < A;) {
                  var S = t[r++];
                  if (!(S & 128)) {
                    C += String.fromCharCode(S);
                    continue;
                  }
                  var F = t[r++] & 63;
                  if ((S & 224) == 192) {
                    C += String.fromCharCode(((S & 31) << 6) | F);
                    continue;
                  }
                  var q = t[r++] & 63;
                  if (
                    ((S & 240) == 224
                      ? (S = ((S & 15) << 12) | (F << 6) | q)
                      : (S =
                          ((S & 7) << 18) |
                          (F << 12) |
                          (q << 6) |
                          (t[r++] & 63)),
                    S < 65536)
                  )
                    C += String.fromCharCode(S);
                  else {
                    var St = S - 65536;
                    C += String.fromCharCode(
                      55296 | (St >> 10),
                      56320 | (St & 1023),
                    );
                  }
                }
                return C;
              }
              function ee(t, r) {
                return t ? Pe(re, t, r) : "";
              }
              typeof TextDecoder < "u" && new TextDecoder("utf-16le");
              var Se = 65536,
                te,
                re,
                N;
              function Ge(t) {
                ((te = t),
                  (e.HEAP8 = new Int8Array(t)),
                  (e.HEAP16 = new Int16Array(t)),
                  (e.HEAP32 = N = new Int32Array(t)),
                  (e.HEAPU8 = re = new Uint8Array(t)),
                  (e.HEAPU16 = new Uint16Array(t)),
                  (e.HEAPU32 = new Uint32Array(t)),
                  (e.HEAPF32 = new Float32Array(t)),
                  (e.HEAPF64 = new Float64Array(t)));
              }
              var Ye = 5289024,
                $e = 45984,
                le = e.INITIAL_MEMORY || 16777216;
              (e.wasmMemory
                ? (G = e.wasmMemory)
                : (G = new WebAssembly.Memory({
                    initial: le / Se,
                    maximum: le / Se,
                  })),
                G && (te = G.buffer),
                (le = te.byteLength),
                Ge(te),
                (N[$e >> 2] = Ye));
              function ne(t) {
                for (; t.length > 0;) {
                  var r = t.shift();
                  if (typeof r == "function") {
                    r();
                    continue;
                  }
                  var o = r.func;
                  typeof o == "number"
                    ? r.arg === void 0
                      ? e.dynCall_v(o)
                      : e.dynCall_vi(o, r.arg)
                    : o(r.arg === void 0 ? null : r.arg);
                }
              }
              var Ce = [],
                Re = [],
                Xe = [],
                Ie = [];
              function Qe() {
                if (e.preRun)
                  for (
                    typeof e.preRun == "function" && (e.preRun = [e.preRun]);
                    e.preRun.length;
                  )
                    et(e.preRun.shift());
                ne(Ce);
              }
              function Ke() {
                ne(Re);
              }
              function Ze() {
                ne(Xe);
              }
              function Je() {
                if (e.postRun)
                  for (
                    typeof e.postRun == "function" && (e.postRun = [e.postRun]);
                    e.postRun.length;
                  )
                    tt(e.postRun.shift());
                ne(Ie);
              }
              function et(t) {
                Ce.unshift(t);
              }
              function tt(t) {
                Ie.unshift(t);
              }
              var D = 0,
                Y = null;
              function rt(t) {
                (D++, e.monitorRunDependencies && e.monitorRunDependencies(D));
              }
              function nt(t) {
                if (
                  (D--,
                  e.monitorRunDependencies && e.monitorRunDependencies(D),
                  D == 0 && Y)
                ) {
                  var r = Y;
                  ((Y = null), r());
                }
              }
              ((e.preloadedImages = {}), (e.preloadedAudios = {}));
              function j(t) {
                throw (
                  e.onAbort && e.onAbort(t),
                  (t += ""),
                  we(t),
                  L(t),
                  (be = !0),
                  (t =
                    "abort(" +
                    t +
                    "). Build with -s ASSERTIONS=1 for more info."),
                  new WebAssembly.RuntimeError(t)
                );
              }
              var Oe = "data:application/octet-stream;base64,";
              function Te(t) {
                return String.prototype.startsWith
                  ? t.startsWith(Oe)
                  : t.indexOf(Oe) === 0;
              }
              var B = "WebMOpusEncoder.wasm";
              Te(B) || (B = ze(B));
              function Be() {
                try {
                  if (V) return new Uint8Array(V);
                  if (z) return z(B);
                  throw "both async and sync fetching of the wasm failed";
                } catch (t) {
                  j(t);
                }
              }
              function it() {
                return !V && (Z || M) && typeof fetch == "function"
                  ? fetch(B, { credentials: "same-origin" })
                      .then(function (t) {
                        if (!t.ok)
                          throw (
                            "failed to load wasm binary file at '" + B + "'"
                          );
                        return t.arrayBuffer();
                      })
                      .catch(function () {
                        return Be();
                      })
                  : new Promise(function (t, r) {
                      t(Be());
                    });
              }
              function ot() {
                var t = { a: We };
                function r(S, F) {
                  var q = S.exports;
                  ((e.asm = q), nt());
                }
                rt();
                function o(S) {
                  r(S.instance);
                }
                function d(S) {
                  return it()
                    .then(function (F) {
                      return WebAssembly.instantiate(F, t);
                    })
                    .then(S, function (F) {
                      (L("failed to asynchronously prepare wasm: " + F), j(F));
                    });
                }
                function A() {
                  if (
                    !V &&
                    typeof WebAssembly.instantiateStreaming == "function" &&
                    !Te(B) &&
                    typeof fetch == "function"
                  )
                    fetch(B, { credentials: "same-origin" }).then(function (S) {
                      var F = WebAssembly.instantiateStreaming(S, t);
                      return F.then(o, function (q) {
                        (L("wasm streaming compile failed: " + q),
                          L("falling back to ArrayBuffer instantiation"),
                          d(o));
                      });
                    });
                  else return d(o);
                }
                if (e.instantiateWasm)
                  try {
                    var C = e.instantiateWasm(t, r);
                    return C;
                  } catch (S) {
                    return (
                      L(
                        "Module.instantiateWasm callback failed with error: " +
                          S,
                      ),
                      !1
                    );
                  }
                return (A(), {});
              }
              function st(t, r) {
                let o = new Uint8Array(e.HEAPU8.buffer, t, r);
                e.encodedBuffers.push(new Uint8Array(o).buffer);
              }
              Re.push({
                func: function () {
                  Ue();
                },
              });
              function at(t, r, o, d) {
                j(
                  "Assertion failed: " +
                    ee(t) +
                    ", at: " +
                    [
                      r ? ee(r) : "unknown filename",
                      o,
                      d ? ee(d) : "unknown function",
                    ],
                );
              }
              var $ = {
                mappings: {},
                buffers: [null, [], []],
                printChar: function (t, r) {
                  var o = $.buffers[t];
                  r === 0 || r === 10
                    ? ((t === 1 ? we : L)(Pe(o, 0)), (o.length = 0))
                    : o.push(r);
                },
                varargs: void 0,
                get: function () {
                  $.varargs += 4;
                  var t = N[($.varargs - 4) >> 2];
                  return t;
                },
                getStr: function (t) {
                  var r = ee(t);
                  return r;
                },
                get64: function (t, r) {
                  return t;
                },
              };
              function ut(t, r, o) {
                return (($.varargs = o), 0);
              }
              function ft(t, r, o) {
                $.varargs = o;
              }
              function ct(t, r, o) {
                return (($.varargs = o), 0);
              }
              function me() {
                j();
              }
              function lt(t, r, o) {
                re.copyWithin(t, r, r + o);
              }
              function _t(t) {
                j("OOM");
              }
              function pt(t) {
                _t();
              }
              function dt(t) {
                return 0;
              }
              function Le(t, r, o, d) {
                var A = $.getStreamFromFD(t),
                  C = $.doReadv(A, r, o);
                return ((N[d >> 2] = C), 0);
              }
              function Ne(t, r, o, d, A) {}
              function De(t, r, o, d) {
                for (var A = 0, C = 0; C < o; C++) {
                  for (
                    var S = N[(r + C * 8) >> 2],
                      F = N[(r + (C * 8 + 4)) >> 2],
                      q = 0;
                    q < F;
                    q++
                  )
                    $.printChar(t, re[S + q]);
                  A += F;
                }
                return ((N[d >> 2] = A), 0);
              }
              function je(t) {
                var r = (Date.now() / 1e3) | 0;
                return (t && (N[t >> 2] = r), r);
              }
              var We = {
                  a: at,
                  e: ut,
                  h: ft,
                  g: ct,
                  b: me,
                  m: st,
                  k: lt,
                  l: pt,
                  c: dt,
                  f: Le,
                  j: Ne,
                  d: De,
                  memory: G,
                  table: Ve,
                  i: je,
                },
                xe = ot();
              e.asm = xe;
              var Ue = (e.___wasm_call_ctors = function () {
                return (Ue = e.___wasm_call_ctors = e.asm.n).apply(
                  null,
                  arguments,
                );
              });
              e.___em_js__emscriptenPushBuffer = function () {
                return (e.___em_js__emscriptenPushBuffer = e.asm.o).apply(
                  null,
                  arguments,
                );
              };
              var ae = (e._emscripten_bind_VoidPtr___destroy___0 = function () {
                  return (ae = e._emscripten_bind_VoidPtr___destroy___0 =
                    e.asm.p).apply(null, arguments);
                }),
                He = (e._emscripten_bind_Container_Container_0 = function () {
                  return (He = e._emscripten_bind_Container_Container_0 =
                    e.asm.q).apply(null, arguments);
                }),
                he = (e._emscripten_bind_Container_init_3 = function () {
                  return (he = e._emscripten_bind_Container_init_3 =
                    e.asm.r).apply(null, arguments);
                }),
                W = (e._emscripten_bind_Container_writeFrame_3 = function () {
                  return (W = e._emscripten_bind_Container_writeFrame_3 =
                    e.asm.s).apply(null, arguments);
                }),
                _e = (e._emscripten_bind_Container___destroy___0 = function () {
                  return (_e = e._emscripten_bind_Container___destroy___0 =
                    e.asm.t).apply(null, arguments);
                });
              ((e._opus_encoder_create = function () {
                return (e._opus_encoder_create = e.asm.u).apply(
                  null,
                  arguments,
                );
              }),
                (e._opus_encode_float = function () {
                  return (e._opus_encode_float = e.asm.v).apply(
                    null,
                    arguments,
                  );
                }),
                (e._opus_encoder_ctl = function () {
                  return (e._opus_encoder_ctl = e.asm.w).apply(null, arguments);
                }),
                (e._opus_encoder_destroy = function () {
                  return (e._opus_encoder_destroy = e.asm.x).apply(
                    null,
                    arguments,
                  );
                }),
                (e._speex_resampler_init = function () {
                  return (e._speex_resampler_init = e.asm.y).apply(
                    null,
                    arguments,
                  );
                }),
                (e._speex_resampler_destroy = function () {
                  return (e._speex_resampler_destroy = e.asm.z).apply(
                    null,
                    arguments,
                  );
                }),
                (e._speex_resampler_process_interleaved_float = function () {
                  return (e._speex_resampler_process_interleaved_float =
                    e.asm.A).apply(null, arguments);
                }),
                (e._free = function () {
                  return (e._free = e.asm.B).apply(null, arguments);
                }),
                (e._malloc = function () {
                  return (e._malloc = e.asm.C).apply(null, arguments);
                }),
                (e.dynCall_vi = function () {
                  return (e.dynCall_vi = e.asm.D).apply(null, arguments);
                }),
                (e.dynCall_v = function () {
                  return (e.dynCall_v = e.asm.E).apply(null, arguments);
                }),
                (e.asm = xe));
              var ie;
              e.then = function (t) {
                if (ie) t(e);
                else {
                  var r = e.onRuntimeInitialized;
                  e.onRuntimeInitialized = function () {
                    (r && r(), t(e));
                  };
                }
                return e;
              };
              function mt(t) {
                ((this.name = "ExitStatus"),
                  (this.message = "Program terminated with exit(" + t + ")"),
                  (this.status = t));
              }
              Y = function t() {
                (ie || Fe(), ie || (Y = t));
              };
              function Fe(t) {
                if (D > 0 || (Qe(), D > 0)) return;
                function r() {
                  ie ||
                    ((ie = !0),
                    (e.calledRun = !0),
                    !be &&
                      (Ke(),
                      Ze(),
                      e.onRuntimeInitialized && e.onRuntimeInitialized(),
                      Je()));
                }
                e.setStatus
                  ? (e.setStatus("Running..."),
                    setTimeout(function () {
                      (setTimeout(function () {
                        e.setStatus("");
                      }, 1),
                        r());
                    }, 1))
                  : r();
              }
              if (((e.run = Fe), e.preInit))
                for (
                  typeof e.preInit == "function" && (e.preInit = [e.preInit]);
                  e.preInit.length > 0;
                )
                  e.preInit.pop()();
              Fe();
              function H() {}
              ((H.prototype = Object.create(H.prototype)),
                (H.prototype.constructor = H),
                (H.prototype.__class__ = H),
                (H.__cache__ = {}),
                (e.WrapperObject = H));
              function ye(t) {
                return (t || H).__cache__;
              }
              e.getCache = ye;
              function Me(t, r) {
                var o = ye(r),
                  d = o[t];
                return (
                  d ||
                  ((d = Object.create((r || H).prototype)),
                  (d.ptr = t),
                  (o[t] = d))
                );
              }
              e.wrapPointer = Me;
              function X(t, r) {
                return Me(t.ptr, r);
              }
              ((e.castObject = X), (e.NULL = Me(0)));
              function U(t) {
                if (!t.__destroy__)
                  throw "Error: Cannot destroy object. (Did you create it yourself?)";
                (t.__destroy__(), delete ye(t.__class__)[t.ptr]);
              }
              e.destroy = U;
              function n(t, r) {
                return t.ptr === r.ptr;
              }
              e.compare = n;
              function s(t) {
                return t.ptr;
              }
              e.getPointer = s;
              function u(t) {
                return t.__class__;
              }
              e.getClass = u;
              function h() {
                throw "cannot construct a VoidPtr, no constructor in IDL";
              }
              ((h.prototype = Object.create(H.prototype)),
                (h.prototype.constructor = h),
                (h.prototype.__class__ = h),
                (h.__cache__ = {}),
                (e.VoidPtr = h),
                (h.prototype.__destroy__ = h.prototype.__destroy__ =
                  function () {
                    var t = this.ptr;
                    ae(t);
                  }));
              function g() {
                ((this.ptr = He()), (ye(g)[this.ptr] = this));
              }
              return (
                (g.prototype = Object.create(H.prototype)),
                (g.prototype.constructor = g),
                (g.prototype.__class__ = g),
                (g.__cache__ = {}),
                (e.Container = g),
                (g.prototype.init = g.prototype.init =
                  function (t, r, o) {
                    var d = this.ptr;
                    (t && typeof t == "object" && (t = t.ptr),
                      r && typeof r == "object" && (r = r.ptr),
                      o && typeof o == "object" && (o = o.ptr),
                      he(d, t, r, o));
                  }),
                (g.prototype.writeFrame = g.prototype.writeFrame =
                  function (t, r, o) {
                    var d = this.ptr;
                    (t && typeof t == "object" && (t = t.ptr),
                      r && typeof r == "object" && (r = r.ptr),
                      o && typeof o == "object" && (o = o.ptr),
                      W(d, t, r, o));
                  }),
                (g.prototype.__destroy__ = g.prototype.__destroy__ =
                  function () {
                    var t = this.ptr;
                    _e(t);
                  }),
                e
              );
            }
          );
        })();
        _.exports = E;
      })(vt)),
    vt.exports
  );
}
var pr = _r(),
  dr = At(pr),
  wt = { exports: {} },
  Tt;
function mr() {
  return (
    Tt ||
      ((Tt = 1),
      (function (_, v) {
        var E = (function () {
          var w =
            typeof document < "u" && document.currentScript
              ? document.currentScript.src
              : void 0;
          return (
            typeof __filename < "u" && (w = w || __filename),
            function (e) {
              e = e || {};
              var e = typeof e < "u" ? e : {};
              const { EmscriptenMemoryAllocator: i } = Pt(),
                f = 2049,
                l = 48e3,
                c = 4e3,
                a = 20,
                m = 6,
                y = 4096,
                T = 0,
                R = 4002,
                b = 0;
              class de {
                constructor(s, u, h = void 0) {
                  ((this.config = { inputSampleRate: s, channelCount: u }),
                    (this.memory = new i(e)),
                    (this._opus_encoder_create = e._opus_encoder_create),
                    (this._opus_encoder_ctl = e._opus_encoder_ctl),
                    (this._opus_encode_float = e._opus_encode_float),
                    (this._opus_encoder_destroy = e._opus_encoder_destroy),
                    (this._speex_resampler_init = e._speex_resampler_init),
                    (this._speex_resampler_process_interleaved_float =
                      e._speex_resampler_process_interleaved_float),
                    (this._speex_resampler_destroy =
                      e._speex_resampler_destroy),
                    (this._container = new e.Container()),
                    this._container.init(
                      l,
                      u,
                      Math.floor(Math.random() * 4294967295),
                    ),
                    this.OpusInitCodec(l, u, h),
                    this.SpeexInitResampler(s, l, u),
                    (this.inputSamplesPerChannel = (s * a) / 1e3),
                    (this.outputSamplePerChannel = (l * a) / 1e3),
                    (this.inputBufferIndex = 0),
                    (this.mInputBuffer = this.memory.mallocFloat32Buffer(
                      this.inputSamplesPerChannel * u,
                    )),
                    (this.mResampledBuffer = this.memory.mallocFloat32Buffer(
                      this.outputSamplePerChannel * u,
                    )),
                    (this.mOutputBuffer = this.memory.mallocUint8Buffer(c)),
                    (this.interleavedBuffers =
                      u !== 1 ? new Float32Array(y * u) : void 0));
                }
                encode(s) {
                  let u = this.interleave(s),
                    h = 0;
                  for (; h < u.length;) {
                    let g = Math.min(
                      this.mInputBuffer.length - this.inputBufferIndex,
                      u.length - h,
                    );
                    if (
                      (this.mInputBuffer.set(
                        u.subarray(h, h + g),
                        this.inputBufferIndex,
                      ),
                      (this.inputBufferIndex += g),
                      this.inputBufferIndex >= this.mInputBuffer.length)
                    ) {
                      let t = this.memory.mallocUint32(
                          this.inputSamplesPerChannel,
                        ),
                        r = this.memory.mallocUint32(
                          this.outputSamplePerChannel,
                        ),
                        o = this._speex_resampler_process_interleaved_float(
                          this.resampler,
                          this.mInputBuffer.pointer,
                          t.pointer,
                          this.mResampledBuffer.pointer,
                          r.pointer,
                        );
                      if ((t.free(), r.free(), o !== b))
                        throw new Error("Resampling error.");
                      let d = this._opus_encode_float(
                        this.encoder,
                        this.mResampledBuffer.pointer,
                        this.outputSamplePerChannel,
                        this.mOutputBuffer.pointer,
                        this.mOutputBuffer.length,
                      );
                      if (d < 0) throw new Error("Opus encoding error.");
                      (this._container.writeFrame(
                        this.mOutputBuffer.pointer,
                        d,
                        this.outputSamplePerChannel,
                      ),
                        (this.inputBufferIndex = 0));
                    }
                    h += g;
                  }
                }
                close() {
                  const { channelCount: s } = this.config;
                  let u = [];
                  for (let h = 0; h < s; ++h)
                    u.push(new Float32Array(y - this.inputBufferIndex / s));
                  (this.encode(u),
                    e.destroy(this._container),
                    this.mInputBuffer.free(),
                    this.mResampledBuffer.free(),
                    this.mOutputBuffer.free(),
                    this._opus_encoder_destroy(this.encoder),
                    this._speex_resampler_destroy(this.resampler));
                }
                interleave(s) {
                  const u = s.length;
                  if (u === 1) return s[0];
                  for (let h = 0; h < u; h++) {
                    let g = s[h];
                    for (let t = 0; t < g.length; t++)
                      this.interleavedBuffers[t * u + h] = g[t];
                  }
                  return this.interleavedBuffers;
                }
                OpusInitCodec(s, u, h = void 0) {
                  let g = this.memory.mallocUint32(void 0);
                  this.encoder = this._opus_encoder_create(s, u, f, g.pointer);
                  let t = g.value;
                  if ((g.free(), t !== T))
                    throw new Error("Opus encodor initialization failed.");
                  h && this.OpusSetOpusControl(R, h);
                }
                OpusSetOpusControl(s, u) {
                  let h = this.memory.mallocInt32(u);
                  (this._opus_encoder_ctl(this.encoder, s, h.pointer),
                    h.free());
                }
                SpeexInitResampler(s, u, h) {
                  let g = this.memory.mallocUint32(void 0);
                  this.resampler = this._speex_resampler_init(
                    h,
                    s,
                    u,
                    m,
                    g.pointer,
                  );
                  let t = g.value;
                  if ((g.free(), t !== b))
                    throw new Error("Initializing resampler failed.");
                }
              }
              ((e.init = function (n, s, u) {
                ((e.encodedBuffers = []), (e.encoder = new de(n, s, u)));
              }),
                (e.encode = function (n) {
                  e.encoder.encode(n);
                }),
                (e.flush = function () {
                  return e.encodedBuffers.splice(0, e.encodedBuffers.length);
                }),
                (e.close = function () {
                  e.encoder.close();
                }));
              var k = {},
                I;
              for (I in e) e.hasOwnProperty(I) && (k[I] = e[I]);
              var Z = !1,
                M = !1,
                ue = !1,
                ge = !1;
              ((Z = typeof window == "object"),
                (M = typeof importScripts == "function"),
                (ue =
                  typeof x == "object" &&
                  typeof x.versions == "object" &&
                  typeof x.versions.node == "string"),
                (ge = !Z && !ue && !M));
              var P = "";
              function ze(n) {
                return e.locateFile ? e.locateFile(n, P) : P + n;
              }
              var J, z, fe, ce;
              ue
                ? (M
                    ? (P = qe().dirname(P) + "/")
                    : (P = "/opt/ci/builds/builder/automattic/beeper/desktop/"),
                  (J = function (s, u) {
                    return (
                      fe || (fe = Nt),
                      ce || (ce = qe()),
                      (s = ce.normalize(s)),
                      fe.readFileSync(s, u ? null : "utf8")
                    );
                  }),
                  (z = function (s) {
                    var u = J(s, !0);
                    return (
                      u.buffer || (u = new Uint8Array(u)),
                      Ee(u.buffer),
                      u
                    );
                  }),
                  x.argv.length > 1 && x.argv[1].replace(/\\/g, "/"),
                  x.argv.slice(2),
                  x.on("uncaughtException", function (n) {
                    if (!(n instanceof He)) throw n;
                  }),
                  x.on("unhandledRejection", j),
                  (e.inspect = function () {
                    return "[Emscripten Module object]";
                  }))
                : ge
                  ? (typeof read < "u" &&
                      (J = function (s) {
                        return read(s);
                      }),
                    (z = function (s) {
                      var u;
                      return typeof readbuffer == "function"
                        ? new Uint8Array(readbuffer(s))
                        : ((u = read(s, "binary")),
                          Ee(typeof u == "object"),
                          u);
                    }),
                    typeof scriptArgs < "u" && scriptArgs,
                    typeof print < "u" &&
                      (typeof console > "u" && (console = {}),
                      (console.log = print),
                      (console.warn = console.error =
                        typeof printErr < "u" ? printErr : print)))
                  : (Z || M) &&
                    (M
                      ? (P = self.location.href)
                      : document.currentScript &&
                        (P = document.currentScript.src),
                    w && (P = w),
                    P.indexOf("blob:") !== 0
                      ? (P = P.substr(0, P.lastIndexOf("/") + 1))
                      : (P = ""),
                    (J = function (s) {
                      var u = new XMLHttpRequest();
                      return (
                        u.open("GET", s, !1),
                        u.send(null),
                        u.responseText
                      );
                    }),
                    M &&
                      (z = function (s) {
                        var u = new XMLHttpRequest();
                        return (
                          u.open("GET", s, !1),
                          (u.responseType = "arraybuffer"),
                          u.send(null),
                          new Uint8Array(u.response)
                        );
                      }));
              var we = e.print || console.log.bind(console),
                L = e.printErr || console.warn.bind(console);
              for (I in k) k.hasOwnProperty(I) && (e[I] = k[I]);
              ((k = null),
                e.arguments && e.arguments,
                e.thisProgram && e.thisProgram,
                e.quit && e.quit);
              var V;
              (e.wasmBinary && (V = e.wasmBinary),
                e.noExitRuntime && e.noExitRuntime,
                typeof WebAssembly != "object" &&
                  L("no native wasm support detected"));
              var G,
                Ve = new WebAssembly.Table({
                  initial: 36,
                  maximum: 36,
                  element: "anyfunc",
                }),
                be = !1;
              function Ee(n, s) {
                n || j("Assertion failed: " + s);
              }
              var Ae =
                typeof TextDecoder < "u" ? new TextDecoder("utf8") : void 0;
              function Pe(n, s, u) {
                for (var h = s + u, g = s; n[g] && !(g >= h);) ++g;
                if (g - s > 16 && n.subarray && Ae)
                  return Ae.decode(n.subarray(s, g));
                for (var t = ""; s < g;) {
                  var r = n[s++];
                  if (!(r & 128)) {
                    t += String.fromCharCode(r);
                    continue;
                  }
                  var o = n[s++] & 63;
                  if ((r & 224) == 192) {
                    t += String.fromCharCode(((r & 31) << 6) | o);
                    continue;
                  }
                  var d = n[s++] & 63;
                  if (
                    ((r & 240) == 224
                      ? (r = ((r & 15) << 12) | (o << 6) | d)
                      : (r =
                          ((r & 7) << 18) |
                          (o << 12) |
                          (d << 6) |
                          (n[s++] & 63)),
                    r < 65536)
                  )
                    t += String.fromCharCode(r);
                  else {
                    var A = r - 65536;
                    t += String.fromCharCode(
                      55296 | (A >> 10),
                      56320 | (A & 1023),
                    );
                  }
                }
                return t;
              }
              function ee(n, s) {
                return n ? Pe(re, n, s) : "";
              }
              typeof TextDecoder < "u" && new TextDecoder("utf-16le");
              var Se = 65536,
                te,
                re,
                N;
              function Ge(n) {
                ((te = n),
                  (e.HEAP8 = new Int8Array(n)),
                  (e.HEAP16 = new Int16Array(n)),
                  (e.HEAP32 = N = new Int32Array(n)),
                  (e.HEAPU8 = re = new Uint8Array(n)),
                  (e.HEAPU16 = new Uint16Array(n)),
                  (e.HEAPU32 = new Uint32Array(n)),
                  (e.HEAPF32 = new Float32Array(n)),
                  (e.HEAPF64 = new Float64Array(n)));
              }
              var Ye = 5289728,
                $e = 46688,
                le = e.INITIAL_MEMORY || 16777216;
              (e.wasmMemory
                ? (G = e.wasmMemory)
                : (G = new WebAssembly.Memory({
                    initial: le / Se,
                    maximum: le / Se,
                  })),
                G && (te = G.buffer),
                (le = te.byteLength),
                Ge(te),
                (N[$e >> 2] = Ye));
              function ne(n) {
                for (; n.length > 0;) {
                  var s = n.shift();
                  if (typeof s == "function") {
                    s();
                    continue;
                  }
                  var u = s.func;
                  typeof u == "number"
                    ? s.arg === void 0
                      ? e.dynCall_v(u)
                      : e.dynCall_vi(u, s.arg)
                    : u(s.arg === void 0 ? null : s.arg);
                }
              }
              var Ce = [],
                Re = [],
                Xe = [],
                Ie = [];
              function Qe() {
                if (e.preRun)
                  for (
                    typeof e.preRun == "function" && (e.preRun = [e.preRun]);
                    e.preRun.length;
                  )
                    et(e.preRun.shift());
                ne(Ce);
              }
              function Ke() {
                ne(Re);
              }
              function Ze() {
                ne(Xe);
              }
              function Je() {
                if (e.postRun)
                  for (
                    typeof e.postRun == "function" && (e.postRun = [e.postRun]);
                    e.postRun.length;
                  )
                    tt(e.postRun.shift());
                ne(Ie);
              }
              function et(n) {
                Ce.unshift(n);
              }
              function tt(n) {
                Ie.unshift(n);
              }
              var D = 0,
                Y = null;
              function rt(n) {
                (D++, e.monitorRunDependencies && e.monitorRunDependencies(D));
              }
              function nt(n) {
                if (
                  (D--,
                  e.monitorRunDependencies && e.monitorRunDependencies(D),
                  D == 0 && Y)
                ) {
                  var s = Y;
                  ((Y = null), s());
                }
              }
              ((e.preloadedImages = {}), (e.preloadedAudios = {}));
              function j(n) {
                throw (
                  e.onAbort && e.onAbort(n),
                  (n += ""),
                  we(n),
                  L(n),
                  (be = !0),
                  (n =
                    "abort(" +
                    n +
                    "). Build with -s ASSERTIONS=1 for more info."),
                  new WebAssembly.RuntimeError(n)
                );
              }
              var Oe = "data:application/octet-stream;base64,";
              function Te(n) {
                return String.prototype.startsWith
                  ? n.startsWith(Oe)
                  : n.indexOf(Oe) === 0;
              }
              var B = "OggOpusEncoder.wasm";
              Te(B) || (B = ze(B));
              function Be() {
                try {
                  if (V) return new Uint8Array(V);
                  if (z) return z(B);
                  throw "both async and sync fetching of the wasm failed";
                } catch (n) {
                  j(n);
                }
              }
              function it() {
                return !V && (Z || M) && typeof fetch == "function"
                  ? fetch(B, { credentials: "same-origin" })
                      .then(function (n) {
                        if (!n.ok)
                          throw (
                            "failed to load wasm binary file at '" + B + "'"
                          );
                        return n.arrayBuffer();
                      })
                      .catch(function () {
                        return Be();
                      })
                  : new Promise(function (n, s) {
                      n(Be());
                    });
              }
              function ot() {
                var n = { a: dt };
                function s(r, o) {
                  var d = r.exports;
                  ((e.asm = d), nt());
                }
                rt();
                function u(r) {
                  s(r.instance);
                }
                function h(r) {
                  return it()
                    .then(function (o) {
                      return WebAssembly.instantiate(o, n);
                    })
                    .then(r, function (o) {
                      (L("failed to asynchronously prepare wasm: " + o), j(o));
                    });
                }
                function g() {
                  if (
                    !V &&
                    typeof WebAssembly.instantiateStreaming == "function" &&
                    !Te(B) &&
                    typeof fetch == "function"
                  )
                    fetch(B, { credentials: "same-origin" }).then(function (r) {
                      var o = WebAssembly.instantiateStreaming(r, n);
                      return o.then(u, function (d) {
                        (L("wasm streaming compile failed: " + d),
                          L("falling back to ArrayBuffer instantiation"),
                          h(u));
                      });
                    });
                  else return h(u);
                }
                if (e.instantiateWasm)
                  try {
                    var t = e.instantiateWasm(n, s);
                    return t;
                  } catch (r) {
                    return (
                      L(
                        "Module.instantiateWasm callback failed with error: " +
                          r,
                      ),
                      !1
                    );
                  }
                return (g(), {});
              }
              function st(n, s) {
                let u = new Uint8Array(e.HEAPU8.buffer, n, s);
                e.encodedBuffers.push(new Uint8Array(u).buffer);
              }
              Re.push({
                func: function () {
                  Ne();
                },
              });
              function at(n, s, u, h) {
                j(
                  "Assertion failed: " +
                    ee(n) +
                    ", at: " +
                    [
                      s ? ee(s) : "unknown filename",
                      u,
                      h ? ee(h) : "unknown function",
                    ],
                );
              }
              function $() {
                j();
              }
              function ut(n, s, u) {
                re.copyWithin(n, s, s + u);
              }
              function ft(n) {
                j("OOM");
              }
              function ct(n) {
                ft();
              }
              var me = {
                mappings: {},
                buffers: [null, [], []],
                printChar: function (n, s) {
                  var u = me.buffers[n];
                  s === 0 || s === 10
                    ? ((n === 1 ? we : L)(Pe(u, 0)), (u.length = 0))
                    : u.push(s);
                },
                varargs: void 0,
                get: function () {
                  me.varargs += 4;
                  var n = N[(me.varargs - 4) >> 2];
                  return n;
                },
                getStr: function (n) {
                  var s = ee(n);
                  return s;
                },
                get64: function (n, s) {
                  return n;
                },
              };
              function lt(n) {
                return 0;
              }
              function _t(n, s, u, h, g) {}
              function pt(n, s, u, h) {
                for (var g = 0, t = 0; t < u; t++) {
                  for (
                    var r = N[(s + t * 8) >> 2],
                      o = N[(s + (t * 8 + 4)) >> 2],
                      d = 0;
                    d < o;
                    d++
                  )
                    me.printChar(n, re[r + d]);
                  g += o;
                }
                return ((N[h >> 2] = g), 0);
              }
              var dt = {
                  a: at,
                  c: $,
                  d: st,
                  f: ut,
                  g: ct,
                  h: lt,
                  e: _t,
                  b: pt,
                  memory: G,
                  table: Ve,
                },
                Le = ot();
              e.asm = Le;
              var Ne = (e.___wasm_call_ctors = function () {
                return (Ne = e.___wasm_call_ctors = e.asm.i).apply(
                  null,
                  arguments,
                );
              });
              e.___em_js__emscriptenPushBuffer = function () {
                return (e.___em_js__emscriptenPushBuffer = e.asm.j).apply(
                  null,
                  arguments,
                );
              };
              var De = (e._emscripten_bind_VoidPtr___destroy___0 = function () {
                  return (De = e._emscripten_bind_VoidPtr___destroy___0 =
                    e.asm.k).apply(null, arguments);
                }),
                je = (e._emscripten_bind_Container_Container_0 = function () {
                  return (je = e._emscripten_bind_Container_Container_0 =
                    e.asm.l).apply(null, arguments);
                }),
                We = (e._emscripten_bind_Container_init_3 = function () {
                  return (We = e._emscripten_bind_Container_init_3 =
                    e.asm.m).apply(null, arguments);
                }),
                xe = (e._emscripten_bind_Container_writeFrame_3 = function () {
                  return (xe = e._emscripten_bind_Container_writeFrame_3 =
                    e.asm.n).apply(null, arguments);
                }),
                Ue = (e._emscripten_bind_Container___destroy___0 = function () {
                  return (Ue = e._emscripten_bind_Container___destroy___0 =
                    e.asm.o).apply(null, arguments);
                });
              ((e._opus_encoder_create = function () {
                return (e._opus_encoder_create = e.asm.p).apply(
                  null,
                  arguments,
                );
              }),
                (e._opus_encode_float = function () {
                  return (e._opus_encode_float = e.asm.q).apply(
                    null,
                    arguments,
                  );
                }),
                (e._opus_encoder_ctl = function () {
                  return (e._opus_encoder_ctl = e.asm.r).apply(null, arguments);
                }),
                (e._opus_encoder_destroy = function () {
                  return (e._opus_encoder_destroy = e.asm.s).apply(
                    null,
                    arguments,
                  );
                }),
                (e._malloc = function () {
                  return (e._malloc = e.asm.t).apply(null, arguments);
                }),
                (e._free = function () {
                  return (e._free = e.asm.u).apply(null, arguments);
                }),
                (e._speex_resampler_init = function () {
                  return (e._speex_resampler_init = e.asm.v).apply(
                    null,
                    arguments,
                  );
                }),
                (e._speex_resampler_destroy = function () {
                  return (e._speex_resampler_destroy = e.asm.w).apply(
                    null,
                    arguments,
                  );
                }),
                (e._speex_resampler_process_interleaved_float = function () {
                  return (e._speex_resampler_process_interleaved_float =
                    e.asm.x).apply(null, arguments);
                }),
                (e.dynCall_vi = function () {
                  return (e.dynCall_vi = e.asm.y).apply(null, arguments);
                }),
                (e.dynCall_v = function () {
                  return (e.dynCall_v = e.asm.z).apply(null, arguments);
                }),
                (e.asm = Le));
              var ae;
              e.then = function (n) {
                if (ae) n(e);
                else {
                  var s = e.onRuntimeInitialized;
                  e.onRuntimeInitialized = function () {
                    (s && s(), n(e));
                  };
                }
                return e;
              };
              function He(n) {
                ((this.name = "ExitStatus"),
                  (this.message = "Program terminated with exit(" + n + ")"),
                  (this.status = n));
              }
              Y = function n() {
                (ae || he(), ae || (Y = n));
              };
              function he(n) {
                if (D > 0 || (Qe(), D > 0)) return;
                function s() {
                  ae ||
                    ((ae = !0),
                    (e.calledRun = !0),
                    !be &&
                      (Ke(),
                      Ze(),
                      e.onRuntimeInitialized && e.onRuntimeInitialized(),
                      Je()));
                }
                e.setStatus
                  ? (e.setStatus("Running..."),
                    setTimeout(function () {
                      (setTimeout(function () {
                        e.setStatus("");
                      }, 1),
                        s());
                    }, 1))
                  : s();
              }
              if (((e.run = he), e.preInit))
                for (
                  typeof e.preInit == "function" && (e.preInit = [e.preInit]);
                  e.preInit.length > 0;
                )
                  e.preInit.pop()();
              he();
              function W() {}
              ((W.prototype = Object.create(W.prototype)),
                (W.prototype.constructor = W),
                (W.prototype.__class__ = W),
                (W.__cache__ = {}),
                (e.WrapperObject = W));
              function _e(n) {
                return (n || W).__cache__;
              }
              e.getCache = _e;
              function ie(n, s) {
                var u = _e(s),
                  h = u[n];
                return (
                  h ||
                  ((h = Object.create((s || W).prototype)),
                  (h.ptr = n),
                  (u[n] = h))
                );
              }
              e.wrapPointer = ie;
              function mt(n, s) {
                return ie(n.ptr, s);
              }
              ((e.castObject = mt), (e.NULL = ie(0)));
              function Fe(n) {
                if (!n.__destroy__)
                  throw "Error: Cannot destroy object. (Did you create it yourself?)";
                (n.__destroy__(), delete _e(n.__class__)[n.ptr]);
              }
              e.destroy = Fe;
              function H(n, s) {
                return n.ptr === s.ptr;
              }
              e.compare = H;
              function ye(n) {
                return n.ptr;
              }
              e.getPointer = ye;
              function Me(n) {
                return n.__class__;
              }
              e.getClass = Me;
              function X() {
                throw "cannot construct a VoidPtr, no constructor in IDL";
              }
              ((X.prototype = Object.create(W.prototype)),
                (X.prototype.constructor = X),
                (X.prototype.__class__ = X),
                (X.__cache__ = {}),
                (e.VoidPtr = X),
                (X.prototype.__destroy__ = X.prototype.__destroy__ =
                  function () {
                    var n = this.ptr;
                    De(n);
                  }));
              function U() {
                ((this.ptr = je()), (_e(U)[this.ptr] = this));
              }
              return (
                (U.prototype = Object.create(W.prototype)),
                (U.prototype.constructor = U),
                (U.prototype.__class__ = U),
                (U.__cache__ = {}),
                (e.Container = U),
                (U.prototype.init = U.prototype.init =
                  function (n, s, u) {
                    var h = this.ptr;
                    (n && typeof n == "object" && (n = n.ptr),
                      s && typeof s == "object" && (s = s.ptr),
                      u && typeof u == "object" && (u = u.ptr),
                      We(h, n, s, u));
                  }),
                (U.prototype.writeFrame = U.prototype.writeFrame =
                  function (n, s, u) {
                    var h = this.ptr;
                    (n && typeof n == "object" && (n = n.ptr),
                      s && typeof s == "object" && (s = s.ptr),
                      u && typeof u == "object" && (u = u.ptr),
                      xe(h, n, s, u));
                  }),
                (U.prototype.__destroy__ = U.prototype.__destroy__ =
                  function () {
                    var n = this.ptr;
                    Ue(n);
                  }),
                e
              );
            }
          );
        })();
        _.exports = E;
      })(wt)),
    wt.exports
  );
}
var hr = mr(),
  yr = At(hr);
function vr(_) {
  let v;
  _.onmessage = function (E) {
    const { command: w } = E.data;
    switch (w) {
      case "loadEncoder": {
        const { mimeType: p, wasmPath: e } = E.data;
        let i;
        switch (p) {
          case "audio/wav":
          case "audio/wave":
            i = Ht;
            break;
          case "audio/webm":
            i = dr;
            break;
          case "audio/ogg":
            i = yr;
            break;
        }
        const f = {};
        (e &&
          (f.locateFile = function (l, c) {
            return l.match(/.wasm/) ? e : c + l;
          }),
          i(f).then((l) => {
            ((v = l), self.postMessage({ command: "readyToInit" }));
          }));
        break;
      }
      case "init": {
        const { sampleRate: p, channelCount: e, bitsPerSecond: i } = E.data;
        v.init(p, e, i);
        break;
      }
      case "pushInputData": {
        const { channelBuffers: p, length: e, duration: i } = E.data;
        for (let f = 0; f < p.length; f++) p[f] = new Float32Array(p[f].buffer);
        v.encode(p);
        break;
      }
      case "getEncodedData":
      case "done": {
        w === "done" && v.close();
        const p = v.flush();
        (self.postMessage(
          {
            command: w === "done" ? "lastEncodedData" : "encodedData",
            buffers: p,
          },
          p,
        ),
          w === "done" && self.close());
        break;
      }
    }
  };
}
typeof WorkerGlobalScope < "u" && self instanceof WorkerGlobalScope && vr(self);
//# sourceMappingURL=encoderWorker-Cva7vKEb.js.map
