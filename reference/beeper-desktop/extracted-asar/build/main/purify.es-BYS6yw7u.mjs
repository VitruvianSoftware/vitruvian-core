(function () {
  try {
    var a =
      typeof window < "u"
        ? window
        : typeof global < "u"
          ? global
          : typeof globalThis < "u"
            ? globalThis
            : typeof self < "u"
              ? self
              : {};
    a.SENTRY_RELEASE = { id: "4.3.209" };
    var o = new a.Error().stack;
    o &&
      ((a._sentryDebugIds = a._sentryDebugIds || {}),
      (a._sentryDebugIds[o] = "24f73af7-64e2-4549-a7b0-4a659b12511d"),
      (a._sentryDebugIdIdentifier =
        "sentry-dbid-24f73af7-64e2-4549-a7b0-4a659b12511d"));
  } catch {}
})();
const {
  entries: pt,
  setPrototypeOf: at,
  isFrozen: Wt,
  getPrototypeOf: Gt,
  getOwnPropertyDescriptor: Bt,
} = Object;
let { freeze: A, seal: y, create: dt } = Object,
  { apply: Ne, construct: Ie } = typeof Reflect < "u" && Reflect;
A ||
  (A = function (o) {
    return o;
  });
y ||
  (y = function (o) {
    return o;
  });
Ne ||
  (Ne = function (o, l, s) {
    return o.apply(l, s);
  });
Ie ||
  (Ie = function (o, l) {
    return new o(...l);
  });
const ae = R(Array.prototype.forEach),
  rt = R(Array.prototype.pop),
  V = R(Array.prototype.push),
  se = R(String.prototype.toLowerCase),
  ye = R(String.prototype.toString),
  st = R(String.prototype.match),
  $ = R(String.prototype.replace),
  Yt = R(String.prototype.indexOf),
  Xt = R(String.prototype.trim),
  L = R(Object.prototype.hasOwnProperty),
  h = R(RegExp.prototype.test),
  q = jt(TypeError);
function R(a) {
  return function (o) {
    for (
      var l = arguments.length, s = new Array(l > 1 ? l - 1 : 0), T = 1;
      T < l;
      T++
    )
      s[T - 1] = arguments[T];
    return Ne(a, o, s);
  };
}
function jt(a) {
  return function () {
    for (var o = arguments.length, l = new Array(o), s = 0; s < o; s++)
      l[s] = arguments[s];
    return Ie(a, l);
  };
}
function r(a, o) {
  let l = arguments.length > 2 && arguments[2] !== void 0 ? arguments[2] : se;
  at && at(a, null);
  let s = o.length;
  for (; s--;) {
    let T = o[s];
    if (typeof T == "string") {
      const N = l(T);
      N !== T && (Wt(o) || (o[s] = N), (T = N));
    }
    a[T] = !0;
  }
  return a;
}
function Vt(a) {
  for (let o = 0; o < a.length; o++) L(a, o) || (a[o] = null);
  return a;
}
function w(a) {
  const o = dt(null);
  for (const [l, s] of pt(a))
    L(a, l) &&
      (Array.isArray(s)
        ? (o[l] = Vt(s))
        : s && typeof s == "object" && s.constructor === Object
          ? (o[l] = w(s))
          : (o[l] = s));
  return o;
}
function K(a, o) {
  for (; a !== null;) {
    const s = Bt(a, o);
    if (s) {
      if (s.get) return R(s.get);
      if (typeof s.value == "function") return R(s.value);
    }
    a = Gt(a);
  }
  function l() {
    return null;
  }
  return l;
}
const lt = A([
    "a",
    "abbr",
    "acronym",
    "address",
    "area",
    "article",
    "aside",
    "audio",
    "b",
    "bdi",
    "bdo",
    "big",
    "blink",
    "blockquote",
    "body",
    "br",
    "button",
    "canvas",
    "caption",
    "center",
    "cite",
    "code",
    "col",
    "colgroup",
    "content",
    "data",
    "datalist",
    "dd",
    "decorator",
    "del",
    "details",
    "dfn",
    "dialog",
    "dir",
    "div",
    "dl",
    "dt",
    "element",
    "em",
    "fieldset",
    "figcaption",
    "figure",
    "font",
    "footer",
    "form",
    "h1",
    "h2",
    "h3",
    "h4",
    "h5",
    "h6",
    "head",
    "header",
    "hgroup",
    "hr",
    "html",
    "i",
    "img",
    "input",
    "ins",
    "kbd",
    "label",
    "legend",
    "li",
    "main",
    "map",
    "mark",
    "marquee",
    "menu",
    "menuitem",
    "meter",
    "nav",
    "nobr",
    "ol",
    "optgroup",
    "option",
    "output",
    "p",
    "picture",
    "pre",
    "progress",
    "q",
    "rp",
    "rt",
    "ruby",
    "s",
    "samp",
    "section",
    "select",
    "shadow",
    "small",
    "source",
    "spacer",
    "span",
    "strike",
    "strong",
    "style",
    "sub",
    "summary",
    "sup",
    "table",
    "tbody",
    "td",
    "template",
    "textarea",
    "tfoot",
    "th",
    "thead",
    "time",
    "tr",
    "track",
    "tt",
    "u",
    "ul",
    "var",
    "video",
    "wbr",
  ]),
  Le = A([
    "svg",
    "a",
    "altglyph",
    "altglyphdef",
    "altglyphitem",
    "animatecolor",
    "animatemotion",
    "animatetransform",
    "circle",
    "clippath",
    "defs",
    "desc",
    "ellipse",
    "filter",
    "font",
    "g",
    "glyph",
    "glyphref",
    "hkern",
    "image",
    "line",
    "lineargradient",
    "marker",
    "mask",
    "metadata",
    "mpath",
    "path",
    "pattern",
    "polygon",
    "polyline",
    "radialgradient",
    "rect",
    "stop",
    "style",
    "switch",
    "symbol",
    "text",
    "textpath",
    "title",
    "tref",
    "tspan",
    "view",
    "vkern",
  ]),
  Oe = A([
    "feBlend",
    "feColorMatrix",
    "feComponentTransfer",
    "feComposite",
    "feConvolveMatrix",
    "feDiffuseLighting",
    "feDisplacementMap",
    "feDistantLight",
    "feDropShadow",
    "feFlood",
    "feFuncA",
    "feFuncB",
    "feFuncG",
    "feFuncR",
    "feGaussianBlur",
    "feImage",
    "feMerge",
    "feMergeNode",
    "feMorphology",
    "feOffset",
    "fePointLight",
    "feSpecularLighting",
    "feSpotLight",
    "feTile",
    "feTurbulence",
  ]),
  $t = A([
    "animate",
    "color-profile",
    "cursor",
    "discard",
    "font-face",
    "font-face-format",
    "font-face-name",
    "font-face-src",
    "font-face-uri",
    "foreignobject",
    "hatch",
    "hatchpath",
    "mesh",
    "meshgradient",
    "meshpatch",
    "meshrow",
    "missing-glyph",
    "script",
    "set",
    "solidcolor",
    "unknown",
    "use",
  ]),
  be = A([
    "math",
    "menclose",
    "merror",
    "mfenced",
    "mfrac",
    "mglyph",
    "mi",
    "mlabeledtr",
    "mmultiscripts",
    "mn",
    "mo",
    "mover",
    "mpadded",
    "mphantom",
    "mroot",
    "mrow",
    "ms",
    "mspace",
    "msqrt",
    "mstyle",
    "msub",
    "msup",
    "msubsup",
    "mtable",
    "mtd",
    "mtext",
    "mtr",
    "munder",
    "munderover",
    "mprescripts",
  ]),
  qt = A([
    "maction",
    "maligngroup",
    "malignmark",
    "mlongdiv",
    "mscarries",
    "mscarry",
    "msgroup",
    "mstack",
    "msline",
    "msrow",
    "semantics",
    "annotation",
    "annotation-xml",
    "mprescripts",
    "none",
  ]),
  ct = A(["#text"]),
  ft = A([
    "accept",
    "action",
    "align",
    "alt",
    "autocapitalize",
    "autocomplete",
    "autopictureinpicture",
    "autoplay",
    "background",
    "bgcolor",
    "border",
    "capture",
    "cellpadding",
    "cellspacing",
    "checked",
    "cite",
    "class",
    "clear",
    "color",
    "cols",
    "colspan",
    "controls",
    "controlslist",
    "coords",
    "crossorigin",
    "datetime",
    "decoding",
    "default",
    "dir",
    "disabled",
    "disablepictureinpicture",
    "disableremoteplayback",
    "download",
    "draggable",
    "enctype",
    "enterkeyhint",
    "face",
    "for",
    "headers",
    "height",
    "hidden",
    "high",
    "href",
    "hreflang",
    "id",
    "inputmode",
    "integrity",
    "ismap",
    "kind",
    "label",
    "lang",
    "list",
    "loading",
    "loop",
    "low",
    "max",
    "maxlength",
    "media",
    "method",
    "min",
    "minlength",
    "multiple",
    "muted",
    "name",
    "nonce",
    "noshade",
    "novalidate",
    "nowrap",
    "open",
    "optimum",
    "pattern",
    "placeholder",
    "playsinline",
    "popover",
    "popovertarget",
    "popovertargetaction",
    "poster",
    "preload",
    "pubdate",
    "radiogroup",
    "readonly",
    "rel",
    "required",
    "rev",
    "reversed",
    "role",
    "rows",
    "rowspan",
    "spellcheck",
    "scope",
    "selected",
    "shape",
    "size",
    "sizes",
    "span",
    "srclang",
    "start",
    "src",
    "srcset",
    "step",
    "style",
    "summary",
    "tabindex",
    "title",
    "translate",
    "type",
    "usemap",
    "valign",
    "value",
    "width",
    "wrap",
    "xmlns",
    "slot",
  ]),
  De = A([
    "accent-height",
    "accumulate",
    "additive",
    "alignment-baseline",
    "ascent",
    "attributename",
    "attributetype",
    "azimuth",
    "basefrequency",
    "baseline-shift",
    "begin",
    "bias",
    "by",
    "class",
    "clip",
    "clippathunits",
    "clip-path",
    "clip-rule",
    "color",
    "color-interpolation",
    "color-interpolation-filters",
    "color-profile",
    "color-rendering",
    "cx",
    "cy",
    "d",
    "dx",
    "dy",
    "diffuseconstant",
    "direction",
    "display",
    "divisor",
    "dur",
    "edgemode",
    "elevation",
    "end",
    "fill",
    "fill-opacity",
    "fill-rule",
    "filter",
    "filterunits",
    "flood-color",
    "flood-opacity",
    "font-family",
    "font-size",
    "font-size-adjust",
    "font-stretch",
    "font-style",
    "font-variant",
    "font-weight",
    "fx",
    "fy",
    "g1",
    "g2",
    "glyph-name",
    "glyphref",
    "gradientunits",
    "gradienttransform",
    "height",
    "href",
    "id",
    "image-rendering",
    "in",
    "in2",
    "k",
    "k1",
    "k2",
    "k3",
    "k4",
    "kerning",
    "keypoints",
    "keysplines",
    "keytimes",
    "lang",
    "lengthadjust",
    "letter-spacing",
    "kernelmatrix",
    "kernelunitlength",
    "lighting-color",
    "local",
    "marker-end",
    "marker-mid",
    "marker-start",
    "markerheight",
    "markerunits",
    "markerwidth",
    "maskcontentunits",
    "maskunits",
    "max",
    "mask",
    "media",
    "method",
    "mode",
    "min",
    "name",
    "numoctaves",
    "offset",
    "operator",
    "opacity",
    "order",
    "orient",
    "orientation",
    "origin",
    "overflow",
    "paint-order",
    "path",
    "pathlength",
    "patterncontentunits",
    "patterntransform",
    "patternunits",
    "points",
    "preservealpha",
    "preserveaspectratio",
    "primitiveunits",
    "r",
    "rx",
    "ry",
    "radius",
    "refx",
    "refy",
    "repeatcount",
    "repeatdur",
    "restart",
    "result",
    "rotate",
    "scale",
    "seed",
    "shape-rendering",
    "specularconstant",
    "specularexponent",
    "spreadmethod",
    "startoffset",
    "stddeviation",
    "stitchtiles",
    "stop-color",
    "stop-opacity",
    "stroke-dasharray",
    "stroke-dashoffset",
    "stroke-linecap",
    "stroke-linejoin",
    "stroke-miterlimit",
    "stroke-opacity",
    "stroke",
    "stroke-width",
    "style",
    "surfacescale",
    "systemlanguage",
    "tabindex",
    "targetx",
    "targety",
    "transform",
    "transform-origin",
    "text-anchor",
    "text-decoration",
    "text-rendering",
    "textlength",
    "type",
    "u1",
    "u2",
    "unicode",
    "values",
    "viewbox",
    "visibility",
    "version",
    "vert-adv-y",
    "vert-origin-x",
    "vert-origin-y",
    "width",
    "word-spacing",
    "wrap",
    "writing-mode",
    "xchannelselector",
    "ychannelselector",
    "x",
    "x1",
    "x2",
    "xmlns",
    "y",
    "y1",
    "y2",
    "z",
    "zoomandpan",
  ]),
  ut = A([
    "accent",
    "accentunder",
    "align",
    "bevelled",
    "close",
    "columnsalign",
    "columnlines",
    "columnspan",
    "denomalign",
    "depth",
    "dir",
    "display",
    "displaystyle",
    "encoding",
    "fence",
    "frame",
    "height",
    "href",
    "id",
    "largeop",
    "length",
    "linethickness",
    "lspace",
    "lquote",
    "mathbackground",
    "mathcolor",
    "mathsize",
    "mathvariant",
    "maxsize",
    "minsize",
    "movablelimits",
    "notation",
    "numalign",
    "open",
    "rowalign",
    "rowlines",
    "rowspacing",
    "rowspan",
    "rspace",
    "rquote",
    "scriptlevel",
    "scriptminsize",
    "scriptsizemultiplier",
    "selection",
    "separator",
    "separators",
    "stretchy",
    "subscriptshift",
    "supscriptshift",
    "symmetric",
    "voffset",
    "width",
    "xmlns",
  ]),
  re = A(["xlink:href", "xml:id", "xlink:title", "xml:space", "xmlns:xlink"]),
  Kt = y(/\{\{[\w\W]*|[\w\W]*\}\}/gm),
  Zt = y(/<%[\w\W]*|[\w\W]*%>/gm),
  Jt = y(/\${[\w\W]*}/gm),
  Qt = y(/^data-[\-\w.\u00B7-\uFFFF]/),
  en = y(/^aria-[\-\w]+$/),
  Tt = y(
    /^(?:(?:(?:f|ht)tps?|mailto|tel|callto|sms|cid|xmpp):|[^a-z]|[a-z+.\-]+(?:[^a-z+.\-:]|$))/i,
  ),
  tn = y(/^(?:\w+script|data):/i),
  nn = y(/[\u0000-\u0020\u00A0\u1680\u180E\u2000-\u2029\u205F\u3000]/g),
  _t = y(/^html$/i),
  on = y(/^[a-z][.\w]*(-[.\w]+)+$/i);
var mt = Object.freeze({
  __proto__: null,
  MUSTACHE_EXPR: Kt,
  ERB_EXPR: Zt,
  TMPLIT_EXPR: Jt,
  DATA_ATTR: Qt,
  ARIA_ATTR: en,
  IS_ALLOWED_URI: Tt,
  IS_SCRIPT_OR_DATA: tn,
  ATTR_WHITESPACE: nn,
  DOCTYPE_NAME: _t,
  CUSTOM_ELEMENT: on,
});
const Z = {
    element: 1,
    text: 3,
    progressingInstruction: 7,
    comment: 8,
    document: 9,
  },
  an = function () {
    return typeof window > "u" ? null : window;
  },
  rn = function (o, l) {
    if (typeof o != "object" || typeof o.createPolicy != "function")
      return null;
    let s = null;
    const T = "data-tt-policy-suffix";
    l && l.hasAttribute(T) && (s = l.getAttribute(T));
    const N = "dompurify" + (s ? "#" + s : "");
    try {
      return o.createPolicy(N, {
        createHTML(x) {
          return x;
        },
        createScriptURL(x) {
          return x;
        },
      });
    } catch {
      return (
        console.warn("TrustedTypes policy " + N + " could not be created."),
        null
      );
    }
  };
function Et() {
  let a = arguments.length > 0 && arguments[0] !== void 0 ? arguments[0] : an();
  const o = (i) => Et(i);
  if (
    ((o.version = "3.1.6"),
    (o.removed = []),
    !a || !a.document || a.document.nodeType !== Z.document)
  )
    return ((o.isSupported = !1), o);
  let { document: l } = a;
  const s = l,
    T = s.currentScript,
    {
      DocumentFragment: N,
      HTMLTemplateElement: x,
      Node: le,
      Element: Ce,
      NodeFilter: z,
      NamedNodeMap: gt = a.NamedNodeMap || a.MozNamedAttrMap,
      HTMLFormElement: ht,
      DOMParser: At,
      trustedTypes: J,
    } = a,
    W = Ce.prototype,
    St = K(W, "cloneNode"),
    Rt = K(W, "remove"),
    yt = K(W, "nextSibling"),
    Lt = K(W, "childNodes"),
    Q = K(W, "parentNode");
  if (typeof x == "function") {
    const i = l.createElement("template");
    i.content && i.content.ownerDocument && (l = i.content.ownerDocument);
  }
  let E,
    G = "";
  const {
      implementation: ce,
      createNodeIterator: Ot,
      createDocumentFragment: bt,
      getElementsByTagName: Dt,
    } = l,
    { importNode: Nt } = s;
  let O = {};
  o.isSupported =
    typeof pt == "function" &&
    typeof Q == "function" &&
    ce &&
    ce.createHTMLDocument !== void 0;
  const {
    MUSTACHE_EXPR: fe,
    ERB_EXPR: ue,
    TMPLIT_EXPR: me,
    DATA_ATTR: It,
    ARIA_ATTR: Ct,
    IS_SCRIPT_OR_DATA: Mt,
    ATTR_WHITESPACE: Me,
    CUSTOM_ELEMENT: wt,
  } = mt;
  let { IS_ALLOWED_URI: we } = mt,
    u = null;
  const xe = r({}, [...lt, ...Le, ...Oe, ...be, ...ct]);
  let m = null;
  const Pe = r({}, [...ft, ...De, ...ut, ...re]);
  let f = Object.seal(
      dt(null, {
        tagNameCheck: {
          writable: !0,
          configurable: !1,
          enumerable: !0,
          value: null,
        },
        attributeNameCheck: {
          writable: !0,
          configurable: !1,
          enumerable: !0,
          value: null,
        },
        allowCustomizedBuiltInElements: {
          writable: !0,
          configurable: !1,
          enumerable: !0,
          value: !1,
        },
      }),
    ),
    B = null,
    pe = null,
    ve = !0,
    de = !0,
    ke = !1,
    Ue = !0,
    P = !1,
    Te = !0,
    M = !1,
    _e = !1,
    Ee = !1,
    v = !1,
    ee = !1,
    te = !1,
    Fe = !0,
    He = !1;
  const xt = "user-content-";
  let ge = !0,
    Y = !1,
    k = {},
    U = null;
  const ze = r({}, [
    "annotation-xml",
    "audio",
    "colgroup",
    "desc",
    "foreignobject",
    "head",
    "iframe",
    "math",
    "mi",
    "mn",
    "mo",
    "ms",
    "mtext",
    "noembed",
    "noframes",
    "noscript",
    "plaintext",
    "script",
    "style",
    "svg",
    "template",
    "thead",
    "title",
    "video",
    "xmp",
  ]);
  let We = null;
  const Ge = r({}, ["audio", "video", "img", "source", "image", "track"]);
  let he = null;
  const Be = r({}, [
      "alt",
      "class",
      "for",
      "id",
      "label",
      "name",
      "pattern",
      "placeholder",
      "role",
      "summary",
      "title",
      "value",
      "style",
      "xmlns",
    ]),
    ne = "http://www.w3.org/1998/Math/MathML",
    oe = "http://www.w3.org/2000/svg",
    I = "http://www.w3.org/1999/xhtml";
  let F = I,
    Ae = !1,
    Se = null;
  const Pt = r({}, [ne, oe, I], ye);
  let X = null;
  const vt = ["application/xhtml+xml", "text/html"],
    kt = "text/html";
  let p = null,
    H = null;
  const Ut = l.createElement("form"),
    Ye = function (e) {
      return e instanceof RegExp || e instanceof Function;
    },
    Re = function () {
      let e =
        arguments.length > 0 && arguments[0] !== void 0 ? arguments[0] : {};
      if (!(H && H === e)) {
        if (
          ((!e || typeof e != "object") && (e = {}),
          (e = w(e)),
          (X =
            vt.indexOf(e.PARSER_MEDIA_TYPE) === -1 ? kt : e.PARSER_MEDIA_TYPE),
          (p = X === "application/xhtml+xml" ? ye : se),
          (u = L(e, "ALLOWED_TAGS") ? r({}, e.ALLOWED_TAGS, p) : xe),
          (m = L(e, "ALLOWED_ATTR") ? r({}, e.ALLOWED_ATTR, p) : Pe),
          (Se = L(e, "ALLOWED_NAMESPACES")
            ? r({}, e.ALLOWED_NAMESPACES, ye)
            : Pt),
          (he = L(e, "ADD_URI_SAFE_ATTR")
            ? r(w(Be), e.ADD_URI_SAFE_ATTR, p)
            : Be),
          (We = L(e, "ADD_DATA_URI_TAGS")
            ? r(w(Ge), e.ADD_DATA_URI_TAGS, p)
            : Ge),
          (U = L(e, "FORBID_CONTENTS") ? r({}, e.FORBID_CONTENTS, p) : ze),
          (B = L(e, "FORBID_TAGS") ? r({}, e.FORBID_TAGS, p) : {}),
          (pe = L(e, "FORBID_ATTR") ? r({}, e.FORBID_ATTR, p) : {}),
          (k = L(e, "USE_PROFILES") ? e.USE_PROFILES : !1),
          (ve = e.ALLOW_ARIA_ATTR !== !1),
          (de = e.ALLOW_DATA_ATTR !== !1),
          (ke = e.ALLOW_UNKNOWN_PROTOCOLS || !1),
          (Ue = e.ALLOW_SELF_CLOSE_IN_ATTR !== !1),
          (P = e.SAFE_FOR_TEMPLATES || !1),
          (Te = e.SAFE_FOR_XML !== !1),
          (M = e.WHOLE_DOCUMENT || !1),
          (v = e.RETURN_DOM || !1),
          (ee = e.RETURN_DOM_FRAGMENT || !1),
          (te = e.RETURN_TRUSTED_TYPE || !1),
          (Ee = e.FORCE_BODY || !1),
          (Fe = e.SANITIZE_DOM !== !1),
          (He = e.SANITIZE_NAMED_PROPS || !1),
          (ge = e.KEEP_CONTENT !== !1),
          (Y = e.IN_PLACE || !1),
          (we = e.ALLOWED_URI_REGEXP || Tt),
          (F = e.NAMESPACE || I),
          (f = e.CUSTOM_ELEMENT_HANDLING || {}),
          e.CUSTOM_ELEMENT_HANDLING &&
            Ye(e.CUSTOM_ELEMENT_HANDLING.tagNameCheck) &&
            (f.tagNameCheck = e.CUSTOM_ELEMENT_HANDLING.tagNameCheck),
          e.CUSTOM_ELEMENT_HANDLING &&
            Ye(e.CUSTOM_ELEMENT_HANDLING.attributeNameCheck) &&
            (f.attributeNameCheck =
              e.CUSTOM_ELEMENT_HANDLING.attributeNameCheck),
          e.CUSTOM_ELEMENT_HANDLING &&
            typeof e.CUSTOM_ELEMENT_HANDLING.allowCustomizedBuiltInElements ==
              "boolean" &&
            (f.allowCustomizedBuiltInElements =
              e.CUSTOM_ELEMENT_HANDLING.allowCustomizedBuiltInElements),
          P && (de = !1),
          ee && (v = !0),
          k &&
            ((u = r({}, ct)),
            (m = []),
            k.html === !0 && (r(u, lt), r(m, ft)),
            k.svg === !0 && (r(u, Le), r(m, De), r(m, re)),
            k.svgFilters === !0 && (r(u, Oe), r(m, De), r(m, re)),
            k.mathMl === !0 && (r(u, be), r(m, ut), r(m, re))),
          e.ADD_TAGS && (u === xe && (u = w(u)), r(u, e.ADD_TAGS, p)),
          e.ADD_ATTR && (m === Pe && (m = w(m)), r(m, e.ADD_ATTR, p)),
          e.ADD_URI_SAFE_ATTR && r(he, e.ADD_URI_SAFE_ATTR, p),
          e.FORBID_CONTENTS &&
            (U === ze && (U = w(U)), r(U, e.FORBID_CONTENTS, p)),
          ge && (u["#text"] = !0),
          M && r(u, ["html", "head", "body"]),
          u.table && (r(u, ["tbody"]), delete B.tbody),
          e.TRUSTED_TYPES_POLICY)
        ) {
          if (typeof e.TRUSTED_TYPES_POLICY.createHTML != "function")
            throw q(
              'TRUSTED_TYPES_POLICY configuration option must provide a "createHTML" hook.',
            );
          if (typeof e.TRUSTED_TYPES_POLICY.createScriptURL != "function")
            throw q(
              'TRUSTED_TYPES_POLICY configuration option must provide a "createScriptURL" hook.',
            );
          ((E = e.TRUSTED_TYPES_POLICY), (G = E.createHTML("")));
        } else
          (E === void 0 && (E = rn(J, T)),
            E !== null && typeof G == "string" && (G = E.createHTML("")));
        (A && A(e), (H = e));
      }
    },
    Xe = r({}, ["mi", "mo", "mn", "ms", "mtext"]),
    je = r({}, ["foreignobject", "annotation-xml"]),
    Ft = r({}, ["title", "style", "font", "a", "script"]),
    Ve = r({}, [...Le, ...Oe, ...$t]),
    $e = r({}, [...be, ...qt]),
    Ht = function (e) {
      let t = Q(e);
      (!t || !t.tagName) && (t = { namespaceURI: F, tagName: "template" });
      const n = se(e.tagName),
        c = se(t.tagName);
      return Se[e.namespaceURI]
        ? e.namespaceURI === oe
          ? t.namespaceURI === I
            ? n === "svg"
            : t.namespaceURI === ne
              ? n === "svg" && (c === "annotation-xml" || Xe[c])
              : !!Ve[n]
          : e.namespaceURI === ne
            ? t.namespaceURI === I
              ? n === "math"
              : t.namespaceURI === oe
                ? n === "math" && je[c]
                : !!$e[n]
            : e.namespaceURI === I
              ? (t.namespaceURI === oe && !je[c]) ||
                (t.namespaceURI === ne && !Xe[c])
                ? !1
                : !$e[n] && (Ft[n] || !Ve[n])
              : !!(X === "application/xhtml+xml" && Se[e.namespaceURI])
        : !1;
    },
    b = function (e) {
      V(o.removed, { element: e });
      try {
        Q(e).removeChild(e);
      } catch {
        Rt(e);
      }
    },
    ie = function (e, t) {
      try {
        V(o.removed, { attribute: t.getAttributeNode(e), from: t });
      } catch {
        V(o.removed, { attribute: null, from: t });
      }
      if ((t.removeAttribute(e), e === "is" && !m[e]))
        if (v || ee)
          try {
            b(t);
          } catch {}
        else
          try {
            t.setAttribute(e, "");
          } catch {}
    },
    qe = function (e) {
      let t = null,
        n = null;
      if (Ee) e = "<remove></remove>" + e;
      else {
        const d = st(e, /^[\r\n\t ]+/);
        n = d && d[0];
      }
      X === "application/xhtml+xml" &&
        F === I &&
        (e =
          '<html xmlns="http://www.w3.org/1999/xhtml"><head></head><body>' +
          e +
          "</body></html>");
      const c = E ? E.createHTML(e) : e;
      if (F === I)
        try {
          t = new At().parseFromString(c, X);
        } catch {}
      if (!t || !t.documentElement) {
        t = ce.createDocument(F, "template", null);
        try {
          t.documentElement.innerHTML = Ae ? G : c;
        } catch {}
      }
      const _ = t.body || t.documentElement;
      return (
        e && n && _.insertBefore(l.createTextNode(n), _.childNodes[0] || null),
        F === I ? Dt.call(t, M ? "html" : "body")[0] : M ? t.documentElement : _
      );
    },
    Ke = function (e) {
      return Ot.call(
        e.ownerDocument || e,
        e,
        z.SHOW_ELEMENT |
          z.SHOW_COMMENT |
          z.SHOW_TEXT |
          z.SHOW_PROCESSING_INSTRUCTION |
          z.SHOW_CDATA_SECTION,
        null,
      );
    },
    Ze = function (e) {
      return (
        e instanceof ht &&
        (typeof e.nodeName != "string" ||
          typeof e.textContent != "string" ||
          typeof e.removeChild != "function" ||
          !(e.attributes instanceof gt) ||
          typeof e.removeAttribute != "function" ||
          typeof e.setAttribute != "function" ||
          typeof e.namespaceURI != "string" ||
          typeof e.insertBefore != "function" ||
          typeof e.hasChildNodes != "function")
      );
    },
    Je = function (e) {
      return typeof le == "function" && e instanceof le;
    },
    C = function (e, t, n) {
      O[e] &&
        ae(O[e], (c) => {
          c.call(o, t, n, H);
        });
    },
    Qe = function (e) {
      let t = null;
      if ((C("beforeSanitizeElements", e, null), Ze(e))) return (b(e), !0);
      const n = p(e.nodeName);
      if (
        (C("uponSanitizeElement", e, { tagName: n, allowedTags: u }),
        (e.hasChildNodes() &&
          !Je(e.firstElementChild) &&
          h(/<[/\w]/g, e.innerHTML) &&
          h(/<[/\w]/g, e.textContent)) ||
          e.nodeType === Z.progressingInstruction ||
          (Te && e.nodeType === Z.comment && h(/<[/\w]/g, e.data)))
      )
        return (b(e), !0);
      if (!u[n] || B[n]) {
        if (
          !B[n] &&
          tt(n) &&
          ((f.tagNameCheck instanceof RegExp && h(f.tagNameCheck, n)) ||
            (f.tagNameCheck instanceof Function && f.tagNameCheck(n)))
        )
          return !1;
        if (ge && !U[n]) {
          const c = Q(e) || e.parentNode,
            _ = Lt(e) || e.childNodes;
          if (_ && c) {
            const d = _.length;
            for (let S = d - 1; S >= 0; --S) {
              const D = St(_[S], !0);
              ((D.__removalCount = (e.__removalCount || 0) + 1),
                c.insertBefore(D, yt(e)));
            }
          }
        }
        return (b(e), !0);
      }
      return (e instanceof Ce && !Ht(e)) ||
        ((n === "noscript" || n === "noembed" || n === "noframes") &&
          h(/<\/no(script|embed|frames)/i, e.innerHTML))
        ? (b(e), !0)
        : (P &&
            e.nodeType === Z.text &&
            ((t = e.textContent),
            ae([fe, ue, me], (c) => {
              t = $(t, c, " ");
            }),
            e.textContent !== t &&
              (V(o.removed, { element: e.cloneNode() }), (e.textContent = t))),
          C("afterSanitizeElements", e, null),
          !1);
    },
    et = function (e, t, n) {
      if (Fe && (t === "id" || t === "name") && (n in l || n in Ut)) return !1;
      if (!(de && !pe[t] && h(It, t))) {
        if (!(ve && h(Ct, t))) {
          if (!m[t] || pe[t]) {
            if (!(
              (tt(e) &&
                ((f.tagNameCheck instanceof RegExp && h(f.tagNameCheck, e)) ||
                  (f.tagNameCheck instanceof Function && f.tagNameCheck(e))) &&
                ((f.attributeNameCheck instanceof RegExp &&
                  h(f.attributeNameCheck, t)) ||
                  (f.attributeNameCheck instanceof Function &&
                    f.attributeNameCheck(t)))) ||
              (t === "is" &&
                f.allowCustomizedBuiltInElements &&
                ((f.tagNameCheck instanceof RegExp && h(f.tagNameCheck, n)) ||
                  (f.tagNameCheck instanceof Function && f.tagNameCheck(n))))
            ))
              return !1;
          } else if (!he[t]) {
            if (!h(we, $(n, Me, ""))) {
              if (!(
                (t === "src" || t === "xlink:href" || t === "href") &&
                e !== "script" &&
                Yt(n, "data:") === 0 &&
                We[e]
              )) {
                if (!(ke && !h(Mt, $(n, Me, "")))) {
                  if (n) return !1;
                }
              }
            }
          }
        }
      }
      return !0;
    },
    tt = function (e) {
      return e !== "annotation-xml" && st(e, wt);
    },
    nt = function (e) {
      C("beforeSanitizeAttributes", e, null);
      const { attributes: t } = e;
      if (!t) return;
      const n = {
        attrName: "",
        attrValue: "",
        keepAttr: !0,
        allowedAttributes: m,
      };
      let c = t.length;
      for (; c--;) {
        const _ = t[c],
          { name: d, namespaceURI: S, value: D } = _,
          j = p(d);
        let g = d === "value" ? D : Xt(D);
        if (
          ((n.attrName = j),
          (n.attrValue = g),
          (n.keepAttr = !0),
          (n.forceKeepAttr = void 0),
          C("uponSanitizeAttribute", e, n),
          (g = n.attrValue),
          Te && h(/((--!?|])>)|<\/(style|title)/i, g))
        ) {
          ie(d, e);
          continue;
        }
        if (n.forceKeepAttr || (ie(d, e), !n.keepAttr)) continue;
        if (!Ue && h(/\/>/i, g)) {
          ie(d, e);
          continue;
        }
        P &&
          ae([fe, ue, me], (it) => {
            g = $(g, it, " ");
          });
        const ot = p(e.nodeName);
        if (et(ot, j, g)) {
          if (
            (He && (j === "id" || j === "name") && (ie(d, e), (g = xt + g)),
            E &&
              typeof J == "object" &&
              typeof J.getAttributeType == "function" &&
              !S)
          )
            switch (J.getAttributeType(ot, j)) {
              case "TrustedHTML": {
                g = E.createHTML(g);
                break;
              }
              case "TrustedScriptURL": {
                g = E.createScriptURL(g);
                break;
              }
            }
          try {
            (S ? e.setAttributeNS(S, d, g) : e.setAttribute(d, g),
              Ze(e) ? b(e) : rt(o.removed));
          } catch {}
        }
      }
      C("afterSanitizeAttributes", e, null);
    },
    zt = function i(e) {
      let t = null;
      const n = Ke(e);
      for (C("beforeSanitizeShadowDOM", e, null); (t = n.nextNode());)
        (C("uponSanitizeShadowNode", t, null),
          !Qe(t) && (t.content instanceof N && i(t.content), nt(t)));
      C("afterSanitizeShadowDOM", e, null);
    };
  return (
    (o.sanitize = function (i) {
      let e =
          arguments.length > 1 && arguments[1] !== void 0 ? arguments[1] : {},
        t = null,
        n = null,
        c = null,
        _ = null;
      if (((Ae = !i), Ae && (i = "<!-->"), typeof i != "string" && !Je(i)))
        if (typeof i.toString == "function") {
          if (((i = i.toString()), typeof i != "string"))
            throw q("dirty is not a string, aborting");
        } else throw q("toString is not a function");
      if (!o.isSupported) return i;
      if (
        (_e || Re(e), (o.removed = []), typeof i == "string" && (Y = !1), Y)
      ) {
        if (i.nodeName) {
          const D = p(i.nodeName);
          if (!u[D] || B[D])
            throw q("root node is forbidden and cannot be sanitized in-place");
        }
      } else if (i instanceof le)
        ((t = qe("<!---->")),
          (n = t.ownerDocument.importNode(i, !0)),
          (n.nodeType === Z.element && n.nodeName === "BODY") ||
          n.nodeName === "HTML"
            ? (t = n)
            : t.appendChild(n));
      else {
        if (!v && !P && !M && i.indexOf("<") === -1)
          return E && te ? E.createHTML(i) : i;
        if (((t = qe(i)), !t)) return v ? null : te ? G : "";
      }
      t && Ee && b(t.firstChild);
      const d = Ke(Y ? i : t);
      for (; (c = d.nextNode());)
        Qe(c) || (c.content instanceof N && zt(c.content), nt(c));
      if (Y) return i;
      if (v) {
        if (ee)
          for (_ = bt.call(t.ownerDocument); t.firstChild;)
            _.appendChild(t.firstChild);
        else _ = t;
        return (
          (m.shadowroot || m.shadowrootmode) && (_ = Nt.call(s, _, !0)),
          _
        );
      }
      let S = M ? t.outerHTML : t.innerHTML;
      return (
        M &&
          u["!doctype"] &&
          t.ownerDocument &&
          t.ownerDocument.doctype &&
          t.ownerDocument.doctype.name &&
          h(_t, t.ownerDocument.doctype.name) &&
          (S =
            "<!DOCTYPE " +
            t.ownerDocument.doctype.name +
            `>
` +
            S),
        P &&
          ae([fe, ue, me], (D) => {
            S = $(S, D, " ");
          }),
        E && te ? E.createHTML(S) : S
      );
    }),
    (o.setConfig = function () {
      let i =
        arguments.length > 0 && arguments[0] !== void 0 ? arguments[0] : {};
      (Re(i), (_e = !0));
    }),
    (o.clearConfig = function () {
      ((H = null), (_e = !1));
    }),
    (o.isValidAttribute = function (i, e, t) {
      H || Re({});
      const n = p(i),
        c = p(e);
      return et(n, c, t);
    }),
    (o.addHook = function (i, e) {
      typeof e == "function" && ((O[i] = O[i] || []), V(O[i], e));
    }),
    (o.removeHook = function (i) {
      if (O[i]) return rt(O[i]);
    }),
    (o.removeHooks = function (i) {
      O[i] && (O[i] = []);
    }),
    (o.removeAllHooks = function () {
      O = {};
    }),
    o
  );
}
var sn = Et();
export { sn as default };
//# sourceMappingURL=purify.es-BYS6yw7u.mjs.map
