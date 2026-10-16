import {
  bZ as fs,
  dk as reactExports,
  cK as jsxRuntimeExports,
} from "./App-CsJiApxN.js";
import {
  a3 as getAugmentedNamespace,
  ag as url,
  aa as process$1,
  ab as require$$5,
  a4 as getDefaultExportFromCjs,
} from "./sentry-common-BxRELKId.js";
import { h as Buffer } from "./matrix-util-Cr_UwXbj.js";
import "./index-Cw3pknxT.js";
import "./index-Dhe7xemD.js";
import "./index-CcYzEQCb.js";
import "./main-process-state-wkFhis-C.js";
import "./report-dialog-7bETf2vU.js";
import "./helpHubMessages-CXhGQ9cB.js";
(function () {
  try {
    var A =
      typeof window < "u"
        ? window
        : typeof global < "u"
          ? global
          : typeof globalThis < "u"
            ? globalThis
            : typeof self < "u"
              ? self
              : {};
    A.SENTRY_RELEASE = { id: "4.3.209" };
    var e = new A.Error().stack;
    e &&
      ((A._sentryDebugIds = A._sentryDebugIds || {}),
      (A._sentryDebugIds[e] = "8af5b7bf-8b6b-48b0-ae1f-1bf65e359897"),
      (A._sentryDebugIdIdentifier =
        "sentry-dbid-8af5b7bf-8b6b-48b0-ae1f-1bf65e359897"));
  } catch {}
})();
function commonjsRequire(A) {
  throw new Error(
    'Could not dynamically require "' +
      A +
      '". Please configure the dynamicRequireTargets or/and ignoreDynamicRequires option of @rollup/plugin-commonjs appropriately for this require call to work.',
  );
}
var pdf$1 = { exports: {} };
const require$$0 = getAugmentedNamespace(fs),
  dummy = {},
  dummy$1 = Object.freeze(
    Object.defineProperty(
      { __proto__: null, default: dummy },
      Symbol.toStringTag,
      { value: "Module" },
    ),
  ),
  require$$1 = getAugmentedNamespace(dummy$1),
  require$$2 = getAugmentedNamespace(url);
var hasRequiredPdf;
function requirePdf() {
  return (
    hasRequiredPdf ||
      ((hasRequiredPdf = 1),
      (function (module, exports) {
        (function (e, y) {
          module.exports = e.pdfjsLib = y();
        })(globalThis, () =>
          (() => {
            var __webpack_modules__ = [
                ,
                (A, e) => {
                  (Object.defineProperty(e, "__esModule", { value: !0 }),
                    (e.VerbosityLevel =
                      e.Util =
                      e.UnknownErrorException =
                      e.UnexpectedResponseException =
                      e.TextRenderingMode =
                      e.RenderingIntentFlag =
                      e.PromiseCapability =
                      e.PermissionFlag =
                      e.PasswordResponses =
                      e.PasswordException =
                      e.PageActionEventType =
                      e.OPS =
                      e.MissingPDFException =
                      e.MAX_IMAGE_SIZE_TO_CACHE =
                      e.LINE_FACTOR =
                      e.LINE_DESCENT_FACTOR =
                      e.InvalidPDFException =
                      e.ImageKind =
                      e.IDENTITY_MATRIX =
                      e.FormatError =
                      e.FeatureTest =
                      e.FONT_IDENTITY_MATRIX =
                      e.DocumentActionEventType =
                      e.CMapCompressionType =
                      e.BaseException =
                      e.BASELINE_FACTOR =
                      e.AnnotationType =
                      e.AnnotationReplyType =
                      e.AnnotationPrefix =
                      e.AnnotationMode =
                      e.AnnotationFlag =
                      e.AnnotationFieldFlag =
                      e.AnnotationEditorType =
                      e.AnnotationEditorPrefix =
                      e.AnnotationEditorParamsType =
                      e.AnnotationBorderStyleType =
                      e.AnnotationActionEventType =
                      e.AbortException =
                        void 0),
                    (e.assert = u),
                    (e.bytesToString = B),
                    (e.createValidAbsoluteUrl = v),
                    (e.getModificationDate = gt),
                    (e.getUuid = Mt),
                    (e.getVerbosityLevel = rt),
                    (e.info = K),
                    (e.isArrayBuffer = ut),
                    (e.isArrayEqual = At),
                    (e.isNodeJS = void 0),
                    (e.normalizeUnicode = Et),
                    (e.objectFromMap = Y),
                    (e.objectSize = st),
                    (e.setVerbosityLevel = tt),
                    (e.shadow = F),
                    (e.string32 = z),
                    (e.stringToBytes = H),
                    (e.stringToPDFString = ct),
                    (e.stringToUTF8String = ht),
                    (e.unreachable = _),
                    (e.utf8StringToString = dt),
                    (e.warn = I));
                  const y =
                    typeof process$1 == "object" &&
                    process$1 + "" == "[object process]" &&
                    !process$1.versions.nw &&
                    !(
                      process$1.versions.electron &&
                      process$1.type &&
                      process$1.type !== "browser"
                    );
                  e.isNodeJS = y;
                  const a = [1, 0, 0, 1, 0, 0];
                  e.IDENTITY_MATRIX = a;
                  const p = [0.001, 0, 0, 0.001, 0, 0];
                  e.FONT_IDENTITY_MATRIX = p;
                  const k = 1e7;
                  e.MAX_IMAGE_SIZE_TO_CACHE = k;
                  const T = 1.35;
                  e.LINE_FACTOR = T;
                  const j = 0.35;
                  e.LINE_DESCENT_FACTOR = j;
                  const D = j / T;
                  e.BASELINE_FACTOR = D;
                  const s = {
                    ANY: 1,
                    DISPLAY: 2,
                    PRINT: 4,
                    SAVE: 8,
                    ANNOTATIONS_FORMS: 16,
                    ANNOTATIONS_STORAGE: 32,
                    ANNOTATIONS_DISABLE: 64,
                    OPLIST: 256,
                  };
                  e.RenderingIntentFlag = s;
                  const t = {
                    DISABLE: 0,
                    ENABLE: 1,
                    ENABLE_FORMS: 2,
                    ENABLE_STORAGE: 3,
                  };
                  e.AnnotationMode = t;
                  const i = "pdfjs_internal_editor_";
                  e.AnnotationEditorPrefix = i;
                  const h = {
                    DISABLE: -1,
                    NONE: 0,
                    FREETEXT: 3,
                    STAMP: 13,
                    INK: 15,
                  };
                  e.AnnotationEditorType = h;
                  const c = {
                    RESIZE: 1,
                    CREATE: 2,
                    FREETEXT_SIZE: 11,
                    FREETEXT_COLOR: 12,
                    FREETEXT_OPACITY: 13,
                    INK_COLOR: 21,
                    INK_THICKNESS: 22,
                    INK_OPACITY: 23,
                  };
                  e.AnnotationEditorParamsType = c;
                  const n = {
                    PRINT: 4,
                    MODIFY_CONTENTS: 8,
                    COPY: 16,
                    MODIFY_ANNOTATIONS: 32,
                    FILL_INTERACTIVE_FORMS: 256,
                    COPY_FOR_ACCESSIBILITY: 512,
                    ASSEMBLE: 1024,
                    PRINT_HIGH_QUALITY: 2048,
                  };
                  e.PermissionFlag = n;
                  const d = {
                    FILL: 0,
                    STROKE: 1,
                    FILL_STROKE: 2,
                    INVISIBLE: 3,
                    FILL_ADD_TO_PATH: 4,
                    STROKE_ADD_TO_PATH: 5,
                    FILL_STROKE_ADD_TO_PATH: 6,
                    ADD_TO_PATH: 7,
                    FILL_STROKE_MASK: 3,
                    ADD_TO_PATH_FLAG: 4,
                  };
                  e.TextRenderingMode = d;
                  const m = { GRAYSCALE_1BPP: 1, RGB_24BPP: 2, RGBA_32BPP: 3 };
                  e.ImageKind = m;
                  const l = {
                    TEXT: 1,
                    LINK: 2,
                    FREETEXT: 3,
                    LINE: 4,
                    SQUARE: 5,
                    CIRCLE: 6,
                    POLYGON: 7,
                    POLYLINE: 8,
                    HIGHLIGHT: 9,
                    UNDERLINE: 10,
                    SQUIGGLY: 11,
                    STRIKEOUT: 12,
                    STAMP: 13,
                    CARET: 14,
                    INK: 15,
                    POPUP: 16,
                    FILEATTACHMENT: 17,
                    SOUND: 18,
                    MOVIE: 19,
                    WIDGET: 20,
                    SCREEN: 21,
                    PRINTERMARK: 22,
                    TRAPNET: 23,
                    WATERMARK: 24,
                    THREED: 25,
                    REDACT: 26,
                  };
                  e.AnnotationType = l;
                  const w = { GROUP: "Group", REPLY: "R" };
                  e.AnnotationReplyType = w;
                  const M = {
                    INVISIBLE: 1,
                    HIDDEN: 2,
                    PRINT: 4,
                    NOZOOM: 8,
                    NOROTATE: 16,
                    NOVIEW: 32,
                    READONLY: 64,
                    LOCKED: 128,
                    TOGGLENOVIEW: 256,
                    LOCKEDCONTENTS: 512,
                  };
                  e.AnnotationFlag = M;
                  const C = {
                    READONLY: 1,
                    REQUIRED: 2,
                    NOEXPORT: 4,
                    MULTILINE: 4096,
                    PASSWORD: 8192,
                    NOTOGGLETOOFF: 16384,
                    RADIO: 32768,
                    PUSHBUTTON: 65536,
                    COMBO: 131072,
                    EDIT: 262144,
                    SORT: 524288,
                    FILESELECT: 1048576,
                    MULTISELECT: 2097152,
                    DONOTSPELLCHECK: 4194304,
                    DONOTSCROLL: 8388608,
                    COMB: 16777216,
                    RICHTEXT: 33554432,
                    RADIOSINUNISON: 33554432,
                    COMMITONSELCHANGE: 67108864,
                  };
                  e.AnnotationFieldFlag = C;
                  const g = {
                    SOLID: 1,
                    DASHED: 2,
                    BEVELED: 3,
                    INSET: 4,
                    UNDERLINE: 5,
                  };
                  e.AnnotationBorderStyleType = g;
                  const E = {
                    E: "Mouse Enter",
                    X: "Mouse Exit",
                    D: "Mouse Down",
                    U: "Mouse Up",
                    Fo: "Focus",
                    Bl: "Blur",
                    PO: "PageOpen",
                    PC: "PageClose",
                    PV: "PageVisible",
                    PI: "PageInvisible",
                    K: "Keystroke",
                    F: "Format",
                    V: "Validate",
                    C: "Calculate",
                  };
                  e.AnnotationActionEventType = E;
                  const U = {
                    WC: "WillClose",
                    WS: "WillSave",
                    DS: "DidSave",
                    WP: "WillPrint",
                    DP: "DidPrint",
                  };
                  e.DocumentActionEventType = U;
                  const W = { O: "PageOpen", C: "PageClose" };
                  e.PageActionEventType = W;
                  const O = { ERRORS: 0, WARNINGS: 1, INFOS: 5 };
                  e.VerbosityLevel = O;
                  const V = { NONE: 0, BINARY: 1 };
                  e.CMapCompressionType = V;
                  const G = {
                    dependency: 1,
                    setLineWidth: 2,
                    setLineCap: 3,
                    setLineJoin: 4,
                    setMiterLimit: 5,
                    setDash: 6,
                    setRenderingIntent: 7,
                    setFlatness: 8,
                    setGState: 9,
                    save: 10,
                    restore: 11,
                    transform: 12,
                    moveTo: 13,
                    lineTo: 14,
                    curveTo: 15,
                    curveTo2: 16,
                    curveTo3: 17,
                    closePath: 18,
                    rectangle: 19,
                    stroke: 20,
                    closeStroke: 21,
                    fill: 22,
                    eoFill: 23,
                    fillStroke: 24,
                    eoFillStroke: 25,
                    closeFillStroke: 26,
                    closeEOFillStroke: 27,
                    endPath: 28,
                    clip: 29,
                    eoClip: 30,
                    beginText: 31,
                    endText: 32,
                    setCharSpacing: 33,
                    setWordSpacing: 34,
                    setHScale: 35,
                    setLeading: 36,
                    setFont: 37,
                    setTextRenderingMode: 38,
                    setTextRise: 39,
                    moveText: 40,
                    setLeadingMoveText: 41,
                    setTextMatrix: 42,
                    nextLine: 43,
                    showText: 44,
                    showSpacedText: 45,
                    nextLineShowText: 46,
                    nextLineSetSpacingShowText: 47,
                    setCharWidth: 48,
                    setCharWidthAndBounds: 49,
                    setStrokeColorSpace: 50,
                    setFillColorSpace: 51,
                    setStrokeColor: 52,
                    setStrokeColorN: 53,
                    setFillColor: 54,
                    setFillColorN: 55,
                    setStrokeGray: 56,
                    setFillGray: 57,
                    setStrokeRGBColor: 58,
                    setFillRGBColor: 59,
                    setStrokeCMYKColor: 60,
                    setFillCMYKColor: 61,
                    shadingFill: 62,
                    beginInlineImage: 63,
                    beginImageData: 64,
                    endInlineImage: 65,
                    paintXObject: 66,
                    markPoint: 67,
                    markPointProps: 68,
                    beginMarkedContent: 69,
                    beginMarkedContentProps: 70,
                    endMarkedContent: 71,
                    beginCompat: 72,
                    endCompat: 73,
                    paintFormXObjectBegin: 74,
                    paintFormXObjectEnd: 75,
                    beginGroup: 76,
                    endGroup: 77,
                    beginAnnotation: 80,
                    endAnnotation: 81,
                    paintImageMaskXObject: 83,
                    paintImageMaskXObjectGroup: 84,
                    paintImageXObject: 85,
                    paintInlineImageXObject: 86,
                    paintInlineImageXObjectGroup: 87,
                    paintImageXObjectRepeat: 88,
                    paintImageMaskXObjectRepeat: 89,
                    paintSolidColorImageMask: 90,
                    constructPath: 91,
                  };
                  e.OPS = G;
                  const nt = { NEED_PASSWORD: 1, INCORRECT_PASSWORD: 2 };
                  e.PasswordResponses = nt;
                  let Z = O.WARNINGS;
                  function tt(it) {
                    Number.isInteger(it) && (Z = it);
                  }
                  function rt() {
                    return Z;
                  }
                  function K(it) {
                    Z >= O.INFOS && console.log(`Info: ${it}`);
                  }
                  function I(it) {
                    Z >= O.WARNINGS && console.log(`Warning: ${it}`);
                  }
                  function _(it) {
                    throw new Error(it);
                  }
                  function u(it, q) {
                    it || _(q);
                  }
                  function f(it) {
                    switch (it?.protocol) {
                      case "http:":
                      case "https:":
                      case "ftp:":
                      case "mailto:":
                      case "tel:":
                        return !0;
                      default:
                        return !1;
                    }
                  }
                  function v(it, q = null, $ = null) {
                    if (!it) return null;
                    try {
                      if (
                        $ &&
                        typeof it == "string" &&
                        ($.addDefaultProtocol &&
                          it.startsWith("www.") &&
                          it.match(/\./g)?.length >= 2 &&
                          (it = `http://${it}`),
                        $.tryConvertEncoding)
                      )
                        try {
                          it = ht(it);
                        } catch {}
                      const ot = q ? new URL(it, q) : new URL(it);
                      if (f(ot)) return ot;
                    } catch {}
                    return null;
                  }
                  function F(it, q, $, ot = !1) {
                    return (
                      Object.defineProperty(it, q, {
                        value: $,
                        enumerable: !ot,
                        configurable: !0,
                        writable: !1,
                      }),
                      $
                    );
                  }
                  const L = (function () {
                    function q($, ot) {
                      (this.constructor === q &&
                        _("Cannot initialize BaseException."),
                        (this.message = $),
                        (this.name = ot));
                    }
                    return (
                      (q.prototype = new Error()),
                      (q.constructor = q),
                      q
                    );
                  })();
                  e.BaseException = L;
                  class N extends L {
                    constructor(q, $) {
                      (super(q, "PasswordException"), (this.code = $));
                    }
                  }
                  e.PasswordException = N;
                  class R extends L {
                    constructor(q, $) {
                      (super(q, "UnknownErrorException"), (this.details = $));
                    }
                  }
                  e.UnknownErrorException = R;
                  class o extends L {
                    constructor(q) {
                      super(q, "InvalidPDFException");
                    }
                  }
                  e.InvalidPDFException = o;
                  class b extends L {
                    constructor(q) {
                      super(q, "MissingPDFException");
                    }
                  }
                  e.MissingPDFException = b;
                  class S extends L {
                    constructor(q, $) {
                      (super(q, "UnexpectedResponseException"),
                        (this.status = $));
                    }
                  }
                  e.UnexpectedResponseException = S;
                  class x extends L {
                    constructor(q) {
                      super(q, "FormatError");
                    }
                  }
                  e.FormatError = x;
                  class P extends L {
                    constructor(q) {
                      super(q, "AbortException");
                    }
                  }
                  e.AbortException = P;
                  function B(it) {
                    (typeof it != "object" || it?.length === void 0) &&
                      _("Invalid argument for bytesToString");
                    const q = it.length,
                      $ = 8192;
                    if (q < $) return String.fromCharCode.apply(null, it);
                    const ot = [];
                    for (let ft = 0; ft < q; ft += $) {
                      const bt = Math.min(ft + $, q),
                        _t = it.subarray(ft, bt);
                      ot.push(String.fromCharCode.apply(null, _t));
                    }
                    return ot.join("");
                  }
                  function H(it) {
                    typeof it != "string" &&
                      _("Invalid argument for stringToBytes");
                    const q = it.length,
                      $ = new Uint8Array(q);
                    for (let ot = 0; ot < q; ++ot)
                      $[ot] = it.charCodeAt(ot) & 255;
                    return $;
                  }
                  function z(it) {
                    return String.fromCharCode(
                      (it >> 24) & 255,
                      (it >> 16) & 255,
                      (it >> 8) & 255,
                      it & 255,
                    );
                  }
                  function st(it) {
                    return Object.keys(it).length;
                  }
                  function Y(it) {
                    const q = Object.create(null);
                    for (const [$, ot] of it) q[$] = ot;
                    return q;
                  }
                  function X() {
                    const it = new Uint8Array(4);
                    return (
                      (it[0] = 1),
                      new Uint32Array(it.buffer, 0, 1)[0] === 1
                    );
                  }
                  function J() {
                    try {
                      return (new Function(""), !0);
                    } catch {
                      return !1;
                    }
                  }
                  class Q {
                    static get isLittleEndian() {
                      return F(this, "isLittleEndian", X());
                    }
                    static get isEvalSupported() {
                      return F(this, "isEvalSupported", J());
                    }
                    static get isOffscreenCanvasSupported() {
                      return F(
                        this,
                        "isOffscreenCanvasSupported",
                        typeof OffscreenCanvas < "u",
                      );
                    }
                    static get platform() {
                      return typeof navigator > "u"
                        ? F(this, "platform", { isWin: !1, isMac: !1 })
                        : F(this, "platform", {
                            isWin: navigator.platform.includes("Win"),
                            isMac: navigator.platform.includes("Mac"),
                          });
                    }
                    static get isCSSRoundSupported() {
                      return F(
                        this,
                        "isCSSRoundSupported",
                        globalThis.CSS?.supports?.("width: round(1.5px, 1px)"),
                      );
                    }
                  }
                  e.FeatureTest = Q;
                  const et = [...Array(256).keys()].map((it) =>
                    it.toString(16).padStart(2, "0"),
                  );
                  class at {
                    static makeHexColor(q, $, ot) {
                      return `#${et[q]}${et[$]}${et[ot]}`;
                    }
                    static scaleMinMax(q, $) {
                      let ot;
                      (q[0]
                        ? (q[0] < 0 &&
                            ((ot = $[0]), ($[0] = $[1]), ($[1] = ot)),
                          ($[0] *= q[0]),
                          ($[1] *= q[0]),
                          q[3] < 0 && ((ot = $[2]), ($[2] = $[3]), ($[3] = ot)),
                          ($[2] *= q[3]),
                          ($[3] *= q[3]))
                        : ((ot = $[0]),
                          ($[0] = $[2]),
                          ($[2] = ot),
                          (ot = $[1]),
                          ($[1] = $[3]),
                          ($[3] = ot),
                          q[1] < 0 && ((ot = $[2]), ($[2] = $[3]), ($[3] = ot)),
                          ($[2] *= q[1]),
                          ($[3] *= q[1]),
                          q[2] < 0 && ((ot = $[0]), ($[0] = $[1]), ($[1] = ot)),
                          ($[0] *= q[2]),
                          ($[1] *= q[2])),
                        ($[0] += q[4]),
                        ($[1] += q[4]),
                        ($[2] += q[5]),
                        ($[3] += q[5]));
                    }
                    static transform(q, $) {
                      return [
                        q[0] * $[0] + q[2] * $[1],
                        q[1] * $[0] + q[3] * $[1],
                        q[0] * $[2] + q[2] * $[3],
                        q[1] * $[2] + q[3] * $[3],
                        q[0] * $[4] + q[2] * $[5] + q[4],
                        q[1] * $[4] + q[3] * $[5] + q[5],
                      ];
                    }
                    static applyTransform(q, $) {
                      const ot = q[0] * $[0] + q[1] * $[2] + $[4],
                        ft = q[0] * $[1] + q[1] * $[3] + $[5];
                      return [ot, ft];
                    }
                    static applyInverseTransform(q, $) {
                      const ot = $[0] * $[3] - $[1] * $[2],
                        ft =
                          (q[0] * $[3] -
                            q[1] * $[2] +
                            $[2] * $[5] -
                            $[4] * $[3]) /
                          ot,
                        bt =
                          (-q[0] * $[1] +
                            q[1] * $[0] +
                            $[4] * $[1] -
                            $[5] * $[0]) /
                          ot;
                      return [ft, bt];
                    }
                    static getAxialAlignedBoundingBox(q, $) {
                      const ot = this.applyTransform(q, $),
                        ft = this.applyTransform(q.slice(2, 4), $),
                        bt = this.applyTransform([q[0], q[3]], $),
                        _t = this.applyTransform([q[2], q[1]], $);
                      return [
                        Math.min(ot[0], ft[0], bt[0], _t[0]),
                        Math.min(ot[1], ft[1], bt[1], _t[1]),
                        Math.max(ot[0], ft[0], bt[0], _t[0]),
                        Math.max(ot[1], ft[1], bt[1], _t[1]),
                      ];
                    }
                    static inverseTransform(q) {
                      const $ = q[0] * q[3] - q[1] * q[2];
                      return [
                        q[3] / $,
                        -q[1] / $,
                        -q[2] / $,
                        q[0] / $,
                        (q[2] * q[5] - q[4] * q[3]) / $,
                        (q[4] * q[1] - q[5] * q[0]) / $,
                      ];
                    }
                    static singularValueDecompose2dScale(q) {
                      const $ = [q[0], q[2], q[1], q[3]],
                        ot = q[0] * $[0] + q[1] * $[2],
                        ft = q[0] * $[1] + q[1] * $[3],
                        bt = q[2] * $[0] + q[3] * $[2],
                        _t = q[2] * $[1] + q[3] * $[3],
                        xt = (ot + _t) / 2,
                        Rt =
                          Math.sqrt((ot + _t) ** 2 - 4 * (ot * _t - bt * ft)) /
                          2,
                        Pt = xt + Rt || 1,
                        yt = xt - Rt || 1;
                      return [Math.sqrt(Pt), Math.sqrt(yt)];
                    }
                    static normalizeRect(q) {
                      const $ = q.slice(0);
                      return (
                        q[0] > q[2] && (($[0] = q[2]), ($[2] = q[0])),
                        q[1] > q[3] && (($[1] = q[3]), ($[3] = q[1])),
                        $
                      );
                    }
                    static intersect(q, $) {
                      const ot = Math.max(
                          Math.min(q[0], q[2]),
                          Math.min($[0], $[2]),
                        ),
                        ft = Math.min(
                          Math.max(q[0], q[2]),
                          Math.max($[0], $[2]),
                        );
                      if (ot > ft) return null;
                      const bt = Math.max(
                          Math.min(q[1], q[3]),
                          Math.min($[1], $[3]),
                        ),
                        _t = Math.min(
                          Math.max(q[1], q[3]),
                          Math.max($[1], $[3]),
                        );
                      return bt > _t ? null : [ot, bt, ft, _t];
                    }
                    static bezierBoundingBox(q, $, ot, ft, bt, _t, xt, Rt) {
                      const Pt = [],
                        yt = [[], []];
                      let kt, Ct, Lt, pt, It, Ot, Nt, jt;
                      for (let Bt = 0; Bt < 2; ++Bt) {
                        if (
                          (Bt === 0
                            ? ((Ct = 6 * q - 12 * ot + 6 * bt),
                              (kt = -3 * q + 9 * ot - 9 * bt + 3 * xt),
                              (Lt = 3 * ot - 3 * q))
                            : ((Ct = 6 * $ - 12 * ft + 6 * _t),
                              (kt = -3 * $ + 9 * ft - 9 * _t + 3 * Rt),
                              (Lt = 3 * ft - 3 * $)),
                          Math.abs(kt) < 1e-12)
                        ) {
                          if (Math.abs(Ct) < 1e-12) continue;
                          ((pt = -Lt / Ct), 0 < pt && pt < 1 && Pt.push(pt));
                          continue;
                        }
                        ((Nt = Ct * Ct - 4 * Lt * kt),
                          (jt = Math.sqrt(Nt)),
                          !(Nt < 0) &&
                            ((It = (-Ct + jt) / (2 * kt)),
                            0 < It && It < 1 && Pt.push(It),
                            (Ot = (-Ct - jt) / (2 * kt)),
                            0 < Ot && Ot < 1 && Pt.push(Ot)));
                      }
                      let Ft = Pt.length,
                        vt;
                      const Dt = Ft;
                      for (; Ft--;)
                        ((pt = Pt[Ft]),
                          (vt = 1 - pt),
                          (yt[0][Ft] =
                            vt * vt * vt * q +
                            3 * vt * vt * pt * ot +
                            3 * vt * pt * pt * bt +
                            pt * pt * pt * xt),
                          (yt[1][Ft] =
                            vt * vt * vt * $ +
                            3 * vt * vt * pt * ft +
                            3 * vt * pt * pt * _t +
                            pt * pt * pt * Rt));
                      return (
                        (yt[0][Dt] = q),
                        (yt[1][Dt] = $),
                        (yt[0][Dt + 1] = xt),
                        (yt[1][Dt + 1] = Rt),
                        (yt[0].length = yt[1].length = Dt + 2),
                        [
                          Math.min(...yt[0]),
                          Math.min(...yt[1]),
                          Math.max(...yt[0]),
                          Math.max(...yt[1]),
                        ]
                      );
                    }
                  }
                  e.Util = at;
                  const lt = [
                    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                    0, 0, 0, 0, 728, 711, 710, 729, 733, 731, 730, 732, 0, 0, 0,
                    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 8226, 8224, 8225,
                    8230, 8212, 8211, 402, 8260, 8249, 8250, 8722, 8240, 8222,
                    8220, 8221, 8216, 8217, 8218, 8482, 64257, 64258, 321, 338,
                    352, 376, 381, 305, 322, 339, 353, 382, 0, 8364,
                  ];
                  function ct(it) {
                    if (it[0] >= "ï") {
                      let $;
                      if (
                        (it[0] === "þ" && it[1] === "ÿ"
                          ? ($ = "utf-16be")
                          : it[0] === "ÿ" && it[1] === "þ"
                            ? ($ = "utf-16le")
                            : it[0] === "ï" &&
                              it[1] === "»" &&
                              it[2] === "¿" &&
                              ($ = "utf-8"),
                        $)
                      )
                        try {
                          const ot = new TextDecoder($, { fatal: !0 }),
                            ft = H(it);
                          return ot.decode(ft);
                        } catch (ot) {
                          I(`stringToPDFString: "${ot}".`);
                        }
                    }
                    const q = [];
                    for (let $ = 0, ot = it.length; $ < ot; $++) {
                      const ft = lt[it.charCodeAt($)];
                      q.push(ft ? String.fromCharCode(ft) : it.charAt($));
                    }
                    return q.join("");
                  }
                  function ht(it) {
                    return decodeURIComponent(escape(it));
                  }
                  function dt(it) {
                    return unescape(encodeURIComponent(it));
                  }
                  function ut(it) {
                    return typeof it == "object" && it?.byteLength !== void 0;
                  }
                  function At(it, q) {
                    if (it.length !== q.length) return !1;
                    for (let $ = 0, ot = it.length; $ < ot; $++)
                      if (it[$] !== q[$]) return !1;
                    return !0;
                  }
                  function gt(it = new Date()) {
                    return [
                      it.getUTCFullYear().toString(),
                      (it.getUTCMonth() + 1).toString().padStart(2, "0"),
                      it.getUTCDate().toString().padStart(2, "0"),
                      it.getUTCHours().toString().padStart(2, "0"),
                      it.getUTCMinutes().toString().padStart(2, "0"),
                      it.getUTCSeconds().toString().padStart(2, "0"),
                    ].join("");
                  }
                  class wt {
                    #t = !1;
                    constructor() {
                      this.promise = new Promise((q, $) => {
                        ((this.resolve = (ot) => {
                          ((this.#t = !0), q(ot));
                        }),
                          (this.reject = (ot) => {
                            ((this.#t = !0), $(ot));
                          }));
                      });
                    }
                    get settled() {
                      return this.#t;
                    }
                  }
                  e.PromiseCapability = wt;
                  let mt = null,
                    St = null;
                  function Et(it) {
                    return (
                      mt ||
                        ((mt =
                          /([\u00a0\u00b5\u037e\u0eb3\u2000-\u200a\u202f\u2126\ufb00-\ufb04\ufb06\ufb20-\ufb36\ufb38-\ufb3c\ufb3e\ufb40-\ufb41\ufb43-\ufb44\ufb46-\ufba1\ufba4-\ufba9\ufbae-\ufbb1\ufbd3-\ufbdc\ufbde-\ufbe7\ufbea-\ufbf8\ufbfc-\ufbfd\ufc00-\ufc5d\ufc64-\ufcf1\ufcf5-\ufd3d\ufd88\ufdf4\ufdfa-\ufdfb\ufe71\ufe77\ufe79\ufe7b\ufe7d]+)|(\ufb05+)/gu),
                        (St = new Map([["ﬅ", "ſt"]]))),
                      it.replaceAll(mt, (q, $, ot) =>
                        $ ? $.normalize("NFKC") : St.get(ot),
                      )
                    );
                  }
                  function Mt() {
                    if (
                      typeof crypto < "u" &&
                      typeof crypto?.randomUUID == "function"
                    )
                      return crypto.randomUUID();
                    const it = new Uint8Array(32);
                    if (
                      typeof crypto < "u" &&
                      typeof crypto?.getRandomValues == "function"
                    )
                      crypto.getRandomValues(it);
                    else
                      for (let q = 0; q < 32; q++)
                        it[q] = Math.floor(Math.random() * 255);
                    return B(it);
                  }
                  const Tt = "pdfjs_internal_id_";
                  e.AnnotationPrefix = Tt;
                },
                (__unused_webpack_module, exports, __w_pdfjs_require__) => {
                  (Object.defineProperty(exports, "__esModule", { value: !0 }),
                    (exports.RenderTask =
                      exports.PDFWorkerUtil =
                      exports.PDFWorker =
                      exports.PDFPageProxy =
                      exports.PDFDocumentProxy =
                      exports.PDFDocumentLoadingTask =
                      exports.PDFDataRangeTransport =
                      exports.LoopbackPort =
                      exports.DefaultStandardFontDataFactory =
                      exports.DefaultFilterFactory =
                      exports.DefaultCanvasFactory =
                      exports.DefaultCMapReaderFactory =
                        void 0),
                    Object.defineProperty(exports, "SVGGraphics", {
                      enumerable: !0,
                      get: function () {
                        return _displaySvg.SVGGraphics;
                      },
                    }),
                    (exports.build = void 0),
                    (exports.getDocument = getDocument),
                    (exports.version = void 0));
                  var _util = __w_pdfjs_require__(1),
                    _annotation_storage = __w_pdfjs_require__(3),
                    _display_utils = __w_pdfjs_require__(6),
                    _font_loader = __w_pdfjs_require__(9),
                    _displayNode_utils = __w_pdfjs_require__(10),
                    _canvas = __w_pdfjs_require__(11),
                    _worker_options = __w_pdfjs_require__(14),
                    _message_handler = __w_pdfjs_require__(15),
                    _metadata = __w_pdfjs_require__(16),
                    _optional_content_config = __w_pdfjs_require__(17),
                    _transport_stream = __w_pdfjs_require__(18),
                    _displayFetch_stream = __w_pdfjs_require__(19),
                    _displayNetwork = __w_pdfjs_require__(22),
                    _displayNode_stream = __w_pdfjs_require__(23),
                    _displaySvg = __w_pdfjs_require__(24),
                    _xfa_text = __w_pdfjs_require__(25);
                  const DEFAULT_RANGE_CHUNK_SIZE = 65536,
                    RENDERING_CANCELLED_TIMEOUT = 100,
                    DELAYED_CLEANUP_TIMEOUT = 5e3,
                    DefaultCanvasFactory = _util.isNodeJS
                      ? _displayNode_utils.NodeCanvasFactory
                      : _display_utils.DOMCanvasFactory;
                  exports.DefaultCanvasFactory = DefaultCanvasFactory;
                  const DefaultCMapReaderFactory = _util.isNodeJS
                    ? _displayNode_utils.NodeCMapReaderFactory
                    : _display_utils.DOMCMapReaderFactory;
                  exports.DefaultCMapReaderFactory = DefaultCMapReaderFactory;
                  const DefaultFilterFactory = _util.isNodeJS
                    ? _displayNode_utils.NodeFilterFactory
                    : _display_utils.DOMFilterFactory;
                  exports.DefaultFilterFactory = DefaultFilterFactory;
                  const DefaultStandardFontDataFactory = _util.isNodeJS
                    ? _displayNode_utils.NodeStandardFontDataFactory
                    : _display_utils.DOMStandardFontDataFactory;
                  exports.DefaultStandardFontDataFactory =
                    DefaultStandardFontDataFactory;
                  function getDocument(A) {
                    if (
                      (typeof A == "string" || A instanceof URL
                        ? (A = { url: A })
                        : (0, _util.isArrayBuffer)(A) && (A = { data: A }),
                      typeof A != "object")
                    )
                      throw new Error(
                        "Invalid parameter in getDocument, need parameter object.",
                      );
                    if (!A.url && !A.data && !A.range)
                      throw new Error(
                        "Invalid parameter object: need either .data, .range or .url",
                      );
                    const e = new PDFDocumentLoadingTask(),
                      { docId: y } = e,
                      a = A.url ? getUrlProp(A.url) : null,
                      p = A.data ? getDataProp(A.data) : null,
                      k = A.httpHeaders || null,
                      T = A.withCredentials === !0,
                      j = A.password ?? null,
                      D =
                        A.range instanceof PDFDataRangeTransport
                          ? A.range
                          : null,
                      s =
                        Number.isInteger(A.rangeChunkSize) &&
                        A.rangeChunkSize > 0
                          ? A.rangeChunkSize
                          : DEFAULT_RANGE_CHUNK_SIZE;
                    let t = A.worker instanceof PDFWorker ? A.worker : null;
                    const i = A.verbosity,
                      h =
                        typeof A.docBaseUrl == "string" &&
                        !(0, _display_utils.isDataScheme)(A.docBaseUrl)
                          ? A.docBaseUrl
                          : null,
                      c = typeof A.cMapUrl == "string" ? A.cMapUrl : null,
                      n = A.cMapPacked !== !1,
                      d = A.CMapReaderFactory || DefaultCMapReaderFactory,
                      m =
                        typeof A.standardFontDataUrl == "string"
                          ? A.standardFontDataUrl
                          : null,
                      l =
                        A.StandardFontDataFactory ||
                        DefaultStandardFontDataFactory,
                      w = A.stopAtErrors !== !0,
                      M =
                        Number.isInteger(A.maxImageSize) && A.maxImageSize > -1
                          ? A.maxImageSize
                          : -1,
                      C = A.isEvalSupported !== !1,
                      g =
                        typeof A.isOffscreenCanvasSupported == "boolean"
                          ? A.isOffscreenCanvasSupported
                          : !_util.isNodeJS,
                      E = Number.isInteger(A.canvasMaxAreaInBytes)
                        ? A.canvasMaxAreaInBytes
                        : -1,
                      U =
                        typeof A.disableFontFace == "boolean"
                          ? A.disableFontFace
                          : _util.isNodeJS,
                      W = A.fontExtraProperties === !0,
                      O = A.enableXfa === !0,
                      V = A.ownerDocument || globalThis.document,
                      G = A.disableRange === !0,
                      nt = A.disableStream === !0,
                      Z = A.disableAutoFetch === !0,
                      tt = A.pdfBug === !0,
                      rt = D ? D.length : (A.length ?? NaN),
                      K =
                        typeof A.useSystemFonts == "boolean"
                          ? A.useSystemFonts
                          : !_util.isNodeJS && !U,
                      I =
                        typeof A.useWorkerFetch == "boolean"
                          ? A.useWorkerFetch
                          : d === _display_utils.DOMCMapReaderFactory &&
                            l === _display_utils.DOMStandardFontDataFactory &&
                            c &&
                            m &&
                            (0, _display_utils.isValidFetchUrl)(
                              c,
                              document.baseURI,
                            ) &&
                            (0, _display_utils.isValidFetchUrl)(
                              m,
                              document.baseURI,
                            ),
                      _ =
                        A.canvasFactory ||
                        new DefaultCanvasFactory({ ownerDocument: V }),
                      u =
                        A.filterFactory ||
                        new DefaultFilterFactory({
                          docId: y,
                          ownerDocument: V,
                        }),
                      f = null;
                    (0, _util.setVerbosityLevel)(i);
                    const v = { canvasFactory: _, filterFactory: u };
                    if (
                      (I ||
                        ((v.cMapReaderFactory = new d({
                          baseUrl: c,
                          isCompressed: n,
                        })),
                        (v.standardFontDataFactory = new l({ baseUrl: m }))),
                      !t)
                    ) {
                      const N = {
                        verbosity: i,
                        port: _worker_options.GlobalWorkerOptions.workerPort,
                      };
                      ((t = N.port ? PDFWorker.fromPort(N) : new PDFWorker(N)),
                        (e._worker = t));
                    }
                    const F = {
                        docId: y,
                        apiVersion: "3.11.174",
                        data: p,
                        password: j,
                        disableAutoFetch: Z,
                        rangeChunkSize: s,
                        length: rt,
                        docBaseUrl: h,
                        enableXfa: O,
                        evaluatorOptions: {
                          maxImageSize: M,
                          disableFontFace: U,
                          ignoreErrors: w,
                          isEvalSupported: C,
                          isOffscreenCanvasSupported: g,
                          canvasMaxAreaInBytes: E,
                          fontExtraProperties: W,
                          useSystemFonts: K,
                          cMapUrl: I ? c : null,
                          standardFontDataUrl: I ? m : null,
                        },
                      },
                      L = {
                        ignoreErrors: w,
                        isEvalSupported: C,
                        disableFontFace: U,
                        fontExtraProperties: W,
                        enableXfa: O,
                        ownerDocument: V,
                        disableAutoFetch: Z,
                        pdfBug: tt,
                        styleElement: f,
                      };
                    return (
                      t.promise
                        .then(function () {
                          if (e.destroyed) throw new Error("Loading aborted");
                          const N = _fetchDocument(t, F),
                            R = new Promise(function (o) {
                              let b;
                              (D
                                ? (b =
                                    new _transport_stream.PDFDataTransportStream(
                                      {
                                        length: rt,
                                        initialData: D.initialData,
                                        progressiveDone: D.progressiveDone,
                                        contentDispositionFilename:
                                          D.contentDispositionFilename,
                                        disableRange: G,
                                        disableStream: nt,
                                      },
                                      D,
                                    ))
                                : p ||
                                  (b = ((x) =>
                                    _util.isNodeJS
                                      ? new _displayNode_stream.PDFNodeStream(x)
                                      : (0, _display_utils.isValidFetchUrl)(
                                            x.url,
                                          )
                                        ? new _displayFetch_stream.PDFFetchStream(
                                            x,
                                          )
                                        : new _displayNetwork.PDFNetworkStream(
                                            x,
                                          ))({
                                    url: a,
                                    length: rt,
                                    httpHeaders: k,
                                    withCredentials: T,
                                    rangeChunkSize: s,
                                    disableRange: G,
                                    disableStream: nt,
                                  })),
                                o(b));
                            });
                          return Promise.all([N, R]).then(function ([o, b]) {
                            if (e.destroyed) throw new Error("Loading aborted");
                            const S = new _message_handler.MessageHandler(
                                y,
                                o,
                                t.port,
                              ),
                              x = new WorkerTransport(S, e, b, L, v);
                            ((e._transport = x), S.send("Ready", null));
                          });
                        })
                        .catch(e._capability.reject),
                      e
                    );
                  }
                  async function _fetchDocument(A, e) {
                    if (A.destroyed) throw new Error("Worker was destroyed");
                    const y = await A.messageHandler.sendWithPromise(
                      "GetDocRequest",
                      e,
                      e.data ? [e.data.buffer] : null,
                    );
                    if (A.destroyed) throw new Error("Worker was destroyed");
                    return y;
                  }
                  function getUrlProp(A) {
                    if (A instanceof URL) return A.href;
                    try {
                      return new URL(A, window.location).href;
                    } catch {
                      if (_util.isNodeJS && typeof A == "string") return A;
                    }
                    throw new Error(
                      "Invalid PDF url data: either string or URL-object is expected in the url property.",
                    );
                  }
                  function getDataProp(A) {
                    if (
                      _util.isNodeJS &&
                      typeof Buffer < "u" &&
                      A instanceof Buffer
                    )
                      throw new Error(
                        "Please provide binary data as `Uint8Array`, rather than `Buffer`.",
                      );
                    if (
                      A instanceof Uint8Array &&
                      A.byteLength === A.buffer.byteLength
                    )
                      return A;
                    if (typeof A == "string")
                      return (0, _util.stringToBytes)(A);
                    if (
                      (typeof A == "object" && !isNaN(A?.length)) ||
                      (0, _util.isArrayBuffer)(A)
                    )
                      return new Uint8Array(A);
                    throw new Error(
                      "Invalid PDF binary data: either TypedArray, string, or array-like object is expected in the data property.",
                    );
                  }
                  class PDFDocumentLoadingTask {
                    static #t = 0;
                    constructor() {
                      ((this._capability = new _util.PromiseCapability()),
                        (this._transport = null),
                        (this._worker = null),
                        (this.docId = `d${PDFDocumentLoadingTask.#t++}`),
                        (this.destroyed = !1),
                        (this.onPassword = null),
                        (this.onProgress = null));
                    }
                    get promise() {
                      return this._capability.promise;
                    }
                    async destroy() {
                      this.destroyed = !0;
                      try {
                        (this._worker?.port &&
                          (this._worker._pendingDestroy = !0),
                          await this._transport?.destroy());
                      } catch (e) {
                        throw (
                          this._worker?.port &&
                            delete this._worker._pendingDestroy,
                          e
                        );
                      }
                      ((this._transport = null),
                        this._worker &&
                          (this._worker.destroy(), (this._worker = null)));
                    }
                  }
                  exports.PDFDocumentLoadingTask = PDFDocumentLoadingTask;
                  class PDFDataRangeTransport {
                    constructor(e, y, a = !1, p = null) {
                      ((this.length = e),
                        (this.initialData = y),
                        (this.progressiveDone = a),
                        (this.contentDispositionFilename = p),
                        (this._rangeListeners = []),
                        (this._progressListeners = []),
                        (this._progressiveReadListeners = []),
                        (this._progressiveDoneListeners = []),
                        (this._readyCapability =
                          new _util.PromiseCapability()));
                    }
                    addRangeListener(e) {
                      this._rangeListeners.push(e);
                    }
                    addProgressListener(e) {
                      this._progressListeners.push(e);
                    }
                    addProgressiveReadListener(e) {
                      this._progressiveReadListeners.push(e);
                    }
                    addProgressiveDoneListener(e) {
                      this._progressiveDoneListeners.push(e);
                    }
                    onDataRange(e, y) {
                      for (const a of this._rangeListeners) a(e, y);
                    }
                    onDataProgress(e, y) {
                      this._readyCapability.promise.then(() => {
                        for (const a of this._progressListeners) a(e, y);
                      });
                    }
                    onDataProgressiveRead(e) {
                      this._readyCapability.promise.then(() => {
                        for (const y of this._progressiveReadListeners) y(e);
                      });
                    }
                    onDataProgressiveDone() {
                      this._readyCapability.promise.then(() => {
                        for (const e of this._progressiveDoneListeners) e();
                      });
                    }
                    transportReady() {
                      this._readyCapability.resolve();
                    }
                    requestDataRange(e, y) {
                      (0, _util.unreachable)(
                        "Abstract method PDFDataRangeTransport.requestDataRange",
                      );
                    }
                    abort() {}
                  }
                  exports.PDFDataRangeTransport = PDFDataRangeTransport;
                  class PDFDocumentProxy {
                    constructor(e, y) {
                      ((this._pdfInfo = e),
                        (this._transport = y),
                        Object.defineProperty(this, "getJavaScript", {
                          value: () => (
                            (0, _display_utils.deprecated)(
                              "`PDFDocumentProxy.getJavaScript`, please use `PDFDocumentProxy.getJSActions` instead.",
                            ),
                            this.getJSActions().then((a) => {
                              if (!a) return a;
                              const p = [];
                              for (const k in a) p.push(...a[k]);
                              return p;
                            })
                          ),
                        }));
                    }
                    get annotationStorage() {
                      return this._transport.annotationStorage;
                    }
                    get filterFactory() {
                      return this._transport.filterFactory;
                    }
                    get numPages() {
                      return this._pdfInfo.numPages;
                    }
                    get fingerprints() {
                      return this._pdfInfo.fingerprints;
                    }
                    get isPureXfa() {
                      return (0, _util.shadow)(
                        this,
                        "isPureXfa",
                        !!this._transport._htmlForXfa,
                      );
                    }
                    get allXfaHtml() {
                      return this._transport._htmlForXfa;
                    }
                    getPage(e) {
                      return this._transport.getPage(e);
                    }
                    getPageIndex(e) {
                      return this._transport.getPageIndex(e);
                    }
                    getDestinations() {
                      return this._transport.getDestinations();
                    }
                    getDestination(e) {
                      return this._transport.getDestination(e);
                    }
                    getPageLabels() {
                      return this._transport.getPageLabels();
                    }
                    getPageLayout() {
                      return this._transport.getPageLayout();
                    }
                    getPageMode() {
                      return this._transport.getPageMode();
                    }
                    getViewerPreferences() {
                      return this._transport.getViewerPreferences();
                    }
                    getOpenAction() {
                      return this._transport.getOpenAction();
                    }
                    getAttachments() {
                      return this._transport.getAttachments();
                    }
                    getJSActions() {
                      return this._transport.getDocJSActions();
                    }
                    getOutline() {
                      return this._transport.getOutline();
                    }
                    getOptionalContentConfig() {
                      return this._transport.getOptionalContentConfig();
                    }
                    getPermissions() {
                      return this._transport.getPermissions();
                    }
                    getMetadata() {
                      return this._transport.getMetadata();
                    }
                    getMarkInfo() {
                      return this._transport.getMarkInfo();
                    }
                    getData() {
                      return this._transport.getData();
                    }
                    saveDocument() {
                      return this._transport.saveDocument();
                    }
                    getDownloadInfo() {
                      return this._transport.downloadInfoCapability.promise;
                    }
                    cleanup(e = !1) {
                      return this._transport.startCleanup(e || this.isPureXfa);
                    }
                    destroy() {
                      return this.loadingTask.destroy();
                    }
                    get loadingParams() {
                      return this._transport.loadingParams;
                    }
                    get loadingTask() {
                      return this._transport.loadingTask;
                    }
                    getFieldObjects() {
                      return this._transport.getFieldObjects();
                    }
                    hasJSActions() {
                      return this._transport.hasJSActions();
                    }
                    getCalculationOrderIds() {
                      return this._transport.getCalculationOrderIds();
                    }
                  }
                  exports.PDFDocumentProxy = PDFDocumentProxy;
                  class PDFPageProxy {
                    #t = null;
                    #e = !1;
                    constructor(e, y, a, p = !1) {
                      ((this._pageIndex = e),
                        (this._pageInfo = y),
                        (this._transport = a),
                        (this._stats = p
                          ? new _display_utils.StatTimer()
                          : null),
                        (this._pdfBug = p),
                        (this.commonObjs = a.commonObjs),
                        (this.objs = new PDFObjects()),
                        (this._maybeCleanupAfterRender = !1),
                        (this._intentStates = new Map()),
                        (this.destroyed = !1));
                    }
                    get pageNumber() {
                      return this._pageIndex + 1;
                    }
                    get rotate() {
                      return this._pageInfo.rotate;
                    }
                    get ref() {
                      return this._pageInfo.ref;
                    }
                    get userUnit() {
                      return this._pageInfo.userUnit;
                    }
                    get view() {
                      return this._pageInfo.view;
                    }
                    getViewport({
                      scale: e,
                      rotation: y = this.rotate,
                      offsetX: a = 0,
                      offsetY: p = 0,
                      dontFlip: k = !1,
                    } = {}) {
                      return new _display_utils.PageViewport({
                        viewBox: this.view,
                        scale: e,
                        rotation: y,
                        offsetX: a,
                        offsetY: p,
                        dontFlip: k,
                      });
                    }
                    getAnnotations({ intent: e = "display" } = {}) {
                      const y = this._transport.getRenderingIntent(e);
                      return this._transport.getAnnotations(
                        this._pageIndex,
                        y.renderingIntent,
                      );
                    }
                    getJSActions() {
                      return this._transport.getPageJSActions(this._pageIndex);
                    }
                    get filterFactory() {
                      return this._transport.filterFactory;
                    }
                    get isPureXfa() {
                      return (0, _util.shadow)(
                        this,
                        "isPureXfa",
                        !!this._transport._htmlForXfa,
                      );
                    }
                    async getXfa() {
                      return (
                        this._transport._htmlForXfa?.children[
                          this._pageIndex
                        ] || null
                      );
                    }
                    render({
                      canvasContext: e,
                      viewport: y,
                      intent: a = "display",
                      annotationMode: p = _util.AnnotationMode.ENABLE,
                      transform: k = null,
                      background: T = null,
                      optionalContentConfigPromise: j = null,
                      annotationCanvasMap: D = null,
                      pageColors: s = null,
                      printAnnotationStorage: t = null,
                    }) {
                      this._stats?.time("Overall");
                      const i = this._transport.getRenderingIntent(a, p, t);
                      ((this.#e = !1),
                        this.#i(),
                        j || (j = this._transport.getOptionalContentConfig()));
                      let h = this._intentStates.get(i.cacheKey);
                      (h ||
                        ((h = Object.create(null)),
                        this._intentStates.set(i.cacheKey, h)),
                        h.streamReaderCancelTimeout &&
                          (clearTimeout(h.streamReaderCancelTimeout),
                          (h.streamReaderCancelTimeout = null)));
                      const c = !!(
                        i.renderingIntent & _util.RenderingIntentFlag.PRINT
                      );
                      h.displayReadyCapability ||
                        ((h.displayReadyCapability =
                          new _util.PromiseCapability()),
                        (h.operatorList = {
                          fnArray: [],
                          argsArray: [],
                          lastChunk: !1,
                          separateAnnots: null,
                        }),
                        this._stats?.time("Page Request"),
                        this._pumpOperatorList(i));
                      const n = (l) => {
                          (h.renderTasks.delete(d),
                            (this._maybeCleanupAfterRender || c) &&
                              (this.#e = !0),
                            this.#n(!c),
                            l
                              ? (d.capability.reject(l),
                                this._abortOperatorList({
                                  intentState: h,
                                  reason: l instanceof Error ? l : new Error(l),
                                }))
                              : d.capability.resolve(),
                            this._stats?.timeEnd("Rendering"),
                            this._stats?.timeEnd("Overall"));
                        },
                        d = new InternalRenderTask({
                          callback: n,
                          params: {
                            canvasContext: e,
                            viewport: y,
                            transform: k,
                            background: T,
                          },
                          objs: this.objs,
                          commonObjs: this.commonObjs,
                          annotationCanvasMap: D,
                          operatorList: h.operatorList,
                          pageIndex: this._pageIndex,
                          canvasFactory: this._transport.canvasFactory,
                          filterFactory: this._transport.filterFactory,
                          useRequestAnimationFrame: !c,
                          pdfBug: this._pdfBug,
                          pageColors: s,
                        });
                      (h.renderTasks ||= new Set()).add(d);
                      const m = d.task;
                      return (
                        Promise.all([h.displayReadyCapability.promise, j])
                          .then(([l, w]) => {
                            if (this.destroyed) {
                              n();
                              return;
                            }
                            (this._stats?.time("Rendering"),
                              d.initializeGraphics({
                                transparency: l,
                                optionalContentConfig: w,
                              }),
                              d.operatorListChanged());
                          })
                          .catch(n),
                        m
                      );
                    }
                    getOperatorList({
                      intent: e = "display",
                      annotationMode: y = _util.AnnotationMode.ENABLE,
                      printAnnotationStorage: a = null,
                    } = {}) {
                      function p() {
                        T.operatorList.lastChunk &&
                          (T.opListReadCapability.resolve(T.operatorList),
                          T.renderTasks.delete(j));
                      }
                      const k = this._transport.getRenderingIntent(e, y, a, !0);
                      let T = this._intentStates.get(k.cacheKey);
                      T ||
                        ((T = Object.create(null)),
                        this._intentStates.set(k.cacheKey, T));
                      let j;
                      return (
                        T.opListReadCapability ||
                          ((j = Object.create(null)),
                          (j.operatorListChanged = p),
                          (T.opListReadCapability =
                            new _util.PromiseCapability()),
                          (T.renderTasks ||= new Set()).add(j),
                          (T.operatorList = {
                            fnArray: [],
                            argsArray: [],
                            lastChunk: !1,
                            separateAnnots: null,
                          }),
                          this._stats?.time("Page Request"),
                          this._pumpOperatorList(k)),
                        T.opListReadCapability.promise
                      );
                    }
                    streamTextContent({
                      includeMarkedContent: e = !1,
                      disableNormalization: y = !1,
                    } = {}) {
                      return this._transport.messageHandler.sendWithStream(
                        "GetTextContent",
                        {
                          pageIndex: this._pageIndex,
                          includeMarkedContent: e === !0,
                          disableNormalization: y === !0,
                        },
                        {
                          highWaterMark: 100,
                          size(p) {
                            return p.items.length;
                          },
                        },
                      );
                    }
                    getTextContent(e = {}) {
                      if (this._transport._htmlForXfa)
                        return this.getXfa().then((a) =>
                          _xfa_text.XfaText.textContent(a),
                        );
                      const y = this.streamTextContent(e);
                      return new Promise(function (a, p) {
                        function k() {
                          T.read().then(function ({ value: D, done: s }) {
                            if (s) {
                              a(j);
                              return;
                            }
                            (Object.assign(j.styles, D.styles),
                              j.items.push(...D.items),
                              k());
                          }, p);
                        }
                        const T = y.getReader(),
                          j = { items: [], styles: Object.create(null) };
                        k();
                      });
                    }
                    getStructTree() {
                      return this._transport.getStructTree(this._pageIndex);
                    }
                    _destroy() {
                      this.destroyed = !0;
                      const e = [];
                      for (const y of this._intentStates.values())
                        if (
                          (this._abortOperatorList({
                            intentState: y,
                            reason: new Error("Page was destroyed."),
                            force: !0,
                          }),
                          !y.opListReadCapability)
                        )
                          for (const a of y.renderTasks)
                            (e.push(a.completed), a.cancel());
                      return (
                        this.objs.clear(),
                        (this.#e = !1),
                        this.#i(),
                        Promise.all(e)
                      );
                    }
                    cleanup(e = !1) {
                      this.#e = !0;
                      const y = this.#n(!1);
                      return (
                        e &&
                          y &&
                          (this._stats &&= new _display_utils.StatTimer()),
                        y
                      );
                    }
                    #n(e = !1) {
                      if ((this.#i(), !this.#e || this.destroyed)) return !1;
                      if (e)
                        return (
                          (this.#t = setTimeout(() => {
                            ((this.#t = null), this.#n(!1));
                          }, DELAYED_CLEANUP_TIMEOUT)),
                          !1
                        );
                      for (const {
                        renderTasks: y,
                        operatorList: a,
                      } of this._intentStates.values())
                        if (y.size > 0 || !a.lastChunk) return !1;
                      return (
                        this._intentStates.clear(),
                        this.objs.clear(),
                        (this.#e = !1),
                        !0
                      );
                    }
                    #i() {
                      this.#t && (clearTimeout(this.#t), (this.#t = null));
                    }
                    _startRenderPage(e, y) {
                      const a = this._intentStates.get(y);
                      a &&
                        (this._stats?.timeEnd("Page Request"),
                        a.displayReadyCapability?.resolve(e));
                    }
                    _renderPageChunk(e, y) {
                      for (let a = 0, p = e.length; a < p; a++)
                        (y.operatorList.fnArray.push(e.fnArray[a]),
                          y.operatorList.argsArray.push(e.argsArray[a]));
                      ((y.operatorList.lastChunk = e.lastChunk),
                        (y.operatorList.separateAnnots = e.separateAnnots));
                      for (const a of y.renderTasks) a.operatorListChanged();
                      e.lastChunk && this.#n(!0);
                    }
                    _pumpOperatorList({
                      renderingIntent: e,
                      cacheKey: y,
                      annotationStorageSerializable: a,
                    }) {
                      const { map: p, transfers: k } = a,
                        j = this._transport.messageHandler
                          .sendWithStream(
                            "GetOperatorList",
                            {
                              pageIndex: this._pageIndex,
                              intent: e,
                              cacheKey: y,
                              annotationStorage: p,
                            },
                            k,
                          )
                          .getReader(),
                        D = this._intentStates.get(y);
                      D.streamReader = j;
                      const s = () => {
                        j.read().then(
                          ({ value: t, done: i }) => {
                            if (i) {
                              D.streamReader = null;
                              return;
                            }
                            this._transport.destroyed ||
                              (this._renderPageChunk(t, D), s());
                          },
                          (t) => {
                            if (
                              ((D.streamReader = null),
                              !this._transport.destroyed)
                            ) {
                              if (D.operatorList) {
                                D.operatorList.lastChunk = !0;
                                for (const i of D.renderTasks)
                                  i.operatorListChanged();
                                this.#n(!0);
                              }
                              if (D.displayReadyCapability)
                                D.displayReadyCapability.reject(t);
                              else if (D.opListReadCapability)
                                D.opListReadCapability.reject(t);
                              else throw t;
                            }
                          },
                        );
                      };
                      s();
                    }
                    _abortOperatorList({
                      intentState: e,
                      reason: y,
                      force: a = !1,
                    }) {
                      if (e.streamReader) {
                        if (
                          (e.streamReaderCancelTimeout &&
                            (clearTimeout(e.streamReaderCancelTimeout),
                            (e.streamReaderCancelTimeout = null)),
                          !a)
                        ) {
                          if (e.renderTasks.size > 0) return;
                          if (
                            y instanceof
                            _display_utils.RenderingCancelledException
                          ) {
                            let p = RENDERING_CANCELLED_TIMEOUT;
                            (y.extraDelay > 0 &&
                              y.extraDelay < 1e3 &&
                              (p += y.extraDelay),
                              (e.streamReaderCancelTimeout = setTimeout(() => {
                                ((e.streamReaderCancelTimeout = null),
                                  this._abortOperatorList({
                                    intentState: e,
                                    reason: y,
                                    force: !0,
                                  }));
                              }, p)));
                            return;
                          }
                        }
                        if (
                          (e.streamReader
                            .cancel(new _util.AbortException(y.message))
                            .catch(() => {}),
                          (e.streamReader = null),
                          !this._transport.destroyed)
                        ) {
                          for (const [p, k] of this._intentStates)
                            if (k === e) {
                              this._intentStates.delete(p);
                              break;
                            }
                          this.cleanup();
                        }
                      }
                    }
                    get stats() {
                      return this._stats;
                    }
                  }
                  exports.PDFPageProxy = PDFPageProxy;
                  class LoopbackPort {
                    #t = new Set();
                    #e = Promise.resolve();
                    postMessage(e, y) {
                      const a = {
                        data: structuredClone(e, y ? { transfer: y } : null),
                      };
                      this.#e.then(() => {
                        for (const p of this.#t) p.call(this, a);
                      });
                    }
                    addEventListener(e, y) {
                      this.#t.add(y);
                    }
                    removeEventListener(e, y) {
                      this.#t.delete(y);
                    }
                    terminate() {
                      this.#t.clear();
                    }
                  }
                  exports.LoopbackPort = LoopbackPort;
                  const PDFWorkerUtil = {
                    isWorkerDisabled: !1,
                    fallbackWorkerSrc: null,
                    fakeWorkerId: 0,
                  };
                  exports.PDFWorkerUtil = PDFWorkerUtil;
                  {
                    if (_util.isNodeJS && typeof commonjsRequire == "function")
                      ((PDFWorkerUtil.isWorkerDisabled = !0),
                        (PDFWorkerUtil.fallbackWorkerSrc = "./pdf.worker.js"));
                    else if (typeof document == "object") {
                      const A = document?.currentScript?.src;
                      A &&
                        (PDFWorkerUtil.fallbackWorkerSrc = A.replace(
                          /(\.(?:min\.)?js)(\?.*)?$/i,
                          ".worker$1$2",
                        ));
                    }
                    ((PDFWorkerUtil.isSameOrigin = function (A, e) {
                      let y;
                      try {
                        if (
                          ((y = new URL(A)), !y.origin || y.origin === "null")
                        )
                          return !1;
                      } catch {
                        return !1;
                      }
                      const a = new URL(e, y);
                      return y.origin === a.origin;
                    }),
                      (PDFWorkerUtil.createCDNWrapper = function (A) {
                        const e = `importScripts("${A}");`;
                        return URL.createObjectURL(new Blob([e]));
                      }));
                  }
                  class PDFWorker {
                    static #workerPorts;
                    constructor({
                      name: A = null,
                      port: e = null,
                      verbosity: y = (0, _util.getVerbosityLevel)(),
                    } = {}) {
                      if (
                        ((this.name = A),
                        (this.destroyed = !1),
                        (this.verbosity = y),
                        (this._readyCapability = new _util.PromiseCapability()),
                        (this._port = null),
                        (this._webWorker = null),
                        (this._messageHandler = null),
                        e)
                      ) {
                        if (PDFWorker.#workerPorts?.has(e))
                          throw new Error(
                            "Cannot use more than one PDFWorker per port.",
                          );
                        ((PDFWorker.#workerPorts ||= new WeakMap()).set(
                          e,
                          this,
                        ),
                          this._initializeFromPort(e));
                        return;
                      }
                      this._initialize();
                    }
                    get promise() {
                      return this._readyCapability.promise;
                    }
                    get port() {
                      return this._port;
                    }
                    get messageHandler() {
                      return this._messageHandler;
                    }
                    _initializeFromPort(A) {
                      ((this._port = A),
                        (this._messageHandler =
                          new _message_handler.MessageHandler(
                            "main",
                            "worker",
                            A,
                          )),
                        this._messageHandler.on("ready", function () {}),
                        this._readyCapability.resolve(),
                        this._messageHandler.send("configure", {
                          verbosity: this.verbosity,
                        }));
                    }
                    _initialize() {
                      if (
                        !PDFWorkerUtil.isWorkerDisabled &&
                        !PDFWorker._mainThreadWorkerMessageHandler
                      ) {
                        let { workerSrc: A } = PDFWorker;
                        try {
                          PDFWorkerUtil.isSameOrigin(window.location.href, A) ||
                            (A = PDFWorkerUtil.createCDNWrapper(
                              new URL(A, window.location).href,
                            ));
                          const e = new Worker(A),
                            y = new _message_handler.MessageHandler(
                              "main",
                              "worker",
                              e,
                            ),
                            a = () => {
                              (e.removeEventListener("error", p),
                                y.destroy(),
                                e.terminate(),
                                this.destroyed
                                  ? this._readyCapability.reject(
                                      new Error("Worker was destroyed"),
                                    )
                                  : this._setupFakeWorker());
                            },
                            p = () => {
                              this._webWorker || a();
                            };
                          (e.addEventListener("error", p),
                            y.on("test", (T) => {
                              if (
                                (e.removeEventListener("error", p),
                                this.destroyed)
                              ) {
                                a();
                                return;
                              }
                              T
                                ? ((this._messageHandler = y),
                                  (this._port = e),
                                  (this._webWorker = e),
                                  this._readyCapability.resolve(),
                                  y.send("configure", {
                                    verbosity: this.verbosity,
                                  }))
                                : (this._setupFakeWorker(),
                                  y.destroy(),
                                  e.terminate());
                            }),
                            y.on("ready", (T) => {
                              if (
                                (e.removeEventListener("error", p),
                                this.destroyed)
                              ) {
                                a();
                                return;
                              }
                              try {
                                k();
                              } catch {
                                this._setupFakeWorker();
                              }
                            }));
                          const k = () => {
                            const T = new Uint8Array();
                            y.send("test", T, [T.buffer]);
                          };
                          k();
                          return;
                        } catch {
                          (0, _util.info)("The worker has been disabled.");
                        }
                      }
                      this._setupFakeWorker();
                    }
                    _setupFakeWorker() {
                      (PDFWorkerUtil.isWorkerDisabled ||
                        ((0, _util.warn)("Setting up fake worker."),
                        (PDFWorkerUtil.isWorkerDisabled = !0)),
                        PDFWorker._setupFakeWorkerGlobal
                          .then((A) => {
                            if (this.destroyed) {
                              this._readyCapability.reject(
                                new Error("Worker was destroyed"),
                              );
                              return;
                            }
                            const e = new LoopbackPort();
                            this._port = e;
                            const y = `fake${PDFWorkerUtil.fakeWorkerId++}`,
                              a = new _message_handler.MessageHandler(
                                y + "_worker",
                                y,
                                e,
                              );
                            A.setup(a, e);
                            const p = new _message_handler.MessageHandler(
                              y,
                              y + "_worker",
                              e,
                            );
                            ((this._messageHandler = p),
                              this._readyCapability.resolve(),
                              p.send("configure", {
                                verbosity: this.verbosity,
                              }));
                          })
                          .catch((A) => {
                            this._readyCapability.reject(
                              new Error(
                                `Setting up fake worker failed: "${A.message}".`,
                              ),
                            );
                          }));
                    }
                    destroy() {
                      ((this.destroyed = !0),
                        this._webWorker &&
                          (this._webWorker.terminate(),
                          (this._webWorker = null)),
                        PDFWorker.#workerPorts?.delete(this._port),
                        (this._port = null),
                        this._messageHandler &&
                          (this._messageHandler.destroy(),
                          (this._messageHandler = null)));
                    }
                    static fromPort(A) {
                      if (!A?.port)
                        throw new Error(
                          "PDFWorker.fromPort - invalid method signature.",
                        );
                      const e = this.#workerPorts?.get(A.port);
                      if (e) {
                        if (e._pendingDestroy)
                          throw new Error(
                            "PDFWorker.fromPort - the worker is being destroyed.\nPlease remember to await `PDFDocumentLoadingTask.destroy()`-calls.",
                          );
                        return e;
                      }
                      return new PDFWorker(A);
                    }
                    static get workerSrc() {
                      if (_worker_options.GlobalWorkerOptions.workerSrc)
                        return _worker_options.GlobalWorkerOptions.workerSrc;
                      if (PDFWorkerUtil.fallbackWorkerSrc !== null)
                        return (
                          _util.isNodeJS ||
                            (0, _display_utils.deprecated)(
                              'No "GlobalWorkerOptions.workerSrc" specified.',
                            ),
                          PDFWorkerUtil.fallbackWorkerSrc
                        );
                      throw new Error(
                        'No "GlobalWorkerOptions.workerSrc" specified.',
                      );
                    }
                    static get _mainThreadWorkerMessageHandler() {
                      try {
                        return (
                          globalThis.pdfjsWorker?.WorkerMessageHandler || null
                        );
                      } catch {
                        return null;
                      }
                    }
                    static get _setupFakeWorkerGlobal() {
                      const loader = async () => {
                        const mainWorkerMessageHandler =
                          this._mainThreadWorkerMessageHandler;
                        if (mainWorkerMessageHandler)
                          return mainWorkerMessageHandler;
                        if (
                          _util.isNodeJS &&
                          typeof commonjsRequire == "function"
                        ) {
                          const worker = eval("require")(this.workerSrc);
                          return worker.WorkerMessageHandler;
                        }
                        return (
                          await (0, _display_utils.loadScript)(this.workerSrc),
                          window.pdfjsWorker.WorkerMessageHandler
                        );
                      };
                      return (0, _util.shadow)(
                        this,
                        "_setupFakeWorkerGlobal",
                        loader(),
                      );
                    }
                  }
                  exports.PDFWorker = PDFWorker;
                  class WorkerTransport {
                    #t = new Map();
                    #e = new Map();
                    #n = new Map();
                    #i = null;
                    constructor(e, y, a, p, k) {
                      ((this.messageHandler = e),
                        (this.loadingTask = y),
                        (this.commonObjs = new PDFObjects()),
                        (this.fontLoader = new _font_loader.FontLoader({
                          ownerDocument: p.ownerDocument,
                          styleElement: p.styleElement,
                        })),
                        (this._params = p),
                        (this.canvasFactory = k.canvasFactory),
                        (this.filterFactory = k.filterFactory),
                        (this.cMapReaderFactory = k.cMapReaderFactory),
                        (this.standardFontDataFactory =
                          k.standardFontDataFactory),
                        (this.destroyed = !1),
                        (this.destroyCapability = null),
                        (this._networkStream = a),
                        (this._fullReader = null),
                        (this._lastProgress = null),
                        (this.downloadInfoCapability =
                          new _util.PromiseCapability()),
                        this.setupMessageHandler());
                    }
                    #o(e, y = null) {
                      const a = this.#t.get(e);
                      if (a) return a;
                      const p = this.messageHandler.sendWithPromise(e, y);
                      return (this.#t.set(e, p), p);
                    }
                    get annotationStorage() {
                      return (0, _util.shadow)(
                        this,
                        "annotationStorage",
                        new _annotation_storage.AnnotationStorage(),
                      );
                    }
                    getRenderingIntent(
                      e,
                      y = _util.AnnotationMode.ENABLE,
                      a = null,
                      p = !1,
                    ) {
                      let k = _util.RenderingIntentFlag.DISPLAY,
                        T = _annotation_storage.SerializableEmpty;
                      switch (e) {
                        case "any":
                          k = _util.RenderingIntentFlag.ANY;
                          break;
                        case "display":
                          break;
                        case "print":
                          k = _util.RenderingIntentFlag.PRINT;
                          break;
                        default:
                          (0, _util.warn)(
                            `getRenderingIntent - invalid intent: ${e}`,
                          );
                      }
                      switch (y) {
                        case _util.AnnotationMode.DISABLE:
                          k += _util.RenderingIntentFlag.ANNOTATIONS_DISABLE;
                          break;
                        case _util.AnnotationMode.ENABLE:
                          break;
                        case _util.AnnotationMode.ENABLE_FORMS:
                          k += _util.RenderingIntentFlag.ANNOTATIONS_FORMS;
                          break;
                        case _util.AnnotationMode.ENABLE_STORAGE:
                          ((k += _util.RenderingIntentFlag.ANNOTATIONS_STORAGE),
                            (T = (
                              k & _util.RenderingIntentFlag.PRINT &&
                              a instanceof
                                _annotation_storage.PrintAnnotationStorage
                                ? a
                                : this.annotationStorage
                            ).serializable));
                          break;
                        default:
                          (0, _util.warn)(
                            `getRenderingIntent - invalid annotationMode: ${y}`,
                          );
                      }
                      return (
                        p && (k += _util.RenderingIntentFlag.OPLIST),
                        {
                          renderingIntent: k,
                          cacheKey: `${k}_${T.hash}`,
                          annotationStorageSerializable: T,
                        }
                      );
                    }
                    destroy() {
                      if (this.destroyCapability)
                        return this.destroyCapability.promise;
                      ((this.destroyed = !0),
                        (this.destroyCapability =
                          new _util.PromiseCapability()),
                        this.#i?.reject(
                          new Error(
                            "Worker was destroyed during onPassword callback",
                          ),
                        ));
                      const e = [];
                      for (const a of this.#e.values()) e.push(a._destroy());
                      (this.#e.clear(),
                        this.#n.clear(),
                        this.hasOwnProperty("annotationStorage") &&
                          this.annotationStorage.resetModified());
                      const y = this.messageHandler.sendWithPromise(
                        "Terminate",
                        null,
                      );
                      return (
                        e.push(y),
                        Promise.all(e).then(() => {
                          (this.commonObjs.clear(),
                            this.fontLoader.clear(),
                            this.#t.clear(),
                            this.filterFactory.destroy(),
                            this._networkStream?.cancelAllRequests(
                              new _util.AbortException(
                                "Worker was terminated.",
                              ),
                            ),
                            this.messageHandler &&
                              (this.messageHandler.destroy(),
                              (this.messageHandler = null)),
                            this.destroyCapability.resolve());
                        }, this.destroyCapability.reject),
                        this.destroyCapability.promise
                      );
                    }
                    setupMessageHandler() {
                      const { messageHandler: e, loadingTask: y } = this;
                      (e.on("GetReader", (a, p) => {
                        ((0, _util.assert)(
                          this._networkStream,
                          "GetReader - no `IPDFStream` instance available.",
                        ),
                          (this._fullReader =
                            this._networkStream.getFullReader()),
                          (this._fullReader.onProgress = (k) => {
                            this._lastProgress = {
                              loaded: k.loaded,
                              total: k.total,
                            };
                          }),
                          (p.onPull = () => {
                            this._fullReader
                              .read()
                              .then(function ({ value: k, done: T }) {
                                if (T) {
                                  p.close();
                                  return;
                                }
                                ((0, _util.assert)(
                                  k instanceof ArrayBuffer,
                                  "GetReader - expected an ArrayBuffer.",
                                ),
                                  p.enqueue(new Uint8Array(k), 1, [k]));
                              })
                              .catch((k) => {
                                p.error(k);
                              });
                          }),
                          (p.onCancel = (k) => {
                            (this._fullReader.cancel(k),
                              p.ready.catch((T) => {
                                if (!this.destroyed) throw T;
                              }));
                          }));
                      }),
                        e.on("ReaderHeadersReady", (a) => {
                          const p = new _util.PromiseCapability(),
                            k = this._fullReader;
                          return (
                            k.headersReady.then(() => {
                              ((!k.isStreamingSupported ||
                                !k.isRangeSupported) &&
                                (this._lastProgress &&
                                  y.onProgress?.(this._lastProgress),
                                (k.onProgress = (T) => {
                                  y.onProgress?.({
                                    loaded: T.loaded,
                                    total: T.total,
                                  });
                                })),
                                p.resolve({
                                  isStreamingSupported: k.isStreamingSupported,
                                  isRangeSupported: k.isRangeSupported,
                                  contentLength: k.contentLength,
                                }));
                            }, p.reject),
                            p.promise
                          );
                        }),
                        e.on("GetRangeReader", (a, p) => {
                          (0, _util.assert)(
                            this._networkStream,
                            "GetRangeReader - no `IPDFStream` instance available.",
                          );
                          const k = this._networkStream.getRangeReader(
                            a.begin,
                            a.end,
                          );
                          if (!k) {
                            p.close();
                            return;
                          }
                          ((p.onPull = () => {
                            k.read()
                              .then(function ({ value: T, done: j }) {
                                if (j) {
                                  p.close();
                                  return;
                                }
                                ((0, _util.assert)(
                                  T instanceof ArrayBuffer,
                                  "GetRangeReader - expected an ArrayBuffer.",
                                ),
                                  p.enqueue(new Uint8Array(T), 1, [T]));
                              })
                              .catch((T) => {
                                p.error(T);
                              });
                          }),
                            (p.onCancel = (T) => {
                              (k.cancel(T),
                                p.ready.catch((j) => {
                                  if (!this.destroyed) throw j;
                                }));
                            }));
                        }),
                        e.on("GetDoc", ({ pdfInfo: a }) => {
                          ((this._numPages = a.numPages),
                            (this._htmlForXfa = a.htmlForXfa),
                            delete a.htmlForXfa,
                            y._capability.resolve(
                              new PDFDocumentProxy(a, this),
                            ));
                        }),
                        e.on("DocException", function (a) {
                          let p;
                          switch (a.name) {
                            case "PasswordException":
                              p = new _util.PasswordException(
                                a.message,
                                a.code,
                              );
                              break;
                            case "InvalidPDFException":
                              p = new _util.InvalidPDFException(a.message);
                              break;
                            case "MissingPDFException":
                              p = new _util.MissingPDFException(a.message);
                              break;
                            case "UnexpectedResponseException":
                              p = new _util.UnexpectedResponseException(
                                a.message,
                                a.status,
                              );
                              break;
                            case "UnknownErrorException":
                              p = new _util.UnknownErrorException(
                                a.message,
                                a.details,
                              );
                              break;
                            default:
                              (0, _util.unreachable)(
                                "DocException - expected a valid Error.",
                              );
                          }
                          y._capability.reject(p);
                        }),
                        e.on("PasswordRequest", (a) => {
                          if (
                            ((this.#i = new _util.PromiseCapability()),
                            y.onPassword)
                          ) {
                            const p = (k) => {
                              k instanceof Error
                                ? this.#i.reject(k)
                                : this.#i.resolve({ password: k });
                            };
                            try {
                              y.onPassword(p, a.code);
                            } catch (k) {
                              this.#i.reject(k);
                            }
                          } else
                            this.#i.reject(
                              new _util.PasswordException(a.message, a.code),
                            );
                          return this.#i.promise;
                        }),
                        e.on("DataLoaded", (a) => {
                          (y.onProgress?.({
                            loaded: a.length,
                            total: a.length,
                          }),
                            this.downloadInfoCapability.resolve(a));
                        }),
                        e.on("StartRenderPage", (a) => {
                          if (this.destroyed) return;
                          this.#e
                            .get(a.pageIndex)
                            ._startRenderPage(a.transparency, a.cacheKey);
                        }),
                        e.on("commonobj", ([a, p, k]) => {
                          if (!this.destroyed && !this.commonObjs.has(a))
                            switch (p) {
                              case "Font":
                                const T = this._params;
                                if ("error" in k) {
                                  const s = k.error;
                                  ((0, _util.warn)(
                                    `Error during font loading: ${s}`,
                                  ),
                                    this.commonObjs.resolve(a, s));
                                  break;
                                }
                                const j =
                                    T.pdfBug &&
                                    globalThis.FontInspector?.enabled
                                      ? (s, t) =>
                                          globalThis.FontInspector.fontAdded(
                                            s,
                                            t,
                                          )
                                      : null,
                                  D = new _font_loader.FontFaceObject(k, {
                                    isEvalSupported: T.isEvalSupported,
                                    disableFontFace: T.disableFontFace,
                                    ignoreErrors: T.ignoreErrors,
                                    inspectFont: j,
                                  });
                                this.fontLoader
                                  .bind(D)
                                  .catch((s) =>
                                    e.sendWithPromise("FontFallback", {
                                      id: a,
                                    }),
                                  )
                                  .finally(() => {
                                    (!T.fontExtraProperties &&
                                      D.data &&
                                      (D.data = null),
                                      this.commonObjs.resolve(a, D));
                                  });
                                break;
                              case "FontPath":
                              case "Image":
                              case "Pattern":
                                this.commonObjs.resolve(a, k);
                                break;
                              default:
                                throw new Error(
                                  `Got unknown common object type ${p}`,
                                );
                            }
                        }),
                        e.on("obj", ([a, p, k, T]) => {
                          if (this.destroyed) return;
                          const j = this.#e.get(p);
                          if (!j.objs.has(a))
                            switch (k) {
                              case "Image":
                                if ((j.objs.resolve(a, T), T)) {
                                  let D;
                                  if (T.bitmap) {
                                    const { width: s, height: t } = T;
                                    D = s * t * 4;
                                  } else D = T.data?.length || 0;
                                  D > _util.MAX_IMAGE_SIZE_TO_CACHE &&
                                    (j._maybeCleanupAfterRender = !0);
                                }
                                break;
                              case "Pattern":
                                j.objs.resolve(a, T);
                                break;
                              default:
                                throw new Error(`Got unknown object type ${k}`);
                            }
                        }),
                        e.on("DocProgress", (a) => {
                          this.destroyed ||
                            y.onProgress?.({
                              loaded: a.loaded,
                              total: a.total,
                            });
                        }),
                        e.on("FetchBuiltInCMap", (a) =>
                          this.destroyed
                            ? Promise.reject(new Error("Worker was destroyed."))
                            : this.cMapReaderFactory
                              ? this.cMapReaderFactory.fetch(a)
                              : Promise.reject(
                                  new Error(
                                    "CMapReaderFactory not initialized, see the `useWorkerFetch` parameter.",
                                  ),
                                ),
                        ),
                        e.on("FetchStandardFontData", (a) =>
                          this.destroyed
                            ? Promise.reject(new Error("Worker was destroyed."))
                            : this.standardFontDataFactory
                              ? this.standardFontDataFactory.fetch(a)
                              : Promise.reject(
                                  new Error(
                                    "StandardFontDataFactory not initialized, see the `useWorkerFetch` parameter.",
                                  ),
                                ),
                        ));
                    }
                    getData() {
                      return this.messageHandler.sendWithPromise(
                        "GetData",
                        null,
                      );
                    }
                    saveDocument() {
                      this.annotationStorage.size <= 0 &&
                        (0, _util.warn)(
                          "saveDocument called while `annotationStorage` is empty, please use the getData-method instead.",
                        );
                      const { map: e, transfers: y } =
                        this.annotationStorage.serializable;
                      return this.messageHandler
                        .sendWithPromise(
                          "SaveDocument",
                          {
                            isPureXfa: !!this._htmlForXfa,
                            numPages: this._numPages,
                            annotationStorage: e,
                            filename: this._fullReader?.filename ?? null,
                          },
                          y,
                        )
                        .finally(() => {
                          this.annotationStorage.resetModified();
                        });
                    }
                    getPage(e) {
                      if (!Number.isInteger(e) || e <= 0 || e > this._numPages)
                        return Promise.reject(
                          new Error("Invalid page request."),
                        );
                      const y = e - 1,
                        a = this.#n.get(y);
                      if (a) return a;
                      const p = this.messageHandler
                        .sendWithPromise("GetPage", { pageIndex: y })
                        .then((k) => {
                          if (this.destroyed)
                            throw new Error("Transport destroyed");
                          const T = new PDFPageProxy(
                            y,
                            k,
                            this,
                            this._params.pdfBug,
                          );
                          return (this.#e.set(y, T), T);
                        });
                      return (this.#n.set(y, p), p);
                    }
                    getPageIndex(e) {
                      return typeof e != "object" ||
                        e === null ||
                        !Number.isInteger(e.num) ||
                        e.num < 0 ||
                        !Number.isInteger(e.gen) ||
                        e.gen < 0
                        ? Promise.reject(
                            new Error("Invalid pageIndex request."),
                          )
                        : this.messageHandler.sendWithPromise("GetPageIndex", {
                            num: e.num,
                            gen: e.gen,
                          });
                    }
                    getAnnotations(e, y) {
                      return this.messageHandler.sendWithPromise(
                        "GetAnnotations",
                        { pageIndex: e, intent: y },
                      );
                    }
                    getFieldObjects() {
                      return this.#o("GetFieldObjects");
                    }
                    hasJSActions() {
                      return this.#o("HasJSActions");
                    }
                    getCalculationOrderIds() {
                      return this.messageHandler.sendWithPromise(
                        "GetCalculationOrderIds",
                        null,
                      );
                    }
                    getDestinations() {
                      return this.messageHandler.sendWithPromise(
                        "GetDestinations",
                        null,
                      );
                    }
                    getDestination(e) {
                      return typeof e != "string"
                        ? Promise.reject(
                            new Error("Invalid destination request."),
                          )
                        : this.messageHandler.sendWithPromise(
                            "GetDestination",
                            { id: e },
                          );
                    }
                    getPageLabels() {
                      return this.messageHandler.sendWithPromise(
                        "GetPageLabels",
                        null,
                      );
                    }
                    getPageLayout() {
                      return this.messageHandler.sendWithPromise(
                        "GetPageLayout",
                        null,
                      );
                    }
                    getPageMode() {
                      return this.messageHandler.sendWithPromise(
                        "GetPageMode",
                        null,
                      );
                    }
                    getViewerPreferences() {
                      return this.messageHandler.sendWithPromise(
                        "GetViewerPreferences",
                        null,
                      );
                    }
                    getOpenAction() {
                      return this.messageHandler.sendWithPromise(
                        "GetOpenAction",
                        null,
                      );
                    }
                    getAttachments() {
                      return this.messageHandler.sendWithPromise(
                        "GetAttachments",
                        null,
                      );
                    }
                    getDocJSActions() {
                      return this.#o("GetDocJSActions");
                    }
                    getPageJSActions(e) {
                      return this.messageHandler.sendWithPromise(
                        "GetPageJSActions",
                        { pageIndex: e },
                      );
                    }
                    getStructTree(e) {
                      return this.messageHandler.sendWithPromise(
                        "GetStructTree",
                        { pageIndex: e },
                      );
                    }
                    getOutline() {
                      return this.messageHandler.sendWithPromise(
                        "GetOutline",
                        null,
                      );
                    }
                    getOptionalContentConfig() {
                      return this.messageHandler
                        .sendWithPromise("GetOptionalContentConfig", null)
                        .then(
                          (e) =>
                            new _optional_content_config.OptionalContentConfig(
                              e,
                            ),
                        );
                    }
                    getPermissions() {
                      return this.messageHandler.sendWithPromise(
                        "GetPermissions",
                        null,
                      );
                    }
                    getMetadata() {
                      const e = "GetMetadata",
                        y = this.#t.get(e);
                      if (y) return y;
                      const a = this.messageHandler
                        .sendWithPromise(e, null)
                        .then((p) => ({
                          info: p[0],
                          metadata: p[1] ? new _metadata.Metadata(p[1]) : null,
                          contentDispositionFilename:
                            this._fullReader?.filename ?? null,
                          contentLength:
                            this._fullReader?.contentLength ?? null,
                        }));
                      return (this.#t.set(e, a), a);
                    }
                    getMarkInfo() {
                      return this.messageHandler.sendWithPromise(
                        "GetMarkInfo",
                        null,
                      );
                    }
                    async startCleanup(e = !1) {
                      if (!this.destroyed) {
                        await this.messageHandler.sendWithPromise(
                          "Cleanup",
                          null,
                        );
                        for (const y of this.#e.values())
                          if (!y.cleanup())
                            throw new Error(
                              `startCleanup: Page ${y.pageNumber} is currently rendering.`,
                            );
                        (this.commonObjs.clear(),
                          e || this.fontLoader.clear(),
                          this.#t.clear(),
                          this.filterFactory.destroy(!0));
                      }
                    }
                    get loadingParams() {
                      const { disableAutoFetch: e, enableXfa: y } =
                        this._params;
                      return (0, _util.shadow)(this, "loadingParams", {
                        disableAutoFetch: e,
                        enableXfa: y,
                      });
                    }
                  }
                  class PDFObjects {
                    #t = Object.create(null);
                    #e(e) {
                      return (this.#t[e] ||= {
                        capability: new _util.PromiseCapability(),
                        data: null,
                      });
                    }
                    get(e, y = null) {
                      if (y) {
                        const p = this.#e(e);
                        return (
                          p.capability.promise.then(() => y(p.data)),
                          null
                        );
                      }
                      const a = this.#t[e];
                      if (!a?.capability.settled)
                        throw new Error(
                          `Requesting object that isn't resolved yet ${e}.`,
                        );
                      return a.data;
                    }
                    has(e) {
                      return this.#t[e]?.capability.settled || !1;
                    }
                    resolve(e, y = null) {
                      const a = this.#e(e);
                      ((a.data = y), a.capability.resolve());
                    }
                    clear() {
                      for (const e in this.#t) {
                        const { data: y } = this.#t[e];
                        y?.bitmap?.close();
                      }
                      this.#t = Object.create(null);
                    }
                  }
                  class RenderTask {
                    #t = null;
                    constructor(e) {
                      ((this.#t = e), (this.onContinue = null));
                    }
                    get promise() {
                      return this.#t.capability.promise;
                    }
                    cancel(e = 0) {
                      this.#t.cancel(null, e);
                    }
                    get separateAnnots() {
                      const { separateAnnots: e } = this.#t.operatorList;
                      if (!e) return !1;
                      const { annotationCanvasMap: y } = this.#t;
                      return e.form || (e.canvas && y?.size > 0);
                    }
                  }
                  exports.RenderTask = RenderTask;
                  class InternalRenderTask {
                    static #t = new WeakSet();
                    constructor({
                      callback: e,
                      params: y,
                      objs: a,
                      commonObjs: p,
                      annotationCanvasMap: k,
                      operatorList: T,
                      pageIndex: j,
                      canvasFactory: D,
                      filterFactory: s,
                      useRequestAnimationFrame: t = !1,
                      pdfBug: i = !1,
                      pageColors: h = null,
                    }) {
                      ((this.callback = e),
                        (this.params = y),
                        (this.objs = a),
                        (this.commonObjs = p),
                        (this.annotationCanvasMap = k),
                        (this.operatorListIdx = null),
                        (this.operatorList = T),
                        (this._pageIndex = j),
                        (this.canvasFactory = D),
                        (this.filterFactory = s),
                        (this._pdfBug = i),
                        (this.pageColors = h),
                        (this.running = !1),
                        (this.graphicsReadyCallback = null),
                        (this.graphicsReady = !1),
                        (this._useRequestAnimationFrame =
                          t === !0 && typeof window < "u"),
                        (this.cancelled = !1),
                        (this.capability = new _util.PromiseCapability()),
                        (this.task = new RenderTask(this)),
                        (this._cancelBound = this.cancel.bind(this)),
                        (this._continueBound = this._continue.bind(this)),
                        (this._scheduleNextBound =
                          this._scheduleNext.bind(this)),
                        (this._nextBound = this._next.bind(this)),
                        (this._canvas = y.canvasContext.canvas));
                    }
                    get completed() {
                      return this.capability.promise.catch(function () {});
                    }
                    initializeGraphics({
                      transparency: e = !1,
                      optionalContentConfig: y,
                    }) {
                      if (this.cancelled) return;
                      if (this._canvas) {
                        if (InternalRenderTask.#t.has(this._canvas))
                          throw new Error(
                            "Cannot use the same canvas during multiple render() operations. Use different canvas or ensure previous operations were cancelled or completed.",
                          );
                        InternalRenderTask.#t.add(this._canvas);
                      }
                      this._pdfBug &&
                        globalThis.StepperManager?.enabled &&
                        ((this.stepper = globalThis.StepperManager.create(
                          this._pageIndex,
                        )),
                        this.stepper.init(this.operatorList),
                        (this.stepper.nextBreakPoint =
                          this.stepper.getNextBreakPoint()));
                      const {
                        canvasContext: a,
                        viewport: p,
                        transform: k,
                        background: T,
                      } = this.params;
                      ((this.gfx = new _canvas.CanvasGraphics(
                        a,
                        this.commonObjs,
                        this.objs,
                        this.canvasFactory,
                        this.filterFactory,
                        { optionalContentConfig: y },
                        this.annotationCanvasMap,
                        this.pageColors,
                      )),
                        this.gfx.beginDrawing({
                          transform: k,
                          viewport: p,
                          transparency: e,
                          background: T,
                        }),
                        (this.operatorListIdx = 0),
                        (this.graphicsReady = !0),
                        this.graphicsReadyCallback?.());
                    }
                    cancel(e = null, y = 0) {
                      ((this.running = !1),
                        (this.cancelled = !0),
                        this.gfx?.endDrawing(),
                        InternalRenderTask.#t.delete(this._canvas),
                        this.callback(
                          e ||
                            new _display_utils.RenderingCancelledException(
                              `Rendering cancelled, page ${this._pageIndex + 1}`,
                              y,
                            ),
                        ));
                    }
                    operatorListChanged() {
                      if (!this.graphicsReady) {
                        this.graphicsReadyCallback ||= this._continueBound;
                        return;
                      }
                      (this.stepper?.updateOperatorList(this.operatorList),
                        !this.running && this._continue());
                    }
                    _continue() {
                      ((this.running = !0),
                        !this.cancelled &&
                          (this.task.onContinue
                            ? this.task.onContinue(this._scheduleNextBound)
                            : this._scheduleNext()));
                    }
                    _scheduleNext() {
                      this._useRequestAnimationFrame
                        ? window.requestAnimationFrame(() => {
                            this._nextBound().catch(this._cancelBound);
                          })
                        : Promise.resolve()
                            .then(this._nextBound)
                            .catch(this._cancelBound);
                    }
                    async _next() {
                      this.cancelled ||
                        ((this.operatorListIdx = this.gfx.executeOperatorList(
                          this.operatorList,
                          this.operatorListIdx,
                          this._continueBound,
                          this.stepper,
                        )),
                        this.operatorListIdx ===
                          this.operatorList.argsArray.length &&
                          ((this.running = !1),
                          this.operatorList.lastChunk &&
                            (this.gfx.endDrawing(),
                            InternalRenderTask.#t.delete(this._canvas),
                            this.callback())));
                    }
                  }
                  const version = "3.11.174";
                  exports.version = version;
                  const build = "ce8716743";
                  exports.build = build;
                },
                (A, e, y) => {
                  (Object.defineProperty(e, "__esModule", { value: !0 }),
                    (e.SerializableEmpty =
                      e.PrintAnnotationStorage =
                      e.AnnotationStorage =
                        void 0));
                  var a = y(1),
                    p = y(4),
                    k = y(8);
                  const T = Object.freeze({
                    map: null,
                    hash: "",
                    transfers: void 0,
                  });
                  e.SerializableEmpty = T;
                  class j {
                    #t = !1;
                    #e = new Map();
                    constructor() {
                      ((this.onSetModified = null),
                        (this.onResetModified = null),
                        (this.onAnnotationEditor = null));
                    }
                    getValue(t, i) {
                      const h = this.#e.get(t);
                      return h === void 0 ? i : Object.assign(i, h);
                    }
                    getRawValue(t) {
                      return this.#e.get(t);
                    }
                    remove(t) {
                      if (
                        (this.#e.delete(t),
                        this.#e.size === 0 && this.resetModified(),
                        typeof this.onAnnotationEditor == "function")
                      ) {
                        for (const i of this.#e.values())
                          if (i instanceof p.AnnotationEditor) return;
                        this.onAnnotationEditor(null);
                      }
                    }
                    setValue(t, i) {
                      const h = this.#e.get(t);
                      let c = !1;
                      if (h !== void 0)
                        for (const [n, d] of Object.entries(i))
                          h[n] !== d && ((c = !0), (h[n] = d));
                      else ((c = !0), this.#e.set(t, i));
                      (c && this.#n(),
                        i instanceof p.AnnotationEditor &&
                          typeof this.onAnnotationEditor == "function" &&
                          this.onAnnotationEditor(i.constructor._type));
                    }
                    has(t) {
                      return this.#e.has(t);
                    }
                    getAll() {
                      return this.#e.size > 0
                        ? (0, a.objectFromMap)(this.#e)
                        : null;
                    }
                    setAll(t) {
                      for (const [i, h] of Object.entries(t))
                        this.setValue(i, h);
                    }
                    get size() {
                      return this.#e.size;
                    }
                    #n() {
                      this.#t ||
                        ((this.#t = !0),
                        typeof this.onSetModified == "function" &&
                          this.onSetModified());
                    }
                    resetModified() {
                      this.#t &&
                        ((this.#t = !1),
                        typeof this.onResetModified == "function" &&
                          this.onResetModified());
                    }
                    get print() {
                      return new D(this);
                    }
                    get serializable() {
                      if (this.#e.size === 0) return T;
                      const t = new Map(),
                        i = new k.MurmurHash3_64(),
                        h = [],
                        c = Object.create(null);
                      let n = !1;
                      for (const [d, m] of this.#e) {
                        const l =
                          m instanceof p.AnnotationEditor
                            ? m.serialize(!1, c)
                            : m;
                        l &&
                          (t.set(d, l),
                          i.update(`${d}:${JSON.stringify(l)}`),
                          (n ||= !!l.bitmap));
                      }
                      if (n)
                        for (const d of t.values())
                          d.bitmap && h.push(d.bitmap);
                      return t.size > 0
                        ? { map: t, hash: i.hexdigest(), transfers: h }
                        : T;
                    }
                  }
                  e.AnnotationStorage = j;
                  class D extends j {
                    #t;
                    constructor(t) {
                      super();
                      const { map: i, hash: h, transfers: c } = t.serializable,
                        n = structuredClone(i, c ? { transfer: c } : null);
                      this.#t = { map: n, hash: h, transfers: c };
                    }
                    get print() {
                      (0, a.unreachable)(
                        "Should not call PrintAnnotationStorage.print",
                      );
                    }
                    get serializable() {
                      return this.#t;
                    }
                  }
                  e.PrintAnnotationStorage = D;
                },
                (A, e, y) => {
                  (Object.defineProperty(e, "__esModule", { value: !0 }),
                    (e.AnnotationEditor = void 0));
                  var a = y(5),
                    p = y(1),
                    k = y(6);
                  class T {
                    #t = "";
                    #e = !1;
                    #n = null;
                    #i = null;
                    #o = null;
                    #a = !1;
                    #r = null;
                    #l = this.focusin.bind(this);
                    #c = this.focusout.bind(this);
                    #s = !1;
                    #f = !1;
                    #d = !1;
                    _initialOptions = Object.create(null);
                    _uiManager = null;
                    _focusEventsAllowed = !0;
                    _l10nPromise = null;
                    #u = !1;
                    #p = T._zIndex++;
                    static _borderLineWidth = -1;
                    static _colorManager = new a.ColorManager();
                    static _zIndex = 1;
                    static SMALL_EDITOR_SIZE = 0;
                    constructor(s) {
                      (this.constructor === T &&
                        (0, p.unreachable)(
                          "Cannot initialize AnnotationEditor.",
                        ),
                        (this.parent = s.parent),
                        (this.id = s.id),
                        (this.width = this.height = null),
                        (this.pageIndex = s.parent.pageIndex),
                        (this.name = s.name),
                        (this.div = null),
                        (this._uiManager = s.uiManager),
                        (this.annotationElementId = null),
                        (this._willKeepAspectRatio = !1),
                        (this._initialOptions.isCentered = s.isCentered),
                        (this._structTreeParentId = null));
                      const {
                        rotation: t,
                        rawDims: {
                          pageWidth: i,
                          pageHeight: h,
                          pageX: c,
                          pageY: n,
                        },
                      } = this.parent.viewport;
                      ((this.rotation = t),
                        (this.pageRotation =
                          (360 + t - this._uiManager.viewParameters.rotation) %
                          360),
                        (this.pageDimensions = [i, h]),
                        (this.pageTranslation = [c, n]));
                      const [d, m] = this.parentDimensions;
                      ((this.x = s.x / d),
                        (this.y = s.y / m),
                        (this.isAttachedToDOM = !1),
                        (this.deleted = !1));
                    }
                    get editorType() {
                      return Object.getPrototypeOf(this).constructor._type;
                    }
                    static get _defaultLineColor() {
                      return (0, p.shadow)(
                        this,
                        "_defaultLineColor",
                        this._colorManager.getHexCode("CanvasText"),
                      );
                    }
                    static deleteAnnotationElement(s) {
                      const t = new j({
                        id: s.parent.getNextId(),
                        parent: s.parent,
                        uiManager: s._uiManager,
                      });
                      ((t.annotationElementId = s.annotationElementId),
                        (t.deleted = !0),
                        t._uiManager.addToAnnotationStorage(t));
                    }
                    static initialize(s, t = null) {
                      if (
                        ((T._l10nPromise ||= new Map(
                          [
                            "editor_alt_text_button_label",
                            "editor_alt_text_edit_button_label",
                            "editor_alt_text_decorative_tooltip",
                          ].map((h) => [h, s.get(h)]),
                        )),
                        t?.strings)
                      )
                        for (const h of t.strings)
                          T._l10nPromise.set(h, s.get(h));
                      if (T._borderLineWidth !== -1) return;
                      const i = getComputedStyle(document.documentElement);
                      T._borderLineWidth =
                        parseFloat(i.getPropertyValue("--outline-width")) || 0;
                    }
                    static updateDefaultParams(s, t) {}
                    static get defaultPropertiesToUpdate() {
                      return [];
                    }
                    static isHandlingMimeForPasting(s) {
                      return !1;
                    }
                    static paste(s, t) {
                      (0, p.unreachable)("Not implemented");
                    }
                    get propertiesToUpdate() {
                      return [];
                    }
                    get _isDraggable() {
                      return this.#u;
                    }
                    set _isDraggable(s) {
                      ((this.#u = s),
                        this.div?.classList.toggle("draggable", s));
                    }
                    center() {
                      const [s, t] = this.pageDimensions;
                      switch (this.parentRotation) {
                        case 90:
                          ((this.x -= (this.height * t) / (s * 2)),
                            (this.y += (this.width * s) / (t * 2)));
                          break;
                        case 180:
                          ((this.x += this.width / 2),
                            (this.y += this.height / 2));
                          break;
                        case 270:
                          ((this.x += (this.height * t) / (s * 2)),
                            (this.y -= (this.width * s) / (t * 2)));
                          break;
                        default:
                          ((this.x -= this.width / 2),
                            (this.y -= this.height / 2));
                          break;
                      }
                      this.fixAndSetPosition();
                    }
                    addCommands(s) {
                      this._uiManager.addCommands(s);
                    }
                    get currentLayer() {
                      return this._uiManager.currentLayer;
                    }
                    setInBackground() {
                      this.div.style.zIndex = 0;
                    }
                    setInForeground() {
                      this.div.style.zIndex = this.#p;
                    }
                    setParent(s) {
                      (s !== null &&
                        ((this.pageIndex = s.pageIndex),
                        (this.pageDimensions = s.pageDimensions)),
                        (this.parent = s));
                    }
                    focusin(s) {
                      this._focusEventsAllowed &&
                        (this.#s
                          ? (this.#s = !1)
                          : this.parent.setSelected(this));
                    }
                    focusout(s) {
                      !this._focusEventsAllowed ||
                        !this.isAttachedToDOM ||
                        s.relatedTarget?.closest(`#${this.id}`) ||
                        (s.preventDefault(),
                        this.parent?.isMultipleSelection ||
                          this.commitOrRemove());
                    }
                    commitOrRemove() {
                      this.isEmpty() ? this.remove() : this.commit();
                    }
                    commit() {
                      this.addToAnnotationStorage();
                    }
                    addToAnnotationStorage() {
                      this._uiManager.addToAnnotationStorage(this);
                    }
                    setAt(s, t, i, h) {
                      const [c, n] = this.parentDimensions;
                      (([i, h] = this.screenToPageTranslation(i, h)),
                        (this.x = (s + i) / c),
                        (this.y = (t + h) / n),
                        this.fixAndSetPosition());
                    }
                    #b([s, t], i, h) {
                      (([i, h] = this.screenToPageTranslation(i, h)),
                        (this.x += i / s),
                        (this.y += h / t),
                        this.fixAndSetPosition());
                    }
                    translate(s, t) {
                      this.#b(this.parentDimensions, s, t);
                    }
                    translateInPage(s, t) {
                      (this.#b(this.pageDimensions, s, t),
                        this.div.scrollIntoView({ block: "nearest" }));
                    }
                    drag(s, t) {
                      const [i, h] = this.parentDimensions;
                      if (
                        ((this.x += s / i),
                        (this.y += t / h),
                        this.parent &&
                          (this.x < 0 ||
                            this.x > 1 ||
                            this.y < 0 ||
                            this.y > 1))
                      ) {
                        const { x: l, y: w } = this.div.getBoundingClientRect();
                        this.parent.findNewParent(this, l, w) &&
                          ((this.x -= Math.floor(this.x)),
                          (this.y -= Math.floor(this.y)));
                      }
                      let { x: c, y: n } = this;
                      const [d, m] = this.#m();
                      ((c += d),
                        (n += m),
                        (this.div.style.left = `${(100 * c).toFixed(2)}%`),
                        (this.div.style.top = `${(100 * n).toFixed(2)}%`),
                        this.div.scrollIntoView({ block: "nearest" }));
                    }
                    #m() {
                      const [s, t] = this.parentDimensions,
                        { _borderLineWidth: i } = T,
                        h = i / s,
                        c = i / t;
                      switch (this.rotation) {
                        case 90:
                          return [-h, c];
                        case 180:
                          return [h, c];
                        case 270:
                          return [h, -c];
                        default:
                          return [-h, -c];
                      }
                    }
                    fixAndSetPosition() {
                      const [s, t] = this.pageDimensions;
                      let { x: i, y: h, width: c, height: n } = this;
                      switch (
                        ((c *= s), (n *= t), (i *= s), (h *= t), this.rotation)
                      ) {
                        case 0:
                          ((i = Math.max(0, Math.min(s - c, i))),
                            (h = Math.max(0, Math.min(t - n, h))));
                          break;
                        case 90:
                          ((i = Math.max(0, Math.min(s - n, i))),
                            (h = Math.min(t, Math.max(c, h))));
                          break;
                        case 180:
                          ((i = Math.min(s, Math.max(c, i))),
                            (h = Math.min(t, Math.max(n, h))));
                          break;
                        case 270:
                          ((i = Math.min(s, Math.max(n, i))),
                            (h = Math.max(0, Math.min(t - c, h))));
                          break;
                      }
                      ((this.x = i /= s), (this.y = h /= t));
                      const [d, m] = this.#m();
                      ((i += d), (h += m));
                      const { style: l } = this.div;
                      ((l.left = `${(100 * i).toFixed(2)}%`),
                        (l.top = `${(100 * h).toFixed(2)}%`),
                        this.moveInDOM());
                    }
                    static #g(s, t, i) {
                      switch (i) {
                        case 90:
                          return [t, -s];
                        case 180:
                          return [-s, -t];
                        case 270:
                          return [-t, s];
                        default:
                          return [s, t];
                      }
                    }
                    screenToPageTranslation(s, t) {
                      return T.#g(s, t, this.parentRotation);
                    }
                    pageTranslationToScreen(s, t) {
                      return T.#g(s, t, 360 - this.parentRotation);
                    }
                    #h(s) {
                      switch (s) {
                        case 90: {
                          const [t, i] = this.pageDimensions;
                          return [0, -t / i, i / t, 0];
                        }
                        case 180:
                          return [-1, 0, 0, -1];
                        case 270: {
                          const [t, i] = this.pageDimensions;
                          return [0, t / i, -i / t, 0];
                        }
                        default:
                          return [1, 0, 0, 1];
                      }
                    }
                    get parentScale() {
                      return this._uiManager.viewParameters.realScale;
                    }
                    get parentRotation() {
                      return (
                        (this._uiManager.viewParameters.rotation +
                          this.pageRotation) %
                        360
                      );
                    }
                    get parentDimensions() {
                      const {
                          parentScale: s,
                          pageDimensions: [t, i],
                        } = this,
                        h = t * s,
                        c = i * s;
                      return p.FeatureTest.isCSSRoundSupported
                        ? [Math.round(h), Math.round(c)]
                        : [h, c];
                    }
                    setDims(s, t) {
                      const [i, h] = this.parentDimensions;
                      ((this.div.style.width = `${((100 * s) / i).toFixed(2)}%`),
                        this.#a ||
                          (this.div.style.height = `${((100 * t) / h).toFixed(2)}%`),
                        this.#n?.classList.toggle(
                          "small",
                          s < T.SMALL_EDITOR_SIZE || t < T.SMALL_EDITOR_SIZE,
                        ));
                    }
                    fixDims() {
                      const { style: s } = this.div,
                        { height: t, width: i } = s,
                        h = i.endsWith("%"),
                        c = !this.#a && t.endsWith("%");
                      if (h && c) return;
                      const [n, d] = this.parentDimensions;
                      (h ||
                        (s.width = `${((100 * parseFloat(i)) / n).toFixed(2)}%`),
                        !this.#a &&
                          !c &&
                          (s.height = `${((100 * parseFloat(t)) / d).toFixed(2)}%`));
                    }
                    getInitialTranslation() {
                      return [0, 0];
                    }
                    #_() {
                      if (this.#r) return;
                      ((this.#r = document.createElement("div")),
                        this.#r.classList.add("resizers"));
                      const s = [
                        "topLeft",
                        "topRight",
                        "bottomRight",
                        "bottomLeft",
                      ];
                      this._willKeepAspectRatio ||
                        s.push(
                          "topMiddle",
                          "middleRight",
                          "bottomMiddle",
                          "middleLeft",
                        );
                      for (const t of s) {
                        const i = document.createElement("div");
                        (this.#r.append(i),
                          i.classList.add("resizer", t),
                          i.addEventListener(
                            "pointerdown",
                            this.#E.bind(this, t),
                          ),
                          i.addEventListener("contextmenu", k.noContextMenu));
                      }
                      this.div.prepend(this.#r);
                    }
                    #E(s, t) {
                      t.preventDefault();
                      const { isMac: i } = p.FeatureTest.platform;
                      if (t.button !== 0 || (t.ctrlKey && i)) return;
                      const h = this.#S.bind(this, s),
                        c = this._isDraggable;
                      this._isDraggable = !1;
                      const n = { passive: !0, capture: !0 };
                      window.addEventListener("pointermove", h, n);
                      const d = this.x,
                        m = this.y,
                        l = this.width,
                        w = this.height,
                        M = this.parent.div.style.cursor,
                        C = this.div.style.cursor;
                      this.div.style.cursor = this.parent.div.style.cursor =
                        window.getComputedStyle(t.target).cursor;
                      const g = () => {
                        ((this._isDraggable = c),
                          window.removeEventListener("pointerup", g),
                          window.removeEventListener("blur", g),
                          window.removeEventListener("pointermove", h, n),
                          (this.parent.div.style.cursor = M),
                          (this.div.style.cursor = C));
                        const E = this.x,
                          U = this.y,
                          W = this.width,
                          O = this.height;
                        (E === d && U === m && W === l && O === w) ||
                          this.addCommands({
                            cmd: () => {
                              ((this.width = W),
                                (this.height = O),
                                (this.x = E),
                                (this.y = U));
                              const [V, G] = this.parentDimensions;
                              (this.setDims(V * W, G * O),
                                this.fixAndSetPosition());
                            },
                            undo: () => {
                              ((this.width = l),
                                (this.height = w),
                                (this.x = d),
                                (this.y = m));
                              const [V, G] = this.parentDimensions;
                              (this.setDims(V * l, G * w),
                                this.fixAndSetPosition());
                            },
                            mustExec: !0,
                          });
                      };
                      (window.addEventListener("pointerup", g),
                        window.addEventListener("blur", g));
                    }
                    #S(s, t) {
                      const [i, h] = this.parentDimensions,
                        c = this.x,
                        n = this.y,
                        d = this.width,
                        m = this.height,
                        l = T.MIN_SIZE / i,
                        w = T.MIN_SIZE / h,
                        M = (R) => Math.round(R * 1e4) / 1e4,
                        C = this.#h(this.rotation),
                        g = (R, o) => [
                          C[0] * R + C[2] * o,
                          C[1] * R + C[3] * o,
                        ],
                        E = this.#h(360 - this.rotation),
                        U = (R, o) => [
                          E[0] * R + E[2] * o,
                          E[1] * R + E[3] * o,
                        ];
                      let W,
                        O,
                        V = !1,
                        G = !1;
                      switch (s) {
                        case "topLeft":
                          ((V = !0),
                            (W = (R, o) => [0, 0]),
                            (O = (R, o) => [R, o]));
                          break;
                        case "topMiddle":
                          ((W = (R, o) => [R / 2, 0]),
                            (O = (R, o) => [R / 2, o]));
                          break;
                        case "topRight":
                          ((V = !0),
                            (W = (R, o) => [R, 0]),
                            (O = (R, o) => [0, o]));
                          break;
                        case "middleRight":
                          ((G = !0),
                            (W = (R, o) => [R, o / 2]),
                            (O = (R, o) => [0, o / 2]));
                          break;
                        case "bottomRight":
                          ((V = !0),
                            (W = (R, o) => [R, o]),
                            (O = (R, o) => [0, 0]));
                          break;
                        case "bottomMiddle":
                          ((W = (R, o) => [R / 2, o]),
                            (O = (R, o) => [R / 2, 0]));
                          break;
                        case "bottomLeft":
                          ((V = !0),
                            (W = (R, o) => [0, o]),
                            (O = (R, o) => [R, 0]));
                          break;
                        case "middleLeft":
                          ((G = !0),
                            (W = (R, o) => [0, o / 2]),
                            (O = (R, o) => [R, o / 2]));
                          break;
                      }
                      const nt = W(d, m),
                        Z = O(d, m);
                      let tt = g(...Z);
                      const rt = M(c + tt[0]),
                        K = M(n + tt[1]);
                      let I = 1,
                        _ = 1,
                        [u, f] = this.screenToPageTranslation(
                          t.movementX,
                          t.movementY,
                        );
                      if ((([u, f] = U(u / i, f / h)), V)) {
                        const R = Math.hypot(d, m);
                        I = _ = Math.max(
                          Math.min(
                            Math.hypot(Z[0] - nt[0] - u, Z[1] - nt[1] - f) / R,
                            1 / d,
                            1 / m,
                          ),
                          l / d,
                          w / m,
                        );
                      } else
                        G
                          ? (I =
                              Math.max(
                                l,
                                Math.min(1, Math.abs(Z[0] - nt[0] - u)),
                              ) / d)
                          : (_ =
                              Math.max(
                                w,
                                Math.min(1, Math.abs(Z[1] - nt[1] - f)),
                              ) / m);
                      const v = M(d * I),
                        F = M(m * _);
                      tt = g(...O(v, F));
                      const L = rt - tt[0],
                        N = K - tt[1];
                      ((this.width = v),
                        (this.height = F),
                        (this.x = L),
                        (this.y = N),
                        this.setDims(i * v, h * F),
                        this.fixAndSetPosition());
                    }
                    async addAltTextButton() {
                      if (this.#n) return;
                      const s = (this.#n = document.createElement("button"));
                      s.className = "altText";
                      const t = await T._l10nPromise.get(
                        "editor_alt_text_button_label",
                      );
                      ((s.textContent = t),
                        s.setAttribute("aria-label", t),
                        (s.tabIndex = "0"),
                        s.addEventListener("contextmenu", k.noContextMenu),
                        s.addEventListener("pointerdown", (i) =>
                          i.stopPropagation(),
                        ),
                        s.addEventListener(
                          "click",
                          (i) => {
                            (i.preventDefault(),
                              this._uiManager.editAltText(this));
                          },
                          { capture: !0 },
                        ),
                        s.addEventListener("keydown", (i) => {
                          i.target === s &&
                            i.key === "Enter" &&
                            (i.preventDefault(),
                            this._uiManager.editAltText(this));
                        }),
                        this.#C(),
                        this.div.append(s),
                        T.SMALL_EDITOR_SIZE ||
                          (T.SMALL_EDITOR_SIZE = Math.min(
                            128,
                            Math.round(s.getBoundingClientRect().width * 1.4),
                          )));
                    }
                    async #C() {
                      const s = this.#n;
                      if (!s) return;
                      if (!this.#t && !this.#e) {
                        (s.classList.remove("done"), this.#i?.remove());
                        return;
                      }
                      T._l10nPromise
                        .get("editor_alt_text_edit_button_label")
                        .then((i) => {
                          s.setAttribute("aria-label", i);
                        });
                      let t = this.#i;
                      if (!t) {
                        ((this.#i = t = document.createElement("span")),
                          (t.className = "tooltip"),
                          t.setAttribute("role", "tooltip"));
                        const i = (t.id = `alt-text-tooltip-${this.id}`);
                        s.setAttribute("aria-describedby", i);
                        const h = 100;
                        (s.addEventListener("mouseenter", () => {
                          this.#o = setTimeout(() => {
                            ((this.#o = null),
                              this.#i.classList.add("show"),
                              this._uiManager._eventBus.dispatch(
                                "reporttelemetry",
                                {
                                  source: this,
                                  details: {
                                    type: "editing",
                                    subtype: this.editorType,
                                    data: { action: "alt_text_tooltip" },
                                  },
                                },
                              ));
                          }, h);
                        }),
                          s.addEventListener("mouseleave", () => {
                            (clearTimeout(this.#o),
                              (this.#o = null),
                              this.#i?.classList.remove("show"));
                          }));
                      }
                      (s.classList.add("done"),
                        (t.innerText = this.#e
                          ? await T._l10nPromise.get(
                              "editor_alt_text_decorative_tooltip",
                            )
                          : this.#t),
                        t.parentNode || s.append(t));
                    }
                    getClientDimensions() {
                      return this.div.getBoundingClientRect();
                    }
                    get altTextData() {
                      return { altText: this.#t, decorative: this.#e };
                    }
                    set altTextData({ altText: s, decorative: t }) {
                      (this.#t === s && this.#e === t) ||
                        ((this.#t = s), (this.#e = t), this.#C());
                    }
                    render() {
                      ((this.div = document.createElement("div")),
                        this.div.setAttribute(
                          "data-editor-rotation",
                          (360 - this.rotation) % 360,
                        ),
                        (this.div.className = this.name),
                        this.div.setAttribute("id", this.id),
                        this.div.setAttribute("tabIndex", 0),
                        this.setInForeground(),
                        this.div.addEventListener("focusin", this.#l),
                        this.div.addEventListener("focusout", this.#c));
                      const [s, t] = this.parentDimensions;
                      this.parentRotation % 180 !== 0 &&
                        ((this.div.style.maxWidth = `${((100 * t) / s).toFixed(2)}%`),
                        (this.div.style.maxHeight = `${((100 * s) / t).toFixed(2)}%`));
                      const [i, h] = this.getInitialTranslation();
                      return (
                        this.translate(i, h),
                        (0, a.bindEvents)(this, this.div, ["pointerdown"]),
                        this.div
                      );
                    }
                    pointerdown(s) {
                      const { isMac: t } = p.FeatureTest.platform;
                      if (s.button !== 0 || (s.ctrlKey && t)) {
                        s.preventDefault();
                        return;
                      }
                      ((this.#s = !0), this.#x(s));
                    }
                    #x(s) {
                      if (!this._isDraggable) return;
                      const t = this._uiManager.isSelected(this);
                      this._uiManager.setUpDragSession();
                      let i, h;
                      t &&
                        ((i = { passive: !0, capture: !0 }),
                        (h = (n) => {
                          const [d, m] = this.screenToPageTranslation(
                            n.movementX,
                            n.movementY,
                          );
                          this._uiManager.dragSelectedEditors(d, m);
                        }),
                        window.addEventListener("pointermove", h, i));
                      const c = () => {
                        if (
                          (window.removeEventListener("pointerup", c),
                          window.removeEventListener("blur", c),
                          t && window.removeEventListener("pointermove", h, i),
                          (this.#s = !1),
                          !this._uiManager.endDragSession())
                        ) {
                          const { isMac: n } = p.FeatureTest.platform;
                          (s.ctrlKey && !n) || s.shiftKey || (s.metaKey && n)
                            ? this.parent.toggleSelected(this)
                            : this.parent.setSelected(this);
                        }
                      };
                      (window.addEventListener("pointerup", c),
                        window.addEventListener("blur", c));
                    }
                    moveInDOM() {
                      this.parent?.moveEditorInDOM(this);
                    }
                    _setParentAndPosition(s, t, i) {
                      (s.changeParent(this),
                        (this.x = t),
                        (this.y = i),
                        this.fixAndSetPosition());
                    }
                    getRect(s, t) {
                      const i = this.parentScale,
                        [h, c] = this.pageDimensions,
                        [n, d] = this.pageTranslation,
                        m = s / i,
                        l = t / i,
                        w = this.x * h,
                        M = this.y * c,
                        C = this.width * h,
                        g = this.height * c;
                      switch (this.rotation) {
                        case 0:
                          return [
                            w + m + n,
                            c - M - l - g + d,
                            w + m + C + n,
                            c - M - l + d,
                          ];
                        case 90:
                          return [
                            w + l + n,
                            c - M + m + d,
                            w + l + g + n,
                            c - M + m + C + d,
                          ];
                        case 180:
                          return [
                            w - m - C + n,
                            c - M + l + d,
                            w - m + n,
                            c - M + l + g + d,
                          ];
                        case 270:
                          return [
                            w - l - g + n,
                            c - M - m - C + d,
                            w - l + n,
                            c - M - m + d,
                          ];
                        default:
                          throw new Error("Invalid rotation");
                      }
                    }
                    getRectInCurrentCoords(s, t) {
                      const [i, h, c, n] = s,
                        d = c - i,
                        m = n - h;
                      switch (this.rotation) {
                        case 0:
                          return [i, t - n, d, m];
                        case 90:
                          return [i, t - h, m, d];
                        case 180:
                          return [c, t - h, d, m];
                        case 270:
                          return [c, t - n, m, d];
                        default:
                          throw new Error("Invalid rotation");
                      }
                    }
                    onceAdded() {}
                    isEmpty() {
                      return !1;
                    }
                    enableEditMode() {
                      this.#d = !0;
                    }
                    disableEditMode() {
                      this.#d = !1;
                    }
                    isInEditMode() {
                      return this.#d;
                    }
                    shouldGetKeyboardEvents() {
                      return !1;
                    }
                    needsToBeRebuilt() {
                      return this.div && !this.isAttachedToDOM;
                    }
                    rebuild() {
                      (this.div?.addEventListener("focusin", this.#l),
                        this.div?.addEventListener("focusout", this.#c));
                    }
                    serialize(s = !1, t = null) {
                      (0, p.unreachable)("An editor must be serializable");
                    }
                    static deserialize(s, t, i) {
                      const h = new this.prototype.constructor({
                        parent: t,
                        id: t.getNextId(),
                        uiManager: i,
                      });
                      h.rotation = s.rotation;
                      const [c, n] = h.pageDimensions,
                        [d, m, l, w] = h.getRectInCurrentCoords(s.rect, n);
                      return (
                        (h.x = d / c),
                        (h.y = m / n),
                        (h.width = l / c),
                        (h.height = w / n),
                        h
                      );
                    }
                    remove() {
                      (this.div.removeEventListener("focusin", this.#l),
                        this.div.removeEventListener("focusout", this.#c),
                        this.isEmpty() || this.commit(),
                        this.parent
                          ? this.parent.remove(this)
                          : this._uiManager.removeEditor(this),
                        this.#n?.remove(),
                        (this.#n = null),
                        (this.#i = null));
                    }
                    get isResizable() {
                      return !1;
                    }
                    makeResizable() {
                      this.isResizable &&
                        (this.#_(), this.#r.classList.remove("hidden"));
                    }
                    select() {
                      (this.makeResizable(),
                        this.div?.classList.add("selectedEditor"));
                    }
                    unselect() {
                      (this.#r?.classList.add("hidden"),
                        this.div?.classList.remove("selectedEditor"),
                        this.div?.contains(document.activeElement) &&
                          this._uiManager.currentLayer.div.focus());
                    }
                    updateParams(s, t) {}
                    disableEditing() {
                      this.#n && (this.#n.hidden = !0);
                    }
                    enableEditing() {
                      this.#n && (this.#n.hidden = !1);
                    }
                    enterInEditMode() {}
                    get contentDiv() {
                      return this.div;
                    }
                    get isEditing() {
                      return this.#f;
                    }
                    set isEditing(s) {
                      ((this.#f = s),
                        this.parent &&
                          (s
                            ? (this.parent.setSelected(this),
                              this.parent.setActiveEditor(this))
                            : this.parent.setActiveEditor(null)));
                    }
                    setAspectRatio(s, t) {
                      this.#a = !0;
                      const i = s / t,
                        { style: h } = this.div;
                      ((h.aspectRatio = i), (h.height = "auto"));
                    }
                    static get MIN_SIZE() {
                      return 16;
                    }
                  }
                  e.AnnotationEditor = T;
                  class j extends T {
                    constructor(s) {
                      (super(s),
                        (this.annotationElementId = s.annotationElementId),
                        (this.deleted = !0));
                    }
                    serialize() {
                      return {
                        id: this.annotationElementId,
                        deleted: !0,
                        pageIndex: this.pageIndex,
                      };
                    }
                  }
                },
                (A, e, y) => {
                  (Object.defineProperty(e, "__esModule", { value: !0 }),
                    (e.KeyboardManager =
                      e.CommandManager =
                      e.ColorManager =
                      e.AnnotationEditorUIManager =
                        void 0),
                    (e.bindEvents = k),
                    (e.opacityToHex = T));
                  var a = y(1),
                    p = y(6);
                  function k(c, n, d) {
                    for (const m of d) n.addEventListener(m, c[m].bind(c));
                  }
                  function T(c) {
                    return Math.round(Math.min(255, Math.max(1, 255 * c)))
                      .toString(16)
                      .padStart(2, "0");
                  }
                  class j {
                    #t = 0;
                    getId() {
                      return `${a.AnnotationEditorPrefix}${this.#t++}`;
                    }
                  }
                  class D {
                    #t = (0, a.getUuid)();
                    #e = 0;
                    #n = null;
                    static get _isSVGFittingCanvas() {
                      const n =
                          'data:image/svg+xml;charset=UTF-8,<svg viewBox="0 0 1 1" width="1" height="1" xmlns="http://www.w3.org/2000/svg"><rect width="1" height="1" style="fill:red;"/></svg>',
                        m = new OffscreenCanvas(1, 3).getContext("2d"),
                        l = new Image();
                      l.src = n;
                      const w = l
                        .decode()
                        .then(
                          () => (
                            m.drawImage(l, 0, 0, 1, 1, 0, 0, 1, 3),
                            new Uint32Array(
                              m.getImageData(0, 0, 1, 1).data.buffer,
                            )[0] === 0
                          ),
                        );
                      return (0, a.shadow)(this, "_isSVGFittingCanvas", w);
                    }
                    async #i(n, d) {
                      this.#n ||= new Map();
                      let m = this.#n.get(n);
                      if (m === null) return null;
                      if (m?.bitmap) return ((m.refCounter += 1), m);
                      try {
                        m ||= {
                          bitmap: null,
                          id: `image_${this.#t}_${this.#e++}`,
                          refCounter: 0,
                          isSvg: !1,
                        };
                        let l;
                        if (typeof d == "string") {
                          m.url = d;
                          const w = await fetch(d);
                          if (!w.ok) throw new Error(w.statusText);
                          l = await w.blob();
                        } else l = m.file = d;
                        if (l.type === "image/svg+xml") {
                          const w = D._isSVGFittingCanvas,
                            M = new FileReader(),
                            C = new Image(),
                            g = new Promise((E, U) => {
                              ((C.onload = () => {
                                ((m.bitmap = C), (m.isSvg = !0), E());
                              }),
                                (M.onload = async () => {
                                  const W = (m.svgUrl = M.result);
                                  C.src = (await w)
                                    ? `${W}#svgView(preserveAspectRatio(none))`
                                    : W;
                                }),
                                (C.onerror = M.onerror = U));
                            });
                          (M.readAsDataURL(l), await g);
                        } else m.bitmap = await createImageBitmap(l);
                        m.refCounter = 1;
                      } catch (l) {
                        (console.error(l), (m = null));
                      }
                      return (this.#n.set(n, m), m && this.#n.set(m.id, m), m);
                    }
                    async getFromFile(n) {
                      const { lastModified: d, name: m, size: l, type: w } = n;
                      return this.#i(`${d}_${m}_${l}_${w}`, n);
                    }
                    async getFromUrl(n) {
                      return this.#i(n, n);
                    }
                    async getFromId(n) {
                      this.#n ||= new Map();
                      const d = this.#n.get(n);
                      return d
                        ? d.bitmap
                          ? ((d.refCounter += 1), d)
                          : d.file
                            ? this.getFromFile(d.file)
                            : this.getFromUrl(d.url)
                        : null;
                    }
                    getSvgUrl(n) {
                      const d = this.#n.get(n);
                      return d?.isSvg ? d.svgUrl : null;
                    }
                    deleteId(n) {
                      this.#n ||= new Map();
                      const d = this.#n.get(n);
                      d &&
                        ((d.refCounter -= 1),
                        d.refCounter === 0 && (d.bitmap = null));
                    }
                    isValidId(n) {
                      return n.startsWith(`image_${this.#t}_`);
                    }
                  }
                  class s {
                    #t = [];
                    #e = !1;
                    #n;
                    #i = -1;
                    constructor(n = 128) {
                      this.#n = n;
                    }
                    add({
                      cmd: n,
                      undo: d,
                      mustExec: m,
                      type: l = NaN,
                      overwriteIfSameType: w = !1,
                      keepUndo: M = !1,
                    }) {
                      if ((m && n(), this.#e)) return;
                      const C = { cmd: n, undo: d, type: l };
                      if (this.#i === -1) {
                        (this.#t.length > 0 && (this.#t.length = 0),
                          (this.#i = 0),
                          this.#t.push(C));
                        return;
                      }
                      if (w && this.#t[this.#i].type === l) {
                        (M && (C.undo = this.#t[this.#i].undo),
                          (this.#t[this.#i] = C));
                        return;
                      }
                      const g = this.#i + 1;
                      (g === this.#n
                        ? this.#t.splice(0, 1)
                        : ((this.#i = g),
                          g < this.#t.length && this.#t.splice(g)),
                        this.#t.push(C));
                    }
                    undo() {
                      this.#i !== -1 &&
                        ((this.#e = !0),
                        this.#t[this.#i].undo(),
                        (this.#e = !1),
                        (this.#i -= 1));
                    }
                    redo() {
                      this.#i < this.#t.length - 1 &&
                        ((this.#i += 1),
                        (this.#e = !0),
                        this.#t[this.#i].cmd(),
                        (this.#e = !1));
                    }
                    hasSomethingToUndo() {
                      return this.#i !== -1;
                    }
                    hasSomethingToRedo() {
                      return this.#i < this.#t.length - 1;
                    }
                    destroy() {
                      this.#t = null;
                    }
                  }
                  e.CommandManager = s;
                  class t {
                    constructor(n) {
                      ((this.buffer = []),
                        (this.callbacks = new Map()),
                        (this.allKeys = new Set()));
                      const { isMac: d } = a.FeatureTest.platform;
                      for (const [m, l, w = {}] of n)
                        for (const M of m) {
                          const C = M.startsWith("mac+");
                          d && C
                            ? (this.callbacks.set(M.slice(4), {
                                callback: l,
                                options: w,
                              }),
                              this.allKeys.add(M.split("+").at(-1)))
                            : !d &&
                              !C &&
                              (this.callbacks.set(M, {
                                callback: l,
                                options: w,
                              }),
                              this.allKeys.add(M.split("+").at(-1)));
                        }
                    }
                    #t(n) {
                      (n.altKey && this.buffer.push("alt"),
                        n.ctrlKey && this.buffer.push("ctrl"),
                        n.metaKey && this.buffer.push("meta"),
                        n.shiftKey && this.buffer.push("shift"),
                        this.buffer.push(n.key));
                      const d = this.buffer.join("+");
                      return ((this.buffer.length = 0), d);
                    }
                    exec(n, d) {
                      if (!this.allKeys.has(d.key)) return;
                      const m = this.callbacks.get(this.#t(d));
                      if (!m) return;
                      const {
                        callback: l,
                        options: {
                          bubbles: w = !1,
                          args: M = [],
                          checker: C = null,
                        },
                      } = m;
                      (C && !C(n, d)) ||
                        (l.bind(n, ...M)(),
                        w || (d.stopPropagation(), d.preventDefault()));
                    }
                  }
                  e.KeyboardManager = t;
                  class i {
                    static _colorsMapping = new Map([
                      ["CanvasText", [0, 0, 0]],
                      ["Canvas", [255, 255, 255]],
                    ]);
                    get _colors() {
                      const n = new Map([
                        ["CanvasText", null],
                        ["Canvas", null],
                      ]);
                      return (
                        (0, p.getColorValues)(n),
                        (0, a.shadow)(this, "_colors", n)
                      );
                    }
                    convert(n) {
                      const d = (0, p.getRGB)(n);
                      if (!window.matchMedia("(forced-colors: active)").matches)
                        return d;
                      for (const [m, l] of this._colors)
                        if (l.every((w, M) => w === d[M]))
                          return i._colorsMapping.get(m);
                      return d;
                    }
                    getHexCode(n) {
                      const d = this._colors.get(n);
                      return d ? a.Util.makeHexColor(...d) : n;
                    }
                  }
                  e.ColorManager = i;
                  class h {
                    #t = null;
                    #e = new Map();
                    #n = new Map();
                    #i = null;
                    #o = null;
                    #a = new s();
                    #r = 0;
                    #l = new Set();
                    #c = null;
                    #s = null;
                    #f = new Set();
                    #d = null;
                    #u = new j();
                    #p = !1;
                    #b = !1;
                    #m = null;
                    #g = a.AnnotationEditorType.NONE;
                    #h = new Set();
                    #_ = null;
                    #E = this.blur.bind(this);
                    #S = this.focus.bind(this);
                    #C = this.copy.bind(this);
                    #x = this.cut.bind(this);
                    #L = this.paste.bind(this);
                    #I = this.keydown.bind(this);
                    #O = this.onEditingAction.bind(this);
                    #A = this.onPageChanging.bind(this);
                    #D = this.onScaleChanging.bind(this);
                    #R = this.onRotationChanging.bind(this);
                    #k = {
                      isEditing: !1,
                      isEmpty: !0,
                      hasSomethingToUndo: !1,
                      hasSomethingToRedo: !1,
                      hasSelectedEditor: !1,
                    };
                    #y = [0, 0];
                    #P = null;
                    #w = null;
                    #N = null;
                    static TRANSLATE_SMALL = 1;
                    static TRANSLATE_BIG = 10;
                    static get _keyboardManager() {
                      const n = h.prototype,
                        d = (w) => {
                          const { activeElement: M } = document;
                          return (
                            M && w.#w.contains(M) && w.hasSomethingToControl()
                          );
                        },
                        m = this.TRANSLATE_SMALL,
                        l = this.TRANSLATE_BIG;
                      return (0, a.shadow)(
                        this,
                        "_keyboardManager",
                        new t([
                          [["ctrl+a", "mac+meta+a"], n.selectAll],
                          [["ctrl+z", "mac+meta+z"], n.undo],
                          [
                            [
                              "ctrl+y",
                              "ctrl+shift+z",
                              "mac+meta+shift+z",
                              "ctrl+shift+Z",
                              "mac+meta+shift+Z",
                            ],
                            n.redo,
                          ],
                          [
                            [
                              "Backspace",
                              "alt+Backspace",
                              "ctrl+Backspace",
                              "shift+Backspace",
                              "mac+Backspace",
                              "mac+alt+Backspace",
                              "mac+ctrl+Backspace",
                              "Delete",
                              "ctrl+Delete",
                              "shift+Delete",
                              "mac+Delete",
                            ],
                            n.delete,
                          ],
                          [["Escape", "mac+Escape"], n.unselectAll],
                          [
                            ["ArrowLeft", "mac+ArrowLeft"],
                            n.translateSelectedEditors,
                            { args: [-m, 0], checker: d },
                          ],
                          [
                            ["ctrl+ArrowLeft", "mac+shift+ArrowLeft"],
                            n.translateSelectedEditors,
                            { args: [-l, 0], checker: d },
                          ],
                          [
                            ["ArrowRight", "mac+ArrowRight"],
                            n.translateSelectedEditors,
                            { args: [m, 0], checker: d },
                          ],
                          [
                            ["ctrl+ArrowRight", "mac+shift+ArrowRight"],
                            n.translateSelectedEditors,
                            { args: [l, 0], checker: d },
                          ],
                          [
                            ["ArrowUp", "mac+ArrowUp"],
                            n.translateSelectedEditors,
                            { args: [0, -m], checker: d },
                          ],
                          [
                            ["ctrl+ArrowUp", "mac+shift+ArrowUp"],
                            n.translateSelectedEditors,
                            { args: [0, -l], checker: d },
                          ],
                          [
                            ["ArrowDown", "mac+ArrowDown"],
                            n.translateSelectedEditors,
                            { args: [0, m], checker: d },
                          ],
                          [
                            ["ctrl+ArrowDown", "mac+shift+ArrowDown"],
                            n.translateSelectedEditors,
                            { args: [0, l], checker: d },
                          ],
                        ]),
                      );
                    }
                    constructor(n, d, m, l, w, M) {
                      ((this.#w = n),
                        (this.#N = d),
                        (this.#i = m),
                        (this._eventBus = l),
                        this._eventBus._on("editingaction", this.#O),
                        this._eventBus._on("pagechanging", this.#A),
                        this._eventBus._on("scalechanging", this.#D),
                        this._eventBus._on("rotationchanging", this.#R),
                        (this.#o = w.annotationStorage),
                        (this.#d = w.filterFactory),
                        (this.#_ = M),
                        (this.viewParameters = {
                          realScale: p.PixelsPerInch.PDF_TO_CSS_UNITS,
                          rotation: 0,
                        }));
                    }
                    destroy() {
                      (this.#M(),
                        this.#B(),
                        this._eventBus._off("editingaction", this.#O),
                        this._eventBus._off("pagechanging", this.#A),
                        this._eventBus._off("scalechanging", this.#D),
                        this._eventBus._off("rotationchanging", this.#R));
                      for (const n of this.#n.values()) n.destroy();
                      (this.#n.clear(),
                        this.#e.clear(),
                        this.#f.clear(),
                        (this.#t = null),
                        this.#h.clear(),
                        this.#a.destroy(),
                        this.#i.destroy());
                    }
                    get hcmFilter() {
                      return (0, a.shadow)(
                        this,
                        "hcmFilter",
                        this.#_
                          ? this.#d.addHCMFilter(
                              this.#_.foreground,
                              this.#_.background,
                            )
                          : "none",
                      );
                    }
                    get direction() {
                      return (0, a.shadow)(
                        this,
                        "direction",
                        getComputedStyle(this.#w).direction,
                      );
                    }
                    editAltText(n) {
                      this.#i?.editAltText(this, n);
                    }
                    onPageChanging({ pageNumber: n }) {
                      this.#r = n - 1;
                    }
                    focusMainContainer() {
                      this.#w.focus();
                    }
                    findParent(n, d) {
                      for (const m of this.#n.values()) {
                        const {
                          x: l,
                          y: w,
                          width: M,
                          height: C,
                        } = m.div.getBoundingClientRect();
                        if (n >= l && n <= l + M && d >= w && d <= w + C)
                          return m;
                      }
                      return null;
                    }
                    disableUserSelect(n = !1) {
                      this.#N.classList.toggle("noUserSelect", n);
                    }
                    addShouldRescale(n) {
                      this.#f.add(n);
                    }
                    removeShouldRescale(n) {
                      this.#f.delete(n);
                    }
                    onScaleChanging({ scale: n }) {
                      (this.commitOrRemove(),
                        (this.viewParameters.realScale =
                          n * p.PixelsPerInch.PDF_TO_CSS_UNITS));
                      for (const d of this.#f) d.onScaleChanging();
                    }
                    onRotationChanging({ pagesRotation: n }) {
                      (this.commitOrRemove(),
                        (this.viewParameters.rotation = n));
                    }
                    addToAnnotationStorage(n) {
                      !n.isEmpty() &&
                        this.#o &&
                        !this.#o.has(n.id) &&
                        this.#o.setValue(n.id, n);
                    }
                    #j() {
                      (window.addEventListener("focus", this.#S),
                        window.addEventListener("blur", this.#E));
                    }
                    #B() {
                      (window.removeEventListener("focus", this.#S),
                        window.removeEventListener("blur", this.#E));
                    }
                    blur() {
                      if (!this.hasSelection) return;
                      const { activeElement: n } = document;
                      for (const d of this.#h)
                        if (d.div.contains(n)) {
                          ((this.#m = [d, n]), (d._focusEventsAllowed = !1));
                          break;
                        }
                    }
                    focus() {
                      if (!this.#m) return;
                      const [n, d] = this.#m;
                      ((this.#m = null),
                        d.addEventListener(
                          "focusin",
                          () => {
                            n._focusEventsAllowed = !0;
                          },
                          { once: !0 },
                        ),
                        d.focus());
                    }
                    #U() {
                      window.addEventListener("keydown", this.#I, {
                        capture: !0,
                      });
                    }
                    #M() {
                      window.removeEventListener("keydown", this.#I, {
                        capture: !0,
                      });
                    }
                    #F() {
                      (document.addEventListener("copy", this.#C),
                        document.addEventListener("cut", this.#x),
                        document.addEventListener("paste", this.#L));
                    }
                    #T() {
                      (document.removeEventListener("copy", this.#C),
                        document.removeEventListener("cut", this.#x),
                        document.removeEventListener("paste", this.#L));
                    }
                    addEditListeners() {
                      (this.#U(), this.#F());
                    }
                    removeEditListeners() {
                      (this.#M(), this.#T());
                    }
                    copy(n) {
                      if (
                        (n.preventDefault(),
                        this.#t?.commitOrRemove(),
                        !this.hasSelection)
                      )
                        return;
                      const d = [];
                      for (const m of this.#h) {
                        const l = m.serialize(!0);
                        l && d.push(l);
                      }
                      d.length !== 0 &&
                        n.clipboardData.setData(
                          "application/pdfjs",
                          JSON.stringify(d),
                        );
                    }
                    cut(n) {
                      (this.copy(n), this.delete());
                    }
                    paste(n) {
                      n.preventDefault();
                      const { clipboardData: d } = n;
                      for (const w of d.items)
                        for (const M of this.#s)
                          if (M.isHandlingMimeForPasting(w.type)) {
                            M.paste(w, this.currentLayer);
                            return;
                          }
                      let m = d.getData("application/pdfjs");
                      if (!m) return;
                      try {
                        m = JSON.parse(m);
                      } catch (w) {
                        (0, a.warn)(`paste: "${w.message}".`);
                        return;
                      }
                      if (!Array.isArray(m)) return;
                      this.unselectAll();
                      const l = this.currentLayer;
                      try {
                        const w = [];
                        for (const g of m) {
                          const E = l.deserialize(g);
                          if (!E) return;
                          w.push(E);
                        }
                        const M = () => {
                            for (const g of w) this.#G(g);
                            this.#V(w);
                          },
                          C = () => {
                            for (const g of w) g.remove();
                          };
                        this.addCommands({ cmd: M, undo: C, mustExec: !0 });
                      } catch (w) {
                        (0, a.warn)(`paste: "${w.message}".`);
                      }
                    }
                    keydown(n) {
                      this.getActive()?.shouldGetKeyboardEvents() ||
                        h._keyboardManager.exec(this, n);
                    }
                    onEditingAction(n) {
                      ["undo", "redo", "delete", "selectAll"].includes(
                        n.name,
                      ) && this[n.name]();
                    }
                    #v(n) {
                      Object.entries(n).some(([m, l]) => this.#k[m] !== l) &&
                        this._eventBus.dispatch(
                          "annotationeditorstateschanged",
                          { source: this, details: Object.assign(this.#k, n) },
                        );
                    }
                    #W(n) {
                      this._eventBus.dispatch("annotationeditorparamschanged", {
                        source: this,
                        details: n,
                      });
                    }
                    setEditingState(n) {
                      n
                        ? (this.#j(),
                          this.#U(),
                          this.#F(),
                          this.#v({
                            isEditing: this.#g !== a.AnnotationEditorType.NONE,
                            isEmpty: this.#H(),
                            hasSomethingToUndo: this.#a.hasSomethingToUndo(),
                            hasSomethingToRedo: this.#a.hasSomethingToRedo(),
                            hasSelectedEditor: !1,
                          }))
                        : (this.#B(),
                          this.#M(),
                          this.#T(),
                          this.#v({ isEditing: !1 }),
                          this.disableUserSelect(!1));
                    }
                    registerEditorTypes(n) {
                      if (!this.#s) {
                        this.#s = n;
                        for (const d of this.#s)
                          this.#W(d.defaultPropertiesToUpdate);
                      }
                    }
                    getId() {
                      return this.#u.getId();
                    }
                    get currentLayer() {
                      return this.#n.get(this.#r);
                    }
                    getLayer(n) {
                      return this.#n.get(n);
                    }
                    get currentPageIndex() {
                      return this.#r;
                    }
                    addLayer(n) {
                      (this.#n.set(n.pageIndex, n),
                        this.#p ? n.enable() : n.disable());
                    }
                    removeLayer(n) {
                      this.#n.delete(n.pageIndex);
                    }
                    updateMode(n, d = null) {
                      if (this.#g !== n) {
                        if (
                          ((this.#g = n), n === a.AnnotationEditorType.NONE)
                        ) {
                          (this.setEditingState(!1), this.#z());
                          return;
                        }
                        (this.setEditingState(!0),
                          this.#$(),
                          this.unselectAll());
                        for (const m of this.#n.values()) m.updateMode(n);
                        if (d) {
                          for (const m of this.#e.values())
                            if (m.annotationElementId === d) {
                              (this.setSelected(m), m.enterInEditMode());
                              break;
                            }
                        }
                      }
                    }
                    updateToolbar(n) {
                      n !== this.#g &&
                        this._eventBus.dispatch("switchannotationeditormode", {
                          source: this,
                          mode: n,
                        });
                    }
                    updateParams(n, d) {
                      if (this.#s) {
                        if (n === a.AnnotationEditorParamsType.CREATE) {
                          this.currentLayer.addNewEditor(n);
                          return;
                        }
                        for (const m of this.#h) m.updateParams(n, d);
                        for (const m of this.#s) m.updateDefaultParams(n, d);
                      }
                    }
                    enableWaiting(n = !1) {
                      if (this.#b !== n) {
                        this.#b = n;
                        for (const d of this.#n.values())
                          (n ? d.disableClick() : d.enableClick(),
                            d.div.classList.toggle("waiting", n));
                      }
                    }
                    #$() {
                      if (!this.#p) {
                        this.#p = !0;
                        for (const n of this.#n.values()) n.enable();
                      }
                    }
                    #z() {
                      if ((this.unselectAll(), this.#p)) {
                        this.#p = !1;
                        for (const n of this.#n.values()) n.disable();
                      }
                    }
                    getEditors(n) {
                      const d = [];
                      for (const m of this.#e.values())
                        m.pageIndex === n && d.push(m);
                      return d;
                    }
                    getEditor(n) {
                      return this.#e.get(n);
                    }
                    addEditor(n) {
                      this.#e.set(n.id, n);
                    }
                    removeEditor(n) {
                      (this.#e.delete(n.id),
                        this.unselect(n),
                        (!n.annotationElementId ||
                          !this.#l.has(n.annotationElementId)) &&
                          this.#o?.remove(n.id));
                    }
                    addDeletedAnnotationElement(n) {
                      (this.#l.add(n.annotationElementId), (n.deleted = !0));
                    }
                    isDeletedAnnotationElement(n) {
                      return this.#l.has(n);
                    }
                    removeDeletedAnnotationElement(n) {
                      (this.#l.delete(n.annotationElementId), (n.deleted = !1));
                    }
                    #G(n) {
                      const d = this.#n.get(n.pageIndex);
                      d ? d.addOrRebuild(n) : this.addEditor(n);
                    }
                    setActiveEditor(n) {
                      this.#t !== n &&
                        ((this.#t = n), n && this.#W(n.propertiesToUpdate));
                    }
                    toggleSelected(n) {
                      if (this.#h.has(n)) {
                        (this.#h.delete(n),
                          n.unselect(),
                          this.#v({ hasSelectedEditor: this.hasSelection }));
                        return;
                      }
                      (this.#h.add(n),
                        n.select(),
                        this.#W(n.propertiesToUpdate),
                        this.#v({ hasSelectedEditor: !0 }));
                    }
                    setSelected(n) {
                      for (const d of this.#h) d !== n && d.unselect();
                      (this.#h.clear(),
                        this.#h.add(n),
                        n.select(),
                        this.#W(n.propertiesToUpdate),
                        this.#v({ hasSelectedEditor: !0 }));
                    }
                    isSelected(n) {
                      return this.#h.has(n);
                    }
                    unselect(n) {
                      (n.unselect(),
                        this.#h.delete(n),
                        this.#v({ hasSelectedEditor: this.hasSelection }));
                    }
                    get hasSelection() {
                      return this.#h.size !== 0;
                    }
                    undo() {
                      (this.#a.undo(),
                        this.#v({
                          hasSomethingToUndo: this.#a.hasSomethingToUndo(),
                          hasSomethingToRedo: !0,
                          isEmpty: this.#H(),
                        }));
                    }
                    redo() {
                      (this.#a.redo(),
                        this.#v({
                          hasSomethingToUndo: !0,
                          hasSomethingToRedo: this.#a.hasSomethingToRedo(),
                          isEmpty: this.#H(),
                        }));
                    }
                    addCommands(n) {
                      (this.#a.add(n),
                        this.#v({
                          hasSomethingToUndo: !0,
                          hasSomethingToRedo: !1,
                          isEmpty: this.#H(),
                        }));
                    }
                    #H() {
                      if (this.#e.size === 0) return !0;
                      if (this.#e.size === 1)
                        for (const n of this.#e.values()) return n.isEmpty();
                      return !1;
                    }
                    delete() {
                      if ((this.commitOrRemove(), !this.hasSelection)) return;
                      const n = [...this.#h],
                        d = () => {
                          for (const l of n) l.remove();
                        },
                        m = () => {
                          for (const l of n) this.#G(l);
                        };
                      this.addCommands({ cmd: d, undo: m, mustExec: !0 });
                    }
                    commitOrRemove() {
                      this.#t?.commitOrRemove();
                    }
                    hasSomethingToControl() {
                      return this.#t || this.hasSelection;
                    }
                    #V(n) {
                      this.#h.clear();
                      for (const d of n)
                        d.isEmpty() || (this.#h.add(d), d.select());
                      this.#v({ hasSelectedEditor: !0 });
                    }
                    selectAll() {
                      for (const n of this.#h) n.commit();
                      this.#V(this.#e.values());
                    }
                    unselectAll() {
                      if (this.#t) {
                        this.#t.commitOrRemove();
                        return;
                      }
                      if (this.hasSelection) {
                        for (const n of this.#h) n.unselect();
                        (this.#h.clear(), this.#v({ hasSelectedEditor: !1 }));
                      }
                    }
                    translateSelectedEditors(n, d, m = !1) {
                      if ((m || this.commitOrRemove(), !this.hasSelection))
                        return;
                      ((this.#y[0] += n), (this.#y[1] += d));
                      const [l, w] = this.#y,
                        M = [...this.#h],
                        C = 1e3;
                      (this.#P && clearTimeout(this.#P),
                        (this.#P = setTimeout(() => {
                          ((this.#P = null),
                            (this.#y[0] = this.#y[1] = 0),
                            this.addCommands({
                              cmd: () => {
                                for (const g of M)
                                  this.#e.has(g.id) && g.translateInPage(l, w);
                              },
                              undo: () => {
                                for (const g of M)
                                  this.#e.has(g.id) &&
                                    g.translateInPage(-l, -w);
                              },
                              mustExec: !1,
                            }));
                        }, C)));
                      for (const g of M) g.translateInPage(n, d);
                    }
                    setUpDragSession() {
                      if (this.hasSelection) {
                        (this.disableUserSelect(!0), (this.#c = new Map()));
                        for (const n of this.#h)
                          this.#c.set(n, {
                            savedX: n.x,
                            savedY: n.y,
                            savedPageIndex: n.pageIndex,
                            newX: 0,
                            newY: 0,
                            newPageIndex: -1,
                          });
                      }
                    }
                    endDragSession() {
                      if (!this.#c) return !1;
                      this.disableUserSelect(!1);
                      const n = this.#c;
                      this.#c = null;
                      let d = !1;
                      for (const [{ x: l, y: w, pageIndex: M }, C] of n)
                        ((C.newX = l),
                          (C.newY = w),
                          (C.newPageIndex = M),
                          (d ||=
                            l !== C.savedX ||
                            w !== C.savedY ||
                            M !== C.savedPageIndex));
                      if (!d) return !1;
                      const m = (l, w, M, C) => {
                        if (this.#e.has(l.id)) {
                          const g = this.#n.get(C);
                          g
                            ? l._setParentAndPosition(g, w, M)
                            : ((l.pageIndex = C), (l.x = w), (l.y = M));
                        }
                      };
                      return (
                        this.addCommands({
                          cmd: () => {
                            for (const [
                              l,
                              { newX: w, newY: M, newPageIndex: C },
                            ] of n)
                              m(l, w, M, C);
                          },
                          undo: () => {
                            for (const [
                              l,
                              { savedX: w, savedY: M, savedPageIndex: C },
                            ] of n)
                              m(l, w, M, C);
                          },
                          mustExec: !0,
                        }),
                        !0
                      );
                    }
                    dragSelectedEditors(n, d) {
                      if (this.#c) for (const m of this.#c.keys()) m.drag(n, d);
                    }
                    rebuild(n) {
                      if (n.parent === null) {
                        const d = this.getLayer(n.pageIndex);
                        d
                          ? (d.changeParent(n), d.addOrRebuild(n))
                          : (this.addEditor(n),
                            this.addToAnnotationStorage(n),
                            n.rebuild());
                      } else n.parent.addOrRebuild(n);
                    }
                    isActive(n) {
                      return this.#t === n;
                    }
                    getActive() {
                      return this.#t;
                    }
                    getMode() {
                      return this.#g;
                    }
                    get imageManager() {
                      return (0, a.shadow)(this, "imageManager", new D());
                    }
                  }
                  e.AnnotationEditorUIManager = h;
                },
                (A, e, y) => {
                  (Object.defineProperty(e, "__esModule", { value: !0 }),
                    (e.StatTimer =
                      e.RenderingCancelledException =
                      e.PixelsPerInch =
                      e.PageViewport =
                      e.PDFDateString =
                      e.DOMStandardFontDataFactory =
                      e.DOMSVGFactory =
                      e.DOMFilterFactory =
                      e.DOMCanvasFactory =
                      e.DOMCMapReaderFactory =
                        void 0),
                    (e.deprecated = U),
                    (e.getColorValues = nt),
                    (e.getCurrentTransform = Z),
                    (e.getCurrentTransformInverse = tt),
                    (e.getFilenameFromUrl = l),
                    (e.getPdfFilenameFromUrl = w),
                    (e.getRGB = G),
                    (e.getXfaPageViewport = V),
                    (e.isDataScheme = d),
                    (e.isPdfFile = m),
                    (e.isValidFetchUrl = C),
                    (e.loadScript = E),
                    (e.noContextMenu = g),
                    (e.setLayerDimensions = rt));
                  var a = y(7),
                    p = y(1);
                  const k = "http://www.w3.org/2000/svg";
                  class T {
                    static CSS = 96;
                    static PDF = 72;
                    static PDF_TO_CSS_UNITS = this.CSS / this.PDF;
                  }
                  e.PixelsPerInch = T;
                  class j extends a.BaseFilterFactory {
                    #t;
                    #e;
                    #n;
                    #i;
                    #o;
                    #a;
                    #r;
                    #l;
                    #c;
                    #s;
                    #f = 0;
                    constructor({
                      docId: I,
                      ownerDocument: _ = globalThis.document,
                    } = {}) {
                      (super(), (this.#n = I), (this.#i = _));
                    }
                    get #d() {
                      return (this.#t ||= new Map());
                    }
                    get #u() {
                      if (!this.#e) {
                        const I = this.#i.createElement("div"),
                          { style: _ } = I;
                        ((_.visibility = "hidden"),
                          (_.contain = "strict"),
                          (_.width = _.height = 0),
                          (_.position = "absolute"),
                          (_.top = _.left = 0),
                          (_.zIndex = -1));
                        const u = this.#i.createElementNS(k, "svg");
                        (u.setAttribute("width", 0),
                          u.setAttribute("height", 0),
                          (this.#e = this.#i.createElementNS(k, "defs")),
                          I.append(u),
                          u.append(this.#e),
                          this.#i.body.append(I));
                      }
                      return this.#e;
                    }
                    addFilter(I) {
                      if (!I) return "none";
                      let _ = this.#d.get(I);
                      if (_) return _;
                      let u, f, v, F;
                      if (I.length === 1) {
                        const o = I[0],
                          b = new Array(256);
                        for (let S = 0; S < 256; S++) b[S] = o[S] / 255;
                        F = u = f = v = b.join(",");
                      } else {
                        const [o, b, S] = I,
                          x = new Array(256),
                          P = new Array(256),
                          B = new Array(256);
                        for (let H = 0; H < 256; H++)
                          ((x[H] = o[H] / 255),
                            (P[H] = b[H] / 255),
                            (B[H] = S[H] / 255));
                        ((u = x.join(",")),
                          (f = P.join(",")),
                          (v = B.join(",")),
                          (F = `${u}${f}${v}`));
                      }
                      if (((_ = this.#d.get(F)), _))
                        return (this.#d.set(I, _), _);
                      const L = `g_${this.#n}_transfer_map_${this.#f++}`,
                        N = `url(#${L})`;
                      (this.#d.set(I, N), this.#d.set(F, N));
                      const R = this.#b(L);
                      return (this.#g(u, f, v, R), N);
                    }
                    addHCMFilter(I, _) {
                      const u = `${I}-${_}`;
                      if (this.#a === u) return this.#r;
                      if (
                        ((this.#a = u),
                        (this.#r = "none"),
                        this.#o?.remove(),
                        !I || !_)
                      )
                        return this.#r;
                      const f = this.#h(I);
                      I = p.Util.makeHexColor(...f);
                      const v = this.#h(_);
                      if (
                        ((_ = p.Util.makeHexColor(...v)),
                        (this.#u.style.color = ""),
                        (I === "#000000" && _ === "#ffffff") || I === _)
                      )
                        return this.#r;
                      const F = new Array(256);
                      for (let b = 0; b <= 255; b++) {
                        const S = b / 255;
                        F[b] =
                          S <= 0.03928
                            ? S / 12.92
                            : ((S + 0.055) / 1.055) ** 2.4;
                      }
                      const L = F.join(","),
                        N = `g_${this.#n}_hcm_filter`,
                        R = (this.#l = this.#b(N));
                      (this.#g(L, L, L, R), this.#p(R));
                      const o = (b, S) => {
                        const x = f[b] / 255,
                          P = v[b] / 255,
                          B = new Array(S + 1);
                        for (let H = 0; H <= S; H++)
                          B[H] = x + (H / S) * (P - x);
                        return B.join(",");
                      };
                      return (
                        this.#g(o(0, 5), o(1, 5), o(2, 5), R),
                        (this.#r = `url(#${N})`),
                        this.#r
                      );
                    }
                    addHighlightHCMFilter(I, _, u, f) {
                      const v = `${I}-${_}-${u}-${f}`;
                      if (this.#c === v) return this.#s;
                      if (
                        ((this.#c = v),
                        (this.#s = "none"),
                        this.#l?.remove(),
                        !I || !_)
                      )
                        return this.#s;
                      const [F, L] = [I, _].map(this.#h.bind(this));
                      let N = Math.round(
                          0.2126 * F[0] + 0.7152 * F[1] + 0.0722 * F[2],
                        ),
                        R = Math.round(
                          0.2126 * L[0] + 0.7152 * L[1] + 0.0722 * L[2],
                        ),
                        [o, b] = [u, f].map(this.#h.bind(this));
                      (R < N && ([N, R, o, b] = [R, N, b, o]),
                        (this.#u.style.color = ""));
                      const S = (B, H, z) => {
                          const st = new Array(256),
                            Y = (R - N) / z,
                            X = B / 255,
                            J = (H - B) / (255 * z);
                          let Q = 0;
                          for (let et = 0; et <= z; et++) {
                            const at = Math.round(N + et * Y),
                              lt = X + et * J;
                            for (let ct = Q; ct <= at; ct++) st[ct] = lt;
                            Q = at + 1;
                          }
                          for (let et = Q; et < 256; et++) st[et] = st[Q - 1];
                          return st.join(",");
                        },
                        x = `g_${this.#n}_hcm_highlight_filter`,
                        P = (this.#l = this.#b(x));
                      return (
                        this.#p(P),
                        this.#g(
                          S(o[0], b[0], 5),
                          S(o[1], b[1], 5),
                          S(o[2], b[2], 5),
                          P,
                        ),
                        (this.#s = `url(#${x})`),
                        this.#s
                      );
                    }
                    destroy(I = !1) {
                      (I && (this.#r || this.#s)) ||
                        (this.#e &&
                          (this.#e.parentNode.parentNode.remove(),
                          (this.#e = null)),
                        this.#t && (this.#t.clear(), (this.#t = null)),
                        (this.#f = 0));
                    }
                    #p(I) {
                      const _ = this.#i.createElementNS(k, "feColorMatrix");
                      (_.setAttribute("type", "matrix"),
                        _.setAttribute(
                          "values",
                          "0.2126 0.7152 0.0722 0 0 0.2126 0.7152 0.0722 0 0 0.2126 0.7152 0.0722 0 0 0 0 0 1 0",
                        ),
                        I.append(_));
                    }
                    #b(I) {
                      const _ = this.#i.createElementNS(k, "filter");
                      return (
                        _.setAttribute("color-interpolation-filters", "sRGB"),
                        _.setAttribute("id", I),
                        this.#u.append(_),
                        _
                      );
                    }
                    #m(I, _, u) {
                      const f = this.#i.createElementNS(k, _);
                      (f.setAttribute("type", "discrete"),
                        f.setAttribute("tableValues", u),
                        I.append(f));
                    }
                    #g(I, _, u, f) {
                      const v = this.#i.createElementNS(
                        k,
                        "feComponentTransfer",
                      );
                      (f.append(v),
                        this.#m(v, "feFuncR", I),
                        this.#m(v, "feFuncG", _),
                        this.#m(v, "feFuncB", u));
                    }
                    #h(I) {
                      return (
                        (this.#u.style.color = I),
                        G(getComputedStyle(this.#u).getPropertyValue("color"))
                      );
                    }
                  }
                  e.DOMFilterFactory = j;
                  class D extends a.BaseCanvasFactory {
                    constructor({
                      ownerDocument: I = globalThis.document,
                    } = {}) {
                      (super(), (this._document = I));
                    }
                    _createCanvas(I, _) {
                      const u = this._document.createElement("canvas");
                      return ((u.width = I), (u.height = _), u);
                    }
                  }
                  e.DOMCanvasFactory = D;
                  async function s(K, I = !1) {
                    if (C(K, document.baseURI)) {
                      const _ = await fetch(K);
                      if (!_.ok) throw new Error(_.statusText);
                      return I
                        ? new Uint8Array(await _.arrayBuffer())
                        : (0, p.stringToBytes)(await _.text());
                    }
                    return new Promise((_, u) => {
                      const f = new XMLHttpRequest();
                      (f.open("GET", K, !0),
                        I && (f.responseType = "arraybuffer"),
                        (f.onreadystatechange = () => {
                          if (f.readyState === XMLHttpRequest.DONE) {
                            if (f.status === 200 || f.status === 0) {
                              let v;
                              if (
                                (I && f.response
                                  ? (v = new Uint8Array(f.response))
                                  : !I &&
                                    f.responseText &&
                                    (v = (0, p.stringToBytes)(f.responseText)),
                                v)
                              ) {
                                _(v);
                                return;
                              }
                            }
                            u(new Error(f.statusText));
                          }
                        }),
                        f.send(null));
                    });
                  }
                  class t extends a.BaseCMapReaderFactory {
                    _fetchData(I, _) {
                      return s(I, this.isCompressed).then((u) => ({
                        cMapData: u,
                        compressionType: _,
                      }));
                    }
                  }
                  e.DOMCMapReaderFactory = t;
                  class i extends a.BaseStandardFontDataFactory {
                    _fetchData(I) {
                      return s(I, !0);
                    }
                  }
                  e.DOMStandardFontDataFactory = i;
                  class h extends a.BaseSVGFactory {
                    _createSVG(I) {
                      return document.createElementNS(k, I);
                    }
                  }
                  e.DOMSVGFactory = h;
                  class c {
                    constructor({
                      viewBox: I,
                      scale: _,
                      rotation: u,
                      offsetX: f = 0,
                      offsetY: v = 0,
                      dontFlip: F = !1,
                    }) {
                      ((this.viewBox = I),
                        (this.scale = _),
                        (this.rotation = u),
                        (this.offsetX = f),
                        (this.offsetY = v));
                      const L = (I[2] + I[0]) / 2,
                        N = (I[3] + I[1]) / 2;
                      let R, o, b, S;
                      switch (((u %= 360), u < 0 && (u += 360), u)) {
                        case 180:
                          ((R = -1), (o = 0), (b = 0), (S = 1));
                          break;
                        case 90:
                          ((R = 0), (o = 1), (b = 1), (S = 0));
                          break;
                        case 270:
                          ((R = 0), (o = -1), (b = -1), (S = 0));
                          break;
                        case 0:
                          ((R = 1), (o = 0), (b = 0), (S = -1));
                          break;
                        default:
                          throw new Error(
                            "PageViewport: Invalid rotation, must be a multiple of 90 degrees.",
                          );
                      }
                      F && ((b = -b), (S = -S));
                      let x, P, B, H;
                      (R === 0
                        ? ((x = Math.abs(N - I[1]) * _ + f),
                          (P = Math.abs(L - I[0]) * _ + v),
                          (B = (I[3] - I[1]) * _),
                          (H = (I[2] - I[0]) * _))
                        : ((x = Math.abs(L - I[0]) * _ + f),
                          (P = Math.abs(N - I[1]) * _ + v),
                          (B = (I[2] - I[0]) * _),
                          (H = (I[3] - I[1]) * _)),
                        (this.transform = [
                          R * _,
                          o * _,
                          b * _,
                          S * _,
                          x - R * _ * L - b * _ * N,
                          P - o * _ * L - S * _ * N,
                        ]),
                        (this.width = B),
                        (this.height = H));
                    }
                    get rawDims() {
                      const { viewBox: I } = this;
                      return (0, p.shadow)(this, "rawDims", {
                        pageWidth: I[2] - I[0],
                        pageHeight: I[3] - I[1],
                        pageX: I[0],
                        pageY: I[1],
                      });
                    }
                    clone({
                      scale: I = this.scale,
                      rotation: _ = this.rotation,
                      offsetX: u = this.offsetX,
                      offsetY: f = this.offsetY,
                      dontFlip: v = !1,
                    } = {}) {
                      return new c({
                        viewBox: this.viewBox.slice(),
                        scale: I,
                        rotation: _,
                        offsetX: u,
                        offsetY: f,
                        dontFlip: v,
                      });
                    }
                    convertToViewportPoint(I, _) {
                      return p.Util.applyTransform([I, _], this.transform);
                    }
                    convertToViewportRectangle(I) {
                      const _ = p.Util.applyTransform(
                          [I[0], I[1]],
                          this.transform,
                        ),
                        u = p.Util.applyTransform([I[2], I[3]], this.transform);
                      return [_[0], _[1], u[0], u[1]];
                    }
                    convertToPdfPoint(I, _) {
                      return p.Util.applyInverseTransform(
                        [I, _],
                        this.transform,
                      );
                    }
                  }
                  e.PageViewport = c;
                  class n extends p.BaseException {
                    constructor(I, _ = 0) {
                      (super(I, "RenderingCancelledException"),
                        (this.extraDelay = _));
                    }
                  }
                  e.RenderingCancelledException = n;
                  function d(K) {
                    const I = K.length;
                    let _ = 0;
                    for (; _ < I && K[_].trim() === "";) _++;
                    return K.substring(_, _ + 5).toLowerCase() === "data:";
                  }
                  function m(K) {
                    return typeof K == "string" && /\.pdf$/i.test(K);
                  }
                  function l(K, I = !1) {
                    return (
                      I || ([K] = K.split(/[#?]/, 1)),
                      K.substring(K.lastIndexOf("/") + 1)
                    );
                  }
                  function w(K, I = "document.pdf") {
                    if (typeof K != "string") return I;
                    if (d(K))
                      return (
                        (0, p.warn)(
                          'getPdfFilenameFromUrl: ignore "data:"-URL for performance reasons.',
                        ),
                        I
                      );
                    const _ =
                        /^(?:(?:[^:]+:)?\/\/[^/]+)?([^?#]*)(\?[^#]*)?(#.*)?$/,
                      u = /[^/?#=]+\.pdf\b(?!.*\.pdf\b)/i,
                      f = _.exec(K);
                    let v = u.exec(f[1]) || u.exec(f[2]) || u.exec(f[3]);
                    if (v && ((v = v[0]), v.includes("%")))
                      try {
                        v = u.exec(decodeURIComponent(v))[0];
                      } catch {}
                    return v || I;
                  }
                  class M {
                    started = Object.create(null);
                    times = [];
                    time(I) {
                      (I in this.started &&
                        (0, p.warn)(`Timer is already running for ${I}`),
                        (this.started[I] = Date.now()));
                    }
                    timeEnd(I) {
                      (I in this.started ||
                        (0, p.warn)(`Timer has not been started for ${I}`),
                        this.times.push({
                          name: I,
                          start: this.started[I],
                          end: Date.now(),
                        }),
                        delete this.started[I]);
                    }
                    toString() {
                      const I = [];
                      let _ = 0;
                      for (const { name: u } of this.times)
                        _ = Math.max(u.length, _);
                      for (const { name: u, start: f, end: v } of this.times)
                        I.push(`${u.padEnd(_)} ${v - f}ms
`);
                      return I.join("");
                    }
                  }
                  e.StatTimer = M;
                  function C(K, I) {
                    try {
                      const { protocol: _ } = I ? new URL(K, I) : new URL(K);
                      return _ === "http:" || _ === "https:";
                    } catch {
                      return !1;
                    }
                  }
                  function g(K) {
                    K.preventDefault();
                  }
                  function E(K, I = !1) {
                    return new Promise((_, u) => {
                      const f = document.createElement("script");
                      ((f.src = K),
                        (f.onload = function (v) {
                          (I && f.remove(), _(v));
                        }),
                        (f.onerror = function () {
                          u(new Error(`Cannot load script at: ${f.src}`));
                        }),
                        (document.head || document.documentElement).append(f));
                    });
                  }
                  function U(K) {
                    console.log("Deprecated API usage: " + K);
                  }
                  let W;
                  class O {
                    static toDateObject(I) {
                      if (!I || typeof I != "string") return null;
                      W ||= new RegExp(
                        "^D:(\\d{4})(\\d{2})?(\\d{2})?(\\d{2})?(\\d{2})?(\\d{2})?([Z|+|-])?(\\d{2})?'?(\\d{2})?'?",
                      );
                      const _ = W.exec(I);
                      if (!_) return null;
                      const u = parseInt(_[1], 10);
                      let f = parseInt(_[2], 10);
                      f = f >= 1 && f <= 12 ? f - 1 : 0;
                      let v = parseInt(_[3], 10);
                      v = v >= 1 && v <= 31 ? v : 1;
                      let F = parseInt(_[4], 10);
                      F = F >= 0 && F <= 23 ? F : 0;
                      let L = parseInt(_[5], 10);
                      L = L >= 0 && L <= 59 ? L : 0;
                      let N = parseInt(_[6], 10);
                      N = N >= 0 && N <= 59 ? N : 0;
                      const R = _[7] || "Z";
                      let o = parseInt(_[8], 10);
                      o = o >= 0 && o <= 23 ? o : 0;
                      let b = parseInt(_[9], 10) || 0;
                      return (
                        (b = b >= 0 && b <= 59 ? b : 0),
                        R === "-"
                          ? ((F += o), (L += b))
                          : R === "+" && ((F -= o), (L -= b)),
                        new Date(Date.UTC(u, f, v, F, L, N))
                      );
                    }
                  }
                  e.PDFDateString = O;
                  function V(K, { scale: I = 1, rotation: _ = 0 }) {
                    const { width: u, height: f } = K.attributes.style,
                      v = [0, 0, parseInt(u), parseInt(f)];
                    return new c({ viewBox: v, scale: I, rotation: _ });
                  }
                  function G(K) {
                    if (K.startsWith("#")) {
                      const I = parseInt(K.slice(1), 16);
                      return [(I & 16711680) >> 16, (I & 65280) >> 8, I & 255];
                    }
                    return K.startsWith("rgb(")
                      ? K.slice(4, -1)
                          .split(",")
                          .map((I) => parseInt(I))
                      : K.startsWith("rgba(")
                        ? K.slice(5, -1)
                            .split(",")
                            .map((I) => parseInt(I))
                            .slice(0, 3)
                        : ((0, p.warn)(`Not a valid color format: "${K}"`),
                          [0, 0, 0]);
                  }
                  function nt(K) {
                    const I = document.createElement("span");
                    ((I.style.visibility = "hidden"), document.body.append(I));
                    for (const _ of K.keys()) {
                      I.style.color = _;
                      const u = window.getComputedStyle(I).color;
                      K.set(_, G(u));
                    }
                    I.remove();
                  }
                  function Z(K) {
                    const {
                      a: I,
                      b: _,
                      c: u,
                      d: f,
                      e: v,
                      f: F,
                    } = K.getTransform();
                    return [I, _, u, f, v, F];
                  }
                  function tt(K) {
                    const {
                      a: I,
                      b: _,
                      c: u,
                      d: f,
                      e: v,
                      f: F,
                    } = K.getTransform().invertSelf();
                    return [I, _, u, f, v, F];
                  }
                  function rt(K, I, _ = !1, u = !0) {
                    if (I instanceof c) {
                      const { pageWidth: f, pageHeight: v } = I.rawDims,
                        { style: F } = K,
                        L = p.FeatureTest.isCSSRoundSupported,
                        N = `var(--scale-factor) * ${f}px`,
                        R = `var(--scale-factor) * ${v}px`,
                        o = L ? `round(${N}, 1px)` : `calc(${N})`,
                        b = L ? `round(${R}, 1px)` : `calc(${R})`;
                      !_ || I.rotation % 180 === 0
                        ? ((F.width = o), (F.height = b))
                        : ((F.width = b), (F.height = o));
                    }
                    u && K.setAttribute("data-main-rotation", I.rotation);
                  }
                },
                (A, e, y) => {
                  (Object.defineProperty(e, "__esModule", { value: !0 }),
                    (e.BaseStandardFontDataFactory =
                      e.BaseSVGFactory =
                      e.BaseFilterFactory =
                      e.BaseCanvasFactory =
                      e.BaseCMapReaderFactory =
                        void 0));
                  var a = y(1);
                  class p {
                    constructor() {
                      this.constructor === p &&
                        (0, a.unreachable)(
                          "Cannot initialize BaseFilterFactory.",
                        );
                    }
                    addFilter(t) {
                      return "none";
                    }
                    addHCMFilter(t, i) {
                      return "none";
                    }
                    addHighlightHCMFilter(t, i, h, c) {
                      return "none";
                    }
                    destroy(t = !1) {}
                  }
                  e.BaseFilterFactory = p;
                  class k {
                    constructor() {
                      this.constructor === k &&
                        (0, a.unreachable)(
                          "Cannot initialize BaseCanvasFactory.",
                        );
                    }
                    create(t, i) {
                      if (t <= 0 || i <= 0)
                        throw new Error("Invalid canvas size");
                      const h = this._createCanvas(t, i);
                      return { canvas: h, context: h.getContext("2d") };
                    }
                    reset(t, i, h) {
                      if (!t.canvas) throw new Error("Canvas is not specified");
                      if (i <= 0 || h <= 0)
                        throw new Error("Invalid canvas size");
                      ((t.canvas.width = i), (t.canvas.height = h));
                    }
                    destroy(t) {
                      if (!t.canvas) throw new Error("Canvas is not specified");
                      ((t.canvas.width = 0),
                        (t.canvas.height = 0),
                        (t.canvas = null),
                        (t.context = null));
                    }
                    _createCanvas(t, i) {
                      (0, a.unreachable)(
                        "Abstract method `_createCanvas` called.",
                      );
                    }
                  }
                  e.BaseCanvasFactory = k;
                  class T {
                    constructor({ baseUrl: t = null, isCompressed: i = !0 }) {
                      (this.constructor === T &&
                        (0, a.unreachable)(
                          "Cannot initialize BaseCMapReaderFactory.",
                        ),
                        (this.baseUrl = t),
                        (this.isCompressed = i));
                    }
                    async fetch({ name: t }) {
                      if (!this.baseUrl)
                        throw new Error(
                          'The CMap "baseUrl" parameter must be specified, ensure that the "cMapUrl" and "cMapPacked" API parameters are provided.',
                        );
                      if (!t) throw new Error("CMap name must be specified.");
                      const i =
                          this.baseUrl +
                          t +
                          (this.isCompressed ? ".bcmap" : ""),
                        h = this.isCompressed
                          ? a.CMapCompressionType.BINARY
                          : a.CMapCompressionType.NONE;
                      return this._fetchData(i, h).catch((c) => {
                        throw new Error(
                          `Unable to load ${this.isCompressed ? "binary " : ""}CMap at: ${i}`,
                        );
                      });
                    }
                    _fetchData(t, i) {
                      (0, a.unreachable)(
                        "Abstract method `_fetchData` called.",
                      );
                    }
                  }
                  e.BaseCMapReaderFactory = T;
                  class j {
                    constructor({ baseUrl: t = null }) {
                      (this.constructor === j &&
                        (0, a.unreachable)(
                          "Cannot initialize BaseStandardFontDataFactory.",
                        ),
                        (this.baseUrl = t));
                    }
                    async fetch({ filename: t }) {
                      if (!this.baseUrl)
                        throw new Error(
                          'The standard font "baseUrl" parameter must be specified, ensure that the "standardFontDataUrl" API parameter is provided.',
                        );
                      if (!t)
                        throw new Error("Font filename must be specified.");
                      const i = `${this.baseUrl}${t}`;
                      return this._fetchData(i).catch((h) => {
                        throw new Error(`Unable to load font data at: ${i}`);
                      });
                    }
                    _fetchData(t) {
                      (0, a.unreachable)(
                        "Abstract method `_fetchData` called.",
                      );
                    }
                  }
                  e.BaseStandardFontDataFactory = j;
                  class D {
                    constructor() {
                      this.constructor === D &&
                        (0, a.unreachable)("Cannot initialize BaseSVGFactory.");
                    }
                    create(t, i, h = !1) {
                      if (t <= 0 || i <= 0)
                        throw new Error("Invalid SVG dimensions");
                      const c = this._createSVG("svg:svg");
                      return (
                        c.setAttribute("version", "1.1"),
                        h ||
                          (c.setAttribute("width", `${t}px`),
                          c.setAttribute("height", `${i}px`)),
                        c.setAttribute("preserveAspectRatio", "none"),
                        c.setAttribute("viewBox", `0 0 ${t} ${i}`),
                        c
                      );
                    }
                    createElement(t) {
                      if (typeof t != "string")
                        throw new Error("Invalid SVG element type");
                      return this._createSVG(t);
                    }
                    _createSVG(t) {
                      (0, a.unreachable)(
                        "Abstract method `_createSVG` called.",
                      );
                    }
                  }
                  e.BaseSVGFactory = D;
                },
                (A, e, y) => {
                  (Object.defineProperty(e, "__esModule", { value: !0 }),
                    (e.MurmurHash3_64 = void 0));
                  var a = y(1);
                  const p = 3285377520,
                    k = 4294901760,
                    T = 65535;
                  class j {
                    constructor(s) {
                      ((this.h1 = s ? s & 4294967295 : p),
                        (this.h2 = s ? s & 4294967295 : p));
                    }
                    update(s) {
                      let t, i;
                      if (typeof s == "string") {
                        ((t = new Uint8Array(s.length * 2)), (i = 0));
                        for (let U = 0, W = s.length; U < W; U++) {
                          const O = s.charCodeAt(U);
                          O <= 255
                            ? (t[i++] = O)
                            : ((t[i++] = O >>> 8), (t[i++] = O & 255));
                        }
                      } else if ((0, a.isArrayBuffer)(s))
                        ((t = s.slice()), (i = t.byteLength));
                      else
                        throw new Error(
                          "Wrong data format in MurmurHash3_64_update. Input must be a string or array.",
                        );
                      const h = i >> 2,
                        c = i - h * 4,
                        n = new Uint32Array(t.buffer, 0, h);
                      let d = 0,
                        m = 0,
                        l = this.h1,
                        w = this.h2;
                      const M = 3432918353,
                        C = 461845907,
                        g = M & T,
                        E = C & T;
                      for (let U = 0; U < h; U++)
                        U & 1
                          ? ((d = n[U]),
                            (d = ((d * M) & k) | ((d * g) & T)),
                            (d = (d << 15) | (d >>> 17)),
                            (d = ((d * C) & k) | ((d * E) & T)),
                            (l ^= d),
                            (l = (l << 13) | (l >>> 19)),
                            (l = l * 5 + 3864292196))
                          : ((m = n[U]),
                            (m = ((m * M) & k) | ((m * g) & T)),
                            (m = (m << 15) | (m >>> 17)),
                            (m = ((m * C) & k) | ((m * E) & T)),
                            (w ^= m),
                            (w = (w << 13) | (w >>> 19)),
                            (w = w * 5 + 3864292196));
                      switch (((d = 0), c)) {
                        case 3:
                          d ^= t[h * 4 + 2] << 16;
                        case 2:
                          d ^= t[h * 4 + 1] << 8;
                        case 1:
                          ((d ^= t[h * 4]),
                            (d = ((d * M) & k) | ((d * g) & T)),
                            (d = (d << 15) | (d >>> 17)),
                            (d = ((d * C) & k) | ((d * E) & T)),
                            h & 1 ? (l ^= d) : (w ^= d));
                      }
                      ((this.h1 = l), (this.h2 = w));
                    }
                    hexdigest() {
                      let s = this.h1,
                        t = this.h2;
                      return (
                        (s ^= t >>> 1),
                        (s = ((s * 3981806797) & k) | ((s * 36045) & T)),
                        (t =
                          ((t * 4283543511) & k) |
                          (((((t << 16) | (s >>> 16)) * 2950163797) & k) >>>
                            16)),
                        (s ^= t >>> 1),
                        (s = ((s * 444984403) & k) | ((s * 60499) & T)),
                        (t =
                          ((t * 3301882366) & k) |
                          (((((t << 16) | (s >>> 16)) * 3120437893) & k) >>>
                            16)),
                        (s ^= t >>> 1),
                        (s >>> 0).toString(16).padStart(8, "0") +
                          (t >>> 0).toString(16).padStart(8, "0")
                      );
                    }
                  }
                  e.MurmurHash3_64 = j;
                },
                (A, e, y) => {
                  (Object.defineProperty(e, "__esModule", { value: !0 }),
                    (e.FontLoader = e.FontFaceObject = void 0));
                  var a = y(1);
                  class p {
                    #t = new Set();
                    constructor({
                      ownerDocument: j = globalThis.document,
                      styleElement: D = null,
                    }) {
                      ((this._document = j),
                        (this.nativeFontFaces = new Set()),
                        (this.styleElement = null),
                        (this.loadingRequests = []),
                        (this.loadTestFontId = 0));
                    }
                    addNativeFontFace(j) {
                      (this.nativeFontFaces.add(j),
                        this._document.fonts.add(j));
                    }
                    removeNativeFontFace(j) {
                      (this.nativeFontFaces.delete(j),
                        this._document.fonts.delete(j));
                    }
                    insertRule(j) {
                      this.styleElement ||
                        ((this.styleElement =
                          this._document.createElement("style")),
                        this._document.documentElement
                          .getElementsByTagName("head")[0]
                          .append(this.styleElement));
                      const D = this.styleElement.sheet;
                      D.insertRule(j, D.cssRules.length);
                    }
                    clear() {
                      for (const j of this.nativeFontFaces)
                        this._document.fonts.delete(j);
                      (this.nativeFontFaces.clear(),
                        this.#t.clear(),
                        this.styleElement &&
                          (this.styleElement.remove(),
                          (this.styleElement = null)));
                    }
                    async loadSystemFont(j) {
                      if (!(!j || this.#t.has(j.loadedName))) {
                        if (
                          ((0, a.assert)(
                            !this.disableFontFace,
                            "loadSystemFont shouldn't be called when `disableFontFace` is set.",
                          ),
                          this.isFontLoadingAPISupported)
                        ) {
                          const { loadedName: D, src: s, style: t } = j,
                            i = new FontFace(D, s, t);
                          this.addNativeFontFace(i);
                          try {
                            (await i.load(), this.#t.add(D));
                          } catch {
                            ((0, a.warn)(
                              `Cannot load system font: ${j.baseFontName}, installing it could help to improve PDF rendering.`,
                            ),
                              this.removeNativeFontFace(i));
                          }
                          return;
                        }
                        (0, a.unreachable)(
                          "Not implemented: loadSystemFont without the Font Loading API.",
                        );
                      }
                    }
                    async bind(j) {
                      if (j.attached || (j.missingFile && !j.systemFontInfo))
                        return;
                      if (((j.attached = !0), j.systemFontInfo)) {
                        await this.loadSystemFont(j.systemFontInfo);
                        return;
                      }
                      if (this.isFontLoadingAPISupported) {
                        const s = j.createNativeFontFace();
                        if (s) {
                          this.addNativeFontFace(s);
                          try {
                            await s.loaded;
                          } catch (t) {
                            throw (
                              (0, a.warn)(
                                `Failed to load font '${s.family}': '${t}'.`,
                              ),
                              (j.disableFontFace = !0),
                              t
                            );
                          }
                        }
                        return;
                      }
                      const D = j.createFontFaceRule();
                      if (D) {
                        if (
                          (this.insertRule(D), this.isSyncFontLoadingSupported)
                        )
                          return;
                        await new Promise((s) => {
                          const t = this._queueLoadingCallback(s);
                          this._prepareFontLoadEvent(j, t);
                        });
                      }
                    }
                    get isFontLoadingAPISupported() {
                      const j = !!this._document?.fonts;
                      return (0, a.shadow)(
                        this,
                        "isFontLoadingAPISupported",
                        j,
                      );
                    }
                    get isSyncFontLoadingSupported() {
                      let j = !1;
                      return (
                        (a.isNodeJS ||
                          (typeof navigator < "u" &&
                            /Mozilla\/5.0.*?rv:\d+.*? Gecko/.test(
                              navigator.userAgent,
                            ))) &&
                          (j = !0),
                        (0, a.shadow)(this, "isSyncFontLoadingSupported", j)
                      );
                    }
                    _queueLoadingCallback(j) {
                      function D() {
                        for (
                          (0, a.assert)(
                            !t.done,
                            "completeRequest() cannot be called twice.",
                          ),
                            t.done = !0;
                          s.length > 0 && s[0].done;
                        ) {
                          const i = s.shift();
                          setTimeout(i.callback, 0);
                        }
                      }
                      const { loadingRequests: s } = this,
                        t = { done: !1, complete: D, callback: j };
                      return (s.push(t), t);
                    }
                    get _loadTestFont() {
                      const j = atob(
                        "T1RUTwALAIAAAwAwQ0ZGIDHtZg4AAAOYAAAAgUZGVE1lkzZwAAAEHAAAABxHREVGABQAFQAABDgAAAAeT1MvMlYNYwkAAAEgAAAAYGNtYXABDQLUAAACNAAAAUJoZWFk/xVFDQAAALwAAAA2aGhlYQdkA+oAAAD0AAAAJGhtdHgD6AAAAAAEWAAAAAZtYXhwAAJQAAAAARgAAAAGbmFtZVjmdH4AAAGAAAAAsXBvc3T/hgAzAAADeAAAACAAAQAAAAEAALZRFsRfDzz1AAsD6AAAAADOBOTLAAAAAM4KHDwAAAAAA+gDIQAAAAgAAgAAAAAAAAABAAADIQAAAFoD6AAAAAAD6AABAAAAAAAAAAAAAAAAAAAAAQAAUAAAAgAAAAQD6AH0AAUAAAKKArwAAACMAooCvAAAAeAAMQECAAACAAYJAAAAAAAAAAAAAQAAAAAAAAAAAAAAAFBmRWQAwAAuAC4DIP84AFoDIQAAAAAAAQAAAAAAAAAAACAAIAABAAAADgCuAAEAAAAAAAAAAQAAAAEAAAAAAAEAAQAAAAEAAAAAAAIAAQAAAAEAAAAAAAMAAQAAAAEAAAAAAAQAAQAAAAEAAAAAAAUAAQAAAAEAAAAAAAYAAQAAAAMAAQQJAAAAAgABAAMAAQQJAAEAAgABAAMAAQQJAAIAAgABAAMAAQQJAAMAAgABAAMAAQQJAAQAAgABAAMAAQQJAAUAAgABAAMAAQQJAAYAAgABWABYAAAAAAAAAwAAAAMAAAAcAAEAAAAAADwAAwABAAAAHAAEACAAAAAEAAQAAQAAAC7//wAAAC7////TAAEAAAAAAAABBgAAAQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAEAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAMAAAAAAAD/gwAyAAAAAQAAAAAAAAAAAAAAAAAAAAABAAQEAAEBAQJYAAEBASH4DwD4GwHEAvgcA/gXBIwMAYuL+nz5tQXkD5j3CBLnEQACAQEBIVhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYAAABAQAADwACAQEEE/t3Dov6fAH6fAT+fPp8+nwHDosMCvm1Cvm1DAz6fBQAAAAAAAABAAAAAMmJbzEAAAAAzgTjFQAAAADOBOQpAAEAAAAAAAAADAAUAAQAAAABAAAAAgABAAAAAAAAAAAD6AAAAAAAAA==",
                      );
                      return (0, a.shadow)(this, "_loadTestFont", j);
                    }
                    _prepareFontLoadEvent(j, D) {
                      function s(V, G) {
                        return (
                          (V.charCodeAt(G) << 24) |
                          (V.charCodeAt(G + 1) << 16) |
                          (V.charCodeAt(G + 2) << 8) |
                          (V.charCodeAt(G + 3) & 255)
                        );
                      }
                      function t(V, G, nt, Z) {
                        const tt = V.substring(0, G),
                          rt = V.substring(G + nt);
                        return tt + Z + rt;
                      }
                      let i, h;
                      const c = this._document.createElement("canvas");
                      ((c.width = 1), (c.height = 1));
                      const n = c.getContext("2d");
                      let d = 0;
                      function m(V, G) {
                        if (++d > 30) {
                          ((0, a.warn)("Load test font never loaded."), G());
                          return;
                        }
                        if (
                          ((n.font = "30px " + V),
                          n.fillText(".", 0, 20),
                          n.getImageData(0, 0, 1, 1).data[3] > 0)
                        ) {
                          G();
                          return;
                        }
                        setTimeout(m.bind(null, V, G));
                      }
                      const l = `lt${Date.now()}${this.loadTestFontId++}`;
                      let w = this._loadTestFont;
                      w = t(w, 976, l.length, l);
                      const C = 16,
                        g = 1482184792;
                      let E = s(w, C);
                      for (i = 0, h = l.length - 3; i < h; i += 4)
                        E = (E - g + s(l, i)) | 0;
                      (i < l.length && (E = (E - g + s(l + "XXX", i)) | 0),
                        (w = t(w, C, 4, (0, a.string32)(E))));
                      const U = `url(data:font/opentype;base64,${btoa(w)});`,
                        W = `@font-face {font-family:"${l}";src:${U}}`;
                      this.insertRule(W);
                      const O = this._document.createElement("div");
                      ((O.style.visibility = "hidden"),
                        (O.style.width = O.style.height = "10px"),
                        (O.style.position = "absolute"),
                        (O.style.top = O.style.left = "0px"));
                      for (const V of [j.loadedName, l]) {
                        const G = this._document.createElement("span");
                        ((G.textContent = "Hi"),
                          (G.style.fontFamily = V),
                          O.append(G));
                      }
                      (this._document.body.append(O),
                        m(l, () => {
                          (O.remove(), D.complete());
                        }));
                    }
                  }
                  e.FontLoader = p;
                  class k {
                    constructor(
                      j,
                      {
                        isEvalSupported: D = !0,
                        disableFontFace: s = !1,
                        ignoreErrors: t = !1,
                        inspectFont: i = null,
                      },
                    ) {
                      this.compiledGlyphs = Object.create(null);
                      for (const h in j) this[h] = j[h];
                      ((this.isEvalSupported = D !== !1),
                        (this.disableFontFace = s === !0),
                        (this.ignoreErrors = t === !0),
                        (this._inspectFont = i));
                    }
                    createNativeFontFace() {
                      if (!this.data || this.disableFontFace) return null;
                      let j;
                      if (!this.cssFontInfo)
                        j = new FontFace(this.loadedName, this.data, {});
                      else {
                        const D = { weight: this.cssFontInfo.fontWeight };
                        (this.cssFontInfo.italicAngle &&
                          (D.style = `oblique ${this.cssFontInfo.italicAngle}deg`),
                          (j = new FontFace(
                            this.cssFontInfo.fontFamily,
                            this.data,
                            D,
                          )));
                      }
                      return (this._inspectFont?.(this), j);
                    }
                    createFontFaceRule() {
                      if (!this.data || this.disableFontFace) return null;
                      const j = (0, a.bytesToString)(this.data),
                        D = `url(data:${this.mimetype};base64,${btoa(j)});`;
                      let s;
                      if (!this.cssFontInfo)
                        s = `@font-face {font-family:"${this.loadedName}";src:${D}}`;
                      else {
                        let t = `font-weight: ${this.cssFontInfo.fontWeight};`;
                        (this.cssFontInfo.italicAngle &&
                          (t += `font-style: oblique ${this.cssFontInfo.italicAngle}deg;`),
                          (s = `@font-face {font-family:"${this.cssFontInfo.fontFamily}";${t}src:${D}}`));
                      }
                      return (this._inspectFont?.(this, D), s);
                    }
                    getPathGenerator(j, D) {
                      if (this.compiledGlyphs[D] !== void 0)
                        return this.compiledGlyphs[D];
                      let s;
                      try {
                        s = j.get(this.loadedName + "_path_" + D);
                      } catch (t) {
                        if (!this.ignoreErrors) throw t;
                        return (
                          (0, a.warn)(
                            `getPathGenerator - ignoring character: "${t}".`,
                          ),
                          (this.compiledGlyphs[D] = function (i, h) {})
                        );
                      }
                      if (
                        this.isEvalSupported &&
                        a.FeatureTest.isEvalSupported
                      ) {
                        const t = [];
                        for (const i of s) {
                          const h = i.args !== void 0 ? i.args.join(",") : "";
                          t.push(
                            "c.",
                            i.cmd,
                            "(",
                            h,
                            `);
`,
                          );
                        }
                        return (this.compiledGlyphs[D] = new Function(
                          "c",
                          "size",
                          t.join(""),
                        ));
                      }
                      return (this.compiledGlyphs[D] = function (t, i) {
                        for (const h of s)
                          (h.cmd === "scale" && (h.args = [i, -i]),
                            t[h.cmd].apply(t, h.args));
                      });
                    }
                  }
                  e.FontFaceObject = k;
                },
                (A, e, y) => {
                  (Object.defineProperty(e, "__esModule", { value: !0 }),
                    (e.NodeStandardFontDataFactory =
                      e.NodeFilterFactory =
                      e.NodeCanvasFactory =
                      e.NodeCMapReaderFactory =
                        void 0));
                  var a = y(7);
                  y(1);
                  const p = function (s) {
                    return new Promise((t, i) => {
                      require$$0.readFile(s, (c, n) => {
                        if (c || !n) {
                          i(new Error(c));
                          return;
                        }
                        t(new Uint8Array(n));
                      });
                    });
                  };
                  class k extends a.BaseFilterFactory {}
                  e.NodeFilterFactory = k;
                  class T extends a.BaseCanvasFactory {
                    _createCanvas(t, i) {
                      return require$$1.createCanvas(t, i);
                    }
                  }
                  e.NodeCanvasFactory = T;
                  class j extends a.BaseCMapReaderFactory {
                    _fetchData(t, i) {
                      return p(t).then((h) => ({
                        cMapData: h,
                        compressionType: i,
                      }));
                    }
                  }
                  e.NodeCMapReaderFactory = j;
                  class D extends a.BaseStandardFontDataFactory {
                    _fetchData(t) {
                      return p(t);
                    }
                  }
                  e.NodeStandardFontDataFactory = D;
                },
                (A, e, y) => {
                  (Object.defineProperty(e, "__esModule", { value: !0 }),
                    (e.CanvasGraphics = void 0));
                  var a = y(1),
                    p = y(6),
                    k = y(12),
                    T = y(13);
                  const j = 16,
                    D = 100,
                    s = 4096,
                    t = 15,
                    i = 10,
                    h = 1e3,
                    c = 16;
                  function n(_, u) {
                    if (_._removeMirroring)
                      throw new Error(
                        "Context is already forwarding operations.",
                      );
                    ((_.__originalSave = _.save),
                      (_.__originalRestore = _.restore),
                      (_.__originalRotate = _.rotate),
                      (_.__originalScale = _.scale),
                      (_.__originalTranslate = _.translate),
                      (_.__originalTransform = _.transform),
                      (_.__originalSetTransform = _.setTransform),
                      (_.__originalResetTransform = _.resetTransform),
                      (_.__originalClip = _.clip),
                      (_.__originalMoveTo = _.moveTo),
                      (_.__originalLineTo = _.lineTo),
                      (_.__originalBezierCurveTo = _.bezierCurveTo),
                      (_.__originalRect = _.rect),
                      (_.__originalClosePath = _.closePath),
                      (_.__originalBeginPath = _.beginPath),
                      (_._removeMirroring = () => {
                        ((_.save = _.__originalSave),
                          (_.restore = _.__originalRestore),
                          (_.rotate = _.__originalRotate),
                          (_.scale = _.__originalScale),
                          (_.translate = _.__originalTranslate),
                          (_.transform = _.__originalTransform),
                          (_.setTransform = _.__originalSetTransform),
                          (_.resetTransform = _.__originalResetTransform),
                          (_.clip = _.__originalClip),
                          (_.moveTo = _.__originalMoveTo),
                          (_.lineTo = _.__originalLineTo),
                          (_.bezierCurveTo = _.__originalBezierCurveTo),
                          (_.rect = _.__originalRect),
                          (_.closePath = _.__originalClosePath),
                          (_.beginPath = _.__originalBeginPath),
                          delete _._removeMirroring);
                      }),
                      (_.save = function () {
                        (u.save(), this.__originalSave());
                      }),
                      (_.restore = function () {
                        (u.restore(), this.__originalRestore());
                      }),
                      (_.translate = function (v, F) {
                        (u.translate(v, F), this.__originalTranslate(v, F));
                      }),
                      (_.scale = function (v, F) {
                        (u.scale(v, F), this.__originalScale(v, F));
                      }),
                      (_.transform = function (v, F, L, N, R, o) {
                        (u.transform(v, F, L, N, R, o),
                          this.__originalTransform(v, F, L, N, R, o));
                      }),
                      (_.setTransform = function (v, F, L, N, R, o) {
                        (u.setTransform(v, F, L, N, R, o),
                          this.__originalSetTransform(v, F, L, N, R, o));
                      }),
                      (_.resetTransform = function () {
                        (u.resetTransform(), this.__originalResetTransform());
                      }),
                      (_.rotate = function (v) {
                        (u.rotate(v), this.__originalRotate(v));
                      }),
                      (_.clip = function (v) {
                        (u.clip(v), this.__originalClip(v));
                      }),
                      (_.moveTo = function (f, v) {
                        (u.moveTo(f, v), this.__originalMoveTo(f, v));
                      }),
                      (_.lineTo = function (f, v) {
                        (u.lineTo(f, v), this.__originalLineTo(f, v));
                      }),
                      (_.bezierCurveTo = function (f, v, F, L, N, R) {
                        (u.bezierCurveTo(f, v, F, L, N, R),
                          this.__originalBezierCurveTo(f, v, F, L, N, R));
                      }),
                      (_.rect = function (f, v, F, L) {
                        (u.rect(f, v, F, L), this.__originalRect(f, v, F, L));
                      }),
                      (_.closePath = function () {
                        (u.closePath(), this.__originalClosePath());
                      }),
                      (_.beginPath = function () {
                        (u.beginPath(), this.__originalBeginPath());
                      }));
                  }
                  class d {
                    constructor(u) {
                      ((this.canvasFactory = u),
                        (this.cache = Object.create(null)));
                    }
                    getCanvas(u, f, v) {
                      let F;
                      return (
                        this.cache[u] !== void 0
                          ? ((F = this.cache[u]),
                            this.canvasFactory.reset(F, f, v))
                          : ((F = this.canvasFactory.create(f, v)),
                            (this.cache[u] = F)),
                        F
                      );
                    }
                    delete(u) {
                      delete this.cache[u];
                    }
                    clear() {
                      for (const u in this.cache) {
                        const f = this.cache[u];
                        (this.canvasFactory.destroy(f), delete this.cache[u]);
                      }
                    }
                  }
                  function m(_, u, f, v, F, L, N, R, o, b) {
                    const [S, x, P, B, H, z] = (0, p.getCurrentTransform)(_);
                    if (x === 0 && P === 0) {
                      const X = N * S + H,
                        J = Math.round(X),
                        Q = R * B + z,
                        et = Math.round(Q),
                        at = (N + o) * S + H,
                        lt = Math.abs(Math.round(at) - J) || 1,
                        ct = (R + b) * B + z,
                        ht = Math.abs(Math.round(ct) - et) || 1;
                      return (
                        _.setTransform(Math.sign(S), 0, 0, Math.sign(B), J, et),
                        _.drawImage(u, f, v, F, L, 0, 0, lt, ht),
                        _.setTransform(S, x, P, B, H, z),
                        [lt, ht]
                      );
                    }
                    if (S === 0 && B === 0) {
                      const X = R * P + H,
                        J = Math.round(X),
                        Q = N * x + z,
                        et = Math.round(Q),
                        at = (R + b) * P + H,
                        lt = Math.abs(Math.round(at) - J) || 1,
                        ct = (N + o) * x + z,
                        ht = Math.abs(Math.round(ct) - et) || 1;
                      return (
                        _.setTransform(0, Math.sign(x), Math.sign(P), 0, J, et),
                        _.drawImage(u, f, v, F, L, 0, 0, ht, lt),
                        _.setTransform(S, x, P, B, H, z),
                        [ht, lt]
                      );
                    }
                    _.drawImage(u, f, v, F, L, N, R, o, b);
                    const st = Math.hypot(S, x),
                      Y = Math.hypot(P, B);
                    return [st * o, Y * b];
                  }
                  function l(_) {
                    const { width: u, height: f } = _;
                    if (u > h || f > h) return null;
                    const v = 1e3,
                      F = new Uint8Array([
                        0, 2, 4, 0, 1, 0, 5, 4, 8, 10, 0, 8, 0, 2, 1, 0,
                      ]),
                      L = u + 1;
                    let N = new Uint8Array(L * (f + 1)),
                      R,
                      o,
                      b;
                    const S = (u + 7) & -8;
                    let x = new Uint8Array(S * f),
                      P = 0;
                    for (const Y of _.data) {
                      let X = 128;
                      for (; X > 0;) ((x[P++] = Y & X ? 0 : 255), (X >>= 1));
                    }
                    let B = 0;
                    for (
                      P = 0, x[P] !== 0 && ((N[0] = 1), ++B), o = 1;
                      o < u;
                      o++
                    )
                      (x[P] !== x[P + 1] && ((N[o] = x[P] ? 2 : 1), ++B), P++);
                    for (x[P] !== 0 && ((N[o] = 2), ++B), R = 1; R < f; R++) {
                      ((P = R * S),
                        (b = R * L),
                        x[P - S] !== x[P] && ((N[b] = x[P] ? 1 : 8), ++B));
                      let Y = (x[P] ? 4 : 0) + (x[P - S] ? 8 : 0);
                      for (o = 1; o < u; o++)
                        ((Y =
                          (Y >> 2) +
                          (x[P + 1] ? 4 : 0) +
                          (x[P - S + 1] ? 8 : 0)),
                          F[Y] && ((N[b + o] = F[Y]), ++B),
                          P++);
                      if (
                        (x[P - S] !== x[P] && ((N[b + o] = x[P] ? 2 : 4), ++B),
                        B > v)
                      )
                        return null;
                    }
                    for (
                      P = S * (f - 1),
                        b = R * L,
                        x[P] !== 0 && ((N[b] = 8), ++B),
                        o = 1;
                      o < u;
                      o++
                    )
                      (x[P] !== x[P + 1] && ((N[b + o] = x[P] ? 4 : 8), ++B),
                        P++);
                    if ((x[P] !== 0 && ((N[b + o] = 4), ++B), B > v))
                      return null;
                    const H = new Int32Array([0, L, -1, 0, -L, 0, 0, 0, 1]),
                      z = new Path2D();
                    for (R = 0; B && R <= f; R++) {
                      let Y = R * L;
                      const X = Y + u;
                      for (; Y < X && !N[Y];) Y++;
                      if (Y === X) continue;
                      z.moveTo(Y % L, R);
                      const J = Y;
                      let Q = N[Y];
                      do {
                        const et = H[Q];
                        do Y += et;
                        while (!N[Y]);
                        const at = N[Y];
                        (at !== 5 && at !== 10
                          ? ((Q = at), (N[Y] = 0))
                          : ((Q = at & ((51 * Q) >> 4)),
                            (N[Y] &= (Q >> 2) | (Q << 2))),
                          z.lineTo(Y % L, (Y / L) | 0),
                          N[Y] || --B);
                      } while (J !== Y);
                      --R;
                    }
                    return (
                      (x = null),
                      (N = null),
                      function (Y) {
                        (Y.save(),
                          Y.scale(1 / u, -1 / f),
                          Y.translate(0, -f),
                          Y.fill(z),
                          Y.beginPath(),
                          Y.restore());
                      }
                    );
                  }
                  class w {
                    constructor(u, f) {
                      ((this.alphaIsShape = !1),
                        (this.fontSize = 0),
                        (this.fontSizeScale = 1),
                        (this.textMatrix = a.IDENTITY_MATRIX),
                        (this.textMatrixScale = 1),
                        (this.fontMatrix = a.FONT_IDENTITY_MATRIX),
                        (this.leading = 0),
                        (this.x = 0),
                        (this.y = 0),
                        (this.lineX = 0),
                        (this.lineY = 0),
                        (this.charSpacing = 0),
                        (this.wordSpacing = 0),
                        (this.textHScale = 1),
                        (this.textRenderingMode = a.TextRenderingMode.FILL),
                        (this.textRise = 0),
                        (this.fillColor = "#000000"),
                        (this.strokeColor = "#000000"),
                        (this.patternFill = !1),
                        (this.fillAlpha = 1),
                        (this.strokeAlpha = 1),
                        (this.lineWidth = 1),
                        (this.activeSMask = null),
                        (this.transferMaps = "none"),
                        this.startNewPathAndClipBox([0, 0, u, f]));
                    }
                    clone() {
                      const u = Object.create(this);
                      return ((u.clipBox = this.clipBox.slice()), u);
                    }
                    setCurrentPoint(u, f) {
                      ((this.x = u), (this.y = f));
                    }
                    updatePathMinMax(u, f, v) {
                      (([f, v] = a.Util.applyTransform([f, v], u)),
                        (this.minX = Math.min(this.minX, f)),
                        (this.minY = Math.min(this.minY, v)),
                        (this.maxX = Math.max(this.maxX, f)),
                        (this.maxY = Math.max(this.maxY, v)));
                    }
                    updateRectMinMax(u, f) {
                      const v = a.Util.applyTransform(f, u),
                        F = a.Util.applyTransform(f.slice(2), u);
                      ((this.minX = Math.min(this.minX, v[0], F[0])),
                        (this.minY = Math.min(this.minY, v[1], F[1])),
                        (this.maxX = Math.max(this.maxX, v[0], F[0])),
                        (this.maxY = Math.max(this.maxY, v[1], F[1])));
                    }
                    updateScalingPathMinMax(u, f) {
                      (a.Util.scaleMinMax(u, f),
                        (this.minX = Math.min(this.minX, f[0])),
                        (this.maxX = Math.max(this.maxX, f[1])),
                        (this.minY = Math.min(this.minY, f[2])),
                        (this.maxY = Math.max(this.maxY, f[3])));
                    }
                    updateCurvePathMinMax(u, f, v, F, L, N, R, o, b, S) {
                      const x = a.Util.bezierBoundingBox(
                        f,
                        v,
                        F,
                        L,
                        N,
                        R,
                        o,
                        b,
                      );
                      if (S) {
                        ((S[0] = Math.min(S[0], x[0], x[2])),
                          (S[1] = Math.max(S[1], x[0], x[2])),
                          (S[2] = Math.min(S[2], x[1], x[3])),
                          (S[3] = Math.max(S[3], x[1], x[3])));
                        return;
                      }
                      this.updateRectMinMax(u, x);
                    }
                    getPathBoundingBox(u = k.PathType.FILL, f = null) {
                      const v = [this.minX, this.minY, this.maxX, this.maxY];
                      if (u === k.PathType.STROKE) {
                        f ||
                          (0, a.unreachable)(
                            "Stroke bounding box must include transform.",
                          );
                        const F = a.Util.singularValueDecompose2dScale(f),
                          L = (F[0] * this.lineWidth) / 2,
                          N = (F[1] * this.lineWidth) / 2;
                        ((v[0] -= L), (v[1] -= N), (v[2] += L), (v[3] += N));
                      }
                      return v;
                    }
                    updateClipFromPath() {
                      const u = a.Util.intersect(
                        this.clipBox,
                        this.getPathBoundingBox(),
                      );
                      this.startNewPathAndClipBox(u || [0, 0, 0, 0]);
                    }
                    isEmptyClip() {
                      return this.minX === 1 / 0;
                    }
                    startNewPathAndClipBox(u) {
                      ((this.clipBox = u),
                        (this.minX = 1 / 0),
                        (this.minY = 1 / 0),
                        (this.maxX = 0),
                        (this.maxY = 0));
                    }
                    getClippedPathBoundingBox(u = k.PathType.FILL, f = null) {
                      return a.Util.intersect(
                        this.clipBox,
                        this.getPathBoundingBox(u, f),
                      );
                    }
                  }
                  function M(_, u) {
                    if (typeof ImageData < "u" && u instanceof ImageData) {
                      _.putImageData(u, 0, 0);
                      return;
                    }
                    const f = u.height,
                      v = u.width,
                      F = f % c,
                      L = (f - F) / c,
                      N = F === 0 ? L : L + 1,
                      R = _.createImageData(v, c);
                    let o = 0,
                      b;
                    const S = u.data,
                      x = R.data;
                    let P, B, H, z;
                    if (u.kind === a.ImageKind.GRAYSCALE_1BPP) {
                      const st = S.byteLength,
                        Y = new Uint32Array(x.buffer, 0, x.byteLength >> 2),
                        X = Y.length,
                        J = (v + 7) >> 3,
                        Q = 4294967295,
                        et = a.FeatureTest.isLittleEndian ? 4278190080 : 255;
                      for (P = 0; P < N; P++) {
                        for (H = P < L ? c : F, b = 0, B = 0; B < H; B++) {
                          const at = st - o;
                          let lt = 0;
                          const ct = at > J ? v : at * 8 - 7,
                            ht = ct & -8;
                          let dt = 0,
                            ut = 0;
                          for (; lt < ht; lt += 8)
                            ((ut = S[o++]),
                              (Y[b++] = ut & 128 ? Q : et),
                              (Y[b++] = ut & 64 ? Q : et),
                              (Y[b++] = ut & 32 ? Q : et),
                              (Y[b++] = ut & 16 ? Q : et),
                              (Y[b++] = ut & 8 ? Q : et),
                              (Y[b++] = ut & 4 ? Q : et),
                              (Y[b++] = ut & 2 ? Q : et),
                              (Y[b++] = ut & 1 ? Q : et));
                          for (; lt < ct; lt++)
                            (dt === 0 && ((ut = S[o++]), (dt = 128)),
                              (Y[b++] = ut & dt ? Q : et),
                              (dt >>= 1));
                        }
                        for (; b < X;) Y[b++] = 0;
                        _.putImageData(R, 0, P * c);
                      }
                    } else if (u.kind === a.ImageKind.RGBA_32BPP) {
                      for (B = 0, z = v * c * 4, P = 0; P < L; P++)
                        (x.set(S.subarray(o, o + z)),
                          (o += z),
                          _.putImageData(R, 0, B),
                          (B += c));
                      P < N &&
                        ((z = v * F * 4),
                        x.set(S.subarray(o, o + z)),
                        _.putImageData(R, 0, B));
                    } else if (u.kind === a.ImageKind.RGB_24BPP)
                      for (H = c, z = v * H, P = 0; P < N; P++) {
                        for (
                          P >= L && ((H = F), (z = v * H)), b = 0, B = z;
                          B--;
                        )
                          ((x[b++] = S[o++]),
                            (x[b++] = S[o++]),
                            (x[b++] = S[o++]),
                            (x[b++] = 255));
                        _.putImageData(R, 0, P * c);
                      }
                    else throw new Error(`bad image kind: ${u.kind}`);
                  }
                  function C(_, u) {
                    if (u.bitmap) {
                      _.drawImage(u.bitmap, 0, 0);
                      return;
                    }
                    const f = u.height,
                      v = u.width,
                      F = f % c,
                      L = (f - F) / c,
                      N = F === 0 ? L : L + 1,
                      R = _.createImageData(v, c);
                    let o = 0;
                    const b = u.data,
                      S = R.data;
                    for (let x = 0; x < N; x++) {
                      const P = x < L ? c : F;
                      (({ srcPos: o } = (0, T.convertBlackAndWhiteToRGBA)({
                        src: b,
                        srcPos: o,
                        dest: S,
                        width: v,
                        height: P,
                        nonBlackColor: 0,
                      })),
                        _.putImageData(R, 0, x * c));
                    }
                  }
                  function g(_, u) {
                    const f = [
                      "strokeStyle",
                      "fillStyle",
                      "fillRule",
                      "globalAlpha",
                      "lineWidth",
                      "lineCap",
                      "lineJoin",
                      "miterLimit",
                      "globalCompositeOperation",
                      "font",
                      "filter",
                    ];
                    for (const v of f) _[v] !== void 0 && (u[v] = _[v]);
                    _.setLineDash !== void 0 &&
                      (u.setLineDash(_.getLineDash()),
                      (u.lineDashOffset = _.lineDashOffset));
                  }
                  function E(_) {
                    if (
                      ((_.strokeStyle = _.fillStyle = "#000000"),
                      (_.fillRule = "nonzero"),
                      (_.globalAlpha = 1),
                      (_.lineWidth = 1),
                      (_.lineCap = "butt"),
                      (_.lineJoin = "miter"),
                      (_.miterLimit = 10),
                      (_.globalCompositeOperation = "source-over"),
                      (_.font = "10px sans-serif"),
                      _.setLineDash !== void 0 &&
                        (_.setLineDash([]), (_.lineDashOffset = 0)),
                      !a.isNodeJS)
                    ) {
                      const { filter: u } = _;
                      u !== "none" && u !== "" && (_.filter = "none");
                    }
                  }
                  function U(_, u, f, v) {
                    const F = _.length;
                    for (let L = 3; L < F; L += 4) {
                      const N = _[L];
                      if (N === 0)
                        ((_[L - 3] = u), (_[L - 2] = f), (_[L - 1] = v));
                      else if (N < 255) {
                        const R = 255 - N;
                        ((_[L - 3] = (_[L - 3] * N + u * R) >> 8),
                          (_[L - 2] = (_[L - 2] * N + f * R) >> 8),
                          (_[L - 1] = (_[L - 1] * N + v * R) >> 8));
                      }
                    }
                  }
                  function W(_, u, f) {
                    const v = _.length,
                      F = 1 / 255;
                    for (let L = 3; L < v; L += 4) {
                      const N = f ? f[_[L]] : _[L];
                      u[L] = (u[L] * N * F) | 0;
                    }
                  }
                  function O(_, u, f) {
                    const v = _.length;
                    for (let F = 3; F < v; F += 4) {
                      const L = _[F - 3] * 77 + _[F - 2] * 152 + _[F - 1] * 28;
                      u[F] = f ? (u[F] * f[L >> 8]) >> 8 : (u[F] * L) >> 16;
                    }
                  }
                  function V(_, u, f, v, F, L, N, R, o, b, S) {
                    const x = !!L,
                      P = x ? L[0] : 0,
                      B = x ? L[1] : 0,
                      H = x ? L[2] : 0,
                      z = F === "Luminosity" ? O : W,
                      Y = Math.min(v, Math.ceil(1048576 / f));
                    for (let X = 0; X < v; X += Y) {
                      const J = Math.min(Y, v - X),
                        Q = _.getImageData(R - b, X + (o - S), f, J),
                        et = u.getImageData(R, X + o, f, J);
                      (x && U(Q.data, P, B, H),
                        z(Q.data, et.data, N),
                        u.putImageData(et, R, X + o));
                    }
                  }
                  function G(_, u, f, v) {
                    const F = v[0],
                      L = v[1],
                      N = v[2] - F,
                      R = v[3] - L;
                    N === 0 ||
                      R === 0 ||
                      (V(
                        u.context,
                        f,
                        N,
                        R,
                        u.subtype,
                        u.backdrop,
                        u.transferMap,
                        F,
                        L,
                        u.offsetX,
                        u.offsetY,
                      ),
                      _.save(),
                      (_.globalAlpha = 1),
                      (_.globalCompositeOperation = "source-over"),
                      _.setTransform(1, 0, 0, 1, 0, 0),
                      _.drawImage(f.canvas, 0, 0),
                      _.restore());
                  }
                  function nt(_, u) {
                    const f = a.Util.singularValueDecompose2dScale(_);
                    ((f[0] = Math.fround(f[0])), (f[1] = Math.fround(f[1])));
                    const v = Math.fround(
                      (globalThis.devicePixelRatio || 1) *
                        p.PixelsPerInch.PDF_TO_CSS_UNITS,
                    );
                    return u !== void 0 ? u : f[0] <= v || f[1] <= v;
                  }
                  const Z = ["butt", "round", "square"],
                    tt = ["miter", "round", "bevel"],
                    rt = {},
                    K = {};
                  class I {
                    constructor(
                      u,
                      f,
                      v,
                      F,
                      L,
                      {
                        optionalContentConfig: N,
                        markedContentStack: R = null,
                      },
                      o,
                      b,
                    ) {
                      ((this.ctx = u),
                        (this.current = new w(
                          this.ctx.canvas.width,
                          this.ctx.canvas.height,
                        )),
                        (this.stateStack = []),
                        (this.pendingClip = null),
                        (this.pendingEOFill = !1),
                        (this.res = null),
                        (this.xobjs = null),
                        (this.commonObjs = f),
                        (this.objs = v),
                        (this.canvasFactory = F),
                        (this.filterFactory = L),
                        (this.groupStack = []),
                        (this.processingType3 = null),
                        (this.baseTransform = null),
                        (this.baseTransformStack = []),
                        (this.groupLevel = 0),
                        (this.smaskStack = []),
                        (this.smaskCounter = 0),
                        (this.tempSMask = null),
                        (this.suspendedCtx = null),
                        (this.contentVisible = !0),
                        (this.markedContentStack = R || []),
                        (this.optionalContentConfig = N),
                        (this.cachedCanvases = new d(this.canvasFactory)),
                        (this.cachedPatterns = new Map()),
                        (this.annotationCanvasMap = o),
                        (this.viewportScale = 1),
                        (this.outputScaleX = 1),
                        (this.outputScaleY = 1),
                        (this.pageColors = b),
                        (this._cachedScaleForStroking = [-1, 0]),
                        (this._cachedGetSinglePixelWidth = null),
                        (this._cachedBitmapsMap = new Map()));
                    }
                    getObject(u, f = null) {
                      return typeof u == "string"
                        ? u.startsWith("g_")
                          ? this.commonObjs.get(u)
                          : this.objs.get(u)
                        : f;
                    }
                    beginDrawing({
                      transform: u,
                      viewport: f,
                      transparency: v = !1,
                      background: F = null,
                    }) {
                      const L = this.ctx.canvas.width,
                        N = this.ctx.canvas.height,
                        R = this.ctx.fillStyle;
                      if (
                        ((this.ctx.fillStyle = F || "#ffffff"),
                        this.ctx.fillRect(0, 0, L, N),
                        (this.ctx.fillStyle = R),
                        v)
                      ) {
                        const o = this.cachedCanvases.getCanvas(
                          "transparent",
                          L,
                          N,
                        );
                        ((this.compositeCtx = this.ctx),
                          (this.transparentCanvas = o.canvas),
                          (this.ctx = o.context),
                          this.ctx.save(),
                          this.ctx.transform(
                            ...(0, p.getCurrentTransform)(this.compositeCtx),
                          ));
                      }
                      (this.ctx.save(),
                        E(this.ctx),
                        u &&
                          (this.ctx.transform(...u),
                          (this.outputScaleX = u[0]),
                          (this.outputScaleY = u[0])),
                        this.ctx.transform(...f.transform),
                        (this.viewportScale = f.scale),
                        (this.baseTransform = (0, p.getCurrentTransform)(
                          this.ctx,
                        )));
                    }
                    executeOperatorList(u, f, v, F) {
                      const L = u.argsArray,
                        N = u.fnArray;
                      let R = f || 0;
                      const o = L.length;
                      if (o === R) return R;
                      const b = o - R > i && typeof v == "function",
                        S = b ? Date.now() + t : 0;
                      let x = 0;
                      const P = this.commonObjs,
                        B = this.objs;
                      let H;
                      for (;;) {
                        if (F !== void 0 && R === F.nextBreakPoint)
                          return (F.breakIt(R, v), R);
                        if (((H = N[R]), H !== a.OPS.dependency))
                          this[H].apply(this, L[R]);
                        else
                          for (const z of L[R]) {
                            const st = z.startsWith("g_") ? P : B;
                            if (!st.has(z)) return (st.get(z, v), R);
                          }
                        if ((R++, R === o)) return R;
                        if (b && ++x > i) {
                          if (Date.now() > S) return (v(), R);
                          x = 0;
                        }
                      }
                    }
                    #t() {
                      for (; this.stateStack.length || this.inSMaskMode;)
                        this.restore();
                      (this.ctx.restore(),
                        this.transparentCanvas &&
                          ((this.ctx = this.compositeCtx),
                          this.ctx.save(),
                          this.ctx.setTransform(1, 0, 0, 1, 0, 0),
                          this.ctx.drawImage(this.transparentCanvas, 0, 0),
                          this.ctx.restore(),
                          (this.transparentCanvas = null)));
                    }
                    endDrawing() {
                      (this.#t(),
                        this.cachedCanvases.clear(),
                        this.cachedPatterns.clear());
                      for (const u of this._cachedBitmapsMap.values()) {
                        for (const f of u.values())
                          typeof HTMLCanvasElement < "u" &&
                            f instanceof HTMLCanvasElement &&
                            (f.width = f.height = 0);
                        u.clear();
                      }
                      (this._cachedBitmapsMap.clear(), this.#e());
                    }
                    #e() {
                      if (this.pageColors) {
                        const u = this.filterFactory.addHCMFilter(
                          this.pageColors.foreground,
                          this.pageColors.background,
                        );
                        if (u !== "none") {
                          const f = this.ctx.filter;
                          ((this.ctx.filter = u),
                            this.ctx.drawImage(this.ctx.canvas, 0, 0),
                            (this.ctx.filter = f));
                        }
                      }
                    }
                    _scaleImage(u, f) {
                      const v = u.width,
                        F = u.height;
                      let L = Math.max(Math.hypot(f[0], f[1]), 1),
                        N = Math.max(Math.hypot(f[2], f[3]), 1),
                        R = v,
                        o = F,
                        b = "prescale1",
                        S,
                        x;
                      for (; (L > 2 && R > 1) || (N > 2 && o > 1);) {
                        let P = R,
                          B = o;
                        (L > 2 &&
                          R > 1 &&
                          ((P =
                            R >= 16384
                              ? Math.floor(R / 2) - 1 || 1
                              : Math.ceil(R / 2)),
                          (L /= R / P)),
                          N > 2 &&
                            o > 1 &&
                            ((B =
                              o >= 16384
                                ? Math.floor(o / 2) - 1 || 1
                                : Math.ceil(o) / 2),
                            (N /= o / B)),
                          (S = this.cachedCanvases.getCanvas(b, P, B)),
                          (x = S.context),
                          x.clearRect(0, 0, P, B),
                          x.drawImage(u, 0, 0, R, o, 0, 0, P, B),
                          (u = S.canvas),
                          (R = P),
                          (o = B),
                          (b = b === "prescale1" ? "prescale2" : "prescale1"));
                      }
                      return { img: u, paintWidth: R, paintHeight: o };
                    }
                    _createMaskCanvas(u) {
                      const f = this.ctx,
                        { width: v, height: F } = u,
                        L = this.current.fillColor,
                        N = this.current.patternFill,
                        R = (0, p.getCurrentTransform)(f);
                      let o, b, S, x;
                      if ((u.bitmap || u.data) && u.count > 1) {
                        const lt = u.bitmap || u.data.buffer;
                        ((b = JSON.stringify(N ? R : [R.slice(0, 4), L])),
                          (o = this._cachedBitmapsMap.get(lt)),
                          o ||
                            ((o = new Map()),
                            this._cachedBitmapsMap.set(lt, o)));
                        const ct = o.get(b);
                        if (ct && !N) {
                          const ht = Math.round(Math.min(R[0], R[2]) + R[4]),
                            dt = Math.round(Math.min(R[1], R[3]) + R[5]);
                          return { canvas: ct, offsetX: ht, offsetY: dt };
                        }
                        S = ct;
                      }
                      S ||
                        ((x = this.cachedCanvases.getCanvas(
                          "maskCanvas",
                          v,
                          F,
                        )),
                        C(x.context, u));
                      let P = a.Util.transform(R, [1 / v, 0, 0, -1 / F, 0, 0]);
                      P = a.Util.transform(P, [1, 0, 0, 1, 0, -F]);
                      const B = a.Util.applyTransform([0, 0], P),
                        H = a.Util.applyTransform([v, F], P),
                        z = a.Util.normalizeRect([B[0], B[1], H[0], H[1]]),
                        st = Math.round(z[2] - z[0]) || 1,
                        Y = Math.round(z[3] - z[1]) || 1,
                        X = this.cachedCanvases.getCanvas("fillCanvas", st, Y),
                        J = X.context,
                        Q = Math.min(B[0], H[0]),
                        et = Math.min(B[1], H[1]);
                      (J.translate(-Q, -et),
                        J.transform(...P),
                        S ||
                          ((S = this._scaleImage(
                            x.canvas,
                            (0, p.getCurrentTransformInverse)(J),
                          )),
                          (S = S.img),
                          o && N && o.set(b, S)),
                        (J.imageSmoothingEnabled = nt(
                          (0, p.getCurrentTransform)(J),
                          u.interpolate,
                        )),
                        m(J, S, 0, 0, S.width, S.height, 0, 0, v, F),
                        (J.globalCompositeOperation = "source-in"));
                      const at = a.Util.transform(
                        (0, p.getCurrentTransformInverse)(J),
                        [1, 0, 0, 1, -Q, -et],
                      );
                      return (
                        (J.fillStyle = N
                          ? L.getPattern(f, this, at, k.PathType.FILL)
                          : L),
                        J.fillRect(0, 0, v, F),
                        o &&
                          !N &&
                          (this.cachedCanvases.delete("fillCanvas"),
                          o.set(b, X.canvas)),
                        {
                          canvas: X.canvas,
                          offsetX: Math.round(Q),
                          offsetY: Math.round(et),
                        }
                      );
                    }
                    setLineWidth(u) {
                      (u !== this.current.lineWidth &&
                        (this._cachedScaleForStroking[0] = -1),
                        (this.current.lineWidth = u),
                        (this.ctx.lineWidth = u));
                    }
                    setLineCap(u) {
                      this.ctx.lineCap = Z[u];
                    }
                    setLineJoin(u) {
                      this.ctx.lineJoin = tt[u];
                    }
                    setMiterLimit(u) {
                      this.ctx.miterLimit = u;
                    }
                    setDash(u, f) {
                      const v = this.ctx;
                      v.setLineDash !== void 0 &&
                        (v.setLineDash(u), (v.lineDashOffset = f));
                    }
                    setRenderingIntent(u) {}
                    setFlatness(u) {}
                    setGState(u) {
                      for (const [f, v] of u)
                        switch (f) {
                          case "LW":
                            this.setLineWidth(v);
                            break;
                          case "LC":
                            this.setLineCap(v);
                            break;
                          case "LJ":
                            this.setLineJoin(v);
                            break;
                          case "ML":
                            this.setMiterLimit(v);
                            break;
                          case "D":
                            this.setDash(v[0], v[1]);
                            break;
                          case "RI":
                            this.setRenderingIntent(v);
                            break;
                          case "FL":
                            this.setFlatness(v);
                            break;
                          case "Font":
                            this.setFont(v[0], v[1]);
                            break;
                          case "CA":
                            this.current.strokeAlpha = v;
                            break;
                          case "ca":
                            ((this.current.fillAlpha = v),
                              (this.ctx.globalAlpha = v));
                            break;
                          case "BM":
                            this.ctx.globalCompositeOperation = v;
                            break;
                          case "SMask":
                            ((this.current.activeSMask = v
                              ? this.tempSMask
                              : null),
                              (this.tempSMask = null),
                              this.checkSMaskState());
                            break;
                          case "TR":
                            this.ctx.filter = this.current.transferMaps =
                              this.filterFactory.addFilter(v);
                            break;
                        }
                    }
                    get inSMaskMode() {
                      return !!this.suspendedCtx;
                    }
                    checkSMaskState() {
                      const u = this.inSMaskMode;
                      this.current.activeSMask && !u
                        ? this.beginSMaskMode()
                        : !this.current.activeSMask && u && this.endSMaskMode();
                    }
                    beginSMaskMode() {
                      if (this.inSMaskMode)
                        throw new Error(
                          "beginSMaskMode called while already in smask mode",
                        );
                      const u = this.ctx.canvas.width,
                        f = this.ctx.canvas.height,
                        v = "smaskGroupAt" + this.groupLevel,
                        F = this.cachedCanvases.getCanvas(v, u, f);
                      ((this.suspendedCtx = this.ctx), (this.ctx = F.context));
                      const L = this.ctx;
                      (L.setTransform(
                        ...(0, p.getCurrentTransform)(this.suspendedCtx),
                      ),
                        g(this.suspendedCtx, L),
                        n(L, this.suspendedCtx),
                        this.setGState([
                          ["BM", "source-over"],
                          ["ca", 1],
                          ["CA", 1],
                        ]));
                    }
                    endSMaskMode() {
                      if (!this.inSMaskMode)
                        throw new Error(
                          "endSMaskMode called while not in smask mode",
                        );
                      (this.ctx._removeMirroring(),
                        g(this.ctx, this.suspendedCtx),
                        (this.ctx = this.suspendedCtx),
                        (this.suspendedCtx = null));
                    }
                    compose(u) {
                      if (!this.current.activeSMask) return;
                      u
                        ? ((u[0] = Math.floor(u[0])),
                          (u[1] = Math.floor(u[1])),
                          (u[2] = Math.ceil(u[2])),
                          (u[3] = Math.ceil(u[3])))
                        : (u = [
                            0,
                            0,
                            this.ctx.canvas.width,
                            this.ctx.canvas.height,
                          ]);
                      const f = this.current.activeSMask,
                        v = this.suspendedCtx;
                      (G(v, f, this.ctx, u),
                        this.ctx.save(),
                        this.ctx.setTransform(1, 0, 0, 1, 0, 0),
                        this.ctx.clearRect(
                          0,
                          0,
                          this.ctx.canvas.width,
                          this.ctx.canvas.height,
                        ),
                        this.ctx.restore());
                    }
                    save() {
                      this.inSMaskMode
                        ? (g(this.ctx, this.suspendedCtx),
                          this.suspendedCtx.save())
                        : this.ctx.save();
                      const u = this.current;
                      (this.stateStack.push(u), (this.current = u.clone()));
                    }
                    restore() {
                      (this.stateStack.length === 0 &&
                        this.inSMaskMode &&
                        this.endSMaskMode(),
                        this.stateStack.length !== 0 &&
                          ((this.current = this.stateStack.pop()),
                          this.inSMaskMode
                            ? (this.suspendedCtx.restore(),
                              g(this.suspendedCtx, this.ctx))
                            : this.ctx.restore(),
                          this.checkSMaskState(),
                          (this.pendingClip = null),
                          (this._cachedScaleForStroking[0] = -1),
                          (this._cachedGetSinglePixelWidth = null)));
                    }
                    transform(u, f, v, F, L, N) {
                      (this.ctx.transform(u, f, v, F, L, N),
                        (this._cachedScaleForStroking[0] = -1),
                        (this._cachedGetSinglePixelWidth = null));
                    }
                    constructPath(u, f, v) {
                      const F = this.ctx,
                        L = this.current;
                      let N = L.x,
                        R = L.y,
                        o,
                        b;
                      const S = (0, p.getCurrentTransform)(F),
                        x =
                          (S[0] === 0 && S[3] === 0) ||
                          (S[1] === 0 && S[2] === 0),
                        P = x ? v.slice(0) : null;
                      for (let B = 0, H = 0, z = u.length; B < z; B++)
                        switch (u[B] | 0) {
                          case a.OPS.rectangle:
                            ((N = f[H++]), (R = f[H++]));
                            const st = f[H++],
                              Y = f[H++],
                              X = N + st,
                              J = R + Y;
                            (F.moveTo(N, R),
                              st === 0 || Y === 0
                                ? F.lineTo(X, J)
                                : (F.lineTo(X, R),
                                  F.lineTo(X, J),
                                  F.lineTo(N, J)),
                              x || L.updateRectMinMax(S, [N, R, X, J]),
                              F.closePath());
                            break;
                          case a.OPS.moveTo:
                            ((N = f[H++]),
                              (R = f[H++]),
                              F.moveTo(N, R),
                              x || L.updatePathMinMax(S, N, R));
                            break;
                          case a.OPS.lineTo:
                            ((N = f[H++]),
                              (R = f[H++]),
                              F.lineTo(N, R),
                              x || L.updatePathMinMax(S, N, R));
                            break;
                          case a.OPS.curveTo:
                            ((o = N),
                              (b = R),
                              (N = f[H + 4]),
                              (R = f[H + 5]),
                              F.bezierCurveTo(
                                f[H],
                                f[H + 1],
                                f[H + 2],
                                f[H + 3],
                                N,
                                R,
                              ),
                              L.updateCurvePathMinMax(
                                S,
                                o,
                                b,
                                f[H],
                                f[H + 1],
                                f[H + 2],
                                f[H + 3],
                                N,
                                R,
                                P,
                              ),
                              (H += 6));
                            break;
                          case a.OPS.curveTo2:
                            ((o = N),
                              (b = R),
                              F.bezierCurveTo(
                                N,
                                R,
                                f[H],
                                f[H + 1],
                                f[H + 2],
                                f[H + 3],
                              ),
                              L.updateCurvePathMinMax(
                                S,
                                o,
                                b,
                                N,
                                R,
                                f[H],
                                f[H + 1],
                                f[H + 2],
                                f[H + 3],
                                P,
                              ),
                              (N = f[H + 2]),
                              (R = f[H + 3]),
                              (H += 4));
                            break;
                          case a.OPS.curveTo3:
                            ((o = N),
                              (b = R),
                              (N = f[H + 2]),
                              (R = f[H + 3]),
                              F.bezierCurveTo(f[H], f[H + 1], N, R, N, R),
                              L.updateCurvePathMinMax(
                                S,
                                o,
                                b,
                                f[H],
                                f[H + 1],
                                N,
                                R,
                                N,
                                R,
                                P,
                              ),
                              (H += 4));
                            break;
                          case a.OPS.closePath:
                            F.closePath();
                            break;
                        }
                      (x && L.updateScalingPathMinMax(S, P),
                        L.setCurrentPoint(N, R));
                    }
                    closePath() {
                      this.ctx.closePath();
                    }
                    stroke(u = !0) {
                      const f = this.ctx,
                        v = this.current.strokeColor;
                      ((f.globalAlpha = this.current.strokeAlpha),
                        this.contentVisible &&
                          (typeof v == "object" && v?.getPattern
                            ? (f.save(),
                              (f.strokeStyle = v.getPattern(
                                f,
                                this,
                                (0, p.getCurrentTransformInverse)(f),
                                k.PathType.STROKE,
                              )),
                              this.rescaleAndStroke(!1),
                              f.restore())
                            : this.rescaleAndStroke(!0)),
                        u &&
                          this.consumePath(
                            this.current.getClippedPathBoundingBox(),
                          ),
                        (f.globalAlpha = this.current.fillAlpha));
                    }
                    closeStroke() {
                      (this.closePath(), this.stroke());
                    }
                    fill(u = !0) {
                      const f = this.ctx,
                        v = this.current.fillColor,
                        F = this.current.patternFill;
                      let L = !1;
                      F &&
                        (f.save(),
                        (f.fillStyle = v.getPattern(
                          f,
                          this,
                          (0, p.getCurrentTransformInverse)(f),
                          k.PathType.FILL,
                        )),
                        (L = !0));
                      const N = this.current.getClippedPathBoundingBox();
                      (this.contentVisible &&
                        N !== null &&
                        (this.pendingEOFill
                          ? (f.fill("evenodd"), (this.pendingEOFill = !1))
                          : f.fill()),
                        L && f.restore(),
                        u && this.consumePath(N));
                    }
                    eoFill() {
                      ((this.pendingEOFill = !0), this.fill());
                    }
                    fillStroke() {
                      (this.fill(!1), this.stroke(!1), this.consumePath());
                    }
                    eoFillStroke() {
                      ((this.pendingEOFill = !0), this.fillStroke());
                    }
                    closeFillStroke() {
                      (this.closePath(), this.fillStroke());
                    }
                    closeEOFillStroke() {
                      ((this.pendingEOFill = !0),
                        this.closePath(),
                        this.fillStroke());
                    }
                    endPath() {
                      this.consumePath();
                    }
                    clip() {
                      this.pendingClip = rt;
                    }
                    eoClip() {
                      this.pendingClip = K;
                    }
                    beginText() {
                      ((this.current.textMatrix = a.IDENTITY_MATRIX),
                        (this.current.textMatrixScale = 1),
                        (this.current.x = this.current.lineX = 0),
                        (this.current.y = this.current.lineY = 0));
                    }
                    endText() {
                      const u = this.pendingTextPaths,
                        f = this.ctx;
                      if (u === void 0) {
                        f.beginPath();
                        return;
                      }
                      (f.save(), f.beginPath());
                      for (const v of u)
                        (f.setTransform(...v.transform),
                          f.translate(v.x, v.y),
                          v.addToPath(f, v.fontSize));
                      (f.restore(),
                        f.clip(),
                        f.beginPath(),
                        delete this.pendingTextPaths);
                    }
                    setCharSpacing(u) {
                      this.current.charSpacing = u;
                    }
                    setWordSpacing(u) {
                      this.current.wordSpacing = u;
                    }
                    setHScale(u) {
                      this.current.textHScale = u / 100;
                    }
                    setLeading(u) {
                      this.current.leading = -u;
                    }
                    setFont(u, f) {
                      const v = this.commonObjs.get(u),
                        F = this.current;
                      if (!v) throw new Error(`Can't find font for ${u}`);
                      if (
                        ((F.fontMatrix =
                          v.fontMatrix || a.FONT_IDENTITY_MATRIX),
                        (F.fontMatrix[0] === 0 || F.fontMatrix[3] === 0) &&
                          (0, a.warn)("Invalid font matrix for font " + u),
                        f < 0
                          ? ((f = -f), (F.fontDirection = -1))
                          : (F.fontDirection = 1),
                        (this.current.font = v),
                        (this.current.fontSize = f),
                        v.isType3Font)
                      )
                        return;
                      const L = v.loadedName || "sans-serif",
                        N =
                          v.systemFontInfo?.css || `"${L}", ${v.fallbackName}`;
                      let R = "normal";
                      v.black ? (R = "900") : v.bold && (R = "bold");
                      const o = v.italic ? "italic" : "normal";
                      let b = f;
                      (f < j ? (b = j) : f > D && (b = D),
                        (this.current.fontSizeScale = f / b),
                        (this.ctx.font = `${o} ${R} ${b}px ${N}`));
                    }
                    setTextRenderingMode(u) {
                      this.current.textRenderingMode = u;
                    }
                    setTextRise(u) {
                      this.current.textRise = u;
                    }
                    moveText(u, f) {
                      ((this.current.x = this.current.lineX += u),
                        (this.current.y = this.current.lineY += f));
                    }
                    setLeadingMoveText(u, f) {
                      (this.setLeading(-f), this.moveText(u, f));
                    }
                    setTextMatrix(u, f, v, F, L, N) {
                      ((this.current.textMatrix = [u, f, v, F, L, N]),
                        (this.current.textMatrixScale = Math.hypot(u, f)),
                        (this.current.x = this.current.lineX = 0),
                        (this.current.y = this.current.lineY = 0));
                    }
                    nextLine() {
                      this.moveText(0, this.current.leading);
                    }
                    paintChar(u, f, v, F) {
                      const L = this.ctx,
                        N = this.current,
                        R = N.font,
                        o = N.textRenderingMode,
                        b = N.fontSize / N.fontSizeScale,
                        S = o & a.TextRenderingMode.FILL_STROKE_MASK,
                        x = !!(o & a.TextRenderingMode.ADD_TO_PATH_FLAG),
                        P = N.patternFill && !R.missingFile;
                      let B;
                      ((R.disableFontFace || x || P) &&
                        (B = R.getPathGenerator(this.commonObjs, u)),
                        R.disableFontFace || P
                          ? (L.save(),
                            L.translate(f, v),
                            L.beginPath(),
                            B(L, b),
                            F && L.setTransform(...F),
                            (S === a.TextRenderingMode.FILL ||
                              S === a.TextRenderingMode.FILL_STROKE) &&
                              L.fill(),
                            (S === a.TextRenderingMode.STROKE ||
                              S === a.TextRenderingMode.FILL_STROKE) &&
                              L.stroke(),
                            L.restore())
                          : ((S === a.TextRenderingMode.FILL ||
                              S === a.TextRenderingMode.FILL_STROKE) &&
                              L.fillText(u, f, v),
                            (S === a.TextRenderingMode.STROKE ||
                              S === a.TextRenderingMode.FILL_STROKE) &&
                              L.strokeText(u, f, v)),
                        x &&
                          (this.pendingTextPaths ||= []).push({
                            transform: (0, p.getCurrentTransform)(L),
                            x: f,
                            y: v,
                            fontSize: b,
                            addToPath: B,
                          }));
                    }
                    get isFontSubpixelAAEnabled() {
                      const { context: u } = this.cachedCanvases.getCanvas(
                        "isFontSubpixelAAEnabled",
                        10,
                        10,
                      );
                      (u.scale(1.5, 1), u.fillText("I", 0, 10));
                      const f = u.getImageData(0, 0, 10, 10).data;
                      let v = !1;
                      for (let F = 3; F < f.length; F += 4)
                        if (f[F] > 0 && f[F] < 255) {
                          v = !0;
                          break;
                        }
                      return (0, a.shadow)(this, "isFontSubpixelAAEnabled", v);
                    }
                    showText(u) {
                      const f = this.current,
                        v = f.font;
                      if (v.isType3Font) return this.showType3Text(u);
                      const F = f.fontSize;
                      if (F === 0) return;
                      const L = this.ctx,
                        N = f.fontSizeScale,
                        R = f.charSpacing,
                        o = f.wordSpacing,
                        b = f.fontDirection,
                        S = f.textHScale * b,
                        x = u.length,
                        P = v.vertical,
                        B = P ? 1 : -1,
                        H = v.defaultVMetrics,
                        z = F * f.fontMatrix[0],
                        st =
                          f.textRenderingMode === a.TextRenderingMode.FILL &&
                          !v.disableFontFace &&
                          !f.patternFill;
                      (L.save(),
                        L.transform(...f.textMatrix),
                        L.translate(f.x, f.y + f.textRise),
                        b > 0 ? L.scale(S, -1) : L.scale(S, 1));
                      let Y;
                      if (f.patternFill) {
                        L.save();
                        const at = f.fillColor.getPattern(
                          L,
                          this,
                          (0, p.getCurrentTransformInverse)(L),
                          k.PathType.FILL,
                        );
                        ((Y = (0, p.getCurrentTransform)(L)),
                          L.restore(),
                          (L.fillStyle = at));
                      }
                      let X = f.lineWidth;
                      const J = f.textMatrixScale;
                      if (J === 0 || X === 0) {
                        const at =
                          f.textRenderingMode &
                          a.TextRenderingMode.FILL_STROKE_MASK;
                        (at === a.TextRenderingMode.STROKE ||
                          at === a.TextRenderingMode.FILL_STROKE) &&
                          (X = this.getSinglePixelWidth());
                      } else X /= J;
                      if (
                        (N !== 1 && (L.scale(N, N), (X /= N)),
                        (L.lineWidth = X),
                        v.isInvalidPDFjsFont)
                      ) {
                        const at = [];
                        let lt = 0;
                        for (const ct of u)
                          (at.push(ct.unicode), (lt += ct.width));
                        (L.fillText(at.join(""), 0, 0),
                          (f.x += lt * z * S),
                          L.restore(),
                          this.compose());
                        return;
                      }
                      let Q = 0,
                        et;
                      for (et = 0; et < x; ++et) {
                        const at = u[et];
                        if (typeof at == "number") {
                          Q += (B * at * F) / 1e3;
                          continue;
                        }
                        let lt = !1;
                        const ct = (at.isSpace ? o : 0) + R,
                          ht = at.fontChar,
                          dt = at.accent;
                        let ut,
                          At,
                          gt = at.width;
                        if (P) {
                          const mt = at.vmetric || H,
                            St = -(at.vmetric ? mt[1] : gt * 0.5) * z,
                            Et = mt[2] * z;
                          ((gt = mt ? -mt[0] : gt),
                            (ut = St / N),
                            (At = (Q + Et) / N));
                        } else ((ut = Q / N), (At = 0));
                        if (v.remeasure && gt > 0) {
                          const mt = ((L.measureText(ht).width * 1e3) / F) * N;
                          if (gt < mt && this.isFontSubpixelAAEnabled) {
                            const St = gt / mt;
                            ((lt = !0), L.save(), L.scale(St, 1), (ut /= St));
                          } else
                            gt !== mt && (ut += (((gt - mt) / 2e3) * F) / N);
                        }
                        if (
                          this.contentVisible &&
                          (at.isInFont || v.missingFile)
                        ) {
                          if (st && !dt) L.fillText(ht, ut, At);
                          else if ((this.paintChar(ht, ut, At, Y), dt)) {
                            const mt = ut + (F * dt.offset.x) / N,
                              St = At - (F * dt.offset.y) / N;
                            this.paintChar(dt.fontChar, mt, St, Y);
                          }
                        }
                        const wt = P ? gt * z - ct * b : gt * z + ct * b;
                        ((Q += wt), lt && L.restore());
                      }
                      (P ? (f.y -= Q) : (f.x += Q * S),
                        L.restore(),
                        this.compose());
                    }
                    showType3Text(u) {
                      const f = this.ctx,
                        v = this.current,
                        F = v.font,
                        L = v.fontSize,
                        N = v.fontDirection,
                        R = F.vertical ? 1 : -1,
                        o = v.charSpacing,
                        b = v.wordSpacing,
                        S = v.textHScale * N,
                        x = v.fontMatrix || a.FONT_IDENTITY_MATRIX,
                        P = u.length,
                        B =
                          v.textRenderingMode === a.TextRenderingMode.INVISIBLE;
                      let H, z, st, Y;
                      if (!(B || L === 0)) {
                        for (
                          this._cachedScaleForStroking[0] = -1,
                            this._cachedGetSinglePixelWidth = null,
                            f.save(),
                            f.transform(...v.textMatrix),
                            f.translate(v.x, v.y),
                            f.scale(S, N),
                            H = 0;
                          H < P;
                          ++H
                        ) {
                          if (((z = u[H]), typeof z == "number")) {
                            ((Y = (R * z * L) / 1e3),
                              this.ctx.translate(Y, 0),
                              (v.x += Y * S));
                            continue;
                          }
                          const X = (z.isSpace ? b : 0) + o,
                            J = F.charProcOperatorList[z.operatorListId];
                          if (!J) {
                            (0, a.warn)(
                              `Type3 character "${z.operatorListId}" is not available.`,
                            );
                            continue;
                          }
                          (this.contentVisible &&
                            ((this.processingType3 = z),
                            this.save(),
                            f.scale(L, L),
                            f.transform(...x),
                            this.executeOperatorList(J),
                            this.restore()),
                            (st =
                              a.Util.applyTransform([z.width, 0], x)[0] * L +
                              X),
                            f.translate(st, 0),
                            (v.x += st * S));
                        }
                        (f.restore(), (this.processingType3 = null));
                      }
                    }
                    setCharWidth(u, f) {}
                    setCharWidthAndBounds(u, f, v, F, L, N) {
                      (this.ctx.rect(v, F, L - v, N - F),
                        this.ctx.clip(),
                        this.endPath());
                    }
                    getColorN_Pattern(u) {
                      let f;
                      if (u[0] === "TilingPattern") {
                        const v = u[1],
                          F =
                            this.baseTransform ||
                            (0, p.getCurrentTransform)(this.ctx),
                          L = {
                            createCanvasGraphics: (N) =>
                              new I(
                                N,
                                this.commonObjs,
                                this.objs,
                                this.canvasFactory,
                                this.filterFactory,
                                {
                                  optionalContentConfig:
                                    this.optionalContentConfig,
                                  markedContentStack: this.markedContentStack,
                                },
                              ),
                          };
                        f = new k.TilingPattern(u, v, this.ctx, L, F);
                      } else f = this._getPattern(u[1], u[2]);
                      return f;
                    }
                    setStrokeColorN() {
                      this.current.strokeColor =
                        this.getColorN_Pattern(arguments);
                    }
                    setFillColorN() {
                      ((this.current.fillColor =
                        this.getColorN_Pattern(arguments)),
                        (this.current.patternFill = !0));
                    }
                    setStrokeRGBColor(u, f, v) {
                      const F = a.Util.makeHexColor(u, f, v);
                      ((this.ctx.strokeStyle = F),
                        (this.current.strokeColor = F));
                    }
                    setFillRGBColor(u, f, v) {
                      const F = a.Util.makeHexColor(u, f, v);
                      ((this.ctx.fillStyle = F),
                        (this.current.fillColor = F),
                        (this.current.patternFill = !1));
                    }
                    _getPattern(u, f = null) {
                      let v;
                      return (
                        this.cachedPatterns.has(u)
                          ? (v = this.cachedPatterns.get(u))
                          : ((v = (0, k.getShadingPattern)(this.getObject(u))),
                            this.cachedPatterns.set(u, v)),
                        f && (v.matrix = f),
                        v
                      );
                    }
                    shadingFill(u) {
                      if (!this.contentVisible) return;
                      const f = this.ctx;
                      this.save();
                      const v = this._getPattern(u);
                      f.fillStyle = v.getPattern(
                        f,
                        this,
                        (0, p.getCurrentTransformInverse)(f),
                        k.PathType.SHADING,
                      );
                      const F = (0, p.getCurrentTransformInverse)(f);
                      if (F) {
                        const { width: L, height: N } = f.canvas,
                          [R, o, b, S] = a.Util.getAxialAlignedBoundingBox(
                            [0, 0, L, N],
                            F,
                          );
                        this.ctx.fillRect(R, o, b - R, S - o);
                      } else this.ctx.fillRect(-1e10, -1e10, 2e10, 2e10);
                      (this.compose(this.current.getClippedPathBoundingBox()),
                        this.restore());
                    }
                    beginInlineImage() {
                      (0, a.unreachable)("Should not call beginInlineImage");
                    }
                    beginImageData() {
                      (0, a.unreachable)("Should not call beginImageData");
                    }
                    paintFormXObjectBegin(u, f) {
                      if (
                        this.contentVisible &&
                        (this.save(),
                        this.baseTransformStack.push(this.baseTransform),
                        Array.isArray(u) &&
                          u.length === 6 &&
                          this.transform(...u),
                        (this.baseTransform = (0, p.getCurrentTransform)(
                          this.ctx,
                        )),
                        f)
                      ) {
                        const v = f[2] - f[0],
                          F = f[3] - f[1];
                        (this.ctx.rect(f[0], f[1], v, F),
                          this.current.updateRectMinMax(
                            (0, p.getCurrentTransform)(this.ctx),
                            f,
                          ),
                          this.clip(),
                          this.endPath());
                      }
                    }
                    paintFormXObjectEnd() {
                      this.contentVisible &&
                        (this.restore(),
                        (this.baseTransform = this.baseTransformStack.pop()));
                    }
                    beginGroup(u) {
                      if (!this.contentVisible) return;
                      (this.save(),
                        this.inSMaskMode &&
                          (this.endSMaskMode(),
                          (this.current.activeSMask = null)));
                      const f = this.ctx;
                      (u.isolated ||
                        (0, a.info)("TODO: Support non-isolated groups."),
                        u.knockout &&
                          (0, a.warn)("Knockout groups not supported."));
                      const v = (0, p.getCurrentTransform)(f);
                      if ((u.matrix && f.transform(...u.matrix), !u.bbox))
                        throw new Error("Bounding box is required.");
                      let F = a.Util.getAxialAlignedBoundingBox(
                        u.bbox,
                        (0, p.getCurrentTransform)(f),
                      );
                      const L = [0, 0, f.canvas.width, f.canvas.height];
                      F = a.Util.intersect(F, L) || [0, 0, 0, 0];
                      const N = Math.floor(F[0]),
                        R = Math.floor(F[1]);
                      let o = Math.max(Math.ceil(F[2]) - N, 1),
                        b = Math.max(Math.ceil(F[3]) - R, 1),
                        S = 1,
                        x = 1;
                      (o > s && ((S = o / s), (o = s)),
                        b > s && ((x = b / s), (b = s)),
                        this.current.startNewPathAndClipBox([0, 0, o, b]));
                      let P = "groupAt" + this.groupLevel;
                      u.smask && (P += "_smask_" + (this.smaskCounter++ % 2));
                      const B = this.cachedCanvases.getCanvas(P, o, b),
                        H = B.context;
                      (H.scale(1 / S, 1 / x),
                        H.translate(-N, -R),
                        H.transform(...v),
                        u.smask
                          ? this.smaskStack.push({
                              canvas: B.canvas,
                              context: H,
                              offsetX: N,
                              offsetY: R,
                              scaleX: S,
                              scaleY: x,
                              subtype: u.smask.subtype,
                              backdrop: u.smask.backdrop,
                              transferMap: u.smask.transferMap || null,
                              startTransformInverse: null,
                            })
                          : (f.setTransform(1, 0, 0, 1, 0, 0),
                            f.translate(N, R),
                            f.scale(S, x),
                            f.save()),
                        g(f, H),
                        (this.ctx = H),
                        this.setGState([
                          ["BM", "source-over"],
                          ["ca", 1],
                          ["CA", 1],
                        ]),
                        this.groupStack.push(f),
                        this.groupLevel++);
                    }
                    endGroup(u) {
                      if (!this.contentVisible) return;
                      this.groupLevel--;
                      const f = this.ctx,
                        v = this.groupStack.pop();
                      if (
                        ((this.ctx = v),
                        (this.ctx.imageSmoothingEnabled = !1),
                        u.smask)
                      )
                        ((this.tempSMask = this.smaskStack.pop()),
                          this.restore());
                      else {
                        this.ctx.restore();
                        const F = (0, p.getCurrentTransform)(this.ctx);
                        (this.restore(),
                          this.ctx.save(),
                          this.ctx.setTransform(...F));
                        const L = a.Util.getAxialAlignedBoundingBox(
                          [0, 0, f.canvas.width, f.canvas.height],
                          F,
                        );
                        (this.ctx.drawImage(f.canvas, 0, 0),
                          this.ctx.restore(),
                          this.compose(L));
                      }
                    }
                    beginAnnotation(u, f, v, F, L) {
                      if (
                        (this.#t(),
                        E(this.ctx),
                        this.ctx.save(),
                        this.save(),
                        this.baseTransform &&
                          this.ctx.setTransform(...this.baseTransform),
                        Array.isArray(f) && f.length === 4)
                      ) {
                        const N = f[2] - f[0],
                          R = f[3] - f[1];
                        if (L && this.annotationCanvasMap) {
                          ((v = v.slice()),
                            (v[4] -= f[0]),
                            (v[5] -= f[1]),
                            (f = f.slice()),
                            (f[0] = f[1] = 0),
                            (f[2] = N),
                            (f[3] = R));
                          const [o, b] = a.Util.singularValueDecompose2dScale(
                              (0, p.getCurrentTransform)(this.ctx),
                            ),
                            { viewportScale: S } = this,
                            x = Math.ceil(N * this.outputScaleX * S),
                            P = Math.ceil(R * this.outputScaleY * S);
                          this.annotationCanvas = this.canvasFactory.create(
                            x,
                            P,
                          );
                          const { canvas: B, context: H } =
                            this.annotationCanvas;
                          (this.annotationCanvasMap.set(u, B),
                            (this.annotationCanvas.savedCtx = this.ctx),
                            (this.ctx = H),
                            this.ctx.save(),
                            this.ctx.setTransform(o, 0, 0, -b, 0, R * b),
                            E(this.ctx));
                        } else
                          (E(this.ctx),
                            this.ctx.rect(f[0], f[1], N, R),
                            this.ctx.clip(),
                            this.endPath());
                      }
                      ((this.current = new w(
                        this.ctx.canvas.width,
                        this.ctx.canvas.height,
                      )),
                        this.transform(...v),
                        this.transform(...F));
                    }
                    endAnnotation() {
                      this.annotationCanvas &&
                        (this.ctx.restore(),
                        this.#e(),
                        (this.ctx = this.annotationCanvas.savedCtx),
                        delete this.annotationCanvas.savedCtx,
                        delete this.annotationCanvas);
                    }
                    paintImageMaskXObject(u) {
                      if (!this.contentVisible) return;
                      const f = u.count;
                      ((u = this.getObject(u.data, u)), (u.count = f));
                      const v = this.ctx,
                        F = this.processingType3;
                      if (
                        F &&
                        (F.compiled === void 0 && (F.compiled = l(u)),
                        F.compiled)
                      ) {
                        F.compiled(v);
                        return;
                      }
                      const L = this._createMaskCanvas(u),
                        N = L.canvas;
                      (v.save(),
                        v.setTransform(1, 0, 0, 1, 0, 0),
                        v.drawImage(N, L.offsetX, L.offsetY),
                        v.restore(),
                        this.compose());
                    }
                    paintImageMaskXObjectRepeat(u, f, v = 0, F = 0, L, N) {
                      if (!this.contentVisible) return;
                      u = this.getObject(u.data, u);
                      const R = this.ctx;
                      R.save();
                      const o = (0, p.getCurrentTransform)(R);
                      R.transform(f, v, F, L, 0, 0);
                      const b = this._createMaskCanvas(u);
                      R.setTransform(
                        1,
                        0,
                        0,
                        1,
                        b.offsetX - o[4],
                        b.offsetY - o[5],
                      );
                      for (let S = 0, x = N.length; S < x; S += 2) {
                        const P = a.Util.transform(o, [
                            f,
                            v,
                            F,
                            L,
                            N[S],
                            N[S + 1],
                          ]),
                          [B, H] = a.Util.applyTransform([0, 0], P);
                        R.drawImage(b.canvas, B, H);
                      }
                      (R.restore(), this.compose());
                    }
                    paintImageMaskXObjectGroup(u) {
                      if (!this.contentVisible) return;
                      const f = this.ctx,
                        v = this.current.fillColor,
                        F = this.current.patternFill;
                      for (const L of u) {
                        const {
                            data: N,
                            width: R,
                            height: o,
                            transform: b,
                          } = L,
                          S = this.cachedCanvases.getCanvas("maskCanvas", R, o),
                          x = S.context;
                        x.save();
                        const P = this.getObject(N, L);
                        (C(x, P),
                          (x.globalCompositeOperation = "source-in"),
                          (x.fillStyle = F
                            ? v.getPattern(
                                x,
                                this,
                                (0, p.getCurrentTransformInverse)(f),
                                k.PathType.FILL,
                              )
                            : v),
                          x.fillRect(0, 0, R, o),
                          x.restore(),
                          f.save(),
                          f.transform(...b),
                          f.scale(1, -1),
                          m(f, S.canvas, 0, 0, R, o, 0, -1, 1, 1),
                          f.restore());
                      }
                      this.compose();
                    }
                    paintImageXObject(u) {
                      if (!this.contentVisible) return;
                      const f = this.getObject(u);
                      if (!f) {
                        (0, a.warn)("Dependent image isn't ready yet");
                        return;
                      }
                      this.paintInlineImageXObject(f);
                    }
                    paintImageXObjectRepeat(u, f, v, F) {
                      if (!this.contentVisible) return;
                      const L = this.getObject(u);
                      if (!L) {
                        (0, a.warn)("Dependent image isn't ready yet");
                        return;
                      }
                      const N = L.width,
                        R = L.height,
                        o = [];
                      for (let b = 0, S = F.length; b < S; b += 2)
                        o.push({
                          transform: [f, 0, 0, v, F[b], F[b + 1]],
                          x: 0,
                          y: 0,
                          w: N,
                          h: R,
                        });
                      this.paintInlineImageXObjectGroup(L, o);
                    }
                    applyTransferMapsToCanvas(u) {
                      return (
                        this.current.transferMaps !== "none" &&
                          ((u.filter = this.current.transferMaps),
                          u.drawImage(u.canvas, 0, 0),
                          (u.filter = "none")),
                        u.canvas
                      );
                    }
                    applyTransferMapsToBitmap(u) {
                      if (this.current.transferMaps === "none") return u.bitmap;
                      const { bitmap: f, width: v, height: F } = u,
                        L = this.cachedCanvases.getCanvas("inlineImage", v, F),
                        N = L.context;
                      return (
                        (N.filter = this.current.transferMaps),
                        N.drawImage(f, 0, 0),
                        (N.filter = "none"),
                        L.canvas
                      );
                    }
                    paintInlineImageXObject(u) {
                      if (!this.contentVisible) return;
                      const f = u.width,
                        v = u.height,
                        F = this.ctx;
                      if ((this.save(), !a.isNodeJS)) {
                        const { filter: R } = F;
                        R !== "none" && R !== "" && (F.filter = "none");
                      }
                      F.scale(1 / f, -1 / v);
                      let L;
                      if (u.bitmap) L = this.applyTransferMapsToBitmap(u);
                      else if (
                        (typeof HTMLElement == "function" &&
                          u instanceof HTMLElement) ||
                        !u.data
                      )
                        L = u;
                      else {
                        const o = this.cachedCanvases.getCanvas(
                          "inlineImage",
                          f,
                          v,
                        ).context;
                        (M(o, u), (L = this.applyTransferMapsToCanvas(o)));
                      }
                      const N = this._scaleImage(
                        L,
                        (0, p.getCurrentTransformInverse)(F),
                      );
                      ((F.imageSmoothingEnabled = nt(
                        (0, p.getCurrentTransform)(F),
                        u.interpolate,
                      )),
                        m(
                          F,
                          N.img,
                          0,
                          0,
                          N.paintWidth,
                          N.paintHeight,
                          0,
                          -v,
                          f,
                          v,
                        ),
                        this.compose(),
                        this.restore());
                    }
                    paintInlineImageXObjectGroup(u, f) {
                      if (!this.contentVisible) return;
                      const v = this.ctx;
                      let F;
                      if (u.bitmap) F = u.bitmap;
                      else {
                        const L = u.width,
                          N = u.height,
                          o = this.cachedCanvases.getCanvas(
                            "inlineImage",
                            L,
                            N,
                          ).context;
                        (M(o, u), (F = this.applyTransferMapsToCanvas(o)));
                      }
                      for (const L of f)
                        (v.save(),
                          v.transform(...L.transform),
                          v.scale(1, -1),
                          m(v, F, L.x, L.y, L.w, L.h, 0, -1, 1, 1),
                          v.restore());
                      this.compose();
                    }
                    paintSolidColorImageMask() {
                      this.contentVisible &&
                        (this.ctx.fillRect(0, 0, 1, 1), this.compose());
                    }
                    markPoint(u) {}
                    markPointProps(u, f) {}
                    beginMarkedContent(u) {
                      this.markedContentStack.push({ visible: !0 });
                    }
                    beginMarkedContentProps(u, f) {
                      (u === "OC"
                        ? this.markedContentStack.push({
                            visible: this.optionalContentConfig.isVisible(f),
                          })
                        : this.markedContentStack.push({ visible: !0 }),
                        (this.contentVisible = this.isContentVisible()));
                    }
                    endMarkedContent() {
                      (this.markedContentStack.pop(),
                        (this.contentVisible = this.isContentVisible()));
                    }
                    beginCompat() {}
                    endCompat() {}
                    consumePath(u) {
                      const f = this.current.isEmptyClip();
                      (this.pendingClip && this.current.updateClipFromPath(),
                        this.pendingClip || this.compose(u));
                      const v = this.ctx;
                      (this.pendingClip &&
                        (f ||
                          (this.pendingClip === K
                            ? v.clip("evenodd")
                            : v.clip()),
                        (this.pendingClip = null)),
                        this.current.startNewPathAndClipBox(
                          this.current.clipBox,
                        ),
                        v.beginPath());
                    }
                    getSinglePixelWidth() {
                      if (!this._cachedGetSinglePixelWidth) {
                        const u = (0, p.getCurrentTransform)(this.ctx);
                        if (u[1] === 0 && u[2] === 0)
                          this._cachedGetSinglePixelWidth =
                            1 / Math.min(Math.abs(u[0]), Math.abs(u[3]));
                        else {
                          const f = Math.abs(u[0] * u[3] - u[2] * u[1]),
                            v = Math.hypot(u[0], u[2]),
                            F = Math.hypot(u[1], u[3]);
                          this._cachedGetSinglePixelWidth = Math.max(v, F) / f;
                        }
                      }
                      return this._cachedGetSinglePixelWidth;
                    }
                    getScaleForStroking() {
                      if (this._cachedScaleForStroking[0] === -1) {
                        const { lineWidth: u } = this.current,
                          { a: f, b: v, c: F, d: L } = this.ctx.getTransform();
                        let N, R;
                        if (v === 0 && F === 0) {
                          const o = Math.abs(f),
                            b = Math.abs(L);
                          if (o === b)
                            if (u === 0) N = R = 1 / o;
                            else {
                              const S = o * u;
                              N = R = S < 1 ? 1 / S : 1;
                            }
                          else if (u === 0) ((N = 1 / o), (R = 1 / b));
                          else {
                            const S = o * u,
                              x = b * u;
                            ((N = S < 1 ? 1 / S : 1), (R = x < 1 ? 1 / x : 1));
                          }
                        } else {
                          const o = Math.abs(f * L - v * F),
                            b = Math.hypot(f, v),
                            S = Math.hypot(F, L);
                          if (u === 0) ((N = S / o), (R = b / o));
                          else {
                            const x = u * o;
                            ((N = S > x ? S / x : 1), (R = b > x ? b / x : 1));
                          }
                        }
                        ((this._cachedScaleForStroking[0] = N),
                          (this._cachedScaleForStroking[1] = R));
                      }
                      return this._cachedScaleForStroking;
                    }
                    rescaleAndStroke(u) {
                      const { ctx: f } = this,
                        { lineWidth: v } = this.current,
                        [F, L] = this.getScaleForStroking();
                      if (((f.lineWidth = v || 1), F === 1 && L === 1)) {
                        f.stroke();
                        return;
                      }
                      const N = f.getLineDash();
                      if ((u && f.save(), f.scale(F, L), N.length > 0)) {
                        const R = Math.max(F, L);
                        (f.setLineDash(N.map((o) => o / R)),
                          (f.lineDashOffset /= R));
                      }
                      (f.stroke(), u && f.restore());
                    }
                    isContentVisible() {
                      for (
                        let u = this.markedContentStack.length - 1;
                        u >= 0;
                        u--
                      )
                        if (!this.markedContentStack[u].visible) return !1;
                      return !0;
                    }
                  }
                  e.CanvasGraphics = I;
                  for (const _ in a.OPS)
                    I.prototype[_] !== void 0 &&
                      (I.prototype[a.OPS[_]] = I.prototype[_]);
                },
                (A, e, y) => {
                  (Object.defineProperty(e, "__esModule", { value: !0 }),
                    (e.TilingPattern = e.PathType = void 0),
                    (e.getShadingPattern = c));
                  var a = y(1),
                    p = y(6);
                  const k = {
                    FILL: "Fill",
                    STROKE: "Stroke",
                    SHADING: "Shading",
                  };
                  e.PathType = k;
                  function T(m, l) {
                    if (!l) return;
                    const w = l[2] - l[0],
                      M = l[3] - l[1],
                      C = new Path2D();
                    (C.rect(l[0], l[1], w, M), m.clip(C));
                  }
                  class j {
                    constructor() {
                      this.constructor === j &&
                        (0, a.unreachable)(
                          "Cannot initialize BaseShadingPattern.",
                        );
                    }
                    getPattern() {
                      (0, a.unreachable)(
                        "Abstract method `getPattern` called.",
                      );
                    }
                  }
                  class D extends j {
                    constructor(l) {
                      (super(),
                        (this._type = l[1]),
                        (this._bbox = l[2]),
                        (this._colorStops = l[3]),
                        (this._p0 = l[4]),
                        (this._p1 = l[5]),
                        (this._r0 = l[6]),
                        (this._r1 = l[7]),
                        (this.matrix = null));
                    }
                    _createGradient(l) {
                      let w;
                      this._type === "axial"
                        ? (w = l.createLinearGradient(
                            this._p0[0],
                            this._p0[1],
                            this._p1[0],
                            this._p1[1],
                          ))
                        : this._type === "radial" &&
                          (w = l.createRadialGradient(
                            this._p0[0],
                            this._p0[1],
                            this._r0,
                            this._p1[0],
                            this._p1[1],
                            this._r1,
                          ));
                      for (const M of this._colorStops)
                        w.addColorStop(M[0], M[1]);
                      return w;
                    }
                    getPattern(l, w, M, C) {
                      let g;
                      if (C === k.STROKE || C === k.FILL) {
                        const E = w.current.getClippedPathBoundingBox(
                            C,
                            (0, p.getCurrentTransform)(l),
                          ) || [0, 0, 0, 0],
                          U = Math.ceil(E[2] - E[0]) || 1,
                          W = Math.ceil(E[3] - E[1]) || 1,
                          O = w.cachedCanvases.getCanvas("pattern", U, W, !0),
                          V = O.context;
                        (V.clearRect(0, 0, V.canvas.width, V.canvas.height),
                          V.beginPath(),
                          V.rect(0, 0, V.canvas.width, V.canvas.height),
                          V.translate(-E[0], -E[1]),
                          (M = a.Util.transform(M, [1, 0, 0, 1, E[0], E[1]])),
                          V.transform(...w.baseTransform),
                          this.matrix && V.transform(...this.matrix),
                          T(V, this._bbox),
                          (V.fillStyle = this._createGradient(V)),
                          V.fill(),
                          (g = l.createPattern(O.canvas, "no-repeat")));
                        const G = new DOMMatrix(M);
                        g.setTransform(G);
                      } else (T(l, this._bbox), (g = this._createGradient(l)));
                      return g;
                    }
                  }
                  function s(m, l, w, M, C, g, E, U) {
                    const W = l.coords,
                      O = l.colors,
                      V = m.data,
                      G = m.width * 4;
                    let nt;
                    (W[w + 1] > W[M + 1] &&
                      ((nt = w),
                      (w = M),
                      (M = nt),
                      (nt = g),
                      (g = E),
                      (E = nt)),
                      W[M + 1] > W[C + 1] &&
                        ((nt = M),
                        (M = C),
                        (C = nt),
                        (nt = E),
                        (E = U),
                        (U = nt)),
                      W[w + 1] > W[M + 1] &&
                        ((nt = w),
                        (w = M),
                        (M = nt),
                        (nt = g),
                        (g = E),
                        (E = nt)));
                    const Z = (W[w] + l.offsetX) * l.scaleX,
                      tt = (W[w + 1] + l.offsetY) * l.scaleY,
                      rt = (W[M] + l.offsetX) * l.scaleX,
                      K = (W[M + 1] + l.offsetY) * l.scaleY,
                      I = (W[C] + l.offsetX) * l.scaleX,
                      _ = (W[C + 1] + l.offsetY) * l.scaleY;
                    if (tt >= _) return;
                    const u = O[g],
                      f = O[g + 1],
                      v = O[g + 2],
                      F = O[E],
                      L = O[E + 1],
                      N = O[E + 2],
                      R = O[U],
                      o = O[U + 1],
                      b = O[U + 2],
                      S = Math.round(tt),
                      x = Math.round(_);
                    let P, B, H, z, st, Y, X, J;
                    for (let Q = S; Q <= x; Q++) {
                      if (Q < K) {
                        const ht = Q < tt ? 0 : (tt - Q) / (tt - K);
                        ((P = Z - (Z - rt) * ht),
                          (B = u - (u - F) * ht),
                          (H = f - (f - L) * ht),
                          (z = v - (v - N) * ht));
                      } else {
                        let ht;
                        (Q > _
                          ? (ht = 1)
                          : K === _
                            ? (ht = 0)
                            : (ht = (K - Q) / (K - _)),
                          (P = rt - (rt - I) * ht),
                          (B = F - (F - R) * ht),
                          (H = L - (L - o) * ht),
                          (z = N - (N - b) * ht));
                      }
                      let et;
                      (Q < tt
                        ? (et = 0)
                        : Q > _
                          ? (et = 1)
                          : (et = (tt - Q) / (tt - _)),
                        (st = Z - (Z - I) * et),
                        (Y = u - (u - R) * et),
                        (X = f - (f - o) * et),
                        (J = v - (v - b) * et));
                      const at = Math.round(Math.min(P, st)),
                        lt = Math.round(Math.max(P, st));
                      let ct = G * Q + at * 4;
                      for (let ht = at; ht <= lt; ht++)
                        ((et = (P - ht) / (P - st)),
                          et < 0 ? (et = 0) : et > 1 && (et = 1),
                          (V[ct++] = (B - (B - Y) * et) | 0),
                          (V[ct++] = (H - (H - X) * et) | 0),
                          (V[ct++] = (z - (z - J) * et) | 0),
                          (V[ct++] = 255));
                    }
                  }
                  function t(m, l, w) {
                    const M = l.coords,
                      C = l.colors;
                    let g, E;
                    switch (l.type) {
                      case "lattice":
                        const U = l.verticesPerRow,
                          W = Math.floor(M.length / U) - 1,
                          O = U - 1;
                        for (g = 0; g < W; g++) {
                          let V = g * U;
                          for (let G = 0; G < O; G++, V++)
                            (s(
                              m,
                              w,
                              M[V],
                              M[V + 1],
                              M[V + U],
                              C[V],
                              C[V + 1],
                              C[V + U],
                            ),
                              s(
                                m,
                                w,
                                M[V + U + 1],
                                M[V + 1],
                                M[V + U],
                                C[V + U + 1],
                                C[V + 1],
                                C[V + U],
                              ));
                        }
                        break;
                      case "triangles":
                        for (g = 0, E = M.length; g < E; g += 3)
                          s(
                            m,
                            w,
                            M[g],
                            M[g + 1],
                            M[g + 2],
                            C[g],
                            C[g + 1],
                            C[g + 2],
                          );
                        break;
                      default:
                        throw new Error("illegal figure");
                    }
                  }
                  class i extends j {
                    constructor(l) {
                      (super(),
                        (this._coords = l[2]),
                        (this._colors = l[3]),
                        (this._figures = l[4]),
                        (this._bounds = l[5]),
                        (this._bbox = l[7]),
                        (this._background = l[8]),
                        (this.matrix = null));
                    }
                    _createMeshCanvas(l, w, M) {
                      const U = Math.floor(this._bounds[0]),
                        W = Math.floor(this._bounds[1]),
                        O = Math.ceil(this._bounds[2]) - U,
                        V = Math.ceil(this._bounds[3]) - W,
                        G = Math.min(Math.ceil(Math.abs(O * l[0] * 1.1)), 3e3),
                        nt = Math.min(Math.ceil(Math.abs(V * l[1] * 1.1)), 3e3),
                        Z = O / G,
                        tt = V / nt,
                        rt = {
                          coords: this._coords,
                          colors: this._colors,
                          offsetX: -U,
                          offsetY: -W,
                          scaleX: 1 / Z,
                          scaleY: 1 / tt,
                        },
                        K = G + 4,
                        I = nt + 4,
                        _ = M.getCanvas("mesh", K, I, !1),
                        u = _.context,
                        f = u.createImageData(G, nt);
                      if (w) {
                        const F = f.data;
                        for (let L = 0, N = F.length; L < N; L += 4)
                          ((F[L] = w[0]),
                            (F[L + 1] = w[1]),
                            (F[L + 2] = w[2]),
                            (F[L + 3] = 255));
                      }
                      for (const F of this._figures) t(f, F, rt);
                      return (
                        u.putImageData(f, 2, 2),
                        {
                          canvas: _.canvas,
                          offsetX: U - 2 * Z,
                          offsetY: W - 2 * tt,
                          scaleX: Z,
                          scaleY: tt,
                        }
                      );
                    }
                    getPattern(l, w, M, C) {
                      T(l, this._bbox);
                      let g;
                      if (C === k.SHADING)
                        g = a.Util.singularValueDecompose2dScale(
                          (0, p.getCurrentTransform)(l),
                        );
                      else if (
                        ((g = a.Util.singularValueDecompose2dScale(
                          w.baseTransform,
                        )),
                        this.matrix)
                      ) {
                        const U = a.Util.singularValueDecompose2dScale(
                          this.matrix,
                        );
                        g = [g[0] * U[0], g[1] * U[1]];
                      }
                      const E = this._createMeshCanvas(
                        g,
                        C === k.SHADING ? null : this._background,
                        w.cachedCanvases,
                      );
                      return (
                        C !== k.SHADING &&
                          (l.setTransform(...w.baseTransform),
                          this.matrix && l.transform(...this.matrix)),
                        l.translate(E.offsetX, E.offsetY),
                        l.scale(E.scaleX, E.scaleY),
                        l.createPattern(E.canvas, "no-repeat")
                      );
                    }
                  }
                  class h extends j {
                    getPattern() {
                      return "hotpink";
                    }
                  }
                  function c(m) {
                    switch (m[0]) {
                      case "RadialAxial":
                        return new D(m);
                      case "Mesh":
                        return new i(m);
                      case "Dummy":
                        return new h();
                    }
                    throw new Error(`Unknown IR type: ${m[0]}`);
                  }
                  const n = { COLORED: 1, UNCOLORED: 2 };
                  class d {
                    static MAX_PATTERN_SIZE = 3e3;
                    constructor(l, w, M, C, g) {
                      ((this.operatorList = l[2]),
                        (this.matrix = l[3] || [1, 0, 0, 1, 0, 0]),
                        (this.bbox = l[4]),
                        (this.xstep = l[5]),
                        (this.ystep = l[6]),
                        (this.paintType = l[7]),
                        (this.tilingType = l[8]),
                        (this.color = w),
                        (this.ctx = M),
                        (this.canvasGraphicsFactory = C),
                        (this.baseTransform = g));
                    }
                    createPatternCanvas(l) {
                      const w = this.operatorList,
                        M = this.bbox,
                        C = this.xstep,
                        g = this.ystep,
                        E = this.paintType,
                        U = this.tilingType,
                        W = this.color,
                        O = this.canvasGraphicsFactory;
                      (0, a.info)("TilingType: " + U);
                      const V = M[0],
                        G = M[1],
                        nt = M[2],
                        Z = M[3],
                        tt = a.Util.singularValueDecompose2dScale(this.matrix),
                        rt = a.Util.singularValueDecompose2dScale(
                          this.baseTransform,
                        ),
                        K = [tt[0] * rt[0], tt[1] * rt[1]],
                        I = this.getSizeAndScale(
                          C,
                          this.ctx.canvas.width,
                          K[0],
                        ),
                        _ = this.getSizeAndScale(
                          g,
                          this.ctx.canvas.height,
                          K[1],
                        ),
                        u = l.cachedCanvases.getCanvas(
                          "pattern",
                          I.size,
                          _.size,
                          !0,
                        ),
                        f = u.context,
                        v = O.createCanvasGraphics(f);
                      ((v.groupLevel = l.groupLevel),
                        this.setFillAndStrokeStyleToContext(v, E, W));
                      let F = V,
                        L = G,
                        N = nt,
                        R = Z;
                      return (
                        V < 0 && ((F = 0), (N += Math.abs(V))),
                        G < 0 && ((L = 0), (R += Math.abs(G))),
                        f.translate(-(I.scale * F), -(_.scale * L)),
                        v.transform(I.scale, 0, 0, _.scale, 0, 0),
                        f.save(),
                        this.clipBbox(v, F, L, N, R),
                        (v.baseTransform = (0, p.getCurrentTransform)(v.ctx)),
                        v.executeOperatorList(w),
                        v.endDrawing(),
                        {
                          canvas: u.canvas,
                          scaleX: I.scale,
                          scaleY: _.scale,
                          offsetX: F,
                          offsetY: L,
                        }
                      );
                    }
                    getSizeAndScale(l, w, M) {
                      l = Math.abs(l);
                      const C = Math.max(d.MAX_PATTERN_SIZE, w);
                      let g = Math.ceil(l * M);
                      return (
                        g >= C ? (g = C) : (M = g / l),
                        { scale: M, size: g }
                      );
                    }
                    clipBbox(l, w, M, C, g) {
                      const E = C - w,
                        U = g - M;
                      (l.ctx.rect(w, M, E, U),
                        l.current.updateRectMinMax(
                          (0, p.getCurrentTransform)(l.ctx),
                          [w, M, C, g],
                        ),
                        l.clip(),
                        l.endPath());
                    }
                    setFillAndStrokeStyleToContext(l, w, M) {
                      const C = l.ctx,
                        g = l.current;
                      switch (w) {
                        case n.COLORED:
                          const E = this.ctx;
                          ((C.fillStyle = E.fillStyle),
                            (C.strokeStyle = E.strokeStyle),
                            (g.fillColor = E.fillStyle),
                            (g.strokeColor = E.strokeStyle));
                          break;
                        case n.UNCOLORED:
                          const U = a.Util.makeHexColor(M[0], M[1], M[2]);
                          ((C.fillStyle = U),
                            (C.strokeStyle = U),
                            (g.fillColor = U),
                            (g.strokeColor = U));
                          break;
                        default:
                          throw new a.FormatError(
                            `Unsupported paint type: ${w}`,
                          );
                      }
                    }
                    getPattern(l, w, M, C) {
                      let g = M;
                      C !== k.SHADING &&
                        ((g = a.Util.transform(g, w.baseTransform)),
                        this.matrix && (g = a.Util.transform(g, this.matrix)));
                      const E = this.createPatternCanvas(w);
                      let U = new DOMMatrix(g);
                      ((U = U.translate(E.offsetX, E.offsetY)),
                        (U = U.scale(1 / E.scaleX, 1 / E.scaleY)));
                      const W = l.createPattern(E.canvas, "repeat");
                      return (W.setTransform(U), W);
                    }
                  }
                  e.TilingPattern = d;
                },
                (A, e, y) => {
                  (Object.defineProperty(e, "__esModule", { value: !0 }),
                    (e.convertBlackAndWhiteToRGBA = k),
                    (e.convertToRGBA = p),
                    (e.grayToRGBA = j));
                  var a = y(1);
                  function p(D) {
                    switch (D.kind) {
                      case a.ImageKind.GRAYSCALE_1BPP:
                        return k(D);
                      case a.ImageKind.RGB_24BPP:
                        return T(D);
                    }
                    return null;
                  }
                  function k({
                    src: D,
                    srcPos: s = 0,
                    dest: t,
                    width: i,
                    height: h,
                    nonBlackColor: c = 4294967295,
                    inverseDecode: n = !1,
                  }) {
                    const d = a.FeatureTest.isLittleEndian ? 4278190080 : 255,
                      [m, l] = n ? [c, d] : [d, c],
                      w = i >> 3,
                      M = i & 7,
                      C = D.length;
                    t = new Uint32Array(t.buffer);
                    let g = 0;
                    for (let E = 0; E < h; E++) {
                      for (const W = s + w; s < W; s++) {
                        const O = s < C ? D[s] : 255;
                        ((t[g++] = O & 128 ? l : m),
                          (t[g++] = O & 64 ? l : m),
                          (t[g++] = O & 32 ? l : m),
                          (t[g++] = O & 16 ? l : m),
                          (t[g++] = O & 8 ? l : m),
                          (t[g++] = O & 4 ? l : m),
                          (t[g++] = O & 2 ? l : m),
                          (t[g++] = O & 1 ? l : m));
                      }
                      if (M === 0) continue;
                      const U = s < C ? D[s++] : 255;
                      for (let W = 0; W < M; W++)
                        t[g++] = U & (1 << (7 - W)) ? l : m;
                    }
                    return { srcPos: s, destPos: g };
                  }
                  function T({
                    src: D,
                    srcPos: s = 0,
                    dest: t,
                    destPos: i = 0,
                    width: h,
                    height: c,
                  }) {
                    let n = 0;
                    const d = D.length >> 2,
                      m = new Uint32Array(D.buffer, s, d);
                    if (a.FeatureTest.isLittleEndian) {
                      for (; n < d - 2; n += 3, i += 4) {
                        const l = m[n],
                          w = m[n + 1],
                          M = m[n + 2];
                        ((t[i] = l | 4278190080),
                          (t[i + 1] = (l >>> 24) | (w << 8) | 4278190080),
                          (t[i + 2] = (w >>> 16) | (M << 16) | 4278190080),
                          (t[i + 3] = (M >>> 8) | 4278190080));
                      }
                      for (let l = n * 4, w = D.length; l < w; l += 3)
                        t[i++] =
                          D[l] |
                          (D[l + 1] << 8) |
                          (D[l + 2] << 16) |
                          4278190080;
                    } else {
                      for (; n < d - 2; n += 3, i += 4) {
                        const l = m[n],
                          w = m[n + 1],
                          M = m[n + 2];
                        ((t[i] = l | 255),
                          (t[i + 1] = (l << 24) | (w >>> 8) | 255),
                          (t[i + 2] = (w << 16) | (M >>> 16) | 255),
                          (t[i + 3] = (M << 8) | 255));
                      }
                      for (let l = n * 4, w = D.length; l < w; l += 3)
                        t[i++] =
                          (D[l] << 24) |
                          (D[l + 1] << 16) |
                          (D[l + 2] << 8) |
                          255;
                    }
                    return { srcPos: s, destPos: i };
                  }
                  function j(D, s) {
                    if (a.FeatureTest.isLittleEndian)
                      for (let t = 0, i = D.length; t < i; t++)
                        s[t] = (D[t] * 65793) | 4278190080;
                    else
                      for (let t = 0, i = D.length; t < i; t++)
                        s[t] = (D[t] * 16843008) | 255;
                  }
                },
                (A, e) => {
                  (Object.defineProperty(e, "__esModule", { value: !0 }),
                    (e.GlobalWorkerOptions = void 0));
                  const y = Object.create(null);
                  ((e.GlobalWorkerOptions = y),
                    (y.workerPort = null),
                    (y.workerSrc = ""));
                },
                (A, e, y) => {
                  (Object.defineProperty(e, "__esModule", { value: !0 }),
                    (e.MessageHandler = void 0));
                  var a = y(1);
                  const p = { DATA: 1, ERROR: 2 },
                    k = {
                      CANCEL: 1,
                      CANCEL_COMPLETE: 2,
                      CLOSE: 3,
                      ENQUEUE: 4,
                      ERROR: 5,
                      PULL: 6,
                      PULL_COMPLETE: 7,
                      START_COMPLETE: 8,
                    };
                  function T(D) {
                    switch (
                      (D instanceof Error ||
                        (typeof D == "object" && D !== null) ||
                        (0, a.unreachable)(
                          'wrapReason: Expected "reason" to be a (possibly cloned) Error.',
                        ),
                      D.name)
                    ) {
                      case "AbortException":
                        return new a.AbortException(D.message);
                      case "MissingPDFException":
                        return new a.MissingPDFException(D.message);
                      case "PasswordException":
                        return new a.PasswordException(D.message, D.code);
                      case "UnexpectedResponseException":
                        return new a.UnexpectedResponseException(
                          D.message,
                          D.status,
                        );
                      case "UnknownErrorException":
                        return new a.UnknownErrorException(
                          D.message,
                          D.details,
                        );
                      default:
                        return new a.UnknownErrorException(
                          D.message,
                          D.toString(),
                        );
                    }
                  }
                  class j {
                    constructor(s, t, i) {
                      ((this.sourceName = s),
                        (this.targetName = t),
                        (this.comObj = i),
                        (this.callbackId = 1),
                        (this.streamId = 1),
                        (this.streamSinks = Object.create(null)),
                        (this.streamControllers = Object.create(null)),
                        (this.callbackCapabilities = Object.create(null)),
                        (this.actionHandler = Object.create(null)),
                        (this._onComObjOnMessage = (h) => {
                          const c = h.data;
                          if (c.targetName !== this.sourceName) return;
                          if (c.stream) {
                            this.#e(c);
                            return;
                          }
                          if (c.callback) {
                            const d = c.callbackId,
                              m = this.callbackCapabilities[d];
                            if (!m)
                              throw new Error(`Cannot resolve callback ${d}`);
                            if (
                              (delete this.callbackCapabilities[d],
                              c.callback === p.DATA)
                            )
                              m.resolve(c.data);
                            else if (c.callback === p.ERROR)
                              m.reject(T(c.reason));
                            else throw new Error("Unexpected callback case");
                            return;
                          }
                          const n = this.actionHandler[c.action];
                          if (!n)
                            throw new Error(
                              `Unknown action from worker: ${c.action}`,
                            );
                          if (c.callbackId) {
                            const d = this.sourceName,
                              m = c.sourceName;
                            new Promise(function (l) {
                              l(n(c.data));
                            }).then(
                              function (l) {
                                i.postMessage({
                                  sourceName: d,
                                  targetName: m,
                                  callback: p.DATA,
                                  callbackId: c.callbackId,
                                  data: l,
                                });
                              },
                              function (l) {
                                i.postMessage({
                                  sourceName: d,
                                  targetName: m,
                                  callback: p.ERROR,
                                  callbackId: c.callbackId,
                                  reason: T(l),
                                });
                              },
                            );
                            return;
                          }
                          if (c.streamId) {
                            this.#t(c);
                            return;
                          }
                          n(c.data);
                        }),
                        i.addEventListener("message", this._onComObjOnMessage));
                    }
                    on(s, t) {
                      const i = this.actionHandler;
                      if (i[s])
                        throw new Error(
                          `There is already an actionName called "${s}"`,
                        );
                      i[s] = t;
                    }
                    send(s, t, i) {
                      this.comObj.postMessage(
                        {
                          sourceName: this.sourceName,
                          targetName: this.targetName,
                          action: s,
                          data: t,
                        },
                        i,
                      );
                    }
                    sendWithPromise(s, t, i) {
                      const h = this.callbackId++,
                        c = new a.PromiseCapability();
                      this.callbackCapabilities[h] = c;
                      try {
                        this.comObj.postMessage(
                          {
                            sourceName: this.sourceName,
                            targetName: this.targetName,
                            action: s,
                            callbackId: h,
                            data: t,
                          },
                          i,
                        );
                      } catch (n) {
                        c.reject(n);
                      }
                      return c.promise;
                    }
                    sendWithStream(s, t, i, h) {
                      const c = this.streamId++,
                        n = this.sourceName,
                        d = this.targetName,
                        m = this.comObj;
                      return new ReadableStream(
                        {
                          start: (l) => {
                            const w = new a.PromiseCapability();
                            return (
                              (this.streamControllers[c] = {
                                controller: l,
                                startCall: w,
                                pullCall: null,
                                cancelCall: null,
                                isClosed: !1,
                              }),
                              m.postMessage(
                                {
                                  sourceName: n,
                                  targetName: d,
                                  action: s,
                                  streamId: c,
                                  data: t,
                                  desiredSize: l.desiredSize,
                                },
                                h,
                              ),
                              w.promise
                            );
                          },
                          pull: (l) => {
                            const w = new a.PromiseCapability();
                            return (
                              (this.streamControllers[c].pullCall = w),
                              m.postMessage({
                                sourceName: n,
                                targetName: d,
                                stream: k.PULL,
                                streamId: c,
                                desiredSize: l.desiredSize,
                              }),
                              w.promise
                            );
                          },
                          cancel: (l) => {
                            (0, a.assert)(
                              l instanceof Error,
                              "cancel must have a valid reason",
                            );
                            const w = new a.PromiseCapability();
                            return (
                              (this.streamControllers[c].cancelCall = w),
                              (this.streamControllers[c].isClosed = !0),
                              m.postMessage({
                                sourceName: n,
                                targetName: d,
                                stream: k.CANCEL,
                                streamId: c,
                                reason: T(l),
                              }),
                              w.promise
                            );
                          },
                        },
                        i,
                      );
                    }
                    #t(s) {
                      const t = s.streamId,
                        i = this.sourceName,
                        h = s.sourceName,
                        c = this.comObj,
                        n = this,
                        d = this.actionHandler[s.action],
                        m = {
                          enqueue(l, w = 1, M) {
                            if (this.isCancelled) return;
                            const C = this.desiredSize;
                            ((this.desiredSize -= w),
                              C > 0 &&
                                this.desiredSize <= 0 &&
                                ((this.sinkCapability =
                                  new a.PromiseCapability()),
                                (this.ready = this.sinkCapability.promise)),
                              c.postMessage(
                                {
                                  sourceName: i,
                                  targetName: h,
                                  stream: k.ENQUEUE,
                                  streamId: t,
                                  chunk: l,
                                },
                                M,
                              ));
                          },
                          close() {
                            this.isCancelled ||
                              ((this.isCancelled = !0),
                              c.postMessage({
                                sourceName: i,
                                targetName: h,
                                stream: k.CLOSE,
                                streamId: t,
                              }),
                              delete n.streamSinks[t]);
                          },
                          error(l) {
                            ((0, a.assert)(
                              l instanceof Error,
                              "error must have a valid reason",
                            ),
                              !this.isCancelled &&
                                ((this.isCancelled = !0),
                                c.postMessage({
                                  sourceName: i,
                                  targetName: h,
                                  stream: k.ERROR,
                                  streamId: t,
                                  reason: T(l),
                                })));
                          },
                          sinkCapability: new a.PromiseCapability(),
                          onPull: null,
                          onCancel: null,
                          isCancelled: !1,
                          desiredSize: s.desiredSize,
                          ready: null,
                        };
                      (m.sinkCapability.resolve(),
                        (m.ready = m.sinkCapability.promise),
                        (this.streamSinks[t] = m),
                        new Promise(function (l) {
                          l(d(s.data, m));
                        }).then(
                          function () {
                            c.postMessage({
                              sourceName: i,
                              targetName: h,
                              stream: k.START_COMPLETE,
                              streamId: t,
                              success: !0,
                            });
                          },
                          function (l) {
                            c.postMessage({
                              sourceName: i,
                              targetName: h,
                              stream: k.START_COMPLETE,
                              streamId: t,
                              reason: T(l),
                            });
                          },
                        ));
                    }
                    #e(s) {
                      const t = s.streamId,
                        i = this.sourceName,
                        h = s.sourceName,
                        c = this.comObj,
                        n = this.streamControllers[t],
                        d = this.streamSinks[t];
                      switch (s.stream) {
                        case k.START_COMPLETE:
                          s.success
                            ? n.startCall.resolve()
                            : n.startCall.reject(T(s.reason));
                          break;
                        case k.PULL_COMPLETE:
                          s.success
                            ? n.pullCall.resolve()
                            : n.pullCall.reject(T(s.reason));
                          break;
                        case k.PULL:
                          if (!d) {
                            c.postMessage({
                              sourceName: i,
                              targetName: h,
                              stream: k.PULL_COMPLETE,
                              streamId: t,
                              success: !0,
                            });
                            break;
                          }
                          (d.desiredSize <= 0 &&
                            s.desiredSize > 0 &&
                            d.sinkCapability.resolve(),
                            (d.desiredSize = s.desiredSize),
                            new Promise(function (m) {
                              m(d.onPull?.());
                            }).then(
                              function () {
                                c.postMessage({
                                  sourceName: i,
                                  targetName: h,
                                  stream: k.PULL_COMPLETE,
                                  streamId: t,
                                  success: !0,
                                });
                              },
                              function (m) {
                                c.postMessage({
                                  sourceName: i,
                                  targetName: h,
                                  stream: k.PULL_COMPLETE,
                                  streamId: t,
                                  reason: T(m),
                                });
                              },
                            ));
                          break;
                        case k.ENQUEUE:
                          if (
                            ((0, a.assert)(
                              n,
                              "enqueue should have stream controller",
                            ),
                            n.isClosed)
                          )
                            break;
                          n.controller.enqueue(s.chunk);
                          break;
                        case k.CLOSE:
                          if (
                            ((0, a.assert)(
                              n,
                              "close should have stream controller",
                            ),
                            n.isClosed)
                          )
                            break;
                          ((n.isClosed = !0),
                            n.controller.close(),
                            this.#n(n, t));
                          break;
                        case k.ERROR:
                          ((0, a.assert)(
                            n,
                            "error should have stream controller",
                          ),
                            n.controller.error(T(s.reason)),
                            this.#n(n, t));
                          break;
                        case k.CANCEL_COMPLETE:
                          (s.success
                            ? n.cancelCall.resolve()
                            : n.cancelCall.reject(T(s.reason)),
                            this.#n(n, t));
                          break;
                        case k.CANCEL:
                          if (!d) break;
                          (new Promise(function (m) {
                            m(d.onCancel?.(T(s.reason)));
                          }).then(
                            function () {
                              c.postMessage({
                                sourceName: i,
                                targetName: h,
                                stream: k.CANCEL_COMPLETE,
                                streamId: t,
                                success: !0,
                              });
                            },
                            function (m) {
                              c.postMessage({
                                sourceName: i,
                                targetName: h,
                                stream: k.CANCEL_COMPLETE,
                                streamId: t,
                                reason: T(m),
                              });
                            },
                          ),
                            d.sinkCapability.reject(T(s.reason)),
                            (d.isCancelled = !0),
                            delete this.streamSinks[t]);
                          break;
                        default:
                          throw new Error("Unexpected stream case");
                      }
                    }
                    async #n(s, t) {
                      (await Promise.allSettled([
                        s.startCall?.promise,
                        s.pullCall?.promise,
                        s.cancelCall?.promise,
                      ]),
                        delete this.streamControllers[t]);
                    }
                    destroy() {
                      this.comObj.removeEventListener(
                        "message",
                        this._onComObjOnMessage,
                      );
                    }
                  }
                  e.MessageHandler = j;
                },
                (A, e, y) => {
                  (Object.defineProperty(e, "__esModule", { value: !0 }),
                    (e.Metadata = void 0));
                  var a = y(1);
                  class p {
                    #t;
                    #e;
                    constructor({ parsedData: T, rawData: j }) {
                      ((this.#t = T), (this.#e = j));
                    }
                    getRaw() {
                      return this.#e;
                    }
                    get(T) {
                      return this.#t.get(T) ?? null;
                    }
                    getAll() {
                      return (0, a.objectFromMap)(this.#t);
                    }
                    has(T) {
                      return this.#t.has(T);
                    }
                  }
                  e.Metadata = p;
                },
                (A, e, y) => {
                  (Object.defineProperty(e, "__esModule", { value: !0 }),
                    (e.OptionalContentConfig = void 0));
                  var a = y(1),
                    p = y(8);
                  const k = Symbol("INTERNAL");
                  class T {
                    #t = !0;
                    constructor(s, t) {
                      ((this.name = s), (this.intent = t));
                    }
                    get visible() {
                      return this.#t;
                    }
                    _setVisible(s, t) {
                      (s !== k &&
                        (0, a.unreachable)(
                          "Internal method `_setVisible` called.",
                        ),
                        (this.#t = t));
                    }
                  }
                  class j {
                    #t = null;
                    #e = new Map();
                    #n = null;
                    #i = null;
                    constructor(s) {
                      if (
                        ((this.name = null), (this.creator = null), s !== null)
                      ) {
                        ((this.name = s.name),
                          (this.creator = s.creator),
                          (this.#i = s.order));
                        for (const t of s.groups)
                          this.#e.set(t.id, new T(t.name, t.intent));
                        if (s.baseState === "OFF")
                          for (const t of this.#e.values())
                            t._setVisible(k, !1);
                        for (const t of s.on) this.#e.get(t)._setVisible(k, !0);
                        for (const t of s.off)
                          this.#e.get(t)._setVisible(k, !1);
                        this.#n = this.getHash();
                      }
                    }
                    #o(s) {
                      const t = s.length;
                      if (t < 2) return !0;
                      const i = s[0];
                      for (let h = 1; h < t; h++) {
                        const c = s[h];
                        let n;
                        if (Array.isArray(c)) n = this.#o(c);
                        else if (this.#e.has(c)) n = this.#e.get(c).visible;
                        else
                          return (
                            (0, a.warn)(
                              `Optional content group not found: ${c}`,
                            ),
                            !0
                          );
                        switch (i) {
                          case "And":
                            if (!n) return !1;
                            break;
                          case "Or":
                            if (n) return !0;
                            break;
                          case "Not":
                            return !n;
                          default:
                            return !0;
                        }
                      }
                      return i === "And";
                    }
                    isVisible(s) {
                      if (this.#e.size === 0) return !0;
                      if (!s)
                        return (
                          (0, a.warn)("Optional content group not defined."),
                          !0
                        );
                      if (s.type === "OCG")
                        return this.#e.has(s.id)
                          ? this.#e.get(s.id).visible
                          : ((0, a.warn)(
                              `Optional content group not found: ${s.id}`,
                            ),
                            !0);
                      if (s.type === "OCMD") {
                        if (s.expression) return this.#o(s.expression);
                        if (!s.policy || s.policy === "AnyOn") {
                          for (const t of s.ids) {
                            if (!this.#e.has(t))
                              return (
                                (0, a.warn)(
                                  `Optional content group not found: ${t}`,
                                ),
                                !0
                              );
                            if (this.#e.get(t).visible) return !0;
                          }
                          return !1;
                        } else if (s.policy === "AllOn") {
                          for (const t of s.ids) {
                            if (!this.#e.has(t))
                              return (
                                (0, a.warn)(
                                  `Optional content group not found: ${t}`,
                                ),
                                !0
                              );
                            if (!this.#e.get(t).visible) return !1;
                          }
                          return !0;
                        } else if (s.policy === "AnyOff") {
                          for (const t of s.ids) {
                            if (!this.#e.has(t))
                              return (
                                (0, a.warn)(
                                  `Optional content group not found: ${t}`,
                                ),
                                !0
                              );
                            if (!this.#e.get(t).visible) return !0;
                          }
                          return !1;
                        } else if (s.policy === "AllOff") {
                          for (const t of s.ids) {
                            if (!this.#e.has(t))
                              return (
                                (0, a.warn)(
                                  `Optional content group not found: ${t}`,
                                ),
                                !0
                              );
                            if (this.#e.get(t).visible) return !1;
                          }
                          return !0;
                        }
                        return (
                          (0, a.warn)(
                            `Unknown optional content policy ${s.policy}.`,
                          ),
                          !0
                        );
                      }
                      return ((0, a.warn)(`Unknown group type ${s.type}.`), !0);
                    }
                    setVisibility(s, t = !0) {
                      if (!this.#e.has(s)) {
                        (0, a.warn)(`Optional content group not found: ${s}`);
                        return;
                      }
                      (this.#e.get(s)._setVisible(k, !!t), (this.#t = null));
                    }
                    get hasInitialVisibility() {
                      return this.#n === null || this.getHash() === this.#n;
                    }
                    getOrder() {
                      return this.#e.size
                        ? this.#i
                          ? this.#i.slice()
                          : [...this.#e.keys()]
                        : null;
                    }
                    getGroups() {
                      return this.#e.size > 0
                        ? (0, a.objectFromMap)(this.#e)
                        : null;
                    }
                    getGroup(s) {
                      return this.#e.get(s) || null;
                    }
                    getHash() {
                      if (this.#t !== null) return this.#t;
                      const s = new p.MurmurHash3_64();
                      for (const [t, i] of this.#e)
                        s.update(`${t}:${i.visible}`);
                      return (this.#t = s.hexdigest());
                    }
                  }
                  e.OptionalContentConfig = j;
                },
                (A, e, y) => {
                  (Object.defineProperty(e, "__esModule", { value: !0 }),
                    (e.PDFDataTransportStream = void 0));
                  var a = y(1),
                    p = y(6);
                  class k {
                    constructor(
                      {
                        length: s,
                        initialData: t,
                        progressiveDone: i = !1,
                        contentDispositionFilename: h = null,
                        disableRange: c = !1,
                        disableStream: n = !1,
                      },
                      d,
                    ) {
                      if (
                        ((0, a.assert)(
                          d,
                          'PDFDataTransportStream - missing required "pdfDataRangeTransport" argument.',
                        ),
                        (this._queuedChunks = []),
                        (this._progressiveDone = i),
                        (this._contentDispositionFilename = h),
                        t?.length > 0)
                      ) {
                        const m =
                          t instanceof Uint8Array &&
                          t.byteLength === t.buffer.byteLength
                            ? t.buffer
                            : new Uint8Array(t).buffer;
                        this._queuedChunks.push(m);
                      }
                      ((this._pdfDataRangeTransport = d),
                        (this._isStreamingSupported = !n),
                        (this._isRangeSupported = !c),
                        (this._contentLength = s),
                        (this._fullRequestReader = null),
                        (this._rangeReaders = []),
                        this._pdfDataRangeTransport.addRangeListener((m, l) => {
                          this._onReceiveData({ begin: m, chunk: l });
                        }),
                        this._pdfDataRangeTransport.addProgressListener(
                          (m, l) => {
                            this._onProgress({ loaded: m, total: l });
                          },
                        ),
                        this._pdfDataRangeTransport.addProgressiveReadListener(
                          (m) => {
                            this._onReceiveData({ chunk: m });
                          },
                        ),
                        this._pdfDataRangeTransport.addProgressiveDoneListener(
                          () => {
                            this._onProgressiveDone();
                          },
                        ),
                        this._pdfDataRangeTransport.transportReady());
                    }
                    _onReceiveData({ begin: s, chunk: t }) {
                      const i =
                        t instanceof Uint8Array &&
                        t.byteLength === t.buffer.byteLength
                          ? t.buffer
                          : new Uint8Array(t).buffer;
                      if (s === void 0)
                        this._fullRequestReader
                          ? this._fullRequestReader._enqueue(i)
                          : this._queuedChunks.push(i);
                      else {
                        const h = this._rangeReaders.some(function (c) {
                          return c._begin !== s ? !1 : (c._enqueue(i), !0);
                        });
                        (0, a.assert)(
                          h,
                          "_onReceiveData - no `PDFDataTransportStreamRangeReader` instance found.",
                        );
                      }
                    }
                    get _progressiveDataLength() {
                      return this._fullRequestReader?._loaded ?? 0;
                    }
                    _onProgress(s) {
                      s.total === void 0
                        ? this._rangeReaders[0]?.onProgress?.({
                            loaded: s.loaded,
                          })
                        : this._fullRequestReader?.onProgress?.({
                            loaded: s.loaded,
                            total: s.total,
                          });
                    }
                    _onProgressiveDone() {
                      (this._fullRequestReader?.progressiveDone(),
                        (this._progressiveDone = !0));
                    }
                    _removeRangeReader(s) {
                      const t = this._rangeReaders.indexOf(s);
                      t >= 0 && this._rangeReaders.splice(t, 1);
                    }
                    getFullReader() {
                      (0, a.assert)(
                        !this._fullRequestReader,
                        "PDFDataTransportStream.getFullReader can only be called once.",
                      );
                      const s = this._queuedChunks;
                      return (
                        (this._queuedChunks = null),
                        new T(
                          this,
                          s,
                          this._progressiveDone,
                          this._contentDispositionFilename,
                        )
                      );
                    }
                    getRangeReader(s, t) {
                      if (t <= this._progressiveDataLength) return null;
                      const i = new j(this, s, t);
                      return (
                        this._pdfDataRangeTransport.requestDataRange(s, t),
                        this._rangeReaders.push(i),
                        i
                      );
                    }
                    cancelAllRequests(s) {
                      this._fullRequestReader?.cancel(s);
                      for (const t of this._rangeReaders.slice(0)) t.cancel(s);
                      this._pdfDataRangeTransport.abort();
                    }
                  }
                  e.PDFDataTransportStream = k;
                  class T {
                    constructor(s, t, i = !1, h = null) {
                      ((this._stream = s),
                        (this._done = i || !1),
                        (this._filename = (0, p.isPdfFile)(h) ? h : null),
                        (this._queuedChunks = t || []),
                        (this._loaded = 0));
                      for (const c of this._queuedChunks)
                        this._loaded += c.byteLength;
                      ((this._requests = []),
                        (this._headersReady = Promise.resolve()),
                        (s._fullRequestReader = this),
                        (this.onProgress = null));
                    }
                    _enqueue(s) {
                      this._done ||
                        (this._requests.length > 0
                          ? this._requests
                              .shift()
                              .resolve({ value: s, done: !1 })
                          : this._queuedChunks.push(s),
                        (this._loaded += s.byteLength));
                    }
                    get headersReady() {
                      return this._headersReady;
                    }
                    get filename() {
                      return this._filename;
                    }
                    get isRangeSupported() {
                      return this._stream._isRangeSupported;
                    }
                    get isStreamingSupported() {
                      return this._stream._isStreamingSupported;
                    }
                    get contentLength() {
                      return this._stream._contentLength;
                    }
                    async read() {
                      if (this._queuedChunks.length > 0)
                        return { value: this._queuedChunks.shift(), done: !1 };
                      if (this._done) return { value: void 0, done: !0 };
                      const s = new a.PromiseCapability();
                      return (this._requests.push(s), s.promise);
                    }
                    cancel(s) {
                      this._done = !0;
                      for (const t of this._requests)
                        t.resolve({ value: void 0, done: !0 });
                      this._requests.length = 0;
                    }
                    progressiveDone() {
                      this._done || (this._done = !0);
                    }
                  }
                  class j {
                    constructor(s, t, i) {
                      ((this._stream = s),
                        (this._begin = t),
                        (this._end = i),
                        (this._queuedChunk = null),
                        (this._requests = []),
                        (this._done = !1),
                        (this.onProgress = null));
                    }
                    _enqueue(s) {
                      if (!this._done) {
                        if (this._requests.length === 0) this._queuedChunk = s;
                        else {
                          this._requests
                            .shift()
                            .resolve({ value: s, done: !1 });
                          for (const i of this._requests)
                            i.resolve({ value: void 0, done: !0 });
                          this._requests.length = 0;
                        }
                        ((this._done = !0),
                          this._stream._removeRangeReader(this));
                      }
                    }
                    get isStreamingSupported() {
                      return !1;
                    }
                    async read() {
                      if (this._queuedChunk) {
                        const t = this._queuedChunk;
                        return (
                          (this._queuedChunk = null),
                          { value: t, done: !1 }
                        );
                      }
                      if (this._done) return { value: void 0, done: !0 };
                      const s = new a.PromiseCapability();
                      return (this._requests.push(s), s.promise);
                    }
                    cancel(s) {
                      this._done = !0;
                      for (const t of this._requests)
                        t.resolve({ value: void 0, done: !0 });
                      ((this._requests.length = 0),
                        this._stream._removeRangeReader(this));
                    }
                  }
                },
                (A, e, y) => {
                  (Object.defineProperty(e, "__esModule", { value: !0 }),
                    (e.PDFFetchStream = void 0));
                  var a = y(1),
                    p = y(20);
                  function k(i, h, c) {
                    return {
                      method: "GET",
                      headers: i,
                      signal: c.signal,
                      mode: "cors",
                      credentials: h ? "include" : "same-origin",
                      redirect: "follow",
                    };
                  }
                  function T(i) {
                    const h = new Headers();
                    for (const c in i) {
                      const n = i[c];
                      n !== void 0 && h.append(c, n);
                    }
                    return h;
                  }
                  function j(i) {
                    return i instanceof Uint8Array
                      ? i.buffer
                      : i instanceof ArrayBuffer
                        ? i
                        : ((0, a.warn)(
                            `getArrayBuffer - unexpected data format: ${i}`,
                          ),
                          new Uint8Array(i).buffer);
                  }
                  class D {
                    constructor(h) {
                      ((this.source = h),
                        (this.isHttp = /^https?:/i.test(h.url)),
                        (this.httpHeaders =
                          (this.isHttp && h.httpHeaders) || {}),
                        (this._fullRequestReader = null),
                        (this._rangeRequestReaders = []));
                    }
                    get _progressiveDataLength() {
                      return this._fullRequestReader?._loaded ?? 0;
                    }
                    getFullReader() {
                      return (
                        (0, a.assert)(
                          !this._fullRequestReader,
                          "PDFFetchStream.getFullReader can only be called once.",
                        ),
                        (this._fullRequestReader = new s(this)),
                        this._fullRequestReader
                      );
                    }
                    getRangeReader(h, c) {
                      if (c <= this._progressiveDataLength) return null;
                      const n = new t(this, h, c);
                      return (this._rangeRequestReaders.push(n), n);
                    }
                    cancelAllRequests(h) {
                      this._fullRequestReader?.cancel(h);
                      for (const c of this._rangeRequestReaders.slice(0))
                        c.cancel(h);
                    }
                  }
                  e.PDFFetchStream = D;
                  class s {
                    constructor(h) {
                      ((this._stream = h),
                        (this._reader = null),
                        (this._loaded = 0),
                        (this._filename = null));
                      const c = h.source;
                      ((this._withCredentials = c.withCredentials || !1),
                        (this._contentLength = c.length),
                        (this._headersCapability = new a.PromiseCapability()),
                        (this._disableRange = c.disableRange || !1),
                        (this._rangeChunkSize = c.rangeChunkSize),
                        !this._rangeChunkSize &&
                          !this._disableRange &&
                          (this._disableRange = !0),
                        (this._abortController = new AbortController()),
                        (this._isStreamingSupported = !c.disableStream),
                        (this._isRangeSupported = !c.disableRange),
                        (this._headers = T(this._stream.httpHeaders)));
                      const n = c.url;
                      (fetch(
                        n,
                        k(
                          this._headers,
                          this._withCredentials,
                          this._abortController,
                        ),
                      )
                        .then((d) => {
                          if (!(0, p.validateResponseStatus)(d.status))
                            throw (0, p.createResponseStatusError)(d.status, n);
                          ((this._reader = d.body.getReader()),
                            this._headersCapability.resolve());
                          const m = (M) => d.headers.get(M),
                            { allowRangeRequests: l, suggestedLength: w } = (0,
                            p.validateRangeRequestCapabilities)({
                              getResponseHeader: m,
                              isHttp: this._stream.isHttp,
                              rangeChunkSize: this._rangeChunkSize,
                              disableRange: this._disableRange,
                            });
                          ((this._isRangeSupported = l),
                            (this._contentLength = w || this._contentLength),
                            (this._filename = (0, p.extractFilenameFromHeader)(
                              m,
                            )),
                            !this._isStreamingSupported &&
                              this._isRangeSupported &&
                              this.cancel(
                                new a.AbortException("Streaming is disabled."),
                              ));
                        })
                        .catch(this._headersCapability.reject),
                        (this.onProgress = null));
                    }
                    get headersReady() {
                      return this._headersCapability.promise;
                    }
                    get filename() {
                      return this._filename;
                    }
                    get contentLength() {
                      return this._contentLength;
                    }
                    get isRangeSupported() {
                      return this._isRangeSupported;
                    }
                    get isStreamingSupported() {
                      return this._isStreamingSupported;
                    }
                    async read() {
                      await this._headersCapability.promise;
                      const { value: h, done: c } = await this._reader.read();
                      return c
                        ? { value: h, done: c }
                        : ((this._loaded += h.byteLength),
                          this.onProgress?.({
                            loaded: this._loaded,
                            total: this._contentLength,
                          }),
                          { value: j(h), done: !1 });
                    }
                    cancel(h) {
                      (this._reader?.cancel(h), this._abortController.abort());
                    }
                  }
                  class t {
                    constructor(h, c, n) {
                      ((this._stream = h),
                        (this._reader = null),
                        (this._loaded = 0));
                      const d = h.source;
                      ((this._withCredentials = d.withCredentials || !1),
                        (this._readCapability = new a.PromiseCapability()),
                        (this._isStreamingSupported = !d.disableStream),
                        (this._abortController = new AbortController()),
                        (this._headers = T(this._stream.httpHeaders)),
                        this._headers.append("Range", `bytes=${c}-${n - 1}`));
                      const m = d.url;
                      (fetch(
                        m,
                        k(
                          this._headers,
                          this._withCredentials,
                          this._abortController,
                        ),
                      )
                        .then((l) => {
                          if (!(0, p.validateResponseStatus)(l.status))
                            throw (0, p.createResponseStatusError)(l.status, m);
                          (this._readCapability.resolve(),
                            (this._reader = l.body.getReader()));
                        })
                        .catch(this._readCapability.reject),
                        (this.onProgress = null));
                    }
                    get isStreamingSupported() {
                      return this._isStreamingSupported;
                    }
                    async read() {
                      await this._readCapability.promise;
                      const { value: h, done: c } = await this._reader.read();
                      return c
                        ? { value: h, done: c }
                        : ((this._loaded += h.byteLength),
                          this.onProgress?.({ loaded: this._loaded }),
                          { value: j(h), done: !1 });
                    }
                    cancel(h) {
                      (this._reader?.cancel(h), this._abortController.abort());
                    }
                  }
                },
                (A, e, y) => {
                  (Object.defineProperty(e, "__esModule", { value: !0 }),
                    (e.createResponseStatusError = D),
                    (e.extractFilenameFromHeader = j),
                    (e.validateRangeRequestCapabilities = T),
                    (e.validateResponseStatus = s));
                  var a = y(1),
                    p = y(21),
                    k = y(6);
                  function T({
                    getResponseHeader: t,
                    isHttp: i,
                    rangeChunkSize: h,
                    disableRange: c,
                  }) {
                    const n = {
                        allowRangeRequests: !1,
                        suggestedLength: void 0,
                      },
                      d = parseInt(t("Content-Length"), 10);
                    return (
                      !Number.isInteger(d) ||
                        ((n.suggestedLength = d), d <= 2 * h) ||
                        c ||
                        !i ||
                        t("Accept-Ranges") !== "bytes" ||
                        (t("Content-Encoding") || "identity") !== "identity" ||
                        (n.allowRangeRequests = !0),
                      n
                    );
                  }
                  function j(t) {
                    const i = t("Content-Disposition");
                    if (i) {
                      let h = (0, p.getFilenameFromContentDispositionHeader)(i);
                      if (h.includes("%"))
                        try {
                          h = decodeURIComponent(h);
                        } catch {}
                      if ((0, k.isPdfFile)(h)) return h;
                    }
                    return null;
                  }
                  function D(t, i) {
                    return t === 404 || (t === 0 && i.startsWith("file:"))
                      ? new a.MissingPDFException('Missing PDF "' + i + '".')
                      : new a.UnexpectedResponseException(
                          `Unexpected server response (${t}) while retrieving PDF "${i}".`,
                          t,
                        );
                  }
                  function s(t) {
                    return t === 200 || t === 206;
                  }
                },
                (A, e, y) => {
                  (Object.defineProperty(e, "__esModule", { value: !0 }),
                    (e.getFilenameFromContentDispositionHeader = p));
                  var a = y(1);
                  function p(k) {
                    let T = !0,
                      j = D("filename\\*", "i").exec(k);
                    if (j) {
                      j = j[1];
                      let d = h(j);
                      return ((d = unescape(d)), (d = c(d)), (d = n(d)), t(d));
                    }
                    if (((j = i(k)), j)) {
                      const d = n(j);
                      return t(d);
                    }
                    if (((j = D("filename", "i").exec(k)), j)) {
                      j = j[1];
                      let d = h(j);
                      return ((d = n(d)), t(d));
                    }
                    function D(d, m) {
                      return new RegExp(
                        "(?:^|;)\\s*" +
                          d +
                          '\\s*=\\s*([^";\\s][^;\\s]*|"(?:[^"\\\\]|\\\\"?)+"?)',
                        m,
                      );
                    }
                    function s(d, m) {
                      if (d) {
                        if (!/^[\x00-\xFF]+$/.test(m)) return m;
                        try {
                          const l = new TextDecoder(d, { fatal: !0 }),
                            w = (0, a.stringToBytes)(m);
                          ((m = l.decode(w)), (T = !1));
                        } catch {}
                      }
                      return m;
                    }
                    function t(d) {
                      return (
                        T &&
                          /[\x80-\xff]/.test(d) &&
                          ((d = s("utf-8", d)), T && (d = s("iso-8859-1", d))),
                        d
                      );
                    }
                    function i(d) {
                      const m = [];
                      let l;
                      const w = D("filename\\*((?!0\\d)\\d+)(\\*?)", "ig");
                      for (; (l = w.exec(d)) !== null;) {
                        let [, C, g, E] = l;
                        if (((C = parseInt(C, 10)), C in m)) {
                          if (C === 0) break;
                          continue;
                        }
                        m[C] = [g, E];
                      }
                      const M = [];
                      for (let C = 0; C < m.length && C in m; ++C) {
                        let [g, E] = m[C];
                        ((E = h(E)),
                          g && ((E = unescape(E)), C === 0 && (E = c(E))),
                          M.push(E));
                      }
                      return M.join("");
                    }
                    function h(d) {
                      if (d.startsWith('"')) {
                        const m = d.slice(1).split('\\"');
                        for (let l = 0; l < m.length; ++l) {
                          const w = m[l].indexOf('"');
                          (w !== -1 &&
                            ((m[l] = m[l].slice(0, w)), (m.length = l + 1)),
                            (m[l] = m[l].replaceAll(/\\(.)/g, "$1")));
                        }
                        d = m.join('"');
                      }
                      return d;
                    }
                    function c(d) {
                      const m = d.indexOf("'");
                      if (m === -1) return d;
                      const l = d.slice(0, m),
                        M = d.slice(m + 1).replace(/^[^']*'/, "");
                      return s(l, M);
                    }
                    function n(d) {
                      return !d.startsWith("=?") ||
                        /[\x00-\x19\x80-\xff]/.test(d)
                        ? d
                        : d.replaceAll(
                            /=\?([\w-]*)\?([QqBb])\?((?:[^?]|\?(?!=))*)\?=/g,
                            function (m, l, w, M) {
                              if (w === "q" || w === "Q")
                                return (
                                  (M = M.replaceAll("_", " ")),
                                  (M = M.replaceAll(
                                    /=([0-9a-fA-F]{2})/g,
                                    function (C, g) {
                                      return String.fromCharCode(
                                        parseInt(g, 16),
                                      );
                                    },
                                  )),
                                  s(l, M)
                                );
                              try {
                                M = atob(M);
                              } catch {}
                              return s(l, M);
                            },
                          );
                    }
                    return "";
                  }
                },
                (A, e, y) => {
                  (Object.defineProperty(e, "__esModule", { value: !0 }),
                    (e.PDFNetworkStream = void 0));
                  var a = y(1),
                    p = y(20);
                  const k = 200,
                    T = 206;
                  function j(h) {
                    const c = h.response;
                    return typeof c != "string"
                      ? c
                      : (0, a.stringToBytes)(c).buffer;
                  }
                  class D {
                    constructor(c, n = {}) {
                      ((this.url = c),
                        (this.isHttp = /^https?:/i.test(c)),
                        (this.httpHeaders =
                          (this.isHttp && n.httpHeaders) ||
                          Object.create(null)),
                        (this.withCredentials = n.withCredentials || !1),
                        (this.currXhrId = 0),
                        (this.pendingRequests = Object.create(null)));
                    }
                    requestRange(c, n, d) {
                      const m = { begin: c, end: n };
                      for (const l in d) m[l] = d[l];
                      return this.request(m);
                    }
                    requestFull(c) {
                      return this.request(c);
                    }
                    request(c) {
                      const n = new XMLHttpRequest(),
                        d = this.currXhrId++,
                        m = (this.pendingRequests[d] = { xhr: n });
                      (n.open("GET", this.url),
                        (n.withCredentials = this.withCredentials));
                      for (const l in this.httpHeaders) {
                        const w = this.httpHeaders[l];
                        w !== void 0 && n.setRequestHeader(l, w);
                      }
                      return (
                        this.isHttp && "begin" in c && "end" in c
                          ? (n.setRequestHeader(
                              "Range",
                              `bytes=${c.begin}-${c.end - 1}`,
                            ),
                            (m.expectedStatus = T))
                          : (m.expectedStatus = k),
                        (n.responseType = "arraybuffer"),
                        c.onError &&
                          (n.onerror = function (l) {
                            c.onError(n.status);
                          }),
                        (n.onreadystatechange = this.onStateChange.bind(
                          this,
                          d,
                        )),
                        (n.onprogress = this.onProgress.bind(this, d)),
                        (m.onHeadersReceived = c.onHeadersReceived),
                        (m.onDone = c.onDone),
                        (m.onError = c.onError),
                        (m.onProgress = c.onProgress),
                        n.send(null),
                        d
                      );
                    }
                    onProgress(c, n) {
                      const d = this.pendingRequests[c];
                      d && d.onProgress?.(n);
                    }
                    onStateChange(c, n) {
                      const d = this.pendingRequests[c];
                      if (!d) return;
                      const m = d.xhr;
                      if (
                        (m.readyState >= 2 &&
                          d.onHeadersReceived &&
                          (d.onHeadersReceived(), delete d.onHeadersReceived),
                        m.readyState !== 4 || !(c in this.pendingRequests))
                      )
                        return;
                      if (
                        (delete this.pendingRequests[c],
                        m.status === 0 && this.isHttp)
                      ) {
                        d.onError?.(m.status);
                        return;
                      }
                      const l = m.status || k;
                      if (
                        !(l === k && d.expectedStatus === T) &&
                        l !== d.expectedStatus
                      ) {
                        d.onError?.(m.status);
                        return;
                      }
                      const M = j(m);
                      if (l === T) {
                        const C = m.getResponseHeader("Content-Range"),
                          g = /bytes (\d+)-(\d+)\/(\d+)/.exec(C);
                        d.onDone({ begin: parseInt(g[1], 10), chunk: M });
                      } else
                        M
                          ? d.onDone({ begin: 0, chunk: M })
                          : d.onError?.(m.status);
                    }
                    getRequestXhr(c) {
                      return this.pendingRequests[c].xhr;
                    }
                    isPendingRequest(c) {
                      return c in this.pendingRequests;
                    }
                    abortRequest(c) {
                      const n = this.pendingRequests[c].xhr;
                      (delete this.pendingRequests[c], n.abort());
                    }
                  }
                  class s {
                    constructor(c) {
                      ((this._source = c),
                        (this._manager = new D(c.url, {
                          httpHeaders: c.httpHeaders,
                          withCredentials: c.withCredentials,
                        })),
                        (this._rangeChunkSize = c.rangeChunkSize),
                        (this._fullRequestReader = null),
                        (this._rangeRequestReaders = []));
                    }
                    _onRangeRequestReaderClosed(c) {
                      const n = this._rangeRequestReaders.indexOf(c);
                      n >= 0 && this._rangeRequestReaders.splice(n, 1);
                    }
                    getFullReader() {
                      return (
                        (0, a.assert)(
                          !this._fullRequestReader,
                          "PDFNetworkStream.getFullReader can only be called once.",
                        ),
                        (this._fullRequestReader = new t(
                          this._manager,
                          this._source,
                        )),
                        this._fullRequestReader
                      );
                    }
                    getRangeReader(c, n) {
                      const d = new i(this._manager, c, n);
                      return (
                        (d.onClosed =
                          this._onRangeRequestReaderClosed.bind(this)),
                        this._rangeRequestReaders.push(d),
                        d
                      );
                    }
                    cancelAllRequests(c) {
                      this._fullRequestReader?.cancel(c);
                      for (const n of this._rangeRequestReaders.slice(0))
                        n.cancel(c);
                    }
                  }
                  e.PDFNetworkStream = s;
                  class t {
                    constructor(c, n) {
                      this._manager = c;
                      const d = {
                        onHeadersReceived: this._onHeadersReceived.bind(this),
                        onDone: this._onDone.bind(this),
                        onError: this._onError.bind(this),
                        onProgress: this._onProgress.bind(this),
                      };
                      ((this._url = n.url),
                        (this._fullRequestId = c.requestFull(d)),
                        (this._headersReceivedCapability =
                          new a.PromiseCapability()),
                        (this._disableRange = n.disableRange || !1),
                        (this._contentLength = n.length),
                        (this._rangeChunkSize = n.rangeChunkSize),
                        !this._rangeChunkSize &&
                          !this._disableRange &&
                          (this._disableRange = !0),
                        (this._isStreamingSupported = !1),
                        (this._isRangeSupported = !1),
                        (this._cachedChunks = []),
                        (this._requests = []),
                        (this._done = !1),
                        (this._storedError = void 0),
                        (this._filename = null),
                        (this.onProgress = null));
                    }
                    _onHeadersReceived() {
                      const c = this._fullRequestId,
                        n = this._manager.getRequestXhr(c),
                        d = (w) => n.getResponseHeader(w),
                        { allowRangeRequests: m, suggestedLength: l } = (0,
                        p.validateRangeRequestCapabilities)({
                          getResponseHeader: d,
                          isHttp: this._manager.isHttp,
                          rangeChunkSize: this._rangeChunkSize,
                          disableRange: this._disableRange,
                        });
                      (m && (this._isRangeSupported = !0),
                        (this._contentLength = l || this._contentLength),
                        (this._filename = (0, p.extractFilenameFromHeader)(d)),
                        this._isRangeSupported && this._manager.abortRequest(c),
                        this._headersReceivedCapability.resolve());
                    }
                    _onDone(c) {
                      if (
                        (c &&
                          (this._requests.length > 0
                            ? this._requests
                                .shift()
                                .resolve({ value: c.chunk, done: !1 })
                            : this._cachedChunks.push(c.chunk)),
                        (this._done = !0),
                        !(this._cachedChunks.length > 0))
                      ) {
                        for (const n of this._requests)
                          n.resolve({ value: void 0, done: !0 });
                        this._requests.length = 0;
                      }
                    }
                    _onError(c) {
                      ((this._storedError = (0, p.createResponseStatusError)(
                        c,
                        this._url,
                      )),
                        this._headersReceivedCapability.reject(
                          this._storedError,
                        ));
                      for (const n of this._requests)
                        n.reject(this._storedError);
                      ((this._requests.length = 0),
                        (this._cachedChunks.length = 0));
                    }
                    _onProgress(c) {
                      this.onProgress?.({
                        loaded: c.loaded,
                        total: c.lengthComputable
                          ? c.total
                          : this._contentLength,
                      });
                    }
                    get filename() {
                      return this._filename;
                    }
                    get isRangeSupported() {
                      return this._isRangeSupported;
                    }
                    get isStreamingSupported() {
                      return this._isStreamingSupported;
                    }
                    get contentLength() {
                      return this._contentLength;
                    }
                    get headersReady() {
                      return this._headersReceivedCapability.promise;
                    }
                    async read() {
                      if (this._storedError) throw this._storedError;
                      if (this._cachedChunks.length > 0)
                        return { value: this._cachedChunks.shift(), done: !1 };
                      if (this._done) return { value: void 0, done: !0 };
                      const c = new a.PromiseCapability();
                      return (this._requests.push(c), c.promise);
                    }
                    cancel(c) {
                      ((this._done = !0),
                        this._headersReceivedCapability.reject(c));
                      for (const n of this._requests)
                        n.resolve({ value: void 0, done: !0 });
                      ((this._requests.length = 0),
                        this._manager.isPendingRequest(this._fullRequestId) &&
                          this._manager.abortRequest(this._fullRequestId),
                        (this._fullRequestReader = null));
                    }
                  }
                  class i {
                    constructor(c, n, d) {
                      this._manager = c;
                      const m = {
                        onDone: this._onDone.bind(this),
                        onError: this._onError.bind(this),
                        onProgress: this._onProgress.bind(this),
                      };
                      ((this._url = c.url),
                        (this._requestId = c.requestRange(n, d, m)),
                        (this._requests = []),
                        (this._queuedChunk = null),
                        (this._done = !1),
                        (this._storedError = void 0),
                        (this.onProgress = null),
                        (this.onClosed = null));
                    }
                    _close() {
                      this.onClosed?.(this);
                    }
                    _onDone(c) {
                      const n = c.chunk;
                      (this._requests.length > 0
                        ? this._requests.shift().resolve({ value: n, done: !1 })
                        : (this._queuedChunk = n),
                        (this._done = !0));
                      for (const d of this._requests)
                        d.resolve({ value: void 0, done: !0 });
                      ((this._requests.length = 0), this._close());
                    }
                    _onError(c) {
                      this._storedError = (0, p.createResponseStatusError)(
                        c,
                        this._url,
                      );
                      for (const n of this._requests)
                        n.reject(this._storedError);
                      ((this._requests.length = 0), (this._queuedChunk = null));
                    }
                    _onProgress(c) {
                      this.isStreamingSupported ||
                        this.onProgress?.({ loaded: c.loaded });
                    }
                    get isStreamingSupported() {
                      return !1;
                    }
                    async read() {
                      if (this._storedError) throw this._storedError;
                      if (this._queuedChunk !== null) {
                        const n = this._queuedChunk;
                        return (
                          (this._queuedChunk = null),
                          { value: n, done: !1 }
                        );
                      }
                      if (this._done) return { value: void 0, done: !0 };
                      const c = new a.PromiseCapability();
                      return (this._requests.push(c), c.promise);
                    }
                    cancel(c) {
                      this._done = !0;
                      for (const n of this._requests)
                        n.resolve({ value: void 0, done: !0 });
                      ((this._requests.length = 0),
                        this._manager.isPendingRequest(this._requestId) &&
                          this._manager.abortRequest(this._requestId),
                        this._close());
                    }
                  }
                },
                (A, e, y) => {
                  (Object.defineProperty(e, "__esModule", { value: !0 }),
                    (e.PDFNodeStream = void 0));
                  var a = y(1),
                    p = y(20);
                  const k = /^file:\/\/\/[a-zA-Z]:\//;
                  function T(d) {
                    const m = require$$2,
                      l = m.parse(d);
                    return l.protocol === "file:" || l.host
                      ? l
                      : /^[a-z]:[/\\]/i.test(d)
                        ? m.parse(`file:///${d}`)
                        : (l.host || (l.protocol = "file:"), l);
                  }
                  class j {
                    constructor(m) {
                      ((this.source = m),
                        (this.url = T(m.url)),
                        (this.isHttp =
                          this.url.protocol === "http:" ||
                          this.url.protocol === "https:"),
                        (this.isFsUrl = this.url.protocol === "file:"),
                        (this.httpHeaders =
                          (this.isHttp && m.httpHeaders) || {}),
                        (this._fullRequestReader = null),
                        (this._rangeRequestReaders = []));
                    }
                    get _progressiveDataLength() {
                      return this._fullRequestReader?._loaded ?? 0;
                    }
                    getFullReader() {
                      return (
                        (0, a.assert)(
                          !this._fullRequestReader,
                          "PDFNodeStream.getFullReader can only be called once.",
                        ),
                        (this._fullRequestReader = this.isFsUrl
                          ? new c(this)
                          : new i(this)),
                        this._fullRequestReader
                      );
                    }
                    getRangeReader(m, l) {
                      if (l <= this._progressiveDataLength) return null;
                      const w = this.isFsUrl
                        ? new n(this, m, l)
                        : new h(this, m, l);
                      return (this._rangeRequestReaders.push(w), w);
                    }
                    cancelAllRequests(m) {
                      this._fullRequestReader?.cancel(m);
                      for (const l of this._rangeRequestReaders.slice(0))
                        l.cancel(m);
                    }
                  }
                  e.PDFNodeStream = j;
                  class D {
                    constructor(m) {
                      ((this._url = m.url),
                        (this._done = !1),
                        (this._storedError = null),
                        (this.onProgress = null));
                      const l = m.source;
                      ((this._contentLength = l.length),
                        (this._loaded = 0),
                        (this._filename = null),
                        (this._disableRange = l.disableRange || !1),
                        (this._rangeChunkSize = l.rangeChunkSize),
                        !this._rangeChunkSize &&
                          !this._disableRange &&
                          (this._disableRange = !0),
                        (this._isStreamingSupported = !l.disableStream),
                        (this._isRangeSupported = !l.disableRange),
                        (this._readableStream = null),
                        (this._readCapability = new a.PromiseCapability()),
                        (this._headersCapability = new a.PromiseCapability()));
                    }
                    get headersReady() {
                      return this._headersCapability.promise;
                    }
                    get filename() {
                      return this._filename;
                    }
                    get contentLength() {
                      return this._contentLength;
                    }
                    get isRangeSupported() {
                      return this._isRangeSupported;
                    }
                    get isStreamingSupported() {
                      return this._isStreamingSupported;
                    }
                    async read() {
                      if ((await this._readCapability.promise, this._done))
                        return { value: void 0, done: !0 };
                      if (this._storedError) throw this._storedError;
                      const m = this._readableStream.read();
                      return m === null
                        ? ((this._readCapability = new a.PromiseCapability()),
                          this.read())
                        : ((this._loaded += m.length),
                          this.onProgress?.({
                            loaded: this._loaded,
                            total: this._contentLength,
                          }),
                          { value: new Uint8Array(m).buffer, done: !1 });
                    }
                    cancel(m) {
                      if (!this._readableStream) {
                        this._error(m);
                        return;
                      }
                      this._readableStream.destroy(m);
                    }
                    _error(m) {
                      ((this._storedError = m), this._readCapability.resolve());
                    }
                    _setReadableStream(m) {
                      ((this._readableStream = m),
                        m.on("readable", () => {
                          this._readCapability.resolve();
                        }),
                        m.on("end", () => {
                          (m.destroy(),
                            (this._done = !0),
                            this._readCapability.resolve());
                        }),
                        m.on("error", (l) => {
                          this._error(l);
                        }),
                        !this._isStreamingSupported &&
                          this._isRangeSupported &&
                          this._error(
                            new a.AbortException("streaming is disabled"),
                          ),
                        this._storedError &&
                          this._readableStream.destroy(this._storedError));
                    }
                  }
                  class s {
                    constructor(m) {
                      ((this._url = m.url),
                        (this._done = !1),
                        (this._storedError = null),
                        (this.onProgress = null),
                        (this._loaded = 0),
                        (this._readableStream = null),
                        (this._readCapability = new a.PromiseCapability()));
                      const l = m.source;
                      this._isStreamingSupported = !l.disableStream;
                    }
                    get isStreamingSupported() {
                      return this._isStreamingSupported;
                    }
                    async read() {
                      if ((await this._readCapability.promise, this._done))
                        return { value: void 0, done: !0 };
                      if (this._storedError) throw this._storedError;
                      const m = this._readableStream.read();
                      return m === null
                        ? ((this._readCapability = new a.PromiseCapability()),
                          this.read())
                        : ((this._loaded += m.length),
                          this.onProgress?.({ loaded: this._loaded }),
                          { value: new Uint8Array(m).buffer, done: !1 });
                    }
                    cancel(m) {
                      if (!this._readableStream) {
                        this._error(m);
                        return;
                      }
                      this._readableStream.destroy(m);
                    }
                    _error(m) {
                      ((this._storedError = m), this._readCapability.resolve());
                    }
                    _setReadableStream(m) {
                      ((this._readableStream = m),
                        m.on("readable", () => {
                          this._readCapability.resolve();
                        }),
                        m.on("end", () => {
                          (m.destroy(),
                            (this._done = !0),
                            this._readCapability.resolve());
                        }),
                        m.on("error", (l) => {
                          this._error(l);
                        }),
                        this._storedError &&
                          this._readableStream.destroy(this._storedError));
                    }
                  }
                  function t(d, m) {
                    return {
                      protocol: d.protocol,
                      auth: d.auth,
                      host: d.hostname,
                      port: d.port,
                      path: d.path,
                      method: "GET",
                      headers: m,
                    };
                  }
                  class i extends D {
                    constructor(m) {
                      super(m);
                      const l = (w) => {
                        if (w.statusCode === 404) {
                          const E = new a.MissingPDFException(
                            `Missing PDF "${this._url}".`,
                          );
                          ((this._storedError = E),
                            this._headersCapability.reject(E));
                          return;
                        }
                        (this._headersCapability.resolve(),
                          this._setReadableStream(w));
                        const M = (E) =>
                            this._readableStream.headers[E.toLowerCase()],
                          { allowRangeRequests: C, suggestedLength: g } = (0,
                          p.validateRangeRequestCapabilities)({
                            getResponseHeader: M,
                            isHttp: m.isHttp,
                            rangeChunkSize: this._rangeChunkSize,
                            disableRange: this._disableRange,
                          });
                        ((this._isRangeSupported = C),
                          (this._contentLength = g || this._contentLength),
                          (this._filename = (0, p.extractFilenameFromHeader)(
                            M,
                          )));
                      };
                      if (
                        ((this._request = null), this._url.protocol === "http:")
                      ) {
                        const w = require$$5;
                        this._request = w.request(
                          t(this._url, m.httpHeaders),
                          l,
                        );
                      } else {
                        const w = require$$5;
                        this._request = w.request(
                          t(this._url, m.httpHeaders),
                          l,
                        );
                      }
                      (this._request.on("error", (w) => {
                        ((this._storedError = w),
                          this._headersCapability.reject(w));
                      }),
                        this._request.end());
                    }
                  }
                  class h extends s {
                    constructor(m, l, w) {
                      (super(m), (this._httpHeaders = {}));
                      for (const C in m.httpHeaders) {
                        const g = m.httpHeaders[C];
                        g !== void 0 && (this._httpHeaders[C] = g);
                      }
                      this._httpHeaders.Range = `bytes=${l}-${w - 1}`;
                      const M = (C) => {
                        if (C.statusCode === 404) {
                          const g = new a.MissingPDFException(
                            `Missing PDF "${this._url}".`,
                          );
                          this._storedError = g;
                          return;
                        }
                        this._setReadableStream(C);
                      };
                      if (
                        ((this._request = null), this._url.protocol === "http:")
                      ) {
                        const C = require$$5;
                        this._request = C.request(
                          t(this._url, this._httpHeaders),
                          M,
                        );
                      } else {
                        const C = require$$5;
                        this._request = C.request(
                          t(this._url, this._httpHeaders),
                          M,
                        );
                      }
                      (this._request.on("error", (C) => {
                        this._storedError = C;
                      }),
                        this._request.end());
                    }
                  }
                  class c extends D {
                    constructor(m) {
                      super(m);
                      let l = decodeURIComponent(this._url.path);
                      k.test(this._url.href) && (l = l.replace(/^\//, ""));
                      const w = require$$0;
                      w.lstat(l, (M, C) => {
                        if (M) {
                          (M.code === "ENOENT" &&
                            (M = new a.MissingPDFException(
                              `Missing PDF "${l}".`,
                            )),
                            (this._storedError = M),
                            this._headersCapability.reject(M));
                          return;
                        }
                        ((this._contentLength = C.size),
                          this._setReadableStream(w.createReadStream(l)),
                          this._headersCapability.resolve());
                      });
                    }
                  }
                  class n extends s {
                    constructor(m, l, w) {
                      super(m);
                      let M = decodeURIComponent(this._url.path);
                      k.test(this._url.href) && (M = M.replace(/^\//, ""));
                      const C = require$$0;
                      this._setReadableStream(
                        C.createReadStream(M, { start: l, end: w - 1 }),
                      );
                    }
                  }
                },
                (A, e, y) => {
                  (Object.defineProperty(e, "__esModule", { value: !0 }),
                    (e.SVGGraphics = void 0));
                  var a = y(6),
                    p = y(1);
                  const k = {
                      fontStyle: "normal",
                      fontWeight: "normal",
                      fillColor: "#000000",
                    },
                    T = "http://www.w3.org/XML/1998/namespace",
                    j = "http://www.w3.org/1999/xlink",
                    D = ["butt", "round", "square"],
                    s = ["miter", "round", "bevel"],
                    t = function (C, g = "", E = !1) {
                      if (URL.createObjectURL && typeof Blob < "u" && !E)
                        return URL.createObjectURL(new Blob([C], { type: g }));
                      const U =
                        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=";
                      let W = `data:${g};base64,`;
                      for (let O = 0, V = C.length; O < V; O += 3) {
                        const G = C[O] & 255,
                          nt = C[O + 1] & 255,
                          Z = C[O + 2] & 255,
                          tt = G >> 2,
                          rt = ((G & 3) << 4) | (nt >> 4),
                          K = O + 1 < V ? ((nt & 15) << 2) | (Z >> 6) : 64,
                          I = O + 2 < V ? Z & 63 : 64;
                        W += U[tt] + U[rt] + U[K] + U[I];
                      }
                      return W;
                    },
                    i = (function () {
                      const C = new Uint8Array([
                          137, 80, 78, 71, 13, 10, 26, 10,
                        ]),
                        g = 12,
                        E = new Int32Array(256);
                      for (let Z = 0; Z < 256; Z++) {
                        let tt = Z;
                        for (let rt = 0; rt < 8; rt++)
                          tt =
                            tt & 1
                              ? 3988292384 ^ ((tt >> 1) & 2147483647)
                              : (tt >> 1) & 2147483647;
                        E[Z] = tt;
                      }
                      function U(Z, tt, rt) {
                        let K = -1;
                        for (let I = tt; I < rt; I++) {
                          const _ = (K ^ Z[I]) & 255,
                            u = E[_];
                          K = (K >>> 8) ^ u;
                        }
                        return K ^ -1;
                      }
                      function W(Z, tt, rt, K) {
                        let I = K;
                        const _ = tt.length;
                        ((rt[I] = (_ >> 24) & 255),
                          (rt[I + 1] = (_ >> 16) & 255),
                          (rt[I + 2] = (_ >> 8) & 255),
                          (rt[I + 3] = _ & 255),
                          (I += 4),
                          (rt[I] = Z.charCodeAt(0) & 255),
                          (rt[I + 1] = Z.charCodeAt(1) & 255),
                          (rt[I + 2] = Z.charCodeAt(2) & 255),
                          (rt[I + 3] = Z.charCodeAt(3) & 255),
                          (I += 4),
                          rt.set(tt, I),
                          (I += tt.length));
                        const u = U(rt, K + 4, I);
                        ((rt[I] = (u >> 24) & 255),
                          (rt[I + 1] = (u >> 16) & 255),
                          (rt[I + 2] = (u >> 8) & 255),
                          (rt[I + 3] = u & 255));
                      }
                      function O(Z, tt, rt) {
                        let K = 1,
                          I = 0;
                        for (let _ = tt; _ < rt; ++_)
                          ((K = (K + (Z[_] & 255)) % 65521),
                            (I = (I + K) % 65521));
                        return (I << 16) | K;
                      }
                      function V(Z) {
                        if (!p.isNodeJS) return G(Z);
                        try {
                          const tt =
                              parseInt(process$1.versions.node) >= 8
                                ? Z
                                : Buffer.from(Z),
                            rt = require$$5.deflateSync(tt, { level: 9 });
                          return rt instanceof Uint8Array
                            ? rt
                            : new Uint8Array(rt);
                        } catch (tt) {
                          (0, p.warn)(
                            "Not compressing PNG because zlib.deflateSync is unavailable: " +
                              tt,
                          );
                        }
                        return G(Z);
                      }
                      function G(Z) {
                        let tt = Z.length;
                        const rt = 65535,
                          K = Math.ceil(tt / rt),
                          I = new Uint8Array(2 + tt + K * 5 + 4);
                        let _ = 0;
                        ((I[_++] = 120), (I[_++] = 156));
                        let u = 0;
                        for (; tt > rt;)
                          ((I[_++] = 0),
                            (I[_++] = 255),
                            (I[_++] = 255),
                            (I[_++] = 0),
                            (I[_++] = 0),
                            I.set(Z.subarray(u, u + rt), _),
                            (_ += rt),
                            (u += rt),
                            (tt -= rt));
                        ((I[_++] = 1),
                          (I[_++] = tt & 255),
                          (I[_++] = (tt >> 8) & 255),
                          (I[_++] = ~tt & 65535 & 255),
                          (I[_++] = ((~tt & 65535) >> 8) & 255),
                          I.set(Z.subarray(u), _),
                          (_ += Z.length - u));
                        const f = O(Z, 0, Z.length);
                        return (
                          (I[_++] = (f >> 24) & 255),
                          (I[_++] = (f >> 16) & 255),
                          (I[_++] = (f >> 8) & 255),
                          (I[_++] = f & 255),
                          I
                        );
                      }
                      function nt(Z, tt, rt, K) {
                        const I = Z.width,
                          _ = Z.height;
                        let u, f, v;
                        const F = Z.data;
                        switch (tt) {
                          case p.ImageKind.GRAYSCALE_1BPP:
                            ((f = 0), (u = 1), (v = (I + 7) >> 3));
                            break;
                          case p.ImageKind.RGB_24BPP:
                            ((f = 2), (u = 8), (v = I * 3));
                            break;
                          case p.ImageKind.RGBA_32BPP:
                            ((f = 6), (u = 8), (v = I * 4));
                            break;
                          default:
                            throw new Error("invalid format");
                        }
                        const L = new Uint8Array((1 + v) * _);
                        let N = 0,
                          R = 0;
                        for (let B = 0; B < _; ++B)
                          ((L[N++] = 0),
                            L.set(F.subarray(R, R + v), N),
                            (R += v),
                            (N += v));
                        if (tt === p.ImageKind.GRAYSCALE_1BPP && K) {
                          N = 0;
                          for (let B = 0; B < _; B++) {
                            N++;
                            for (let H = 0; H < v; H++) L[N++] ^= 255;
                          }
                        }
                        const o = new Uint8Array([
                            (I >> 24) & 255,
                            (I >> 16) & 255,
                            (I >> 8) & 255,
                            I & 255,
                            (_ >> 24) & 255,
                            (_ >> 16) & 255,
                            (_ >> 8) & 255,
                            _ & 255,
                            u,
                            f,
                            0,
                            0,
                            0,
                          ]),
                          b = V(L),
                          S = C.length + g * 3 + o.length + b.length,
                          x = new Uint8Array(S);
                        let P = 0;
                        return (
                          x.set(C, P),
                          (P += C.length),
                          W("IHDR", o, x, P),
                          (P += g + o.length),
                          W("IDATA", b, x, P),
                          (P += g + b.length),
                          W("IEND", new Uint8Array(0), x, P),
                          t(x, "image/png", rt)
                        );
                      }
                      return function (tt, rt, K) {
                        const I =
                          tt.kind === void 0
                            ? p.ImageKind.GRAYSCALE_1BPP
                            : tt.kind;
                        return nt(tt, I, rt, K);
                      };
                    })();
                  class h {
                    constructor() {
                      ((this.fontSizeScale = 1),
                        (this.fontWeight = k.fontWeight),
                        (this.fontSize = 0),
                        (this.textMatrix = p.IDENTITY_MATRIX),
                        (this.fontMatrix = p.FONT_IDENTITY_MATRIX),
                        (this.leading = 0),
                        (this.textRenderingMode = p.TextRenderingMode.FILL),
                        (this.textMatrixScale = 1),
                        (this.x = 0),
                        (this.y = 0),
                        (this.lineX = 0),
                        (this.lineY = 0),
                        (this.charSpacing = 0),
                        (this.wordSpacing = 0),
                        (this.textHScale = 1),
                        (this.textRise = 0),
                        (this.fillColor = k.fillColor),
                        (this.strokeColor = "#000000"),
                        (this.fillAlpha = 1),
                        (this.strokeAlpha = 1),
                        (this.lineWidth = 1),
                        (this.lineJoin = ""),
                        (this.lineCap = ""),
                        (this.miterLimit = 0),
                        (this.dashArray = []),
                        (this.dashPhase = 0),
                        (this.dependencies = []),
                        (this.activeClipUrl = null),
                        (this.clipGroup = null),
                        (this.maskId = ""));
                    }
                    clone() {
                      return Object.create(this);
                    }
                    setCurrentPoint(g, E) {
                      ((this.x = g), (this.y = E));
                    }
                  }
                  function c(C) {
                    let g = [];
                    const E = [];
                    for (const U of C) {
                      if (U.fn === "save") {
                        (g.push({ fnId: 92, fn: "group", items: [] }),
                          E.push(g),
                          (g = g.at(-1).items));
                        continue;
                      }
                      U.fn === "restore" ? (g = E.pop()) : g.push(U);
                    }
                    return g;
                  }
                  function n(C) {
                    if (Number.isInteger(C)) return C.toString();
                    const g = C.toFixed(10);
                    let E = g.length - 1;
                    if (g[E] !== "0") return g;
                    do E--;
                    while (g[E] === "0");
                    return g.substring(0, g[E] === "." ? E : E + 1);
                  }
                  function d(C) {
                    if (C[4] === 0 && C[5] === 0) {
                      if (C[1] === 0 && C[2] === 0)
                        return C[0] === 1 && C[3] === 1
                          ? ""
                          : `scale(${n(C[0])} ${n(C[3])})`;
                      if (C[0] === C[3] && C[1] === -C[2]) {
                        const g = (Math.acos(C[0]) * 180) / Math.PI;
                        return `rotate(${n(g)})`;
                      }
                    } else if (
                      C[0] === 1 &&
                      C[1] === 0 &&
                      C[2] === 0 &&
                      C[3] === 1
                    )
                      return `translate(${n(C[4])} ${n(C[5])})`;
                    return `matrix(${n(C[0])} ${n(C[1])} ${n(C[2])} ${n(C[3])} ${n(C[4])} ${n(C[5])})`;
                  }
                  let m = 0,
                    l = 0,
                    w = 0;
                  class M {
                    constructor(g, E, U = !1) {
                      ((0, a.deprecated)(
                        "The SVG back-end is no longer maintained and *may* be removed in the future.",
                      ),
                        (this.svgFactory = new a.DOMSVGFactory()),
                        (this.current = new h()),
                        (this.transformMatrix = p.IDENTITY_MATRIX),
                        (this.transformStack = []),
                        (this.extraStack = []),
                        (this.commonObjs = g),
                        (this.objs = E),
                        (this.pendingClip = null),
                        (this.pendingEOFill = !1),
                        (this.embedFonts = !1),
                        (this.embeddedFonts = Object.create(null)),
                        (this.cssStyle = null),
                        (this.forceDataSchema = !!U),
                        (this._operatorIdMapping = []));
                      for (const W in p.OPS)
                        this._operatorIdMapping[p.OPS[W]] = W;
                    }
                    getObject(g, E = null) {
                      return typeof g == "string"
                        ? g.startsWith("g_")
                          ? this.commonObjs.get(g)
                          : this.objs.get(g)
                        : E;
                    }
                    save() {
                      this.transformStack.push(this.transformMatrix);
                      const g = this.current;
                      (this.extraStack.push(g), (this.current = g.clone()));
                    }
                    restore() {
                      ((this.transformMatrix = this.transformStack.pop()),
                        (this.current = this.extraStack.pop()),
                        (this.pendingClip = null),
                        (this.tgrp = null));
                    }
                    group(g) {
                      (this.save(), this.executeOpTree(g), this.restore());
                    }
                    loadDependencies(g) {
                      const E = g.fnArray,
                        U = g.argsArray;
                      for (let W = 0, O = E.length; W < O; W++)
                        if (E[W] === p.OPS.dependency)
                          for (const V of U[W]) {
                            const G = V.startsWith("g_")
                                ? this.commonObjs
                                : this.objs,
                              nt = new Promise((Z) => {
                                G.get(V, Z);
                              });
                            this.current.dependencies.push(nt);
                          }
                      return Promise.all(this.current.dependencies);
                    }
                    transform(g, E, U, W, O, V) {
                      const G = [g, E, U, W, O, V];
                      ((this.transformMatrix = p.Util.transform(
                        this.transformMatrix,
                        G,
                      )),
                        (this.tgrp = null));
                    }
                    getSVG(g, E) {
                      this.viewport = E;
                      const U = this._initialize(E);
                      return this.loadDependencies(g).then(
                        () => (
                          (this.transformMatrix = p.IDENTITY_MATRIX),
                          this.executeOpTree(this.convertOpList(g)),
                          U
                        ),
                      );
                    }
                    convertOpList(g) {
                      const E = this._operatorIdMapping,
                        U = g.argsArray,
                        W = g.fnArray,
                        O = [];
                      for (let V = 0, G = W.length; V < G; V++) {
                        const nt = W[V];
                        O.push({ fnId: nt, fn: E[nt], args: U[V] });
                      }
                      return c(O);
                    }
                    executeOpTree(g) {
                      for (const E of g) {
                        const U = E.fn,
                          W = E.fnId,
                          O = E.args;
                        switch (W | 0) {
                          case p.OPS.beginText:
                            this.beginText();
                            break;
                          case p.OPS.dependency:
                            break;
                          case p.OPS.setLeading:
                            this.setLeading(O);
                            break;
                          case p.OPS.setLeadingMoveText:
                            this.setLeadingMoveText(O[0], O[1]);
                            break;
                          case p.OPS.setFont:
                            this.setFont(O);
                            break;
                          case p.OPS.showText:
                            this.showText(O[0]);
                            break;
                          case p.OPS.showSpacedText:
                            this.showText(O[0]);
                            break;
                          case p.OPS.endText:
                            this.endText();
                            break;
                          case p.OPS.moveText:
                            this.moveText(O[0], O[1]);
                            break;
                          case p.OPS.setCharSpacing:
                            this.setCharSpacing(O[0]);
                            break;
                          case p.OPS.setWordSpacing:
                            this.setWordSpacing(O[0]);
                            break;
                          case p.OPS.setHScale:
                            this.setHScale(O[0]);
                            break;
                          case p.OPS.setTextMatrix:
                            this.setTextMatrix(
                              O[0],
                              O[1],
                              O[2],
                              O[3],
                              O[4],
                              O[5],
                            );
                            break;
                          case p.OPS.setTextRise:
                            this.setTextRise(O[0]);
                            break;
                          case p.OPS.setTextRenderingMode:
                            this.setTextRenderingMode(O[0]);
                            break;
                          case p.OPS.setLineWidth:
                            this.setLineWidth(O[0]);
                            break;
                          case p.OPS.setLineJoin:
                            this.setLineJoin(O[0]);
                            break;
                          case p.OPS.setLineCap:
                            this.setLineCap(O[0]);
                            break;
                          case p.OPS.setMiterLimit:
                            this.setMiterLimit(O[0]);
                            break;
                          case p.OPS.setFillRGBColor:
                            this.setFillRGBColor(O[0], O[1], O[2]);
                            break;
                          case p.OPS.setStrokeRGBColor:
                            this.setStrokeRGBColor(O[0], O[1], O[2]);
                            break;
                          case p.OPS.setStrokeColorN:
                            this.setStrokeColorN(O);
                            break;
                          case p.OPS.setFillColorN:
                            this.setFillColorN(O);
                            break;
                          case p.OPS.shadingFill:
                            this.shadingFill(O[0]);
                            break;
                          case p.OPS.setDash:
                            this.setDash(O[0], O[1]);
                            break;
                          case p.OPS.setRenderingIntent:
                            this.setRenderingIntent(O[0]);
                            break;
                          case p.OPS.setFlatness:
                            this.setFlatness(O[0]);
                            break;
                          case p.OPS.setGState:
                            this.setGState(O[0]);
                            break;
                          case p.OPS.fill:
                            this.fill();
                            break;
                          case p.OPS.eoFill:
                            this.eoFill();
                            break;
                          case p.OPS.stroke:
                            this.stroke();
                            break;
                          case p.OPS.fillStroke:
                            this.fillStroke();
                            break;
                          case p.OPS.eoFillStroke:
                            this.eoFillStroke();
                            break;
                          case p.OPS.clip:
                            this.clip("nonzero");
                            break;
                          case p.OPS.eoClip:
                            this.clip("evenodd");
                            break;
                          case p.OPS.paintSolidColorImageMask:
                            this.paintSolidColorImageMask();
                            break;
                          case p.OPS.paintImageXObject:
                            this.paintImageXObject(O[0]);
                            break;
                          case p.OPS.paintInlineImageXObject:
                            this.paintInlineImageXObject(O[0]);
                            break;
                          case p.OPS.paintImageMaskXObject:
                            this.paintImageMaskXObject(O[0]);
                            break;
                          case p.OPS.paintFormXObjectBegin:
                            this.paintFormXObjectBegin(O[0], O[1]);
                            break;
                          case p.OPS.paintFormXObjectEnd:
                            this.paintFormXObjectEnd();
                            break;
                          case p.OPS.closePath:
                            this.closePath();
                            break;
                          case p.OPS.closeStroke:
                            this.closeStroke();
                            break;
                          case p.OPS.closeFillStroke:
                            this.closeFillStroke();
                            break;
                          case p.OPS.closeEOFillStroke:
                            this.closeEOFillStroke();
                            break;
                          case p.OPS.nextLine:
                            this.nextLine();
                            break;
                          case p.OPS.transform:
                            this.transform(O[0], O[1], O[2], O[3], O[4], O[5]);
                            break;
                          case p.OPS.constructPath:
                            this.constructPath(O[0], O[1]);
                            break;
                          case p.OPS.endPath:
                            this.endPath();
                            break;
                          case 92:
                            this.group(E.items);
                            break;
                          default:
                            (0, p.warn)(`Unimplemented operator ${U}`);
                            break;
                        }
                      }
                    }
                    setWordSpacing(g) {
                      this.current.wordSpacing = g;
                    }
                    setCharSpacing(g) {
                      this.current.charSpacing = g;
                    }
                    nextLine() {
                      this.moveText(0, this.current.leading);
                    }
                    setTextMatrix(g, E, U, W, O, V) {
                      const G = this.current;
                      ((G.textMatrix = G.lineMatrix = [g, E, U, W, O, V]),
                        (G.textMatrixScale = Math.hypot(g, E)),
                        (G.x = G.lineX = 0),
                        (G.y = G.lineY = 0),
                        (G.xcoords = []),
                        (G.ycoords = []),
                        (G.tspan = this.svgFactory.createElement("svg:tspan")),
                        G.tspan.setAttributeNS(
                          null,
                          "font-family",
                          G.fontFamily,
                        ),
                        G.tspan.setAttributeNS(
                          null,
                          "font-size",
                          `${n(G.fontSize)}px`,
                        ),
                        G.tspan.setAttributeNS(null, "y", n(-G.y)),
                        (G.txtElement =
                          this.svgFactory.createElement("svg:text")),
                        G.txtElement.append(G.tspan));
                    }
                    beginText() {
                      const g = this.current;
                      ((g.x = g.lineX = 0),
                        (g.y = g.lineY = 0),
                        (g.textMatrix = p.IDENTITY_MATRIX),
                        (g.lineMatrix = p.IDENTITY_MATRIX),
                        (g.textMatrixScale = 1),
                        (g.tspan = this.svgFactory.createElement("svg:tspan")),
                        (g.txtElement =
                          this.svgFactory.createElement("svg:text")),
                        (g.txtgrp = this.svgFactory.createElement("svg:g")),
                        (g.xcoords = []),
                        (g.ycoords = []));
                    }
                    moveText(g, E) {
                      const U = this.current;
                      ((U.x = U.lineX += g),
                        (U.y = U.lineY += E),
                        (U.xcoords = []),
                        (U.ycoords = []),
                        (U.tspan = this.svgFactory.createElement("svg:tspan")),
                        U.tspan.setAttributeNS(
                          null,
                          "font-family",
                          U.fontFamily,
                        ),
                        U.tspan.setAttributeNS(
                          null,
                          "font-size",
                          `${n(U.fontSize)}px`,
                        ),
                        U.tspan.setAttributeNS(null, "y", n(-U.y)));
                    }
                    showText(g) {
                      const E = this.current,
                        U = E.font,
                        W = E.fontSize;
                      if (W === 0) return;
                      const O = E.fontSizeScale,
                        V = E.charSpacing,
                        G = E.wordSpacing,
                        nt = E.fontDirection,
                        Z = E.textHScale * nt,
                        tt = U.vertical,
                        rt = tt ? 1 : -1,
                        K = U.defaultVMetrics,
                        I = W * E.fontMatrix[0];
                      let _ = 0;
                      for (const v of g) {
                        if (v === null) {
                          _ += nt * G;
                          continue;
                        } else if (typeof v == "number") {
                          _ += (rt * v * W) / 1e3;
                          continue;
                        }
                        const F = (v.isSpace ? G : 0) + V,
                          L = v.fontChar;
                        let N,
                          R,
                          o = v.width;
                        if (tt) {
                          let S;
                          const x = v.vmetric || K;
                          ((S = v.vmetric ? x[1] : o * 0.5), (S = -S * I));
                          const P = x[2] * I;
                          ((o = x ? -x[0] : o), (N = S / O), (R = (_ + P) / O));
                        } else ((N = _ / O), (R = 0));
                        (v.isInFont || U.missingFile) &&
                          (E.xcoords.push(E.x + N),
                          tt && E.ycoords.push(-E.y + R),
                          (E.tspan.textContent += L));
                        const b = tt ? o * I - F * nt : o * I + F * nt;
                        _ += b;
                      }
                      (E.tspan.setAttributeNS(
                        null,
                        "x",
                        E.xcoords.map(n).join(" "),
                      ),
                        tt
                          ? E.tspan.setAttributeNS(
                              null,
                              "y",
                              E.ycoords.map(n).join(" "),
                            )
                          : E.tspan.setAttributeNS(null, "y", n(-E.y)),
                        tt ? (E.y -= _) : (E.x += _ * Z),
                        E.tspan.setAttributeNS(
                          null,
                          "font-family",
                          E.fontFamily,
                        ),
                        E.tspan.setAttributeNS(
                          null,
                          "font-size",
                          `${n(E.fontSize)}px`,
                        ),
                        E.fontStyle !== k.fontStyle &&
                          E.tspan.setAttributeNS(
                            null,
                            "font-style",
                            E.fontStyle,
                          ),
                        E.fontWeight !== k.fontWeight &&
                          E.tspan.setAttributeNS(
                            null,
                            "font-weight",
                            E.fontWeight,
                          ));
                      const u =
                        E.textRenderingMode &
                        p.TextRenderingMode.FILL_STROKE_MASK;
                      if (
                        (u === p.TextRenderingMode.FILL ||
                        u === p.TextRenderingMode.FILL_STROKE
                          ? (E.fillColor !== k.fillColor &&
                              E.tspan.setAttributeNS(null, "fill", E.fillColor),
                            E.fillAlpha < 1 &&
                              E.tspan.setAttributeNS(
                                null,
                                "fill-opacity",
                                E.fillAlpha,
                              ))
                          : E.textRenderingMode ===
                              p.TextRenderingMode.ADD_TO_PATH
                            ? E.tspan.setAttributeNS(
                                null,
                                "fill",
                                "transparent",
                              )
                            : E.tspan.setAttributeNS(null, "fill", "none"),
                        u === p.TextRenderingMode.STROKE ||
                          u === p.TextRenderingMode.FILL_STROKE)
                      ) {
                        const v = 1 / (E.textMatrixScale || 1);
                        this._setStrokeAttributes(E.tspan, v);
                      }
                      let f = E.textMatrix;
                      (E.textRise !== 0 &&
                        ((f = f.slice()), (f[5] += E.textRise)),
                        E.txtElement.setAttributeNS(
                          null,
                          "transform",
                          `${d(f)} scale(${n(Z)}, -1)`,
                        ),
                        E.txtElement.setAttributeNS(T, "xml:space", "preserve"),
                        E.txtElement.append(E.tspan),
                        E.txtgrp.append(E.txtElement),
                        this._ensureTransformGroup().append(E.txtElement));
                    }
                    setLeadingMoveText(g, E) {
                      (this.setLeading(-E), this.moveText(g, E));
                    }
                    addFontStyle(g) {
                      if (!g.data)
                        throw new Error(
                          'addFontStyle: No font data available, ensure that the "fontExtraProperties" API parameter is set.',
                        );
                      this.cssStyle ||
                        ((this.cssStyle =
                          this.svgFactory.createElement("svg:style")),
                        this.cssStyle.setAttributeNS(null, "type", "text/css"),
                        this.defs.append(this.cssStyle));
                      const E = t(g.data, g.mimetype, this.forceDataSchema);
                      this.cssStyle.textContent += `@font-face { font-family: "${g.loadedName}"; src: url(${E}); }
`;
                    }
                    setFont(g) {
                      const E = this.current,
                        U = this.commonObjs.get(g[0]);
                      let W = g[1];
                      ((E.font = U),
                        this.embedFonts &&
                          !U.missingFile &&
                          !this.embeddedFonts[U.loadedName] &&
                          (this.addFontStyle(U),
                          (this.embeddedFonts[U.loadedName] = U)),
                        (E.fontMatrix =
                          U.fontMatrix || p.FONT_IDENTITY_MATRIX));
                      let O = "normal";
                      U.black ? (O = "900") : U.bold && (O = "bold");
                      const V = U.italic ? "italic" : "normal";
                      (W < 0
                        ? ((W = -W), (E.fontDirection = -1))
                        : (E.fontDirection = 1),
                        (E.fontSize = W),
                        (E.fontFamily = U.loadedName),
                        (E.fontWeight = O),
                        (E.fontStyle = V),
                        (E.tspan = this.svgFactory.createElement("svg:tspan")),
                        E.tspan.setAttributeNS(null, "y", n(-E.y)),
                        (E.xcoords = []),
                        (E.ycoords = []));
                    }
                    endText() {
                      const g = this.current;
                      g.textRenderingMode &
                        p.TextRenderingMode.ADD_TO_PATH_FLAG &&
                        g.txtElement?.hasChildNodes() &&
                        ((g.element = g.txtElement),
                        this.clip("nonzero"),
                        this.endPath());
                    }
                    setLineWidth(g) {
                      g > 0 && (this.current.lineWidth = g);
                    }
                    setLineCap(g) {
                      this.current.lineCap = D[g];
                    }
                    setLineJoin(g) {
                      this.current.lineJoin = s[g];
                    }
                    setMiterLimit(g) {
                      this.current.miterLimit = g;
                    }
                    setStrokeAlpha(g) {
                      this.current.strokeAlpha = g;
                    }
                    setStrokeRGBColor(g, E, U) {
                      this.current.strokeColor = p.Util.makeHexColor(g, E, U);
                    }
                    setFillAlpha(g) {
                      this.current.fillAlpha = g;
                    }
                    setFillRGBColor(g, E, U) {
                      ((this.current.fillColor = p.Util.makeHexColor(g, E, U)),
                        (this.current.tspan =
                          this.svgFactory.createElement("svg:tspan")),
                        (this.current.xcoords = []),
                        (this.current.ycoords = []));
                    }
                    setStrokeColorN(g) {
                      this.current.strokeColor = this._makeColorN_Pattern(g);
                    }
                    setFillColorN(g) {
                      this.current.fillColor = this._makeColorN_Pattern(g);
                    }
                    shadingFill(g) {
                      const { width: E, height: U } = this.viewport,
                        W = p.Util.inverseTransform(this.transformMatrix),
                        [O, V, G, nt] = p.Util.getAxialAlignedBoundingBox(
                          [0, 0, E, U],
                          W,
                        ),
                        Z = this.svgFactory.createElement("svg:rect");
                      (Z.setAttributeNS(null, "x", O),
                        Z.setAttributeNS(null, "y", V),
                        Z.setAttributeNS(null, "width", G - O),
                        Z.setAttributeNS(null, "height", nt - V),
                        Z.setAttributeNS(
                          null,
                          "fill",
                          this._makeShadingPattern(g),
                        ),
                        this.current.fillAlpha < 1 &&
                          Z.setAttributeNS(
                            null,
                            "fill-opacity",
                            this.current.fillAlpha,
                          ),
                        this._ensureTransformGroup().append(Z));
                    }
                    _makeColorN_Pattern(g) {
                      return g[0] === "TilingPattern"
                        ? this._makeTilingPattern(g)
                        : this._makeShadingPattern(g);
                    }
                    _makeTilingPattern(g) {
                      const E = g[1],
                        U = g[2],
                        W = g[3] || p.IDENTITY_MATRIX,
                        [O, V, G, nt] = g[4],
                        Z = g[5],
                        tt = g[6],
                        rt = g[7],
                        K = `shading${w++}`,
                        [I, _, u, f] = p.Util.normalizeRect([
                          ...p.Util.applyTransform([O, V], W),
                          ...p.Util.applyTransform([G, nt], W),
                        ]),
                        [v, F] = p.Util.singularValueDecompose2dScale(W),
                        L = Z * v,
                        N = tt * F,
                        R = this.svgFactory.createElement("svg:pattern");
                      (R.setAttributeNS(null, "id", K),
                        R.setAttributeNS(
                          null,
                          "patternUnits",
                          "userSpaceOnUse",
                        ),
                        R.setAttributeNS(null, "width", L),
                        R.setAttributeNS(null, "height", N),
                        R.setAttributeNS(null, "x", `${I}`),
                        R.setAttributeNS(null, "y", `${_}`));
                      const o = this.svg,
                        b = this.transformMatrix,
                        S = this.current.fillColor,
                        x = this.current.strokeColor,
                        P = this.svgFactory.create(u - I, f - _);
                      if (
                        ((this.svg = P), (this.transformMatrix = W), rt === 2)
                      ) {
                        const B = p.Util.makeHexColor(...E);
                        ((this.current.fillColor = B),
                          (this.current.strokeColor = B));
                      }
                      return (
                        this.executeOpTree(this.convertOpList(U)),
                        (this.svg = o),
                        (this.transformMatrix = b),
                        (this.current.fillColor = S),
                        (this.current.strokeColor = x),
                        R.append(P.childNodes[0]),
                        this.defs.append(R),
                        `url(#${K})`
                      );
                    }
                    _makeShadingPattern(g) {
                      switch (
                        (typeof g == "string" && (g = this.objs.get(g)), g[0])
                      ) {
                        case "RadialAxial":
                          const E = `shading${w++}`,
                            U = g[3];
                          let W;
                          switch (g[1]) {
                            case "axial":
                              const O = g[4],
                                V = g[5];
                              ((W =
                                this.svgFactory.createElement(
                                  "svg:linearGradient",
                                )),
                                W.setAttributeNS(null, "id", E),
                                W.setAttributeNS(
                                  null,
                                  "gradientUnits",
                                  "userSpaceOnUse",
                                ),
                                W.setAttributeNS(null, "x1", O[0]),
                                W.setAttributeNS(null, "y1", O[1]),
                                W.setAttributeNS(null, "x2", V[0]),
                                W.setAttributeNS(null, "y2", V[1]));
                              break;
                            case "radial":
                              const G = g[4],
                                nt = g[5],
                                Z = g[6],
                                tt = g[7];
                              ((W =
                                this.svgFactory.createElement(
                                  "svg:radialGradient",
                                )),
                                W.setAttributeNS(null, "id", E),
                                W.setAttributeNS(
                                  null,
                                  "gradientUnits",
                                  "userSpaceOnUse",
                                ),
                                W.setAttributeNS(null, "cx", nt[0]),
                                W.setAttributeNS(null, "cy", nt[1]),
                                W.setAttributeNS(null, "r", tt),
                                W.setAttributeNS(null, "fx", G[0]),
                                W.setAttributeNS(null, "fy", G[1]),
                                W.setAttributeNS(null, "fr", Z));
                              break;
                            default:
                              throw new Error(
                                `Unknown RadialAxial type: ${g[1]}`,
                              );
                          }
                          for (const O of U) {
                            const V = this.svgFactory.createElement("svg:stop");
                            (V.setAttributeNS(null, "offset", O[0]),
                              V.setAttributeNS(null, "stop-color", O[1]),
                              W.append(V));
                          }
                          return (this.defs.append(W), `url(#${E})`);
                        case "Mesh":
                          return (
                            (0, p.warn)("Unimplemented pattern Mesh"),
                            null
                          );
                        case "Dummy":
                          return "hotpink";
                        default:
                          throw new Error(`Unknown IR type: ${g[0]}`);
                      }
                    }
                    setDash(g, E) {
                      ((this.current.dashArray = g),
                        (this.current.dashPhase = E));
                    }
                    constructPath(g, E) {
                      const U = this.current;
                      let W = U.x,
                        O = U.y,
                        V = [],
                        G = 0;
                      for (const nt of g)
                        switch (nt | 0) {
                          case p.OPS.rectangle:
                            ((W = E[G++]), (O = E[G++]));
                            const Z = E[G++],
                              tt = E[G++],
                              rt = W + Z,
                              K = O + tt;
                            V.push(
                              "M",
                              n(W),
                              n(O),
                              "L",
                              n(rt),
                              n(O),
                              "L",
                              n(rt),
                              n(K),
                              "L",
                              n(W),
                              n(K),
                              "Z",
                            );
                            break;
                          case p.OPS.moveTo:
                            ((W = E[G++]),
                              (O = E[G++]),
                              V.push("M", n(W), n(O)));
                            break;
                          case p.OPS.lineTo:
                            ((W = E[G++]),
                              (O = E[G++]),
                              V.push("L", n(W), n(O)));
                            break;
                          case p.OPS.curveTo:
                            ((W = E[G + 4]),
                              (O = E[G + 5]),
                              V.push(
                                "C",
                                n(E[G]),
                                n(E[G + 1]),
                                n(E[G + 2]),
                                n(E[G + 3]),
                                n(W),
                                n(O),
                              ),
                              (G += 6));
                            break;
                          case p.OPS.curveTo2:
                            (V.push(
                              "C",
                              n(W),
                              n(O),
                              n(E[G]),
                              n(E[G + 1]),
                              n(E[G + 2]),
                              n(E[G + 3]),
                            ),
                              (W = E[G + 2]),
                              (O = E[G + 3]),
                              (G += 4));
                            break;
                          case p.OPS.curveTo3:
                            ((W = E[G + 2]),
                              (O = E[G + 3]),
                              V.push(
                                "C",
                                n(E[G]),
                                n(E[G + 1]),
                                n(W),
                                n(O),
                                n(W),
                                n(O),
                              ),
                              (G += 4));
                            break;
                          case p.OPS.closePath:
                            V.push("Z");
                            break;
                        }
                      ((V = V.join(" ")),
                        U.path &&
                        g.length > 0 &&
                        g[0] !== p.OPS.rectangle &&
                        g[0] !== p.OPS.moveTo
                          ? (V = U.path.getAttributeNS(null, "d") + V)
                          : ((U.path =
                              this.svgFactory.createElement("svg:path")),
                            this._ensureTransformGroup().append(U.path)),
                        U.path.setAttributeNS(null, "d", V),
                        U.path.setAttributeNS(null, "fill", "none"),
                        (U.element = U.path),
                        U.setCurrentPoint(W, O));
                    }
                    endPath() {
                      const g = this.current;
                      if (((g.path = null), !this.pendingClip)) return;
                      if (!g.element) {
                        this.pendingClip = null;
                        return;
                      }
                      const E = `clippath${m++}`,
                        U = this.svgFactory.createElement("svg:clipPath");
                      (U.setAttributeNS(null, "id", E),
                        U.setAttributeNS(
                          null,
                          "transform",
                          d(this.transformMatrix),
                        ));
                      const W = g.element.cloneNode(!0);
                      if (
                        (this.pendingClip === "evenodd"
                          ? W.setAttributeNS(null, "clip-rule", "evenodd")
                          : W.setAttributeNS(null, "clip-rule", "nonzero"),
                        (this.pendingClip = null),
                        U.append(W),
                        this.defs.append(U),
                        g.activeClipUrl)
                      ) {
                        g.clipGroup = null;
                        for (const O of this.extraStack) O.clipGroup = null;
                        U.setAttributeNS(null, "clip-path", g.activeClipUrl);
                      }
                      ((g.activeClipUrl = `url(#${E})`), (this.tgrp = null));
                    }
                    clip(g) {
                      this.pendingClip = g;
                    }
                    closePath() {
                      const g = this.current;
                      if (g.path) {
                        const E = `${g.path.getAttributeNS(null, "d")}Z`;
                        g.path.setAttributeNS(null, "d", E);
                      }
                    }
                    setLeading(g) {
                      this.current.leading = -g;
                    }
                    setTextRise(g) {
                      this.current.textRise = g;
                    }
                    setTextRenderingMode(g) {
                      this.current.textRenderingMode = g;
                    }
                    setHScale(g) {
                      this.current.textHScale = g / 100;
                    }
                    setRenderingIntent(g) {}
                    setFlatness(g) {}
                    setGState(g) {
                      for (const [E, U] of g)
                        switch (E) {
                          case "LW":
                            this.setLineWidth(U);
                            break;
                          case "LC":
                            this.setLineCap(U);
                            break;
                          case "LJ":
                            this.setLineJoin(U);
                            break;
                          case "ML":
                            this.setMiterLimit(U);
                            break;
                          case "D":
                            this.setDash(U[0], U[1]);
                            break;
                          case "RI":
                            this.setRenderingIntent(U);
                            break;
                          case "FL":
                            this.setFlatness(U);
                            break;
                          case "Font":
                            this.setFont(U);
                            break;
                          case "CA":
                            this.setStrokeAlpha(U);
                            break;
                          case "ca":
                            this.setFillAlpha(U);
                            break;
                          default:
                            (0, p.warn)(
                              `Unimplemented graphic state operator ${E}`,
                            );
                            break;
                        }
                    }
                    fill() {
                      const g = this.current;
                      g.element &&
                        (g.element.setAttributeNS(null, "fill", g.fillColor),
                        g.element.setAttributeNS(
                          null,
                          "fill-opacity",
                          g.fillAlpha,
                        ),
                        this.endPath());
                    }
                    stroke() {
                      const g = this.current;
                      g.element &&
                        (this._setStrokeAttributes(g.element),
                        g.element.setAttributeNS(null, "fill", "none"),
                        this.endPath());
                    }
                    _setStrokeAttributes(g, E = 1) {
                      const U = this.current;
                      let W = U.dashArray;
                      (E !== 1 &&
                        W.length > 0 &&
                        (W = W.map(function (O) {
                          return E * O;
                        })),
                        g.setAttributeNS(null, "stroke", U.strokeColor),
                        g.setAttributeNS(null, "stroke-opacity", U.strokeAlpha),
                        g.setAttributeNS(
                          null,
                          "stroke-miterlimit",
                          n(U.miterLimit),
                        ),
                        g.setAttributeNS(null, "stroke-linecap", U.lineCap),
                        g.setAttributeNS(null, "stroke-linejoin", U.lineJoin),
                        g.setAttributeNS(
                          null,
                          "stroke-width",
                          n(E * U.lineWidth) + "px",
                        ),
                        g.setAttributeNS(
                          null,
                          "stroke-dasharray",
                          W.map(n).join(" "),
                        ),
                        g.setAttributeNS(
                          null,
                          "stroke-dashoffset",
                          n(E * U.dashPhase) + "px",
                        ));
                    }
                    eoFill() {
                      (this.current.element?.setAttributeNS(
                        null,
                        "fill-rule",
                        "evenodd",
                      ),
                        this.fill());
                    }
                    fillStroke() {
                      (this.stroke(), this.fill());
                    }
                    eoFillStroke() {
                      (this.current.element?.setAttributeNS(
                        null,
                        "fill-rule",
                        "evenodd",
                      ),
                        this.fillStroke());
                    }
                    closeStroke() {
                      (this.closePath(), this.stroke());
                    }
                    closeFillStroke() {
                      (this.closePath(), this.fillStroke());
                    }
                    closeEOFillStroke() {
                      (this.closePath(), this.eoFillStroke());
                    }
                    paintSolidColorImageMask() {
                      const g = this.svgFactory.createElement("svg:rect");
                      (g.setAttributeNS(null, "x", "0"),
                        g.setAttributeNS(null, "y", "0"),
                        g.setAttributeNS(null, "width", "1px"),
                        g.setAttributeNS(null, "height", "1px"),
                        g.setAttributeNS(null, "fill", this.current.fillColor),
                        this._ensureTransformGroup().append(g));
                    }
                    paintImageXObject(g) {
                      const E = this.getObject(g);
                      if (!E) {
                        (0, p.warn)(
                          `Dependent image with object ID ${g} is not ready yet`,
                        );
                        return;
                      }
                      this.paintInlineImageXObject(E);
                    }
                    paintInlineImageXObject(g, E) {
                      const U = g.width,
                        W = g.height,
                        O = i(g, this.forceDataSchema, !!E),
                        V = this.svgFactory.createElement("svg:rect");
                      (V.setAttributeNS(null, "x", "0"),
                        V.setAttributeNS(null, "y", "0"),
                        V.setAttributeNS(null, "width", n(U)),
                        V.setAttributeNS(null, "height", n(W)),
                        (this.current.element = V),
                        this.clip("nonzero"));
                      const G = this.svgFactory.createElement("svg:image");
                      (G.setAttributeNS(j, "xlink:href", O),
                        G.setAttributeNS(null, "x", "0"),
                        G.setAttributeNS(null, "y", n(-W)),
                        G.setAttributeNS(null, "width", n(U) + "px"),
                        G.setAttributeNS(null, "height", n(W) + "px"),
                        G.setAttributeNS(
                          null,
                          "transform",
                          `scale(${n(1 / U)} ${n(-1 / W)})`,
                        ),
                        E
                          ? E.append(G)
                          : this._ensureTransformGroup().append(G));
                    }
                    paintImageMaskXObject(g) {
                      const E = this.getObject(g.data, g);
                      if (E.bitmap) {
                        (0, p.warn)(
                          "paintImageMaskXObject: ImageBitmap support is not implemented, ensure that the `isOffscreenCanvasSupported` API parameter is disabled.",
                        );
                        return;
                      }
                      const U = this.current,
                        W = E.width,
                        O = E.height,
                        V = U.fillColor;
                      U.maskId = `mask${l++}`;
                      const G = this.svgFactory.createElement("svg:mask");
                      G.setAttributeNS(null, "id", U.maskId);
                      const nt = this.svgFactory.createElement("svg:rect");
                      (nt.setAttributeNS(null, "x", "0"),
                        nt.setAttributeNS(null, "y", "0"),
                        nt.setAttributeNS(null, "width", n(W)),
                        nt.setAttributeNS(null, "height", n(O)),
                        nt.setAttributeNS(null, "fill", V),
                        nt.setAttributeNS(null, "mask", `url(#${U.maskId})`),
                        this.defs.append(G),
                        this._ensureTransformGroup().append(nt),
                        this.paintInlineImageXObject(E, G));
                    }
                    paintFormXObjectBegin(g, E) {
                      if (
                        (Array.isArray(g) &&
                          g.length === 6 &&
                          this.transform(g[0], g[1], g[2], g[3], g[4], g[5]),
                        E)
                      ) {
                        const U = E[2] - E[0],
                          W = E[3] - E[1],
                          O = this.svgFactory.createElement("svg:rect");
                        (O.setAttributeNS(null, "x", E[0]),
                          O.setAttributeNS(null, "y", E[1]),
                          O.setAttributeNS(null, "width", n(U)),
                          O.setAttributeNS(null, "height", n(W)),
                          (this.current.element = O),
                          this.clip("nonzero"),
                          this.endPath());
                      }
                    }
                    paintFormXObjectEnd() {}
                    _initialize(g) {
                      const E = this.svgFactory.create(g.width, g.height),
                        U = this.svgFactory.createElement("svg:defs");
                      (E.append(U), (this.defs = U));
                      const W = this.svgFactory.createElement("svg:g");
                      return (
                        W.setAttributeNS(null, "transform", d(g.transform)),
                        E.append(W),
                        (this.svg = W),
                        E
                      );
                    }
                    _ensureClipGroup() {
                      if (!this.current.clipGroup) {
                        const g = this.svgFactory.createElement("svg:g");
                        (g.setAttributeNS(
                          null,
                          "clip-path",
                          this.current.activeClipUrl,
                        ),
                          this.svg.append(g),
                          (this.current.clipGroup = g));
                      }
                      return this.current.clipGroup;
                    }
                    _ensureTransformGroup() {
                      return (
                        this.tgrp ||
                          ((this.tgrp = this.svgFactory.createElement("svg:g")),
                          this.tgrp.setAttributeNS(
                            null,
                            "transform",
                            d(this.transformMatrix),
                          ),
                          this.current.activeClipUrl
                            ? this._ensureClipGroup().append(this.tgrp)
                            : this.svg.append(this.tgrp)),
                        this.tgrp
                      );
                    }
                  }
                  e.SVGGraphics = M;
                },
                (A, e) => {
                  (Object.defineProperty(e, "__esModule", { value: !0 }),
                    (e.XfaText = void 0));
                  class y {
                    static textContent(p) {
                      const k = [],
                        T = { items: k, styles: Object.create(null) };
                      function j(D) {
                        if (!D) return;
                        let s = null;
                        const t = D.name;
                        if (t === "#text") s = D.value;
                        else if (y.shouldBuildText(t))
                          D?.attributes?.textContent
                            ? (s = D.attributes.textContent)
                            : D.value && (s = D.value);
                        else return;
                        if ((s !== null && k.push({ str: s }), !!D.children))
                          for (const i of D.children) j(i);
                      }
                      return (j(p), T);
                    }
                    static shouldBuildText(p) {
                      return !(
                        p === "textarea" ||
                        p === "input" ||
                        p === "option" ||
                        p === "select"
                      );
                    }
                  }
                  e.XfaText = y;
                },
                (A, e, y) => {
                  (Object.defineProperty(e, "__esModule", { value: !0 }),
                    (e.TextLayerRenderTask = void 0),
                    (e.renderTextLayer = d),
                    (e.updateTextLayer = m));
                  var a = y(1),
                    p = y(6);
                  const k = 1e5,
                    T = 30,
                    j = 0.8,
                    D = new Map();
                  function s(l, w) {
                    let M;
                    if (w && a.FeatureTest.isOffscreenCanvasSupported)
                      M = new OffscreenCanvas(l, l).getContext("2d", {
                        alpha: !1,
                      });
                    else {
                      const C = document.createElement("canvas");
                      ((C.width = C.height = l),
                        (M = C.getContext("2d", { alpha: !1 })));
                    }
                    return M;
                  }
                  function t(l, w) {
                    const M = D.get(l);
                    if (M) return M;
                    const C = s(T, w);
                    C.font = `${T}px ${l}`;
                    const g = C.measureText("");
                    let E = g.fontBoundingBoxAscent,
                      U = Math.abs(g.fontBoundingBoxDescent);
                    if (E) {
                      const O = E / (E + U);
                      return (
                        D.set(l, O),
                        (C.canvas.width = C.canvas.height = 0),
                        O
                      );
                    }
                    ((C.strokeStyle = "red"),
                      C.clearRect(0, 0, T, T),
                      C.strokeText("g", 0, 0));
                    let W = C.getImageData(0, 0, T, T).data;
                    U = 0;
                    for (let O = W.length - 1 - 3; O >= 0; O -= 4)
                      if (W[O] > 0) {
                        U = Math.ceil(O / 4 / T);
                        break;
                      }
                    (C.clearRect(0, 0, T, T),
                      C.strokeText("A", 0, T),
                      (W = C.getImageData(0, 0, T, T).data),
                      (E = 0));
                    for (let O = 0, V = W.length; O < V; O += 4)
                      if (W[O] > 0) {
                        E = T - Math.floor(O / 4 / T);
                        break;
                      }
                    if (((C.canvas.width = C.canvas.height = 0), E)) {
                      const O = E / (E + U);
                      return (D.set(l, O), O);
                    }
                    return (D.set(l, j), j);
                  }
                  function i(l, w, M) {
                    const C = document.createElement("span"),
                      g = {
                        angle: 0,
                        canvasWidth: 0,
                        hasText: w.str !== "",
                        hasEOL: w.hasEOL,
                        fontSize: 0,
                      };
                    l._textDivs.push(C);
                    const E = a.Util.transform(l._transform, w.transform);
                    let U = Math.atan2(E[1], E[0]);
                    const W = M[w.fontName];
                    W.vertical && (U += Math.PI / 2);
                    const O = Math.hypot(E[2], E[3]),
                      V = O * t(W.fontFamily, l._isOffscreenCanvasSupported);
                    let G, nt;
                    U === 0
                      ? ((G = E[4]), (nt = E[5] - V))
                      : ((G = E[4] + V * Math.sin(U)),
                        (nt = E[5] - V * Math.cos(U)));
                    const Z = "calc(var(--scale-factor)*",
                      tt = C.style;
                    (l._container === l._rootContainer
                      ? ((tt.left = `${((100 * G) / l._pageWidth).toFixed(2)}%`),
                        (tt.top = `${((100 * nt) / l._pageHeight).toFixed(2)}%`))
                      : ((tt.left = `${Z}${G.toFixed(2)}px)`),
                        (tt.top = `${Z}${nt.toFixed(2)}px)`)),
                      (tt.fontSize = `${Z}${O.toFixed(2)}px)`),
                      (tt.fontFamily = W.fontFamily),
                      (g.fontSize = O),
                      C.setAttribute("role", "presentation"),
                      (C.textContent = w.str),
                      (C.dir = w.dir),
                      l._fontInspectorEnabled &&
                        (C.dataset.fontName = w.fontName),
                      U !== 0 && (g.angle = U * (180 / Math.PI)));
                    let rt = !1;
                    if (w.str.length > 1) rt = !0;
                    else if (
                      w.str !== " " &&
                      w.transform[0] !== w.transform[3]
                    ) {
                      const K = Math.abs(w.transform[0]),
                        I = Math.abs(w.transform[3]);
                      K !== I &&
                        Math.max(K, I) / Math.min(K, I) > 1.5 &&
                        (rt = !0);
                    }
                    (rt && (g.canvasWidth = W.vertical ? w.height : w.width),
                      l._textDivProperties.set(C, g),
                      l._isReadableStream && l._layoutText(C));
                  }
                  function h(l) {
                    const {
                        div: w,
                        scale: M,
                        properties: C,
                        ctx: g,
                        prevFontSize: E,
                        prevFontFamily: U,
                      } = l,
                      { style: W } = w;
                    let O = "";
                    if (C.canvasWidth !== 0 && C.hasText) {
                      const { fontFamily: V } = W,
                        { canvasWidth: G, fontSize: nt } = C;
                      (E !== nt || U !== V) &&
                        ((g.font = `${nt * M}px ${V}`),
                        (l.prevFontSize = nt),
                        (l.prevFontFamily = V));
                      const { width: Z } = g.measureText(w.textContent);
                      Z > 0 && (O = `scaleX(${(G * M) / Z})`);
                    }
                    (C.angle !== 0 && (O = `rotate(${C.angle}deg) ${O}`),
                      O.length > 0 && (W.transform = O));
                  }
                  function c(l) {
                    if (l._canceled) return;
                    const w = l._textDivs,
                      M = l._capability;
                    if (w.length > k) {
                      M.resolve();
                      return;
                    }
                    if (!l._isReadableStream)
                      for (const g of w) l._layoutText(g);
                    M.resolve();
                  }
                  class n {
                    constructor({
                      textContentSource: w,
                      container: M,
                      viewport: C,
                      textDivs: g,
                      textDivProperties: E,
                      textContentItemsStr: U,
                      isOffscreenCanvasSupported: W,
                    }) {
                      ((this._textContentSource = w),
                        (this._isReadableStream = w instanceof ReadableStream),
                        (this._container = this._rootContainer = M),
                        (this._textDivs = g || []),
                        (this._textContentItemsStr = U || []),
                        (this._isOffscreenCanvasSupported = W),
                        (this._fontInspectorEnabled =
                          !!globalThis.FontInspector?.enabled),
                        (this._reader = null),
                        (this._textDivProperties = E || new WeakMap()),
                        (this._canceled = !1),
                        (this._capability = new a.PromiseCapability()),
                        (this._layoutTextParams = {
                          prevFontSize: null,
                          prevFontFamily: null,
                          div: null,
                          scale: C.scale * (globalThis.devicePixelRatio || 1),
                          properties: null,
                          ctx: s(0, W),
                        }));
                      const {
                        pageWidth: O,
                        pageHeight: V,
                        pageX: G,
                        pageY: nt,
                      } = C.rawDims;
                      ((this._transform = [1, 0, 0, -1, -G, nt + V]),
                        (this._pageWidth = O),
                        (this._pageHeight = V),
                        (0, p.setLayerDimensions)(M, C),
                        this._capability.promise
                          .finally(() => {
                            this._layoutTextParams = null;
                          })
                          .catch(() => {}));
                    }
                    get promise() {
                      return this._capability.promise;
                    }
                    cancel() {
                      ((this._canceled = !0),
                        this._reader &&
                          (this._reader
                            .cancel(
                              new a.AbortException("TextLayer task cancelled."),
                            )
                            .catch(() => {}),
                          (this._reader = null)),
                        this._capability.reject(
                          new a.AbortException("TextLayer task cancelled."),
                        ));
                    }
                    _processItems(w, M) {
                      for (const C of w) {
                        if (C.str === void 0) {
                          if (
                            C.type === "beginMarkedContentProps" ||
                            C.type === "beginMarkedContent"
                          ) {
                            const g = this._container;
                            ((this._container = document.createElement("span")),
                              this._container.classList.add("markedContent"),
                              C.id !== null &&
                                this._container.setAttribute("id", `${C.id}`),
                              g.append(this._container));
                          } else
                            C.type === "endMarkedContent" &&
                              (this._container = this._container.parentNode);
                          continue;
                        }
                        (this._textContentItemsStr.push(C.str), i(this, C, M));
                      }
                    }
                    _layoutText(w) {
                      const M = (this._layoutTextParams.properties =
                        this._textDivProperties.get(w));
                      if (
                        ((this._layoutTextParams.div = w),
                        h(this._layoutTextParams),
                        M.hasText && this._container.append(w),
                        M.hasEOL)
                      ) {
                        const C = document.createElement("br");
                        (C.setAttribute("role", "presentation"),
                          this._container.append(C));
                      }
                    }
                    _render() {
                      const w = new a.PromiseCapability();
                      let M = Object.create(null);
                      if (this._isReadableStream) {
                        const C = () => {
                          this._reader.read().then(({ value: g, done: E }) => {
                            if (E) {
                              w.resolve();
                              return;
                            }
                            (Object.assign(M, g.styles),
                              this._processItems(g.items, M),
                              C());
                          }, w.reject);
                        };
                        ((this._reader = this._textContentSource.getReader()),
                          C());
                      } else if (this._textContentSource) {
                        const { items: C, styles: g } = this._textContentSource;
                        (this._processItems(C, g), w.resolve());
                      } else
                        throw new Error(
                          'No "textContentSource" parameter specified.',
                        );
                      w.promise.then(() => {
                        ((M = null), c(this));
                      }, this._capability.reject);
                    }
                  }
                  e.TextLayerRenderTask = n;
                  function d(l) {
                    !l.textContentSource &&
                      (l.textContent || l.textContentStream) &&
                      ((0, p.deprecated)(
                        "The TextLayerRender `textContent`/`textContentStream` parameters will be removed in the future, please use `textContentSource` instead.",
                      ),
                      (l.textContentSource =
                        l.textContent || l.textContentStream));
                    const { container: w, viewport: M } = l,
                      C = getComputedStyle(w),
                      g = C.getPropertyValue("visibility"),
                      E = parseFloat(C.getPropertyValue("--scale-factor"));
                    g === "visible" &&
                      (!E || Math.abs(E - M.scale) > 1e-5) &&
                      console.error(
                        "The `--scale-factor` CSS-variable must be set, to the same value as `viewport.scale`, either on the `container`-element itself or higher up in the DOM.",
                      );
                    const U = new n(l);
                    return (U._render(), U);
                  }
                  function m({
                    container: l,
                    viewport: w,
                    textDivs: M,
                    textDivProperties: C,
                    isOffscreenCanvasSupported: g,
                    mustRotate: E = !0,
                    mustRescale: U = !0,
                  }) {
                    if (
                      (E &&
                        (0, p.setLayerDimensions)(l, { rotation: w.rotation }),
                      U)
                    ) {
                      const W = s(0, g),
                        V = {
                          prevFontSize: null,
                          prevFontFamily: null,
                          div: null,
                          scale: w.scale * (globalThis.devicePixelRatio || 1),
                          properties: null,
                          ctx: W,
                        };
                      for (const G of M)
                        ((V.properties = C.get(G)), (V.div = G), h(V));
                    }
                  }
                },
                (A, e, y) => {
                  (Object.defineProperty(e, "__esModule", { value: !0 }),
                    (e.AnnotationEditorLayer = void 0));
                  var a = y(1),
                    p = y(4),
                    k = y(28),
                    T = y(33),
                    j = y(6),
                    D = y(34);
                  class s {
                    #t;
                    #e = !1;
                    #n = null;
                    #i = this.pointerup.bind(this);
                    #o = this.pointerdown.bind(this);
                    #a = new Map();
                    #r = !1;
                    #l = !1;
                    #c = !1;
                    #s;
                    static _initialized = !1;
                    constructor({
                      uiManager: i,
                      pageIndex: h,
                      div: c,
                      accessibilityManager: n,
                      annotationLayer: d,
                      viewport: m,
                      l10n: l,
                    }) {
                      const w = [k.FreeTextEditor, T.InkEditor, D.StampEditor];
                      if (!s._initialized) {
                        s._initialized = !0;
                        for (const M of w) M.initialize(l);
                      }
                      (i.registerEditorTypes(w),
                        (this.#s = i),
                        (this.pageIndex = h),
                        (this.div = c),
                        (this.#t = n),
                        (this.#n = d),
                        (this.viewport = m),
                        this.#s.addLayer(this));
                    }
                    get isEmpty() {
                      return this.#a.size === 0;
                    }
                    updateToolbar(i) {
                      this.#s.updateToolbar(i);
                    }
                    updateMode(i = this.#s.getMode()) {
                      (this.#p(),
                        i === a.AnnotationEditorType.INK
                          ? (this.addInkEditorIfNeeded(!1), this.disableClick())
                          : this.enableClick(),
                        i !== a.AnnotationEditorType.NONE &&
                          (this.div.classList.toggle(
                            "freeTextEditing",
                            i === a.AnnotationEditorType.FREETEXT,
                          ),
                          this.div.classList.toggle(
                            "inkEditing",
                            i === a.AnnotationEditorType.INK,
                          ),
                          this.div.classList.toggle(
                            "stampEditing",
                            i === a.AnnotationEditorType.STAMP,
                          ),
                          (this.div.hidden = !1)));
                    }
                    addInkEditorIfNeeded(i) {
                      if (
                        !i &&
                        this.#s.getMode() !== a.AnnotationEditorType.INK
                      )
                        return;
                      if (!i) {
                        for (const c of this.#a.values())
                          if (c.isEmpty()) {
                            c.setInBackground();
                            return;
                          }
                      }
                      this.#d({ offsetX: 0, offsetY: 0 }, !1).setInBackground();
                    }
                    setEditingState(i) {
                      this.#s.setEditingState(i);
                    }
                    addCommands(i) {
                      this.#s.addCommands(i);
                    }
                    enable() {
                      this.div.style.pointerEvents = "auto";
                      const i = new Set();
                      for (const c of this.#a.values())
                        (c.enableEditing(),
                          c.annotationElementId &&
                            i.add(c.annotationElementId));
                      if (!this.#n) return;
                      const h = this.#n.getEditableAnnotations();
                      for (const c of h) {
                        if (
                          (c.hide(),
                          this.#s.isDeletedAnnotationElement(c.data.id) ||
                            i.has(c.data.id))
                        )
                          continue;
                        const n = this.deserialize(c);
                        n && (this.addOrRebuild(n), n.enableEditing());
                      }
                    }
                    disable() {
                      ((this.#c = !0), (this.div.style.pointerEvents = "none"));
                      const i = new Set();
                      for (const h of this.#a.values()) {
                        if (
                          (h.disableEditing(),
                          !h.annotationElementId || h.serialize() !== null)
                        ) {
                          i.add(h.annotationElementId);
                          continue;
                        }
                        (this.getEditableAnnotation(
                          h.annotationElementId,
                        )?.show(),
                          h.remove());
                      }
                      if (this.#n) {
                        const h = this.#n.getEditableAnnotations();
                        for (const c of h) {
                          const { id: n } = c.data;
                          i.has(n) ||
                            this.#s.isDeletedAnnotationElement(n) ||
                            c.show();
                        }
                      }
                      (this.#p(),
                        this.isEmpty && (this.div.hidden = !0),
                        (this.#c = !1));
                    }
                    getEditableAnnotation(i) {
                      return this.#n?.getEditableAnnotation(i) || null;
                    }
                    setActiveEditor(i) {
                      this.#s.getActive() !== i && this.#s.setActiveEditor(i);
                    }
                    enableClick() {
                      (this.div.addEventListener("pointerdown", this.#o),
                        this.div.addEventListener("pointerup", this.#i));
                    }
                    disableClick() {
                      (this.div.removeEventListener("pointerdown", this.#o),
                        this.div.removeEventListener("pointerup", this.#i));
                    }
                    attach(i) {
                      this.#a.set(i.id, i);
                      const { annotationElementId: h } = i;
                      h &&
                        this.#s.isDeletedAnnotationElement(h) &&
                        this.#s.removeDeletedAnnotationElement(i);
                    }
                    detach(i) {
                      (this.#a.delete(i.id),
                        this.#t?.removePointerInTextLayer(i.contentDiv),
                        !this.#c &&
                          i.annotationElementId &&
                          this.#s.addDeletedAnnotationElement(i));
                    }
                    remove(i) {
                      (this.detach(i),
                        this.#s.removeEditor(i),
                        i.div.contains(document.activeElement) &&
                          setTimeout(() => {
                            this.#s.focusMainContainer();
                          }, 0),
                        i.div.remove(),
                        (i.isAttachedToDOM = !1),
                        this.#l || this.addInkEditorIfNeeded(!1));
                    }
                    changeParent(i) {
                      i.parent !== this &&
                        (i.annotationElementId &&
                          (this.#s.addDeletedAnnotationElement(
                            i.annotationElementId,
                          ),
                          p.AnnotationEditor.deleteAnnotationElement(i),
                          (i.annotationElementId = null)),
                        this.attach(i),
                        i.parent?.detach(i),
                        i.setParent(this),
                        i.div &&
                          i.isAttachedToDOM &&
                          (i.div.remove(), this.div.append(i.div)));
                    }
                    add(i) {
                      if (
                        (this.changeParent(i),
                        this.#s.addEditor(i),
                        this.attach(i),
                        !i.isAttachedToDOM)
                      ) {
                        const h = i.render();
                        (this.div.append(h), (i.isAttachedToDOM = !0));
                      }
                      (i.fixAndSetPosition(),
                        i.onceAdded(),
                        this.#s.addToAnnotationStorage(i));
                    }
                    moveEditorInDOM(i) {
                      if (!i.isAttachedToDOM) return;
                      const { activeElement: h } = document;
                      (i.div.contains(h) &&
                        ((i._focusEventsAllowed = !1),
                        setTimeout(() => {
                          i.div.contains(document.activeElement)
                            ? (i._focusEventsAllowed = !0)
                            : (i.div.addEventListener(
                                "focusin",
                                () => {
                                  i._focusEventsAllowed = !0;
                                },
                                { once: !0 },
                              ),
                              h.focus());
                        }, 0)),
                        (i._structTreeParentId = this.#t?.moveElementInDOM(
                          this.div,
                          i.div,
                          i.contentDiv,
                          !0,
                        )));
                    }
                    addOrRebuild(i) {
                      i.needsToBeRebuilt() ? i.rebuild() : this.add(i);
                    }
                    addUndoableEditor(i) {
                      const h = () => i._uiManager.rebuild(i),
                        c = () => {
                          i.remove();
                        };
                      this.addCommands({ cmd: h, undo: c, mustExec: !1 });
                    }
                    getNextId() {
                      return this.#s.getId();
                    }
                    #f(i) {
                      switch (this.#s.getMode()) {
                        case a.AnnotationEditorType.FREETEXT:
                          return new k.FreeTextEditor(i);
                        case a.AnnotationEditorType.INK:
                          return new T.InkEditor(i);
                        case a.AnnotationEditorType.STAMP:
                          return new D.StampEditor(i);
                      }
                      return null;
                    }
                    pasteEditor(i, h) {
                      (this.#s.updateToolbar(i), this.#s.updateMode(i));
                      const { offsetX: c, offsetY: n } = this.#u(),
                        d = this.getNextId(),
                        m = this.#f({
                          parent: this,
                          id: d,
                          x: c,
                          y: n,
                          uiManager: this.#s,
                          isCentered: !0,
                          ...h,
                        });
                      m && this.add(m);
                    }
                    deserialize(i) {
                      switch (i.annotationType ?? i.annotationEditorType) {
                        case a.AnnotationEditorType.FREETEXT:
                          return k.FreeTextEditor.deserialize(i, this, this.#s);
                        case a.AnnotationEditorType.INK:
                          return T.InkEditor.deserialize(i, this, this.#s);
                        case a.AnnotationEditorType.STAMP:
                          return D.StampEditor.deserialize(i, this, this.#s);
                      }
                      return null;
                    }
                    #d(i, h) {
                      const c = this.getNextId(),
                        n = this.#f({
                          parent: this,
                          id: c,
                          x: i.offsetX,
                          y: i.offsetY,
                          uiManager: this.#s,
                          isCentered: h,
                        });
                      return (n && this.add(n), n);
                    }
                    #u() {
                      const {
                          x: i,
                          y: h,
                          width: c,
                          height: n,
                        } = this.div.getBoundingClientRect(),
                        d = Math.max(0, i),
                        m = Math.max(0, h),
                        l = Math.min(window.innerWidth, i + c),
                        w = Math.min(window.innerHeight, h + n),
                        M = (d + l) / 2 - i,
                        C = (m + w) / 2 - h,
                        [g, E] =
                          this.viewport.rotation % 180 === 0 ? [M, C] : [C, M];
                      return { offsetX: g, offsetY: E };
                    }
                    addNewEditor() {
                      this.#d(this.#u(), !0);
                    }
                    setSelected(i) {
                      this.#s.setSelected(i);
                    }
                    toggleSelected(i) {
                      this.#s.toggleSelected(i);
                    }
                    isSelected(i) {
                      return this.#s.isSelected(i);
                    }
                    unselect(i) {
                      this.#s.unselect(i);
                    }
                    pointerup(i) {
                      const { isMac: h } = a.FeatureTest.platform;
                      if (
                        !(i.button !== 0 || (i.ctrlKey && h)) &&
                        i.target === this.div &&
                        this.#r
                      ) {
                        if (((this.#r = !1), !this.#e)) {
                          this.#e = !0;
                          return;
                        }
                        if (
                          this.#s.getMode() === a.AnnotationEditorType.STAMP
                        ) {
                          this.#s.unselectAll();
                          return;
                        }
                        this.#d(i, !1);
                      }
                    }
                    pointerdown(i) {
                      if (this.#r) {
                        this.#r = !1;
                        return;
                      }
                      const { isMac: h } = a.FeatureTest.platform;
                      if (
                        i.button !== 0 ||
                        (i.ctrlKey && h) ||
                        i.target !== this.div
                      )
                        return;
                      this.#r = !0;
                      const c = this.#s.getActive();
                      this.#e = !c || c.isEmpty();
                    }
                    findNewParent(i, h, c) {
                      const n = this.#s.findParent(h, c);
                      return n === null || n === this
                        ? !1
                        : (n.changeParent(i), !0);
                    }
                    destroy() {
                      this.#s.getActive()?.parent === this &&
                        (this.#s.commitOrRemove(),
                        this.#s.setActiveEditor(null));
                      for (const i of this.#a.values())
                        (this.#t?.removePointerInTextLayer(i.contentDiv),
                          i.setParent(null),
                          (i.isAttachedToDOM = !1),
                          i.div.remove());
                      ((this.div = null),
                        this.#a.clear(),
                        this.#s.removeLayer(this));
                    }
                    #p() {
                      this.#l = !0;
                      for (const i of this.#a.values())
                        i.isEmpty() && i.remove();
                      this.#l = !1;
                    }
                    render({ viewport: i }) {
                      ((this.viewport = i),
                        (0, j.setLayerDimensions)(this.div, i));
                      for (const h of this.#s.getEditors(this.pageIndex))
                        this.add(h);
                      this.updateMode();
                    }
                    update({ viewport: i }) {
                      (this.#s.commitOrRemove(),
                        (this.viewport = i),
                        (0, j.setLayerDimensions)(this.div, {
                          rotation: i.rotation,
                        }),
                        this.updateMode());
                    }
                    get pageDimensions() {
                      const { pageWidth: i, pageHeight: h } =
                        this.viewport.rawDims;
                      return [i, h];
                    }
                  }
                  e.AnnotationEditorLayer = s;
                },
                (A, e, y) => {
                  (Object.defineProperty(e, "__esModule", { value: !0 }),
                    (e.FreeTextEditor = void 0));
                  var a = y(1),
                    p = y(5),
                    k = y(4),
                    T = y(29);
                  class j extends k.AnnotationEditor {
                    #t = this.editorDivBlur.bind(this);
                    #e = this.editorDivFocus.bind(this);
                    #n = this.editorDivInput.bind(this);
                    #i = this.editorDivKeydown.bind(this);
                    #o;
                    #a = "";
                    #r = `${this.id}-editor`;
                    #l;
                    #c = null;
                    static _freeTextDefaultContent = "";
                    static _internalPadding = 0;
                    static _defaultColor = null;
                    static _defaultFontSize = 10;
                    static get _keyboardManager() {
                      const s = j.prototype,
                        t = (c) => c.isEmpty(),
                        i = p.AnnotationEditorUIManager.TRANSLATE_SMALL,
                        h = p.AnnotationEditorUIManager.TRANSLATE_BIG;
                      return (0, a.shadow)(
                        this,
                        "_keyboardManager",
                        new p.KeyboardManager([
                          [
                            ["ctrl+s", "mac+meta+s", "ctrl+p", "mac+meta+p"],
                            s.commitOrRemove,
                            { bubbles: !0 },
                          ],
                          [
                            [
                              "ctrl+Enter",
                              "mac+meta+Enter",
                              "Escape",
                              "mac+Escape",
                            ],
                            s.commitOrRemove,
                          ],
                          [
                            ["ArrowLeft", "mac+ArrowLeft"],
                            s._translateEmpty,
                            { args: [-i, 0], checker: t },
                          ],
                          [
                            ["ctrl+ArrowLeft", "mac+shift+ArrowLeft"],
                            s._translateEmpty,
                            { args: [-h, 0], checker: t },
                          ],
                          [
                            ["ArrowRight", "mac+ArrowRight"],
                            s._translateEmpty,
                            { args: [i, 0], checker: t },
                          ],
                          [
                            ["ctrl+ArrowRight", "mac+shift+ArrowRight"],
                            s._translateEmpty,
                            { args: [h, 0], checker: t },
                          ],
                          [
                            ["ArrowUp", "mac+ArrowUp"],
                            s._translateEmpty,
                            { args: [0, -i], checker: t },
                          ],
                          [
                            ["ctrl+ArrowUp", "mac+shift+ArrowUp"],
                            s._translateEmpty,
                            { args: [0, -h], checker: t },
                          ],
                          [
                            ["ArrowDown", "mac+ArrowDown"],
                            s._translateEmpty,
                            { args: [0, i], checker: t },
                          ],
                          [
                            ["ctrl+ArrowDown", "mac+shift+ArrowDown"],
                            s._translateEmpty,
                            { args: [0, h], checker: t },
                          ],
                        ]),
                      );
                    }
                    static _type = "freetext";
                    constructor(s) {
                      (super({ ...s, name: "freeTextEditor" }),
                        (this.#o =
                          s.color ||
                          j._defaultColor ||
                          k.AnnotationEditor._defaultLineColor),
                        (this.#l = s.fontSize || j._defaultFontSize));
                    }
                    static initialize(s) {
                      k.AnnotationEditor.initialize(s, {
                        strings: [
                          "free_text2_default_content",
                          "editor_free_text2_aria_label",
                        ],
                      });
                      const t = getComputedStyle(document.documentElement);
                      this._internalPadding = parseFloat(
                        t.getPropertyValue("--freetext-padding"),
                      );
                    }
                    static updateDefaultParams(s, t) {
                      switch (s) {
                        case a.AnnotationEditorParamsType.FREETEXT_SIZE:
                          j._defaultFontSize = t;
                          break;
                        case a.AnnotationEditorParamsType.FREETEXT_COLOR:
                          j._defaultColor = t;
                          break;
                      }
                    }
                    updateParams(s, t) {
                      switch (s) {
                        case a.AnnotationEditorParamsType.FREETEXT_SIZE:
                          this.#s(t);
                          break;
                        case a.AnnotationEditorParamsType.FREETEXT_COLOR:
                          this.#f(t);
                          break;
                      }
                    }
                    static get defaultPropertiesToUpdate() {
                      return [
                        [
                          a.AnnotationEditorParamsType.FREETEXT_SIZE,
                          j._defaultFontSize,
                        ],
                        [
                          a.AnnotationEditorParamsType.FREETEXT_COLOR,
                          j._defaultColor ||
                            k.AnnotationEditor._defaultLineColor,
                        ],
                      ];
                    }
                    get propertiesToUpdate() {
                      return [
                        [a.AnnotationEditorParamsType.FREETEXT_SIZE, this.#l],
                        [a.AnnotationEditorParamsType.FREETEXT_COLOR, this.#o],
                      ];
                    }
                    #s(s) {
                      const t = (h) => {
                          ((this.editorDiv.style.fontSize = `calc(${h}px * var(--scale-factor))`),
                            this.translate(
                              0,
                              -(h - this.#l) * this.parentScale,
                            ),
                            (this.#l = h),
                            this.#u());
                        },
                        i = this.#l;
                      this.addCommands({
                        cmd: () => {
                          t(s);
                        },
                        undo: () => {
                          t(i);
                        },
                        mustExec: !0,
                        type: a.AnnotationEditorParamsType.FREETEXT_SIZE,
                        overwriteIfSameType: !0,
                        keepUndo: !0,
                      });
                    }
                    #f(s) {
                      const t = this.#o;
                      this.addCommands({
                        cmd: () => {
                          this.#o = this.editorDiv.style.color = s;
                        },
                        undo: () => {
                          this.#o = this.editorDiv.style.color = t;
                        },
                        mustExec: !0,
                        type: a.AnnotationEditorParamsType.FREETEXT_COLOR,
                        overwriteIfSameType: !0,
                        keepUndo: !0,
                      });
                    }
                    _translateEmpty(s, t) {
                      this._uiManager.translateSelectedEditors(s, t, !0);
                    }
                    getInitialTranslation() {
                      const s = this.parentScale;
                      return [
                        -j._internalPadding * s,
                        -(j._internalPadding + this.#l) * s,
                      ];
                    }
                    rebuild() {
                      this.parent &&
                        (super.rebuild(),
                        this.div !== null &&
                          (this.isAttachedToDOM || this.parent.add(this)));
                    }
                    enableEditMode() {
                      this.isInEditMode() ||
                        (this.parent.setEditingState(!1),
                        this.parent.updateToolbar(
                          a.AnnotationEditorType.FREETEXT,
                        ),
                        super.enableEditMode(),
                        this.overlayDiv.classList.remove("enabled"),
                        (this.editorDiv.contentEditable = !0),
                        (this._isDraggable = !1),
                        this.div.removeAttribute("aria-activedescendant"),
                        this.editorDiv.addEventListener("keydown", this.#i),
                        this.editorDiv.addEventListener("focus", this.#e),
                        this.editorDiv.addEventListener("blur", this.#t),
                        this.editorDiv.addEventListener("input", this.#n));
                    }
                    disableEditMode() {
                      this.isInEditMode() &&
                        (this.parent.setEditingState(!0),
                        super.disableEditMode(),
                        this.overlayDiv.classList.add("enabled"),
                        (this.editorDiv.contentEditable = !1),
                        this.div.setAttribute("aria-activedescendant", this.#r),
                        (this._isDraggable = !0),
                        this.editorDiv.removeEventListener("keydown", this.#i),
                        this.editorDiv.removeEventListener("focus", this.#e),
                        this.editorDiv.removeEventListener("blur", this.#t),
                        this.editorDiv.removeEventListener("input", this.#n),
                        this.div.focus({ preventScroll: !0 }),
                        (this.isEditing = !1),
                        this.parent.div.classList.add("freeTextEditing"));
                    }
                    focusin(s) {
                      this._focusEventsAllowed &&
                        (super.focusin(s),
                        s.target !== this.editorDiv && this.editorDiv.focus());
                    }
                    onceAdded() {
                      if (this.width) {
                        this.#m();
                        return;
                      }
                      (this.enableEditMode(),
                        this.editorDiv.focus(),
                        this._initialOptions?.isCentered && this.center(),
                        (this._initialOptions = null));
                    }
                    isEmpty() {
                      return (
                        !this.editorDiv ||
                        this.editorDiv.innerText.trim() === ""
                      );
                    }
                    remove() {
                      ((this.isEditing = !1),
                        this.parent &&
                          (this.parent.setEditingState(!0),
                          this.parent.div.classList.add("freeTextEditing")),
                        super.remove());
                    }
                    #d() {
                      const s = this.editorDiv.getElementsByTagName("div");
                      if (s.length === 0) return this.editorDiv.innerText;
                      const t = [];
                      for (const i of s)
                        t.push(i.innerText.replace(/\r\n?|\n/, ""));
                      return t.join(`
`);
                    }
                    #u() {
                      const [s, t] = this.parentDimensions;
                      let i;
                      if (this.isAttachedToDOM)
                        i = this.div.getBoundingClientRect();
                      else {
                        const { currentLayer: h, div: c } = this,
                          n = c.style.display;
                        ((c.style.display = "hidden"),
                          h.div.append(this.div),
                          (i = c.getBoundingClientRect()),
                          c.remove(),
                          (c.style.display = n));
                      }
                      (this.rotation % 180 === this.parentRotation % 180
                        ? ((this.width = i.width / s),
                          (this.height = i.height / t))
                        : ((this.width = i.height / s),
                          (this.height = i.width / t)),
                        this.fixAndSetPosition());
                    }
                    commit() {
                      if (!this.isInEditMode()) return;
                      (super.commit(), this.disableEditMode());
                      const s = this.#a,
                        t = (this.#a = this.#d().trimEnd());
                      if (s === t) return;
                      const i = (h) => {
                        if (((this.#a = h), !h)) {
                          this.remove();
                          return;
                        }
                        (this.#p(), this._uiManager.rebuild(this), this.#u());
                      };
                      (this.addCommands({
                        cmd: () => {
                          i(t);
                        },
                        undo: () => {
                          i(s);
                        },
                        mustExec: !1,
                      }),
                        this.#u());
                    }
                    shouldGetKeyboardEvents() {
                      return this.isInEditMode();
                    }
                    enterInEditMode() {
                      (this.enableEditMode(), this.editorDiv.focus());
                    }
                    dblclick(s) {
                      this.enterInEditMode();
                    }
                    keydown(s) {
                      s.target === this.div &&
                        s.key === "Enter" &&
                        (this.enterInEditMode(), s.preventDefault());
                    }
                    editorDivKeydown(s) {
                      j._keyboardManager.exec(this, s);
                    }
                    editorDivFocus(s) {
                      this.isEditing = !0;
                    }
                    editorDivBlur(s) {
                      this.isEditing = !1;
                    }
                    editorDivInput(s) {
                      this.parent.div.classList.toggle(
                        "freeTextEditing",
                        this.isEmpty(),
                      );
                    }
                    disableEditing() {
                      (this.editorDiv.setAttribute("role", "comment"),
                        this.editorDiv.removeAttribute("aria-multiline"));
                    }
                    enableEditing() {
                      (this.editorDiv.setAttribute("role", "textbox"),
                        this.editorDiv.setAttribute("aria-multiline", !0));
                    }
                    render() {
                      if (this.div) return this.div;
                      let s, t;
                      (this.width && ((s = this.x), (t = this.y)),
                        super.render(),
                        (this.editorDiv = document.createElement("div")),
                        (this.editorDiv.className = "internal"),
                        this.editorDiv.setAttribute("id", this.#r),
                        this.enableEditing(),
                        k.AnnotationEditor._l10nPromise
                          .get("editor_free_text2_aria_label")
                          .then((h) =>
                            this.editorDiv?.setAttribute("aria-label", h),
                          ),
                        k.AnnotationEditor._l10nPromise
                          .get("free_text2_default_content")
                          .then((h) =>
                            this.editorDiv?.setAttribute("default-content", h),
                          ),
                        (this.editorDiv.contentEditable = !0));
                      const { style: i } = this.editorDiv;
                      if (
                        ((i.fontSize = `calc(${this.#l}px * var(--scale-factor))`),
                        (i.color = this.#o),
                        this.div.append(this.editorDiv),
                        (this.overlayDiv = document.createElement("div")),
                        this.overlayDiv.classList.add("overlay", "enabled"),
                        this.div.append(this.overlayDiv),
                        (0, p.bindEvents)(this, this.div, [
                          "dblclick",
                          "keydown",
                        ]),
                        this.width)
                      ) {
                        const [h, c] = this.parentDimensions;
                        if (this.annotationElementId) {
                          const { position: n } = this.#c;
                          let [d, m] = this.getInitialTranslation();
                          [d, m] = this.pageTranslationToScreen(d, m);
                          const [l, w] = this.pageDimensions,
                            [M, C] = this.pageTranslation;
                          let g, E;
                          switch (this.rotation) {
                            case 0:
                              ((g = s + (n[0] - M) / l),
                                (E = t + this.height - (n[1] - C) / w));
                              break;
                            case 90:
                              ((g = s + (n[0] - M) / l),
                                (E = t - (n[1] - C) / w),
                                ([d, m] = [m, -d]));
                              break;
                            case 180:
                              ((g = s - this.width + (n[0] - M) / l),
                                (E = t - (n[1] - C) / w),
                                ([d, m] = [-d, -m]));
                              break;
                            case 270:
                              ((g = s + (n[0] - M - this.height * w) / l),
                                (E = t + (n[1] - C - this.width * l) / w),
                                ([d, m] = [-m, d]));
                              break;
                          }
                          this.setAt(g * h, E * c, d, m);
                        } else
                          this.setAt(
                            s * h,
                            t * c,
                            this.width * h,
                            this.height * c,
                          );
                        (this.#p(),
                          (this._isDraggable = !0),
                          (this.editorDiv.contentEditable = !1));
                      } else
                        ((this._isDraggable = !1),
                          (this.editorDiv.contentEditable = !0));
                      return this.div;
                    }
                    #p() {
                      if ((this.editorDiv.replaceChildren(), !!this.#a))
                        for (const s of this.#a.split(`
`)) {
                          const t = document.createElement("div");
                          (t.append(
                            s
                              ? document.createTextNode(s)
                              : document.createElement("br"),
                          ),
                            this.editorDiv.append(t));
                        }
                    }
                    get contentDiv() {
                      return this.editorDiv;
                    }
                    static deserialize(s, t, i) {
                      let h = null;
                      if (s instanceof T.FreeTextAnnotationElement) {
                        const {
                          data: {
                            defaultAppearanceData: {
                              fontSize: n,
                              fontColor: d,
                            },
                            rect: m,
                            rotation: l,
                            id: w,
                          },
                          textContent: M,
                          textPosition: C,
                          parent: {
                            page: { pageNumber: g },
                          },
                        } = s;
                        if (!M || M.length === 0) return null;
                        h = s = {
                          annotationType: a.AnnotationEditorType.FREETEXT,
                          color: Array.from(d),
                          fontSize: n,
                          value: M.join(`
`),
                          position: C,
                          pageIndex: g - 1,
                          rect: m,
                          rotation: l,
                          id: w,
                          deleted: !1,
                        };
                      }
                      const c = super.deserialize(s, t, i);
                      return (
                        (c.#l = s.fontSize),
                        (c.#o = a.Util.makeHexColor(...s.color)),
                        (c.#a = s.value),
                        (c.annotationElementId = s.id || null),
                        (c.#c = h),
                        c
                      );
                    }
                    serialize(s = !1) {
                      if (this.isEmpty()) return null;
                      if (this.deleted)
                        return {
                          pageIndex: this.pageIndex,
                          id: this.annotationElementId,
                          deleted: !0,
                        };
                      const t = j._internalPadding * this.parentScale,
                        i = this.getRect(t, t),
                        h = k.AnnotationEditor._colorManager.convert(
                          this.isAttachedToDOM
                            ? getComputedStyle(this.editorDiv).color
                            : this.#o,
                        ),
                        c = {
                          annotationType: a.AnnotationEditorType.FREETEXT,
                          color: h,
                          fontSize: this.#l,
                          value: this.#a,
                          pageIndex: this.pageIndex,
                          rect: i,
                          rotation: this.rotation,
                          structTreeParentId: this._structTreeParentId,
                        };
                      return s
                        ? c
                        : this.annotationElementId && !this.#b(c)
                          ? null
                          : ((c.id = this.annotationElementId), c);
                    }
                    #b(s) {
                      const {
                        value: t,
                        fontSize: i,
                        color: h,
                        rect: c,
                        pageIndex: n,
                      } = this.#c;
                      return (
                        s.value !== t ||
                        s.fontSize !== i ||
                        s.rect.some((d, m) => Math.abs(d - c[m]) >= 1) ||
                        s.color.some((d, m) => d !== h[m]) ||
                        s.pageIndex !== n
                      );
                    }
                    #m(s = !1) {
                      if (!this.annotationElementId) return;
                      if (
                        (this.#u(),
                        !s && (this.width === 0 || this.height === 0))
                      ) {
                        setTimeout(() => this.#m(!0), 0);
                        return;
                      }
                      const t = j._internalPadding * this.parentScale;
                      this.#c.rect = this.getRect(t, t);
                    }
                  }
                  e.FreeTextEditor = j;
                },
                (A, e, y) => {
                  (Object.defineProperty(e, "__esModule", { value: !0 }),
                    (e.StampAnnotationElement =
                      e.InkAnnotationElement =
                      e.FreeTextAnnotationElement =
                      e.AnnotationLayer =
                        void 0));
                  var a = y(1),
                    p = y(6),
                    k = y(3),
                    T = y(30),
                    j = y(31),
                    D = y(32);
                  const s = 1e3,
                    t = 9,
                    i = new WeakSet();
                  function h(R) {
                    return { width: R[2] - R[0], height: R[3] - R[1] };
                  }
                  class c {
                    static create(o) {
                      switch (o.data.annotationType) {
                        case a.AnnotationType.LINK:
                          return new d(o);
                        case a.AnnotationType.TEXT:
                          return new m(o);
                        case a.AnnotationType.WIDGET:
                          switch (o.data.fieldType) {
                            case "Tx":
                              return new w(o);
                            case "Btn":
                              return o.data.radioButton
                                ? new g(o)
                                : o.data.checkBox
                                  ? new C(o)
                                  : new E(o);
                            case "Ch":
                              return new U(o);
                            case "Sig":
                              return new M(o);
                          }
                          return new l(o);
                        case a.AnnotationType.POPUP:
                          return new W(o);
                        case a.AnnotationType.FREETEXT:
                          return new V(o);
                        case a.AnnotationType.LINE:
                          return new G(o);
                        case a.AnnotationType.SQUARE:
                          return new nt(o);
                        case a.AnnotationType.CIRCLE:
                          return new Z(o);
                        case a.AnnotationType.POLYLINE:
                          return new tt(o);
                        case a.AnnotationType.CARET:
                          return new K(o);
                        case a.AnnotationType.INK:
                          return new I(o);
                        case a.AnnotationType.POLYGON:
                          return new rt(o);
                        case a.AnnotationType.HIGHLIGHT:
                          return new _(o);
                        case a.AnnotationType.UNDERLINE:
                          return new u(o);
                        case a.AnnotationType.SQUIGGLY:
                          return new f(o);
                        case a.AnnotationType.STRIKEOUT:
                          return new v(o);
                        case a.AnnotationType.STAMP:
                          return new F(o);
                        case a.AnnotationType.FILEATTACHMENT:
                          return new L(o);
                        default:
                          return new n(o);
                      }
                    }
                  }
                  class n {
                    #t = !1;
                    constructor(
                      o,
                      {
                        isRenderable: b = !1,
                        ignoreBorder: S = !1,
                        createQuadrilaterals: x = !1,
                      } = {},
                    ) {
                      ((this.isRenderable = b),
                        (this.data = o.data),
                        (this.layer = o.layer),
                        (this.linkService = o.linkService),
                        (this.downloadManager = o.downloadManager),
                        (this.imageResourcesPath = o.imageResourcesPath),
                        (this.renderForms = o.renderForms),
                        (this.svgFactory = o.svgFactory),
                        (this.annotationStorage = o.annotationStorage),
                        (this.enableScripting = o.enableScripting),
                        (this.hasJSActions = o.hasJSActions),
                        (this._fieldObjects = o.fieldObjects),
                        (this.parent = o.parent),
                        b && (this.container = this._createContainer(S)),
                        x && this._createQuadrilaterals());
                    }
                    static _hasPopupData({
                      titleObj: o,
                      contentsObj: b,
                      richText: S,
                    }) {
                      return !!(o?.str || b?.str || S?.str);
                    }
                    get hasPopupData() {
                      return n._hasPopupData(this.data);
                    }
                    _createContainer(o) {
                      const {
                          data: b,
                          parent: { page: S, viewport: x },
                        } = this,
                        P = document.createElement("section");
                      (P.setAttribute("data-annotation-id", b.id),
                        this instanceof l || (P.tabIndex = s),
                        (P.style.zIndex = this.parent.zIndex++),
                        this.data.popupRef &&
                          P.setAttribute("aria-haspopup", "dialog"),
                        b.noRotate && P.classList.add("norotate"));
                      const {
                        pageWidth: B,
                        pageHeight: H,
                        pageX: z,
                        pageY: st,
                      } = x.rawDims;
                      if (!b.rect || this instanceof W) {
                        const { rotation: et } = b;
                        return (
                          !b.hasOwnCanvas &&
                            et !== 0 &&
                            this.setRotation(et, P),
                          P
                        );
                      }
                      const { width: Y, height: X } = h(b.rect),
                        J = a.Util.normalizeRect([
                          b.rect[0],
                          S.view[3] - b.rect[1] + S.view[1],
                          b.rect[2],
                          S.view[3] - b.rect[3] + S.view[1],
                        ]);
                      if (!o && b.borderStyle.width > 0) {
                        P.style.borderWidth = `${b.borderStyle.width}px`;
                        const et = b.borderStyle.horizontalCornerRadius,
                          at = b.borderStyle.verticalCornerRadius;
                        if (et > 0 || at > 0) {
                          const ct = `calc(${et}px * var(--scale-factor)) / calc(${at}px * var(--scale-factor))`;
                          P.style.borderRadius = ct;
                        } else if (this instanceof g) {
                          const ct = `calc(${Y}px * var(--scale-factor)) / calc(${X}px * var(--scale-factor))`;
                          P.style.borderRadius = ct;
                        }
                        switch (b.borderStyle.style) {
                          case a.AnnotationBorderStyleType.SOLID:
                            P.style.borderStyle = "solid";
                            break;
                          case a.AnnotationBorderStyleType.DASHED:
                            P.style.borderStyle = "dashed";
                            break;
                          case a.AnnotationBorderStyleType.BEVELED:
                            (0, a.warn)("Unimplemented border style: beveled");
                            break;
                          case a.AnnotationBorderStyleType.INSET:
                            (0, a.warn)("Unimplemented border style: inset");
                            break;
                          case a.AnnotationBorderStyleType.UNDERLINE:
                            P.style.borderBottomStyle = "solid";
                            break;
                        }
                        const lt = b.borderColor || null;
                        lt
                          ? ((this.#t = !0),
                            (P.style.borderColor = a.Util.makeHexColor(
                              lt[0] | 0,
                              lt[1] | 0,
                              lt[2] | 0,
                            )))
                          : (P.style.borderWidth = 0);
                      }
                      ((P.style.left = `${(100 * (J[0] - z)) / B}%`),
                        (P.style.top = `${(100 * (J[1] - st)) / H}%`));
                      const { rotation: Q } = b;
                      return (
                        b.hasOwnCanvas || Q === 0
                          ? ((P.style.width = `${(100 * Y) / B}%`),
                            (P.style.height = `${(100 * X) / H}%`))
                          : this.setRotation(Q, P),
                        P
                      );
                    }
                    setRotation(o, b = this.container) {
                      if (!this.data.rect) return;
                      const { pageWidth: S, pageHeight: x } =
                          this.parent.viewport.rawDims,
                        { width: P, height: B } = h(this.data.rect);
                      let H, z;
                      (o % 180 === 0
                        ? ((H = (100 * P) / S), (z = (100 * B) / x))
                        : ((H = (100 * B) / S), (z = (100 * P) / x)),
                        (b.style.width = `${H}%`),
                        (b.style.height = `${z}%`),
                        b.setAttribute("data-main-rotation", (360 - o) % 360));
                    }
                    get _commonActions() {
                      const o = (b, S, x) => {
                        const P = x.detail[b],
                          B = P[0],
                          H = P.slice(1);
                        ((x.target.style[S] =
                          T.ColorConverters[`${B}_HTML`](H)),
                          this.annotationStorage.setValue(this.data.id, {
                            [S]: T.ColorConverters[`${B}_rgb`](H),
                          }));
                      };
                      return (0, a.shadow)(this, "_commonActions", {
                        display: (b) => {
                          const { display: S } = b.detail,
                            x = S % 2 === 1;
                          ((this.container.style.visibility = x
                            ? "hidden"
                            : "visible"),
                            this.annotationStorage.setValue(this.data.id, {
                              noView: x,
                              noPrint: S === 1 || S === 2,
                            }));
                        },
                        print: (b) => {
                          this.annotationStorage.setValue(this.data.id, {
                            noPrint: !b.detail.print,
                          });
                        },
                        hidden: (b) => {
                          const { hidden: S } = b.detail;
                          ((this.container.style.visibility = S
                            ? "hidden"
                            : "visible"),
                            this.annotationStorage.setValue(this.data.id, {
                              noPrint: S,
                              noView: S,
                            }));
                        },
                        focus: (b) => {
                          setTimeout(
                            () => b.target.focus({ preventScroll: !1 }),
                            0,
                          );
                        },
                        userName: (b) => {
                          b.target.title = b.detail.userName;
                        },
                        readonly: (b) => {
                          b.target.disabled = b.detail.readonly;
                        },
                        required: (b) => {
                          this._setRequired(b.target, b.detail.required);
                        },
                        bgColor: (b) => {
                          o("bgColor", "backgroundColor", b);
                        },
                        fillColor: (b) => {
                          o("fillColor", "backgroundColor", b);
                        },
                        fgColor: (b) => {
                          o("fgColor", "color", b);
                        },
                        textColor: (b) => {
                          o("textColor", "color", b);
                        },
                        borderColor: (b) => {
                          o("borderColor", "borderColor", b);
                        },
                        strokeColor: (b) => {
                          o("strokeColor", "borderColor", b);
                        },
                        rotation: (b) => {
                          const S = b.detail.rotation;
                          (this.setRotation(S),
                            this.annotationStorage.setValue(this.data.id, {
                              rotation: S,
                            }));
                        },
                      });
                    }
                    _dispatchEventFromSandbox(o, b) {
                      const S = this._commonActions;
                      for (const x of Object.keys(b.detail))
                        (o[x] || S[x])?.(b);
                    }
                    _setDefaultPropertiesFromJS(o) {
                      if (!this.enableScripting) return;
                      const b = this.annotationStorage.getRawValue(
                        this.data.id,
                      );
                      if (!b) return;
                      const S = this._commonActions;
                      for (const [x, P] of Object.entries(b)) {
                        const B = S[x];
                        if (B) {
                          const H = { detail: { [x]: P }, target: o };
                          (B(H), delete b[x]);
                        }
                      }
                    }
                    _createQuadrilaterals() {
                      if (!this.container) return;
                      const { quadPoints: o } = this.data;
                      if (!o) return;
                      const [b, S, x, P] = this.data.rect;
                      if (o.length === 1) {
                        const [, { x: at, y: lt }, { x: ct, y: ht }] = o[0];
                        if (x === at && P === lt && b === ct && S === ht)
                          return;
                      }
                      const { style: B } = this.container;
                      let H;
                      if (this.#t) {
                        const { borderColor: at, borderWidth: lt } = B;
                        ((B.borderWidth = 0),
                          (H = [
                            "url('data:image/svg+xml;utf8,",
                            '<svg xmlns="http://www.w3.org/2000/svg"',
                            ' preserveAspectRatio="none" viewBox="0 0 1 1">',
                            `<g fill="transparent" stroke="${at}" stroke-width="${lt}">`,
                          ]),
                          this.container.classList.add("hasBorder"));
                      }
                      const z = x - b,
                        st = P - S,
                        { svgFactory: Y } = this,
                        X = Y.createElement("svg");
                      (X.classList.add("quadrilateralsContainer"),
                        X.setAttribute("width", 0),
                        X.setAttribute("height", 0));
                      const J = Y.createElement("defs");
                      X.append(J);
                      const Q = Y.createElement("clipPath"),
                        et = `clippath_${this.data.id}`;
                      (Q.setAttribute("id", et),
                        Q.setAttribute("clipPathUnits", "objectBoundingBox"),
                        J.append(Q));
                      for (const [, { x: at, y: lt }, { x: ct, y: ht }] of o) {
                        const dt = Y.createElement("rect"),
                          ut = (ct - b) / z,
                          At = (P - lt) / st,
                          gt = (at - ct) / z,
                          wt = (lt - ht) / st;
                        (dt.setAttribute("x", ut),
                          dt.setAttribute("y", At),
                          dt.setAttribute("width", gt),
                          dt.setAttribute("height", wt),
                          Q.append(dt),
                          H?.push(
                            `<rect vector-effect="non-scaling-stroke" x="${ut}" y="${At}" width="${gt}" height="${wt}"/>`,
                          ));
                      }
                      (this.#t &&
                        (H.push("</g></svg>')"),
                        (B.backgroundImage = H.join(""))),
                        this.container.append(X),
                        (this.container.style.clipPath = `url(#${et})`));
                    }
                    _createPopup() {
                      const { container: o, data: b } = this;
                      o.setAttribute("aria-haspopup", "dialog");
                      const S = new W({
                        data: {
                          color: b.color,
                          titleObj: b.titleObj,
                          modificationDate: b.modificationDate,
                          contentsObj: b.contentsObj,
                          richText: b.richText,
                          parentRect: b.rect,
                          borderStyle: 0,
                          id: `popup_${b.id}`,
                          rotation: b.rotation,
                        },
                        parent: this.parent,
                        elements: [this],
                      });
                      this.parent.div.append(S.render());
                    }
                    render() {
                      (0, a.unreachable)(
                        "Abstract method `AnnotationElement.render` called",
                      );
                    }
                    _getElementsByName(o, b = null) {
                      const S = [];
                      if (this._fieldObjects) {
                        const x = this._fieldObjects[o];
                        if (x)
                          for (const { page: P, id: B, exportValues: H } of x) {
                            if (P === -1 || B === b) continue;
                            const z = typeof H == "string" ? H : null,
                              st = document.querySelector(
                                `[data-element-id="${B}"]`,
                              );
                            if (st && !i.has(st)) {
                              (0, a.warn)(
                                `_getElementsByName - element not allowed: ${B}`,
                              );
                              continue;
                            }
                            S.push({ id: B, exportValue: z, domElement: st });
                          }
                        return S;
                      }
                      for (const x of document.getElementsByName(o)) {
                        const { exportValue: P } = x,
                          B = x.getAttribute("data-element-id");
                        B !== b &&
                          i.has(x) &&
                          S.push({ id: B, exportValue: P, domElement: x });
                      }
                      return S;
                    }
                    show() {
                      (this.container && (this.container.hidden = !1),
                        this.popup?.maybeShow());
                    }
                    hide() {
                      (this.container && (this.container.hidden = !0),
                        this.popup?.forceHide());
                    }
                    getElementsToTriggerPopup() {
                      return this.container;
                    }
                    addHighlightArea() {
                      const o = this.getElementsToTriggerPopup();
                      if (Array.isArray(o))
                        for (const b of o) b.classList.add("highlightArea");
                      else o.classList.add("highlightArea");
                    }
                    _editOnDoubleClick() {
                      const {
                        annotationEditorType: o,
                        data: { id: b },
                      } = this;
                      this.container.addEventListener("dblclick", () => {
                        this.linkService.eventBus?.dispatch(
                          "switchannotationeditormode",
                          { source: this, mode: o, editId: b },
                        );
                      });
                    }
                  }
                  class d extends n {
                    constructor(o, b = null) {
                      (super(o, {
                        isRenderable: !0,
                        ignoreBorder: !!b?.ignoreBorder,
                        createQuadrilaterals: !0,
                      }),
                        (this.isTooltipOnly = o.data.isTooltipOnly));
                    }
                    render() {
                      const { data: o, linkService: b } = this,
                        S = document.createElement("a");
                      S.setAttribute("data-element-id", o.id);
                      let x = !1;
                      return (
                        o.url
                          ? (b.addLinkAttributes(S, o.url, o.newWindow),
                            (x = !0))
                          : o.action
                            ? (this._bindNamedAction(S, o.action), (x = !0))
                            : o.attachment
                              ? (this._bindAttachment(S, o.attachment),
                                (x = !0))
                              : o.setOCGState
                                ? (this.#e(S, o.setOCGState), (x = !0))
                                : o.dest
                                  ? (this._bindLink(S, o.dest), (x = !0))
                                  : (o.actions &&
                                      (o.actions.Action ||
                                        o.actions["Mouse Up"] ||
                                        o.actions["Mouse Down"]) &&
                                      this.enableScripting &&
                                      this.hasJSActions &&
                                      (this._bindJSAction(S, o), (x = !0)),
                                    o.resetForm
                                      ? (this._bindResetFormAction(
                                          S,
                                          o.resetForm,
                                        ),
                                        (x = !0))
                                      : this.isTooltipOnly &&
                                        !x &&
                                        (this._bindLink(S, ""), (x = !0))),
                        this.container.classList.add("linkAnnotation"),
                        x && this.container.append(S),
                        this.container
                      );
                    }
                    #t() {
                      this.container.setAttribute("data-internal-link", "");
                    }
                    _bindLink(o, b) {
                      ((o.href = this.linkService.getDestinationHash(b)),
                        (o.onclick = () => (
                          b && this.linkService.goToDestination(b),
                          !1
                        )),
                        (b || b === "") && this.#t());
                    }
                    _bindNamedAction(o, b) {
                      ((o.href = this.linkService.getAnchorUrl("")),
                        (o.onclick = () => (
                          this.linkService.executeNamedAction(b),
                          !1
                        )),
                        this.#t());
                    }
                    _bindAttachment(o, b) {
                      ((o.href = this.linkService.getAnchorUrl("")),
                        (o.onclick = () => (
                          this.downloadManager?.openOrDownloadData(
                            this.container,
                            b.content,
                            b.filename,
                          ),
                          !1
                        )),
                        this.#t());
                    }
                    #e(o, b) {
                      ((o.href = this.linkService.getAnchorUrl("")),
                        (o.onclick = () => (
                          this.linkService.executeSetOCGState(b),
                          !1
                        )),
                        this.#t());
                    }
                    _bindJSAction(o, b) {
                      o.href = this.linkService.getAnchorUrl("");
                      const S = new Map([
                        ["Action", "onclick"],
                        ["Mouse Up", "onmouseup"],
                        ["Mouse Down", "onmousedown"],
                      ]);
                      for (const x of Object.keys(b.actions)) {
                        const P = S.get(x);
                        P &&
                          (o[P] = () => (
                            this.linkService.eventBus?.dispatch(
                              "dispatcheventinsandbox",
                              { source: this, detail: { id: b.id, name: x } },
                            ),
                            !1
                          ));
                      }
                      (o.onclick || (o.onclick = () => !1), this.#t());
                    }
                    _bindResetFormAction(o, b) {
                      const S = o.onclick;
                      if (
                        (S || (o.href = this.linkService.getAnchorUrl("")),
                        this.#t(),
                        !this._fieldObjects)
                      ) {
                        ((0, a.warn)(
                          '_bindResetFormAction - "resetForm" action not supported, ensure that the `fieldObjects` parameter is provided.',
                        ),
                          S || (o.onclick = () => !1));
                        return;
                      }
                      o.onclick = () => {
                        S?.();
                        const { fields: x, refs: P, include: B } = b,
                          H = [];
                        if (x.length !== 0 || P.length !== 0) {
                          const Y = new Set(P);
                          for (const X of x) {
                            const J = this._fieldObjects[X] || [];
                            for (const { id: Q } of J) Y.add(Q);
                          }
                          for (const X of Object.values(this._fieldObjects))
                            for (const J of X) Y.has(J.id) === B && H.push(J);
                        } else
                          for (const Y of Object.values(this._fieldObjects))
                            H.push(...Y);
                        const z = this.annotationStorage,
                          st = [];
                        for (const Y of H) {
                          const { id: X } = Y;
                          switch ((st.push(X), Y.type)) {
                            case "text": {
                              const Q = Y.defaultValue || "";
                              z.setValue(X, { value: Q });
                              break;
                            }
                            case "checkbox":
                            case "radiobutton": {
                              const Q = Y.defaultValue === Y.exportValues;
                              z.setValue(X, { value: Q });
                              break;
                            }
                            case "combobox":
                            case "listbox": {
                              const Q = Y.defaultValue || "";
                              z.setValue(X, { value: Q });
                              break;
                            }
                            default:
                              continue;
                          }
                          const J = document.querySelector(
                            `[data-element-id="${X}"]`,
                          );
                          if (J) {
                            if (!i.has(J)) {
                              (0, a.warn)(
                                `_bindResetFormAction - element not allowed: ${X}`,
                              );
                              continue;
                            }
                          } else continue;
                          J.dispatchEvent(new Event("resetform"));
                        }
                        return (
                          this.enableScripting &&
                            this.linkService.eventBus?.dispatch(
                              "dispatcheventinsandbox",
                              {
                                source: this,
                                detail: {
                                  id: "app",
                                  ids: st,
                                  name: "ResetForm",
                                },
                              },
                            ),
                          !1
                        );
                      };
                    }
                  }
                  class m extends n {
                    constructor(o) {
                      super(o, { isRenderable: !0 });
                    }
                    render() {
                      this.container.classList.add("textAnnotation");
                      const o = document.createElement("img");
                      return (
                        (o.src =
                          this.imageResourcesPath +
                          "annotation-" +
                          this.data.name.toLowerCase() +
                          ".svg"),
                        (o.alt = "[{{type}} Annotation]"),
                        (o.dataset.l10nId = "text_annotation_type"),
                        (o.dataset.l10nArgs = JSON.stringify({
                          type: this.data.name,
                        })),
                        !this.data.popupRef &&
                          this.hasPopupData &&
                          this._createPopup(),
                        this.container.append(o),
                        this.container
                      );
                    }
                  }
                  class l extends n {
                    render() {
                      return (
                        this.data.alternativeText &&
                          (this.container.title = this.data.alternativeText),
                        this.container
                      );
                    }
                    showElementAndHideCanvas(o) {
                      this.data.hasOwnCanvas &&
                        (o.previousSibling?.nodeName === "CANVAS" &&
                          (o.previousSibling.hidden = !0),
                        (o.hidden = !1));
                    }
                    _getKeyModifier(o) {
                      const { isWin: b, isMac: S } = a.FeatureTest.platform;
                      return (b && o.ctrlKey) || (S && o.metaKey);
                    }
                    _setEventListener(o, b, S, x, P) {
                      S.includes("mouse")
                        ? o.addEventListener(S, (B) => {
                            this.linkService.eventBus?.dispatch(
                              "dispatcheventinsandbox",
                              {
                                source: this,
                                detail: {
                                  id: this.data.id,
                                  name: x,
                                  value: P(B),
                                  shift: B.shiftKey,
                                  modifier: this._getKeyModifier(B),
                                },
                              },
                            );
                          })
                        : o.addEventListener(S, (B) => {
                            if (S === "blur") {
                              if (!b.focused || !B.relatedTarget) return;
                              b.focused = !1;
                            } else if (S === "focus") {
                              if (b.focused) return;
                              b.focused = !0;
                            }
                            P &&
                              this.linkService.eventBus?.dispatch(
                                "dispatcheventinsandbox",
                                {
                                  source: this,
                                  detail: {
                                    id: this.data.id,
                                    name: x,
                                    value: P(B),
                                  },
                                },
                              );
                          });
                    }
                    _setEventListeners(o, b, S, x) {
                      for (const [P, B] of S)
                        (B === "Action" || this.data.actions?.[B]) &&
                          ((B === "Focus" || B === "Blur") &&
                            (b ||= { focused: !1 }),
                          this._setEventListener(o, b, P, B, x),
                          B === "Focus" && !this.data.actions?.Blur
                            ? this._setEventListener(o, b, "blur", "Blur", null)
                            : B === "Blur" &&
                              !this.data.actions?.Focus &&
                              this._setEventListener(
                                o,
                                b,
                                "focus",
                                "Focus",
                                null,
                              ));
                    }
                    _setBackgroundColor(o) {
                      const b = this.data.backgroundColor || null;
                      o.style.backgroundColor =
                        b === null
                          ? "transparent"
                          : a.Util.makeHexColor(b[0], b[1], b[2]);
                    }
                    _setTextStyle(o) {
                      const b = ["left", "center", "right"],
                        { fontColor: S } = this.data.defaultAppearanceData,
                        x = this.data.defaultAppearanceData.fontSize || t,
                        P = o.style;
                      let B;
                      const H = 2,
                        z = (st) => Math.round(10 * st) / 10;
                      if (this.data.multiLine) {
                        const st = Math.abs(
                            this.data.rect[3] - this.data.rect[1] - H,
                          ),
                          Y = Math.round(st / (a.LINE_FACTOR * x)) || 1,
                          X = st / Y;
                        B = Math.min(x, z(X / a.LINE_FACTOR));
                      } else {
                        const st = Math.abs(
                          this.data.rect[3] - this.data.rect[1] - H,
                        );
                        B = Math.min(x, z(st / a.LINE_FACTOR));
                      }
                      ((P.fontSize = `calc(${B}px * var(--scale-factor))`),
                        (P.color = a.Util.makeHexColor(S[0], S[1], S[2])),
                        this.data.textAlignment !== null &&
                          (P.textAlign = b[this.data.textAlignment]));
                    }
                    _setRequired(o, b) {
                      (b
                        ? o.setAttribute("required", !0)
                        : o.removeAttribute("required"),
                        o.setAttribute("aria-required", b));
                    }
                  }
                  class w extends l {
                    constructor(o) {
                      const b =
                        o.renderForms ||
                        (!o.data.hasAppearance && !!o.data.fieldValue);
                      super(o, { isRenderable: b });
                    }
                    setPropertyOnSiblings(o, b, S, x) {
                      const P = this.annotationStorage;
                      for (const B of this._getElementsByName(o.name, o.id))
                        (B.domElement && (B.domElement[b] = S),
                          P.setValue(B.id, { [x]: S }));
                    }
                    render() {
                      const o = this.annotationStorage,
                        b = this.data.id;
                      this.container.classList.add("textWidgetAnnotation");
                      let S = null;
                      if (this.renderForms) {
                        const x = o.getValue(b, {
                          value: this.data.fieldValue,
                        });
                        let P = x.value || "";
                        const B = o.getValue(b, {
                          charLimit: this.data.maxLen,
                        }).charLimit;
                        B && P.length > B && (P = P.slice(0, B));
                        let H =
                          x.formattedValue ||
                          this.data.textContent?.join(`
`) ||
                          null;
                        H && this.data.comb && (H = H.replaceAll(/\s+/g, ""));
                        const z = {
                          userValue: P,
                          formattedValue: H,
                          lastCommittedValue: null,
                          commitKey: 1,
                          focused: !1,
                        };
                        (this.data.multiLine
                          ? ((S = document.createElement("textarea")),
                            (S.textContent = H ?? P),
                            this.data.doNotScroll &&
                              (S.style.overflowY = "hidden"))
                          : ((S = document.createElement("input")),
                            (S.type = "text"),
                            S.setAttribute("value", H ?? P),
                            this.data.doNotScroll &&
                              (S.style.overflowX = "hidden")),
                          this.data.hasOwnCanvas && (S.hidden = !0),
                          i.add(S),
                          S.setAttribute("data-element-id", b),
                          (S.disabled = this.data.readOnly),
                          (S.name = this.data.fieldName),
                          (S.tabIndex = s),
                          this._setRequired(S, this.data.required),
                          B && (S.maxLength = B),
                          S.addEventListener("input", (Y) => {
                            (o.setValue(b, { value: Y.target.value }),
                              this.setPropertyOnSiblings(
                                S,
                                "value",
                                Y.target.value,
                                "value",
                              ),
                              (z.formattedValue = null));
                          }),
                          S.addEventListener("resetform", (Y) => {
                            const X = this.data.defaultFieldValue ?? "";
                            ((S.value = z.userValue = X),
                              (z.formattedValue = null));
                          }));
                        let st = (Y) => {
                          const { formattedValue: X } = z;
                          (X != null && (Y.target.value = X),
                            (Y.target.scrollLeft = 0));
                        };
                        if (this.enableScripting && this.hasJSActions) {
                          (S.addEventListener("focus", (X) => {
                            if (z.focused) return;
                            const { target: J } = X;
                            (z.userValue && (J.value = z.userValue),
                              (z.lastCommittedValue = J.value),
                              (z.commitKey = 1),
                              (z.focused = !0));
                          }),
                            S.addEventListener("updatefromsandbox", (X) => {
                              this.showElementAndHideCanvas(X.target);
                              const J = {
                                value(Q) {
                                  ((z.userValue = Q.detail.value ?? ""),
                                    o.setValue(b, {
                                      value: z.userValue.toString(),
                                    }),
                                    (Q.target.value = z.userValue));
                                },
                                formattedValue(Q) {
                                  const { formattedValue: et } = Q.detail;
                                  ((z.formattedValue = et),
                                    et != null &&
                                      Q.target !== document.activeElement &&
                                      (Q.target.value = et),
                                    o.setValue(b, { formattedValue: et }));
                                },
                                selRange(Q) {
                                  Q.target.setSelectionRange(
                                    ...Q.detail.selRange,
                                  );
                                },
                                charLimit: (Q) => {
                                  const { charLimit: et } = Q.detail,
                                    { target: at } = Q;
                                  if (et === 0) {
                                    at.removeAttribute("maxLength");
                                    return;
                                  }
                                  at.setAttribute("maxLength", et);
                                  let lt = z.userValue;
                                  !lt ||
                                    lt.length <= et ||
                                    ((lt = lt.slice(0, et)),
                                    (at.value = z.userValue = lt),
                                    o.setValue(b, { value: lt }),
                                    this.linkService.eventBus?.dispatch(
                                      "dispatcheventinsandbox",
                                      {
                                        source: this,
                                        detail: {
                                          id: b,
                                          name: "Keystroke",
                                          value: lt,
                                          willCommit: !0,
                                          commitKey: 1,
                                          selStart: at.selectionStart,
                                          selEnd: at.selectionEnd,
                                        },
                                      },
                                    ));
                                },
                              };
                              this._dispatchEventFromSandbox(J, X);
                            }),
                            S.addEventListener("keydown", (X) => {
                              z.commitKey = 1;
                              let J = -1;
                              if (
                                (X.key === "Escape"
                                  ? (J = 0)
                                  : X.key === "Enter" && !this.data.multiLine
                                    ? (J = 2)
                                    : X.key === "Tab" && (z.commitKey = 3),
                                J === -1)
                              )
                                return;
                              const { value: Q } = X.target;
                              z.lastCommittedValue !== Q &&
                                ((z.lastCommittedValue = Q),
                                (z.userValue = Q),
                                this.linkService.eventBus?.dispatch(
                                  "dispatcheventinsandbox",
                                  {
                                    source: this,
                                    detail: {
                                      id: b,
                                      name: "Keystroke",
                                      value: Q,
                                      willCommit: !0,
                                      commitKey: J,
                                      selStart: X.target.selectionStart,
                                      selEnd: X.target.selectionEnd,
                                    },
                                  },
                                ));
                            }));
                          const Y = st;
                          ((st = null),
                            S.addEventListener("blur", (X) => {
                              if (!z.focused || !X.relatedTarget) return;
                              z.focused = !1;
                              const { value: J } = X.target;
                              ((z.userValue = J),
                                z.lastCommittedValue !== J &&
                                  this.linkService.eventBus?.dispatch(
                                    "dispatcheventinsandbox",
                                    {
                                      source: this,
                                      detail: {
                                        id: b,
                                        name: "Keystroke",
                                        value: J,
                                        willCommit: !0,
                                        commitKey: z.commitKey,
                                        selStart: X.target.selectionStart,
                                        selEnd: X.target.selectionEnd,
                                      },
                                    },
                                  ),
                                Y(X));
                            }),
                            this.data.actions?.Keystroke &&
                              S.addEventListener("beforeinput", (X) => {
                                z.lastCommittedValue = null;
                                const { data: J, target: Q } = X,
                                  {
                                    value: et,
                                    selectionStart: at,
                                    selectionEnd: lt,
                                  } = Q;
                                let ct = at,
                                  ht = lt;
                                switch (X.inputType) {
                                  case "deleteWordBackward": {
                                    const dt = et
                                      .substring(0, at)
                                      .match(/\w*[^\w]*$/);
                                    dt && (ct -= dt[0].length);
                                    break;
                                  }
                                  case "deleteWordForward": {
                                    const dt = et
                                      .substring(at)
                                      .match(/^[^\w]*\w*/);
                                    dt && (ht += dt[0].length);
                                    break;
                                  }
                                  case "deleteContentBackward":
                                    at === lt && (ct -= 1);
                                    break;
                                  case "deleteContentForward":
                                    at === lt && (ht += 1);
                                    break;
                                }
                                (X.preventDefault(),
                                  this.linkService.eventBus?.dispatch(
                                    "dispatcheventinsandbox",
                                    {
                                      source: this,
                                      detail: {
                                        id: b,
                                        name: "Keystroke",
                                        value: et,
                                        change: J || "",
                                        willCommit: !1,
                                        selStart: ct,
                                        selEnd: ht,
                                      },
                                    },
                                  ));
                              }),
                            this._setEventListeners(
                              S,
                              z,
                              [
                                ["focus", "Focus"],
                                ["blur", "Blur"],
                                ["mousedown", "Mouse Down"],
                                ["mouseenter", "Mouse Enter"],
                                ["mouseleave", "Mouse Exit"],
                                ["mouseup", "Mouse Up"],
                              ],
                              (X) => X.target.value,
                            ));
                        }
                        if (
                          (st && S.addEventListener("blur", st), this.data.comb)
                        ) {
                          const X = (this.data.rect[2] - this.data.rect[0]) / B;
                          (S.classList.add("comb"),
                            (S.style.letterSpacing = `calc(${X}px * var(--scale-factor) - 1ch)`));
                        }
                      } else
                        ((S = document.createElement("div")),
                          (S.textContent = this.data.fieldValue),
                          (S.style.verticalAlign = "middle"),
                          (S.style.display = "table-cell"));
                      return (
                        this._setTextStyle(S),
                        this._setBackgroundColor(S),
                        this._setDefaultPropertiesFromJS(S),
                        this.container.append(S),
                        this.container
                      );
                    }
                  }
                  class M extends l {
                    constructor(o) {
                      super(o, { isRenderable: !!o.data.hasOwnCanvas });
                    }
                  }
                  class C extends l {
                    constructor(o) {
                      super(o, { isRenderable: o.renderForms });
                    }
                    render() {
                      const o = this.annotationStorage,
                        b = this.data,
                        S = b.id;
                      let x = o.getValue(S, {
                        value: b.exportValue === b.fieldValue,
                      }).value;
                      (typeof x == "string" &&
                        ((x = x !== "Off"), o.setValue(S, { value: x })),
                        this.container.classList.add(
                          "buttonWidgetAnnotation",
                          "checkBox",
                        ));
                      const P = document.createElement("input");
                      return (
                        i.add(P),
                        P.setAttribute("data-element-id", S),
                        (P.disabled = b.readOnly),
                        this._setRequired(P, this.data.required),
                        (P.type = "checkbox"),
                        (P.name = b.fieldName),
                        x && P.setAttribute("checked", !0),
                        P.setAttribute("exportValue", b.exportValue),
                        (P.tabIndex = s),
                        P.addEventListener("change", (B) => {
                          const { name: H, checked: z } = B.target;
                          for (const st of this._getElementsByName(H, S)) {
                            const Y = z && st.exportValue === b.exportValue;
                            (st.domElement && (st.domElement.checked = Y),
                              o.setValue(st.id, { value: Y }));
                          }
                          o.setValue(S, { value: z });
                        }),
                        P.addEventListener("resetform", (B) => {
                          const H = b.defaultFieldValue || "Off";
                          B.target.checked = H === b.exportValue;
                        }),
                        this.enableScripting &&
                          this.hasJSActions &&
                          (P.addEventListener("updatefromsandbox", (B) => {
                            const H = {
                              value(z) {
                                ((z.target.checked = z.detail.value !== "Off"),
                                  o.setValue(S, { value: z.target.checked }));
                              },
                            };
                            this._dispatchEventFromSandbox(H, B);
                          }),
                          this._setEventListeners(
                            P,
                            null,
                            [
                              ["change", "Validate"],
                              ["change", "Action"],
                              ["focus", "Focus"],
                              ["blur", "Blur"],
                              ["mousedown", "Mouse Down"],
                              ["mouseenter", "Mouse Enter"],
                              ["mouseleave", "Mouse Exit"],
                              ["mouseup", "Mouse Up"],
                            ],
                            (B) => B.target.checked,
                          )),
                        this._setBackgroundColor(P),
                        this._setDefaultPropertiesFromJS(P),
                        this.container.append(P),
                        this.container
                      );
                    }
                  }
                  class g extends l {
                    constructor(o) {
                      super(o, { isRenderable: o.renderForms });
                    }
                    render() {
                      this.container.classList.add(
                        "buttonWidgetAnnotation",
                        "radioButton",
                      );
                      const o = this.annotationStorage,
                        b = this.data,
                        S = b.id;
                      let x = o.getValue(S, {
                        value: b.fieldValue === b.buttonValue,
                      }).value;
                      typeof x == "string" &&
                        ((x = x !== b.buttonValue),
                        o.setValue(S, { value: x }));
                      const P = document.createElement("input");
                      if (
                        (i.add(P),
                        P.setAttribute("data-element-id", S),
                        (P.disabled = b.readOnly),
                        this._setRequired(P, this.data.required),
                        (P.type = "radio"),
                        (P.name = b.fieldName),
                        x && P.setAttribute("checked", !0),
                        (P.tabIndex = s),
                        P.addEventListener("change", (B) => {
                          const { name: H, checked: z } = B.target;
                          for (const st of this._getElementsByName(H, S))
                            o.setValue(st.id, { value: !1 });
                          o.setValue(S, { value: z });
                        }),
                        P.addEventListener("resetform", (B) => {
                          const H = b.defaultFieldValue;
                          B.target.checked = H != null && H === b.buttonValue;
                        }),
                        this.enableScripting && this.hasJSActions)
                      ) {
                        const B = b.buttonValue;
                        (P.addEventListener("updatefromsandbox", (H) => {
                          const z = {
                            value: (st) => {
                              const Y = B === st.detail.value;
                              for (const X of this._getElementsByName(
                                st.target.name,
                              )) {
                                const J = Y && X.id === S;
                                (X.domElement && (X.domElement.checked = J),
                                  o.setValue(X.id, { value: J }));
                              }
                            },
                          };
                          this._dispatchEventFromSandbox(z, H);
                        }),
                          this._setEventListeners(
                            P,
                            null,
                            [
                              ["change", "Validate"],
                              ["change", "Action"],
                              ["focus", "Focus"],
                              ["blur", "Blur"],
                              ["mousedown", "Mouse Down"],
                              ["mouseenter", "Mouse Enter"],
                              ["mouseleave", "Mouse Exit"],
                              ["mouseup", "Mouse Up"],
                            ],
                            (H) => H.target.checked,
                          ));
                      }
                      return (
                        this._setBackgroundColor(P),
                        this._setDefaultPropertiesFromJS(P),
                        this.container.append(P),
                        this.container
                      );
                    }
                  }
                  class E extends d {
                    constructor(o) {
                      super(o, { ignoreBorder: o.data.hasAppearance });
                    }
                    render() {
                      const o = super.render();
                      (o.classList.add("buttonWidgetAnnotation", "pushButton"),
                        this.data.alternativeText &&
                          (o.title = this.data.alternativeText));
                      const b = o.lastChild;
                      return (
                        this.enableScripting &&
                          this.hasJSActions &&
                          b &&
                          (this._setDefaultPropertiesFromJS(b),
                          b.addEventListener("updatefromsandbox", (S) => {
                            this._dispatchEventFromSandbox({}, S);
                          })),
                        o
                      );
                    }
                  }
                  class U extends l {
                    constructor(o) {
                      super(o, { isRenderable: o.renderForms });
                    }
                    render() {
                      this.container.classList.add("choiceWidgetAnnotation");
                      const o = this.annotationStorage,
                        b = this.data.id,
                        S = o.getValue(b, { value: this.data.fieldValue }),
                        x = document.createElement("select");
                      (i.add(x),
                        x.setAttribute("data-element-id", b),
                        (x.disabled = this.data.readOnly),
                        this._setRequired(x, this.data.required),
                        (x.name = this.data.fieldName),
                        (x.tabIndex = s));
                      let P = this.data.combo && this.data.options.length > 0;
                      (this.data.combo ||
                        ((x.size = this.data.options.length),
                        this.data.multiSelect && (x.multiple = !0)),
                        x.addEventListener("resetform", (Y) => {
                          const X = this.data.defaultFieldValue;
                          for (const J of x.options) J.selected = J.value === X;
                        }));
                      for (const Y of this.data.options) {
                        const X = document.createElement("option");
                        ((X.textContent = Y.displayValue),
                          (X.value = Y.exportValue),
                          S.value.includes(Y.exportValue) &&
                            (X.setAttribute("selected", !0), (P = !1)),
                          x.append(X));
                      }
                      let B = null;
                      if (P) {
                        const Y = document.createElement("option");
                        ((Y.value = " "),
                          Y.setAttribute("hidden", !0),
                          Y.setAttribute("selected", !0),
                          x.prepend(Y),
                          (B = () => {
                            (Y.remove(),
                              x.removeEventListener("input", B),
                              (B = null));
                          }),
                          x.addEventListener("input", B));
                      }
                      const H = (Y) => {
                        const X = Y ? "value" : "textContent",
                          { options: J, multiple: Q } = x;
                        return Q
                          ? Array.prototype.filter
                              .call(J, (et) => et.selected)
                              .map((et) => et[X])
                          : J.selectedIndex === -1
                            ? null
                            : J[J.selectedIndex][X];
                      };
                      let z = H(!1);
                      const st = (Y) => {
                        const X = Y.target.options;
                        return Array.prototype.map.call(X, (J) => ({
                          displayValue: J.textContent,
                          exportValue: J.value,
                        }));
                      };
                      return (
                        this.enableScripting && this.hasJSActions
                          ? (x.addEventListener("updatefromsandbox", (Y) => {
                              const X = {
                                value(J) {
                                  B?.();
                                  const Q = J.detail.value,
                                    et = new Set(Array.isArray(Q) ? Q : [Q]);
                                  for (const at of x.options)
                                    at.selected = et.has(at.value);
                                  (o.setValue(b, { value: H(!0) }),
                                    (z = H(!1)));
                                },
                                multipleSelection(J) {
                                  x.multiple = !0;
                                },
                                remove(J) {
                                  const Q = x.options,
                                    et = J.detail.remove;
                                  ((Q[et].selected = !1),
                                    x.remove(et),
                                    Q.length > 0 &&
                                      Array.prototype.findIndex.call(
                                        Q,
                                        (lt) => lt.selected,
                                      ) === -1 &&
                                      (Q[0].selected = !0),
                                    o.setValue(b, {
                                      value: H(!0),
                                      items: st(J),
                                    }),
                                    (z = H(!1)));
                                },
                                clear(J) {
                                  for (; x.length !== 0;) x.remove(0);
                                  (o.setValue(b, { value: null, items: [] }),
                                    (z = H(!1)));
                                },
                                insert(J) {
                                  const {
                                      index: Q,
                                      displayValue: et,
                                      exportValue: at,
                                    } = J.detail.insert,
                                    lt = x.children[Q],
                                    ct = document.createElement("option");
                                  ((ct.textContent = et),
                                    (ct.value = at),
                                    lt ? lt.before(ct) : x.append(ct),
                                    o.setValue(b, {
                                      value: H(!0),
                                      items: st(J),
                                    }),
                                    (z = H(!1)));
                                },
                                items(J) {
                                  const { items: Q } = J.detail;
                                  for (; x.length !== 0;) x.remove(0);
                                  for (const et of Q) {
                                    const {
                                        displayValue: at,
                                        exportValue: lt,
                                      } = et,
                                      ct = document.createElement("option");
                                    ((ct.textContent = at),
                                      (ct.value = lt),
                                      x.append(ct));
                                  }
                                  (x.options.length > 0 &&
                                    (x.options[0].selected = !0),
                                    o.setValue(b, {
                                      value: H(!0),
                                      items: st(J),
                                    }),
                                    (z = H(!1)));
                                },
                                indices(J) {
                                  const Q = new Set(J.detail.indices);
                                  for (const et of J.target.options)
                                    et.selected = Q.has(et.index);
                                  (o.setValue(b, { value: H(!0) }),
                                    (z = H(!1)));
                                },
                                editable(J) {
                                  J.target.disabled = !J.detail.editable;
                                },
                              };
                              this._dispatchEventFromSandbox(X, Y);
                            }),
                            x.addEventListener("input", (Y) => {
                              const X = H(!0);
                              (o.setValue(b, { value: X }),
                                Y.preventDefault(),
                                this.linkService.eventBus?.dispatch(
                                  "dispatcheventinsandbox",
                                  {
                                    source: this,
                                    detail: {
                                      id: b,
                                      name: "Keystroke",
                                      value: z,
                                      changeEx: X,
                                      willCommit: !1,
                                      commitKey: 1,
                                      keyDown: !1,
                                    },
                                  },
                                ));
                            }),
                            this._setEventListeners(
                              x,
                              null,
                              [
                                ["focus", "Focus"],
                                ["blur", "Blur"],
                                ["mousedown", "Mouse Down"],
                                ["mouseenter", "Mouse Enter"],
                                ["mouseleave", "Mouse Exit"],
                                ["mouseup", "Mouse Up"],
                                ["input", "Action"],
                                ["input", "Validate"],
                              ],
                              (Y) => Y.target.value,
                            ))
                          : x.addEventListener("input", function (Y) {
                              o.setValue(b, { value: H(!0) });
                            }),
                        this.data.combo && this._setTextStyle(x),
                        this._setBackgroundColor(x),
                        this._setDefaultPropertiesFromJS(x),
                        this.container.append(x),
                        this.container
                      );
                    }
                  }
                  class W extends n {
                    constructor(o) {
                      const { data: b, elements: S } = o;
                      (super(o, { isRenderable: n._hasPopupData(b) }),
                        (this.elements = S));
                    }
                    render() {
                      this.container.classList.add("popupAnnotation");
                      const o = new O({
                          container: this.container,
                          color: this.data.color,
                          titleObj: this.data.titleObj,
                          modificationDate: this.data.modificationDate,
                          contentsObj: this.data.contentsObj,
                          richText: this.data.richText,
                          rect: this.data.rect,
                          parentRect: this.data.parentRect || null,
                          parent: this.parent,
                          elements: this.elements,
                          open: this.data.open,
                        }),
                        b = [];
                      for (const S of this.elements)
                        ((S.popup = o),
                          b.push(S.data.id),
                          S.addHighlightArea());
                      return (
                        this.container.setAttribute(
                          "aria-controls",
                          b.map((S) => `${a.AnnotationPrefix}${S}`).join(","),
                        ),
                        this.container
                      );
                    }
                  }
                  class O {
                    #t = null;
                    #e = this.#h.bind(this);
                    #n = this.#S.bind(this);
                    #i = this.#E.bind(this);
                    #o = this.#_.bind(this);
                    #a = null;
                    #r = null;
                    #l = null;
                    #c = null;
                    #s = null;
                    #f = null;
                    #d = !1;
                    #u = null;
                    #p = null;
                    #b = null;
                    #m = null;
                    #g = !1;
                    constructor({
                      container: o,
                      color: b,
                      elements: S,
                      titleObj: x,
                      modificationDate: P,
                      contentsObj: B,
                      richText: H,
                      parent: z,
                      rect: st,
                      parentRect: Y,
                      open: X,
                    }) {
                      ((this.#r = o),
                        (this.#m = x),
                        (this.#l = B),
                        (this.#b = H),
                        (this.#s = z),
                        (this.#a = b),
                        (this.#p = st),
                        (this.#f = Y),
                        (this.#c = S));
                      const J = p.PDFDateString.toDateObject(P);
                      (J &&
                        (this.#t = z.l10n.get("annotation_date_string", {
                          date: J.toLocaleDateString(),
                          time: J.toLocaleTimeString(),
                        })),
                        (this.trigger = S.flatMap((Q) =>
                          Q.getElementsToTriggerPopup(),
                        )));
                      for (const Q of this.trigger)
                        (Q.addEventListener("click", this.#o),
                          Q.addEventListener("mouseenter", this.#i),
                          Q.addEventListener("mouseleave", this.#n),
                          Q.classList.add("popupTriggerArea"));
                      for (const Q of S)
                        Q.container?.addEventListener("keydown", this.#e);
                      ((this.#r.hidden = !0), X && this.#_());
                    }
                    render() {
                      if (this.#u) return;
                      const {
                          page: { view: o },
                          viewport: {
                            rawDims: {
                              pageWidth: b,
                              pageHeight: S,
                              pageX: x,
                              pageY: P,
                            },
                          },
                        } = this.#s,
                        B = (this.#u = document.createElement("div"));
                      if (((B.className = "popup"), this.#a)) {
                        const dt = (B.style.outlineColor = a.Util.makeHexColor(
                          ...this.#a,
                        ));
                        CSS.supports(
                          "background-color",
                          "color-mix(in srgb, red 30%, white)",
                        )
                          ? (B.style.backgroundColor = `color-mix(in srgb, ${dt} 30%, white)`)
                          : (B.style.backgroundColor = a.Util.makeHexColor(
                              ...this.#a.map((At) =>
                                Math.floor(0.7 * (255 - At) + At),
                              ),
                            ));
                      }
                      const H = document.createElement("span");
                      H.className = "header";
                      const z = document.createElement("h1");
                      if (
                        (H.append(z),
                        ({ dir: z.dir, str: z.textContent } = this.#m),
                        B.append(H),
                        this.#t)
                      ) {
                        const dt = document.createElement("span");
                        (dt.classList.add("popupDate"),
                          this.#t.then((ut) => {
                            dt.textContent = ut;
                          }),
                          H.append(dt));
                      }
                      const st = this.#l,
                        Y = this.#b;
                      if (Y?.str && (!st?.str || st.str === Y.str))
                        (D.XfaLayer.render({
                          xfaHtml: Y.html,
                          intent: "richText",
                          div: B,
                        }),
                          B.lastChild.classList.add(
                            "richText",
                            "popupContent",
                          ));
                      else {
                        const dt = this._formatContents(st);
                        B.append(dt);
                      }
                      let X = !!this.#f,
                        J = X ? this.#f : this.#p;
                      for (const dt of this.#c)
                        if (!J || a.Util.intersect(dt.data.rect, J) !== null) {
                          ((J = dt.data.rect), (X = !0));
                          break;
                        }
                      const Q = a.Util.normalizeRect([
                          J[0],
                          o[3] - J[1] + o[1],
                          J[2],
                          o[3] - J[3] + o[1],
                        ]),
                        at = X ? J[2] - J[0] + 5 : 0,
                        lt = Q[0] + at,
                        ct = Q[1],
                        { style: ht } = this.#r;
                      ((ht.left = `${(100 * (lt - x)) / b}%`),
                        (ht.top = `${(100 * (ct - P)) / S}%`),
                        this.#r.append(B));
                    }
                    _formatContents({ str: o, dir: b }) {
                      const S = document.createElement("p");
                      (S.classList.add("popupContent"), (S.dir = b));
                      const x = o.split(/(?:\r\n?|\n)/);
                      for (let P = 0, B = x.length; P < B; ++P) {
                        const H = x[P];
                        (S.append(document.createTextNode(H)),
                          P < B - 1 && S.append(document.createElement("br")));
                      }
                      return S;
                    }
                    #h(o) {
                      o.altKey ||
                        o.shiftKey ||
                        o.ctrlKey ||
                        o.metaKey ||
                        ((o.key === "Enter" ||
                          (o.key === "Escape" && this.#d)) &&
                          this.#_());
                    }
                    #_() {
                      ((this.#d = !this.#d),
                        this.#d
                          ? (this.#E(),
                            this.#r.addEventListener("click", this.#o),
                            this.#r.addEventListener("keydown", this.#e))
                          : (this.#S(),
                            this.#r.removeEventListener("click", this.#o),
                            this.#r.removeEventListener("keydown", this.#e)));
                    }
                    #E() {
                      (this.#u || this.render(),
                        this.isVisible
                          ? this.#d && this.#r.classList.add("focused")
                          : ((this.#r.hidden = !1),
                            (this.#r.style.zIndex =
                              parseInt(this.#r.style.zIndex) + 1e3)));
                    }
                    #S() {
                      (this.#r.classList.remove("focused"),
                        !(this.#d || !this.isVisible) &&
                          ((this.#r.hidden = !0),
                          (this.#r.style.zIndex =
                            parseInt(this.#r.style.zIndex) - 1e3)));
                    }
                    forceHide() {
                      ((this.#g = this.isVisible),
                        this.#g && (this.#r.hidden = !0));
                    }
                    maybeShow() {
                      this.#g && ((this.#g = !1), (this.#r.hidden = !1));
                    }
                    get isVisible() {
                      return this.#r.hidden === !1;
                    }
                  }
                  class V extends n {
                    constructor(o) {
                      (super(o, { isRenderable: !0, ignoreBorder: !0 }),
                        (this.textContent = o.data.textContent),
                        (this.textPosition = o.data.textPosition),
                        (this.annotationEditorType =
                          a.AnnotationEditorType.FREETEXT));
                    }
                    render() {
                      if (
                        (this.container.classList.add("freeTextAnnotation"),
                        this.textContent)
                      ) {
                        const o = document.createElement("div");
                        (o.classList.add("annotationTextContent"),
                          o.setAttribute("role", "comment"));
                        for (const b of this.textContent) {
                          const S = document.createElement("span");
                          ((S.textContent = b), o.append(S));
                        }
                        this.container.append(o);
                      }
                      return (
                        !this.data.popupRef &&
                          this.hasPopupData &&
                          this._createPopup(),
                        this._editOnDoubleClick(),
                        this.container
                      );
                    }
                  }
                  e.FreeTextAnnotationElement = V;
                  class G extends n {
                    #t = null;
                    constructor(o) {
                      super(o, { isRenderable: !0, ignoreBorder: !0 });
                    }
                    render() {
                      this.container.classList.add("lineAnnotation");
                      const o = this.data,
                        { width: b, height: S } = h(o.rect),
                        x = this.svgFactory.create(b, S, !0),
                        P = (this.#t =
                          this.svgFactory.createElement("svg:line"));
                      return (
                        P.setAttribute("x1", o.rect[2] - o.lineCoordinates[0]),
                        P.setAttribute("y1", o.rect[3] - o.lineCoordinates[1]),
                        P.setAttribute("x2", o.rect[2] - o.lineCoordinates[2]),
                        P.setAttribute("y2", o.rect[3] - o.lineCoordinates[3]),
                        P.setAttribute(
                          "stroke-width",
                          o.borderStyle.width || 1,
                        ),
                        P.setAttribute("stroke", "transparent"),
                        P.setAttribute("fill", "transparent"),
                        x.append(P),
                        this.container.append(x),
                        !o.popupRef && this.hasPopupData && this._createPopup(),
                        this.container
                      );
                    }
                    getElementsToTriggerPopup() {
                      return this.#t;
                    }
                    addHighlightArea() {
                      this.container.classList.add("highlightArea");
                    }
                  }
                  class nt extends n {
                    #t = null;
                    constructor(o) {
                      super(o, { isRenderable: !0, ignoreBorder: !0 });
                    }
                    render() {
                      this.container.classList.add("squareAnnotation");
                      const o = this.data,
                        { width: b, height: S } = h(o.rect),
                        x = this.svgFactory.create(b, S, !0),
                        P = o.borderStyle.width,
                        B = (this.#t =
                          this.svgFactory.createElement("svg:rect"));
                      return (
                        B.setAttribute("x", P / 2),
                        B.setAttribute("y", P / 2),
                        B.setAttribute("width", b - P),
                        B.setAttribute("height", S - P),
                        B.setAttribute("stroke-width", P || 1),
                        B.setAttribute("stroke", "transparent"),
                        B.setAttribute("fill", "transparent"),
                        x.append(B),
                        this.container.append(x),
                        !o.popupRef && this.hasPopupData && this._createPopup(),
                        this.container
                      );
                    }
                    getElementsToTriggerPopup() {
                      return this.#t;
                    }
                    addHighlightArea() {
                      this.container.classList.add("highlightArea");
                    }
                  }
                  class Z extends n {
                    #t = null;
                    constructor(o) {
                      super(o, { isRenderable: !0, ignoreBorder: !0 });
                    }
                    render() {
                      this.container.classList.add("circleAnnotation");
                      const o = this.data,
                        { width: b, height: S } = h(o.rect),
                        x = this.svgFactory.create(b, S, !0),
                        P = o.borderStyle.width,
                        B = (this.#t =
                          this.svgFactory.createElement("svg:ellipse"));
                      return (
                        B.setAttribute("cx", b / 2),
                        B.setAttribute("cy", S / 2),
                        B.setAttribute("rx", b / 2 - P / 2),
                        B.setAttribute("ry", S / 2 - P / 2),
                        B.setAttribute("stroke-width", P || 1),
                        B.setAttribute("stroke", "transparent"),
                        B.setAttribute("fill", "transparent"),
                        x.append(B),
                        this.container.append(x),
                        !o.popupRef && this.hasPopupData && this._createPopup(),
                        this.container
                      );
                    }
                    getElementsToTriggerPopup() {
                      return this.#t;
                    }
                    addHighlightArea() {
                      this.container.classList.add("highlightArea");
                    }
                  }
                  class tt extends n {
                    #t = null;
                    constructor(o) {
                      (super(o, { isRenderable: !0, ignoreBorder: !0 }),
                        (this.containerClassName = "polylineAnnotation"),
                        (this.svgElementName = "svg:polyline"));
                    }
                    render() {
                      this.container.classList.add(this.containerClassName);
                      const o = this.data,
                        { width: b, height: S } = h(o.rect),
                        x = this.svgFactory.create(b, S, !0);
                      let P = [];
                      for (const H of o.vertices) {
                        const z = H.x - o.rect[0],
                          st = o.rect[3] - H.y;
                        P.push(z + "," + st);
                      }
                      P = P.join(" ");
                      const B = (this.#t = this.svgFactory.createElement(
                        this.svgElementName,
                      ));
                      return (
                        B.setAttribute("points", P),
                        B.setAttribute(
                          "stroke-width",
                          o.borderStyle.width || 1,
                        ),
                        B.setAttribute("stroke", "transparent"),
                        B.setAttribute("fill", "transparent"),
                        x.append(B),
                        this.container.append(x),
                        !o.popupRef && this.hasPopupData && this._createPopup(),
                        this.container
                      );
                    }
                    getElementsToTriggerPopup() {
                      return this.#t;
                    }
                    addHighlightArea() {
                      this.container.classList.add("highlightArea");
                    }
                  }
                  class rt extends tt {
                    constructor(o) {
                      (super(o),
                        (this.containerClassName = "polygonAnnotation"),
                        (this.svgElementName = "svg:polygon"));
                    }
                  }
                  class K extends n {
                    constructor(o) {
                      super(o, { isRenderable: !0, ignoreBorder: !0 });
                    }
                    render() {
                      return (
                        this.container.classList.add("caretAnnotation"),
                        !this.data.popupRef &&
                          this.hasPopupData &&
                          this._createPopup(),
                        this.container
                      );
                    }
                  }
                  class I extends n {
                    #t = [];
                    constructor(o) {
                      (super(o, { isRenderable: !0, ignoreBorder: !0 }),
                        (this.containerClassName = "inkAnnotation"),
                        (this.svgElementName = "svg:polyline"),
                        (this.annotationEditorType =
                          a.AnnotationEditorType.INK));
                    }
                    render() {
                      this.container.classList.add(this.containerClassName);
                      const o = this.data,
                        { width: b, height: S } = h(o.rect),
                        x = this.svgFactory.create(b, S, !0);
                      for (const P of o.inkLists) {
                        let B = [];
                        for (const z of P) {
                          const st = z.x - o.rect[0],
                            Y = o.rect[3] - z.y;
                          B.push(`${st},${Y}`);
                        }
                        B = B.join(" ");
                        const H = this.svgFactory.createElement(
                          this.svgElementName,
                        );
                        (this.#t.push(H),
                          H.setAttribute("points", B),
                          H.setAttribute(
                            "stroke-width",
                            o.borderStyle.width || 1,
                          ),
                          H.setAttribute("stroke", "transparent"),
                          H.setAttribute("fill", "transparent"),
                          !o.popupRef &&
                            this.hasPopupData &&
                            this._createPopup(),
                          x.append(H));
                      }
                      return (this.container.append(x), this.container);
                    }
                    getElementsToTriggerPopup() {
                      return this.#t;
                    }
                    addHighlightArea() {
                      this.container.classList.add("highlightArea");
                    }
                  }
                  e.InkAnnotationElement = I;
                  class _ extends n {
                    constructor(o) {
                      super(o, {
                        isRenderable: !0,
                        ignoreBorder: !0,
                        createQuadrilaterals: !0,
                      });
                    }
                    render() {
                      return (
                        !this.data.popupRef &&
                          this.hasPopupData &&
                          this._createPopup(),
                        this.container.classList.add("highlightAnnotation"),
                        this.container
                      );
                    }
                  }
                  class u extends n {
                    constructor(o) {
                      super(o, {
                        isRenderable: !0,
                        ignoreBorder: !0,
                        createQuadrilaterals: !0,
                      });
                    }
                    render() {
                      return (
                        !this.data.popupRef &&
                          this.hasPopupData &&
                          this._createPopup(),
                        this.container.classList.add("underlineAnnotation"),
                        this.container
                      );
                    }
                  }
                  class f extends n {
                    constructor(o) {
                      super(o, {
                        isRenderable: !0,
                        ignoreBorder: !0,
                        createQuadrilaterals: !0,
                      });
                    }
                    render() {
                      return (
                        !this.data.popupRef &&
                          this.hasPopupData &&
                          this._createPopup(),
                        this.container.classList.add("squigglyAnnotation"),
                        this.container
                      );
                    }
                  }
                  class v extends n {
                    constructor(o) {
                      super(o, {
                        isRenderable: !0,
                        ignoreBorder: !0,
                        createQuadrilaterals: !0,
                      });
                    }
                    render() {
                      return (
                        !this.data.popupRef &&
                          this.hasPopupData &&
                          this._createPopup(),
                        this.container.classList.add("strikeoutAnnotation"),
                        this.container
                      );
                    }
                  }
                  class F extends n {
                    constructor(o) {
                      super(o, { isRenderable: !0, ignoreBorder: !0 });
                    }
                    render() {
                      return (
                        this.container.classList.add("stampAnnotation"),
                        !this.data.popupRef &&
                          this.hasPopupData &&
                          this._createPopup(),
                        this.container
                      );
                    }
                  }
                  e.StampAnnotationElement = F;
                  class L extends n {
                    #t = null;
                    constructor(o) {
                      super(o, { isRenderable: !0 });
                      const { filename: b, content: S } = this.data.file;
                      ((this.filename = (0, p.getFilenameFromUrl)(b, !0)),
                        (this.content = S),
                        this.linkService.eventBus?.dispatch(
                          "fileattachmentannotation",
                          { source: this, filename: b, content: S },
                        ));
                    }
                    render() {
                      this.container.classList.add("fileAttachmentAnnotation");
                      const { container: o, data: b } = this;
                      let S;
                      (b.hasAppearance || b.fillAlpha === 0
                        ? (S = document.createElement("div"))
                        : ((S = document.createElement("img")),
                          (S.src = `${this.imageResourcesPath}annotation-${/paperclip/i.test(b.name) ? "paperclip" : "pushpin"}.svg`),
                          b.fillAlpha &&
                            b.fillAlpha < 1 &&
                            (S.style = `filter: opacity(${Math.round(b.fillAlpha * 100)}%);`)),
                        S.addEventListener("dblclick", this.#e.bind(this)),
                        (this.#t = S));
                      const { isMac: x } = a.FeatureTest.platform;
                      return (
                        o.addEventListener("keydown", (P) => {
                          P.key === "Enter" &&
                            (x ? P.metaKey : P.ctrlKey) &&
                            this.#e();
                        }),
                        !b.popupRef && this.hasPopupData
                          ? this._createPopup()
                          : S.classList.add("popupTriggerArea"),
                        o.append(S),
                        o
                      );
                    }
                    getElementsToTriggerPopup() {
                      return this.#t;
                    }
                    addHighlightArea() {
                      this.container.classList.add("highlightArea");
                    }
                    #e() {
                      this.downloadManager?.openOrDownloadData(
                        this.container,
                        this.content,
                        this.filename,
                      );
                    }
                  }
                  class N {
                    #t = null;
                    #e = null;
                    #n = new Map();
                    constructor({
                      div: o,
                      accessibilityManager: b,
                      annotationCanvasMap: S,
                      l10n: x,
                      page: P,
                      viewport: B,
                    }) {
                      ((this.div = o),
                        (this.#t = b),
                        (this.#e = S),
                        (this.l10n = x),
                        (this.page = P),
                        (this.viewport = B),
                        (this.zIndex = 0),
                        (this.l10n ||= j.NullL10n));
                    }
                    #i(o, b) {
                      const S = o.firstChild || o;
                      ((S.id = `${a.AnnotationPrefix}${b}`),
                        this.div.append(o),
                        this.#t?.moveElementInDOM(this.div, o, S, !1));
                    }
                    async render(o) {
                      const { annotations: b } = o,
                        S = this.div;
                      (0, p.setLayerDimensions)(S, this.viewport);
                      const x = new Map(),
                        P = {
                          data: null,
                          layer: S,
                          linkService: o.linkService,
                          downloadManager: o.downloadManager,
                          imageResourcesPath: o.imageResourcesPath || "",
                          renderForms: o.renderForms !== !1,
                          svgFactory: new p.DOMSVGFactory(),
                          annotationStorage:
                            o.annotationStorage || new k.AnnotationStorage(),
                          enableScripting: o.enableScripting === !0,
                          hasJSActions: o.hasJSActions,
                          fieldObjects: o.fieldObjects,
                          parent: this,
                          elements: null,
                        };
                      for (const B of b) {
                        if (B.noHTML) continue;
                        const H = B.annotationType === a.AnnotationType.POPUP;
                        if (H) {
                          const Y = x.get(B.id);
                          if (!Y) continue;
                          P.elements = Y;
                        } else {
                          const { width: Y, height: X } = h(B.rect);
                          if (Y <= 0 || X <= 0) continue;
                        }
                        P.data = B;
                        const z = c.create(P);
                        if (!z.isRenderable) continue;
                        if (!H && B.popupRef) {
                          const Y = x.get(B.popupRef);
                          Y ? Y.push(z) : x.set(B.popupRef, [z]);
                        }
                        z.annotationEditorType > 0 && this.#n.set(z.data.id, z);
                        const st = z.render();
                        (B.hidden && (st.style.visibility = "hidden"),
                          this.#i(st, B.id));
                      }
                      (this.#o(), await this.l10n.translate(S));
                    }
                    update({ viewport: o }) {
                      const b = this.div;
                      ((this.viewport = o),
                        (0, p.setLayerDimensions)(b, { rotation: o.rotation }),
                        this.#o(),
                        (b.hidden = !1));
                    }
                    #o() {
                      if (!this.#e) return;
                      const o = this.div;
                      for (const [b, S] of this.#e) {
                        const x = o.querySelector(
                          `[data-annotation-id="${b}"]`,
                        );
                        if (!x) continue;
                        const { firstChild: P } = x;
                        P
                          ? P.nodeName === "CANVAS"
                            ? P.replaceWith(S)
                            : P.before(S)
                          : x.append(S);
                      }
                      this.#e.clear();
                    }
                    getEditableAnnotations() {
                      return Array.from(this.#n.values());
                    }
                    getEditableAnnotation(o) {
                      return this.#n.get(o);
                    }
                  }
                  e.AnnotationLayer = N;
                },
                (A, e) => {
                  (Object.defineProperty(e, "__esModule", { value: !0 }),
                    (e.ColorConverters = void 0));
                  function y(k) {
                    return Math.floor(Math.max(0, Math.min(1, k)) * 255)
                      .toString(16)
                      .padStart(2, "0");
                  }
                  function a(k) {
                    return Math.max(0, Math.min(255, 255 * k));
                  }
                  class p {
                    static CMYK_G([T, j, D, s]) {
                      return [
                        "G",
                        1 - Math.min(1, 0.3 * T + 0.59 * D + 0.11 * j + s),
                      ];
                    }
                    static G_CMYK([T]) {
                      return ["CMYK", 0, 0, 0, 1 - T];
                    }
                    static G_RGB([T]) {
                      return ["RGB", T, T, T];
                    }
                    static G_rgb([T]) {
                      return ((T = a(T)), [T, T, T]);
                    }
                    static G_HTML([T]) {
                      const j = y(T);
                      return `#${j}${j}${j}`;
                    }
                    static RGB_G([T, j, D]) {
                      return ["G", 0.3 * T + 0.59 * j + 0.11 * D];
                    }
                    static RGB_rgb(T) {
                      return T.map(a);
                    }
                    static RGB_HTML(T) {
                      return `#${T.map(y).join("")}`;
                    }
                    static T_HTML() {
                      return "#00000000";
                    }
                    static T_rgb() {
                      return [null];
                    }
                    static CMYK_RGB([T, j, D, s]) {
                      return [
                        "RGB",
                        1 - Math.min(1, T + s),
                        1 - Math.min(1, D + s),
                        1 - Math.min(1, j + s),
                      ];
                    }
                    static CMYK_rgb([T, j, D, s]) {
                      return [
                        a(1 - Math.min(1, T + s)),
                        a(1 - Math.min(1, D + s)),
                        a(1 - Math.min(1, j + s)),
                      ];
                    }
                    static CMYK_HTML(T) {
                      const j = this.CMYK_RGB(T).slice(1);
                      return this.RGB_HTML(j);
                    }
                    static RGB_CMYK([T, j, D]) {
                      const s = 1 - T,
                        t = 1 - j,
                        i = 1 - D,
                        h = Math.min(s, t, i);
                      return ["CMYK", s, t, i, h];
                    }
                  }
                  e.ColorConverters = p;
                },
                (A, e) => {
                  (Object.defineProperty(e, "__esModule", { value: !0 }),
                    (e.NullL10n = void 0),
                    (e.getL10nFallback = a));
                  const y = {
                    of_pages: "of {{pagesCount}}",
                    page_of_pages: "({{pageNumber}} of {{pagesCount}})",
                    document_properties_kb: "{{size_kb}} KB ({{size_b}} bytes)",
                    document_properties_mb: "{{size_mb}} MB ({{size_b}} bytes)",
                    document_properties_date_string: "{{date}}, {{time}}",
                    document_properties_page_size_unit_inches: "in",
                    document_properties_page_size_unit_millimeters: "mm",
                    document_properties_page_size_orientation_portrait:
                      "portrait",
                    document_properties_page_size_orientation_landscape:
                      "landscape",
                    document_properties_page_size_name_a3: "A3",
                    document_properties_page_size_name_a4: "A4",
                    document_properties_page_size_name_letter: "Letter",
                    document_properties_page_size_name_legal: "Legal",
                    document_properties_page_size_dimension_string:
                      "{{width}} × {{height}} {{unit}} ({{orientation}})",
                    document_properties_page_size_dimension_name_string:
                      "{{width}} × {{height}} {{unit}} ({{name}}, {{orientation}})",
                    document_properties_linearized_yes: "Yes",
                    document_properties_linearized_no: "No",
                    additional_layers: "Additional Layers",
                    page_landmark: "Page {{page}}",
                    thumb_page_title: "Page {{page}}",
                    thumb_page_canvas: "Thumbnail of Page {{page}}",
                    find_reached_top:
                      "Reached top of document, continued from bottom",
                    find_reached_bottom:
                      "Reached end of document, continued from top",
                    "find_match_count[one]": "{{current}} of {{total}} match",
                    "find_match_count[other]":
                      "{{current}} of {{total}} matches",
                    "find_match_count_limit[one]": "More than {{limit}} match",
                    "find_match_count_limit[other]":
                      "More than {{limit}} matches",
                    find_not_found: "Phrase not found",
                    page_scale_width: "Page Width",
                    page_scale_fit: "Page Fit",
                    page_scale_auto: "Automatic Zoom",
                    page_scale_actual: "Actual Size",
                    page_scale_percent: "{{scale}}%",
                    loading_error: "An error occurred while loading the PDF.",
                    invalid_file_error: "Invalid or corrupted PDF file.",
                    missing_file_error: "Missing PDF file.",
                    unexpected_response_error: "Unexpected server response.",
                    rendering_error:
                      "An error occurred while rendering the page.",
                    annotation_date_string: "{{date}}, {{time}}",
                    printing_not_supported:
                      "Warning: Printing is not fully supported by this browser.",
                    printing_not_ready:
                      "Warning: The PDF is not fully loaded for printing.",
                    web_fonts_disabled:
                      "Web fonts are disabled: unable to use embedded PDF fonts.",
                    free_text2_default_content: "Start typing…",
                    editor_free_text2_aria_label: "Text Editor",
                    editor_ink2_aria_label: "Draw Editor",
                    editor_ink_canvas_aria_label: "User-created image",
                    editor_alt_text_button_label: "Alt text",
                    editor_alt_text_edit_button_label: "Edit alt text",
                    editor_alt_text_decorative_tooltip: "Marked as decorative",
                  };
                  y.print_progress_percent = "{{progress}}%";
                  function a(T, j) {
                    switch (T) {
                      case "find_match_count":
                        T = `find_match_count[${j.total === 1 ? "one" : "other"}]`;
                        break;
                      case "find_match_count_limit":
                        T = `find_match_count_limit[${j.limit === 1 ? "one" : "other"}]`;
                        break;
                    }
                    return y[T] || "";
                  }
                  function p(T, j) {
                    return j
                      ? T.replaceAll(/\{\{\s*(\w+)\s*\}\}/g, (D, s) =>
                          s in j ? j[s] : "{{" + s + "}}",
                        )
                      : T;
                  }
                  const k = {
                    async getLanguage() {
                      return "en-us";
                    },
                    async getDirection() {
                      return "ltr";
                    },
                    async get(T, j = null, D = a(T, j)) {
                      return p(D, j);
                    },
                    async translate(T) {},
                  };
                  e.NullL10n = k;
                },
                (A, e, y) => {
                  (Object.defineProperty(e, "__esModule", { value: !0 }),
                    (e.XfaLayer = void 0));
                  var a = y(25);
                  class p {
                    static setupStorage(T, j, D, s, t) {
                      const i = s.getValue(j, { value: null });
                      switch (D.name) {
                        case "textarea":
                          if (
                            (i.value !== null && (T.textContent = i.value),
                            t === "print")
                          )
                            break;
                          T.addEventListener("input", (h) => {
                            s.setValue(j, { value: h.target.value });
                          });
                          break;
                        case "input":
                          if (
                            D.attributes.type === "radio" ||
                            D.attributes.type === "checkbox"
                          ) {
                            if (
                              (i.value === D.attributes.xfaOn
                                ? T.setAttribute("checked", !0)
                                : i.value === D.attributes.xfaOff &&
                                  T.removeAttribute("checked"),
                              t === "print")
                            )
                              break;
                            T.addEventListener("change", (h) => {
                              s.setValue(j, {
                                value: h.target.checked
                                  ? h.target.getAttribute("xfaOn")
                                  : h.target.getAttribute("xfaOff"),
                              });
                            });
                          } else {
                            if (
                              (i.value !== null &&
                                T.setAttribute("value", i.value),
                              t === "print")
                            )
                              break;
                            T.addEventListener("input", (h) => {
                              s.setValue(j, { value: h.target.value });
                            });
                          }
                          break;
                        case "select":
                          if (i.value !== null) {
                            T.setAttribute("value", i.value);
                            for (const h of D.children)
                              h.attributes.value === i.value
                                ? (h.attributes.selected = !0)
                                : h.attributes.hasOwnProperty("selected") &&
                                  delete h.attributes.selected;
                          }
                          T.addEventListener("input", (h) => {
                            const c = h.target.options,
                              n =
                                c.selectedIndex === -1
                                  ? ""
                                  : c[c.selectedIndex].value;
                            s.setValue(j, { value: n });
                          });
                          break;
                      }
                    }
                    static setAttributes({
                      html: T,
                      element: j,
                      storage: D = null,
                      intent: s,
                      linkService: t,
                    }) {
                      const { attributes: i } = j,
                        h = T instanceof HTMLAnchorElement;
                      i.type === "radio" && (i.name = `${i.name}-${s}`);
                      for (const [c, n] of Object.entries(i))
                        if (n != null)
                          switch (c) {
                            case "class":
                              n.length && T.setAttribute(c, n.join(" "));
                              break;
                            case "dataId":
                              break;
                            case "id":
                              T.setAttribute("data-element-id", n);
                              break;
                            case "style":
                              Object.assign(T.style, n);
                              break;
                            case "textContent":
                              T.textContent = n;
                              break;
                            default:
                              (!h || (c !== "href" && c !== "newWindow")) &&
                                T.setAttribute(c, n);
                          }
                      (h && t.addLinkAttributes(T, i.href, i.newWindow),
                        D && i.dataId && this.setupStorage(T, i.dataId, j, D));
                    }
                    static render(T) {
                      const j = T.annotationStorage,
                        D = T.linkService,
                        s = T.xfaHtml,
                        t = T.intent || "display",
                        i = document.createElement(s.name);
                      s.attributes &&
                        this.setAttributes({
                          html: i,
                          element: s,
                          intent: t,
                          linkService: D,
                        });
                      const h = [[s, -1, i]],
                        c = T.div;
                      if ((c.append(i), T.viewport)) {
                        const d = `matrix(${T.viewport.transform.join(",")})`;
                        c.style.transform = d;
                      }
                      t !== "richText" &&
                        c.setAttribute("class", "xfaLayer xfaFont");
                      const n = [];
                      for (; h.length > 0;) {
                        const [d, m, l] = h.at(-1);
                        if (m + 1 === d.children.length) {
                          h.pop();
                          continue;
                        }
                        const w = d.children[++h.at(-1)[1]];
                        if (w === null) continue;
                        const { name: M } = w;
                        if (M === "#text") {
                          const g = document.createTextNode(w.value);
                          (n.push(g), l.append(g));
                          continue;
                        }
                        const C = w?.attributes?.xmlns
                          ? document.createElementNS(w.attributes.xmlns, M)
                          : document.createElement(M);
                        if (
                          (l.append(C),
                          w.attributes &&
                            this.setAttributes({
                              html: C,
                              element: w,
                              storage: j,
                              intent: t,
                              linkService: D,
                            }),
                          w.children && w.children.length > 0)
                        )
                          h.push([w, -1, C]);
                        else if (w.value) {
                          const g = document.createTextNode(w.value);
                          (a.XfaText.shouldBuildText(M) && n.push(g),
                            C.append(g));
                        }
                      }
                      for (const d of c.querySelectorAll(
                        ".xfaNonInteractive input, .xfaNonInteractive textarea",
                      ))
                        d.setAttribute("readOnly", !0);
                      return { textDivs: n };
                    }
                    static update(T) {
                      const j = `matrix(${T.viewport.transform.join(",")})`;
                      ((T.div.style.transform = j), (T.div.hidden = !1));
                    }
                  }
                  e.XfaLayer = p;
                },
                (A, e, y) => {
                  (Object.defineProperty(e, "__esModule", { value: !0 }),
                    (e.InkEditor = void 0));
                  var a = y(1),
                    p = y(4),
                    k = y(29),
                    T = y(6),
                    j = y(5);
                  class D extends p.AnnotationEditor {
                    #t = 0;
                    #e = 0;
                    #n = this.canvasPointermove.bind(this);
                    #i = this.canvasPointerleave.bind(this);
                    #o = this.canvasPointerup.bind(this);
                    #a = this.canvasPointerdown.bind(this);
                    #r = new Path2D();
                    #l = !1;
                    #c = !1;
                    #s = !1;
                    #f = null;
                    #d = 0;
                    #u = 0;
                    #p = null;
                    static _defaultColor = null;
                    static _defaultOpacity = 1;
                    static _defaultThickness = 1;
                    static _type = "ink";
                    constructor(t) {
                      (super({ ...t, name: "inkEditor" }),
                        (this.color = t.color || null),
                        (this.thickness = t.thickness || null),
                        (this.opacity = t.opacity || null),
                        (this.paths = []),
                        (this.bezierPath2D = []),
                        (this.allRawPaths = []),
                        (this.currentPath = []),
                        (this.scaleFactor = 1),
                        (this.translationX = this.translationY = 0),
                        (this.x = 0),
                        (this.y = 0),
                        (this._willKeepAspectRatio = !0));
                    }
                    static initialize(t) {
                      p.AnnotationEditor.initialize(t, {
                        strings: [
                          "editor_ink_canvas_aria_label",
                          "editor_ink2_aria_label",
                        ],
                      });
                    }
                    static updateDefaultParams(t, i) {
                      switch (t) {
                        case a.AnnotationEditorParamsType.INK_THICKNESS:
                          D._defaultThickness = i;
                          break;
                        case a.AnnotationEditorParamsType.INK_COLOR:
                          D._defaultColor = i;
                          break;
                        case a.AnnotationEditorParamsType.INK_OPACITY:
                          D._defaultOpacity = i / 100;
                          break;
                      }
                    }
                    updateParams(t, i) {
                      switch (t) {
                        case a.AnnotationEditorParamsType.INK_THICKNESS:
                          this.#b(i);
                          break;
                        case a.AnnotationEditorParamsType.INK_COLOR:
                          this.#m(i);
                          break;
                        case a.AnnotationEditorParamsType.INK_OPACITY:
                          this.#g(i);
                          break;
                      }
                    }
                    static get defaultPropertiesToUpdate() {
                      return [
                        [
                          a.AnnotationEditorParamsType.INK_THICKNESS,
                          D._defaultThickness,
                        ],
                        [
                          a.AnnotationEditorParamsType.INK_COLOR,
                          D._defaultColor ||
                            p.AnnotationEditor._defaultLineColor,
                        ],
                        [
                          a.AnnotationEditorParamsType.INK_OPACITY,
                          Math.round(D._defaultOpacity * 100),
                        ],
                      ];
                    }
                    get propertiesToUpdate() {
                      return [
                        [
                          a.AnnotationEditorParamsType.INK_THICKNESS,
                          this.thickness || D._defaultThickness,
                        ],
                        [
                          a.AnnotationEditorParamsType.INK_COLOR,
                          this.color ||
                            D._defaultColor ||
                            p.AnnotationEditor._defaultLineColor,
                        ],
                        [
                          a.AnnotationEditorParamsType.INK_OPACITY,
                          Math.round(100 * (this.opacity ?? D._defaultOpacity)),
                        ],
                      ];
                    }
                    #b(t) {
                      const i = this.thickness;
                      this.addCommands({
                        cmd: () => {
                          ((this.thickness = t), this.#T());
                        },
                        undo: () => {
                          ((this.thickness = i), this.#T());
                        },
                        mustExec: !0,
                        type: a.AnnotationEditorParamsType.INK_THICKNESS,
                        overwriteIfSameType: !0,
                        keepUndo: !0,
                      });
                    }
                    #m(t) {
                      const i = this.color;
                      this.addCommands({
                        cmd: () => {
                          ((this.color = t), this.#A());
                        },
                        undo: () => {
                          ((this.color = i), this.#A());
                        },
                        mustExec: !0,
                        type: a.AnnotationEditorParamsType.INK_COLOR,
                        overwriteIfSameType: !0,
                        keepUndo: !0,
                      });
                    }
                    #g(t) {
                      t /= 100;
                      const i = this.opacity;
                      this.addCommands({
                        cmd: () => {
                          ((this.opacity = t), this.#A());
                        },
                        undo: () => {
                          ((this.opacity = i), this.#A());
                        },
                        mustExec: !0,
                        type: a.AnnotationEditorParamsType.INK_OPACITY,
                        overwriteIfSameType: !0,
                        keepUndo: !0,
                      });
                    }
                    rebuild() {
                      this.parent &&
                        (super.rebuild(),
                        this.div !== null &&
                          (this.canvas || (this.#R(), this.#k()),
                          this.isAttachedToDOM ||
                            (this.parent.add(this), this.#y()),
                          this.#T()));
                    }
                    remove() {
                      this.canvas !== null &&
                        (this.isEmpty() || this.commit(),
                        (this.canvas.width = this.canvas.height = 0),
                        this.canvas.remove(),
                        (this.canvas = null),
                        this.#f.disconnect(),
                        (this.#f = null),
                        super.remove());
                    }
                    setParent(t) {
                      (!this.parent && t
                        ? this._uiManager.removeShouldRescale(this)
                        : this.parent &&
                          t === null &&
                          this._uiManager.addShouldRescale(this),
                        super.setParent(t));
                    }
                    onScaleChanging() {
                      const [t, i] = this.parentDimensions,
                        h = this.width * t,
                        c = this.height * i;
                      this.setDimensions(h, c);
                    }
                    enableEditMode() {
                      this.#l ||
                        this.canvas === null ||
                        (super.enableEditMode(),
                        (this._isDraggable = !1),
                        this.canvas.addEventListener("pointerdown", this.#a));
                    }
                    disableEditMode() {
                      !this.isInEditMode() ||
                        this.canvas === null ||
                        (super.disableEditMode(),
                        (this._isDraggable = !this.isEmpty()),
                        this.div.classList.remove("editing"),
                        this.canvas.removeEventListener(
                          "pointerdown",
                          this.#a,
                        ));
                    }
                    onceAdded() {
                      this._isDraggable = !this.isEmpty();
                    }
                    isEmpty() {
                      return (
                        this.paths.length === 0 ||
                        (this.paths.length === 1 && this.paths[0].length === 0)
                      );
                    }
                    #h() {
                      const {
                        parentRotation: t,
                        parentDimensions: [i, h],
                      } = this;
                      switch (t) {
                        case 90:
                          return [0, h, h, i];
                        case 180:
                          return [i, h, i, h];
                        case 270:
                          return [i, 0, h, i];
                        default:
                          return [0, 0, i, h];
                      }
                    }
                    #_() {
                      const {
                        ctx: t,
                        color: i,
                        opacity: h,
                        thickness: c,
                        parentScale: n,
                        scaleFactor: d,
                      } = this;
                      ((t.lineWidth = (c * n) / d),
                        (t.lineCap = "round"),
                        (t.lineJoin = "round"),
                        (t.miterLimit = 10),
                        (t.strokeStyle = `${i}${(0, j.opacityToHex)(h)}`));
                    }
                    #E(t, i) {
                      (this.canvas.addEventListener(
                        "contextmenu",
                        T.noContextMenu,
                      ),
                        this.canvas.addEventListener("pointerleave", this.#i),
                        this.canvas.addEventListener("pointermove", this.#n),
                        this.canvas.addEventListener("pointerup", this.#o),
                        this.canvas.removeEventListener("pointerdown", this.#a),
                        (this.isEditing = !0),
                        this.#s ||
                          ((this.#s = !0),
                          this.#y(),
                          (this.thickness ||= D._defaultThickness),
                          (this.color ||=
                            D._defaultColor ||
                            p.AnnotationEditor._defaultLineColor),
                          (this.opacity ??= D._defaultOpacity)),
                        this.currentPath.push([t, i]),
                        (this.#c = !1),
                        this.#_(),
                        (this.#p = () => {
                          (this.#L(),
                            this.#p && window.requestAnimationFrame(this.#p));
                        }),
                        window.requestAnimationFrame(this.#p));
                    }
                    #S(t, i) {
                      const [h, c] = this.currentPath.at(-1);
                      if (this.currentPath.length > 1 && t === h && i === c)
                        return;
                      const n = this.currentPath;
                      let d = this.#r;
                      if ((n.push([t, i]), (this.#c = !0), n.length <= 2)) {
                        (d.moveTo(...n[0]), d.lineTo(t, i));
                        return;
                      }
                      (n.length === 3 &&
                        ((this.#r = d = new Path2D()), d.moveTo(...n[0])),
                        this.#I(d, ...n.at(-3), ...n.at(-2), t, i));
                    }
                    #C() {
                      if (this.currentPath.length === 0) return;
                      const t = this.currentPath.at(-1);
                      this.#r.lineTo(...t);
                    }
                    #x(t, i) {
                      ((this.#p = null),
                        (t = Math.min(Math.max(t, 0), this.canvas.width)),
                        (i = Math.min(Math.max(i, 0), this.canvas.height)),
                        this.#S(t, i),
                        this.#C());
                      let h;
                      if (this.currentPath.length !== 1) h = this.#O();
                      else {
                        const l = [t, i];
                        h = [[l, l.slice(), l.slice(), l]];
                      }
                      const c = this.#r,
                        n = this.currentPath;
                      ((this.currentPath = []), (this.#r = new Path2D()));
                      const d = () => {
                          (this.allRawPaths.push(n),
                            this.paths.push(h),
                            this.bezierPath2D.push(c),
                            this.rebuild());
                        },
                        m = () => {
                          (this.allRawPaths.pop(),
                            this.paths.pop(),
                            this.bezierPath2D.pop(),
                            this.paths.length === 0
                              ? this.remove()
                              : (this.canvas || (this.#R(), this.#k()),
                                this.#T()));
                        };
                      this.addCommands({ cmd: d, undo: m, mustExec: !0 });
                    }
                    #L() {
                      if (!this.#c) return;
                      this.#c = !1;
                      const t = Math.ceil(this.thickness * this.parentScale),
                        i = this.currentPath.slice(-3),
                        h = i.map((d) => d[0]),
                        c = i.map((d) => d[1]);
                      (Math.min(...h) - t,
                        Math.max(...h) + t,
                        Math.min(...c) - t,
                        Math.max(...c) + t);
                      const { ctx: n } = this;
                      (n.save(),
                        n.clearRect(
                          0,
                          0,
                          this.canvas.width,
                          this.canvas.height,
                        ));
                      for (const d of this.bezierPath2D) n.stroke(d);
                      (n.stroke(this.#r), n.restore());
                    }
                    #I(t, i, h, c, n, d, m) {
                      const l = (i + c) / 2,
                        w = (h + n) / 2,
                        M = (c + d) / 2,
                        C = (n + m) / 2;
                      t.bezierCurveTo(
                        l + (2 * (c - l)) / 3,
                        w + (2 * (n - w)) / 3,
                        M + (2 * (c - M)) / 3,
                        C + (2 * (n - C)) / 3,
                        M,
                        C,
                      );
                    }
                    #O() {
                      const t = this.currentPath;
                      if (t.length <= 2)
                        return [[t[0], t[0], t.at(-1), t.at(-1)]];
                      const i = [];
                      let h,
                        [c, n] = t[0];
                      for (h = 1; h < t.length - 2; h++) {
                        const [g, E] = t[h],
                          [U, W] = t[h + 1],
                          O = (g + U) / 2,
                          V = (E + W) / 2,
                          G = [c + (2 * (g - c)) / 3, n + (2 * (E - n)) / 3],
                          nt = [O + (2 * (g - O)) / 3, V + (2 * (E - V)) / 3];
                        (i.push([[c, n], G, nt, [O, V]]), ([c, n] = [O, V]));
                      }
                      const [d, m] = t[h],
                        [l, w] = t[h + 1],
                        M = [c + (2 * (d - c)) / 3, n + (2 * (m - n)) / 3],
                        C = [l + (2 * (d - l)) / 3, w + (2 * (m - w)) / 3];
                      return (i.push([[c, n], M, C, [l, w]]), i);
                    }
                    #A() {
                      if (this.isEmpty()) {
                        this.#w();
                        return;
                      }
                      this.#_();
                      const { canvas: t, ctx: i } = this;
                      (i.setTransform(1, 0, 0, 1, 0, 0),
                        i.clearRect(0, 0, t.width, t.height),
                        this.#w());
                      for (const h of this.bezierPath2D) i.stroke(h);
                    }
                    commit() {
                      this.#l ||
                        (super.commit(),
                        (this.isEditing = !1),
                        this.disableEditMode(),
                        this.setInForeground(),
                        (this.#l = !0),
                        this.div.classList.add("disabled"),
                        this.#T(!0),
                        this.makeResizable(),
                        this.parent.addInkEditorIfNeeded(!0),
                        this.moveInDOM(),
                        this.div.focus({ preventScroll: !0 }));
                    }
                    focusin(t) {
                      this._focusEventsAllowed &&
                        (super.focusin(t), this.enableEditMode());
                    }
                    canvasPointerdown(t) {
                      t.button !== 0 ||
                        !this.isInEditMode() ||
                        this.#l ||
                        (this.setInForeground(),
                        t.preventDefault(),
                        t.type !== "mouse" && this.div.focus(),
                        this.#E(t.offsetX, t.offsetY));
                    }
                    canvasPointermove(t) {
                      (t.preventDefault(), this.#S(t.offsetX, t.offsetY));
                    }
                    canvasPointerup(t) {
                      (t.preventDefault(), this.#D(t));
                    }
                    canvasPointerleave(t) {
                      this.#D(t);
                    }
                    #D(t) {
                      (this.canvas.removeEventListener("pointerleave", this.#i),
                        this.canvas.removeEventListener("pointermove", this.#n),
                        this.canvas.removeEventListener("pointerup", this.#o),
                        this.canvas.addEventListener("pointerdown", this.#a),
                        setTimeout(() => {
                          this.canvas.removeEventListener(
                            "contextmenu",
                            T.noContextMenu,
                          );
                        }, 10),
                        this.#x(t.offsetX, t.offsetY),
                        this.addToAnnotationStorage(),
                        this.setInBackground());
                    }
                    #R() {
                      ((this.canvas = document.createElement("canvas")),
                        (this.canvas.width = this.canvas.height = 0),
                        (this.canvas.className = "inkEditorCanvas"),
                        p.AnnotationEditor._l10nPromise
                          .get("editor_ink_canvas_aria_label")
                          .then((t) =>
                            this.canvas?.setAttribute("aria-label", t),
                          ),
                        this.div.append(this.canvas),
                        (this.ctx = this.canvas.getContext("2d")));
                    }
                    #k() {
                      ((this.#f = new ResizeObserver((t) => {
                        const i = t[0].contentRect;
                        i.width &&
                          i.height &&
                          this.setDimensions(i.width, i.height);
                      })),
                        this.#f.observe(this.div));
                    }
                    get isResizable() {
                      return !this.isEmpty() && this.#l;
                    }
                    render() {
                      if (this.div) return this.div;
                      let t, i;
                      (this.width && ((t = this.x), (i = this.y)),
                        super.render(),
                        p.AnnotationEditor._l10nPromise
                          .get("editor_ink2_aria_label")
                          .then((m) =>
                            this.div?.setAttribute("aria-label", m),
                          ));
                      const [h, c, n, d] = this.#h();
                      if (
                        (this.setAt(h, c, 0, 0),
                        this.setDims(n, d),
                        this.#R(),
                        this.width)
                      ) {
                        const [m, l] = this.parentDimensions;
                        (this.setAspectRatio(this.width * m, this.height * l),
                          this.setAt(
                            t * m,
                            i * l,
                            this.width * m,
                            this.height * l,
                          ),
                          (this.#s = !0),
                          this.#y(),
                          this.setDims(this.width * m, this.height * l),
                          this.#A(),
                          this.div.classList.add("disabled"));
                      } else
                        (this.div.classList.add("editing"),
                          this.enableEditMode());
                      return (this.#k(), this.div);
                    }
                    #y() {
                      if (!this.#s) return;
                      const [t, i] = this.parentDimensions;
                      ((this.canvas.width = Math.ceil(this.width * t)),
                        (this.canvas.height = Math.ceil(this.height * i)),
                        this.#w());
                    }
                    setDimensions(t, i) {
                      const h = Math.round(t),
                        c = Math.round(i);
                      if (this.#d === h && this.#u === c) return;
                      ((this.#d = h),
                        (this.#u = c),
                        (this.canvas.style.visibility = "hidden"));
                      const [n, d] = this.parentDimensions;
                      ((this.width = t / n),
                        (this.height = i / d),
                        this.fixAndSetPosition(),
                        this.#l && this.#P(t, i),
                        this.#y(),
                        this.#A(),
                        (this.canvas.style.visibility = "visible"),
                        this.fixDims());
                    }
                    #P(t, i) {
                      const h = this.#F(),
                        c = (t - h) / this.#e,
                        n = (i - h) / this.#t;
                      this.scaleFactor = Math.min(c, n);
                    }
                    #w() {
                      const t = this.#F() / 2;
                      this.ctx.setTransform(
                        this.scaleFactor,
                        0,
                        0,
                        this.scaleFactor,
                        this.translationX * this.scaleFactor + t,
                        this.translationY * this.scaleFactor + t,
                      );
                    }
                    static #N(t) {
                      const i = new Path2D();
                      for (let h = 0, c = t.length; h < c; h++) {
                        const [n, d, m, l] = t[h];
                        (h === 0 && i.moveTo(...n),
                          i.bezierCurveTo(d[0], d[1], m[0], m[1], l[0], l[1]));
                      }
                      return i;
                    }
                    static #j(t, i, h) {
                      const [c, n, d, m] = i;
                      switch (h) {
                        case 0:
                          for (let l = 0, w = t.length; l < w; l += 2)
                            ((t[l] += c), (t[l + 1] = m - t[l + 1]));
                          break;
                        case 90:
                          for (let l = 0, w = t.length; l < w; l += 2) {
                            const M = t[l];
                            ((t[l] = t[l + 1] + c), (t[l + 1] = M + n));
                          }
                          break;
                        case 180:
                          for (let l = 0, w = t.length; l < w; l += 2)
                            ((t[l] = d - t[l]), (t[l + 1] += n));
                          break;
                        case 270:
                          for (let l = 0, w = t.length; l < w; l += 2) {
                            const M = t[l];
                            ((t[l] = d - t[l + 1]), (t[l + 1] = m - M));
                          }
                          break;
                        default:
                          throw new Error("Invalid rotation");
                      }
                      return t;
                    }
                    static #B(t, i, h) {
                      const [c, n, d, m] = i;
                      switch (h) {
                        case 0:
                          for (let l = 0, w = t.length; l < w; l += 2)
                            ((t[l] -= c), (t[l + 1] = m - t[l + 1]));
                          break;
                        case 90:
                          for (let l = 0, w = t.length; l < w; l += 2) {
                            const M = t[l];
                            ((t[l] = t[l + 1] - n), (t[l + 1] = M - c));
                          }
                          break;
                        case 180:
                          for (let l = 0, w = t.length; l < w; l += 2)
                            ((t[l] = d - t[l]), (t[l + 1] -= n));
                          break;
                        case 270:
                          for (let l = 0, w = t.length; l < w; l += 2) {
                            const M = t[l];
                            ((t[l] = m - t[l + 1]), (t[l + 1] = d - M));
                          }
                          break;
                        default:
                          throw new Error("Invalid rotation");
                      }
                      return t;
                    }
                    #U(t, i, h, c) {
                      const n = [],
                        d = this.thickness / 2,
                        m = t * i + d,
                        l = t * h + d;
                      for (const w of this.paths) {
                        const M = [],
                          C = [];
                        for (let g = 0, E = w.length; g < E; g++) {
                          const [U, W, O, V] = w[g],
                            G = t * U[0] + m,
                            nt = t * U[1] + l,
                            Z = t * W[0] + m,
                            tt = t * W[1] + l,
                            rt = t * O[0] + m,
                            K = t * O[1] + l,
                            I = t * V[0] + m,
                            _ = t * V[1] + l;
                          (g === 0 && (M.push(G, nt), C.push(G, nt)),
                            M.push(Z, tt, rt, K, I, _),
                            C.push(Z, tt),
                            g === E - 1 && C.push(I, _));
                        }
                        n.push({
                          bezier: D.#j(M, c, this.rotation),
                          points: D.#j(C, c, this.rotation),
                        });
                      }
                      return n;
                    }
                    #M() {
                      let t = 1 / 0,
                        i = -1 / 0,
                        h = 1 / 0,
                        c = -1 / 0;
                      for (const n of this.paths)
                        for (const [d, m, l, w] of n) {
                          const M = a.Util.bezierBoundingBox(
                            ...d,
                            ...m,
                            ...l,
                            ...w,
                          );
                          ((t = Math.min(t, M[0])),
                            (h = Math.min(h, M[1])),
                            (i = Math.max(i, M[2])),
                            (c = Math.max(c, M[3])));
                        }
                      return [t, h, i, c];
                    }
                    #F() {
                      return this.#l
                        ? Math.ceil(this.thickness * this.parentScale)
                        : 0;
                    }
                    #T(t = !1) {
                      if (this.isEmpty()) return;
                      if (!this.#l) {
                        this.#A();
                        return;
                      }
                      const i = this.#M(),
                        h = this.#F();
                      ((this.#e = Math.max(
                        p.AnnotationEditor.MIN_SIZE,
                        i[2] - i[0],
                      )),
                        (this.#t = Math.max(
                          p.AnnotationEditor.MIN_SIZE,
                          i[3] - i[1],
                        )));
                      const c = Math.ceil(h + this.#e * this.scaleFactor),
                        n = Math.ceil(h + this.#t * this.scaleFactor),
                        [d, m] = this.parentDimensions;
                      ((this.width = c / d),
                        (this.height = n / m),
                        this.setAspectRatio(c, n));
                      const l = this.translationX,
                        w = this.translationY;
                      ((this.translationX = -i[0]),
                        (this.translationY = -i[1]),
                        this.#y(),
                        this.#A(),
                        (this.#d = c),
                        (this.#u = n),
                        this.setDims(c, n));
                      const M = t ? h / this.scaleFactor / 2 : 0;
                      this.translate(
                        l - this.translationX - M,
                        w - this.translationY - M,
                      );
                    }
                    static deserialize(t, i, h) {
                      if (t instanceof k.InkAnnotationElement) return null;
                      const c = super.deserialize(t, i, h);
                      ((c.thickness = t.thickness),
                        (c.color = a.Util.makeHexColor(...t.color)),
                        (c.opacity = t.opacity));
                      const [n, d] = c.pageDimensions,
                        m = c.width * n,
                        l = c.height * d,
                        w = c.parentScale,
                        M = t.thickness / 2;
                      ((c.#l = !0),
                        (c.#d = Math.round(m)),
                        (c.#u = Math.round(l)));
                      const { paths: C, rect: g, rotation: E } = t;
                      for (let { bezier: W } of C) {
                        W = D.#B(W, g, E);
                        const O = [];
                        c.paths.push(O);
                        let V = w * (W[0] - M),
                          G = w * (W[1] - M);
                        for (let Z = 2, tt = W.length; Z < tt; Z += 6) {
                          const rt = w * (W[Z] - M),
                            K = w * (W[Z + 1] - M),
                            I = w * (W[Z + 2] - M),
                            _ = w * (W[Z + 3] - M),
                            u = w * (W[Z + 4] - M),
                            f = w * (W[Z + 5] - M);
                          (O.push([
                            [V, G],
                            [rt, K],
                            [I, _],
                            [u, f],
                          ]),
                            (V = u),
                            (G = f));
                        }
                        const nt = this.#N(O);
                        c.bezierPath2D.push(nt);
                      }
                      const U = c.#M();
                      return (
                        (c.#e = Math.max(
                          p.AnnotationEditor.MIN_SIZE,
                          U[2] - U[0],
                        )),
                        (c.#t = Math.max(
                          p.AnnotationEditor.MIN_SIZE,
                          U[3] - U[1],
                        )),
                        c.#P(m, l),
                        c
                      );
                    }
                    serialize() {
                      if (this.isEmpty()) return null;
                      const t = this.getRect(0, 0),
                        i = p.AnnotationEditor._colorManager.convert(
                          this.ctx.strokeStyle,
                        );
                      return {
                        annotationType: a.AnnotationEditorType.INK,
                        color: i,
                        thickness: this.thickness,
                        opacity: this.opacity,
                        paths: this.#U(
                          this.scaleFactor / this.parentScale,
                          this.translationX,
                          this.translationY,
                          t,
                        ),
                        pageIndex: this.pageIndex,
                        rect: t,
                        rotation: this.rotation,
                        structTreeParentId: this._structTreeParentId,
                      };
                    }
                  }
                  e.InkEditor = D;
                },
                (A, e, y) => {
                  (Object.defineProperty(e, "__esModule", { value: !0 }),
                    (e.StampEditor = void 0));
                  var a = y(1),
                    p = y(4),
                    k = y(6),
                    T = y(29);
                  class j extends p.AnnotationEditor {
                    #t = null;
                    #e = null;
                    #n = null;
                    #i = null;
                    #o = null;
                    #a = null;
                    #r = null;
                    #l = null;
                    #c = !1;
                    #s = !1;
                    static _type = "stamp";
                    constructor(s) {
                      (super({ ...s, name: "stampEditor" }),
                        (this.#i = s.bitmapUrl),
                        (this.#o = s.bitmapFile));
                    }
                    static initialize(s) {
                      p.AnnotationEditor.initialize(s);
                    }
                    static get supportedTypes() {
                      const s = [
                        "apng",
                        "avif",
                        "bmp",
                        "gif",
                        "jpeg",
                        "png",
                        "svg+xml",
                        "webp",
                        "x-icon",
                      ];
                      return (0, a.shadow)(
                        this,
                        "supportedTypes",
                        s.map((t) => `image/${t}`),
                      );
                    }
                    static get supportedTypesStr() {
                      return (0, a.shadow)(
                        this,
                        "supportedTypesStr",
                        this.supportedTypes.join(","),
                      );
                    }
                    static isHandlingMimeForPasting(s) {
                      return this.supportedTypes.includes(s);
                    }
                    static paste(s, t) {
                      t.pasteEditor(a.AnnotationEditorType.STAMP, {
                        bitmapFile: s.getAsFile(),
                      });
                    }
                    #f(s, t = !1) {
                      if (!s) {
                        this.remove();
                        return;
                      }
                      ((this.#t = s.bitmap),
                        t || ((this.#e = s.id), (this.#c = s.isSvg)),
                        this.#p());
                    }
                    #d() {
                      ((this.#n = null),
                        this._uiManager.enableWaiting(!1),
                        this.#a && this.div.focus());
                    }
                    #u() {
                      if (this.#e) {
                        (this._uiManager.enableWaiting(!0),
                          this._uiManager.imageManager
                            .getFromId(this.#e)
                            .then((t) => this.#f(t, !0))
                            .finally(() => this.#d()));
                        return;
                      }
                      if (this.#i) {
                        const t = this.#i;
                        ((this.#i = null),
                          this._uiManager.enableWaiting(!0),
                          (this.#n = this._uiManager.imageManager
                            .getFromUrl(t)
                            .then((i) => this.#f(i))
                            .finally(() => this.#d())));
                        return;
                      }
                      if (this.#o) {
                        const t = this.#o;
                        ((this.#o = null),
                          this._uiManager.enableWaiting(!0),
                          (this.#n = this._uiManager.imageManager
                            .getFromFile(t)
                            .then((i) => this.#f(i))
                            .finally(() => this.#d())));
                        return;
                      }
                      const s = document.createElement("input");
                      ((s.type = "file"),
                        (s.accept = j.supportedTypesStr),
                        (this.#n = new Promise((t) => {
                          (s.addEventListener("change", async () => {
                            if (!s.files || s.files.length === 0) this.remove();
                            else {
                              this._uiManager.enableWaiting(!0);
                              const i =
                                await this._uiManager.imageManager.getFromFile(
                                  s.files[0],
                                );
                              this.#f(i);
                            }
                            t();
                          }),
                            s.addEventListener("cancel", () => {
                              (this.remove(), t());
                            }));
                        }).finally(() => this.#d())),
                        s.click());
                    }
                    remove() {
                      (this.#e &&
                        ((this.#t = null),
                        this._uiManager.imageManager.deleteId(this.#e),
                        this.#a?.remove(),
                        (this.#a = null),
                        this.#r?.disconnect(),
                        (this.#r = null)),
                        super.remove());
                    }
                    rebuild() {
                      if (!this.parent) {
                        this.#e && this.#u();
                        return;
                      }
                      (super.rebuild(),
                        this.div !== null &&
                          (this.#e && this.#u(),
                          this.isAttachedToDOM || this.parent.add(this)));
                    }
                    onceAdded() {
                      ((this._isDraggable = !0), this.div.focus());
                    }
                    isEmpty() {
                      return !(this.#n || this.#t || this.#i || this.#o);
                    }
                    get isResizable() {
                      return !0;
                    }
                    render() {
                      if (this.div) return this.div;
                      let s, t;
                      if (
                        (this.width && ((s = this.x), (t = this.y)),
                        super.render(),
                        (this.div.hidden = !0),
                        this.#t ? this.#p() : this.#u(),
                        this.width)
                      ) {
                        const [i, h] = this.parentDimensions;
                        this.setAt(
                          s * i,
                          t * h,
                          this.width * i,
                          this.height * h,
                        );
                      }
                      return this.div;
                    }
                    #p() {
                      const { div: s } = this;
                      let { width: t, height: i } = this.#t;
                      const [h, c] = this.pageDimensions,
                        n = 0.75;
                      if (this.width)
                        ((t = this.width * h), (i = this.height * c));
                      else if (t > n * h || i > n * c) {
                        const w = Math.min((n * h) / t, (n * c) / i);
                        ((t *= w), (i *= w));
                      }
                      const [d, m] = this.parentDimensions;
                      (this.setDims((t * d) / h, (i * m) / c),
                        this._uiManager.enableWaiting(!1));
                      const l = (this.#a = document.createElement("canvas"));
                      (s.append(l),
                        (s.hidden = !1),
                        this.#g(t, i),
                        this.#_(),
                        this.#s ||
                          (this.parent.addUndoableEditor(this), (this.#s = !0)),
                        this._uiManager._eventBus.dispatch("reporttelemetry", {
                          source: this,
                          details: {
                            type: "editing",
                            subtype: this.editorType,
                            data: { action: "inserted_image" },
                          },
                        }),
                        this.addAltTextButton());
                    }
                    #b(s, t) {
                      const [i, h] = this.parentDimensions;
                      ((this.width = s / i),
                        (this.height = t / h),
                        this.setDims(s, t),
                        this._initialOptions?.isCentered
                          ? this.center()
                          : this.fixAndSetPosition(),
                        (this._initialOptions = null),
                        this.#l !== null && clearTimeout(this.#l));
                      const c = 200;
                      this.#l = setTimeout(() => {
                        ((this.#l = null), this.#g(s, t));
                      }, c);
                    }
                    #m(s, t) {
                      const { width: i, height: h } = this.#t;
                      let c = i,
                        n = h,
                        d = this.#t;
                      for (; c > 2 * s || n > 2 * t;) {
                        const m = c,
                          l = n;
                        (c > 2 * s &&
                          (c =
                            c >= 16384
                              ? Math.floor(c / 2) - 1
                              : Math.ceil(c / 2)),
                          n > 2 * t &&
                            (n =
                              n >= 16384
                                ? Math.floor(n / 2) - 1
                                : Math.ceil(n / 2)));
                        const w = new OffscreenCanvas(c, n);
                        (w
                          .getContext("2d")
                          .drawImage(d, 0, 0, m, l, 0, 0, c, n),
                          (d = w.transferToImageBitmap()));
                      }
                      return d;
                    }
                    #g(s, t) {
                      ((s = Math.ceil(s)), (t = Math.ceil(t)));
                      const i = this.#a;
                      if (!i || (i.width === s && i.height === t)) return;
                      ((i.width = s), (i.height = t));
                      const h = this.#c ? this.#t : this.#m(s, t),
                        c = i.getContext("2d");
                      ((c.filter = this._uiManager.hcmFilter),
                        c.drawImage(h, 0, 0, h.width, h.height, 0, 0, s, t));
                    }
                    #h(s) {
                      if (s) {
                        if (this.#c) {
                          const h = this._uiManager.imageManager.getSvgUrl(
                            this.#e,
                          );
                          if (h) return h;
                        }
                        const t = document.createElement("canvas");
                        return (
                          ({ width: t.width, height: t.height } = this.#t),
                          t.getContext("2d").drawImage(this.#t, 0, 0),
                          t.toDataURL()
                        );
                      }
                      if (this.#c) {
                        const [t, i] = this.pageDimensions,
                          h = Math.round(
                            this.width * t * k.PixelsPerInch.PDF_TO_CSS_UNITS,
                          ),
                          c = Math.round(
                            this.height * i * k.PixelsPerInch.PDF_TO_CSS_UNITS,
                          ),
                          n = new OffscreenCanvas(h, c);
                        return (
                          n
                            .getContext("2d")
                            .drawImage(
                              this.#t,
                              0,
                              0,
                              this.#t.width,
                              this.#t.height,
                              0,
                              0,
                              h,
                              c,
                            ),
                          n.transferToImageBitmap()
                        );
                      }
                      return structuredClone(this.#t);
                    }
                    #_() {
                      ((this.#r = new ResizeObserver((s) => {
                        const t = s[0].contentRect;
                        t.width && t.height && this.#b(t.width, t.height);
                      })),
                        this.#r.observe(this.div));
                    }
                    static deserialize(s, t, i) {
                      if (s instanceof T.StampAnnotationElement) return null;
                      const h = super.deserialize(s, t, i),
                        {
                          rect: c,
                          bitmapUrl: n,
                          bitmapId: d,
                          isSvg: m,
                          accessibilityData: l,
                        } = s;
                      (d && i.imageManager.isValidId(d)
                        ? (h.#e = d)
                        : (h.#i = n),
                        (h.#c = m));
                      const [w, M] = h.pageDimensions;
                      return (
                        (h.width = (c[2] - c[0]) / w),
                        (h.height = (c[3] - c[1]) / M),
                        l && (h.altTextData = l),
                        h
                      );
                    }
                    serialize(s = !1, t = null) {
                      if (this.isEmpty()) return null;
                      const i = {
                        annotationType: a.AnnotationEditorType.STAMP,
                        bitmapId: this.#e,
                        pageIndex: this.pageIndex,
                        rect: this.getRect(0, 0),
                        rotation: this.rotation,
                        isSvg: this.#c,
                        structTreeParentId: this._structTreeParentId,
                      };
                      if (s)
                        return (
                          (i.bitmapUrl = this.#h(!0)),
                          (i.accessibilityData = this.altTextData),
                          i
                        );
                      const { decorative: h, altText: c } = this.altTextData;
                      if (
                        (!h &&
                          c &&
                          (i.accessibilityData = { type: "Figure", alt: c }),
                        t === null)
                      )
                        return i;
                      t.stamps ||= new Map();
                      const n = this.#c
                        ? (i.rect[2] - i.rect[0]) * (i.rect[3] - i.rect[1])
                        : null;
                      if (!t.stamps.has(this.#e))
                        (t.stamps.set(this.#e, { area: n, serialized: i }),
                          (i.bitmap = this.#h(!1)));
                      else if (this.#c) {
                        const d = t.stamps.get(this.#e);
                        n > d.area &&
                          ((d.area = n),
                          d.serialized.bitmap.close(),
                          (d.serialized.bitmap = this.#h(!1)));
                      }
                      return i;
                    }
                  }
                  e.StampEditor = j;
                },
              ],
              __webpack_module_cache__ = {};
            function __w_pdfjs_require__(A) {
              var e = __webpack_module_cache__[A];
              if (e !== void 0) return e.exports;
              var y = (__webpack_module_cache__[A] = { exports: {} });
              return (
                __webpack_modules__[A](y, y.exports, __w_pdfjs_require__),
                y.exports
              );
            }
            var __webpack_exports__ = {};
            return (
              (() => {
                var A = __webpack_exports__;
                (Object.defineProperty(A, "__esModule", { value: !0 }),
                  Object.defineProperty(A, "AbortException", {
                    enumerable: !0,
                    get: function () {
                      return e.AbortException;
                    },
                  }),
                  Object.defineProperty(A, "AnnotationEditorLayer", {
                    enumerable: !0,
                    get: function () {
                      return k.AnnotationEditorLayer;
                    },
                  }),
                  Object.defineProperty(A, "AnnotationEditorParamsType", {
                    enumerable: !0,
                    get: function () {
                      return e.AnnotationEditorParamsType;
                    },
                  }),
                  Object.defineProperty(A, "AnnotationEditorType", {
                    enumerable: !0,
                    get: function () {
                      return e.AnnotationEditorType;
                    },
                  }),
                  Object.defineProperty(A, "AnnotationEditorUIManager", {
                    enumerable: !0,
                    get: function () {
                      return T.AnnotationEditorUIManager;
                    },
                  }),
                  Object.defineProperty(A, "AnnotationLayer", {
                    enumerable: !0,
                    get: function () {
                      return j.AnnotationLayer;
                    },
                  }),
                  Object.defineProperty(A, "AnnotationMode", {
                    enumerable: !0,
                    get: function () {
                      return e.AnnotationMode;
                    },
                  }),
                  Object.defineProperty(A, "CMapCompressionType", {
                    enumerable: !0,
                    get: function () {
                      return e.CMapCompressionType;
                    },
                  }),
                  Object.defineProperty(A, "DOMSVGFactory", {
                    enumerable: !0,
                    get: function () {
                      return a.DOMSVGFactory;
                    },
                  }),
                  Object.defineProperty(A, "FeatureTest", {
                    enumerable: !0,
                    get: function () {
                      return e.FeatureTest;
                    },
                  }),
                  Object.defineProperty(A, "GlobalWorkerOptions", {
                    enumerable: !0,
                    get: function () {
                      return D.GlobalWorkerOptions;
                    },
                  }),
                  Object.defineProperty(A, "ImageKind", {
                    enumerable: !0,
                    get: function () {
                      return e.ImageKind;
                    },
                  }),
                  Object.defineProperty(A, "InvalidPDFException", {
                    enumerable: !0,
                    get: function () {
                      return e.InvalidPDFException;
                    },
                  }),
                  Object.defineProperty(A, "MissingPDFException", {
                    enumerable: !0,
                    get: function () {
                      return e.MissingPDFException;
                    },
                  }),
                  Object.defineProperty(A, "OPS", {
                    enumerable: !0,
                    get: function () {
                      return e.OPS;
                    },
                  }),
                  Object.defineProperty(A, "PDFDataRangeTransport", {
                    enumerable: !0,
                    get: function () {
                      return y.PDFDataRangeTransport;
                    },
                  }),
                  Object.defineProperty(A, "PDFDateString", {
                    enumerable: !0,
                    get: function () {
                      return a.PDFDateString;
                    },
                  }),
                  Object.defineProperty(A, "PDFWorker", {
                    enumerable: !0,
                    get: function () {
                      return y.PDFWorker;
                    },
                  }),
                  Object.defineProperty(A, "PasswordResponses", {
                    enumerable: !0,
                    get: function () {
                      return e.PasswordResponses;
                    },
                  }),
                  Object.defineProperty(A, "PermissionFlag", {
                    enumerable: !0,
                    get: function () {
                      return e.PermissionFlag;
                    },
                  }),
                  Object.defineProperty(A, "PixelsPerInch", {
                    enumerable: !0,
                    get: function () {
                      return a.PixelsPerInch;
                    },
                  }),
                  Object.defineProperty(A, "PromiseCapability", {
                    enumerable: !0,
                    get: function () {
                      return e.PromiseCapability;
                    },
                  }),
                  Object.defineProperty(A, "RenderingCancelledException", {
                    enumerable: !0,
                    get: function () {
                      return a.RenderingCancelledException;
                    },
                  }),
                  Object.defineProperty(A, "SVGGraphics", {
                    enumerable: !0,
                    get: function () {
                      return y.SVGGraphics;
                    },
                  }),
                  Object.defineProperty(A, "UnexpectedResponseException", {
                    enumerable: !0,
                    get: function () {
                      return e.UnexpectedResponseException;
                    },
                  }),
                  Object.defineProperty(A, "Util", {
                    enumerable: !0,
                    get: function () {
                      return e.Util;
                    },
                  }),
                  Object.defineProperty(A, "VerbosityLevel", {
                    enumerable: !0,
                    get: function () {
                      return e.VerbosityLevel;
                    },
                  }),
                  Object.defineProperty(A, "XfaLayer", {
                    enumerable: !0,
                    get: function () {
                      return s.XfaLayer;
                    },
                  }),
                  Object.defineProperty(A, "build", {
                    enumerable: !0,
                    get: function () {
                      return y.build;
                    },
                  }),
                  Object.defineProperty(A, "createValidAbsoluteUrl", {
                    enumerable: !0,
                    get: function () {
                      return e.createValidAbsoluteUrl;
                    },
                  }),
                  Object.defineProperty(A, "getDocument", {
                    enumerable: !0,
                    get: function () {
                      return y.getDocument;
                    },
                  }),
                  Object.defineProperty(A, "getFilenameFromUrl", {
                    enumerable: !0,
                    get: function () {
                      return a.getFilenameFromUrl;
                    },
                  }),
                  Object.defineProperty(A, "getPdfFilenameFromUrl", {
                    enumerable: !0,
                    get: function () {
                      return a.getPdfFilenameFromUrl;
                    },
                  }),
                  Object.defineProperty(A, "getXfaPageViewport", {
                    enumerable: !0,
                    get: function () {
                      return a.getXfaPageViewport;
                    },
                  }),
                  Object.defineProperty(A, "isDataScheme", {
                    enumerable: !0,
                    get: function () {
                      return a.isDataScheme;
                    },
                  }),
                  Object.defineProperty(A, "isPdfFile", {
                    enumerable: !0,
                    get: function () {
                      return a.isPdfFile;
                    },
                  }),
                  Object.defineProperty(A, "loadScript", {
                    enumerable: !0,
                    get: function () {
                      return a.loadScript;
                    },
                  }),
                  Object.defineProperty(A, "noContextMenu", {
                    enumerable: !0,
                    get: function () {
                      return a.noContextMenu;
                    },
                  }),
                  Object.defineProperty(A, "normalizeUnicode", {
                    enumerable: !0,
                    get: function () {
                      return e.normalizeUnicode;
                    },
                  }),
                  Object.defineProperty(A, "renderTextLayer", {
                    enumerable: !0,
                    get: function () {
                      return p.renderTextLayer;
                    },
                  }),
                  Object.defineProperty(A, "setLayerDimensions", {
                    enumerable: !0,
                    get: function () {
                      return a.setLayerDimensions;
                    },
                  }),
                  Object.defineProperty(A, "shadow", {
                    enumerable: !0,
                    get: function () {
                      return e.shadow;
                    },
                  }),
                  Object.defineProperty(A, "updateTextLayer", {
                    enumerable: !0,
                    get: function () {
                      return p.updateTextLayer;
                    },
                  }),
                  Object.defineProperty(A, "version", {
                    enumerable: !0,
                    get: function () {
                      return y.version;
                    },
                  }));
                var e = __w_pdfjs_require__(1),
                  y = __w_pdfjs_require__(2),
                  a = __w_pdfjs_require__(6),
                  p = __w_pdfjs_require__(26),
                  k = __w_pdfjs_require__(27),
                  T = __w_pdfjs_require__(5),
                  j = __w_pdfjs_require__(29),
                  D = __w_pdfjs_require__(14),
                  s = __w_pdfjs_require__(32);
              })(),
              __webpack_exports__
            );
          })(),
        );
      })(pdf$1)),
    pdf$1.exports
  );
}
var pdfExports = requirePdf();
const pdf = getDefaultExportFromCjs(pdfExports),
  pdfjs = pdf;
var __spreadArray = function (A, e, y) {
    if (y || arguments.length === 2)
      for (var a = 0, p = e.length, k; a < p; a++)
        (k || !(a in e)) &&
          (k || (k = Array.prototype.slice.call(e, 0, a)), (k[a] = e[a]));
    return A.concat(k || Array.prototype.slice.call(e));
  },
  clipboardEvents = ["onCopy", "onCut", "onPaste"],
  compositionEvents = [
    "onCompositionEnd",
    "onCompositionStart",
    "onCompositionUpdate",
  ],
  focusEvents = ["onFocus", "onBlur"],
  formEvents = ["onInput", "onInvalid", "onReset", "onSubmit"],
  imageEvents = ["onLoad", "onError"],
  keyboardEvents = ["onKeyDown", "onKeyPress", "onKeyUp"],
  mediaEvents = [
    "onAbort",
    "onCanPlay",
    "onCanPlayThrough",
    "onDurationChange",
    "onEmptied",
    "onEncrypted",
    "onEnded",
    "onError",
    "onLoadedData",
    "onLoadedMetadata",
    "onLoadStart",
    "onPause",
    "onPlay",
    "onPlaying",
    "onProgress",
    "onRateChange",
    "onSeeked",
    "onSeeking",
    "onStalled",
    "onSuspend",
    "onTimeUpdate",
    "onVolumeChange",
    "onWaiting",
  ],
  mouseEvents = [
    "onClick",
    "onContextMenu",
    "onDoubleClick",
    "onMouseDown",
    "onMouseEnter",
    "onMouseLeave",
    "onMouseMove",
    "onMouseOut",
    "onMouseOver",
    "onMouseUp",
  ],
  dragEvents = [
    "onDrag",
    "onDragEnd",
    "onDragEnter",
    "onDragExit",
    "onDragLeave",
    "onDragOver",
    "onDragStart",
    "onDrop",
  ],
  selectionEvents = ["onSelect"],
  touchEvents = ["onTouchCancel", "onTouchEnd", "onTouchMove", "onTouchStart"],
  pointerEvents = [
    "onPointerDown",
    "onPointerMove",
    "onPointerUp",
    "onPointerCancel",
    "onGotPointerCapture",
    "onLostPointerCapture",
    "onPointerEnter",
    "onPointerLeave",
    "onPointerOver",
    "onPointerOut",
  ],
  uiEvents = ["onScroll"],
  wheelEvents = ["onWheel"],
  animationEvents = [
    "onAnimationStart",
    "onAnimationEnd",
    "onAnimationIteration",
  ],
  transitionEvents = ["onTransitionEnd"],
  otherEvents = ["onToggle"],
  changeEvents = ["onChange"],
  allEvents = __spreadArray(
    __spreadArray(
      __spreadArray(
        __spreadArray(
          __spreadArray(
            __spreadArray(
              __spreadArray(
                __spreadArray(
                  __spreadArray(
                    __spreadArray(
                      __spreadArray(
                        __spreadArray(
                          __spreadArray(
                            __spreadArray(
                              __spreadArray(
                                __spreadArray(
                                  __spreadArray(
                                    __spreadArray([], clipboardEvents, !0),
                                    compositionEvents,
                                    !0,
                                  ),
                                  focusEvents,
                                  !0,
                                ),
                                formEvents,
                                !0,
                              ),
                              imageEvents,
                              !0,
                            ),
                            keyboardEvents,
                            !0,
                          ),
                          mediaEvents,
                          !0,
                        ),
                        mouseEvents,
                        !0,
                      ),
                      dragEvents,
                      !0,
                    ),
                    selectionEvents,
                    !0,
                  ),
                  touchEvents,
                  !0,
                ),
                pointerEvents,
                !0,
              ),
              uiEvents,
              !0,
            ),
            wheelEvents,
            !0,
          ),
          animationEvents,
          !0,
        ),
        transitionEvents,
        !0,
      ),
      changeEvents,
      !0,
    ),
    otherEvents,
    !0,
  );
function makeEventProps(A, e) {
  var y = {};
  return (
    allEvents.forEach(function (a) {
      var p = A[a];
      p &&
        (e
          ? (y[a] = function (k) {
              return p(k, e(a));
            })
          : (y[a] = p));
    }),
    y
  );
}
function makeCancellablePromise(A) {
  var e = !1,
    y = new Promise(function (a, p) {
      A.then(function (k) {
        return !e && a(k);
      }).catch(function (k) {
        return !e && p(k);
      });
    });
  return {
    promise: y,
    cancel: function () {
      e = !0;
    },
  };
}
function r(A) {
  var e,
    y,
    a = "";
  if (typeof A == "string" || typeof A == "number") a += A;
  else if (typeof A == "object")
    if (Array.isArray(A)) {
      var p = A.length;
      for (e = 0; e < p; e++)
        A[e] && (y = r(A[e])) && (a && (a += " "), (a += y));
    } else for (y in A) A[y] && (a && (a += " "), (a += y));
  return a;
}
function clsx() {
  for (var A, e, y = 0, a = "", p = arguments.length; y < p; y++)
    (A = arguments[y]) && (e = r(A)) && (a && (a += " "), (a += e));
  return a;
}
var prefix = "Invariant failed";
function invariant(A, e) {
  if (!A) throw new Error(prefix);
}
var warning_1, hasRequiredWarning;
function requireWarning() {
  if (hasRequiredWarning) return warning_1;
  hasRequiredWarning = 1;
  var A = function () {};
  return ((warning_1 = A), warning_1);
}
var warningExports = requireWarning();
const warning = getDefaultExportFromCjs(warningExports);
var has = Object.prototype.hasOwnProperty;
function find(A, e, y) {
  for (y of A.keys()) if (dequal(y, e)) return y;
}
function dequal(A, e) {
  var y, a, p;
  if (A === e) return !0;
  if (A && e && (y = A.constructor) === e.constructor) {
    if (y === Date) return A.getTime() === e.getTime();
    if (y === RegExp) return A.toString() === e.toString();
    if (y === Array) {
      if ((a = A.length) === e.length) for (; a-- && dequal(A[a], e[a]););
      return a === -1;
    }
    if (y === Set) {
      if (A.size !== e.size) return !1;
      for (a of A)
        if (
          ((p = a),
          (p && typeof p == "object" && ((p = find(e, p)), !p)) || !e.has(p))
        )
          return !1;
      return !0;
    }
    if (y === Map) {
      if (A.size !== e.size) return !1;
      for (a of A)
        if (
          ((p = a[0]),
          (p && typeof p == "object" && ((p = find(e, p)), !p)) ||
            !dequal(a[1], e.get(p)))
        )
          return !1;
      return !0;
    }
    if (y === ArrayBuffer) ((A = new Uint8Array(A)), (e = new Uint8Array(e)));
    else if (y === DataView) {
      if ((a = A.byteLength) === e.byteLength)
        for (; a-- && A.getInt8(a) === e.getInt8(a););
      return a === -1;
    }
    if (ArrayBuffer.isView(A)) {
      if ((a = A.byteLength) === e.byteLength) for (; a-- && A[a] === e[a];);
      return a === -1;
    }
    if (!y || typeof A == "object") {
      a = 0;
      for (y in A)
        if (
          (has.call(A, y) && ++a && !has.call(e, y)) ||
          !(y in e) ||
          !dequal(A[y], e[y])
        )
          return !1;
      return Object.keys(e).length === a;
    }
  }
  return A !== A && e !== e;
}
const DocumentContext = reactExports.createContext(null);
function Message({ children: A, type: e }) {
  return jsxRuntimeExports.jsx("div", {
    className: `react-pdf__message react-pdf__message--${e}`,
    children: A,
  });
}
const DEFAULT_LINK_REL = "noopener noreferrer nofollow";
class LinkService {
  constructor() {
    ((this.externalLinkEnabled = !0),
      (this.externalLinkRel = void 0),
      (this.externalLinkTarget = void 0),
      (this.isInPresentationMode = !1),
      (this.pdfDocument = void 0),
      (this.pdfViewer = void 0));
  }
  setDocument(e) {
    this.pdfDocument = e;
  }
  setViewer(e) {
    this.pdfViewer = e;
  }
  setExternalLinkRel(e) {
    this.externalLinkRel = e;
  }
  setExternalLinkTarget(e) {
    this.externalLinkTarget = e;
  }
  setHistory() {}
  get pagesCount() {
    return this.pdfDocument ? this.pdfDocument.numPages : 0;
  }
  get page() {
    return (invariant(this.pdfViewer), this.pdfViewer.currentPageNumber || 0);
  }
  set page(e) {
    (invariant(this.pdfViewer), (this.pdfViewer.currentPageNumber = e));
  }
  get rotation() {
    return 0;
  }
  set rotation(e) {}
  goToDestination(e) {
    return new Promise((y) => {
      (invariant(this.pdfDocument),
        invariant(e),
        typeof e == "string"
          ? this.pdfDocument.getDestination(e).then(y)
          : Array.isArray(e)
            ? y(e)
            : e.then(y));
    }).then((y) => {
      invariant(Array.isArray(y));
      const a = y[0];
      new Promise((p) => {
        (invariant(this.pdfDocument),
          a instanceof Object
            ? this.pdfDocument
                .getPageIndex(a)
                .then((k) => {
                  p(k);
                })
                .catch(() => {
                  invariant(!1);
                })
            : typeof a == "number"
              ? p(a)
              : invariant(!1));
      }).then((p) => {
        const k = p + 1;
        (invariant(this.pdfViewer),
          invariant(k >= 1 && k <= this.pagesCount),
          this.pdfViewer.scrollPageIntoView({
            dest: y,
            pageIndex: p,
            pageNumber: k,
          }));
      });
    });
  }
  navigateTo(e) {
    this.goToDestination(e);
  }
  goToPage(e) {
    const y = e - 1;
    (invariant(this.pdfViewer),
      invariant(e >= 1 && e <= this.pagesCount),
      this.pdfViewer.scrollPageIntoView({ pageIndex: y, pageNumber: e }));
  }
  addLinkAttributes(e, y, a) {
    ((e.href = y),
      (e.rel = this.externalLinkRel || DEFAULT_LINK_REL),
      (e.target = a ? "_blank" : this.externalLinkTarget || ""));
  }
  getDestinationHash() {
    return "#";
  }
  getAnchorUrl() {
    return "#";
  }
  setHash() {}
  executeNamedAction() {}
  cachePageRef() {}
  isPageVisible() {
    return !0;
  }
  isPageCached() {
    return !0;
  }
  executeSetOCGState() {}
}
const PasswordResponses = { NEED_PASSWORD: 1, INCORRECT_PASSWORD: 2 },
  isBrowser = typeof document < "u",
  isLocalFileSystem = isBrowser && window.location.protocol === "file:";
function isDefined(A) {
  return typeof A < "u";
}
function isProvided(A) {
  return isDefined(A) && A !== null;
}
function isString(A) {
  return typeof A == "string";
}
function isArrayBuffer(A) {
  return A instanceof ArrayBuffer;
}
function isBlob(A) {
  return (invariant(isBrowser), A instanceof Blob);
}
function isDataURI(A) {
  return isString(A) && /^data:/.test(A);
}
function dataURItoByteString(A) {
  invariant(isDataURI(A));
  const [e = "", y = ""] = A.split(",");
  return e.split(";").indexOf("base64") !== -1 ? atob(y) : unescape(y);
}
function getDevicePixelRatio() {
  return (isBrowser && window.devicePixelRatio) || 1;
}
const allowFileAccessFromFilesTip =
  "On Chromium based browsers, you can use --allow-file-access-from-files flag for debugging purposes.";
function displayCORSWarning() {
  warning(
    !isLocalFileSystem,
    `Loading PDF as base64 strings/URLs may not work on protocols other than HTTP/HTTPS. ${allowFileAccessFromFilesTip}`,
  );
}
function displayWorkerWarning() {
  warning(
    !isLocalFileSystem,
    `Loading PDF.js worker may not work on protocols other than HTTP/HTTPS. ${allowFileAccessFromFilesTip}`,
  );
}
function cancelRunningTask(A) {
  A && A.cancel && A.cancel();
}
function makePageCallback(A, e) {
  return (
    Object.defineProperty(A, "width", {
      get() {
        return this.view[2] * e;
      },
      configurable: !0,
    }),
    Object.defineProperty(A, "height", {
      get() {
        return this.view[3] * e;
      },
      configurable: !0,
    }),
    Object.defineProperty(A, "originalWidth", {
      get() {
        return this.view[2];
      },
      configurable: !0,
    }),
    Object.defineProperty(A, "originalHeight", {
      get() {
        return this.view[3];
      },
      configurable: !0,
    }),
    A
  );
}
function isCancelException(A) {
  return A.name === "RenderingCancelledException";
}
function loadFromFile(A) {
  return new Promise((e, y) => {
    const a = new FileReader();
    ((a.onload = () => {
      if (!a.result) return y(new Error("Error while reading a file."));
      e(a.result);
    }),
      (a.onerror = (p) => {
        if (!p.target) return y(new Error("Error while reading a file."));
        const { error: k } = p.target;
        if (!k) return y(new Error("Error while reading a file."));
        switch (k.code) {
          case k.NOT_FOUND_ERR:
            return y(new Error("Error while reading a file: File not found."));
          case k.SECURITY_ERR:
            return y(new Error("Error while reading a file: Security error."));
          case k.ABORT_ERR:
            return y(new Error("Error while reading a file: Aborted."));
          default:
            return y(new Error("Error while reading a file."));
        }
      }),
      a.readAsArrayBuffer(A));
  });
}
function reducer(A, e) {
  switch (e.type) {
    case "RESOLVE":
      return { value: e.value, error: void 0 };
    case "REJECT":
      return { value: !1, error: e.error };
    case "RESET":
      return { value: void 0, error: void 0 };
    default:
      return A;
  }
}
function useResolver() {
  return reactExports.useReducer(reducer, { value: void 0, error: void 0 });
}
var __awaiter = function (A, e, y, a) {
    function p(k) {
      return k instanceof y
        ? k
        : new y(function (T) {
            T(k);
          });
    }
    return new (y || (y = Promise))(function (k, T) {
      function j(t) {
        try {
          s(a.next(t));
        } catch (i) {
          T(i);
        }
      }
      function D(t) {
        try {
          s(a.throw(t));
        } catch (i) {
          T(i);
        }
      }
      function s(t) {
        t.done ? k(t.value) : p(t.value).then(j, D);
      }
      s((a = a.apply(A, e || [])).next());
    });
  },
  __rest$1 = function (A, e) {
    var y = {};
    for (var a in A)
      Object.prototype.hasOwnProperty.call(A, a) &&
        e.indexOf(a) < 0 &&
        (y[a] = A[a]);
    if (A != null && typeof Object.getOwnPropertySymbols == "function")
      for (var p = 0, a = Object.getOwnPropertySymbols(A); p < a.length; p++)
        e.indexOf(a[p]) < 0 &&
          Object.prototype.propertyIsEnumerable.call(A, a[p]) &&
          (y[a[p]] = A[a[p]]);
    return y;
  };
const { PDFDataRangeTransport } = pdfjs,
  defaultOnPassword = (A, e) => {
    switch (e) {
      case PasswordResponses.NEED_PASSWORD: {
        const y = prompt("Enter the password to open this PDF file.");
        A(y);
        break;
      }
      case PasswordResponses.INCORRECT_PASSWORD: {
        const y = prompt("Invalid password. Please try again.");
        A(y);
        break;
      }
    }
  };
function isParameterObject(A) {
  return (
    typeof A == "object" &&
    A !== null &&
    ("data" in A || "range" in A || "url" in A)
  );
}
const Document = reactExports.forwardRef(function A(e, y) {
  var {
      children: a,
      className: p,
      error: k = "Failed to load PDF file.",
      externalLinkRel: T,
      externalLinkTarget: j,
      file: D,
      inputRef: s,
      imageResourcesPath: t,
      loading: i = "Loading PDF…",
      noData: h = "No PDF file specified.",
      onItemClick: c,
      onLoadError: n,
      onLoadProgress: d,
      onLoadSuccess: m,
      onPassword: l = defaultOnPassword,
      onSourceError: w,
      onSourceSuccess: M,
      options: C,
      renderMode: g,
      rotate: E,
    } = e,
    U = __rest$1(e, [
      "children",
      "className",
      "error",
      "externalLinkRel",
      "externalLinkTarget",
      "file",
      "inputRef",
      "imageResourcesPath",
      "loading",
      "noData",
      "onItemClick",
      "onLoadError",
      "onLoadProgress",
      "onLoadSuccess",
      "onPassword",
      "onSourceError",
      "onSourceSuccess",
      "options",
      "renderMode",
      "rotate",
    ]);
  const [W, O] = useResolver(),
    { value: V, error: G } = W,
    [nt, Z] = useResolver(),
    { value: tt, error: rt } = nt,
    K = reactExports.useRef(new LinkService()),
    I = reactExports.useRef([]),
    _ = reactExports.useRef(void 0),
    u = reactExports.useRef(void 0);
  (D &&
    D !== _.current &&
    isParameterObject(D) &&
    (warning(
      !dequal(D, _.current),
      `File prop passed to <Document /> changed, but it's equal to previous one. This might result in unnecessary reloads. Consider memoizing the value passed to "file" prop.`,
    ),
    (_.current = D)),
    C &&
      C !== u.current &&
      (warning(
        !dequal(C, u.current),
        `Options prop passed to <Document /> changed, but it's equal to previous one. This might result in unnecessary reloads. Consider memoizing the value passed to "options" prop.`,
      ),
      (u.current = C)));
  const f = reactExports.useRef({
    scrollPageIntoView: (X) => {
      const { dest: J, pageNumber: Q, pageIndex: et = Q - 1 } = X;
      if (c) {
        c({ dest: J, pageIndex: et, pageNumber: Q });
        return;
      }
      const at = I.current[et];
      if (at) {
        at.scrollIntoView();
        return;
      }
      warning(
        !1,
        `An internal link leading to page ${Q} was clicked, but neither <Document> was provided with onItemClick nor it was able to find the page within itself. Either provide onItemClick to <Document> and handle navigating by yourself or ensure that all pages are rendered within <Document>.`,
      );
    },
  });
  reactExports.useImperativeHandle(
    y,
    () => ({ linkService: K, pages: I, viewer: f }),
    [],
  );
  function v() {
    M && M();
  }
  function F() {
    G && (warning(!1, G.toString()), w && w(G));
  }
  function L() {
    O({ type: "RESET" });
  }
  reactExports.useEffect(L, [D, O]);
  const N = reactExports.useCallback(
    () =>
      __awaiter(this, void 0, void 0, function* () {
        if (!D) return null;
        if (typeof D == "string")
          return isDataURI(D)
            ? { data: dataURItoByteString(D) }
            : (displayCORSWarning(), { url: D });
        if (D instanceof PDFDataRangeTransport) return { range: D };
        if (isArrayBuffer(D)) return { data: D };
        if (isBrowser && isBlob(D)) return { data: yield loadFromFile(D) };
        if (
          (invariant(typeof D == "object"),
          invariant(isParameterObject(D)),
          "url" in D && typeof D.url == "string")
        ) {
          if (isDataURI(D.url)) {
            const { url: X } = D,
              J = __rest$1(D, ["url"]),
              Q = dataURItoByteString(X);
            return Object.assign({ data: Q }, J);
          }
          displayCORSWarning();
        }
        return D;
      }),
    [D],
  );
  (reactExports.useEffect(() => {
    const X = makeCancellablePromise(N());
    return (
      X.promise
        .then((J) => {
          O({ type: "RESOLVE", value: J });
        })
        .catch((J) => {
          O({ type: "REJECT", error: J });
        }),
      () => {
        cancelRunningTask(X);
      }
    );
  }, [N, O]),
    reactExports.useEffect(() => {
      if (!(typeof V > "u")) {
        if (V === !1) {
          F();
          return;
        }
        v();
      }
    }, [V]));
  function R() {
    tt &&
      (m && m(tt),
      (I.current = new Array(tt.numPages)),
      K.current.setDocument(tt));
  }
  function o() {
    rt && (warning(!1, rt.toString()), n && n(rt));
  }
  function b() {
    Z({ type: "RESET" });
  }
  reactExports.useEffect(b, [Z, V]);
  function S() {
    if (!V) return;
    const X = Object.assign(Object.assign({}, C), { isEvalSupported: !1 }),
      J = Object.assign(Object.assign({}, V), X),
      Q = pdfjs.getDocument(J);
    (d && (Q.onProgress = d), l && (Q.onPassword = l));
    const et = Q;
    return (
      et.promise
        .then((at) => {
          Z({ type: "RESOLVE", value: at });
        })
        .catch((at) => {
          et.destroyed || Z({ type: "REJECT", error: at });
        }),
      () => {
        et.destroy();
      }
    );
  }
  (reactExports.useEffect(S, [C, Z, V]),
    reactExports.useEffect(() => {
      if (!(typeof tt > "u")) {
        if (tt === !1) {
          o();
          return;
        }
        R();
      }
    }, [tt]));
  function x() {
    (K.current.setViewer(f.current),
      K.current.setExternalLinkRel(T),
      K.current.setExternalLinkTarget(j));
  }
  reactExports.useEffect(x, [T, j]);
  function P(X, J) {
    I.current[X] = J;
  }
  function B(X) {
    delete I.current[X];
  }
  const H = reactExports.useMemo(
      () => ({
        imageResourcesPath: t,
        linkService: K.current,
        onItemClick: c,
        pdf: tt,
        registerPage: P,
        renderMode: g,
        rotate: E,
        unregisterPage: B,
      }),
      [t, c, tt, g, E],
    ),
    z = reactExports.useMemo(() => makeEventProps(U, () => tt), [U, tt]);
  function st() {
    return jsxRuntimeExports.jsx(DocumentContext.Provider, {
      value: H,
      children: a,
    });
  }
  function Y() {
    return D
      ? tt == null
        ? jsxRuntimeExports.jsx(Message, {
            type: "loading",
            children: typeof i == "function" ? i() : i,
          })
        : tt === !1
          ? jsxRuntimeExports.jsx(Message, {
              type: "error",
              children: typeof k == "function" ? k() : k,
            })
          : st()
      : jsxRuntimeExports.jsx(Message, {
          type: "no-data",
          children: typeof h == "function" ? h() : h,
        });
  }
  return jsxRuntimeExports.jsx(
    "div",
    Object.assign(
      {
        className: clsx("react-pdf__Document", p),
        ref: s,
        style: { "--scale-factor": "1" },
      },
      z,
      { children: Y() },
    ),
  );
});
function useDocumentContext() {
  return reactExports.useContext(DocumentContext);
}
function mergeRefs() {
  for (var A = [], e = 0; e < arguments.length; e++) A[e] = arguments[e];
  var y = A.filter(Boolean);
  if (y.length <= 1) {
    var a = y[0];
    return a || null;
  }
  return function (k) {
    y.forEach(function (T) {
      typeof T == "function" ? T(k) : T && (T.current = k);
    });
  };
}
const PageContext = reactExports.createContext(null),
  PDF_ROLE_TO_HTML_ROLE = {
    Document: null,
    DocumentFragment: null,
    Part: "group",
    Sect: "group",
    Div: "group",
    Aside: "note",
    NonStruct: "none",
    P: null,
    H: "heading",
    Title: null,
    FENote: "note",
    Sub: "group",
    Lbl: null,
    Span: null,
    Em: null,
    Strong: null,
    Link: "link",
    Annot: "note",
    Form: "form",
    Ruby: null,
    RB: null,
    RT: null,
    RP: null,
    Warichu: null,
    WT: null,
    WP: null,
    L: "list",
    LI: "listitem",
    LBody: null,
    Table: "table",
    TR: "row",
    TH: "columnheader",
    TD: "cell",
    THead: "columnheader",
    TBody: null,
    TFoot: null,
    Caption: null,
    Figure: "figure",
    Formula: null,
    Artifact: null,
  },
  HEADING_PATTERN = /^H(\d+)$/;
function isPdfRole(A) {
  return A in PDF_ROLE_TO_HTML_ROLE;
}
function isStructTreeNode(A) {
  return "children" in A;
}
function isStructTreeNodeWithOnlyContentChild(A) {
  return isStructTreeNode(A)
    ? A.children.length === 1 && 0 in A.children && "id" in A.children[0]
    : !1;
}
function getRoleAttributes(A) {
  const e = {};
  if (isStructTreeNode(A)) {
    const { role: y } = A,
      a = y.match(HEADING_PATTERN);
    if (a) ((e.role = "heading"), (e["aria-level"] = Number(a[1])));
    else if (isPdfRole(y)) {
      const p = PDF_ROLE_TO_HTML_ROLE[y];
      p && (e.role = p);
    }
  }
  return e;
}
function getBaseAttributes(A) {
  const e = {};
  if (isStructTreeNode(A)) {
    if (
      (A.alt !== void 0 && (e["aria-label"] = A.alt),
      A.lang !== void 0 && (e.lang = A.lang),
      isStructTreeNodeWithOnlyContentChild(A))
    ) {
      const [y] = A.children;
      if (y) {
        const a = getBaseAttributes(y);
        return Object.assign(Object.assign({}, e), a);
      }
    }
  } else "id" in A && (e["aria-owns"] = A.id);
  return e;
}
function getAttributes(A) {
  return A
    ? Object.assign(
        Object.assign({}, getRoleAttributes(A)),
        getBaseAttributes(A),
      )
    : null;
}
function StructTreeItem({ className: A, node: e }) {
  const y = reactExports.useMemo(() => getAttributes(e), [e]),
    a = reactExports.useMemo(
      () =>
        !isStructTreeNode(e) || isStructTreeNodeWithOnlyContentChild(e)
          ? null
          : e.children.map((p, k) =>
              jsxRuntimeExports.jsx(StructTreeItem, { node: p }, k),
            ),
      [e],
    );
  return jsxRuntimeExports.jsx(
    "span",
    Object.assign({ className: A }, y, { children: a }),
  );
}
function usePageContext() {
  return reactExports.useContext(PageContext);
}
function StructTree() {
  const A = usePageContext();
  invariant(A);
  const { onGetStructTreeError: e, onGetStructTreeSuccess: y } = A,
    [a, p] = useResolver(),
    { value: k, error: T } = a,
    { customTextRenderer: j, page: D } = A;
  function s() {
    k && y && y(k);
  }
  function t() {
    T && (warning(!1, T.toString()), e && e(T));
  }
  function i() {
    p({ type: "RESET" });
  }
  reactExports.useEffect(i, [p, D]);
  function h() {
    if (j || !D) return;
    const c = makeCancellablePromise(D.getStructTree()),
      n = c;
    return (
      c.promise
        .then((d) => {
          p({ type: "RESOLVE", value: d });
        })
        .catch((d) => {
          p({ type: "REJECT", error: d });
        }),
      () => cancelRunningTask(n)
    );
  }
  return (
    reactExports.useEffect(h, [j, D, p]),
    reactExports.useEffect(() => {
      if (k !== void 0) {
        if (k === !1) {
          t();
          return;
        }
        s();
      }
    }, [k]),
    k
      ? jsxRuntimeExports.jsx(StructTreeItem, {
          className: "react-pdf__Page__structTree structTree",
          node: k,
        })
      : null
  );
}
const ANNOTATION_MODE = pdfjs.AnnotationMode;
function PageCanvas(A) {
  const e = usePageContext();
  invariant(e);
  const y = Object.assign(Object.assign({}, e), A),
    {
      _className: a,
      canvasBackground: p,
      devicePixelRatio: k = getDevicePixelRatio(),
      onRenderError: T,
      onRenderSuccess: j,
      page: D,
      renderForms: s,
      renderTextLayer: t,
      rotate: i,
      scale: h,
    } = y,
    { canvasRef: c } = A;
  invariant(D);
  const n = reactExports.useRef(null);
  function d() {
    D && j && j(makePageCallback(D, h));
  }
  function m(g) {
    isCancelException(g) || (warning(!1, g.toString()), T && T(g));
  }
  const l = reactExports.useMemo(
      () => D.getViewport({ scale: h * k, rotation: i }),
      [k, D, i, h],
    ),
    w = reactExports.useMemo(
      () => D.getViewport({ scale: h, rotation: i }),
      [D, i, h],
    );
  function M() {
    if (!D) return;
    D.cleanup();
    const { current: g } = n;
    if (!g) return;
    ((g.width = l.width),
      (g.height = l.height),
      (g.style.width = `${Math.floor(w.width)}px`),
      (g.style.height = `${Math.floor(w.height)}px`),
      (g.style.visibility = "hidden"));
    const E = {
      annotationMode: s ? ANNOTATION_MODE.ENABLE_FORMS : ANNOTATION_MODE.ENABLE,
      canvasContext: g.getContext("2d", { alpha: !1 }),
      viewport: l,
    };
    p && (E.background = p);
    const U = D.render(E),
      W = U;
    return (
      U.promise
        .then(() => {
          ((g.style.visibility = ""), d());
        })
        .catch(m),
      () => cancelRunningTask(W)
    );
  }
  reactExports.useEffect(M, [p, n, k, D, s, l, w]);
  const C = reactExports.useCallback(() => {
    const { current: g } = n;
    g && ((g.width = 0), (g.height = 0));
  }, [n]);
  return (
    reactExports.useEffect(() => C, [C]),
    jsxRuntimeExports.jsx("canvas", {
      className: `${a}__canvas`,
      dir: "ltr",
      ref: mergeRefs(c, n),
      style: { display: "block", userSelect: "none" },
      children: t ? jsxRuntimeExports.jsx(StructTree, {}) : null,
    })
  );
}
function PageSVG() {
  const A = usePageContext();
  invariant(A);
  const {
    _className: e,
    onRenderSuccess: y,
    onRenderError: a,
    page: p,
    rotate: k,
    scale: T,
  } = A;
  invariant(p);
  const [j, D] = useResolver(),
    { value: s, error: t } = j;
  function i() {
    p && y && y(makePageCallback(p, T));
  }
  function h() {
    t && (isCancelException(t) || (warning(!1, t.toString()), a && a(t)));
  }
  const c = reactExports.useMemo(
    () => p.getViewport({ scale: T, rotation: k }),
    [p, k, T],
  );
  function n() {
    D({ type: "RESET" });
  }
  reactExports.useEffect(n, [p, D, c]);
  function d() {
    if (!p) return;
    const M = makeCancellablePromise(p.getOperatorList());
    return (
      M.promise
        .then((C) => {
          new pdfjs.SVGGraphics(p.commonObjs, p.objs)
            .getSVG(C, c)
            .then((E) => {
              if (!(E instanceof SVGElement))
                throw new Error("getSVG returned unexpected result.");
              D({ type: "RESOLVE", value: E });
            })
            .catch((E) => {
              D({ type: "REJECT", error: E });
            });
        })
        .catch((C) => {
          D({ type: "REJECT", error: C });
        }),
      () => cancelRunningTask(M)
    );
  }
  (reactExports.useEffect(d, [p, D, c]),
    reactExports.useEffect(() => {
      if (s !== void 0) {
        if (s === !1) {
          h();
          return;
        }
        i();
      }
    }, [s]));
  function m(M) {
    if (!M || !s) return;
    M.firstElementChild || M.appendChild(s);
    const { width: C, height: g } = c;
    (s.setAttribute("width", `${C}`), s.setAttribute("height", `${g}`));
  }
  const { width: l, height: w } = c;
  return jsxRuntimeExports.jsx("div", {
    className: `${e}__svg`,
    ref: (M) => m(M),
    style: {
      display: "block",
      backgroundColor: "white",
      overflow: "hidden",
      width: l,
      height: w,
      userSelect: "none",
    },
  });
}
function isTextItem(A) {
  return "str" in A;
}
function TextLayer() {
  const A = usePageContext();
  invariant(A);
  const {
    customTextRenderer: e,
    onGetTextError: y,
    onGetTextSuccess: a,
    onRenderTextLayerError: p,
    onRenderTextLayerSuccess: k,
    page: T,
    pageIndex: j,
    pageNumber: D,
    rotate: s,
    scale: t,
  } = A;
  invariant(T);
  const [i, h] = useResolver(),
    { value: c, error: n } = i,
    d = reactExports.useRef(null),
    m = reactExports.useRef(void 0);
  warning(
    parseInt(
      window
        .getComputedStyle(document.body)
        .getPropertyValue("--react-pdf-text-layer"),
      10,
    ) === 1,
    "TextLayer styles not found. Read more: https://github.com/wojtekmaj/react-pdf#support-for-text-layer",
  );
  function l() {
    c && a && a(c);
  }
  function w() {
    n && (warning(!1, n.toString()), y && y(n));
  }
  function M() {
    h({ type: "RESET" });
  }
  reactExports.useEffect(M, [T, h]);
  function C() {
    if (!T) return;
    const G = makeCancellablePromise(T.getTextContent()),
      nt = G;
    return (
      G.promise
        .then((Z) => {
          h({ type: "RESOLVE", value: Z });
        })
        .catch((Z) => {
          h({ type: "REJECT", error: Z });
        }),
      () => cancelRunningTask(nt)
    );
  }
  (reactExports.useEffect(C, [T, h]),
    reactExports.useEffect(() => {
      if (c !== void 0) {
        if (c === !1) {
          w();
          return;
        }
        l();
      }
    }, [c]));
  const g = reactExports.useCallback(() => {
      k && k();
    }, [k]),
    E = reactExports.useCallback(
      (G) => {
        (warning(!1, G.toString()), p && p(G));
      },
      [p],
    );
  function U() {
    const G = m.current;
    G && G.classList.add("active");
  }
  function W() {
    const G = m.current;
    G && G.classList.remove("active");
  }
  const O = reactExports.useMemo(
    () => T.getViewport({ scale: t, rotation: s }),
    [T, s, t],
  );
  function V() {
    if (!T || !c) return;
    const { current: G } = d;
    if (!G) return;
    G.innerHTML = "";
    const nt = T.streamTextContent({ includeMarkedContent: !0 }),
      Z = { container: G, textContentSource: nt, viewport: O },
      tt = pdfjs.renderTextLayer(Z),
      rt = tt;
    return (
      tt.promise
        .then(() => {
          const K = document.createElement("div");
          ((K.className = "endOfContent"), G.append(K), (m.current = K));
          const I = G.querySelectorAll('[role="presentation"]');
          if (e) {
            let _ = 0;
            c.items.forEach((u, f) => {
              if (!isTextItem(u)) return;
              const v = I[_];
              if (!v) return;
              const F = e(
                Object.assign({ pageIndex: j, pageNumber: D, itemIndex: f }, u),
              );
              ((v.innerHTML = F), (_ += u.str && u.hasEOL ? 2 : 1));
            });
          }
          g();
        })
        .catch(E),
      () => cancelRunningTask(rt)
    );
  }
  return (
    reactExports.useLayoutEffect(V, [e, E, g, T, j, D, c, O]),
    jsxRuntimeExports.jsx("div", {
      className: clsx("react-pdf__Page__textContent", "textLayer"),
      onMouseUp: W,
      onMouseDown: U,
      ref: d,
    })
  );
}
function AnnotationLayer() {
  const A = useDocumentContext(),
    e = usePageContext();
  invariant(e);
  const y = Object.assign(Object.assign({}, A), e),
    {
      imageResourcesPath: a,
      linkService: p,
      onGetAnnotationsError: k,
      onGetAnnotationsSuccess: T,
      onRenderAnnotationLayerError: j,
      onRenderAnnotationLayerSuccess: D,
      page: s,
      pdf: t,
      renderForms: i,
      rotate: h,
      scale: c = 1,
    } = y;
  (invariant(t), invariant(s), invariant(p));
  const [n, d] = useResolver(),
    { value: m, error: l } = n,
    w = reactExports.useRef(null);
  warning(
    parseInt(
      window
        .getComputedStyle(document.body)
        .getPropertyValue("--react-pdf-annotation-layer"),
      10,
    ) === 1,
    "AnnotationLayer styles not found. Read more: https://github.com/wojtekmaj/react-pdf#support-for-annotations",
  );
  function M() {
    m && T && T(m);
  }
  function C() {
    l && (warning(!1, l.toString()), k && k(l));
  }
  function g() {
    d({ type: "RESET" });
  }
  reactExports.useEffect(g, [d, s]);
  function E() {
    if (!s) return;
    const G = makeCancellablePromise(s.getAnnotations()),
      nt = G;
    return (
      G.promise
        .then((Z) => {
          d({ type: "RESOLVE", value: Z });
        })
        .catch((Z) => {
          d({ type: "REJECT", error: Z });
        }),
      () => {
        cancelRunningTask(nt);
      }
    );
  }
  (reactExports.useEffect(E, [d, s, i]),
    reactExports.useEffect(() => {
      if (m !== void 0) {
        if (m === !1) {
          C();
          return;
        }
        M();
      }
    }, [m]));
  function U() {
    D && D();
  }
  function W(G) {
    (warning(!1, `${G}`), j && j(G));
  }
  const O = reactExports.useMemo(
    () => s.getViewport({ scale: c, rotation: h }),
    [s, h, c],
  );
  function V() {
    if (!t || !s || !p || !m) return;
    const { current: G } = w;
    if (!G) return;
    const nt = O.clone({ dontFlip: !0 }),
      Z = {
        accessibilityManager: null,
        annotationCanvasMap: null,
        div: G,
        l10n: null,
        page: s,
        viewport: nt,
      },
      tt = {
        annotations: m,
        annotationStorage: t.annotationStorage,
        div: G,
        downloadManager: null,
        imageResourcesPath: a,
        linkService: p,
        page: s,
        renderForms: i,
        viewport: nt,
      };
    G.innerHTML = "";
    try {
      (new pdfjs.AnnotationLayer(Z).render(tt), U());
    } catch (rt) {
      W(rt);
    }
    return () => {};
  }
  return (
    reactExports.useEffect(V, [m, a, p, s, i, O]),
    jsxRuntimeExports.jsx("div", {
      className: clsx("react-pdf__Page__annotations", "annotationLayer"),
      ref: w,
    })
  );
}
var __rest = function (A, e) {
  var y = {};
  for (var a in A)
    Object.prototype.hasOwnProperty.call(A, a) &&
      e.indexOf(a) < 0 &&
      (y[a] = A[a]);
  if (A != null && typeof Object.getOwnPropertySymbols == "function")
    for (var p = 0, a = Object.getOwnPropertySymbols(A); p < a.length; p++)
      e.indexOf(a[p]) < 0 &&
        Object.prototype.propertyIsEnumerable.call(A, a[p]) &&
        (y[a[p]] = A[a[p]]);
  return y;
};
const defaultScale = 1;
function Page(A) {
  const e = useDocumentContext(),
    y = Object.assign(Object.assign({}, e), A),
    {
      _className: a = "react-pdf__Page",
      _enableRegisterUnregisterPage: p = !0,
      canvasBackground: k,
      canvasRef: T,
      children: j,
      className: D,
      customRenderer: s,
      customTextRenderer: t,
      devicePixelRatio: i,
      error: h = "Failed to load the page.",
      height: c,
      inputRef: n,
      loading: d = "Loading page…",
      noData: m = "No page specified.",
      onGetAnnotationsError: l,
      onGetAnnotationsSuccess: w,
      onGetStructTreeError: M,
      onGetStructTreeSuccess: C,
      onGetTextError: g,
      onGetTextSuccess: E,
      onLoadError: U,
      onLoadSuccess: W,
      onRenderAnnotationLayerError: O,
      onRenderAnnotationLayerSuccess: V,
      onRenderError: G,
      onRenderSuccess: nt,
      onRenderTextLayerError: Z,
      onRenderTextLayerSuccess: tt,
      pageIndex: rt,
      pageNumber: K,
      pdf: I,
      registerPage: _,
      renderAnnotationLayer: u = !0,
      renderForms: f = !1,
      renderMode: v = "canvas",
      renderTextLayer: F = !0,
      rotate: L,
      scale: N = defaultScale,
      unregisterPage: R,
      width: o,
    } = y,
    b = __rest(y, [
      "_className",
      "_enableRegisterUnregisterPage",
      "canvasBackground",
      "canvasRef",
      "children",
      "className",
      "customRenderer",
      "customTextRenderer",
      "devicePixelRatio",
      "error",
      "height",
      "inputRef",
      "loading",
      "noData",
      "onGetAnnotationsError",
      "onGetAnnotationsSuccess",
      "onGetStructTreeError",
      "onGetStructTreeSuccess",
      "onGetTextError",
      "onGetTextSuccess",
      "onLoadError",
      "onLoadSuccess",
      "onRenderAnnotationLayerError",
      "onRenderAnnotationLayerSuccess",
      "onRenderError",
      "onRenderSuccess",
      "onRenderTextLayerError",
      "onRenderTextLayerSuccess",
      "pageIndex",
      "pageNumber",
      "pdf",
      "registerPage",
      "renderAnnotationLayer",
      "renderForms",
      "renderMode",
      "renderTextLayer",
      "rotate",
      "scale",
      "unregisterPage",
      "width",
    ]),
    [S, x] = useResolver(),
    { value: P, error: B } = S,
    H = reactExports.useRef(null);
  invariant(I);
  const z = isProvided(K) ? K - 1 : (rt ?? null),
    st = K ?? (isProvided(rt) ? rt + 1 : null),
    Y = L ?? (P ? P.rotate : null),
    X = reactExports.useMemo(() => {
      if (!P) return null;
      let Et = 1;
      const Mt = N ?? defaultScale;
      if (o || c) {
        const Tt = P.getViewport({ scale: 1, rotation: Y });
        o ? (Et = o / Tt.width) : c && (Et = c / Tt.height);
      }
      return Mt * Et;
    }, [c, P, Y, N, o]);
  function J() {
    return () => {
      isProvided(z) && p && R && R(z);
    };
  }
  reactExports.useEffect(J, [p, I, z, R]);
  function Q() {
    if (W) {
      if (!P || !X) return;
      W(makePageCallback(P, X));
    }
    if (p && _) {
      if (!isProvided(z) || !H.current) return;
      _(z, H.current);
    }
  }
  function et() {
    B && (warning(!1, B.toString()), U && U(B));
  }
  function at() {
    x({ type: "RESET" });
  }
  reactExports.useEffect(at, [x, I, z]);
  function lt() {
    if (!I || !st) return;
    const Et = makeCancellablePromise(I.getPage(st)),
      Mt = Et;
    return (
      Et.promise
        .then((Tt) => {
          x({ type: "RESOLVE", value: Tt });
        })
        .catch((Tt) => {
          x({ type: "REJECT", error: Tt });
        }),
      () => cancelRunningTask(Mt)
    );
  }
  (reactExports.useEffect(lt, [x, I, z, st, _]),
    reactExports.useEffect(() => {
      if (P !== void 0) {
        if (P === !1) {
          et();
          return;
        }
        Q();
      }
    }, [P, X]));
  const ct = reactExports.useMemo(
      () =>
        P && isProvided(z) && st && isProvided(Y) && isProvided(X)
          ? {
              _className: a,
              canvasBackground: k,
              customTextRenderer: t,
              devicePixelRatio: i,
              onGetAnnotationsError: l,
              onGetAnnotationsSuccess: w,
              onGetStructTreeError: M,
              onGetStructTreeSuccess: C,
              onGetTextError: g,
              onGetTextSuccess: E,
              onRenderAnnotationLayerError: O,
              onRenderAnnotationLayerSuccess: V,
              onRenderError: G,
              onRenderSuccess: nt,
              onRenderTextLayerError: Z,
              onRenderTextLayerSuccess: tt,
              page: P,
              pageIndex: z,
              pageNumber: st,
              renderForms: f,
              renderTextLayer: F,
              rotate: Y,
              scale: X,
            }
          : null,
      [a, k, t, i, l, w, M, C, g, E, O, V, G, nt, Z, tt, P, z, st, f, F, Y, X],
    ),
    ht = reactExports.useMemo(
      () => makeEventProps(b, () => P && (X ? makePageCallback(P, X) : void 0)),
      [b, P, X],
    ),
    dt = `${z}@${X}/${Y}`,
    ut = `${z}/${Y}`;
  function At() {
    switch (v) {
      case "custom":
        return (invariant(s), jsxRuntimeExports.jsx(s, {}, `${dt}_custom`));
      case "none":
        return null;
      case "svg":
        return jsxRuntimeExports.jsx(PageSVG, {}, `${ut}_svg`);
      default:
        return jsxRuntimeExports.jsx(
          PageCanvas,
          { canvasRef: T },
          `${dt}_canvas`,
        );
    }
  }
  function gt() {
    return F ? jsxRuntimeExports.jsx(TextLayer, {}, `${dt}_text`) : null;
  }
  function wt() {
    return u
      ? jsxRuntimeExports.jsx(AnnotationLayer, {}, `${dt}_annotations`)
      : null;
  }
  function mt() {
    return jsxRuntimeExports.jsxs(PageContext.Provider, {
      value: ct,
      children: [At(), gt(), wt(), j],
    });
  }
  function St() {
    return st
      ? I === null || P === void 0 || P === null
        ? jsxRuntimeExports.jsx(Message, {
            type: "loading",
            children: typeof d == "function" ? d() : d,
          })
        : I === !1 || P === !1
          ? jsxRuntimeExports.jsx(Message, {
              type: "error",
              children: typeof h == "function" ? h() : h,
            })
          : mt()
      : jsxRuntimeExports.jsx(Message, {
          type: "no-data",
          children: typeof m == "function" ? m() : m,
        });
  }
  return jsxRuntimeExports.jsx(
    "div",
    Object.assign(
      {
        className: clsx(a, D),
        "data-page-number": st,
        ref: mergeRefs(n, H),
        style: {
          "--scale-factor": `${X}`,
          backgroundColor: k || "white",
          position: "relative",
          minWidth: "min-content",
          minHeight: "min-content",
        },
      },
      ht,
      { children: St() },
    ),
  );
}
displayWorkerWarning();
pdfjs.GlobalWorkerOptions.workerSrc = "pdf.worker.js";
pdfjs.GlobalWorkerOptions.workerSrc = new URL(
  "" + new URL("pdf.worker.min-DKQKFyKK.js", import.meta.url).href,
  import.meta.url,
).toString();
const PDF = ({ docProps: A, pageProps: e }) =>
  jsxRuntimeExports.jsx(Document, {
    ...A,
    "data-sentry-element": "Document",
    "data-sentry-component": "PDF",
    "data-sentry-source-file": "PDF.tsx",
    children: jsxRuntimeExports.jsx(Page, {
      ...e,
      "data-sentry-element": "Page",
      "data-sentry-source-file": "PDF.tsx",
    }),
  });
export { PDF as default };
//# sourceMappingURL=PDF-CktwDke5.js.map
