import { aa as Nt } from "./sentry-common-BxRELKId.js";
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
      (e._sentryDebugIds[t] = "2b69a3b2-0d4b-4b7e-8ed4-e94fcb4b54c5"),
      (e._sentryDebugIdIdentifier =
        "sentry-dbid-2b69a3b2-0d4b-4b7e-8ed4-e94fcb4b54c5"));
  } catch {}
})();
let Oc = { one: {}, two: {}, three: {}, four: {} },
  Ic = { one: {}, two: {}, three: {} },
  Ec = {},
  Hc = [];
const ti = { methods: Oc, model: Ic, compute: Ec, hooks: Hc },
  zc = (e) => Object.prototype.toString.call(e) === "[object Array]",
  Fc = {
    compute: function (e) {
      const { world: t } = this,
        n = t.compute;
      return (
        typeof e == "string" && n.hasOwnProperty(e)
          ? n[e](this)
          : zc(e)
            ? e.forEach((r) => {
                t.compute.hasOwnProperty(r)
                  ? n[r](this)
                  : console.warn("no compute:", e);
              })
            : typeof e == "function"
              ? e(this)
              : console.warn("no compute:", e),
        this
      );
    },
  },
  Vc = function (e) {
    return (
      this.fullPointer.forEach((n, r) => {
        let a = this.update([n]);
        e(a, r);
      }),
      this
    );
  },
  Gc = function (e, t) {
    let r = this.fullPointer.map((i, o) => {
      let s = this.update([i]),
        l = e(s, o);
      return l === void 0 ? this.none() : l;
    });
    if (r.length === 0) return t || this.update([]);
    if (
      r[0] !== void 0 &&
      (typeof r[0] == "string" ||
        (typeof r[0] == "object" && (r[0] === null || !r[0].isView)))
    )
      return r;
    let a = [];
    return (
      r.forEach((i) => {
        a = a.concat(i.fullPointer);
      }),
      this.toView(a)
    );
  },
  Sc = function (e) {
    let t = this.fullPointer;
    return (
      (t = t.filter((r, a) => {
        let i = this.update([r]);
        return e(i, a);
      })),
      this.update(t)
    );
  },
  Mc = function (e) {
    let n = this.fullPointer.find((r, a) => {
      let i = this.update([r]);
      return e(i, a);
    });
    return this.update([n]);
  },
  Bc = function (e) {
    return this.fullPointer.some((n, r) => {
      let a = this.update([n]);
      return e(a, r);
    });
  },
  Lc = function (e = 1) {
    let t = this.fullPointer,
      n = Math.floor(Math.random() * t.length);
    return (
      n + e > this.length && ((n = this.length - e), (n = n < 0 ? 0 : n)),
      (t = t.slice(n, n + e)),
      this.update(t)
    );
  },
  Wc = { forEach: Vc, map: Gc, filter: Sc, find: Mc, some: Bc, random: Lc },
  We = {
    termList: function () {
      return this.methods.one.termList(this.docs);
    },
    terms: function (e) {
      let t = this.match(".");
      return typeof e == "number" ? t.eq(e) : t;
    },
    groups: function (e) {
      if (e || e === 0) return this.update(this._groups[e] || []);
      let t = {};
      return (
        Object.keys(this._groups).forEach((n) => {
          t[n] = this.update(this._groups[n]);
        }),
        t
      );
    },
    eq: function (e) {
      let t = this.pointer;
      return (
        t || (t = this.docs.map((n, r) => [r])),
        t[e] ? this.update([t[e]]) : this.none()
      );
    },
    first: function () {
      return this.eq(0);
    },
    last: function () {
      let e = this.fullPointer.length - 1;
      return this.eq(e);
    },
    firstTerms: function () {
      return this.match("^.");
    },
    lastTerms: function () {
      return this.match(".$");
    },
    slice: function (e, t) {
      let n = this.pointer || this.docs.map((r, a) => [a]);
      return ((n = n.slice(e, t)), this.update(n));
    },
    all: function () {
      return this.update().toView();
    },
    fullSentences: function () {
      let e = this.fullPointer.map((t) => [t[0]]);
      return this.update(e).toView();
    },
    none: function () {
      return this.update([]);
    },
    isDoc: function (e) {
      if (!e || !e.isView) return !1;
      let t = this.fullPointer,
        n = e.fullPointer;
      return !t.length === n.length
        ? !1
        : t.every((r, a) =>
            n[a]
              ? r[0] === n[a][0] && r[1] === n[a][1] && r[2] === n[a][2]
              : !1,
          );
    },
    wordCount: function () {
      return this.docs.reduce(
        (e, t) => ((e += t.filter((n) => n.text !== "").length), e),
        0,
      );
    },
    isFull: function () {
      let e = this.pointer;
      if (!e) return !0;
      if (e.length === 0 || e[0][0] !== 0) return !1;
      let t = 0,
        n = 0;
      return (
        this.document.forEach((r) => (t += r.length)),
        this.docs.forEach((r) => (n += r.length)),
        t === n
      );
    },
    getNth: function (e) {
      return typeof e == "number"
        ? this.eq(e)
        : typeof e == "string"
          ? this.if(e)
          : this;
    },
  };
We.group = We.groups;
We.fullSentence = We.fullSentences;
We.sentence = We.fullSentences;
We.lastTerm = We.lastTerms;
We.firstTerm = We.firstTerms;
const ni = Object.assign({}, We, Fc, Wc);
ni.get = ni.eq;
class xt {
  constructor(t, n, r = {}) {
    ([
      ["document", t],
      ["world", ti],
      ["_groups", r],
      ["_cache", null],
      ["viewType", "View"],
    ].forEach((i) => {
      Object.defineProperty(this, i[0], { value: i[1], writable: !0 });
    }),
      (this.ptrs = n));
  }
  get docs() {
    let t = this.document;
    return (
      this.ptrs && (t = ti.methods.one.getDoc(this.ptrs, this.document)),
      t
    );
  }
  get pointer() {
    return this.ptrs;
  }
  get methods() {
    return this.world.methods;
  }
  get model() {
    return this.world.model;
  }
  get hooks() {
    return this.world.hooks;
  }
  get isView() {
    return !0;
  }
  get found() {
    return this.docs.length > 0;
  }
  get length() {
    return this.docs.length;
  }
  get fullPointer() {
    let { docs: t, ptrs: n, document: r } = this;
    return (n || t.map((i, o) => [o])).map((i) => {
      let [o, s, l, u, c] = i;
      return (
        (s = s || 0),
        (l = l || (r[o] || []).length),
        r[o] &&
          r[o][s] &&
          ((u = u || r[o][s].id), r[o][l - 1] && (c = c || r[o][l - 1].id)),
        [o, s, l, u, c]
      );
    });
  }
  update(t) {
    let n = new xt(this.document, t);
    if (this._cache && t && t.length > 0) {
      let r = [];
      (t.forEach((a, i) => {
        let [o, s, l] = a;
        a.length === 1
          ? (r[i] = this._cache[o])
          : s === 0 && this.document[o].length === l && (r[i] = this._cache[o]);
      }),
        r.length > 0 && (n._cache = r));
    }
    return ((n.world = this.world), n);
  }
  toView(t) {
    return new xt(this.document, t || this.pointer);
  }
  fromText(t) {
    const { methods: n } = this;
    let r = n.one.tokenize.fromString(t, this.world),
      a = new xt(r);
    return (
      (a.world = this.world),
      a.compute(["normal", "freeze", "lexicon"]),
      this.world.compute.preTagger && a.compute("preTagger"),
      a.compute("unfreeze"),
      a
    );
  }
  clone() {
    let t = this.document.slice(0);
    t = t.map((r) =>
      r.map((a) => ((a = Object.assign({}, a)), (a.tags = new Set(a.tags)), a)),
    );
    let n = this.update(this.pointer);
    return ((n.document = t), (n._cache = this._cache), n);
  }
}
Object.assign(xt.prototype, ni);
const qc = "14.14.0",
  fo = function (e) {
    return e && typeof e == "object" && !Array.isArray(e);
  };
function wu(e, t) {
  if (fo(t))
    for (const n in t)
      fo(t[n])
        ? (e[n] || Object.assign(e, { [n]: {} }), wu(e[n], t[n]))
        : Object.assign(e, { [n]: t[n] });
  return e;
}
function Kc(e, t) {
  for (const n in t) ((e[n] = e[n] || {}), Object.assign(e[n], t[n]));
  return e;
}
const Jc = function (e, t) {
    let n = e.two.models || {};
    Object.keys(t).forEach((r) => {
      (t[r].pastTense &&
        (n.toPast && (n.toPast.ex[r] = t[r].pastTense),
        n.fromPast && (n.fromPast.ex[t[r].pastTense] = r)),
        t[r].presentTense &&
          (n.toPresent && (n.toPresent.ex[r] = t[r].presentTense),
          n.fromPresent && (n.fromPresent.ex[t[r].presentTense] = r)),
        t[r].gerund &&
          (n.toGerund && (n.toGerund.ex[r] = t[r].gerund),
          n.fromGerund && (n.fromGerund.ex[t[r].gerund] = r)),
        t[r].comparative &&
          (n.toComparative && (n.toComparative.ex[r] = t[r].comparative),
          n.fromComparative && (n.fromComparative.ex[t[r].comparative] = r)),
        t[r].superlative &&
          (n.toSuperlative && (n.toSuperlative.ex[r] = t[r].superlative),
          n.fromSuperlative && (n.fromSuperlative.ex[t[r].superlative] = r)));
    });
  },
  _c = function (e, t, n, r) {
    const { methods: a, model: i, compute: o, hooks: s } = t;
    (e.methods && Kc(a, e.methods),
      e.model && wu(i, e.model),
      e.irregulars && Jc(i, e.irregulars),
      e.compute && Object.assign(o, e.compute),
      s && (t.hooks = s.concat(e.hooks || [])),
      e.api && e.api(n),
      e.lib && Object.keys(e.lib).forEach((l) => (r[l] = e.lib[l])),
      e.tags && r.addTags(e.tags),
      e.words && r.addWords(e.words),
      e.frozen && r.addWords(e.frozen, !0),
      e.mutate && e.mutate(t, r));
  };
var mo = {};
const Uc = function (e) {
    const t = typeof Nt > "u" || !mo ? self.env || {} : mo;
    return (
      (t.DEBUG_TAGS = e === "tagger" || e === !0 ? !0 : ""),
      (t.DEBUG_MATCH = e === "match" || e === !0 ? !0 : ""),
      (t.DEBUG_CHUNKS = e === "chunker" || e === !0 ? !0 : ""),
      this
    );
  },
  Rc = (e) => Object.prototype.toString.call(e) === "[object Object]",
  ri = function (e) {
    return Object.prototype.toString.call(e) === "[object Array]";
  },
  Yc = function (e) {
    return e.map((t) =>
      t.terms.map((n) => (ri(n.tags) && (n.tags = new Set(n.tags)), n)),
    );
  },
  Qc = function (e) {
    return e.map((t) =>
      t.map((n) => ({
        text: n,
        normal: n,
        pre: "",
        post: " ",
        tags: new Set(),
      })),
    );
  },
  ku = function (e, t, n) {
    const { methods: r } = n;
    let a = new t([]);
    if (((a.world = n), typeof e == "number" && (e = String(e)), !e)) return a;
    if (typeof e == "string") {
      let i = r.one.tokenize.fromString(e, n);
      return new t(i);
    }
    if (Rc(e) && e.isView) return new t(e.document, e.ptrs);
    if (ri(e)) {
      if (ri(e[0])) {
        let o = Qc(e);
        return new t(o);
      }
      let i = Yc(e);
      return new t(i);
    }
    return a;
  };
let Zr = Object.assign({}, ti);
const k = function (e, t) {
  t && k.addWords(t);
  let n = ku(e, xt, Zr);
  return (e && n.compute(Zr.hooks), n);
};
Object.defineProperty(k, "_world", { value: Zr, writable: !0 });
k.tokenize = function (e, t) {
  const { compute: n } = this._world;
  t && k.addWords(t);
  let r = ku(e, xt, Zr);
  return (
    n.contractions && r.compute(["alias", "normal", "machine", "contractions"]),
    r
  );
};
k.plugin = function (e) {
  return (_c(e, this._world, xt, this), this);
};
k.extend = k.plugin;
k.world = function () {
  return this._world;
};
k.model = function () {
  return this._world.model;
};
k.methods = function () {
  return this._world.methods;
};
k.hooks = function () {
  return this._world.hooks;
};
k.verbose = Uc;
k.version = qc;
const Zc = function (e) {
    return e.map((n) => {
      let r = new Set();
      return (
        n.forEach((a) => {
          (a.normal !== "" && r.add(a.normal),
            a.switch && r.add(`%${a.switch}%`),
            a.implicit && r.add(a.implicit),
            a.machine && r.add(a.machine),
            a.root && r.add(a.root),
            a.alias && a.alias.forEach((o) => r.add(o)));
          let i = Array.from(a.tags);
          for (let o = 0; o < i.length; o += 1) r.add("#" + i[o]);
        }),
        r
      );
    });
  },
  Xc = { one: { cacheDoc: Zc } },
  eh = {
    cache: function () {
      return ((this._cache = this.methods.one.cacheDoc(this.document)), this);
    },
    uncache: function () {
      return ((this._cache = null), this);
    },
  },
  th = function (e) {
    Object.assign(e.prototype, eh);
  },
  nh = {
    cache: function (e) {
      e._cache = e.methods.one.cacheDoc(e.document);
    },
  },
  rh = { api: th, compute: nh, methods: Xc },
  ah = {
    toLowerCase: function () {
      return (
        this.termList().forEach((e) => {
          e.text = e.text.toLowerCase();
        }),
        this
      );
    },
    toUpperCase: function () {
      return (
        this.termList().forEach((e) => {
          e.text = e.text.toUpperCase();
        }),
        this
      );
    },
    toTitleCase: function () {
      return (
        this.termList().forEach((e) => {
          e.text = e.text.replace(/^ *[a-z\u00C0-\u00FF]/, (t) =>
            t.toUpperCase(),
          );
        }),
        this
      );
    },
    toCamelCase: function () {
      return (
        this.docs.forEach((e) => {
          e.forEach((t, n) => {
            (n !== 0 &&
              (t.text = t.text.replace(/^ *[a-z\u00C0-\u00FF]/, (r) =>
                r.toUpperCase(),
              )),
              n !== e.length - 1 && (t.post = ""));
          });
        }),
        this
      );
    },
  },
  po = (e) =>
    new RegExp("^\\p{Lu}[\\p{Ll}'’]", "u").test(e) ||
    new RegExp("^\\p{Lu}$", "u").test(e),
  ih = (e) => e.replace(new RegExp("^\\p{Ll}", "u"), (t) => t.toUpperCase()),
  oh = (e) => e.replace(new RegExp("^\\p{Lu}", "u"), (t) => t.toLowerCase()),
  Pu = (e, t, n) => {
    if ((n.forEach((r) => (r.dirty = !0)), e)) {
      let r = [t, 0].concat(n);
      Array.prototype.splice.apply(e, r);
    }
    return e;
  },
  bn = function (e) {
    const t = / $/,
      n = /[-–—]/;
    let r = e[e.length - 1];
    r && !t.test(r.post) && !n.test(r.post) && (r.post += " ");
  },
  go = (e, t, n) => {
    const r = /[-.?!,;:)–—'"]/g;
    let a = e[t - 1];
    if (!a) return;
    let i = a.post;
    if (r.test(i)) {
      let o = i.match(r).join(""),
        s = n[n.length - 1];
      ((s.post = o + s.post), (a.post = a.post.replace(r, "")));
    }
  },
  sh = function (e, t, n) {
    let r = e[t];
    if (t !== 0 || !po(r.text)) return;
    n[0].text = ih(n[0].text);
    let a = e[t];
    a.tags.has("ProperNoun") ||
      a.tags.has("Acronym") ||
      (po(a.text) && a.text.length > 1 && (a.text = oh(a.text)));
  },
  lh = function (e, t, n, r) {
    let [a, i, o] = t;
    (i === 0 || o === r[a].length ? bn(n) : (bn(n), bn([e[t[1]]])),
      sh(e, i, n),
      Pu(e, i, n));
  },
  uh = function (e, t, n, r) {
    let [a, , i] = t,
      o = (r[a] || []).length;
    (i < o
      ? (go(e, i, n), bn(n))
      : o === i &&
        (bn(e), go(e, i, n), r[a + 1] && (n[n.length - 1].post += " ")),
      Pu(e, t[2], n),
      (t[4] = n[n.length - 1].id));
  };
let Dn = 0;
const yo = (e) => (
    (e = e.length < 3 ? "0" + e : e),
    e.length < 3 ? "0" + e : e
  ),
  Au = function (e) {
    let [t, n] = e.index || [0, 0];
    ((Dn += 1),
      (Dn = Dn > 46655 ? 0 : Dn),
      (t = t > 46655 ? 0 : t),
      (n = n > 1294 ? 0 : n));
    let r = yo(Dn.toString(36));
    r += yo(t.toString(36));
    let a = n.toString(36);
    ((a = a.length < 2 ? "0" + a : a), (r += a));
    let i = parseInt(Math.random() * 36, 10);
    return ((r += i.toString(36)), e.normal + "|" + r.toUpperCase());
  },
  bo = function (e) {
    e.has("@hasContraction") &&
      typeof e.contractions == "function" &&
      e.grow("@hasContraction").contractions().expand();
  },
  vo = (e) => Object.prototype.toString.call(e) === "[object Array]",
  ch = function (e) {
    return ((e = e.map((t) => ((t.id = Au(t)), t))), e);
  },
  hh = function (e, t) {
    const { methods: n } = t;
    return typeof e == "string"
      ? n.one.tokenize.fromString(e, t)[0]
      : typeof e == "object" && e.isView
        ? e.clone().docs[0] || []
        : vo(e)
          ? vo(e[0])
            ? e[0]
            : e
          : [];
  },
  wo = function (e, t, n) {
    const { document: r, world: a } = t;
    t.uncache();
    let i = t.fullPointer,
      o = t.fullPointer;
    t.forEach((l, u) => {
      let c = l.fullPointer[0],
        [h] = c,
        f = r[h],
        $ = hh(e, a);
      $.length !== 0 &&
        (($ = ch($)),
        n
          ? (bo(t.update([c]).firstTerm()), lh(f, c, $, r))
          : (bo(t.update([c]).lastTerm()), uh(f, c, $, r)),
        r[h] && r[h][c[1]] && (c[3] = r[h][c[1]].id),
        (o[u] = c),
        (c[2] += $.length),
        (i[u] = c));
    });
    let s = t.toView(i);
    return (
      (t.ptrs = o),
      s.compute(["id", "index", "freeze", "lexicon"]),
      s.world.compute.preTagger && s.compute("preTagger"),
      s.compute("unfreeze"),
      s
    );
  },
  Ut = {
    insertAfter: function (e) {
      return wo(e, this, !1);
    },
    insertBefore: function (e) {
      return wo(e, this, !0);
    },
  };
Ut.append = Ut.insertAfter;
Ut.prepend = Ut.insertBefore;
Ut.insert = Ut.insertAfter;
const dh = /\$[0-9a-z]+/g,
  Wi = {},
  fh = function (e) {
    return e.replace(
      /\w\S*/g,
      (t) => t.charAt(0).toUpperCase() + t.substring(1).toLowerCase(),
    );
  },
  mh = function (e, t) {
    return (
      e.forEach((n) => {
        let r = t(n);
        n.replaceWith(r);
      }),
      e
    );
  },
  ph = function (e, t) {
    if (typeof e != "string") return e;
    let n = t.groups();
    return (
      (e = e.replace(dh, (r) => {
        let a = r.replace(/\$/, "");
        return n.hasOwnProperty(a) ? n[a].text() : r;
      })),
      e
    );
  };
Wi.replaceWith = function (e, t = {}) {
  let n = this.fullPointer,
    r = this;
  if ((this.uncache(), typeof e == "function")) return mh(r, e);
  let a = r.docs[0],
    i = t.possessives && a[a.length - 1].tags.has("Possessive");
  e = ph(e, r);
  let o = this.update(n);
  n = n.map((u) => u.slice(0, 3));
  let s = (o.docs[0] || []).map((u) => Array.from(u.tags));
  if (
    (typeof e == "string" && (e = this.fromText(e).compute("id")),
    r.insertAfter(e),
    o.has("@hasContraction") &&
      r.contractions &&
      r.grow("@hasContraction+").contractions().expand(),
    r.delete(o),
    i)
  ) {
    let u = r.docs[0],
      c = u[u.length - 1];
    c.tags.has("Possessive") ||
      ((c.text += "'s"), (c.normal += "'s"), c.tags.add("Possessive"));
  }
  let l = r.toView(n).compute(["index", "freeze", "lexicon"]);
  return (
    l.world.compute.preTagger && l.compute("preTagger"),
    l.compute("unfreeze"),
    t.tags &&
      l.terms().forEach((u, c) => {
        u.tagSafe(s[c]);
      }),
    t.case &&
      l.docs[0] &&
      l.docs[0][0] &&
      l.docs[0][0].index[1] === 0 &&
      (l.docs[0][0].text = fh(l.docs[0][0].text)),
    l
  );
};
Wi.replace = function (e, t, n) {
  if (e && !t) return this.replaceWith(e, n);
  let r = this.match(e);
  return r.found ? (this.soften(), r.replaceWith(t, n)) : this;
};
const gh = function (e, t) {
    let n = e.length - 1,
      r = e[n],
      a = e[n - t];
    a &&
      r &&
      ((a.post += r.post),
      (a.post = a.post.replace(/ +([.?!,;:])/, "$1")),
      (a.post = a.post.replace(/[,;:]+([.?!])/, "$1")));
  },
  yh = function (e, t) {
    t.forEach((n) => {
      let [r, a, i] = n,
        o = i - a;
      e[r] && (i === e[r].length && i > 1 && gh(e[r], o), e[r].splice(a, o));
    });
    for (let n = e.length - 1; n >= 0; n -= 1)
      if (e[n].length === 0 && (e.splice(n, 1), n === e.length && e[n - 1])) {
        let r = e[n - 1],
          a = r[r.length - 1];
        a && (a.post = a.post.trimEnd());
      }
    return e;
  },
  bh = function (e, t) {
    return (
      (e = e.map((n) => {
        let [r] = n;
        return (
          t[r] &&
            t[r].forEach((a) => {
              let i = a[2] - a[1];
              n[1] <= a[1] && n[2] >= a[2] && (n[2] -= i);
            }),
          n
        );
      })),
      e.forEach((n, r) => {
        if (n[1] === 0 && n[2] == 0)
          for (let a = r + 1; a < e.length; a += 1)
            ((e[a][0] -= 1), e[a][0] < 0 && (e[a][0] = 0));
      }),
      (e = e.filter((n) => n[2] - n[1] > 0)),
      (e = e.map((n) => ((n[3] = null), (n[4] = null), n))),
      e
    );
  },
  ai = {
    remove: function (e) {
      const { indexN: t } = this.methods.one.pointer;
      this.uncache();
      let n = this.all(),
        r = this;
      e && ((n = this), (r = this.match(e)));
      let a = !n.ptrs;
      r.has("@hasContraction") &&
        r.contractions &&
        r.grow("@hasContraction").contractions().expand();
      let i = n.fullPointer,
        o = r.fullPointer.reverse(),
        s = yh(this.document, o),
        l = t(o);
      return (
        (i = bh(i, l)),
        (n.ptrs = i),
        (n.document = s),
        n.compute("index"),
        a && (n.ptrs = void 0),
        e ? n.toView(i) : ((this.ptrs = []), n.none())
      );
    },
  };
ai.delete = ai.remove;
const Ln = {
  pre: function (e, t) {
    return e === void 0 && this.found
      ? this.docs[0][0].pre
      : (this.docs.forEach((n) => {
          let r = n[0];
          t === !0 ? (r.pre += e) : (r.pre = e);
        }),
        this);
  },
  post: function (e, t) {
    if (e === void 0) {
      let n = this.docs[this.docs.length - 1];
      return n[n.length - 1].post;
    }
    return (
      this.docs.forEach((n) => {
        let r = n[n.length - 1];
        t === !0 ? (r.post += e) : (r.post = e);
      }),
      this
    );
  },
  trim: function () {
    if (!this.found) return this;
    let e = this.docs,
      t = e[0][0];
    t.pre = t.pre.trimStart();
    let n = e[e.length - 1],
      r = n[n.length - 1];
    return ((r.post = r.post.trimEnd()), this);
  },
  hyphenate: function () {
    return (
      this.docs.forEach((e) => {
        e.forEach((t, n) => {
          (n !== 0 && (t.pre = ""), e[n + 1] && (t.post = "-"));
        });
      }),
      this
    );
  },
  dehyphenate: function () {
    const e = /[-–—]/;
    return (
      this.docs.forEach((t) => {
        t.forEach((n) => {
          e.test(n.post) && (n.post = " ");
        });
      }),
      this
    );
  },
  toQuotations: function (e, t) {
    return (
      (e = e || '"'),
      (t = t || '"'),
      this.docs.forEach((n) => {
        n[0].pre = e + n[0].pre;
        let r = n[n.length - 1];
        r.post = t + r.post;
      }),
      this
    );
  },
  toParentheses: function (e, t) {
    return (
      (e = e || "("),
      (t = t || ")"),
      this.docs.forEach((n) => {
        n[0].pre = e + n[0].pre;
        let r = n[n.length - 1];
        r.post = t + r.post;
      }),
      this
    );
  },
};
Ln.deHyphenate = Ln.dehyphenate;
Ln.toQuotation = Ln.toQuotations;
const vh = (e, t) => (e.normal < t.normal ? -1 : e.normal > t.normal ? 1 : 0),
  wh = (e, t) => {
    let n = e.normal.trim().length,
      r = t.normal.trim().length;
    return n < r ? 1 : n > r ? -1 : 0;
  },
  kh = (e, t) => (e.words < t.words ? 1 : e.words > t.words ? -1 : 0),
  Ph = (e, t) => (e[0] < t[0] ? 1 : e[0] > t[0] ? -1 : e[1] > t[1] ? 1 : -1),
  Ah = function (e) {
    let t = {};
    return (
      e.forEach((n) => {
        ((t[n.normal] = t[n.normal] || 0), (t[n.normal] += 1));
      }),
      e.sort((n, r) => {
        let a = t[n.normal],
          i = t[r.normal];
        return a < i ? 1 : a > i ? -1 : 0;
      }),
      e
    );
  },
  ua = { alpha: vh, length: wh, wordCount: kh, sequential: Ph, byFreq: Ah },
  xh = new Set([
    "index",
    "sequence",
    "seq",
    "sequential",
    "chron",
    "chronological",
  ]),
  Ch = new Set(["freq", "frequency", "topk", "repeats"]),
  Dh = new Set(["alpha", "alphabetical"]),
  $h = function (e, t) {
    let n = e.fullPointer;
    return (
      (n = n.sort(
        (r, a) => ((r = e.update([r])), (a = e.update([a])), t(r, a)),
      )),
      (e.ptrs = n),
      e
    );
  },
  jh = function (e) {
    let { docs: t, pointer: n } = this;
    if ((this.uncache(), typeof e == "function")) return $h(this, e);
    e = e || "alpha";
    let r = n || t.map((i, o) => [o]),
      a = t.map((i, o) => ({
        index: o,
        words: i.length,
        normal: i.map((s) => s.machine || s.normal || "").join(" "),
        pointer: r[o],
      }));
    return (
      xh.has(e) && (e = "sequential"),
      Dh.has(e) && (e = "alpha"),
      Ch.has(e)
        ? ((a = ua.byFreq(a)), this.update(a.map((i) => i.pointer)))
        : typeof ua[e] == "function"
          ? ((a = a.sort(ua[e])), this.update(a.map((i) => i.pointer)))
          : this
    );
  },
  Nh = function () {
    let e = this.pointer || this.docs.map((t, n) => [n]);
    return (
      (e = [].concat(e)),
      (e = e.reverse()),
      this._cache && (this._cache = this._cache.reverse()),
      this.update(e)
    );
  },
  Th = function () {
    let e = new Set();
    return this.filter((n) => {
      let r = n.text("machine");
      return e.has(r) ? !1 : (e.add(r), !0);
    });
  },
  Oh = { unique: Th, reverse: Nh, sort: jh },
  Ih = (e) => Object.prototype.toString.call(e) === "[object Array]",
  xu = function (e, t) {
    if (e.length > 0) {
      let n = e[e.length - 1],
        r = n[n.length - 1];
      / /.test(r.post) === !1 && (r.post += " ");
    }
    return ((e = e.concat(t)), e);
  },
  Eh = function (e, t) {
    if (e.document === t.document) {
      let r = e.fullPointer.concat(t.fullPointer);
      return e.toView(r).compute("index");
    }
    return (
      t.fullPointer.forEach((r) => {
        r[0] += e.document.length;
      }),
      (e.document = xu(e.document, t.docs)),
      e.all()
    );
  },
  Hh = {
    concat: function (e) {
      if (typeof e == "string") {
        let t = this.fromText(e);
        if (!this.found || !this.ptrs)
          this.document = this.document.concat(t.document);
        else {
          let n = this.fullPointer,
            r = n[n.length - 1][0];
          this.document.splice(r, 0, ...t.document);
        }
        return this.all().compute("index");
      }
      if (typeof e == "object" && e.isView) return Eh(this, e);
      if (Ih(e)) {
        let t = xu(this.document, e);
        return ((this.document = t), this.all());
      }
      return this;
    },
  },
  zh = function () {
    return ((this.ptrs = this.fullPointer), this);
  },
  Fh = function () {
    let e = this.ptrs;
    return !e || e.length < 1
      ? this
      : ((e = e.map((t) => t.slice(0, 3))), (this.ptrs = e), this);
  },
  Vh = { harden: zh, soften: Fh },
  Gh = Object.assign({}, ah, Ut, Wi, ai, Ln, Oh, Hh, Vh),
  Sh = function (e) {
    Object.assign(e.prototype, Gh);
  },
  Mh = {
    id: function (e) {
      let t = e.docs;
      for (let n = 0; n < t.length; n += 1)
        for (let r = 0; r < t[n].length; r += 1) {
          let a = t[n][r];
          a.id = a.id || Au(a);
        }
    },
  },
  Bh = { api: Sh, compute: Mh },
  Lh = [
    { word: "@", out: ["at"] },
    { word: "arent", out: ["are", "not"] },
    { word: "alot", out: ["a", "lot"] },
    { word: "brb", out: ["be", "right", "back"] },
    { word: "cannot", out: ["can", "not"] },
    { word: "dun", out: ["do", "not"] },
    { word: "can't", out: ["can", "not"] },
    { word: "shan't", out: ["should", "not"] },
    { word: "won't", out: ["will", "not"] },
    { word: "that's", out: ["that", "is"] },
    { word: "what's", out: ["what", "is"] },
    { word: "let's", out: ["let", "us"] },
    { word: "dunno", out: ["do", "not", "know"] },
    { word: "gonna", out: ["going", "to"] },
    { word: "gotta", out: ["have", "got", "to"] },
    { word: "gimme", out: ["give", "me"] },
    { word: "outta", out: ["out", "of"] },
    { word: "tryna", out: ["trying", "to"] },
    { word: "gtg", out: ["got", "to", "go"] },
    { word: "im", out: ["i", "am"] },
    { word: "imma", out: ["I", "will"] },
    { word: "imo", out: ["in", "my", "opinion"] },
    { word: "irl", out: ["in", "real", "life"] },
    { word: "ive", out: ["i", "have"] },
    { word: "rn", out: ["right", "now"] },
    { word: "tbh", out: ["to", "be", "honest"] },
    { word: "wanna", out: ["want", "to"] },
    { word: "c'mere", out: ["come", "here"] },
    { word: "c'mon", out: ["come", "on"] },
    { word: "shoulda", out: ["should", "have"] },
    { word: "coulda", out: ["coulda", "have"] },
    { word: "woulda", out: ["woulda", "have"] },
    { word: "musta", out: ["must", "have"] },
    { word: "tis", out: ["it", "is"] },
    { word: "twas", out: ["it", "was"] },
    { word: "y'know", out: ["you", "know"] },
    { word: "ne'er", out: ["never"] },
    { word: "o'er", out: ["over"] },
    { after: "ll", out: ["will"] },
    { after: "ve", out: ["have"] },
    { after: "re", out: ["are"] },
    { after: "m", out: ["am"] },
    { before: "c", out: ["ce"] },
    { before: "m", out: ["me"] },
    { before: "n", out: ["ne"] },
    { before: "qu", out: ["que"] },
    { before: "s", out: ["se"] },
    { before: "t", out: ["tu"] },
    { word: "shouldnt", out: ["should", "not"] },
    { word: "couldnt", out: ["could", "not"] },
    { word: "wouldnt", out: ["would", "not"] },
    { word: "hasnt", out: ["has", "not"] },
    { word: "wasnt", out: ["was", "not"] },
    { word: "isnt", out: ["is", "not"] },
    { word: "cant", out: ["can", "not"] },
    { word: "dont", out: ["do", "not"] },
    { word: "wont", out: ["will", "not"] },
    { word: "howd", out: ["how", "did"] },
    { word: "whatd", out: ["what", "did"] },
    { word: "whend", out: ["when", "did"] },
    { word: "whered", out: ["where", "did"] },
  ],
  ye = !0,
  Wh = {
    st: ye,
    nd: ye,
    rd: ye,
    th: ye,
    am: ye,
    pm: ye,
    max: ye,
    "°": ye,
    s: ye,
    e: ye,
    er: ye,
    ère: ye,
    ème: ye,
  },
  qh = { one: { contractions: Lh, numberSuffixes: Wh } },
  ca = function (e, t, n) {
    let [r, a] = t;
    !n ||
      n.length === 0 ||
      ((n = n.map(
        (i, o) => (
          (i.implicit = i.text),
          (i.machine = i.text),
          (i.pre = ""),
          (i.post = ""),
          (i.text = ""),
          (i.normal = ""),
          (i.index = [r, a + o]),
          i
        ),
      )),
      n[0] &&
        ((n[0].pre = e[r][a].pre),
        (n[n.length - 1].post = e[r][a].post),
        (n[0].text = e[r][a].text),
        (n[0].normal = e[r][a].normal)),
      e[r].splice(a, 1, ...n));
  },
  Kh = /'/,
  Jh = new Set(["what", "how", "when", "where", "why"]),
  _h = new Set(["be", "go", "start", "think", "need"]),
  Uh = new Set(["been", "gone"]),
  Rh = function (e, t) {
    let n = e[t].normal.split(Kh)[0];
    if (Jh.has(n)) return [n, "did"];
    if (e[t + 1]) {
      if (Uh.has(e[t + 1].normal)) return [n, "had"];
      if (_h.has(e[t + 1].normal)) return [n, "would"];
    }
    return null;
  },
  Yh = function (e, t) {
    return e[t].normal === "ain't" || e[t].normal === "aint"
      ? null
      : [e[t].normal.replace(/n't/, ""), "not"];
  },
  qi = /'/,
  Qh = /(e|é|aison|sion|tion)$/,
  Zh = /(age|isme|acle|ege|oire)$/,
  Xh = (e, t) => {
    let n = e[t].normal.split(qi)[1];
    return n && n.endsWith("e") ? ["la", n] : ["le", n];
  },
  ed = (e, t) => {
    let n = e[t].normal.split(qi)[1];
    return n && Qh.test(n) && !Zh.test(n)
      ? ["du", n]
      : n && n.endsWith("s")
        ? ["des", n]
        : ["de", n];
  },
  td = (e, t) => ["je", e[t].normal.split(qi)[1]],
  ha = { preJ: td, preL: Xh, preD: ed },
  nd = /^([0-9.]{1,4}[a-z]{0,2}) ?[-–—] ?([0-9]{1,4}[a-z]{0,2})$/i,
  rd =
    /^([0-9]{1,2}(:[0-9][0-9])?(am|pm)?) ?[-–—] ?([0-9]{1,2}(:[0-9][0-9])?(am|pm)?)$/i,
  ad = /^[0-9]{3}-[0-9]{4}$/,
  id = function (e, t) {
    let n = e[t],
      r = n.text.match(nd);
    return r !== null
      ? n.tags.has("PhoneNumber") === !0 || ad.test(n.text)
        ? null
        : [r[1], "to", r[2]]
      : ((r = n.text.match(rd)), r !== null ? [r[1], "to", r[4]] : null);
  },
  od = /^([+-]?[0-9][.,0-9]*)([a-z°²³µ/]+)$/,
  sd = function (e, t, n) {
    const r = n.model.one.numberSuffixes || {};
    let i = e[t].text.match(od);
    if (i !== null) {
      let o = i[2].toLowerCase().trim();
      return r.hasOwnProperty(o) ? null : [i[1], o];
    }
    return null;
  },
  ko = /'/,
  ld = /^[0-9][^-–—]*[-–—].*?[0-9]/,
  Po = function (e, t, n, r) {
    let a = t.update();
    a.document = [e];
    let i = n + r;
    (n > 0 && (n -= 1), e[i] && (i += 1), (a.ptrs = [[0, n, i]]));
  },
  Ao = { t: (e, t) => Yh(e, t), d: (e, t) => Rh(e, t) },
  xo = {
    j: (e, t) => ha.preJ(e, t),
    l: (e, t) => ha.preL(e, t),
    d: (e, t) => ha.preD(e, t),
  },
  ud = function (e, t, n, r) {
    for (let a = 0; a < e.length; a += 1) {
      let i = e[a];
      if (i.word === t.normal) return i.out;
      if (r !== null && r === i.after) return [n].concat(i.out);
      if (n !== null && n === i.before && r && r.length > 2)
        return i.out.concat(r);
    }
    return null;
  },
  da = function (e, t) {
    let n = t.fromText(e.join(" "));
    return (n.compute(["id", "alias"]), n.docs[0]);
  },
  cd = function (e, t) {
    for (let n = t + 1; n < 5 && e[n]; n += 1)
      if (e[n].normal === "been") return ["there", "has"];
    return ["there", "is"];
  },
  hd = (e) => {
    let { world: t, document: n } = e;
    const { model: r, methods: a } = t;
    let i = r.one.contractions || [];
    n.forEach((o, s) => {
      for (let l = o.length - 1; l >= 0; l -= 1) {
        let u = null,
          c = null;
        if (ko.test(o[l].normal) === !0) {
          let f = o[l].normal.split(ko);
          ((u = f[0]), (c = f[1]));
        }
        let h = ud(i, o[l], u, c);
        if (
          (!h && Ao.hasOwnProperty(c) && (h = Ao[c](o, l, t)),
          !h && xo.hasOwnProperty(u) && (h = xo[u](o, l)),
          u === "there" && c === "s" && (h = cd(o, l)),
          h)
        ) {
          ((h = da(h, e)), ca(n, [s, l], h), Po(n[s], e, l, h.length));
          continue;
        }
        if (ld.test(o[l].normal)) {
          ((h = id(o, l)),
            h &&
              ((h = da(h, e)),
              ca(n, [s, l], h),
              a.one.setTag(h, "NumberRange", t),
              h[2] &&
                h[2].tags.has("Time") &&
                a.one.setTag([h[0]], "Time", t, null, "time-range"),
              Po(n[s], e, l, h.length)));
          continue;
        }
        ((h = sd(o, l, t)),
          h &&
            ((h = da(h, e)),
            ca(n, [s, l], h),
            a.one.setTag([h[1]], "Unit", t, null, "contraction-unit")));
      }
    });
  },
  dd = { contractions: hd },
  fd = { model: qh, compute: dd, hooks: ["contractions"] },
  Co = function (e) {
    const t = e.world,
      { model: n, methods: r } = e.world,
      a = r.one.setTag,
      { frozenLex: i } = n.one,
      o = n.one._multiCache || {};
    e.docs.forEach((s) => {
      for (let l = 0; l < s.length; l += 1) {
        let u = s[l],
          c = u.machine || u.normal;
        if (o[c] !== void 0 && s[l + 1]) {
          let h = l + o[c] - 1;
          for (let f = h; f > l; f -= 1) {
            let $ = s.slice(l, f + 1),
              Oe = $.map((rr) => rr.machine || rr.normal).join(" ");
            if (i.hasOwnProperty(Oe) === !0) {
              (a($, i[Oe], t, !1, "1-frozen-multi-lexicon"),
                $.forEach((rr) => (rr.frozen = !0)));
              continue;
            }
          }
        }
        if (i[c] !== void 0 && i.hasOwnProperty(c)) {
          (a([u], i[c], t, !1, "1-freeze-lexicon"), (u.frozen = !0));
          continue;
        }
      }
    });
  },
  md = function (e) {
    return (
      e.docs.forEach((t) => {
        t.forEach((n) => {
          delete n.frozen;
        });
      }),
      e
    );
  },
  pd = { frozen: Co, freeze: Co, unfreeze: md },
  Do = (e) => "\x1B[34m" + e + "\x1B[0m",
  $o = (e) => "\x1B[3m\x1B[2m" + e + "\x1B[0m",
  jo = function (e) {
    e.docs.forEach((t) => {
      (console.log(
        Do(`
  ┌─────────`),
      ),
        t.forEach((n) => {
          let r = `  ${$o("│")}  `,
            a = n.implicit || n.text || "-";
          (n.frozen === !0 ? (r += `${Do(a)} ❄️`) : (r += $o(a)),
            console.log(r));
        }));
    });
  },
  gd = {
    compute: pd,
    mutate: (e) => {
      const t = e.methods.one;
      ((t.termMethods.isFrozen = (n) => n.frozen === !0),
        (t.debug.freeze = jo),
        (t.debug.frozen = jo));
    },
    api: function (e) {
      ((e.prototype.freeze = function () {
        return (
          this.docs.forEach((t) => {
            t.forEach((n) => {
              n.frozen = !0;
            });
          }),
          this
        );
      }),
        (e.prototype.unfreeze = function () {
          this.compute("unfreeze");
        }),
        (e.prototype.isFrozen = function () {
          return this.match("@isFrozen+");
        }));
    },
    hooks: ["freeze"],
  },
  yd = function (e, t, n) {
    const { model: r, methods: a } = n,
      i = a.one.setTag,
      o = r.one._multiCache || {},
      { lexicon: s } = r.one || {};
    let l = e[t],
      u = l.machine || l.normal;
    if (o[u] !== void 0 && e[t + 1]) {
      let c = t + o[u] - 1;
      for (let h = c; h > t; h -= 1) {
        let f = e.slice(t, h + 1);
        if (f.length <= 1) return !1;
        let $ = f.map((Oe) => Oe.machine || Oe.normal).join(" ");
        if (s.hasOwnProperty($) === !0) {
          let Oe = s[$];
          return (
            i(f, Oe, n, !1, "1-multi-lexicon"),
            Oe &&
              Oe.length === 2 &&
              (Oe[0] === "PhrasalVerb" || Oe[1] === "PhrasalVerb") &&
              i([f[1]], "Particle", n, !1, "1-phrasal-particle"),
            !0
          );
        }
      }
      return !1;
    }
    return null;
  },
  No = /^(under|over|mis|re|un|dis|semi|pre|post)-?/,
  bd = new Set([
    "Verb",
    "Infinitive",
    "PastTense",
    "Gerund",
    "PresentTense",
    "Adjective",
    "Participle",
  ]),
  vd = function (e, t, n) {
    const { model: r, methods: a } = n,
      i = a.one.setTag,
      { lexicon: o } = r.one;
    let s = e[t],
      l = s.machine || s.normal;
    if (o[l] !== void 0 && o.hasOwnProperty(l))
      return (i([s], o[l], n, !1, "1-lexicon"), !0);
    if (s.alias) {
      let u = s.alias.find((c) => o.hasOwnProperty(c));
      if (u) return (i([s], o[u], n, !1, "1-lexicon-alias"), !0);
    }
    if (No.test(l) === !0) {
      let u = l.replace(No, "");
      if (o.hasOwnProperty(u) && u.length > 3 && bd.has(o[u]))
        return (i([s], o[u], n, !1, "1-lexicon-prefix"), !0);
    }
    return null;
  },
  wd = function (e) {
    const t = e.world;
    e.docs.forEach((n) => {
      for (let r = 0; r < n.length; r += 1)
        if (n[r].tags.size === 0) {
          let a = null;
          ((a = a || yd(n, r, t)), (a = a || vd(n, r, t)));
        }
    });
  },
  kd = { lexicon: wd },
  Pd = function (e) {
    let t = {},
      n = {};
    return (
      Object.keys(e).forEach((r) => {
        let a = e[r];
        ((r = r.toLowerCase().trim()), (r = r.replace(/'s\b/, "")));
        let i = r.split(/ /);
        (i.length > 1 &&
          (n[i[0]] === void 0 || i.length > n[i[0]]) &&
          (n[i[0]] = i.length),
          (t[r] = t[r] || a));
      }),
      delete t[""],
      delete t[null],
      delete t[" "],
      { lex: t, _multi: n }
    );
  },
  Ad = { one: { expandLexicon: Pd } },
  xd = function (e, t = !1) {
    const n = this.world(),
      { methods: r, model: a } = n;
    if (!e) return;
    if (
      (Object.keys(e).forEach((s) => {
        typeof e[s] == "string" &&
          e[s].startsWith("#") &&
          (e[s] = e[s].replace(/^#/, ""));
      }),
      t === !0)
    ) {
      let { lex: s, _multi: l } = r.one.expandLexicon(e, n);
      (Object.assign(a.one._multiCache, l), Object.assign(a.one.frozenLex, s));
      return;
    }
    if (r.two.expandLexicon) {
      let { lex: s, _multi: l } = r.two.expandLexicon(e, n);
      (Object.assign(a.one.lexicon, s), Object.assign(a.one._multiCache, l));
    }
    let { lex: i, _multi: o } = r.one.expandLexicon(e, n);
    (Object.assign(a.one.lexicon, i), Object.assign(a.one._multiCache, o));
  },
  Cd = { addWords: xd },
  Dd = { one: { lexicon: {}, _multiCache: {}, frozenLex: {} } },
  $d = { model: Dd, methods: Ad, compute: kd, lib: Cd, hooks: ["lexicon"] },
  jd = function (e, t) {
    const { methods: n, model: r } = t;
    return n.one.tokenize
      .splitTerms(e, r)
      .map((i) => n.one.tokenize.splitWhitespace(i, r))
      .map((i) => i.text.toLowerCase());
  },
  Cu = function (e, t) {
    let n = [{}],
      r = [null],
      a = [0],
      i = [],
      o = 0;
    e.forEach(function (s) {
      let l = 0,
        u = jd(s, t);
      for (let c = 0; c < u.length; c++) {
        let h = u[c];
        n[l] && n[l].hasOwnProperty(h)
          ? (l = n[l][h])
          : (o++, (n[l][h] = o), (n[o] = {}), (l = o), (r[o] = null));
      }
      r[l] = [u.length];
    });
    for (let s in n[0]) ((o = n[0][s]), (a[o] = 0), i.push(o));
    for (; i.length;) {
      let s = i.shift(),
        l = Object.keys(n[s]);
      for (let u = 0; u < l.length; u += 1) {
        let c = l[u],
          h = n[s][c];
        for (i.push(h), o = a[s]; o > 0 && !n[o].hasOwnProperty(c);) o = a[o];
        if (n.hasOwnProperty(o)) {
          let f = n[o][c];
          ((a[h] = f),
            r[f] && ((r[h] = r[h] || []), (r[h] = r[h].concat(r[f]))));
        } else a[h] = 0;
      }
    }
    return { goNext: n, endAs: r, failTo: a };
  },
  Nd = function (e, t, n) {
    let r = 0,
      a = [];
    for (let i = 0; i < e.length; i++) {
      let o = e[i][n.form] || e[i].normal;
      for (
        ;
        r > 0 && (t.goNext[r] === void 0 || !t.goNext[r].hasOwnProperty(o));
      )
        r = t.failTo[r] || 0;
      if (t.goNext[r].hasOwnProperty(o) && ((r = t.goNext[r][o]), t.endAs[r])) {
        let s = t.endAs[r];
        for (let l = 0; l < s.length; l++) {
          let u = s[l],
            c = e[i - u + 1],
            [h, f] = c.index;
          a.push([h, f, f + u, c.id]);
        }
      }
    }
    return a;
  },
  Td = function (e, t) {
    for (let n = 0; n < e.length; n += 1) if (t.has(e[n]) === !0) return !1;
    return !0;
  },
  Od = function (e, t, n) {
    let r = [];
    n.form = n.form || "normal";
    let a = e.docs;
    if (!t.goNext || !t.goNext[0])
      return (console.error("Compromise invalid lookup trie"), e.none());
    let i = Object.keys(t.goNext[0]);
    for (let o = 0; o < a.length; o++) {
      if (e._cache && e._cache[o] && Td(i, e._cache[o]) === !0) continue;
      let s = a[o],
        l = Nd(s, t, n);
      l.length > 0 && (r = r.concat(l));
    }
    return e.update(r);
  },
  Id = (e) => Object.prototype.toString.call(e) === "[object Object]";
function Ed(e) {
  e.prototype.lookup = function (t, n = {}) {
    if (!t) return this.none();
    typeof t == "string" && (t = [t]);
    let r = Id(t) ? t : Cu(t, this.world),
      a = Od(this, r, n);
    return ((a = a.settle()), a);
  };
}
const fa = (e, t) => {
    for (let n = e.length - 1; n >= 0; n -= 1)
      if (e[n] !== t) return ((e = e.slice(0, n + 1)), e);
    return e;
  },
  Hd = function (e) {
    return (
      (e.goNext = e.goNext.map((t) => {
        if (Object.keys(t).length !== 0) return t;
      })),
      (e.goNext = fa(e.goNext, void 0)),
      (e.failTo = fa(e.failTo, 0)),
      (e.endAs = fa(e.endAs, null)),
      e
    );
  },
  ii = {
    buildTrie: function (e) {
      const t = Cu(e, this.world());
      return Hd(t);
    },
  };
ii.compile = ii.buildTrie;
const zd = { api: Ed, lib: ii },
  To = function (e, t) {
    return (
      t &&
        e.forEach((n) => {
          let r = n[0];
          t[r] && ((n[0] = t[r][0]), (n[1] += t[r][1]), (n[2] += t[r][1]));
        }),
      e
    );
  },
  Du = function (e, t) {
    let { ptrs: n, byGroup: r } = e;
    return (
      (n = To(n, t)),
      Object.keys(r).forEach((a) => {
        r[a] = To(r[a], t);
      }),
      { ptrs: n, byGroup: r }
    );
  },
  Yn = function (e, t, n) {
    const r = n.methods.one;
    return (
      typeof e == "number" && (e = String(e)),
      typeof e == "string" &&
        ((e = r.killUnicode(e, n)), (e = r.parseMatch(e, t, n))),
      e
    );
  },
  $u = (e) => Object.prototype.toString.call(e) === "[object Object]",
  Qn = (e) => e && $u(e) && e.isView === !0,
  Zn = (e) => e && $u(e) && e.isNet === !0,
  Fd = function (e, t, n) {
    const r = this.methods.one;
    if (Qn(e)) return this.intersection(e);
    if (Zn(e)) return this.sweep(e, { tagger: !1 }).view.settle();
    e = Yn(e, n, this.world);
    let a = { regs: e, group: t },
      i = r.match(this.docs, a, this._cache),
      { ptrs: o, byGroup: s } = Du(i, this.fullPointer),
      l = this.toView(o);
    return ((l._groups = s), l);
  },
  Vd = function (e, t, n) {
    const r = this.methods.one;
    if (Qn(e)) return this.intersection(e).eq(0);
    if (Zn(e)) return this.sweep(e, { tagger: !1, matchOne: !0 }).view;
    e = Yn(e, n, this.world);
    let a = { regs: e, group: t, justOne: !0 },
      i = r.match(this.docs, a, this._cache),
      { ptrs: o, byGroup: s } = Du(i, this.fullPointer),
      l = this.toView(o);
    return ((l._groups = s), l);
  },
  Gd = function (e, t, n) {
    const r = this.methods.one;
    if (Qn(e)) return this.intersection(e).fullPointer.length > 0;
    if (Zn(e)) return this.sweep(e, { tagger: !1 }).view.found;
    e = Yn(e, n, this.world);
    let a = { regs: e, group: t, justOne: !0 };
    return r.match(this.docs, a, this._cache).ptrs.length > 0;
  },
  Sd = function (e, t, n) {
    const r = this.methods.one;
    if (Qn(e)) return this.filter((l) => l.intersection(e).found);
    if (Zn(e)) {
      let l = this.sweep(e, { tagger: !1 }).view.settle();
      return this.if(l);
    }
    e = Yn(e, n, this.world);
    let a = { regs: e, group: t, justOne: !0 },
      i = this.fullPointer,
      o = this._cache || [];
    i = i.filter((l, u) => {
      let c = this.update([l]);
      return r.match(c.docs, a, o[u]).ptrs.length > 0;
    });
    let s = this.update(i);
    return (this._cache && (s._cache = i.map((l) => o[l[0]])), s);
  },
  Md = function (e, t, n) {
    const { methods: r } = this,
      a = r.one;
    if (Qn(e)) return this.filter((s) => !s.intersection(e).found);
    if (Zn(e)) {
      let s = this.sweep(e, { tagger: !1 }).view.settle();
      return this.ifNo(s);
    }
    e = Yn(e, n, this.world);
    let i = this._cache || [],
      o = this.filter((s, l) => {
        let u = { regs: e, group: t, justOne: !0 };
        return a.match(s.docs, u, i[l]).ptrs.length === 0;
      });
    return (this._cache && (o._cache = o.ptrs.map((s) => i[s[0]])), o);
  },
  Bd = { matchOne: Vd, match: Fd, has: Gd, if: Sd, ifNo: Md },
  Ld = function (e, t, n) {
    const { indexN: r } = this.methods.one.pointer;
    let a = [],
      i = r(this.fullPointer);
    Object.keys(i).forEach((s) => {
      let l = i[s].sort((u, c) => (u[1] > c[1] ? 1 : -1))[0];
      l[1] > 0 && a.push([l[0], 0, l[1]]);
    });
    let o = this.toView(a);
    return e ? o.match(e, t, n) : o;
  },
  Wd = function (e, t, n) {
    const { indexN: r } = this.methods.one.pointer;
    let a = [],
      i = r(this.fullPointer),
      o = this.document;
    Object.keys(i).forEach((l) => {
      let u = i[l].sort((f, $) => (f[1] > $[1] ? -1 : 1))[0],
        [c, , h] = u;
      h < o[c].length && a.push([c, h, o[c].length]);
    });
    let s = this.toView(a);
    return e ? s.match(e, t, n) : s;
  },
  qd = function (e, t, n) {
    (typeof e == "string" &&
      (e = this.world.methods.one.parseMatch(e, n, this.world)),
      (e[e.length - 1].end = !0));
    let r = this.fullPointer;
    return (
      this.forEach((a, i) => {
        let o = a.before(e, t);
        if (o.found) {
          let s = o.terms();
          ((r[i][1] -= s.length), (r[i][3] = s.docs[0][0].id));
        }
      }),
      this.update(r)
    );
  },
  Kd = function (e, t, n) {
    (typeof e == "string" &&
      (e = this.world.methods.one.parseMatch(e, n, this.world)),
      (e[0].start = !0));
    let r = this.fullPointer;
    return (
      this.forEach((a, i) => {
        let o = a.after(e, t);
        if (o.found) {
          let s = o.terms();
          ((r[i][2] += s.length), (r[i][4] = null));
        }
      }),
      this.update(r)
    );
  },
  Jd = function (e, t, n) {
    return this.growRight(e, t, n).growLeft(e, t, n);
  },
  _d = { before: Ld, after: Wd, growLeft: qd, growRight: Kd, grow: Jd },
  ju = function (e, t) {
    return [e[0], e[1], t[2]];
  },
  Ud = function (e) {
    return Object.prototype.toString.call(e) === "[object Array]";
  },
  Ki = (e, t, n) =>
    typeof e == "string" || Ud(e) ? t.match(e, n) : e || t.none(),
  Ji = function (e, t) {
    let [n, r, a] = e;
    return (
      t.document[n] &&
        t.document[n][r] &&
        ((e[3] = e[3] || t.document[n][r].id),
        t.document[n][a - 1] && (e[4] = e[4] || t.document[n][a - 1].id)),
      e
    );
  },
  Pn = {};
Pn.splitOn = function (e, t) {
  const { splitAll: n } = this.methods.one.pointer;
  let r = Ki(e, this, t).fullPointer,
    a = n(this.fullPointer, r),
    i = [];
  return (
    a.forEach((o) => {
      (i.push(o.passthrough),
        i.push(o.before),
        i.push(o.match),
        i.push(o.after));
    }),
    (i = i.filter((o) => o)),
    (i = i.map((o) => Ji(o, this))),
    this.update(i)
  );
};
Pn.splitBefore = function (e, t) {
  const { splitAll: n } = this.methods.one.pointer;
  let r = Ki(e, this, t).fullPointer,
    a = n(this.fullPointer, r);
  for (let o = 0; o < a.length; o += 1)
    !a[o].after &&
      a[o + 1] &&
      a[o + 1].before &&
      a[o].match &&
      a[o].match[0] === a[o + 1].before[0] &&
      ((a[o].after = a[o + 1].before), delete a[o + 1].before);
  let i = [];
  return (
    a.forEach((o) => {
      (i.push(o.passthrough),
        i.push(o.before),
        o.match && o.after ? i.push(ju(o.match, o.after)) : i.push(o.match));
    }),
    (i = i.filter((o) => o)),
    (i = i.map((o) => Ji(o, this))),
    this.update(i)
  );
};
Pn.splitAfter = function (e, t) {
  const { splitAll: n } = this.methods.one.pointer;
  let r = Ki(e, this, t).fullPointer,
    a = n(this.fullPointer, r),
    i = [];
  return (
    a.forEach((o) => {
      (i.push(o.passthrough),
        o.before && o.match
          ? i.push(ju(o.before, o.match))
          : (i.push(o.before), i.push(o.match)),
        i.push(o.after));
    }),
    (i = i.filter((o) => o)),
    (i = i.map((o) => Ji(o, this))),
    this.update(i)
  );
};
Pn.split = Pn.splitAfter;
const Rd = function (e, t) {
    return !e || !t || e[0] !== t[0] ? !1 : e[2] === t[1];
  },
  Oo = function (e, t, n) {
    const r = e.world,
      a = r.methods.one.parseMatch;
    ((t = t || ".$"), (n = n || "^."));
    let i = a(t, {}, r),
      o = a(n, {}, r);
    ((i[i.length - 1].end = !0), (o[0].start = !0));
    let s = e.fullPointer,
      l = [s[0]];
    for (let u = 1; u < s.length; u += 1) {
      let c = l[l.length - 1],
        h = s[u],
        f = e.update([c]),
        $ = e.update([h]);
      Rd(c, h) && f.has(i) && $.has(o)
        ? (l[l.length - 1] = [c[0], c[1], h[2], c[3], h[4]])
        : l.push(h);
    }
    return e.update(l);
  },
  Yd = {
    joinIf: function (e, t) {
      return Oo(this, e, t);
    },
    join: function () {
      return Oo(this);
    },
  },
  qe = Object.assign({}, Bd, _d, Pn, Yd);
qe.lookBehind = qe.before;
qe.lookBefore = qe.before;
qe.lookAhead = qe.after;
qe.lookAfter = qe.after;
qe.notIf = qe.ifNo;
const Qd = function (e) {
    Object.assign(e.prototype, qe);
  },
  Zd = /(?:^|\s)([![^]*(?:<[^<]*>)?\/.*?[^\\/]\/[?\]+*$~]*)(?:\s|$)/,
  Xd = /([!~[^]*(?:<[^<]*>)?\([^)]+[^\\)]\)[?\]+*$~]*)(?:\s|$)/,
  ef = / /g,
  tf = (e) => /^[![^]*(<[^<]*>)?\(/.test(e) && /\)[?\]+*$~]*$/.test(e),
  Io = (e) => /^[![^]*(<[^<]*>)?\//.test(e) && /\/[?\]+*$~]*$/.test(e),
  Eo = function (e) {
    return ((e = e.map((t) => t.trim())), (e = e.filter((t) => t)), e);
  },
  nf = function (e) {
    let t = e.split(Zd),
      n = [];
    (t.forEach((a) => {
      if (Io(a)) {
        n.push(a);
        return;
      }
      n = n.concat(a.split(Xd));
    }),
      (n = Eo(n)));
    let r = [];
    return (
      n.forEach((a) => {
        tf(a) || Io(a) ? r.push(a) : (r = r.concat(a.split(ef)));
      }),
      (r = Eo(r)),
      r
    );
  },
  Ho = /\{([0-9]+)?(, *[0-9]*)?\}/,
  zo = /&&/,
  rf = new RegExp(/^<\s*(\S+)\s*>/),
  Fo = (e) => e.charAt(0).toUpperCase() + e.substring(1),
  xe = (e) => e.charAt(e.length - 1),
  be = (e) => e.charAt(0),
  mn = (e) => e.substring(1),
  pn = (e) => e.substring(0, e.length - 1),
  $n = function (e) {
    return ((e = mn(e)), (e = pn(e)), e);
  },
  Nu = function (e, t) {
    let n = {};
    for (let r = 0; r < 2; r += 1) {
      if (
        (xe(e) === "$" && ((n.end = !0), (e = pn(e))),
        be(e) === "^" && ((n.start = !0), (e = mn(e))),
        xe(e) === "?" && ((n.optional = !0), (e = pn(e))),
        (be(e) === "[" || xe(e) === "]") &&
          ((n.group = null),
          be(e) === "[" && (n.groupStart = !0),
          xe(e) === "]" && (n.groupEnd = !0),
          (e = e.replace(/^\[/, "")),
          (e = e.replace(/\]$/, "")),
          be(e) === "<"))
      ) {
        const a = rf.exec(e);
        a.length >= 2 && ((n.group = a[1]), (e = e.replace(a[0], "")));
      }
      if (
        (xe(e) === "+" && ((n.greedy = !0), (e = pn(e))),
        e !== "*" &&
          xe(e) === "*" &&
          e !== "\\*" &&
          ((n.greedy = !0), (e = pn(e))),
        be(e) === "!" && ((n.negative = !0), (e = mn(e))),
        be(e) === "~" &&
          xe(e) === "~" &&
          e.length > 2 &&
          ((e = $n(e)),
          (n.fuzzy = !0),
          (n.min = t.fuzzy || 0.85),
          /\(/.test(e) === !1))
      )
        return ((n.word = e), n);
      if (be(e) === "/" && xe(e) === "/")
        return (
          (e = $n(e)),
          t.caseSensitive && (n.use = "text"),
          (n.regex = new RegExp(e)),
          n
        );
      if (
        (Ho.test(e) === !0 &&
          (e = e.replace(
            Ho,
            (a, i, o) => (
              o === void 0
                ? ((n.min = Number(i)), (n.max = Number(i)))
                : ((o = o.replace(/, */, "")),
                  i === void 0
                    ? ((n.min = 0), (n.max = Number(o)))
                    : ((n.min = Number(i)), (n.max = Number(o || 999)))),
              (n.greedy = !0),
              n.min || (n.optional = !0),
              ""
            ),
          )),
        be(e) === "(" && xe(e) === ")")
      ) {
        (zo.test(e)
          ? ((n.choices = e.split(zo)), (n.operator = "and"))
          : ((n.choices = e.split("|")), (n.operator = "or")),
          (n.choices[0] = mn(n.choices[0])));
        let a = n.choices.length - 1;
        ((n.choices[a] = pn(n.choices[a])),
          (n.choices = n.choices.map((i) => i.trim())),
          (n.choices = n.choices.filter((i) => i)),
          (n.choices = n.choices.map((i) =>
            i.split(/ /g).map((o) => Nu(o, t)),
          )),
          (e = ""));
      }
      if (be(e) === "{" && xe(e) === "}") {
        if (((e = $n(e)), (n.root = e), /\//.test(e))) {
          let a = n.root.split(/\//);
          ((n.root = a[0]),
            (n.pos = a[1]),
            n.pos === "adj" && (n.pos = "Adjective"),
            (n.pos =
              n.pos.charAt(0).toUpperCase() + n.pos.substr(1).toLowerCase()),
            a[2] !== void 0 && (n.sense = a[2]));
        }
        return n;
      }
      if (be(e) === "<" && xe(e) === ">")
        return ((e = $n(e)), (n.chunk = Fo(e)), (n.greedy = !0), n);
      if (be(e) === "%" && xe(e) === "%")
        return ((e = $n(e)), (n.switch = e), n);
    }
    return be(e) === "#"
      ? ((n.tag = mn(e)), (n.tag = Fo(n.tag)), n)
      : be(e) === "@"
        ? ((n.method = mn(e)), n)
        : e === "."
          ? ((n.anything = !0), n)
          : e === "*"
            ? ((n.anything = !0), (n.greedy = !0), (n.optional = !0), n)
            : (e &&
                ((e = e.replace("\\*", "*")),
                (e = e.replace("\\.", ".")),
                t.caseSensitive ? (n.use = "text") : (e = e.toLowerCase()),
                (n.word = e)),
              n);
  },
  af = /[a-z0-9][-–—][a-z]/i,
  of = function (e, t) {
    let n = t.model.one.prefixes;
    for (let r = e.length - 1; r >= 0; r -= 1) {
      let a = e[r];
      if (a.word && af.test(a.word)) {
        let i = a.word.split(/[-–—]/g);
        if (n.hasOwnProperty(i[0])) continue;
        ((i = i.filter((o) => o).reverse()),
          e.splice(r, 1),
          i.forEach((o) => {
            let s = Object.assign({}, a);
            ((s.word = o), e.splice(r, 0, s));
          }));
      }
    }
    return e;
  },
  Vo = function (e, t) {
    let { all: n } = t.methods.two.transform.verb || {},
      r = e.root;
    return n ? n(r, t.model) : [];
  },
  Go = function (e, t) {
    let { all: n } = t.methods.two.transform.noun || {};
    return n ? n(e.root, t.model) : [e.root];
  },
  So = function (e, t) {
    let { all: n } = t.methods.two.transform.adjective || {};
    return n ? n(e.root, t.model) : [e.root];
  },
  sf = function (e, t) {
    return (
      (e = e.map((n) => {
        if (n.root)
          if (t.methods.two && t.methods.two.transform) {
            let r = [];
            (n.pos
              ? n.pos === "Verb"
                ? (r = r.concat(Vo(n, t)))
                : n.pos === "Noun"
                  ? (r = r.concat(Go(n, t)))
                  : n.pos === "Adjective" && (r = r.concat(So(n, t)))
              : ((r = r.concat(Vo(n, t))),
                (r = r.concat(Go(n, t))),
                (r = r.concat(So(n, t)))),
              (r = r.filter((a) => a)),
              r.length > 0 && ((n.operator = "or"), (n.fastOr = new Set(r))));
          } else ((n.machine = n.root), delete n.id, delete n.root);
        return n;
      })),
      e
    );
  },
  lf = function (e) {
    let t = 0,
      n = null;
    for (let r = 0; r < e.length; r++) {
      const a = e[r];
      (a.groupStart === !0 &&
        ((n = a.group), n === null && ((n = String(t)), (t += 1))),
        n !== null && (a.group = n),
        a.groupEnd === !0 && (n = null));
    }
    return e;
  },
  uf = function (e) {
    return e.map((t) => {
      if (t.choices !== void 0) {
        if (t.operator !== "or" || t.fuzzy === !0) return t;
        t.choices.every((r) => {
          if (r.length !== 1) return !1;
          let a = r[0];
          return a.fuzzy === !0 || a.start || a.end
            ? !1
            : a.word !== void 0 &&
                a.negative !== !0 &&
                a.optional !== !0 &&
                a.method !== !0;
        }) === !0 &&
          ((t.fastOr = new Set()),
          t.choices.forEach((r) => {
            t.fastOr.add(r[0].word);
          }),
          delete t.choices);
      }
      return t;
    });
  },
  cf = function (e) {
    return e.map(
      (t) => (
        t.fuzzy &&
          t.choices &&
          t.choices.forEach((n) => {
            n.length === 1 &&
              n[0].word &&
              ((n[0].fuzzy = !0), (n[0].min = t.min));
          }),
        t
      ),
    );
  },
  hf = function (e) {
    return ((e = lf(e)), (e = uf(e)), (e = cf(e)), e);
  },
  df = function (e, t, n) {
    if (e == null || e === "") return [];
    ((t = t || {}), typeof e == "number" && (e = String(e)));
    let r = nf(e);
    return (
      (r = r.map((a) => Nu(a, t))),
      (r = of(r, n)),
      (r = sf(r, n)),
      (r = hf(r)),
      r
    );
  },
  ff = function (e, t) {
    for (let n of t) if (e.has(n)) return !0;
    return !1;
  },
  mf = function (e, t) {
    for (let n = 0; n < e.length; n += 1) {
      let r = e[n];
      if (!(r.optional === !0 || r.negative === !0 || r.fuzzy === !0)) {
        if (
          (r.word !== void 0 && t.has(r.word) === !1) ||
          (r.tag !== void 0 && t.has("#" + r.tag) === !1)
        )
          return !0;
        if (r.fastOr && ff(r.fastOr, t) === !1) return !1;
      }
    }
    return !1;
  },
  pf = function (e, t) {
    let n = e.length,
      r = t.length;
    if (n === 0) return r;
    if (r === 0) return n;
    let a = (r > n ? r : n) + 1;
    if (Math.abs(n - r) > (a || 100)) return a || 100;
    let i = [];
    for (let f = 0; f < a; f++) ((i[f] = [f]), (i[f].length = a));
    for (let f = 0; f < a; f++) i[0][f] = f;
    let o, s, l, u, c, h;
    for (let f = 1; f <= n; ++f)
      for (s = e[f - 1], o = 1; o <= r; ++o) {
        if (f === o && i[f][o] > 4) return n;
        ((l = t[o - 1]),
          (u = s === l ? 0 : 1),
          (c = i[f - 1][o] + 1),
          (h = i[f][o - 1] + 1) < c && (c = h),
          (h = i[f - 1][o - 1] + u) < c && (c = h),
          f > 1 &&
          o > 1 &&
          s === t[o - 2] &&
          e[f - 2] === l &&
          (h = i[f - 2][o - 2] + u) < c
            ? (i[f][o] = h)
            : (i[f][o] = c));
      }
    return i[n][r];
  },
  gf = function (e, t, n = 3) {
    if (e === t) return 1;
    if (e.length < n || t.length < n) return 0;
    const r = pf(e, t);
    let a = Math.max(e.length, t.length);
    return 1 - (a === 0 ? 0 : r / a);
  },
  yf =
    /([\u0022\uFF02\u0027\u201C\u2018\u201F\u201B\u201E\u2E42\u201A\u00AB\u2039\u2035\u2036\u2037\u301D\u0060\u301F])/,
  bf =
    /([\u0022\uFF02\u0027\u201D\u2019\u00BB\u203A\u2032\u2033\u2034\u301E\u00B4])/,
  Mo = /^[-–—]$/,
  Bo = / [-–—]{1,3} /,
  Ke = (e, t) => e.post.indexOf(t) !== -1,
  Wn = {
    hasQuote: (e) => yf.test(e.pre) || bf.test(e.post),
    hasComma: (e) => Ke(e, ","),
    hasPeriod: (e) => Ke(e, ".") === !0 && Ke(e, "...") === !1,
    hasExclamation: (e) => Ke(e, "!"),
    hasQuestionMark: (e) => Ke(e, "?") || Ke(e, "¿"),
    hasEllipses: (e) => Ke(e, "..") || Ke(e, "…"),
    hasSemicolon: (e) => Ke(e, ";"),
    hasColon: (e) => Ke(e, ":"),
    hasSlash: (e) => /\//.test(e.text),
    hasHyphen: (e) => Mo.test(e.post) || Mo.test(e.pre),
    hasDash: (e) => Bo.test(e.post) || Bo.test(e.pre),
    hasContraction: (e) => !!e.implicit,
    isAcronym: (e) => e.tags.has("Acronym"),
    isKnown: (e) => e.tags.size > 0,
    isTitleCase: (e) =>
      new RegExp("^\\p{Lu}[a-z'\\u00C0-\\u00FF]", "u").test(e.text),
    isUpperCase: (e) => new RegExp("^\\p{Lu}+$", "u").test(e.text),
  };
Wn.hasQuotation = Wn.hasQuote;
let te = function () {};
const vf = function (e, t, n, r) {
  if (t.anything === !0) return !0;
  if ((t.start === !0 && n !== 0) || (t.end === !0 && n !== r - 1)) return !1;
  if (t.id !== void 0 && t.id === e.id) return !0;
  if (t.word !== void 0)
    return t.use
      ? t.word === e[t.use]
      : (e.machine !== null && e.machine === t.word) ||
          (e.alias !== void 0 && e.alias.hasOwnProperty(t.word)) ||
          (t.fuzzy === !0 &&
            (t.word === e.root || gf(t.word, e.normal) >= t.min)) ||
          (e.alias && e.alias.some((a) => a === t.word))
        ? !0
        : t.word === e.text || t.word === e.normal;
  if (t.tag !== void 0) return e.tags.has(t.tag) === !0;
  if (t.method !== void 0)
    return typeof Wn[t.method] == "function" && Wn[t.method](e) === !0;
  if (t.pre !== void 0) return e.pre && e.pre.includes(t.pre);
  if (t.post !== void 0) return e.post && e.post.includes(t.post);
  if (t.regex !== void 0) {
    let a = e.normal;
    return (t.use && (a = e[t.use]), t.regex.test(a));
  }
  if (t.chunk !== void 0) return e.chunk === t.chunk;
  if (t.switch !== void 0) return e.switch === t.switch;
  if (t.machine !== void 0)
    return (
      e.normal === t.machine || e.machine === t.machine || e.root === t.machine
    );
  if (t.sense !== void 0) return e.sense === t.sense;
  if (t.fastOr !== void 0) {
    if (t.pos && !e.tags.has(t.pos)) return null;
    let a = e.root || e.implicit || e.machine || e.normal;
    return t.fastOr.has(a) || t.fastOr.has(e.text);
  }
  return t.choices !== void 0
    ? t.operator === "and"
      ? t.choices.every((a) => te(e, a, n, r))
      : t.choices.some((a) => te(e, a, n, r))
    : !1;
};
te = function (e, t, n, r) {
  let a = vf(e, t, n, r);
  return t.negative === !0 ? !a : a;
};
const wf = function (e, t) {
    let n = Object.assign({}, e.regs[e.r], { start: !1, end: !1 }),
      r = e.t;
    for (; e.t < e.terms.length; e.t += 1) {
      if (t && te(e.terms[e.t], t, e.start_i + e.t, e.phrase_length))
        return e.t;
      let a = e.t - r + 1;
      if (n.max !== void 0 && a === n.max) return e.t;
      if (te(e.terms[e.t], n, e.start_i + e.t, e.phrase_length) === !1)
        return n.min !== void 0 && a < n.min ? null : e.t;
    }
    return e.t;
  },
  kf = function (e, t) {
    let n = e.t;
    if (!t) return e.terms.length;
    for (; n < e.terms.length; n += 1)
      if (te(e.terms[n], t, e.start_i + n, e.phrase_length) === !0) return n;
    return null;
  },
  Pf = function (e, t) {
    if (
      e.end === !0 &&
      e.greedy === !0 &&
      t.start_i + t.t < t.phrase_length - 1
    ) {
      let n = Object.assign({}, e, { end: !1 });
      if (te(t.terms[t.t], n, t.start_i + t.t, t.phrase_length) === !0)
        return !0;
    }
    return !1;
  },
  ia = function (e, t) {
    return (
      e.groups[e.inGroup] || (e.groups[e.inGroup] = { start: t, length: 0 }),
      e.groups[e.inGroup]
    );
  },
  Af = function (e) {
    let { regs: t } = e,
      n = t[e.r],
      r = kf(e, t[e.r + 1]);
    if (r === null || r === 0 || (n.min !== void 0 && r - e.t < n.min))
      return null;
    if (n.max !== void 0 && r - e.t > n.max) return ((e.t = e.t + n.max), !0);
    if (e.hasGroup === !0) {
      const a = ia(e, e.t);
      a.length = r - e.t;
    }
    return ((e.t = r), !0);
  },
  xf = function (e) {
    return Object.prototype.toString.call(e) === "[object Array]";
  },
  Tu = function (e, t = 0) {
    let n = e.regs[e.r],
      r = !1;
    for (let a = 0; a < n.choices.length; a += 1) {
      let i = n.choices[a];
      if (!xf(i)) return !1;
      if (
        ((r = i.every((o, s) => {
          let l = 0,
            u = e.t + s + t + l;
          if (e.terms[u] === void 0) return !1;
          let c = te(e.terms[u], o, u + e.start_i, e.phrase_length);
          if (c === !0 && o.greedy === !0)
            for (let h = 1; h < e.terms.length; h += 1) {
              let f = e.terms[u + h];
              if (f)
                if (te(f, o, e.start_i + h, e.phrase_length) === !0) l += 1;
                else break;
            }
          return ((t += l), c);
        })),
        r)
      ) {
        t += i.length;
        break;
      }
    }
    return r && n.greedy === !0 ? Tu(e, t) : t;
  },
  Cf = function (e) {
    let t = 0;
    return e.regs[e.r].choices.every((a) => {
      let i = a.every((o, s) => {
        let l = e.t + s;
        return e.terms[l] === void 0
          ? !1
          : te(e.terms[l], o, l, e.phrase_length);
      });
      return (i === !0 && a.length > t && (t = a.length), i);
    }) === !0
      ? t
      : !1;
  },
  Df = function (e) {
    const { regs: t } = e;
    let n = t[e.r],
      r = Tu(e);
    if (r) {
      if (n.negative === !0) return null;
      if (e.hasGroup === !0) {
        const a = ia(e, e.t);
        a.length += r;
      }
      if (n.end === !0) {
        let a = e.phrase_length;
        if (e.t + e.start_i + r !== a) return null;
      }
      return ((e.t += r), !0);
    } else if (!n.optional) return null;
    return !0;
  },
  $f = function (e) {
    const { regs: t } = e;
    let n = t[e.r],
      r = Cf(e);
    if (r) {
      if (n.negative === !0) return null;
      if (e.hasGroup === !0) {
        const a = ia(e, e.t);
        a.length += r;
      }
      if (n.end === !0) {
        let a = e.phrase_length - 1;
        if (e.t + e.start_i !== a) return null;
      }
      return ((e.t += r), !0);
    } else if (!n.optional) return null;
    return !0;
  },
  jf = function (e, t, n) {
    let r = 0;
    for (let a = e.t; a < e.terms.length; a += 1) {
      let i = te(e.terms[a], t, e.start_i + e.t, e.phrase_length);
      if (
        i ||
        (n && ((i = te(e.terms[a], n, e.start_i + e.t, e.phrase_length)), i)) ||
        ((r += 1), t.max !== void 0 && r === t.max)
      )
        break;
    }
    return r === 0 || (t.min && t.min > r) ? !1 : ((e.t += r), !0);
  },
  Nf = function (e) {
    const { regs: t } = e;
    let n = t[e.r],
      r = Object.assign({}, n);
    if (
      ((r.negative = !1), te(e.terms[e.t], r, e.start_i + e.t, e.phrase_length))
    )
      return !1;
    if (n.optional) {
      let i = t[e.r + 1];
      i &&
        (te(e.terms[e.t], i, e.start_i + e.t, e.phrase_length)
          ? (e.r += 1)
          : i.optional &&
            t[e.r + 2] &&
            te(e.terms[e.t], t[e.r + 2], e.start_i + e.t, e.phrase_length) &&
            (e.r += 2));
    }
    return n.greedy ? jf(e, r, t[e.r + 1]) : ((e.t += 1), !0);
  },
  Tf = function (e) {
    const { regs: t } = e;
    let n = t[e.r],
      r = e.terms[e.t],
      a = te(r, t[e.r + 1], e.start_i + e.t, e.phrase_length);
    if (n.negative || a) {
      let i = e.terms[e.t + 1];
      (!i || !te(i, t[e.r + 1], e.start_i + e.t, e.phrase_length)) &&
        (e.r += 1);
    }
  },
  Of = function (e) {
    const { regs: t, phrase_length: n } = e;
    let r = t[e.r];
    return (
      (e.t = wf(e, t[e.r + 1])),
      e.t === null ||
      (r.min && r.min > e.t) ||
      (r.end === !0 && e.start_i + e.t !== n)
        ? null
        : !0
    );
  },
  If = function (e) {
    let t = e.terms[e.t],
      n = e.regs[e.r];
    if (t.implicit && e.terms[e.t + 1]) {
      if (!e.terms[e.t + 1].implicit) return;
      (n.word === t.normal && (e.t += 1),
        n.method === "hasContraction" && (e.t += 1));
    }
  },
  Ef = function (e, t) {
    let n = e.regs[e.r];
    const r = ia(e, t);
    e.t > 1 && n.greedy ? (r.length += e.t - t) : r.length++;
  },
  ma = function (e) {
    const { regs: t } = e;
    let n = t[e.r],
      r = e.terms[e.t],
      a = e.t;
    return n.optional && t[e.r + 1] && n.negative
      ? !0
      : (n.optional && t[e.r + 1] && Tf(e),
        r.implicit && e.terms[e.t + 1] && If(e),
        (e.t += 1),
        (n.end === !0 && e.t !== e.terms.length && n.greedy !== !0) ||
        (n.greedy === !0 && !Of(e))
          ? null
          : (e.hasGroup === !0 && Ef(e, a), !0));
  },
  _i = function (e, t, n, r) {
    if (e.length === 0 || t.length === 0) return null;
    let a = {
      t: 0,
      terms: e,
      r: 0,
      regs: t,
      groups: {},
      start_i: n,
      phrase_length: r,
      inGroup: null,
    };
    for (; a.r < t.length; a.r += 1) {
      let s = t[a.r];
      if (
        ((a.hasGroup = !!s.group),
        a.hasGroup === !0 ? (a.inGroup = s.group) : (a.inGroup = null),
        !a.terms[a.t])
      ) {
        if (t.slice(a.r).some((c) => !c.optional) === !1) break;
        return null;
      }
      if (s.anything === !0 && s.greedy === !0) {
        if (!Af(a)) return null;
        continue;
      }
      if (s.choices !== void 0 && s.operator === "or") {
        if (!Df(a)) return null;
        continue;
      }
      if (s.choices !== void 0 && s.operator === "and") {
        if (!$f(a)) return null;
        continue;
      }
      if (s.anything === !0) {
        if ((s.negative && s.anything) || !ma(a)) return null;
        continue;
      }
      if (Pf(s, a) === !0) {
        if (!ma(a)) return null;
        continue;
      }
      if (s.negative) {
        if (!Nf(a)) return null;
        continue;
      }
      if (te(a.terms[a.t], s, a.start_i + a.t, a.phrase_length) === !0) {
        if (!ma(a)) return null;
        continue;
      }
      if (s.optional !== !0) return null;
    }
    let i = [null, n, a.t + n];
    if (i[1] === i[2]) return null;
    let o = {};
    return (
      Object.keys(a.groups).forEach((s) => {
        let l = a.groups[s],
          u = n + l.start;
        o[s] = [null, u, u + l.length];
      }),
      { pointer: i, groups: o }
    );
  },
  Hf = function (e, t) {
    let n = [],
      r = {};
    return e.length === 0
      ? { ptrs: n, byGroup: r }
      : (typeof t == "number" && (t = String(t)),
        t
          ? e.forEach((a) => {
              a.groups[t] && n.push(a.groups[t]);
            })
          : e.forEach((a) => {
              (n.push(a.pointer),
                Object.keys(a.groups).forEach((i) => {
                  ((r[i] = r[i] || []), r[i].push(a.groups[i]));
                }));
            }),
        { ptrs: n, byGroup: r });
  },
  zf = function (e, t, n) {
    return (
      (e = e.filter((r) => {
        let [a, i, o] = r.pointer,
          s = n[a].slice(i, o);
        for (let l = 0; l < s.length; l += 1) {
          let u = s.slice(l);
          if (_i(u, t, l, s.length) !== null) return !1;
        }
        return !0;
      })),
      e
    );
  },
  Ou = function (e, t) {
    return (
      (e.pointer[0] = t),
      Object.keys(e.groups).forEach((n) => {
        e.groups[n][0] = t;
      }),
      e
    );
  },
  Ff = function (e, t, n) {
    let r = _i(e, t, 0, e.length);
    return r ? ((r = Ou(r, n)), r) : null;
  },
  Vf = function (e, t, n) {
    n = n || [];
    let { regs: r, group: a, justOne: i } = t,
      o = [];
    if (!r || r.length === 0) return { ptrs: [], byGroup: {} };
    const s = r.filter((l) => l.optional !== !0 && l.negative !== !0).length;
    e: for (let l = 0; l < e.length; l += 1) {
      let u = e[l];
      if (!(n[l] && mf(r, n[l]))) {
        if (r[0].start === !0) {
          let c = Ff(u, r, l);
          c && o.push(c);
          continue;
        }
        for (let c = 0; c < u.length; c += 1) {
          let h = u.slice(c);
          if (h.length < s) break;
          let f = _i(h, r, c, u.length);
          if (f) {
            if (((f = Ou(f, l)), o.push(f), i === !0)) break e;
            let $ = f.pointer[2];
            Math.abs($ - 1) > c && (c = Math.abs($ - 1));
          }
        }
      }
    }
    return (
      r[r.length - 1].end === !0 &&
        (o = o.filter((l) => {
          let u = l.pointer[0];
          return e[u].length === l.pointer[2];
        })),
      t.notIf && (o = zf(o, t.notIf, e)),
      (o = Hf(o, a)),
      o.ptrs.forEach((l) => {
        let [u, c, h] = l;
        ((l[3] = e[u][c].id), (l[4] = e[u][h - 1].id));
      }),
      o
    );
  },
  Gf = { one: { termMethods: Wn, parseMatch: df, match: Vf } },
  Sf = {
    parseMatch: function (e, t) {
      const n = this.world();
      let r = n.methods.one.killUnicode;
      return (r && (e = r(e, n)), n.methods.one.parseMatch(e, t, n));
    },
  },
  Mf = { api: Qd, methods: Gf, lib: Sf },
  Bf = /^\../,
  Lf = /^#./,
  Wf = (e) => (
    (e = e.replace(/&/g, "&amp;")),
    (e = e.replace(/</g, "&lt;")),
    (e = e.replace(/>/g, "&gt;")),
    (e = e.replace(/"/g, "&quot;")),
    (e = e.replace(/'/g, "&apos;")),
    e
  ),
  qf = function (e) {
    let t = "",
      n = "</span>";
    return (
      (e = Wf(e)),
      Bf.test(e)
        ? (t = `<span class="${e.replace(/^\./, "")}"`)
        : Lf.test(e)
          ? (t = `<span id="${e.replace(/^#/, "")}"`)
          : ((t = `<${e}`), (n = `</${e}>`)),
      (t += ">"),
      { start: t, end: n }
    );
  },
  Kf = function (e, t) {
    let n = {},
      r = {};
    return (
      Object.keys(t).forEach((a) => {
        let i = t[a],
          o = qf(a);
        (typeof i == "string" && (i = e.match(i)),
          i.docs.forEach((s) => {
            if (s.every((c) => c.implicit)) return;
            let l = s[0].id;
            ((n[l] = n[l] || []), n[l].push(o.start));
            let u = s[s.length - 1].id;
            ((r[u] = r[u] || []), r[u].push(o.end));
          }));
      }),
      { starts: n, ends: r }
    );
  },
  Jf = function (e) {
    let { starts: t, ends: n } = Kf(this, e),
      r = "";
    return (
      this.docs.forEach((a) => {
        for (let i = 0; i < a.length; i += 1) {
          let o = a[i];
          (t.hasOwnProperty(o.id) && (r += t[o.id].join("")),
            (r += o.pre || ""),
            (r += o.text || ""),
            n.hasOwnProperty(o.id) && (r += n[o.id].join("")),
            (r += o.post || ""));
        }
      }),
      r
    );
  },
  _f = { html: Jf },
  Iu =
    /[,:;)\]*.?~!\u0022\uFF02\u201D\u2019\u00BB\u203A\u2032\u2033\u2034\u301E\u00B4—-]+$/,
  oi =
    /^[(['"*~\uFF02\u201C\u2018\u201F\u201B\u201E\u2E42\u201A\u00AB\u2039\u2035\u2036\u2037\u301D\u0060\u301F]+/,
  Uf = /[,:;)('"\u201D\]]/,
  Rf = /^[-–—]$/,
  Yf = / /,
  Gt = function (e, t, n = !0) {
    let r = "";
    return (
      e.forEach((a) => {
        let i = a.pre || "",
          o = a.post || "";
        (t.punctuation === "some" &&
          ((i = i.replace(oi, "")),
          Rf.test(o) && (o = " "),
          (o = o.replace(Uf, "")),
          (o = o.replace(/\?!+/, "?")),
          (o = o.replace(/!+/, "!")),
          (o = o.replace(/\?+/, "?")),
          (o = o.replace(/\.{2,}/, "")),
          a.tags.has("Abbreviation") && (o = o.replace(/\./, ""))),
          t.whitespace === "some" &&
            ((i = i.replace(/\s/, "")), (o = o.replace(/\s+/, " "))),
          t.keepPunct ||
            ((i = i.replace(oi, "")),
            o === "-" ? (o = " ") : (o = o.replace(Iu, ""))));
        let s = a[t.form || "text"] || a.normal || "";
        (t.form === "implicit" && (s = a.implicit || a.text),
          t.form === "root" &&
            a.implicit &&
            (s = a.root || a.implicit || a.normal),
          (t.form === "machine" ||
            t.form === "implicit" ||
            t.form === "root") &&
            a.implicit &&
            (!o || !Yf.test(o)) &&
            (o += " "),
          (r += i + s + o));
      }),
      n === !1 && (r = r.trim()),
      t.lowerCase === !0 && (r = r.toLowerCase()),
      r
    );
  },
  Qf = function (e, t) {
    let n = "";
    if (!e || !e[0] || !e[0][0]) return n;
    for (let r = 0; r < e.length; r += 1) n += Gt(e[r], t, !0);
    if ((t.keepSpace || (n = n.trim()), t.keepEndPunct === !1)) {
      e[0][0].tags.has("Emoticon") || (n = n.replace(oi, ""));
      let r = e[e.length - 1];
      (r[r.length - 1].tags.has("Emoticon") || (n = n.replace(Iu, "")),
        n.endsWith("'") && !n.endsWith("s'") && (n = n.replace(/'/, "")));
    }
    return (t.cleanWhitespace === !0 && (n = n.trim()), n);
  },
  Dt = {
    text: { form: "text" },
    normal: {
      whitespace: "some",
      punctuation: "some",
      case: "some",
      unicode: "some",
      form: "normal",
    },
    machine: {
      keepSpace: !1,
      whitespace: "some",
      punctuation: "some",
      case: "none",
      unicode: "some",
      form: "machine",
    },
    root: {
      keepSpace: !1,
      whitespace: "some",
      punctuation: "some",
      case: "some",
      unicode: "some",
      form: "root",
    },
    implicit: { form: "implicit" },
  };
Dt.clean = Dt.normal;
Dt.reduced = Dt.root;
let Eu = [],
  Lt = 0;
for (; Lt < 64;) Eu[Lt] = 0 | (Math.sin(++Lt % Math.PI) * 4294967296);
const Ui = function (e) {
    let t,
      n,
      r,
      a = [(t = 1732584193), (n = 4023233417), ~t, ~n],
      i = [],
      o = decodeURI(encodeURI(e)) + "",
      s = o.length;
    for (e = (--s / 4 + 2) | 15, i[--e] = s * 8; ~s;)
      i[s >> 2] |= o.charCodeAt(s) << (8 * s--);
    for (Lt = o = 0; Lt < e; Lt += 16) {
      for (
        s = a;
        o < 64;
        s = [
          (r = s[3]),
          t +
            (((r =
              s[0] +
              [(t & n) | (~t & r), (r & t) | (~r & n), t ^ n ^ r, n ^ (t | ~r)][
                (s = o >> 4)
              ] +
              Eu[o] +
              ~~i[Lt | ([o, 5 * o + 1, 3 * o + 5, 7 * o][s] & 15)]) <<
              (s = [7, 12, 17, 22, 5, 9, 14, 20, 4, 11, 16, 23, 6, 10, 15, 21][
                4 * s + (o++ % 4)
              ])) |
              (r >>> -s)),
          t,
          n,
        ]
      )
        ((t = s[1] | 0), (n = s[2]));
      for (o = 4; o;) a[--o] += s[o];
    }
    for (e = ""; o < 32;)
      e += ((a[o >> 3] >> ((1 ^ o++) * 4)) & 15).toString(16);
    return e;
  },
  Zf = { text: !0, terms: !0 };
let Lo = {
  case: "none",
  unicode: "some",
  form: "machine",
  punctuation: "some",
};
const pa = function (e, t) {
    return Object.assign({}, e, t);
  },
  ht = {
    text: (e) => Gt(e, { keepPunct: !0 }, !1),
    normal: (e) => Gt(e, pa(Dt.normal, { keepPunct: !0 }), !1),
    implicit: (e) => Gt(e, pa(Dt.implicit, { keepPunct: !0 }), !1),
    machine: (e) => Gt(e, Lo, !1),
    root: (e) => Gt(e, pa(Lo, { form: "root" }), !1),
    hash: (e) => Ui(Gt(e, { keepPunct: !0 }, !1)),
    offset: (e) => {
      let t = ht.text(e).length;
      return { index: e[0].offset.index, start: e[0].offset.start, length: t };
    },
    terms: (e) =>
      e.map((t) => {
        let n = Object.assign({}, t);
        return ((n.tags = Array.from(t.tags)), n);
      }),
    confidence: (e, t, n) => t.eq(n).confidence(),
    syllables: (e, t, n) => t.eq(n).syllables(),
    sentence: (e, t, n) => t.eq(n).fullSentence().text(),
    dirty: (e) => e.some((t) => t.dirty === !0),
  };
ht.sentences = ht.sentence;
ht.clean = ht.normal;
ht.reduced = ht.root;
const Xf = function (e, t) {
    return (
      (t = t || {}),
      typeof t == "string" && (t = {}),
      (t = Object.assign({}, Zf, t)),
      t.offset && e.compute("offset"),
      e.docs.map((n, r) => {
        let a = {};
        return (
          Object.keys(t).forEach((i) => {
            t[i] && ht[i] && (a[i] = ht[i](n, e, r));
          }),
          a
        );
      })
    );
  },
  si = {
    json: function (e) {
      let t = Xf(this, e);
      return typeof e == "number" ? t[e] : t;
    },
  };
si.data = si.json;
const em = () => typeof window < "u" && window.document,
  tm = function (e) {
    let t = this.methods.one.debug || {};
    return e && t.hasOwnProperty(e)
      ? (t[e](this), this)
      : em()
        ? (t.clientSide(this), this)
        : (t.tags(this), this);
  },
  nm = function (e) {
    let t = e.pre || "",
      n = e.post || "";
    return t + e.text + n;
  },
  rm = function (e, t) {
    let n = {};
    return (
      Object.keys(t).forEach((r) => {
        e.match(r).fullPointer.forEach((i) => {
          n[i[3]] = { fn: t[r], end: i[2] };
        });
      }),
      n
    );
  },
  Hu = function (e, t) {
    let n = rm(e, t),
      r = "";
    return (
      e.docs.forEach((a, i) => {
        for (let o = 0; o < a.length; o += 1) {
          let s = a[o];
          if (n.hasOwnProperty(s.id)) {
            let { fn: l, end: u } = n[s.id],
              c = e.update([[i, o, u]]);
            ((r += a[o].pre || ""),
              (r += l(c)),
              (o = u - 1),
              (r += a[o].post || ""));
          } else r += nm(s);
        }
      }),
      r
    );
  },
  am = (e) => Object.prototype.toString.call(e) === "[object Object]",
  im = function (e) {
    let t = {};
    return (
      e.forEach((r) => {
        ((t[r] = t[r] || 0), (t[r] += 1));
      }),
      Object.keys(t)
        .map((r) => ({ normal: r, count: t[r] }))
        .sort((r, a) => (r.count > a.count ? -1 : 0))
    );
  },
  om = function (e) {
    if (am(e)) return Hu(this, e);
    if (e === "text") return this.text();
    if (e === "normal") return this.text("normal");
    if (e === "root") return this.text("root");
    if (e === "machine" || e === "reduced") return this.text("machine");
    if (e === "hash" || e === "md5") return Ui(this.text());
    if (e === "json") return this.json();
    if (e === "offset" || e === "offsets")
      return (this.compute("offset"), this.json({ offset: !0 }));
    if (e === "array")
      return this.docs
        .map((n) => n.reduce((r, a) => r + a.pre + a.text + a.post, "").trim())
        .filter((n) => n);
    if (e === "freq" || e === "frequency" || e === "topk")
      return im(this.json({ normal: !0 }).map((t) => t.normal));
    if (e === "terms") {
      let t = [];
      return (
        this.docs.forEach((n) => {
          let r = n.map((a) => a.text);
          ((r = r.filter((a) => a)), (t = t.concat(r)));
        }),
        t
      );
    }
    return e === "tags"
      ? this.docs.map((t) =>
          t.reduce(
            (n, r) => ((n[r.implicit || r.normal] = Array.from(r.tags)), n),
            {},
          ),
        )
      : e === "debug"
        ? this.debug()
        : this.text();
  },
  sm = {
    debug: tm,
    out: om,
    wrap: function (e) {
      return Hu(this, e);
    },
  },
  lm = (e) => Object.prototype.toString.call(e) === "[object Object]",
  um = {
    text: function (e) {
      let t = {};
      if (
        (e && typeof e == "string" && Dt.hasOwnProperty(e)
          ? (t = Object.assign({}, Dt[e]))
          : e && lm(e) && (t = Object.assign({}, e)),
        t.keepSpace === void 0 && !this.isFull() && (t.keepSpace = !1),
        t.keepEndPunct === void 0 && this.pointer)
      ) {
        let n = this.pointer[0];
        n && n[1] ? (t.keepEndPunct = !1) : (t.keepEndPunct = !0);
      }
      return (
        t.keepPunct === void 0 && (t.keepPunct = !0),
        t.keepSpace === void 0 && (t.keepSpace = !0),
        Qf(this.docs, t)
      );
    },
  },
  cm = Object.assign({}, sm, um, si, _f),
  hm = function (e) {
    Object.assign(e.prototype, cm);
  },
  dm = function (e) {
    (console.log("%c -=-=- ", "background-color:#6699cc;"),
      e.forEach((t) => {
        console.groupCollapsed(t.text());
        let r = t.docs[0].map((a) => {
          let i = a.text || "-";
          a.implicit && (i = "[" + a.implicit + "]");
          let o = "[" + Array.from(a.tags).join(", ") + "]";
          return { text: i, tags: o };
        });
        (console.table(r, ["text", "tags"]), console.groupEnd());
      }));
  },
  Qe = "\x1B[0m",
  ke = {
    green: (e) => "\x1B[32m" + e + Qe,
    red: (e) => "\x1B[31m" + e + Qe,
    blue: (e) => "\x1B[34m" + e + Qe,
    magenta: (e) => "\x1B[35m" + e + Qe,
    cyan: (e) => "\x1B[36m" + e + Qe,
    yellow: (e) => "\x1B[33m" + e + Qe,
    black: (e) => "\x1B[30m" + e + Qe,
    dim: (e) => "\x1B[2m" + e + Qe,
    i: (e) => "\x1B[3m" + e + Qe,
  },
  fm = function (e, t) {
    return (
      t.one.tagSet &&
        (e = e.map((n) => {
          if (!t.one.tagSet.hasOwnProperty(n)) return n;
          const r = t.one.tagSet[n].color || "blue";
          return ke[r](n);
        })),
      e.join(", ")
    );
  },
  mm = function (e) {
    let { docs: t, model: n } = e;
    (t.length === 0 &&
      console.log(
        ke.blue(`
     ──────`),
      ),
      t.forEach((r) => {
        (console.log(
          ke.blue(`
  ┌─────────`),
        ),
          r.forEach((a) => {
            let i = [...(a.tags || [])],
              o = a.text || "-";
            (a.sense && (o = `{${a.normal}/${a.sense}}`),
              a.implicit && (o = "[" + a.implicit + "]"),
              (o = ke.yellow(o)));
            let s = "'" + o + "'";
            if (a.reference) {
              let u = e.update([a.reference]).text("normal");
              s += ` - ${ke.dim(ke.i("[" + u + "]"))}`;
            }
            s = s.padEnd(18);
            let l = ke.blue("  │ ") + ke.i(s) + "  - " + fm(i, n);
            console.log(l);
          }));
      }),
      console.log(`
`));
  },
  pm = function (e) {
    let { docs: t } = e;
    (console.log(""),
      t.forEach((n) => {
        let r = [];
        (n.forEach((a) => {
          a.chunk === "Noun"
            ? r.push(ke.blue(a.implicit || a.normal))
            : a.chunk === "Verb"
              ? r.push(ke.green(a.implicit || a.normal))
              : a.chunk === "Adjective"
                ? r.push(ke.yellow(a.implicit || a.normal))
                : a.chunk === "Pivot"
                  ? r.push(ke.red(a.implicit || a.normal))
                  : r.push(a.implicit || a.normal);
        }),
          console.log(
            r.join(" "),
            `
`,
          ));
      }),
      console.log(`
`));
  },
  gm = (e, t, n) => {
    let r = n * 9,
      a = t.start + r,
      i = a + t.length,
      o = e.substring(0, a),
      s = e.substring(a, i),
      l = e.substring(i, e.length);
    return [o, s, l];
  },
  ym = function (e, t, n) {
    let r = gm(e, t, n);
    return `${r[0]}${ke.blue(r[1])}${r[2]}`;
  },
  bm = function (e) {
    if (!e.found) return;
    let t = {};
    (e.fullPointer.forEach((n) => {
      ((t[n[0]] = t[n[0]] || []), t[n[0]].push(n));
    }),
      Object.keys(t).forEach((n) => {
        let a = e.update([[Number(n)]]).text();
        (e
          .update(t[n])
          .json({ offset: !0 })
          .forEach((s, l) => {
            a = ym(a, s.offset, l);
          }),
          console.log(a));
      }),
      console.log(`
`));
  },
  vm = { tags: mm, clientSide: dm, chunks: pm, highlight: bm },
  wm = { api: hm, methods: { one: { hash: Ui, debug: vm } } },
  zu = function (e, t) {
    if (e[0] !== t[0]) return !1;
    let [, n, r] = e,
      [, a, i] = t;
    return (n <= a && r > a) || (a <= n && i > n);
  },
  km = function (e) {
    let t = e[0][1],
      n = e[0][2];
    return (
      e.forEach((r) => {
        (r[1] < t && (t = r[1]), r[2] > n && (n = r[2]));
      }),
      [e[0][0], t, n]
    );
  },
  oa = function (e) {
    let t = {};
    return (
      e.forEach((n) => {
        ((t[n[0]] = t[n[0]] || []), t[n[0]].push(n));
      }),
      t
    );
  },
  Pm = function (e) {
    let t = {};
    for (let n = 0; n < e.length; n += 1) t[e[n].join(",")] = e[n];
    return Object.values(t);
  },
  Am = function (e, t) {
    let [n, r] = e,
      a = t[1],
      i = t[2],
      o = {};
    if (r < a) {
      let s = a < e[2] ? a : e[2];
      o.before = [n, r, s];
    }
    return ((o.match = t), e[2] > i && (o.after = [n, i, e[2]]), o);
  },
  xm = function (e, t) {
    return e[1] <= t[1] && t[2] <= e[2];
  },
  Fu = function (e, t) {
    let n = oa(t),
      r = [];
    return (
      e.forEach((a) => {
        let [i] = a,
          o = n[i] || [];
        if (((o = o.filter((l) => xm(a, l))), o.length === 0)) {
          r.push({ passthrough: a });
          return;
        }
        o = o.sort((l, u) => l[1] - u[1]);
        let s = a;
        o.forEach((l, u) => {
          let c = Am(s, l);
          o[u + 1]
            ? (r.push({ before: c.before, match: c.match }),
              c.after && (s = c.after))
            : r.push(c);
        });
      }),
      r
    );
  },
  Cm = 20,
  Dm = function (e, t, n) {
    for (let r = 0; r < Cm; r += 1) {
      if (t[n - r]) {
        let a = t[n - r].findIndex((i) => i.id === e);
        if (a !== -1) return [n - r, a];
      }
      if (t[n + r]) {
        let a = t[n + r].findIndex((i) => i.id === e);
        if (a !== -1) return [n + r, a];
      }
    }
    return null;
  },
  $m = function (e, t) {
    let [n, r, , , a] = e,
      i = t[n],
      o = i.findIndex((s) => s.id === a);
    return (
      o === -1
        ? ((e[2] = t[n].length), (e[4] = i.length ? i[i.length - 1].id : null))
        : (e[2] = o),
      t[n].slice(r, e[2] + 1)
    );
  },
  jm = function (e, t) {
    let n = [];
    return (
      e.forEach((r, a) => {
        if (!r) return;
        let [i, o, s, l, u] = r,
          c = t[i] || [];
        if (
          (o === void 0 && (o = 0),
          s === void 0 && (s = c.length),
          l && (!c[o] || c[o].id !== l))
        ) {
          let h = Dm(l, t, i);
          if (h !== null) {
            let f = s - o;
            c = t[h[0]].slice(h[1], h[1] + f);
            let $ = c[0] ? c[0].id : null;
            e[a] = [h[0], h[1], h[1] + f, $];
          }
        } else c = c.slice(o, s);
        c.length !== 0 &&
          o !== s &&
          (u && c[c.length - 1].id !== u && (c = $m(r, t)), n.push(c));
      }),
      (n = n.filter((r) => r.length > 0)),
      n
    );
  },
  Nm = function (e) {
    let t = [];
    for (let n = 0; n < e.length; n += 1)
      for (let r = 0; r < e[n].length; r += 1) t.push(e[n][r]);
    return t;
  },
  Tm = {
    one: { termList: Nm, getDoc: jm, pointer: { indexN: oa, splitAll: Fu } },
  },
  Vu = function (e, t) {
    let n = e.concat(t),
      r = oa(n),
      a = [];
    return (
      n.forEach((i) => {
        let [o] = i;
        if (r[o].length === 1) {
          a.push(i);
          return;
        }
        let s = r[o].filter((u) => zu(i, u));
        s.push(i);
        let l = km(s);
        a.push(l);
      }),
      (a = Pm(a)),
      a
    );
  },
  Gu = function (e, t) {
    let n = [];
    return (
      Fu(e, t).forEach((a) => {
        (a.passthrough && n.push(a.passthrough),
          a.before && n.push(a.before),
          a.after && n.push(a.after));
      }),
      n
    );
  },
  Om = function (e, t) {
    let n = e[1] < t[1] ? t[1] : e[1],
      r = e[2] > t[2] ? t[2] : e[2];
    return n < r ? [e[0], n, r] : null;
  },
  Im = function (e, t) {
    let n = oa(t),
      r = [];
    return (
      e.forEach((a) => {
        let i = n[a[0]] || [];
        ((i = i.filter((o) => zu(a, o))),
          i.length !== 0 &&
            i.forEach((o) => {
              let s = Om(a, o);
              s && r.push(s);
            }));
      }),
      r
    );
  },
  Em = function (e) {
    return Object.prototype.toString.call(e) === "[object Array]";
  },
  Ri = (e, t) => (typeof e == "string" || Em(e) ? t.match(e) : e || t.none()),
  Xn = function (e, t) {
    return e.map((n) => {
      let [r, a] = n;
      return (t[r] && t[r][a] && (n[3] = t[r][a].id), n);
    });
  },
  Ye = {};
Ye.union = function (e) {
  e = Ri(e, this);
  let t = Vu(this.fullPointer, e.fullPointer);
  return ((t = Xn(t, this.document)), this.toView(t));
};
Ye.and = Ye.union;
Ye.intersection = function (e) {
  e = Ri(e, this);
  let t = Im(this.fullPointer, e.fullPointer);
  return ((t = Xn(t, this.document)), this.toView(t));
};
Ye.not = function (e) {
  e = Ri(e, this);
  let t = Gu(this.fullPointer, e.fullPointer);
  return ((t = Xn(t, this.document)), this.toView(t));
};
Ye.difference = Ye.not;
Ye.complement = function () {
  let e = this.all(),
    t = Gu(e.fullPointer, this.fullPointer);
  return ((t = Xn(t, this.document)), this.toView(t));
};
Ye.settle = function () {
  let e = this.fullPointer;
  return (
    e.forEach((t) => {
      e = Vu(e, [t]);
    }),
    (e = Xn(e, this.document)),
    this.update(e)
  );
};
const Hm = function (e) {
    Object.assign(e.prototype, Ye);
  },
  zm = { methods: Tm, api: Hm },
  Fm = {
    buildNet: function (e) {
      let n = this.methods().one.buildNet(e, this.world());
      return ((n.isNet = !0), n);
    },
  },
  Vm = function (e) {
    e.prototype.sweep = function (t, n = {}) {
      const { world: r, docs: a } = this,
        { methods: i } = r;
      let o = i.one.bulkMatch(a, t, this.methods, n);
      (n.tagger !== !1 && i.one.bulkTagger(o, a, this.world),
        (o = o.map((l) => {
          let u = l.pointer,
            c = a[u[0]][u[1]],
            h = u[2] - u[1];
          return (
            c.index && (l.pointer = [c.index[0], c.index[1], u[1] + h]),
            l
          );
        })));
      let s = o.map((l) => l.pointer);
      return (
        (o = o.map(
          (l) => (
            (l.view = this.update([l.pointer])),
            delete l.regs,
            delete l.needs,
            delete l.pointer,
            delete l._expanded,
            l
          ),
        )),
        { view: this.update(s), found: o }
      );
    };
  },
  li = function (e) {
    return e.optional === !0 || e.negative === !0
      ? null
      : e.tag
        ? "#" + e.tag
        : e.word
          ? e.word
          : e.switch
            ? `%${e.switch}%`
            : null;
  },
  Gm = function (e) {
    let t = [];
    return (
      e.forEach((n) => {
        (t.push(li(n)),
          n.operator === "and" &&
            n.choices &&
            n.choices.forEach((r) => {
              r.forEach((a) => {
                t.push(li(a));
              });
            }));
      }),
      t.filter((n) => n)
    );
  },
  Sm = function (e) {
    let t = [],
      n = 0;
    return (
      e.forEach((r) => {
        r.operator === "or" &&
          !r.optional &&
          !r.negative &&
          (r.fastOr &&
            Array.from(r.fastOr).forEach((a) => {
              t.push(a);
            }),
          r.choices &&
            r.choices.forEach((a) => {
              a.forEach((i) => {
                let o = li(i);
                o && t.push(o);
              });
            }),
          (n += 1));
      }),
      { wants: t, count: n }
    );
  },
  Mm = function (e, t) {
    const n = t.methods.one.parseMatch;
    return (
      e.forEach((r) => {
        ((r.regs = n(r.match, {}, t)),
          typeof r.ifNo == "string" && (r.ifNo = [r.ifNo]),
          r.notIf && (r.notIf = n(r.notIf, {}, t)),
          (r.needs = Gm(r.regs)));
        let { wants: a, count: i } = Sm(r.regs);
        ((r.wants = a),
          (r.minWant = i),
          (r.minWords = r.regs.filter((o) => !o.optional).length));
      }),
      e
    );
  },
  Bm = function (e, t) {
    e = Mm(e, t);
    let n = {};
    (e.forEach((a) => {
      (a.needs.forEach((i) => {
        ((n[i] = Array.isArray(n[i]) ? n[i] : []), n[i].push(a));
      }),
        a.wants.forEach((i) => {
          ((n[i] = Array.isArray(n[i]) ? n[i] : []), n[i].push(a));
        }));
    }),
      Object.keys(n).forEach((a) => {
        let i = {};
        n[a] = n[a].filter((o) =>
          typeof i[o.match] == "boolean" ? !1 : ((i[o.match] = !0), !0),
        );
      }));
    let r = e.filter((a) => a.needs.length === 0 && a.wants.length === 0);
    return { hooks: n, always: r };
  },
  Lm = function (e, t) {
    return e.map((n, r) => {
      let a = [];
      Object.keys(t).forEach((o) => {
        e[r].has(o) && (a = a.concat(t[o]));
      });
      let i = {};
      return (
        (a = a.filter((o) =>
          typeof i[o.match] == "boolean" ? !1 : ((i[o.match] = !0), !0),
        )),
        a
      );
    });
  },
  Wm = function (e, t) {
    return e.map((n, r) => {
      let a = t[r];
      return (
        (n = n.filter((i) => i.needs.every((o) => a.has(o)))),
        (n = n.filter(
          (i) => !(i.ifNo !== void 0 && i.ifNo.some((o) => a.has(o)) === !0),
        )),
        (n = n.filter((i) =>
          i.wants.length === 0
            ? !0
            : i.wants.filter((s) => a.has(s)).length >= i.minWant,
        )),
        n
      );
    });
  },
  qm = function (e, t, n, r, a) {
    let i = [];
    for (let o = 0; o < e.length; o += 1)
      for (let s = 0; s < e[o].length; s += 1) {
        let l = e[o][s],
          u = r.one.match([t[o]], l);
        if (
          u.ptrs.length > 0 &&
          (u.ptrs.forEach((c) => {
            c[0] = o;
            let h = Object.assign({}, l, { pointer: c });
            (l.unTag !== void 0 && (h.unTag = l.unTag), i.push(h));
          }),
          a.matchOne === !0)
        )
          return [i[0]];
      }
    return i;
  },
  Km = function (e, t) {
    return e.map((n, r) => {
      let a = t[r].length;
      return ((n = n.filter((i) => a >= i.minWords)), n);
    });
  },
  Jm = function (e, t, n, r = {}) {
    let a = n.one.cacheDoc(e),
      i = Lm(a, t.hooks);
    return (
      (i = Wm(i, a)),
      t.always.length > 0 && (i = i.map((s) => s.concat(t.always))),
      (i = Km(i, e)),
      qm(i, e, a, n, r)
    );
  },
  _m = function (e, t, n) {
    let r = n.one.tagSet;
    if (!r.hasOwnProperty(t)) return !0;
    let a = r[t].not || [];
    for (let i = 0; i < e.length; i += 1) {
      let o = e[i];
      for (let s = 0; s < a.length; s += 1)
        if (o.tags.has(a[s]) === !0) return !1;
    }
    return !0;
  };
var Wo = {};
const Um = function (e, t, n) {
    const { model: r, methods: a } = n,
      { getDoc: i, setTag: o, unTag: s } = a.one,
      l = a.two.looksPlural;
    return e.length === 0
      ? e
      : ((typeof Nt > "u" || !Wo ? self.env || {} : Wo).DEBUG_TAGS &&
          console.log(`

  \x1B[32m→ ${e.length} post-tagger:\x1B[0m`),
        e.map((c) => {
          if (!c.tag && !c.chunk && !c.unTag) return;
          let h = c.reason || c.match,
            f = i([c.pointer], t)[0];
          if (!(
            c.safe === !0 &&
            (_m(f, c.tag, r) === !1 || f[f.length - 1].post === "-")
          )) {
            if (c.tag !== void 0) {
              if (
                (o(f, c.tag, n, c.safe, `[post] '${h}'`), c.tag === "Noun" && l)
              ) {
                let $ = f[f.length - 1];
                l($.text)
                  ? o([$], "Plural", n, c.safe, "quick-plural")
                  : o([$], "Singular", n, c.safe, "quick-singular");
              }
              c.freeze === !0 && f.forEach(($) => ($.frozen = !0));
            }
            (c.unTag !== void 0 && s(f, c.unTag, n, c.safe, h),
              c.chunk && f.forEach(($) => ($.chunk = c.chunk)));
          }
        }));
  },
  Rm = { buildNet: Bm, bulkMatch: Jm, bulkTagger: Um },
  Ym = { lib: Fm, api: Vm, methods: { one: Rm } };
var qo = {};
const Su = / /,
  Ko = function (e, t) {
    (t === "Noun" && (e.chunk = t), t === "Verb" && (e.chunk = t));
  },
  Mu = function (e, t, n, r) {
    if (e.tags.has(t) === !0 || t === ".") return null;
    e.frozen === !0 && (r = !0);
    let a = n[t];
    if (a) {
      if (a.not && a.not.length > 0)
        for (let i = 0; i < a.not.length; i += 1) {
          if (r === !0 && e.tags.has(a.not[i])) return null;
          e.tags.delete(a.not[i]);
        }
      if (a.parents && a.parents.length > 0)
        for (let i = 0; i < a.parents.length; i += 1)
          (e.tags.add(a.parents[i]), Ko(e, a.parents[i]));
    }
    return (e.tags.add(t), (e.dirty = !0), Ko(e, t), !0);
  },
  Qm = function (e, t, n, r) {
    let a = t.split(Su);
    e.forEach((i, o) => {
      let s = a[o];
      s && ((s = s.replace(/^#/, "")), Mu(i, s, n, r));
    });
  },
  Zm = function (e) {
    return Object.prototype.toString.call(e) === "[object Array]";
  },
  Xm = (e, t, n = "") => {
    const r = (o) => "\x1B[33m\x1B[3m" + o + "\x1B[0m",
      a = (o) => "\x1B[3m" + o + "\x1B[0m";
    let i = e.map((o) => o.text || "[" + o.implicit + "]").join(" ");
    (typeof t != "string" &&
      t.length > 2 &&
      (t = t.slice(0, 2).join(", #") + " +"),
      (t = typeof t != "string" ? t.join(", #") : t),
      console.log(
        ` ${r(i).padEnd(24)} \x1B[32m→\x1B[0m #${t.padEnd(22)}  ${a(n)}`,
      ));
  },
  Bu = function (e, t, n = {}, r, a) {
    const i = n.model.one.tagSet || {};
    if (!t) return;
    const o = typeof Nt > "u" || !qo ? self.env || {} : qo;
    if ((o && o.DEBUG_TAGS && Xm(e, t, a), Zm(t) === !0)) {
      t.forEach((s) => Bu(e, s, n, r));
      return;
    }
    if (typeof t != "string") {
      console.warn(`compromise: Invalid tag '${t}'`);
      return;
    }
    if (((t = t.trim()), Su.test(t))) {
      Qm(e, t, i, r);
      return;
    }
    t = t.replace(/^#/, "");
    for (let s = 0; s < e.length; s += 1) Mu(e[s], t, i, r);
  },
  ep = function (e, t, n) {
    t = t.trim().replace(/^#/, "");
    for (let r = 0; r < e.length; r += 1) {
      let a = e[r];
      if (a.frozen === !0) continue;
      if (t === "*") {
        a.tags.clear();
        continue;
      }
      let i = n[t];
      if (i && i.children.length > 0)
        for (let o = 0; o < i.children.length; o += 1)
          a.tags.delete(i.children[o]);
      a.tags.delete(t);
    }
  },
  tp = function (e, t, n) {
    if (!n.hasOwnProperty(t)) return !0;
    let r = n[t].not || [];
    for (let a = 0; a < r.length; a += 1) if (e.tags.has(r[a])) return !1;
    return !0;
  },
  kt = function (e) {
    return (
      (e.children = e.children || []),
      (e._cache = e._cache || {}),
      (e.props = e.props || {}),
      (e._cache.parents = e._cache.parents || []),
      (e._cache.children = e._cache.children || []),
      e
    );
  },
  np = /^ *(#|\/\/)/,
  rp = function (e) {
    let t = e.trim().split(/->/),
      n = [];
    (t.forEach((a) => {
      n = n.concat(
        (function (i) {
          if (!(i = i.trim())) return null;
          if (/^\[/.test(i) && /\]$/.test(i)) {
            let o = (i = (i = i.replace(/^\[/, "")).replace(/\]$/, "")).split(
              /,/,
            );
            return (
              (o = o.map((s) => s.trim()).filter((s) => s)),
              (o = o.map((s) => kt({ id: s }))),
              o
            );
          }
          return [kt({ id: i })];
        })(a),
      );
    }),
      (n = n.filter((a) => a)));
    let r = n[0];
    for (let a = 1; a < n.length; a += 1) (r.children.push(n[a]), (r = n[a]));
    return n[0];
  },
  ut = (e, t) => {
    let n = [],
      r = [e];
    for (; r.length > 0;) {
      let a = r.pop();
      (n.push(a),
        a.children &&
          a.children.forEach((i) => {
            (t && t(a, i), r.push(i));
          }));
    }
    return n;
  },
  Yi = (e) => Object.prototype.toString.call(e) === "[object Array]",
  ar = (e) => (e = e || "").trim(),
  ap = function (e = []) {
    return typeof e == "string"
      ? (function (n) {
          let r = n.split(/\r?\n/),
            a = [];
          r.forEach((o) => {
            if (!o.trim() || np.test(o)) return;
            let s = ((l) => {
              const u = /^( {2}|\t)/;
              let c = 0;
              for (; u.test(l);) ((l = l.replace(u, "")), (c += 1));
              return c;
            })(o);
            a.push({ indent: s, node: rp(o) });
          });
          let i = (function (o) {
            let s = { children: [] };
            return (
              o.forEach((l, u) => {
                l.indent === 0
                  ? (s.children = s.children.concat(l.node))
                  : o[u - 1] &&
                    (function (c, h) {
                      let f = c[h].indent;
                      for (; h >= 0; h -= 1) if (c[h].indent < f) return c[h];
                      return c[0];
                    })(o, u).node.children.push(l.node);
              }),
              s
            );
          })(a);
          return ((i = kt(i)), i);
        })(e)
      : Yi(e)
        ? (function (n) {
            let r = {};
            n.forEach((i) => {
              r[i.id] = i;
            });
            let a = kt({});
            return (
              n.forEach((i) => {
                if ((i = kt(i)).parent)
                  if (r.hasOwnProperty(i.parent)) {
                    let o = r[i.parent];
                    (delete i.parent, o.children.push(i));
                  } else console.warn(`[Grad] - missing node '${i.parent}'`);
                else a.children.push(i);
              }),
              a
            );
          })(e)
        : (ut((t = e)).forEach(kt), t);
    var t;
  },
  ip = (e) => "\x1B[31m" + e + "\x1B[0m",
  op = (e) => "\x1B[2m" + e + "\x1B[0m",
  ui = function (e, t) {
    let n = "-> ";
    t && (n = op("→ "));
    let r = "";
    return (
      ut(e).forEach((a, i) => {
        let o = a.id || "";
        if ((t && (o = ip(o)), i === 0 && !a.id)) return;
        let s = a._cache.parents.length;
        r +=
          "    ".repeat(s) +
          n +
          o +
          `
`;
      }),
      r
    );
  },
  Jo = function (e) {
    let t = ut(e);
    t.forEach((r) => {
      delete (r = Object.assign({}, r)).children;
    });
    let n = t[0];
    return (n && !n.id && Object.keys(n.props).length === 0 && t.shift(), t);
  },
  _o = { text: ui, txt: ui, array: Jo, flat: Jo },
  Uo = function (e, t) {
    return t === "nested" || t === "json"
      ? e
      : t === "debug"
        ? (console.log(ui(e, !0)), null)
        : _o.hasOwnProperty(t)
          ? _o[t](e)
          : e;
  },
  ga = (e) => {
    ut(e, (t, n) => {
      t.id &&
        ((t._cache.parents = t._cache.parents || []),
        (n._cache.parents = t._cache.parents.concat([t.id])));
    });
  },
  sp = (e, t) => (
    Object.keys(t).forEach((n) => {
      if (t[n] instanceof Set) {
        let r = e[n] || new Set();
        e[n] = new Set([...r, ...t[n]]);
      } else if (
        ((r) => r && typeof r == "object" && !Array.isArray(r))(t[n])
      ) {
        let r = e[n] || {};
        e[n] = Object.assign({}, t[n], r);
      } else
        Yi(t[n])
          ? (e[n] = t[n].concat(e[n] || []))
          : e[n] === void 0 && (e[n] = t[n]);
    }),
    e
  ),
  lp = /\//;
let up = class qr {
  constructor(t = {}) {
    Object.defineProperty(this, "json", {
      enumerable: !1,
      value: t,
      writable: !0,
    });
  }
  get children() {
    return this.json.children;
  }
  get id() {
    return this.json.id;
  }
  get found() {
    return this.json.id || this.json.children.length > 0;
  }
  props(t = {}) {
    let n = this.json.props || {};
    return (
      typeof t == "string" && (n[t] = !0),
      (this.json.props = Object.assign(n, t)),
      this
    );
  }
  get(t) {
    if (((t = ar(t)), !lp.test(t))) {
      let r = this.json.children.find((a) => a.id === t);
      return new qr(r);
    }
    let n =
      ((r, a) => {
        let i = ((o) =>
          typeof o != "string" ? o : (o = o.replace(/^\//, "")).split(/\//))(
          (a = a || ""),
        );
        for (let o = 0; o < i.length; o += 1) {
          let s = r.children.find((l) => l.id === i[o]);
          if (!s) return null;
          r = s;
        }
        return r;
      })(this.json, t) || kt({});
    return new qr(n);
  }
  add(t, n = {}) {
    if (Yi(t)) return (t.forEach((a) => this.add(ar(a), n)), this);
    t = ar(t);
    let r = kt({ id: t, props: n });
    return (this.json.children.push(r), new qr(r));
  }
  remove(t) {
    return (
      (t = ar(t)),
      (this.json.children = this.json.children.filter((n) => n.id !== t)),
      this
    );
  }
  nodes() {
    return ut(this.json).map(
      (t) => (delete (t = Object.assign({}, t)).children, t),
    );
  }
  cache() {
    return (
      ((t) => {
        let n = ut(t, (a, i) => {
            a.id &&
              ((a._cache.parents = a._cache.parents || []),
              (a._cache.children = a._cache.children || []),
              (i._cache.parents = a._cache.parents.concat([a.id])));
          }),
          r = {};
        (n.forEach((a) => {
          a.id && (r[a.id] = a);
        }),
          n.forEach((a) => {
            a._cache.parents.forEach((i) => {
              r.hasOwnProperty(i) && r[i]._cache.children.push(a.id);
            });
          }),
          (t._cache.children = Object.keys(r)));
      })(this.json),
      this
    );
  }
  list() {
    return ut(this.json);
  }
  fillDown() {
    var t;
    return (
      (t = this.json),
      ut(t, (n, r) => {
        r.props = sp(r.props, n.props);
      }),
      this
    );
  }
  depth() {
    ga(this.json);
    let t = ut(this.json),
      n = t.length > 1 ? 1 : 0;
    return (
      t.forEach((r) => {
        if (r._cache.parents.length === 0) return;
        let a = r._cache.parents.length + 1;
        a > n && (n = a);
      }),
      n
    );
  }
  out(t) {
    return (ga(this.json), Uo(this.json, t));
  }
  debug() {
    return (ga(this.json), Uo(this.json, "debug"), this);
  }
};
const Lu = function (e) {
  let t = ap(e);
  return new up(t);
};
Lu.prototype.plugin = function (e) {
  e(this);
};
const tn = {
    Noun: "blue",
    Verb: "green",
    Negative: "green",
    Date: "red",
    Value: "red",
    Adjective: "magenta",
    Preposition: "cyan",
    Conjunction: "cyan",
    Determiner: "cyan",
    Hyphenated: "cyan",
    Adverb: "cyan",
  },
  cp = function (e) {
    if (tn.hasOwnProperty(e.id)) return tn[e.id];
    if (tn.hasOwnProperty(e.is)) return tn[e.is];
    let t = e._cache.parents.find((n) => tn[n]);
    return tn[t];
  },
  hp = function (e) {
    const t = {};
    return (
      e.forEach((n) => {
        let { not: r, also: a, is: i, novel: o } = n.props,
          s = n._cache.parents;
        (a && (s = s.concat(a)),
          (t[n.id] = {
            is: i,
            not: r,
            novel: o,
            also: a,
            parents: s,
            children: n._cache.children,
            color: cp(n),
          }));
      }),
      Object.keys(t).forEach((n) => {
        let r = new Set(t[n].not);
        (t[n].not.forEach((a) => {
          t[a] && t[a].children.forEach((i) => r.add(i));
        }),
          (t[n].not = Array.from(r)));
      }),
      t
    );
  },
  Ro = function (e) {
    return e ? (typeof e == "string" ? [e] : e) : [];
  },
  dp = function (e, t) {
    return (
      Object.keys(e).forEach((n) => {
        (e[n].isA && (e[n].is = e[n].isA),
          e[n].notA && (e[n].not = e[n].notA),
          e[n].is &&
            typeof e[n].is == "string" &&
            !t.hasOwnProperty(e[n].is) &&
            !e.hasOwnProperty(e[n].is) &&
            (e[e[n].is] = {}),
          e[n].not &&
            typeof e[n].not == "string" &&
            !e.hasOwnProperty(e[n].not) &&
            !t.hasOwnProperty(e[n].not) &&
            !e.hasOwnProperty(e[n].not) &&
            (e[e[n].not] = {}));
      }),
      e
    );
  },
  fp = function (e, t) {
    return (
      (e = dp(e, t)),
      Object.keys(e).forEach((n) => {
        ((e[n].children = Ro(e[n].children)), (e[n].not = Ro(e[n].not)));
      }),
      Object.keys(e).forEach((n) => {
        (e[n].not || []).forEach((a) => {
          e[a] && e[a].not && e[a].not.push(n);
        });
      }),
      e
    );
  },
  mp = function (e) {
    const t = Object.keys(e).map((r) => {
      let a = e[r];
      const i = { not: new Set(a.not), also: a.also, is: a.is, novel: a.novel };
      return { id: r, parent: a.is, props: i, children: [] };
    });
    return Lu(t).cache().fillDown().out("array");
  },
  pp = function (e) {
    return (
      Object.keys(e).forEach((t) => {
        ((e[t] = Object.assign({}, e[t])), (e[t].novel = !0));
      }),
      e
    );
  },
  gp = function (e, t) {
    (Object.keys(t).length > 0 && (e = pp(e)), (e = fp(e, t)));
    let n = Object.assign({}, t, e);
    const r = mp(n);
    return hp(r);
  },
  yp = { one: { setTag: Bu, unTag: ep, addTags: gp, canBe: tp } },
  Yo = function (e) {
    return Object.prototype.toString.call(e) === "[object Array]";
  },
  bp = {
    tag: function (e, t = "", n) {
      if (!this.found || !e) return this;
      let r = this.termList();
      if (r.length === 0) return this;
      const { methods: a, verbose: i, world: o } = this;
      return (
        i === !0 && console.log(" +  ", e, t || ""),
        Yo(e)
          ? e.forEach((s) => a.one.setTag(r, s, o, n, t))
          : a.one.setTag(r, e, o, n, t),
        this.uncache(),
        this
      );
    },
    tagSafe: function (e, t = "") {
      return this.tag(e, t, !0);
    },
    unTag: function (e, t) {
      if (!this.found || !e) return this;
      let n = this.termList();
      if (n.length === 0) return this;
      const { methods: r, verbose: a, model: i } = this;
      a === !0 && console.log(" -  ", e, t || "");
      let o = i.one.tagSet;
      return (
        Yo(e) ? e.forEach((s) => r.one.unTag(n, s, o)) : r.one.unTag(n, e, o),
        this.uncache(),
        this
      );
    },
    canBe: function (e) {
      e = e.replace(/^#/, "");
      let t = this.model.one.tagSet,
        n = this.methods.one.canBe,
        r = [];
      this.document.forEach((i, o) => {
        i.forEach((s, l) => {
          n(s, e, t) || r.push([o, l, l + 1]);
        });
      });
      let a = this.update(r);
      return this.difference(a);
    },
  },
  vp = function (e) {
    Object.assign(e.prototype, bp);
  },
  wp = function (e) {
    const { model: t, methods: n } = this.world(),
      r = t.one.tagSet,
      a = n.one.addTags;
    let i = a(e, r);
    return ((t.one.tagSet = i), this);
  },
  kp = { addTags: wp },
  Qo = new Set(["Auxiliary", "Possessive"]),
  Pp = function (e, t) {
    return (
      (e = e.sort((n, r) => {
        if (Qo.has(n) || !t.hasOwnProperty(r)) return 1;
        if (Qo.has(r) || !t.hasOwnProperty(n)) return -1;
        let a = t[n].children || [],
          i = a.length;
        a = t[r].children || [];
        let o = a.length;
        return i - o;
      })),
      e
    );
  },
  Ap = function (e) {
    const { document: t, world: n } = e,
      r = n.model.one.tagSet;
    t.forEach((a) => {
      a.forEach((i) => {
        let o = Array.from(i.tags);
        i.tagRank = Pp(o, r);
      });
    });
  },
  xp = {
    model: { one: { tagSet: {} } },
    compute: { tagRank: Ap },
    methods: yp,
    api: vp,
    lib: kp,
  },
  Cp = /([.!?\u203D\u2E18\u203C\u2047-\u2049\u3002]+\s)/g,
  Dp = /^[.!?\u203D\u2E18\u203C\u2047-\u2049\u3002]+\s$/,
  $p = /((?:\r?\n|\r)+)/,
  jp = function (e) {
    let t = [],
      n = e.split($p);
    for (let r = 0; r < n.length; r++) {
      let a = n[r].split(Cp);
      for (let i = 0; i < a.length; i++)
        (a[i + 1] &&
          Dp.test(a[i + 1]) === !0 &&
          ((a[i] += a[i + 1]), (a[i + 1] = "")),
          a[i] !== "" && t.push(a[i]));
    }
    return t;
  },
  Np = /[a-z0-9\u00C0-\u00FF\u00a9\u00ae\u2000-\u3300\ud000-\udfff]/i,
  Tp = /\S/,
  Op = function (e) {
    let t = [];
    for (let n = 0; n < e.length; n++) {
      let r = e[n];
      if (!(r === void 0 || r === "")) {
        if (Tp.test(r) === !1 || Np.test(r) === !1) {
          if (t[t.length - 1]) {
            t[t.length - 1] += r;
            continue;
          } else if (e[n + 1]) {
            e[n + 1] = r + e[n + 1];
            continue;
          }
        }
        t.push(r);
      }
    }
    return t;
  },
  Ip = function (e, t) {
    const n = t.methods.one.tokenize.isSentence,
      r = t.model.one.abbreviations || new Set();
    let a = [];
    for (let i = 0; i < e.length; i++) {
      let o = e[i];
      e[i + 1] && n(o, r) === !1
        ? (e[i + 1] = o + (e[i + 1] || ""))
        : o && o.length > 0 && (a.push(o), (e[i] = ""));
    }
    return a;
  },
  Zo = 280,
  Wu = {
    '"': '"',
    "＂": "＂",
    "“": "”",
    "‟": "”",
    "„": "”",
    "⹂": "”",
    "‚": "’",
    "«": "»",
    "‹": "›",
    "‵": "′",
    "‶": "″",
    "‷": "‴",
    "〝": "〞",
    "〟": "〞",
  },
  Ep = RegExp("[" + Object.keys(Wu).join("") + "]", "g"),
  Hp = RegExp("[" + Object.values(Wu).join("") + "]", "g"),
  Xo = function (e) {
    if (!e) return !1;
    let t = e.match(Hp);
    return t !== null && t.length === 1;
  },
  zp = function (e) {
    let t = [];
    for (let n = 0; n < e.length; n += 1) {
      let a = e[n].match(Ep);
      if (a !== null && a.length === 1) {
        if (Xo(e[n + 1]) && e[n + 1].length < Zo) {
          ((e[n] += e[n + 1]), t.push(e[n]), (e[n + 1] = ""), (n += 1));
          continue;
        }
        if (Xo(e[n + 2])) {
          let i = e[n + 1] + e[n + 2];
          if (i.length < Zo) {
            ((e[n] += i),
              t.push(e[n]),
              (e[n + 1] = ""),
              (e[n + 2] = ""),
              (n += 2));
            continue;
          }
        }
      }
      t.push(e[n]);
    }
    return t;
  },
  Fp = 250,
  es = /\(/g,
  Vp = /\)/g,
  Gp = function (e) {
    let t = [];
    for (let n = 0; n < e.length; n += 1) {
      let a = e[n].match(es);
      if (
        a !== null &&
        a.length === 1 &&
        e[n + 1] &&
        e[n + 1].length < Fp &&
        e[n + 1].match(Vp) !== null &&
        a.length === 1 &&
        !es.test(e[n + 1])
      ) {
        ((e[n] += e[n + 1]), t.push(e[n]), (e[n + 1] = ""), (n += 1));
        continue;
      }
      t.push(e[n]);
    }
    return t;
  },
  Sp = /\S/,
  ts = /^\s+/,
  Mp = function (e, t) {
    if (
      ((e = e || ""),
      (e = String(e)),
      !e || typeof e != "string" || Sp.test(e) === !1)
    )
      return [];
    e = e.replace(" ", " ");
    let n = jp(e),
      r = Op(n);
    if (((r = Ip(r, t)), (r = zp(r)), (r = Gp(r)), r.length === 0)) return [e];
    for (let a = 1; a < r.length; a += 1) {
      let i = r[a].match(ts);
      i !== null && ((r[a - 1] += i[0]), (r[a] = r[a].replace(ts, "")));
    }
    return r;
  },
  Bp = function (e, t) {
    let n = e.split(/[-–—]/);
    if (n.length <= 1) return !1;
    const { prefixes: r, suffixes: a } = t.one;
    return (n[0].length === 1 && /[a-z]/i.test(n[0])) ||
      r.hasOwnProperty(n[0]) ||
      ((n[1] = n[1].trim().replace(/[.?!]$/, "")), a.hasOwnProperty(n[1]))
      ? !1
      : /^([a-z\u00C0-\u00FF`"'/]+)[-–—]([a-z0-9\u00C0-\u00FF].*)/i.test(e) ===
          !0 ||
          /^[('"]?([0-9]{1,4})[-–—]([a-z\u00C0-\u00FF`"'/-]+[)'"]?$)/i.test(
            e,
          ) === !0;
  },
  Lp = function (e) {
    let t = [];
    const n = e.split(/[-–—]/);
    let r = "-",
      a = e.match(/[-–—]/);
    a && a[0] && (r = a);
    for (let i = 0; i < n.length; i++)
      i === n.length - 1 ? t.push(n[i]) : t.push(n[i] + r);
    return t;
  },
  Wp = function (e) {
    const t = /^[0-9]{1,4}(:[0-9][0-9])?([a-z]{1,2})? ?[-–—] ?$/,
      n = /^[0-9]{1,4}([a-z]{1,2})? ?$/;
    for (let r = 0; r < e.length - 1; r += 1)
      e[r + 1] &&
        t.test(e[r]) &&
        n.test(e[r + 1]) &&
        ((e[r] = e[r] + e[r + 1]), (e[r + 1] = null));
    return e;
  },
  qp = new RegExp("\\p{L} ?\\/ ?\\p{L}+$", "u"),
  Kp = function (e) {
    for (let t = 1; t < e.length - 1; t++)
      qp.test(e[t]) &&
        ((e[t - 1] += e[t] + e[t + 1]), (e[t] = null), (e[t + 1] = null));
    return e;
  },
  Jp = /\S/,
  _p = /^[!?.]+$/,
  Up = /(\S+)/;
let ci = [
  ".",
  "?",
  "!",
  ":",
  ";",
  "-",
  "–",
  "—",
  "--",
  "...",
  "(",
  ")",
  "[",
  "]",
  '"',
  "'",
  "`",
  "«",
  "»",
  "*",
  "•",
];
ci = ci.reduce((e, t) => ((e[t] = !0), e), {});
const Rp = function (e) {
    return Object.prototype.toString.call(e) === "[object Array]";
  },
  Yp = function (e, t) {
    let n = [],
      r = [];
    if (((e = e || ""), typeof e == "number" && (e = String(e)), Rp(e)))
      return e;
    const a = e.split(Up);
    for (let o = 0; o < a.length; o++) {
      if (Bp(a[o], t) === !0) {
        r = r.concat(Lp(a[o]));
        continue;
      }
      r.push(a[o]);
    }
    let i = "";
    for (let o = 0; o < r.length; o++) {
      let s = r[o];
      Jp.test(s) === !0 && ci.hasOwnProperty(s) === !1 && _p.test(s) === !1
        ? (n.length > 0 ? ((n[n.length - 1] += i), n.push(s)) : n.push(i + s),
          (i = ""))
        : (i += s);
    }
    return (
      i && (n.length === 0 && (n[0] = ""), (n[n.length - 1] += i)),
      (n = Kp(n)),
      (n = Wp(n)),
      (n = n.filter((o) => o)),
      n
    );
  },
  ns = new RegExp("\\p{Letter}", "u"),
  ir = /[\p{Number}\p{Currency_Symbol}]/u,
  Qp = /^[a-z]\.([a-z]\.)+/i,
  Zp = /[sn]['’]$/,
  Xp = function (e, t) {
    let { prePunctuation: n, postPunctuation: r, emoticons: a } = t.one,
      i = e,
      o = "",
      s = "",
      l = Array.from(e);
    if (a.hasOwnProperty(e.trim())) return { str: e.trim(), pre: o, post: " " };
    let u = l.length;
    for (let c = 0; c < u; c += 1) {
      let h = l[0];
      if (n[h] !== !0) {
        if (
          ((h === "+" || h === "-") && ir.test(l[1])) ||
          (h === "'" && h.length === 3 && ir.test(l[1])) ||
          ns.test(h) ||
          ir.test(h)
        )
          break;
        o += l.shift();
      }
    }
    u = l.length;
    for (let c = 0; c < u; c += 1) {
      let h = l[l.length - 1];
      if (r[h] !== !0) {
        if (ns.test(h) || ir.test(h)) break;
        (h === "." && Qp.test(i) === !0) ||
          (h === "'" && Zp.test(i) === !0) ||
          (s = l.pop() + s);
      }
    }
    return (
      (e = l.join("")),
      e === "" &&
        ((i = i.replace(/ *$/, (c) => ((s = c || ""), ""))), (e = i), (o = "")),
      { str: e, pre: o, post: s }
    );
  },
  eg = (e, t) => {
    let { str: n, pre: r, post: a } = Xp(e, t);
    return { text: n, pre: r, post: a, tags: new Set() };
  },
  tg = function (e, t) {
    const n = t.model.one.unicode || {};
    e = e || "";
    let r = e.split("");
    return (
      r.forEach((a, i) => {
        n[a] && (r[i] = n[a]);
      }),
      r.join("")
    );
  },
  ng = function (e) {
    ((e = e || ""), (e = e.toLowerCase()), (e = e.trim()));
    let t = e;
    return (
      (e = e.replace(/[,;.!?]+$/, "")),
      (e = e.replace(/\u2026/g, "...")),
      (e = e.replace(/\u2013/g, "-")),
      /^[:;]/.test(e) === !1 &&
        ((e = e.replace(/\.{3,}$/g, "")),
        (e = e.replace(/[",.!:;?)]+$/g, "")),
        (e = e.replace(/^['"(]+/g, ""))),
      (e = e.replace(/[\u200B-\u200D\uFEFF]/g, "")),
      (e = e.trim()),
      e === "" && (e = t),
      (e = e.replace(/([0-9]),([0-9])/g, "$1$2")),
      e
    );
  },
  rg = /([A-Z]\.)+[A-Z]?,?$/,
  ag = /^[A-Z]\.,?$/,
  ig = /[A-Z]{2,}('s|,)?$/,
  og = /([a-z]\.)+[a-z]\.?$/,
  sg = function (e) {
    return (
      rg.test(e) === !0 ||
      og.test(e) === !0 ||
      ag.test(e) === !0 ||
      ig.test(e) === !0
    );
  },
  lg = function (e) {
    return (sg(e) && (e = e.replace(/\./g, "")), e);
  },
  qu = function (e, t) {
    const n = t.methods.one.killUnicode;
    let r = e.text || "";
    ((r = ng(r)), (r = n(r, t)), (r = lg(r)), (e.normal = r));
  },
  ug = function (e, t) {
    const { methods: n, model: r } = t,
      { splitSentences: a, splitTerms: i, splitWhitespace: o } = n.one.tokenize;
    return (
      (e = e || ""),
      (e = a(e, t).map((l) => {
        let u = i(l, r);
        return (
          (u = u.map((c) => o(c, r))),
          u.forEach((c) => {
            qu(c, t);
          }),
          u
        );
      })),
      e
    );
  },
  cg = /[ .][A-Z]\.? *$/i,
  hg = /(?:\u2026|\.{2,}) *$/,
  dg = new RegExp("\\p{L}", "u"),
  fg = /\. *$/,
  mg = /^[A-Z]\. $/,
  pg = function (e, t) {
    if (
      dg.test(e) === !1 ||
      cg.test(e) === !0 ||
      (e.length === 3 && mg.test(e)) ||
      hg.test(e) === !0
    )
      return !1;
    let r = e.replace(/[.!?\u203D\u2E18\u203C\u2047-\u2049] *$/, "").split(" "),
      a = r[r.length - 1].toLowerCase();
    return !(t.hasOwnProperty(a) === !0 && fg.test(e) === !0);
  },
  gg = {
    one: {
      killUnicode: tg,
      tokenize: {
        splitSentences: Mp,
        isSentence: pg,
        splitTerms: Yp,
        splitWhitespace: eg,
        fromString: ug,
      },
    },
  },
  yg = { "&": "and", "@": "at", "%": "percent", plz: "please", bein: "being" },
  bg = [
    "approx",
    "apt",
    "bc",
    "cyn",
    "eg",
    "esp",
    "est",
    "etc",
    "ex",
    "exp",
    "prob",
    "pron",
    "gal",
    "min",
    "pseud",
    "fig",
    "jd",
    "lat",
    "lng",
    "vol",
    "fm",
    "def",
    "misc",
    "plz",
    "ea",
    "ps",
    "sec",
    "pt",
    "pref",
    "pl",
    "pp",
    "qt",
    "fr",
    "sq",
    "nee",
    "ss",
    "tel",
    "temp",
    "vet",
    "ver",
    "fem",
    "masc",
    "eng",
    "adj",
    "vb",
    "rb",
    "inf",
    "situ",
    "vivo",
    "vitro",
    "wr",
  ],
  vg = [
    "adj",
    "adm",
    "adv",
    "asst",
    "atty",
    "bldg",
    "brig",
    "capt",
    "cmdr",
    "comdr",
    "cpl",
    "det",
    "dr",
    "esq",
    "gen",
    "gov",
    "hon",
    "jr",
    "llb",
    "lt",
    "maj",
    "messrs",
    "mlle",
    "mme",
    "mr",
    "mrs",
    "ms",
    "mstr",
    "phd",
    "prof",
    "pvt",
    "rep",
    "reps",
    "res",
    "rev",
    "sen",
    "sens",
    "sfc",
    "sgt",
    "sir",
    "sr",
    "supt",
    "surg",
  ],
  wg = [
    "jan",
    "feb",
    "mar",
    "apr",
    "jun",
    "jul",
    "aug",
    "sep",
    "sept",
    "oct",
    "nov",
    "dec",
  ],
  kg = [
    "ad",
    "al",
    "arc",
    "ba",
    "bl",
    "ca",
    "cca",
    "col",
    "corp",
    "ft",
    "fy",
    "ie",
    "lit",
    "ma",
    "md",
    "pd",
    "tce",
  ],
  Pg = ["dept", "univ", "assn", "bros", "inc", "ltd", "co"],
  Ag = [
    "rd",
    "st",
    "dist",
    "mt",
    "ave",
    "blvd",
    "cl",
    "cres",
    "hwy",
    "ariz",
    "cal",
    "calif",
    "colo",
    "conn",
    "fla",
    "fl",
    "ga",
    "ida",
    "ia",
    "kan",
    "kans",
    "minn",
    "neb",
    "nebr",
    "okla",
    "penna",
    "penn",
    "pa",
    "dak",
    "tenn",
    "tex",
    "ut",
    "vt",
    "va",
    "wis",
    "wisc",
    "wy",
    "wyo",
    "usafa",
    "alta",
    "ont",
    "que",
    "sask",
  ],
  xg = [
    "dl",
    "ml",
    "gal",
    "qt",
    "pt",
    "tbl",
    "tsp",
    "tbsp",
    "km",
    "dm",
    "cm",
    "mm",
    "mi",
    "td",
    "hr",
    "hrs",
    "kg",
    "hg",
    "dg",
    "cg",
    "mg",
    "µg",
    "lb",
    "oz",
    "sq ft",
    "hz",
    "mps",
    "mph",
    "kmph",
    "kb",
    "mb",
    "tb",
    "lx",
    "lm",
    "fl oz",
    "yb",
  ];
let Cg = [
    [bg],
    [xg, "Unit"],
    [kg, "Noun"],
    [vg, "Honorific"],
    [wg, "Month"],
    [Pg, "Organization"],
    [Ag, "Place"],
  ],
  Ku = {},
  Kr = {};
Cg.forEach((e) => {
  e[0].forEach((t) => {
    ((Ku[t] = !0),
      (Kr[t] = "Abbreviation"),
      e[1] !== void 0 && (Kr[t] = [Kr[t], e[1]]));
  });
});
const Dg = [
    "anti",
    "bi",
    "co",
    "contra",
    "de",
    "extra",
    "infra",
    "inter",
    "intra",
    "macro",
    "micro",
    "mis",
    "mono",
    "multi",
    "peri",
    "pre",
    "pro",
    "proto",
    "pseudo",
    "re",
    "sub",
    "supra",
    "trans",
    "tri",
    "un",
    "out",
    "ex",
  ].reduce((e, t) => ((e[t] = !0), e), {}),
  $g = {
    like: !0,
    ish: !0,
    less: !0,
    able: !0,
    elect: !0,
    type: !0,
    designate: !0,
  };
let rs = {
    "!": "¡",
    "?": "¿Ɂ",
    '"': '“”"❝❞',
    "'": "‘‛❛❜’",
    "-": "—–",
    a: "ªÀÁÂÃÄÅàáâãäåĀāĂăĄąǍǎǞǟǠǡǺǻȀȁȂȃȦȧȺΆΑΔΛάαλАаѦѧӐӑӒӓƛæ",
    b: "ßþƀƁƂƃƄƅɃΒβϐϦБВЪЬвъьѢѣҌҍ",
    c: "¢©ÇçĆćĈĉĊċČčƆƇƈȻȼͻͼϲϹϽϾСсєҀҁҪҫ",
    d: "ÐĎďĐđƉƊȡƋƌ",
    e: "ÈÉÊËèéêëĒēĔĕĖėĘęĚěƐȄȅȆȇȨȩɆɇΈΕΞΣέεξϵЀЁЕеѐёҼҽҾҿӖӗễ",
    f: "ƑƒϜϝӺӻҒғſ",
    g: "ĜĝĞğĠġĢģƓǤǥǦǧǴǵ",
    h: "ĤĥĦħƕǶȞȟΉΗЂЊЋНнђћҢңҤҥҺһӉӊ",
    I: "ÌÍÎÏ",
    i: "ìíîïĨĩĪīĬĭĮįİıƖƗȈȉȊȋΊΐΪίιϊІЇіїi̇",
    j: "ĴĵǰȷɈɉϳЈј",
    k: "ĶķĸƘƙǨǩΚκЌЖКжкќҚқҜҝҞҟҠҡ",
    l: "ĹĺĻļĽľĿŀŁłƚƪǀǏǐȴȽΙӀӏ",
    m: "ΜϺϻМмӍӎ",
    n: "ÑñŃńŅņŇňŉŊŋƝƞǸǹȠȵΝΠήηϞЍИЙЛПийлпѝҊҋӅӆӢӣӤӥπ",
    o: "ÒÓÔÕÖØðòóôõöøŌōŎŏŐőƟƠơǑǒǪǫǬǭǾǿȌȍȎȏȪȫȬȭȮȯȰȱΌΘΟθοσόϕϘϙϬϴОФоѲѳӦӧӨөӪӫ",
    p: "ƤΡρϷϸϼРрҎҏÞ",
    q: "Ɋɋ",
    r: "ŔŕŖŗŘřƦȐȑȒȓɌɍЃГЯгяѓҐґ",
    s: "ŚśŜŝŞşŠšƧƨȘșȿЅѕ",
    t: "ŢţŤťŦŧƫƬƭƮȚțȶȾΓΤτϮТт",
    u: "ÙÚÛÜùúûüŨũŪūŬŭŮůŰűŲųƯưƱƲǓǔǕǖǗǘǙǚǛǜȔȕȖȗɄΰυϋύ",
    v: "νѴѵѶѷ",
    w: "ŴŵƜωώϖϢϣШЩшщѡѿ",
    x: "×ΧχϗϰХхҲҳӼӽӾӿ",
    y: "ÝýÿŶŷŸƳƴȲȳɎɏΎΥΫγψϒϓϔЎУучўѰѱҮүҰұӮӯӰӱӲӳ",
    z: "ŹźŻżŽžƵƶȤȥɀΖ",
  },
  Ju = {};
Object.keys(rs).forEach(function (e) {
  rs[e].split("").forEach(function (t) {
    Ju[t] = e;
  });
});
const jg = {
    "#": !0,
    "@": !0,
    _: !0,
    "°": !0,
    "​": !0,
    "‌": !0,
    "‍": !0,
    "\uFEFF": !0,
  },
  Ng = { "%": !0, _: !0, "°": !0, "​": !0, "‌": !0, "‍": !0, "\uFEFF": !0 },
  Tg = {
    "<3": !0,
    "</3": !0,
    "<\\3": !0,
    ":^P": !0,
    ":^p": !0,
    ":^O": !0,
    ":^3": !0,
  },
  Og = {
    one: {
      aliases: yg,
      abbreviations: Ku,
      prefixes: Dg,
      suffixes: $g,
      prePunctuation: jg,
      postPunctuation: Ng,
      lexicon: Kr,
      unicode: Ju,
      emoticons: Tg,
    },
  },
  as = /\//,
  Ig = /[a-z]\.[a-z]/i,
  Eg = /[0-9]/,
  Hg = function (e, t) {
    let n = e.normal || e.text || e.machine;
    const r = t.model.one.aliases;
    if (
      (r.hasOwnProperty(n) && ((e.alias = e.alias || []), e.alias.push(r[n])),
      as.test(n) && !Ig.test(n) && !Eg.test(n))
    ) {
      let a = n.split(as);
      a.length <= 3 &&
        a.forEach((i) => {
          ((i = i.trim()),
            i !== "" && ((e.alias = e.alias || []), e.alias.push(i)));
        });
    }
    return e;
  },
  zg = new RegExp("^\\p{Letter}+-\\p{Letter}+$", "u"),
  Fg = function (e) {
    let t = e.implicit || e.normal || e.text;
    ((t = t.replace(/['’]s$/, "")),
      (t = t.replace(/s['’]$/, "s")),
      (t = t.replace(/([aeiou][ktrp])in'$/, "$1ing")),
      zg.test(t) && (t = t.replace(/-/g, "")),
      (t = t.replace(/^[#@]/, "")),
      t !== e.normal && (e.machine = t));
  },
  Vg = function (e) {
    let t = e.docs,
      n = {};
    for (let r = 0; r < t.length; r += 1)
      for (let a = 0; a < t[r].length; a += 1) {
        let i = t[r][a],
          o = i.machine || i.normal;
        ((n[o] = n[o] || 0), (n[o] += 1));
      }
    for (let r = 0; r < t.length; r += 1)
      for (let a = 0; a < t[r].length; a += 1) {
        let i = t[r][a],
          o = i.machine || i.normal;
        i.freq = n[o];
      }
  },
  Gg = function (e) {
    let t = 0,
      n = 0,
      r = e.document;
    for (let a = 0; a < r.length; a += 1)
      for (let i = 0; i < r[a].length; i += 1) {
        let o = r[a][i];
        ((o.offset = {
          index: n,
          start: t + o.pre.length,
          length: o.text.length,
        }),
          (t += o.pre.length + o.text.length + o.post.length),
          (n += 1));
      }
  },
  Sg = function (e) {
    let t = e.document;
    for (let n = 0; n < t.length; n += 1)
      for (let r = 0; r < t[n].length; r += 1) t[n][r].index = [n, r];
  },
  Mg = function (e) {
    let t = 0,
      n = e.docs;
    for (let r = 0; r < n.length; r += 1)
      for (let a = 0; a < n[r].length; a += 1)
        n[r][a].normal !== "" && ((t += 1), (n[r][a].wordCount = t));
  },
  ya = function (e, t) {
    let n = e.docs;
    for (let r = 0; r < n.length; r += 1)
      for (let a = 0; a < n[r].length; a += 1) t(n[r][a], e.world);
  },
  Bg = {
    alias: (e) => ya(e, Hg),
    machine: (e) => ya(e, Fg),
    normal: (e) => ya(e, qu),
    freq: Vg,
    offset: Gg,
    index: Sg,
    wordCount: Mg,
  },
  Lg = {
    compute: Bg,
    methods: gg,
    model: Og,
    hooks: ["alias", "machine", "index", "id"],
  },
  Wg = function (e) {
    const t = e.model.one.typeahead,
      n = e.docs;
    if (n.length === 0 || Object.keys(t).length === 0) return;
    let r = n[n.length - 1] || [],
      a = r[r.length - 1];
    if (!a.post && t.hasOwnProperty(a.normal)) {
      let i = t[a.normal];
      ((a.implicit = i),
        (a.machine = i),
        (a.typeahead = !0),
        e.compute.preTagger &&
          e.last().unTag("*").compute(["lexicon", "preTagger"]));
    }
  },
  qg = { typeahead: Wg },
  Kg = function () {
    const e = this.docs;
    if (e.length === 0) return this;
    let t = e[e.length - 1] || [],
      n = t[t.length - 1];
    return (
      n.typeahead === !0 &&
        n.machine &&
        ((n.text = n.machine), (n.normal = n.machine)),
      this
    );
  },
  Jg = function (e) {
    e.prototype.autoFill = Kg;
  },
  _g = function (e, t, n) {
    let r = {},
      a = [],
      i = n.prefixes || {};
    return (
      e.forEach((o) => {
        o = o.toLowerCase().trim();
        let s = o.length;
        t.max && s > t.max && (s = t.max);
        for (let l = t.min; l < s; l += 1) {
          let u = o.substring(0, l);
          if (!(t.safe && n.model.one.lexicon.hasOwnProperty(u))) {
            if (i.hasOwnProperty(u) === !0) {
              a.push(u);
              continue;
            }
            if (r.hasOwnProperty(u) === !0) {
              a.push(u);
              continue;
            }
            r[u] = o;
          }
        }
      }),
      (r = Object.assign({}, i, r)),
      a.forEach((o) => {
        delete r[o];
      }),
      r
    );
  },
  Ug = (e) => Object.prototype.toString.call(e) === "[object Object]",
  Rg = { safe: !0, min: 3 },
  Yg = function (e = [], t = {}) {
    let n = this.model();
    ((t = Object.assign({}, Rg, t)),
      Ug(e) && (Object.assign(n.one.lexicon, e), (e = Object.keys(e))));
    let r = _g(e, t, this.world());
    return (
      Object.keys(r).forEach((a) => {
        if (n.one.typeahead.hasOwnProperty(a)) {
          delete n.one.typeahead[a];
          return;
        }
        n.one.typeahead[a] = r[a];
      }),
      this
    );
  },
  Qg = { typeahead: Yg },
  Zg = { one: { typeahead: {} } },
  Xg = { model: Zg, api: Jg, lib: Qg, compute: qg, hooks: ["typeahead"] };
k.extend(Bh);
k.extend(wm);
k.extend(Mf);
k.extend(zm);
k.extend(xp);
k.plugin(fd);
k.extend(Lg);
k.extend(gd);
k.plugin(rh);
k.extend(zd);
k.extend(Xg);
k.extend($d);
k.extend(Ym);
const _u = {
    addendum: "addenda",
    corpus: "corpora",
    criterion: "criteria",
    curriculum: "curricula",
    genus: "genera",
    memorandum: "memoranda",
    opus: "opera",
    ovum: "ova",
    phenomenon: "phenomena",
    referendum: "referenda",
    alga: "algae",
    alumna: "alumnae",
    antenna: "antennae",
    formula: "formulae",
    larva: "larvae",
    nebula: "nebulae",
    vertebra: "vertebrae",
    analysis: "analyses",
    axis: "axes",
    diagnosis: "diagnoses",
    parenthesis: "parentheses",
    prognosis: "prognoses",
    synopsis: "synopses",
    thesis: "theses",
    neurosis: "neuroses",
    appendix: "appendices",
    index: "indices",
    matrix: "matrices",
    ox: "oxen",
    sex: "sexes",
    alumnus: "alumni",
    bacillus: "bacilli",
    cactus: "cacti",
    fungus: "fungi",
    hippopotamus: "hippopotami",
    libretto: "libretti",
    modulus: "moduli",
    nucleus: "nuclei",
    octopus: "octopi",
    radius: "radii",
    stimulus: "stimuli",
    syllabus: "syllabi",
    cookie: "cookies",
    calorie: "calories",
    auntie: "aunties",
    movie: "movies",
    pie: "pies",
    rookie: "rookies",
    tie: "ties",
    zombie: "zombies",
    leaf: "leaves",
    loaf: "loaves",
    thief: "thieves",
    foot: "feet",
    goose: "geese",
    tooth: "teeth",
    beau: "beaux",
    chateau: "chateaux",
    tableau: "tableaux",
    bus: "buses",
    gas: "gases",
    circus: "circuses",
    crisis: "crises",
    virus: "viruses",
    database: "databases",
    excuse: "excuses",
    abuse: "abuses",
    avocado: "avocados",
    barracks: "barracks",
    child: "children",
    clothes: "clothes",
    echo: "echoes",
    embargo: "embargoes",
    epoch: "epochs",
    deer: "deer",
    halo: "halos",
    man: "men",
    woman: "women",
    mosquito: "mosquitoes",
    mouse: "mice",
    person: "people",
    quiz: "quizzes",
    rodeo: "rodeos",
    shoe: "shoes",
    sombrero: "sombreros",
    stomach: "stomachs",
    tornado: "tornados",
    tuxedo: "tuxedos",
    volcano: "volcanoes",
  },
  is = {
    Comparative: "true¦bett1f0;arth0ew0in0;er",
    Superlative: "true¦earlier",
    PresentTense: "true¦bests,sounds",
    Condition: "true¦lest,unless",
    PastTense: "true¦began,came,d4had,kneel3l2m0sa4we1;ea0sg2;nt;eap0i0;ed;id",
    Participle:
      "true¦0:09;a06b01cZdXeat0fSgQhPoJprov0rHs7t6u4w1;ak0ithdra02o2r1;i02uY;k0v0;nd1pr04;ergoJoJ;ak0hHo3;e9h7lain,o6p5t4un3w1;o1um;rn;g,k;ol0reS;iQok0;ught,wn;ak0o1runk;ne,wn;en,wn;ewriNi1uJ;dd0s0;ut3ver1;do4se0t1;ak0h2;do2g1;roG;ne;ast0i7;iv0o1;ne,tt0;all0loBor1;bi3g2s1;ak0e0;iv0o9;dd0;ove,r1;a5eamt,iv0;hos0lu1;ng;e4i3lo2ui1;lt;wn;tt0;at0en,gun;r2w1;ak0ok0;is0;en",
    Gerund: "true¦accord0be0doin,go0result0stain0;ing",
    Expression:
      "true¦a0Yb0Uc0Sd0Oe0Mfarew0Lg0FhZjeez,lWmVnToOpLsJtIuFvEw7y0;a5e3i1u0;ck,p;k04p0;ee,pee;a0p,s;!h;!a,h,y;a5h2o1t0;af,f;rd up,w;atsoever,e1o0;a,ops;e,w;hoo,t;ery w06oi0L;gh,h0;! 0h,m;huh,oh;here nPsk,ut tut;h0ic;eesh,hh,it,oo;ff,h1l0ow,sst;ease,s,z;ew,ooey;h1i,mg,o0uch,w,y;h,o,ps;! 0h;hTmy go0wT;d,sh;a7evertheless,o0;!pe;eh,mm;ah,eh,m1ol0;!s;ao,fao;aCeBi9o2u0;h,mph,rra0zzC;h,y;l1o0;r6y9;la,y0;! 0;c1moCsmok0;es;ow;!p hip hoor0;ay;ck,e,llo,y;ha1i,lleluj0;ah;!ha;ah,ee4o1r0;eat scott,r;l1od0sh; grief,bye;ly;! whiz;ell;e0h,t cetera,ureka,ww,xcuse me;k,p;'oh,a0rat,uh;m0ng;mit,n0;!it;mon,o0;ngratulations,wabunga;a2oo1r0tw,ye;avo,r;!ya;h,m; 1h0ka,las,men,rgh,ye;!a,em,h,oy;la",
    Negative: "true¦n0;ever,o0;n,t",
    QuestionWord: "true¦how3wh0;at,e1ich,o0y;!m,se;n,re; come,'s",
    Reflexive: "true¦h4it5my5o1the0your2;ir1m1;ne3ur0;sel0;f,ves;er0im0;self",
    Plural: "true¦dick0gre0ones,records;ens",
    "Unit|Noun":
      "true¦cEfDgChBinchAk9lb,m6newt5oz,p4qt,t1y0;ardEd;able1b0ea1sp;!l,sp;spo1;a,t,x;on9;!b,g,i1l,m,p0;h,s;!les;!b,elvin,g,m;!es;g,z;al,b;eet,oot,t;m,up0;!s",
    Value: "true¦a few",
    Imperative: "true¦bewa0come he0;re",
    "Plural|Verb": "true¦leaves",
    Demonym:
      "true¦0:15;1:12;a0Vb0Oc0Dd0Ce08f07g04h02iYjVkTlPmLnIomHpEqatari,rCs7t5u4v3welAz2;am0Gimbabwe0;enezuel0ietnam0I;gAkrai1;aiwTex0hai,rinida0Ju2;ni0Prkmen;a5cotti4e3ingapoOlovak,oma0Spaniard,udRw2y0W;ede,iss;negal0Cr09;sh;mo0uT;o5us0Jw2;and0;a2eru0Fhilippi0Nortugu07uerto r0S;kist3lesti1na2raguay0;ma1;ani;ami00i2orweP;caragu0geri2;an,en;a3ex0Lo2;ngo0Drocc0;cedo1la2;gasy,y07;a4eb9i2;b2thua1;e0Cy0;o,t01;azakh,eny0o2uwaiI;re0;a2orda1;ma0Ap2;anO;celandic,nd4r2sraeli,ta01vo05;a2iB;ni0qi;i0oneU;aiAin2ondur0unO;di;amEe2hanai0reek,uatemal0;or2rm0;gi0;ilipino,ren8;cuadoVgyp4mira3ngli2sto1thiopi0urope0;shm0;ti;ti0;aPominUut3;a9h6o4roat3ub0ze2;ch;!i0;lom2ngol5;bi0;a6i2;le0n2;ese;lifor1m2na3;bo2eroo1;di0;angladeshi,el6o4r3ul2;gaE;azi9it;li2s1;vi0;aru2gi0;si0;fAl7merBngol0r5si0us2;sie,tr2;a2i0;li0;genti2me1;ne;ba1ge2;ri0;ni0;gh0r2;ic0;an",
    Organization:
      "true¦0:4Q;a3Tb3Bc2Od2He2Df27g1Zh1Ti1Pj1Nk1Ll1Gm12n0Po0Mp0Cqu0Br02sTtHuCv9w3xiaomi,y1;amaha,m1Bou1w1B;gov,tu3C;a4e2iki1orld trade organizati33;leaRped0O;lls fargo,st1;fie2Hinghou2R;l1rner br3U;gree3Jl street journ2Im1E;an halOeriz2Xisa,o1;dafo2Yl1;kswagMvo;b4kip,n2ps,s1;a tod3Aps;es3Mi1;lev3Fted natio3C;er,s; mobi32aco beRd bOe9gi frida3Lh3im horto3Amz,o1witt3D;shi49y1;ota,s r 05;e 1in lizzy;b3carpen3Jdaily ma3Dguess w2holli0s1w2;mashing pumpki35uprem0;ho;ea1lack eyed pe3Xyr0Q;ch bo3Dtl0;l2n3Qs1xas instrumen1U;co,la m1F;efoni0Kus;a8cientology,e5ieme2Ymirnoff,np,o3pice gir6quare0Ata1ubaru;rbuc1to34;ks;ny,undgard1;en;a2x pisto1;ls;g1Wrs;few2Minsbur31lesfor03msu2E;adiohead,b8e4o1yana3C;man empi1Xyal 1;b1dutch she4;ank;a3d 1max,vl20;bu1c2Ahot chili peppe2Ylobst2N;ll;ders dige1Ll madrid;c,s;ant3Aizn2Q;a8bs,e5fiz2Ihilip4i3r1;emier 1udenti1D;leagTo2K;nk floyd,zza hut; morrBs;psi2tro1uge0E;br33chi0Tn33;!co;lant2Un1yp16; 2ason27da2P;ld navy,pec,range juli2xf1;am;us;aAb9e6fl,h5i4o1sa,vid3wa;k2tre dame,vart1;is;ia;ke,ntendo,ss0QvZ;l,s;c,st1Otflix,w1; 1sweek;kids on the block,york0D;a,c;nd22s2t1;ional aca2Po,we0U;a,c02d0S;aDcdonalCe9i6lb,o3tv,y1;spa1;ce;b1Tnsanto,ody blu0t1;ley cr1or0T;ue;c2t1;as,subisO;helin,rosoft;dica2rcedes benz,talli1;ca;id,re;ds;cs milk,tt19z24;a3e1g,ittle caesa1P; ore09novo,x1;is,mark,us; 1bour party;pres0Dz boy;atv,fc,kk,lm,m1od1O;art;iffy lu0Roy divisi0Jpmorgan1sa;! cha09;bm,hop,k3n1tv;g,te1;l,rpol;ea;a5ewlett pack1Vi3o1sbc,yundai;me dep1n1P;ot;tac1zbollah;hi;lliburt08sbro;eneral 6hq,ithub,l5mb,o2reen d0Ou1;cci,ns n ros0;ldman sachs,o1;dye1g0H;ar;axo smith kli04encoW;electr0Nm1;oto0Z;a5bi,c barcelo4da,edex,i2leetwood m03o1rito l0G;rd,xcY;at,fa,nancial1restoZ; tim0;na;cebook,nnie mae;b0Asa,u3xxon1; m1m1;ob0J;!rosceptics;aiml0De5isney,o4u1;nkin donu2po0Zran dur1;an;ts;j,w jon0;a,f lepp12ll,peche mode,r spieg02stiny's chi1;ld;aJbc,hFiDloudflaCnn,o3r1;aigsli5eedence clearwater reviv1ossra09;al;c7inba6l4m1o0Est09;ca2p1;aq;st;dplSg1;ate;se;a c1o chanQ;ola;re;a,sco1tigroup;! systems;ev2i1;ck fil a,na daily;r1y;on;d2pital o1rls jr;ne;bury,ill1;ac;aEbc,eBf9l5mw,ni,o1p,rexiteeU;ei3mbardiIston 1;glo1pizza;be;ng;o2ue c1;roV;ckbuster video,omingda1;le; g1g1;oodriL;cht2e ge0rkshire hathaw1;ay;el;cardi,idu,nana republ3s1xt5y5;f,kin robbi1;ns;ic;bYcTdidSerosmith,iRlKmEnheuser busDol,ppleAr6s4u3v2y1;er;is,on;di,todesk;hland o1sociated E;il;b3g2m1;co;os;ys; compu1be0;te1;rs;ch;c,d,erican3t1;!r1;ak; ex1;pre1;ss; 5catel2ta1;ir;! lu1;ce1;nt;jazeera,qae1;da;g,rbnb;as;/dc,a3er,tivision1;! blizz1;ard;demy of scienc0;es;ba",
    Possessive: "true¦its,my,our0thy;!s",
    "Noun|Verb":
      "true¦0:9W;1:AA;2:96;3:A3;4:9R;5:A2;6:9K;7:8N;8:7L;9:A8;A:93;B:8D;C:8X;a9Ob8Qc7Id6Re6Gf5Sg5Hh55i4Xj4Uk4Rl4Em40n3Vo3Sp2Squ2Rr21s0Jt02u00vVwGyFzD;ip,oD;ne,om;awn,e6Fie68;aOeMhJiHoErD;ap,e9Oink2;nd0rDuC;kDry,sh5Hth;!shop;ck,nDpe,re,sh;!d,g;e86iD;p,sD;k,p0t2;aDed,lco8W;r,th0;it,lk,rEsDt4ve,x;h,te;!ehou1ra9;aGen5FiFoD;iDmAte,w;ce,d;be,ew,sA;cuum,l4B;pDr7;da5gra6Elo6A;aReQhrPiOoMrGuEwiDy5Z;n,st;nDrn;e,n7O;aGeFiEoDu6;t,ub2;bu5ck4Jgg0m,p;at,k,nd;ck,de,in,nsDp,v7J;f0i8R;ll,ne,p,r4Yss,t94uD;ch,r;ck,de,e,le,me,p,re;e5Wow,u6;ar,e,ll,mp0st,xt;g,lDng2rg7Ps5x;k,ly;a0Sc0Ne0Kh0Fi0Dk0Cl0Am08n06o05pXquaBtKuFwD;ea88iD;ng,pe,t4;bGit,m,ppErD;fa3ge,pri1v2U;lDo6S;e6Py;!je8;aMeLiKoHrEuDy2;dy,ff,mb2;a85eEiDo5Pugg2;ke,ng;am,ss,t4;ckEop,p,rD;e,m;ing,pi2;ck,nk,t4;er,m,p;ck,ff,ge,in,ke,lEmp,nd,p2rDte,y;!e,t;k,l;aJeIiHlGoFrDur,y;ay,e56inDu3;g,k2;ns8Bt;a5Qit;ll,n,r87te;ed,ll;m,n,rk;b,uC;aDee1Tow;ke,p;a5Je4FiDo53;le,rk;eep,iDou4;ce,p,t;ateboa7Ii;de,gnDl2Vnk,p,ze;!al;aGeFiEoDuff2;ck,p,re,w;ft,p,v0;d,i3Ylt0;ck,de,pe,re,ve;aEed,nDrv1It;se,t2N;l,r4t;aGhedu2oBrD;aEeDibb2o3Z;en,w;pe,t4;le,n,r2M;cDfegua72il,mp2;k,rifi3;aZeHhy6LiGoEuD;b,in,le,n,s5X;a6ck,ll,oDpe,u5;f,t;de,ng,ot,p,s1W;aTcSdo,el,fQgPje8lOmMnLo17pJque6sFturn,vDwa6V;eDi27;al,r1;er74oFpe8tEuD;lt,me;!a55;l71rt;air,eaDly,o53;l,t;dezvo2Zt;aDedy;ke,rk;ea1i4G;a6Iist0r5N;act6Yer1Vo71uD;nd,se;a38o6F;ch,s6G;c1Dge,iEke,lly,nDp1Wt1W;ge,k,t;n,se;es6Biv0;a04e00hYiXlToNrEsy4uD;mp,n4rcha1sh;aKeIiHoDu4O;be,ceFdu3fi2grDje8mi1p,te6;amDe6W;!me;ed,ss;ce,de,nt;sDy;er6Cs;cti3i1;iHlFoEp,re,sDuCw0;e,i5Yt;l,p;iDl;ce,sh;nt,s5V;aEce,e32uD;g,mp,n7;ce,nDy;!t;ck,le,n17pe,tNvot;a1oD;ne,tograph;ak,eFnErDt;fu55mA;!c32;!l,r;ckJiInHrFsEtDu1y;ch,e9;s,te;k,tD;!y;!ic;nt,r,se;!a7;bje8ff0il,oErDutli3Qver4B;bAd0ie9;ze;a4ReFoDur1;d,tD;e,i3;ed,gle8tD;!work;aMeKiIoEuD;rd0;ck,d3Rld,nEp,uDve;nt,th;it5EkD;ey;lk,n4Brr5CsDx;s,ta2B;asuBn4UrDss;ge,it;il,nFp,rk3WsEtD;ch,t0;h,k,t0;da5n0oeuvB;aLeJiHoEuD;mp,st;aEbby,ck,g,oDve;k,t;d,n;cDe,ft,mAnIst;en1k;aDc0Pe4vK;ch,d,k,p,se;bFcEnd,p,t4uD;gh,n4;e,k;el,o2U;eEiDno4E;ck,d,ll,ss;el,y;aEo1OuD;i3mp;m,zz;mpJnEr46ssD;ue;c1Rdex,fluGha2k,se2HteDvoi3;nt,rD;e6fa3viD;ew;en3;a8le2A;aJeHiGoEuD;g,nt;l3Ano2Dok,pDr1u1;!e;ghli1Fke,nt,re,t;aDd7lp;d,t;ck,mGndFrEsh,tDu9;ch,e;bo3Xm,ne4Eve6;!le;!m0;aMear,ift,lKossJrFuD;arDe4Alp,n;antee,d;aFiEoDumb2;uCwth;ll,nd,p;de,sp;ip;aBoDue;ss,w;g,in,me,ng,s,te,ze;aZeWiRlNoJrFuD;ck,el,nDss,zz;c38d;aEoDy;st,wn;cDgme,me,nchi1;tuB;cFg,il,ld,rD;ce,e29mDwa31;!at;us;aFe0Vip,oDy;at,ck,od,wD;!er;g,ke,me,re,sh,vo1E;eGgFlEnDre,sh,t,x;an3i0Q;e,m,t0;ht,uB;ld;aEeDn3;d,l;r,tuB;ce,il,ll,rm,vo2W;cho,d7ffe8nMsKxFyeD;!baD;ll;cGerci1hFpDtra8;eriDo0W;en3me9;au6ibA;el,han7u1;caDtima5;pe;count0d,vy;a01eSiMoJrEuDye;b,el,mp,pli2X;aGeFiEoD;ne,p;ft,ll,nk,p,ve;am,ss;ft,g,in;cEd7ubt,wnloD;ad;k,u0E;ge6p,sFt4vD;e,iDor3;de;char7gui1h,liEpD;at4lay,u5;ke;al,bKcJfeIlGmaCposAsEtaD;il;e07iD;gn,re;ay,ega5iD;ght;at,ct;li04rea1;a5ut;b,ma7n3rDte;e,t;a0Eent0Dh06irc2l03oKrFuD;be,e,rDt;b,e,l,ve;aGeFoEuDy;sh;p,ss,wd;dAep;ck,ft,sh;at,de,in,lTmMnFordina5py,re,st,uDv0;gh,nDp2rt;s01t;ceHdu8fli8glomeIsFtDveN;a8rD;a6ol;e9tru8;ct;ntDrn;ra5;bHfoGmFpD;leDouCromi1;me9;aCe9it,u5;rt;at,iD;ne;lap1oD;r,ur;aEiDoud,ub;ck,p;im,w;aEeDip;at,ck,er;iGllen7nErD;ge,m,t;ge,nD;el;n,r;er,re;ke,ll,mp,noe,pGrXsFtEuDve;se,ti0I;alog,ch;h,t;!tuB;re;a03eZiXlToPrHuEyD;pa11;bb2ck2dgEff0mp,rDst,zz;den,n;et;anJeHiFoadEuD;i1sh;ca6;be,d7;ge;aDed;ch,k;ch,d;aFg,mb,nEoDrd0tt2x,ycott;k,st,t;d,e;rd,st;aFeCiDoYur;nk,tz;nd;me;as,d,ke,nd,opsy,tD;!ch,e;aFef,lt,nDt;d,efA;it;r,t;ck,il,lan3nIrFsEtt2;le;e,h;!gDk;aDe;in;!d,g,k;bu1c05dZge,iYlVnTppQrLsIttGucEwaD;rd;tiD;on;aDempt;ck;k,sD;i6ocia5;st;chFmD;!oD;ur;!iD;ve;eEroa4;ch;al;chDg0sw0;or;aEt0;er;rm;d,m,r;dreHvD;an3oD;ca5;te;ce;ss;cDe,he,t;eFoD;rd,u9;nt;nt,ss;se",
    Actor:
      "true¦0:7B;1:7G;2:6A;3:7F;4:7O;5:7K;a6Nb62c4Ud4Be41f3Sg3Bh30i2Uj2Qkin2Pl2Km26n1Zo1Sp0Vqu0Tr0JsQtJuHvEw8yo6;gi,ut6;h,ub0;aAe9i8o7r6;estl0it0;m2rk0;fe,nn0t2Bza2H;atherm2ld0;ge earn0it0nder0rri1;eter7i6oyF;ll5Qp,s3Z;an,ina2U;n6s0;c6Uder03;aoisea23e9herapi5iktok0o8r6ut1yco6S;a6endseLo43;d0mp,nscri0Bvel0;ddl0u1G;a0Qchn7en6na4st0;ag0;i3Oo0D;aiXcUeRhPiMki0mu26oJpGquaFtBu7wee6;p0theart;lt2per7r6;f0ge6Iviv1;h6inten0Ist5Ivis1;ero,um2;a8ep7r6;ang0eam0;bro2Nc2Ofa2Nmo2Nsi20;ff0tesm2;tt0;ec7ir2Do6;kesp59u0M;ia5Jt3;l7me6An,rcere6ul;r,ss;di0oi5;n7s6;sy,t0;g0n0;am2ephe1Iow6;girl,m2r2Q;cretInior cit3Fr6;gea4v6;a4it1;hol4Xi7reen6ulpt1;wr2C;e01on;l1nt;aEe9o8u6;l0nn6;er up,ingE;g40le mod3Zof0;a4Zc8fug2Ppo32searQv6;ere4Uolution6;ary;e6luYru22;ptio3T;bbi,dic5Vpp0;arter6e2Z;back;aYeWhSiRlOoKr8sycho7u6;nk,p31;logi5;aGeDiBo6;d9fess1g7ph47s6;pe2Ktitu51;en6ramm0;it1y;igy,uc0;est4Nme mini0Unce6s3E;!ss;a7si6;de4;ch0;ctiti39nk0P;dca0Oet,li6pula50rnst42;c2Itic6;al scie6i2;nti5;a6umb0;nn0y6;er,ma4Lwright;lgrim,one0;a8iloso7otogra7ra6ysi1V;se;ph0;ntom,rmaci5;r6ssi1T;form0s4O;i3El,nel3Yr8st1tr6wn;i6on;arWot;ent4Wi42tn0;ccupa4ffBp8r7ut6;ca5l0B;ac4Iganiz0ig2Fph2;er3t6;i1Jomet6;ri5;ic0spring;aBe9ie4Xo7u6;n,rser3J;b6mad,vi4V;le2Vo4D;i6mesis,phew;ce,ghb1;nny,rr3t1X;aEeDiAo7u6yst1Y;m8si16;der3gul,m7n6th0;arDk;!my;ni7s6;f02s0Jt0;on,st0;chan1Qnt1rcha4;gi9k0n8rtyr,t6y1;e,riar6;ch;ag0iac;ci2stra3I;a7e2Aieutena4o6;rd,s0v0;bor0d7ndlo6ss,urea3Fwy0ym2;rd;!y;!s28;e8o7u6;ggl0;gg0urna2U;st0;c3Hdol,llu3Ummigra4n6; l9c1Qfa4habi42nov3s7ve6;nt1stig3;pe0Nt6;a1Fig3ru0M;aw;airFeBistoAo8u6ygie1K;man6sba2H;!ita8;bo,st6usekN;age,e3P;ri2;ir,r6;m7o6;!ine;it;dress0sty2C;aLeIhostGirl26ladi3oCrand7u6;e5ru;c9daug0Jfa8m7pa6s2Y;!re4;a,o6;th0;hi1B;al7d6lf0;!de3A;ie,k6te26;eep0;!wr6;it0;isha,n6;i6tl04;us;mbl0rden0;aDella,iAo7r6;eela2Nie1P;e,re6ster pare4;be1Hm2r6st0;unn0;an2ZgZlmm17nanci0r6tt0;e6st la2H; marsh2OfigXm2;rm0th0;conoEdDlectriCm8n7x6;amin0cellency,i2A;emy,trepreneur,vironmenta1J;c8p6;er1loye6;e,r;ee;ci2;it1;mi5;aKeBi8ork,ri7u6we02;de,tche2H;ft0v0;ct3eti7plom2Hre6va;ct1;ci2ti2;aDcor3fencCi0InAput9s7tectLvel6;op0;ce1Ge6ign0;rt0;ee,y;iz6;en;em2;c1Ml0;d8nc0redev7ug6;ht0;il;!dy;a06e04fo,hXitizenWlToBr9u6;r3stomer6;! representat6;ive;e3it6;ic;lJmGnAord9rpor1Nu7w6;boy,ork0;n6ri0;ciTte1Q;in3;fidantAgressSs9t6;e0Kr6;ibut1o6;ll0;tab13ul1O;!e;edi2m6pos0rade;a0EeQissi6;on0;leag8on7um6;ni5;el;ue;e6own;an0r6;ic,k;!s;a9e7i6um;ld;erle6f;ad0;ir7nce6plFract0;ll1;m2wI;lebri6o;ty;dBptAr6shi0;e7pe6;nt0;r,t6;ak0;ain;et;aMeLiJlogg0oErBu6;dd0Fild0rgl9siness6;m2p7w6;om2;ers05;ar;i7o6;!k0th0;cklay0de,gadi0;hemi2oge8y6;!frie6;nd;ym2;an;cyc6sR;li5;atbox0ings;by,nk0r6;b0on7te6;nd0;!e07;c04dWge4nQpLrHsFtAu7yatull6;ah;nt7t6;h1oG;!ie;h8t6;e6orney;nda4;ie5le6;te;sis00tron6;aut,om0;chbis8isto7tis6;an,t;crU;hop;ost9p6;ari6rentiS;ti6;on;le;a9cest1im3nou8y6;bo6;dy;nc0;ly5rc6;hi5;mi8v6;entur0is1;er;ni7r6;al;str3;at1;or;counBquaintanArob9t6;ivi5or,re6;ss;st;at;ce;ta4;nt",
    "Adj|Noun":
      "true¦0:16;a1Db17c0Ud0Re0Mf0Dg0Ah08i06ju05l02mWnUoSpNrIsBt7u4v1watershed;a1ision0Z;gabo4nilla,ria1;b0Vnt;ndergr1pstairs;adua14ou1;nd;a3e1oken,ri0;en,r1;min0rori13;boo,n;age,e5ilv0Flack,o3quat,ta2u1well;bordina0Xper5;b0Lndard;ciali0Yl1vereign;e,ve16;cret,n1ri0;ior;a4e2ou1ubbiL;nd,tiY;ar,bBl0Wnt0p1side11;resent0Vublican;ci0Qsh;a4eriodic0last0Zotenti0r1;emi2incip0o1;!fession0;er,um;rall4st,tie0U;ff1pposi0Hv0;ens0Oi0C;agg01ov1uts;el;a5e3iniatJo1;bi01der07r1;al,t0;di1tr0N;an,um;le,riG;attOi2u1;sh;ber0ght,qC;stice,veniT;de0mpressioYn1;cumbe0Edividu0no0Dsta0Eterim;alf,o1umdrum;bby,melF;en2old,ra1;ph0Bve;er0ious;a7e5i4l3u1;git03t1;ure;uid;ne;llow,m1;aFiL;ir,t,vo1;riOuriO;l3p00x1;c1ecutUpeV;ess;d1iK;er;ar2e1;mographUrivO;k,l2;hiGlassSo2rude,unn1;ing;m5n1operK;creCstitueOte2vertab1;le;mpor1nt;ary;ic,m2p1;anion,lex;er2u1;ni8;ci0;al;e5lank,o4r1;i2u1;te;ef;ttom,urgeois;st;cadem9d6l2ntarct9r1;ab,ct8;e3tern1;at1;ive;rt;oles1ult;ce1;nt;ic",
    "Adj|Past":
      "true¦0:4Q;1:4C;2:4H;3:4E;a44b3Tc36d2Je29f20g1Wh1Si1Jj1Gkno1Fl1Am15n12o0Xp0Mqu0Kr08sLtEuAv9w4yellow0;a7ea6o4rinkl0;r4u3Y;n,ri0;k31th3;rp0sh0tZ;ari0e1O;n5p4s0;d1li1Rset;cov3derstood,i4;fi0t0;a8e3Rhr7i6ouTr4urn0wi4C;a4imm0ou2G;ck0in0pp0;ed,r0;eat2Qi37;m0nn0r4;get0ni2T;aOcKeIhGimFm0Hoak0pDt7u4;bsid3Ogge44s4;pe4ta2Y;ct0nd0;a8e7i2Eok0r5u4;ff0mp0nn0;ength2Hip4;ed,p0;am0reotyp0;in0t0;eci4ik0oH;al3Efi0;pRul1;a4ock0ut;d0r0;a4c1Jle2t31;l0s3Ut0;a6or5r4;at4e25;ch0;r0tt3;t4ut0;is2Mur1;aEe5o4;tt0;cAdJf2Bg9je2l8m0Knew0p7qu6s4;eTpe2t4;or0ri2;e3Dir0;e1lac0;at0e2Q;i0Rul1;eiv0o4ycl0;mme2Lrd0v3;in0lli0ti2A;a4ot0;li28;aCer30iBlAo9r5u4;mp0zzl0;e6i2Oo4;ce2Fd4lo1Anou30pos0te2v0;uc0;fe1CocCp0Iss0;i2Kli1L;ann0e2CuS;ck0erc0ss0;ck0i2Hr4st0;allLk0;bse7c6pp13rgan2Dver4;lo4whelm0;ok0;cupi0;rv0;aJe5o4;t0uri1A;ed0gle2;a6e5ix0o4ut0ys1N;di1Nt15u26;as0Clt0;n4rk0;ag0ufact0A;e6i5o4;ad0ck0st,v0;cens0m04st0;ft,v4;el0;tt0wn;a5o15u4;dg0s1B;gg0;llumSmpAn4sol1;br0cre1Ldebt0f8jZspir0t5v4;it0olv0;e4ox0Y;gr1n4re23;d0si15;e2l1o1Wuri1;li0o01r4;ov0;a6e1o4um03;ok0r4;ri0Z;mm3rm0;i6r5u4;a1Bid0;a0Ui0Rown;ft0;aAe9i8l6oc0Ir4;a4i0oz0Y;ctHg19m0;avo0Ju4;st3;ni08tt0x0;ar0;d0il0sc4;in1;dCl1mBn9quipp0s8x4;agger1c6p4te0T;a0Se4os0;ct0rie1D;it0;cap0tabliZ;cha0XgFha1As4;ur0;a0Zbarra0N;i0Buc1;aMeDi5r4;a01i0;gni08miniSre2s4;a9c6grun0Ft4;o4re0Hu17;rt0;iplWou4;nt0r4;ag0;bl0;cBdRf9l8p7ra6t5v4;elop0ot0;ail0ermQ;ng0;re07;ay0ight0;e4in0o0M;rr0;ay0enTor1;m5t0z4;ed,zl0;ag0p4;en0;aPeLhIlHo9r6u4;lt4r0stom03;iv1;a5owd0u4;sh0;ck0mp0;d0loAm7n4ok0v3;centr1f5s4troC;id3olid1;us0;b5pl4;ic1;in0;r0ur0;assi9os0utt3;ar5i4;ll0;g0m0;lebr1n6r4;ti4;fi0;tralJ;g0lcul1;aDewild3iCl9o7r5urn4;ed,t;ok4uis0;en;il0r0t4und;tl0;e5i4;nd0;ss0;as0;ffl0k0laMs0tt3;bPcNdKfIg0lFmaz0nDppBrm0ss9u5wa4;rd0;g5thor4;iz0;me4;nt0;o6u4;m0r0;li0re4;ci1;im1ticip1;at0;a5leg0t3;er0;rm0;fe2;ct0;ju5o7va4;nc0;st0;ce4knowledg0;pt0;and5so4;rb0;on0;ed",
    Singular:
      "true¦0:5J;1:5H;2:4W;3:4S;4:52;5:57;6:5L;7:56;8:5B;a52b4Lc3Nd35e2Xf2Og2Jh28in24j23k22l1Um1Ln1Ho1Bp0Rqu0Qr0FsZtMuHvCw9x r58yo yo;a9ha3Po3Q;f3i4Rt0Gy9;! arou39;arCeAideo ga2Qo9;cabu4Jl5C;gOr9t;di4Zt1Y;iety,ni4P;nBp30rAs 9;do43s5E;bani1in0;coordinat3Ader9;estima1to24we41; rex,aKeJhHiFoErBuAv9;! show;m2On2rntLto1D;agedy,ib9o4E;e,u9;n0ta46;ni1p2rq3L;c,er,m9;etF;ing9ree26;!y;am,mp3F;ct2le6x return;aNcMeKhor4QiJkHoGpin off,tDuBy9;ll9ner7st4T;ab2X;b9i1n28per bowl,rro1X;st3Ltot0;atAipe2Go1Lrate7udent9;! lo0I;i39u1;ft ser4Lmeo1I;elet5i9;ll,r3V;b38gn2Tte;ab2Jc9min3B;t,urity gua2N;e6ho2Y;bbatic0la3Jndwi0Qpi5;av5eDhetor2iAo9;de6om,w;tAv9;erb2C;e,u0;bDcBf9publ2r10spi1;er9orm3;e6r0;i9ord label;p2Ht0;a1u46;estion mark,ot2F;aPeMhoLiIlGoErAu9yram1F;ddi3HpErpo1Js3J;eBo9;bl3Zs9;pe3Jta1;dic1Rmi1Fp1Qroga8ss relea1F;p9rt0;py;a9ebisci1;q2Dte;cn2eAg9;!gy;!r;ne call,tocoK;anut,dAr9t0yo1;cen3Jsp3K;al,est0;nop4rAt9;e,hog5;adi11i2V;atme0bj3FcBpia1rde0thers,utspok5ve9wn3;n,r9;ti0Pview;cuAe9;an;pi3;arBitAot9umb3;a2Fhi2R;e,ra1;cot2ra8;aFeCiAo9ur0;nopo4p18rni2Nsq1Rti36uld;c,li11n0As9tt5;chief,si34;dAnu,t9;al,i3;al,ic;gna1mm0nd15rsupi0te9yf4;ri0;aDegCiBu9;ddi1n9;ch;me,p09; Be0M;bor14y9; 9er;up;eyno1itt5;el4ourn0;cBdices,itia8ni25sAtel0Lvert9;eb1J;e28titu1;en8i2T;aIeEighDoAu9;man right,s22;me9rmoFsp1Ftb0K;! r9;un; scho0YriY;a9i1N;d9v5; start,pho9;ne;ndful,sh brown,v5ze;aBelat0Ilaci3r9ul4yp1S;an9enadi3id;a1Cd slam,ny;df4r9;l2ni1I;aGeti1HiFlu1oCrAun9;er0;ee market,i9onti3;ga1;l4ur9;so9;me;ePref4;br2mi4;conoFffi7gg,lecto0Rmbas1EnCpidem2s1Zth2venBxAyel9;id;ampZempl0Nte6;i19t;er7terp9;ri9;se;my;eLiEoBr9ump tru0U;agonf4i9;er,ve thru;cAg7i4or,ssi3wn9;side;to0EumenE;aEgniDnn3sAvide9;nd;conte6incen8p9tri11;osi9;ti0C;ta0H;le0X;athBcAf9ni0terre6;ault 05err0;al,im0;!b9;ed;aWeThMiLlJoDr9;edit caBuc9;ib9;le;rd;efficDke,lCmmuniqLnsApi3rr0t0Xus9yo1;in;erv9uI;ato02;ic,lQ;ie6;er7i9oth;e6n2;ty,vil wM;aDeqCick5ocoBr9;istmas car9ysanthemum;ol;la1;ue;ndeli3racteri9;st2;iAllEr9;e0tifica1;liZ;hi3nFpErCt9ucus;erpi9hedr0;ll9;ar;!bohyd9ri3;ra1;it0;aAe,nib0t9;on;l,ry;aMeLiop2leJoHrDu9;nny,r9tterf4;g9i0;la9;ry;eakAi9;ck;fa9throB;st;dy,ro9wl;ugh;mi9;sh;an,l4;nkiArri3;er;ng;cSdMlInFppeti1rDsBtt2utop9;sy;ic;ce6pe9;ct;r9sen0;ay;ecAoma4tiA;ly;do1;i5l9;er7y;gy;en; hominDjAvan9;tage;ec8;ti9;ve;em;cCeAqui9;tt0;ta1;te;iAru0;al;de6;nt",
    "Person|Noun":
      "true¦a0Eb07c03dWeUfQgOhLjHkiGlFmCnBolive,p7r4s3trini06v1wa0;ng,rd,tts;an,enus,iol0;a,et;ky,onPumm09;ay,e1o0uby;bin,d,se;ed,x;a2e1o0;l,tt04;aLnJ;dYge,tR;at,orm;a0eloW;t0x,ya;!s;a9eo,iH;ng,tP;a2e1o0;lGy;an,w3;de,smi4y;a0erb,iOolBuntR;ll,z0;el;ail,e0iLuy;ne;a1ern,i0lo;elds,nn;ith,n0;ny;a0dEmir,ula,ve;rl;a4e3i1j,ol0;ly;ck,x0;ie;an,ja;i0wn;sy;am,h0liff,rystal;a0in,ristian;mbers,ri0;ty;a4e3i2o,r0ud;an0ook;dy;ll;nedict,rg;k0nks;er;l0rt;fredo,ma",
    "Actor|Verb":
      "true¦aCb8c5doctor,engineAfool,g3host,judge,m2nerd,p1recruit,scout,ushAvolunteAwi0;mp,tneA;arent,ilot;an,ime;eek,oof,r0uide;adu8oom;ha1o0;ach,nscript,ok;mpion,uffeur;o2u0;lly,tch0;er;ss;ddi1ffili0rchite1;ate;ct",
    MaleName:
      "true¦0:H6;1:FZ;2:DS;3:GQ;4:CZ;5:FV;6:GM;7:FP;8:GW;9:ET;A:C2;B:GD;aF8bE1cCQdBMeASfA1g8Yh88i7Uj6Sk6Bl5Mm48n3So3Ip33qu31r26s1Et0Ru0Ov0CwTxSyHzC;aCor0;cChC1karia,nAT;!hDkC;!aF6;!ar7CeF5;aJevgenBSoEuC;en,rFVsCu3FvEF;if,uf;nDs6OusC;ouf,s6N;aCg;s,tC;an,h0;hli,nCrosE1ss09;is,nC;!iBU;avi2ho5;aPeNiDoCyaEL;jcieBJlfgang,odrFutR;lFnC;f8TsC;lCt1;ow;bGey,frEhe4QlC;aE5iCy;am,e,s;ed8iC;d,ed;eAur;i,ndeD2rn2sC;!l9t1;lDyC;l1ne;lDtC;!er;aCHy;aKernDAiFladDoC;jteB0lodymyr;!iC;mFQsDB;cFha0ktBZnceDrgCOvC;a0ek;!nC;t,zo;!e4StBV;lCnC7sily;!entC;in9J;ghE2lCm70nax,ri,sm0;riCyss87;ch,k;aWeRhNiLoGrEuDyC;!l2roEDs1;n6r6E;avD0eCist0oy,um0;ntCRvBKy;bFdAWmCny;!asDmCoharu;aFFie,y;!z;iA6y;mCt4;!my,othy;adEeoDia0SomC;!as;!dor91;!de4;dFrC;enBKrC;anBJeCy;ll,nBI;!dy;dgh,ha,iCnn2req,tsu5V;cDAka;aYcotWeThPiMlobod0oKpenc2tEurDvenAEyCzym1;ed,lvest2;aj,e9V;anFeDuC;!aA;fan17phEQvCwaA;e77ie;!islaCl9;v,w;lom1rBuC;leymaDHta;dDgmu9UlCm1yabonga;as,v8B;!dhart8Yn9;aEeClo75;lCrm0;d1t1;h9Jne,qu1Jun,wn,yne;aDbastiEDk2Yl5Mpp,rgCth,ymoCU;e1Dio;m4n;!tC;!ie,y;eDPlFmEnCq67tosCMul;dCj2UtiA5;e01ro;!iATkeB6mC4u5;!ik,vato9K;aZeUheC8iRoGuDyC;an,ou;b99dDf4peAssC;!elEG;ol00y;an,bLc7MdJel,geIh0lHmGnEry,sDyC;!ce;ar7Ocoe,s;!aCnBU;ld,n;an,eo;a7Ef;l7Jr;e3Eg2n9olfo,riC;go;bBNeDH;cCl9;ar87c86h54kCo;!ey,ie,y;cFeA3gDid,ubByCza;an8Ln06;g85iC;naC6s;ep;ch8Kfa5hHin2je8HlGmFndEoHpha5sDul,wi36yC;an,mo8O;h9Im4;alDSol3O;iD0on;f,ph;ul;e9CinC;cy,t1;aOeLhilJiFrCyoG;aDeC;m,st1;ka85v2O;eDoC;tr;r8GtC;er,ro;!ipCl6H;!p6U;dCLrcy,tC;ar,e9JrC;!o7;b9Udra8So9UscAHtri62ulCv8I;!ie,o7;ctav6Ji2lImHndrBRrGsDtCum6wB;is,to;aDc6k6m0vCwaBE;al79;ma;i,vR;ar,er;aDeksandr,ivC;er,i2;f,v;aNeLguyBiFoCu3O;aDel,j4l0ma0rC;beAm0;h,m;cFels,g5i9EkDlC;es,s;!au,h96l78olaC;!i,y;hCkCol76;ol75;al,d,il,ls1vC;ilAF;hom,tC;e,hC;anCy;!a5i5;aYeViLoGuDyC;l4Nr1;hamDr84staC;fa,p6E;ed,mG;di10e,hamEis4JntDritz,sCussa;es,he;e,y;ad,ed,mC;ad,ed;cGgu5hai,kFlEnDtchC;!e8O;a9Pik;house,o7t1;ae73eC3ha8Iolaj;ah,hDkC;!ey,y;aDeC;al,l;el,l;hDlv3rC;le,ri8Ev4T;di,met;ay0c00gn4hWjd,ks2NlTmadZnSrKsXtDuric7VxC;imilBKwe8B;eHhEi69tCus,y69;!eo,hCia7;ew,i67;eDiC;as,eu,s;us,w;j,o;cHiGkFlEqu8Qsha83tCv3;iCy;!m,n;in,on;el,o7us;a6Yo7us;!elCin,o7us;!l8o;frAEi5Zny,u5;achDcoCik;lm;ai,y;amDdi,e5VmC;oud;adCm6W;ou;aulCi9P;ay;aWeOiMloyd,oJuDyC;le,nd1;cFdEiDkCth2uk;a7e;gi,s,z;ov7Cv6Hw6H;!as,iC;a6Een;g0nn52renDuCvA4we7D;!iS;!zo;am,n4oC;n5r;a9Yevi,la5KnHoFst2thaEvC;eCi;nte;bo;nCpo8V;!a82el,id;!nC;aAy;mEnd1rDsz73urenCwr6K;ce,t;ry,s;ar,beAont;aOeIhalHiFla4onr63rDu5SylC;e,s;istCzysztof;i0oph2;er0ngsl9p,rC;ilA9k,ollos;ed,id;en0iGnDrmCv4Z;it;!dDnCt1;e2Ny;ri4Z;r,th;cp2j4mEna8BrDsp6them,uC;ri;im,l;al,il;a03eXiVoFuC;an,lCst3;en,iC;an,en,o,us;aQeOhKkub4AnIrGsDzC;ef;eDhCi9Wue;!ua;!f,ph;dCge;i,on;!aCny;h,s,th6J;anDnC;!ath6Hie,n72;!nC;!es;!l,sCy;ph;o,qu3;an,mC;!i,m6V;d,ffFns,rCs4;a7JemDmai7QoCry;me,ni1H;i9Dy;!e73rC;ey,y;cKdBkImHrEsDvi2yC;dBs1;on,p2;ed,oDrCv67;e6Qod;d,s61;al,es5Wis1;a,e,oCub;b,v;ob,qu13;aTbNchiMgLke53lija,nuKonut,rIsEtCv0;ai,suC;ki;aDha0i8XmaCsac;el,il;ac,iaC;h,s;a,vinCw3;!g;k,nngu6X;nac1Xor;ka;ai,rahC;im;aReLoIuCyd6;beAgGmFsC;eyDsC;a3e3;in,n;ber5W;h,o;m2raDsse3wC;a5Pie;c49t1K;a0Qct3XiGnDrC;beAman08;dr7VrC;iCy2N;!k,q1R;n0Tt3S;bKlJmza,nIo,rEsDyC;a5KdB;an,s0;lEo67r2IuCv9;hi5Hki,tC;a,o;an,ey;k,s;!im;ib;a08e00iUlenToQrMuCyorgy;iHnFsC;!taC;f,vC;!e,o;n6tC;er,h2;do,lC;herDlC;auCerQ;me;aEegCov2;!g,orC;!io,y;dy,h7C;dfr9nza3XrDttfC;ri6C;an,d47;!n;acoGlEno,oCuseppe;rgiCvan6O;!o,s;be6Ies,lC;es;mo;oFrC;aDha4HrC;it,y;ld,rd8;ffErgC;!e7iCy;!os;!r9;bElBrCv3;eCla1Nr4Hth,y;th;e,rC;e3YielC;!i4;aXeSiQlOorrest,rCyod2E;aHedFiC;edDtC;s,z;ri18;!d42eri11riC;ck,k;nCs2;cEkC;ie,lC;in,yn;esLisC;!co,z3M;etch2oC;ri0yd;d5lConn;ip;deriFliEng,rC;dinaCg4nan0B;nd8;pe,x;co;bCdi,hd;iEriC;ce,zC;io;an,en,o;benez2dZfrYit0lTmMnJo3rFsteb0th0ugenEvCymBzra;an,eCge4D;ns,re3K;!e;gi,iDnCrol,v3w3;est8ie,st;cCk;!h,k;o0DriCzo;co,qC;ue;aHerGiDmC;aGe3A;lCrh0;!iC;a10o,s;s1y;nu5;beAd1iEliDm2t1viCwood;n,s;ot28s;!as,j5Hot,sC;ha;a3en;!dGg6mFoDua2QwC;a2Pin;arC;do;oZuZ;ie;a04eTiOmitrNoFrag0uEwDylC;an,l0;ay3Hig4D;a3Gdl9nc0st3;minFnDri0ugCvydGy2S;!lF;!a36nCov0;e1Eie,y;go,iDykC;as;cCk;!k;i,y;armuFetDll1mitri7neCon,rk;sh;er,m6riC;ch;id;andLepak,j0lbeAmetri4nIon,rGsEvDwCxt2;ay30ey;en,in;hawn,moC;nd;ek,riC;ck;is,nC;is,y;rt;re;an,le,mKnIrEvC;e,iC;!d;en,iEne0PrCyl;eCin,yl;l45n;n,o,us;!iCny;el,lo;iCon;an,en,on;a0Fe0Ch03iar0lRoJrFuDyrC;il,us;rtC;!is;aEistC;iaCob12;no;ig;dy,lInErC;ey,neliCy;s,us;nEor,rDstaC;nt3;ad;or;by,e,in,l3t1;aHeEiCyde;fCnt,ve;fo0Xt1;menDt4;us;s,t;rFuDyC;!t1;dCs;e,io;enC;ce;aHeGrisC;!toC;phCs;!eC;!r;st2t;d,rCs;b5leC;s,y;cDdrCs6;ic;il;lHmFrC;ey,lDroCy;ll;!o7t1;er1iC;lo;!eb,v3;a09eZiVjorn,laUoSrEuCyr1;ddy,rtKst2;er;aKeFiEuDyC;an,ce,on;ce,no;an,ce;nDtC;!t;dDtC;!on;an,on;dFnC;dDisC;lav;en,on;!foOl9y;bby,gd0rCyd;is;i0Lke;bElDshC;al;al,lL;ek;nIrCshoi;at,nEtC;!raC;m,nd;aDhaCie;rd;rd8;!iDjam3nCs1;ie,y;to;kaMlazs,nHrC;n9rDtC;!holomew;eCy;tt;ey;dCeD;ar,iC;le;ar1Nb1Dd16fon15gust3hm12i0Zja0Yl0Bm07nTputsiSrGsaFugustEveDyCziz;a0kh0;ry;o,us;hi;aMchiKiJjun,mHnEon,tCy0;em,hCie,ur8;ur;aDoC;!ld;ud,v;aCin;an,nd8;!el,ki;baCe;ld;ta;aq;aMdHgel8tCw6;hoFoC;iDnC;!i8y;ne;ny;er7rCy;eDzC;ej;!as,i,j,s,w;!s;s,tolC;iCy;!y;ar,iEmaCos;nu5r;el;ne,r,t;aVbSdBeJfHiGl01onFphonsEt1vC;aPin;on;e,o;so,zo;!sR;!onZrC;ed;c,jaHksFssaHxC;!andC;er,rC;e,os,u;andCei;ar,er,r;ndC;ro;en;eDrecC;ht;rt8;dd3in,n,sC;taC;ir;ni;dDm6;ar;an,en;ad,eC;d,t;in;so;aGi,olErDvC;ik;ian8;f8ph;!o;mCn;!a;dGeFraDuC;!bakr,lfazl;hCm;am;!l;allFel,oulaye,ulC;!lDrahm0;an;ah,o;ah;av,on",
    Uncountable:
      "true¦0:2E;1:2L;2:33;a2Ub2Lc29d22e1Rf1Ng1Eh16i11j0Yk0Wl0Rm0Hn0Do0Cp03rZsLt9uran2Jv7w3you gu0E;a5his17i4oo3;d,l;ldlife,ne;rm8t1;apor,ernacul29i3;neg28ol1Otae;eDhBiAo8r4un3yranny;a,gst1B;aff2Oea1Ko4ue nor3;th;o08u3;bleshoot2Ose1Tt;night,othpas1Vwn3;foEsfoE;me off,n;er3und1;e,mod2S;a,nnis;aDcCeBhAi9ki8o7p6t4u3weepstak0;g1Unshi2Hshi;ati08e3;am,el;ace2Keci0;ap,cc1meth2C;n,ttl0;lk;eep,ingl0or1C;lf,na1Gri0;ene1Kisso1C;d0Wfe2l4nd,t3;i0Iurn;m1Ut;abi0e4ic3;e,ke15;c3i01laxa11search;ogni10rea10;a9e8hys7luto,o5re3ut2;amble,mis0s3ten20;en1Zs0L;l3rk;i28l0EyH; 16i28;a24tr0F;nt3ti0M;i0s;bstetri24vercrowd1Qxyg09;a5e4owada3utella;ys;ptu1Ows;il poliZtional securi2;aAe8o5u3;m3s1H;ps;n3o1K;ey,o3;gamy;a3cha0Elancholy,rchandi1Htallurgy;sl0t;chine3g1Aj1Hrs,thema1Q; learn1Cry;aught1e6i5ogi4u3;ck,g12;c,s1M;ce,ghtn18nguis1LteratWv1;ath1isVss;ara0EindergartPn3;icke0Aowled0Y;e3upit1;a3llyfiGwel0G;ns;ce,gnor6mp5n3;forma00ter3;net,sta07;atiSort3rov;an18;a7e6isto09o3ung1;ckey,mework,ne4o3rseradi8spitali2use arrest;ky;s2y;adquarteXre;ir,libut,ppiHs3;hi3te;sh;ene8l6o5r3um,ymnas11;a3eZ;niUss;lf,re;ut3yce0F;en; 3ti0W;edit0Hpo3;ol;aNicFlour,o4urnit3;ure;od,rgive3uri1wl;ness;arCcono0LducaBlectr9n7quip8thi0Pvery6x3;ist4per3;ti0B;en0J;body,o08th07;joy3tertain3;ment;ici2o3;ni0H;tiS;nings,th;emi02i6o4raugh3ynas2;ts;pe,wnstai3;rs;abet0ce,s3;honZrepu3;te;aDelciChAivi07l8o3urrency;al,ld w6mmenta5n3ral,ttIuscoB;fusiHt 3;ed;ry;ar;assi01oth0;es;aos,e3;eMwK;us;d,rO;a8i6lood,owlHread5u3;ntGtt1;er;!th;lliarJs3;on;g3ss;ga3;ge;cKdviJeroGirFmBn6ppeal court,r4spi3thleL;rin;ithmet3sen3;ic;i6y3;o4th3;ing;ne;se;en5n3;es2;ty;ds;craft;bi8d3nau7;yna3;mi6;ce;id,ous3;ti3;cs",
    Infinitive:
      "true¦0:9G;1:9T;2:AD;3:90;4:9Z;5:84;6:AH;7:A9;8:92;9:A0;A:AG;B:AI;C:9V;D:8R;E:8O;F:97;G:6H;H:7D;a94b8Hc7Jd68e4Zf4Mg4Gh4Ai3Qj3Nk3Kl3Bm34nou48o2Vp2Equ2Dr1Es0CtZuTvRwI;aOeNiLors5rI;eJiI;ng,te;ak,st3;d5e8TthI;draw,er;a2d,ep;i2ke,nIrn;d1t;aIie;liADniAry;nJpI;ho8Llift;cov1dJear8Hfound8DlIplug,rav82tie,ve94;eaAo3X;erIo;cut,go,staAFvalA3w2G;aSeQhNoMrIu73;aIe72;ffi3Smp3nsI;aBfo7CpI;i8oD;pp3ugh5;aJiJrIwaD;eat5i2;nk;aImA0;ch,se;ck3ilor,keImp1r8L;! paD;a0Ic0He0Fh0Bi0Al08mugg3n07o05p02qu01tUuLwI;aJeeIim;p,t5;ll7Wy;bNccMffLggeCmmKppJrI;mouFpa6Zvi2;o0re6Y;ari0on;er,i4;e7Numb;li9KmJsiIveD;de,st;er9it;aMe8MiKrI;ang3eIi2;ng27w;fIng;f5le;b,gg1rI;t3ve;a4AiA;a4UeJit,l7DoI;il,of;ak,nd;lIot7Kw;icEve;atGeak,i0O;aIi6;m,y;ft,ng,t;aKi6CoJriIun;nk,v6Q;ot,rt5;ke,rp5tt1;eIll,nd,que8Gv1w;!k,m;aven9ul8W;dd5tis1Iy;a0FeKiJoI;am,t,ut;d,p5;a0Ab08c06d05f01group,hea00iZjoi4lXmWnVpTq3MsOtMup,vI;amp,eJiIo3B;sEve;l,rI;e,t;i8rI;ie2ofE;eLiKpo8PtIurfa4;o24rI;aHiBuctu8;de,gn,st;mb3nt;el,hra0lIreseF;a4e71;d1ew,o07;aHe3Fo2;a7eFiIo6Jy;e2nq41ve;mbur0nf38;r0t;inKleBocus,rJuI;el,rbiA;aBeA;an4e;aBu4;ei2k8Bla43oIyc3;gni39nci3up,v1;oot,uI;ff;ct,d,liIp;se,ze;tt3viA;aAenGit,o7;aWerUinpoiFlumm1LoTrLuI;b47ke,niArIt;poDsuI;aFe;eMoI;cKd,fe4XhibEmo7noJpo0sp1tru6vI;e,i6o5L;un4;la3Nu8;aGclu6dJf1occupy,sup0JvI;a6BeF;etermi4TiB;aGllu7rtr5Ksse4Q;cei2fo4NiAmea7plex,sIva6;eve8iCua6;mp1rItrol,ve;a6It6E;bOccuNmEpMutLverIwe;l07sJtu6Yu0wI;helm;ee,h1F;gr5Cnu2Cpa4;era7i4Ipo0;py,r;ey,seItaH;r2ss;aMe0ViJoIultiply;leCu6Pw;micJnIspla4;ce,g3us;!k;iIke,na9;m,ntaH;aPeLiIo0u3N;ke,ng1quIv5;eIi6S;fy;aKnIss5;d,gI;th5;rn,ve;ng2Gu1N;eep,idnJnI;e4Cow;ap;oHuI;gg3xtaI;po0;gno8mVnIrk;cTdRfQgeChPitia7ju8q1CsNtKun6EvI;a6eIo11;nt,rt,st;erJimi6BoxiPrI;odu4u6;aBn,pr03ru6C;iCpi8tIu8;all,il,ruB;abEibE;eCo3Eu0;iIul9;ca7;i7lu6;b5Xmer0pI;aLer4Uin9ly,oJrI;e3Ais6Bo2;rt,se,veI;riA;le,rt;aLeKiIoiCuD;de,jaInd1;ck;ar,iT;mp1ng,pp5raIve;ng5Mss;ath1et,iMle27oLrI;aJeIow;et;b,pp3ze;!ve5A;gg3ve;aTer45i5RlSorMrJuI;lf4Cndrai0r48;eJiIolic;ght5;e0Qsh5;b3XeLfeEgJsI;a3Dee;eIi2;!t;clo0go,shIwa4Z;ad3F;att1ee,i36;lt1st5;a0OdEl0Mm0FnXquip,rWsVtGvTxI;aRcPeDhOiNpJtIu6;ing0Yol;eKi8lIo0un9;aHoI;it,re;ct,di7l;st,t;a3oDu3B;e30lI;a10u6;lt,mi28;alua7oI;ke,l2;chew,pou0tab19;a0u4U;aYcVdTfSgQhan4joy,lPqOrNsuMtKvI;e0YisI;a9i50;er,i4rI;aHenGuC;e,re;iGol0F;ui8;ar9iC;a9eIra2ulf;nd1;or4;ang1oIu8;r0w;irc3lo0ou0ErJuI;mb1;oaGy4D;b3ct;bKer9pI;hasiIow1;ze;aKody,rI;a4oiI;d1l;lm,rk;ap0eBuI;ci40de;rIt;ma0Rn;a0Re04iKo,rIwind3;aw,ed9oI;wn;agno0e,ff1g,mi2Kne,sLvI;eIul9;rIst;ge,t;aWbVcQlod9mant3pNru3TsMtI;iIoDu37;lJngI;uiA;!l;ol2ua6;eJlIo0ro2;a4ea0;n0r0;a2Xe36lKoIu0S;uIv1;ra9;aIo0;im;a3Kur0;b3rm;af5b01cVduBep5fUliTmQnOpMrLsiCtaGvI;eIol2;lop;ch;a20i2;aDiBloIoD;re,y;oIy;te,un4;eJoI;liA;an;mEv1;a4i0Ao06raud,y;ei2iMla8oKrI;ee,yI;!pt;de,mIup3;missi34po0;de,ma7ph1;aJrief,uI;g,nk;rk;mp5rk5uF;a0Dea0h0Ai09l08oKrIurta1G;a2ea7ipp3uI;mb3;ales4e04habEinci6ll03m00nIrro6;cXdUfQju8no7qu1sLtKvI;eIin4;ne,r9y;aHin2Bribu7;er2iLoli2Epi8tJuI;lt,me;itu7raH;in;d1st;eKiJoIroFu0;rm;de,gu8rm;ss;eJoI;ne;mn,n0;eIlu6ur;al,i2;buCe,men4pI;eIi3ly;l,te;eBi6u6;r4xiC;ean0iT;rcumveFte;eJirp,oI;o0p;riAw;ncIre5t1ulk;el;a02eSi6lQoPrKuI;iXrIy;st,y;aLeaKiJoad5;en;ng;stfeLtX;ke;il,l11mba0WrrMth1;eIow;ed;!coQfrie1LgPhMliLqueaKstJtrIwild1;ay;ow;th;e2tt3;a2eJoI;ld;ad;!in,ui3;me;bysEckfi8ff3tI;he;b15c0Rd0Iff0Ggree,l0Cm09n03ppZrXsQttOuMvJwaE;it;eDoI;id;rt;gIto0X;meF;aIeCraB;ch,in;pi8sJtoI;niA;aKeIi04u8;mb3rt,ss;le;il;re;g0Hi0ou0rI;an9i2;eaKly,oiFrI;ai0o2;nt;r,se;aMi0GnJtI;icipa7;eJoIul;un4y;al;ly0;aJu0;se;lga08ze;iKlI;e9oIu6;t,w;gn;ix,oI;rd;a03jNmiKoJsoI;rb;pt,rn;niIt;st1;er;ouJuC;st;rn;cLhie2knowled9quiItiva7;es4re;ce;ge;eQliOoKrJusI;e,tom;ue;mIst;moJpI;any,liA;da7;ma7;te;pt;andPduBet,i6oKsI;coKol2;ve;liArt,uI;nd;sh;de;ct;on",
    Person:
      "true¦0:1Q;a29b1Zc1Md1Ee18f15g13h0Ri0Qj0Nk0Jl0Gm09n06o05p00rPsItCusain bolt,v9w4xzibit,y1;anni,oko on2uji,v1;an,es;en,o;a3ednesday adams,i2o1;lfram,o0Q;ll ferrell,z khalifa;lt disn1Qr1;hol,r0G;a2i1oltai06;n dies0Zrginia wo17;lentino rossi,n goG;a4h3i2ripp,u1yra banks;lZpac shakur;ger woods,mba07;eresa may,or;kashi,t1ylor;um,ya1B;a5carlett johanss0h4i3lobodan milosevic,no2ocr1Lpider1uperm0Fwami; m0Em0E;op dogg,w whi1H;egfried,nbad;akespeaTerlock holm1Sia labeouf;ddam hussa16nt1;a cla11ig9;aAe6i5o3u1za;mi,n dmc,paul,sh limbau1;gh;bin hood,d stew16nald1thko;in0Mo;han0Yngo starr,valdo;ese witherspo0i1mbrandt;ll2nh1;old;ey,y;chmaninoff,ffi,iJshid,y roma1H;a4e3i2la16o1uff daddy;cahont0Ie;lar,p19;le,rZ;lm17ris hilt0;leg,prah winfr0Sra;a2e1iles cra1Bostradam0J; yo,l5tt06wmQ;pole0s;a5e4i2o1ubar03;by,lie5net,rriss0N;randa ju1tt romn0M;ly;rl0GssiaB;cklemo1rkov,s0ta hari,ya angelou;re;ady gaga,e1ibera0Pu;bron jam0Xch wale1e;sa;anye west,e3i1obe bryant;d cudi,efer suther1;la0P;ats,sha;a2effers0fk,k rowling,rr tolki1;en;ck the ripp0Mwaharlal nehru,y z;liTnez,ron m7;a7e5i3u1;lk hog5mphrey1sa01;! bog05;l1tl0H;de; m1dwig,nry 4;an;ile selassFlle ber4m3rrison1;! 1;ford;id,mo09;ry;ast0iannis,o1;odwPtye;ergus0lorence nightinga08r1;an1ederic chopN;s,z;ff5m2nya,ustaXzeki1;el;eril lagasse,i1;le zatop1nem;ek;ie;a6e4i2octor w1rake;ho;ck w1ego maradoC;olf;g1mi lovaOnzel washingt0;as;l1nHrth vadR;ai lNt0;a8h5lint0o1thulhu;n1olio;an,fuci1;us;on;aucKop2ristian baMy1;na;in;millo,ptain beefhe4r1;dinal wols2son1;! palmF;ey;art;a8e5hatt,i3oHro1;ck,n1;te;ll g1ng crosby;atB;ck,nazir bhut2rtil,yon1;ce;to;nksy,rack ob1;ama;l 6r3shton kutch2vril lavig8yn ra1;nd;er;chimed2istot1;le;es;capo2paci1;no;ne",
    Adjective:
      "true¦0:AI;1:BS;2:BI;3:BA;4:A8;5:84;6:AV;7:AN;8:AF;9:7H;A:BQ;B:AY;C:BC;D:BH;E:9Y;aA2b9Ec8Fd7We79f6Ng6Eh61i4Xj4Wk4Tl4Im41n3Po36p2Oquart7Pr2Ds1Dt14uSvOwFye29;aMeKhIiHoF;man5oFrth7G;dADzy;despreB1n w97s86;acked1UoleF;!sa6;ather1PeFll o70ste1D;!k5;nt1Ist6Ate4;aHeGiFola5T;bBUce versa,gi3Lle;ng67rsa5R;ca1gBSluAV;lt0PnLpHrGsFttermoBL;ef9Ku3;b96ge1; Hb32pGsFtiAH;ca6ide d4R;er,i85;f52to da2;a0Fbeco0Hc0Bd04e02f01gu1XheaBGiXkn4OmUnTopp06pRrNsJtHus0wF;aFiel3K;nt0rra0P;app0eXoF;ld,uS;eHi37o5ApGuF;perv06spec39;e1ok9O;en,ttl0;eFu5;cogn06gul2RlGqu84sF;erv0olv0;at0en33;aFrecede0E;id,rallel0;am0otic0;aFet;rri0tF;ch0;nFq26vers3;sur0terFv7U;eFrupt0;st0;air,inish0orese98;mploy0n7Ov97xpF;ect0lain0;eHisFocume01ue;clFput0;os0;cid0rF;!a8Scov9ha8Jlyi8nea8Gprivileg0sMwF;aFei9I;t9y;hGircumcFonvin2U;is0;aFeck0;lleng0rt0;b20ppea85ssuGttend0uthorF;iz0;mi8;i4Ara;aLeIhoHip 25oGrF;anspare1encha1i2;geth9leADp notch,rpB;rny,ugh6H;ena8DmpGrFs6U;r49tia4;eCo8P;leFst4M;nt0;a0Dc09e07h06i04ki03l01mug,nobbi4XoVpRqueami4XtKuFymb94;bHccinAi generis,pFr5;erFre7N;! dup9b,vi70;du0li7Lp6IsFurb7J;eq9Atanda9X;aKeJi16o2QrGubboFy4Q;rn;aightFin5GungS; fFfF;or7V;adfa9Pri6;lwa6Ftu82;arHeGir6NlendBot Fry;on;c3Qe1S;k5se; call0lImb9phistic16rHuFviV;ndFth1B;proof;dBry;dFub6; o2A;e60ipF;pe4shod;ll0n d7R;g2HnF;ceEg6ist9;am3Se9;co1Zem5lfFn6Are7; suf4Xi43;aGholFient3A;ar5;rlFt4A;et;cr0me,tisfac7F;aOeIheumatoBiGoF;bu8Ztt7Gy3;ghtFv3; 1Sf6X;cJdu8PlInown0pro69sGtF;ard0;is47oF;lu2na1;e1Suc45;alcit8Xe1ondi2;bBci3mpa1;aSePicayu7laOoNrGuF;bl7Tnjabi;eKiIoF;b7VfGmi49pFxi2M;er,ort81;a7uD;maFor,sti7va2;!ry;ciDexis0Ima2CpaB;in55puli8G;cBid;ac2Ynt 3IrFti2;ma40tFv7W;!i3Z;i2YrFss7R;anoBtF; 5XiF;al,s5V;bSffQkPld OnMrLth9utKverF;!aIbMdHhGni75seas,t,wF;ei74rou74;a63e7A;ue;ll;do1Ger,si6A;d3Qg2Aotu5Z; bFbFe on o7g3Uli7;oa80;fashion0school;!ay; gua7XbFha5Uli7;eat;eHligGsF;ce7er0So1C;at0;diFse;a1e1;aOeNiMoGuF;anc0de; moEnHrthFt6V;!eFwe7L;a7Krn;chaGdescri7Iprof30sF;top;la1;ght5;arby,cessa4ighbor5wlyw0xt;k0usiaFv3;ti8;aQeNiLoHuF;dIltiF;facet0p6;deHlGnFot,rbBst;ochro4Xth5;dy;rn,st;ddle ag0nF;dbloZi,or;ag9diocEga,naGrFtropolit4Q;e,ry;ci8;cIgenta,inHj0Fkeshift,mmGnFri4Oscu61ver18;da5Dy;ali4Lo4U;!stream;abEho;aOeLiIoFumberi8;ngFuti1R;stan3RtF;erm,i4H;ghtGteraF;l,ry,te;heart0wei5O;ft JgFss9th3;al,eFi0M;nda4;nguBps0te5;apGind5noF;wi8;ut;ad0itte4uniW;ce co0Hgno6Mll0Cm04nHpso 2UrF;a2releF;va1; ZaYcoWdReQfOgrNhibi4Ri05nMoLsHtFvalu5M;aAeF;nDrdepe2K;a7iGolFuboI;ub6ve1;de,gF;nifica1;rdi5N;a2er;own;eriIiLluenVrF;ar0eq5H;pt,rt;eHiGoFul1O;or;e,reA;fiFpe26termi5E;ni2;mpFnsideCrreA;le2;ccuCdeq5Ene,ppr4J;fFsitu,vitro;ro1;mJpF;arHeGl15oFrop9;li2r11;n2LrfeA;ti3;aGeFi18;d4BnD;tuE;egGiF;c0YteC;al,iF;tiF;ma2;ld;aOelNiLoFuma7;a4meInHrrGsFur5;ti6;if4E;e58o3U; ma3GsF;ick;ghfalut2HspF;an49;li00pf33;i4llow0ndGrdFtM; 05coEworki8;sy,y;aLener44iga3Blob3oKrGuF;il1Nng ho;aFea1Fizzl0;cGtF;ef2Vis;ef2U;ld3Aod;iFuc2D;nf2R;aVeSiQlOoJrF;aGeFil5ug3;q43tf2O;gFnt3S;i6ra1;lk13oHrF; keeps,eFge0Vm9tu41;g0Ei2Ds3R;liF;sh;ag4Mowe4uF;e1or45;e4nF;al,i2;d Gmini7rF;ti6ve1;up;bl0lDmIr Fst pac0ux;oGreacF;hi8;ff;ed,ili0R;aXfVlTmQnOqu3rMthere3veryday,xF;aApIquisi2traHuF;be48lF;ta1;!va2L;edRlF;icF;it;eAstF;whi6; Famor0ough,tiE;rou2sui2;erGiF;ne1;ge1;dFe2Aoq34;er5;ficF;ie1;g9sF;t,ygF;oi8;er;aWeMiHoGrFue;ea4owY;ci6mina1ne,r31ti8ubQ;dact2Jfficult,m,sGverF;ge1se;creGePjoi1paCtF;a1inA;et,te; Nadp0WceMfiLgeneCliJmuEpeIreliAsGvoF;id,ut;pFtitu2ul1L;eCoF;nde1;ca2ghF;tf13;a1ni2;as0;facto;i5ngero0I;ar0Ce09h07i06l05oOrIuF;rmudgeon5stoma4teF;sy;ly;aIeHu1EystalF; cleFli7;ar;epy;fFv17z0;ty;erUgTloSmPnGrpoCunterclVveFy;rt;cLdJgr21jIsHtrF;aFi2;dic0Yry;eq1Yta1;oi1ug3;escenFuN;di8;a1QeFiD;it0;atoDmensuCpF;ass1SulF;so4;ni3ss3;e1niza1;ci1J;ockwiD;rcumspeAvil;eFintzy;e4wy;leGrtaF;in;ba2;diac,ef00;a00ePiLliJoGrFuck nak0;and new,isk,on22;gGldface,naF; fi05fi05;us;nd,tF;he;gGpartisFzarE;an;tiF;me;autifOhiNlLnHsFyoN;iWtselF;li8;eGiFt;gn;aFfi03;th;at0oF;v0w;nd;ul;ckwards,rF;e,rT; priori,b13c0Zd0Tf0Ng0Ihe0Hl09mp6nt06pZrTsQttracti0MuLvIwF;aGkF;wa1B;ke,re;ant garGeraF;ge;de;diIsteEtF;heFoimmu7;nt07;re;to4;hGlFtu2;eep;en;bitIchiv3roHtF;ifiFsy;ci3;ga1;ra4;ry;pFt;aHetizi8rF;oprF;ia2;llFre1;ed,i8;ng;iquFsy;at0e;ed;cohKiJkaHl,oGriFterX;ght;ne,of;li7;ne;ke,ve;olF;ic;ad;ain07gressiIi6rF;eeF;ab6;le;ve;fGraB;id;ectGlF;ue1;ioF;na2; JaIeGvF;erD;pt,qF;ua2;ma1;hoc,infinitum;cuCquiGtu3u2;al;esce1;ra2;erSjeAlPoNrKsGuF;nda1;e1olu2trF;aAuD;se;te;eaGuF;pt;st;aFve;rd;aFe;ze;ct;ra1;nt",
    Pronoun: "true¦elle,h3i2me,she,th0us,we,you;e0ou;e,m,y;!l,t;e,im",
    Preposition:
      "true¦aPbMcLdKexcept,fIinGmid,notwithstandiWoDpXqua,sCt7u4v2w0;/o,hereSith0;! whHin,oW;ersus,i0;a,s a vis;n1p0;!on;like,til;h1ill,oward0;!s;an,ereby,r0;ough0u;!oM;ans,ince,o that,uch G;f1n0ut;!to;!f;! 0to;effect,part;or,r0;om;espite,own,u3;hez,irca;ar1e0oBy;sides,tween;ri7;bo8cross,ft7lo6m4propos,round,s1t0;!op;! 0;a whole,long 0;as;id0ong0;!st;ng;er;ut",
    SportsTeam:
      "true¦0:18;1:1E;2:1D;3:14;a1Db15c0Sd0Kfc dallas,g0Ihouston 0Hindiana0Gjacksonville jagua0k0El0Am01new UoRpKqueens parkJreal salt lake,sBt6utah jazz,vancouver whitecaps,w4yW;ashington 4h10;natio1Mredski2wizar0W;ampa bay 7e6o4;ronto 4ttenham hotspur;blue ja0Mrapto0;nnessee tita2xasD;buccanee0ra0K;a8eattle 6porting kansas0Wt4; louis 4oke0V;c1Drams;marine0s4;eah13ounH;cramento Rn 4;antonio spu0diego 4francisco gJjose earthquak1;char08paB; ran07;a9h6ittsburgh 5ortland t4;imbe0rail blaze0;pirat1steele0;il4oenix su2;adelphia 4li1;eagl1philNunE;dr1;akland 4klahoma city thunder,rlando magic;athle0Lrai4;de0;england 8orleans 7york 4;g5je3knYme3red bul0Xy4;anke1;ian3;pelica2sain3;patrio3revolut4;ion;anchEeAi4ontreal impact;ami 8lwaukee b7nnesota 4;t5vi4;kings;imberwolv1wi2;rewe0uc0J;dolphi2heat,marli2;mphis grizz4ts;li1;a6eic5os angeles 4;clippe0dodFlaB;esterV; galaxy,ke0;ansas city 4nF;chiefs,roya0D; pace0polis col3;astr05dynamo,rocke3texa2;olden state warrio0reen bay pac4;ke0;allas 8e4i04od6;nver 6troit 4;lio2pisto2ti4;ge0;broncYnugge3;cowbo5maver4;icZ;ys;arEelLhAincinnati 8leveland 6ol4;orado r4umbus crew sc;api7ocki1;brow2cavalie0guar4in4;dia2;bengaVre4;ds;arlotte horAicago 4;b5cubs,fire,wh4;iteB;ea0ulQ;diff4olina panthe0; city;altimore Alackburn rove0oston 6rooklyn 4uffalo bilN;ne3;ts;cel5red4; sox;tics;rs;oriol1rave2;rizona Ast8tlanta 4;brav1falco2h4;awA;ns;es;on villa,r4;os;c6di4;amondbac4;ks;ardi4;na4;ls",
    Unit: "true¦a07b04cXdWexVfTgRhePinYjoule0BkMlJmDnan08oCp9quart0Bsq ft,t7volts,w6y2ze3°1µ0;g,s;c,f,n;dVear1o0;ttR; 0s 0;old;att,b;erNon0;!ne02;ascals,e1i0;cXnt00;rcent,tJ;hms,unceY;/s,e4i0m²,²,³;/h,cro2l0;e0liK;!²;grLsR;gCtJ;it1u0;menQx;erPreP;b5elvins,ilo1m0notO;/h,ph,²;!byGgrEmCs;ct0rtzL;aJogrC;allonJb0ig3rB;ps;a0emtEl oz,t4;hrenheit,radG;aby9;eci3m1;aratDe1m0oulombD;²,³;lsius,nti0;gr2lit1m0;et0;er8;am7;b1y0;te5;l,ps;c2tt0;os0;econd1;re0;!s",
    "Noun|Gerund":
      "true¦0:3O;1:3M;2:3N;3:3D;4:32;5:2V;6:3E;7:3K;8:36;9:3J;A:3B;a3Pb37c2Jd27e23f1Vg1Sh1Mi1Ij1Gk1Dl18m13n11o0Wp0Pques0Sr0EsTtNunderMvKwFyDzB;eroi0oB;ni0o3P;aw2eB;ar2l3;aEed4hispe5i5oCrB;ap8est3i1;n0ErB;ki0r31;i1r2s9tc9;isualizi0oB;lunt1Vti0;stan4ta6;aFeDhin6iCraBy8;c6di0i2vel1M;mi0p8;aBs1;c9si0;l6n2s1;aUcReQhOiMkatKl2Wmo6nowJpeItFuCwB;ea5im37;b35f0FrB;fi0vB;e2Mi2J;aAoryt1KrCuB;d2KfS;etc9ugg3;l3n4;bCi0;ebBi0;oar4;gnBnAt1;a3i0;ip8oB;p8rte2u1;a1r27t1;hCo5reBulp1;a2Qe2;edu3oo3;i3yi0;aKeEi4oCuB;li0n2;oBwi0;fi0;aFcEhear7laxi0nDpor1sB;pon4tructB;r2Iu5;de5;or4yc3;di0so2;p8ti0;aFeacek20laEoCrBublis9;a1Teten4in1oces7;iso2siB;tio2;n2yi0;ckaAin1rB;ki0t1O;fEpeDrganiCvB;erco24ula1;si0zi0;ni0ra1;fe5;avi0QeBur7;gotia1twor6;aDeCi2oB;de3nito5;a2dita1e1ssaA;int0XnBrke1;ifUufactu5;aEeaDiBodAyi0;cen7f1mi1stB;e2i0;r2si0;n4ug9;iCnB;ea4it1;c6l3;ogAuB;dAgg3stif12;ci0llust0VmDnBro2;nova1sp0NterBven1;ac1vie02;agi2plo4;aDea1iCoBun1;l4w3;ki0ri0;nd3rB;roWvB;es1;aCene0Lli4rBui4;ee1ie0N;rde2the5;aHeGiDlCorBros1un4;e0Pmat1;ir1oo4;gh1lCnBs9;anZdi0;i0li0;e3nX;r0Zscina1;a1du01nCxB;erci7plo5;chan1di0ginB;ee5;aLeHiGoub1rCum8wB;el3;aDeCiB;bb3n6vi0;a0Qs7;wi0;rTscoDvi0;ba1coZlBvelo8;eCiB;ve5;ga1;nGti0;aVelebUhSlPoDrBur3yc3;aBos7yi0;f1w3;aLdi0lJmFnBo6pi0ve5;dDsCvinB;ci0;trBul1;uc1;muniDpB;lBo7;ai2;ca1;lBo5;ec1;c9ti0;ap8eaCimToBubT;ni0t9;ni0ri0;aBee5;n1t1;ra1;m8rCs1te5;ri0;vi0;aPeNitMlLoGrDuB;dge1il4llBr8;yi0;an4eat9oadB;cas1;di0;a1mEokB;i0kB;ee8;pi0;bi0;es7oa1;c9i0;gin2lonAt1;gi0;bysit1c6ki0tt3;li0;ki0;bando2cGdverti7gi0pproac9rgDssuCtB;trac1;mi0;ui0;hi0;si0;coun1ti0;ti0;ni0;ng",
    PhrasalVerb:
      "true¦0:92;1:96;2:8H;3:8V;4:8A;5:83;6:85;7:98;8:90;9:8G;A:8X;B:8R;C:8U;D:8S;E:70;F:97;G:8Y;H:81;I:7H;J:79;a9Fb7Uc6Rd6Le6Jf5Ig50h4Biron0j47k40l3Em31n2Yo2Wp2Cquiet Hr1Xs0KtZuXvacuu6QwNyammerBzK;ero Dip LonK;e0k0;by,ov9up;aQeMhLiKor0Mrit19;mp0n3Fpe0r5s5;ackAeel Di0S;aLiKn33;gh 3Wrd0;n Dr K;do1in,oJ;it 79k5lk Lrm 69sh Kt83v60;aw3do1o7up;aw3in,oC;rgeBsK;e 2herE;a00eYhViRoQrMuKypP;ckErn K;do1in,oJup;aLiKot0y 30;ckl7Zp F;ck HdK;e 5Y;n7Wp 3Es5K;ck MdLe Kghten 6me0p o0Rre0;aw3ba4do1in,up;e Iy 2;by,oG;ink Lrow K;aw3ba4in,up;ba4ov9up;aKe 77ll62;m 2r 5M;ckBke Llk K;ov9shit,u47;aKba4do1in,leave,o4Dup;ba4ft9pa69w3;a0Vc0Te0Mh0Ii0Fl09m08n07o06p01quar5GtQuOwK;earMiK;ngLtch K;aw3ba4o8K; by;cKi6Bm 2ss0;k 64;aReQiPoNrKud35;aigh2Det75iK;ke 7Sng K;al6Yup;p Krm2F;by,in,oG;c3Ln3Lr 2tc4O;p F;c3Jmp0nd LrKveAy 2O;e Ht 2L;ba4do1up;ar3GeNiMlLrKurB;ead0ingBuc5;a49it 6H;c5ll o3Cn 2;ak Fe1Xll0;a3Bber 2rt0und like;ap 5Vow Duggl5;ash 6Noke0;eep NiKow 6;cLp K;o6Dup;e 68;in,oK;ff,v9;de19gn 4NnKt 6Gz5;gKkE; al6Ale0;aMoKu5W;ot Kut0w 7M;aw3ba4f48oC;c2WdeEk6EveA;e Pll1Nnd Orv5tK; Ktl5J;do1foLin,o7upK;!on;ot,r5Z;aw3ba4do1in,o33up;oCto;al66out0rK;ap65ew 6J;ilAv5;aXeUiSoOuK;b 5Yle0n Kstl5;aLba4do1inKo2Ith4Nu5P;!to;c2Xr8w3;ll Mot LpeAuK;g3Ind17;a2Wf3Po7;ar8in,o7up;ng 68p oKs5;ff,p18;aKelAinEnt0;c6Hd K;o4Dup;c27t0;aZeYiWlToQrOsyc35uK;ll Mn5Kt K;aKba4do1in,oJto47up;pa4Dw3;a3Jdo1in,o21to45up;attleBess KiNop 2;ah2Fon;iLp Kr4Zu1Gwer 6N;do1in,o6Nup;nt0;aLuK;gEmp 6;ce u20y 6D;ck Kg0le 4An 6p5B;oJup;el 5NncilE;c53ir 39n0ss MtLy K;ba4oG; Hc2R;aw3ba4in,oJ;pKw4Y;e4Xt D;aLerd0oK;dAt53;il Hrrow H;aTeQiPoLuK;ddl5ll I;c1FnkeyMp 6uthAve K;aKdo1in,o4Lup;l4Nw3; wi4K;ss0x 2;asur5e3SlLss K;a21up;t 6;ke Ln 6rKs2Ax0;k 6ryA;do,fun,oCsure,up;a02eViQoLuK;ck0st I;aNc4Fg MoKse0;k Kse4D;aft9ba4do1forw37in56o0Zu46;in,oJ;d 6;e NghtMnLsKve 00;ten F;e 2k 2; 2e46;ar8do1in;aMt LvelK; oC;do1go,in,o7up;nEve K;in,oK;pKut;en;c5p 2sh LtchBughAy K;do1o59;in4Po7;eMick Lnock K;do1oCup;oCup;eLy K;in,up;l Ip K;aw3ba4do1f04in,oJto,up;aMoLuK;ic5mpE;ke3St H;c43zz 2;a01eWiToPuK;nLrrKsh 6;y 2;keLt K;ar8do1;r H;lKneErse3K;d Ke 2;ba4dKfast,o0Cup;ear,o1;de Lt K;ba4on,up;aw3o7;aKlp0;d Ml Ir Kt 2;fKof;rom;f11in,o03uW;cPm 2nLsh0ve Kz2P;at,it,to;d Lg KkerP;do1in,o2Tup;do1in,oK;ut,v9;k 2;aZeTive Rloss IoMrLunK; f0S;ab hold,in43ow 2U; Kof 2I;aMb1Mit,oLr8th1IuK;nd9;ff,n,v9;bo7ft9hQw3;aw3bKdo1in,oJrise,up,w3;a4ir2H;ar 6ek0t K;aLb1Fdo1in,oKr8up;ff,n,ut,v9;cLhKl2Fr8t,w3;ead;ross;d aKng 2;bo7;a0Ee07iYlUoQrMuK;ck Ke2N;ar8up;eLighten KownBy 2;aw3oG;eKshe27; 2z5;g 2lMol Krk I;aKwi20;bo7r8;d 6low 2;aLeKip0;sh0;g 6ke0mKrKtten H;e F;gRlPnNrLsKzzle0;h F;e Km 2;aw3ba4up;d0isK;h 2;e Kl 1T;aw3fPin,o7;ht ba4ure0;ePnLsK;s 2;cMd K;fKoG;or;e D;d04l 2;cNll Krm0t1G;aLbKdo1in,o09sho0Eth08victim;a4ehi2O;pa0C;e K;do1oGup;at Kdge0nd 12y5;in,o7up;aOi1HoNrK;aLess 6op KuN;aw3b03in,oC;gBwB; Ile0ubl1B;m 2;a0Ah05l02oOrLut K;aw3ba4do1oCup;ackBeep LoKy0;ss Dwd0;by,do1in,o0Uup;me NoLuntK; o2A;k 6l K;do1oG;aRbQforOin,oNtKu0O;hLoKrue;geth9;rough;ff,ut,v9;th,wK;ard;a4y;paKr8w3;rt;eaLose K;in,oCup;n 6r F;aNeLiK;ll0pE;ck Der Kw F;on,up;t 2;lRncel0rOsMtch LveE; in;o1Nup;h Dt K;doubt,oG;ry LvK;e 08;aw3oJ;l Km H;aLba4do1oJup;ff,n,ut;r8w3;a0Ve0MiteAl0Fo04rQuK;bblNckl05il0Dlk 6ndl05rLsKtMy FzzA;t 00;n 0HsK;t D;e I;ov9;anWeaUiLush K;oGup;ghQng K;aNba4do1forMin,oLuK;nd9p;n,ut;th;bo7lKr8w3;ong;teK;n 2;k K;do1in,o7up;ch0;arTg 6iRn5oPrNssMttlLunce Kx D;aw3ba4;e 6; ar8;e H;do1;k Dt 2;e 2;l 6;do1up;d 2;aPeed0oKurt0;cMw K;aw3ba4do1o7up;ck;k K;in,oC;ck0nk0stA; oQaNef 2lt0nd K;do1ov9up;er;up;r Lt K;do1in,oCup;do1o7;ff,nK;to;ck Pil0nMrgLsK;h D;ainBe D;g DkB; on;in,o7;aw3do1in,oCup;ff,ut;ay;ct FdQir0sk MuctionA; oG;ff;ar8o7;ouK;nd; o7;d K;do1oKup;ff,n;wn;o7up;ut",
    ProperNoun:
      "true¦aIbDc8dalhousHe7f5gosford,h4iron maiden,kirby,landsdowne,m2nis,r1s0wembF;herwood,paldiB;iel,othwe1;cgi0ercedes,issy;ll;intBudsB;airview,lorence,ra0;mpt9nco;lmo,uro;a1h0;arlt6es5risti;rl0talina;et4i0;ng;arb3e0;et1nt0rke0;ley;on;ie;bid,jax",
    "Person|Place":
      "true¦a8d6h4jordan,k3orlando,s1vi0;ctor9rgin9;a0ydney;lvador,mara,ntia4;ent,obe;amil0ous0;ton;arw2ie0;go;lexandr1ust0;in;ia",
    LastName:
      "true¦0:BR;1:BF;2:B5;3:BH;4:AX;5:9Y;6:B6;7:BK;8:B0;9:AV;A:AL;B:8Q;C:8G;D:7K;E:BM;F:AH;aBDb9Zc8Wd88e81f7Kg6Wh64i60j5Lk4Vl4Dm39n2Wo2Op25quispe,r1Ls0Pt0Ev03wTxSyKzG;aIhGimmerm6A;aGou,u;ng,o;khar5ytsE;aKeun9BiHoGun;koya32shiBU;!lG;diGmaz;rim,z;maGng;da,g52mo83sGzaC;aChiBV;iao,u;aLeJiHoGright,u;jcA5lff,ng;lGmm0nkl0sniewsC;kiB1liams33s3;bGiss,lt0;b,er,st0;a6Vgn0lHtG;anabe,s3;k0sh,tG;e2Non;aLeKiHoGukD;gt,lk5roby5;dHllalGnogr3Kr1Css0val3S;ba,ob1W;al,ov4;lasHsel8W;lJn dIrgBEsHzG;qu7;ilyEqu7siljE;en b6Aijk,yk;enzueAIverde;aPeix1VhKi2j8ka43oJrIsui,uG;om5UrG;c2n0un1;an,emblA7ynisC;dorAMlst3Km4rrAth;atch0i8UoG;mHrG;are84laci79;ps3sG;en,on;hirDkah9Mnaka,te,varA;a06ch01eYhUiRmOoMtIuHvGzabo;en9Jobod3N;ar7bot4lliv2zuC;aIeHoG;i7Bj4AyanAB;ele,in2FpheBvens25;l8rm0;kol5lovy5re7Tsa,to,uG;ng,sa;iGy72;rn5tG;!h;l71mHnGrbu;at9cla9Egh;moBo7M;aIeGimizu;hu,vchG;en8Luk;la,r1G;gu9infe5YmGoh,pulveA7rra5P;jGyG;on5;evi6iltz,miHneid0roed0uGwarz;be3Elz;dHtG;!t,z;!t;ar4Th8ito,ka4OlJnGr4saCto,unde19v4;ch7dHtGz;a5Le,os;b53e16;as,ihDm4Po0Y;aVeSiPoJuHyG;a6oo,u;bio,iz,sG;so,u;bKc8Fdrigue67ge10j9YmJosevelt,sItHux,wG;e,li6;a9Ch;enb4Usi;a54e4L;erts15i93;bei4JcHes,vGzzo;as,e9;ci,hards12;ag2es,iHut0yG;es,nol5N;s,t0;dImHnGsmu97v6C;tan1;ir7os;ic,u;aUeOhMiJoHrGut8;asad,if6Zochazk27;lishc2GpGrti72u10we76;e3Aov51;cHe45nG;as,to;as70hl0;aGillips;k,m,n6I;a3Hde3Wete0Bna,rJtG;ersHrovGters54;!a,ic;!en,on;eGic,kiBss3;i9ra,tz,z;h86k,padopoulIrk0tHvG;ic,l4N;el,te39;os;bMconn2Ag2TlJnei6PrHsbor6XweBzG;dem7Rturk;ella4DtGwe6N;ega,iz;iGof7Hs8I;vGyn1R;ei9;aSri1;aPeNiJoGune50ym2;rHvGwak;ak4Qik5otn66;odahl,r4S;cholsZeHkolGls4Jx3;ic,ov84;ls1miG;!n1;ils3mG;co4Xec;gy,kaGray2sh,var38;jiGmu9shiG;ma;a07c04eZiWoMuHyeG;rs;lJnIrGssoli6S;atGp03r7C;i,ov4;oz,te58;d0l0;h2lOnNo0RrHsGza1A;er,s;aKeJiIoz5risHtG;e56on;!on;!n7K;au,i9no,t5J;!lA;r1Btgome59;i3El0;cracFhhail5kkeHlG;l0os64;ls1;hmeJiIj30lHn3Krci0ssiGyer2N;!er;n0Po;er,j0;dDti;cartHlG;aughl8e2;hy;dQe7Egnu68i0jer3TkPmNnMrItHyG;er,r;ei,ic,su21thews;iHkDquAroqu8tinG;ez,s;a5Xc,nG;!o;ci5Vn;a5UmG;ad5;ar5e6Kin1;rig77s1;aVeOiLoJuHyG;!nch;k4nGo;d,gu;mbarGpe3Fvr4we;di;!nGu,yana2B;coln,dG;b21holm,strom;bedEfeKhIitn0kaHn8rGw35;oy;!j;m11tG;in1on1;bvGvG;re;iGmmy,ng,rs2Qu,voie,ws3;ne,t1F;aZeYh2iWlUnez50oNrJuHvar2woG;k,n;cerGmar68znets5;a,o34;aHem0isGyeziu;h23t3O;m0sni4Fus3KvG;ch4O;bay57ch,rh0Usk16vaIwalGzl5;czGsC;yk;cIlG;!cGen4K;huk;!ev4ic,s;e8uiveG;rt;eff0kGl4mu9nnun1;ucF;ll0nnedy;hn,llKminsCne,pIrHstra3Qto,ur,yGzl5;a,s0;j0Rls22;l2oG;or;oe;aPenOha6im14oHuG;ng,r4;e32hInHrge32u6vG;anD;es,ss3;anHnsG;en,on,t3;nesGs1R;en,s1;kiBnings,s1;cJkob4EnGrv0E;kDsG;en,sG;en0Ion;ks3obs2A;brahimDglesi5Nke5Fl0Qno07oneIshikHto,vanoG;u,v54;awa;scu;aVeOiNjaltal8oIrist50uG;!aGb0ghAynh;m2ng;a6dz4fIjgaa3Hk,lHpUrGwe,x3X;ak1Gvat;mAt;er,fm3WmG;ann;ggiBtchcock;iJmingw4BnHrGss;nand7re9;deGriks1;rs3;kkiHnG;on1;la,n1;dz4g1lvoQmOns0ZqNrMsJuIwHyG;asFes;kiB;g1ng;anHhiG;mo14;i,ov0J;di6p0r10t;ue;alaG;in1;rs1;aVeorgUheorghe,iSjonRoLrJuGw3;errGnnar3Co,staf3Ctierr7zm2;a,eG;ro;ayli6ee2Lg4iffithGub0;!s;lIme0UnHodGrbachE;e,m2;calvAzale0S;dGubE;bGs0E;erg;aj,i;bs3l,mGordaO;en7;iev3U;gnMlJmaIndFo,rGsFuthi0;cGdn0za;ia;ge;eaHlG;agh0i,o;no;e,on;aVerQiLjeldsted,lKoIrHuG;chs,entAji41ll0;eem2iedm2;ntaGrt8urni0wl0;na;emi6orA;lipIsHtzgeraG;ld;ch0h0;ovG;!ic;hatDnanIrG;arGei9;a,i;deY;ov4;b0rre1D;dKinsJriksIsGvaB;cob3GpGtra3D;inoza,osiQ;en,s3;te8;er,is3warG;ds;aXePiNjurhuMoKrisco15uHvorakG;!oT;arte,boHmitru,nn,rGt3C;and,ic;is;g2he0Omingu7nErd1ItG;to;us;aGcki2Hmitr2Ossanayake,x3;s,z; JbnaIlHmirGrvisFvi,w2;!ov4;gado,ic;th;bo0groot,jo6lHsilGvriA;va;a cruz,e3uG;ca;hl,mcevsCnIt2WviG;dGes,s;ov,s3;ielsGku22;!en;ki;a0Be06hRiobQlarkPoIrGunningh1H;awfo0RivGuz;elli;h1lKntJoIrGs2Nx;byn,reG;a,ia;ke,p0;i,rer2K;em2liB;ns;!e;anu;aOeMiu,oIristGu6we;eGiaG;ns1;i,ng,p9uHwGy;!dH;dGng;huJ;!n,onGu6;!g;kJnIpm2ttHudhGv7;ry;erjee,o14;!d,g;ma,raboG;rty;bJl0Cng4rG;eghetHnG;a,y;ti;an,ota1C;cerAlder3mpbeLrIstGvadi0B;iGro;llo;doHl0Er,t0uGvalho;so;so,zo;ll;a0Fe01hYiXlUoNrKuIyG;rLtyG;qi;chan2rG;ke,ns;ank5iem,oGyant;oks,wG;ne;gdan5nIruya,su,uchaHyKziG;c,n5;rd;darGik;enG;ko;ov;aGond15;nco,zG;ev4;ancFshw16;a08oGuiy2;umGwmG;ik;ckRethov1gu,ktPnNrG;gJisInG;ascoGds1;ni;ha;er,mG;anG;!n;gtGit7nP;ss3;asF;hi;er,hG;am;b4ch,ez,hRiley,kk0ldw8nMrIshHtAu0;es;ir;bInHtlGua;ett;es,i0;ieYosa;dGik;a9yoG;padhyG;ay;ra;k,ng;ic;bb0Acos09d07g04kht05lZnPrLsl2tJyG;aHd8;in;la;chis3kiG;ns3;aImstro6sl2;an;ng;ujo,ya;dJgelHsaG;ri;ovG;!a;ersJov,reG;aGjEws;ss1;en;en,on,s3;on;eksejEiyEmeiIvG;ar7es;ez;da;ev;arwHuilG;ar;al;ams,l0;er;ta;as",
    Ordinal:
      "true¦eBf7nin5s3t0zeroE;enDhir1we0;lfCn7;d,t3;e0ixt8;cond,vent7;et0th;e6ie7;i2o0;r0urt3;tie4;ft1rst;ight0lev1;e0h,ie1;en0;th",
    Cardinal:
      "true¦bEeBf5mEnine7one,s4t0zero;en,h2rDw0;e0o;lve,n5;irt6ousands,ree;even2ix2;i3o0;r1ur0;!t2;ty;ft0ve;e2y;ight0lev1;!e0y;en;illions",
    Multiple: "true¦b3hundred,m3qu2se1t0;housand,r2;pt1xt1;adr0int0;illion",
    City: "true¦0:74;1:61;2:6G;3:6J;4:5S;a68b53c4Id48e44f3Wg3Hh39i31j2Wk2Fl23m1Mn1Co19p0Wq0Ur0Os05tRuQvLwDxiBy9z5;a7h5i4Muri4O;a5e5ongsh0;ng3H;greb,nzib5G;ang2e5okoha3Sunfu;katerin3Hrev0;a5n0Q;m5Hn;arsBeAi6roclBu5;h0xi,zh5P;c7n5;d5nipeg,terth4;hoek,s1L;hi5Zkl3A;l63xford;aw;a8e6i5ladivost5Molgogr6L;en3lni6S;ni22r5;o3saill4N;lenc4Wncouv3Sr3ughn;lan bat1Crumqi,trecht;aFbilisi,eEheDiBo9r7u5;l21n63r5;in,ku;i5ondh62;es51poli;kyo,m2Zron1Pulo5;n,uS;an5jua3l2Tmisoa6Bra3;j4Tshui; hag62ssaloni2H;gucigal26hr0l av1U;briz,i6llinn,mpe56ng5rtu,shk2R;i3Esh0;an,chu1n0p2Eyu0;aEeDh8kopje,owe1Gt7u5;ra5zh4X;ba0Ht;aten is55ockholm,rasbou67uttga2V;an8e6i5;jiazhua1llo1m5Xy0;f50n5;ya1zh4H;gh3Kt4Q;att45o1Vv44;cramen16int ClBn5o paulo,ppo3Rrajevo; 7aa,t5;a 5o domin3E;a3fe,m1M;antonio,die3Cfrancisco,j5ped3Nsalvad0J;o5u0;se;em,t lake ci5Fz25;lou58peters24;a9e8i6o5;me,t59;ga,o5yadh;! de janei3F;cife,ims,nn3Jykjavik;b4Sip4lei2Inc2Pwalpindi;ingdao,u5;ez2i0Q;aFeEhDiCo9r7u6yong5;ya1;eb59ya1;a5etor3M;g52to;rt5zn0; 5la4Co;au prin0Melizabe24sa03;ls3Prae5Atts26;iladelph3Gnom pe1Aoenix;ki1tah tik3E;dua,lerYnaji,r4Ot5;na,r32;ak44des0Km1Mr6s5ttawa;a3Vlo;an,d06;a7ew5ing2Fovosibir1Jyc; 5cast36;del24orlea44taip14;g8iro4Wn5pl2Wshv33v0;ch6ji1t5;es,o1;a1o1;a6o5p4;ya;no,sa0W;aEeCi9o6u5;mb2Ani26sc3Y;gadishu,nt6s5;c13ul;evideo,pelli1Rre2Z;ami,l6n14s5;kolc,sissauga;an,waukee;cca,d5lbour2Mmph41ndo1Cssi3;an,ell2Xi3;cau,drAkass2Sl9n8r5shh4A;aca6ib5rakesh,se2L;or;i1Sy;a4EchFdal0Zi47;mo;id;aDeAi8o6u5vSy2;anMckn0Odhia3;n5s angel26;d2g bea1N;brev2Be3Lma5nz,sb2verpo28;!ss27; ma39i5;c5pzig;est16; p6g5ho2Wn0Cusan24;os;az,la33;aHharFiClaipeBo9rak0Du7y5;iv,o5;to;ala lump4n5;mi1sh0;hi0Hlka2Xpavog4si5wlo2;ce;da;ev,n5rkuk;gst2sha5;sa;k5toum;iv;bHdu3llakuric0Qmpa3Fn6ohsiu1ra5un1Iwaguc0Q;c0Pj;d5o,p4;ah1Ty;a7e6i5ohannesV;l1Vn0;dd36rusalem;ip4k5;ar2H;bad0mph1OnArkutUs7taXz5;mir,tapala5;pa;fah0l6tanb5;ul;am2Zi2H;che2d5;ianap2Mo20;aAe7o5yder2W; chi mi5ms,nolulu;nh;f6lsin5rakli2;ki;ei;ifa,lifax,mCn5rb1Dva3;g8nov01oi;aFdanEenDhCiPlasgBo9raz,u5;a5jr23;dal6ng5yaquil;zh1J;aja2Oupe;ld coa1Bthen5;bu2S;ow;ent;e0Uoa;sk;lw7n5za;dhi5gt1E;nag0U;ay;aisal29es,o8r6ukuya5;ma;ankfu5esno;rt;rt5sh0; wor6ale5;za;th;d5indhov0Pl paso;in5mont2;bur5;gh;aBe8ha0Xisp4o7resd0Lu5;b5esseldorf,nkirk,rb0shanbe;ai,l0I;ha,nggu0rtmu13;hradSl6nv5troit;er;hi;donghIe6k09l5masc1Zr es sala1KugavpiY;i0lU;gu,je2;aJebu,hAleve0Vo5raio02uriti1Q;lo7n6penhag0Ar5;do1Ok;akKst0V;gUm5;bo;aBen8i6ongqi1ristchur5;ch;ang m7ca5ttago1;go;g6n5;ai;du,zho1;ng5ttogr14;ch8sha,zh07;gliari,i9lga8mayenJn6pe town,r5tanO;acCdiff;ber1Ac5;un;ry;ro;aWeNhKirmingh0WoJr9u5;chareTdapeTenos air7r5s0tu0;g5sa;as;es;a9is6usse5;ls;ba6t5;ol;ne;sil8tisla7zzav5;il5;le;va;ia;goZst2;op6ubaneshw5;ar;al;iCl9ng8r5;g6l5n;in;en;aluru,hazi;fa6grade,o horizon5;te;st;ji1rut;ghd0BkFn9ot8r7s6yan n4;ur;el,r07;celo3i,ranquil09;ou;du1g6ja lu5;ka;alo6k5;ok;re;ng;ers5u;field;a05b02cc01ddis aba00gartaZhmedXizawl,lSmPnHqa00rEsBt7uck5;la5;nd;he7l5;an5;ta;ns;h5unci2;dod,gab5;at;li5;ngt2;on;a8c5kaOtwerp;hora6o3;na;ge;h7p5;ol5;is;eim;aravati,m0s5;terd5;am; 7buquerq6eppo,giers,ma5;ty;ue;basrah al qadim5mawsil al jadid5;ah;ab5;ad;la;ba;ra;idj0u dha5;bi;an;lbo6rh5;us;rg",
    Region:
      "true¦0:2O;1:2L;2:2U;3:2F;a2Sb2Fc21d1Wes1Vf1Tg1Oh1Ki1Fj1Bk16l13m0Sn09o07pYqVrSsJtEuBverAw6y4zacatec2W;akut0o0Fu4;cat1k09;a5est 4isconsin,yomi1O;bengal,virgin0;rwick3shington4;! dc;acruz,mont;dmurt0t4;ah,tar4; 2Pa12;a6e5laxca1Vripu21u4;scaEva;langa2nnessee,x2J;bas10m4smQtar29;aulip2Hil nadu;a9elang07i7o5taf16u4ylh1J;ff02rr09s1E;me1Gno1Uuth 4;cZdY;ber0c4kkim,naloa;hu1ily;n5rawak,skatchew1xo4;ny; luis potosi,ta catari2;a4hodeA;j4ngp0C;asth1shahi;ingh29u4;e4intana roo;bec,en6retaro;aAe6rince edward4unjab; i4;sl0G;i,n5r4;ak,nambu0F;a0Rnsylv4;an0;ha0Pra4;!na;axa0Zdisha,h4klaho21ntar4reg7ss0Dx0I;io;aLeEo6u4;evo le4nav0X;on;r4tt18va scot0;f9mandy,th4; 4ampton3;c6d5yo4;rk3;ako1O;aroli2;olk;bras1Nva0Dw4; 6foundland4;! and labrad4;or;brunswick,hamp3jers5mexiTyork4;! state;ey;galPyarit;aAeghala0Mi6o4;nta2r4;dov0elos;ch6dlanDn5ss4zor11;issippi,ouri;as geraPneso18;ig1oac1;dhy12harasht0Gine,lac07ni5r4ssachusetts;anhao,i el,ylG;p4toba;ur;anca3e4incoln3ouisI;e4iR;ds;a6e5h4omi;aka06ul2;dah,lant1ntucky,ra01;bardino,lmyk0ns0Qr4;achay,el0nata0X;alis6har4iangxi;kh4;and;co;daho,llino7n4owa;d5gush4;et0;ia2;is;a6ert5i4un1;dalFm0D;ford3;mp3rya2waii;ansu,eorg0lou7oa,u4;an4izhou,jarat;ajuato,gdo4;ng;cester3;lori4uji1;da;sex;ageUe7o5uran4;go;rs4;et;lawaMrby3;aFeaEh9o4rim08umbr0;ahui7l6nnectic5rsi4ventry;ca;ut;i03orado;la;e5hattisgarh,i4uvash0;apRhuahua;chn5rke4;ss0;ya;ra;lGm4;bridge3peche;a9ihar,r8u4;ck4ryat0;ingham3;shi4;re;emen,itish columb0;h0ja cal8lk7s4v7;hkorto4que;st1;an;ar0;iforn0;ia;dygHguascalientes,lBndhr9r5ss4;am;izo2kans5un4;achal 7;as;na;a 4;pradesh;a6ber5t4;ai;ta;ba5s4;ka;ma;ea",
    Place:
      "true¦0:4T;1:4V;2:44;3:4B;4:3I;a4Eb3Gc2Td2Ge26f25g1Vh1Ji1Fk1Cl14m0Vn0No0Jp08r04sTtNuLvJw7y5;a5o0Syz;kut1Bngtze;aDeChitBi9o5upatki,ycom2P;ki26o5;d5l1B;b3Ps5;i4to3Y;c0SllowbroCn5;c2Qgh2;by,chur1P;ed0ntw3Gs22;ke6r3St5;erf1f1; is0Gf3V;auxha3Mirgin is0Jost5;ok;laanbaatar,pto5xb3E;n,wn;a9eotihuac43h7ive49o6ru2Nsarskoe selo,u5;l2Dzigo47;nto,rquay,tt2J;am3e 5orn3E;bronx,hamptons;hiti,j mah0Iu1N;aEcotts bluff,eCfo,herbroQoApring9t7u5yd2F;dbu1Wn5;der03set3B;aff1ock2Nr5;atf1oud;hi37w24;ho,uth5; 1Iam1Zwo3E;a5i2O;f2Tt0;int lawrence riv3Pkhal2D;ayleigh,ed7i5oc1Z;chmo1Eo gran4ver5;be1Dfr09si4; s39cliffe,hi2Y;aCe9h8i5ompeii,utn2;c6ne5tcai2T; 2Pc0G;keri13t0;l,x;k,lh2mbr6n5r2J;n1Hzance;oke;cif38pahanaumokuak30r5;k5then0;si4w1K;ak7r6x5;f1l2X;ange county,d,f1inoco;mTw1G;e8i1Uo5;r5tt2N;th5wi0E; 0Sam19;uschwanste1Pw5; eng6a5h2market,po36;rk;la0P;a8co,e6i5uc;dt1Yll0Z;adow5ko0H;lands;chu picchu,gad2Ridsto1Ql8n7ple6r5;kh2; g1Cw11;hatt2Osf2B;ibu,t0ve1Z;a8e7gw,hr,in5owlOynd02;coln memori5dl2C;al;asi4w3;kefr7mbe1On5s,x;ca2Ig5si05;f1l27t0;ont;azan kreml14e6itchen2Gosrae,rasnoyar5ul;sk;ns0Hs1U;ax,cn,lf1n6ps5st;wiN;d5glew0Lverness;ian27ochina;aDeBi6kg,nd,ov5unti2H;d,enweep;gh6llc5;reL;bu03l5;and5;!s;r5yw0C;ef1tf1;libu24mp6r5stings;f1lem,row;stead,t0;aDodavari,r5uelph;avenAe5imsS;at 8en5; 6f1Fwi5;ch;acr3vall1H;brita0Flak3;hur5;st;ng3y villa0W;airhavHco,ra;aAgli9nf17ppi8u7ver6x5;et1Lf1;glad3t0;rope,st0;ng;nt0;rls1Ls5;t 5;e5si4;nd;aCe9fw,ig8o7ryd6u5xb;mfri3nstab00rh2tt0;en;nca18rcKv19wnt0B;by;n6r5vonpo1D;ry;!h2;nu8r5;l6t5;f1moor;ingt0;be;aLdg,eIgk,hClBo5royd0;l6m5rnwa0B;pt0;c7lingw6osse5;um;ood;he0S;earwat0St;a8el6i5uuk;chen itza,mney ro07natSricahua;m0Zt5;enh2;mor5rlottetPth2;ro;dar 5ntervilA;breaks,faZg5;rove;ld9m8r5versh2;lis6rizo pla5;in;le;bLpbellf1;weQ;aZcn,eNingl01kk,lackLolt0r5uckV;aGiAo5;ckt0ok5wns cany0;lyn,s5;i4to5;ne;de;dge6gh5;am,t0;n6t5;own;or5;th;ceb6m5;lNpt0;rid5;ge;bu5pool,wa8;rn;aconsfEdf1lBr9verly7x5;hi5;ll; hi5;lls;wi5;ck; air,l5;ingh2;am;ie5;ld;ltimore,rnsl6tters5;ea;ey;bLct0driadic,frica,ginJlGmFn9rc8s7tl6yleOzor3;es;!ant8;hcroft,ia; de triomphe,t6;adyr,ca8dov9tarct5;ic5; oce5;an;st5;er;ericas,s;be6dersh5hambra,list0;ot;rt0;cou5;rt;bot7i5;ngd0;on;sf1;ord",
    Country:
      "true¦0:38;1:2L;2:3B;a2Xb2Ec22d1Ye1Sf1Mg1Ch1Ai14j12k0Zl0Um0Gn05om2pZqat1KrXsKtCu7v5wal4yemTz3;a25imbabwe;es,lis and futu2Y;a3enezue32ietnam;nuatu,tican city;gTk6nited 4ruXs3zbeE; 2Ca,sr;arab emirat0Kkingdom,states3;! of am2Y;!raiV;a8haCimor les0Co7rinidad 5u3;nis0rk3valu;ey,me2Zs and caic1V;and t3t3;oba1L;go,kel10nga;iw2ji3nz2T;ki2V;aDcotl1eCi9lov8o6pa2Dri lanka,u5w3yr0;az3edAitzerl1;il1;d2riname;lomon1Xmal0uth 3;afr2KkMsud2;ak0en0;erra leoFn3;gapo1Yt maart3;en;negLrb0ychellZ;int 3moa,n marino,udi arab0;hele26luc0mart21;epublic of ir0Eom2Euss0w3;an27;a4eIhilippinUitcairn1Mo3uerto riN;l1rtugF;ki2Dl4nama,pua new0Vra3;gu7;au,esti3;ne;aBe9i7or3;folk1Ith4w3;ay; k3ern mariana1D;or0O;caragua,ger3ue;!ia;p3ther1Aw zeal1;al;mib0u3;ru;a7exi6icro0Bo3yanm06;ldova,n3roc5zambA;a4gol0t3;enegro,serrat;co;cAdagasc01l7r5urit4yot3;te;an0i16;shall0Xtin3;ique;a4div3i,ta;es;wi,ys0;ao,ed02;a6e5i3uxembourg;b3echtenste12thu1G;er0ya;ban0Isotho;os,tv0;azakh1Fe4iriba04o3uwait,yrgyz1F;rXsovo;eling0Knya;a3erG;ma16p2;c7nd6r4s3taly,vory coast;le of m2rael;a3el1;n,q;ia,oJ;el1;aiTon3ungary;dur0Ng kong;aBermany,ha0QibraltAre8u3;a6ern5inea3ya0P;! biss3;au;sey;deloupe,m,tema0Q;e3na0N;ce,nl1;ar;bUmb0;a7i6r3;ance,ench 3;guia0Epoly3;nes0;ji,nl1;lklandUroeU;ast tim7cu6gypt,l salv6ngl1quatorial4ritr5st3thiop0;on0; guin3;ea;ad3;or;enmark,jibou5ominica4r con3;go;!n C;ti;aBentral african Ah8o5roat0u4yprRzech3; 9ia;ba,racao;c4lo3morQngo brazzaville,okGsta r04te de ivoiL;mb0;osE;i3ristmasG;le,na;republic;m3naUpe verde,ymanA;bod0ero3;on;aGeDhut2o9r5u3;lgar0r3;kina faso,ma,undi;azil,itish 3unei;virgin3; is3;lands;liv0nai5snia and herzegoviHtswaHuvet3; isl1;and;re;l3n8rmuG;ar3gium,ize;us;h4ngladesh,rbad3;os;am4ra3;in;as;fghaGlDmBn6r4ustr3zerbaij2;al0ia;genti3men0uba;na;dorra,g5t3;arct7igua and barbu3;da;o3uil3;la;er3;ica;b3ger0;an0;ia;ni3;st2;an",
    FirstName:
      "true¦aTblair,cQdOfrancoZgabMhinaLilya,jHkClBm6ni4quinn,re3s0;h0umit,yd;ay,e0iloh;a,lby;g9ne;co,ko0;!s;a1el0ina,org6;!okuhF;ds,naia,r1tt0xiB;i,y;ion,lo;ashawn,eif,uca;a3e1ir0rM;an;lsFn0rry;dall,yat5;i,sD;a0essIie,ude;i1m0;ie,mG;me;ta;rie0y;le;arcy,ev0;an,on;as1h0;arl8eyenne;ey,sidy;drien,kira,l4nd1ubr0vi;ey;i,r0;a,e0;a,y;ex2f1o0;is;ie;ei,is",
    WeekDay: "true¦fri2mon2s1t0wednesd3;hurs1ues1;aturd1und1;!d0;ay0;!s",
    Month: "true¦dec0february,july,nov0octo1sept0;em0;ber",
    Date: "true¦ago,on4som4t1week0yesterd5; end,ends;mr1o0;d2morrow;!w;ed0;ay",
    Duration:
      "true¦centurAd8h7m5q4se3w1y0;ear8r8;eek0k7;!end,s;ason,c5;tr,uarter;i0onth3;llisecond2nute2;our1r1;ay0ecade0;!s;ies,y",
    FemaleName:
      "true¦0:J7;1:JB;2:IJ;3:IK;4:J1;5:IO;6:JS;7:JO;8:HB;9:JK;A:H4;B:I2;C:IT;D:JH;E:IX;F:BA;G:I4;aGTbFLcDRdD0eBMfB4gADh9Ti9Gj8Dk7Cl5Wm48n3Lo3Hp33qu32r29s15t0Eu0Cv02wVxiTyOzH;aLeIineb,oHsof3;e3Sf3la,ra;h2iKlIna,ynH;ab,ep;da,ma;da,h2iHra;nab;aKeJi0FolB7uIvH;et8onDP;i0na;le0sen3;el,gm3Hn,rGLs8W;aoHme0nyi;m5XyAD;aMendDZhiDGiH;dele9lJnH;if48niHo0;e,f47;a,helmi0lHma;a,ow;ka0nB;aNeKiHusa5;ck84kIl8oleAviH;anFenJ4;ky,toriBK;da,lA8rHs0;a,nHoniH9;a,iFR;leHnesH9;nILrH;i1y;g9rHs6xHA;su5te;aYeUhRiNoLrIuHy2;i,la;acJ3iHu0J;c3na,sH;hFta;nHr0F;iFya;aJffaEOnHs6;a,gtiH;ng;!nFSra;aIeHomasi0;a,l9Oo8Ares1;l3ndolwethu;g9Fo88rIssH;!a,ie;eHi,ri7;sa,za;bOlMmKnIrHs6tia0wa0;a60yn;iHya;a,ka,s6;arFe2iHm77ra;!ka;a,iH;a,t6;at6it6;a0Ecarlett,e0AhWiSkye,neza0oQri,tNuIyH;bIGlvi1;ha,mayIJniAsIzH;an3Net8ie,y;anHi7;!a,e,nH;aCe;aIeH;fan4l5Dphan6E;cI5r5;b3fiAAm0LnHphi1;d2ia,ja,ya;er2lJmon1nIobh8QtH;a,i;dy;lETv3;aMeIirHo0risFDy5;a,lDM;ba,e0i5lJrH;iHr6Jyl;!d8Ifa;ia,lDZ;hd,iMki2nJrIu0w0yH;la,ma,na;i,le9on,ron,yn;aIda,ia,nHon;a,on;!ya;k6mH;!aa;lJrItaye82vH;da,inj;e0ife;en1i0ma;anA9bLd5Oh1SiBkKlJmInd2rHs6vannaC;aCi0;ant6i2;lDOma,ome;ee0in8Tu2;in1ri0;a05eZhXiUoHuthDM;bScRghQl8LnPsJwIxH;anB3ie,y;an,e0;aIeHie,lD;ann7ll1marDGtA;!lHnn1;iHyn;e,nH;a,dF;da,i,na;ayy8G;hel67io;bDRerAyn;a,cIkHmas,nFta,ya;ki,o;h8Xki;ea,iannGMoH;da,n1P;an0bJemFgi0iInHta,y0;a8Bee;han86na;a,eH;cHkaC;a,ca;bi0chIe,i0mo0nHquETy0;di,ia;aERelHiB;!e,le;een4ia0;aPeOhMiLoJrHute6A;iHudenCV;scil3LyamvaB;lHrt3;i0ly;a,paluk;ilome0oebe,ylH;is,lis;ggy,nelope,r5t2;ige,m0VnKo5rvaDMtIulH;a,et8in1;ricHt4T;a,e,ia;do2i07;ctav3dIfD3is6ksa0lHphD3umC5yunbileg;a,ga,iv3;eHvAF;l3t8;aWeUiMoIurHy5;!ay,ul;a,eJor,rIuH;f,r;aCeEma;ll1mi;aNcLhariBQkKlaJna,sHta,vi;anHha;ur;!y;a,iDZki;hoGk9YolH;a,e4P;!mh;hir,lHna,risDEsreE;!a,lBV;asuMdLh3i6Dl5nKomi7rgEVtH;aHhal4;lHs6;i1ya;cy,et8;e9iF0ya;nngu2X;a0Ackenz4e02iMoJrignayani,uriDJyH;a,rH;a,iOlNna,tG;bi0i2llBJnH;a,iH;ca,ka,qD9;a,cUdo4ZkaTlOmi,nMrItzi,yH;ar;aJiIlH;anET;am;!l,nB;dy,eHh,n4;nhGrva;aKdJe0iCUlH;iHy;cent,e;red;!gros;!e5;ae5hH;ae5el3Z;ag5DgNi,lKrH;edi7AiIjem,on,yH;em,l;em,sCG;an4iHliCF;nHsCJ;a,da;!an,han;b09cASd07e,g05ha,i04ja,l02n00rLsoum5YtKuIv84xBKyHz4;bell,ra,soBB;d7rH;a,eE;h8Gild1t4;a,cUgQiKjor4l7Un4s6tJwa,yH;!aHbe6Xja9lAE;m,nBL;a,ha,in1;!aJbCGeIja,lDna,sHt63;!a,ol,sa;!l1D;!h,mInH;!a,e,n1;!awit,i;arJeIie,oHr48ueri8;!t;!ry;et46i3B;el4Xi7Cy;dHon,ue5;akranAy;ak,en,iHlo3S;a,ka,nB;a,re,s4te;daHg4;!l3E;alDd4elHge,isDJon0;ei9in1yn;el,le;a0Ne0CiXoQuLyH;d3la,nH;!a,dIe2OnHsCT;!a,e2N;a,sCR;aD4cJel0Pis1lIna,pHz;e,iA;a,u,wa;iHy;a0Se,ja,l2NnB;is,l1UrItt1LuHvel4;el5is1;aKeIi7na,rH;aADi7;lHn1tA;ei;!in1;aTbb9HdSepa,lNnKsJvIzH;!a,be5Ret8z4;!ia;a,et8;!a,dH;a,sHy;ay,ey,i,y;a,iJja,lH;iHy;aA8e;!aH;!nF;ia,ya;!nH;!a,ne;aPda,e0iNjYla,nMoKsJtHx93y5;iHt4;c3t3;e2PlCO;la,nHra;a,ie,o2;a,or1;a,gh,laH;!ni;!h,nH;a,d2e,n5V;cOdon9DiNkes6mi9Gna,rMtJurIvHxmi,y5;ern1in3;a,e5Aie,yn;as6iIoH;nya,ya;fa,s6;a,isA9;a,la;ey,ie,y;a04eZhXiOlASoNrJyH;lHra;a,ee,ie;istHy6I;a,en,iIyH;!na;!e,n5F;nul,ri,urtnB8;aOerNlB7mJrHzzy;a,stH;en,in;!berlImernH;aq;eHi,y;e,y;a,stE;!na,ra;aHei2ongordzol;dij1w5;el7UiKjsi,lJnIrH;a,i,ri;d2na,za;ey,i,lBLs4y;ra,s6;biAcARdiat7MeBAiSlQmPnyakuma1DrNss6NtKviAyH;!e,lH;a,eH;e,i8T;!a6HeIhHi4TlDri0y;ar8Her8Hie,leErBAy;!lyn8Ori0;a,en,iHl5Xoli0yn;!ma,nFs95;a5il1;ei8Mi,lH;e,ie;a,tl6O;a0AeZiWoOuH;anMdLlHst88;es,iH;a8NeHs8X;!n9tH;!a,te;e5Mi3My;a,iA;!anNcelDdMelGhan7VleLni,sIva0yH;a,ce;eHie;fHlDph7Y;a,in1;en,n1;i7y;!a,e,n45;lHng;!i1DlH;!i1C;anNle0nKrJsH;i8JsH;!e,i8I;i,ri;!a,elGif2CnH;a,et8iHy;!e,f2A;a,eJiInH;a,eIiH;e,n1;!t8;cMda,mi,nIque4YsminFvie2y9zH;min7;a7eIiH;ce,e,n1s;!lHs82t0F;e,le;inIk6HlDquelH;in1yn;da,ta;da,lRmPnOo0rNsIvaHwo0zaro;!a0lu,na;aJiIlaHob89;!n9R;do2;belHdo2;!a,e,l3B;a7Ben1i0ma;di2es,gr72ji;a9elBogH;en1;a,e9iHo0se;a0na;aSeOiJoHus7Kyacin2C;da,ll4rten24snH;a,i9U;lImaH;ri;aIdHlaI;a,egard;ry;ath1BiJlInrietArmi9sH;sa,t1A;en2Uga,mi;di;bi2Fil8MlNnMrJsItHwa,yl8M;i5Tt4;n60ti;iHmo51ri53;etH;!te;aCnaC;a,ey,l4;a02eWiRlPoNrKunJwH;enHyne1R;!dolD;ay,el;acieIetHiselB;a,chE;!la;ld1CogooH;sh;adys,enHor3yn2K;a,da,na;aKgi,lIna,ov8EselHta;a,e,le;da,liH;an;!n0;mLnJorgIrH;ald5Si,m3Etrud7;et8i4X;a,eHna;s29vieve;ma;bIle,mHrnet,yG;al5Si5;iIrielH;a,l1;!ja;aTeQiPlorOoz3rH;anJeIiH;da,eB;da,ja;!cH;esIiHoi0P;n1s66;!ca;a,enc3;en,o0;lIn0rnH;anB;ec3ic3;jr,nArKtHy7;emIiHma,oumaA;ha,ma,n;eh;ah,iBrah,za0;cr4Rd0Re0Qi0Pk0Ol07mXn54rUsOtNuMvHwa;aKelIiH;!e,ta;inFyn;!a;!ngel4V;geni1ni47;h5Yien9ta;mLperanKtH;eIhHrel5;er;l31r7;za;a,eralB;iHma,ne4Lyn;cHka,n;a,ka;aPeNiKmH;aHe21ie,y;!li9nuH;elG;lHn1;e7iHy;a,e,ja;lHrald;da,y;!nue5;aWeUiNlMma,no2oKsJvH;a,iH;na,ra;a,ie;iHuiH;se;a,en,ie,y;a0c3da,e,f,nMsJzaH;!betHveA;e,h;aHe,ka;!beH;th;!a,or;anor,nH;!a,i;!in1na;ate1Rta;leEs6;vi;eIiHna,wi0;e,th;l,n;aYeMh3iLjeneKoH;lor5Vminiq4Ln3FrHtt4;a,eEis,la,othHthy;ea,y;ba;an09naCon9ya;anQbPde,eOiMlJmetr3nHsir5M;a,iH;ce,se;a,iIla,orHphi9;es,is;a,l6F;dHrdH;re;!d5Ena;!b2ForaCraC;a,d2nH;!a,e;hl3i0l0GmNnLphn1rIvi1WyH;le,na;a,by,cIia,lH;a,en1;ey,ie;a,et8iH;!ca,el1Aka,z;arHia;is;a0Re0Nh04i02lUoJristIynH;di,th3;al,i0;lPnMrIurH;tn1D;aJd2OiHn2Ori9;!nH;a,e,n1;!l4;cepci5Cn4sH;tanHuelo;ce,za;eHleE;en,t8;aJeoIotH;il54;!pat2;ir7rJudH;et8iH;a,ne;a,e,iH;ce,sZ;a2er2ndH;i,y;aReNloe,rH;isJyH;stH;al;sy,tH;a1Sen,iHy;an1e,n1;deJlseIrH;!i7yl;a,y;li9;nMrH;isKlImH;ai9;a,eHot8;n1t8;!sa;d2elGtH;al,elG;cIlH;es8i47;el3ilH;e,ia,y;itlYlXmilWndVrMsKtHy5;aIeIhHri0;er1IleErDy;ri0;a38sH;a37ie;a,iOlLmeJolIrH;ie,ol;!e,in1yn;lHn;!a,la;a,eIie,otHy;a,ta;ne,y;na,s1X;a0Ii0I;a,e,l1;isAl4;in,yn;a0Ke02iZlXoUrH;andi7eRiJoIyH;an0nn;nwDoke;an3HdgMgiLtH;n31tH;!aInH;ey,i,y;ny;d,t8;etH;!t7;an0e,nH;da,na;bbi7glarIlo07nH;iAn4;ka;ancHythe;a,he;an1Clja0nHsm3M;iAtH;ou;aWcVlinUniArPssOtJulaCvH;!erlH;ey,y;hJsy,tH;e,iHy7;e,na;!anH;ie,y;!ie;nItHyl;ha,ie;adIiH;ce;et8i9;ay,da;ca,ky;!triH;ce,z;rbJyaH;rmH;aa;a2o2ra;a2Ub2Od25g21i1Sj5l18m0Zn0Boi,r06sWtVuPvOwa,yIzH;ra,u0;aKes6gJlIn,seH;!l;in;un;!nH;a,na;a,i2K;drLguJrIsteH;ja;el3;stH;in1;a,ey,i,y;aahua,he0;hIi2Gja,miAs2DtrH;id;aMlIraqHt21;at;eIi7yH;!n;e,iHy;gh;!nH;ti;iJleIo6piA;ta;en,n1t8;aHelG;!n1J;a01dje5eZgViTjRnKohito,toHya;inet8nH;el5ia;te;!aKeIiHmJ;e,ka;!mHtt7;ar4;!belIliHmU;sa;!l1;a,eliH;ca;ka,sHta;a,sa;elHie;a,iH;a,ca,n1qH;ue;!tH;a,te;!bImHstasiMya;ar3;el;aLberKeliJiHy;e,l3naH;!ta;a,ja;!ly;hGiIl3nB;da;a,ra;le;aWba,ePiMlKthJyH;a,c3sH;a,on,sa;ea;iHys0N;e,s0M;a,cIn1sHza;a,e,ha,on,sa;e,ia,ja;c3is6jaKksaKna,sJxH;aHia;!nd2;ia,saH;nd2;ra;ia;i0nIyH;ah,na;a,is,naCoud;la;c6da,leEmNnLsH;haClH;inHyY;g,n;!h;a,o,slH;ey;ee;en;at6g4nIusH;ti0;es;ie;aWdiTelMrH;eJiH;anMenH;a,e,ne;an0;na;!aLeKiIyH;nn;a,n1;a,e;!ne;!iH;de;e,lDsH;on;yn;!lH;i9yn;ne;aKbIiHrL;!e,gaK;ey,i7y;!e;gaH;il;dKliyJradhIs6;ha;ya;ah;a,ya",
    Honorific:
      "true¦director1field marsh2lieutenant1rear0sergeant major,vice0; admir1; gener0;al",
    "Adj|Gerund":
      "true¦0:3F;1:3H;2:31;3:2X;4:35;5:33;6:3C;7:2Z;8:36;9:29;a33b2Tc2Bd1Te1If19g12h0Zi0Rl0Nm0Gnu0Fo0Ap04rYsKtEuBvAw1Ayiel3;ar6e08;nBpA;l1Rs0B;fol3n1Zsett2;aEeDhrBi4ouc7rAwis0;e0Bif2oub2us0yi1;ea1SiA;l2vi1;l2mp0rr1J;nt1Vxi1;aMcreec7enten2NhLkyrocke0lo0Vmi2oJpHtDuBweA;e0Ul2;pp2ArA;gi1pri5roun3;aBea8iAri2Hun9;mula0r4;gge4rA;t2vi1;ark2eAraw2;e3llb2F;aAot7;ki1ri1;i9oc29;dYtisf6;aEeBive0oAus7;a4l2;assu4defi9fres7ig9juve07mai9s0vAwar3;ea2italiAol1G;si1zi1;gi1ll6mb2vi1;a6eDier23lun1VrAun2C;eBoA;mi5vo1Z;ce3s5vai2;n3rpleA;xi1;ffCpWutBverAwi1;arc7lap04p0Pri3whel8;goi1l6st1J;en3sA;et0;m2Jrtu4;aEeDiCoBuAyst0L;mb2;t1Jvi1;s5tiga0;an1Rl0n3smeri26;dAtu4;de9;aCeaBiAo0U;fesa0Tvi1;di1ni1;c1Fg19s0;llumiGmFnArri0R;cDfurHsCtBviA;go23ti1;e1Oimi21oxica0rig0V;pi4ul0;orpo20r0K;po5;na0;eaBorr02umilA;ia0;li1rtwar8;lFrA;atiDipCoBuelA;i1li1;undbrea10wi1;pi1;f6ng;a4ea8;a3etc7it0lEoCrBulfA;il2;ee1FighXust1L;rAun3;ebo3thco8;aCoA;a0wA;e4i1;mi1tte4;lectrJmHnExA;aCci0hBis0pA;an3lo3;aOila1B;c0spe1A;ab2coura0CdBergi13ga0Clive9ric7s02tA;hral2i0J;ea4u4;barras5er09pA;owe4;if6;aQeIiBrA;if0;sAzz6;aEgDhearCsen0tA;rAur11;ac0es5;te9;us0;ppoin0r8;biliGcDfi9gra3ligh0mBpres5sAvasG;erE;an3ea9orA;ali0L;a6eiBli9rA;ea5;vi1;ta0;maPri1s7un0zz2;aPhMlo5oAripp2ut0;mGnArrespon3;cer9fDspi4tA;inBrA;as0ibu0ol2;ui1;lic0u5;ni1;fDmCpA;eAromi5;l2ti1;an3;or0;aAil2;llenAnAr8;gi1;l8ptAri1;iva0;aff2eGin3lFoDrBuA;d3st2;eathtaAui5;ki1;gg2i2o8ri1unA;ci1;in3;co8wiA;lAtc7;de4;bsorVcOgonMlJmHnno6ppea2rFsA;pi4su4toA;nBun3;di1;is7;hi1;res0;li1;aFu5;si1;ar8lu4;ri1;mi1;iAzi1;zi1;cAhi1;eleDomA;moBpan6;yi1;da0;ra0;ti1;bi1;ng",
    Comparable:
      "true¦0:3C;1:3Q;2:3F;a3Tb3Cc33d2Te2Mf2Ag1Wh1Li1Fj1Ek1Bl13m0Xn0So0Rp0Iqu0Gr07sHtCug0vAw4y3za0Q;el10ouN;ary,e6hi5i3ry;ck0Cde,l3n1ry,se;d,y;ny,te;a3i3R;k,ry;a3erda2ulgar;gue,in,st;a6en2Xhi5i4ouZr3;anqu2Cen1ue;dy,g36me0ny;ck,rs28;ll,me,rt,wd3I;aRcaPeOhMiLkin0BlImGoEpDt6u4w3;eet,ift;b3dd0Wperfi21rre28;sta26t21;a8e7iff,r4u3;pUr1;a4ict,o3;ng;ig2Vn0N;a1ep,rn;le,rk,te0;e1Si2Vright0;ci1Yft,l3on,re;emn,id;a3el0;ll,rt;e4i3y;g2Mm0Z;ek,nd2T;ck24l0mp1L;a3iRrill,y;dy,l01rp;ve0Jxy;n1Jr3;ce,y;d,fe,int0l1Hv0V;a8e6i5o3ude;mantic,o19sy,u3;gh;pe,t1P;a3d,mo0A;dy,l;gg4iFndom,p3re,w;id;ed;ai2i3;ck,et;hoAi1Fl9o8r5u3;ny,r3;e,p11;egna2ic4o3;fouSud;ey,k0;liXor;ain,easa2;ny;dd,i0ld,ranL;aive,e5i4o3u14;b0Sisy,rm0Ysy;bb0ce,mb0R;a3r1w;r,t;ad,e5ild,o4u3;nda12te;ist,o1;a4ek,l3;low;s0ty;a8e7i6o3ucky;f0Jn4o15u3ve0w10y0N;d,sy;e0g;ke0l,mp,tt0Eve0;e1Qwd;me,r3te;ge;e4i3;nd;en;ol0ui19;cy,ll,n3;secu6t3;e3ima4;llege2rmedia3;te;re;aAe7i6o5u3;ge,m3ng1C;bYid;me0t;gh,l0;a3fXsita2;dy,rWv3;en0y;nd13ppy,r3;d3sh;!y;aFenEhCiBlAoofy,r3;a8e6i5o3ue0Z;o3ss;vy;m,s0;at,e3y;dy,n;nd,y;ad,ib,ooD;a2d1;a3o3;st0;tDuiS;u1y;aCeebBi9l8o6r5u3;ll,n3r0N;!ny;aCesh,iend0;a3nd,rmD;my;at,ir7;erce,nan3;ci9;le;r,ul3;ty;a6erie,sse4v3xtre0B;il;nti3;al;r4s3;tern,y;ly,th0;appZe9i5ru4u3;mb;nk;r5vi4z3;zy;ne;e,ty;a3ep,n9;d3f,r;!ly;agey,h8l7o5r4u3;dd0r0te;isp,uel;ar3ld,mmon,st0ward0zy;se;evKou1;e3il0;ap,e3;sy;aHiFlCoAr5u3;ff,r0sy;ly;a6i3oad;g4llia2;nt;ht;sh,ve;ld,un3;cy;a4o3ue;nd,o1;ck,nd;g,tt3;er;d,ld,w1;dy;bsu6ng5we3;so3;me;ry;rd",
    Adverb:
      "true¦a08b05d00eYfSheQinPjustOkinda,likewiZmMnJoEpCquite,r9s5t2u0very,well;ltima01p0; to,wards5;h1iny bit,o0wiO;o,t6;en,us;eldom,o0uch;!me1rt0; of;how,times,w0C;a1e0;alS;ndomRth05;ar excellenEer0oint blank; Lhaps;f3n0utright;ce0ly;! 0;ag05moX; courGten;ewJo0; longWt 0;onHwithstand9;aybe,eanwhiNore0;!ovT;! aboX;deed,steY;lla,n0;ce;or3u0;ck1l9rther0;!moK;ing; 0evK;exampCgood,suH;n mas0vI;se;e0irect2; 2fini0;te0;ly;juAtrop;ackward,y 0;far,no0; means,w; GbroFd nauseam,gEl7ny5part,s4t 2w0;ay,hi0;le;be7l0mo7wor7;arge,ea6; soon,i4;mo0way;re;l 3mo2ongsi1ready,so,togeth0ways;er;de;st;b1t0;hat;ut;ain;ad;lot,posteriori",
    Conjunction:
      "true¦aXbTcReNhowMiEjust00noBo9p8supposing,t5wh0yet;e1il0o3;e,st;n1re0thN; if,by,vM;evL;h0il,o;erefOo0;!uU;lus,rovided th9;r0therwiM;! not; mattEr,w0;! 0;since,th4w7;f4n0; 0asmuch;as mIcaForder t0;h0o;at;! 0;only,t0w0;hen;!ev3;ith2ven0;! 0;if,tB;er;o0uz;s,z;e0ut,y the time;cau1f0;ore;se;lt3nd,s 0;far1if,m0soon1t2;uch0; as;hou0;gh",
    Currency:
      "true¦$,aud,bQcOdJeurIfHgbp,hkd,iGjpy,kElDp8r7s3usd,x2y1z0¢,£,¥,ден,лв,руб,฿,₡,₨,€,₭,﷼;lotyQł;en,uanP;af,of;h0t5;e0il5;k0q0;elK;oubleJp,upeeJ;e2ound st0;er0;lingG;n0soF;ceEnies;empi7i7;n,r0wanzaCyatC;!onaBw;ls,nr;ori7ranc9;!os;en3i2kk,o0;b0ll2;ra5;me4n0rham4;ar3;e0ny;nt1;aht,itcoin0;!s",
    Determiner:
      "true¦aBboth,d9e6few,le5mu8neiDplenty,s4th2various,wh0;at0ich0;evC;a0e4is,ose;!t;everal,ome;!ast,s;a1l0very;!se;ch;e0u;!s;!n0;!o0y;th0;er",
    "Adj|Present":
      "true¦a07b04cVdQeNfJhollIidRlEmCnarrIoBp9qua8r7s3t2uttFw0;aKet,ro0;ng,u08;endChin;e2hort,l1mooth,our,pa9tray,u0;re,speU;i2ow;cu6da02leSpaN;eplica01i02;ck;aHerfePr0;eseUime,omV;bscu1pen,wn;atu0e3odeH;re;a2e1ive,ow0;er;an;st,y;ow;a2i1oul,r0;ee,inge;rm;iIke,ncy,st;l1mpty,x0;emHpress;abo4ic7;amp,e2i1oub0ry,ull;le;ffu9re6;fu8libe0;raE;alm,l5o0;mpleCn3ol,rr1unterfe0;it;e0u7;ct;juga8sum7;ea1o0;se;n,r;ankru1lu0;nt;pt;li2pproxi0rticula1;ma0;te;ght",
    "Person|Adj":
      "true¦b3du2earnest,frank,mi2r0san1woo1;an0ich,u1;dy;sty;ella,rown",
    Modal:
      "true¦c5lets,m4ought3sh1w0;ill,o5;a0o4;ll,nt;! to,a;ight,ust;an,o0;uld",
    Verb: "true¦born,cannot,gonna,has,keep tabs,msg",
    "Person|Verb":
      "true¦b8ch7dr6foster,gra5ja9lan4ma2ni9ollie,p1rob,s0wade;kip,pike,t5ue;at,eg,ier2;ck,r0;k,shal;ce;ce,nt;ew;ase,u1;iff,l1ob,u0;ck;aze,ossom",
    "Person|Date": "true¦a2j0sep;an0une;!uary;p0ugust,v0;ril",
  },
  Wt = 36,
  hi = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ",
  os = hi.split("").reduce(function (e, t, n) {
    return ((e[t] = n), e);
  }, {}),
  e0 = function (e) {
    if (hi[e] !== void 0) return hi[e];
    let t = 1,
      n = Wt,
      r = "";
    for (; e >= n; e -= n, t++, n *= Wt);
    for (; t--;) {
      const a = e % Wt;
      ((r = String.fromCharCode((a < 10 ? 48 : 55) + a) + r),
        (e = (e - a) / Wt));
    }
    return r;
  },
  t0 = function (e) {
    if (os[e] !== void 0) return os[e];
    let t = 0,
      n = 1,
      r = Wt,
      a = 1;
    for (; n < e.length; t += r, n++, r *= Wt);
    for (let i = e.length - 1; i >= 0; i--, a *= Wt) {
      let o = e.charCodeAt(i) - 48;
      (o > 10 && (o -= 7), (t += o * a));
    }
    return t;
  },
  di = { toAlphaCode: e0, fromAlphaCode: t0 },
  n0 = function (e) {
    const t = new RegExp("([0-9A-Z]+):([0-9A-Z]+)");
    for (let n = 0; n < e.nodes.length; n++) {
      const r = t.exec(e.nodes[n]);
      if (!r) {
        e.symCount = n;
        break;
      }
      e.syms[di.fromAlphaCode(r[1])] = di.fromAlphaCode(r[2]);
    }
    e.nodes = e.nodes.slice(e.symCount, e.nodes.length);
  },
  r0 = function (e, t, n) {
    const r = di.fromAlphaCode(t);
    return r < e.symCount ? e.syms[r] : n + r + 1 - e.symCount;
  },
  a0 = function (e) {
    const t = [],
      n = (r, a) => {
        let i = e.nodes[r];
        i[0] === "!" && (t.push(a), (i = i.slice(1)));
        const o = i.split(/([A-Z0-9,]+)/g);
        for (let s = 0; s < o.length; s += 2) {
          const l = o[s],
            u = o[s + 1];
          if (!l) continue;
          const c = a + l;
          if (u === "," || u === void 0) {
            t.push(c);
            continue;
          }
          const h = r0(e, u, r);
          n(h, c);
        }
      };
    return (n(0, ""), t);
  },
  i0 = function (e) {
    const t = { nodes: e.split(";"), syms: [], symCount: 0 };
    return (e.match(":") && n0(t), a0(t));
  },
  o0 = function (e) {
    if (!e) return {};
    const t = e.split("|").reduce((r, a) => {
        const i = a.split("¦");
        return ((r[i[0]] = i[1]), r);
      }, {}),
      n = {};
    return (
      Object.keys(t).forEach(function (r) {
        const a = i0(t[r]);
        r === "true" && (r = !0);
        for (let i = 0; i < a.length; i++) {
          const o = a[i];
          n.hasOwnProperty(o) === !0
            ? Array.isArray(n[o]) === !1
              ? (n[o] = [n[o], r])
              : n[o].push(r)
            : (n[o] = r);
        }
      }),
      n
    );
  },
  Ie = ["Possessive", "Pronoun"];
let s0 = {
  "20th century fox": "Organization",
  "7 eleven": "Organization",
  "motel 6": "Organization",
  g8: "Organization",
  vh1: "Organization",
  "76ers": "SportsTeam",
  "49ers": "SportsTeam",
  q1: "Date",
  q2: "Date",
  q3: "Date",
  q4: "Date",
  km2: "Unit",
  m2: "Unit",
  dm2: "Unit",
  cm2: "Unit",
  mm2: "Unit",
  mile2: "Unit",
  in2: "Unit",
  yd2: "Unit",
  ft2: "Unit",
  m3: "Unit",
  dm3: "Unit",
  cm3: "Unit",
  in3: "Unit",
  ft3: "Unit",
  yd3: "Unit",
  "at&t": "Organization",
  "black & decker": "Organization",
  "h & m": "Organization",
  "johnson & johnson": "Organization",
  "procter & gamble": "Organization",
  "ben & jerry's": "Organization",
  "&": "Conjunction",
  i: ["Pronoun", "Singular"],
  he: ["Pronoun", "Singular"],
  she: ["Pronoun", "Singular"],
  it: ["Pronoun", "Singular"],
  they: ["Pronoun", "Plural"],
  we: ["Pronoun", "Plural"],
  was: ["Copula", "PastTense"],
  is: ["Copula", "PresentTense"],
  are: ["Copula", "PresentTense"],
  am: ["Copula", "PresentTense"],
  were: ["Copula", "PastTense"],
  her: Ie,
  his: Ie,
  hers: Ie,
  their: Ie,
  theirs: Ie,
  themselves: Ie,
  your: Ie,
  our: Ie,
  ours: Ie,
  my: Ie,
  its: Ie,
  vs: ["Conjunction", "Abbreviation"],
  if: ["Condition", "Preposition"],
  closer: "Comparative",
  closest: "Superlative",
  much: "Adverb",
  may: "Modal",
  babysat: "PastTense",
  blew: "PastTense",
  drank: "PastTense",
  drove: "PastTense",
  forgave: "PastTense",
  skiied: "PastTense",
  spilt: "PastTense",
  stung: "PastTense",
  swam: "PastTense",
  swung: "PastTense",
  guaranteed: "PastTense",
  shrunk: "PastTense",
  nears: "PresentTense",
  nearing: "Gerund",
  neared: "PastTense",
  no: ["Negative", "Expression"],
};
const l0 = {
    "20th century fox": "Organization",
    "7 eleven": "Organization",
    "motel 6": "Organization",
    "excuse me": "Expression",
    "financial times": "Organization",
    "guns n roses": "Organization",
    "la z boy": "Organization",
    "labour party": "Organization",
    "new kids on the block": "Organization",
    "new york times": "Organization",
    "the guess who": "Organization",
    "thin lizzy": "Organization",
    "prime minister": "Actor",
    "free market": "Singular",
    "lay up": "Singular",
    "living room": "Singular",
    "living rooms": "Plural",
    "spin off": "Singular",
    "appeal court": "Uncountable",
    "cold war": "Uncountable",
    "gene pool": "Uncountable",
    "machine learning": "Uncountable",
    "nail polish": "Uncountable",
    "time off": "Uncountable",
    "take part": "Infinitive",
    "bill gates": "Person",
    "doctor who": "Person",
    "dr who": "Person",
    "he man": "Person",
    "iron man": "Person",
    "kid cudi": "Person",
    "run dmc": "Person",
    "rush limbaugh": "Person",
    "snow white": "Person",
    "tiger woods": "Person",
    "brand new": "Adjective",
    "en route": "Adjective",
    "left wing": "Adjective",
    "off guard": "Adjective",
    "on board": "Adjective",
    "part time": "Adjective",
    "right wing": "Adjective",
    "so called": "Adjective",
    "spot on": "Adjective",
    "straight forward": "Adjective",
    "super duper": "Adjective",
    "tip top": "Adjective",
    "top notch": "Adjective",
    "up to date": "Adjective",
    "win win": "Adjective",
    "brooklyn nets": "SportsTeam",
    "chicago bears": "SportsTeam",
    "houston astros": "SportsTeam",
    "houston dynamo": "SportsTeam",
    "houston rockets": "SportsTeam",
    "houston texans": "SportsTeam",
    "minnesota twins": "SportsTeam",
    "orlando magic": "SportsTeam",
    "san antonio spurs": "SportsTeam",
    "san diego chargers": "SportsTeam",
    "san diego padres": "SportsTeam",
    "iron maiden": "ProperNoun",
    "isle of man": "Country",
    "united states": "Country",
    "united states of america": "Country",
    "prince edward island": "Region",
    "cedar breaks": "Place",
    "cedar falls": "Place",
    "point blank": "Adverb",
    "tiny bit": "Adverb",
    "by the time": "Conjunction",
    "no matter": "Conjunction",
    "civil wars": "Plural",
    "credit cards": "Plural",
    "default rates": "Plural",
    "free markets": "Plural",
    "head starts": "Plural",
    "home runs": "Plural",
    "lay ups": "Plural",
    "phone calls": "Plural",
    "press releases": "Plural",
    "record labels": "Plural",
    "soft serves": "Plural",
    "student loans": "Plural",
    "tax returns": "Plural",
    "tv shows": "Plural",
    "video games": "Plural",
    "took part": "PastTense",
    "takes part": "PresentTense",
    "taking part": "Gerund",
    "taken part": "Participle",
    "light bulb": "Noun",
    "rush hour": "Noun",
    "fluid ounce": "Unit",
    "the rolling stones": "Organization",
  },
  u0 = [
    ":(",
    ":)",
    ":P",
    ":p",
    ":O",
    ";(",
    ";)",
    ";P",
    ";p",
    ";O",
    ":3",
    ":|",
    ":/",
    ":\\",
    ":$",
    ":*",
    ":@",
    ":-(",
    ":-)",
    ":-P",
    ":-p",
    ":-O",
    ":-3",
    ":-|",
    ":-/",
    ":-\\",
    ":-$",
    ":-*",
    ":-@",
    ":^(",
    ":^)",
    ":^P",
    ":^p",
    ":^O",
    ":^3",
    ":^|",
    ":^/",
    ":^\\",
    ":^$",
    ":^*",
    ":^@",
    "):",
    "(:",
    "$:",
    "*:",
    ")-:",
    "(-:",
    "$-:",
    "*-:",
    ")^:",
    "(^:",
    "$^:",
    "*^:",
    "<3",
    "</3",
    "<\\3",
    "=(",
  ],
  or = {
    a: [
      [/(antenn|formul|nebul|vertebr|vit)a$/i, "$1ae"],
      [/ia$/i, "ia"],
    ],
    e: [
      [/(kn|l|w)ife$/i, "$1ives"],
      [/(hive)$/i, "$1s"],
      [/([m|l])ouse$/i, "$1ice"],
      [/([m|l])ice$/i, "$1ice"],
    ],
    f: [
      [/^(dwar|handkerchie|hoo|scar|whar)f$/i, "$1ves"],
      [
        /^((?:ca|e|ha|(?:our|them|your)?se|she|wo)l|lea|loa|shea|thie)f$/i,
        "$1ves",
      ],
    ],
    i: [[/(octop|vir)i$/i, "$1i"]],
    m: [[/([ti])um$/i, "$1a"]],
    n: [[/^(oxen)$/i, "$1"]],
    o: [[/(al|ad|at|er|et|ed)o$/i, "$1oes"]],
    s: [
      [/(ax|test)is$/i, "$1es"],
      [/(alias|status)$/i, "$1es"],
      [/sis$/i, "ses"],
      [/(bu)s$/i, "$1ses"],
      [/(sis)$/i, "ses"],
      [/^(?!talis|.*hu)(.*)man$/i, "$1men"],
      [/(octop|vir|radi|nucle|fung|cact|stimul)us$/i, "$1i"],
    ],
    x: [
      [/(matr|vert|ind|cort)(ix|ex)$/i, "$1ices"],
      [/^(ox)$/i, "$1en"],
    ],
    y: [[/([^aeiouy]|qu)y$/i, "$1ies"]],
    z: [[/(quiz)$/i, "$1zes"]],
  },
  c0 = /([xsz]|ch|sh)$/,
  h0 = function (e) {
    let t = e[e.length - 1];
    if (or.hasOwnProperty(t) === !0)
      for (let n = 0; n < or[t].length; n += 1) {
        let r = or[t][n][0];
        if (r.test(e) === !0) return e.replace(r, or[t][n][1]);
      }
    return null;
  },
  sa = function (e = "", t) {
    let { irregularPlurals: n, uncountable: r } = t.two;
    if (r.hasOwnProperty(e)) return e;
    if (n.hasOwnProperty(e)) return n[e];
    let a = h0(e);
    return a !== null ? a : c0.test(e) ? e + "es" : e + "s";
  },
  d0 = /\|/;
let xn = s0,
  fi = {};
const f0 = { two: { irregularPlurals: _u, uncountable: {} } };
Object.keys(is).forEach((e) => {
  let t = o0(is[e]);
  if (!d0.test(e)) {
    Object.keys(t).forEach((n) => {
      xn[n] = e;
    });
    return;
  }
  Object.keys(t).forEach((n) => {
    if (((fi[n] = e), e === "Noun|Verb")) {
      let r = sa(n, f0);
      fi[r] = "Plural|Verb";
    }
  });
});
u0.forEach((e) => (xn[e] = "Emoticon"));
delete xn[""];
delete xn[null];
delete xn[" "];
const d = "Singular",
  L = {
    beforeTags: {
      Determiner: d,
      Possessive: d,
      Acronym: d,
      Noun: d,
      Adjective: d,
      PresentTense: d,
      Gerund: d,
      PastTense: d,
      Infinitive: d,
      Date: d,
      Ordinal: d,
      Demonym: d,
    },
    afterTags: {
      Value: d,
      Modal: d,
      Copula: d,
      PresentTense: d,
      PastTense: d,
      Demonym: d,
      Actor: d,
    },
    beforeWords: {
      the: d,
      with: d,
      without: d,
      of: d,
      for: d,
      any: d,
      all: d,
      on: d,
      cut: d,
      cuts: d,
      increase: d,
      decrease: d,
      raise: d,
      drop: d,
      save: d,
      saved: d,
      saves: d,
      make: d,
      makes: d,
      made: d,
      minus: d,
      plus: d,
      than: d,
      another: d,
      versus: d,
      neither: d,
      about: d,
      favorite: d,
      best: d,
      daily: d,
      weekly: d,
      linear: d,
      binary: d,
      mobile: d,
      lexical: d,
      technical: d,
      computer: d,
      scientific: d,
      security: d,
      government: d,
      popular: d,
      formal: d,
      no: d,
      more: d,
      one: d,
      let: d,
      her: d,
      his: d,
      their: d,
      our: d,
      us: d,
      sheer: d,
      monthly: d,
      yearly: d,
      current: d,
      previous: d,
      upcoming: d,
      last: d,
      next: d,
      main: d,
      initial: d,
      final: d,
      beginning: d,
      end: d,
      top: d,
      bottom: d,
      future: d,
      past: d,
      major: d,
      minor: d,
      side: d,
      central: d,
      peripheral: d,
      public: d,
      private: d,
    },
    afterWords: {
      of: d,
      system: d,
      aid: d,
      method: d,
      utility: d,
      tool: d,
      reform: d,
      therapy: d,
      philosophy: d,
      room: d,
      authority: d,
      says: d,
      said: d,
      wants: d,
      wanted: d,
      is: d,
      did: d,
      do: d,
      can: d,
      wise: d,
    },
  },
  m = "Infinitive",
  le = {
    beforeTags: { Modal: m, Adverb: m, Negative: m, Plural: m },
    afterTags: {
      Determiner: m,
      Adverb: m,
      Possessive: m,
      Reflexive: m,
      Preposition: m,
      Cardinal: m,
      Comparative: m,
      Superlative: m,
    },
    beforeWords: {
      i: m,
      we: m,
      you: m,
      they: m,
      to: m,
      please: m,
      will: m,
      have: m,
      had: m,
      would: m,
      could: m,
      should: m,
      do: m,
      did: m,
      does: m,
      can: m,
      must: m,
      us: m,
      me: m,
      let: m,
      even: m,
      when: m,
      help: m,
      he: m,
      she: m,
      it: m,
      being: m,
      bi: m,
      co: m,
      contra: m,
      de: m,
      inter: m,
      intra: m,
      mis: m,
      pre: m,
      out: m,
      counter: m,
      nobody: m,
      somebody: m,
      anybody: m,
      everybody: m,
    },
    afterWords: {
      the: m,
      me: m,
      you: m,
      him: m,
      us: m,
      her: m,
      his: m,
      them: m,
      they: m,
      it: m,
      himself: m,
      herself: m,
      itself: m,
      myself: m,
      ourselves: m,
      themselves: m,
      something: m,
      anything: m,
      a: m,
      an: m,
      up: m,
      down: m,
      by: m,
      out: m,
      off: m,
      under: m,
      what: m,
      all: m,
      to: m,
      because: m,
      although: m,
      how: m,
      otherwise: m,
      together: m,
      though: m,
      into: m,
      yet: m,
      more: m,
      here: m,
      there: m,
      away: m,
    },
  },
  m0 = {
    beforeTags: Object.assign({}, le.beforeTags, L.beforeTags, {}),
    afterTags: Object.assign({}, le.afterTags, L.afterTags, {}),
    beforeWords: Object.assign({}, le.beforeWords, L.beforeWords, {}),
    afterWords: Object.assign({}, le.afterWords, L.afterWords, {}),
  },
  p = "Adjective",
  R = {
    beforeTags: { Determiner: p, Possessive: p, Hyphenated: p },
    afterTags: { Adjective: p },
    beforeWords: {
      seem: p,
      seemed: p,
      seems: p,
      feel: p,
      feels: p,
      felt: p,
      stay: p,
      appear: p,
      appears: p,
      appeared: p,
      also: p,
      over: p,
      under: p,
      too: p,
      it: p,
      but: p,
      still: p,
      really: p,
      quite: p,
      well: p,
      very: p,
      truly: p,
      how: p,
      deeply: p,
      hella: p,
      profoundly: p,
      extremely: p,
      so: p,
      badly: p,
      mostly: p,
      totally: p,
      awfully: p,
      rather: p,
      nothing: p,
      something: p,
      anything: p,
      not: p,
      me: p,
      is: p,
      face: p,
      faces: p,
      faced: p,
      look: p,
      looks: p,
      looked: p,
      reveal: p,
      reveals: p,
      revealed: p,
      sound: p,
      sounded: p,
      sounds: p,
      remains: p,
      remained: p,
      prove: p,
      proves: p,
      proved: p,
      becomes: p,
      stays: p,
      tastes: p,
      taste: p,
      smells: p,
      smell: p,
      gets: p,
      grows: p,
      as: p,
      rings: p,
      radiates: p,
      conveys: p,
      convey: p,
      conveyed: p,
      of: p,
    },
    afterWords: { too: p, also: p, or: p, enough: p, as: p },
  },
  v = "Gerund",
  Pt = {
    beforeTags: { Adverb: v, Preposition: v, Conjunction: v },
    afterTags: {
      Adverb: v,
      Possessive: v,
      Person: v,
      Pronoun: v,
      Determiner: v,
      Copula: v,
      Preposition: v,
      Conjunction: v,
      Comparative: v,
    },
    beforeWords: {
      been: v,
      keep: v,
      continue: v,
      stop: v,
      am: v,
      be: v,
      me: v,
      began: v,
      start: v,
      starts: v,
      started: v,
      stops: v,
      stopped: v,
      help: v,
      helps: v,
      avoid: v,
      avoids: v,
      love: v,
      loves: v,
      loved: v,
      hate: v,
      hates: v,
      hated: v,
    },
    afterWords: {
      you: v,
      me: v,
      her: v,
      him: v,
      his: v,
      them: v,
      their: v,
      it: v,
      this: v,
      there: v,
      on: v,
      about: v,
      for: v,
      up: v,
      down: v,
    },
  },
  j = "Gerund",
  mt = "Adjective",
  p0 = {
    beforeTags: Object.assign({}, R.beforeTags, Pt.beforeTags, {
      Imperative: j,
      Infinitive: mt,
      Plural: j,
    }),
    afterTags: Object.assign({}, R.afterTags, Pt.afterTags, { Noun: mt }),
    beforeWords: Object.assign({}, R.beforeWords, Pt.beforeWords, {
      is: mt,
      are: j,
      was: mt,
      of: mt,
      suggest: j,
      suggests: j,
      suggested: j,
      recommend: j,
      recommends: j,
      recommended: j,
      imagine: j,
      imagines: j,
      imagined: j,
      consider: j,
      considered: j,
      considering: j,
      resist: j,
      resists: j,
      resisted: j,
      avoid: j,
      avoided: j,
      avoiding: j,
      except: mt,
      accept: mt,
      assess: j,
      explore: j,
      fear: j,
      fears: j,
      appreciate: j,
      question: j,
      help: j,
      embrace: j,
      with: mt,
    }),
    afterWords: Object.assign({}, R.afterWords, Pt.afterWords, {
      to: j,
      not: j,
      the: j,
    }),
  },
  ss = {
    beforeTags: {
      Determiner: void 0,
      Cardinal: "Noun",
      PhrasalVerb: "Adjective",
    },
    afterTags: {},
  },
  g0 = {
    beforeTags: Object.assign({}, R.beforeTags, L.beforeTags, ss.beforeTags),
    afterTags: Object.assign({}, R.afterTags, L.afterTags, ss.afterTags),
    beforeWords: Object.assign({}, R.beforeWords, L.beforeWords, {
      are: "Adjective",
      is: "Adjective",
      was: "Adjective",
      be: "Adjective",
      off: "Adjective",
      out: "Adjective",
    }),
    afterWords: Object.assign({}, R.afterWords, L.afterWords),
  };
let P = "PastTense",
  jn = "Adjective";
const sr = {
    beforeTags: { Adverb: P, Pronoun: P, ProperNoun: P, Auxiliary: P, Noun: P },
    afterTags: {
      Possessive: P,
      Pronoun: P,
      Determiner: P,
      Adverb: P,
      Comparative: P,
      Date: P,
      Gerund: P,
    },
    beforeWords: {
      be: P,
      who: P,
      get: jn,
      had: P,
      has: P,
      have: P,
      been: P,
      it: P,
      as: P,
      for: jn,
      more: jn,
      always: jn,
    },
    afterWords: {
      by: P,
      back: P,
      out: P,
      in: P,
      up: P,
      down: P,
      before: P,
      after: P,
      for: P,
      the: P,
      with: P,
      as: P,
      on: P,
      at: P,
      between: P,
      to: P,
      into: P,
      us: P,
      them: P,
      his: P,
      her: P,
      their: P,
      our: P,
      me: P,
      about: jn,
    },
  },
  y0 = {
    beforeTags: Object.assign({}, R.beforeTags, sr.beforeTags),
    afterTags: Object.assign({}, R.afterTags, sr.afterTags),
    beforeWords: Object.assign({}, R.beforeWords, sr.beforeWords),
    afterWords: Object.assign({}, R.afterWords, sr.afterWords),
  },
  b0 = { afterTags: { Noun: "Adjective", Conjunction: void 0 } },
  v0 = {
    beforeTags: Object.assign({}, R.beforeTags, le.beforeTags, {
      Adverb: void 0,
      Negative: void 0,
    }),
    afterTags: Object.assign({}, R.afterTags, le.afterTags, b0.afterTags),
    beforeWords: Object.assign({}, R.beforeWords, le.beforeWords, {
      have: void 0,
      had: void 0,
      not: void 0,
      went: "Adjective",
      goes: "Adjective",
      got: "Adjective",
      be: "Adjective",
    }),
    afterWords: Object.assign({}, R.afterWords, le.afterWords, {
      to: void 0,
      as: "Adjective",
    }),
  },
  lr = {
    beforeTags: {
      Copula: "Gerund",
      PastTense: "Gerund",
      PresentTense: "Gerund",
      Infinitive: "Gerund",
    },
    afterTags: { Value: "Gerund" },
    beforeWords: {
      are: "Gerund",
      were: "Gerund",
      be: "Gerund",
      no: "Gerund",
      without: "Gerund",
      you: "Gerund",
      we: "Gerund",
      they: "Gerund",
      he: "Gerund",
      she: "Gerund",
      us: "Gerund",
      them: "Gerund",
    },
    afterWords: {
      the: "Gerund",
      this: "Gerund",
      that: "Gerund",
      me: "Gerund",
      us: "Gerund",
      them: "Gerund",
    },
  },
  w0 = {
    beforeTags: Object.assign({}, Pt.beforeTags, L.beforeTags, lr.beforeTags),
    afterTags: Object.assign({}, Pt.afterTags, L.afterTags, lr.afterTags),
    beforeWords: Object.assign(
      {},
      Pt.beforeWords,
      L.beforeWords,
      lr.beforeWords,
    ),
    afterWords: Object.assign({}, Pt.afterWords, L.afterWords, lr.afterWords),
  },
  nn = "Singular",
  Ot = "Infinitive",
  k0 = {
    beforeTags: Object.assign({}, le.beforeTags, L.beforeTags, {
      Adjective: nn,
      Particle: nn,
    }),
    afterTags: Object.assign({}, le.afterTags, L.afterTags, {
      ProperNoun: Ot,
      Gerund: Ot,
      Adjective: Ot,
      Copula: nn,
    }),
    beforeWords: Object.assign({}, le.beforeWords, L.beforeWords, {
      is: nn,
      was: nn,
      of: nn,
      have: null,
    }),
    afterWords: Object.assign({}, le.afterWords, L.afterWords, {
      instead: Ot,
      about: Ot,
      his: Ot,
      her: Ot,
      to: null,
      by: null,
      in: null,
    }),
  },
  I = "Person",
  Y = {
    beforeTags: { Honorific: I, Person: I },
    afterTags: { Person: I, ProperNoun: I, Verb: I },
    beforeWords: { hi: I, hey: I, yo: I, dear: I, hello: I },
    afterWords: {
      said: I,
      says: I,
      told: I,
      tells: I,
      feels: I,
      felt: I,
      seems: I,
      thinks: I,
      thought: I,
      spends: I,
      spendt: I,
      plays: I,
      played: I,
      sing: I,
      sang: I,
      learn: I,
      learned: I,
      wants: I,
      wanted: I,
    },
  },
  M = "Month",
  P0 = "Person",
  ur = {
    beforeTags: { Date: M, Value: M },
    afterTags: { Date: M, Value: M },
    beforeWords: {
      by: M,
      in: M,
      on: M,
      during: M,
      after: M,
      before: M,
      between: M,
      until: M,
      til: M,
      sometime: M,
      of: M,
      this: M,
      next: M,
      last: M,
      previous: M,
      following: M,
      with: P0,
    },
    afterWords: { sometime: M, in: M, of: M, until: M, the: M },
  },
  A0 = {
    beforeTags: Object.assign({}, Y.beforeTags, ur.beforeTags),
    afterTags: Object.assign({}, Y.afterTags, ur.afterTags),
    beforeWords: Object.assign({}, Y.beforeWords, ur.beforeWords),
    afterWords: Object.assign({}, Y.afterWords, ur.afterWords),
  },
  x0 = {
    beforeTags: Object.assign({}, L.beforeTags, Y.beforeTags),
    afterTags: Object.assign({}, L.afterTags, Y.afterTags),
    beforeWords: Object.assign({}, L.beforeWords, Y.beforeWords, {
      i: "Infinitive",
      we: "Infinitive",
    }),
    afterWords: Object.assign({}, L.afterWords, Y.afterWords),
  },
  C0 = {
    beforeTags: Object.assign({}, L.beforeTags, Y.beforeTags, le.beforeTags),
    afterTags: Object.assign({}, L.afterTags, Y.afterTags, le.afterTags),
    beforeWords: Object.assign(
      {},
      L.beforeWords,
      Y.beforeWords,
      le.beforeWords,
    ),
    afterWords: Object.assign({}, L.afterWords, Y.afterWords, le.afterWords),
  },
  re = "Place",
  cr = {
    beforeTags: { Place: re },
    afterTags: { Place: re, Abbreviation: re },
    beforeWords: { in: re, by: re, near: re, from: re, to: re },
    afterWords: {
      in: re,
      by: re,
      near: re,
      from: re,
      to: re,
      government: re,
      council: re,
      region: re,
      city: re,
    },
  },
  D0 = {
    beforeTags: Object.assign({}, cr.beforeTags, Y.beforeTags),
    afterTags: Object.assign({}, cr.afterTags, Y.afterTags),
    beforeWords: Object.assign({}, cr.beforeWords, Y.beforeWords),
    afterWords: Object.assign({}, cr.afterWords, Y.afterWords),
  },
  $0 = {
    beforeTags: Object.assign({}, Y.beforeTags, R.beforeTags),
    afterTags: Object.assign({}, Y.afterTags, R.afterTags),
    beforeWords: Object.assign({}, Y.beforeWords, R.beforeWords),
    afterWords: Object.assign({}, Y.afterWords, R.afterWords),
  };
let Ce = "Unit";
const j0 = {
    beforeTags: { Value: Ce },
    afterTags: {},
    beforeWords: {
      per: Ce,
      every: Ce,
      each: Ce,
      square: Ce,
      cubic: Ce,
      sq: Ce,
      metric: Ce,
    },
    afterWords: { per: Ce, squared: Ce, cubed: Ce, long: Ce },
  },
  gn = {
    "Actor|Verb": m0,
    "Adj|Gerund": p0,
    "Adj|Noun": g0,
    "Adj|Past": y0,
    "Adj|Present": v0,
    "Noun|Verb": k0,
    "Noun|Gerund": w0,
    "Person|Noun": x0,
    "Person|Date": A0,
    "Person|Verb": C0,
    "Person|Place": D0,
    "Person|Adj": $0,
    "Unit|Noun": j0,
  },
  hr = (e, t) => {
    let n = Object.keys(e).reduce(
      (r, a) => ((r[a] = e[a] === "Infinitive" ? "PresentTense" : "Plural"), r),
      {},
    );
    return Object.assign(n, t);
  };
gn["Plural|Verb"] = {
  beforeWords: hr(gn["Noun|Verb"].beforeWords, {
    had: "Plural",
    have: "Plural",
  }),
  afterWords: hr(gn["Noun|Verb"].afterWords, {
    his: "PresentTense",
    her: "PresentTense",
    its: "PresentTense",
    in: null,
    to: null,
    is: "PresentTense",
    by: "PresentTense",
  }),
  beforeTags: hr(gn["Noun|Verb"].beforeTags, {
    Conjunction: "PresentTense",
    Noun: void 0,
    ProperNoun: "PresentTense",
  }),
  afterTags: hr(gn["Noun|Verb"].afterTags, {
    Gerund: "Plural",
    Noun: "PresentTense",
    Value: "PresentTense",
  }),
};
const T = "Adjective",
  Q = "Infinitive",
  It = "PresentTense",
  A = "Singular",
  Z = "PastTense",
  rn = "Adverb",
  ve = "Plural",
  W = "Actor",
  dr = "Verb",
  ie = "Noun",
  N0 = "ProperNoun",
  Ee = "LastName",
  ls = "Modal",
  H = "Place",
  ba = "Participle",
  T0 = [
    null,
    null,
    { ea: A, ia: ie, ic: T, ly: rn, "'n": dr, "'t": dr },
    {
      oed: Z,
      ued: Z,
      xed: Z,
      " so": rn,
      "'ll": ls,
      "'re": "Copula",
      azy: T,
      eer: ie,
      end: dr,
      ped: Z,
      ffy: T,
      ify: Q,
      ing: "Gerund",
      ize: Q,
      ibe: Q,
      lar: T,
      mum: T,
      nes: It,
      nny: T,
      ous: T,
      que: T,
      ger: ie,
      ber: ie,
      rol: A,
      sis: A,
      ogy: A,
      oid: A,
      ian: A,
      zes: It,
      eld: Z,
      ken: ba,
      ven: ba,
      ten: ba,
      ect: Q,
      ict: Q,
      ign: Q,
      oze: Q,
      ful: T,
      bal: T,
      ton: ie,
      pur: H,
    },
    {
      amed: Z,
      aped: Z,
      ched: Z,
      lked: Z,
      rked: Z,
      reed: Z,
      nded: Z,
      mned: T,
      cted: Z,
      dged: Z,
      ield: A,
      akis: Ee,
      cede: Q,
      chuk: Ee,
      czyk: Ee,
      ects: It,
      iend: A,
      ends: dr,
      enko: Ee,
      ette: A,
      iary: A,
      wner: A,
      fies: It,
      fore: rn,
      gate: Q,
      gone: T,
      ices: ve,
      ints: ve,
      ruct: Q,
      ines: ve,
      ions: ve,
      ners: ve,
      pers: ve,
      lers: ve,
      less: T,
      llen: T,
      made: T,
      nsen: Ee,
      oses: It,
      ould: ls,
      some: T,
      sson: Ee,
      ians: ve,
      tion: A,
      tage: ie,
      ique: A,
      tive: T,
      tors: ie,
      vice: A,
      lier: A,
      fier: A,
      wned: Z,
      gent: A,
      tist: W,
      pist: W,
      rist: W,
      mist: W,
      yist: W,
      vist: W,
      ists: W,
      lite: A,
      site: A,
      rite: A,
      mite: A,
      bite: A,
      mate: A,
      date: A,
      ndal: A,
      vent: A,
      uist: W,
      gist: W,
      note: A,
      cide: A,
      ence: A,
      wide: T,
      vide: Q,
      ract: Q,
      duce: Q,
      pose: Q,
      eive: Q,
      lyze: Q,
      lyse: Q,
      iant: T,
      nary: T,
      ghty: T,
      uent: T,
      erer: W,
      bury: H,
      dorf: ie,
      esty: ie,
      wych: H,
      dale: H,
      folk: H,
      vale: H,
      abad: H,
      sham: H,
      wick: H,
      view: H,
    },
    {
      elist: W,
      holic: A,
      phite: A,
      tized: Z,
      urned: Z,
      eased: Z,
      ances: ve,
      bound: T,
      ettes: ve,
      fully: rn,
      ishes: It,
      ities: ve,
      marek: Ee,
      nssen: Ee,
      ology: ie,
      osome: A,
      tment: A,
      ports: ve,
      rough: T,
      tches: It,
      tieth: "Ordinal",
      tures: ve,
      wards: rn,
      where: rn,
      archy: ie,
      pathy: ie,
      opoly: ie,
      embly: ie,
      phate: ie,
      ndent: A,
      scent: A,
      onist: W,
      anist: W,
      alist: W,
      olist: W,
      icist: W,
      ounce: Q,
      iable: T,
      borne: T,
      gnant: T,
      inant: T,
      igent: T,
      atory: T,
      rient: A,
      dient: A,
      maker: W,
      burgh: H,
      mouth: H,
      ceter: H,
      ville: H,
      hurst: H,
      stead: H,
      endon: H,
      brook: H,
      shire: H,
      worth: ie,
      field: N0,
      ridge: H,
    },
    {
      auskas: Ee,
      parent: A,
      cedent: A,
      ionary: A,
      cklist: A,
      brooke: H,
      keeper: W,
      logist: W,
      teenth: "Value",
      worker: W,
      master: W,
      writer: W,
      brough: H,
      cester: H,
      ington: H,
      cliffe: H,
      ingham: H,
    },
    { chester: H, logists: W, opoulos: Ee, borough: H, sdottir: Ee },
  ],
  we = "Adjective",
  z = "Noun",
  Nn = "Verb",
  O0 = [
    null,
    null,
    {},
    { neo: z, bio: z, "de-": Nn, "re-": Nn, "un-": Nn, "ex-": z },
    {
      anti: z,
      auto: z,
      faux: we,
      hexa: z,
      kilo: z,
      mono: z,
      nano: z,
      octa: z,
      poly: z,
      semi: we,
      tele: z,
      "pro-": we,
      "mis-": Nn,
      "dis-": Nn,
      "pre-": we,
    },
    {
      anglo: z,
      centi: z,
      ethno: z,
      ferro: z,
      grand: z,
      hepta: z,
      hydro: z,
      intro: z,
      macro: z,
      micro: z,
      milli: z,
      nitro: z,
      penta: z,
      quasi: we,
      radio: z,
      tetra: z,
      "omni-": we,
      "post-": we,
    },
    {
      pseudo: we,
      "extra-": we,
      "hyper-": we,
      "inter-": we,
      "intra-": we,
      "deca-": we,
    },
    { electro: z },
  ],
  B = "Adjective",
  fr = "Infinitive",
  mr = "PresentTense",
  Ze = "Singular",
  ue = "PastTense",
  us = "Adverb",
  Xe = "Expression",
  cs = "Actor",
  hs = "Verb",
  ds = "Noun",
  pr = "LastName",
  I0 = {
    a: [
      [/.[aeiou]na$/, ds, "tuna"],
      [/.[oau][wvl]ska$/, pr],
      [/.[^aeiou]ica$/, Ze, "harmonica"],
      [/^([hyj]a+)+$/, Xe, "haha"],
    ],
    c: [[/.[^aeiou]ic$/, B]],
    d: [
      [/[aeiou](pp|ll|ss|ff|gg|tt|rr|bb|nn|mm)ed$/, ue, "popped"],
      [/.[aeo]{2}[bdgmnprvz]ed$/, ue, "rammed"],
      [/.[aeiou][sg]hed$/, ue, "gushed"],
      [/.[aeiou]red$/, ue, "hired"],
      [/.[aeiou]r?ried$/, ue, "hurried"],
      [/[^aeiou]ard$/, Ze, "steward"],
      [/[aeiou][^aeiou]id$/, B, ""],
      [/.[vrl]id$/, B, "livid"],
      [/..led$/, ue, "hurled"],
      [/.[iao]sed$/, ue, ""],
      [/[aeiou]n?[cs]ed$/, ue, ""],
      [/[aeiou][rl]?[mnf]ed$/, ue, ""],
      [/[aeiou][ns]?c?ked$/, ue, "bunked"],
      [/[aeiou]gned$/, ue],
      [/[aeiou][nl]?ged$/, ue],
      [/.[tdbwxyz]ed$/, ue],
      [/[^aeiou][aeiou][tvx]ed$/, ue],
      [/.[cdflmnprstv]ied$/, ue, "emptied"],
    ],
    e: [
      [/.[lnr]ize$/, fr, "antagonize"],
      [/.[^aeiou]ise$/, fr, "antagonise"],
      [/.[aeiou]te$/, fr, "bite"],
      [/.[^aeiou][ai]ble$/, B, "fixable"],
      [/.[^aeiou]eable$/, B, "maleable"],
      [/.[ts]ive$/, B, "festive"],
      [/[a-z]-like$/, B, "woman-like"],
    ],
    h: [
      [/.[^aeiouf]ish$/, B, "cornish"],
      [/.v[iy]ch$/, pr, "..ovich"],
      [/^ug?h+$/, Xe, "ughh"],
      [/^uh[ -]?oh$/, Xe, "uhoh"],
      [/[a-z]-ish$/, B, "cartoon-ish"],
    ],
    i: [[/.[oau][wvl]ski$/, pr, "polish-male"]],
    k: [[/^(k){2}$/, Xe, "kkkk"]],
    l: [
      [/.[gl]ial$/, B, "familial"],
      [/.[^aeiou]ful$/, B, "fitful"],
      [/.[nrtumcd]al$/, B, "natal"],
      [/.[^aeiou][ei]al$/, B, "familial"],
    ],
    m: [
      [/.[^aeiou]ium$/, Ze, "magnesium"],
      [/[^aeiou]ism$/, Ze, "schism"],
      [/^[hu]m+$/, Xe, "hmm"],
      [/^\d+ ?[ap]m$/, "Date", "3am"],
    ],
    n: [
      [/.[lsrnpb]ian$/, B, "republican"],
      [/[^aeiou]ician$/, cs, "musician"],
      [/[aeiou][ktrp]in'$/, "Gerund", "cookin'"],
    ],
    o: [
      [/^no+$/, Xe, "noooo"],
      [/^(yo)+$/, Xe, "yoo"],
      [/^wo{2,}[pt]?$/, Xe, "woop"],
    ],
    r: [
      [/.[bdfklmst]ler$/, "Noun"],
      [/[aeiou][pns]er$/, Ze],
      [/[^i]fer$/, fr],
      [/.[^aeiou][ao]pher$/, cs],
      [/.[lk]er$/, "Noun"],
      [/.ier$/, "Comparative"],
    ],
    t: [
      [/.[di]est$/, "Superlative"],
      [/.[icldtgrv]ent$/, B],
      [/[aeiou].*ist$/, B],
      [/^[a-z]et$/, hs],
    ],
    s: [
      [/.[^aeiou]ises$/, mr],
      [/.[rln]ates$/, mr],
      [/.[^z]ens$/, hs],
      [/.[lstrn]us$/, Ze],
      [/.[aeiou]sks$/, mr],
      [/.[aeiou]kes$/, mr],
      [/[aeiou][^aeiou]is$/, Ze],
      [/[a-z]'s$/, ds],
      [/^yes+$/, Xe],
    ],
    v: [[/.[^aeiou][ai][kln]ov$/, pr]],
    y: [
      [/.[cts]hy$/, B],
      [/.[st]ty$/, B],
      [/.[tnl]ary$/, B],
      [/.[oe]ry$/, Ze],
      [/[rdntkbhs]ly$/, us],
      [/.(gg|bb|zz)ly$/, B],
      [/...lly$/, us],
      [/.[gk]y$/, B],
      [/[bszmp]{2}y$/, B],
      [/.[ai]my$/, B],
      [/[ea]{2}zy$/, B],
      [/.[^aeiou]ity$/, Ze],
    ],
  },
  oe = "Verb",
  V = "Noun",
  E0 = {
    leftTags: [
      ["Adjective", V],
      ["Possessive", V],
      ["Determiner", V],
      ["Adverb", oe],
      ["Pronoun", oe],
      ["Value", V],
      ["Ordinal", V],
      ["Modal", oe],
      ["Superlative", V],
      ["Demonym", V],
      ["Honorific", "Person"],
    ],
    leftWords: [
      ["i", oe],
      ["first", V],
      ["it", oe],
      ["there", oe],
      ["not", oe],
      ["because", V],
      ["if", V],
      ["but", V],
      ["who", oe],
      ["this", V],
      ["his", V],
      ["when", V],
      ["you", oe],
      ["very", "Adjective"],
      ["old", V],
      ["never", oe],
      ["before", V],
      ["a", V],
      ["the", V],
      ["been", oe],
    ],
    rightTags: [
      ["Copula", V],
      ["PastTense", V],
      ["Conjunction", V],
      ["Modal", V],
    ],
    rightWords: [
      ["there", oe],
      ["me", oe],
      ["man", "Adjective"],
      ["him", oe],
      ["it", oe],
      ["were", V],
      ["took", V],
      ["himself", oe],
      ["went", V],
      ["who", V],
      ["jr", "Person"],
    ],
  },
  Zt = {
    Comparative: {
      fwd: "3:ser,ier¦1er:h,t,f,l,n¦1r:e¦2er:ss,or,om",
      both: "3er:ver,ear,alm¦3ner:hin¦3ter:lat¦2mer:im¦2er:ng,rm,mb¦2ber:ib¦2ger:ig¦1er:w,p,k,d¦ier:y",
      rev: "1:tter,yer¦2:uer,ver,ffer,oner,eler,ller,iler,ster,cer,uler,sher,ener,gher,aner,adder,nter,eter,rter,hter,rner,fter¦3:oser,ooler,eafer,user,airer,bler,maler,tler,eater,uger,rger,ainer,urer,ealer,icher,pler,emner,icter,nser,iser¦4:arser,viner,ucher,rosser,somer,ndomer,moter,oother,uarer,hiter¦5:nuiner,esser,emier¦ar:urther",
      ex: "worse:bad¦better:good¦4er:fair,gray,poor¦1urther:far¦3ter:fat,hot,wet¦3der:mad,sad¦3er:shy,fun¦4der:glad¦:¦4r:cute,dire,fake,fine,free,lame,late,pale,rare,ripe,rude,safe,sore,tame,wide¦5r:eerie,stale",
    },
    Gerund: {
      fwd: "1:nning,tting,rring,pping,eing,mming,gging,dding,bbing,kking¦2:eking,oling,eling,eming¦3:velling,siting,uiting,fiting,loting,geting,ialing,celling¦4:graming",
      both: "1:aing,iing,fing,xing,ying,oing,hing,wing¦2:tzing,rping,izzing,bting,mning,sping,wling,rling,wding,rbing,uping,lming,wning,mping,oning,lting,mbing,lking,fting,hting,sking,gning,pting,cking,ening,nking,iling,eping,ering,rting,rming,cting,lping,ssing,nting,nding,lding,sting,rning,rding,rking¦3:belling,siping,toming,yaking,uaking,oaning,auling,ooping,aiding,naping,euring,tolling,uzzing,ganing,haning,ualing,halling,iasing,auding,ieting,ceting,ouling,voring,ralling,garing,joring,oaming,oaking,roring,nelling,ooring,uelling,eaming,ooding,eaping,eeting,ooting,ooming,xiting,keting,ooking,ulling,airing,oaring,biting,outing,oiting,earing,naling,oading,eeding,ouring,eaking,aiming,illing,oining,eaning,onging,ealing,aining,eading¦4:thoming,melling,aboring,ivoting,weating,dfilling,onoring,eriting,imiting,tialling,rgining,otoring,linging,winging,lleting,louding,spelling,mpelling,heating,feating,opelling,choring,welling,ymaking,ctoring,calling,peating,iloring,laiting,utoring,uditing,mmaking,loating,iciting,waiting,mbating,voiding,otalling,nsoring,nselling,ocusing,itoring,eloping¦5:rselling,umpeting,atrolling,treating,tselling,rpreting,pringing,ummeting,ossoming,elmaking,eselling,rediting,totyping,onmaking,rfeiting,ntrolling¦5e:chmaking,dkeeping,severing,erouting,ecreting,ephoning,uthoring,ravening,reathing,pediting,erfering,eotyping,fringing,entoring,ombining,ompeting¦4e:emaking,eething,twining,rruling,chuting,xciting,rseding,scoping,edoring,pinging,lunging,agining,craping,pleting,eleting,nciting,nfining,ncoding,tponing,ecoding,writing,esaling,nvening,gnoring,evoting,mpeding,rvening,dhering,mpiling,storing,nviting,ploring¦3e:tining,nuring,saking,miring,haling,ceding,xuding,rining,nuting,laring,caring,miling,riding,hoking,piring,lading,curing,uading,noting,taping,futing,paring,hading,loding,siring,guring,vading,voking,during,niting,laning,caping,luting,muting,ruding,ciding,juring,laming,caling,hining,uoting,liding,ciling,duling,tuting,puting,cuting,coring,uiding,tiring,turing,siding,rading,enging,haping,buting,lining,taking,anging,haring,uiring,coming,mining,moting,suring,viding,luding¦2e:tring,zling,uging,oging,gling,iging,vring,fling,lging,obing,psing,pling,ubing,cling,dling,wsing,iking,rsing,dging,kling,ysing,tling,rging,eging,nsing,uning,osing,uming,using,ibing,bling,aging,ising,asing,ating¦2ie:rlying¦1e:zing,uing,cing,ving",
      rev: "ying:ie¦1ing:se,ke,te,we,ne,re,de,pe,me,le,c,he¦2ing:ll,ng,dd,ee,ye,oe,rg,us¦2ning:un¦2ging:og,ag,ug,ig,eg¦2ming:um¦2bing:ub,ab,eb,ob¦3ning:lan,can,hin,pin,win¦3ring:cur,lur,tir,tar,pur,car¦3ing:ait,del,eel,fin,eat,oat,eem,lel,ool,ein,uin¦3ping:rop,rap,top,uip,wap,hip,hop,lap,rip,cap¦3ming:tem,wim,rim,kim,lim¦3ting:mat,cut,pot,lit,lot,hat,set,pit,put¦3ding:hed,bed,bid¦3king:rek¦3ling:cil,pel¦3bing:rib¦4ning:egin¦4ing:isit,ruit,ilot,nsit,dget,rkel,ival,rcel¦4ring:efer,nfer¦4ting:rmit,mmit,ysit,dmit,emit,bmit,tfit,gret¦4ling:evel,xcel,ivel¦4ding:hred¦5ing:arget,posit,rofit¦5ring:nsfer¦5ting:nsmit,orget,cquit¦5ling:ancel,istil",
      ex: "3:adding,eating,aiming,aiding,airing,outing,gassing,setting,getting,putting,cutting,winning,sitting,betting,mapping,tapping,letting,bidding,hitting,tanning,netting,popping,fitting,capping,lapping,barring,banning,vetting,topping,rotting,tipping,potting,wetting,pitting,dipping,budding,hemming,pinning,jetting,kidding,padding,podding,sipping,wedding,bedding,donning,warring,penning,gutting,cueing,wadding,petting,ripping,napping,matting,tinning,binning,dimming,hopping,mopping,nodding,panning,rapping,ridding,sinning¦4:selling,falling,calling,waiting,editing,telling,rolling,heating,boating,hanging,beating,coating,singing,tolling,felling,polling,discing,seating,voiding,gelling,yelling,baiting,reining,ruining,seeking,spanning,stepping,knitting,emitting,slipping,quitting,dialing,omitting,clipping,shutting,skinning,abutting,flipping,trotting,cramming,fretting,suiting¦5:bringing,treating,spelling,stalling,trolling,expelling,rivaling,wringing,deterring,singeing,befitting,refitting¦6:enrolling,distilling,scrolling,strolling,caucusing,travelling¦7:installing,redefining,stencilling,recharging,overeating,benefiting,unraveling,programing¦9:reprogramming¦is:being¦2e:using,aging,owing¦3e:making,taking,coming,noting,hiring,filing,coding,citing,doping,baking,coping,hoping,lading,caring,naming,voting,riding,mining,curing,lining,ruling,typing,boring,dining,firing,hiding,piling,taping,waning,baling,boning,faring,honing,wiping,luring,timing,wading,piping,fading,biting,zoning,daring,waking,gaming,raking,ceding,tiring,coking,wining,joking,paring,gaping,poking,pining,coring,liming,toting,roping,wiring,aching¦4e:writing,storing,eroding,framing,smoking,tasting,wasting,phoning,shaking,abiding,braking,flaking,pasting,priming,shoring,sloping,withing,hinging¦5e:defining,refining,renaming,swathing,fringing,reciting¦1ie:dying,tying,lying,vying¦7e:sunbathing",
    },
    Participle: {
      fwd: "1:mt¦2:llen¦3:iven,aken¦:ne¦y:in",
      both: "1:wn¦2:me,aten¦3:seen,bidden,isen¦4:roven,asten¦3l:pilt¦3d:uilt¦2e:itten¦1im:wum¦1eak:poken¦1ine:hone¦1ose:osen¦1in:gun¦1ake:woken¦ear:orn¦eal:olen¦eeze:ozen¦et:otten¦ink:unk¦ing:ung",
      rev: "2:un¦oken:eak¦ought:eek¦oven:eave¦1ne:o¦1own:ly¦1den:de¦1in:ay¦2t:am¦2n:ee¦3en:all¦4n:rive,sake,take¦5n:rgive",
      ex: "2:been¦3:seen,run¦4:given,taken¦5:shaken¦2eak:broken¦1ive:dove¦2y:flown¦3e:hidden,ridden¦1eek:sought¦1ake:woken¦1eave:woven",
    },
    PastTense: {
      fwd: "1:tted,wed,gged,nned,een,rred,pped,yed,bbed,oed,dded,rd,wn,mmed¦2:eed,nded,et,hted,st,oled,ut,emed,eled,lded,ken,rt,nked,apt,ant,eped,eked¦3:eared,eat,eaded,nelled,ealt,eeded,ooted,eaked,eaned,eeted,mited,bid,uit,ead,uited,ealed,geted,velled,ialed,belled¦4:ebuted,hined,comed¦y:ied¦ome:ame¦ear:ore¦ind:ound¦ing:ung,ang¦ep:pt¦ink:ank,unk¦ig:ug¦all:ell¦ee:aw¦ive:ave¦eeze:oze¦old:eld¦ave:ft¦ake:ook¦ell:old¦ite:ote¦ide:ode¦ine:one¦in:un,on¦eal:ole¦im:am¦ie:ay¦and:ood¦1ise:rose¦1eak:roke¦1ing:rought¦1ive:rove¦1el:elt¦1id:bade¦1et:got¦1y:aid¦1it:sat¦3e:lid¦3d:pent",
      both: "1:aed,fed,xed,hed¦2:sged,xted,wled,rped,lked,kied,lmed,lped,uped,bted,rbed,rked,wned,rled,mped,fted,mned,mbed,zzed,omed,ened,cked,gned,lted,sked,ued,zed,nted,ered,rted,rmed,ced,sted,rned,ssed,rded,pted,ved,cted¦3:cled,eined,siped,ooned,uked,ymed,jored,ouded,ioted,oaned,lged,asped,iged,mured,oided,eiled,yped,taled,moned,yled,lit,kled,oaked,gled,naled,fled,uined,oared,valled,koned,soned,aided,obed,ibed,meted,nicked,rored,micked,keted,vred,ooped,oaded,rited,aired,auled,filled,ouled,ooded,ceted,tolled,oited,bited,aped,tled,vored,dled,eamed,nsed,rsed,sited,owded,pled,sored,rged,osed,pelled,oured,psed,oated,loned,aimed,illed,eured,tred,ioned,celled,bled,wsed,ooked,oiled,itzed,iked,iased,onged,ased,ailed,uned,umed,ained,auded,nulled,ysed,eged,ised,aged,oined,ated,used,dged,doned¦4:ntied,efited,uaked,caded,fired,roped,halled,roked,himed,culed,tared,lared,tuted,uared,routed,pited,naked,miled,houted,helled,hared,cored,caled,tired,peated,futed,ciled,called,tined,moted,filed,sided,poned,iloted,honed,lleted,huted,ruled,cured,named,preted,vaded,sured,talled,haled,peded,gined,nited,uided,ramed,feited,laked,gured,ctored,unged,pired,cuted,voked,eloped,ralled,rined,coded,icited,vided,uaded,voted,mined,sired,noted,lined,nselled,luted,jured,fided,puted,piled,pared,olored,cided,hoked,enged,tured,geoned,cotted,lamed,uiled,waited,udited,anged,luded,mired,uired,raded¦5:modelled,izzled,eleted,umpeted,ailored,rseded,treated,eduled,ecited,rammed,eceded,atrolled,nitored,basted,twined,itialled,ncited,gnored,ploded,xcited,nrolled,namelled,plored,efeated,redited,ntrolled,nfined,pleted,llided,lcined,eathed,ibuted,lloted,dhered,cceded¦3ad:sled¦2aw:drew¦2ot:hot¦2ke:made¦2ow:hrew,grew¦2ose:hose¦2d:ilt¦2in:egan¦1un:ran¦1ink:hought¦1ick:tuck¦1ike:ruck¦1eak:poke,nuck¦1it:pat¦1o:did¦1ow:new¦1ake:woke¦go:went",
      rev: "3:rst,hed,hut,cut,set¦4:tbid¦5:dcast,eread,pread,erbid¦ought:uy,eek¦1ied:ny,ly,dy,ry,fy,py,vy,by,ty,cy¦1ung:ling,ting,wing¦1pt:eep¦1ank:rink¦1ore:bear,wear¦1ave:give¦1oze:reeze¦1ound:rind,wind¦1ook:take,hake¦1aw:see¦1old:sell¦1ote:rite¦1ole:teal¦1unk:tink¦1am:wim¦1ay:lie¦1ood:tand¦1eld:hold¦2d:he,ge,re,le,leed,ne,reed,be,ye,lee,pe,we¦2ed:dd,oy,or,ey,gg,rr,us,ew,to¦2ame:ecome,rcome¦2ped:ap¦2ged:ag,og,ug,eg¦2bed:ub,ab,ib,ob¦2lt:neel¦2id:pay¦2ang:pring¦2ove:trive¦2med:um¦2ode:rride¦2at:ysit¦3ted:mit,hat,mat,lat,pot,rot,bat¦3ed:low,end,tow,und,ond,eem,lay,cho,dow,xit,eld,ald,uld,law,lel,eat,oll,ray,ank,fin,oam,out,how,iek,tay,haw,ait,vet,say,cay,bow¦3d:ste,ede,ode,ete,ree,ude,ame,oke,ote,ime,ute,ade¦3red:lur,cur,pur,car¦3ped:hop,rop,uip,rip,lip,tep,top¦3ded:bed,rod,kid¦3ade:orbid¦3led:uel¦3ned:lan,can,kin,pan,tun¦3med:rim,lim¦4ted:quit,llot¦4ed:pear,rrow,rand,lean,mand,anel,pand,reet,link,abel,evel,imit,ceed,ruit,mind,peal,veal,hool,head,pell,well,mell,uell,band,hear,weak¦4led:nnel,qual,ebel,ivel¦4red:nfer,efer,sfer¦4n:sake,trew¦4d:ntee¦4ded:hred¦4ned:rpin¦5ed:light,nceal,right,ndear,arget,hread,eight,rtial,eboot¦5d:edite,nvite¦5ted:egret¦5led:ravel",
      ex: "2:been,upped¦3:added,aged,aided,aimed,aired,bid,died,dyed,egged,erred,eyed,fit,gassed,hit,lied,owed,pent,pied,tied,used,vied,oiled,outed,banned,barred,bet,canned,cut,dipped,donned,ended,feed,inked,jarred,let,manned,mowed,netted,padded,panned,pitted,popped,potted,put,set,sewn,sowed,tanned,tipped,topped,vowed,weed,bowed,jammed,binned,dimmed,hopped,mopped,nodded,pinned,rigged,sinned,towed,vetted¦4:ached,baked,baled,boned,bored,called,caned,cared,ceded,cited,coded,cored,cubed,cured,dared,dined,edited,exited,faked,fared,filed,fined,fired,fuelled,gamed,gelled,hired,hoped,joked,lined,mined,named,noted,piled,poked,polled,pored,pulled,reaped,roamed,rolled,ruled,seated,shed,sided,timed,tolled,toned,voted,waited,walled,waned,winged,wiped,wired,zoned,yelled,tamed,lubed,roped,faded,mired,caked,honed,banged,culled,heated,raked,welled,banded,beat,cast,cooled,cost,dealt,feared,folded,footed,handed,headed,heard,hurt,knitted,landed,leaked,leapt,linked,meant,minded,molded,neared,needed,peaked,plodded,plotted,pooled,quit,read,rooted,sealed,seeded,seeped,shipped,shunned,skimmed,slammed,sparred,stemmed,stirred,suited,thinned,twinned,swayed,winked,dialed,abutted,blotted,fretted,healed,heeded,peeled,reeled¦5:basted,cheated,equalled,eroded,exiled,focused,opined,pleated,primed,quoted,scouted,shored,sloped,smoked,sniped,spelled,spouted,routed,staked,stored,swelled,tasted,treated,wasted,smelled,dwelled,honored,prided,quelled,eloped,scared,coveted,sweated,breaded,cleared,debuted,deterred,freaked,modeled,pleaded,rebutted,speeded¦6:anchored,defined,endured,impaled,invited,refined,revered,strolled,cringed,recast,thrust,unfolded¦7:authored,combined,competed,conceded,convened,excreted,extruded,redefined,restored,secreted,rescinded,welcomed¦8:expedited,infringed¦9:interfered,intervened,persevered¦10:contravened¦eat:ate¦is:was¦go:went¦are:were¦3d:bent,lent,rent,sent¦3e:bit,fled,hid,lost¦3ed:bled,bred¦2ow:blew,grew¦1uy:bought¦2tch:caught¦1o:did¦1ive:dove,gave¦2aw:drew¦2ed:fed¦2y:flew,laid,paid,said¦1ight:fought¦1et:got¦2ve:had¦1ang:hung¦2ad:led¦2ght:lit¦2ke:made¦2et:met¦1un:ran¦1ise:rose¦1it:sat¦1eek:sought¦1each:taught¦1ake:woke,took¦1eave:wove¦2ise:arose¦1ear:bore,tore,wore¦1ind:bound,found,wound¦2eak:broke¦2ing:brought,wrung¦1ome:came¦2ive:drove¦1ig:dug¦1all:fell¦2el:felt¦4et:forgot¦1old:held¦2ave:left¦1ing:rang,sang¦1ide:rode¦1ink:sank¦1ee:saw¦2ine:shone¦4e:slid¦1ell:sold,told¦4d:spent¦2in:spun¦1in:won",
    },
    PresentTense: {
      fwd: "1:oes¦1ve:as",
      both: "1:xes¦2:zzes,ches,shes,sses¦3:iases¦2y:llies,plies¦1y:cies,bies,ties,vies,nies,pies,dies,ries,fies¦:s",
      rev: "1ies:ly¦2es:us,go,do¦3es:cho,eto",
      ex: "2:does,goes¦3:gasses¦5:focuses¦is:are¦3y:relies¦2y:flies¦2ve:has",
    },
    Superlative: {
      fwd: "1st:e¦1est:l,m,f,s¦1iest:cey¦2est:or,ir¦3est:ver",
      both: "4:east¦5:hwest¦5lest:erful¦4est:weet,lgar,tter,oung¦4most:uter¦3est:ger,der,rey,iet,ong,ear¦3test:lat¦3most:ner¦2est:pt,ft,nt,ct,rt,ht¦2test:it¦2gest:ig¦1est:b,k,n,p,h,d,w¦iest:y",
      rev: "1:ttest,nnest,yest¦2:sest,stest,rmest,cest,vest,lmest,olest,ilest,ulest,ssest,imest,uest¦3:rgest,eatest,oorest,plest,allest,urest,iefest,uelest,blest,ugest,amest,yalest,ealest,illest,tlest,itest¦4:cerest,eriest,somest,rmalest,ndomest,motest,uarest,tiffest¦5:leverest,rangest¦ar:urthest¦3ey:riciest",
      ex: "best:good¦worst:bad¦5est:great¦4est:fast,full,fair,dull¦3test:hot,wet,fat¦4nest:thin¦1urthest:far¦3est:gay,shy,ill¦4test:neat¦4st:late,wide,fine,safe,cute,fake,pale,rare,rude,sore,ripe,dire¦6st:severe",
    },
    AdjToNoun: {
      fwd: "1:tistic,eable,lful,sful,ting,tty¦2:onate,rtable,geous,ced,seful,ctful¦3:ortive,ented¦arity:ear¦y:etic¦fulness:begone¦1ity:re¦1y:tiful,gic¦2ity:ile,imous,ilous,ime¦2ion:ated¦2eness:iving¦2y:trious¦2ation:iring¦2tion:vant¦3ion:ect¦3ce:mant,mantic¦3tion:irable¦3y:est,estic¦3m:mistic,listic¦3ess:ning¦4n:utious¦4on:rative,native,vative,ective¦4ce:erant",
      both: "1:king,wing¦2:alous,ltuous,oyful,rdous¦3:gorous,ectable,werful,amatic¦4:oised,usical,agical,raceful,ocused,lined,ightful¦5ness:stful,lding,itous,nuous,ulous,otous,nable,gious,ayful,rvous,ntous,lsive,peful,entle,ciful,osive,leful,isive,ncise,reful,mious¦5ty:ivacious¦5ties:ubtle¦5ce:ilient,adiant,atient¦5cy:icient¦5sm:gmatic¦5on:sessive,dictive¦5ity:pular,sonal,eative,entic¦5sity:uminous¦5ism:conic¦5nce:mperate¦5ility:mitable¦5ment:xcited¦5n:bitious¦4cy:brant,etent,curate¦4ility:erable,acable,icable,ptable¦4ty:nacious,aive,oyal,dacious¦4n:icious¦4ce:vient,erent,stent,ndent,dient,quent,ident¦4ness:adic,ound,hing,pant,sant,oing,oist,tute¦4icity:imple¦4ment:fined,mused¦4ism:otic¦4ry:dantic¦4ity:tund,eral¦4edness:hand¦4on:uitive¦4lity:pitable¦4sm:eroic,namic¦4sity:nerous¦3th:arm¦3ility:pable,bable,dable,iable¦3cy:hant,nant,icate¦3ness:red,hin,nse,ict,iet,ite,oud,ind,ied,rce¦3ion:lute¦3ity:ual,gal,volous,ial¦3ce:sent,fensive,lant,gant,gent,lent,dant¦3on:asive¦3m:fist,sistic,iastic¦3y:terious,xurious,ronic,tastic¦3ur:amorous¦3e:tunate¦3ation:mined¦3sy:rteous¦3ty:ain¦3ry:ave¦3ment:azed¦2ness:de,on,ue,rn,ur,ft,rp,pe,om,ge,rd,od,ay,ss,er,ll,oy,ap,ht,ld,ad,rt¦2inousness:umous¦2ity:neous,ene,id,ane¦2cy:bate,late¦2ation:ized¦2ility:oble,ible¦2y:odic¦2e:oving,aring¦2s:ost¦2itude:pt¦2dom:ee¦2ance:uring¦2tion:reet¦2ion:oted¦2sion:ending¦2liness:an¦2or:rdent¦1th:ung¦1e:uable¦1ness:w,h,k,f¦1ility:mble¦1or:vent¦1ement:ging¦1tiquity:ncient¦1ment:hed¦verty:or¦ength:ong¦eat:ot¦pth:ep¦iness:y",
      rev: "",
      ex: "5:forceful,humorous¦8:charismatic¦13:understanding¦5ity:active¦11ness:adventurous,inquisitive,resourceful¦8on:aggressive,automatic,perceptive¦7ness:amorous,fatuous,furtive,ominous,serious¦5ness:ample,sweet¦12ness:apprehensive,cantankerous,contemptuous,ostentatious¦13ness:argumentative,conscientious¦9ness:assertive,facetious,imperious,inventive,oblivious,rapacious,receptive,seditious,whimsical¦10ness:attractive,expressive,impressive,loquacious,salubrious,thoughtful¦3edom:boring¦4ness:calm,fast,keen,tame¦8ness:cheerful,gracious,specious,spurious,timorous,unctuous¦5sity:curious¦9ion:deliberate¦8ion:desperate¦6e:expensive¦7ce:fragrant¦3y:furious¦9ility:ineluctable¦6ism:mystical¦8ity:physical,proactive,sensitive,vertical¦5cy:pliant¦7ity:positive¦9ity:practical¦12ism:professional¦6ce:prudent¦3ness:red¦6cy:vagrant¦3dom:wise",
    },
  },
  H0 = function (e, t = {}) {
    return t.hasOwnProperty(e) ? t[e] : null;
  },
  z0 = function (e, t = []) {
    for (let n = 0; n < t.length; n += 1) if (e.endsWith(t[n])) return e;
    return null;
  },
  F0 = function (e, t, n = {}) {
    t = t || {};
    let r = e.length - 1;
    for (let a = r; a >= 1; a -= 1) {
      let i = e.length - a,
        o = e.substring(i, e.length);
      if (t.hasOwnProperty(o) === !0) return e.slice(0, i) + t[o];
      if (n.hasOwnProperty(o) === !0) return e.slice(0, i) + n[o];
    }
    return t.hasOwnProperty("")
      ? (e += t[""])
      : n.hasOwnProperty("")
        ? (e += n[""])
        : null;
  },
  Pe = function (e = "", t = {}) {
    let n = H0(e, t.ex);
    return (
      (n = n || z0(e, t.same)),
      (n = n || F0(e, t.fwd, t.both)),
      (n = n || e),
      n
    );
  },
  fs = function (e) {
    return Object.entries(e).reduce((t, n) => ((t[n[1]] = n[0]), t), {});
  },
  Cn = function (e = {}) {
    return { reversed: !0, both: fs(e.both), ex: fs(e.ex), fwd: e.rev || {} };
  },
  ms = /^([0-9]+)/,
  V0 = function (e) {
    let t = {};
    return (
      e.split("¦").forEach((n) => {
        let [r, a] = n.split(":");
        ((a = (a || "").split(",")),
          a.forEach((i) => {
            t[i] = r;
          }));
      }),
      t
    );
  },
  G0 = function (e = "", t = "") {
    t = String(t);
    let n = t.match(ms);
    if (n === null) return t;
    let r = Number(n[1]) || 0;
    return e.substring(0, r) + t.replace(ms, "");
  },
  gr = function (e) {
    let t = V0(e);
    return Object.keys(t).reduce((n, r) => ((n[r] = G0(r, t[r])), n), {});
  },
  Xt = function (e = {}) {
    return (
      typeof e == "string" && (e = JSON.parse(e)),
      (e.fwd = gr(e.fwd || "")),
      (e.both = gr(e.both || "")),
      (e.rev = gr(e.rev || "")),
      (e.ex = gr(e.ex || "")),
      e
    );
  },
  Uu = Xt(Zt.PastTense),
  Ru = Xt(Zt.PresentTense),
  Yu = Xt(Zt.Gerund),
  Qu = Xt(Zt.Participle),
  S0 = Cn(Uu),
  M0 = Cn(Ru),
  B0 = Cn(Yu),
  L0 = Cn(Qu),
  Zu = Xt(Zt.Comparative),
  Xu = Xt(Zt.Superlative),
  W0 = Cn(Zu),
  q0 = Cn(Xu),
  K0 = Xt(Zt.AdjToNoun),
  ec = {
    fromPast: Uu,
    fromPresent: Ru,
    fromGerund: Yu,
    fromParticiple: Qu,
    toPast: S0,
    toPresent: M0,
    toGerund: B0,
    toParticiple: L0,
    toComparative: Zu,
    toSuperlative: Xu,
    fromComparative: W0,
    fromSuperlative: q0,
    adjToNoun: K0,
  },
  J0 = [
    [/^[\w.]+@[\w.]+\.[a-z]{2,3}$/, "Email"],
    [/^(https?:\/\/|www\.)+\w+\.[a-z]{2,3}/, "Url", "http.."],
    [
      /^[a-z0-9./].+\.(com|net|gov|org|ly|edu|info|biz|dev|ru|jp|de|in|uk|br|io|ai)/,
      "Url",
      ".com",
    ],
    [/^[PMCE]ST$/, "Timezone", "EST"],
    [/^ma?c'[a-z]{3}/, "LastName", "mc'neil"],
    [/^o'[a-z]{3}/, "LastName", "o'connor"],
    [/^ma?cd[aeiou][a-z]{3}/, "LastName", "mcdonald"],
    [/^(lol)+[sz]$/, "Expression", "lol"],
    [/^wo{2,}a*h?$/, "Expression", "wooah"],
    [/^(hee?){2,}h?$/, "Expression", "hehe"],
    [/^(un|de|re)\\-[a-z\u00C0-\u00FF]{2}/, "Verb", "un-vite"],
    [/^(m|k|cm|km)\/(s|h|hr)$/, "Unit", "5 k/m"],
    [/^(ug|ng|mg)\/(l|m3|ft3)$/, "Unit", "ug/L"],
    [new RegExp("[^:/]\\/\\p{Letter}", "u"), "SlashedTerm", "love/hate"],
  ],
  _0 = [
    [new RegExp("^#[\\p{Number}_]*\\p{Letter}", "u"), "HashTag"],
    [/^@\w{2,}$/, "AtMention"],
    [/^([A-Z]\.){2}[A-Z]?/i, ["Acronym", "Noun"], "F.B.I"],
    [/.{3}[lkmnp]in['‘’‛‵′`´]$/, "Gerund", "chillin'"],
    [/.{4}s['‘’‛‵′`´]$/, "Possessive", "flanders'"],
    [
      /^[\p{Emoji_Presentation}\p{Extended_Pictographic}]/u,
      "Emoji",
      "emoji-class",
    ],
  ],
  U0 = [
    [/^@1?[0-9](am|pm)$/i, "Time", "3pm"],
    [/^@1?[0-9]:[0-9]{2}(am|pm)?$/i, "Time", "3:30pm"],
    [/^'[0-9]{2}$/, "Year"],
    [/^[012]?[0-9](:[0-5][0-9])(:[0-5][0-9])$/, "Time", "3:12:31"],
    [/^[012]?[0-9](:[0-5][0-9])?(:[0-5][0-9])? ?(am|pm)$/i, "Time", "1:12pm"],
    [
      /^[012]?[0-9](:[0-5][0-9])(:[0-5][0-9])? ?(am|pm)?$/i,
      "Time",
      "1:12:31pm",
    ],
    [/^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}/i, "Date", "iso-date"],
    [/^[0-9]{1,4}-[0-9]{1,2}-[0-9]{1,4}$/, "Date", "iso-dash"],
    [/^[0-9]{1,4}\/[0-9]{1,2}\/([0-9]{4}|[0-9]{2})$/, "Date", "iso-slash"],
    [/^[0-9]{1,4}\.[0-9]{1,2}\.[0-9]{1,4}$/, "Date", "iso-dot"],
    [/^[0-9]{1,4}-[a-z]{2,9}-[0-9]{1,4}$/i, "Date", "12-dec-2019"],
    [/^utc ?[+-]?[0-9]+$/, "Timezone", "utc-9"],
    [/^(gmt|utc)[+-][0-9]{1,2}$/i, "Timezone", "gmt-3"],
    [/^[0-9]{3}-[0-9]{4}$/, "PhoneNumber", "421-0029"],
    [
      /^(\+?[0-9][ -])?[0-9]{3}[ -]?[0-9]{3}-[0-9]{4}$/,
      "PhoneNumber",
      "1-800-",
    ],
    [
      new RegExp(
        "^[-+]?\\p{Currency_Symbol}[-+]?[0-9]+(,[0-9]{3})*(\\.[0-9]+)?([kmb]|bn)?\\+?$",
        "u",
      ),
      ["Money", "Value"],
      "$5.30",
    ],
    [
      new RegExp(
        "^[-+]?[0-9]+(,[0-9]{3})*(\\.[0-9]+)?\\p{Currency_Symbol}\\+?$",
        "u",
      ),
      ["Money", "Value"],
      "5.30£",
    ],
    [
      /^[-+]?[$£]?[0-9]([0-9,.])+(usd|eur|jpy|gbp|cad|aud|chf|cny|hkd|nzd|kr|rub)$/i,
      ["Money", "Value"],
      "$400usd",
    ],
    [
      /^[-+]?[0-9]+(,[0-9]{3})*(\.[0-9]+)?\+?$/,
      ["Cardinal", "NumericValue"],
      "5,999",
    ],
    [
      /^[-+]?[0-9]+(,[0-9]{3})*(\.[0-9]+)?(st|nd|rd|r?th)$/,
      ["Ordinal", "NumericValue"],
      "53rd",
    ],
    [/^\.[0-9]+\+?$/, ["Cardinal", "NumericValue"], ".73th"],
    [
      /^[-+]?[0-9]+(,[0-9]{3})*(\.[0-9]+)?%\+?$/,
      ["Percent", "Cardinal", "NumericValue"],
      "-4%",
    ],
    [/^\.[0-9]+%$/, ["Percent", "Cardinal", "NumericValue"], ".3%"],
    [
      /^[0-9]{1,4}\/[0-9]{1,4}(st|nd|rd|th)?s?$/,
      ["Fraction", "NumericValue"],
      "2/3rds",
    ],
    [
      /^[0-9.]{1,3}[a-z]{0,2}[-–—][0-9]{1,3}[a-z]{0,2}$/,
      ["Value", "NumberRange"],
      "3-4",
    ],
    [
      /^[0-9]{1,2}(:[0-9][0-9])?(am|pm)? ?[-–—] ?[0-9]{1,2}(:[0-9][0-9])?(am|pm)$/,
      ["Time", "NumberRange"],
      "3-4pm",
    ],
    [/^[0-9.]+([a-z°]{1,4})$/, "NumericValue", "9km"],
  ],
  R0 = [
    "academy",
    "administration",
    "agence",
    "agences",
    "agencies",
    "agency",
    "airlines",
    "airways",
    "army",
    "assoc",
    "associates",
    "association",
    "assurance",
    "authority",
    "autorite",
    "aviation",
    "bank",
    "banque",
    "board",
    "boys",
    "brands",
    "brewery",
    "brotherhood",
    "brothers",
    "bureau",
    "cafe",
    "co",
    "caisse",
    "capital",
    "care",
    "cathedral",
    "center",
    "centre",
    "chemicals",
    "choir",
    "chronicle",
    "church",
    "circus",
    "clinic",
    "clinique",
    "club",
    "co",
    "coalition",
    "coffee",
    "collective",
    "college",
    "commission",
    "committee",
    "communications",
    "community",
    "company",
    "comprehensive",
    "computers",
    "confederation",
    "conference",
    "conseil",
    "consulting",
    "containers",
    "corporation",
    "corps",
    "corp",
    "council",
    "crew",
    "data",
    "departement",
    "department",
    "departments",
    "design",
    "development",
    "directorate",
    "division",
    "drilling",
    "education",
    "eglise",
    "electric",
    "electricity",
    "energy",
    "ensemble",
    "enterprise",
    "enterprises",
    "entertainment",
    "estate",
    "etat",
    "faculty",
    "faction",
    "federation",
    "financial",
    "fm",
    "foundation",
    "fund",
    "gas",
    "gazette",
    "girls",
    "government",
    "group",
    "guild",
    "herald",
    "holdings",
    "hospital",
    "hotel",
    "hotels",
    "inc",
    "industries",
    "institut",
    "institute",
    "institutes",
    "insurance",
    "international",
    "interstate",
    "investment",
    "investments",
    "investors",
    "journal",
    "laboratory",
    "labs",
    "llc",
    "ltd",
    "limited",
    "machines",
    "magazine",
    "management",
    "marine",
    "marketing",
    "markets",
    "media",
    "memorial",
    "ministere",
    "ministry",
    "military",
    "mobile",
    "motor",
    "motors",
    "musee",
    "museum",
    "news",
    "observatory",
    "office",
    "oil",
    "optical",
    "orchestra",
    "organization",
    "partners",
    "partnership",
    "petrol",
    "petroleum",
    "pharmacare",
    "pharmaceutical",
    "pharmaceuticals",
    "pizza",
    "plc",
    "police",
    "politburo",
    "polytechnic",
    "post",
    "power",
    "press",
    "productions",
    "quartet",
    "radio",
    "reserve",
    "resources",
    "restaurant",
    "restaurants",
    "savings",
    "school",
    "securities",
    "service",
    "services",
    "societe",
    "subsidiary",
    "society",
    "sons",
    "subcommittee",
    "syndicat",
    "systems",
    "telecommunications",
    "telegraph",
    "television",
    "times",
    "tribunal",
    "tv",
    "union",
    "university",
    "utilities",
    "workers",
  ].reduce((e, t) => ((e[t] = !0), e), {}),
  Y0 = [
    "atoll",
    "basin",
    "bay",
    "beach",
    "bluff",
    "bog",
    "camp",
    "canyon",
    "canyons",
    "cape",
    "cave",
    "caves",
    "cliffs",
    "coast",
    "cove",
    "coves",
    "crater",
    "crossing",
    "creek",
    "desert",
    "dune",
    "dunes",
    "downs",
    "estates",
    "escarpment",
    "estuary",
    "falls",
    "fjord",
    "fjords",
    "forest",
    "forests",
    "glacier",
    "gorge",
    "gorges",
    "grove",
    "gulf",
    "gully",
    "highland",
    "heights",
    "hollow",
    "hill",
    "hills",
    "inlet",
    "island",
    "islands",
    "isthmus",
    "junction",
    "knoll",
    "lagoon",
    "lake",
    "lakeshore",
    "marsh",
    "marshes",
    "mount",
    "mountain",
    "mountains",
    "narrows",
    "peninsula",
    "plains",
    "plateau",
    "pond",
    "rapids",
    "ravine",
    "reef",
    "reefs",
    "ridge",
    "river",
    "rivers",
    "sandhill",
    "shoal",
    "shore",
    "shoreline",
    "shores",
    "strait",
    "straits",
    "springs",
    "stream",
    "swamp",
    "tombolo",
    "trail",
    "trails",
    "trench",
    "valley",
    "vallies",
    "village",
    "volcano",
    "waterfall",
    "watershed",
    "wetland",
    "woods",
    "acres",
    "burough",
    "county",
    "district",
    "municipality",
    "prefecture",
    "province",
    "region",
    "reservation",
    "state",
    "territory",
    "borough",
    "metropolis",
    "downtown",
    "uptown",
    "midtown",
    "city",
    "town",
    "township",
    "hamlet",
    "country",
    "kingdom",
    "enclave",
    "neighbourhood",
    "neighborhood",
    "kingdom",
    "ward",
    "zone",
    "airport",
    "amphitheater",
    "arch",
    "arena",
    "auditorium",
    "bar",
    "barn",
    "basilica",
    "battlefield",
    "bridge",
    "building",
    "castle",
    "centre",
    "coliseum",
    "cineplex",
    "complex",
    "dam",
    "farm",
    "field",
    "fort",
    "garden",
    "gardens",
    "gymnasium",
    "hall",
    "house",
    "levee",
    "library",
    "manor",
    "memorial",
    "monument",
    "museum",
    "gallery",
    "palace",
    "pillar",
    "pits",
    "plantation",
    "playhouse",
    "quarry",
    "sportsfield",
    "sportsplex",
    "stadium",
    "terrace",
    "terraces",
    "theater",
    "tower",
    "park",
    "parks",
    "site",
    "ranch",
    "raceway",
    "sportsplex",
    "ave",
    "st",
    "street",
    "rd",
    "road",
    "lane",
    "landing",
    "crescent",
    "cr",
    "way",
    "tr",
    "terrace",
    "avenue",
  ].reduce((e, t) => ((e[t] = !0), e), {}),
  yr = [
    [/([^v])ies$/i, "$1y"],
    [/(ise)s$/i, "$1"],
    [/(kn|[^o]l|w)ives$/i, "$1ife"],
    [
      /^((?:ca|e|ha|(?:our|them|your)?se|she|wo)l|lea|loa|shea|thie)ves$/i,
      "$1f",
    ],
    [/^(dwar|handkerchie|hoo|scar|whar)ves$/i, "$1f"],
    [/(antenn|formul|nebul|vertebr|vit)ae$/i, "$1a"],
    [/(octop|vir|radi|nucle|fung|cact|stimul)(i)$/i, "$1us"],
    [/(buffal|tomat|tornad)(oes)$/i, "$1o"],
    [/(ause)s$/i, "$1"],
    [/(ease)s$/i, "$1"],
    [/(ious)es$/i, "$1"],
    [/(ouse)s$/i, "$1"],
    [/(ose)s$/i, "$1"],
    [/(..ase)s$/i, "$1"],
    [/(..[aeiu]s)es$/i, "$1"],
    [/(vert|ind|cort)(ices)$/i, "$1ex"],
    [/(matr|append)(ices)$/i, "$1ix"],
    [/([xo]|ch|ss|sh)es$/i, "$1"],
    [/men$/i, "man"],
    [/(n)ews$/i, "$1ews"],
    [/([ti])a$/i, "$1um"],
    [/([^aeiouy]|qu)ies$/i, "$1y"],
    [/(s)eries$/i, "$1eries"],
    [/(m)ovies$/i, "$1ovie"],
    [/(cris|ax|test)es$/i, "$1is"],
    [/(alias|status)es$/i, "$1"],
    [/(ss)$/i, "$1"],
    [/(ic)s$/i, "$1"],
    [/s$/i, ""],
  ],
  Q0 = function (e) {
    return Object.keys(e).reduce((t, n) => ((t[e[n]] = n), t), {});
  },
  tc = function (e, t) {
    const { irregularPlurals: n } = t.two;
    let r = Q0(n);
    if (r.hasOwnProperty(e)) return r[e];
    for (let a = 0; a < yr.length; a++)
      if (yr[a][0].test(e) === !0)
        return ((e = e.replace(yr[a][0], yr[a][1])), e);
    return e;
  },
  Z0 = function (e, t) {
    let n = [e],
      r = sa(e, t);
    r !== e && n.push(r);
    let a = tc(e, t);
    return (a !== e && n.push(a), n);
  },
  X0 = { toPlural: sa, toSingular: tc, all: Z0 };
let qt = {
  Gerund: ["ing"],
  Actor: ["erer"],
  Infinitive: [
    "ate",
    "ize",
    "tion",
    "rify",
    "then",
    "ress",
    "ify",
    "age",
    "nce",
    "ect",
    "ise",
    "ine",
    "ish",
    "ace",
    "ash",
    "ure",
    "tch",
    "end",
    "ack",
    "and",
    "ute",
    "ade",
    "ock",
    "ite",
    "ase",
    "ose",
    "use",
    "ive",
    "int",
    "nge",
    "lay",
    "est",
    "ain",
    "ant",
    "ent",
    "eed",
    "er",
    "le",
    "unk",
    "ung",
    "upt",
    "en",
  ],
  PastTense: ["ept", "ed", "lt", "nt", "ew", "ld"],
  PresentTense: [
    "rks",
    "cks",
    "nks",
    "ngs",
    "mps",
    "tes",
    "zes",
    "ers",
    "les",
    "acks",
    "ends",
    "ands",
    "ocks",
    "lays",
    "eads",
    "lls",
    "els",
    "ils",
    "ows",
    "nds",
    "ays",
    "ams",
    "ars",
    "ops",
    "ffs",
    "als",
    "urs",
    "lds",
    "ews",
    "ips",
    "es",
    "ts",
    "ns",
  ],
  Participle: ["ken", "wn"],
};
qt = Object.keys(qt).reduce(
  (e, t) => (qt[t].forEach((n) => (e[n] = t)), e),
  {},
);
const nc = function (e) {
    let t = e.substring(e.length - 3);
    if (qt.hasOwnProperty(t) === !0) return qt[t];
    let n = e.substring(e.length - 2);
    return qt.hasOwnProperty(n) === !0
      ? qt[n]
      : e.substring(e.length - 1) === "s"
        ? "PresentTense"
        : null;
  },
  ey = function (e, t) {
    let n = "",
      r = {};
    t.one && t.one.prefixes && (r = t.one.prefixes);
    let [a, i] = e.split(/ /);
    return (
      i && r[a] === !0 && ((n = a), (a = i), (i = "")),
      { prefix: n, verb: a, particle: i }
    );
  },
  ps = {
    are: "be",
    were: "be",
    been: "be",
    is: "be",
    am: "be",
    was: "be",
    be: "be",
    being: "be",
  },
  mi = function (e, t, n) {
    const {
      fromPast: r,
      fromPresent: a,
      fromGerund: i,
      fromParticiple: o,
    } = t.two.models;
    let { prefix: s, verb: l, particle: u } = ey(e, t),
      c = "";
    if ((n || (n = nc(e)), ps.hasOwnProperty(e))) c = ps[e];
    else if (n === "Participle") c = Pe(l, o);
    else if (n === "PastTense") c = Pe(l, r);
    else if (n === "PresentTense") c = Pe(l, a);
    else if (n === "Gerund") c = Pe(l, i);
    else return e;
    return (u && (c += " " + u), s && (c = s + " " + c), c);
  },
  ty = (e) => (/ /.test(e) ? e.split(/ /) : [e, ""]),
  Qi = function (e, t) {
    const {
      toPast: n,
      toPresent: r,
      toGerund: a,
      toParticiple: i,
    } = t.two.models;
    if (e === "be")
      return {
        Infinitive: e,
        Gerund: "being",
        PastTense: "was",
        PresentTense: "is",
      };
    let [o, s] = ty(e),
      l = {
        Infinitive: o,
        PastTense: Pe(o, n),
        PresentTense: Pe(o, r),
        Gerund: Pe(o, a),
        FutureTense: "will " + o,
      },
      u = Pe(o, i);
    if (u !== e && u !== l.PastTense) {
      let c = t.one.lexicon || {};
      (c[u] === "Participle" || c[u] === "Adjective") &&
        (e === "play" && (u = "played"), (l.Participle = u));
    }
    return (
      s &&
        Object.keys(l).forEach((c) => {
          l[c] += " " + s;
        }),
      l
    );
  },
  ny = function (e, t) {
    let n = Qi(e, t);
    return (delete n.FutureTense, Object.values(n).filter((r) => r));
  },
  ry = { toInfinitive: mi, conjugate: Qi, all: ny },
  Zi = function (e, t) {
    const n = t.two.models.toSuperlative;
    return Pe(e, n);
  },
  Xi = function (e, t) {
    const n = t.two.models.toComparative;
    return Pe(e, n);
  },
  ay = function (e, t) {
    const n = t.two.models.fromComparative;
    return Pe(e, n);
  },
  iy = function (e, t) {
    const n = t.two.models.fromSuperlative;
    return Pe(e, n);
  },
  oy = function (e, t) {
    const n = t.two.models.adjToNoun;
    return Pe(e, n);
  },
  rc = function (e = "", t = []) {
    const n = e.length;
    let r = n <= 6 ? n - 1 : 6;
    for (let a = r; a >= 1; a -= 1) {
      let i = e.substring(n - a, e.length);
      if (t[i.length].hasOwnProperty(i) === !0) {
        let o = e.slice(0, n - a),
          s = t[i.length][i];
        return o + s;
      }
    }
    return null;
  },
  D = "ically",
  sy = new Set([
    "analyt" + D,
    "chem" + D,
    "class" + D,
    "clin" + D,
    "crit" + D,
    "ecolog" + D,
    "electr" + D,
    "empir" + D,
    "frant" + D,
    "grammat" + D,
    "ident" + D,
    "ideolog" + D,
    "log" + D,
    "mag" + D,
    "mathemat" + D,
    "mechan" + D,
    "med" + D,
    "method" + D,
    "method" + D,
    "mus" + D,
    "phys" + D,
    "phys" + D,
    "polit" + D,
    "pract" + D,
    "rad" + D,
    "satir" + D,
    "statist" + D,
    "techn" + D,
    "technolog" + D,
    "theoret" + D,
    "typ" + D,
    "vert" + D,
    "whims" + D,
  ]),
  ly = [
    null,
    {},
    { ly: "" },
    { ily: "y", bly: "ble", ply: "ple" },
    { ally: "al", rply: "rp" },
    {
      ually: "ual",
      ially: "ial",
      cally: "cal",
      eally: "eal",
      rally: "ral",
      nally: "nal",
      mally: "mal",
      eeply: "eep",
      eaply: "eap",
    },
    { ically: "ic" },
  ],
  uy = new Set([
    "early",
    "only",
    "hourly",
    "daily",
    "weekly",
    "monthly",
    "yearly",
    "mostly",
    "duly",
    "unduly",
    "especially",
    "undoubtedly",
    "conversely",
    "namely",
    "exceedingly",
    "presumably",
    "accordingly",
    "overly",
    "best",
    "latter",
    "little",
    "long",
    "low",
  ]),
  gs = {
    wholly: "whole",
    fully: "full",
    truly: "true",
    gently: "gentle",
    singly: "single",
    customarily: "customary",
    idly: "idle",
    publically: "public",
    quickly: "quick",
    superbly: "superb",
    cynically: "cynical",
    well: "good",
  },
  cy = function (e) {
    return e.endsWith("ly")
      ? sy.has(e)
        ? e.replace(/ically/, "ical")
        : uy.has(e)
          ? null
          : gs.hasOwnProperty(e)
            ? gs[e]
            : rc(e, ly) || e
      : null;
  },
  hy = [
    null,
    { y: "ily" },
    { ly: "ly", ic: "ically" },
    {
      ial: "ially",
      ual: "ually",
      tle: "tly",
      ble: "bly",
      ple: "ply",
      ary: "arily",
    },
    {},
    {},
    {},
  ],
  ys = {
    cool: "cooly",
    whole: "wholly",
    full: "fully",
    good: "well",
    idle: "idly",
    public: "publicly",
    single: "singly",
    special: "especially",
  },
  ac = function (e) {
    if (ys.hasOwnProperty(e)) return ys[e];
    let t = rc(e, hy);
    return (t || (t = e + "ly"), t);
  },
  dy = function (e, t) {
    let n = [e];
    return (
      n.push(Zi(e, t)),
      n.push(Xi(e, t)),
      n.push(ac(e)),
      (n = n.filter((r) => r)),
      (n = new Set(n)),
      Array.from(n)
    );
  },
  fy = {
    toSuperlative: Zi,
    toComparative: Xi,
    toAdverb: ac,
    toNoun: oy,
    fromAdverb: cy,
    fromSuperlative: iy,
    fromComparative: ay,
    all: dy,
  },
  my = { noun: X0, verb: ry, adjective: fy },
  bs = {
    Singular: (e, t, n, r) => {
      let a = r.one.lexicon,
        i = n.two.transform.noun.toPlural(e, r);
      a[i] || (t[i] = t[i] || "Plural");
    },
    Actor: (e, t, n, r) => {
      let a = r.one.lexicon,
        i = n.two.transform.noun.toPlural(e, r);
      a[i] || (t[i] = t[i] || ["Plural", "Actor"]);
    },
    Comparable: (e, t, n, r) => {
      let a = r.one.lexicon,
        { toSuperlative: i, toComparative: o } = n.two.transform.adjective,
        s = i(e, r);
      a[s] || (t[s] = t[s] || "Superlative");
      let l = o(e, r);
      (a[l] || (t[l] = t[l] || "Comparative"), (t[e] = "Adjective"));
    },
    Demonym: (e, t, n, r) => {
      let a = n.two.transform.noun.toPlural(e, r);
      t[a] = t[a] || ["Demonym", "Plural"];
    },
    Infinitive: (e, t, n, r) => {
      let a = r.one.lexicon,
        i = n.two.transform.verb.conjugate(e, r);
      Object.entries(i).forEach((o) => {
        !a[o[1]] && !t[o[1]] && o[0] !== "FutureTense" && (t[o[1]] = o[0]);
      });
    },
    PhrasalVerb: (e, t, n, r) => {
      let a = r.one.lexicon;
      t[e] = ["PhrasalVerb", "Infinitive"];
      let i = r.one._multiCache,
        [o, s] = e.split(" ");
      a[o] || (t[o] = t[o] || "Infinitive");
      let l = n.two.transform.verb.conjugate(o, r);
      (delete l.FutureTense,
        Object.entries(l).forEach((u) => {
          if (u[0] === "Actor" || u[1] === "") return;
          (!t[u[1]] && !a[u[1]] && (t[u[1]] = u[0]), (i[u[1]] = 2));
          let c = u[1] + " " + s;
          t[c] = t[c] || [u[0], "PhrasalVerb"];
        }));
    },
    Multiple: (e, t) => {
      ((t[e] = ["Multiple", "Cardinal"]),
        (t[e + "th"] = ["Multiple", "Ordinal"]),
        (t[e + "ths"] = ["Multiple", "Fraction"]));
    },
    Cardinal: (e, t) => {
      t[e] = ["TextValue", "Cardinal"];
    },
    Ordinal: (e, t) => {
      ((t[e] = ["TextValue", "Ordinal"]),
        (t[e + "s"] = ["TextValue", "Fraction"]));
    },
    Place: (e, t) => {
      t[e] = ["Place", "ProperNoun"];
    },
    Region: (e, t) => {
      t[e] = ["Region", "ProperNoun"];
    },
  },
  py = function (e, t) {
    const { methods: n, model: r } = t;
    let a = {},
      i = {};
    return (
      Object.keys(e).forEach((o) => {
        let s = e[o];
        ((o = o.toLowerCase().trim()), (o = o.replace(/'s\b/, "")));
        let l = o.split(/ /);
        (l.length > 1 &&
          (i[l[0]] === void 0 || l.length > i[l[0]]) &&
          (i[l[0]] = l.length),
          bs.hasOwnProperty(s) === !0 && bs[s](o, a, n, r),
          (a[o] = a[o] || s));
      }),
      delete a[""],
      delete a[null],
      delete a[" "],
      { lex: a, _multi: i }
    );
  },
  gy = function (e, t) {
    const n = /^[0-9]+$/;
    let r = e[t];
    if (!r) return !1;
    const a = new Set(["may", "april", "august", "jan"]);
    if (
      r.normal === "like" ||
      a.has(r.normal) ||
      r.tags.has("Place") ||
      r.tags.has("Date")
    )
      return !1;
    if (e[t - 1]) {
      let o = e[t - 1];
      if (
        o.tags.has("Date") ||
        a.has(o.normal) ||
        o.tags.has("Adjective") ||
        r.tags.has("Adjective")
      )
        return !1;
    }
    let i = r.normal;
    return !((i.length === 1 || i.length === 2 || i.length === 4) && n.test(i));
  },
  yy = function (e) {
    const t = /[,:;]/;
    let n = [];
    return (
      e.forEach((r) => {
        let a = 0;
        (r.forEach((i, o) => {
          t.test(i.post) &&
            gy(r, o + 1) &&
            (n.push(r.slice(a, o + 1)), (a = o + 1));
        }),
          a < r.length && n.push(r.slice(a, r.length)));
      }),
      n
    );
  },
  vs = {
    e: [
      "mice",
      "louse",
      "antennae",
      "formulae",
      "nebulae",
      "vertebrae",
      "vitae",
    ],
    i: [
      "tia",
      "octopi",
      "viri",
      "radii",
      "nuclei",
      "fungi",
      "cacti",
      "stimuli",
    ],
    n: ["men"],
    t: ["feet"],
  },
  by = new Set(["israelis", "menus", "logos"]),
  vy = [
    "bus",
    "mas",
    "was",
    "ias",
    "xas",
    "vas",
    "cis",
    "lis",
    "nis",
    "ois",
    "ris",
    "sis",
    "tis",
    "xis",
    "aus",
    "cus",
    "eus",
    "fus",
    "gus",
    "ius",
    "lus",
    "nus",
    "das",
    "ous",
    "pus",
    "rus",
    "sus",
    "tus",
    "xus",
    "aos",
    "igos",
    "ados",
    "ogos",
    "'s",
    "ss",
  ],
  ic = function (e) {
    if (!e || e.length <= 3) return !1;
    if (by.has(e)) return !0;
    let t = e[e.length - 1];
    return vs.hasOwnProperty(t)
      ? vs[t].find((n) => e.endsWith(n))
      : !(t !== "s" || vy.find((n) => e.endsWith(n)));
  },
  pi = {
    two: { quickSplit: yy, expandLexicon: py, transform: my, looksPlural: ic },
  },
  wy = function (e) {
    const { irregularPlurals: t } = e.two,
      { lexicon: n } = e.one;
    return (
      Object.entries(t).forEach((r) => {
        ((n[r[0]] = n[r[0]] || "Singular"), (n[r[1]] = n[r[1]] || "Plural"));
      }),
      e
    );
  };
let gi = { one: { lexicon: {} }, two: { models: ec } };
const ky = {
    "Actor|Verb": "Actor",
    "Adj|Gerund": "Adjective",
    "Adj|Noun": "Adjective",
    "Adj|Past": "Adjective",
    "Adj|Present": "Adjective",
    "Noun|Verb": "Singular",
    "Noun|Gerund": "Gerund",
    "Person|Noun": "Noun",
    "Person|Date": "Month",
    "Person|Verb": "FirstName",
    "Person|Place": "Person",
    "Person|Adj": "Comparative",
    "Plural|Verb": "Plural",
    "Unit|Noun": "Noun",
  },
  oc = function (e, t) {
    const n = { model: t, methods: pi };
    let { lex: r, _multi: a } = pi.two.expandLexicon(e, n);
    return (
      Object.assign(t.one.lexicon, r),
      Object.assign(t.one._multiCache, a),
      t
    );
  },
  Py = function (e, t) {
    return (
      Object.keys(e).forEach((n) => {
        e[n] === "Uncountable" &&
          ((t.two.uncountable[n] = !0), (e[n] = "Uncountable"));
      }),
      t
    );
  },
  ws = function (e, t, n) {
    let r = Qi(e, gi);
    ((t[r.PastTense] = t[r.PastTense] || "PastTense"),
      (t[r.Gerund] = t[r.Gerund] || "Gerund"),
      n === !0 && (t[r.PresentTense] = t[r.PresentTense] || "PresentTense"));
  },
  ks = function (e, t, n) {
    let r = Zi(e, n);
    t[r] = t[r] || "Superlative";
    let a = Xi(e, n);
    t[a] = t[a] || "Comparative";
  },
  Ay = function (e, t, n) {
    let r = sa(e, n);
    t[r] = t[r] || "Plural";
  },
  xy = function (e, t) {
    let n = {};
    const r = t.one.lexicon;
    return (
      Object.keys(e).forEach((a) => {
        const i = e[a];
        if (
          ((n[a] = ky[i]),
          (i === "Noun|Verb" || i === "Person|Verb" || i === "Actor|Verb") &&
            ws(a, r, !1),
          i === "Adj|Present" && (ws(a, r, !0), ks(a, r, t)),
          i === "Person|Adj" && ks(a, r, t),
          i === "Adj|Gerund" || i === "Noun|Gerund")
        ) {
          let o = mi(a, gi, "Gerund");
          r[o] || (n[o] = "Infinitive");
        }
        if (
          ((i === "Noun|Gerund" || i === "Adj|Noun" || i === "Person|Noun") &&
            Ay(a, r, t),
          i === "Adj|Past")
        ) {
          let o = mi(a, gi, "PastTense");
          r[o] || (n[o] = "Infinitive");
        }
      }),
      (t = oc(n, t)),
      t
    );
  },
  Cy = function (e) {
    return (
      (e = oc(e.one.lexicon, e)),
      (e = Py(e.one.lexicon, e)),
      (e = xy(e.two.switches, e)),
      (e = wy(e)),
      e
    );
  };
let yi = {
  one: { _multiCache: {}, lexicon: xn, frozenLex: l0 },
  two: {
    irregularPlurals: _u,
    models: ec,
    suffixPatterns: T0,
    prefixPatterns: O0,
    endsWith: I0,
    neighbours: E0,
    regexNormal: J0,
    regexText: _0,
    regexNumbers: U0,
    switches: fi,
    clues: gn,
    uncountable: {},
    orgWords: R0,
    placeWords: Y0,
  },
};
yi = Cy(yi);
const Dy = function (e, t, n, r) {
    const a = r.methods.one.setTag;
    if (e.length >= 3) {
      const i = /:/;
      if (e[0].post.match(i)) {
        let s = e[1];
        if (
          s.tags.has("Value") ||
          s.tags.has("Email") ||
          s.tags.has("PhoneNumber")
        )
          return;
        a([e[0]], "Expression", r, null, "2-punct-colon''");
      }
    }
  },
  $y = function (e, t, n, r) {
    const a = r.methods.one.setTag;
    e[t].post === "-" &&
      e[t + 1] &&
      a([e[t], e[t + 1]], "Hyphenated", r, null, "1-punct-hyphen''");
  },
  Ps = /^(under|over|mis|re|un|dis|semi)-?/,
  jy = function (e, t, n) {
    const r = n.two.switches;
    let a = e[t];
    if (r.hasOwnProperty(a.normal)) {
      a.switch = r[a.normal];
      return;
    }
    if (Ps.test(a.normal)) {
      let i = a.normal.replace(Ps, "");
      i.length > 3 && r.hasOwnProperty(i) && (a.switch = r[i]);
    }
  };
var As = {};
const Ny = (e, t, n = "") => {
    const r = (o) => "\x1B[33m\x1B[3m" + o + "\x1B[0m",
      a = (o) => "\x1B[3m" + o + "\x1B[0m";
    let i = e.text || "[" + e.implicit + "]";
    (typeof t != "string" &&
      t.length > 2 &&
      (t = t.slice(0, 2).join(", #") + " +"),
      (t = typeof t != "string" ? t.join(", #") : t),
      console.log(
        ` ${r(i).padEnd(24)} \x1B[32m→\x1B[0m #${t.padEnd(22)}  ${a(n)}`,
      ));
  },
  _ = function (e, t, n) {
    if (!t || t.length === 0 || e.frozen === !0) return;
    const r = typeof Nt > "u" || !As ? self.env || {} : As;
    (r && r.DEBUG_TAGS && Ny(e, t, n),
      (e.tags = e.tags || new Set()),
      typeof t == "string" ? e.tags.add(t) : t.forEach((a) => e.tags.add(a)));
  },
  Ty = [
    "Acronym",
    "Abbreviation",
    "ProperNoun",
    "Uncountable",
    "Possessive",
    "Pronoun",
    "Activity",
    "Honorific",
    "Month",
  ],
  Oy = function (e) {
    !e.tags.has("Noun") ||
      e.tags.has("Plural") ||
      e.tags.has("Singular") ||
      Ty.find((t) => e.tags.has(t)) ||
      (ic(e.normal)
        ? _(e, "Plural", "3-plural-guess")
        : _(e, "Singular", "3-singular-guess"));
  },
  Iy = function (e) {
    let t = e.tags;
    if (t.has("Verb") && t.size === 1) {
      let n = nc(e.normal);
      n && _(e, n, "3-verb-tense-guess");
    }
  },
  er = function (e, t, n) {
    let r = e[t],
      a = Array.from(r.tags);
    for (let i = 0; i < a.length; i += 1)
      if (n.one.tagSet[a[i]]) {
        let o = n.one.tagSet[a[i]].parents;
        _(r, o, ` -inferred by #${a[i]}`);
      }
    (Oy(r), Iy(r));
  },
  Ey = new RegExp("^\\p{Lu}[\\p{Ll}'’]", "u"),
  Hy = /[0-9]/,
  zy = ["Date", "Month", "WeekDay", "Unit", "Expression"],
  Fy = /[IVX]/,
  Vy = /^[IVXLCDM]{2,}$/,
  Gy = /^M{0,4}(CM|CD|D?C{0,3})(XC|XL|L?X{0,3})(IX|IV|V?I{0,3})$/,
  Sy = { li: !0, dc: !0, md: !0, dm: !0, ml: !0 },
  My = function (e, t, n) {
    let r = e[t];
    r.index = r.index || [0, 0];
    let a = r.index[1],
      i = r.text || "";
    return a !== 0 && Ey.test(i) === !0 && Hy.test(i) === !1
      ? zy.find((o) => r.tags.has(o)) ||
        r.pre.match(/["']$/) ||
        r.normal === "the"
        ? null
        : (er(e, t, n),
          !r.tags.has("Noun") && !r.frozen && r.tags.clear(),
          _(r, "ProperNoun", "2-titlecase"),
          !0)
      : i.length >= 2 && Vy.test(i) && Fy.test(i) && Gy.test(i) && !Sy[r.normal]
        ? (_(r, "RomanNumeral", "2-xvii"), !0)
        : null;
  },
  xs = function (e = "", t = []) {
    const n = e.length;
    let r = 7;
    n <= r && (r = n - 1);
    for (let a = r; a > 1; a -= 1) {
      let i = e.substring(n - a, n);
      if (t[i.length].hasOwnProperty(i) === !0) return t[i.length][i];
    }
    return null;
  },
  By = function (e, t, n) {
    let r = e[t];
    if (r.tags.size === 0) {
      let a = xs(r.normal, n.two.suffixPatterns);
      if (a !== null) return (_(r, a, "2-suffix"), (r.confidence = 0.7), !0);
      if (
        r.implicit &&
        ((a = xs(r.implicit, n.two.suffixPatterns)), a !== null)
      )
        return (_(r, a, "2-implicit-suffix"), (r.confidence = 0.7), !0);
    }
    return null;
  },
  Cs = /['‘’‛‵′`´]/,
  va = function (e, t) {
    for (let n = 0; n < t.length; n += 1)
      if (t[n][0].test(e) === !0) return t[n];
    return null;
  },
  Ly = function (e = "", t) {
    let n = e[e.length - 1];
    if (t.hasOwnProperty(n) === !0) {
      let r = t[n] || [];
      for (let a = 0; a < r.length; a += 1)
        if (r[a][0].test(e) === !0) return r[a];
    }
    return null;
  },
  Wy = function (e, t, n, r) {
    const a = r.methods.one.setTag;
    let { regexText: i, regexNormal: o, regexNumbers: s, endsWith: l } = n.two,
      u = e[t],
      c = u.machine || u.normal,
      h = u.text;
    Cs.test(u.post) && !Cs.test(u.pre) && (h += u.post.trim());
    let f = va(h, i) || va(c, o);
    return (
      !f && /[0-9]/.test(c) && (f = va(c, s)),
      !f && u.tags.size === 0 && (f = Ly(c, l)),
      f
        ? (a([u], f[1], r, null, `2-regex-'${f[2] || f[0]}'`),
          (u.confidence = 0.6),
          !0)
        : null
    );
  },
  qy = function (e = "", t = []) {
    const n = e.length;
    let r = 7;
    r > n - 3 && (r = n - 3);
    for (let a = r; a > 2; a -= 1) {
      let i = e.substring(0, a);
      if (t[i.length].hasOwnProperty(i) === !0) return t[i.length][i];
    }
    return null;
  },
  Ky = function (e, t, n) {
    let r = e[t];
    if (r.tags.size === 0) {
      let a = qy(r.normal, n.two.prefixPatterns);
      if (a !== null) return (_(r, a, "2-prefix"), (r.confidence = 0.5), !0);
    }
    return null;
  },
  Jy = 1400,
  _y = 2100,
  Uy = new Set([
    "in",
    "on",
    "by",
    "until",
    "for",
    "to",
    "during",
    "throughout",
    "through",
    "within",
    "before",
    "after",
    "of",
    "this",
    "next",
    "last",
    "circa",
    "around",
    "post",
    "pre",
    "budget",
    "classic",
    "plan",
    "may",
  ]),
  Ds = function (e) {
    if (!e) return !1;
    let t = e.normal || e.implicit;
    return !!(
      Uy.has(t) ||
      e.tags.has("Date") ||
      e.tags.has("Month") ||
      e.tags.has("WeekDay") ||
      e.tags.has("Year") ||
      e.tags.has("ProperNoun")
    );
  },
  $s = function (e) {
    return e
      ? !!(
          e.tags.has("Ordinal") ||
          (e.tags.has("Cardinal") && e.normal.length < 3) ||
          e.normal === "is" ||
          e.normal === "was"
        )
      : !1;
  },
  js = function (e) {
    return (
      e &&
      (e.tags.has("Date") ||
        e.tags.has("Month") ||
        e.tags.has("WeekDay") ||
        e.tags.has("Year"))
    );
  },
  Ry = function (e, t) {
    const n = e[t];
    if (
      n.tags.has("NumericValue") &&
      n.tags.has("Cardinal") &&
      n.normal.length === 4
    ) {
      let r = Number(n.normal);
      if (r && !isNaN(r) && r > Jy && r < _y) {
        let a = e[t - 1],
          i = e[t + 1];
        if (Ds(a) || Ds(i)) return _(n, "Year", "2-tagYear");
        if (r >= 1920 && r < 2025) {
          if ($s(a) || $s(i)) return _(n, "Year", "2-tagYear-close");
          if (js(e[t - 2]) || js(e[t + 2]))
            return _(n, "Year", "2-tagYear-far");
          if (
            a &&
            (a.tags.has("Determiner") || a.tags.has("Possessive")) &&
            i &&
            i.tags.has("Noun") &&
            !i.tags.has("Plural")
          )
            return _(n, "Year", "2-tagYear-noun");
        }
      }
    }
    return null;
  },
  Yy = function (e, t, n, r) {
    const a = r.methods.one.setTag,
      i = e[t],
      o = ["PastTense", "PresentTense", "Auxiliary", "Modal", "Particle"];
    i.tags.has("Verb") &&
      (o.find((l) => i.tags.has(l)) ||
        a([i], "Infinitive", r, null, "2-verb-type''"));
  },
  sc = /^[A-Z]('s|,)?$/,
  lc = /^[A-Z-]+$/,
  uc = /^[A-Z]+s$/,
  Qy = /([A-Z]\.)+[A-Z]?,?$/,
  Zy = /[A-Z]{2,}('s|,)?$/,
  Xy = /([a-z]\.)+[a-z]\.?$/,
  cc = { I: !0, A: !0 },
  e1 = { la: !0, ny: !0, us: !0, dc: !0, gb: !0 },
  t1 = function (e, t) {
    let n = e.text;
    if (lc.test(n) === !1)
      if (n.length > 3 && uc.test(n) === !0) n = n.replace(/s$/, "");
      else return !1;
    return n.length > 5 ||
      cc.hasOwnProperty(n) ||
      t.one.lexicon.hasOwnProperty(e.normal)
      ? !1
      : Qy.test(n) === !0 ||
          Xy.test(n) === !0 ||
          sc.test(n) === !0 ||
          Zy.test(n) === !0;
  },
  n1 = function (e, t, n) {
    let r = e[t];
    return r.tags.has("RomanNumeral") || r.tags.has("Acronym") || r.frozen
      ? null
      : t1(r, n)
        ? (r.tags.clear(),
          _(r, ["Acronym", "Noun"], "3-no-period-acronym"),
          e1[r.normal] === !0 && _(r, "Place", "3-place-acronym"),
          uc.test(r.text) === !0 && _(r, "Plural", "3-plural-acronym"),
          !0)
        : !cc.hasOwnProperty(r.text) && sc.test(r.text)
          ? (r.tags.clear(),
            _(r, ["Acronym", "Noun"], "3-one-letter-acronym"),
            !0)
          : r.tags.has("Organization") && r.text.length <= 3
            ? (_(r, "Acronym", "3-org-acronym"), !0)
            : r.tags.has("Organization") &&
                lc.test(r.text) &&
                r.text.length <= 6
              ? (_(r, "Acronym", "3-titlecase-acronym"), !0)
              : null;
  },
  Ns = function (e, t) {
    if (!e) return null;
    let n = t.find((r) => e.normal === r[0]);
    return n ? n[1] : null;
  },
  Ts = function (e, t) {
    if (!e) return null;
    let n = t.find((r) => e.tags.has(r[0]));
    return n ? n[1] : null;
  },
  r1 = function (e, t, n) {
    const {
      leftTags: r,
      leftWords: a,
      rightWords: i,
      rightTags: o,
    } = n.two.neighbours;
    let s = e[t];
    if (s.tags.size === 0) {
      let l = null;
      if (
        ((l = l || Ns(e[t - 1], a)),
        (l = l || Ns(e[t + 1], i)),
        (l = l || Ts(e[t - 1], r)),
        (l = l || Ts(e[t + 1], o)),
        l)
      )
        return (
          _(s, l, "3-[neighbour]"),
          er(e, t, n),
          (e[t].confidence = 0.2),
          !0
        );
    }
    return null;
  },
  a1 = (e) => new RegExp("^\\p{Lu}[\\p{Ll}'’]", "u").test(e),
  Os = function (e, t, n) {
    return !e || e.tags.has("FirstName") || e.tags.has("Place")
      ? !1
      : e.tags.has("ProperNoun") ||
          e.tags.has("Organization") ||
          e.tags.has("Acronym")
        ? !0
        : !n && a1(e.text)
          ? t === 0
            ? e.tags.has("Singular")
            : !0
          : !1;
  },
  i1 = function (e, t, n, r) {
    const a = n.model.two.orgWords,
      i = n.methods.one.setTag;
    let o = e[t],
      s = o.machine || o.normal;
    if (a[s] === !0 && Os(e[t - 1], t - 1, r)) {
      i([e[t]], "Organization", n, null, "3-[org-word]");
      for (let l = t; l >= 0 && Os(e[l], l, r); l -= 1)
        i([e[l]], "Organization", n, null, "3-[org-word]");
    }
    return null;
  },
  o1 = (e) => new RegExp("^\\p{Lu}[\\p{Ll}'’]", "u").test(e),
  s1 = /'s$/,
  Is = new Set([
    "athletic",
    "city",
    "community",
    "eastern",
    "federal",
    "financial",
    "great",
    "historic",
    "historical",
    "local",
    "memorial",
    "municipal",
    "national",
    "northern",
    "provincial",
    "southern",
    "state",
    "western",
    "spring",
    "pine",
    "sunset",
    "view",
    "oak",
    "maple",
    "spruce",
    "cedar",
    "willow",
  ]),
  l1 = new Set([
    "center",
    "centre",
    "way",
    "range",
    "bar",
    "bridge",
    "field",
    "pit",
  ]),
  Es = function (e, t, n) {
    if (!e) return !1;
    let r = e.tags;
    return r.has("Organization") || r.has("Possessive") || s1.test(e.normal)
      ? !1
      : r.has("ProperNoun") || r.has("Place")
        ? !0
        : !n && o1(e.text)
          ? t === 0
            ? r.has("Singular")
            : !0
          : !1;
  },
  u1 = function (e, t, n, r) {
    const a = n.model.two.placeWords,
      i = n.methods.one.setTag;
    let o = e[t],
      s = o.machine || o.normal;
    if (a[s] === !0) {
      for (let l = t - 1; l >= 0; l -= 1)
        if (!Is.has(e[l].normal)) {
          if (Es(e[l], l, r)) {
            i(e.slice(l, t + 1), "Place", n, null, "3-[place-of-foo]");
            continue;
          }
          break;
        }
      if (l1.has(s)) return !1;
      for (let l = t + 1; l < e.length; l += 1) {
        if (Es(e[l], l, r))
          return (i(e.slice(t, l + 1), "Place", n, null, "3-[foo-place]"), !0);
        if (!(e[l].normal === "of" || Is.has(e[l].normal))) break;
      }
    }
    return null;
  },
  c1 = function (e, t, n) {
    let r = !1,
      a = e[t].tags;
    ((a.size === 0 ||
      (a.size === 1 &&
        (a.has("Hyphenated") ||
          a.has("HashTag") ||
          a.has("Prefix") ||
          a.has("SlashedTerm")))) &&
      (r = !0),
      r &&
        (_(e[t], "Noun", "3-[fallback]"),
        er(e, t, n),
        (e[t].confidence = 0.1)));
  },
  h1 = /^[A-Z][a-z]/,
  He = (e, t) =>
    e[t].tags.has("ProperNoun") && h1.test(e[t].text) ? "Noun" : null,
  Hs = (e, t, n) => (t === 0 && !e[1] ? n : null),
  d1 = function (e, t) {
    return !e[t + 1] && e[t - 1] && e[t - 1].tags.has("Determiner")
      ? "Noun"
      : null;
  },
  f1 = function (e, t, n) {
    return t === 0 && e.length > 3 ? n : null;
  },
  zs = {
    "Adj|Gerund": (e, t) => He(e, t),
    "Adj|Noun": (e, t) => He(e, t) || d1(e, t),
    "Actor|Verb": (e, t) => He(e, t),
    "Adj|Past": (e, t) => He(e, t),
    "Adj|Present": (e, t) => He(e, t),
    "Noun|Gerund": (e, t) => He(e, t),
    "Noun|Verb": (e, t) => (t > 0 && He(e, t)) || Hs(e, t, "Infinitive"),
    "Plural|Verb": (e, t) =>
      He(e, t) || Hs(e, t, "PresentTense") || f1(e, t, "Plural"),
    "Person|Noun": (e, t) => He(e, t),
    "Person|Verb": (e, t) => (t !== 0 ? He(e, t) : null),
    "Person|Adj": (e, t) =>
      (t === 0 && e.length > 1) || He(e, t) ? "Person" : null,
  };
var Fs = {};
const eo = typeof Nt > "u" || !Fs ? self.env || {} : Fs,
  Vs = /^(under|over|mis|re|un|dis|semi)-?/,
  Gs = (e, t) => {
    if (!e || !t) return null;
    let n = e.normal || e.implicit,
      r = null;
    return (
      t.hasOwnProperty(n) && (r = t[n]),
      r &&
        eo.DEBUG_TAGS &&
        console.log(`
  \x1B[2m\x1B[3m     ↓ - '${n}' \x1B[0m`),
      r
    );
  },
  Ss = (e, t = {}, n) => {
    if (!e || !t) return null;
    let a = Array.from(e.tags)
      .sort((i, o) => {
        let s = n[i] ? n[i].parents.length : 0,
          l = n[o] ? n[o].parents.length : 0;
        return s > l ? -1 : 1;
      })
      .find((i) => t[i]);
    return (
      a &&
        eo.DEBUG_TAGS &&
        console.log(
          `  \x1B[2m\x1B[3m      ↓ - '${e.normal || e.implicit}' (#${a})  \x1B[0m`,
        ),
      (a = t[a]),
      a
    );
  },
  m1 = function (e, t, n, r) {
    if (!n) return null;
    const a = e[t - 1]?.text !== "also" ? t - 1 : Math.max(0, t - 2),
      i = r.one.tagSet;
    let o = Gs(e[t + 1], n.afterWords);
    return (
      (o = o || Gs(e[a], n.beforeWords)),
      (o = o || Ss(e[a], n.beforeTags, i)),
      (o = o || Ss(e[t + 1], n.afterTags, i)),
      o
    );
  },
  p1 = function (e, t, n) {
    const r = n.model,
      a = n.methods.one.setTag,
      { switches: i, clues: o } = r.two,
      s = e[t];
    let l = s.normal || s.implicit || "";
    if ((Vs.test(l) && !i[l] && (l = l.replace(Vs, "")), s.switch)) {
      let u = s.switch;
      if (s.tags.has("Acronym") || s.tags.has("PhrasalVerb")) return;
      let c = m1(e, t, o[u], r);
      (zs[u] && (c = zs[u](e, t) || c),
        c
          ? (a([s], c, n, null, `3-[switch] (${u})`), er(e, t, r))
          : eo.DEBUG_TAGS &&
            console.log(`
 -> X  - '${l}'  : (${u})  `));
    }
  },
  g1 = { there: !0, this: !0, it: !0, him: !0, her: !0, us: !0 },
  y1 = function (e, t) {
    const n = t.methods.one.setTag,
      r = t.model.one._multiCache || {};
    let a = e[0];
    if (
      (a.switch === "Noun|Verb" || a.tags.has("Infinitive")) &&
      e.length >= 2
    ) {
      if (
        (e.length < 4 && !g1[e[1].normal]) ||
        (!a.tags.has("PhrasalVerb") && r.hasOwnProperty(a.normal))
      )
        return;
      (e[1].tags.has("Noun") || e[1].tags.has("Determiner")) &&
        (!e.slice(1, 3).some((l) => l.tags.has("Verb")) ||
          a.tags.has("#PhrasalVerb")) &&
        n([a], "Imperative", t, null, "3-[imperative]");
    }
  },
  b1 = function (e) {
    if (e.filter((n) => !n.tags.has("ProperNoun")).length <= 3) return !1;
    const t = /^[a-z]/;
    return e.every((n) => !t.test(n.text));
  },
  v1 = function (e, t, n) {
    e.forEach((r) => {
      Dy(r, 0, t, n);
    });
  },
  w1 = function (e, t, n, r) {
    for (let a = 0; a < e.length; a += 1)
      e[a].frozen !== !0 &&
        (jy(e, a, t),
        r === !1 && My(e, a, t),
        By(e, a, t),
        Wy(e, a, t, n),
        Ky(e, a, t),
        Ry(e, a));
  },
  k1 = function (e, t, n, r) {
    for (let a = 0; a < e.length; a += 1) {
      let i = n1(e, a, t);
      (er(e, a, t), (i = i || r1(e, a, t)), (i = i || c1(e, a, t)));
    }
    for (let a = 0; a < e.length; a += 1)
      e[a].frozen !== !0 &&
        (i1(e, a, n, r),
        u1(e, a, n, r),
        p1(e, a, n),
        Yy(e, a, t, n),
        $y(e, a, t, n));
    y1(e, n);
  },
  P1 = function (e) {
    const { methods: t, model: n, world: r } = e;
    let a = e.docs;
    v1(a, n, r);
    let i = t.two.quickSplit(a);
    for (let o = 0; o < i.length; o += 1) {
      let s = i[o];
      const l = b1(s);
      (w1(s, n, r, l), k1(s, n, r, l));
    }
    return i;
  },
  Ms = {
    Possessive: (e) => {
      let t = e.machine || e.normal || e.text;
      return ((t = t.replace(/'s$/, "")), t);
    },
    Plural: (e, t) => {
      let n = e.machine || e.normal || e.text;
      return t.methods.two.transform.noun.toSingular(n, t.model);
    },
    Copula: () => "is",
    PastTense: (e, t) => {
      let n = e.machine || e.normal || e.text;
      return t.methods.two.transform.verb.toInfinitive(n, t.model, "PastTense");
    },
    Gerund: (e, t) => {
      let n = e.machine || e.normal || e.text;
      return t.methods.two.transform.verb.toInfinitive(n, t.model, "Gerund");
    },
    PresentTense: (e, t) => {
      let n = e.machine || e.normal || e.text;
      return e.tags.has("Infinitive")
        ? n
        : t.methods.two.transform.verb.toInfinitive(n, t.model, "PresentTense");
    },
    Comparative: (e, t) => {
      let n = e.machine || e.normal || e.text;
      return t.methods.two.transform.adjective.fromComparative(n, t.model);
    },
    Superlative: (e, t) => {
      let n = e.machine || e.normal || e.text;
      return t.methods.two.transform.adjective.fromSuperlative(n, t.model);
    },
    Adverb: (e, t) => {
      const { fromAdverb: n } = t.methods.two.transform.adjective;
      let r = e.machine || e.normal || e.text;
      return n(r);
    },
  },
  A1 = function (e) {
    const t = e.world,
      n = Object.keys(Ms);
    e.docs.forEach((r) => {
      for (let a = 0; a < r.length; a += 1) {
        const i = r[a];
        for (let o = 0; o < n.length; o += 1)
          if (i.tags.has(n[o])) {
            const s = Ms[n[o]];
            let l = s(i, t);
            i.normal !== l && (i.root = l);
            break;
          }
      }
    });
  },
  Bs = {
    Adverb: "RB",
    Comparative: "JJR",
    Superlative: "JJS",
    Adjective: "JJ",
    TO: "Conjunction",
    Modal: "MD",
    Auxiliary: "MD",
    Gerund: "VBG",
    PastTense: "VBD",
    Participle: "VBN",
    PresentTense: "VBZ",
    Infinitive: "VB",
    Particle: "RP",
    Verb: "VB",
    Pronoun: "PRP",
    Cardinal: "CD",
    Conjunction: "CC",
    Determiner: "DT",
    Preposition: "IN",
    QuestionWord: "WP",
    Expression: "UH",
    Possessive: "POS",
    ProperNoun: "NNP",
    Person: "NNP",
    Place: "NNP",
    Organization: "NNP",
    Singular: "NN",
    Plural: "NNS",
    Noun: "NN",
    There: "EX",
  },
  x1 = function (e) {
    if (e.tags.has("ProperNoun") && e.tags.has("Plural")) return "NNPS";
    if (e.tags.has("Possessive") && e.tags.has("Pronoun")) return "PRP$";
    if (e.normal === "there") return "EX";
    if (e.normal === "to") return "TO";
    let t = e.tagRank || [];
    for (let n = 0; n < t.length; n += 1)
      if (Bs.hasOwnProperty(t[n])) return Bs[t[n]];
    return null;
  },
  C1 = function (e) {
    (e.compute("tagRank"),
      e.docs.forEach((t) => {
        t.forEach((n) => {
          n.penn = x1(n);
        });
      }));
  },
  D1 = { preTagger: P1, root: A1, penn: C1 },
  wa = ["Person", "Place", "Organization"],
  $1 = {
    Noun: { not: ["Verb", "Adjective", "Adverb", "Value", "Determiner"] },
    Singular: { is: "Noun", not: ["Plural", "Uncountable"] },
    ProperNoun: { is: "Noun" },
    Person: {
      is: "Singular",
      also: ["ProperNoun"],
      not: ["Place", "Organization", "Date"],
    },
    FirstName: { is: "Person" },
    MaleName: { is: "FirstName", not: ["FemaleName", "LastName"] },
    FemaleName: { is: "FirstName", not: ["MaleName", "LastName"] },
    LastName: { is: "Person", not: ["FirstName"] },
    Honorific: { is: "Person", not: ["FirstName", "LastName", "Value"] },
    Place: { is: "Singular", not: ["Person", "Organization"] },
    Country: { is: "Place", also: ["ProperNoun"], not: ["City"] },
    City: { is: "Place", also: ["ProperNoun"], not: ["Country"] },
    Region: { is: "Place", also: ["ProperNoun"] },
    Address: {},
    Organization: { is: "ProperNoun", not: ["Person", "Place"] },
    SportsTeam: { is: "Organization" },
    School: { is: "Organization" },
    Company: { is: "Organization" },
    Plural: { is: "Noun", not: ["Singular", "Uncountable"] },
    Uncountable: { is: "Noun" },
    Pronoun: { is: "Noun", not: wa },
    Actor: { is: "Noun", not: ["Place", "Organization"] },
    Activity: { is: "Noun", not: ["Person", "Place"] },
    Unit: { is: "Noun", not: wa },
    Demonym: { is: "Noun", also: ["ProperNoun"], not: wa },
    Possessive: { is: "Noun" },
    Reflexive: { is: "Pronoun" },
  },
  j1 = {
    Verb: { not: ["Noun", "Adjective", "Adverb", "Value", "Expression"] },
    PresentTense: { is: "Verb", not: ["PastTense", "FutureTense"] },
    Infinitive: { is: "PresentTense", not: ["Gerund"] },
    Imperative: { is: "Verb", not: ["PastTense", "Gerund", "Copula"] },
    Gerund: { is: "PresentTense", not: ["Copula"] },
    PastTense: { is: "Verb", not: ["PresentTense", "Gerund", "FutureTense"] },
    FutureTense: { is: "Verb", not: ["PresentTense", "PastTense"] },
    Copula: { is: "Verb" },
    Modal: { is: "Verb", not: ["Infinitive"] },
    Participle: { is: "PastTense" },
    Auxiliary: {
      is: "Verb",
      not: ["PastTense", "PresentTense", "Gerund", "Conjunction"],
    },
    PhrasalVerb: { is: "Verb" },
    Particle: {
      is: "PhrasalVerb",
      not: ["PastTense", "PresentTense", "Copula", "Gerund"],
    },
    Passive: { is: "Verb" },
  },
  N1 = {
    Value: { not: ["Verb", "Adjective", "Adverb"] },
    Ordinal: { is: "Value", not: ["Cardinal"] },
    Cardinal: { is: "Value", not: ["Ordinal"] },
    Fraction: { is: "Value", not: ["Noun"] },
    Multiple: { is: "TextValue" },
    RomanNumeral: { is: "Cardinal", not: ["TextValue"] },
    TextValue: { is: "Value", not: ["NumericValue"] },
    NumericValue: { is: "Value", not: ["TextValue"] },
    Money: { is: "Cardinal" },
    Percent: { is: "Value" },
  },
  T1 = {
    Date: { not: ["Verb", "Adverb", "Adjective"] },
    Month: { is: "Date", also: ["Noun"], not: ["Year", "WeekDay", "Time"] },
    WeekDay: { is: "Date", also: ["Noun"] },
    Year: { is: "Date", not: ["RomanNumeral"] },
    FinancialQuarter: { is: "Date", not: "Fraction" },
    Holiday: { is: "Date", also: ["Noun"] },
    Season: { is: "Date" },
    Timezone: { is: "Date", also: ["Noun"], not: ["ProperNoun"] },
    Time: { is: "Date", not: ["AtMention"] },
    Duration: { is: "Date", also: ["Noun"] },
  },
  O1 = ["Noun", "Verb", "Adjective", "Adverb", "Value", "QuestionWord"],
  I1 = {
    Adjective: { not: ["Noun", "Verb", "Adverb", "Value"] },
    Comparable: { is: "Adjective" },
    Comparative: { is: "Adjective" },
    Superlative: { is: "Adjective", not: ["Comparative"] },
    NumberRange: {},
    Adverb: { not: ["Noun", "Verb", "Adjective", "Value"] },
    Determiner: {
      not: [
        "Noun",
        "Verb",
        "Adjective",
        "Adverb",
        "QuestionWord",
        "Conjunction",
      ],
    },
    Conjunction: { not: O1 },
    Preposition: {
      not: [
        "Noun",
        "Verb",
        "Adjective",
        "Adverb",
        "QuestionWord",
        "Determiner",
      ],
    },
    QuestionWord: { not: ["Determiner"] },
    Currency: { is: "Noun" },
    Expression: { not: ["Noun", "Adjective", "Verb", "Adverb"] },
    Abbreviation: {},
    Url: {
      not: [
        "HashTag",
        "PhoneNumber",
        "Verb",
        "Adjective",
        "Value",
        "AtMention",
        "Email",
        "SlashedTerm",
      ],
    },
    PhoneNumber: {
      not: ["HashTag", "Verb", "Adjective", "Value", "AtMention", "Email"],
    },
    HashTag: {},
    AtMention: { is: "Noun", not: ["HashTag", "Email"] },
    Emoji: { not: ["HashTag", "Verb", "Adjective", "Value", "AtMention"] },
    Emoticon: {
      not: [
        "HashTag",
        "Verb",
        "Adjective",
        "Value",
        "AtMention",
        "SlashedTerm",
      ],
    },
    SlashedTerm: { not: ["Emoticon", "Url", "Value"] },
    Email: { not: ["HashTag", "Verb", "Adjective", "Value", "AtMention"] },
    Acronym: { not: ["Plural", "RomanNumeral", "Pronoun", "Date"] },
    Negative: { not: ["Noun", "Adjective", "Value", "Expression"] },
    Condition: { not: ["Verb", "Adjective", "Noun", "Value"] },
    There: {
      not: ["Verb", "Adjective", "Noun", "Value", "Conjunction", "Preposition"],
    },
    Prefix: { not: ["Abbreviation", "Acronym", "ProperNoun"] },
    Hyphenated: {},
  };
let E1 = Object.assign({}, $1, j1, N1, T1, I1);
const H1 = {
    compute: D1,
    methods: pi,
    model: yi,
    tags: E1,
    hooks: ["preTagger"],
  },
  z1 = /[,)"';:\-–—.…]/,
  et = function (e, t) {
    if (!e.found) return;
    let n = e.termList();
    for (let r = 0; r < n.length - 1; r++) {
      const a = n[r];
      if (z1.test(a.post)) return;
    }
    ((n[0].implicit = n[0].normal),
      (n[0].text += t),
      (n[0].normal += t),
      n.slice(1).forEach((r) => {
        ((r.implicit = r.normal), (r.text = ""), (r.normal = ""));
      }));
    for (let r = 0; r < n.length - 1; r++)
      n[r].post = n[r].post.replace(/ /, "");
  },
  F1 = function () {
    let e = this.not("@hasContraction"),
      t = e.match("(we|they|you) are");
    return (
      et(t, "'re"),
      (t = e.match("(he|she|they|it|we|you) will")),
      et(t, "'ll"),
      (t = e.match("(he|she|they|it|we) is")),
      et(t, "'s"),
      (t = e.match("#Person is")),
      et(t, "'s"),
      (t = e.match("#Person would")),
      et(t, "'d"),
      (t = e.match("(is|was|had|would|should|could|do|does|have|has|can) not")),
      et(t, "n't"),
      (t = e.match("(i|we|they) have")),
      et(t, "'ve"),
      (t = e.match("(would|should|could) have")),
      et(t, "'ve"),
      (t = e.match("i am")),
      et(t, "'m"),
      (t = e.match("going to")),
      this
    );
  },
  V1 = new RegExp("^\\p{Lu}[\\p{Ll}'’]", "u"),
  G1 = function (e = "") {
    return (
      (e = e.replace(/^ *[a-z\u00C0-\u00FF]/, (t) => t.toUpperCase())),
      e
    );
  },
  S1 = function (e) {
    class t extends e {
      constructor(r, a, i) {
        (super(r, a, i), (this.viewType = "Contraction"));
      }
      expand() {
        return (
          this.docs.forEach((r) => {
            let a = V1.test(r[0].text);
            (r.forEach((i, o) => {
              ((i.text = i.implicit || ""),
                delete i.implicit,
                o < r.length - 1 && i.post === "" && (i.post += " "),
                (i.dirty = !0));
            }),
              a && (r[0].text = G1(r[0].text)));
          }),
          this.compute("normal"),
          this
        );
      }
    }
    ((e.prototype.contractions = function () {
      let n = this.match("@hasContraction+");
      return new t(this.document, n.pointer);
    }),
      (e.prototype.contract = F1));
  },
  M1 = function (e, t, n) {
    let [r, a] = t;
    !n ||
      n.length === 0 ||
      ((n = n.map(
        (i, o) => (
          (i.implicit = i.text),
          (i.machine = i.text),
          (i.pre = ""),
          (i.post = ""),
          (i.text = ""),
          (i.normal = ""),
          (i.index = [r, a + o]),
          i
        ),
      )),
      n[0] &&
        ((n[0].pre = e[r][a].pre),
        (n[n.length - 1].post = e[r][a].post),
        (n[0].text = e[r][a].text),
        (n[0].normal = e[r][a].normal)),
      e[r].splice(a, 1, ...n));
  },
  B1 = /'/,
  L1 = new Set(["been", "become"]),
  W1 = new Set(["what", "how", "when", "if", "too"]);
let q1 = new Set(["too", "also", "enough"]);
const K1 = (e, t) => {
    for (let n = t + 1; n < e.length; n += 1) {
      let r = e[n];
      if (L1.has(r.normal)) return "has";
      if (
        W1.has(r.normal) ||
        r.tags.has("Gerund") ||
        r.tags.has("Determiner") ||
        r.tags.has("Adjective") ||
        (r.switch === "Adj|Past" &&
          e[n + 1] &&
          (q1.has(e[n + 1].normal) || e[n + 1].tags.has("Preposition")))
      )
        return "is";
      if (r.tags.has("PastTense"))
        return e[n + 1] && e[n + 1].normal === "for" ? "is" : "has";
    }
    return "is";
  },
  J1 = function (e, t) {
    let n = e[t].normal.split(B1)[0];
    if (n === "let") return [n, "us"];
    if (n === "there") {
      let r = e[t + 1];
      if (r && r.tags.has("Plural")) return [n, "are"];
    }
    return K1(e, t) === "has" ? [n, "has"] : [n, "is"];
  },
  _1 = /'/,
  U1 = new Set(["better", "done", "before", "it", "had"]),
  R1 = new Set(["have", "be"]),
  Y1 = (e, t) => {
    for (let n = t + 1; n < e.length; n += 1) {
      let r = e[n];
      if (U1.has(r.normal)) return "had";
      if (R1.has(r.normal)) return "would";
      if (r.tags.has("PastTense") || r.switch === "Adj|Past") return "had";
      if (r.tags.has("PresentTense") || r.tags.has("Infinitive"))
        return "would";
      if (r.tags.has("#Determiner")) return "had";
      if (r.tags.has("Adjective")) return "would";
    }
    return !1;
  },
  Q1 = function (e, t) {
    let n = e[t].normal.split(_1)[0];
    return n === "how" || n === "what"
      ? [n, "did"]
      : Y1(e, t) === "had"
        ? [n, "had"]
        : [n, "would"];
  },
  Z1 = function (e, t) {
    for (let n = t - 1; n >= 0; n -= 1)
      if (
        e[n].tags.has("Noun") ||
        e[n].tags.has("Pronoun") ||
        e[n].tags.has("Plural") ||
        e[n].tags.has("Singular")
      )
        return e[n];
    return null;
  },
  X1 = function (e, t) {
    if (e[t].normal === "ain't" || e[t].normal === "aint") {
      if (e[t + 1] && e[t + 1].normal === "never") return ["have"];
      let r = Z1(e, t);
      if (r) {
        if (r.normal === "we" || r.normal === "they") return ["are", "not"];
        if (r.normal === "i") return ["am", "not"];
        if (r.tags && r.tags.has("Plural")) return ["are", "not"];
      }
      return ["is", "not"];
    }
    return [e[t].normal.replace(/n't/, ""), "not"];
  },
  eb = { that: !0, there: !0, let: !0, here: !0, everywhere: !0 },
  tb = { in: !0, by: !0, for: !0 };
let nb = new Set(["too", "also", "enough", "about"]),
  rb = new Set([
    "is",
    "are",
    "did",
    "were",
    "could",
    "should",
    "must",
    "had",
    "have",
  ]);
const ab = (e, t) => {
    let n = e[t];
    if (eb.hasOwnProperty(n.machine || n.normal)) return !1;
    if (n.tags.has("Possessive")) return !0;
    if (
      n.tags.has("QuestionWord") ||
      n.normal === "he's" ||
      n.normal === "she's"
    )
      return !1;
    let r = e[t + 1];
    if (!r) return !0;
    if (n.normal === "it's") return !!r.tags.has("#Noun");
    if (r.switch == "Noun|Gerund") {
      let a = e[t + 2];
      return a
        ? a.tags.has("Copula")
          ? !0
          : (a.normal === "on" || a.normal === "in", !1)
        : !!(n.tags.has("Actor") || n.tags.has("ProperNoun"));
    }
    if (r.tags.has("Verb"))
      return r.tags.has("Infinitive")
        ? !0
        : r.tags.has("Gerund")
          ? !1
          : !!r.tags.has("PresentTense");
    if (r.switch === "Adj|Noun") {
      let a = e[t + 2];
      if (!a) return !1;
      if (rb.has(a.normal)) return !0;
      if (nb.has(a.normal)) return !1;
    }
    if (r.tags.has("Noun")) {
      let a = r.machine || r.normal;
      return !(
        a === "here" ||
        a === "there" ||
        a === "everywhere" ||
        r.tags.has("Possessive") ||
        (r.tags.has("ProperNoun") && !n.tags.has("ProperNoun"))
      );
    }
    if (e[t - 1] && tb[e[t - 1].normal] === !0) return !0;
    if (r.tags.has("Adjective")) {
      let a = e[t + 2];
      if (!a) return !1;
      if (a.tags.has("Noun") && !a.tags.has("Pronoun")) {
        let i = r.normal;
        return !(i === "above" || i === "below" || i === "behind");
      }
      return a.switch === "Noun|Verb";
    }
    return !!r.tags.has("Value");
  },
  Ls = /'/,
  ib = function (e) {
    e.forEach((t, n) => {
      t.index && (t.index[1] = n);
    });
  },
  ob = function (e, t, n, r) {
    let a = t.update();
    a.document = [e];
    let i = n + r;
    (n > 0 && (n -= 1),
      e[i] && (i += 1),
      (a.ptrs = [[0, n, i]]),
      a.compute(["freeze", "lexicon", "preTagger", "unfreeze"]),
      ib(e));
  },
  Ws = {
    d: (e, t) => Q1(e, t),
    t: (e, t) => X1(e, t),
    s: (e, t, n) =>
      ab(e, t)
        ? n.methods.one.setTag([e[t]], "Possessive", n, null, "2-contraction")
        : J1(e, t),
  },
  sb = function (e, t) {
    let n = t.fromText(e.join(" "));
    return (n.compute("id"), n.docs[0]);
  },
  lb = (e) => {
    let { world: t, document: n } = e;
    n.forEach((r, a) => {
      for (let i = r.length - 1; i >= 0; i -= 1) {
        if (r[i].implicit) continue;
        let o = null;
        Ls.test(r[i].normal) === !0 && (o = r[i].normal.split(Ls)[1]);
        let s = null;
        if ((Ws.hasOwnProperty(o) && (s = Ws[o](r, i, t)), s)) {
          ((s = sb(s, e)), M1(n, [a, i], s), ob(n[a], e, i, s.length));
          continue;
        }
      }
    });
  },
  ub = { contractionTwo: lb },
  cb = { compute: ub, api: S1, hooks: ["contractionTwo"] },
  hb = [
    {
      match: "[(all|both)] #Determiner #Noun",
      group: 0,
      tag: "Noun",
      reason: "all-noun",
    },
    {
      match: "#Copula [(just|alone)]$",
      group: 0,
      tag: "Adjective",
      reason: "not-adverb",
    },
    {
      match: "#Singular is #Adverb? [#PastTense$]",
      group: 0,
      tag: "Adjective",
      reason: "is-filled",
    },
    {
      match: "[#PastTense] #Singular is",
      group: 0,
      tag: "Adjective",
      reason: "smoked-poutine",
    },
    {
      match: "[#PastTense] #Plural are",
      group: 0,
      tag: "Adjective",
      reason: "baked-onions",
    },
    {
      match: "well [#PastTense]",
      group: 0,
      tag: "Adjective",
      reason: "well-made",
    },
    {
      match: "#Copula [fucked up?]",
      group: 0,
      tag: "Adjective",
      reason: "swears-adjective",
    },
    {
      match: "#Singular (seems|appears) #Adverb? [#PastTense$]",
      group: 0,
      tag: "Adjective",
      reason: "seems-filled",
    },
    {
      match: "#Copula #Adjective? [(out|in|through)]$",
      group: 0,
      tag: "Adjective",
      reason: "still-out",
    },
    {
      match: "^[#Adjective] (the|your) #Noun",
      group: 0,
      notIf: "(all|even)",
      tag: "Infinitive",
      reason: "shut-the",
    },
    {
      match: "the [said] #Noun",
      group: 0,
      tag: "Adjective",
      reason: "the-said-card",
    },
    {
      match: "[#Hyphenated (#Hyphenated && #PastTense)] (#Noun|#Conjunction)",
      group: 0,
      tag: "Adjective",
      notIf: "#Adverb",
      reason: "faith-based",
    },
    {
      match: "[#Hyphenated (#Hyphenated && #Gerund)] (#Noun|#Conjunction)",
      group: 0,
      tag: "Adjective",
      notIf: "#Adverb",
      reason: "self-driving",
    },
    {
      match: "[#PastTense (#Hyphenated && #PhrasalVerb)] (#Noun|#Conjunction)",
      group: 0,
      tag: "Adjective",
      reason: "dammed-up",
    },
    {
      match: "(#Hyphenated && #Value) fold",
      tag: "Adjective",
      reason: "two-fold",
    },
    {
      match: "must (#Hyphenated && #Infinitive)",
      tag: "Adjective",
      reason: "must-win",
    },
    {
      match: "(#Hyphenated && #Infinitive) #Hyphenated",
      tag: "Adjective",
      notIf: "#PhrasalVerb",
      reason: "vacuum-sealed",
    },
    { match: "too much", tag: "Adverb Adjective", reason: "bit-4" },
    {
      match: "a bit much",
      tag: "Determiner Adverb Adjective",
      reason: "bit-3",
    },
    {
      match:
        "[(un|contra|extra|inter|intra|macro|micro|mid|mis|mono|multi|pre|sub|tri|ex)] #Adjective",
      group: 0,
      tag: ["Adjective", "Prefix"],
      reason: "un-skilled",
    },
  ],
  db =
    "(dark|bright|flat|light|soft|pale|dead|dim|faux|little|wee|sheer|most|near|good|extra|all)",
  qs = "(hard|fast|late|early|high|right|deep|close|direct)",
  fb = [
    {
      match: "#Adverb [#Adverb] (and|or|then)",
      group: 0,
      tag: "Adjective",
      reason: "kinda-sparkly-and",
    },
    {
      match: `[${db}] #Adjective`,
      group: 0,
      tag: "Adverb",
      reason: "dark-green",
    },
    {
      match: "#Copula [far too] #Adjective",
      group: 0,
      tag: "Adverb",
      reason: "far-too",
    },
    {
      match: "#Copula [still] (in|#Gerund|#Adjective)",
      group: 0,
      tag: "Adverb",
      reason: "was-still-walking",
    },
    {
      match: `#Plural ${qs}`,
      tag: "#PresentTense #Adverb",
      reason: "studies-hard",
    },
    {
      match: `#Verb [${qs}] !#Noun?`,
      group: 0,
      notIf:
        "(#Copula|get|got|getting|become|became|becoming|feel|feels|feeling|#Determiner|#Preposition)",
      tag: "Adverb",
      reason: "shops-direct",
    },
    { match: "[#Plural] a lot", tag: "PresentTense", reason: "studies-a-lot" },
  ],
  mb = [
    {
      match: "as [#Gerund] as",
      group: 0,
      tag: "Adjective",
      reason: "as-gerund-as",
    },
    {
      match: "more [#Gerund] than",
      group: 0,
      tag: "Adjective",
      reason: "more-gerund-than",
    },
    {
      match: "(so|very|extremely) [#Gerund]",
      group: 0,
      tag: "Adjective",
      reason: "so-gerund",
    },
    {
      match: "(found|found) it #Adverb? [#Gerund]",
      group: 0,
      tag: "Adjective",
      reason: "found-it-gerund",
    },
    {
      match: "a (little|bit|wee) bit? [#Gerund]",
      group: 0,
      tag: "Adjective",
      reason: "a-bit-gerund",
    },
    {
      match: "#Gerund [#Gerund]",
      group: 0,
      tag: "Adjective",
      notIf: "(impersonating|practicing|considering|assuming)",
      reason: "looking-annoying",
    },
    {
      match: "(looked|look|looks) #Adverb? [%Adj|Gerund%]",
      group: 0,
      tag: "Adjective",
      notIf: "(impersonating|practicing|considering|assuming)",
      reason: "looked-amazing",
    },
    {
      match: "[%Adj|Gerund%] #Determiner",
      group: 0,
      tag: "Gerund",
      reason: "developing-a",
    },
    {
      match: "#Possessive [%Adj|Gerund%] #Noun",
      group: 0,
      tag: "Adjective",
      reason: "leading-manufacturer",
    },
    {
      match: "%Noun|Gerund% %Adj|Gerund%",
      tag: "Gerund #Adjective",
      reason: "meaning-alluring",
    },
    {
      match: "(face|embrace|reveal|stop|start|resume) %Adj|Gerund%",
      tag: "#PresentTense #Adjective",
      reason: "face-shocking",
    },
    {
      match: "(are|were) [%Adj|Gerund%] #Plural",
      group: 0,
      tag: "Adjective",
      reason: "are-enduring-symbols",
    },
  ],
  pb = [
    {
      match: "#Determiner [#Adjective] #Copula",
      group: 0,
      tag: "Noun",
      reason: "the-adj-is",
    },
    {
      match: "#Adjective [#Adjective] #Copula",
      group: 0,
      tag: "Noun",
      reason: "adj-adj-is",
    },
    {
      match: "(his|its) [%Adj|Noun%]",
      group: 0,
      tag: "Noun",
      notIf: "#Hyphenated",
      reason: "his-fine",
    },
    {
      match: "#Copula #Adverb? [all]",
      group: 0,
      tag: "Noun",
      reason: "is-all",
    },
    {
      match: "(have|had) [#Adjective] #Preposition .",
      group: 0,
      tag: "Noun",
      reason: "have-fun",
    },
    {
      match: "#Gerund (giant|capital|center|zone|application)",
      tag: "Noun",
      reason: "brewing-giant",
    },
    {
      match: "#Preposition (a|an) [#Adjective]$",
      group: 0,
      tag: "Noun",
      reason: "an-instant",
    },
    {
      match: "no [#Adjective] #Modal",
      group: 0,
      tag: "Noun",
      reason: "no-golden",
    },
    {
      match: "[brand #Gerund?] new",
      group: 0,
      tag: "Adverb",
      reason: "brand-new",
    },
    {
      match: "(#Determiner|#Comparative|new|different) [kind]",
      group: 0,
      tag: "Noun",
      reason: "some-kind",
    },
    {
      match: "#Possessive [%Adj|Noun%] #Noun",
      group: 0,
      tag: "Adjective",
      reason: "her-favourite",
    },
    { match: "must && #Hyphenated .", tag: "Adjective", reason: "must-win" },
    {
      match: "#Determiner [#Adjective]$",
      tag: "Noun",
      notIf: "(this|that|#Comparative|#Superlative)",
      reason: "the-south",
    },
    {
      match: "(#Noun && #Hyphenated) (#Adjective && #Hyphenated)",
      tag: "Adjective",
      notIf: "(this|that|#Comparative|#Superlative)",
      reason: "company-wide",
    },
    {
      match: "#Determiner [#Adjective] (#Copula|#Determiner)",
      notIf: "(#Comparative|#Superlative)",
      group: 0,
      tag: "Noun",
      reason: "the-poor",
    },
    {
      match: "[%Adj|Noun%] #Noun",
      notIf: "(#Pronoun|#ProperNoun)",
      group: 0,
      tag: "Adjective",
      reason: "stable-foundations",
    },
  ],
  gb = [
    {
      match: "(slowly|quickly) [#Adjective]",
      group: 0,
      tag: "Verb",
      reason: "slowly-adj",
    },
    {
      match: "does (#Adverb|not)? [#Adjective]",
      group: 0,
      tag: "PresentTense",
      reason: "does-mean",
    },
    {
      match: "[(fine|okay|cool|ok)] by me",
      group: 0,
      tag: "Adjective",
      reason: "okay-by-me",
    },
    {
      match: "i (#Adverb|do)? not? [mean]",
      group: 0,
      tag: "PresentTense",
      reason: "i-mean",
    },
    {
      match: "will #Adjective",
      tag: "Auxiliary Infinitive",
      reason: "will-adj",
    },
    {
      match: "#Pronoun [#Adjective] #Determiner #Adjective? #Noun",
      group: 0,
      tag: "Verb",
      reason: "he-adj-the",
    },
    {
      match: "#Copula [%Adj|Present%] to #Verb",
      group: 0,
      tag: "Verb",
      reason: "adj-to",
    },
    {
      match: "#Copula [#Adjective] (well|badly|quickly|slowly)",
      group: 0,
      tag: "Verb",
      reason: "done-well",
    },
    {
      match: "#Adjective and [#Gerund] !#Preposition?",
      group: 0,
      tag: "Adjective",
      reason: "rude-and-x",
    },
    {
      match: "#Copula #Adverb? (over|under) [#PastTense]",
      group: 0,
      tag: "Adjective",
      reason: "over-cooked",
    },
    {
      match: "#Copula #Adjective+ (and|or) [#PastTense]$",
      group: 0,
      tag: "Adjective",
      reason: "bland-and-overcooked",
    },
    {
      match: "got #Adverb? [#PastTense] of",
      group: 0,
      tag: "Adjective",
      reason: "got-tired-of",
    },
    {
      match:
        "(seem|seems|seemed|appear|appeared|appears|feel|feels|felt|sound|sounds|sounded) (#Adverb|#Adjective)? [#PastTense]",
      group: 0,
      tag: "Adjective",
      reason: "felt-loved",
    },
    {
      match: "(seem|feel|seemed|felt) [#PastTense #Particle?]",
      group: 0,
      tag: "Adjective",
      reason: "seem-confused",
    },
    {
      match: "a (bit|little|tad) [#PastTense #Particle?]",
      group: 0,
      tag: "Adjective",
      reason: "a-bit-confused",
    },
    {
      match: "not be [%Adj|Past% #Particle?]",
      group: 0,
      tag: "Adjective",
      reason: "do-not-be-confused",
    },
    {
      match: "#Copula just [%Adj|Past% #Particle?]",
      group: 0,
      tag: "Adjective",
      reason: "is-just-right",
    },
    {
      match: "as [#Infinitive] as",
      group: 0,
      tag: "Adjective",
      reason: "as-pale-as",
    },
    {
      match: "[%Adj|Past%] and #Adjective",
      group: 0,
      tag: "Adjective",
      reason: "faled-and-oppressive",
    },
    {
      match: "or [#PastTense] #Noun",
      group: 0,
      tag: "Adjective",
      notIf: "(#Copula|#Pronoun)",
      reason: "or-heightened-emotion",
    },
    {
      match: "(become|became|becoming|becomes) [#Verb]",
      group: 0,
      tag: "Adjective",
      reason: "become-verb",
    },
    {
      match: "#Possessive [#PastTense] #Noun",
      group: 0,
      tag: "Adjective",
      reason: "declared-intentions",
    },
    {
      match: "#Copula #Pronoun [%Adj|Present%]",
      group: 0,
      tag: "Adjective",
      reason: "is-he-cool",
    },
    {
      match: "#Copula [%Adj|Past%] with",
      group: 0,
      tag: "Adjective",
      notIf:
        "(associated|worn|baked|aged|armed|bound|fried|loaded|mixed|packed|pumped|filled|sealed)",
      reason: "is-crowded-with",
    },
    {
      match: "#Copula #Adverb? [%Adj|Present%]$",
      group: 0,
      tag: "Adjective",
      reason: "was-empty$",
    },
  ],
  yb = [
    {
      match: "[still] #Adjective",
      group: 0,
      tag: "Adverb",
      reason: "still-advb",
    },
    { match: "[still] #Verb", group: 0, tag: "Adverb", reason: "still-verb" },
    { match: "[so] #Adjective", group: 0, tag: "Adverb", reason: "so-adv" },
    { match: "[way] #Comparative", group: 0, tag: "Adverb", reason: "way-adj" },
    {
      match: "[way] #Adverb #Adjective",
      group: 0,
      tag: "Adverb",
      reason: "way-too-adj",
    },
    { match: "[all] #Verb", group: 0, tag: "Adverb", reason: "all-verb" },
    {
      match: "#Verb  [like]",
      group: 0,
      notIf: "(#Modal|#PhrasalVerb)",
      tag: "Adverb",
      reason: "verb-like",
    },
    { match: "(barely|hardly) even", tag: "Adverb", reason: "barely-even" },
    { match: "[even] #Verb", group: 0, tag: "Adverb", reason: "even-walk" },
    {
      match: "[even] #Comparative",
      group: 0,
      tag: "Adverb",
      reason: "even-worse",
    },
    {
      match: "[even] (#Determiner|#Possessive)",
      group: 0,
      tag: "#Adverb",
      reason: "even-the",
    },
    { match: "even left", tag: "#Adverb #Verb", reason: "even-left" },
    { match: "[way] #Adjective", group: 0, tag: "#Adverb", reason: "way-over" },
    {
      match: "#PresentTense [(hard|quick|bright|slow|fast|backwards|forwards)]",
      notIf: "#Copula",
      group: 0,
      tag: "Adverb",
      reason: "lazy-ly",
    },
    { match: "[much] #Adjective", group: 0, tag: "Adverb", reason: "bit-1" },
    {
      match: "#Copula [#Adverb]$",
      group: 0,
      tag: "Adjective",
      reason: "is-well",
    },
    {
      match: "a [(little|bit|wee) bit?] #Adjective",
      group: 0,
      tag: "Adverb",
      reason: "a-bit-cold",
    },
    {
      match: "[(super|pretty)] #Adjective",
      group: 0,
      tag: "Adverb",
      reason: "super-strong",
    },
    {
      match: "(become|fall|grow) #Adverb? [#PastTense]",
      group: 0,
      tag: "Adjective",
      reason: "overly-weakened",
    },
    {
      match: "(a|an) #Adverb [#Participle] #Noun",
      group: 0,
      tag: "Adjective",
      reason: "completely-beaten",
    },
    {
      match: "#Determiner #Adverb? [close]",
      group: 0,
      tag: "Adjective",
      reason: "a-close",
    },
    {
      match: "#Gerund #Adverb? [close]",
      group: 0,
      tag: "Adverb",
      notIf: "(getting|becoming|feeling)",
      reason: "being-close",
    },
    {
      match: "(the|those|these|a|an) [#Participle] #Noun",
      group: 0,
      tag: "Adjective",
      reason: "blown-motor",
    },
    {
      match: "(#PresentTense|#PastTense) [back]",
      group: 0,
      tag: "Adverb",
      notIf: "(#PhrasalVerb|#Copula)",
      reason: "charge-back",
    },
    {
      match: "#Verb [around]",
      group: 0,
      tag: "Adverb",
      notIf: "#PhrasalVerb",
      reason: "send-around",
    },
    {
      match: "[later] #PresentTense",
      group: 0,
      tag: "Adverb",
      reason: "later-say",
    },
    {
      match: "#Determiner [well] !#PastTense?",
      group: 0,
      tag: "Noun",
      reason: "the-well",
    },
    {
      match: "#Adjective [enough]",
      group: 0,
      tag: "Adverb",
      reason: "high-enough",
    },
  ],
  bb = [
    { match: "#Holiday (day|eve)", tag: "Holiday", reason: "holiday-day" },
    { match: "#Value of #Month", tag: "Date", reason: "value-of-month" },
    { match: "#Cardinal #Month", tag: "Date", reason: "cardinal-month" },
    { match: "#Month #Value to #Value", tag: "Date", reason: "value-to-value" },
    { match: "#Month the #Value", tag: "Date", reason: "month-the-value" },
    { match: "(#WeekDay|#Month) #Value", tag: "Date", reason: "date-value" },
    { match: "#Value (#WeekDay|#Month)", tag: "Date", reason: "value-date" },
    {
      match: "(#TextValue && #Date) #TextValue",
      tag: "Date",
      reason: "textvalue-date",
    },
    { match: "#Month #NumberRange", tag: "Date", reason: "aug 20-21" },
    { match: "#WeekDay #Month #Ordinal", tag: "Date", reason: "week mm-dd" },
    { match: "#Month #Ordinal #Cardinal", tag: "Date", reason: "mm-dd-yyy" },
    {
      match:
        "(#Place|#Demonmym|#Time) (standard|daylight|central|mountain)? time",
      tag: "Timezone",
      reason: "std-time",
    },
    {
      match:
        "(eastern|mountain|pacific|central|atlantic) (standard|daylight|summer)? time",
      tag: "Timezone",
      reason: "eastern-time",
    },
    {
      match: "#Time [(eastern|mountain|pacific|central|est|pst|gmt)]",
      group: 0,
      tag: "Timezone",
      reason: "5pm-central",
    },
    {
      match: "(central|western|eastern) european time",
      tag: "Timezone",
      reason: "cet",
    },
  ],
  vb = [
    { match: "[sun] the #Ordinal", tag: "WeekDay", reason: "sun-the-5th" },
    { match: "[sun] #Date", group: 0, tag: "WeekDay", reason: "sun-feb" },
    {
      match: "#Date (on|this|next|last|during)? [sun]",
      group: 0,
      tag: "WeekDay",
      reason: "1pm-sun",
    },
    {
      match: "(in|by|before|during|on|until|after|of|within|all) [sat]",
      group: 0,
      tag: "WeekDay",
      reason: "sat",
    },
    {
      match: "(in|by|before|during|on|until|after|of|within|all) [wed]",
      group: 0,
      tag: "WeekDay",
      reason: "wed",
    },
    {
      match: "(in|by|before|during|on|until|after|of|within|all) [march]",
      group: 0,
      tag: "Month",
      reason: "march",
    },
    { match: "[sat] #Date", group: 0, tag: "WeekDay", reason: "sat-feb" },
    {
      match: "#Preposition [(march|may)]",
      group: 0,
      tag: "Month",
      reason: "in-month",
    },
    {
      match: "(this|next|last) (march|may) !#Infinitive?",
      tag: "#Date #Month",
      reason: "this-month",
    },
    {
      match: "(march|may) the? #Value",
      tag: "#Month #Date #Date",
      reason: "march-5th",
    },
    {
      match: "#Value of? (march|may)",
      tag: "#Date #Date #Month",
      reason: "5th-of-march",
    },
    {
      match: "[(march|may)] .? #Date",
      group: 0,
      tag: "Month",
      reason: "march-and-feb",
    },
    {
      match: "#Date .? [(march|may)]",
      group: 0,
      tag: "Month",
      reason: "feb-and-march",
    },
    {
      match: "#Adverb [(march|may)]",
      group: 0,
      tag: "Verb",
      reason: "quickly-march",
    },
    {
      match: "[(march|may)] #Adverb",
      group: 0,
      tag: "Verb",
      reason: "march-quickly",
    },
    { match: "#Value (am|pm)", tag: "Time", reason: "2-am" },
  ],
  wb =
    "(feel|sense|process|rush|side|bomb|bully|challenge|cover|crush|dump|exchange|flow|function|issue|lecture|limit|march|process)",
  kb = [
    {
      match: "(the|any) [more]",
      group: 0,
      tag: "Singular",
      reason: "more-noun",
    },
    { match: "[more] #Noun", group: 0, tag: "Adjective", reason: "more-noun" },
    { match: "(right|rights) of .", tag: "Noun", reason: "right-of" },
    { match: "a [bit]", group: 0, tag: "Singular", reason: "bit-2" },
    { match: "a [must]", group: 0, tag: "Singular", reason: "must-2" },
    { match: "(we|us) [all]", group: 0, tag: "Noun", reason: "we all" },
    { match: "due to [#Verb]", group: 0, tag: "Noun", reason: "due-to" },
    {
      match: "some [#Verb] #Plural",
      group: 0,
      tag: "Noun",
      reason: "determiner6",
    },
    {
      match: "#Possessive #Ordinal [#PastTense]",
      group: 0,
      tag: "Noun",
      reason: "first-thought",
    },
    {
      match: "(the|this|those|these) #Adjective [%Verb|Noun%]",
      group: 0,
      tag: "Noun",
      notIf: "#Copula",
      reason: "the-adj-verb",
    },
    {
      match: "(the|this|those|these) #Adverb #Adjective [#Verb]",
      group: 0,
      tag: "Noun",
      reason: "determiner4",
    },
    {
      match: "the [#Verb] #Preposition .",
      group: 0,
      tag: "Noun",
      reason: "determiner1",
    },
    {
      match: "(a|an|the) [#Verb] of",
      group: 0,
      tag: "Noun",
      reason: "the-verb-of",
    },
    {
      match: "#Determiner #Noun of [#Verb]",
      group: 0,
      tag: "Noun",
      notIf: "#Gerund",
      reason: "noun-of-noun",
    },
    {
      match: "#PastTense #Preposition [#PresentTense]",
      group: 0,
      notIf: "#Gerund",
      tag: "Noun",
      reason: "ended-in-ruins",
    },
    {
      match: "#Conjunction [u]",
      group: 0,
      tag: "Pronoun",
      reason: "u-pronoun-2",
    },
    { match: "[u] #Verb", group: 0, tag: "Pronoun", reason: "u-pronoun-1" },
    {
      match: "#Determiner [(western|eastern|northern|southern|central)] #Noun",
      group: 0,
      tag: "Noun",
      reason: "western-line",
    },
    {
      match: "(#Singular && @hasHyphen) #PresentTense",
      tag: "Noun",
      reason: "hyphen-verb",
    },
    { match: "is no [#Verb]", group: 0, tag: "Noun", reason: "is-no-verb" },
    { match: "do [so]", group: 0, tag: "Noun", reason: "so-noun" },
    {
      match: "#Determiner [(shit|damn|hell)]",
      group: 0,
      tag: "Noun",
      reason: "swears-noun",
    },
    { match: "to [(shit|hell)]", group: 0, tag: "Noun", reason: "to-swears" },
    {
      match: "(the|these) [#Singular] (were|are)",
      group: 0,
      tag: "Plural",
      reason: "singular-were",
    },
    {
      match: "a #Noun+ or #Adverb+? [#Verb]",
      group: 0,
      tag: "Noun",
      reason: "noun-or-noun",
    },
    {
      match: "(the|those|these|a|an) #Adjective? [#PresentTense #Particle?]",
      group: 0,
      tag: "Noun",
      notIf: "(seem|appear|include|#Gerund|#Copula)",
      reason: "det-inf",
    },
    {
      match: "#Noun #Actor",
      tag: "Actor",
      notIf: "(#Person|#Pronoun)",
      reason: "thing-doer",
    },
    { match: "#Gerund #Actor", tag: "Actor", reason: "gerund-doer" },
    { match: "co #Singular", tag: "Actor", reason: "co-noun" },
    {
      match: "[#Noun+] #Actor",
      group: 0,
      tag: "Actor",
      notIf: "(#Honorific|#Pronoun|#Possessive)",
      reason: "air-traffic-controller",
    },
    {
      match:
        "(urban|cardiac|cardiovascular|respiratory|medical|clinical|visual|graphic|creative|dental|exotic|fine|certified|registered|technical|virtual|professional|amateur|junior|senior|special|pharmaceutical|theoretical)+ #Noun? #Actor",
      tag: "Actor",
      reason: "fine-artist",
    },
    {
      match:
        "#Noun+ (coach|chef|king|engineer|fellow|personality|boy|girl|man|woman|master)",
      tag: "Actor",
      reason: "dance-coach",
    },
    { match: "chief . officer", tag: "Actor", reason: "chief-x-officer" },
    { match: "chief of #Noun+", tag: "Actor", reason: "chief-of-police" },
    {
      match: "senior? vice? president of #Noun+",
      tag: "Actor",
      reason: "president-of",
    },
    {
      match: "#Determiner [sun]",
      group: 0,
      tag: "Singular",
      reason: "the-sun",
    },
    {
      match: "#Verb (a|an) [#Value]$",
      group: 0,
      tag: "Singular",
      reason: "did-a-value",
    },
    {
      match: "the [(can|will|may)]",
      group: 0,
      tag: "Singular",
      reason: "the can",
    },
    {
      match: "#FirstName #Acronym? (#Possessive && #LastName)",
      tag: "Possessive",
      reason: "name-poss",
    },
    {
      match: "#Organization+ #Possessive",
      tag: "Possessive",
      reason: "org-possessive",
    },
    {
      match: "#Place+ #Possessive",
      tag: "Possessive",
      reason: "place-possessive",
    },
    {
      match: "#Possessive #PresentTense #Particle?",
      notIf: "(#Gerund|her)",
      tag: "Noun",
      reason: "possessive-verb",
    },
    {
      match: "(my|our|their|her|his|its) [(#Plural && #Actor)] #Noun",
      tag: "Possessive",
      reason: "my-dads",
    },
    {
      match: "#Value of a [second]",
      group: 0,
      unTag: "Value",
      tag: "Singular",
      reason: "10th-of-a-second",
    },
    {
      match: "#Value [seconds]",
      group: 0,
      unTag: "Value",
      tag: "Plural",
      reason: "10-seconds",
    },
    { match: "in [#Infinitive]", group: 0, tag: "Singular", reason: "in-age" },
    {
      match: "a [#Adjective] #Preposition",
      group: 0,
      tag: "Noun",
      reason: "a-minor-in",
    },
    {
      match: "#Determiner [#Singular] said",
      group: 0,
      tag: "Actor",
      reason: "the-actor-said",
    },
    {
      match: `#Determiner #Noun [${wb}] !(#Preposition|to|#Adverb)?`,
      group: 0,
      tag: "Noun",
      reason: "the-noun-sense",
    },
    {
      match: "[#PresentTense] (of|by|for) (a|an|the) #Noun #Copula",
      group: 0,
      tag: "Plural",
      reason: "photographs-of",
    },
    {
      match: "#Infinitive and [%Noun|Verb%]",
      group: 0,
      tag: "Infinitive",
      reason: "fight and win",
    },
    {
      match: "#Noun and [#Verb] and #Noun",
      group: 0,
      tag: "Noun",
      reason: "peace-and-flowers",
    },
    {
      match: "the #Cardinal [%Adj|Noun%]",
      group: 0,
      tag: "Noun",
      reason: "the-1992-classic",
    },
    {
      match: "#Copula the [%Adj|Noun%] #Noun",
      group: 0,
      tag: "Adjective",
      reason: "the-premier-university",
    },
    {
      match: "i #Verb [me] #Noun",
      group: 0,
      tag: "Possessive",
      reason: "scottish-me",
    },
    {
      match:
        "[#PresentTense] (music|class|lesson|night|party|festival|league|ceremony)",
      group: 0,
      tag: "Noun",
      reason: "dance-music",
    },
    { match: "[wit] (me|it)", group: 0, tag: "Presposition", reason: "wit-me" },
    {
      match: "#PastTense #Possessive [#Verb]",
      group: 0,
      tag: "Noun",
      notIf: "(saw|made)",
      reason: "left-her-boots",
    },
    {
      match: "#Value [%Plural|Verb%]",
      group: 0,
      tag: "Plural",
      notIf: "(one|1|a|an)",
      reason: "35-signs",
    },
    {
      match: "had [#PresentTense]",
      group: 0,
      tag: "Noun",
      notIf: "(#Gerund|come|become)",
      reason: "had-time",
    },
    {
      match: "%Adj|Noun% %Noun|Verb%",
      tag: "#Adjective #Noun",
      notIf: "#ProperNoun #Noun",
      reason: "instant-access",
    },
    {
      match: "#Determiner [%Adj|Noun%] #Conjunction",
      group: 0,
      tag: "Noun",
      reason: "a-rep-to",
    },
    {
      match: "#Adjective #Noun [%Plural|Verb%]$",
      group: 0,
      tag: "Plural",
      notIf: "#Pronoun",
      reason: "near-death-experiences",
    },
    {
      match: "#Possessive #Noun [%Plural|Verb%]$",
      group: 0,
      tag: "Plural",
      reason: "your-guild-colors",
    },
  ],
  Pb = [
    {
      match: "(this|that|the|a|an) [#Gerund #Infinitive]",
      group: 0,
      tag: "Singular",
      reason: "the-planning-process",
    },
    {
      match: "(that|the) [#Gerund #PresentTense]",
      group: 0,
      ifNo: "#Copula",
      tag: "Plural",
      reason: "the-paving-stones",
    },
    {
      match: "#Determiner [#Gerund] #Noun",
      group: 0,
      tag: "Adjective",
      reason: "the-gerund-noun",
    },
    {
      match: "#Pronoun #Infinitive [#Gerund] #PresentTense",
      group: 0,
      tag: "Noun",
      reason: "tipping-sucks",
    },
    {
      match: "#Adjective [#Gerund]",
      group: 0,
      tag: "Noun",
      notIf: "(still|even|just)",
      reason: "early-warning",
    },
    {
      match: "[#Gerund] #Adverb? not? #Copula",
      group: 0,
      tag: "Activity",
      reason: "gerund-copula",
    },
    {
      match: "#Copula [(#Gerund|#Activity)] #Copula",
      group: 0,
      tag: "Gerund",
      reason: "are-doing-is",
    },
    {
      match: "[#Gerund] #Modal",
      group: 0,
      tag: "Activity",
      reason: "gerund-modal",
    },
    {
      match: "#Singular for [%Noun|Gerund%]",
      group: 0,
      tag: "Gerund",
      reason: "noun-for-gerund",
    },
    {
      match: "#Comparative (for|at) [%Noun|Gerund%]",
      group: 0,
      tag: "Gerund",
      reason: "better-for-gerund",
    },
    {
      match: "#PresentTense the [#Gerund]",
      group: 0,
      tag: "Noun",
      reason: "keep-the-touching",
    },
  ],
  Ab = [
    {
      match: "#Infinitive (this|that|the) [#Infinitive]",
      group: 0,
      tag: "Noun",
      reason: "do-this-dance",
    },
    {
      match: "#Gerund #Determiner [#Infinitive]",
      group: 0,
      tag: "Noun",
      reason: "running-a-show",
    },
    {
      match: "#Determiner (only|further|just|more|backward) [#Infinitive]",
      group: 0,
      tag: "Noun",
      reason: "the-only-reason",
    },
    {
      match: "(the|this|a|an) [#Infinitive] #Adverb? #Verb",
      group: 0,
      tag: "Noun",
      reason: "determiner5",
    },
    {
      match: "#Determiner #Adjective #Adjective? [#Infinitive]",
      group: 0,
      tag: "Noun",
      reason: "a-nice-inf",
    },
    {
      match: "#Determiner #Demonym [#PresentTense]",
      group: 0,
      tag: "Noun",
      reason: "mexican-train",
    },
    {
      match: "#Adjective #Noun+ [#Infinitive] #Copula",
      group: 0,
      tag: "Noun",
      reason: "career-move",
    },
    {
      match: "at some [#Infinitive]",
      group: 0,
      tag: "Noun",
      reason: "at-some-inf",
    },
    {
      match: "(go|goes|went) to [#Infinitive]",
      group: 0,
      tag: "Noun",
      reason: "goes-to-verb",
    },
    {
      match: "(a|an) #Adjective? #Noun [#Infinitive] (#Preposition|#Noun)",
      group: 0,
      notIf: "from",
      tag: "Noun",
      reason: "a-noun-inf",
    },
    {
      match: "(a|an) #Noun [#Infinitive]$",
      group: 0,
      tag: "Noun",
      reason: "a-noun-inf2",
    },
    {
      match: "#Gerund #Adjective? for [#Infinitive]",
      group: 0,
      tag: "Noun",
      reason: "running-for",
    },
    {
      match: "about [#Infinitive]",
      group: 0,
      tag: "Singular",
      reason: "about-love",
    },
    {
      match: "#Plural on [#Infinitive]",
      group: 0,
      tag: "Noun",
      reason: "on-stage",
    },
    { match: "any [#Infinitive]", group: 0, tag: "Noun", reason: "any-charge" },
    { match: "no [#Infinitive]", group: 0, tag: "Noun", reason: "no-doubt" },
    {
      match: "number of [#PresentTense]",
      group: 0,
      tag: "Noun",
      reason: "number-of-x",
    },
    {
      match: "(taught|teaches|learns|learned) [#PresentTense]",
      group: 0,
      tag: "Noun",
      reason: "teaches-x",
    },
    {
      match: "(try|use|attempt|build|make) [#Verb #Particle?]",
      notIf: "(#Copula|#Noun|sure|fun|up)",
      group: 0,
      tag: "Noun",
      reason: "do-verb",
    },
    {
      match: "^[#Infinitive] (is|was)",
      group: 0,
      tag: "Noun",
      reason: "checkmate-is",
    },
    {
      match: "#Infinitive much [#Infinitive]",
      group: 0,
      tag: "Noun",
      reason: "get-much",
    },
    {
      match: "[cause] #Pronoun #Verb",
      group: 0,
      tag: "Conjunction",
      reason: "cause-cuz",
    },
    {
      match: "the #Singular [#Infinitive] #Noun",
      group: 0,
      tag: "Noun",
      notIf: "#Pronoun",
      reason: "cardio-dance",
    },
    {
      match: "#Determiner #Modal [#Noun]",
      group: 0,
      tag: "PresentTense",
      reason: "should-smoke",
    },
    {
      match: "this [#Plural]",
      group: 0,
      tag: "PresentTense",
      notIf: "(#Preposition|#Date)",
      reason: "this-verbs",
    },
    {
      match: "#Noun that [#Plural]",
      group: 0,
      tag: "PresentTense",
      notIf: "(#Preposition|#Pronoun|way)",
      reason: "voice-that-rocks",
    },
    {
      match: "that [#Plural] to",
      group: 0,
      tag: "PresentTense",
      notIf: "#Preposition",
      reason: "that-leads-to",
    },
    {
      match:
        "(let|make|made) (him|her|it|#Person|#Place|#Organization)+ [#Singular] (a|an|the|it)",
      group: 0,
      tag: "Infinitive",
      reason: "let-him-glue",
    },
    {
      match: "#Verb (all|every|each|most|some|no) [#PresentTense]",
      notIf: "#Modal",
      group: 0,
      tag: "Noun",
      reason: "all-presentTense",
    },
    {
      match: "(had|have|#PastTense) #Adjective [#PresentTense]",
      group: 0,
      tag: "Noun",
      notIf: "better",
      reason: "adj-presentTense",
    },
    {
      match: "#Value #Adjective [#PresentTense]",
      group: 0,
      tag: "Noun",
      notIf: "#Copula",
      reason: "one-big-reason",
    },
    {
      match: "#PastTense #Adjective+ [#PresentTense]",
      group: 0,
      tag: "Noun",
      notIf: "(#Copula|better)",
      reason: "won-wide-support",
    },
    {
      match: "(many|few|several|couple) [#PresentTense]",
      group: 0,
      tag: "Noun",
      notIf: "#Copula",
      reason: "many-poses",
    },
    {
      match: "#Determiner #Adverb #Adjective [%Noun|Verb%]",
      group: 0,
      tag: "Noun",
      notIf: "#Copula",
      reason: "very-big-dream",
    },
    {
      match: "from #Noun to [%Noun|Verb%]",
      group: 0,
      tag: "Noun",
      reason: "start-to-finish",
    },
    {
      match: "(for|with|of) #Noun (and|or|not) [%Noun|Verb%]",
      group: 0,
      tag: "Noun",
      notIf: "#Pronoun",
      reason: "for-food-and-gas",
    },
    {
      match: "#Adjective #Adjective [#PresentTense]",
      group: 0,
      tag: "Noun",
      notIf: "#Copula",
      reason: "adorable-little-store",
    },
    {
      match: "#Gerund #Adverb? #Comparative [#PresentTense]",
      group: 0,
      tag: "Noun",
      notIf: "#Copula",
      reason: "higher-costs",
    },
    {
      match: "(#Noun && @hasComma) #Noun (and|or) [#PresentTense]",
      group: 0,
      tag: "Noun",
      notIf: "#Copula",
      reason: "noun-list",
    },
    {
      match: "(many|any|some|several) [#PresentTense] for",
      group: 0,
      tag: "Noun",
      reason: "any-verbs-for",
    },
    {
      match: "to #PresentTense #Noun [#PresentTense] #Preposition",
      group: 0,
      tag: "Noun",
      reason: "gas-exchange",
    },
    {
      match: "#PastTense (until|as|through|without) [#PresentTense]",
      group: 0,
      tag: "Noun",
      reason: "waited-until-release",
    },
    {
      match: "#Gerund like #Adjective? [#PresentTense]",
      group: 0,
      tag: "Plural",
      reason: "like-hot-cakes",
    },
    {
      match: "some #Adjective [#PresentTense]",
      group: 0,
      tag: "Noun",
      reason: "some-reason",
    },
    {
      match: "for some [#PresentTense]",
      group: 0,
      tag: "Noun",
      reason: "for-some-reason",
    },
    {
      match: "(same|some|the|that|a) kind of [#PresentTense]",
      group: 0,
      tag: "Noun",
      reason: "some-kind-of",
    },
    {
      match: "(same|some|the|that|a) type of [#PresentTense]",
      group: 0,
      tag: "Noun",
      reason: "some-type-of",
    },
    {
      match: "#Gerund #Adjective #Preposition [#PresentTense]",
      group: 0,
      tag: "Noun",
      reason: "doing-better-for-x",
    },
    {
      match: "(get|got|have) #Comparative [#PresentTense]",
      group: 0,
      tag: "Noun",
      reason: "got-better-aim",
    },
    {
      match: "whose [#PresentTense] #Copula",
      group: 0,
      tag: "Noun",
      reason: "whos-name-was",
    },
    {
      match: "#PhrasalVerb #Particle #Preposition [#PresentTense]",
      group: 0,
      tag: "Noun",
      reason: "given-up-on-x",
    },
    {
      match: "there (are|were) #Adjective? [#PresentTense]",
      group: 0,
      tag: "Plural",
      reason: "there-are",
    },
    {
      match: "#Value [#PresentTense] of",
      group: 0,
      notIf: "(one|1|#Copula|#Infinitive)",
      tag: "Plural",
      reason: "2-trains",
    },
    {
      match: "[#PresentTense] (are|were) #Adjective",
      group: 0,
      tag: "Plural",
      reason: "compromises-are-possible",
    },
    {
      match: "^[(hope|guess|thought|think)] #Pronoun #Verb",
      group: 0,
      tag: "Infinitive",
      reason: "suppose-i",
    },
    {
      match: "#Possessive #Adjective [#Verb]",
      group: 0,
      tag: "Noun",
      notIf: "#Copula",
      reason: "our-full-support",
    },
    {
      match: "[(tastes|smells)] #Adverb? #Adjective",
      group: 0,
      tag: "PresentTense",
      reason: "tastes-good",
    },
    {
      match: "#Copula #Gerund [#PresentTense] !by?",
      group: 0,
      tag: "Noun",
      notIf: "going",
      reason: "ignoring-commute",
    },
    {
      match: "#Determiner #Adjective? [(shed|thought|rose|bid|saw|spelt)]",
      group: 0,
      tag: "Noun",
      reason: "noun-past",
    },
    {
      match: "how to [%Noun|Verb%]",
      group: 0,
      tag: "Infinitive",
      reason: "how-to-noun",
    },
    {
      match: "which [%Noun|Verb%] #Noun",
      group: 0,
      tag: "Infinitive",
      reason: "which-boost-it",
    },
    {
      match: "#Gerund [%Plural|Verb%]",
      group: 0,
      tag: "Plural",
      reason: "asking-questions",
    },
    {
      match:
        "(ready|available|difficult|hard|easy|made|attempt|try) to [%Noun|Verb%]",
      group: 0,
      tag: "Infinitive",
      reason: "ready-to-noun",
    },
    {
      match: "(bring|went|go|drive|run|bike) to [%Noun|Verb%]",
      group: 0,
      tag: "Noun",
      reason: "bring-to-noun",
    },
    {
      match: "#Modal #Noun [%Noun|Verb%]",
      group: 0,
      tag: "Infinitive",
      reason: "would-you-look",
    },
    {
      match: "#Copula just [#Infinitive]",
      group: 0,
      tag: "Noun",
      reason: "is-just-spam",
    },
    {
      match: "^%Noun|Verb% %Plural|Verb%",
      tag: "Imperative #Plural",
      reason: "request-copies",
    },
    {
      match: "#Adjective #Plural and [%Plural|Verb%]",
      group: 0,
      tag: "#Plural",
      reason: "pickles-and-drinks",
    },
    {
      match: "#Determiner #Year [#Verb]",
      group: 0,
      tag: "Noun",
      reason: "the-1968-film",
    },
    {
      match: "#Determiner [#PhrasalVerb #Particle]",
      group: 0,
      tag: "Noun",
      reason: "the-break-up",
    },
    {
      match: "#Determiner [%Adj|Noun%] #Noun",
      group: 0,
      tag: "Adjective",
      notIf: "(#Pronoun|#Possessive|#ProperNoun)",
      reason: "the-individual-goals",
    },
    {
      match: "[%Noun|Verb%] or #Infinitive",
      group: 0,
      tag: "Infinitive",
      reason: "work-or-prepare",
    },
    {
      match: "to #Infinitive [#PresentTense]",
      group: 0,
      tag: "Noun",
      notIf: "(#Gerund|#Copula|help)",
      reason: "to-give-thanks",
    },
    { match: "[#Noun] me", group: 0, tag: "Verb", reason: "kills-me" },
    {
      match: "%Plural|Verb% %Plural|Verb%",
      tag: "#PresentTense #Plural",
      reason: "removes-wrinkles",
    },
  ],
  xb = [
    {
      match: "#Money and #Money #Currency?",
      tag: "Money",
      reason: "money-and-money",
    },
    {
      match: "#Value #Currency [and] #Value (cents|ore|centavos|sens)",
      group: 0,
      tag: "money",
      reason: "and-5-cents",
    },
    {
      match: "#Value (mark|rand|won|rub|ore)",
      tag: "#Money #Currency",
      reason: "4-mark",
    },
    { match: "a pound", tag: "#Money #Unit", reason: "a-pound" },
    { match: "#Value (pound|pounds)", tag: "#Money #Unit", reason: "4-pounds" },
  ],
  Cb = [
    {
      match: "[(half|quarter)] of? (a|an)",
      group: 0,
      tag: "Fraction",
      reason: "millionth",
    },
    {
      match: "#Adverb [half]",
      group: 0,
      tag: "Fraction",
      reason: "nearly-half",
    },
    { match: "[half] the", group: 0, tag: "Fraction", reason: "half-the" },
    { match: "#Cardinal and a half", tag: "Fraction", reason: "and-a-half" },
    {
      match: "#Value (halves|halfs|quarters)",
      tag: "Fraction",
      reason: "two-halves",
    },
    { match: "a #Ordinal", tag: "Fraction", reason: "a-quarter" },
    {
      match: "[#Cardinal+] (#Fraction && /s$/)",
      tag: "Fraction",
      reason: "seven-fifths",
    },
    {
      match: "[#Cardinal+ #Ordinal] of .",
      group: 0,
      tag: "Fraction",
      reason: "ordinal-of",
    },
    {
      match: "[(#NumericValue && #Ordinal)] of .",
      group: 0,
      tag: "Fraction",
      reason: "num-ordinal-of",
    },
    {
      match: "(a|one) #Cardinal?+ #Ordinal",
      tag: "Fraction",
      reason: "a-ordinal",
    },
    {
      match: "#Cardinal+ out? of every? #Cardinal",
      tag: "Fraction",
      reason: "out-of",
    },
  ],
  Db = [
    { match: "#Cardinal [second]", tag: "Unit", reason: "one-second" },
    {
      match:
        "!once? [(a|an)] (#Duration|hundred|thousand|million|billion|trillion)",
      group: 0,
      tag: "Value",
      reason: "a-is-one",
    },
    {
      match: "1 #Value #PhoneNumber",
      tag: "PhoneNumber",
      reason: "1-800-Value",
    },
    {
      match: "#NumericValue #PhoneNumber",
      tag: "PhoneNumber",
      reason: "(800) PhoneNumber",
    },
    {
      match: "#Demonym #Currency",
      tag: "Currency",
      reason: "demonym-currency",
    },
    {
      match: "#Value [(buck|bucks|grand)]",
      group: 0,
      tag: "Currency",
      reason: "value-bucks",
    },
    { match: "[#Value+] #Currency", group: 0, tag: "Money", reason: "15 usd" },
    {
      match: "[second] #Noun",
      group: 0,
      tag: "Ordinal",
      reason: "second-noun",
    },
    { match: "#Value+ [#Currency]", group: 0, tag: "Unit", reason: "5-yan" },
    {
      match: "#Value [(foot|feet)]",
      group: 0,
      tag: "Unit",
      reason: "foot-unit",
    },
    {
      match: "#Value [#Abbreviation]",
      group: 0,
      tag: "Unit",
      reason: "value-abbr",
    },
    { match: "#Value [k]", group: 0, tag: "Unit", reason: "value-k" },
    { match: "#Unit an hour", tag: "Unit", reason: "unit-an-hour" },
    { match: "(minus|negative) #Value", tag: "Value", reason: "minus-value" },
    {
      match: "#Value (point|decimal) #Value",
      tag: "Value",
      reason: "value-point-value",
    },
    {
      match: "#Determiner [(half|quarter)] #Ordinal",
      group: 0,
      tag: "Value",
      reason: "half-ordinal",
    },
    {
      match: "#Multiple+ and #Value",
      tag: "Value",
      reason: "magnitude-and-value",
    },
    {
      match: "#Value #Unit [(per|an) (hr|hour|sec|second|min|minute)]",
      group: 0,
      tag: "Unit",
      reason: "12-miles-per-second",
    },
    {
      match: "#Value [(square|cubic)] #Unit",
      group: 0,
      tag: "Unit",
      reason: "square-miles",
    },
  ],
  $b = [
    {
      match: "#Copula [(#Noun|#PresentTense)] #LastName",
      group: 0,
      tag: "FirstName",
      reason: "copula-noun-lastname",
    },
    {
      match:
        "(sister|pope|brother|father|aunt|uncle|grandpa|grandfather|grandma) #ProperNoun",
      tag: "Person",
      reason: "lady-titlecase",
      safe: !0,
    },
    {
      match: "#FirstName [#Determiner #Noun] #LastName",
      group: 0,
      tag: "Person",
      reason: "first-noun-last",
    },
    {
      match:
        "#ProperNoun (b|c|d|e|f|g|h|j|k|l|m|n|o|p|q|r|s|t|u|v|w|x|y|z) #ProperNoun",
      tag: "Person",
      reason: "titlecase-acronym-titlecase",
      safe: !0,
    },
    {
      match: "#Acronym #LastName",
      tag: "Person",
      reason: "acronym-lastname",
      safe: !0,
    },
    { match: "#Person (jr|sr|md)", tag: "Person", reason: "person-honorific" },
    {
      match: "#Honorific #Acronym",
      tag: "Person",
      reason: "Honorific-TitleCase",
    },
    {
      match: "#Person #Person the? #RomanNumeral",
      tag: "Person",
      reason: "roman-numeral",
    },
    {
      match: "#FirstName [/^[^aiurck]$/]",
      group: 0,
      tag: ["Acronym", "Person"],
      reason: "john-e",
    },
    {
      match: "#Noun van der? #Noun",
      tag: "Person",
      reason: "van der noun",
      safe: !0,
    },
    {
      match: "(king|queen|prince|saint|lady) of #Noun",
      tag: "Person",
      reason: "king-of-noun",
      safe: !0,
    },
    { match: "(prince|lady) #Place", tag: "Person", reason: "lady-place" },
    {
      match: "(king|queen|prince|saint) #ProperNoun",
      tag: "Person",
      notIf: "#Place",
      reason: "saint-foo",
    },
    {
      match: "al (#Person|#ProperNoun)",
      tag: "Person",
      reason: "al-borlen",
      safe: !0,
    },
    { match: "#FirstName de #Noun", tag: "Person", reason: "bill-de-noun" },
    {
      match: "#FirstName (bin|al) #Noun",
      tag: "Person",
      reason: "bill-al-noun",
    },
    {
      match: "#FirstName #Acronym #ProperNoun",
      tag: "Person",
      reason: "bill-acronym-title",
    },
    {
      match: "#FirstName #FirstName #ProperNoun",
      tag: "Person",
      reason: "bill-firstname-title",
    },
    {
      match: "#Honorific #FirstName? #ProperNoun",
      tag: "Person",
      reason: "dr-john-Title",
    },
    {
      match: "#FirstName the #Adjective",
      tag: "Person",
      reason: "name-the-great",
    },
    {
      match: "#ProperNoun (van|al|bin) #ProperNoun",
      tag: "Person",
      reason: "title-van-title",
      safe: !0,
    },
    {
      match: "#ProperNoun (de|du) la? #ProperNoun",
      tag: "Person",
      notIf: "#Place",
      reason: "title-de-title",
    },
    {
      match: "#Singular #Acronym #LastName",
      tag: "#FirstName #Person .",
      reason: "title-acro-noun",
      safe: !0,
    },
    {
      match: "[#ProperNoun] #Person",
      group: 0,
      tag: "Person",
      reason: "proper-person",
      safe: !0,
    },
    {
      match: "#Person [#ProperNoun #ProperNoun]",
      group: 0,
      tag: "Person",
      notIf: "#Possessive",
      reason: "three-name-person",
      safe: !0,
    },
    {
      match: "#FirstName #Acronym? [#ProperNoun]",
      group: 0,
      tag: "LastName",
      notIf: "#Possessive",
      reason: "firstname-titlecase",
    },
    {
      match: "#FirstName [#FirstName]",
      group: 0,
      tag: "LastName",
      reason: "firstname-firstname",
    },
    {
      match: "#FirstName #Acronym #Noun",
      tag: "Person",
      reason: "n-acro-noun",
      safe: !0,
    },
    {
      match: "#FirstName [(de|di|du|van|von)] #Person",
      group: 0,
      tag: "LastName",
      reason: "de-firstname",
    },
    {
      match:
        "[(lieutenant|corporal|sergeant|captain|qeen|king|admiral|major|colonel|marshal|president|queen|king)+] #ProperNoun",
      group: 0,
      tag: "Honorific",
      reason: "seargeant-john",
    },
    {
      match:
        "[(private|general|major|rear|prime|field|count|miss)] #Honorific? #Person",
      group: 0,
      tag: ["Honorific", "Person"],
      reason: "ambg-honorifics",
    },
    {
      match: "#Honorific #FirstName [#Singular]",
      group: 0,
      tag: "LastName",
      notIf: "#Possessive",
      reason: "dr-john-foo",
      safe: !0,
    },
    {
      match:
        "[(his|her) (majesty|honour|worship|excellency|honorable)] #Person",
      group: 0,
      tag: "Honorific",
      reason: "his-excellency",
    },
    {
      match: "#Honorific #Actor",
      tag: "Honorific",
      reason: "Lieutenant colonel",
    },
    {
      match: "(first|second|third|1st|2nd|3rd) #Actor",
      tag: "Honorific",
      reason: "first lady",
    },
    { match: "#Person #RomanNumeral", tag: "Person", reason: "louis-IV" },
  ],
  jb = [
    {
      match: "#FirstName #Noun$",
      tag: ". #LastName",
      notIf: "(#Possessive|#Organization|#Place|#Pronoun|@hasTitleCase)",
      reason: "firstname-noun",
    },
    {
      match: "%Person|Date% #Acronym? #ProperNoun",
      tag: "Person",
      reason: "jan-thierson",
    },
    {
      match: "%Person|Noun% #Acronym? #ProperNoun",
      tag: "Person",
      reason: "switch-person",
      safe: !0,
    },
    {
      match: "%Person|Noun% #Organization",
      tag: "Organization",
      reason: "olive-garden",
    },
    {
      match: "%Person|Verb% #Acronym? #ProperNoun",
      tag: "Person",
      reason: "verb-propernoun",
      ifNo: "#Actor",
    },
    {
      match:
        "[%Person|Verb%] (will|had|has|said|says|told|did|learned|wants|wanted)",
      group: 0,
      tag: "Person",
      reason: "person-said",
    },
    {
      match:
        "[%Person|Place%] (harbor|harbour|pier|town|city|place|dump|landfill)",
      group: 0,
      tag: "Place",
      reason: "sydney-harbour",
    },
    {
      match: "(west|east|north|south) [%Person|Place%]",
      group: 0,
      tag: "Place",
      reason: "east-sydney",
    },
    {
      match: "#Modal [%Person|Verb%]",
      group: 0,
      tag: "Verb",
      reason: "would-mark",
    },
    {
      match: "#Adverb [%Person|Verb%]",
      group: 0,
      tag: "Verb",
      reason: "really-mark",
    },
    {
      match: "[%Person|Verb%] (#Adverb|#Comparative)",
      group: 0,
      tag: "Verb",
      reason: "drew-closer",
    },
    { match: "%Person|Verb% #Person", tag: "Person", reason: "rob-smith" },
    {
      match: "%Person|Verb% #Acronym #ProperNoun",
      tag: "Person",
      reason: "rob-a-smith",
    },
    { match: "[will] #Verb", group: 0, tag: "Modal", reason: "will-verb" },
    {
      match: "(will && @isTitleCase) #ProperNoun",
      tag: "Person",
      reason: "will-name",
    },
    {
      match: "(#FirstName && !#Possessive) [#Singular] #Verb",
      group: 0,
      safe: !0,
      tag: "LastName",
      reason: "jack-layton",
    },
    {
      match: "^[#Singular] #Person #Verb",
      group: 0,
      safe: !0,
      tag: "Person",
      reason: "sherwood-anderson",
    },
    {
      match: "(a|an) [#Person]$",
      group: 0,
      unTag: "Person",
      reason: "a-warhol",
    },
  ],
  Nb = [
    {
      match: "#Copula (pretty|dead|full|well|sure) (#Adjective|#Noun)",
      tag: "#Copula #Adverb #Adjective",
      reason: "sometimes-adverb",
    },
    {
      match: "(#Pronoun|#Person) (had|#Adverb)? [better] #PresentTense",
      group: 0,
      tag: "Modal",
      reason: "i-better",
    },
    {
      match: "(#Modal|i|they|we|do) not? [like]",
      group: 0,
      tag: "PresentTense",
      reason: "modal-like",
    },
    {
      match: "#Noun #Adverb? [left]",
      group: 0,
      tag: "PastTense",
      reason: "left-verb",
    },
    {
      match: "will #Adverb? not? #Adverb? [be] #Gerund",
      group: 0,
      tag: "Copula",
      reason: "will-be-copula",
    },
    {
      match: "will #Adverb? not? #Adverb? [be] #Adjective",
      group: 0,
      tag: "Copula",
      reason: "be-copula",
    },
    {
      match: "[march] (up|down|back|toward)",
      notIf: "#Date",
      group: 0,
      tag: "Infinitive",
      reason: "march-to",
    },
    {
      match: "#Modal [march]",
      group: 0,
      tag: "Infinitive",
      reason: "must-march",
    },
    { match: "[may] be", group: 0, tag: "Verb", reason: "may-be" },
    {
      match: "[(subject|subjects|subjected)] to",
      group: 0,
      tag: "Verb",
      reason: "subject to",
    },
    { match: "[home] to", group: 0, tag: "PresentTense", reason: "home to" },
    {
      match: "[open] #Determiner",
      group: 0,
      tag: "Infinitive",
      reason: "open-the",
    },
    {
      match: "(were|was) being [#PresentTense]",
      group: 0,
      tag: "PastTense",
      reason: "was-being",
    },
    {
      match: "(had|has|have) [been /en$/]",
      group: 0,
      tag: "Auxiliary Participle",
      reason: "had-been-broken",
    },
    {
      match: "(had|has|have) [been /ed$/]",
      group: 0,
      tag: "Auxiliary PastTense",
      reason: "had-been-smoked",
    },
    {
      match: "(had|has) #Adverb? [been] #Adverb? #PastTense",
      group: 0,
      tag: "Auxiliary",
      reason: "had-been-adj",
    },
    {
      match: "(had|has) to [#Noun] (#Determiner|#Possessive)",
      group: 0,
      tag: "Infinitive",
      reason: "had-to-noun",
    },
    {
      match: "have [#PresentTense]",
      group: 0,
      tag: "PastTense",
      notIf: "(come|gotten)",
      reason: "have-read",
    },
    {
      match: "(does|will|#Modal) that [work]",
      group: 0,
      tag: "PastTense",
      reason: "does-that-work",
    },
    {
      match: "[(sound|sounds)] #Adjective",
      group: 0,
      tag: "PresentTense",
      reason: "sounds-fun",
    },
    {
      match: "[(look|looks)] #Adjective",
      group: 0,
      tag: "PresentTense",
      reason: "looks-good",
    },
    {
      match: "[(start|starts|stop|stops|begin|begins)] #Gerund",
      group: 0,
      tag: "Verb",
      reason: "starts-thinking",
    },
    { match: "(have|had) read", tag: "Modal #PastTense", reason: "read-read" },
    {
      match: "(is|was|were) [(under|over) #PastTense]",
      group: 0,
      tag: "Adverb Adjective",
      reason: "was-under-cooked",
    },
    {
      match: "[shit] (#Determiner|#Possessive|them)",
      group: 0,
      tag: "Verb",
      reason: "swear1-verb",
    },
    {
      match: "[damn] (#Determiner|#Possessive|them)",
      group: 0,
      tag: "Verb",
      reason: "swear2-verb",
    },
    {
      match: "[fuck] (#Determiner|#Possessive|them)",
      group: 0,
      tag: "Verb",
      reason: "swear3-verb",
    },
    {
      match: "#Plural that %Noun|Verb%",
      tag: ". #Preposition #Infinitive",
      reason: "jobs-that-work",
    },
    {
      match: "[works] for me",
      group: 0,
      tag: "PresentTense",
      reason: "works-for-me",
    },
    {
      match: "as #Pronoun [please]",
      group: 0,
      tag: "Infinitive",
      reason: "as-we-please",
    },
    {
      match: "[(co|mis|de|inter|intra|pre|re|un|out|under|over|counter)] #Verb",
      group: 0,
      tag: ["Verb", "Prefix"],
      notIf: "(#Copula|#PhrasalVerb)",
      reason: "co-write",
    },
    {
      match: "#PastTense and [%Adj|Past%]",
      group: 0,
      tag: "PastTense",
      reason: "dressed-and-left",
    },
    {
      match: "[%Adj|Past%] and #PastTense",
      group: 0,
      tag: "PastTense",
      reason: "dressed-and-left",
    },
    {
      match: "#Copula #Pronoun [%Adj|Past%]",
      group: 0,
      tag: "Adjective",
      reason: "is-he-stoked",
    },
    {
      match: "to [%Noun|Verb%] #Preposition",
      group: 0,
      tag: "Infinitive",
      reason: "to-dream-of",
    },
  ],
  Tb = [
    {
      match: "will (#Adverb|not)+? [have] (#Adverb|not)+? #Verb",
      group: 0,
      tag: "Auxiliary",
      reason: "will-have-vb",
    },
    {
      match: "[#Copula] (#Adverb|not)+? (#Gerund|#PastTense)",
      group: 0,
      tag: "Auxiliary",
      reason: "copula-walking",
    },
    {
      match: "[(#Modal|did)+] (#Adverb|not)+? #Verb",
      group: 0,
      tag: "Auxiliary",
      reason: "modal-verb",
    },
    {
      match:
        "#Modal (#Adverb|not)+? [have] (#Adverb|not)+? [had] (#Adverb|not)+? #Verb",
      group: 0,
      tag: "Auxiliary",
      reason: "would-have",
    },
    {
      match: "[(has|had)] (#Adverb|not)+? #PastTense",
      group: 0,
      tag: "Auxiliary",
      reason: "had-walked",
    },
    {
      match: "[(do|does|did|will|have|had|has|got)] (not|#Adverb)+? #Verb",
      group: 0,
      tag: "Auxiliary",
      reason: "have-had",
    },
    {
      match: "[about to] #Adverb? #Verb",
      group: 0,
      tag: ["Auxiliary", "Verb"],
      reason: "about-to",
    },
    {
      match: "#Modal (#Adverb|not)+? [be] (#Adverb|not)+? #Verb",
      group: 0,
      tag: "Auxiliary",
      reason: "would-be",
    },
    {
      match: "[(#Modal|had|has)] (#Adverb|not)+? [been] (#Adverb|not)+? #Verb",
      group: 0,
      tag: "Auxiliary",
      reason: "had-been",
    },
    {
      match: "[(be|being|been)] #Participle",
      group: 0,
      tag: "Auxiliary",
      reason: "being-driven",
    },
    {
      match: "[may] #Adverb? #Infinitive",
      group: 0,
      tag: "Auxiliary",
      reason: "may-want",
    },
    {
      match: "#Copula (#Adverb|not)+? [(be|being|been)] #Adverb+? #PastTense",
      group: 0,
      tag: "Auxiliary",
      reason: "being-walked",
    },
    {
      match: "will [be] #PastTense",
      group: 0,
      tag: "Auxiliary",
      reason: "will-be-x",
    },
    {
      match: "[(be|been)] (#Adverb|not)+? #Gerund",
      group: 0,
      tag: "Auxiliary",
      reason: "been-walking",
    },
    {
      match: "[used to] #PresentTense",
      group: 0,
      tag: "Auxiliary",
      reason: "used-to-walk",
    },
    {
      match: "#Copula (#Adverb|not)+? [going to] #Adverb+? #PresentTense",
      group: 0,
      tag: "Auxiliary",
      reason: "going-to-walk",
    },
    {
      match: "#Imperative [(me|him|her)]",
      group: 0,
      tag: "Reflexive",
      reason: "tell-him",
    },
    {
      match: "(is|was) #Adverb? [no]",
      group: 0,
      tag: "Negative",
      reason: "is-no",
    },
    {
      match: "[(been|had|became|came)] #PastTense",
      group: 0,
      notIf: "#PhrasalVerb",
      tag: "Auxiliary",
      reason: "been-told",
    },
    {
      match: "[(being|having|getting)] #Verb",
      group: 0,
      tag: "Auxiliary",
      reason: "being-born",
    },
    { match: "[be] #Gerund", group: 0, tag: "Auxiliary", reason: "be-walking" },
    {
      match: "[better] #PresentTense",
      group: 0,
      tag: "Modal",
      notIf: "(#Copula|#Gerund)",
      reason: "better-go",
    },
    { match: "even better", tag: "Adverb #Comparative", reason: "even-better" },
  ],
  Ob = [
    { match: "(#Verb && @hasHyphen) up", tag: "PhrasalVerb", reason: "foo-up" },
    {
      match: "(#Verb && @hasHyphen) off",
      tag: "PhrasalVerb",
      reason: "foo-off",
    },
    {
      match: "(#Verb && @hasHyphen) over",
      tag: "PhrasalVerb",
      reason: "foo-over",
    },
    {
      match: "(#Verb && @hasHyphen) out",
      tag: "PhrasalVerb",
      reason: "foo-out",
    },
    {
      match: "[#Verb (in|out|up|down|off|back)] (on|in)",
      notIf: "#Copula",
      tag: "PhrasalVerb Particle",
      reason: "walk-in-on",
    },
    {
      match: "(lived|went|crept|go) [on] for",
      group: 0,
      tag: "PhrasalVerb",
      reason: "went-on",
    },
    {
      match: "#Verb (up|down|in|on|for)$",
      tag: "PhrasalVerb #Particle",
      notIf: "#PhrasalVerb",
      reason: "come-down$",
    },
    {
      match: "help [(stop|end|make|start)]",
      group: 0,
      tag: "Infinitive",
      reason: "help-stop",
    },
    {
      match: "#PhrasalVerb (in && #Particle) #Determiner",
      tag: "#Verb #Preposition #Determiner",
      unTag: "PhrasalVerb",
      reason: "work-in-the",
    },
    {
      match: "[(stop|start|finish|help)] #Gerund",
      group: 0,
      tag: "Infinitive",
      reason: "start-listening",
    },
    {
      match:
        "#Verb (him|her|it|us|himself|herself|itself|everything|something) [(up|down)]",
      group: 0,
      tag: "Adverb",
      reason: "phrasal-pronoun-advb",
    },
  ],
  ka = "(i|we|they)",
  Ib = [
    {
      match: "^do not? [#Infinitive #Particle?]",
      notIf: ka,
      group: 0,
      tag: "Imperative",
      reason: "do-eat",
    },
    {
      match: "^please do? not? [#Infinitive #Particle?]",
      group: 0,
      tag: "Imperative",
      reason: "please-go",
    },
    {
      match: "^just do? not? [#Infinitive #Particle?]",
      group: 0,
      tag: "Imperative",
      reason: "just-go",
    },
    {
      match: "^[#Infinitive] it #Comparative",
      notIf: ka,
      group: 0,
      tag: "Imperative",
      reason: "do-it-better",
    },
    {
      match: "^[#Infinitive] it (please|now|again|plz)",
      notIf: ka,
      group: 0,
      tag: "Imperative",
      reason: "do-it-please",
    },
    {
      match: "^[#Infinitive] (#Adjective|#Adverb)$",
      group: 0,
      tag: "Imperative",
      notIf: "(so|such|rather|enough)",
      reason: "go-quickly",
    },
    {
      match: "^[#Infinitive] (up|down|over) #Determiner",
      group: 0,
      tag: "Imperative",
      reason: "turn-down",
    },
    {
      match:
        "^[#Infinitive] (your|my|the|a|an|any|each|every|some|more|with|on)",
      group: 0,
      notIf: "like",
      tag: "Imperative",
      reason: "eat-my-shorts",
    },
    {
      match: "^[#Infinitive] (him|her|it|us|me|there)",
      group: 0,
      tag: "Imperative",
      reason: "tell-him",
    },
    {
      match: "^[#Infinitive] #Adjective #Noun$",
      group: 0,
      tag: "Imperative",
      reason: "avoid-loud-noises",
    },
    {
      match: "^[#Infinitive] (#Adjective|#Adverb)? and #Infinitive",
      group: 0,
      tag: "Imperative",
      reason: "call-and-reserve",
    },
    {
      match: "^(go|stop|wait|hurry) please?$",
      tag: "Imperative",
      reason: "go",
    },
    {
      match: "^(somebody|everybody) [#Infinitive]",
      group: 0,
      tag: "Imperative",
      reason: "somebody-call",
    },
    {
      match: "^let (us|me) [#Infinitive]",
      group: 0,
      tag: "Imperative",
      reason: "lets-leave",
    },
    {
      match: "^[(shut|close|open|start|stop|end|keep)] #Determiner #Noun",
      group: 0,
      tag: "Imperative",
      reason: "shut-the-door",
    },
    {
      match: "^[#PhrasalVerb #Particle] #Determiner #Noun",
      group: 0,
      tag: "Imperative",
      reason: "turn-off-the-light",
    },
    {
      match: "^[go] to .",
      group: 0,
      tag: "Imperative",
      reason: "go-to-toronto",
    },
    {
      match: "^#Modal you [#Infinitive]",
      group: 0,
      tag: "Imperative",
      reason: "would-you-",
    },
    {
      match: "^never [#Infinitive]",
      group: 0,
      tag: "Imperative",
      reason: "never-stop",
    },
    {
      match: "^come #Infinitive",
      tag: "Imperative",
      notIf: "on",
      reason: "come-have",
    },
    {
      match: "^come and? #Infinitive",
      tag: "Imperative . Imperative",
      notIf: "#PhrasalVerb",
      reason: "come-and-have",
    },
    { match: "^stay (out|away|back)", tag: "Imperative", reason: "stay-away" },
    {
      match: "^[(stay|be|keep)] #Adjective",
      group: 0,
      tag: "Imperative",
      reason: "stay-cool",
    },
    {
      match: "^[keep it] #Adjective",
      group: 0,
      tag: "Imperative",
      reason: "keep-it-cool",
    },
    {
      match: "^do not [#Infinitive]",
      group: 0,
      tag: "Imperative",
      reason: "do-not-be",
    },
    {
      match: "[#Infinitive] (yourself|yourselves)",
      group: 0,
      tag: "Imperative",
      reason: "allow-yourself",
    },
    {
      match: "[#Infinitive] what .",
      group: 0,
      tag: "Imperative",
      reason: "look-what",
    },
    {
      match: "^[#Infinitive] #Gerund",
      group: 0,
      tag: "Imperative",
      reason: "keep-playing",
    },
    {
      match: "^[#Infinitive] (to|for|into|toward|here|there)",
      group: 0,
      tag: "Imperative",
      reason: "go-to",
    },
    {
      match: "^[#Infinitive] (and|or) #Infinitive",
      group: 0,
      tag: "Imperative",
      reason: "inf-and-inf",
    },
    {
      match: "^[%Noun|Verb%] to",
      group: 0,
      tag: "Imperative",
      reason: "commit-to",
    },
    {
      match: "^[#Infinitive] #Adjective? #Singular #Singular",
      group: 0,
      tag: "Imperative",
      reason: "maintain-eye-contact",
    },
    {
      match: "do not (forget|omit|neglect) to [#Infinitive]",
      group: 0,
      tag: "Imperative",
      reason: "do-not-forget",
    },
    {
      match:
        "^[(ask|wear|pay|look|help|show|watch|act|fix|kill|stop|start|turn|try|win)] #Noun",
      group: 0,
      tag: "Imperative",
      reason: "pay-attention",
    },
  ],
  Eb = [
    {
      match: "(that|which) were [%Adj|Gerund%]",
      group: 0,
      tag: "Gerund",
      reason: "that-were-growing",
    },
    {
      match: "#Gerund [#Gerund] #Plural",
      group: 0,
      tag: "Adjective",
      reason: "hard-working-fam",
    },
  ],
  Hb = [
    {
      match: "(got|were|was|is|are|am) (#PastTense|#Participle)",
      tag: "Passive",
      reason: "got-walked",
    },
    {
      match: "(was|were|is|are|am) being (#PastTense|#Participle)",
      tag: "Passive",
      reason: "was-being",
    },
    {
      match: "(had|have|has) been (#PastTense|#Participle)",
      tag: "Passive",
      reason: "had-been",
    },
    {
      match: "will be being? (#PastTense|#Participle)",
      tag: "Passive",
      reason: "will-be-cleaned",
    },
    {
      match: "#Noun [(#PastTense|#Participle)] by (the|a) #Noun",
      group: 0,
      tag: "Passive",
      reason: "suffered-by",
    },
  ];
let zb = [
  { match: "u r", tag: "#Pronoun #Copula", reason: "u r" },
  {
    match: "#Noun [(who|whom)]",
    group: 0,
    tag: "Determiner",
    reason: "captain-who",
  },
  {
    match: "[had] #Noun+ #PastTense",
    group: 0,
    tag: "Condition",
    reason: "had-he",
  },
  {
    match: "[were] #Noun+ to #Infinitive",
    group: 0,
    tag: "Condition",
    reason: "were-he",
  },
  {
    match: "some sort of",
    tag: "Adjective Noun Conjunction",
    reason: "some-sort-of",
  },
  {
    match: "of some sort",
    tag: "Conjunction Adjective Noun",
    reason: "of-some-sort",
  },
  {
    match: "[such] (a|an|is)? #Noun",
    group: 0,
    tag: "Determiner",
    reason: "such-skill",
  },
  {
    match: "[right] (before|after|in|into|to|toward)",
    group: 0,
    tag: "#Adverb",
    reason: "right-into",
  },
  {
    match: "#Preposition [about]",
    group: 0,
    tag: "Adjective",
    reason: "at-about",
  },
  {
    match: "(are|#Modal|see|do|for) [ya]",
    group: 0,
    tag: "Pronoun",
    reason: "are-ya",
  },
  {
    match: "[long live] .",
    group: 0,
    tag: "#Adjective #Infinitive",
    reason: "long-live",
  },
  { match: "[plenty] of", group: 0, tag: "#Uncountable", reason: "plenty-of" },
  {
    match: "(always|nearly|barely|practically) [there]",
    group: 0,
    tag: "Adjective",
    reason: "always-there",
  },
  {
    match: "[there] (#Adverb|#Pronoun)? #Copula",
    group: 0,
    tag: "There",
    reason: "there-is",
  },
  { match: "#Copula [there] .", group: 0, tag: "There", reason: "is-there" },
  {
    match: "#Modal #Adverb? [there]",
    group: 0,
    tag: "There",
    reason: "should-there",
  },
  {
    match: "^[do] (you|we|they)",
    group: 0,
    tag: "QuestionWord",
    reason: "do-you",
  },
  {
    match: "^[does] (he|she|it|#ProperNoun)",
    group: 0,
    tag: "QuestionWord",
    reason: "does-he",
  },
  {
    match: "#Determiner #Noun+ [who] #Verb",
    group: 0,
    tag: "Preposition",
    reason: "the-x-who",
  },
  {
    match: "#Determiner #Noun+ [which] #Verb",
    group: 0,
    tag: "Preposition",
    reason: "the-x-which",
  },
  { match: "a [while]", group: 0, tag: "Noun", reason: "a-while" },
  { match: "guess who", tag: "#Infinitive #QuestionWord", reason: "guess-who" },
  {
    match: "[fucking] !#Verb",
    group: 0,
    tag: "#Gerund",
    reason: "f-as-gerund",
  },
];
const Fb = [
    {
      match: "university of #Place",
      tag: "Organization",
      reason: "university-of-Foo",
    },
    { match: "#Noun (&|n) #Noun", tag: "Organization", reason: "Noun-&-Noun" },
    {
      match: "#Organization of the? #ProperNoun",
      tag: "Organization",
      reason: "org-of-place",
      safe: !0,
    },
    {
      match: "#Organization #Country",
      tag: "Organization",
      reason: "org-country",
    },
    {
      match: "#ProperNoun #Organization",
      tag: "Organization",
      notIf: "#FirstName",
      reason: "titlecase-org",
    },
    {
      match: "#ProperNoun (ltd|co|inc|dept|assn|bros)",
      tag: "Organization",
      reason: "org-abbrv",
    },
    {
      match: "the [#Acronym]",
      group: 0,
      tag: "Organization",
      reason: "the-acronym",
      safe: !0,
    },
    {
      match: "government of the? [#Place+]",
      tag: "Organization",
      reason: "government-of-x",
    },
    {
      match: "(health|school|commerce) board",
      tag: "Organization",
      reason: "school-board",
    },
    {
      match:
        "(nominating|special|conference|executive|steering|central|congressional) committee",
      tag: "Organization",
      reason: "special-comittee",
    },
    {
      match: "(world|global|international|national|#Demonym) #Organization",
      tag: "Organization",
      reason: "global-org",
    },
    {
      match: "#Noun+ (public|private) school",
      tag: "School",
      reason: "noun-public-school",
    },
    {
      match: "#Place+ #SportsTeam",
      tag: "SportsTeam",
      reason: "place-sportsteam",
    },
    {
      match: "(dc|atlanta|minnesota|manchester|newcastle|sheffield) united",
      tag: "SportsTeam",
      reason: "united-sportsteam",
    },
    { match: "#Place+ fc", tag: "SportsTeam", reason: "fc-sportsteam" },
    {
      match:
        "#Place+ #Noun{0,2} (club|society|group|team|committee|commission|association|guild|crew)",
      tag: "Organization",
      reason: "place-noun-society",
    },
  ],
  Vb = [
    {
      match:
        "(west|north|south|east|western|northern|southern|eastern)+ #Place",
      tag: "Region",
      reason: "west-norfolk",
    },
    {
      match:
        "#City [(al|ak|az|ar|ca|ct|dc|fl|ga|id|il|nv|nh|nj|ny|oh|pa|sc|tn|tx|ut|vt|pr)]",
      group: 0,
      tag: "Region",
      reason: "us-state",
    },
    { match: "portland [or]", group: 0, tag: "Region", reason: "portland-or" },
    {
      match:
        "#ProperNoun+ (cliff|place|range|pit|place|point|room|grounds|ruins)",
      tag: "Place",
      reason: "foo-point",
    },
    {
      match: "in [#ProperNoun] #Place",
      group: 0,
      tag: "Place",
      reason: "propernoun-place",
    },
    {
      match:
        "#Value #Noun (st|street|rd|road|crescent|cr|way|tr|terrace|avenue|ave)",
      tag: "Address",
      reason: "address-st",
    },
    { match: "(port|mount|mt) #ProperName", tag: "Place", reason: "port-name" },
  ],
  Gb = [
    { match: "[so] #Noun", group: 0, tag: "Conjunction", reason: "so-conj" },
    {
      match:
        "[(who|what|where|why|how|when)] #Noun #Copula #Adverb? (#Verb|#Adjective)",
      group: 0,
      tag: "Conjunction",
      reason: "how-he-is-x",
    },
    {
      match: "#Copula [(who|what|where|why|how|when)] #Noun",
      group: 0,
      tag: "Conjunction",
      reason: "when-he",
    },
    {
      match: "#Verb [that] #Pronoun",
      group: 0,
      tag: "Conjunction",
      reason: "said-that-he",
    },
    {
      match: "#Noun [that] #Copula",
      group: 0,
      tag: "Conjunction",
      reason: "that-are",
    },
    {
      match: "#Noun [that] #Verb #Adjective",
      group: 0,
      tag: "Conjunction",
      reason: "that-seem",
    },
    {
      match: "#Noun #Copula not? [that] #Adjective",
      group: 0,
      tag: "Adverb",
      reason: "that-adj",
    },
    {
      match: "#Verb #Adverb? #Noun [(that|which)]",
      group: 0,
      tag: "Preposition",
      reason: "that-prep",
    },
    {
      match: "@hasComma [which] (#Pronoun|#Verb)",
      group: 0,
      tag: "Preposition",
      reason: "which-copula",
    },
    {
      match: "#Noun [like] #Noun",
      group: 0,
      tag: "Preposition",
      reason: "noun-like",
    },
    {
      match: "^[like] #Determiner",
      group: 0,
      tag: "Preposition",
      reason: "like-the",
    },
    {
      match: "a #Noun [like] (#Noun|#Determiner)",
      group: 0,
      tag: "Preposition",
      reason: "a-noun-like",
    },
    { match: "#Adverb [like]", group: 0, tag: "Verb", reason: "really-like" },
    {
      match: "(not|nothing|never) [like]",
      group: 0,
      tag: "Preposition",
      reason: "nothing-like",
    },
    {
      match: "#Infinitive #Pronoun [like]",
      group: 0,
      tag: "Preposition",
      reason: "treat-them-like",
    },
    {
      match: "[#QuestionWord] (#Pronoun|#Determiner)",
      group: 0,
      tag: "Preposition",
      reason: "how-he",
    },
    {
      match: "[#QuestionWord] #Participle",
      group: 0,
      tag: "Preposition",
      reason: "when-stolen",
    },
    {
      match: "[how] (#Determiner|#Copula|#Modal|#PastTense)",
      group: 0,
      tag: "QuestionWord",
      reason: "how-is",
    },
    {
      match: "#Plural [(who|which|when)] .",
      group: 0,
      tag: "Preposition",
      reason: "people-who",
    },
  ],
  Sb = [
    {
      match: "holy (shit|fuck|hell)",
      tag: "Expression",
      reason: "swears-expression",
    },
    {
      match: "^[(well|so|okay|now)] !#Adjective?",
      group: 0,
      tag: "Expression",
      reason: "well-",
    },
    { match: "^come on", tag: "Expression", reason: "come-on" },
    {
      match: "(say|says|said) [sorry]",
      group: 0,
      tag: "Expression",
      reason: "say-sorry",
    },
    {
      match: "^(ok|alright|shoot|hell|anyways)",
      tag: "Expression",
      reason: "ok-",
    },
    { match: "^(say && @hasComma)", tag: "Expression", reason: "say-" },
    { match: "^(like && @hasComma)", tag: "Expression", reason: "like-" },
    {
      match: "^[(dude|man|girl)] #Pronoun",
      group: 0,
      tag: "Expression",
      reason: "dude-i",
    },
  ];
let Mb = [].concat(
  Hb,
  hb,
  fb,
  mb,
  pb,
  yb,
  vb,
  bb,
  kb,
  Pb,
  Ab,
  xb,
  Cb,
  Db,
  $b,
  jb,
  Nb,
  gb,
  Tb,
  Ob,
  Ib,
  Eb,
  zb,
  Fb,
  Vb,
  Gb,
  Sb,
);
const Bb = { two: { matches: Mb } };
let Pa = null;
const Lb = function (e) {
    const { world: t } = e,
      { model: n, methods: r } = t;
    Pa = Pa || r.one.buildNet(n.two.matches, t);
    let i = r.two.quickSplit(e.document).map((s) => {
        let l = s[0];
        return [l.index[0], l.index[1], l.index[1] + s.length];
      }),
      o = e.update(i);
    return (o.cache(), o.sweep(Pa), e.uncache(), e.unfreeze(), e);
  },
  Wb = (e) =>
    e.compute(["freeze", "lexicon", "preTagger", "postTagger", "unfreeze"]),
  qb = { postTagger: Lb, tagger: Wb },
  Kb = (e) => Math.round(e * 100) / 100;
function Jb(e) {
  ((e.prototype.confidence = function () {
    let t = 0,
      n = 0;
    return (
      this.docs.forEach((r) => {
        r.forEach((a) => {
          ((n += 1), (t += a.confidence || 1));
        });
      }),
      n === 0 ? 1 : Kb(t / n)
    );
  }),
    (e.prototype.tagger = function () {
      return this.compute(["tagger"]);
    }));
}
const _b = { api: Jb, compute: qb, model: Bb, hooks: ["postTagger"] },
  Ub = function (e) {
    return Object.keys(e.hooks).filter(
      (t) => !t.startsWith("#") && !t.startsWith("%"),
    );
  },
  Rb = function (e, t) {
    let n = Ub(t);
    if (n.length === 0) return e;
    e._cache || e.cache();
    let r = e._cache;
    return e.filter((a, i) => n.some((o) => r[i].has(o)));
  },
  Yb = function (e, t) {
    let n = t;
    typeof t == "string" && (n = this.buildNet([{ match: t }]));
    let r = this.tokenize(e),
      a = Rb(r, n);
    return a.found ? (a.compute(["index", "tagger"]), a.match(t)) : r.none();
  },
  Qb = { lib: { lazy: Yb } },
  Zb = function (e, t) {
    const n = e.methods.two.transform.verb.conjugate;
    let r = n(t, e.model);
    return e.has("#Gerund")
      ? r.Gerund
      : e.has("#PastTense")
        ? r.PastTense
        : e.has("#PresentTense")
          ? r.PresentTense
          : e.has("#Gerund")
            ? r.Gerund
            : t;
  },
  Xb = function (e, t) {
    let n = t;
    return (
      e.forEach((r) => {
        (r.has("#Infinitive") || (n = Zb(r, t)), r.replaceWith(n));
      }),
      e
    );
  },
  ev = function (e, t) {
    let n = t;
    if (e.has("#Plural")) {
      const r = e.methods.two.transform.noun.toPlural;
      n = r(t, e.model);
    }
    e.replaceWith(n, { possessives: !0 });
  },
  tv = function (e, t) {
    const { toAdverb: n } = e.methods.two.transform.adjective;
    let a = n(t);
    a && e.replaceWith(a);
  },
  nv = function (e, t) {
    const { toComparative: n, toSuperlative: r } =
      e.methods.two.transform.adjective;
    let a = t;
    (e.has("#Comparative")
      ? (a = n(a, e.model))
      : e.has("#Superlative") && (a = r(a, e.model)),
      a && e.replaceWith(a));
  },
  rv = function (e, t, n) {
    let r = e.split(/ /g).map((i) => i.toLowerCase().trim());
    ((r = r.filter((i) => i)), (r = r.map((i) => `{${i}}`).join(" ")));
    let a = this.match(r);
    return (
      n && (a = a.if(n)),
      a.has("#Verb")
        ? Xb(a, t)
        : a.has("#Noun")
          ? ev(a, t)
          : a.has("#Adverb")
            ? tv(a, t)
            : a.has("#Adjective")
              ? nv(a, t)
              : this
    );
  },
  av = function (e) {
    e.prototype.swap = rv;
  },
  iv = { api: av };
k.plugin(H1);
k.plugin(cb);
k.plugin(_b);
k.plugin(Qb);
k.plugin(iv);
const an = function (e) {
    const { fromComparative: t, fromSuperlative: n } =
      e.methods.two.transform.adjective;
    let r = e.text("normal");
    return e.has("#Comparative")
      ? t(r, e.model)
      : e.has("#Superlative")
        ? n(r, e.model)
        : r;
  },
  ov = function (e) {
    class t extends e {
      constructor(r, a, i) {
        (super(r, a, i), (this.viewType = "Adjectives"));
      }
      json(r = {}) {
        const {
          toAdverb: a,
          toNoun: i,
          toSuperlative: o,
          toComparative: s,
        } = this.methods.two.transform.adjective;
        return (
          (r.normal = !0),
          this.map((l) => {
            let u = l.toView().json(r)[0] || {},
              c = an(l);
            return (
              (u.adjective = {
                adverb: a(c, this.model),
                noun: i(c, this.model),
                superlative: o(c, this.model),
                comparative: s(c, this.model),
              }),
              u
            );
          }, [])
        );
      }
      adverbs() {
        return this.before("#Adverb+$").concat(this.after("^#Adverb+"));
      }
      conjugate(r) {
        const {
          toComparative: a,
          toSuperlative: i,
          toNoun: o,
          toAdverb: s,
        } = this.methods.two.transform.adjective;
        return this.getNth(r).map((l) => {
          let u = an(l);
          return {
            Adjective: u,
            Comparative: a(u, this.model),
            Superlative: i(u, this.model),
            Noun: o(u, this.model),
            Adverb: s(u, this.model),
          };
        }, []);
      }
      toComparative(r) {
        const { toComparative: a } = this.methods.two.transform.adjective;
        return this.getNth(r).map((i) => {
          let o = an(i),
            s = a(o, this.model);
          return i.replaceWith(s);
        });
      }
      toSuperlative(r) {
        const { toSuperlative: a } = this.methods.two.transform.adjective;
        return this.getNth(r).map((i) => {
          let o = an(i),
            s = a(o, this.model);
          return i.replaceWith(s);
        });
      }
      toAdverb(r) {
        const { toAdverb: a } = this.methods.two.transform.adjective;
        return this.getNth(r).map((i) => {
          let o = an(i),
            s = a(o, this.model);
          return i.replaceWith(s);
        });
      }
      toNoun(r) {
        const { toNoun: a } = this.methods.two.transform.adjective;
        return this.getNth(r).map((i) => {
          let o = an(i),
            s = a(o, this.model);
          return i.replaceWith(s);
        });
      }
    }
    ((e.prototype.adjectives = function (n) {
      let r = this.match("#Adjective");
      return ((r = r.getNth(n)), new t(r.document, r.pointer));
    }),
      (e.prototype.superlatives = function (n) {
        let r = this.match("#Superlative");
        return ((r = r.getNth(n)), new t(r.document, r.pointer));
      }),
      (e.prototype.comparatives = function (n) {
        let r = this.match("#Comparative");
        return ((r = r.getNth(n)), new t(r.document, r.pointer));
      }));
  },
  sv = { api: ov },
  lv = function (e) {
    return e.compute("root").text("root");
  },
  uv = function (e) {
    class t extends e {
      constructor(r, a, i) {
        (super(r, a, i), (this.viewType = "Adverbs"));
      }
      conjugate(r) {
        return this.getNth(r).map((a) => {
          let i = lv(a);
          return { Adverb: a.text("normal"), Adjective: i };
        }, []);
      }
      json(r = {}) {
        const a = this.methods.two.transform.adjective.fromAdverb;
        return (
          (r.normal = !0),
          this.map((i) => {
            let o = i.toView().json(r)[0] || {};
            return ((o.adverb = { adjective: a(o.normal) }), o);
          }, [])
        );
      }
    }
    e.prototype.adverbs = function (n) {
      let r = this.match("#Adverb");
      return ((r = r.getNth(n)), new t(r.document, r.pointer));
    };
  },
  cv = { api: uv },
  hv = function (e) {
    let t = e.match("@hasComma");
    return (
      (t = t.filter((n) => {
        if (
          n.growLeft(".").wordCount() === 1 ||
          n.growRight(". .").wordCount() === 1
        )
          return !1;
        let r = n.grow(".");
        return (
          (r = r.ifNo("@hasComma @hasComma")),
          (r = r.ifNo("@hasComma (and|or) .")),
          (r = r.ifNo("(#City && @hasComma) #Country")),
          (r = r.ifNo("(#WeekDay && @hasComma) #Date")),
          (r = r.ifNo("(#Date+ && @hasComma) #Value")),
          (r = r.ifNo("(#Adjective && @hasComma) #Adjective")),
          r.found
        );
      })),
      e.splitAfter(t)
    );
  },
  dv = function (e) {
    let t = e.parentheses();
    return (
      (t = t.filter(
        (n) => n.wordCount() >= 3 && n.has("#Verb") && n.has("#Noun"),
      )),
      e.splitOn(t)
    );
  },
  fv = function (e) {
    let t = e.quotations();
    return (
      (t = t.filter(
        (n) => n.wordCount() >= 3 && n.has("#Verb") && n.has("#Noun"),
      )),
      e.splitOn(t)
    );
  },
  mv = function (e) {
    let t = this;
    ((t = dv(t)),
      (t = fv(t)),
      (t = hv(t)),
      (t = t.splitAfter("(@hasEllipses|@hasSemicolon|@hasDash|@hasColon)")),
      (t = t.splitAfter("^#Pronoun (said|says)")),
      (t = t.splitBefore("(said|says) #ProperNoun$")),
      (t = t.splitBefore(". . if .{4}")),
      (t = t.splitBefore("and while")),
      (t = t.splitBefore("now that")),
      (t = t.splitBefore("ever since")),
      (t = t.splitBefore("(supposing|although)")),
      (t = t.splitBefore("even (while|if|though)")),
      (t = t.splitBefore("(whereas|whose)")),
      (t = t.splitBefore("as (though|if)")),
      (t = t.splitBefore("(til|until)")));
    let n = t.match("#Verb .* [but] .* #Verb", 0);
    n.found && (t = t.splitBefore(n));
    let r = t.if("if .{2,9} then .").match("then");
    return ((t = t.splitBefore(r)), typeof e == "number" && (t = t.get(e)), t);
  },
  pv = function (e) {
    let t = [],
      n = null;
    return (
      e.clauses().docs.forEach((i) => {
        (i.forEach((o) => {
          !o.chunk || o.chunk !== n
            ? ((n = o.chunk), t.push([o.index[0], o.index[1], o.index[1] + 1]))
            : (t[t.length - 1][2] = o.index[1] + 1);
        }),
          (n = null));
      }),
      e.update(t)
    );
  },
  gv = function (e) {
    class t extends e {
      constructor(r, a, i) {
        (super(r, a, i), (this.viewType = "Chunks"));
      }
      isVerb() {
        return this.filter((r) => r.has("<Verb>"));
      }
      isNoun() {
        return this.filter((r) => r.has("<Noun>"));
      }
      isAdjective() {
        return this.filter((r) => r.has("<Adjective>"));
      }
      isPivot() {
        return this.filter((r) => r.has("<Pivot>"));
      }
      debug() {
        return (this.toView().debug("chunks"), this);
      }
      update(r) {
        let a = new t(this.document, r);
        return ((a._cache = this._cache), a);
      }
    }
    ((e.prototype.chunks = function (n) {
      let r = pv(this);
      return ((r = r.getNth(n)), new t(this.document, r.pointer));
    }),
      (e.prototype.clauses = mv));
  },
  Ks = { this: "Noun", then: "Pivot" },
  yv = function (e) {
    for (let t = 0; t < e.length; t += 1)
      for (let n = 0; n < e[t].length; n += 1) {
        let r = e[t][n];
        if (Ks.hasOwnProperty(r.normal) === !0) {
          r.chunk = Ks[r.normal];
          continue;
        }
        if (r.tags.has("Verb")) {
          r.chunk = "Verb";
          continue;
        }
        if (r.tags.has("Noun") || r.tags.has("Determiner")) {
          r.chunk = "Noun";
          continue;
        }
        if (r.tags.has("Value")) {
          r.chunk = "Noun";
          continue;
        }
        if (r.tags.has("QuestionWord")) {
          r.chunk = "Pivot";
          continue;
        }
      }
  },
  bv = function (e) {
    for (let t = 0; t < e.length; t += 1)
      for (let n = 0; n < e[t].length; n += 1) {
        let r = e[t][n];
        if (r.chunk) continue;
        let a = e[t][n + 1],
          i = e[t][n - 1];
        if (r.tags.has("Adjective")) {
          if (i && i.tags.has("Copula")) {
            r.chunk = "Adjective";
            continue;
          }
          if (i && i.tags.has("Determiner")) {
            r.chunk = "Noun";
            continue;
          }
          if (a && a.tags.has("Noun")) {
            r.chunk = "Noun";
            continue;
          }
          continue;
        }
        if (r.tags.has("Adverb") || r.tags.has("Negative")) {
          if (i && i.tags.has("Adjective")) {
            r.chunk = "Adjective";
            continue;
          }
          if (i && i.tags.has("Verb")) {
            r.chunk = "Verb";
            continue;
          }
          if (a && a.tags.has("Adjective")) {
            r.chunk = "Adjective";
            continue;
          }
          if (a && a.tags.has("Verb")) {
            r.chunk = "Verb";
            continue;
          }
        }
      }
  },
  vv = [
    { match: "[that] #Determiner #Noun", group: 0, chunk: "Pivot" },
    { match: "#PastTense [that]", group: 0, chunk: "Pivot" },
    { match: "[so] #Determiner", group: 0, chunk: "Pivot" },
    { match: "#Copula #Adverb+? [#Adjective]", group: 0, chunk: "Adjective" },
    { match: "#Adjective and #Adjective", chunk: "Adjective" },
    { match: "#Adverb+ and #Adverb #Verb", chunk: "Verb" },
    { match: "#Gerund #Adjective$", chunk: "Verb" },
    { match: "#Gerund to #Verb", chunk: "Verb" },
    { match: "#PresentTense and #PresentTense", chunk: "Verb" },
    { match: "#Adverb #Negative", chunk: "Verb" },
    { match: "(want|wants|wanted) to #Infinitive", chunk: "Verb" },
    { match: "#Verb #Reflexive", chunk: "Verb" },
    { match: "#Verb [to] #Adverb? #Infinitive", group: 0, chunk: "Verb" },
    { match: "[#Preposition] #Gerund", group: 0, chunk: "Verb" },
    { match: "#Infinitive [that] <Noun>", group: 0, chunk: "Verb" },
    { match: "#Noun of #Determiner? #Noun", chunk: "Noun" },
    { match: "#Value+ #Adverb? #Adjective", chunk: "Noun" },
    { match: "the [#Adjective] #Noun", chunk: "Noun" },
    { match: "#Singular in #Determiner? #Singular", chunk: "Noun" },
    { match: "#Plural [in] #Determiner? #Noun", group: 0, chunk: "Pivot" },
    {
      match: "#Noun and #Determiner? #Noun",
      notIf: "(#Possessive|#Pronoun)",
      chunk: "Noun",
    },
  ];
let Aa = null;
const wv = function (e, t, n) {
  const { methods: r } = n;
  ((Aa = Aa || r.one.buildNet(vv, n)), e.sweep(Aa));
};
var Js = {};
const xa = function (e, t) {
    if ((typeof Nt > "u" || !Js ? self.env || {} : Js).DEBUG_CHUNKS) {
      let r = (e.normal + "'").padEnd(8);
      console.log(
        `  | '${r}  →  \x1B[34m${t.padEnd(12)}\x1B[0m \x1B[2m -fallback- \x1B[0m`,
      );
    }
    e.chunk = t;
  },
  kv = function (e) {
    for (let t = 0; t < e.length; t += 1)
      for (let n = 0; n < e[t].length; n += 1) {
        let r = e[t][n];
        r.chunk === void 0 &&
          (r.tags.has("Conjunction") || r.tags.has("Preposition")
            ? xa(r, "Pivot")
            : r.tags.has("Adverb")
              ? xa(r, "Verb")
              : (r.chunk = "Noun"));
      }
  },
  Pv = function (e) {
    let t = [],
      n = null;
    (e.forEach((r) => {
      for (let a = 0; a < r.length; a += 1) {
        let i = r[a];
        n && i.chunk === n
          ? t[t.length - 1].terms.push(i)
          : (t.push({ chunk: i.chunk, terms: [i] }), (n = i.chunk));
      }
    }),
      t.forEach((r) => {
        r.chunk === "Verb" &&
          (r.terms.find((i) => i.tags.has("Verb")) ||
            r.terms.forEach((i) => (i.chunk = null)));
      }));
  },
  Av = function (e) {
    const { document: t, world: n } = e;
    (yv(t), bv(t), wv(e, t, n), kv(t), Pv(t));
  },
  xv = { chunks: Av },
  Cv = { compute: xv, api: gv, hooks: ["chunks"] },
  br = /\./g,
  Dv = function (e) {
    class t extends e {
      constructor(r, a, i) {
        (super(r, a, i), (this.viewType = "Acronyms"));
      }
      strip() {
        return (
          this.docs.forEach((r) => {
            r.forEach((a) => {
              ((a.text = a.text.replace(br, "")),
                (a.normal = a.normal.replace(br, "")));
            });
          }),
          this
        );
      }
      addPeriods() {
        return (
          this.docs.forEach((r) => {
            r.forEach((a) => {
              ((a.text = a.text.replace(br, "")),
                (a.normal = a.normal.replace(br, "")),
                (a.text = a.text.split("").join(".") + "."),
                (a.normal = a.normal.split("").join(".") + "."));
            });
          }),
          this
        );
      }
    }
    e.prototype.acronyms = function (n) {
      let r = this.match("#Acronym");
      return ((r = r.getNth(n)), new t(r.document, r.pointer));
    };
  },
  hc = /\(/,
  dc = /\)/,
  $v = function (e, t) {
    for (; t < e.length; t += 1)
      if (e[t].post && dc.test(e[t].post)) {
        let [, n] = e[t].index;
        return ((n = n || 0), n);
      }
    return null;
  },
  jv = function (e) {
    let t = [];
    return (
      e.docs.forEach((n) => {
        for (let r = 0; r < n.length; r += 1) {
          let a = n[r];
          if (a.pre && hc.test(a.pre)) {
            let i = $v(n, r);
            if (i !== null) {
              let [o, s] = n[r].index;
              (t.push([o, s, i + 1, n[r].id]), (r = i));
            }
          }
        }
      }),
      e.update(t)
    );
  },
  Nv = function (e) {
    return (
      e.docs.forEach((t) => {
        t[0].pre = t[0].pre.replace(hc, "");
        let n = t[t.length - 1];
        n.post = n.post.replace(dc, "");
      }),
      e
    );
  },
  Tv = function (e) {
    class t extends e {
      constructor(r, a, i) {
        (super(r, a, i), (this.viewType = "Possessives"));
      }
      strip() {
        return Nv(this);
      }
    }
    e.prototype.parentheses = function (n) {
      let r = jv(this);
      return ((r = r.getNth(n)), new t(r.document, r.pointer));
    };
  },
  _s = /'s$/,
  Ov = function (e) {
    let t = e.match("#Possessive+");
    return (
      t.has("#Person") && (t = t.growLeft("#Person+")),
      t.has("#Place") && (t = t.growLeft("#Place+")),
      t.has("#Organization") && (t = t.growLeft("#Organization+")),
      t
    );
  },
  Iv = function (e) {
    class t extends e {
      constructor(r, a, i) {
        (super(r, a, i), (this.viewType = "Possessives"));
      }
      strip() {
        return (
          this.docs.forEach((r) => {
            r.forEach((a) => {
              ((a.text = a.text.replace(_s, "")),
                (a.normal = a.normal.replace(_s, "")));
            });
          }),
          this
        );
      }
    }
    e.prototype.possessives = function (n) {
      let r = Ov(this);
      return ((r = r.getNth(n)), new t(r.document, r.pointer));
    };
  },
  Xr = {
    '"': '"',
    "＂": "＂",
    "'": "'",
    "“": "”",
    "‘": "’",
    "‟": "”",
    "‛": "’",
    "„": "”",
    "⹂": "”",
    "‚": "’",
    "«": "»",
    "‹": "›",
    "‵": "′",
    "‶": "″",
    "‷": "‴",
    "〝": "〞",
    "`": "´",
    "〟": "〞",
  },
  to = RegExp("[" + Object.keys(Xr).join("") + "]"),
  Ev = RegExp("[" + Object.values(Xr).join("") + "]"),
  Hv = function (e, t) {
    const n = e[t].pre.match(to)[0] || "";
    if (!n || !Xr[n]) return null;
    const r = Xr[n];
    for (; t < e.length; t += 1) if (e[t].post && e[t].post.match(r)) return t;
    return null;
  },
  zv = function (e) {
    let t = [];
    return (
      e.docs.forEach((n) => {
        for (let r = 0; r < n.length; r += 1) {
          let a = n[r];
          if (a.pre && to.test(a.pre)) {
            let i = Hv(n, r);
            if (i !== null) {
              let [o, s] = n[r].index;
              (t.push([o, s, i + 1, n[r].id]), (r = i));
            }
          }
        }
      }),
      e.update(t)
    );
  },
  Fv = function (e) {
    e.docs.forEach((t) => {
      t[0].pre = t[0].pre.replace(to, "");
      let n = t[t.length - 1];
      n.post = n.post.replace(Ev, "");
    });
  },
  Vv = function (e) {
    class t extends e {
      constructor(r, a, i) {
        (super(r, a, i), (this.viewType = "Possessives"));
      }
      strip() {
        return Fv(this);
      }
    }
    e.prototype.quotations = function (n) {
      let r = zv(this);
      return ((r = r.getNth(n)), new t(r.document, r.pointer));
    };
  },
  Gv = function (e) {
    let t = this.splitAfter("@hasComma");
    return ((t = t.match("#PhoneNumber+")), (t = t.getNth(e)), t);
  },
  Sv = [
    ["hyphenated", "@hasHyphen ."],
    ["hashTags", "#HashTag"],
    ["emails", "#Email"],
    ["emoji", "#Emoji"],
    ["emoticons", "#Emoticon"],
    ["atMentions", "#AtMention"],
    ["urls", "#Url"],
    ["conjunctions", "#Conjunction"],
    ["prepositions", "#Preposition"],
    ["abbreviations", "#Abbreviation"],
    ["honorifics", "#Honorific"],
  ];
let Mv = [
  ["emojis", "emoji"],
  ["atmentions", "atMentions"],
];
const Bv = function (e) {
    (Sv.forEach((t) => {
      e.prototype[t[0]] = function (n) {
        let r = this.match(t[1]);
        return typeof n == "number" ? r.get(n) : r;
      };
    }),
      (e.prototype.phoneNumbers = Gv),
      Mv.forEach((t) => {
        e.prototype[t[0]] = e.prototype[t[1]];
      }));
  },
  Lv = /\//,
  Wv = function (e) {
    class t extends e {
      constructor(r, a, i) {
        (super(r, a, i), (this.viewType = "Slashes"));
      }
      split() {
        return this.map((r) => {
          let i = r.text().split(Lv);
          return (
            (r = r.replaceWith(i.join(" "))),
            r.growRight("(" + i.join("|") + ")+")
          );
        });
      }
    }
    e.prototype.slashes = function (n) {
      let r = this.match("#SlashedTerm");
      return ((r = r.getNth(n)), new t(r.document, r.pointer));
    };
  },
  qv = {
    api: function (e) {
      (Dv(e), Tv(e), Iv(e), Vv(e), Bv(e), Wv(e));
    },
  },
  vr = function (e, t) {
    e.docs.forEach((n) => {
      n.forEach(t);
    });
  },
  Us = {
    case: (e) => {
      vr(e, (t) => {
        t.text = t.text.toLowerCase();
      });
    },
    unicode: (e) => {
      const t = e.world,
        n = t.methods.one.killUnicode;
      vr(e, (r) => (r.text = n(r.text, t)));
    },
    whitespace: (e) => {
      vr(e, (t) => {
        ((t.post = t.post.replace(/\s+/g, " ")),
          (t.post = t.post.replace(/\s([.,?!:;])/g, "$1")),
          (t.pre = t.pre.replace(/\s+/g, "")));
      });
    },
    punctuation: (e) => {
      vr(e, (r) => {
        ((r.post = r.post.replace(/[–—-]/g, " ")),
          (r.post = r.post.replace(/[,:;]/g, "")),
          (r.post = r.post.replace(/\.{2,}/g, "")),
          (r.post = r.post.replace(/\?{2,}/g, "?")),
          (r.post = r.post.replace(/!{2,}/g, "!")),
          (r.post = r.post.replace(/\?!+/g, "?")));
      });
      let t = e.docs,
        n = t[t.length - 1];
      if (n && n.length > 0) {
        let r = n[n.length - 1];
        r.post = r.post.replace(/ /g, "");
      }
    },
    contractions: (e) => {
      e.contractions().expand();
    },
    acronyms: (e) => {
      e.acronyms().strip();
    },
    parentheses: (e) => {
      e.parentheses().strip();
    },
    possessives: (e) => {
      e.possessives().strip();
    },
    quotations: (e) => {
      e.quotations().strip();
    },
    emoji: (e) => {
      e.emojis().remove();
    },
    honorifics: (e) => {
      e.match("#Honorific+ #Person").honorifics().remove();
    },
    adverbs: (e) => {
      e.adverbs().remove();
    },
    nouns: (e) => {
      e.nouns().toSingular();
    },
    verbs: (e) => {
      e.verbs().toInfinitive();
    },
    numbers: (e) => {
      e.numbers().toNumber();
    },
    debullet: (e) => {
      const t = /^\s*([-–—*•])\s*$/;
      return (
        e.docs.forEach((n) => {
          t.test(n[0].pre) && (n[0].pre = n[0].pre.replace(t, ""));
        }),
        e
      );
    },
  },
  Ca = (e) => e.split("|").reduce((t, n) => ((t[n] = !0), t), {}),
  Da = "unicode|punctuation|whitespace|acronyms",
  Rs = "|case|contractions|parentheses|quotations|emoji|honorifics|debullet",
  Kv = "|possessives|adverbs|nouns|verbs",
  Jv = { light: Ca(Da), medium: Ca(Da + Rs), heavy: Ca(Da + Rs + Kv) };
function _v(e) {
  e.prototype.normalize = function (t = "light") {
    return (
      typeof t == "string" && (t = Jv[t]),
      Object.keys(t).forEach((n) => {
        Us.hasOwnProperty(n) && Us[n](this, t[n]);
      }),
      this
    );
  };
}
const Uv = { api: _v },
  Rv = function (e) {
    let t = e.clauses().match("<Noun>"),
      n = t.match("@hasComma");
    return (
      (n = n.not("#Place")),
      n.found && (t = t.splitAfter(n)),
      (t = t.splitOn("#Expression")),
      (t = t.splitOn("(he|she|we|you|they|i)")),
      (t = t.splitOn("(#Noun|#Adjective) [(he|him|she|it)]", 0)),
      (t = t.splitOn("[(he|him|she|it)] (#Determiner|#Value)", 0)),
      (t = t.splitBefore("#Noun [(the|a|an)] #Adjective? #Noun", 0)),
      (t = t.splitOn("[(here|there)] #Noun", 0)),
      (t = t.splitOn("[#Noun] (here|there)", 0)),
      (t = t.splitBefore("(our|my|their|your)")),
      (t = t.splitOn("#Noun [#Determiner]", 0)),
      (t = t.if("#Noun")),
      t
    );
  },
  Ys = [
    "after",
    "although",
    "as if",
    "as long as",
    "as",
    "because",
    "before",
    "even if",
    "even though",
    "ever since",
    "if",
    "in order that",
    "provided that",
    "since",
    "so that",
    "than",
    "that",
    "though",
    "unless",
    "until",
    "what",
    "whatever",
    "when",
    "whenever",
    "where",
    "whereas",
    "wherever",
    "whether",
    "which",
    "whichever",
    "who",
    "whoever",
    "whom",
    "whomever",
    "whose",
  ],
  Yv = function (e) {
    if (e.before("#Preposition$").found) return !0;
    if (!e.before().found) return !1;
    for (let n = 0; n < Ys.length; n += 1) if (e.has(Ys[n])) return !0;
    return !1;
  },
  Qv =
    "(#Pronoun|#Place|#Value|#Person|#Uncountable|#Month|#WeekDay|#Holiday|#Possessive)",
  Zv = function (e, t) {
    if (e.has("#Plural") || e.has("#Noun and #Noun") || e.has("(we|they)"))
      return !0;
    if (t.has(Qv) === !0 || e.has("#Singular")) return !1;
    let n = t.text("normal");
    return n.length > 3 && n.endsWith("s") && !n.endsWith("ss");
  },
  Xv = function (e) {
    let t = e.clone();
    return (
      (t = t.match("#Noun+")),
      (t = t.remove("(#Adjective|#Preposition|#Determiner|#Value)")),
      (t = t.not("#Possessive")),
      (t = t.first()),
      t.found ? t : e
    );
  },
  vt = function (e) {
    let t = Xv(e);
    return {
      determiner: e.match("#Determiner").eq(0),
      adjectives: e.match("#Adjective"),
      number: e.values(),
      isPlural: Zv(e, t),
      isSubordinate: Yv(e),
      root: t,
    };
  },
  Qs = (e) => e.text(),
  ew = (e) => e.json({ terms: !1, normal: !0 }).map((t) => t.normal),
  tw = function (e) {
    let t = null;
    if (!e.found) return t;
    let n = e.values(0);
    return n.found ? (n.parse()[0] || {}).num : t;
  },
  nw = function (e) {
    let t = vt(e);
    return {
      root: Qs(t.root),
      number: tw(t.number),
      determiner: Qs(t.determiner),
      adjectives: ew(t.adjectives),
      isPlural: t.isPlural,
      isSubordinate: t.isSubordinate,
    };
  },
  fc = function (e) {
    return !e.has("^(#Uncountable|#ProperNoun|#Place|#Pronoun|#Acronym)+$");
  },
  rw = { tags: !0 },
  aw = function (e, t) {
    if (
      t.isPlural === !0 ||
      (t.root.has("#Possessive") && (t.root = t.root.possessives().strip()),
      !fc(t.root))
    )
      return e;
    const { methods: n, model: r } = e.world,
      { toPlural: a } = n.two.transform.noun;
    let i = t.root.text({ keepPunct: !1 }),
      o = a(i, r);
    (e.match(t.root).replaceWith(o, rw).tag("Plural", "toPlural"),
      t.determiner.has("(a|an)") && e.remove(t.determiner));
    let s = t.root.after("not? #Adverb+? [#Copula]", 0);
    return (
      s.found &&
        (s.has("is")
          ? e.replace(s, "are")
          : s.has("was") && e.replace(s, "were")),
      e
    );
  },
  iw = { tags: !0 },
  ow = function (e, t) {
    if (t.isPlural === !1) return e;
    const { methods: n, model: r } = e.world,
      { toSingular: a } = n.two.transform.noun;
    let i = t.root.text("normal"),
      o = a(i, r);
    return (e.replace(t.root, o, iw).tag("Singular", "toPlural"), e);
  },
  sw = function (e) {
    class t extends e {
      constructor(r, a, i) {
        (super(r, a, i), (this.viewType = "Nouns"));
      }
      parse(r) {
        return this.getNth(r).map(vt);
      }
      json(r) {
        let a = typeof r == "object" ? r : {};
        return this.getNth(r).map((i) => {
          let o = i.toView().json(a)[0] || {};
          return (a && a.noun !== !1 && (o.noun = nw(i)), o);
        }, []);
      }
      conjugate(r) {
        const a = this.world.methods.two.transform.noun;
        return this.getNth(r).map((i) => {
          let o = vt(i),
            s = o.root.compute("root").text("root"),
            l = { Singular: s };
          return (
            fc(o.root) && (l.Plural = a.toPlural(s, this.model)),
            l.Singular === l.Plural && delete l.Plural,
            l
          );
        }, []);
      }
      isPlural(r) {
        return this.filter((i) => vt(i).isPlural).getNth(r);
      }
      isSingular(r) {
        return this.filter((i) => !vt(i).isPlural).getNth(r);
      }
      adjectives(r) {
        let a = this.update([]);
        return (
          this.forEach((i) => {
            let o = vt(i).adjectives;
            o.found && (a = a.concat(o));
          }),
          a.getNth(r)
        );
      }
      toPlural(r) {
        return this.getNth(r).map((a) => aw(a, vt(a)));
      }
      toSingular(r) {
        return this.getNth(r).map((a) => {
          let i = vt(a);
          return ow(a, i);
        });
      }
      update(r) {
        let a = new t(this.document, r);
        return ((a._cache = this._cache), a);
      }
    }
    e.prototype.nouns = function (n) {
      let r = Rv(this);
      return ((r = r.getNth(n)), new t(this.document, r.pointer));
    };
  },
  lw = { api: sw },
  uw = function (e, t) {
    let n = e.match("#Fraction+");
    return (
      (n = n.filter((r) => !r.lookBehind("#Value and$").found)),
      (n = n.notIf("#Value seconds")),
      n
    );
  },
  cw = (e) => {
    const t = [
      { reg: /^(minus|negative)[\s-]/i, mult: -1 },
      { reg: /^(a\s)?half[\s-](of\s)?/i, mult: 0.5 },
    ];
    for (let n = 0; n < t.length; n++)
      if (t[n].reg.test(e) === !0)
        return { amount: t[n].mult, str: e.replace(t[n].reg, "") };
    return { amount: 1, str: e };
  },
  U = {
    ones: {
      zeroth: 0,
      first: 1,
      second: 2,
      third: 3,
      fourth: 4,
      fifth: 5,
      sixth: 6,
      seventh: 7,
      eighth: 8,
      ninth: 9,
      zero: 0,
      one: 1,
      two: 2,
      three: 3,
      four: 4,
      five: 5,
      six: 6,
      seven: 7,
      eight: 8,
      nine: 9,
    },
    teens: {
      tenth: 10,
      eleventh: 11,
      twelfth: 12,
      thirteenth: 13,
      fourteenth: 14,
      fifteenth: 15,
      sixteenth: 16,
      seventeenth: 17,
      eighteenth: 18,
      nineteenth: 19,
      ten: 10,
      eleven: 11,
      twelve: 12,
      thirteen: 13,
      fourteen: 14,
      fifteen: 15,
      sixteen: 16,
      seventeen: 17,
      eighteen: 18,
      nineteen: 19,
    },
    tens: {
      twentieth: 20,
      thirtieth: 30,
      fortieth: 40,
      fourtieth: 40,
      fiftieth: 50,
      sixtieth: 60,
      seventieth: 70,
      eightieth: 80,
      ninetieth: 90,
      twenty: 20,
      thirty: 30,
      forty: 40,
      fourty: 40,
      fifty: 50,
      sixty: 60,
      seventy: 70,
      eighty: 80,
      ninety: 90,
    },
    multiples: {
      hundredth: 100,
      thousandth: 1e3,
      millionth: 1e6,
      billionth: 1e9,
      trillionth: 1e12,
      quadrillionth: 1e15,
      quintillionth: 1e18,
      sextillionth: 1e21,
      septillionth: 1e24,
      hundred: 100,
      thousand: 1e3,
      million: 1e6,
      billion: 1e9,
      trillion: 1e12,
      quadrillion: 1e15,
      quintillion: 1e18,
      sextillion: 1e21,
      septillion: 1e24,
      grand: 1e3,
    },
  },
  hw = (e, t) => {
    if (U.ones.hasOwnProperty(e)) {
      if (t.ones || t.teens) return !1;
    } else if (U.teens.hasOwnProperty(e)) {
      if (t.ones || t.teens || t.tens) return !1;
    } else if (U.tens.hasOwnProperty(e) && (t.ones || t.teens || t.tens))
      return !1;
    return !0;
  },
  dw = function (e) {
    let t = "0.";
    for (let n = 0; n < e.length; n++) {
      let r = e[n];
      if (U.ones.hasOwnProperty(r) === !0) t += U.ones[r];
      else if (U.teens.hasOwnProperty(r) === !0) t += U.teens[r];
      else if (U.tens.hasOwnProperty(r) === !0) t += U.tens[r];
      else if (/^[0-9]$/.test(r) === !0) t += r;
      else return 0;
    }
    return parseFloat(t);
  },
  fw = (e) => (
    (e = e.replace(/1st$/, "1")),
    (e = e.replace(/2nd$/, "2")),
    (e = e.replace(/3rd$/, "3")),
    (e = e.replace(/([4567890])r?th$/, "$1")),
    (e = e.replace(/^[$€¥£¢]/, "")),
    (e = e.replace(/[%$€¥£¢]$/, "")),
    (e = e.replace(/,/g, "")),
    (e = e.replace(/([0-9])([a-z\u00C0-\u00FF]{1,2})$/, "$1")),
    e
  ),
  mw = /^([0-9,. ]+)\/([0-9,. ]+)$/,
  Zs = { "a few": 3, "a couple": 2, "a dozen": 12, "two dozen": 24, zero: 0 },
  wr = (e) => Object.keys(e).reduce((t, n) => ((t += e[n]), t), 0),
  bi = function (e) {
    if (Zs.hasOwnProperty(e) === !0) return Zs[e];
    if (e === "a" || e === "an") return 1;
    const t = cw(e);
    e = t.str;
    let n = null,
      r = {},
      a = 0,
      i = !1;
    const o = e.split(/[ -]/);
    for (let s = 0; s < o.length; s++) {
      let l = o[s];
      if (((l = fw(l)), !l || l === "and")) continue;
      if (l === "-" || l === "negative") {
        i = !0;
        continue;
      }
      if (
        (l.charAt(0) === "-" && ((i = !0), (l = l.substring(1))), l === "point")
      )
        return (
          (a += wr(r)),
          (a += dw(o.slice(s + 1, o.length))),
          (a *= t.amount),
          a
        );
      const u = l.match(mw);
      if (u) {
        const c = parseFloat(u[1].replace(/[, ]/g, "")),
          h = parseFloat(u[2].replace(/[, ]/g, ""));
        h && (a += c / h || 0);
        continue;
      }
      if (
        (U.tens.hasOwnProperty(l) &&
          r.ones &&
          Object.keys(r).length === 1 &&
          ((a = r.ones * 100), (r = {})),
        hw(l, r) === !1)
      )
        return null;
      if (/^[0-9.]+$/.test(l)) r.ones = parseFloat(l);
      else if (U.ones.hasOwnProperty(l) === !0) r.ones = U.ones[l];
      else if (U.teens.hasOwnProperty(l) === !0) r.teens = U.teens[l];
      else if (U.tens.hasOwnProperty(l) === !0) r.tens = U.tens[l];
      else if (U.multiples.hasOwnProperty(l) === !0) {
        let c = U.multiples[l];
        if (c === n) return null;
        if (c === 100 && o[s + 1] !== void 0) {
          const h = o[s + 1];
          U.multiples[h] && ((c *= U.multiples[h]), (s += 1));
        }
        n === null || c < n
          ? ((a += (wr(r) || 1) * c), (n = c), (r = {}))
          : ((a += wr(r)), (n = c), (a = (a || 1) * c), (r = {}));
      }
    }
    return (
      (a += wr(r)),
      (a *= t.amount),
      (a *= i ? -1 : 1),
      a === 0 && Object.keys(r).length === 0 ? null : a
    );
  },
  Xs = /s$/,
  qn = function (e) {
    let t = e.text("reduced");
    return bi(t);
  };
let ea = { half: 2, halve: 2, quarter: 4 };
const pw = function (e) {
    let n = e
      .text("reduced")
      .match(/^([-+]?[0-9]+)\/([-+]?[0-9]+)(st|nd|rd|th)?s?$/);
    return n && n[1] && n[0]
      ? { numerator: Number(n[1]), denominator: Number(n[2]) }
      : null;
  },
  gw = function (e) {
    let t = e.match("[<num>#Value+] out of every? [<den>#Value+]");
    if (t.found !== !0) return null;
    let { num: n, den: r } = t.groups();
    return !n || !r || ((n = qn(n)), (r = qn(r)), !n || !r)
      ? null
      : typeof n == "number" && typeof r == "number"
        ? { numerator: n, denominator: r }
        : null;
  },
  yw = function (e) {
    let t = e.match("[<num>(#Cardinal|a)+] [<den>#Fraction+]");
    if (t.found !== !0) return null;
    let { num: n, den: r } = t.groups();
    n.has("a") ? (n = 1) : (n = qn(n));
    let a = r.text("reduced");
    return (
      Xs.test(a) && ((a = a.replace(Xs, "")), (r = r.replaceWith(a))),
      ea.hasOwnProperty(a) ? (r = ea[a]) : (r = qn(r)),
      typeof n == "number" && typeof r == "number"
        ? { numerator: n, denominator: r }
        : null
    );
  },
  bw = function (e) {
    let t = e.match("^#Ordinal$");
    return t.found !== !0
      ? null
      : e.lookAhead("^of .")
        ? { numerator: 1, denominator: qn(t) }
        : null;
  },
  vw = function (e) {
    let t = e.text("reduced");
    return ea.hasOwnProperty(t) ? { numerator: 1, denominator: ea[t] } : null;
  },
  ww = (e) => {
    let t = Math.round(e * 1e3) / 1e3;
    return t === 0 && e !== 0 ? e : t;
  },
  at = function (e) {
    e = e.clone();
    let t = vw(e) || pw(e) || gw(e) || yw(e) || bw(e) || null;
    return (
      t !== null &&
        t.numerator &&
        t.denominator &&
        ((t.decimal = t.numerator / t.denominator),
        (t.decimal = ww(t.decimal))),
      t
    );
  },
  no = function (e) {
    if (e < 1e6) return String(e);
    let t;
    return (
      typeof e == "number" ? (t = e.toFixed(0)) : (t = e),
      t.indexOf("e+") === -1
        ? t
        : t
            .replace(".", "")
            .split("e+")
            .reduce(function (n, r) {
              return n + Array(r - n.length + 2).join(0);
            })
    );
  },
  kr = [
    ["ninety", 90],
    ["eighty", 80],
    ["seventy", 70],
    ["sixty", 60],
    ["fifty", 50],
    ["forty", 40],
    ["thirty", 30],
    ["twenty", 20],
  ],
  el = [
    "",
    "one",
    "two",
    "three",
    "four",
    "five",
    "six",
    "seven",
    "eight",
    "nine",
    "ten",
    "eleven",
    "twelve",
    "thirteen",
    "fourteen",
    "fifteen",
    "sixteen",
    "seventeen",
    "eighteen",
    "nineteen",
  ],
  kw = [
    [1e24, "septillion"],
    [1e20, "hundred sextillion"],
    [1e21, "sextillion"],
    [1e20, "hundred quintillion"],
    [1e18, "quintillion"],
    [1e17, "hundred quadrillion"],
    [1e15, "quadrillion"],
    [1e14, "hundred trillion"],
    [1e12, "trillion"],
    [1e11, "hundred billion"],
    [1e9, "billion"],
    [1e8, "hundred million"],
    [1e6, "million"],
    [1e5, "hundred thousand"],
    [1e3, "thousand"],
    [100, "hundred"],
    [1, "one"],
  ],
  Pw = function (e) {
    let t = e,
      n = [];
    return (
      kw.forEach((r) => {
        if (e >= r[0]) {
          let a = Math.floor(t / r[0]);
          ((t -= a * r[0]), a && n.push({ unit: r[1], count: a }));
        }
      }),
      n
    );
  },
  Aw = function (e) {
    let t = [];
    if (e > 100) return t;
    for (let n = 0; n < kr.length; n++)
      e >= kr[n][1] && ((e -= kr[n][1]), t.push(kr[n][0]));
    return (el[e] && t.push(el[e]), t);
  },
  xw = (e) => {
    const t = [
      "zero",
      "one",
      "two",
      "three",
      "four",
      "five",
      "six",
      "seven",
      "eight",
      "nine",
    ];
    let n = [],
      a = no(e).match(/\.([0-9]+)/);
    if (!a || !a[0]) return n;
    n.push("point");
    let i = a[0].split("");
    for (let o = 0; o < i.length; o++) n.push(t[i[o]]);
    return n;
  },
  Kn = function (e) {
    let t = e.num;
    if (t === 0 || t === "0") return "zero";
    t > 1e21 && (t = no(t));
    let n = [];
    t < 0 && (n.push("minus"), (t = Math.abs(t)));
    let r = Pw(t);
    for (let a = 0; a < r.length; a++) {
      let i = r[a].unit;
      (i === "one" && ((i = ""), n.length > 1 && n.push("and")),
        (n = n.concat(Aw(r[a].count))),
        n.push(i));
    }
    return (
      (n = n.concat(xw(t))),
      (n = n.filter((a) => a)),
      n.length === 0 && (n[0] = ""),
      n.join(" ")
    );
  },
  Cw = function (e) {
    if (!e.numerator || !e.denominator) return "";
    let t = Kn({ num: e.numerator }),
      n = Kn({ num: e.denominator });
    return `${t} out of ${n}`;
  },
  tl = {
    one: "first",
    two: "second",
    three: "third",
    five: "fifth",
    eight: "eighth",
    nine: "ninth",
    twelve: "twelfth",
    twenty: "twentieth",
    thirty: "thirtieth",
    forty: "fortieth",
    fourty: "fourtieth",
    fifty: "fiftieth",
    sixty: "sixtieth",
    seventy: "seventieth",
    eighty: "eightieth",
    ninety: "ninetieth",
  },
  mc = (e) => {
    let t = Kn(e).split(" "),
      n = t[t.length - 1];
    return (
      tl.hasOwnProperty(n)
        ? (t[t.length - 1] = tl[n])
        : (t[t.length - 1] = n.replace(/y$/, "i") + "th"),
      t.join(" ")
    );
  },
  Dw = function (e) {
    if (!e.numerator || !e.denominator) return "";
    let t = Kn({ num: e.numerator }),
      n = mc({ num: e.denominator });
    return (
      e.denominator === 2 && (n = "half"),
      t && n ? (e.numerator !== 1 && (n += "s"), `${t} ${n}`) : ""
    );
  },
  $w = function (e) {
    class t extends e {
      constructor(r, a, i) {
        (super(r, a, i), (this.viewType = "Fractions"));
      }
      parse(r) {
        return this.getNth(r).map(at);
      }
      get(r) {
        return this.getNth(r).map(at);
      }
      json(r) {
        return this.getNth(r).map((a) => {
          let i = a.toView().json(r)[0],
            o = at(a);
          return ((i.fraction = o), i);
        }, []);
      }
      toDecimal(r) {
        return (
          this.getNth(r).forEach((a) => {
            let { decimal: i } = at(a);
            ((a = a.replaceWith(String(i), !0)),
              a.tag("NumericValue"),
              a.unTag("Fraction"));
          }),
          this
        );
      }
      toFraction(r) {
        return (
          this.getNth(r).forEach((a) => {
            let i = at(a);
            if (
              i &&
              typeof i.numerator == "number" &&
              typeof i.denominator == "number"
            ) {
              let o = `${i.numerator}/${i.denominator}`;
              this.replace(a, o);
            }
          }),
          this
        );
      }
      toOrdinal(r) {
        return (
          this.getNth(r).forEach((a) => {
            let i = at(a),
              o = Dw(i);
            (a.after("^#Noun").found && (o += " of"), a.replaceWith(o));
          }),
          this
        );
      }
      toCardinal(r) {
        return (
          this.getNth(r).forEach((a) => {
            let i = at(a),
              o = Cw(i);
            a.replaceWith(o);
          }),
          this
        );
      }
      toPercentage(r) {
        return (
          this.getNth(r).forEach((a) => {
            let { decimal: i } = at(a),
              o = i * 100;
            ((o = Math.round(o * 100) / 100), a.replaceWith(`${o}%`));
          }),
          this
        );
      }
    }
    e.prototype.fractions = function (n) {
      let r = uw(this);
      return ((r = r.getNth(n)), new t(this.document, r.pointer));
    };
  },
  jw = "one|two|three|four|five|six|seven|eight|nine",
  pt = "twenty|thirty|forty|fifty|sixty|seventy|eighty|ninety|fourty",
  Nw =
    "eleven|twelve|thirteen|fourteen|fifteen|sixteen|seventeen|eighteen|nineteen",
  $a = function (e) {
    let t = e.match("#Value+");
    if (
      (t.has("#NumericValue #NumericValue") &&
        (t.has("#Value @hasComma #Value")
          ? t.splitAfter("@hasComma")
          : t.has("#NumericValue #Fraction")
            ? t.splitAfter("#NumericValue #Fraction")
            : (t = t.splitAfter("#NumericValue"))),
      t.has("#Value #Value #Value") &&
        !t.has("#Multiple") &&
        t.has("(" + pt + ") #Cardinal #Cardinal") &&
        (t = t.splitAfter("(" + pt + ") #Cardinal")),
      t.has("#Value #Value"))
    ) {
      (t.has("#NumericValue #NumericValue") && (t = t.splitOn("#Year")),
        t.has("(" + pt + ") (" + Nw + ")") &&
          (t = t.splitAfter("(" + pt + ")")));
      let n = t.match("#Cardinal #Cardinal");
      if (
        n.found &&
        !t.has("(point|decimal|#Fraction)") &&
        !n.has("#Cardinal (#Multiple|point|decimal)")
      ) {
        let r = t.has(`(${jw}) (${pt})`),
          a = n.has("(" + pt + ") #Cardinal"),
          i = n.has("#Multiple #Value");
        !r &&
          !a &&
          !i &&
          n.terms().forEach((o) => {
            t = t.splitOn(o);
          });
      }
      (t.match("#Ordinal #Ordinal").match("#TextValue").found &&
        !t.has("#Multiple") &&
        (t.has("(" + pt + ") #Ordinal") || (t = t.splitAfter("#Ordinal"))),
        (t = t.splitBefore("#Ordinal [#Cardinal]", 0)),
        t.has("#TextValue #NumericValue") &&
          !t.has("(" + pt + "|#Multiple)") &&
          (t = t.splitBefore("#TextValue #NumericValue")));
    }
    return (
      (t = t.splitAfter("#NumberRange")),
      (t = t.splitBefore("#Year")),
      t
    );
  },
  Tw = function (e, t) {
    e = e.replace(/,/g, "");
    let n = e.split(/([0-9.,]*)/),
      [r, a] = n,
      i = n.slice(2).join("");
    return a !== "" && t.length < 2
      ? ((a = Number(a || e)),
        typeof a != "number" && (a = null),
        (i = i || ""),
        (i === "st" || i === "nd" || i === "rd" || i === "th") && (i = ""),
        { prefix: r || "", num: a, suffix: i })
      : null;
  },
  ae = function (e) {
    if (typeof e == "string") return { num: bi(e) };
    let t = e.text("reduced"),
      n = e.growRight("#Unit").match("#Unit$").text("machine"),
      r = /[0-9],[0-9]/.test(e.text("text"));
    if (e.terms().length === 1 && !e.has("#Multiple")) {
      let s = Tw(t, e);
      if (s !== null) return ((s.hasComma = r), (s.unit = n), s);
    }
    let a = e.match("#Fraction{2,}$");
    a = a.found === !1 ? e.match("^#Fraction$") : a;
    let i = null;
    a.found &&
      (a.has("#Value and #Value #Fraction") &&
        (a = a.match("and #Value #Fraction")),
      (i = at(a)),
      (e = e.not(a)),
      (e = e.not("and$")),
      (t = e.text("reduced")));
    let o = 0;
    return (
      t && (o = bi(t) || 0),
      i && i.decimal && (o += i.decimal),
      {
        hasComma: r,
        prefix: "",
        num: o,
        suffix: "",
        isOrdinal: e.has("#Ordinal"),
        isText: e.has("#TextValue"),
        isFraction: e.has("#Fraction"),
        isMoney: e.has("#Money"),
        unit: n,
      }
    );
  },
  Ow = function (e) {
    let t = e.num;
    if (!t && t !== 0) return null;
    let n = t % 100;
    if (n > 10 && n < 20) return String(t) + "th";
    const r = { 0: "th", 1: "st", 2: "nd", 3: "rd" };
    let a = no(t),
      i = a.slice(a.length - 1, a.length);
    return (r[i] ? (a += r[i]) : (a += "th"), a);
  },
  nl = {
    "¢": "cents",
    $: "dollars",
    "£": "pounds",
    "¥": "yen",
    "€": "euros",
    "₡": "colón",
    "฿": "baht",
    "₭": "kip",
    "₩": "won",
    "₹": "rupees",
    "₽": "ruble",
    "₺": "liras",
  },
  rl = { "%": "percent", "°": "degrees" },
  al = function (e) {
    let t = { suffix: "", prefix: e.prefix };
    return (
      nl.hasOwnProperty(e.prefix) &&
        ((t.suffix += " " + nl[e.prefix]), (t.prefix = "")),
      rl.hasOwnProperty(e.suffix) && (t.suffix += " " + rl[e.suffix]),
      t.suffix && e.num === 1 && (t.suffix = t.suffix.replace(/s$/, "")),
      !t.suffix && e.suffix && (t.suffix += " " + e.suffix),
      t
    );
  },
  Et = function (e, t) {
    if (t === "TextOrdinal") {
      let { prefix: r, suffix: a } = al(e);
      return r + mc(e) + a;
    }
    if (t === "Ordinal") return e.prefix + Ow(e) + e.suffix;
    if (t === "TextCardinal") {
      let { prefix: r, suffix: a } = al(e);
      return r + Kn(e) + a;
    }
    let n = e.num;
    return (
      e.hasComma && (n = n.toLocaleString()),
      e.prefix + String(n) + e.suffix
    );
  },
  Iw = (e) => Object.prototype.toString.call(e) === "[object Array]",
  Ew = function (e) {
    if (typeof e == "string" || typeof e == "number") {
      let t = {};
      return ((t[e] = !0), t);
    }
    return Iw(e) ? e.reduce((t, n) => ((t[n] = !0), t), {}) : e || {};
  },
  Hw = function (e, t = {}) {
    return (
      (t = Ew(t)),
      e.filter((n) => {
        let { unit: r } = ae(n);
        return !!(r && t[r] === !0);
      })
    );
  },
  zw = function (e) {
    class t extends e {
      constructor(r, a, i) {
        (super(r, a, i), (this.viewType = "Numbers"));
      }
      parse(r) {
        return this.getNth(r).map(ae);
      }
      get(r) {
        return this.getNth(r)
          .map(ae)
          .map((a) => a.num);
      }
      json(r) {
        let a = typeof r == "object" ? r : {};
        return this.getNth(r).map((i) => {
          let o = i.toView().json(a)[0],
            s = ae(i);
          return (
            (o.number = {
              prefix: s.prefix,
              num: s.num,
              suffix: s.suffix,
              hasComma: s.hasComma,
              unit: s.unit,
            }),
            o
          );
        }, []);
      }
      units() {
        return this.growRight("#Unit").match("#Unit$");
      }
      isUnit(r) {
        return Hw(this, r);
      }
      isOrdinal() {
        return this.if("#Ordinal");
      }
      isCardinal() {
        return this.if("#Cardinal");
      }
      toNumber() {
        let r = this.map((a) => {
          if (!this.has("#TextValue")) return a;
          let i = ae(a);
          if (i.num === null) return a;
          let o = a.has("#Ordinal") ? "Ordinal" : "Cardinal",
            s = Et(i, o);
          return (a.replaceWith(s, { tags: !0 }), a.tag("NumericValue"));
        });
        return new t(r.document, r.pointer);
      }
      toLocaleString() {
        return (
          this.forEach((a) => {
            let i = ae(a);
            if (i.num === null) return;
            let o = i.num.toLocaleString();
            if (a.has("#Ordinal")) {
              let l = Et(i, "Ordinal").match(/[a-z]+$/);
              l && (o += l[0] || "");
            }
            a.replaceWith(o, { tags: !0 });
          }),
          this
        );
      }
      toText() {
        let a = this.map((i) => {
          if (i.has("#TextValue")) return i;
          let o = ae(i);
          if (o.num === null) return i;
          let s = i.has("#Ordinal") ? "TextOrdinal" : "TextCardinal",
            l = Et(o, s);
          return (i.replaceWith(l, { tags: !0 }), i.tag("TextValue"), i);
        });
        return new t(a.document, a.pointer);
      }
      toCardinal() {
        let a = this.map((i) => {
          if (!i.has("#Ordinal")) return i;
          let o = ae(i);
          if (o.num === null) return i;
          let s = i.has("#TextValue") ? "TextCardinal" : "Cardinal",
            l = Et(o, s);
          return (i.replaceWith(l, { tags: !0 }), i.tag("Cardinal"), i);
        });
        return new t(a.document, a.pointer);
      }
      toOrdinal() {
        let a = this.map((i) => {
          if (i.has("#Ordinal")) return i;
          let o = ae(i);
          if (o.num === null) return i;
          let s = i.has("#TextValue") ? "TextOrdinal" : "Ordinal",
            l = Et(o, s);
          return (i.replaceWith(l, { tags: !0 }), i.tag("Ordinal"), i);
        });
        return new t(a.document, a.pointer);
      }
      isEqual(r) {
        return this.filter((a) => ae(a).num === r);
      }
      greaterThan(r) {
        return this.filter((a) => ae(a).num > r);
      }
      lessThan(r) {
        return this.filter((a) => ae(a).num < r);
      }
      between(r, a) {
        return this.filter((i) => {
          let o = ae(i).num;
          return o > r && o < a;
        });
      }
      set(r) {
        if (r === void 0) return this;
        typeof r == "string" && (r = ae(r).num);
        let i = this.map((o) => {
          let s = ae(o);
          if (((s.num = r), s.num === null)) return o;
          let l = o.has("#Ordinal") ? "Ordinal" : "Cardinal";
          o.has("#TextValue") &&
            (l = o.has("#Ordinal") ? "TextOrdinal" : "TextCardinal");
          let u = Et(s, l);
          return (
            s.hasComma && l === "Cardinal" && (u = Number(u).toLocaleString()),
            (o = o.not("#Currency")),
            o.replaceWith(u, { tags: !0 }),
            o
          );
        });
        return new t(i.document, i.pointer);
      }
      add(r) {
        if (!r) return this;
        typeof r == "string" && (r = ae(r).num);
        let i = this.map((o) => {
          let s = ae(o);
          if (s.num === null) return o;
          s.num += r;
          let l = o.has("#Ordinal") ? "Ordinal" : "Cardinal";
          s.isText && (l = o.has("#Ordinal") ? "TextOrdinal" : "TextCardinal");
          let u = Et(s, l);
          return (o.replaceWith(u, { tags: !0 }), o);
        });
        return new t(i.document, i.pointer);
      }
      subtract(r, a) {
        return this.add(r * -1, a);
      }
      increment(r) {
        return this.add(1, r);
      }
      decrement(r) {
        return this.add(-1, r);
      }
      update(r) {
        let a = new t(this.document, r);
        return ((a._cache = this._cache), a);
      }
    }
    ((t.prototype.toNice = t.prototype.toLocaleString),
      (t.prototype.isBetween = t.prototype.between),
      (t.prototype.minus = t.prototype.subtract),
      (t.prototype.plus = t.prototype.add),
      (t.prototype.equals = t.prototype.isEqual),
      (e.prototype.numbers = function (n) {
        let r = $a(this);
        return ((r = r.getNth(n)), new t(this.document, r.pointer));
      }),
      (e.prototype.percentages = function (n) {
        let r = $a(this);
        return (
          (r = r.filter((a) => a.has("#Percent") || a.after("^percent"))),
          (r = r.getNth(n)),
          new t(this.document, r.pointer)
        );
      }),
      (e.prototype.money = function (n) {
        let r = $a(this);
        return (
          (r = r.filter((a) => a.has("#Money") || a.after("^#Currency"))),
          (r = r.getNth(n)),
          new t(this.document, r.pointer)
        );
      }),
      (e.prototype.values = e.prototype.numbers));
  },
  Fw = function (e) {
    ($w(e), zw(e));
  },
  Vw = { api: Fw },
  Gw = { people: !0, emails: !0, phoneNumbers: !0, places: !0 },
  Sw = function (e = {}) {
    return (
      (e = Object.assign({}, Gw, e)),
      e.people !== !1 && this.people().replaceWith("██████████"),
      e.emails !== !1 && this.emails().replaceWith("██████████"),
      e.places !== !1 && this.places().replaceWith("██████████"),
      e.phoneNumbers !== !1 && this.phoneNumbers().replaceWith("███████"),
      this
    );
  },
  Mw = {
    api: function (e) {
      e.prototype.redact = Sw;
    },
  },
  Bw = function (e) {
    let t = e.clauses();
    return /\.\.$/.test(e.out("text")) ||
      (e.has("^#QuestionWord") && e.has("@hasComma"))
      ? !1
      : !!(
          e.has("or not$") ||
          e.has("^#QuestionWord") ||
          e.has("^(do|does|did|is|was|can|could|will|would|may) #Noun") ||
          e.has("^(have|must) you") ||
          t.has("(do|does|is|was) #Noun+ #Adverb? (#Adjective|#Infinitive)$")
        );
  },
  Lw = function (e) {
    const t = /\?/,
      { document: n } = e;
    return e.filter((r) => {
      let a = r.docs[0] || [],
        i = a[a.length - 1];
      return !i || n[i.index[0]].length !== a.length
        ? !1
        : t.test(i.post)
          ? !0
          : Bw(r);
    });
  },
  Ww =
    "(after|although|as|because|before|if|since|than|that|though|when|whenever|where|whereas|wherever|whether|while|why|unless|until|once)",
  qw = "(that|which|whichever|who|whoever|whom|whose|whomever)",
  Kw = function (e) {
    let t = e;
    return t.length === 1 ||
      ((t = t.if("#Verb")), t.length === 1) ||
      ((t = t.ifNo(Ww)),
      (t = t.ifNo("^even (if|though)")),
      (t = t.ifNo("^so that")),
      (t = t.ifNo("^rather than")),
      (t = t.ifNo("^provided that")),
      t.length === 1) ||
      ((t = t.ifNo(qw)), t.length === 1) ||
      ((t = t.ifNo("(^despite|^during|^before|^through|^throughout)")),
      t.length === 1) ||
      ((t = t.ifNo("^#Gerund")), t.length === 1)
      ? t
      : (t.length === 0 && (t = e), t.eq(0));
  },
  Jw = function (e) {
    let t = null;
    return (
      e.has("#PastTense")
        ? (t = "PastTense")
        : e.has("#FutureTense")
          ? (t = "FutureTense")
          : e.has("#PresentTense") && (t = "PresentTense"),
      { tense: t }
    );
  },
  Ht = function (e) {
    let t = e.clauses(),
      r = Kw(t).chunks(),
      a = e.none(),
      i = e.none(),
      o = e.none();
    return (
      r.forEach((s, l) => {
        if (l === 0 && !s.has("<Verb>")) {
          a = s;
          return;
        }
        if (!i.found && s.has("<Verb>")) {
          i = s;
          return;
        }
        i.found && (o = o.concat(s));
      }),
      i.found && !a.found && (a = i.before("<Noun>+").first()),
      { subj: a, verb: i, pred: o, grammar: Jw(i) }
    );
  },
  _w = function (e) {
    let t = e.verbs(),
      n = t.eq(0);
    if (n.has("#PastTense")) return e;
    if ((n.toPastTense(), t.length > 1)) {
      ((t = t.slice(1)),
        (t = t.filter((a) => !a.lookBehind("to$").found)),
        (t = t.if("#PresentTense")),
        (t = t.notIf("#Gerund")));
      let r = e.match("to #Verb+ #Conjunction #Verb").terms();
      ((t = t.not(r)), t.found && t.verbs().toPastTense());
    }
    return e;
  },
  Uw = function (e) {
    let t = e.verbs();
    return (
      t.eq(0).toPresentTense(),
      t.length > 1 &&
        ((t = t.slice(1)),
        (t = t.filter((r) => !r.lookBehind("to$").found)),
        (t = t.notIf("#Gerund")),
        t.found && t.verbs().toPresentTense()),
      e
    );
  },
  Rw = function (e) {
    let t = e.verbs();
    if (
      (t.eq(0).toFutureTense(),
      (e = e.fullSentence()),
      (t = e.verbs()),
      t.length > 1)
    ) {
      t = t.slice(1);
      let r = t.filter((a) =>
        a.lookBehind("to$").found
          ? !1
          : a.has("#Copula #Gerund")
            ? !0
            : a.has("#Gerund")
              ? !1
              : a.has("#Copula")
                ? !0
                : !(
                    a.has("#PresentTense") &&
                    !a.has("#Infinitive") &&
                    a.lookBefore("(he|she|it|that|which)$").found
                  ),
      );
      r.found &&
        r.forEach((a) => {
          if (a.has("#Copula")) {
            (a.match("was").replaceWith("is"),
              a.match("is").replaceWith("will be"));
            return;
          }
          a.toInfinitive();
        });
    }
    return e;
  },
  Yw = function (e) {
    return (e.verbs().first().toNegative().compute("chunks"), e);
  },
  Qw = function (e) {
    return (e.verbs().first().toPositive().compute("chunks"), e);
  },
  Zw = function (e) {
    return (e.verbs().toInfinitive(), e);
  },
  Xw = function (e) {
    class t extends e {
      constructor(a, i, o) {
        (super(a, i, o), (this.viewType = "Sentences"));
      }
      json(a = {}) {
        return this.map((i) => {
          let o = i.toView().json(a)[0] || {},
            { subj: s, verb: l, pred: u, grammar: c } = Ht(i);
          return (
            (o.sentence = {
              subject: s.text("normal"),
              verb: l.text("normal"),
              predicate: u.text("normal"),
              grammar: c,
            }),
            o
          );
        }, []);
      }
      toPastTense(a) {
        return this.getNth(a).map((i) => (Ht(i), _w(i)));
      }
      toPresentTense(a) {
        return this.getNth(a).map((i) => (Ht(i), Uw(i)));
      }
      toFutureTense(a) {
        return this.getNth(a).map((i) => (Ht(i), (i = Rw(i)), i));
      }
      toInfinitive(a) {
        return this.getNth(a).map((i) => (Ht(i), Zw(i)));
      }
      toNegative(a) {
        return this.getNth(a).map((i) => (Ht(i), Yw(i)));
      }
      toPositive(a) {
        return this.getNth(a).map((i) => (Ht(i), Qw(i)));
      }
      isQuestion(a) {
        return this.questions(a);
      }
      isExclamation(a) {
        return this.filter((o) => o.lastTerm().has("@hasExclamation")).getNth(
          a,
        );
      }
      isStatement(a) {
        return this.filter(
          (o) => !o.isExclamation().found && !o.isQuestion().found,
        ).getNth(a);
      }
      update(a) {
        let i = new t(this.document, a);
        return ((i._cache = this._cache), i);
      }
    }
    ((t.prototype.toPresent = t.prototype.toPresentTense),
      (t.prototype.toPast = t.prototype.toPastTense),
      (t.prototype.toFuture = t.prototype.toFutureTense));
    const n = {
      sentences: function (r) {
        let a = this.map((i) => i.fullSentence());
        return ((a = a.getNth(r)), new t(this.document, a.pointer));
      },
      questions: function (r) {
        return Lw(this).getNth(r);
      },
    };
    Object.assign(e.prototype, n);
  },
  e2 = { api: Xw },
  t2 = function (e) {
    let t = e.splitAfter("@hasComma");
    t = t.match("#Honorific+? #Person+");
    let n = t.match("#Possessive").notIf("(his|her)");
    return ((t = t.splitAfter(n)), t);
  },
  il = function (e) {
    let t = {};
    ((t.firstName = e.match("#FirstName+")),
      (t.lastName = e.match("#LastName+")),
      (t.honorific = e.match("#Honorific+")));
    let n = t.lastName,
      r = t.firstName;
    return (
      (!r.found || !n.found) &&
        !r.found &&
        !n.found &&
        e.has("^#Honorific .$") &&
        (t.lastName = e.match(".$")),
      t
    );
  },
  Ne = "male",
  ce = "female",
  ol = {
    mr: Ne,
    mrs: ce,
    miss: ce,
    madam: ce,
    king: Ne,
    queen: ce,
    duke: Ne,
    duchess: ce,
    baron: Ne,
    baroness: ce,
    count: Ne,
    countess: ce,
    prince: Ne,
    princess: ce,
    sire: Ne,
    dame: ce,
    lady: ce,
    ayatullah: Ne,
    congressman: Ne,
    congresswoman: ce,
    "first lady": ce,
    mx: null,
  },
  n2 = function (e, t) {
    let { firstName: n, honorific: r } = e;
    if (n.has("#FemaleName")) return ce;
    if (n.has("#MaleName")) return Ne;
    if (r.found) {
      let i = r.text("normal");
      if (((i = i.replace(/\./g, "")), ol.hasOwnProperty(i))) return ol[i];
      if (/^her /.test(i)) return ce;
      if (/^his /.test(i)) return Ne;
    }
    let a = t.after();
    if (!a.has("#Person") && a.has("#Pronoun")) {
      let i = a.match("#Pronoun");
      if (i.has("(they|their)")) return null;
      let o = i.has("(he|his)"),
        s = i.has("(she|her|hers)");
      if (o && !s) return Ne;
      if (s && !o) return ce;
    }
    return null;
  },
  r2 = function (e) {
    class t extends e {
      constructor(r, a, i) {
        (super(r, a, i), (this.viewType = "People"));
      }
      parse(r) {
        return this.getNth(r).map(il);
      }
      json(r) {
        let a = typeof r == "object" ? r : {};
        return this.getNth(r).map((i) => {
          let o = i.toView().json(a)[0],
            s = il(i);
          return (
            (o.person = {
              firstName: s.firstName.text("normal"),
              lastName: s.lastName.text("normal"),
              honorific: s.honorific.text("normal"),
              presumed_gender: n2(s, i),
            }),
            o
          );
        }, []);
      }
      presumedMale() {
        return this.filter((r) =>
          r.has("(#MaleName|mr|mister|sr|jr|king|pope|prince|sir)"),
        );
      }
      presumedFemale() {
        return this.filter((r) =>
          r.has("(#FemaleName|mrs|miss|queen|princess|madam)"),
        );
      }
      update(r) {
        let a = new t(this.document, r);
        return ((a._cache = this._cache), a);
      }
    }
    e.prototype.people = function (n) {
      let r = t2(this);
      return ((r = r.getNth(n)), new t(this.document, r.pointer));
    };
  },
  a2 = function (e) {
    let t = e.match("(#Place|#Address)+"),
      n = t.match("@hasComma");
    return (
      (n = n.filter((r) =>
        r.has("(asia|africa|europe|america)$")
          ? !0
          : !(
              r.has("(#City|#Region|#ProperNoun)$") &&
              r.after("^(#Country|#Region)").found
            ),
      )),
      (t = t.splitAfter(n)),
      t
    );
  },
  i2 = function (e) {
    e.prototype.places = function (t) {
      let n = a2(this);
      return ((n = n.getNth(t)), new e(this.document, n.pointer));
    };
  },
  o2 = function (e) {
    e.prototype.organizations = function (t) {
      return this.match("#Organization+").getNth(t);
    };
  },
  s2 = function (e) {
    let t = this.clauses(),
      n = t.people();
    return (
      (n = n.concat(t.places())),
      (n = n.concat(t.organizations())),
      (n = n.not("(someone|man|woman|mother|brother|sister|father)")),
      (n = n.sort("seq")),
      (n = n.getNth(e)),
      n
    );
  },
  l2 = function (e) {
    e.prototype.topics = s2;
  },
  u2 = function (e) {
    (r2(e), i2(e), o2(e), l2(e));
  },
  c2 = { api: u2 },
  h2 = function (e) {
    let t = e.match("<Verb>");
    return (
      (t = t.not("#Conjunction")),
      (t = t.not("#Preposition")),
      (t = t.splitAfter("@hasComma")),
      (t = t.splitAfter("[(do|did|am|was|is|will)] (is|was)", 0)),
      (t = t.splitBefore("(#Verb && !#Copula) [being] #Verb", 0)),
      (t = t.splitBefore("#Verb [to be] #Verb", 0)),
      (t = t.splitAfter("[help] #PresentTense", 0)),
      (t = t.splitBefore("(#PresentTense|#PastTense) [#Copula]$", 0)),
      (t = t.splitBefore("(#PresentTense|#PastTense) [will be]$", 0)),
      (t = t.splitBefore("(#PresentTense|#PastTense) [(had|has)]", 0)),
      (t = t.not("#Reflexive$")),
      (t = t.not("#Adjective")),
      (t = t.splitAfter("[#PastTense] #PastTense", 0)),
      (t = t.splitAfter("[#PastTense] #Auxiliary+ #PastTense", 0)),
      (t = t.splitAfter("#Copula [#Gerund] #PastTense", 0)),
      (t = t.if("#Verb")),
      t.has("(#Verb && !#Auxiliary) #Adverb+? #Copula") &&
        (t = t.splitBefore("#Copula")),
      t
    );
  },
  d2 = function (e) {
    let t = e;
    return (
      e.wordCount() > 1 &&
        (t = e.not("(#Negative|#Auxiliary|#Modal|#Adverb|#Prefix)")),
      t.length > 1 && !t.has("#Phrasal #Particle") && (t = t.last()),
      (t = t.not("(want|wants|wanted) to")),
      t.found || (t = e.not("#Negative")),
      t
    );
  },
  f2 = function (e, t) {
    let n = { pre: e.none(), post: e.none() };
    if (!e.has("#Adverb")) return n;
    let r = e.splitOn(t);
    return r.length === 3
      ? { pre: r.eq(0).adverbs(), post: r.eq(2).adverbs() }
      : r.eq(0).isDoc(t)
        ? ((n.post = r.eq(1).adverbs()), n)
        : ((n.pre = r.eq(0).adverbs()), n);
  },
  m2 = function (e, t) {
    let n = e.splitBefore(t);
    if (n.length <= 1) return e.none();
    let r = n.eq(0);
    return ((r = r.not("(#Adverb|#Negative|#Prefix)")), r);
  },
  p2 = function (e) {
    return e.match("#Negative");
  },
  g2 = function (e) {
    if (!e.has("(#Particle|#PhrasalVerb)"))
      return { verb: e.none(), particle: e.none() };
    let t = e.match("#Particle$");
    return { verb: e.not(t), particle: t };
  },
  Se = function (e) {
    let t = e.clone();
    t.contractions().expand();
    const n = d2(t);
    return {
      root: n,
      prefix: t.match("#Prefix"),
      adverbs: f2(t, n),
      auxiliary: m2(t, n),
      negative: p2(t),
      phrasal: g2(n),
    };
  },
  ze = { tense: "PresentTense" },
  Pr = { conditional: !0 },
  tt = { tense: "FutureTense" },
  on = { progressive: !0 },
  X = { tense: "PastTense" },
  sn = { complete: !0, progressive: !1 },
  gt = { passive: !0 },
  y2 = { plural: !0 },
  b2 = { plural: !1 },
  v2 = function (e) {
    let t = {};
    return (
      e.forEach((n) => {
        Object.assign(t, n);
      }),
      t
    );
  },
  sl = {
    imperative: [["#Imperative", []]],
    "want-infinitive": [
      ["^(want|wants|wanted) to #Infinitive$", [ze]],
      ["^wanted to #Infinitive$", [X]],
      ["^will want to #Infinitive$", [tt]],
    ],
    "gerund-phrase": [
      ["^#PastTense #Gerund$", [X]],
      ["^#PresentTense #Gerund$", [ze]],
      ["^#Infinitive #Gerund$", [ze]],
      ["^will #Infinitive #Gerund$", [tt]],
      ["^have #PastTense #Gerund$", [X]],
      ["^will have #PastTense #Gerund$", [X]],
    ],
    "simple-present": [
      ["^#PresentTense$", [ze]],
      ["^#Infinitive$", [ze]],
    ],
    "simple-past": [["^#PastTense$", [X]]],
    "simple-future": [["^will #Adverb? #Infinitive", [tt]]],
    "present-progressive": [["^(is|are|am) #Gerund$", [ze, on]]],
    "past-progressive": [["^(was|were) #Gerund$", [X, on]]],
    "future-progressive": [["^will be #Gerund$", [tt, on]]],
    "present-perfect": [["^(has|have) #PastTense$", [X, sn]]],
    "past-perfect": [
      ["^had #PastTense$", [X, sn]],
      ["^had #PastTense to #Infinitive", [X, sn]],
    ],
    "future-perfect": [["^will have #PastTense$", [tt, sn]]],
    "present-perfect-progressive": [["^(has|have) been #Gerund$", [X, on]]],
    "past-perfect-progressive": [["^had been #Gerund$", [X, on]]],
    "future-perfect-progressive": [["^will have been #Gerund$", [tt, on]]],
    "passive-past": [
      ["(got|were|was) #Passive", [X, gt]],
      ["^(was|were) being #Passive", [X, gt]],
      ["^(had|have) been #Passive", [X, gt]],
    ],
    "passive-present": [
      ["^(is|are|am) #Passive", [ze, gt]],
      ["^(is|are|am) being #Passive", [ze, gt]],
      ["^has been #Passive", [ze, gt]],
    ],
    "passive-future": [
      ["will have been #Passive", [tt, gt, Pr]],
      ["will be being? #Passive", [tt, gt, Pr]],
    ],
    "present-conditional": [["would be #PastTense", [ze, Pr]]],
    "past-conditional": [["would have been #PastTense", [X, Pr]]],
    "auxiliary-future": [
      ["(is|are|am|was) going to (#Infinitive|#PresentTense)", [tt]],
    ],
    "auxiliary-past": [
      ["^did #Infinitive$", [X, b2]],
      ["^used to #Infinitive$", [X, sn]],
    ],
    "auxiliary-present": [["^(does|do) #Infinitive$", [ze, sn, y2]]],
    "modal-past": [["^(could|must|should|shall) have #PastTense$", [X]]],
    "modal-infinitive": [["^#Modal #Infinitive$", []]],
    infinitive: [["^#Infinitive$", []]],
  };
let vi = [];
Object.keys(sl).map((e) => {
  sl[e].forEach((t) => {
    vi.push({ name: e, match: t[0], data: v2(t[1]) });
  });
});
const w2 = function (e, t) {
    return (
      (e = e.clone()),
      t.adverbs.post && t.adverbs.post.found && e.remove(t.adverbs.post),
      t.adverbs.pre && t.adverbs.pre.found && e.remove(t.adverbs.pre),
      e.has("#Negative") && (e = e.remove("#Negative")),
      e.has("#Prefix") && (e = e.remove("#Prefix")),
      t.root.has("#PhrasalVerb #Particle") && e.remove("#Particle$"),
      (e = e.not("#Adverb")),
      e
    );
  },
  k2 = function (e) {
    return !!(e.has("#Infinitive") && e.growLeft("to").has("^to #Infinitive"));
  },
  it = function (e, t) {
    let n = {};
    e = w2(e, t);
    for (let r = 0; r < vi.length; r += 1) {
      let a = vi[r];
      if (e.has(a.match) === !0) {
        ((n.form = a.name), Object.assign(n, a.data));
        break;
      }
    }
    return (
      n.form || (e.has("^#Verb$") && (n.form = "infinitive")),
      n.tense ||
        (n.tense = t.root.has("#PastTense") ? "PastTense" : "PresentTense"),
      (n.copula = t.root.has("#Copula")),
      (n.isInfinitive = k2(e)),
      n
    );
  },
  ll = function (e) {
    return e.length <= 1 ? !1 : (e.parse()[0] || {}).isSubordinate;
  },
  P2 = function (e) {
    let t = e.clauses();
    return (
      (t = t.filter(
        (n, r) =>
          !(
            n.has("^(if|unless|while|but|for|per|at|by|that|which|who|from)") ||
            (r > 0 && n.has("^#Verb . #Noun+$")) ||
            (r > 0 && n.has("^#Adverb"))
          ),
      )),
      t.length === 0 ? e : t
    );
  },
  A2 = function (e) {
    let t = e.before();
    t = P2(t);
    let n = t.nouns(),
      r = n.last(),
      a = r.match("(i|he|she|we|you|they)");
    if (a.found) return a.nouns();
    let i = n.if("^(that|this|those)");
    return i.found ||
      (n.found === !1 && ((i = t.match("^(that|this|those)")), i.found))
      ? i
      : ((r = n.last()),
        ll(r) && (n.remove(r), (r = n.last())),
        ll(r) && (n.remove(r), (r = n.last())),
        r);
  },
  x2 = function (e, t) {
    return t.has("(are|were|does)") || e.has("(those|they|we)")
      ? !0
      : e.found && e.isPlural
        ? e.isPlural().found
        : !1;
  },
  Re = function (e) {
    let t = A2(e);
    return { subject: t, plural: x2(t, e) };
  },
  S = (e) => e,
  Gn = (e, t) => {
    let n = Re(e),
      r = n.subject;
    return r.has("i") || r.has("we") ? !0 : n.plural;
  },
  C2 = (e, t) => {
    let { subject: n, plural: r } = Re(e);
    return r || n.has("we") ? "were" : "was";
  },
  Sn = function (e, t) {
    if (e.has("were")) return "are";
    let { subject: n, plural: r } = Re(e);
    return n.has("i") ? "am" : n.has("we") || r ? "are" : "is";
  },
  ro = function (e, t) {
    let n = Re(e),
      r = n.subject;
    return r.has("i") || r.has("we") || n.plural ? "do" : "does";
  },
  Ae = function (e) {
    if (e.has("#Infinitive")) return "Infinitive";
    if (e.has("#Participle")) return "Participle";
    if (e.has("#PastTense")) return "PastTense";
    if (e.has("#Gerund")) return "Gerund";
    if (e.has("#PresentTense")) return "PresentTense";
  },
  wi = function (e, t) {
    const { toInfinitive: n } = e.methods.two.transform.verb;
    let r = t.root.text({ keepPunct: !1 });
    return ((r = n(r, e.model, Ae(e))), r && e.replace(t.root, r), e);
  },
  ul = (e) =>
    e.has("will not") ? e.replace("will not", "have not") : e.remove("will"),
  cl = function (e) {
    if (!e || !e.isView) return [];
    const t = { normal: !0, terms: !1, text: !1 };
    return e.json(t).map((n) => n.normal);
  },
  hl = function (e) {
    return !e || !e.isView ? "" : e.text("normal");
  },
  D2 = function (e) {
    const { toInfinitive: t } = e.methods.two.transform.verb;
    let n = e.text("normal");
    return t(n, e.model, Ae(e));
  },
  $2 = function (e) {
    let t = Se(e);
    e = e.clone().toView();
    const n = it(e, t);
    return {
      root: t.root.text(),
      preAdverbs: cl(t.adverbs.pre),
      postAdverbs: cl(t.adverbs.post),
      auxiliary: hl(t.auxiliary),
      negative: t.negative.found,
      prefix: hl(t.prefix),
      infinitive: D2(t.root),
      grammar: n,
    };
  },
  j2 = { tags: !0 },
  N2 = function (e, t) {
    const { toInfinitive: n } = e.methods.two.transform.verb,
      { root: r, auxiliary: a } = t;
    let i = a.terms().harden(),
      o = r.text("normal");
    if (
      ((o = n(o, e.model, Ae(r))),
      o && e.replace(r, o, j2).tag("Verb").firstTerm().tag("Infinitive"),
      i.found && e.remove(i),
      t.negative.found)
    ) {
      e.has("not") || e.prepend("not");
      let s = ro(e);
      e.prepend(s);
    }
    return (
      e
        .fullSentence()
        .compute([
          "freeze",
          "lexicon",
          "preTagger",
          "postTagger",
          "unfreeze",
          "chunks",
        ]),
      e
    );
  },
  je = { tags: !0 },
  ot = {
    noAux: (e, t) => (t.auxiliary.found && (e = e.remove(t.auxiliary)), e),
    simple: (e, t) => {
      const { conjugate: n, toInfinitive: r } = e.methods.two.transform.verb,
        a = t.root;
      if (a.has("#Modal")) return e;
      let i = a.text({ keepPunct: !1 });
      return (
        (i = r(i, e.model, Ae(a))),
        (i = n(i, e.model).PastTense),
        (i = i === "been" ? "was" : i),
        i === "was" && (i = C2(e)),
        i && e.replace(a, i, je),
        e
      );
    },
    both: function (e, t) {
      return t.negative.found
        ? (e.replace("will", "did"), e)
        : ((e = ot.simple(e, t)), (e = ot.noAux(e, t)), e);
    },
    hasHad: (e) => (e.replace("has", "had", je), e),
    hasParticiple: (e, t) => {
      const { conjugate: n, toInfinitive: r } = e.methods.two.transform.verb,
        a = t.root;
      let i = a.text("normal");
      return ((i = r(i, e.model, Ae(a))), n(i, e.model).Participle);
    },
  },
  dl = {
    infinitive: ot.simple,
    "simple-present": ot.simple,
    "simple-past": S,
    "simple-future": ot.both,
    "present-progressive": (e) => (
      e.replace("are", "were", je),
      e.replace("(is|are|am)", "was", je),
      e
    ),
    "past-progressive": S,
    "future-progressive": (e, t) => (
      e.match(t.root).insertBefore("was"),
      e.remove("(will|be)"),
      e
    ),
    "present-perfect": ot.hasHad,
    "past-perfect": S,
    "future-perfect": (e, t) => (
      e.match(t.root).insertBefore("had"),
      e.has("will") && (e = ul(e)),
      e.remove("have"),
      e
    ),
    "present-perfect-progressive": ot.hasHad,
    "past-perfect-progressive": S,
    "future-perfect-progressive": (e) => (
      e.remove("will"),
      e.replace("have", "had", je),
      e
    ),
    "passive-past": (e) => (e.replace("have", "had", je), e),
    "passive-present": (e) => (e.replace("(is|are)", "was", je), e),
    "passive-future": (e, t) => (
      t.auxiliary.has("will be") &&
        (e.match(t.root).insertBefore("had been"), e.remove("(will|be)")),
      t.auxiliary.has("will have been") &&
        (e.replace("have", "had", je), e.remove("will")),
      e
    ),
    "present-conditional": (e) => (e.replace("be", "have been"), e),
    "past-conditional": S,
    "auxiliary-future": (e) => (e.replace("(is|are|am)", "was", je), e),
    "auxiliary-past": S,
    "auxiliary-present": (e) => (e.replace("(do|does)", "did", je), e),
    "modal-infinitive": (e, t) => (
      e.has("can")
        ? e.replace("can", "could", je)
        : (ot.simple(e, t),
          e.match("#Modal").insertAfter("have").tag("Auxiliary")),
      e
    ),
    "modal-past": S,
    "want-infinitive": (e) => (
      e.replace("(want|wants)", "wanted", je),
      e.remove("will"),
      e
    ),
    "gerund-phrase": (e, t) => (
      (t.root = t.root.not("#Gerund$")),
      ot.simple(e, t),
      ul(e),
      e
    ),
  },
  T2 = function (e, t, n) {
    return (
      dl.hasOwnProperty(n) &&
        ((e = dl[n](e, t)), e.fullSentence().compute(["tagger", "chunks"])),
      e
    );
  },
  ki = function (e, t) {
    let n = Re(e),
      r = n.subject;
    return r.has("(i|we|you)")
      ? "have"
      : n.plural === !1 || r.has("he") || r.has("she") || r.has("#Person")
        ? "has"
        : "have";
  },
  Pi = (e, t) => {
    const { conjugate: n, toInfinitive: r } = e.methods.two.transform.verb,
      { root: a, auxiliary: i } = t;
    if (a.has("#Modal")) return e;
    let o = a.text({ keepPunct: !1 });
    o = r(o, e.model, Ae(a));
    let s = n(o, e.model);
    if (((o = s.Participle || s.PastTense), o)) {
      e = e.replace(a, o);
      let l = ki(e);
      (e.prepend(l).match(l).tag("Auxiliary"), e.remove(i));
    }
    return e;
  },
  fl = {
    infinitive: Pi,
    "simple-present": Pi,
    "simple-future": (e, t) => e.replace("will", ki(e)),
    "present-perfect": S,
    "past-perfect": S,
    "future-perfect": (e, t) => e.replace("will have", ki(e)),
    "present-perfect-progressive": S,
    "past-perfect-progressive": S,
    "future-perfect-progressive": S,
  },
  O2 = function (e, t, n) {
    return fl.hasOwnProperty(n)
      ? ((e = fl[n](e, t)), e.fullSentence().compute(["tagger", "chunks"]), e)
      : ((e = Pi(e, t)), e.fullSentence().compute(["tagger", "chunks"]), e);
  },
  lt = { tags: !0 },
  ln = (e, t) => {
    const { conjugate: n, toInfinitive: r } = e.methods.two.transform.verb,
      a = t.root;
    let i = a.text("normal");
    return (
      (i = r(i, e.model, Ae(a))),
      Gn(e) === !1 && (i = n(i, e.model).PresentTense),
      a.has("#Copula") && (i = Sn(e)),
      i && ((e = e.replace(a, i, lt)), e.not("#Particle").tag("PresentTense")),
      e
    );
  },
  ml = (e, t) => {
    const { conjugate: n, toInfinitive: r } = e.methods.two.transform.verb,
      a = t.root;
    let i = a.text("normal");
    return (
      (i = r(i, e.model, Ae(a))),
      Gn(e) === !1 && (i = n(i, e.model).Gerund),
      i && ((e = e.replace(a, i, lt)), e.not("#Particle").tag("Gerund")),
      e
    );
  },
  I2 = (e, t) => {
    const { toInfinitive: n } = e.methods.two.transform.verb,
      r = t.root;
    let a = t.root.text("normal");
    return ((a = n(a, e.model, Ae(r))), a && (e = e.replace(t.root, a, lt)), e);
  },
  pl = {
    infinitive: ln,
    "simple-present": (e, t) => {
      const { conjugate: n } = e.methods.two.transform.verb;
      let { root: r } = t;
      if (r.has("#Infinitive")) {
        let i = Re(e).subject;
        if (Gn(e) || i.has("i")) return e;
        let o = r.text("normal"),
          s = n(o, e.model).PresentTense;
        o !== s && e.replace(r, s, lt);
      } else return ln(e, t);
      return e;
    },
    "simple-past": ln,
    "simple-future": (e, t) => {
      const { root: n, auxiliary: r } = t;
      if (r.has("will") && n.has("be")) {
        let a = Sn(e);
        (e.replace(n, a),
          (e = e.remove("will")),
          e.replace("not " + a, a + " not"));
      } else (ln(e, t), (e = e.remove("will")));
      return e;
    },
    "present-progressive": S,
    "past-progressive": (e, t) => {
      let n = Sn(e);
      return e.replace("(were|was)", n, lt);
    },
    "future-progressive": (e) => (
      e.match("will").insertBefore("is"),
      e.remove("be"),
      e.remove("will")
    ),
    "present-perfect": (e, t) => (
      ln(e, t),
      (e = e.remove("(have|had|has)")),
      e
    ),
    "past-perfect": (e, t) => {
      let r = Re(e).subject;
      return Gn(e) || r.has("i")
        ? ((e = wi(e, t)), e.remove("had"), e)
        : (e.replace("had", "has", lt), e);
    },
    "future-perfect": (e) => (
      e.match("will").insertBefore("has"),
      e.remove("have").remove("will")
    ),
    "present-perfect-progressive": S,
    "past-perfect-progressive": (e) => e.replace("had", "has", lt),
    "future-perfect-progressive": (e) => (
      e.match("will").insertBefore("has"),
      e.remove("have").remove("will")
    ),
    "passive-past": (e, t) => {
      let n = Sn(e);
      return e.has("(had|have|has)") && e.has("been")
        ? (e.replace("(had|have|has)", n, lt), e.replace("been", "being"), e)
        : e.replace("(got|was|were)", n);
    },
    "passive-present": S,
    "passive-future": (e) => (
      e.replace("will", "is"),
      e.replace("be", "being")
    ),
    "present-conditional": S,
    "past-conditional": (e) => (e.replace("been", "be"), e.remove("have")),
    "auxiliary-future": (e, t) => (ml(e, t), e.remove("(going|to)"), e),
    "auxiliary-past": (e, t) => {
      if (t.auxiliary.has("did")) {
        let n = ro(e);
        return (e.replace(t.auxiliary, n), e);
      }
      return (ml(e, t), e.replace(t.auxiliary, "is"), e);
    },
    "auxiliary-present": S,
    "modal-infinitive": S,
    "modal-past": (e, t) => (I2(e, t), e.remove("have")),
    "gerund-phrase": (e, t) => (
      (t.root = t.root.not("#Gerund$")),
      ln(e, t),
      e.remove("(will|have)")
    ),
    "want-infinitive": (e, t) => {
      let n = "wants";
      return (
        Gn(e) && (n = "want"),
        e.replace("(want|wanted|wants)", n, lt),
        e.remove("will"),
        e
      );
    },
  },
  E2 = function (e, t, n) {
    return (
      pl.hasOwnProperty(n) &&
        ((e = pl[n](e, t)), e.fullSentence().compute(["tagger", "chunks"])),
      e
    );
  },
  pc = { tags: !0 },
  Ar = (e, t) => {
    const { toInfinitive: n } = e.methods.two.transform.verb,
      { root: r, auxiliary: a } = t;
    if (r.has("#Modal")) return e;
    let i = r.text("normal");
    return (
      (i = n(i, e.model, Ae(r))),
      i && ((e = e.replace(r, i, pc)), e.not("#Particle").tag("Verb")),
      e.prepend("will").match("will").tag("Auxiliary"),
      e.remove(a),
      e
    );
  },
  gl = (e, t) => {
    const { conjugate: n, toInfinitive: r } = e.methods.two.transform.verb,
      { root: a, auxiliary: i } = t;
    let o = a.text("normal");
    return (
      (o = r(o, e.model, Ae(a))),
      o &&
        ((o = n(o, e.model).Gerund),
        e.replace(a, o, pc),
        e.not("#Particle").tag("PresentTense")),
      e.remove(i),
      e.prepend("will be").match("will be").tag("Auxiliary"),
      e
    );
  },
  yl = {
    infinitive: Ar,
    "simple-present": Ar,
    "simple-past": Ar,
    "simple-future": S,
    "present-progressive": gl,
    "past-progressive": gl,
    "future-progressive": S,
    "present-perfect": (e) => (
      e.match("(have|has)").replaceWith("will have"),
      e
    ),
    "past-perfect": (e) => e.replace("(had|has)", "will have"),
    "future-perfect": S,
    "present-perfect-progressive": (e) => e.replace("has", "will have"),
    "past-perfect-progressive": (e) => e.replace("had", "will have"),
    "future-perfect-progressive": S,
    "passive-past": (e) =>
      e.has("got")
        ? e.replace("got", "will get")
        : e.has("(was|were)")
          ? (e.replace("(was|were)", "will be"), e.remove("being"))
          : e.has("(have|has|had) been")
            ? e.replace("(have|has|had) been", "will be")
            : e,
    "passive-present": (e) => (
      e.replace("being", "will be"),
      e.remove("(is|are|am)"),
      e
    ),
    "passive-future": S,
    "present-conditional": (e) => e.replace("would", "will"),
    "past-conditional": (e) => e.replace("would", "will"),
    "auxiliary-future": S,
    "auxiliary-past": (e) =>
      e.has("used") && e.has("to")
        ? (e.replace("used", "will"), e.remove("to"))
        : (e.replace("did", "will"), e),
    "auxiliary-present": (e) => e.replace("(do|does)", "will"),
    "modal-infinitive": S,
    "modal-past": S,
    "gerund-phrase": (e, t) => (
      (t.root = t.root.not("#Gerund$")),
      Ar(e, t),
      e.remove("(had|have)")
    ),
    "want-infinitive": (e) => (
      e.replace("(want|wants|wanted)", "will want"),
      e
    ),
  },
  H2 = function (e, t, n) {
    return (
      e.has("will") ||
        e.has("going to") ||
        (yl.hasOwnProperty(n) &&
          ((e = yl[n](e, t)), e.fullSentence().compute(["tagger", "chunks"]))),
      e
    );
  },
  z2 = { tags: !0 },
  F2 = function (e, t) {
    const { toInfinitive: n, conjugate: r } = e.methods.two.transform.verb,
      { root: a, auxiliary: i } = t;
    if (e.has("#Gerund")) return e;
    let o = a.text("normal");
    o = n(o, e.model, Ae(a));
    let s = r(o, e.model).Gerund;
    if (s) {
      let l = Sn(e);
      (e.replace(a, s, z2), e.remove(i), e.prepend(l));
    }
    return (
      e.replace("not is", "is not"),
      e.replace("not are", "are not"),
      e.fullSentence().compute(["tagger", "chunks"]),
      e
    );
  },
  bl = { tags: !0 },
  ja = function (e, t) {
    let n = ro(e);
    return (e.prepend(n + " not"), e);
  },
  Jr = function (e) {
    let t = e.match("be");
    return t.found
      ? (t.prepend("not"), e)
      : ((t = e.match("(is|was|am|are|will|were)")),
        t.found && t.append("not"),
        e);
  },
  _r = (e) => e.has("(is|was|am|are|will|were|be)"),
  vl = {
    "simple-present": (e, t) =>
      _r(e) === !0 ? Jr(e) : ((e = wi(e, t)), (e = ja(e)), e),
    "simple-past": (e, t) =>
      _r(e) === !0 ? Jr(e) : ((e = wi(e, t)), e.prepend("did not"), e),
    imperative: (e) => (e.prepend("do not"), e),
    infinitive: (e, t) => (_r(e) === !0 ? Jr(e) : ja(e)),
    "passive-past": (e) => {
      if (e.has("got"))
        return (e.replace("got", "get", bl), e.prepend("did not"), e);
      let t = e.match("(was|were|had|have)");
      return (t.found && t.append("not"), e);
    },
    "auxiliary-past": (e) => {
      if (e.has("used")) return (e.prepend("did not"), e);
      let t = e.match("(did|does|do)");
      return (t.found && t.append("not"), e);
    },
    "want-infinitive": (e, t) => (
      (e = ja(e)),
      (e = e.replace("wants", "want", bl)),
      e
    ),
  },
  V2 = function (e, t, n) {
    if (e.has("#Negative")) return e;
    if (vl.hasOwnProperty(n)) return ((e = vl[n](e, t)), e);
    let r = e.matchOne("be");
    return r.found
      ? (r.prepend("not"), e)
      : _r(e) === !0
        ? Jr(e)
        : ((r = e.matchOne("(will|had|have|has|did|does|do|#Modal)")),
          r.found && r.append("not"),
          e);
  },
  G2 = function (e) {
    class t extends e {
      constructor(r, a, i) {
        (super(r, a, i), (this.viewType = "Verbs"));
      }
      parse(r) {
        return this.getNth(r).map(Se);
      }
      json(r, a) {
        return this.getNth(a).map((s) => {
          let l = s.toView().json(r)[0] || {};
          return ((l.verb = $2(s)), l);
        }, []);
      }
      subjects(r) {
        return this.getNth(r).map((a) => (Se(a), Re(a).subject));
      }
      adverbs(r) {
        return this.getNth(r).map((a) => a.match("#Adverb"));
      }
      isSingular(r) {
        return this.getNth(r).filter((a) => Re(a).plural !== !0);
      }
      isPlural(r) {
        return this.getNth(r).filter((a) => Re(a).plural === !0);
      }
      isImperative(r) {
        return this.getNth(r).filter((a) => a.has("#Imperative"));
      }
      toInfinitive(r) {
        return this.getNth(r).map((a) => {
          let i = Se(a),
            o = it(a, i);
          return N2(a, i, o.form);
        });
      }
      toPresentTense(r) {
        return this.getNth(r).map((a) => {
          let i = Se(a),
            o = it(a, i);
          return o.isInfinitive ? a : E2(a, i, o.form);
        });
      }
      toPastTense(r) {
        return this.getNth(r).map((a) => {
          let i = Se(a),
            o = it(a, i);
          return o.isInfinitive ? a : T2(a, i, o.form);
        });
      }
      toFutureTense(r) {
        return this.getNth(r).map((a) => {
          let i = Se(a),
            o = it(a, i);
          return o.isInfinitive ? a : H2(a, i, o.form);
        });
      }
      toGerund(r) {
        return this.getNth(r).map((a) => {
          let i = Se(a),
            o = it(a, i);
          return o.isInfinitive ? a : F2(a, i, o.form);
        });
      }
      toPastParticiple(r) {
        return this.getNth(r).map((a) => {
          let i = Se(a),
            o = it(a, i);
          return o.isInfinitive ? a : O2(a, i, o.form);
        });
      }
      conjugate(r) {
        const { conjugate: a, toInfinitive: i } =
          this.world.methods.two.transform.verb;
        return this.getNth(r).map((o) => {
          let s = Se(o),
            l = it(o, s);
          l.form === "imperative" && (l.form = "simple-present");
          let u = s.root.text("normal");
          if (!s.root.has("#Infinitive")) {
            let c = Ae(s.root);
            u = i(u, o.model, c) || u;
          }
          return a(u, o.model);
        }, []);
      }
      isNegative() {
        return this.if("#Negative");
      }
      isPositive() {
        return this.ifNo("#Negative");
      }
      toPositive() {
        let r = this.match("do not #Verb");
        return (r.found && r.remove("do not"), this.remove("#Negative"));
      }
      toNegative(r) {
        return this.getNth(r).map((a) => {
          let i = Se(a),
            o = it(a, i);
          return V2(a, i, o.form);
        });
      }
      update(r) {
        let a = new t(this.document, r);
        return ((a._cache = this._cache), a);
      }
    }
    ((t.prototype.toPast = t.prototype.toPastTense),
      (t.prototype.toPresent = t.prototype.toPresentTense),
      (t.prototype.toFuture = t.prototype.toFutureTense),
      (e.prototype.verbs = function (n) {
        let r = h2(this);
        return ((r = r.getNth(n)), new t(this.document, r.pointer));
      }));
  },
  S2 = { api: G2 },
  Ai = function (e, t) {
    let n = t.match(e);
    if (n.found) {
      let r = n.pronouns().refersTo();
      if (r.found) return r;
    }
    return t.none();
  },
  wl = function (e) {
    if (!e.found) return e;
    let [t] = e.fullPointer[0];
    return t && t > 0 ? e.update([[t - 1]]) : e.none();
  },
  M2 = function (e, t) {
    return t === "m"
      ? e.filter((n) => !n.presumedFemale().found)
      : t === "f"
        ? e.filter((n) => !n.presumedMale().found)
        : e;
  },
  kl = function (e, t) {
    let n = e.people();
    return (
      (n = M2(n, t)),
      n.found || ((n = e.nouns("#Actor")), n.found)
        ? n.last()
        : t === "f"
          ? Ai("(she|her|hers)", e)
          : t === "m"
            ? Ai("(he|him|his)", e)
            : e.none()
    );
  },
  B2 = function (e) {
    let t = e.nouns(),
      n = t.isPlural().notIf("#Pronoun");
    if (n.found) return n.last();
    let r = Ai("(they|their|theirs)", e);
    return r.found
      ? r
      : ((n = t.match(
          "(somebody|nobody|everybody|anybody|someone|noone|everyone|anyone)",
        )),
        n.found ? n.last() : e.none());
  },
  L2 = function (e, t) {
    if (t && t.found) {
      let n = e.docs[0][0];
      n.reference = t.ptrs[0];
    }
  },
  Na = function (e, t) {
    let n = e.before(),
      r = t(n);
    return r.found ||
      ((n = wl(e)), (r = t(n)), r.found) ||
      ((n = wl(n)), (r = t(n)), r.found)
      ? r
      : e.none();
  },
  W2 = function (e) {
    e.pronouns()
      .if("(he|him|his|she|her|hers|they|their|theirs|it|its)")
      .forEach((n) => {
        let r = null;
        (n.has("(he|him|his)")
          ? (r = Na(n, (a) => kl(a, "m")))
          : n.has("(she|her|hers)")
            ? (r = Na(n, (a) => kl(a, "f")))
            : n.has("(they|their|theirs)") && (r = Na(n, B2)),
          r && r.found && L2(n, r));
      });
  },
  q2 = function (e) {
    class t extends e {
      constructor(r, a, i) {
        (super(r, a, i), (this.viewType = "Pronouns"));
      }
      hasReference() {
        return (
          this.compute("coreference"),
          this.filter((r) => r.docs[0][0].reference)
        );
      }
      refersTo() {
        return (
          this.compute("coreference"),
          this.map((r) => {
            if (!r.found) return r.none();
            let a = r.docs[0][0];
            return a.reference ? r.update([a.reference]) : r.none();
          })
        );
      }
      update(r) {
        let a = new t(this.document, r);
        return ((a._cache = this._cache), a);
      }
    }
    e.prototype.pronouns = function (n) {
      let r = this.match("#Pronoun");
      return ((r = r.getNth(n)), new t(r.document, r.pointer));
    };
  },
  K2 = { compute: { coreference: W2 }, api: q2 };
k.plugin(sv);
k.plugin(cv);
k.plugin(Cv);
k.plugin(K2);
k.plugin(qv);
k.plugin(Uv);
k.plugin(lw);
k.plugin(Vw);
k.plugin(Mw);
k.plugin(e2);
k.plugin(c2);
k.plugin(S2);
const J2 = function (e) {
    let t = null;
    return (
      e.has("^(between|within) #Date") ||
        (e.has("#Month") &&
          ((t = e.match("[#Month #Value] and? #Month", 0).ifNo("@hasDash$")),
          t.found && (e = e.splitAfter(t)),
          (t = e.match("[#Value #Month] and? #Value #Month", 0)),
          t.found && (e = e.splitAfter(t)),
          (t = e.match("^[#Month] and? #Month #Ordinal?$", 0)),
          t.found && (e = e.splitAfter(t)),
          (t = e.match("[#Month #Value] #Month", 0).ifNo("@hasDash$")),
          t.found && (e = e.splitAfter(t))),
        e.has("#WeekDay") &&
          ((t = e.match("^[#WeekDay] and? #WeekDay$", 0).ifNo("@hasDash$")),
          t.found && (e = e.splitAfter(t)),
          (t = e.match("#WeekDay #WeekDay and? #WeekDay")),
          t.found && (e = e.splitOn("#WeekDay")),
          (t = e
            .match("[#WeekDay] (and|or|this|next)? #WeekDay", 0)
            .ifNo("@hasDash$")),
          t.found && (e = e.splitAfter("#WeekDay"))),
        (t = e.match("(this|next) #Duration [(today|tomorrow|yesterday)]", 0)),
        t.found && (e = e.splitBefore(t)),
        (t = e.match("[(today|tomorrow|yesterday)] #Value #Month", 0)),
        t.found && (e = e.splitAfter(t)),
        (t = e
          .match(
            "[(today|tomorrow|yesterday)] (today|tomorrow|yesterday|#WeekDay)",
            0,
          )
          .ifNo("@hasDash$")),
        t.found && (e = e.splitAfter(t)),
        (t = e.match("#Year [and] #Year", 0)),
        t.found && (e = e.splitAfter(t)),
        (e = e.not("^and")),
        (e = e.not("and$"))),
      e
    );
  },
  _2 = function (e) {
    let t = e.match("#Date+");
    t = t.filter((r) => {
      let a = r.has("^#Duration+$") || r.has("^#Value #Duration+$");
      return a === !0 && r.has("(#FinancialQuarter|quarter)") ? !0 : a === !1;
    });
    let n = t.match(
      "[#Cardinal #Duration (in|on|this|next|during|for)] #Date",
      0,
    );
    return (
      n.found && (t = t.not(n)),
      (n = t.match("[#Cardinal #Duration] #WeekDay", 0)),
      n.found && (t = t.not(n)),
      (n = t.match("#Date [for #Value #Duration]$", 0)),
      n.found && (t = t.not(n)),
      (n = t.match("[#Cardinal #Duration] #Date", 0)),
      n.found &&
        !t.has("#Cardinal #Duration] (ago|from|before|after|back)") &&
        (t = t.not(n)),
      (n = t.match("for #Cardinal #Duration")),
      n.found && (t = t.not(n)),
      (t = t.notIf("^one (#WeekDay|#Month)$")),
      (t = J2(t)),
      (t = t.notIf("(#Money|#Percentage)")),
      (t = t.notIf("^per #Duration")),
      t
    );
  },
  U2 = {
    second: !0,
    minute: !0,
    hour: !0,
    day: !0,
    week: !0,
    weekend: !0,
    month: !0,
    season: !0,
    quarter: !0,
    year: !0,
  },
  Pl = { wk: "week", min: "minute", sec: "second", weekend: "week" },
  Al = function (e) {
    let t = e.match("#Duration").text("normal");
    return ((t = t.replace(/s$/, "")), Pl.hasOwnProperty(t) && (t = Pl[t]), t);
  },
  R2 = function (e) {
    let t = {},
      n = e.none(),
      r = e.match("#DateShift+");
    if (r.found === !1) return { res: t, m: n };
    if (
      (r.match("#Cardinal #Duration").forEach((a) => {
        let i = a.match("#Cardinal").numbers().get()[0];
        if (i && typeof i == "number") {
          let o = Al(a);
          U2[o] === !0 && (t[o] = i);
        }
      }),
      r.has("(before|ago|hence|back)$") === !0 &&
        Object.keys(t).forEach((a) => (t[a] *= -1)),
      (n = r.match("#Cardinal #Duration")),
      (r = r.not(n)),
      (n = r.match("[<unit>#Duration] [<dir>(after|before)]")),
      n.found)
    ) {
      let a = n.groups("unit").text("reduced"),
        i = n.groups("dir").text("reduced");
      i === "after" ? (t[a] = 1) : i === "before" && (t[a] = -1);
    }
    if (((n = r.match("half (a|an) [#Duration]", 0)), n.found)) {
      let a = Al(n);
      t[a] = 0.5;
    }
    return ((n = e.match("#DateShift+")), { result: t, m: n });
  },
  Y2 = { minute: !0 },
  Q2 = function (e) {
    let t = e.match("[<num>#Value] [<unit>#Duration+] (of|in)");
    if (t.found) {
      let n = t.groups(),
        r = n.num.numbers().get()[0],
        a = n.unit.text("reduced"),
        i = { unit: a, num: Number(r) || 0 };
      return (Y2[a] || (i.num -= 1), { result: i, m: t });
    }
    if (
      ((t = e.match(
        "[<dir>(first|initial|last|final)] [<unit>#Duration+] (of|in)",
      )),
      t.found)
    ) {
      let n = t.groups(),
        r = n.dir.text("reduced"),
        a = n.unit.text("reduced");
      return (
        r === "initial" && (r = "first"),
        r === "final" && (r = "last"),
        { result: { unit: a, dir: r }, m: t }
      );
    }
    return { result: null, m: e.none() };
  },
  Z2 = 3600 * 1e3,
  xl = (e, t, n) => {
    const [r, a] = e.split("/"),
      [i, o] = a.split(":");
    return Date.UTC(n, r - 1, i, o) - t * Z2;
  },
  gc = (e, t, n, r, a) => {
    const i = new Date(e).getUTCFullYear(),
      o = xl(t, a, i),
      s = xl(n, r, i);
    return e >= o && e < s;
  },
  X2 = (e) => {
    let n = e.timezones[e.tz];
    if (n === void 0)
      return (console.warn("Warning: couldn't find timezone " + e.tz), 0);
    if (n.dst === void 0) return n.offset;
    let r = n.offset,
      a = n.offset + 1;
    n.hem === "n" && (a = r - 1);
    let i = n.dst.split("->");
    return gc(e.epoch, i[0], i[1], r, a) === !0 ? r : a;
  },
  Cl = {
    "9|s": "2/dili,2/jayapura",
    "9|n":
      "2/chita,2/khandyga,2/pyongyang,2/seoul,2/tokyo,2/yakutsk,11/palau,japan,rok",
    "9.5|s|04/07:03->10/06:04": "4/adelaide,4/broken_hill,4/south,4/yancowinna",
    "9.5|s": "4/darwin,4/north",
    "8|s|03/13:01->10/02:00": "12/casey",
    "8|s":
      "2/kuala_lumpur,2/makassar,2/singapore,4/perth,2/ujung_pandang,4/west,singapore",
    "8|n":
      "2/brunei,2/choibalsan,2/hong_kong,2/irkutsk,2/kuching,2/macau,2/manila,2/shanghai,2/taipei,2/ulaanbaatar,2/chongqing,2/chungking,2/harbin,2/macao,2/ulan_bator,hongkong,prc,roc",
    "8.75|s": "4/eucla",
    "7|s": "12/davis,2/jakarta,9/christmas",
    "7|n":
      "2/bangkok,2/barnaul,2/hovd,2/krasnoyarsk,2/novokuznetsk,2/novosibirsk,2/phnom_penh,2/pontianak,2/ho_chi_minh,2/tomsk,2/vientiane,2/saigon",
    "6|s": "12/vostok",
    "6|n":
      "2/almaty,2/bishkek,2/dhaka,2/omsk,2/qyzylorda,2/qostanay,2/thimphu,2/urumqi,9/chagos,2/dacca,2/kashgar,2/thimbu",
    "6.5|n": "2/yangon,9/cocos,2/rangoon",
    "5|s": "12/mawson,9/kerguelen",
    "5|n":
      "2/aqtau,2/aqtobe,2/ashgabat,2/atyrau,2/dushanbe,2/karachi,2/oral,2/samarkand,2/tashkent,2/yekaterinburg,9/maldives,2/ashkhabad",
    "5.75|n": "2/kathmandu,2/katmandu",
    "5.5|n": "2/kolkata,2/colombo,2/calcutta",
    "4|s": "9/reunion",
    "4|n":
      "2/baku,2/dubai,2/muscat,2/tbilisi,2/yerevan,8/astrakhan,8/samara,8/saratov,8/ulyanovsk,8/volgograd,9/mahe,9/mauritius,2/volgograd",
    "4.5|n": "2/kabul",
    "3|s": "12/syowa,9/antananarivo",
    "3|n|04/26:02->10/31:24": "0/cairo,egypt",
    "3|n|04/20:04->10/26:02": "2/gaza,2/hebron",
    "3|n|03/31:05->10/27:04":
      "2/famagusta,2/nicosia,8/athens,8/bucharest,8/helsinki,8/kyiv,8/mariehamn,8/riga,8/sofia,8/tallinn,8/uzhgorod,8/vilnius,8/zaporozhye,8/nicosia,8/kiev,eet",
    "3|n|03/31:04->10/27:03": "8/chisinau,8/tiraspol",
    "3|n|03/31:02->10/26:24": "2/beirut",
    "3|n|03/29:04->10/27:02": "2/jerusalem,2/tel_aviv,israel",
    "3|n":
      "0/addis_ababa,0/asmara,0/asmera,0/dar_es_salaam,0/djibouti,0/juba,0/kampala,0/mogadishu,0/nairobi,2/aden,2/amman,2/baghdad,2/bahrain,2/damascus,2/kuwait,2/qatar,2/riyadh,8/istanbul,8/kirov,8/minsk,8/moscow,8/simferopol,9/comoro,9/mayotte,2/istanbul,turkey,w-su",
    "3.5|n": "2/tehran,iran",
    "2|s|03/31:04->10/27:02": "12/troll",
    "2|s":
      "0/gaborone,0/harare,0/johannesburg,0/lubumbashi,0/lusaka,0/maputo,0/maseru,0/mbabane",
    "2|n|03/31:04->10/27:03":
      "0/ceuta,arctic/longyearbyen,8/amsterdam,8/andorra,8/belgrade,8/berlin,8/bratislava,8/brussels,8/budapest,8/busingen,8/copenhagen,8/gibraltar,8/ljubljana,8/luxembourg,8/madrid,8/malta,8/monaco,8/oslo,8/paris,8/podgorica,8/prague,8/rome,8/san_marino,8/sarajevo,8/skopje,8/stockholm,8/tirane,8/vaduz,8/vatican,8/vienna,8/warsaw,8/zagreb,8/zurich,3/jan_mayen,poland,cet,met",
    "2|n":
      "0/blantyre,0/bujumbura,0/khartoum,0/kigali,0/tripoli,8/kaliningrad,libya",
    "1|s": "0/brazzaville,0/kinshasa,0/luanda,0/windhoek",
    "1|n|03/31:03->10/27:02":
      "3/canary,3/faroe,3/madeira,8/dublin,8/guernsey,8/isle_of_man,8/jersey,8/lisbon,8/london,3/faeroe,eire,8/belfast,gb-eire,gb,portugal,wet",
    "1|n":
      "0/algiers,0/bangui,0/douala,0/lagos,0/libreville,0/malabo,0/ndjamena,0/niamey,0/porto-novo,0/tunis",
    "14|n": "11/kiritimati",
    "13|s": "11/apia,11/tongatapu",
    "13|n": "11/enderbury,11/kanton,11/fakaofo",
    "12|s|04/07:03->09/29:04": "12/mcmurdo,11/auckland,12/south_pole,nz",
    "12|s": "11/fiji",
    "12|n":
      "2/anadyr,2/kamchatka,2/srednekolymsk,11/funafuti,11/kwajalein,11/majuro,11/nauru,11/tarawa,11/wake,11/wallis,kwajalein",
    "12.75|s|04/07:03->04/07:02": "11/chatham,nz-chat",
    "11|s|04/07:03->10/06:04": "12/macquarie",
    "11|s": "11/bougainville",
    "11|n":
      "2/magadan,2/sakhalin,11/efate,11/guadalcanal,11/kosrae,11/noumea,11/pohnpei,11/ponape",
    "11.5|n|04/07:03->10/06:04": "11/norfolk",
    "10|s|04/07:03->10/06:04":
      "4/currie,4/hobart,4/melbourne,4/sydney,4/act,4/canberra,4/nsw,4/tasmania,4/victoria",
    "10|s":
      "12/dumontdurville,4/brisbane,4/lindeman,11/port_moresby,4/queensland",
    "10|n":
      "2/ust-nera,2/vladivostok,11/guam,11/saipan,11/chuuk,11/truk,11/yap",
    "10.5|s|04/07:01->10/06:02": "4/lord_howe,4/lhi",
    "0|s|03/10:03->04/14:04": "0/casablanca,0/el_aaiun",
    "0|n|03/31:02->10/27:01": "3/azores",
    "0|n|03/31:01->10/26:24": "1/scoresbysund",
    "0|n":
      "0/abidjan,0/accra,0/bamako,0/banjul,0/bissau,0/conakry,0/dakar,0/freetown,0/lome,0/monrovia,0/nouakchott,0/ouagadougou,0/sao_tome,1/danmarkshavn,3/reykjavik,3/st_helena,13/gmt,13/utc,0/timbuktu,13/greenwich,13/uct,13/universal,13/zulu,gmt-0,gmt+0,gmt0,greenwich,iceland,uct,universal,utc,zulu,13/unknown,factory",
    "-9|n|03/10:04->11/03:02": "1/adak,1/atka,us/aleutian",
    "-9|n": "11/gambier",
    "-9.5|n": "11/marquesas",
    "-8|n|03/10:04->11/03:02":
      "1/anchorage,1/juneau,1/metlakatla,1/nome,1/sitka,1/yakutat,us/alaska",
    "-8|n": "11/pitcairn",
    "-7|n|03/10:04->11/03:02":
      "1/los_angeles,1/santa_isabel,1/tijuana,1/vancouver,1/ensenada,6/pacific,10/bajanorte,us/pacific-new,us/pacific",
    "-7|n":
      "1/creston,1/dawson,1/dawson_creek,1/fort_nelson,1/hermosillo,1/mazatlan,1/phoenix,1/whitehorse,6/yukon,10/bajasur,us/arizona,mst",
    "-6|s|04/06:22->09/07:24": "11/easter,7/easterisland",
    "-6|n|04/07:02->10/27:02": "1/merida",
    "-6|n|03/10:04->11/03:02":
      "1/boise,1/cambridge_bay,1/denver,1/edmonton,1/inuvik,1/north_dakota,1/ojinaga,1/ciudad_juarez,1/yellowknife,1/shiprock,6/mountain,navajo,us/mountain",
    "-6|n":
      "1/bahia_banderas,1/belize,1/chihuahua,1/costa_rica,1/el_salvador,1/guatemala,1/managua,1/mexico_city,1/monterrey,1/regina,1/swift_current,1/tegucigalpa,11/galapagos,6/east-saskatchewan,6/saskatchewan,10/general",
    "-5|s": "1/lima,1/rio_branco,1/porto_acre,5/acre",
    "-5|n|03/10:04->11/03:02":
      "1/chicago,1/matamoros,1/menominee,1/rainy_river,1/rankin_inlet,1/resolute,1/winnipeg,1/indiana/knox,1/indiana/tell_city,1/north_dakota/beulah,1/north_dakota/center,1/north_dakota/new_salem,1/knox_in,6/central,us/central,us/indiana-starke",
    "-5|n":
      "1/bogota,1/cancun,1/cayman,1/coral_harbour,1/eirunepe,1/guayaquil,1/jamaica,1/panama,1/atikokan,jamaica,est",
    "-4|s|04/06:24->09/08:02": "1/santiago,7/continental",
    "-4|s|03/23:24->10/06:02": "1/asuncion",
    "-4|s": "1/campo_grande,1/cuiaba,1/la_paz,1/manaus,5/west",
    "-4|n|03/10:04->11/03:02":
      "1/detroit,1/grand_turk,1/indiana,1/indianapolis,1/iqaluit,1/kentucky,1/louisville,1/montreal,1/nassau,1/new_york,1/nipigon,1/pangnirtung,1/port-au-prince,1/thunder_bay,1/toronto,1/indiana/marengo,1/indiana/petersburg,1/indiana/vevay,1/indiana/vincennes,1/indiana/winamac,1/kentucky/monticello,1/fort_wayne,1/indiana/indianapolis,1/kentucky/louisville,6/eastern,us/east-indiana,us/eastern,us/michigan",
    "-4|n|03/10:02->11/03:01": "1/havana,cuba",
    "-4|n":
      "1/anguilla,1/antigua,1/aruba,1/barbados,1/blanc-sablon,1/boa_vista,1/caracas,1/curacao,1/dominica,1/grenada,1/guadeloupe,1/guyana,1/kralendijk,1/lower_princes,1/marigot,1/martinique,1/montserrat,1/port_of_spain,1/porto_velho,1/puerto_rico,1/santo_domingo,1/st_barthelemy,1/st_kitts,1/st_lucia,1/st_thomas,1/st_vincent,1/tortola,1/virgin",
    "-3|s":
      "1/argentina,1/buenos_aires,1/catamarca,1/cordoba,1/fortaleza,1/jujuy,1/mendoza,1/montevideo,1/punta_arenas,1/sao_paulo,12/palmer,12/rothera,3/stanley,1/argentina/la_rioja,1/argentina/rio_gallegos,1/argentina/salta,1/argentina/san_juan,1/argentina/san_luis,1/argentina/tucuman,1/argentina/ushuaia,1/argentina/comodrivadavia,1/argentina/buenos_aires,1/argentina/catamarca,1/argentina/cordoba,1/argentina/jujuy,1/argentina/mendoza,1/argentina/rosario,1/rosario,5/east",
    "-3|n|03/10:04->11/03:02":
      "1/glace_bay,1/goose_bay,1/halifax,1/moncton,1/thule,3/bermuda,6/atlantic",
    "-3|n":
      "1/araguaina,1/bahia,1/belem,1/cayenne,1/maceio,1/paramaribo,1/recife,1/santarem",
    "-2|n|03/31:01->10/26:24": "1/nuuk,1/godthab",
    "-2|n|03/10:04->11/03:02": "1/miquelon",
    "-2|n": "1/noronha,3/south_georgia,5/denoronha",
    "-2.5|n|03/10:04->11/03:02": "1/st_johns,6/newfoundland",
    "-1|n": "3/cape_verde",
    "-11|n": "11/midway,11/niue,11/pago_pago,11/samoa,us/samoa",
    "-10|n": "11/honolulu,11/johnston,11/rarotonga,11/tahiti,us/hawaii,hst",
  },
  ek = [
    "africa",
    "america",
    "asia",
    "atlantic",
    "australia",
    "brazil",
    "canada",
    "chile",
    "europe",
    "indian",
    "mexico",
    "pacific",
    "antarctica",
    "etc",
  ];
let An = {};
Object.keys(Cl).forEach((e) => {
  let t = e.split("|"),
    n = { offset: Number(t[0]), hem: t[1] };
  (t[2] && (n.dst = t[2]),
    Cl[e].split(",").forEach((a) => {
      ((a = a.replace(/(^[0-9]+)\//, (i, o) => ((o = Number(o)), ek[o] + "/"))),
        (An[a] = n));
    }));
});
An.utc = { offset: 0, hem: "n" };
for (let e = -14; e <= 14; e += 0.5) {
  let t = e;
  t > 0 && (t = "+" + t);
  let n = "etc/gmt" + t;
  ((An[n] = { offset: e * -1, hem: "n" }),
    (n = "utc/gmt" + t),
    (An[n] = { offset: e * -1, hem: "n" }));
}
const tk = "utc",
  nk = () => {
    if (typeof Intl > "u" || typeof Intl.DateTimeFormat > "u") return null;
    let e = Intl.DateTimeFormat();
    if (typeof e > "u" || typeof e.resolvedOptions > "u") return null;
    let t = e.resolvedOptions().timeZone;
    return t ? t.toLowerCase() : null;
  },
  rk = () => {
    let e = nk();
    return e === null ? tk : e;
  },
  ak = /(-?[0-9]+)h(rs)?/i,
  ik = /(-?[0-9]+)/,
  ok = /utc([\-+]?[0-9]+)/i,
  sk = /gmt([\-+]?[0-9]+)/i,
  xr = function (e) {
    return (
      (e = Number(e)),
      e >= -13 && e <= 13
        ? ((e = e * -1), (e = (e > 0 ? "+" : "") + e), "etc/gmt" + e)
        : null
    );
  },
  lk = function (e) {
    let t = e.match(ak);
    if (t !== null || ((t = e.match(ok)), t !== null)) return xr(t[1]);
    if (((t = e.match(sk)), t !== null)) {
      let n = Number(t[1]) * -1;
      return xr(n);
    }
    return ((t = e.match(ik)), t !== null ? xr(t[1]) : null);
  };
let Cr = rk();
const Dl = Object.keys(An).reduce((e, t) => {
    let n = t.split("/")[1] || "";
    return ((n = n.replace(/_/g, " ")), (e[n] = t), e);
  }, {}),
  uk = (e) => (
    (e = e.replace(/ time/g, "")),
    (e = e.replace(/ (standard|daylight|summer)/g, "")),
    (e = e.replace(/\b(east|west|north|south)ern/g, "$1")),
    (e = e.replace(/\b(africa|america|australia)n/g, "$1")),
    (e = e.replace(/\beuropean/g, "europe")),
    (e = e.replace(/islands/g, "island")),
    e
  ),
  ta = (e, t) => {
    if (!e)
      return (
        t.hasOwnProperty(Cr) ||
          (console.warn(
            `Unrecognized IANA id '${Cr}'. Setting fallback tz to UTC.`,
          ),
          (Cr = "utc")),
        Cr
      );
    typeof e != "string" &&
      console.error(
        "Timezone must be a string - recieved: '",
        e,
        `'
`,
      );
    let n = e.trim();
    if (
      ((n = n.toLowerCase()),
      t.hasOwnProperty(n) === !0 || ((n = uk(n)), t.hasOwnProperty(n) === !0))
    )
      return n;
    if (Dl.hasOwnProperty(n) === !0) return Dl[n];
    if (/[0-9]/.test(n) === !0) {
      let r = lk(n);
      if (r) return r;
    }
    throw new Error(
      "Spacetime: Cannot find timezone named: '" +
        e +
        "'. Please enter an IANA timezone id.",
    );
  };
function tr(e) {
  return (e % 4 === 0 && e % 100 !== 0) || e % 400 === 0;
}
function yc(e) {
  return (
    Object.prototype.toString.call(e) === "[object Date]" && !isNaN(e.valueOf())
  );
}
function ck(e) {
  return Object.prototype.toString.call(e) === "[object Array]";
}
function wt(e) {
  return Object.prototype.toString.call(e) === "[object Object]";
}
function hk(e) {
  return Object.prototype.toString.call(e) === "[object Boolean]";
}
function w(e, t = 2) {
  let n = "0";
  return (
    (e = e + ""),
    e.length >= t ? e : new Array(t - e.length + 1).join(n) + e
  );
}
function dk(e) {
  return e ? e[0].toUpperCase() + e.substr(1) : "";
}
function nt(e) {
  let t = e % 10,
    n = e % 100;
  return t === 1 && n !== 11
    ? e + "st"
    : t === 2 && n !== 12
      ? e + "nd"
      : t === 3 && n !== 13
        ? e + "rd"
        : e + "th";
}
function kn(e) {
  return (
    (e = String(e)),
    (e = e.replace(/([0-9])(st|nd|rd|th)$/i, "$1")),
    parseInt(e, 10)
  );
}
function en(e = "") {
  return (
    (e = e.toLowerCase().trim()),
    (e = e.replace(/ies$/, "y")),
    (e = e.replace(/s$/, "")),
    (e = e.replace(/-/g, "")),
    e === "day" || e === "days"
      ? "date"
      : e === "min" || e === "mins"
        ? "minute"
        : e
  );
}
function Tn(e) {
  return typeof e == "number"
    ? e
    : yc(e)
      ? e.getTime()
      : e.epoch
        ? e.epoch
        : null;
}
function Bt(e, t) {
  return wt(e) === !1 ? t.clone().set(e) : e;
}
function Vn(e, t = "") {
  const n = e > 0 ? "+" : "-",
    r = Math.abs(e),
    a = w(parseInt("" + r, 10)),
    i = w((r % 1) * 60);
  return `${n}${a}${t}${i}`;
}
const xi = { year: new Date().getFullYear(), month: 0, date: 1 },
  fk = (e, t, n) => {
    if (t.length === 0) return e;
    let r = [
      "year",
      "month",
      "date",
      "hour",
      "minute",
      "second",
      "millisecond",
    ];
    for (let a = 0; a < r.length; a++) {
      let i = t[a] || n[r[a]] || xi[r[a]] || 0;
      e = e[r[a]](i);
    }
    return e;
  },
  mk = (e, t, n) => {
    if (Object.keys(t).length === 0) return e;
    t = Object.assign({}, xi, n, t);
    let r = Object.keys(t);
    for (let a = 0; a < r.length; a++) {
      let i = r[a];
      if (
        e[i] === void 0 ||
        typeof e[i] != "function" ||
        t[i] === null ||
        t[i] === void 0 ||
        t[i] === ""
      )
        continue;
      let o = t[i] || n[i] || xi[i] || 0;
      e = e[i](o);
    }
    return e;
  },
  pk = function (e, t) {
    return (
      t > 0 &&
        t < 25e8 &&
        e.silent === !1 &&
        (console.warn("  - Warning: You are setting the date to January 1970."),
        console.warn("       -   did input seconds instead of milliseconds?")),
      (e.epoch = t),
      e
    );
  },
  gk = { parseArray: fk, parseObject: mk, parseNumber: pk },
  zt = function (e) {
    return (
      (e.epoch = Date.now()),
      Object.keys(e._today || {}).forEach((t) => {
        typeof e[t] == "function" && (e = e[t](e._today[t]));
      }),
      e
    );
  },
  na = {
    now: (e) => zt(e),
    today: (e) => zt(e),
    tonight: (e) => ((e = zt(e)), (e = e.hour(18)), e),
    tomorrow: (e) => (
      (e = zt(e)),
      (e = e.add(1, "day")),
      (e = e.startOf("day")),
      e
    ),
    yesterday: (e) => (
      (e = zt(e)),
      (e = e.subtract(1, "day")),
      (e = e.startOf("day")),
      e
    ),
    christmas: (e) => {
      let t = zt(e).year();
      return ((e = e.set([t, 11, 25, 18, 0, 0])), e);
    },
    "new years": (e) => {
      let t = zt(e).year();
      return ((e = e.set([t, 11, 31, 18, 0, 0])), e);
    },
  };
na["new years eve"] = na["new years"];
const yk = function (e) {
  return (
    (e = e.replace(
      /\b(mon|tues?|wed|wednes|thur?s?|fri|sat|satur|sun)(day)?\b/i,
      "",
    )),
    (e = e.replace(/([0-9])(th|rd|st|nd)/, "$1")),
    (e = e.replace(/,/g, "")),
    (e = e.replace(/ +/g, " ").trim()),
    e
  );
};
let O = { millisecond: 1 };
O.second = 1e3;
O.minute = 6e4;
O.hour = 36e5;
O.day = 864e5;
O.date = O.day;
O.month = 864e5 * 29.5;
O.week = 6048e5;
O.year = 3154e7;
Object.keys(O).forEach((e) => {
  O[e + "s"] = O[e];
});
const Dr = (e, t, n, r, a) => {
    let i = e.d[n]();
    if (i === t) return;
    let o = a === null ? null : e.d[a](),
      s = e.epoch,
      l = t - i;
    ((e.epoch += O[r] * l),
      r === "day" && Math.abs(l) > 28 && t < 28 && (e.epoch += O.hour),
      a !== null && o !== e.d[a]() && (e.epoch = s));
    const u = O[r] / 2;
    for (; e.d[n]() < t;) e.epoch += u;
    for (; e.d[n]() > t;) e.epoch -= u;
    a !== null && o !== e.d[a]() && (e.epoch = s);
  },
  Ta = {
    year: {
      valid: (e) => e > -4e3 && e < 4e3,
      walkTo: (e, t) => Dr(e, t, "getFullYear", "year", null),
    },
    month: {
      valid: (e) => e >= 0 && e <= 11,
      walkTo: (e, t) => {
        let n = e.d,
          r = n.getMonth(),
          a = e.epoch,
          i = n.getFullYear();
        if (r === t) return;
        let o = t - r;
        for (
          e.epoch += O.day * (o * 28), i !== e.d.getFullYear() && (e.epoch = a);
          e.d.getMonth() < t;
        )
          e.epoch += O.day;
        for (; e.d.getMonth() > t;) e.epoch -= O.day;
      },
    },
    date: {
      valid: (e) => e > 0 && e <= 31,
      walkTo: (e, t) => Dr(e, t, "getDate", "day", "getMonth"),
    },
    hour: {
      valid: (e) => e >= 0 && e < 24,
      walkTo: (e, t) => Dr(e, t, "getHours", "hour", "getDate"),
    },
    minute: {
      valid: (e) => e >= 0 && e < 60,
      walkTo: (e, t) => Dr(e, t, "getMinutes", "minute", "getHours"),
    },
    second: {
      valid: (e) => e >= 0 && e < 60,
      walkTo: (e, t) => {
        e.epoch = e.seconds(t).epoch;
      },
    },
    millisecond: {
      valid: (e) => e >= 0 && e < 1e3,
      walkTo: (e, t) => {
        e.epoch = e.milliseconds(t).epoch;
      },
    },
  },
  N = (e, t) => {
    let n = Object.keys(Ta),
      r = e.clone();
    for (let a = 0; a < n.length; a++) {
      let i = n[a],
        o = t[i];
      if (
        (o === void 0 && (o = r[i]()),
        typeof o == "string" && (o = parseInt(o, 10)),
        !Ta[i].valid(o))
      ) {
        ((e.epoch = null),
          e.silent === !1 && console.warn("invalid " + i + ": " + o));
        return;
      }
      Ta[i].walkTo(e, o);
    }
  },
  Rt = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
let Jn = [
    "jan",
    "feb",
    "mar",
    "apr",
    "may",
    "jun",
    "jul",
    "aug",
    "sep",
    "oct",
    "nov",
    "dec",
  ],
  _n = [
    "january",
    "february",
    "march",
    "april",
    "may",
    "june",
    "july",
    "august",
    "september",
    "october",
    "november",
    "december",
  ];
function bk() {
  const e = { sep: 8 };
  for (let t = 0; t < Jn.length; t++) e[Jn[t]] = t;
  for (let t = 0; t < _n.length; t++) e[_n[t]] = t;
  return e;
}
function On() {
  return Jn;
}
function vk() {
  return _n;
}
function bc() {
  return bk();
}
function wk(e) {
  ((Jn = e.short || Jn), (_n = e.long || _n));
}
const vc = (e, t) => {
    if (!t) return e;
    t = t.trim().toLowerCase();
    let n = 0;
    if (
      (/^[+-]?[0-9]{2}:[0-9]{2}$/.test(t) &&
        (/:00/.test(t) === !0 && (t = t.replace(/:00/, "")),
        /:30/.test(t) === !0 && (t = t.replace(/:30/, ".5"))),
      /^[+-]?[0-9]{4}$/.test(t) && (t = t.replace(/30$/, ".5")),
      (n = parseFloat(t)),
      Math.abs(n) > 100 && (n = n / 100),
      n === 0 || t === "Z" || t === "z")
    )
      return ((e.tz = "etc/gmt"), e);
    ((n *= -1), n >= 0 && (n = "+" + n));
    let r = "etc/gmt" + n;
    return (e.timezones[r] && (e.tz = r), e);
  },
  kk = function (e = "") {
    return (
      (e = String(e)),
      e.length > 3
        ? (e = e.substring(0, 3))
        : e.length === 1
          ? (e = e + "00")
          : e.length === 2 && (e = e + "0"),
      Number(e) || 0
    );
  },
  he = (e, t = "") => {
    t = t.replace(/^\s+/, "").toLowerCase();
    let n = t.match(
      /([0-9]{1,2}):([0-9]{1,2}):?([0-9]{1,2})?[:.]?([0-9]{1,4})?/,
    );
    if (n !== null) {
      let [, r, a, i, o] = n;
      if (
        ((r = Number(r)),
        r < 0 ||
          r > 24 ||
          ((a = Number(a)), n[2].length < 2 || a < 0 || a > 59))
      )
        return e.startOf("day");
      ((e = e.hour(r)),
        (e = e.minute(a)),
        (e = e.seconds(i || 0)),
        (e = e.millisecond(kk(o))));
      let s = t.match(/[0-9] ?(am|pm)\b/);
      return (s !== null && s[1] && (e = e.ampm(s[1])), e);
    }
    if (((n = t.match(/([0-9]+) ?(am|pm)/)), n !== null && n[1])) {
      let r = Number(n[1]);
      return r > 12 || r < 1
        ? e.startOf("day")
        : ((e = e.hour(n[1] || 0)),
          (e = e.ampm(n[2])),
          (e = e.startOf("hour")),
          e);
    }
    return ((e = e.startOf("day")), e);
  };
let $l = bc();
const de = (e) => {
    if (Rt.hasOwnProperty(e.month) !== !0) return !1;
    if (e.month === 1) return tr(e.year) && e.date <= 29 ? !0 : e.date <= 28;
    let t = Rt[e.month] || 0;
    return e.date <= t;
  },
  ct = (e = "", t) => {
    if (((e = e.trim()), /^'[0-9][0-9]$/.test(e) === !0)) {
      let r = Number(e.replace(/'/, ""));
      return r > 50 ? 1900 + r : 2e3 + r;
    }
    let n = parseInt(e, 10);
    return (!n && t && (n = t.year), (n = n || new Date().getFullYear()), n);
  },
  Ct = function (e) {
    return ((e = e.toLowerCase().trim()), e === "sept" ? $l.sep : $l[e]);
  },
  Pk = [
    {
      reg: /^(-?0{0,2}[0-9]{3,4})-([0-9]{1,2})-([0-9]{1,2})[T| ]([0-9.:]+)(Z|[0-9-+:]+)?$/i,
      parse: (e, t) => {
        let n = { year: t[1], month: parseInt(t[2], 10) - 1, date: t[3] };
        return de(n) === !1
          ? ((e.epoch = null), e)
          : (vc(e, t[5]), N(e, n), (e = he(e, t[4])), e);
      },
    },
    {
      reg: /^([0-9]{4})[\-/. ]([0-9]{1,2})[\-/. ]([0-9]{1,2})( [0-9]{1,2}(:[0-9]{0,2})?(:[0-9]{0,3})? ?(am|pm)?)?$/i,
      parse: (e, t) => {
        let n = {
          year: t[1],
          month: parseInt(t[2], 10) - 1,
          date: parseInt(t[3], 10),
        };
        return (
          n.month >= 12 &&
            ((n.date = parseInt(t[2], 10)), (n.month = parseInt(t[3], 10) - 1)),
          de(n) === !1 ? ((e.epoch = null), e) : (N(e, n), (e = he(e, t[4])), e)
        );
      },
    },
    {
      reg: /^([0-9]{4})[\-/. ]([a-z]+)[\-/. ]([0-9]{1,2})( [0-9]{1,2}(:[0-9]{0,2})?(:[0-9]{0,3})? ?(am|pm)?)?$/i,
      parse: (e, t) => {
        let n = {
          year: ct(t[1], e._today),
          month: Ct(t[2]),
          date: kn(t[3] || ""),
        };
        return de(n) === !1
          ? ((e.epoch = null), e)
          : (N(e, n), (e = he(e, t[4])), e);
      },
    },
  ],
  Ak = [
    {
      reg: /^([0-9]{1,2})[-/.]([0-9]{1,2})[\-/.]?([0-9]{4})?( [0-9]{1,2}:[0-9]{2}:?[0-9]{0,2} ?(am|pm|gmt))?$/i,
      parse: (e, t) => {
        let n = parseInt(t[1], 10) - 1,
          r = parseInt(t[2], 10);
        (e.british || n >= 12) &&
          ((r = parseInt(t[1], 10)), (n = parseInt(t[2], 10) - 1));
        let a = {
          date: r,
          month: n,
          year: ct(t[3], e._today) || new Date().getFullYear(),
        };
        return de(a) === !1
          ? ((e.epoch = null), e)
          : (N(e, a), (e = he(e, t[4])), e);
      },
    },
    {
      reg: /^([a-z]+)[\-/. ]([0-9]{1,2})[\-/. ]?([0-9]{4}|'[0-9]{2})?( [0-9]{1,2}(:[0-9]{0,2})?(:[0-9]{0,3})? ?(am|pm)?)?$/i,
      parse: (e, t) => {
        let n = {
          year: ct(t[3], e._today),
          month: Ct(t[1]),
          date: kn(t[2] || ""),
        };
        return de(n) === !1
          ? ((e.epoch = null), e)
          : (N(e, n), (e = he(e, t[4])), e);
      },
    },
    {
      reg: /^([a-z]+) ([0-9]{1,2})( [0-9]{4})?( ([0-9:]+( ?am| ?pm| ?gmt)?))?$/i,
      parse: (e, t) => {
        let n = {
          year: ct(t[3], e._today),
          month: Ct(t[1]),
          date: kn(t[2] || ""),
        };
        return de(n) === !1
          ? ((e.epoch = null), e)
          : (N(e, n), (e = he(e, t[4])), e);
      },
    },
    {
      reg: /^([a-z]+) ([0-9]{1,2}) ([0-9]{1,2}:[0-9]{2}:?[0-9]{0,2})( \+[0-9]{4})?( [0-9]{4})?$/i,
      parse: (e, t) => {
        let [, n, r, a, i, o] = t,
          s = { year: ct(o, e._today), month: Ct(n), date: kn(r || "") };
        return de(s) === !1
          ? ((e.epoch = null), e)
          : (N(e, s), (e = vc(e, i)), (e = he(e, a)), e);
      },
    },
  ],
  xk = [
    {
      reg: /^([0-9]{1,2})[-/]([a-z]+)[\-/]?([0-9]{4})?$/i,
      parse: (e, t) => {
        let n = {
          year: ct(t[3], e._today),
          month: Ct(t[2]),
          date: kn(t[1] || ""),
        };
        return de(n) === !1
          ? ((e.epoch = null), e)
          : (N(e, n), (e = he(e, t[4])), e);
      },
    },
    {
      reg: /^([0-9]{1,2})( [a-z]+)( [0-9]{4}| '[0-9]{2})? ?([0-9]{1,2}:[0-9]{2}:?[0-9]{0,2} ?(am|pm|gmt))?$/i,
      parse: (e, t) => {
        let n = { year: ct(t[3], e._today), month: Ct(t[2]), date: kn(t[1]) };
        return !n.month || de(n) === !1
          ? ((e.epoch = null), e)
          : (N(e, n), (e = he(e, t[4])), e);
      },
    },
    {
      reg: /^([0-9]{1,2})[. \-/]([a-z]+)[. \-/]([0-9]{4})?( [0-9]{1,2}(:[0-9]{0,2})?(:[0-9]{0,3})? ?(am|pm)?)?$/i,
      parse: (e, t) => {
        let n = { date: Number(t[1]), month: Ct(t[2]), year: Number(t[3]) };
        return de(n) === !1
          ? ((e.epoch = null), e)
          : (N(e, n), (e = e.startOf("day")), (e = he(e, t[4])), e);
      },
    },
  ],
  Ck = [
    {
      reg: /^([0-9]{4})[\-/]([0-9]{2})$/,
      parse: (e, t) => {
        let n = { year: t[1], month: parseInt(t[2], 10) - 1, date: 1 };
        return de(n) === !1
          ? ((e.epoch = null), e)
          : (N(e, n), (e = he(e, t[4])), e);
      },
    },
    {
      reg: /^([a-z]+) ([0-9]{4})$/i,
      parse: (e, t) => {
        let n = {
          year: ct(t[2], e._today),
          month: Ct(t[1]),
          date: e._today.date || 1,
        };
        return de(n) === !1
          ? ((e.epoch = null), e)
          : (N(e, n), (e = he(e, t[4])), e);
      },
    },
    {
      reg: /^(q[0-9])( of)?( [0-9]{4})?/i,
      parse: (e, t) => {
        let n = t[1] || "";
        e = e.quarter(n);
        let r = t[3] || "";
        return (r && ((r = r.trim()), (e = e.year(r))), e);
      },
    },
    {
      reg: /^(spring|summer|winter|fall|autumn)( of)?( [0-9]{4})?/i,
      parse: (e, t) => {
        let n = t[1] || "";
        e = e.season(n);
        let r = t[3] || "";
        return (r && ((r = r.trim()), (e = e.year(r))), e);
      },
    },
    {
      reg: /^[0-9,]+ ?b\.?c\.?$/i,
      parse: (e, t) => {
        let n = t[0] || "";
        n = n.replace(/^([0-9,]+) ?b\.?c\.?$/i, "-$1");
        let r = new Date(),
          a = {
            year: parseInt(n.trim(), 10),
            month: r.getMonth(),
            date: r.getDate(),
          };
        return de(a) === !1 ? ((e.epoch = null), e) : (N(e, a), (e = he(e)), e);
      },
    },
    {
      reg: /^[0-9,]+ ?(a\.?d\.?|c\.?e\.?)$/i,
      parse: (e, t) => {
        let n = t[0] || "";
        n = n.replace(/,/g, "");
        let r = new Date(),
          a = {
            year: parseInt(n.trim(), 10),
            month: r.getMonth(),
            date: r.getDate(),
          };
        return de(a) === !1 ? ((e.epoch = null), e) : (N(e, a), (e = he(e)), e);
      },
    },
    {
      reg: /^[0-9]{4}( ?a\.?d\.?)?$/i,
      parse: (e, t) => {
        let n = e._today;
        n.month && !n.date && (n.date = 1);
        let r = new Date(),
          a = {
            year: ct(t[0], n),
            month: n.month || r.getMonth(),
            date: n.date || r.getDate(),
          };
        return de(a) === !1 ? ((e.epoch = null), e) : (N(e, a), (e = he(e)), e);
      },
    },
  ],
  Oa = [].concat(Pk, Ak, xk, Ck),
  Dk = function (e, t, n) {
    for (let r = 0; r < Oa.length; r++) {
      let a = t.match(Oa[r].reg);
      if (a) {
        let i = Oa[r].parse(e, a, n);
        if (i !== null && i.isValid()) return i;
      }
    }
    return (
      e.silent === !1 &&
        console.warn("Warning: couldn't parse date-string: '" + t + "'"),
      (e.epoch = null),
      e
    );
  },
  { parseArray: $k, parseObject: jl, parseNumber: jk } = gk,
  Nl = { year: new Date().getFullYear(), month: 0, date: 1 },
  wc = (e, t) => {
    let n = e._today || Nl;
    if (typeof t == "number") return jk(e, t);
    if (
      ((e.epoch = Date.now()),
      e._today && wt(e._today) && Object.keys(e._today).length > 0)
    ) {
      let r = jl(e, n, Nl);
      r.isValid() && (e.epoch = r.epoch);
    }
    return t == null || t === ""
      ? e
      : yc(t) === !0
        ? ((e.epoch = t.getTime()), e)
        : ck(t) === !0
          ? ((e = $k(e, t, n)), e)
          : wt(t) === !0
            ? t.epoch
              ? ((e.epoch = t.epoch), (e.tz = t.tz), e)
              : ((e = jl(e, t, n)), e)
            : typeof t != "string"
              ? e
              : ((t = yk(t)),
                na.hasOwnProperty(t) === !0 ? ((e = na[t](e)), e) : Dk(e, t));
  };
let Ci = ["sun", "mon", "tue", "wed", "thu", "fri", "sat"],
  Di = [
    "sunday",
    "monday",
    "tuesday",
    "wednesday",
    "thursday",
    "friday",
    "saturday",
  ];
function Un() {
  return Ci;
}
function ra() {
  return Di;
}
function Nk(e) {
  ((Ci = e.short || Ci), (Di = e.long || Di));
}
const Tl = {
  mo: 1,
  tu: 2,
  we: 3,
  th: 4,
  fr: 5,
  sa: 6,
  su: 7,
  tues: 2,
  weds: 3,
  wedn: 3,
  thur: 4,
  thurs: 4,
};
let kc = !0;
function Tk() {
  return kc;
}
function Ok(e) {
  kc = e;
}
const Ol = (e) => {
    let t = e.timezone().current.offset;
    return t ? Vn(t, ":") : "Z";
  },
  st = (e) => (Tk() ? dk(e) : e),
  Ik = (e) => (e >= 0 ? w(e, 4) : ((e = Math.abs(e)), "-" + w(e, 4))),
  vn = {
    day: (e) => st(e.dayName()),
    "day-short": (e) => st(Un()[e.day()]),
    "day-number": (e) => e.day(),
    "day-ordinal": (e) => nt(e.day()),
    "day-pad": (e) => w(e.day()),
    date: (e) => e.date(),
    "date-ordinal": (e) => nt(e.date()),
    "date-pad": (e) => w(e.date()),
    month: (e) => st(e.monthName()),
    "month-short": (e) => st(On()[e.month()]),
    "month-number": (e) => e.month(),
    "month-ordinal": (e) => nt(e.month()),
    "month-pad": (e) => w(e.month()),
    "iso-month": (e) => w(e.month() + 1),
    year: (e) => {
      let t = e.year();
      return t > 0 ? t : ((t = Math.abs(t)), t + " BC");
    },
    "year-short": (e) => {
      let t = e.year();
      return t > 0
        ? `'${String(e.year()).substr(2, 4)}`
        : ((t = Math.abs(t)), t + " BC");
    },
    "iso-year": (e) => {
      let t = e.year(),
        n = t < 0,
        r = w(Math.abs(t), 4);
      return (n && ((r = w(r, 6)), (r = "-" + r)), r);
    },
    time: (e) => e.time(),
    "time-24": (e) => `${e.hour24()}:${w(e.minute())}`,
    hour: (e) => e.hour12(),
    "hour-pad": (e) => w(e.hour12()),
    "hour-24": (e) => e.hour24(),
    "hour-24-pad": (e) => w(e.hour24()),
    minute: (e) => e.minute(),
    "minute-pad": (e) => w(e.minute()),
    second: (e) => e.second(),
    "second-pad": (e) => w(e.second()),
    millisecond: (e) => e.millisecond(),
    "millisecond-pad": (e) => w(e.millisecond(), 3),
    ampm: (e) => e.ampm(),
    AMPM: (e) => e.ampm().toUpperCase(),
    quarter: (e) => "Q" + e.quarter(),
    season: (e) => e.season(),
    era: (e) => e.era(),
    json: (e) => e.json(),
    timezone: (e) => e.timezone().name,
    offset: (e) => Ol(e),
    numeric: (e) => `${e.year()}/${w(e.month() + 1)}/${w(e.date())}`,
    "numeric-us": (e) => `${w(e.month() + 1)}/${w(e.date())}/${e.year()}`,
    "numeric-uk": (e) => `${w(e.date())}/${w(e.month() + 1)}/${e.year()}`,
    "mm/dd": (e) => `${w(e.month() + 1)}/${w(e.date())}`,
    iso: (e) => {
      let t = e.format("iso-year"),
        n = w(e.month() + 1),
        r = w(e.date()),
        a = w(e.h24()),
        i = w(e.minute()),
        o = w(e.second()),
        s = w(e.millisecond(), 3),
        l = Ol(e);
      return `${t}-${n}-${r}T${a}:${i}:${o}.${s}${l}`;
    },
    "iso-short": (e) => {
      let t = w(e.month() + 1),
        n = w(e.date());
      return `${Ik(e.year())}-${t}-${n}`;
    },
    "iso-utc": (e) => new Date(e.epoch).toISOString(),
    nice: (e) => `${On()[e.month()]} ${nt(e.date())}, ${e.time()}`,
    "nice-24": (e) =>
      `${On()[e.month()]} ${nt(e.date())}, ${e.hour24()}:${w(e.minute())}`,
    "nice-year": (e) => `${On()[e.month()]} ${nt(e.date())}, ${e.year()}`,
    "nice-day": (e) =>
      `${Un()[e.day()]} ${st(On()[e.month()])} ${nt(e.date())}`,
    "nice-full": (e) =>
      `${e.dayName()} ${st(e.monthName())} ${nt(e.date())}, ${e.time()}`,
    "nice-full-24": (e) =>
      `${e.dayName()} ${st(e.monthName())} ${nt(e.date())}, ${e.hour24()}:${w(e.minute())}`,
  },
  Il = {
    "day-name": "day",
    "month-name": "month",
    "iso 8601": "iso",
    "time-h24": "time-24",
    "time-12": "time",
    "time-h12": "time",
    tz: "timezone",
    "day-num": "day-number",
    "month-num": "month-number",
    "month-iso": "iso-month",
    "year-iso": "iso-year",
    "nice-short": "nice",
    "nice-short-24": "nice-24",
    mdy: "numeric-us",
    dmy: "numeric-uk",
    ymd: "numeric",
    "yyyy/mm/dd": "numeric",
    "mm/dd/yyyy": "numeric-us",
    "dd/mm/yyyy": "numeric-us",
    "little-endian": "numeric-uk",
    "big-endian": "numeric",
    "day-nice": "nice-day",
  };
Object.keys(Il).forEach((e) => (vn[e] = vn[Il[e]]));
const Ia = (e, t = "") => {
    if (e.isValid() !== !0) return "";
    if (vn.hasOwnProperty(t)) {
      let n = vn[t](e) || "";
      return (
        t !== "json" &&
          ((n = String(n)), t.toLowerCase() !== "ampm" && (n = st(n))),
        n
      );
    }
    if (t.indexOf("{") !== -1) {
      let n = /\{(.+?)\}/g;
      return (
        (t = t.replace(n, (r, a) => {
          if (((a = a.toLowerCase().trim()), vn.hasOwnProperty(a))) {
            let i = String(vn[a](e));
            return a.toLowerCase() !== "ampm" ? st(i) : i;
          }
          return "";
        })),
        t
      );
    }
    return e.format("iso-short");
  },
  aa = {
    G: (e) => e.era(),
    GG: (e) => e.era(),
    GGG: (e) => e.era(),
    GGGG: (e) => (e.era() === "AD" ? "Anno Domini" : "Before Christ"),
    y: (e) => e.year(),
    yy: (e) => w(Number(String(e.year()).substr(2, 4))),
    yyy: (e) => e.year(),
    yyyy: (e) => e.year(),
    yyyyy: (e) => "0" + e.year(),
    Q: (e) => e.quarter(),
    QQ: (e) => e.quarter(),
    QQQ: (e) => e.quarter(),
    QQQQ: (e) => e.quarter(),
    M: (e) => e.month() + 1,
    MM: (e) => w(e.month() + 1),
    MMM: (e) => e.format("month-short"),
    MMMM: (e) => e.format("month"),
    w: (e) => e.week(),
    ww: (e) => w(e.week()),
    d: (e) => e.date(),
    dd: (e) => w(e.date()),
    D: (e) => e.dayOfYear(),
    DD: (e) => w(e.dayOfYear()),
    DDD: (e) => w(e.dayOfYear(), 3),
    E: (e) => e.format("day-short"),
    EE: (e) => e.format("day-short"),
    EEE: (e) => e.format("day-short"),
    EEEE: (e) => e.format("day"),
    EEEEE: (e) => e.format("day")[0],
    e: (e) => e.day(),
    ee: (e) => e.day(),
    eee: (e) => e.format("day-short"),
    eeee: (e) => e.format("day"),
    eeeee: (e) => e.format("day")[0],
    a: (e) => e.ampm().toUpperCase(),
    aa: (e) => e.ampm().toUpperCase(),
    aaa: (e) => e.ampm().toUpperCase(),
    aaaa: (e) => e.ampm().toUpperCase(),
    h: (e) => e.h12(),
    hh: (e) => w(e.h12()),
    H: (e) => e.hour(),
    HH: (e) => w(e.hour()),
    m: (e) => e.minute(),
    mm: (e) => w(e.minute()),
    s: (e) => e.second(),
    ss: (e) => w(e.second()),
    SSS: (e) => w(e.millisecond(), 3),
    A: (e) => e.epoch - e.startOf("day").epoch,
    z: (e) => e.timezone().name,
    zz: (e) => e.timezone().name,
    zzz: (e) => e.timezone().name,
    zzzz: (e) => e.timezone().name,
    Z: (e) => Vn(e.timezone().current.offset),
    ZZ: (e) => Vn(e.timezone().current.offset),
    ZZZ: (e) => Vn(e.timezone().current.offset),
    ZZZZ: (e) => Vn(e.timezone().current.offset, ":"),
  },
  dt = (e, t, n) => {
    let r = e,
      a = t;
    for (let i = 0; i < n; i += 1) ((aa[r] = aa[a]), (r += e), (a += t));
  };
dt("q", "Q", 4);
dt("L", "M", 4);
dt("Y", "y", 4);
dt("c", "e", 4);
dt("k", "H", 2);
dt("K", "h", 2);
dt("S", "s", 2);
dt("v", "z", 4);
dt("V", "Z", 4);
const Ek = function (e) {
    for (let t = 0; t < e.length; t += 1)
      if (e[t] === "'")
        for (let n = t + 1; n < e.length; n += 1) {
          if ((e[n] && (e[t] += e[n]), e[n] === "'")) {
            e[n] = null;
            break;
          }
          e[n] = null;
        }
    return e.filter((t) => t);
  },
  Hk = function (e) {
    for (let t = 0; t < e.length; t += 1) {
      let n = e[t];
      for (let r = t + 1; r < e.length && e[r] === n; r += 1)
        ((e[t] += e[r]), (e[r] = null));
    }
    return (
      (e = e.filter((t) => t)),
      (e = e.map((t) => (t === "''" && (t = "'"), t))),
      e
    );
  },
  zk = (e, t) => {
    let n = t.split("");
    return (
      (n = Ek(n)),
      (n = Hk(n)),
      n.reduce(
        (r, a) => (
          aa[a] !== void 0
            ? (r += aa[a](e) || "")
            : (/^'.+'$/.test(a) && (a = a.replace(/'/g, "")), (r += a)),
          r
        ),
        "",
      )
    );
  },
  Fk = [
    "year",
    "season",
    "quarter",
    "month",
    "week",
    "day",
    "quarterHour",
    "hour",
    "minute",
  ],
  El = function (e, t) {
    let n = e.clone().startOf(t),
      a = e.clone().endOf(t).epoch - n.epoch,
      i = (e.epoch - n.epoch) / a;
    return parseFloat(i.toFixed(2));
  },
  Vk = (e, t) => {
    if (t) return ((t = en(t)), El(e, t));
    let n = {};
    return (
      Fk.forEach((r) => {
        n[r] = El(e, r);
      }),
      n
    );
  },
  Gk = (e, t) => {
    let n = e.progress();
    return (
      (t = en(t)),
      t === "quarterhour" && (t = "quarterHour"),
      n[t] !== void 0
        ? (n[t] > 0.5 && (e = e.add(1, t)), (e = e.startOf(t)))
        : e.silent === !1 && console.warn("no known unit '" + t + "'"),
      e
    );
  },
  Hl = (e, t, n) => {
    let r = 0;
    for (e = e.clone(); e.isBefore(t);) ((e = e.add(1, n)), (r += 1));
    return (e.isAfter(t, n) && (r -= 1), r);
  },
  Ea = (e, t, n) => (e.isBefore(t) ? Hl(e, t, n) : Hl(t, e, n) * -1),
  Sk = (e, t) => {
    let n = t.year() - e.year();
    return ((e = e.year(t.year())), e.isAfter(t) && (n -= 1), n);
  },
  Mk = function (e, t) {
    let n = t.epoch - e.epoch,
      r = { milliseconds: n, seconds: parseInt(n / 1e3, 10) };
    ((r.minutes = parseInt(r.seconds / 60, 10)),
      (r.hours = parseInt(r.minutes / 60, 10)));
    let a = e.clone();
    return (
      (r.years = Sk(a, t)),
      (a = e.add(r.years, "year")),
      (r.months = r.years * 12),
      (a = e.add(r.months, "month")),
      (r.months += Ea(a, t, "month")),
      (r.quarters = r.years * 4),
      (r.quarters += parseInt((r.months % 12) / 3, 10)),
      (r.weeks = r.years * 52),
      (a = e.add(r.weeks, "week")),
      (r.weeks += Ea(a, t, "week")),
      (r.days = r.weeks * 7),
      (a = e.add(r.days, "day")),
      (r.days += Ea(a, t, "day")),
      r
    );
  },
  Bk = function (e) {
    return (
      Object.keys(e).forEach((t) => {
        e[t] *= -1;
      }),
      e
    );
  },
  Lk = function (e, t, n) {
    t = Bt(t, e);
    let r = !1;
    if (e.isAfter(t)) {
      let i = e;
      ((e = t), (t = i), (r = !0));
    }
    let a = Mk(e, t);
    return (
      r && (a = Bk(a)),
      n
        ? ((n = en(n)),
          /s$/.test(n) !== !0 && (n += "s"),
          n === "dates" && (n = "days"),
          a[n])
        : a
    );
  },
  un = (e) => Math.abs(e) || 0,
  Wk = function (e) {
    let t = "P";
    return (
      (t += un(e.years) + "Y"),
      (t += un(e.months) + "M"),
      (t += un(e.days) + "DT"),
      (t += un(e.hours) + "H"),
      (t += un(e.minutes) + "M"),
      (t += un(e.seconds) + "S"),
      t
    );
  };
function qk(e, t) {
  const n = e.isBefore(t),
    r = n ? t : e;
  let a = n ? e : t;
  a = a.clone();
  const i = { years: 0, months: 0, days: 0, hours: 0, minutes: 0, seconds: 0 };
  return (
    Object.keys(i).forEach((o) => {
      if (a.isSame(r, o)) return;
      let s = a.diff(r, o);
      ((a = a.add(s, o)), (i[o] = s));
    }),
    n &&
      Object.keys(i).forEach((o) => {
        i[o] !== 0 && (i[o] *= -1);
      }),
    i
  );
}
let ge = {
  second: "second",
  seconds: "seconds",
  minute: "minute",
  minutes: "minutes",
  hour: "hour",
  hours: "hours",
  day: "day",
  days: "days",
  month: "month",
  months: "months",
  year: "year",
  years: "years",
};
function zl(e) {
  return ge[e] || "";
}
function Kk(e = {}) {
  ge = {
    second: e.second || ge.second,
    seconds: e.seconds || ge.seconds,
    minute: e.minute || ge.minute,
    minutes: e.minutes || ge.minutes,
    hour: e.hour || ge.hour,
    hours: e.hours || ge.hours,
    day: e.day || ge.day,
    days: e.days || ge.days,
    month: e.month || ge.month,
    months: e.months || ge.months,
    year: e.year || ge.year,
    years: e.years || ge.years,
  };
}
let $i = "past",
  ji = "future",
  Ni = "present",
  Ti = "now",
  Oi = "almost",
  Ii = "over",
  Ei = (e) => `${e} ago`,
  Hi = (e) => `in ${e}`;
function Ha(e) {
  return Ei(e);
}
function za(e) {
  return Hi(e);
}
function Jk() {
  return $i;
}
function _k() {
  return ji;
}
function Uk() {
  return Ni;
}
function Fa() {
  return Ti;
}
function Rk() {
  return Oi;
}
function Yk() {
  return Ii;
}
function Qk(e) {
  ((Ei = e.pastDistance || Ei),
    (Hi = e.futureDistance || Hi),
    ($i = e.past || $i),
    (ji = e.future || ji),
    (Ni = e.present || Ni),
    (Ti = e.now || Ti),
    (Oi = e.almost || Oi),
    (Ii = e.over || Ii));
}
const Fl = {
  months: { almost: 10, over: 4 },
  days: { almost: 25, over: 10 },
  hours: { almost: 20, over: 8 },
  minutes: { almost: 50, over: 20 },
  seconds: { almost: 50, over: 20 },
};
function Vl(e, t) {
  return e === 1 ? e + " " + zl(t.slice(0, -1)) : e + " " + zl(t);
}
const Zk = function (e) {
    let t = null,
      n = null,
      r = [],
      a = [];
    return (
      Object.keys(e).forEach((i, o, s) => {
        const l = Math.abs(e[i]);
        if (l === 0) return;
        r.push(l + i[0]);
        const u = Vl(l, i);
        if ((a.push(u), !t)) {
          if (((t = u), (n = u), o > 4)) return;
          const c = s[o + 1],
            h = Math.abs(e[c]);
          h > Fl[c].almost
            ? ((t = Vl(l + 1, i)), (n = Rk() + " " + t))
            : h > Fl[c].over && (n = Yk() + " " + u);
        }
      }),
      { qualified: n, rounded: t, abbreviated: r, englishValues: a }
    );
  },
  Xk = (e, t) => {
    t = Bt(t, e);
    const n = qk(e, t);
    if (Object.keys(n).every((h) => !n[h]) === !0)
      return {
        diff: n,
        rounded: Fa(),
        qualified: Fa(),
        precise: Fa(),
        abbreviated: [],
        iso: "P0Y0M0DT0H0M0S",
        direction: Uk(),
      };
    let a,
      i = _k(),
      { rounded: o, qualified: s, englishValues: l, abbreviated: u } = Zk(n);
    ((a = l.splice(0, 2).join(", ")),
      e.isAfter(t) === !0
        ? ((o = Ha(o)), (s = Ha(s)), (a = Ha(a)), (i = Jk()))
        : ((o = za(o)), (s = za(s)), (a = za(a))));
    let c = Wk(n);
    return {
      diff: n,
      rounded: o,
      qualified: s,
      precise: a,
      abbreviated: u,
      iso: c,
      direction: i,
    };
  },
  e3 = [
    ["spring", 2, 1],
    ["summer", 5, 1],
    ["fall", 8, 1],
    ["autumn", 8, 1],
    ["winter", 11, 1],
  ],
  t3 = [
    ["fall", 2, 1],
    ["autumn", 2, 1],
    ["winter", 5, 1],
    ["spring", 8, 1],
    ["summer", 11, 1],
  ],
  Be = { north: e3, south: t3 },
  Kt = [null, [0, 1], [3, 1], [6, 1], [9, 1]],
  _t = {
    second: (e) => (N(e, { millisecond: 0 }), e),
    minute: (e) => (N(e, { second: 0, millisecond: 0 }), e),
    quarterhour: (e) => {
      let t = e.minutes();
      return (
        t >= 45
          ? (e = e.minutes(45))
          : t >= 30
            ? (e = e.minutes(30))
            : t >= 15
              ? (e = e.minutes(15))
              : (e = e.minutes(0)),
        N(e, { second: 0, millisecond: 0 }),
        e
      );
    },
    hour: (e) => (N(e, { minute: 0, second: 0, millisecond: 0 }), e),
    day: (e) => (N(e, { hour: 0, minute: 0, second: 0, millisecond: 0 }), e),
    week: (e) => {
      let t = e.clone();
      return (
        (e = e.day(e._weekStart)),
        e.isAfter(t) && (e = e.subtract(1, "week")),
        N(e, { hour: 0, minute: 0, second: 0, millisecond: 0 }),
        e
      );
    },
    month: (e) => (
      N(e, { date: 1, hour: 0, minute: 0, second: 0, millisecond: 0 }),
      e
    ),
    quarter: (e) => {
      let t = e.quarter();
      return (
        Kt[t] &&
          N(e, {
            month: Kt[t][0],
            date: Kt[t][1],
            hour: 0,
            minute: 0,
            second: 0,
            millisecond: 0,
          }),
        e
      );
    },
    season: (e) => {
      let t = e.season(),
        n = "north";
      e.hemisphere() === "South" && (n = "south");
      for (let r = 0; r < Be[n].length; r++)
        if (Be[n][r][0] === t) {
          let a = e.year();
          return (
            t === "winter" && e.month() < 3 && (a -= 1),
            N(e, {
              year: a,
              month: Be[n][r][1],
              date: Be[n][r][2],
              hour: 0,
              minute: 0,
              second: 0,
              millisecond: 0,
            }),
            e
          );
        }
      return e;
    },
    year: (e) => (
      N(e, {
        month: 0,
        date: 1,
        hour: 0,
        minute: 0,
        second: 0,
        millisecond: 0,
      }),
      e
    ),
    decade: (e) => {
      e = e.startOf("year");
      let t = e.year(),
        n = parseInt(t / 10, 10) * 10;
      return ((e = e.year(n)), e);
    },
    century: (e) => {
      e = e.startOf("year");
      let t = e.year(),
        n = parseInt(t / 100, 10) * 100;
      return ((e = e.year(n)), e);
    },
  };
_t.date = _t.day;
const n3 = (e, t) => {
    let n = e.clone();
    return (
      (t = en(t)),
      _t[t]
        ? _t[t](n)
        : t === "summer" || t === "winter"
          ? ((n = n.season(t)), _t.season(n))
          : n
    );
  },
  r3 = (e, t) => {
    let n = e.clone();
    return (
      (t = en(t)),
      _t[t] &&
        ((n = _t[t](n)), (n = n.add(1, t)), (n = n.subtract(1, "millisecond"))),
      n
    );
  },
  a3 = function (e) {
    return !!(Un().find((t) => t === e) || ra().find((t) => t === e));
  },
  i3 = function (e, t, n, r = 1) {
    if (!t || !n) return [];
    if (((t = en(t)), (n = e.clone().set(n)), e.isAfter(n))) {
      let o = e;
      ((e = n), (n = o));
    }
    if (e.diff(n, t) < r) return [];
    let a = e.clone();
    a3(t)
      ? ((a = a.next(t)), (t = "week"))
      : a.startOf(t).isBefore(e) && (a = a.next(t));
    let i = [];
    for (; a.isBefore(n);) (i.push(a), (a = a.add(r, t)));
    return i;
  },
  o3 = (e) => (e ? e.split("->") : []),
  s3 = (e) => (
    (e = e[0].toUpperCase() + e.substr(1)),
    (e = e.replace(/[/_-]([a-z])/gi, (t) => t.toUpperCase())),
    (e = e.replace(/_(of|es)_/i, (t) => t.toLowerCase())),
    (e = e.replace(/\/gmt/i, "/GMT")),
    (e = e.replace(/\/Dumontdurville$/i, "/DumontDUrville")),
    (e = e.replace(/\/Mcmurdo$/i, "/McMurdo")),
    (e = e.replace(/\/Port-au-prince$/i, "/Port-au-Prince")),
    e
  ),
  In = (e) => {
    let t = e.timezones,
      n = e.tz;
    if ((t.hasOwnProperty(n) === !1 && (n = ta(e.tz, t)), n === null))
      return (
        e.silent === !1 &&
          console.warn(
            "Warn: could not find given or local timezone - '" + e.tz + "'",
          ),
        { current: { epochShift: 0 } }
      );
    let r = t[n],
      a = {
        name: s3(n),
        hasDst: !!r.dst,
        default_offset: r.offset,
        hemisphere: r.hem === "s" ? "South" : "North",
        current: {},
      };
    if (a.hasDst) {
      let s = o3(r.dst);
      a.change = { start: s[0], back: s[1] };
    }
    let i = r.offset,
      o = i;
    return (
      a.hasDst === !0 &&
        (a.hemisphere === "North" ? (o = i - 1) : (o = r.offset + 1)),
      a.hasDst === !1
        ? ((a.current.offset = i), (a.current.isDST = !1))
        : gc(e.epoch, a.change.start, a.change.back, i, o) === !0
          ? ((a.current.offset = i),
            (a.current.isDST = a.hemisphere === "North"))
          : ((a.current.offset = o),
            (a.current.isDST = a.hemisphere === "South")),
      a
    );
  },
  l3 = [
    "century",
    "decade",
    "year",
    "month",
    "date",
    "day",
    "hour",
    "minute",
    "second",
    "millisecond",
  ],
  $t = {
    set: function (e, t) {
      let n = this.clone();
      return ((n = wc(n, e)), t && (this.tz = ta(t)), n);
    },
    timezone: function () {
      return In(this);
    },
    isDST: function () {
      return In(this).current.isDST;
    },
    hasDST: function () {
      return In(this).hasDst;
    },
    offset: function () {
      return In(this).current.offset * 60;
    },
    hemisphere: function () {
      return In(this).hemisphere;
    },
    format: function (e) {
      return Ia(this, e);
    },
    unixFmt: function (e) {
      return zk(this, e);
    },
    startOf: function (e) {
      return n3(this, e);
    },
    endOf: function (e) {
      return r3(this, e);
    },
    leapYear: function () {
      let e = this.year();
      return tr(e);
    },
    progress: function (e) {
      return Vk(this, e);
    },
    nearest: function (e) {
      return Gk(this, e);
    },
    diff: function (e, t) {
      return Lk(this, e, t);
    },
    since: function (e) {
      return (e || (e = this.clone().set()), Xk(this, e));
    },
    next: function (e) {
      return this.add(1, e).startOf(e);
    },
    last: function (e) {
      return this.subtract(1, e).startOf(e);
    },
    isValid: function () {
      return !this.epoch && this.epoch !== 0 ? !1 : !isNaN(this.d.getTime());
    },
    goto: function (e) {
      let t = this.clone();
      return ((t.tz = ta(e, t.timezones)), t);
    },
    every: function (e, t, n) {
      if (typeof e == "object" && typeof t == "string") {
        let r = t;
        ((t = e), (e = r));
      }
      return i3(this, e, t, n);
    },
    isAwake: function () {
      let e = this.hour();
      return !(e < 8 || e > 22);
    },
    isAsleep: function () {
      return !this.isAwake();
    },
    daysInMonth: function () {
      switch (this.month()) {
        case 0:
          return 31;
        case 1:
          return this.leapYear() ? 29 : 28;
        case 2:
          return 31;
        case 3:
          return 30;
        case 4:
          return 31;
        case 5:
          return 30;
        case 6:
          return 31;
        case 7:
          return 31;
        case 8:
          return 30;
        case 9:
          return 31;
        case 10:
          return 30;
        case 11:
          return 31;
        default:
          throw new Error("Invalid Month state.");
      }
    },
    log: function () {
      return (console.log(""), console.log(Ia(this, "nice-short")), this);
    },
    logYear: function () {
      return (console.log(""), console.log(Ia(this, "full-short")), this);
    },
    json: function () {
      return l3.reduce((e, t) => ((e[t] = this[t]()), e), {});
    },
    debug: function () {
      let e = this.timezone(),
        t =
          this.format("MM") +
          " " +
          this.format("date-ordinal") +
          " " +
          this.year();
      return (
        (t +=
          `
     - ` + this.format("time")),
        console.log(
          `

`,
          t +
            `
     - ` +
            e.name +
            " (" +
            e.current.offset +
            ")",
        ),
        this
      );
    },
    from: function (e) {
      return ((e = this.clone().set(e)), e.since(this));
    },
    fromNow: function () {
      return this.clone().set(Date.now()).since(this);
    },
    weekStart: function (e) {
      if (typeof e == "number") return ((this._weekStart = e), this);
      if (typeof e == "string") {
        e = e.toLowerCase().trim();
        let t = Un().indexOf(e);
        (t === -1 && (t = ra().indexOf(e)),
          t === -1 && (t = 1),
          (this._weekStart = t));
      } else
        console.warn(
          "Spacetime Error: Cannot understand .weekStart() input:",
          e,
        );
      return this;
    },
  };
$t.inDST = $t.isDST;
$t.round = $t.nearest;
$t.each = $t.every;
const ft = (e) => (typeof e == "string" && (e = parseInt(e, 10)), e),
  Va = ["year", "month", "date", "hour", "minute", "second", "millisecond"],
  ao = (e, t, n) => {
    let r = Va.indexOf(n),
      a = Va.slice(r, Va.length);
    for (let i = 0; i < a.length; i++) {
      let o = t[a[i]]();
      e[a[i]](o);
    }
    return e;
  },
  Tt = function (e, t, n, r) {
    return (
      n === !0 && e.isBefore(t)
        ? (e = e.add(1, r))
        : n === !1 && e.isAfter(t) && (e = e.minus(1, r)),
      e
    );
  },
  u3 = function (e, t) {
    t = ft(t);
    let r = e.millisecond() - t;
    return e.epoch - r;
  },
  c3 = function (e, t, n) {
    t = ft(t);
    let r = e.clone(),
      i = (e.second() - t) * O.second;
    return ((e.epoch = e.epoch - i), (e = Tt(e, r, n, "minute")), e.epoch);
  },
  Gl = function (e, t, n) {
    t = ft(t);
    let r = e.clone(),
      i = (e.minute() - t) * O.minute;
    return (
      (e.epoch -= i),
      ao(e, r, "second"),
      (e = Tt(e, r, n, "hour")),
      e.epoch
    );
  },
  Ga = function (e, t, n) {
    ((t = ft(t)), t >= 24 ? (t = 24) : t < 0 && (t = 0));
    let r = e.clone(),
      a = e.hour() - t,
      i = a * O.hour;
    return (
      (e.epoch -= i),
      e.date() !== r.date() &&
        ((e = r.clone()),
        a > 1 && (a -= 1),
        a < 1 && (a += 1),
        (i = a * O.hour),
        (e.epoch -= i)),
      N(e, { hour: t }),
      ao(e, r, "minute"),
      (e = Tt(e, r, n, "day")),
      e.epoch
    );
  },
  h3 = function (e, t, n) {
    let r = t.match(/([0-9]{1,2})[:h]([0-9]{1,2})(:[0-9]{1,2})? ?(am|pm)?/);
    if (!r) {
      if (((r = t.match(/([0-9]{1,2}) ?(am|pm)/)), !r)) return e.epoch;
      (r.splice(2, 0, "0"), r.splice(3, 0, ""));
    }
    let a = !1,
      i = parseInt(r[1], 10),
      o = parseInt(r[2], 10);
    (o >= 60 && (o = 59),
      i > 12 && (a = !0),
      a === !1 &&
        (r[4] === "am" && i === 12 && (i = 0),
        r[4] === "pm" && i < 12 && (i += 12)),
      (r[3] = r[3] || ""),
      (r[3] = r[3].replace(/:/, "")));
    let s = parseInt(r[3], 10) || 0,
      l = e.clone();
    return (
      (e = e.hour(i)),
      (e = e.minute(o)),
      (e = e.second(s)),
      (e = e.millisecond(0)),
      (e = Tt(e, l, n, "day")),
      e.epoch
    );
  },
  d3 = function (e, t, n) {
    if (((t = ft(t)), t > 28)) {
      let a = e.month(),
        i = Rt[a];
      (a === 1 && t === 29 && tr(e.year()) && (i = 29), t > i && (t = i));
    }
    t <= 0 && (t = 1);
    let r = e.clone();
    return (N(e, { date: t }), (e = Tt(e, r, n, "month")), e.epoch);
  },
  f3 = function (e, t, n) {
    (typeof t == "string" &&
      (t === "sept" && (t = "sep"), (t = bc()[t.toLowerCase()])),
      (t = ft(t)),
      t >= 12 && (t = 11),
      t <= 0 && (t = 0));
    let r = e.date();
    r > Rt[t] && (r = Rt[t]);
    let a = e.clone();
    return (N(e, { month: t, d: r }), (e = Tt(e, a, n, "year")), e.epoch);
  },
  Sa = function (e, t) {
    return (
      typeof t == "string" &&
        /^'[0-9]{2}$/.test(t) &&
        ((t = t.replace(/'/, "").trim()),
        (t = Number(t)),
        t > 30 ? (t = 1900 + t) : (t = 2e3 + t)),
      (t = ft(t)),
      N(e, { year: t }),
      e.epoch
    );
  },
  m3 = function (e, t, n) {
    let r = e.clone();
    return (
      (t = ft(t)),
      (e = e.month(0)),
      (e = e.date(1)),
      (e = e.day("monday")),
      e.monthName() === "december" && e.date() >= 28 && (e = e.add(1, "week")),
      (t -= 1),
      (e = e.add(t, "weeks")),
      (e = Tt(e, r, n, "year")),
      e.epoch
    );
  },
  p3 = function (e, t, n) {
    t = ft(t);
    let r = e.clone();
    return (
      (t -= 1),
      t <= 0 ? (t = 0) : t >= 365 && (tr(e.year()) ? (t = 365) : (t = 364)),
      (e = e.startOf("year")),
      (e = e.add(t, "day")),
      ao(e, r, "hour"),
      (e = Tt(e, r, n, "year")),
      e.epoch
    );
  };
let zi = "am",
  Fi = "pm";
function g3() {
  return zi;
}
function y3() {
  return Fi;
}
function b3(e) {
  ((zi = e.am || zi), (Fi = e.pm || Fi));
}
const v3 = {
    millisecond: function (e) {
      if (e !== void 0) {
        let t = this.clone();
        return ((t.epoch = u3(t, e)), t);
      }
      return this.d.getMilliseconds();
    },
    second: function (e, t) {
      if (e !== void 0) {
        let n = this.clone();
        return ((n.epoch = c3(n, e, t)), n);
      }
      return this.d.getSeconds();
    },
    minute: function (e, t) {
      if (e !== void 0) {
        let n = this.clone();
        return ((n.epoch = Gl(n, e, t)), n);
      }
      return this.d.getMinutes();
    },
    hour: function (e, t) {
      let n = this.d;
      if (e !== void 0) {
        let r = this.clone();
        return ((r.epoch = Ga(r, e, t)), r);
      }
      return n.getHours();
    },
    hourFloat: function (e, t) {
      if (e !== void 0) {
        let i = this.clone(),
          o = e % 1;
        o = o * 60;
        let s = parseInt(e, 10);
        return ((i.epoch = Ga(i, s, t)), (i.epoch = Gl(i, o, t)), i);
      }
      let n = this.d,
        r = n.getHours(),
        a = n.getMinutes();
      return ((a = a / 60), r + a);
    },
    hour12: function (e, t) {
      let n = this.d;
      if (e !== void 0) {
        let a = this.clone();
        e = "" + e;
        let i = e.match(/^([0-9]+)(am|pm)$/);
        if (i) {
          let o = parseInt(i[1], 10);
          (i[2] === "pm" && (o += 12), (a.epoch = Ga(a, o, t)));
        }
        return a;
      }
      let r = n.getHours();
      return (r > 12 && (r = r - 12), r === 0 && (r = 12), r);
    },
    time: function (e, t) {
      if (e !== void 0) {
        let n = this.clone();
        return ((e = e.toLowerCase().trim()), (n.epoch = h3(n, e, t)), n);
      }
      return `${this.h12()}:${w(this.minute())}${this.ampm()}`;
    },
    ampm: function (e, t) {
      let n = g3(),
        r = this.hour();
      if ((r >= 12 && (n = y3()), typeof e != "string")) return n;
      let a = this.clone();
      return (
        (e = e.toLowerCase().trim()),
        r >= 12 && e === "am"
          ? ((r -= 12), a.hour(r, t))
          : r < 12 && e === "pm"
            ? ((r += 12), a.hour(r, t))
            : a
      );
    },
    dayTime: function (e, t) {
      if (e !== void 0) {
        const r = {
          morning: "7:00",
          breakfast: "7:00",
          noon: "12:00",
          lunch: "12:00",
          afternoon: "14:00",
          evening: "18:00",
          dinner: "18:00",
          night: "23:00",
          midnight: "00:00",
        };
        let a = this.clone();
        return (
          (e = e || ""),
          (e = e.toLowerCase()),
          r.hasOwnProperty(e) === !0 && (a = a.time(r[e], t)),
          a
        );
      }
      let n = this.hour();
      return n < 6
        ? "night"
        : n < 12
          ? "morning"
          : n < 17
            ? "afternoon"
            : n < 22
              ? "evening"
              : "night";
    },
    iso: function (e) {
      return e !== void 0 ? this.set(e) : this.format("iso");
    },
  },
  w3 = {
    date: function (e, t) {
      if (e !== void 0) {
        let n = this.clone();
        return ((e = parseInt(e, 10)), e && (n.epoch = d3(n, e, t)), n);
      }
      return this.d.getDate();
    },
    day: function (e, t) {
      if (e === void 0) return this.d.getDay();
      let n = this.clone(),
        r = e;
      typeof e == "string" &&
        ((e = e.toLowerCase()),
        Tl.hasOwnProperty(e)
          ? (r = Tl[e])
          : ((r = Un().indexOf(e)), r === -1 && (r = ra().indexOf(e))));
      let i = this.d.getDay() - r;
      (t === !0 && i > 0 && (i = i - 7), t === !1 && i < 0 && (i = i + 7));
      let o = this.subtract(i, "days");
      return (
        N(o, { hour: n.hour(), minute: n.minute(), second: n.second() }),
        o
      );
    },
    dayName: function (e, t) {
      if (e === void 0) return ra()[this.day()];
      let n = this.clone();
      return ((n = n.day(e, t)), n);
    },
  },
  Sl = (e) => ((e = e.minute(0)), (e = e.second(0)), (e = e.millisecond(1)), e),
  k3 = {
    dayOfYear: function (e, t) {
      if (e !== void 0) {
        let i = this.clone();
        return ((i.epoch = p3(i, e, t)), i);
      }
      let n = 0,
        r = this.d.getMonth(),
        a;
      for (let i = 1; i <= r; i++)
        ((a = new Date()),
          a.setDate(1),
          a.setFullYear(this.d.getFullYear()),
          a.setHours(1),
          a.setMinutes(1),
          a.setMonth(i),
          a.setHours(-2),
          (n += a.getDate()));
      return n + this.d.getDate();
    },
    week: function (e, t) {
      if (e !== void 0) {
        let s = this.clone();
        return ((s.epoch = m3(this, e, t)), (s = Sl(s)), s);
      }
      let n = this.clone();
      ((n = n.month(0)),
        (n = n.date(1)),
        (n = Sl(n)),
        (n = n.day("monday")),
        n.month() === 11 && n.date() >= 25 && (n = n.add(1, "week")));
      let r = 1;
      (n.date() === 1 && (r = 0), (n = n.minus(1, "second")));
      const a = this.epoch;
      if (n.epoch > a) return 1;
      let i = 0,
        o = this.month() * 4;
      for (n.epoch += O.week * o, i += o; i <= 52; i++) {
        if (n.epoch > a) return i + r;
        n = n.add(1, "week");
      }
      return 52;
    },
    month: function (e, t) {
      if (e !== void 0) {
        let n = this.clone();
        return ((n.epoch = f3(n, e, t)), n);
      }
      return this.d.getMonth();
    },
    monthName: function (e, t) {
      if (e !== void 0) {
        let n = this.clone();
        return ((n = n.month(e, t)), n);
      }
      return vk()[this.month()];
    },
    quarter: function (e, t) {
      if (
        e !== void 0 &&
        (typeof e == "string" &&
          ((e = e.replace(/^q/i, "")), (e = parseInt(e, 10))),
        Kt[e])
      ) {
        let r = this.clone(),
          a = Kt[e][0];
        return (
          (r = r.month(a, t)),
          (r = r.date(1, t)),
          (r = r.startOf("day")),
          r
        );
      }
      let n = this.d.getMonth();
      for (let r = 1; r < Kt.length; r++) if (n < Kt[r][0]) return r - 1;
      return 4;
    },
    season: function (e, t) {
      let n = "north";
      if ((this.hemisphere() === "South" && (n = "south"), e !== void 0)) {
        let a = this.clone();
        for (let i = 0; i < Be[n].length; i++)
          e === Be[n][i][0] &&
            ((a = a.month(Be[n][i][1], t)),
            (a = a.date(1)),
            (a = a.startOf("day")));
        return a;
      }
      let r = this.d.getMonth();
      for (let a = 0; a < Be[n].length - 1; a++)
        if (r >= Be[n][a][1] && r < Be[n][a + 1][1]) return Be[n][a][0];
      return n === "north" ? "winter" : "summer";
    },
    year: function (e) {
      if (e !== void 0) {
        let t = this.clone();
        return ((t.epoch = Sa(t, e)), t);
      }
      return this.d.getFullYear();
    },
    era: function (e) {
      if (e !== void 0) {
        let t = this.clone();
        e = e.toLowerCase();
        let n = t.d.getFullYear();
        return (
          e === "bc" && n > 0 && (t.epoch = Sa(t, n * -1)),
          e === "ad" && n < 0 && (t.epoch = Sa(t, n * -1)),
          t
        );
      }
      return this.d.getFullYear() < 0 ? "BC" : "AD";
    },
    decade: function (e) {
      if (e !== void 0) {
        if (
          ((e = String(e)),
          (e = e.replace(/([0-9])'?s$/, "$1")),
          (e = e.replace(/([0-9])(th|rd|st|nd)/, "$1")),
          !e)
        )
          return (console.warn("Spacetime: Invalid decade input"), this);
        e.length === 2 && /[0-9][0-9]/.test(e) && (e = "19" + e);
        let t = Number(e);
        return isNaN(t) ? this : ((t = Math.floor(t / 10) * 10), this.year(t));
      }
      return this.startOf("decade").year();
    },
    century: function (e) {
      if (e !== void 0) {
        typeof e == "string" &&
          ((e = e.replace(/([0-9])(th|rd|st|nd)/, "$1")),
          (e = e.replace(
            /([0-9]+) ?(b\.?c\.?|a\.?d\.?)/i,
            (r, a, i) => (i.match(/b\.?c\.?/i) && (a = "-" + a), a),
          )),
          (e = e.replace(/c$/, "")));
        let n = Number(e);
        return isNaN(e)
          ? (console.warn("Spacetime: Invalid century input"), this)
          : (n === 0 && (n = 1),
            n >= 0 ? (n = (n - 1) * 100) : (n = (n + 1) * 100),
            this.year(n));
      }
      let t = this.startOf("century").year();
      return ((t = Math.floor(t / 100)), t < 0 ? t - 1 : t + 1);
    },
    millenium: function (e) {
      if (e !== void 0) {
        if (
          typeof e == "string" &&
          ((e = e.replace(/([0-9])(th|rd|st|nd)/, "$1")),
          (e = Number(e)),
          isNaN(e))
        )
          return (console.warn("Spacetime: Invalid millenium input"), this);
        e > 0 && (e -= 1);
        let n = e * 1e3;
        return (n === 0 && (n = 1), this.year(n));
      }
      let t = Math.floor(this.year() / 1e3);
      return (t >= 0 && (t += 1), t);
    },
  },
  ne = Object.assign({}, v3, w3, k3);
ne.milliseconds = ne.millisecond;
ne.seconds = ne.second;
ne.minutes = ne.minute;
ne.hours = ne.hour;
ne.hour24 = ne.hour;
ne.h12 = ne.hour12;
ne.h24 = ne.hour24;
ne.days = ne.day;
const P3 = (e) => {
    Object.keys(ne).forEach((t) => {
      e.prototype[t] = ne[t];
    });
  },
  Vi = function (e, t) {
    return e === 1 && tr(t) ? 29 : Rt[e];
  },
  A3 = (e, t) => {
    if (e.month > 0) {
      let n = parseInt(e.month / 12, 10);
      ((e.year = t.year() + n), (e.month = e.month % 12));
    } else if (e.month < 0) {
      let n = Math.abs(e.month),
        r = parseInt(n / 12, 10);
      (n % 12 !== 0 && (r += 1),
        (e.year = t.year() - r),
        (e.month = e.month % 12),
        (e.month = e.month + 12),
        e.month === 12 && (e.month = 0));
    }
    return e;
  },
  x3 = (e, t, n) => {
    ((e.year = t.year()), (e.month = t.month()));
    let r = t.date();
    for (e.date = r - Math.abs(n); e.date < 1;) {
      ((e.month -= 1), e.month < 0 && ((e.month = 11), (e.year -= 1)));
      let a = Vi(e.month, e.year);
      e.date += a;
    }
    return e;
  },
  C3 = (e, t, n) => {
    let r = t.year(),
      a = t.month(),
      i = Vi(a, r);
    for (; n > i;)
      ((n -= i), (a += 1), a >= 12 && ((a -= 12), (r += 1)), (i = Vi(a, r)));
    return ((e.month = a), (e.date = n), e);
  },
  D3 = A3,
  $3 = C3,
  j3 = x3,
  Fe = ["millisecond", "second", "minute", "hour", "date", "month"];
let jt = {
  second: Fe.slice(0, 1),
  minute: Fe.slice(0, 2),
  quarterhour: Fe.slice(0, 2),
  hour: Fe.slice(0, 3),
  date: Fe.slice(0, 4),
  month: Fe.slice(0, 4),
  quarter: Fe.slice(0, 4),
  season: Fe.slice(0, 4),
  year: Fe,
  decade: Fe,
  century: Fe,
};
jt.week = jt.hour;
jt.season = jt.date;
jt.quarter = jt.date;
const N3 = { year: !0, quarter: !0, season: !0, month: !0, week: !0, date: !0 },
  T3 = { month: !0, quarter: !0, season: !0, year: !0 },
  O3 = (e) => {
    ((e.prototype.add = function (t, n) {
      let r = this.clone();
      if (!n || t === 0) return r;
      let a = this.clone();
      if (((n = en(n)), n === "millisecond")) return ((r.epoch += t), r);
      (n === "fortnight" && ((t *= 2), (n = "week")),
        O[n]
          ? (r.epoch += O[n] * t)
          : n === "week" || n === "weekend"
            ? (r.epoch += O.day * (t * 7))
            : n === "quarter" || n === "season"
              ? (r.epoch += O.month * (t * 3))
              : n === "quarterhour" && (r.epoch += O.minute * 15 * t));
      let i = {};
      if (
        (jt[n] &&
          jt[n].forEach((o) => {
            i[o] = a[o]();
          }),
        N3[n])
      ) {
        const o = a.timezone().current.offset - r.timezone().current.offset;
        r.epoch += o * 3600 * 1e3;
      }
      if (
        (n === "month" && ((i.month = a.month() + t), (i = D3(i, a))),
        n === "week")
      ) {
        let o = a.date() + t * 7;
        o <= 28 && o > 1 && (i.date = o);
      }
      if (n === "weekend" && r.dayName() !== "saturday")
        r = r.day("saturday", !0);
      else if (n === "date") {
        if (t < 0) i = j3(i, a, t);
        else {
          let o = a.date() + t;
          i = $3(i, a, o);
        }
        t !== 0 && a.isSame(r, "day") && (i.date = a.date() + t);
      } else if (n === "quarter") {
        if (((i.month = a.month() + t * 3), (i.year = a.year()), i.month < 0)) {
          let o = Math.floor(i.month / 12),
            s = i.month + Math.abs(o) * 12;
          ((i.month = s), (i.year += o));
        } else if (i.month >= 12) {
          let o = Math.floor(i.month / 12);
          ((i.month = i.month % 12), (i.year += o));
        }
        i.date = a.date();
      } else if (n === "year") {
        let o = a.year() + t,
          s = r.year();
        if (s < o) {
          let l = Math.floor(t / 4) || 1;
          r.epoch += Math.abs(O.day * l);
        } else if (s > o) {
          let l = Math.floor(t / 4) || 1;
          r.epoch += O.day * l;
        }
      } else
        n === "decade"
          ? (i.year = r.year() + 10)
          : n === "century" && (i.year = r.year() + 100);
      if (T3[n]) {
        let o = Rt[i.month];
        ((i.date = a.date()), i.date > o && (i.date = o));
      }
      return (Object.keys(i).length > 1 && N(r, i), r);
    }),
      (e.prototype.subtract = function (t, n) {
        return this.clone().add(t * -1, n);
      }),
      (e.prototype.minus = e.prototype.subtract),
      (e.prototype.plus = e.prototype.add));
  },
  Mn = {
    millisecond: (e) => e.epoch,
    second: (e) =>
      [e.year(), e.month(), e.date(), e.hour(), e.minute(), e.second()].join(
        "-",
      ),
    minute: (e) =>
      [e.year(), e.month(), e.date(), e.hour(), e.minute()].join("-"),
    hour: (e) => [e.year(), e.month(), e.date(), e.hour()].join("-"),
    day: (e) => [e.year(), e.month(), e.date()].join("-"),
    week: (e) => [e.year(), e.week()].join("-"),
    month: (e) => [e.year(), e.month()].join("-"),
    quarter: (e) => [e.year(), e.quarter()].join("-"),
    year: (e) => e.year(),
  };
Mn.date = Mn.day;
const I3 = (e) => {
    e.prototype.isSame = function (t, n, r = !0) {
      let a = this;
      if (!n) return null;
      if (typeof t == "string" && typeof n == "object") {
        let i = t;
        ((t = n), (n = i));
      }
      return (
        (typeof t == "string" || typeof t == "number") &&
          (t = new e(t, this.timezone.name)),
        (n = n.replace(/s$/, "")),
        r === !0 && a.tz !== t.tz && ((t = t.clone()), (t.tz = a.tz)),
        Mn[n] ? Mn[n](a) === Mn[n](t) : null
      );
    };
  },
  E3 = (e) => {
    const t = {
      isAfter: function (n) {
        n = Bt(n, this);
        let r = Tn(n);
        return r === null ? null : this.epoch > r;
      },
      isBefore: function (n) {
        n = Bt(n, this);
        let r = Tn(n);
        return r === null ? null : this.epoch < r;
      },
      isEqual: function (n) {
        n = Bt(n, this);
        let r = Tn(n);
        return r === null ? null : this.epoch === r;
      },
      isBetween: function (n, r, a = !1) {
        ((n = Bt(n, this)), (r = Bt(r, this)));
        let i = Tn(n);
        if (i === null) return null;
        let o = Tn(r);
        return o === null
          ? null
          : a
            ? this.isBetween(n, r) || this.isEqual(n) || this.isEqual(r)
            : i < this.epoch && this.epoch < o;
      },
    };
    Object.keys(t).forEach((n) => {
      e.prototype[n] = t[n];
    });
  },
  H3 = (e) => {
    const t = {
      i18n: function (n) {
        return (
          wt(n.days) && Nk(n.days),
          wt(n.months) && wk(n.months),
          hk(n.useTitleCase) && Ok(n.useTitleCase),
          wt(n.ampm) && b3(n.ampm),
          wt(n.distance) && Qk(n.distance),
          wt(n.units) && Kk(n.units),
          this
        );
      },
    };
    Object.keys(t).forEach((n) => {
      e.prototype[n] = t[n];
    });
  };
let Ma = An;
const J = function (e, t, n = {}) {
  ((this.epoch = null),
    (this.tz = ta(t, Ma)),
    (this.silent = typeof n.silent < "u" ? n.silent : !0),
    (this.british = n.dmy || n.british),
    (this._weekStart = 1),
    n.weekStart !== void 0 && (this._weekStart = n.weekStart),
    (this._today = {}),
    n.today !== void 0 && (this._today = n.today),
    Object.defineProperty(this, "d", {
      get: function () {
        let a = X2(this),
          o = (new Date(this.epoch).getTimezoneOffset() || 0) + a * 60;
        o = o * 60 * 1e3;
        let s = this.epoch + o;
        return new Date(s);
      },
    }),
    Object.defineProperty(this, "timezones", {
      get: () => Ma,
      set: (a) => ((Ma = a), a),
    }));
  let r = wc(this, e);
  ((this.epoch = r.epoch), r.tz && (this.tz = r.tz));
};
Object.keys($t).forEach((e) => {
  J.prototype[e] = $t[e];
});
J.prototype.clone = function () {
  return new J(this.epoch, this.tz, {
    silent: this.silent,
    weekStart: this._weekStart,
    today: this._today,
    parsers: this.parsers,
  });
};
J.prototype.toLocalDate = function () {
  return this.toNativeDate();
};
J.prototype.toNativeDate = function () {
  return new Date(this.epoch);
};
P3(J);
O3(J);
I3(J);
E3(J);
H3(J);
const z3 = (e, t) => {
    let n = new J(null),
      r = new J(null);
    ((n = n.time(e)), t ? (r = r.time(t)) : (r = n.add(59, "minutes")));
    let a = n.hour(),
      i = r.hour();
    return Object.keys(n.timezones).filter((s) => {
      if (s.indexOf("/") === -1) return !1;
      let l = new J(null, s),
        u = l.hour();
      return u >= a && u <= i
        ? !(
            (u === a && l.minute() < n.minute()) ||
            (u === i && l.minute() > r.minute())
          )
        : !1;
    });
  },
  F3 = "7.6.1",
  C = (e, t, n) => new J(e, t, n),
  la = function (e) {
    let t = e._today || {};
    return (
      Object.keys(t).forEach((n) => {
        e = e[n](t[n]);
      }),
      e
    );
  };
C.now = (e, t) => {
  let n = new J(new Date().getTime(), e, t);
  return ((n = la(n)), n);
};
C.today = (e, t) => {
  let n = new J(new Date().getTime(), e, t);
  return ((n = la(n)), n.startOf("day"));
};
C.tomorrow = (e, t) => {
  let n = new J(new Date().getTime(), e, t);
  return ((n = la(n)), n.add(1, "day").startOf("day"));
};
C.yesterday = (e, t) => {
  let n = new J(new Date().getTime(), e, t);
  return ((n = la(n)), n.subtract(1, "day").startOf("day"));
};
C.extend = function (e = {}) {
  return (
    Object.keys(e).forEach((t) => {
      J.prototype[t] = e[t];
    }),
    this
  );
};
C.timezones = function () {
  return new J().timezones;
};
C.max = function (e, t) {
  let n = new J(null, e, t);
  return ((n.epoch = 864e13), n);
};
C.min = function (e, t) {
  let n = new J(null, e, t);
  return ((n.epoch = -864e13), n);
};
C.whereIts = z3;
C.version = F3;
C.plugin = C.extend;
const Ml = {
    daybreak: "7:00am",
    breakfast: "8:00am",
    morning: "9:00am",
    noon: "12:00pm",
    midday: "12:00pm",
    afternoon: "2:00pm",
    lunchtime: "12:00pm",
    evening: "6:00pm",
    dinnertime: "6:00pm",
    night: "8:00pm",
    eod: "10:00pm",
    midnight: "12:00am",
    am: "9:00am",
    pm: "5:00pm",
    "early day": "8:00am",
    "late at night": "11:00pm",
  },
  wn = { quarter: 15, half: 30 },
  $r = function (e) {
    let t = e.time("6:00am");
    return e.isBefore(t) ? e.ampm("pm") : e;
  },
  V3 = function (e, t) {
    let n = e.match("#Cardinal$"),
      r = e.not(n).match("(half|quarter|25|20|15|10|5)");
    n = n.text("reduced");
    let a = r.text("reduced");
    wn.hasOwnProperty(a) && (a = wn[a]);
    let i = e.has("to");
    return (
      (t = t.hour(n)),
      (t = t.startOf("hour")),
      n < 6 && (t = t.ampm("pm")),
      i ? (t = t.subtract(a, "minutes")) : (t = t.add(a, "minutes")),
      t
    );
  },
  io = function (e, t) {
    let n = e.match("(at|by|for|before|this|after)? #Time+");
    ((n = n.not("^(at|by|for|before|this|after)")),
      (n = n.not("sharp")),
      (n = n.not("on the dot")));
    let r = C.now(t.timezone),
      a = r.clone(),
      i = n.not("in the").text("reduced");
    if (((i = i.replace(/^@/, "")), Ml.hasOwnProperty(i)))
      return { result: Ml[i], m: n };
    let o = n.match("^#Cardinal oclock (am|pm)?");
    if (
      o.found &&
      ((r = r.hour(o.text("reduced"))),
      (r = r.startOf("hour")),
      r.isValid() && !r.isEqual(a))
    ) {
      let l = o.match("(am|pm)");
      return (
        l.found ? (r = r.ampm(l.text("reduced"))) : (r = $r(r)),
        { result: r.time(), m: o }
      );
    }
    if (
      ((o = n.match("(half|quarter|25|20|15|10|5) (past|after|to) #Cardinal")),
      o.found && ((r = V3(o, r)), r.isValid() && !r.isEqual(a)))
    )
      return ((r = $r(r)), { result: r.time(), m: o });
    if (
      ((o = n.match("[<min>(half|quarter|25|20|15|10|5)] (past|after)")),
      o.found)
    ) {
      let l = o.groups("min").text("reduced"),
        u = C(t.today);
      if (
        (wn.hasOwnProperty(l) && (l = wn[l]),
        (u = u.next("hour").startOf("hour").minute(l)),
        u.isValid() && !u.isEqual(a))
      )
        return { result: u.time(), m: o };
    }
    if (((o = n.match("[<min>(half|quarter|25|20|15|10|5)] to")), o.found)) {
      let l = o.groups("min").text("reduced"),
        u = C(t.today);
      if (
        (wn.hasOwnProperty(l) && (l = wn[l]),
        (u = u.next("hour").startOf("hour").minus(l, "minutes")),
        u.isValid() && !u.isEqual(a))
      )
        return { result: u.time(), m: o };
    }
    if (
      ((o = n.match(
        "[<time>#Time] (in|at) the? [<desc>(morning|evening|night|nighttime)]",
      )),
      o.found)
    ) {
      let l = o.groups("time").text("normal");
      if (
        (/^[0-9]{1,2}$/.test(l)
          ? ((r = r.hour(l)), (r = r.startOf("hour")))
          : (r = r.time(l)),
        r.isValid() && !r.isEqual(a))
      ) {
        let u = o.groups("desc").text("reduced");
        return (
          (u === "evening" || u === "night") && (r = r.ampm("pm")),
          { result: r.time(), m: o }
        );
      }
    }
    if (
      ((o = n.match(
        "this? [<desc>(morning|evening|tonight)] at [<time>(#Cardinal|#Time)]",
      )),
      o.found)
    ) {
      let l = o.groups(),
        u = l.time.text("reduced");
      if (
        (/^[0-9]{1,2}$/.test(u)
          ? ((r = r.hour(u)), (r = r.startOf("hour")))
          : (r = r.time(u)),
        r.isValid() && !r.isEqual(a))
      ) {
        let c = l.desc.text("reduced");
        return (
          c === "morning" && (r = r.ampm("am")),
          (c === "evening" || c === "tonight") && (r = r.ampm("pm")),
          { result: r.time(), m: o }
        );
      }
    }
    if (((o = n.match("^#Cardinal$")), o.found)) {
      let l = o.text("reduced");
      if (
        ((r = r.hour(l)), (r = r.startOf("hour")), r.isValid() && !r.isEqual(a))
      )
        return (
          /(am|pm)/i.test(l) === !1 && (r = $r(r)),
          { result: r.time(), m: o }
        );
    }
    let s = n.text("reduced");
    return (
      (r = r.time(s)),
      r.isValid() && !r.isEqual(a)
        ? (/(am|pm)/i.test(s) === !1 && (r = $r(r)), { result: r.time(), m: n })
        : t.dayStart
          ? { result: t.dayStart, m: e.none() }
          : { result: null, m: e.none() }
    );
  },
  G3 = function (e) {
    if (e.has("(next|last|this)$")) return { result: null, m: e.none() };
    let t = e.match("^this? (next|upcoming|coming)");
    return t.found
      ? { result: "next", m: t }
      : ((t = e.match("^this? (past)")),
        t.found
          ? { result: "this-past", m: t }
          : ((t = e.match("^this? (last|previous)")),
            t.found
              ? { result: "last", m: t }
              : ((t = e.match("^(this|current)")),
                t.found
                  ? { result: "this", m: t }
                  : { result: null, m: e.none() })));
  },
  S3 = function (e) {
    let t = e.match("[(start|beginning) of] .", 0);
    return t.found
      ? { result: "start", m: t }
      : ((t = e.match("[end of] .", 0)),
        t.found
          ? { result: "end", m: t }
          : ((t = e.match("[(middle|midpoint|center) of] .", 0)),
            t.found ? { result: "middle", m: t } : { result: null, m: t }));
  },
  g = "America/",
  b = "Asia/",
  G = "Europe/",
  se = "Africa/",
  q = "Australia/",
  me = "Pacific/",
  M3 = {
    "british summer time": G + "London",
    bst: G + "London",
    "british time": G + "London",
    "britain time": G + "London",
    "irish summer time": G + "Dublin",
    "irish time": G + "Dublin",
    ireland: G + "Dublin",
    "central european time": G + "Berlin",
    cet: G + "Berlin",
    "central european summer time": G + "Berlin",
    cest: G + "Berlin",
    "central europe": G + "Berlin",
    "eastern european time": G + "Riga",
    eet: G + "Riga",
    "eastern european summer time": G + "Riga",
    eest: G + "Riga",
    "eastern europe time": G + "Riga",
    "western european time": G + "Lisbon",
    "western european summer time": G + "Lisbon",
    "western europe": G + "Lisbon",
    "turkey standard time": G + "Istanbul",
    trt: G + "Istanbul",
    "turkish time": G + "Istanbul",
    etc: se + "Freetown",
    utc: se + "Freetown",
    "greenwich standard time": se + "Freetown",
    gmt: se + "Freetown",
    "east africa time": se + "Nairobi",
    "east african time": se + "Nairobi",
    "eastern africa time": se + "Nairobi",
    "central africa time": se + "Khartoum",
    "central african time": se + "Khartoum",
    "south africa standard time": se + "Johannesburg",
    sast: se + "Johannesburg",
    "southern africa": se + "Johannesburg",
    "south african": se + "Johannesburg",
    "west africa standard time": se + "Lagos",
    "western africa time": se + "Lagos",
    "west african time": se + "Lagos",
    "australian central standard time": q + "Adelaide",
    acst: q + "Adelaide",
    "australian central daylight time": q + "Adelaide",
    acdt: q + "Adelaide",
    "australia central": q + "Adelaide",
    "australian eastern standard time": q + "Brisbane",
    aest: q + "Brisbane",
    "australian eastern daylight time": q + "Brisbane",
    aedt: q + "Brisbane",
    "australia east": q + "Brisbane",
    "australian western standard time": q + "Perth",
    awst: q + "Perth",
    "australian western daylight time": q + "Perth",
    awdt: q + "Perth",
    "australia west": q + "Perth",
    "australian central western standard time": q + "Eucla",
    acwst: q + "Eucla",
    "australia central west": q + "Eucla",
    "lord howe standard time": q + "Lord_Howe",
    lhst: q + "Lord_Howe",
    "lord howe daylight time": q + "Lord_Howe",
    lhdt: q + "Lord_Howe",
    "russian standard time": G + "Moscow",
    msk: G + "Moscow",
    russian: G + "Moscow",
    "central standard time": g + "Chicago",
    "central time": g + "Chicago",
    cst: g + "Havana",
    "central daylight time": g + "Chicago",
    cdt: g + "Havana",
    "mountain standard time": g + "Denver",
    "mountain time": g + "Denver",
    mst: g + "Denver",
    "mountain daylight time": g + "Denver",
    mdt: g + "Denver",
    "atlantic standard time": g + "Halifax",
    "atlantic time": g + "Halifax",
    ast: b + "Baghdad",
    "atlantic daylight time": g + "Halifax",
    adt: g + "Halifax",
    "eastern standard time": g + "New_York",
    eastern: g + "New_York",
    "eastern time": g + "New_York",
    est: g + "New_York",
    "eastern daylight time": g + "New_York",
    edt: g + "New_York",
    "pacific time": g + "Los_Angeles",
    "pacific standard time": g + "Los_Angeles",
    pst: g + "Los_Angeles",
    "pacific daylight time": g + "Los_Angeles",
    pdt: g + "Los_Angeles",
    "alaskan standard time": g + "Anchorage",
    "alaskan time": g + "Anchorage",
    ahst: g + "Anchorage",
    "alaskan daylight time": g + "Anchorage",
    ahdt: g + "Anchorage",
    "hawaiian standard time": me + "Honolulu",
    "hawaiian time": me + "Honolulu",
    hst: me + "Honolulu",
    "aleutian time": me + "Honolulu",
    "hawaii time": me + "Honolulu",
    "newfoundland standard time": g + "St_Johns",
    "newfoundland time": g + "St_Johns",
    nst: g + "St_Johns",
    "newfoundland daylight time": g + "St_Johns",
    ndt: g + "St_Johns",
    "brazil time": g + "Sao_Paulo",
    brt: g + "Sao_Paulo",
    brasília: g + "Sao_Paulo",
    brasilia: g + "Sao_Paulo",
    "brazilian time": g + "Sao_Paulo",
    "argentina time": g + "Buenos_Aires",
    "argentinian time": g + "Buenos_Aires",
    "amazon time": g + "Manaus",
    amt: g + "Manaus",
    "amazonian time": g + "Manaus",
    "easter island standard time": "Chile/Easterisland",
    east: "Chile/Easterisland",
    "easter island summer time": "Chile/Easterisland",
    easst: "Chile/Easterisland",
    "venezuelan standard time": g + "Caracas",
    "venezuelan time": g + "Caracas",
    vet: g + "Caracas",
    "venezuela time": g + "Caracas",
    "paraguay time": g + "Asuncion",
    pyt: g + "Asuncion",
    "paraguay summer time": g + "Asuncion",
    pyst: g + "Asuncion",
    "cuba standard time": g + "Havana",
    "cuba time": g + "Havana",
    "cuba daylight time": g + "Havana",
    "cuban time": g + "Havana",
    "bolivia time": g + "La_Paz",
    "bolivian time": g + "La_Paz",
    "colombia time": g + "Bogota",
    cot: g + "Bogota",
    "colombian time": g + "Bogota",
    "acre time": g + "Eirunepe",
    "peru time": g + "Lima",
    "chile standard time": g + "Punta_Arenas",
    "chile time": g + "Punta_Arenas",
    clst: g + "Punta_Arenas",
    "chile summer time": g + "Punta_Arenas",
    cldt: g + "Punta_Arenas",
    "uruguay time": g + "Montevideo",
    uyt: g + "Montevideo",
    ist: b + "Jerusalem",
    "arabic standard time": b + "Baghdad",
    "arabic time": b + "Baghdad",
    "arab time": b + "Baghdad",
    "iran standard time": b + "Tehran",
    "iran time": b + "Tehran",
    irst: b + "Tehran",
    "iran daylight time": b + "Tehran",
    irdt: b + "Tehran",
    iranian: b + "Tehran",
    "pakistan standard time": b + "Karachi",
    "pakistan time": b + "Karachi",
    pkt: b + "Karachi",
    "india standard time": b + "Kolkata",
    "indian time": b + "Kolkata",
    "indochina time": b + "Bangkok",
    ict: b + "Bangkok",
    "south east asia": b + "Bangkok",
    "china standard time": b + "Shanghai",
    ct: b + "Shanghai",
    "chinese time": b + "Shanghai",
    "alma-ata time": b + "Almaty",
    almt: b + "Almaty",
    "oral time": b + "Oral",
    "orat time": b + "Oral",
    "yakutsk time": b + "Yakutsk",
    yakt: b + "Yakutsk",
    "gulf standard time": b + "Dubai",
    "gulf time": b + "Dubai",
    gst: b + "Dubai",
    uae: b + "Dubai",
    "hong kong time": b + "Hong_Kong",
    hkt: b + "Hong_Kong",
    "western indonesian time": b + "Jakarta",
    wib: b + "Jakarta",
    "indonesia time": b + "Jakarta",
    "central indonesian time": b + "Makassar",
    wita: b + "Makassar",
    "israel daylight time": b + "Jerusalem",
    idt: b + "Jerusalem",
    "israel standard time": b + "Jerusalem",
    "israel time": b + "Jerusalem",
    israeli: b + "Jerusalem",
    "krasnoyarsk time": b + "Krasnoyarsk",
    krat: b + "Krasnoyarsk",
    "malaysia time": b + "Kuala_Lumpur",
    myt: b + "Kuala_Lumpur",
    "singapore time": b + "Singapore",
    sgt: b + "Singapore",
    "korea standard time": b + "Seoul",
    "korea time": b + "Seoul",
    kst: b + "Seoul",
    "korean time": b + "Seoul",
    "uzbekistan time": b + "Samarkand",
    uzt: b + "Samarkand",
    "vladivostok time": b + "Vladivostok",
    vlat: b + "Vladivostok",
    "maldives time": "Indian/Maldives",
    mvt: "Indian/Maldives",
    "mauritius time": "Indian/Mauritius",
    mut: "Indian/Mauritius",
    "marshall islands time": me + "Kwajalein",
    mht: me + "Kwajalein",
    "samoa standard time": me + "Midway",
    sst: me + "Midway",
    "somoan time": me + "Midway",
    "chamorro standard time": me + "Guam",
    chst: me + "Guam",
    "papua new guinea time": me + "Bougainville",
    pgt: me + "Bougainville",
  };
let B3 = C().timezones,
  L3 = Object.keys(B3).reduce((e, t) => ((e[t] = t), e), {});
const Bl = Object.assign({}, M3, L3),
  W3 = /(-?[0-9]+)h(rs)?/i,
  q3 = /(-?[0-9]+)/,
  K3 = /utc([-+]?[0-9]+)/i,
  J3 = /gmt([-+]?[0-9]+)/i,
  jr = function (e) {
    return (
      (e = Number(e)),
      e > -13 && e < 13
        ? ((e = e * -1), (e = (e > 0 ? "+" : "") + e), "Etc/GMT" + e)
        : null
    );
  },
  _3 = function (e) {
    let t = e.match(W3);
    if (t !== null || ((t = e.match(K3)), t !== null)) return jr(t[1]);
    if (((t = e.match(J3)), t !== null)) {
      let n = Number(t[1]) * -1;
      return jr(n);
    }
    return ((t = e.match(q3)), t !== null ? jr(t[1]) : null);
  },
  U3 = function (e) {
    let t = e.match("#Timezone+");
    t = t.not("(in|for|by|near|at)");
    let n = t.text("reduced");
    if (Bl.hasOwnProperty(n)) return { result: Bl[n], m: t };
    let r = _3(n);
    return r ? { result: r, m: t } : { result: null, m: e.none() };
  },
  R3 = function (e) {
    let t = e.match("#WeekDay");
    return t.found && !e.has("^#WeekDay$")
      ? e.has("(this|next|last) (next|upcoming|coming|past)? #WeekDay")
        ? { result: null, m: e.none() }
        : { result: t.text("reduced"), m: t }
      : { result: null, m: e.none() };
  },
  Y3 = function (e) {
    return (
      (e = e.not("[^the] !#Value", 0)),
      (e = e.not("#Preposition$")),
      (e = e.not("#Conjunction$")),
      (e = e.not("sharp")),
      (e = e.not("on the dot")),
      (e = e.not("^(on|of)")),
      (e = e.not("(next|last|this)$")),
      e
    );
  },
  Q3 = function (e, t) {
    let n = R2(e),
      r = n.result;
    ((e = e.not(n.m)), (n = Q2(e)));
    let a = n.result;
    ((e = e.not(n.m)), (n = U3(e)));
    let i = n.result;
    ((e = e.not(n.m)), (n = io(e, t)));
    let o = n.result;
    ((e = e.not(n.m)), (n = R3(e)));
    let s = n.result;
    ((e = e.not(n.m)), (n = S3(e)));
    let l = n.result;
    ((e = e.not(n.m)), (n = G3(e)));
    let u = n.result;
    return (
      (e = e.not(n.m)),
      (e = Y3(e)),
      {
        shift: r,
        counter: a,
        tz: i,
        time: o,
        weekDay: s,
        section: l,
        rel: u,
        doc: e,
      }
    );
  };
class fe {
  constructor(t, n, r) {
    ((this.unit = n || "day"), (this.setTime = !1), (r = r || {}));
    let a = {};
    (r.today &&
      (a = {
        date: r.today.date(),
        month: r.today.month(),
        year: r.today.year(),
      }),
      t && t.month === "sept" && (t.month = "sep"));
    let i = C(t, r.timezone, { today: a, dmy: r.dmy });
    (Object.defineProperty(this, "d", {
      enumerable: !1,
      writable: !0,
      value: i,
    }),
      Object.defineProperty(this, "context", {
        enumerable: !1,
        writable: !0,
        value: r,
      }));
  }
  clone() {
    let t = new fe(this.d, this.unit, this.context);
    return ((t.setTime = this.setTime), t);
  }
  log() {
    return (
      console.log("--"),
      this.d.log(),
      console.log(`
`),
      this
    );
  }
  applyShift(t = {}) {
    return (
      Object.keys(t).forEach((n) => {
        ((this.d = this.d.add(t[n], n)),
          (n === "hour" || n === "minute") && (this.setTime = !0));
      }),
      this
    );
  }
  applyTime(t) {
    if (t) {
      if (
        (/^[0-9]{1,2}$/.test(t)
          ? (this.d = this.d.hour(t))
          : (this.d = this.d.time(t)),
        !/[ap]m/.test(t))
      ) {
        let a = this.d.time("6:00am");
        this.d.isBefore(a) && (this.d = this.d.ampm("pm"));
        let i = this.d.time("10:00pm");
        this.d.isAfter(i) && (this.d = this.d.ampm("am"));
      }
    } else this.d = this.d.startOf("day");
    return ((this.setTime = !0), this);
  }
  applyWeekDay(t) {
    if (t) {
      let n = this.d.epoch;
      ((this.d = this.d.day(t)),
        this.d.epoch < n && (this.d = this.d.add(1, "week")));
    }
    return this;
  }
  applyRel(t) {
    return t === "next"
      ? this.next()
      : t === "last" || t === "this-past"
        ? this.last()
        : this;
  }
  applySection(t) {
    return t === "start"
      ? this.start()
      : t === "end"
        ? this.end()
        : t === "middle"
          ? this.middle()
          : this;
  }
  format(t) {
    return this.d.format(t);
  }
  start() {
    return (
      (this.d = this.d.startOf(this.unit)),
      this.context.dayStart && (this.d = this.d.time(this.context.dayStart)),
      this
    );
  }
  end() {
    if (((this.d = this.d.endOf(this.unit)), this.context.dayEnd)) {
      this.d = this.d.startOf("day");
      let t = this.d.time(this.context.dayEnd);
      if (t.isAfter(this.d)) return ((this.d = t), this);
    }
    return this;
  }
  middle() {
    let t = this.d.diff(this.d.endOf(this.unit)),
      n = Math.round(t.minutes / 2);
    return ((this.d = this.d.add(n, "minutes")), this);
  }
  beforeEnd() {
    let t = this.d.startOf(this.unit).diff(this.d.endOf(this.unit)),
      n = Math.round(t.minutes / 4);
    return (
      (this.d = this.d.endOf(this.unit)),
      (this.d = this.d.minus(n, "minutes")),
      this.context.dayStart && (this.d = this.d.time(this.context.dayStart)),
      this
    );
  }
  before() {
    return (
      (this.d = this.d.minus(1, this.unit)),
      (this.d = this.d.endOf(this.unit)),
      this.context.dayEnd && (this.d = this.d.time(this.context.dayEnd)),
      this
    );
  }
  after() {
    return (
      (this.d = this.d.add(1, this.unit)),
      (this.d = this.d.startOf(this.unit)),
      this
    );
  }
  next() {
    return (
      (this.d = this.d.add(1, this.unit)),
      (this.d = this.d.startOf(this.unit)),
      this
    );
  }
  last() {
    return (
      (this.d = this.d.minus(1, this.unit)),
      (this.d = this.d.startOf(this.unit)),
      this
    );
  }
}
class Te extends fe {
  constructor(t, n, r) {
    (super(t, n, r),
      (this.unit = "day"),
      this.d.isValid() && (this.d = this.d.startOf("day")));
  }
  middle() {
    return ((this.d = this.d.time("10am")), this);
  }
  beforeEnd() {
    return ((this.d = this.d.time("2pm")), this);
  }
}
class yn extends Te {
  constructor(t, n, r) {
    (super(t, n, r),
      (this.unit = "day"),
      this.d.isValid() && (this.d = this.d.startOf("day")));
  }
  next() {
    return ((this.d = this.d.add(1, "year")), this);
  }
  last() {
    return ((this.d = this.d.minus(1, "year")), this);
  }
}
class Gi extends Te {
  constructor(t, n, r) {
    (super(t, n, r),
      (this.unit = "day"),
      (this.isWeekDay = !0),
      typeof t == "string"
        ? ((this.d = C(r.today, r.timezone)),
          (this.d = this.d.day(t)),
          this.d.isBefore(r.today) && (this.d = this.d.add(7, "days")))
        : (this.d = t),
      (this.weekDay = this.d.dayName()),
      this.d.isValid() && (this.d = this.d.startOf("day")));
  }
  next() {
    return (
      (this.d = this.d.add(7, "days")),
      (this.d = this.d.day(this.weekDay)),
      this
    );
  }
  last() {
    return (
      (this.d = this.d.minus(7, "days")),
      (this.d = this.d.day(this.weekDay)),
      this
    );
  }
  before() {
    return (
      (this.d = this.d.minus(1, "day")),
      (this.d = this.d.endOf("day")),
      this.context.dayEnd && (this.d = this.d.time(this.context.dayEnd)),
      this
    );
  }
  applyRel(t) {
    if (t === "next") {
      let n = this.context.today.endOf("week").add(1, "week");
      return (this.next(), this.d.isAfter(n) && this.last(), this);
    }
    if (t === "this-past") return this.last();
    if (t === "last") {
      let n = this.context.today.startOf("week");
      return (this.last(), this.d.isBefore(n) === !1 && this.last(), this);
    }
    return this;
  }
}
class Z3 extends yn {
  constructor(t, n, r) {
    (super(t, n, r),
      (this.unit = "day"),
      this.d.isValid() && (this.d = this.d.startOf("day")));
  }
}
class Ur extends fe {
  constructor(t, n, r) {
    (super(t, n, r, !0),
      (this.unit = "hour"),
      this.d.isValid() && (this.d = this.d.startOf("hour")));
  }
}
class Pc extends fe {
  constructor(t, n, r) {
    (super(t, n, r, !0),
      (this.unit = "minute"),
      this.d.isValid() && (this.d = this.d.startOf("minute")));
  }
}
class Ue extends fe {
  constructor(t, n, r) {
    (super(t, n, r, !0), (this.unit = "millisecond"));
  }
}
class X3 extends fe {
  constructor(t, n, r) {
    (super(t, n, r),
      (this.unit = "month"),
      this.d.isValid() && (this.d = this.d.startOf(this.unit)));
  }
}
class Rr extends fe {
  constructor(t, n, r) {
    (super(t, n, r),
      (this.unit = "month"),
      this.d.isValid() && (this.d = this.d.startOf(this.unit)));
  }
  next() {
    return (
      (this.d = this.d.add(1, "year")),
      (this.d = this.d.startOf("month")),
      this
    );
  }
  last() {
    return (
      (this.d = this.d.minus(1, "year")),
      (this.d = this.d.startOf("month")),
      this
    );
  }
}
class Ll extends fe {
  constructor(t, n, r) {
    (super(t, n, r),
      (this.unit = "quarter"),
      this.d.isValid() && (this.d = this.d.startOf(this.unit)));
  }
  last() {
    return (
      (this.d = this.d.minus(1, "quarter")),
      (this.d = this.d.startOf(this.unit)),
      this
    );
  }
}
class Si extends fe {
  constructor(t, n, r) {
    (super(t, n, r),
      (this.unit = "quarter"),
      this.d.isValid() && (this.d = this.d.startOf(this.unit)));
  }
  next() {
    return (
      (this.d = this.d.add(1, "year")),
      (this.d = this.d.startOf(this.unit)),
      this
    );
  }
  last() {
    return (
      (this.d = this.d.minus(1, "year")),
      (this.d = this.d.startOf(this.unit)),
      this
    );
  }
}
class oo extends fe {
  constructor(t, n, r) {
    (super(t, n, r),
      (this.unit = "season"),
      this.d.isValid() && (this.d = this.d.startOf(this.unit)));
  }
  next() {
    return (
      (this.d = this.d.add(1, "year")),
      (this.d = this.d.startOf(this.unit)),
      this
    );
  }
  last() {
    return (
      (this.d = this.d.minus(1, "year")),
      (this.d = this.d.startOf(this.unit)),
      this
    );
  }
}
class Mi extends fe {
  constructor(t, n, r) {
    (super(t, n, r),
      (this.unit = "year"),
      this.d.isValid() && (this.d = this.d.startOf("year")));
  }
}
class Rn extends fe {
  constructor(t, n, r) {
    (super(t, n, r),
      (this.unit = "week"),
      this.d.isValid() && (this.d = this.d.startOf("week")));
  }
  clone() {
    return new Rn(this.d, this.unit, this.context);
  }
  middle() {
    return ((this.d = this.d.add(2, "days")), this);
  }
  beforeEnd() {
    return ((this.d = this.d.day("friday")), this);
  }
}
class Ac extends fe {
  constructor(t, n, r) {
    (super(t, n, r),
      (this.unit = "week"),
      this.d.isValid() &&
        ((this.d = this.d.day("saturday")), (this.d = this.d.startOf("day"))));
  }
  start() {
    return ((this.d = this.d.day("saturday").startOf("day")), this);
  }
  next() {
    return (
      (this.d = this.d.add(1, this.unit)),
      (this.d = this.d.startOf("weekend")),
      this
    );
  }
  last() {
    return (
      (this.d = this.d.minus(1, this.unit)),
      (this.d = this.d.startOf("weekend")),
      this
    );
  }
}
const Le = {
  today: (e) => new Te(e.today, null, e),
  yesterday: (e) => new Te(e.today.minus(1, "day"), null, e),
  tomorrow: (e) => new Te(e.today.plus(1, "day"), null, e),
  eom: (e) => {
    let t = e.today.endOf("month");
    return ((t = t.startOf("day")), new Te(t, null, e));
  },
  eoy: (e) => {
    let t = e.today.endOf("year");
    return ((t = t.startOf("day")), new Te(t, null, e));
  },
  now: (e) => new Ue(e.today, null, e),
};
Le.tommorrow = Le.tomorrow;
Le.tmrw = Le.tomorrow;
Le.anytime = Le.today;
Le.sometime = Le.today;
const eP = function (e, t, n) {
    let r = null;
    e.found === !1 &&
      (n.time !== null && (r = new Ue(t.today, null, t)),
      n.shift &&
        Object.keys(n.shift).length > 0 &&
        (n.shift.hour || n.shift.minute
          ? (r = new Ue(t.today, null, t))
          : (r = new Te(t.today, null, t))));
    let a = e.text("reduced");
    return Le.hasOwnProperty(a) === !0
      ? Le[a](t)
      : a === "next" && n.shift && Object.keys(n.shift).length > 0
        ? Le.tomorrow(t)
        : r;
  },
  Ft = "january",
  Vt = "february",
  Wl = "march",
  Nr = "april",
  cn = "may",
  tP = "june",
  Tr = "july",
  Or = "august",
  Ba = "september",
  En = "october",
  yt = "november",
  Je = "december";
var Ir = {
  "new years eve": [Je, 31],
  "new years": [Ft, 1],
  "new years day": [Ft, 1],
  "inauguration day": [Ft, 20],
  "australia day": [Ft, 26],
  "national freedom day": [Vt, 1],
  "groundhog day": [Vt, 2],
  "rosa parks day": [Vt, 4],
  "valentines day": [Vt, 14],
  "saint valentines day": [Vt, 14],
  "st valentines day ": [Vt, 14],
  "saint patricks day": [Wl, 17],
  "st patricks day": [Wl, 17],
  "april fools": [Nr, 1],
  "april fools day": [Nr, 1],
  "emancipation day": [Nr, 16],
  "tax day": [Nr, 15],
  "labour day": [cn, 1],
  "cinco de mayo": [cn, 5],
  "national nurses day": [cn, 6],
  "harvey milk day": [cn, 22],
  "victoria day": [cn, 24],
  juneteenth: [tP, 19],
  "canada day": [Tr, 1],
  "independence day": [Tr, 4],
  "independents day": [Tr, 4],
  "bastille day": [Tr, 14],
  "purple heart day": [Or, 7],
  "womens equality day": [Or, 26],
  "16 de septiembre": [Ba, 16],
  "dieciseis de septiembre": [Ba, 16],
  "grito de dolores": [Ba, 16],
  halloween: [En, 31],
  "all hallows eve": [En, 31],
  "day of the dead": [En, 31],
  "dia de muertos": [En, 31],
  "veterans day": [yt, 11],
  "st andrews day": [yt, 30],
  "saint andrews day": [yt, 30],
  "all saints day": [yt, 1],
  "all sts day": [yt, 1],
  "armistice day": [yt, 11],
  "rememberance day": [yt, 11],
  "christmas eve": [Je, 24],
  christmas: [Je, 25],
  xmas: [Je, 25],
  "boxing day": [Je, 26],
  "st stephens day": [Je, 26],
  "saint stephens day": [Je, 26],
  epiphany: [Ft, 6],
  "orthodox christmas day": [Ft, 7],
  "orthodox new year": [Ft, 14],
  "assumption of mary": [Or, 15],
  "all souls day": [yt, 2],
  "feast of the immaculate conception": [Je, 8],
  "feast of our lady of guadalupe": [Je, 12],
  kwanzaa: [Je, 26],
  imbolc: [Vt, 2],
  beltaine: [cn, 1],
  lughnassadh: [Or, 1],
  samhain: [En, 31],
};
const nP = function (e, t, n, r) {
  if (Ir.hasOwnProperty(e) || Ir.hasOwnProperty(t)) {
    let a = Ir[e] || Ir[t] || [],
      i = C.now(r);
    if (
      ((i = i.year(n)),
      (i = i.startOf("year")),
      (i = i.month(a[0])),
      (i = i.date(a[1])),
      i.isValid())
    )
      return i;
  }
  return null;
};
var rP = nP;
const aP = "january",
  iP = "february",
  oP = "march",
  sP = "may",
  lP = "june",
  uP = "september",
  ql = "october",
  Kl = "november",
  hn = "monday",
  cP = "thursday",
  hP = "friday",
  Jl = "sunday";
let Yt = {
  "martin luther king day": [3, hn, aP],
  "presidents day": [3, hn, iP],
  "commonwealth day": [2, hn, oP],
  "mothers day": [2, Jl, sP],
  "fathers day": [3, Jl, lP],
  "labor day": [1, hn, uP],
  "columbus day": [2, hn, ql],
  "canadian thanksgiving": [2, hn, ql],
  thanksgiving: [4, cP, Kl],
  "black friday": [4, hP, Kl],
};
Yt["turday day"] = Yt.thanksgiving;
Yt["indigenous peoples day"] = Yt["columbus day"];
Yt["mlk day"] = Yt["martin luther king day"];
var Er = Yt;
const dP = function (e, t, n, r) {
  if (Er.hasOwnProperty(e) || Er.hasOwnProperty(t)) {
    let a = Er[e] || Er[t] || [],
      i = C.now(r);
    ((i = i.year(n)), (i = i.month(a[2])), (i = i.startOf("month")));
    let o = i.month();
    if (
      ((i = i.day(a[1])),
      i.month() !== o && (i = i.add(1, "week")),
      a[0] > 1 && (i = i.add(a[0] - 1, "week")),
      i.isValid())
    )
      return i;
  }
  return null;
};
var fP = dP;
let Qt = {
  easter: 0,
  "ash wednesday": -46,
  "palm sunday": 7,
  "maundy thursday": -3,
  "good friday": -2,
  "holy saturday": -1,
  "easter saturday": -1,
  "easter monday": 1,
  "ascension day": 39,
  "whit sunday": 49,
  "whit monday": 50,
  "trinity sunday": 65,
  "corpus christi": 60,
  "mardi gras": -47,
};
Qt["easter sunday"] = Qt.easter;
Qt.pentecost = Qt["whit sunday"];
Qt.whitsun = Qt["whit sunday"];
var Hr = Qt;
const mP = function (e) {
  let t = Math.floor,
    n = e % 19,
    r = t(e / 100),
    a = (r - t(r / 4) - t((8 * r + 13) / 25) + 19 * n + 15) % 30,
    i = a - t(a / 28) * (1 - t(29 / (a + 1)) * t((21 - n) / 11)),
    o = (e + t(e / 4) + i + 2 - r + t(r / 4)) % 7,
    s = i - o,
    l = 3 + t((s + 40) / 44),
    u = s + 28 - 31 * t(l / 4);
  return ((l = l === 4 ? "April" : "March"), l + " " + u);
};
var pP = mP;
const gP = function (e, t, n, r) {
  if (Hr.hasOwnProperty(e) || Hr.hasOwnProperty(t)) {
    let a = Hr[e] || Hr[t] || [],
      i = pP(n);
    if (!i) return null;
    let o = C(i, r);
    o = o.year(n);
    let s = o.add(a, "day");
    if (s.isValid()) return s;
  }
  return null;
};
var yP = gP;
const zr = {
    spring: [
      2003, 2007, 2044, 2048, 2052, 2056, 2060, 2064, 2068, 2072, 2076, 2077,
      2080, 2081, 2084, 2085, 2088, 2089, 2092, 2093, 2096, 2097,
    ],
    summer: [
      2021, 2016, 2020, 2024, 2028, 2032, 2036, 2040, 2041, 2044, 2045, 2048,
      2049, 2052, 2053, 2056, 2057, 2060, 2061, 2064, 2065, 2068, 2069, 2070,
      2072, 2073, 2074, 2076, 2077, 2078, 2080, 2081, 2082, 2084, 2085, 2086,
      2088, 2089, 2090, 2092, 2093, 2094, 2096, 2097, 2098, 2099,
    ],
    fall: [
      2002, 2003, 2004, 2006, 2007, 2010, 2011, 2014, 2015, 2018, 2019, 2022,
      2023, 2026, 2027, 2031, 2035, 2039, 2043, 2047, 2051, 2055, 2059, 2092,
      2096,
    ],
    winter: [
      2002, 2003, 2006, 2007, 2011, 2015, 2019, 2023, 2027, 2031, 2035, 2039,
      2043, 2080, 2084, 2088, 2092, 2096,
    ],
  },
  bP = [2080, 2084, 2088, 2092, 2096],
  vP = function (e) {
    let t = {
      spring: "March 20 " + e,
      summer: "June 21 " + e,
      fall: "Sept 22 " + e,
      winter: "Dec 21 " + e,
    };
    return (
      zr.spring.indexOf(e) !== -1 && (t.spring = "March 19 " + e),
      zr.summer.indexOf(e) !== -1 && (t.summer = "June 20 " + e),
      zr.fall.indexOf(e) !== -1 && (t.fall = "Sept 21 " + e),
      zr.winter.indexOf(e) !== -1 && (t.winter = "Dec 22 " + e),
      bP.indexOf(e) !== -1 && (t.winter = "Dec 20 " + e),
      t
    );
  };
var wP = vP;
let F = {
  "spring equinox": "spring",
  "summer solistice": "summer",
  "fall equinox": "fall",
  "winter solstice": "winter",
};
F["march equinox"] = F["spring equinox"];
F["vernal equinox"] = F["spring equinox"];
F.ostara = F["spring equinox"];
F["june solstice"] = F["summer solistice"];
F.litha = F["summer solistice"];
F["autumn equinox"] = F["fall equinox"];
F["autumnal equinox"] = F["fall equinox"];
F["september equinox"] = F["fall equinox"];
F["sept equinox"] = F["fall equinox"];
F.mabon = F["fall equinox"];
F["december solstice"] = F["winter solistice"];
F["dec solstice"] = F["winter solistice"];
F.yule = F["winter solistice"];
var Fr = F;
const kP = function (e, t, n, r) {
  if (Fr.hasOwnProperty(e) || Fr.hasOwnProperty(t)) {
    let a = Fr[e] || Fr[t],
      i = wP(n);
    if (!a || !i || !i[a]) return null;
    let o = C(i[a], r);
    if (o.isValid()) return o;
  }
  return null;
};
var PP = kP;
let AP = {
  "isra and miraj": "april 13",
  "lailat al-qadr": "june 10",
  "eid al-fitr": "june 15",
  "id al-Fitr": "june 15",
  "eid ul-Fitr": "june 15",
  ramadan: "may 16",
  "eid al-adha": "sep 22",
  muharram: "sep 12",
  "prophets birthday": "nov 21",
};
var Vr = AP;
const xP = -10.64,
  CP = function (e, t, n, r) {
    if (Vr.hasOwnProperty(e) || Vr.hasOwnProperty(t)) {
      let a = Vr[e] || Vr[t] || [];
      if (!a) return null;
      let i = C(a + " 2018", r),
        s = (n - 2018) * xP;
      if (
        ((i = i.add(s, "day")),
        (i = i.startOf("day")),
        (i = i.year(n)),
        i.isValid())
      )
        return i;
    }
    return null;
  };
var DP = CP;
const $P = C.now().year(),
  _l = function (e, t, n) {
    ((t = t || $P),
      (e = e || ""),
      (e = String(e)),
      (e = e.trim().toLowerCase()),
      (e = e.replace(/'s/, "s")));
    let r = e.replace(/ day$/, "");
    ((r = r.replace(/^the /, "")), (r = r.replace(/^orthodox /, "")));
    let a = rP(e, r, t, n);
    return a !== null ||
      ((a = fP(e, r, t, n)), a !== null) ||
      ((a = yP(e, r, t, n)), a !== null) ||
      ((a = PP(e, r, t, n)), a !== null) ||
      ((a = DP(e, r, t, n)), a !== null)
      ? a
      : null;
  },
  jP = function (e, t) {
    let n = null,
      r = e.match("[<holiday>#Holiday+] [<year>#Year?]"),
      a = t.today.year();
    r.groups("year").found &&
      (a = Number(r.groups("year").text("reduced")) || a);
    let i = r.groups("holiday").text("reduced"),
      o = _l(i, a, t.timezone);
    return (
      o !== null &&
        (o.isBefore(t.today) &&
          a === t.today.year() &&
          (o = _l(i, a + 1, t.timezone)),
        (n = new Z3(o, null, t))),
      n
    );
  },
  Bi = {
    day: Te,
    hour: Ur,
    evening: Ur,
    second: Ue,
    milliscond: Ue,
    instant: Ue,
    minute: Pc,
    week: Rn,
    weekend: Ac,
    month: X3,
    quarter: Ll,
    year: Mi,
    season: oo,
    yr: Mi,
    qtr: Ll,
    wk: Rn,
    sec: Ue,
    hr: Ur,
  };
let NP = `^(${Object.keys(Bi).join("|")})$`;
const TP = function (e, t) {
    let n = e.match(NP);
    if (n.found === !0) {
      let r = n.text("reduced");
      if (Bi.hasOwnProperty(r)) {
        let a = Bi[r];
        return a ? new a(null, r, t) : null;
      }
    }
    if (((n = e.match("^#WeekDay$")), n.found === !0)) {
      let r = n.text("reduced");
      return new Gi(r, null, t);
    }
    return null;
  },
  Gr = function (e) {
    return {
      date: e.today.date(),
      month: e.today.month(),
      year: e.today.year(),
    };
  },
  OP = function (e, t) {
    let n = e.match("(spring|summer|winter|fall|autumn) [<year>#Year?]");
    if (n.found) {
      let r = e.text("reduced"),
        a = C(r, t.timezone, { today: Gr(t) }),
        i = new oo(a, null, t);
      if (i.d.isValid() === !0) return i;
    }
    if (((n = e.match("[<q>#FinancialQuarter] [<year>#Year?]")), n.found)) {
      let r = n.groups("q").text("reduced"),
        a = C(r, t.timezone, { today: Gr(t) });
      if (n.groups("year")) {
        let o = Number(n.groups("year").text()) || t.today.year();
        a = a.year(o);
      }
      let i = new Si(a, null, t);
      if (i.d.isValid() === !0) return i;
    }
    if (
      ((n = e.match("[<q>#Value] quarter (of|in)? [<year>#Year?]")), n.found)
    ) {
      let r = n.groups("q").text("reduced"),
        a = C(`q${r}`, t.timezone, { today: Gr(t) });
      if (n.groups("year")) {
        let o = Number(n.groups("year").text()) || t.today.year();
        a = a.year(o);
      }
      let i = new Si(a, null, t);
      if (i.d.isValid() === !0) return i;
    }
    if (((n = e.match("^#Year$")), n.found)) {
      let r = e.text("reduced"),
        a = C(null, t.timezone, { today: Gr(t) });
      a = a.year(r);
      let i = new Mi(a, null, t);
      if (i.d.isValid() === !0) return i;
    }
    return null;
  },
  IP = function (e, t) {
    let n = t.today.year(),
      r = e.match("[<date>#Value] of? [<month>#Month] [<year>#Year]");
    if (
      (r.found ||
        (r = e.match("[<month>#Month] the? [<date>#Value] [<year>#Year]")),
      r.found)
    ) {
      let o = {
          month: r.groups("month").text("reduced"),
          date: r.groups("date").text("reduced"),
          year: r.groups("year").text() || n,
        },
        s = new yn(o, null, t);
      if (s.d.isValid() === !0) return s;
    }
    if (((r = e.match("[<month>#Month] of? [<year>#Year]")), r.found)) {
      let o = {
          month: r.groups("month").text("reduced"),
          year: r.groups("year").text("reduced") || n,
        },
        s = new Rr(o, null, t);
      if (s.d.isValid() === !0) return s;
    }
    if (
      ((r = e.match("[<date>#Value] of? [<month>#Month]")),
      r.found || (r = e.match("[<month>#Month] the? [<date>#Value]")),
      r.found)
    ) {
      let o = {
          month: r.groups("month").text("reduced"),
          date: r.groups("date").text("reduced"),
          year: t.today.year(),
        },
        s = new yn(o, null, t);
      if (
        (s.d.month() < t.today.month() &&
          ((o.year += 1), (s = new yn(o, null, t))),
        s.d.isValid() === !0)
      )
        return s;
    }
    if (e.has("#Month")) {
      let o = {
          month: e.match("#Month").text("reduced"),
          date: 1,
          year: t.today.year(),
        },
        s = new Rr(o, null, t);
      if (
        (s.d.month() < t.today.month() &&
          ((o.year += 1), (s = new Rr(o, null, t))),
        s.d.isValid() === !0)
      )
        return s;
    }
    if (((r = e.match("#WeekDay [<date>#Value]")), r.found)) {
      let o = {
          month: t.today.month(),
          date: r.groups("date").text("reduced"),
          year: t.today.year(),
        },
        s = new yn(o, null, t);
      if (s.d.isValid() === !0) return s;
    }
    if (((r = e.match("the [<date>#Value]")), r.found)) {
      let o = {
          month: t.today.month(),
          date: r.groups("date").text("reduced"),
          year: t.today.year(),
        },
        s = new yn(o, null, t);
      if (s.d.isValid() === !0)
        return (s.d.isBefore(t.today) && (s.d = s.d.add(1, "month")), s);
    }
    if (((r = e.match("/[0-9]{4}-[0-9]{2}-[0-9]{2}t[0-9]{2}:/")), r.found)) {
      let o = e.text("reduced"),
        s = new Ue(o, null, t);
      if (s.d.isValid() === !0) return s;
    }
    let a = e.text("reduced");
    if (!a) return new Ue(t.today, null, t);
    let i = new Te(a, null, t);
    return i.d.isValid() === !1 ? null : i;
  },
  EP = function (e, t, n) {
    let r = null;
    return (
      (r = r || eP(e, t, n)),
      (r = r || jP(e, t)),
      (r = r || TP(e, t)),
      (r = r || OP(e, t)),
      (r = r || IP(e, t)),
      r
    );
  },
  HP = {
    day: Te,
    week: Rn,
    weekend: Ac,
    month: Rr,
    quarter: Si,
    season: oo,
    hour: Ur,
    minute: Pc,
  },
  zP = function (e, t = {}) {
    let n = HP[t.unit];
    if (!n) return e;
    let r = e.d;
    t.dir === "first" || t.num === 0
      ? ((r = e.start().d), (r = r.startOf(t.unit)))
      : t.dir === "last"
        ? ((r = r.endOf(e.unit)),
          t.unit === "weekend"
            ? (r = r.day("saturday", !1))
            : (r = r.startOf(t.unit)))
        : t.num &&
          (t.unit === "weekend" && (r = r.day("saturday", !0).add(1, "day")),
          (r = r.add(t.num, t.unit)));
    let a = new n(r, null, e.context);
    return a.d.isValid() === !0 ? a : e;
  },
  FP = function (e, t, n) {
    if (
      (!e &&
        n.weekDay &&
        ((e = new Gi(n.weekDay, null, t)), (n.weekDay = null)),
      !e)
    )
      return null;
    if (n.shift) {
      let r = n.shift;
      (e.applyShift(r),
        r.hour || r.minute
          ? (e = new Ue(e.d, null, e.context))
          : (r.week || r.day || r.month) && (e = new Te(e.d, null, e.context)));
    }
    return (
      n.weekDay &&
        e.unit !== "day" &&
        (e.applyWeekDay(n.weekDay), (e = new Gi(e.d, null, e.context))),
      n.rel && e.applyRel(n.rel),
      n.section && e.applySection(n.section),
      n.time && e.applyTime(n.time),
      n.counter && n.counter.unit && (e = zP(e, n.counter)),
      e
    );
  };
var Ul = {};
const VP = typeof Nt > "u" || !Ul ? self.env || {} : Ul,
  GP = (e) => {
    VP.DEBUG_DATE &&
      (console.log(`
==== '${e.doc.text()}' =====`),
      Object.keys(e).forEach((t) => {
        t !== "doc" && e[t] && console.log(t, e[t]);
      }),
      e.doc.debug());
  },
  E = function (e, t) {
    let n = Q3(e, t);
    if (((e = n.doc), GP(n), n.tz)) {
      t = Object.assign({}, t, { timezone: n.tz });
      let a = t.today.format("iso-short");
      t.today = t.today.goto(t.timezone).set(a);
    }
    let r = EP(e, t, n);
    return ((r = FP(r, t, n)), r);
  },
  Rl = {
    mon: "monday",
    tue: "tuesday",
    tues: "wednesday",
    wed: "wednesday",
    thu: "thursday",
    fri: "friday",
    sat: "saturday",
    sun: "sunday",
    monday: "monday",
    tuesday: "tuesday",
    wednesday: "wednesday",
    thursday: "thursday",
    friday: "friday",
    saturday: "saturday",
    sunday: "sunday",
  },
  Sr = function (e) {
    return e.match("(every|each)").found
      ? "AND"
      : e.match("(any|a)").found
        ? "OR"
        : null;
  },
  SP = function (e, t) {
    let n = e.match(
      "[<logic>(every|any|each)] [<skip>other?] [<unit>#Duration] (starting|beginning|commencing)?",
    );
    if (n.found) {
      let r = { interval: {} },
        a = n.groups("unit").text("reduced");
      return (
        (r.interval[a] = 1),
        (r.choose = Sr(n)),
        n.groups("skip").found && (r.interval[a] = 2),
        (e = e.remove(n)),
        { repeat: r }
      );
    }
    if (
      ((n = e.match(
        "[<logic>(every|any|each)] [<num>#Value] [<unit>#Duration] (starting|beginning|commencing)?",
      )),
      n.found)
    ) {
      let r = { interval: {} },
        a = n.groups("unit");
      a.nouns().toSingular();
      let i = a.text("reduced");
      return (
        (r.interval[i] = n.groups("num").numbers().get()[0]),
        (r.choose = Sr(n)),
        (e = e.remove(n)),
        { repeat: r }
      );
    }
    if (
      ((n = e.match(
        "[<logic>(every|any|each|a)] [<skip>other?] [<day>#WeekDay+] (starting|beginning|commencing)?",
      )),
      n.found)
    ) {
      let r = { interval: { day: 1 }, filter: { weekDays: {} } },
        a = n.groups("day").text("reduced");
      if (((a = Rl[a]), a))
        return (
          (r.filter.weekDays[a] = !0),
          (r.choose = Sr(n)),
          (e = e.remove(n)),
          { repeat: r }
        );
    }
    if (
      ((n = e.match(
        "[<logic>(every|any|each|a)] [<day>(weekday|week day|weekend|weekend day)] (starting|beginning|commencing)?",
      )),
      n.found)
    ) {
      let r = { interval: { day: 1 }, filter: { weekDays: {} } },
        a = n.groups("day");
      return (
        a.has("(weekday|week day)")
          ? (r.filter.weekDays = {
              monday: !0,
              tuesday: !0,
              wednesday: !0,
              thursday: !0,
              friday: !0,
            })
          : a.has("(weekend|weekend day)") &&
            (r.filter.weekDays = { saturday: !0, sunday: !0 }),
        (r.choose = Sr(n)),
        (e = e.remove(n)),
        { repeat: r }
      );
    }
    if (
      ((n = e.match(
        "[<day>(mondays|tuesdays|wednesdays|thursdays|fridays|saturdays|sundays)] (at|near|after)? [<time>#Time+?]",
      )),
      n.found)
    ) {
      let r = { interval: { day: 1 }, filter: { weekDays: {} } },
        a = n.groups("day").text("reduced");
      if (((a = a.replace(/s$/, "")), (a = Rl[a]), a)) {
        ((r.filter.weekDays[a] = !0), (r.choose = "OR"), (e = e.remove(n)));
        let i = n.groups("time");
        return (i.found && (r.time = io(i, t)), { repeat: r });
      }
    }
    return null;
  },
  Bn = function (e) {
    let t = e.start,
      n = e.end;
    if (t.d.isAfter(n.d)) {
      if (t.isWeekDay && n.isWeekDay) return (e.end.next(), e);
      let r = t;
      ((e.start = n), (e.end = r));
    }
    return e;
  },
  La = function (e) {
    let t = e.start,
      n = e.end;
    return (t.d.isAfter(n.d) && n.d.hour() < 10 && (n.d = n.d.ampm("pm")), e);
  },
  MP = [
    {
      match:
        "[<from>#Time+] (to|until|upto|through|thru|and) [<to>#Time+ #Date+]",
      desc: "3pm to 4pm january 5th",
      parse: (e, t) => {
        let n = e.groups("from"),
          r = e.groups("to"),
          a = E(r, t);
        if (a) {
          let i = a.clone();
          if ((i.applyTime(n.text("implicit")), i)) {
            let o = { start: i, end: a, unit: "time" };
            return (/(am|pm)/.test(r) === !1 && (o = La(o)), (o = Bn(o)), o);
          }
        }
        return null;
      },
    },
    {
      match:
        "[<main>#Date+] from [<a>#Time] (to|until|upto|through|thru|and) [<b>#Time+]",
      desc: "january from 3pm to 4pm",
      parse: (e, t) => {
        let n = e.groups("main"),
          r = e.groups("a"),
          a = e.groups("b");
        if (((n = E(n, t)), n)) {
          n.applyTime(r.text("implicit"));
          let i = n.clone();
          if ((i.applyTime(a.text("implicit")), i)) {
            let o = { start: n, end: i, unit: "time" };
            return (
              /(am|pm)/.test(a.text()) === !1 && (o = La(o)),
              (o = Bn(o)),
              o
            );
          }
        }
        return null;
      },
    },
    {
      match: "[<from>#Date+] (to|until|upto|through|thru|and) [<to>#Time+]",
      desc: "january from 3pm to 4pm",
      parse: (e, t) => {
        let n = e.groups("from"),
          r = e.groups("to");
        if (((n = E(n, t)), n)) {
          let a = n.clone();
          if ((a.applyTime(r.text("implicit")), a)) {
            let i = { start: n, end: a, unit: "time" };
            return (
              /(am|pm)/.test(r.text()) === !1 && (i = La(i)),
              (i = Bn(i)),
              i
            );
          }
        }
        return null;
      },
    },
  ],
  BP = [
    {
      match: "^during? #Month+ (or|and) #Month [<year>#Year]?",
      desc: "march or june",
      parse: (e, t) => {
        let n = e.match("^during? [#Month]", 0);
        e = e.not("(or|and)");
        let r = E(n, t);
        if (r) {
          let a = [{ start: r, end: r.clone().end(), unit: r.unit }],
            i = e.not(n);
          i.found &&
            i.match("#Month").forEach((s) => {
              let l = E(s, t);
              a.push({ start: l, end: l.clone().end(), unit: l.unit });
            });
          let o = e.match("#Year$");
          return (
            o.found &&
              ((o = o.text("reduced")),
              a.forEach((s) => {
                ((s.start.d = s.start.d.year(o)), (s.end.d = s.end.d.year(o)));
              })),
            a
          );
        }
        return null;
      },
    },
    {
      match: "^#Month #Value+ (or|and)? #Value$",
      desc: "jan 5 or 8",
      parse: (e, t) => {
        e = e.not("(or|and)");
        let n = e.match("^#Month #Value"),
          r = E(n, t);
        if (r) {
          let a = [{ start: r, end: r.clone().end(), unit: r.unit }],
            i = e.not(n);
          return (
            i.found &&
              i.match("#Value").forEach((o) => {
                let s = r.clone();
                ((s.d = s.d.date(o.text("reduced"))),
                  a.push({ start: s, end: s.clone().end(), unit: s.unit }));
              }),
            a
          );
        }
        return null;
      },
    },
    {
      match: "^#Month+ #Value #Value+$",
      desc: "jan 5 8",
      parse: (e, t) => {
        let n = e.match("#Month"),
          r = e.match("#Year");
        e = e.not("#Year");
        let a = [];
        return (
          e.match("#Value").forEach((i) => {
            i = i.clone();
            let o = i.prepend(n.text());
            r.found && o.append(r);
            let s = E(o, t);
            s && a.push({ start: s, end: s.clone().end(), unit: s.unit });
          }),
          a
        );
      },
    },
    {
      match: "^#Value+ (or|and)? #Value of #Month #Year?$",
      desc: "5 or 8 of Jan",
      parse: (e, t) => {
        let n = e.match("#Month"),
          r = e.match("#Year");
        e = e.not("#Year");
        let a = [];
        return (
          e.match("#Value").forEach((i) => {
            let o = i.append(n);
            r.found && o.append(r);
            let s = E(o, t);
            s && a.push({ start: s, end: s.clone().end(), unit: s.unit });
          }),
          a
        );
      },
    },
    {
      match: "^!(between|from|during)? [<from>#Date+] (and|or) [<to>#Date+]$",
      desc: "A or B",
      parse: (e, t) => {
        let n = e.groups("from"),
          r = e.groups("to"),
          a = E(n, t),
          i = E(r, t);
        return a && i
          ? [
              { start: a, end: a.clone().end() },
              { start: i, end: i.clone().end() },
            ]
          : null;
      },
    },
  ],
  LP = [
    {
      match: "between [<start>.+] and [<end>.+]",
      desc: "between friday and sunday",
      parse: (e, t) => {
        let n = e.groups("start");
        n = E(n, t);
        let r = e.groups("end");
        return (
          (r = E(r, t)),
          n && r ? ((r = r.before()), { start: n, end: r }) : null
        );
      },
    },
    {
      match:
        "[<from>#Month #Value] (to|through|thru) [<to>#Month #Value] [<year>#Year?]",
      desc: "june 5 to june 7",
      parse: (e, t) => {
        let n = e.groups(),
          r = n.from;
        if ((n.year && (r = r.append(n.year)), (r = E(r, t)), r)) {
          let a = n.to;
          if ((n.year && (a = a.append(n.year)), (a = E(a, t)), a))
            return (
              r.d.isAfter(a.d) && (a.d = a.d.add(1, "year")),
              { start: r, end: a.end() }
            );
        }
        return null;
      },
    },
    {
      match:
        "[<month>#Month] [<from>#Value] (to|through|thru) [<to>#Value] of? [<year>#Year]",
      desc: "january 5 to 7 1998",
      parse: (e, t) => {
        let { month: n, from: r, to: a, year: i } = e.groups(),
          o = i.clone(),
          s = r.prepend(n).append(i);
        if (((s = E(s, t)), s)) {
          let l = a.prepend(n).append(o);
          return ((l = E(l, t)), { start: s, end: l.end() });
        }
        return null;
      },
    },
    {
      match: "[<from>#Value] (to|through|thru) [<to>#Value of? #Month #Date+?]",
      desc: "5 to 7 of january 1998",
      parse: (e, t) => {
        let n = e.groups("to");
        if (((n = E(n, t)), n)) {
          let r = e.groups("from"),
            a = n.clone();
          return (
            (a.d = a.d.date(r.text("implicit"))),
            { start: a, end: n.end() }
          );
        }
        return null;
      },
    },
    {
      match: "[<from>#Month #Value] (to|through|thru) [<to>#Value]",
      desc: "january 5 to 7",
      parse: (e, t) => {
        let n = e.groups("from");
        if (((n = E(n, t)), n)) {
          let r = e.groups("to"),
            a = n.clone();
          return (
            (a.d = a.d.date(r.text("implicit"))),
            { start: n, end: a.end() }
          );
        }
        return null;
      },
    },
    {
      match:
        "from? [<from>#Month] (to|until|upto|through|thru) [<to>#Month] [<year>#Year]",
      desc: "january to may 2020",
      parse: (e, t) => {
        let n = e.groups("from"),
          r = e.groups("year").numbers().get()[0],
          a = e.groups("to");
        if (
          ((n = E(n, t)),
          (a = E(a, t)),
          (n.d = n.d.year(r)),
          (a.d = a.d.year(r)),
          n && a)
        ) {
          let i = { start: n, end: a.end() };
          return ((i = Bn(i)), i);
        }
        return null;
      },
    },
  ],
  WP = function (e, t) {
    return ((e = e.applyShift(t.punt)), e);
  },
  qP = [
    {
      match: "from? [<from>.+] (to|until|upto|through|thru) [<to>.+]",
      desc: "from A to B",
      parse: (e, t) => {
        let n = e.groups("from"),
          r = e.groups("to");
        if (((n = E(n, t)), (r = E(r, t)), n && r)) {
          let a = { start: n, end: r.end() };
          return ((a = Bn(a)), a);
        }
        return null;
      },
    },
    {
      match: "^due? (by|before) [.+]",
      desc: "before june",
      parse: (e, t) => {
        e = e.group(0);
        let n = E(e, t);
        if (n) {
          let r = new fe(t.today, null, t);
          r.d.isAfter(n.d) && (r = n.clone().applyShift({ weeks: -2 }));
          let a = n.clone().applyShift({ day: -1 });
          return { start: r, end: a.end() };
        }
        return null;
      },
    },
    {
      match: "^(on|in|at|@|during) [.+]",
      desc: "in june",
      parse: (e, t) => {
        e = e.group(0);
        let n = E(e, t);
        return n ? { start: n, end: n.clone().end(), unit: n.unit } : null;
      },
    },
    {
      match: "^(after|following) [.+]",
      desc: "after june",
      parse: (e, t) => {
        e = e.group(0);
        let n = E(e, t);
        return n
          ? ((n = n.after()), { start: n.clone(), end: WP(n.clone(), t) })
          : null;
      },
    },
    {
      match: "^(middle|center|midpoint) of [.+]",
      desc: "middle of",
      parse: (e, t) => {
        e = e.group(0);
        let n = E(e, t),
          r = n.clone().middle(),
          a = n.beforeEnd();
        return n ? { start: r, end: a } : null;
      },
    },
    {
      match: ".+ after #Time+$",
      desc: "tuesday after 5pm",
      parse: (e, t) => {
        let n = E(e, t);
        if (n) {
          let r = n.clone(),
            a = n.end();
          return { start: r, end: a, unit: "time" };
        }
        return null;
      },
    },
    {
      match: ".+ before #Time+$",
      desc: "tuesday before noon",
      parse: (e, t) => {
        let n = E(e, t);
        if (n) {
          let r = n.clone(),
            a = n.start();
          if (n) return { start: a, end: r, unit: "time" };
        }
        return null;
      },
    },
  ];
var Yl = {};
const Ql = [].concat(MP, BP, LP, qP),
  KP = typeof Nt > "u" || !Yl ? self.env || {} : Yl,
  JP = (e) => {
    KP.DEBUG_DATE &&
      console.log(`
  \x1B[32m ${e} \x1B[0m`);
  },
  _P = function (e) {
    return Object.prototype.toString.call(e) === "[object Array]";
  },
  UP = function (e, t) {
    let n = { start: null, end: null };
    if (!e.found) return n;
    let r = E(e, t);
    if (r) {
      let a = r.clone().end();
      n = { start: r, end: a, unit: r.setTime ? "time" : r.unit };
    }
    return n;
  },
  RP = function (e, t) {
    for (let n = 0; n < Ql.length; n += 1) {
      let r = Ql[n],
        a = e.match(r.match);
      if (a.found) {
        JP(`  ---[${r.desc}]---`);
        let i = r.parse(a, t);
        if (i !== null) return (_P(i) || (i = [i]), i);
      }
    }
    return null;
  },
  YP = function (e, t) {
    let n = SP(e, t) || {},
      r = RP(e, t);
    return (
      r || (r = [UP(e, t)]),
      (r = r.map((a) => Object.assign({}, n, a))),
      r.forEach((a) => {
        a.start &&
          a.end &&
          a.start.d.epoch > a.end.d.epoch &&
          (a.start = a.start.start());
      }),
      r
    );
  },
  QP = function (e) {
    return (
      e.numbers ||
        console.warn(`
Compromise warning: compromise/three must be used with compromise-dates plugin
`),
      (e = e.clone()),
      e.numbers().toNumber(),
      e.contractions().expand(),
      e.replace("week end", "weekend", !0).tag("Date"),
      e.replace("up to", "upto", !0).tag("Date"),
      e.has("once (a|an) #Duration") === !1 &&
        e
          .match("[(a|an)] #Duration", 0)
          .replaceWith("1", { tags: !0 })
          .compute("lexicon"),
      e.match("@hasDash").insertAfter("to").tag("Date"),
      e
    );
  },
  St = function (e, t) {
    return (
      (t = t || {}),
      t.timezone === !1 && (t.timezone = "UTC"),
      (t.today = t.today || C.now(t.timezone)),
      (t.today = C(t.today, t.timezone)),
      (e = QP(e)),
      YP(e, t)
    );
  },
  ZP = function (e) {
    let n = e.end.d.add(1, "millisecond").since(e.start.d).diff;
    return (delete n.milliseconds, delete n.seconds, n);
  },
  Zl = function (e) {
    if (!e.start)
      return { start: null, end: null, timezone: null, duration: {} };
    let t = e.end ? ZP(e) : {};
    return {
      start: e.start.format("iso"),
      end: e.end ? e.end.format("iso") : null,
      timezone: e.start.d.format("timezone"),
      duration: t,
    };
  },
  Wa = function (e, t) {
    let n = e.fromText(t),
      r = St(n, e.opts)[0];
    return !r || !r.start || !r.start.d ? null : r.start.d;
  },
  XP = function (e) {
    class t extends e {
      constructor(r, a, i, o = {}) {
        (super(r, a, i),
          (this.viewType = "Dates"),
          (this.opts = Object.assign({}, o)));
      }
      get(r) {
        let a = [];
        return (
          this.forEach((i) => {
            St(i, this.opts).forEach((o) => {
              let s = Zl(o);
              s.start && a.push(s);
            });
          }),
          typeof r == "number" ? a[r] : a
        );
      }
      json(r = {}) {
        return this.map((a) => {
          let i = a.toView().json(r)[0] || {};
          if (r && r.dates !== !1) {
            let o = St(a, this.opts);
            i.dates = Zl(o[0]);
          }
          return i;
        }, []);
      }
      format(r) {
        let i = this.map((o) => {
          let s = St(o, this.opts)[0] || {};
          if (s.start) {
            let l = s.start.d,
              u = l.format(r);
            if (s.end) {
              let c = s.end.d;
              l.isSame(c, "day") === !1 && (u += " to " + c.format(r));
            }
            o.replaceWith(u);
          }
          return o;
        });
        return new t(this.document, i.pointer, null, this.opts);
      }
      isBefore(r) {
        let a = Wa(this, r);
        return this.filter((i) => {
          let o = St(i, this.opts)[0] || {};
          return o.start && o.start.d && o.start.d.isBefore(a);
        });
      }
      isAfter(r) {
        let a = Wa(this, r);
        return this.filter((i) => {
          let o = St(i, this.opts)[0] || {};
          return o.start && o.start.d && o.start.d.isAfter(a);
        });
      }
      isSame(r, a) {
        let i = Wa(this, a);
        return this.filter((o) => {
          let s = St(o, this.opts)[0] || {};
          return s.start && s.start.d && s.start.d.isSame(i, r);
        });
      }
    }
    e.prototype.dates = function (n) {
      let r = _2(this);
      return new t(this.document, r.pointer, null, n);
    };
  },
  eA = function (e) {
    e = e.clone();
    let t = e
      .match("#Time+")
      .match("[<hour>#Cardinal] [<min>(thirty|fifteen)]");
    if (t.found) {
      let n = t.groups("hour"),
        r = t.groups("min"),
        a = n.values().get()[0];
      if (a > 0 && a <= 12) {
        let i = r.values().get()[0],
          o = `${a}:${i}`;
        t.replaceWith(o);
      }
    }
    if (!e.numbers)
      console.warn(`Warning: compromise .numbers() not loaded.
   This plugin requires >= v14`);
    else {
      let n = e.numbers();
      (n.toNumber(), n.toCardinal(!1));
    }
    return (
      e.contractions && e.contractions().expand(),
      e.adverbs().remove(),
      e.replace("week end", "weekend", !0).tag("Date"),
      e.replace("up to", "upto", !0).tag("Date"),
      e.has("once (a|an) #Duration") === !1 &&
        e.match("[(a|an)] #Duration", 0).replaceWith("1").compute("lexicon"),
      e.match("@hasDash").insertAfter("to").tag("Date"),
      e
    );
  },
  tA = function (e) {
    return e.match("#Time+ (am|pm)?");
  },
  qa = function (e, t = {}) {
    e = eA(e);
    let n = io(e, t);
    if (!n.result) return { time: null, "24h": null };
    let r = C.now().time(n.result);
    return {
      time: n.result,
      "24h": r.format("time-24"),
      hour: r.hour(),
      minute: r.minute(),
    };
  },
  Xl = (e, t) => (typeof t == "number" ? e.eq(t) : e),
  nA = function (e) {
    class t extends e {
      constructor(r, a, i, o) {
        (super(r, a, i), (this.viewType = "Times"), (this.opts = o || {}));
      }
      format(r) {
        let i = this.map((o) => {
          let s = qa(o) || {};
          if (s.time) {
            let l = C.now().time(s.time),
              u = s.time;
            (r === "24h" ? (u = l.format("time-24")) : (u = l.format(r)),
              (o = o.not("#Preposition")),
              o.replaceWith(u));
          }
          return o;
        });
        return new t(this.document, i.pointer, null, this.opts);
      }
      get(r) {
        return Xl(this, r).map(qa);
      }
      json(r = {}) {
        return this.map((a) => {
          let i = a.toView().json(r)[0] || {};
          return (r && r.time !== !1 && (i.time = qa(a)), i);
        }, []);
      }
    }
    e.prototype.times = function (n) {
      let r = tA(this);
      return ((r = Xl(r, n)), new t(this.document, r.pointer));
    };
  },
  eu = {
    century: !0,
    day: !0,
    decade: !0,
    hour: !0,
    millisecond: !0,
    minute: !0,
    month: !0,
    second: !0,
    weekend: !0,
    week: !0,
    year: !0,
    quarter: !0,
    season: !0,
  };
let Jt = {
  m: "minute",
  h: "hour",
  hr: "hour",
  min: "minute",
  sec: "second",
  "week end": "weekend",
  wk: "week",
  yr: "year",
  qtr: "quarter",
};
Object.keys(Jt).forEach((e) => {
  Jt[e + "s"] = Jt[e];
});
const tu = function (e) {
    let t = {},
      n = e.match("#Value+ #Duration");
    if (n.found)
      n.forEach((r) => {
        let a = r.numbers().get()[0],
          i = r.terms().last().text("reduced");
        ((i = i.replace(/ies$/, "y")),
          (i = i.replace(/s$/, "")),
          Jt.hasOwnProperty(i) && (i = Jt[i]),
          eu.hasOwnProperty(i) && a !== null && (t[i] = a));
      });
    else if (e.match("(#Duration && /[0-9][a-z]+$/)").found) {
      let a = e.text(),
        i = a.match(/([0-9]+)/),
        o = a.match(/([a-z]+)/);
      i &&
        o &&
        ((i = i[0] || null),
        (o = o[0] || null),
        Jt.hasOwnProperty(o) && (o = Jt[o]),
        eu.hasOwnProperty(o) && i !== null && (t[o] = Number(i)));
    }
    return t;
  },
  rA = function (e) {
    class t extends e {
      constructor(r, a, i) {
        (super(r, a, i), (this.context = {}));
      }
      json(r = {}) {
        return this.map((a) => {
          let i = a.toView().json(r)[0] || {};
          return (r && r.duration !== !1 && (i.duration = tu(a)), i);
        }, []);
      }
      get(r) {
        let a = [];
        return (
          this.forEach((i) => {
            let o = tu(i);
            a.push(o);
          }),
          typeof r == "number" ? a[r] : a
        );
      }
    }
    e.prototype.durations = function (n) {
      let r = this.match("#Value+ #Duration (and? #Value+ #Duration)?");
      return (
        (r = r.notIf("#DateShift")),
        typeof n == "number" && (r = r.eq(n)),
        new t(this.document, r.pointer)
      );
    };
  },
  aA = function (e) {
    (XP(e), nA(e), rA(e));
  },
  nu = "(start|end|middle|starting|ending|midpoint|beginning)",
  rt = (e, t) => {
    e.found === !0 &&
      e.forEach((n) => {
        let r = n.text("reduced"),
          a = parseInt(r, 10);
        a && a > 1e3 && a < 3e3 && n.tag("Year", t);
      });
  },
  Mr = (e, t) => {
    e.found === !0 &&
      e.forEach((n) => {
        let r = n.text("reduced"),
          a = parseInt(r, 10);
        a && a > 1900 && a < 2030 && n.tag("Year", t);
      });
  },
  iA = function (e) {
    e.match("(march|april|may) (and|to|or|through|until)? (march|april|may)")
      .tag("Date")
      .match("(march|april|may)")
      .tag("Month", "march|april|may");
    let t = e.if("#Cardinal");
    if (t.found === !0) {
      let r = t.match("#Date #Value [#Cardinal]", 0);
      (rt(r, "date-value-year"),
        (r = t.match("#Date [#Cardinal]", 0)),
        Mr(r, "date-year"),
        (r = t.match(`${nu} of [#Cardinal]`)),
        Mr(r, "section-year"),
        (r = t.match("#Month #Value [#Cardinal]", 0)),
        rt(r, "month-value-year"),
        (r = t.match("#Month #Value to #Value [#Cardinal]", 0)),
        rt(r, "month-range-year"),
        (r = t.match(
          "(in|of|by|during|before|starting|ending|for|year|since) [#Cardinal]",
          0,
        )),
        rt(r, "in-year-1"),
        (r = t.match("(q1|q2|q3|q4) [#Cardinal]", 0)),
        rt(r, "in-year-2"),
        (r = t.match("#Ordinal quarter of? [#Cardinal]", 0)),
        rt(r, "in-year-3"),
        (r = t.match("the year [#Cardinal]", 0)),
        rt(r, "in-year-4"),
        (r = t.match("it (is|was) [#Cardinal]", 0)),
        Mr(r, "in-year-5"),
        t.match(`${nu} of #Year`).tag("Date"));
      let a = t.match("between [#Cardinal] and [#Cardinal]");
      (rt(a.groups("0"), "between-year-and-year-1"),
        rt(a.groups("1"), "between-year-and-year-2"));
    }
    let n = e.match("^/^20[012][0-9]$/$");
    return (Mr(n, "2020-ish"), e);
  },
  De = function (e, t) {
    e.found &&
      (e.tag("Date", t),
      e.numbers().lessThan(31).ifNo("#Year").tag("#Time", t));
  },
  oA = function (e) {
    let t = e.if("#Date");
    if (t.found) {
      let n = t.if("#NumberRange");
      if (n.found) {
        let a = n.match("[#NumberRange+] (on|by|at)? #WeekDay", 0);
        (De(a, "3-4-tuesday"),
          (a = n.match("[#NumberRange+] (on|by|at)? #Month #Value", 0)),
          De(a, "3-4 mar 3"),
          (a = n.match("[#NumberRange] to (#NumberRange && #Time)", 0)),
          De(a, "3-4pm"),
          (a = n.match("(#NumberRange && #Time) to [#NumberRange]", 0)),
          De(a, "3pm-4"));
      }
      let r = t.match(
        "(from|between) #Cardinal and #Cardinal (in|on)? (#WeekDay|tomorrow|yesterday)",
      );
      (De(r, "from 9-5 tues"),
        (r = e.match("#Cardinal to #Cardinal (#WeekDay|tomorrow|yesterday)")),
        De(r, "9-5 tues"),
        (r = t
          .match("(from|between) [#NumericValue] (to|and) #Time", 0)
          .tag("Time", "4-to-5pm")),
        De(r, "from 9-5pm"),
        (r = t.match(
          "(#WeekDay|tomorrow|yesterday) (from|between)? (#Cardinal|#Time) (and|to) (#Cardinal|#Time)",
        )),
        De(r, "tues 3-5"),
        (r = t
          .match(
            "#Month #Value+ (from|between) [<time>(#Cardinal|#Time) (and|to) (#Cardinal|#Time)]",
          )
          .group("time")),
        De(r, "sep 4 from 9-5"),
        (r = t.match("#Time to #Cardinal on? #Date")),
        De(r, "3pm-4 wed"),
        (r = t.match("#Cardinal to #Time on? #Date")),
        De(r, "3-4pm wed"),
        (r = t.match("#Cardinal to #Cardinal on? (#WeekDay|#Month #Value)")),
        De(r, "3-4 wed"));
    }
    return e;
  },
  sA = [
    "act",
    "aft",
    "akst",
    "anat",
    "art",
    "azot",
    "azt",
    "bnt",
    "bot",
    "bt",
    "cast",
    "cat",
    "cct",
    "chast",
    "chut",
    "ckt",
    "cvt",
    "cxt",
    "davt",
    "eat",
    "ect",
    "fjt",
    "fkst",
    "fnt",
    "gamt",
    "get",
    "gft",
    "gilt",
    "gyt",
    "hast",
    "hncu",
    "hneg",
    "hnnomx",
    "hnog",
    "hnpm",
    "hnpmx",
    "hntn",
    "hovt",
    "iot",
    "irkt",
    "jst",
    "kgt",
    "kost",
    "lint",
    "magt",
    "mart",
    "mawt",
    "mmt",
    "nct",
    "nft",
    "novt",
    "npt",
    "nrt",
    "nut",
    "nzst",
    "omst",
    "pet",
    "pett",
    "phot",
    "phst",
    "pont",
    "pwt",
    "ret",
    "sakt",
    "samt",
    "sbt",
    "sct",
    "sret",
    "srt",
    "syot",
    "taht",
    "tft",
    "tjt",
    "tkt",
    "tlt",
    "tmt",
    "tot",
    "tvt",
    "ulat",
    "vut",
    "wakt",
    "wat",
    "wet",
    "wft",
    "wit",
    "wst",
    "yekt",
  ].reduce((e, t) => ((e[t] = !0), e), {}),
  lA = function (e) {
    let t = e.match("#Time [#Acronym]", 0);
    if (t.found) {
      let n = t.text("reduced");
      sA[n] === !0 && t.tag("Timezone", "tz-abbr");
    }
  },
  uA = "fix-tagger",
  cA = function (e) {
    if (e.has("#Date")) {
      let t = e.match("#Date+ by #Date+");
      t.found &&
        !t.has("^due") &&
        t.match("^#Date+").unTag("Date", "by-monday");
      let n = e.match("#Date+");
      (n.has("^between") && !n.has("and .") && n.unTag("Date", uA),
        n.has("(minutes|seconds|weeks|hours|days|months)") &&
          !n.has("#Value #Duration") &&
          n
            .match("(minutes|seconds|weeks|hours|days|months)")
            .unTag("Date", "log-hours"),
        n.has("about #Holiday") &&
          n.match("about").unTag("#Date", "about-thanksgiving"),
        n.match("#Date+").match("^the").unTag("Date"));
    }
    return e;
  },
  Ka = "(in|by|before|during|on|until|after|of|within|all)",
  ru = "(last|next|this|previous|current|upcoming|coming)",
  Ja = "(start|end|middle|starting|ending|midpoint|beginning|mid)",
  _a = "(spring|summer|winter|fall|autumn)",
  au = "(yesterday|today|tomorrow)";
let hA = [
    {
      match: "in the (night|evening|morning|afternoon|day|daytime)",
      tag: "Time",
      reason: "in-the-night",
    },
    { match: "(#Value|#Time) (am|pm)", tag: "Time", reason: "value-ampm" },
    { match: "(tue|thu)", tag: "WeekDay", reason: "misc-weekday" },
    { match: "#Month #Date+", tag: "Date", reason: "correction-numberRange" },
    {
      match: "#Value of #Month",
      tag: "Date",
      unTag: "Time",
      reason: "value-of-month",
    },
    { match: "#Cardinal #Month", tag: "Date", reason: "cardinal-month" },
    {
      match: "#Month #Value (and|or|to)? #Value+",
      tag: "Date",
      reason: "value-to-value",
    },
    { match: "#Month the #Value", tag: "Date", reason: "month-the-value" },
    {
      match: "[(march|may)] to? #Date",
      group: 0,
      tag: "Month",
      reason: "march-to",
    },
    { match: "^(march|may)$", tag: "Month", reason: "single-march" },
    { match: "#Month or #Month", tag: "Date", reason: "month-or-month" },
    {
      match: "(#WeekDay|#Month) #Value",
      ifNo: "#Money",
      tag: "Date",
      reason: "date-value",
    },
    {
      match: "#Value (#WeekDay|#Month)",
      ifNo: "#Money",
      tag: "Date",
      reason: "value-date",
    },
    {
      match: "#Value (#WeekDay|#Duration) back",
      tag: "#Date",
      reason: "3-back",
    },
    { match: "for #Value #Duration", tag: "Date", reason: "for-x-duration" },
    {
      match: "#Value #Duration #Conjunction",
      tag: "Date",
      reason: "val-duration-conjunction",
    },
    { match: `${Ka}? #Value #Duration`, tag: "Date", reason: "value-duration" },
    {
      match: "in? #Value to #Value #Duration time?",
      tag: "Date",
      reason: "6-to-8-years",
    },
    { match: "#Value #Duration old", unTag: "Date", reason: "val-years-old" },
    { match: `${Ka}? ${ru} ${_a}`, tag: "Date", reason: "thisNext-season" },
    { match: `the? ${Ja} of ${_a}`, tag: "Date", reason: "section-season" },
    { match: `${_a} ${Ka}? #Cardinal`, tag: "Date", reason: "season-year" },
    { match: "#Date the? #Ordinal", tag: "Date", reason: "correction" },
    { match: `${ru} #Date`, tag: "Date", reason: "thisNext-date" },
    { match: "due? (by|before|after|until) #Date", tag: "Date", reason: "by" },
    {
      match: "(last|next|this|previous|current|upcoming|coming|the) #Date",
      tag: "Date",
      reason: "next-feb",
    },
    {
      match: `#Preposition? the? ${Ja} of #Date`,
      tag: "Date",
      reason: "section-of",
    },
    {
      match: "#Ordinal #Duration in #Date",
      tag: "Date",
      reason: "duration-in",
    },
    {
      match: "(early|late) (at|in)? the? #Date",
      tag: "Time",
      reason: "early-evening",
    },
    {
      match: "#Date [(by|before|after|at|@|about) #Cardinal]",
      group: 0,
      tag: "Time",
      reason: "date-before-Cardinal",
    },
    {
      match: "#Date (#Preposition|to) #Date",
      ifNo: "#Duration",
      tag: "Date",
      reason: "date-prep-date",
    },
    {
      match: "(by|before|after|at|@|about) #Time",
      tag: "Time",
      reason: "preposition-time",
    },
    {
      match: "(in|after) /^[0-9]+(min|sec|wk)s?/",
      tag: "Date",
      reason: "shift-units",
    },
    {
      match: "#Date [(now|night|sometime)]",
      group: 0,
      tag: "Time",
      reason: "date-now",
    },
    { match: "(from|starting|until|by) now", tag: "Date", reason: "for-now" },
    { match: "(each|every) night", tag: "Date", reason: "for-now" },
    { match: "#Date [(am|pm)]", group: 0, tag: "Time", reason: "date-am" },
    { match: `[${Ja}] #Date`, group: 0, tag: "Date", reason: "mid-sept" },
    {
      match: "#Month #Value to #Value of? #Year?",
      tag: "Date",
      reason: "june 5 to 7th",
    },
    {
      match: "#Value to #Value of? #Month #Year?",
      tag: "Date",
      reason: "5 to 7th june",
    },
    {
      match: "#Value #Duration of #Date",
      tag: "Date",
      reason: "third week of may",
    },
    {
      match: "#Value+ #Duration (after|before|into|later|afterwards|ago)?",
      tag: "Date",
      reason: "two days after",
    },
    { match: "#Value #Date", tag: "Date", reason: "two days" },
    { match: "#Date #Value", tag: "Date", reason: "june 5th" },
    { match: "#Date #Preposition #Value", tag: "Date", reason: "tuesday at 5" },
    {
      match: "#Date (after|before|during|on|in) #Value",
      tag: "Date",
      reason: "tomorrow before 3",
    },
    {
      match: "#Value (year|month|week|day) and a half",
      tag: "Date",
      reason: "a year and a half",
    },
    {
      match: "#Value and a half (years|months|weeks|days)",
      tag: "Date",
      reason: "5 and a half years",
    },
    { match: "on the #Ordinal", tag: "Date", reason: "on the fifth" },
    {
      match: "#Month #Value+ (and|or) #Value",
      tag: "Date",
      reason: "date-or-date",
    },
    {
      match: "#Value+ (and|or) #Value of #Month ",
      tag: "Date",
      reason: "date-and-date",
    },
    {
      match:
        "(spring|summer|winter|fall|autumn|springtime|wintertime|summertime)",
      tag: "Season",
      reason: "date-tag1",
    },
    { match: "(q1|q2|q3|q4)", tag: "FinancialQuarter", reason: "date-tag2" },
    {
      match: "(this|next|last|current) quarter",
      tag: "FinancialQuarter",
      reason: "date-tag3",
    },
    {
      match: "(this|next|last|current) season",
      tag: "Season",
      reason: "date-tag4",
    },
    {
      match: "#Date #Preposition #Date",
      tag: "Date",
      reason: "friday to sunday",
    },
    {
      match: "(once|twice) (a|an|each) #Date",
      tag: "Date",
      reason: "once a day",
    },
    { match: "a #Duration", tag: "Date", reason: "a year" },
    { match: "(between|from) #Date", tag: "Date", reason: "between x and y" },
    { match: "(to|until|upto) #Date", tag: "Date", reason: "between x and y2" },
    {
      match: "between #Date+ and #Date+",
      tag: "Date",
      reason: "between x and y3",
    },
    { match: "#Month and #Month #Year", tag: "Date", reason: "x and y4" },
    {
      match: "the? #Date after next one?",
      tag: "Date",
      reason: "day after next",
    },
    {
      match: "(about|approx|approximately|around) #Date",
      tag: "Date",
      reason: "approximately june",
    },
    {
      match: "(by|until|on|in|at|during|over|every|each|due) the? #Date",
      ifNo: "#PhrasalVerb",
      tag: "Date",
      reason: "until june",
    },
    {
      match:
        "(by|until|after|before|during|on|in|following|since) (next|this|last)? #Date",
      ifNo: "#PhrasalVerb",
      tag: "Date",
      reason: "until last june",
    },
    {
      match:
        "this? (last|next|past|this|previous|current|upcoming|coming|the) #Date",
      tag: "Date",
      reason: "next september",
    },
    {
      match: "(starting|beginning|ending) #Date",
      tag: "Date",
      reason: "starting this june",
    },
    {
      match: "the? (start|end|middle|beginning) of (last|next|this|the) #Date",
      tag: "Date",
      reason: "start of june",
    },
    { match: "(the|this) #Date", tag: "Date", reason: "this coming june" },
    { match: "#Date up to #Date", tag: "Date", reason: "january up to june" },
    { match: "#Cardinal oclock", tag: "Time", reason: "2 oclock" },
    {
      match: "#Value (in|at) the? (morning|evening|night|nighttime)",
      tag: "Time",
      reason: "3 in the morning",
    },
    {
      match:
        "(5|10|15|20|five|ten|fifteen|quarter|twenty|half) (after|past) #Cardinal",
      tag: "Time",
      reason: "ten to seven",
    },
    {
      match:
        "(at|by|before) (5|10|15|20|five|ten|fifteen|twenty|quarter|half) (after|past|to)",
      tag: "Time",
      reason: "at-20-past",
    },
    {
      match: "#Date [at #Cardinal]",
      group: 0,
      ifNo: "#Year",
      tag: "Time",
      reason: " tuesday at 4",
    },
    {
      match: "half an (hour|minute|second)",
      tag: "Date",
      reason: "half an hour",
    },
    {
      match: "(in|for|by|near|at) #Timezone",
      tag: "Date",
      reason: "in eastern time",
    },
    { match: "#Time to #Time", tag: "Date", reason: "3pm to 4pm" },
    {
      match: "#Time [(sharp|on the dot)]",
      group: 0,
      tag: "Time",
      reason: "4pm sharp",
    },
    {
      match: "(at|around|near|#Date) [#Cardinal (thirty|fifteen) (am|pm)?]",
      group: 0,
      tag: "Time",
      reason: "around four thirty",
    },
    {
      match: "#Cardinal (thirty|fifteen) (am|pm)",
      tag: "Time",
      reason: "four thirty am",
    },
    {
      match: "[#Cardinal (thirty|fifteen)] #Date",
      group: 0,
      tag: "Time",
      reason: "four thirty tomorrow",
    },
    {
      match: "(anytime|sometime) (before|after|near) [#Cardinal]",
      group: 0,
      tag: "Time",
      reason: "antime-after-3",
    },
    {
      match: "(#Cardinal|a|an) #Duration (before|after|ago|from|hence|back)",
      tag: "DateShift",
      reason: "nine weeks frow now",
    },
    {
      match: "in (around|about|maybe|perhaps)? #Cardinal #Duration",
      tag: "DateShift",
      reason: "in two weeks",
    },
    { match: "in (a|an) #Duration", tag: "DateShift", reason: "in a week" },
    {
      match: "[(a|an) #Duration from] #Date",
      group: 0,
      tag: "DateShift",
      reason: "an hour from now",
    },
    { match: "(a|an) #Duration ago", tag: "DateShift", reason: "a month ago" },
    {
      match: "in half (a|an) #Duration",
      tag: "DateShift",
      reason: "in half an hour",
    },
    {
      match: "in a (few|couple) of? #Duration",
      tag: "DateShift",
      reason: "in a few weeks",
    },
    {
      match: "[#Duration (after|before)] #Date",
      group: 0,
      tag: "DateShift",
      reason: "day after tomorrow",
    },
    {
      match: "#Month #Ordinal and #Ordinal",
      tag: "Date",
      reason: "ord-and-ord",
    },
    { match: "every other #Duration", tag: "Date", reason: "every-other" },
    {
      match: "(every|any|each|a) (day|weekday|week day|weekend|weekend day)",
      tag: "Date",
      reason: "any-weekday",
    },
    {
      match: "(every|any|each|a) (#WeekDay)",
      tag: "Date",
      reason: "any-wednesday",
    },
    {
      match: "(every|any|each|a) (#Duration)",
      tag: "Date",
      reason: "any-week",
    },
    {
      match: "[(wed|sat)] (#Month|#Year|on|between|during|from)",
      group: 0,
      tag: "WeekDay",
      reason: "wed",
    },
    { match: "^day$", unTag: "Date", reason: "spa-day" },
    {
      match: "(in|of|by|for)? (#Possessive && #Date)",
      unTag: "Date",
      reason: "tomorrows meeting",
    },
    {
      match: `${au} [#Value]$`,
      unTag: "Date",
      group: 0,
      reason: "yesterday-7",
    },
    {
      match: `^[#Value] ${au}$`,
      group: 0,
      unTag: "Date",
      reason: "7 yesterday",
    },
    { match: "on #Cardinal$", unTag: "Date", reason: "on 5" },
    {
      match: "[this] tomorrow",
      group: 0,
      unTag: "Date",
      reason: "this-tomorrow",
    },
    { match: "(q1|q2|q3|q4) #Year", tag: "Date", reason: "q2 2016" },
    {
      match: "^[#Value] (this|next|last)",
      group: 0,
      unTag: "Date",
      reason: "4 next",
    },
    {
      match: "(last|this|next) #Duration [#Value]",
      group: 0,
      unTag: "Date",
      reason: "this month 7",
    },
    {
      match: "[!#Month] #Value (last|this|next) #Date",
      group: 0,
      unTag: "Date",
      reason: "7 this month",
    },
    {
      match: "(in|over) the #Duration #Date+?",
      unTag: "Date",
      reason: "over-the-duration",
    },
    { match: "#Ordinal quarter of? #Year", unTag: "Fraction" },
    { match: "(from|by|before) now", unTag: "Time", tag: "Date" },
  ],
  Ua = null;
const iu = function (e) {
    let { world: t } = e;
    ((Ua = Ua || t.methods.one.buildNet(hA, t)), e.sweep(Ua));
  },
  dA = function (e) {
    return (
      e.cache(),
      iu(e),
      iu(e),
      iA(e),
      oA(e),
      lA(e),
      cA(e),
      e.uncache(),
      e
        .match("#Cardinal #Duration and? #DateShift")
        .tag("DateShift", "three days before"),
      e
        .match("#DateShift and #Cardinal #Duration")
        .tag("DateShift", "three days and two weeks"),
      e.match("#Time [(sharp|on the dot)]").tag("Time", "4pm sharp"),
      e
    );
  },
  fA = { dates: dA },
  mA = {
    FinancialQuarter: { is: "Date", not: ["Fraction"] },
    Season: { is: "Date" },
    Year: { is: "Date", not: ["RomanNumeral"] },
    Holiday: { is: "Date", also: "Noun" },
    DateShift: { is: "Date", not: ["Timezone", "Holiday"] },
  },
  y = "America/",
  x = "Asia/",
  K = "Europe/",
  $e = "Africa/",
  ee = "Australia/",
  _e = "Pacific/",
  pA = {
    "british summer time": K + "London",
    bst: K + "London",
    "british time": K + "London",
    "britain time": K + "London",
    "irish summer time": K + "Dublin",
    "irish time": K + "Dublin",
    "central european time": K + "Berlin",
    cet: K + "Berlin",
    "central european summer time": K + "Berlin",
    cest: K + "Berlin",
    "central europe": K + "Berlin",
    "eastern european time": K + "Riga",
    eet: K + "Riga",
    "eastern european summer time": K + "Riga",
    eest: K + "Riga",
    "eastern europe time": K + "Riga",
    "western european time": K + "Lisbon",
    "western european summer time": K + "Lisbon",
    "turkey standard time": K + "Istanbul",
    "turkish time": K + "Istanbul",
    utc: $e + "Freetown",
    "greenwich standard time": $e + "Freetown",
    gmt: $e + "Freetown",
    "east africa time": $e + "Nairobi",
    "east african time": $e + "Nairobi",
    "eastern africa time": $e + "Nairobi",
    "central africa time": $e + "Khartoum",
    "central african time": $e + "Khartoum",
    "south africa standard time": $e + "Johannesburg",
    "west africa standard time": $e + "Lagos",
    "western africa time": $e + "Lagos",
    "west african time": $e + "Lagos",
    "australian central standard time": ee + "Adelaide",
    acst: ee + "Adelaide",
    "australian central daylight time": ee + "Adelaide",
    acdt: ee + "Adelaide",
    "australian eastern standard time": ee + "Brisbane",
    aest: ee + "Brisbane",
    "australian eastern daylight time": ee + "Brisbane",
    aedt: ee + "Brisbane",
    "australian western standard time": ee + "Perth",
    awst: ee + "Perth",
    "australian western daylight time": ee + "Perth",
    awdt: ee + "Perth",
    "australian central western standard time": ee + "Eucla",
    acwst: ee + "Eucla",
    "lord howe standard time": ee + "Lord_Howe",
    lhst: ee + "Lord_Howe",
    "lord howe daylight time": ee + "Lord_Howe",
    lhdt: ee + "Lord_Howe",
    "russian standard time": K + "Moscow",
    msk: K + "Moscow",
    "central standard time": y + "Chicago",
    "central time": y + "Chicago",
    cst: y + "Havana",
    "central daylight time": y + "Chicago",
    cdt: y + "Havana",
    "mountain standard time": y + "Denver",
    "mountain time": y + "Denver",
    mst: y + "Denver",
    "mountain daylight time": y + "Denver",
    mdt: y + "Denver",
    "atlantic standard time": y + "Halifax",
    "atlantic time": y + "Halifax",
    ast: x + "Baghdad",
    "atlantic daylight time": y + "Halifax",
    adt: y + "Halifax",
    "eastern standard time": y + "New_York",
    "eastern time": y + "New_York",
    est: y + "New_York",
    "eastern daylight time": y + "New_York",
    edt: y + "New_York",
    "pacific time": y + "Los_Angeles",
    "pacific standard time": y + "Los_Angeles",
    pst: y + "Los_Angeles",
    "pacific daylight time": y + "Los_Angeles",
    pdt: y + "Los_Angeles",
    "alaskan standard time": y + "Anchorage",
    "alaskan time": y + "Anchorage",
    ahst: y + "Anchorage",
    "alaskan daylight time": y + "Anchorage",
    ahdt: y + "Anchorage",
    "hawaiian standard time": _e + "Honolulu",
    "hawaiian time": _e + "Honolulu",
    hst: _e + "Honolulu",
    "aleutian time": _e + "Honolulu",
    "hawaii time": _e + "Honolulu",
    "newfoundland standard time": y + "St_Johns",
    "newfoundland time": y + "St_Johns",
    "newfoundland daylight time": y + "St_Johns",
    "brazil time": y + "Sao_Paulo",
    "brazilian time": y + "Sao_Paulo",
    "argentina time": y + "Buenos_Aires",
    "argentinian time": y + "Buenos_Aires",
    "amazon time": y + "Manaus",
    "amazonian time": y + "Manaus",
    "easter island standard time": "Chile/Easterisland",
    "easter island summer time": "Chile/Easterisland",
    easst: "Chile/Easterisland",
    "venezuelan standard time": y + "Caracas",
    "venezuelan time": y + "Caracas",
    "venezuela time": y + "Caracas",
    "paraguay time": y + "Asuncion",
    "paraguay summer time": y + "Asuncion",
    "cuba standard time": y + "Havana",
    "cuba time": y + "Havana",
    "cuba daylight time": y + "Havana",
    "cuban time": y + "Havana",
    "bolivia time": y + "La_Paz",
    "bolivian time": y + "La_Paz",
    "colombia time": y + "Bogota",
    "colombian time": y + "Bogota",
    "acre time": y + "Eirunepe",
    "peru time": y + "Lima",
    "chile standard time": y + "Punta_Arenas",
    "chile time": y + "Punta_Arenas",
    clst: y + "Punta_Arenas",
    "chile summer time": y + "Punta_Arenas",
    cldt: y + "Punta_Arenas",
    "uruguay time": y + "Montevideo",
    uyt: y + "Montevideo",
    "arabic standard time": x + "Baghdad",
    "iran standard time": x + "Tehran",
    "iran time": x + "Tehran",
    "iran daylight time": x + "Tehran",
    "pakistan standard time": x + "Karachi",
    "pakistan time": x + "Karachi",
    "india standard time": x + "Kolkata",
    "indian time": x + "Kolkata",
    "indochina time": x + "Bangkok",
    "china standard time": x + "Shanghai",
    "alma-ata time": x + "Almaty",
    "oral time": x + "Oral",
    "orat time": x + "Oral",
    "yakutsk time": x + "Yakutsk",
    yakt: x + "Yakutsk",
    "gulf standard time": x + "Dubai",
    "gulf time": x + "Dubai",
    "hong kong time": x + "Hong_Kong",
    "western indonesian time": x + "Jakarta",
    "indonesia time": x + "Jakarta",
    "central indonesian time": x + "Makassar",
    "israel daylight time": x + "Jerusalem",
    "israel standard time": x + "Jerusalem",
    "israel time": x + "Jerusalem",
    "krasnoyarsk time": x + "Krasnoyarsk",
    "malaysia time": x + "Kuala_Lumpur",
    "singapore time": x + "Singapore",
    "korea standard time": x + "Seoul",
    "korea time": x + "Seoul",
    kst: x + "Seoul",
    "korean time": x + "Seoul",
    "uzbekistan time": x + "Samarkand",
    "vladivostok time": x + "Vladivostok",
    "maldives time": "Indian/Maldives",
    "mauritius time": "Indian/Mauritius",
    "marshall islands time": _e + "Kwajalein",
    "samoa standard time": _e + "Midway",
    "somoan time": _e + "Midway",
    "chamorro standard time": _e + "Guam",
    "papua new guinea time": _e + "Bougainville",
  };
let gA = C().timezones,
  yA = Object.keys(gA).reduce((e, t) => ((e[t] = t), e), {});
const bA = Object.assign({}, pA, yA),
  vA = [
    "weekday",
    "summer",
    "winter",
    "autumn",
    "all day",
    "eod",
    "eom",
    "eoy",
    "standard time",
    "daylight time",
    "tommorrow",
  ],
  wA = [
    "centuries",
    "century",
    "day",
    "days",
    "decade",
    "decades",
    "hour",
    "hours",
    "hr",
    "hrs",
    "millisecond",
    "milliseconds",
    "minute",
    "minutes",
    "min",
    "mins",
    "month",
    "months",
    "seconds",
    "sec",
    "secs",
    "week end",
    "week ends",
    "weekend",
    "weekends",
    "week",
    "weeks",
    "wk",
    "wks",
    "year",
    "years",
    "yr",
    "yrs",
    "quarter",
    "qtr",
    "qtrs",
    "season",
    "seasons",
  ],
  kA = [
    "all hallows eve",
    "all saints day",
    "all sts day",
    "april fools",
    "armistice day",
    "australia day",
    "bastille day",
    "boxing day",
    "canada day",
    "christmas eve",
    "christmas",
    "cinco de mayo",
    "day of the dead",
    "dia de muertos",
    "dieciseis de septiembre",
    "emancipation day",
    "grito de dolores",
    "groundhog day",
    "halloween",
    "harvey milk day",
    "inauguration day",
    "independence day",
    "independents day",
    "juneteenth",
    "labour day",
    "national freedom day",
    "national nurses day",
    "new years eve",
    "new years",
    "purple heart day",
    "rememberance day",
    "rosa parks day",
    "saint andrews day",
    "saint patricks day",
    "saint stephens day",
    "saint valentines day",
    "st andrews day",
    "st patricks day",
    "st stephens day",
    "st valentines day ",
    "valentines day",
    "valentines",
    "veterans day",
    "victoria day",
    "womens equality day",
    "xmas",
    "epiphany",
    "orthodox christmas day",
    "orthodox new year",
    "assumption of mary",
    "all souls day",
    "feast of the immaculate conception",
    "feast of our lady of guadalupe",
    "kwanzaa",
    "imbolc",
    "beltaine",
    "lughnassadh",
    "samhain",
    "martin luther king day",
    "mlk day",
    "presidents day",
    "mardi gras",
    "tax day",
    "commonwealth day",
    "mothers day",
    "memorial day",
    "fathers day",
    "columbus day",
    "indigenous peoples day",
    "canadian thanksgiving",
    "election day",
    "thanksgiving",
    "t-day",
    "turkey day",
    "black friday",
    "cyber monday",
    "ash wednesday",
    "palm sunday",
    "maundy thursday",
    "good friday",
    "holy saturday",
    "easter",
    "easter sunday",
    "easter monday",
    "orthodox good friday",
    "orthodox holy saturday",
    "orthodox easter",
    "orthodox easter monday",
    "ascension day",
    "pentecost",
    "whitsunday",
    "whit sunday",
    "whit monday",
    "trinity sunday",
    "corpus christi",
    "advent",
    "tu bishvat",
    "tu bshevat",
    "purim",
    "passover",
    "yom hashoah",
    "lag baomer",
    "shavuot",
    "tisha bav",
    "rosh hashana",
    "yom kippur",
    "sukkot",
    "shmini atzeret",
    "simchat torah",
    "chanukah",
    "hanukkah",
    "isra and miraj",
    "lailat al-qadr",
    "eid al-fitr",
    "id al-Fitr",
    "eid ul-Fitr",
    "ramadan",
    "eid al-adha",
    "muharram",
    "the prophets birthday",
    "ostara",
    "march equinox",
    "vernal equinox",
    "litha",
    "june solistice",
    "summer solistice",
    "mabon",
    "september equinox",
    "fall equinox",
    "autumnal equinox",
    "yule",
    "december solstice",
    "winter solstice",
    "chinese new year",
    "diwali",
  ],
  PA = [
    "noon",
    "midnight",
    "morning",
    "tonight",
    "evening",
    "afternoon",
    "breakfast time",
    "lunchtime",
    "dinnertime",
    "midday",
    "eod",
    "oclock",
    "oclock",
    "at night",
  ];
let xc = { "a couple": "Value", thur: "WeekDay", thurs: "WeekDay" };
const nr = function (e, t) {
  e.forEach((n) => {
    xc[n] = t;
  });
};
nr(Object.keys(bA), "Timezone");
nr(vA, "Date");
nr(wA, "Duration");
nr(kA, "Holiday");
nr(PA, "Time");
const AA = [
    [/^[0-9]+(min|sec|hr|d)s?$/i, "Duration", "30min"],
    [/^[0-9]{4}-[0-9]{2}$/, "Date", "2012-06"],
    [/^[0-9]{2}h[0-9]{2}$/i, "Time", "13h30"],
    [/^@[0-9]+:[0-9]{2}$/, "Time", "@5:30"],
    [/^@[1-9]+(am|pm)$/, "Time", "@5pm"],
    [/^(?:0[1-9]|[12]\d|3[01])\/(?:0[1-9]|[12]\d|3[01])$/, "Date", "03/02"],
  ],
  xA = "3.6.0",
  ou = (e) => (e ? C(e).format("{nice-day} {year}") : "-"),
  Hn = "\x1B[0m",
  Ra = {
    magenta: (e) => "\x1B[35m" + e + Hn,
    cyan: (e) => "\x1B[36m" + e + Hn,
    yellow: (e) => "\x1B[33m" + e + Hn,
    dim: (e) => "\x1B[2m" + e + Hn,
    i: (e) => "\x1B[3m" + e + Hn,
  },
  CA = function (e) {
    e.dates().forEach((t) => {
      let n = t.dates().get()[0];
      (console.log(`
────────`),
        t.debug("highlight"));
      let r = "";
      (n && n.start && (r = "   " + Ra.magenta(ou(n.start))),
        n && n.end && (r += Ra.dim("   →   ") + Ra.cyan(ou(n.end))),
        console.log(
          r +
            `
`,
        ));
    });
  },
  DA = {
    tags: mA,
    words: xc,
    compute: fA,
    api: aA,
    mutate: (e) => {
      ((e.model.two.regexText = e.model.two.regexText || []),
        (e.model.two.regexText = e.model.two.regexText.concat(AA)),
        (e.methods.one.debug = e.methods.one.debug || {}),
        (e.methods.one.debug.dates = CA));
    },
    hooks: ["dates"],
    version: xA,
  };
var $A = function (e, t) {
  let n = e.match("#Value+? #Money+ #Currency+ (and #Money+ #Currency+)+?");
  return (
    e.match("#Money").forEach((r) => {
      r.lookAfter("#Currency").found || (n = n.concat(r));
    }),
    typeof t == "number" && (n = n.get(t)),
    n
  );
};
const bt = "twenty|thirty|forty|fifty|sixty|seventy|eighty|ninety|fourty";
var jA = function (e, t) {
    let n = e.match("#Value+");
    if (
      (n.has("#NumericValue #NumericValue") &&
        (n.has("#Value @hasComma #Value")
          ? n.splitAfter("@hasComma")
          : n.has("#NumericValue #Fraction")
            ? n.splitAfter("#NumericValue #Fraction")
            : (n = n.splitAfter("#NumericValue"))),
      n.has("#Value #Value #Value") &&
        !n.has("#Multiple") &&
        n.has("(" + bt + ") #Cardinal #Cardinal") &&
        (n = n.splitAfter("(" + bt + ") #Cardinal")),
      n.has("#Value #Value"))
    ) {
      (n.has("#NumericValue #NumericValue") && (n = n.splitOn("#Year")),
        n.has(
          "(" +
            bt +
            ") (eleven|twelve|thirteen|fourteen|fifteen|sixteen|seventeen|eighteen|nineteen)",
        ) && (n = n.splitAfter("(" + bt + ")")));
      let r = n.match("#Cardinal #Cardinal");
      if (
        r.found &&
        !n.has("(point|decimal|#Fraction)") &&
        !r.has("#Cardinal (#Multiple|point|decimal)")
      ) {
        let a = n.has(`(one|two|three|four|five|six|seven|eight|nine) (${bt})`),
          i = r.has("(" + bt + ") #Cardinal"),
          o = r.has("#Multiple #Value");
        a ||
          i ||
          o ||
          r.terms().forEach((s) => {
            n = n.splitOn(s);
          });
      }
      (n.match("#Ordinal #Ordinal").match("#TextValue").found &&
        !n.has("#Multiple") &&
        (n.has("(" + bt + ") #Ordinal") || (n = n.splitAfter("#Ordinal"))),
        n.has("#Ordinal #Cardinal") && (n = n.splitBefore("#Cardinal+")),
        n.has("#TextValue #NumericValue") &&
          !n.has("(" + bt + "|#Multiple)") &&
          (n = n.splitBefore("#NumericValue+")));
    }
    return (
      n.has("#NumberRange") && (n = n.splitAfter("#NumberRange")),
      typeof t == "number" && (n = n.get(t)),
      n
    );
  },
  NA = function (e, t) {
    let n = e.match("#Fraction+");
    return (
      (n = n.filter((r) => !r.lookBehind("#Value and$").found)),
      typeof t == "number" && (n = n.eq(t)),
      n
    );
  },
  TA = function (e, t) {
    let n = e.match("#Percent+");
    return (
      (n = n.concat(e.match("[#Cardinal] percent", 0))),
      typeof t == "number" && (n = n.eq(t)),
      n
    );
  },
  so = {
    ones: {
      zeroth: 0,
      first: 1,
      second: 2,
      third: 3,
      fourth: 4,
      fifth: 5,
      sixth: 6,
      seventh: 7,
      eighth: 8,
      ninth: 9,
      zero: 0,
      one: 1,
      two: 2,
      three: 3,
      four: 4,
      five: 5,
      six: 6,
      seven: 7,
      eight: 8,
      nine: 9,
    },
    teens: {
      tenth: 10,
      eleventh: 11,
      twelfth: 12,
      thirteenth: 13,
      fourteenth: 14,
      fifteenth: 15,
      sixteenth: 16,
      seventeenth: 17,
      eighteenth: 18,
      nineteenth: 19,
      ten: 10,
      eleven: 11,
      twelve: 12,
      thirteen: 13,
      fourteen: 14,
      fifteen: 15,
      sixteen: 16,
      seventeen: 17,
      eighteen: 18,
      nineteen: 19,
    },
    tens: {
      twentieth: 20,
      thirtieth: 30,
      fortieth: 40,
      fourtieth: 40,
      fiftieth: 50,
      sixtieth: 60,
      seventieth: 70,
      eightieth: 80,
      ninetieth: 90,
      twenty: 20,
      thirty: 30,
      forty: 40,
      fourty: 40,
      fifty: 50,
      sixty: 60,
      seventy: 70,
      eighty: 80,
      ninety: 90,
    },
    multiples: {
      hundredth: 100,
      thousandth: 1e3,
      millionth: 1e6,
      billionth: 1e9,
      trillionth: 1e12,
      quadrillionth: 1e15,
      quintillionth: 1e18,
      sextillionth: 1e21,
      septillionth: 1e24,
      hundred: 100,
      thousand: 1e3,
      million: 1e6,
      billion: 1e9,
      trillion: 1e12,
      quadrillion: 1e15,
      quintillion: 1e18,
      sextillion: 1e21,
      septillion: 1e24,
      grand: 1e3,
    },
  };
const Ya = so,
  dn = so,
  OA = (e) => {
    const t = [
      { reg: /^(minus|negative)[\s\-]/i, mult: -1 },
      { reg: /^(a\s)?half[\s\-](of\s)?/i, mult: 0.5 },
    ];
    for (let n = 0; n < t.length; n++)
      if (t[n].reg.test(e) === !0)
        return { amount: t[n].mult, str: e.replace(t[n].reg, "") };
    return { amount: 1, str: e };
  },
  Ve = so,
  IA = (e, t) => {
    if (Ya.ones.hasOwnProperty(e)) {
      if (t.ones || t.teens) return !1;
    } else if (Ya.teens.hasOwnProperty(e)) {
      if (t.ones || t.teens || t.tens) return !1;
    } else if (Ya.tens.hasOwnProperty(e) && (t.ones || t.teens || t.tens))
      return !1;
    return !0;
  },
  EA = function (e) {
    let t = "0.";
    for (let n = 0; n < e.length; n++) {
      let r = e[n];
      if (dn.ones.hasOwnProperty(r) === !0) t += dn.ones[r];
      else if (dn.teens.hasOwnProperty(r) === !0) t += dn.teens[r];
      else if (dn.tens.hasOwnProperty(r) === !0) t += dn.tens[r];
      else {
        if (/^[0-9]$/.test(r) !== !0) return 0;
        t += r;
      }
    }
    return parseFloat(t);
  },
  HA = (e) =>
    (e = (e = (e = (e = (e = (e = (e = (e = e.replace(/1st$/, "1")).replace(
      /2nd$/,
      "2",
    )).replace(/3rd$/, "3")).replace(/([4567890])r?th$/, "$1")).replace(
      /^[$€¥£¢]/,
      "",
    )).replace(/[%$€¥£¢]$/, "")).replace(/,/g, "")).replace(
      /([0-9])([a-z\u00C0-\u00FF]{1,2})$/,
      "$1",
    )),
  zA = /^([0-9,\. ]+)\/([0-9,\. ]+)$/,
  su = { "a few": 3, "a couple": 2, "a dozen": 12, "two dozen": 24, zero: 0 },
  Br = (e) => Object.keys(e).reduce((t, n) => (t += e[n]), 0);
var lo = function (e) {
  if (su.hasOwnProperty(e) === !0) return su[e];
  if (e === "a" || e === "an") return 1;
  const t = OA(e);
  let n = null,
    r = {},
    a = 0,
    i = !1;
  const o = (e = t.str).split(/[ -]/);
  for (let s = 0; s < o.length; s++) {
    let l = o[s];
    if (((l = HA(l)), !l || l === "and")) continue;
    if (l === "-" || l === "negative") {
      i = !0;
      continue;
    }
    if ((l.charAt(0) === "-" && ((i = !0), (l = l.substr(1))), l === "point"))
      return (
        (a += Br(r)),
        (a += EA(o.slice(s + 1, o.length))),
        (a *= t.amount),
        a
      );
    const u = l.match(zA);
    if (u) {
      const c = parseFloat(u[1].replace(/[, ]/g, "")),
        h = parseFloat(u[2].replace(/[, ]/g, ""));
      h && (a += c / h || 0);
    } else {
      if (
        (Ve.tens.hasOwnProperty(l) &&
          r.ones &&
          Object.keys(r).length === 1 &&
          ((a = 100 * r.ones), (r = {})),
        IA(l, r) === !1)
      )
        return null;
      if (/^[0-9\.]+$/.test(l)) r.ones = parseFloat(l);
      else if (Ve.ones.hasOwnProperty(l) === !0) r.ones = Ve.ones[l];
      else if (Ve.teens.hasOwnProperty(l) === !0) r.teens = Ve.teens[l];
      else if (Ve.tens.hasOwnProperty(l) === !0) r.tens = Ve.tens[l];
      else if (Ve.multiples.hasOwnProperty(l) === !0) {
        let c = Ve.multiples[l];
        if (c === n) return null;
        if (c === 100 && o[s + 1] !== void 0) {
          const h = o[s + 1];
          Ve.multiples[h] && ((c *= Ve.multiples[h]), (s += 1));
        }
        n === null || c < n
          ? ((a += (Br(r) || 1) * c), (n = c), (r = {}))
          : ((a += Br(r)), (n = c), (a = (a || 1) * c), (r = {}));
      }
    }
  }
  return (
    (a += Br(r)),
    (a *= t.amount),
    (a *= i ? -1 : 1),
    a === 0 && Object.keys(r).length === 0 ? null : a
  );
};
const lu = /s$/,
  FA = lo,
  zn = function (e) {
    let t = e.text("reduced");
    return FA(t);
  };
let Lr = { half: 2, halve: 2, quarter: 4 };
var Cc = function (e) {
  let t =
    (function (n) {
      let r = n.text("reduced");
      return Lr.hasOwnProperty(r) ? { numerator: 1, denominator: Lr[r] } : null;
    })((e = e.clone())) ||
    (function (n) {
      let r = n
        .text("reduced")
        .match(/^([-+]?[0-9]+)\/([-+]?[0-9]+)(st|nd|rd|th)?s?$/);
      return r && r[1] && r[0]
        ? { numerator: Number(r[1]), denominator: Number(r[2]) }
        : null;
    })(e) ||
    (function (n) {
      let r = n.match("[<num>#Value+] out of every? [<den>#Value+]");
      if (r.found !== !0) return null;
      let { num: a, den: i } = r.groups();
      return a && i
        ? ((a = zn(a)),
          (i = zn(i)),
          typeof a == "number" && typeof i == "number"
            ? { numerator: a, denominator: i }
            : null)
        : null;
    })(e) ||
    (function (n) {
      let r = n.match("[<num>(#Cardinal|a)+] [<dem>#Fraction+]");
      if (r.found !== !0) return null;
      let { num: a, dem: i } = r.groups();
      a = a.has("a") ? 1 : zn(a);
      let o = i.text("reduced");
      return (
        lu.test(o) && ((o = o.replace(lu, "")), i.replaceWith(o)),
        (i = Lr.hasOwnProperty(o) ? Lr[o] : zn(i)),
        typeof a == "number" && typeof i == "number"
          ? { numerator: a, denominator: i }
          : null
      );
    })(e) ||
    (function (n) {
      let r = n.match("^#Ordinal$");
      return r.found !== !0
        ? null
        : n.lookAhead("^of .")
          ? { numerator: 1, denominator: zn(r) }
          : null;
    })(e) ||
    null;
  return (
    t !== null &&
      t.numerator &&
      t.denominator &&
      ((t.decimal = t.numerator / t.denominator),
      (t.decimal = ((n) => {
        let r = Math.round(1e3 * n) / 1e3;
        return r === 0 && n !== 0 ? n : r;
      })(t.decimal))),
    t
  );
};
const VA = lo,
  GA = Cc;
var uo = function (e) {
    let t = e.text("reduced"),
      n = /[0-9],[0-9]/.test(e.text("text")),
      r = (function (s, l, u) {
        let c = (s = s.replace(/,/g, "")).split(
          /^([^0-9]*)([0-9.,]*)([^0-9]*)$/,
        );
        if (c && c[2] && l.terms().length < 2) {
          let h = parseFloat(c[2] || s);
          typeof h != "number" && (h = null);
          let f = c[3] || "";
          return (
            (f !== "st" && f !== "nd" && f !== "rd" && f !== "th") || (f = ""),
            (f !== "m" && f !== "M") || ((h *= 1e6), (f = "")),
            (f !== "k" && f !== "k") || ((h *= 1e3), (f = "")),
            (h = h),
            { prefix: c[1] || "", num: h, suffix: f }
          );
        }
        return null;
      })(t, e);
    if (r !== null) return ((r.hasComma = n), r);
    let a = e.match("#Fraction #Fraction+$");
    a = a.found === !1 ? e.match("^#Fraction$") : a;
    let i = null;
    a.found &&
      ((i = GA(a)), (t = (e = (e = e.not(a)).not("and$")).text("reduced")));
    let o = 0;
    return (
      t && (o = VA(t) || 0),
      i && i.decimal && (o += i.decimal),
      { hasComma: n, prefix: "", num: o, suffix: "" }
    );
  },
  co = function (e) {
    if (e < 1e6) return String(e);
    let t;
    return (
      (t = typeof e == "number" ? e.toFixed(0) : e),
      t.indexOf("e+") === -1
        ? t
        : t
            .replace(".", "")
            .split("e+")
            .reduce(function (n, r) {
              return n + Array(r - n.length + 2).join(0);
            })
    );
  };
const uu = co,
  Wr = [
    ["ninety", 90],
    ["eighty", 80],
    ["seventy", 70],
    ["sixty", 60],
    ["fifty", 50],
    ["forty", 40],
    ["thirty", 30],
    ["twenty", 20],
  ],
  cu = [
    "",
    "one",
    "two",
    "three",
    "four",
    "five",
    "six",
    "seven",
    "eight",
    "nine",
    "ten",
    "eleven",
    "twelve",
    "thirteen",
    "fourteen",
    "fifteen",
    "sixteen",
    "seventeen",
    "eighteen",
    "nineteen",
  ],
  SA = [
    [1e24, "septillion"],
    [1e20, "hundred sextillion"],
    [1e21, "sextillion"],
    [1e20, "hundred quintillion"],
    [1e18, "quintillion"],
    [1e17, "hundred quadrillion"],
    [1e15, "quadrillion"],
    [1e14, "hundred trillion"],
    [1e12, "trillion"],
    [1e11, "hundred billion"],
    [1e9, "billion"],
    [1e8, "hundred million"],
    [1e6, "million"],
    [1e5, "hundred thousand"],
    [1e3, "thousand"],
    [100, "hundred"],
    [1, "one"],
  ],
  MA = function (e) {
    let t = [];
    if (e > 100) return t;
    for (let n = 0; n < Wr.length; n++)
      e >= Wr[n][1] && ((e -= Wr[n][1]), t.push(Wr[n][0]));
    return (cu[e] && t.push(cu[e]), t);
  };
var ho = function (e) {
  if (e === 0 || e === "0") return "zero";
  e > 1e21 && (e = uu(e));
  let t = [];
  e < 0 && (t.push("minus"), (e = Math.abs(e)));
  let n = (function (r) {
    let a = r,
      i = [];
    return (
      SA.forEach((o) => {
        if (r >= o[0]) {
          let s = Math.floor(a / o[0]);
          ((a -= s * o[0]), s && i.push({ unit: o[1], count: s }));
        }
      }),
      i
    );
  })(e);
  for (let r = 0; r < n.length; r++) {
    let a = n[r].unit;
    (a === "one" && ((a = ""), t.length > 1 && t.push("and")),
      (t = t.concat(MA(n[r].count))),
      t.push(a));
  }
  return (
    (t = t.concat(
      ((r) => {
        const a = [
          "zero",
          "one",
          "two",
          "three",
          "four",
          "five",
          "six",
          "seven",
          "eight",
          "nine",
        ];
        let i = [],
          o = uu(r).match(/\.([0-9]+)/);
        if (!o || !o[0]) return i;
        i.push("point");
        let s = o[0].split("");
        for (let l = 0; l < s.length; l++) i.push(a[s[l]]);
        return i;
      })(e),
    )),
    (t = t.filter((r) => r)),
    t.length === 0 && (t[0] = ""),
    t.join(" ")
  );
};
const BA = co,
  LA = ho,
  hu = {
    one: "first",
    two: "second",
    three: "third",
    five: "fifth",
    eight: "eighth",
    nine: "ninth",
    twelve: "twelfth",
    twenty: "twentieth",
    thirty: "thirtieth",
    forty: "fortieth",
    fourty: "fourtieth",
    fifty: "fiftieth",
    sixty: "sixtieth",
    seventy: "seventieth",
    eighty: "eightieth",
    ninety: "ninetieth",
  };
var Dc = (e) => {
    let t = LA(e).split(" "),
      n = t[t.length - 1];
    return (
      hu.hasOwnProperty(n)
        ? (t[t.length - 1] = hu[n])
        : (t[t.length - 1] = n.replace(/y$/, "i") + "th"),
      t.join(" ")
    );
  },
  $c = {
    prefixes: {
      "¢": "cents",
      $: "dollars",
      "£": "pounds",
      "¥": "yen",
      "€": "euros",
      "₡": "colón",
      "฿": "baht",
      "₭": "kip",
      "₩": "won",
      "₹": "rupees",
      "₽": "ruble",
      "₺": "liras",
    },
    suffixes: {
      "%": "percent",
      s: "seconds",
      cm: "centimetres",
      km: "kilometres",
    },
  };
const WA = co,
  qA = ho,
  KA = function (e) {
    if (!e && e !== 0) return null;
    let t = e % 100;
    if (t > 10 && t < 20) return String(e) + "th";
    const n = { 0: "th", 1: "st", 2: "nd", 3: "rd" };
    let r = BA(e),
      a = r.slice(r.length - 1, r.length);
    return ((r += n[a] ? n[a] : "th"), r);
  },
  JA = Dc,
  du = $c.prefixes,
  fu = $c.suffixes,
  _A = {
    usd: !0,
    eur: !0,
    jpy: !0,
    gbp: !0,
    cad: !0,
    aud: !0,
    chf: !0,
    cny: !0,
    hkd: !0,
    nzd: !0,
    kr: !0,
    rub: !0,
  },
  mu = function (e) {
    return (
      du.hasOwnProperty(e.prefix) &&
        ((e.suffix += du[e.prefix]), (e.prefix = "")),
      fu.hasOwnProperty(e.suffix) && (e.suffix = fu[e.suffix]),
      _A.hasOwnProperty(e.suffix) && (e.suffix = e.suffix.toUpperCase()),
      e.suffix && (e.suffix = " " + e.suffix),
      e
    );
  };
var jc = function (e, t, n) {
  let r = String(e.num);
  return t
    ? ((e = mu(e)),
      n
        ? ((r = JA(r)), `${e.prefix || ""}${r}${e.suffix || ""}`)
        : ((r = qA(r)), `${e.prefix || ""}${r}${e.suffix || ""}`))
    : n
      ? ((r = KA(r)), `${(e = mu(e)).prefix || ""}${r}${e.suffix || ""}`)
      : (e.hasComma === !0 && (r = e.num.toLocaleString()),
        (r = WA(r)),
        `${e.prefix || ""}${r}${e.suffix || ""}`);
};
const pe = uo,
  Qa = function (e, t, n) {
    if (e === !1) return;
    let r = t.lookAhead("^(#Unit|#Noun)");
    r.has("(#Address|#Money|#Percent)") ||
      t.has("#Ordinal") ||
      (n.num === 1
        ? r.nouns().toSingular()
        : r.has("#Singular") && r.nouns().toPlural());
  },
  Ge = jc,
  pu = lo;
let Me = {
  json: function (e) {
    let t = null;
    (typeof e == "number" && ((t = e), (e = null)),
      (e = e || { text: !0, normal: !0, trim: !0, terms: !0 }));
    let n = [];
    return (
      this.forEach((r) => {
        let a = r.json(e)[0],
          i = pe(r);
        ((a.prefix = i.prefix),
          (a.number = i.num),
          (a.suffix = i.suffix),
          (a.cardinal = Ge(i, !1, !1)),
          (a.ordinal = Ge(i, !1, !0)),
          (a.textCardinal = Ge(i, !0, !1)),
          (a.textOrdinal = Ge(i, !0, !0)),
          n.push(a));
      }),
      t !== null ? n[t] : n
    );
  },
  units: function () {
    let e = this.lookAhead("(#Unit|#Noun)+");
    return (
      (e = e.splitAfter("@hasComma").first()),
      (e = e.not("#Pronoun")),
      e.first()
    );
  },
  isOrdinal: function () {
    return this.if("#Ordinal");
  },
  isCardinal: function () {
    return this.if("#Cardinal");
  },
  toNumber: function () {
    return (
      this.forEach((e) => {
        let t = pe(e);
        if (t.num === null) return;
        let n = Ge(t, !1, e.has("#Ordinal"));
        (e.replaceWith(n, !0), e.tag("NumericValue"));
      }),
      this
    );
  },
  toLocaleString: function () {
    return (
      this.forEach((e) => {
        let t = pe(e);
        if (t.num === null) return;
        t.num = t.num.toLocaleString();
        let n = Ge(t, !1, e.has("#Ordinal"));
        e.replaceWith(n, !0);
      }),
      this
    );
  },
  toText: function () {
    return (
      this.forEach((e) => {
        let t = pe(e);
        if (t.num === null) return;
        let n = Ge(t, !0, e.has("#Ordinal"));
        (e.replaceWith(n, !0), e.tag("TextValue"));
      }),
      this
    );
  },
  toCardinal: function (e) {
    return (
      this.if("#Ordinal").forEach((t) => {
        let n = pe(t);
        if (n.num === null) return;
        let r = Ge(n, t.has("#TextValue"), !1);
        if (t.has("#NumberRange")) {
          let a = t.termList()[0];
          a.text && a.post === "" && (a.post = " ");
        }
        (t.replaceWith(r, !0), t.tag("Cardinal"), Qa(e, t, n));
      }),
      this
    );
  },
  toOrdinal: function () {
    return (
      this.if("#Cardinal").forEach((e) => {
        let t = pe(e);
        if (t.num === null) return;
        let n = Ge(t, e.has("#TextValue"), !0);
        if (e.has("#NumberRange")) {
          let a = e.termList()[0];
          a.text && a.post === "" && (a.post = " ");
        }
        (e.replaceWith(n, !0), e.tag("Ordinal"));
        let r = this.lookAhead("^#Plural");
        r.found && r.nouns().toSingular();
      }),
      this
    );
  },
  isEqual: function (e) {
    return this.filter((t) => pe(t).num === e);
  },
  greaterThan: function (e) {
    return this.filter((t) => pe(t).num > e);
  },
  lessThan: function (e) {
    return this.filter((t) => pe(t).num < e);
  },
  between: function (e, t) {
    return this.filter((n) => {
      let r = pe(n).num;
      return r > e && r < t;
    });
  },
  set: function (e, t) {
    return (
      e === void 0 ||
        (typeof e == "string" && (e = pu(e)),
        this.forEach((n) => {
          let r = pe(n);
          if (((r.num = e), r.num === null)) return;
          let a = Ge(r, n.has("#TextValue"), n.has("#Ordinal"));
          ((n = n.not("#Currency")).replaceWith(a, !0), Qa(t, n, r));
        })),
      this
    );
  },
  add: function (e, t) {
    return e
      ? (typeof e == "string" && (e = pu(e)),
        this.forEach((n) => {
          let r = pe(n);
          if (r.num === null) return;
          r.num += e;
          let a = Ge(r, n.has("#TextValue"), n.has("#Ordinal"));
          ((n = n.not("#Currency")).replaceWith(a, !0), Qa(t, n, r));
        }),
        this)
      : this;
  },
  subtract: function (e, t) {
    return this.add(-1 * e, t);
  },
  increment: function (e) {
    return (this.add(1, e), this);
  },
  decrement: function (e) {
    return (this.add(-1, e), this);
  },
  romanNumerals: function (e) {
    let t = this.match("#RomanNumeral").numbers();
    return (typeof e == "number" && (t = t.get(e)), t);
  },
  normalize: function () {
    const e = { "%": !0 };
    return (
      this.forEach((t) => {
        let n = pe(t);
        if (n.num !== null && n.suffix && e[n.suffix] !== !0) {
          let r = n.prefix || "";
          t = t.replaceWith(r + n.num + " " + n.suffix);
        }
      }),
      this
    );
  },
  get: function (e) {
    let t = [];
    return (
      this.forEach((n) => {
        t.push(pe(n).num);
      }),
      e !== void 0 ? t[e] || null : t || null
    );
  },
};
((Me.toNice = Me.toLocaleString),
  (Me.isBetween = Me.between),
  (Me.minus = Me.subtract),
  (Me.plus = Me.add),
  (Me.equals = Me.isEqual));
var UA = Me;
const RA = uo,
  Za = function (e) {
    let t = RA(e).num;
    return typeof t == "number" ? t / 100 : null;
  };
var YA = {
    get: function (e) {
      let t = [];
      return (
        this.forEach((n) => {
          let r = Za(n);
          r !== null && t.push(r);
        }),
        e !== void 0 ? t[e] || null : t || null
      );
    },
    json: function (e) {
      let t = null;
      (typeof e == "number" && ((t = e), (e = null)),
        (e = e || { text: !0, normal: !0, trim: !0, terms: !0 }));
      let n = [];
      return (
        this.forEach((r) => {
          let a = r.json(e)[0],
            i = Za(r);
          if (((a.number = i), i !== null)) {
            let o = 100 * i;
            ((a.textNumber = `${o} percent`), (a.cardinal = `${o}%`));
          }
          n.push(a);
        }),
        t !== null ? n[t] || {} : n
      );
    },
    toFraction: function () {
      return (
        this.forEach((e) => {
          let t = Za(e);
          if (t !== null) {
            ((t *= 100), (t = Math.round(100 * t) / 100));
            let n = `${t}/100`;
            this.replace(e, n);
          }
        }),
        this
      );
    },
  },
  Nc = [
    {
      dem: "american",
      name: "dollar",
      iso: "usd",
      sub: "cent",
      sym: ["$", "US$", "U$"],
    },
    { name: "euro", iso: "eur", sub: "cent", sym: ["€"] },
    {
      dem: "british",
      name: "pound",
      iso: "gbp",
      sub: "penny",
      alias: { sterling: !0 },
      sym: ["£"],
    },
    {
      name: "renminbi",
      iso: "cny",
      plural: "yuán",
      alias: { yuan: !0 },
      sym: ["元"],
    },
    {
      dem: "japanese",
      name: "yen",
      iso: "jpy",
      sub: "sen",
      sym: ["¥", "円", "圓"],
    },
    {
      dem: "swedish",
      name: "krona",
      iso: "sek",
      sub: "öre",
      alias: { ore: !0, kronor: !0 },
      sym: ["kr"],
    },
    { dem: "estonian", name: "kroon", iso: "eek", sub: "sent", sym: ["kr"] },
    { dem: "norwegian", name: "krone", iso: "nok", sub: "øre", sym: ["kr"] },
    { dem: "icelandic", name: "króna", iso: "isk", sym: ["kr"] },
    { dem: "danish", name: "krone", iso: "dkk", sub: "øre", sym: ["kr."] },
    { dem: "zambian", name: "kwacha", iso: "zmw", sub: "ngwee", sym: ["K"] },
    { dem: "malawian", name: "kwacha", iso: "mwk", sub: "tambala", sym: ["K"] },
    {
      dem: "greek",
      name: "drachma",
      iso: "grd",
      sub: "leptοn",
      sym: ["Δρχ.", "Δρ.", "₯"],
    },
    {
      dem: "eastern caribbean",
      name: "dollar",
      iso: "xcd",
      sub: "cent",
      sym: ["$"],
    },
    { dem: "finnish", name: "markka", iso: "fim", sub: "penni", sym: ["mk"] },
    { dem: "polish", name: "złoty", iso: "pln", sub: "grosz", sym: ["zł"] },
    { dem: "slovenian", name: "tolar", iso: "sit", sub: "stotin", sym: [] },
    {
      dem: "australian",
      name: "dollar",
      iso: "aud",
      sub: "cent",
      sym: ["$", "A$", "AU$"],
    },
    { dem: "deutsche", name: "mark", iso: "dem", sub: "pfennig", sym: ["DM"] },
    { dem: "thai", name: "baht", iso: "thb", sub: "satang", sym: ["฿"] },
    {
      dem: "canadian",
      name: "dollar",
      iso: "cad",
      sub: "cent",
      sym: ["$", "Can$", "C$", "CA$", "CAD"],
    },
    {
      dem: "mexican",
      name: "peso",
      iso: "mxn",
      sub: "centavo",
      sym: ["$", "Mex$"],
    },
    {
      dem: "spanish",
      name: "peseta",
      iso: "esp",
      sub: "céntimo",
      sym: ["Pta"],
    },
    {
      dem: "new zealand",
      name: "dollar",
      iso: "nzd",
      sub: "cent",
      sym: ["$", "NZ$"],
    },
    {
      dem: "chilean",
      name: "peso",
      iso: "clp",
      sub: "centavo",
      sym: ["Cifrão", "$"],
    },
    { dem: "nigerian", name: "naira", iso: "ngn", sub: "kobo", sym: ["₦"] },
    {
      dem: "austrian",
      name: "schilling",
      iso: "ats",
      sub: "groschen",
      sym: ["S", "öS"],
    },
    {
      dem: "guatemalan",
      name: "quetzal",
      iso: "gtq",
      sub: "centavo",
      sym: ["Q"],
    },
    { dem: "philippine", name: "peso", iso: "php", sub: "sentimo", sym: ["₱"] },
    { dem: "hungarian", name: "forint", iso: "huf", sym: ["Ft"] },
    {
      dem: "russian",
      name: "ruble",
      iso: "rub",
      sub: "kopeyka",
      sym: ["₽", "руб", "р."],
    },
    {
      dem: "kuwaiti",
      name: "dinar",
      iso: "kwd",
      sub: "fils",
      sym: ["د.ك", "KD"],
    },
    {
      dem: "israeli",
      name: "new shekel",
      iso: "ils",
      sub: "agora",
      sym: ["₪"],
    },
    { dem: "latvian", name: "lats", iso: "lvl", sub: "santīms", sym: ["Ls"] },
    { dem: "kazakhstani", name: "tenge", iso: "kzt", sub: "tıyn", sym: ["₸"] },
    { dem: "iraqi", name: "dinar", iso: "iqd", sub: "fils", sym: ["د.ع"] },
    {
      dem: "bahamian",
      name: "dollar",
      iso: "bsd",
      sub: "cent",
      sym: ["$", "B$"],
    },
    {
      dem: "seychellois",
      name: "rupee",
      iso: "scr",
      sub: "cent",
      sym: ["SCR", "SR"],
    },
    { dem: "albanian", name: "lek", iso: "all", sub: "qindarkë", sym: ["L"] },
    {
      dem: "bulgarian",
      name: "lev",
      iso: "bgn",
      sub: "stotinka",
      sym: ["лв."],
    },
    { dem: "irish", name: "pound", iso: "iep", sym: ["£", "IR£"] },
    { name: "cfp franc", iso: "xpf", sym: ["f"] },
    { dem: "south african", name: "rand", iso: "zar", sub: "cent", sym: ["R"] },
    {
      dem: "south korean",
      name: "won",
      iso: "krw",
      sub: "jeon",
      plural: "won",
      sym: ["₩"],
    },
    {
      dem: "north korean",
      name: "won",
      iso: "kpw",
      sub: "chon",
      plural: "won",
      sym: ["₩"],
    },
    { dem: "portuguese", name: "escudo", iso: "pte", sub: "centavo", sym: [] },
    { dem: "ghanaian", name: "cedi", iso: "ghs", sub: "pesewa", sym: ["GH₵"] },
    { dem: "hong kong", name: "dollar", iso: "hkd", sub: "毫", sym: ["$"] },
    {
      dem: "new taiwan",
      name: "dollar",
      iso: "twd",
      sub: "dime",
      sym: ["NT$"],
    },
    {
      dem: "east german",
      name: "mark",
      iso: "ddm",
      sub: "pfennig",
      sym: ["M"],
    },
    { dem: "namibian", name: "dollar", iso: "nad", sub: "cent", sym: ["$"] },
    { dem: "malaysian", name: "ringgit", iso: "myr", sub: "sen", sym: ["RM"] },
    { dem: "swiss", name: "franc", iso: "chf", sym: ["Rp."] },
    {
      dem: "panamanian",
      name: "balboa",
      iso: "pab",
      sub: "centésimo",
      sym: ["B/."],
    },
    { dem: "indonesian", name: "rupiah", iso: "idr", sub: "sen", sym: ["Rp"] },
    { dem: "brunei", name: "dollar", iso: "bnd", sub: "sen", sym: ["$", "B$"] },
    {
      dem: "venezuelan",
      name: "bolívar",
      iso: "vef",
      sub: "céntimo",
      sym: ["Bs.F", "Bs."],
    },
    { dem: "macedonian", name: "denar", iso: "mkd", sub: "deni", sym: ["den"] },
    {
      dem: "mauritanian",
      name: "ouguiya",
      iso: "mru",
      sub: "khoums",
      sym: ["UM"],
    },
    { dem: "argentine", name: "peso", iso: "ars", sub: "centavo", sym: ["$"] },
    {
      dem: "libyan",
      name: "dinar",
      iso: "lyd",
      sub: "dirham",
      sym: ["LD", "ل.د"],
    },
    {
      dem: "jordanian",
      name: "dinar",
      iso: "jod",
      sub: "dirham",
      sym: ["د.أ"],
    },
    {
      dem: "french",
      name: "franc",
      iso: "frf",
      sub: "centime",
      sym: ["F", "Fr", "FF", "₣"],
    },
    {
      dem: "syrian",
      name: "pound",
      iso: "syp",
      sub: "piastre",
      sym: ["LS", "£S"],
    },
    { dem: "belize", name: "dollar", iso: "bzd", sub: "cent", sym: ["$"] },
    {
      dem: "saudi",
      name: "riyal",
      iso: "sar",
      sub: "halalah",
      sym: ["SAR", "ر.س", " ﷼"],
    },
    { dem: "surinamese", name: "dollar", iso: "srd", sub: "cent", sym: ["$"] },
    {
      dem: "singapore",
      name: "dollar",
      iso: "sgd",
      sub: "cent",
      sym: ["S$", "$"],
    },
    {
      dem: "nepalese",
      name: "rupee",
      iso: "npr",
      sub: "paisa",
      sym: ["रु ₨", "Re"],
    },
    {
      dem: "nicaraguan",
      name: "córdoba",
      iso: "nio",
      sub: "centavo",
      sym: ["C$"],
    },
    { dem: "bangladeshi", name: "taka", iso: "bdt", sub: "poysha", sym: ["৳"] },
    { dem: "indian", name: "rupee", iso: "inr", sub: "paisa", sym: ["₹"] },
    {
      dem: "maldivian",
      name: "rufiyaa",
      iso: "mvr",
      sub: "laari",
      sym: ["Rf", "MRf", "MVR", ".ރ "],
    },
    {
      dem: "sri lankan",
      name: "rupee",
      iso: "lkr",
      sub: "cents",
      sym: ["Rs", "රු", "ரூ"],
    },
    {
      dem: "bhutanese",
      name: "ngultrum",
      iso: "btn",
      sub: "chhertum",
      sym: ["Nu."],
    },
    { dem: "turkish", name: "lira", iso: "try", sub: "kuruş", sym: ["YTL"] },
    {
      dem: "serbian",
      name: "dinar",
      iso: "rsd",
      sub: "para",
      sym: ["din", "дин"],
    },
    {
      dem: "bosnia and herzegovina",
      name: "convertible mark",
      iso: "bam",
      sub: "fening",
      sym: ["KM"],
    },
    { dem: "botswana", name: "pula", iso: "bwp", sub: "thebe", sym: ["p"] },
    {
      dem: "swazi",
      name: "lilangeni",
      iso: "szl",
      sub: "cent",
      sym: ["L", "E"],
    },
    {
      dem: "lithuanian",
      name: "litas",
      iso: "ltl",
      sub: "centas",
      sym: ["Lt", "ct"],
    },
    { dem: "mauritian", name: "rupee", iso: "mur", sub: "cent", sym: ["₨"] },
    { dem: "pakistani", name: "rupee", iso: "pkr", sub: "paisa", sym: ["₨"] },
    { dem: "maltese", name: "lira", iso: "mtl", sub: "cent", sym: ["₤", "Lm"] },
    { dem: "cypriot", name: "pound", iso: "cyp", sub: "cent", sym: ["£"] },
    { dem: "moldovan", name: "leu", iso: "mdl", sym: ["l"] },
    { dem: "croatian", name: "kuna", iso: "hrk", sub: "lipa", sym: ["kn"] },
    {
      dem: "afghan",
      name: "afghani",
      iso: "afn",
      sub: "pul",
      sym: ["؋", "Af", "Afs"],
    },
    {
      dem: "ecuadorian",
      name: "sucre",
      iso: "ecs",
      sub: "centavo",
      sym: ["S/."],
    },
    {
      dem: "sierra leonean",
      name: "leone",
      iso: "sll",
      sub: "cent",
      sym: ["Le"],
    },
  ];
const Yr = Nc,
  gu = uo,
  At = {};
let Tc = {};
Yr.forEach((e) => {
  (e.sym.forEach((t) => {
    At[t] = At[t] || e.iso;
  }),
    (At[e.iso] = At[e.iso] || e.iso),
    e.sub && (Tc[e.sub] = !0));
});
let yu = `(${Object.keys(Tc).join("|")})`;
const QA = jc,
  Xa = function (e) {
    let t = 0,
      n = e.match(`and #Money+ ${yu}`);
    if (n.found) {
      e = e.not(n);
      let l = gu(n.match("#Value+"));
      l && l.num && (t = l.num / 100);
    }
    let r = gu(e),
      a = r.num || 0;
    a += t;
    let i =
      ((o = r).suffix && At.hasOwnProperty(o.suffix)
        ? Yr.find((l) => l.iso === At[o.suffix])
        : o.prefix && At.hasOwnProperty(o.prefix)
          ? Yr.find((l) => l.iso === At[o.prefix])
          : null) ||
      (function (l) {
        let u = l.match("#Currency+");
        u.nouns().toSingular();
        let c = u.text("reduced");
        return Yr.find(
          (h) =>
            (c === `${h.dem} ${h.name}` ||
              c === h.iso ||
              c === h.sub ||
              c === h.name ||
              !(!h.alias || h.alias[c] !== !0)) &&
            h,
        );
      })(e) ||
      {};
    var o;
    let s = "";
    return (
      i && i.sym && ((s = i.sym[0]), a && e.has(`${yu}`) && (a /= 100)),
      {
        num: a,
        iso: i.iso,
        demonym: i.dem,
        currency: i.name,
        plural: i.plural,
        symbol: s,
      }
    );
  },
  bu = function (e = "") {
    return e.replace(/\w\S*/g, function (t) {
      return t.charAt(0).toUpperCase() + t.substr(1).toLowerCase();
    });
  };
var ZA = {
    get: function (e) {
      let t = [];
      return (
        this.forEach((n) => {
          t.push(Xa(n));
        }),
        e !== void 0 ? t[e] || null : t || null
      );
    },
    currency: function (e) {
      let t = [];
      return (
        this.forEach((n) => {
          let r = Xa(n);
          r && t.push(r);
        }),
        typeof e == "number" ? t[e] || null : t || null
      );
    },
    json: function (e) {
      let t = null;
      (typeof e == "number" && ((t = e), (e = null)),
        (e = e || { text: !0, normal: !0, trim: !0, terms: !0 }));
      let n = [];
      return (
        this.forEach((r) => {
          let a = r.json(e)[0],
            i = Xa(r);
          if (
            ((a.number = i.num),
            i.iso &&
              ((a.iso = i.iso.toUpperCase()),
              (a.symbol = i.symbol),
              (a.currency = bu(i.demonym) + " " + bu(i.currency))),
            (a.textFmt = QA(i, !0, !1)),
            i.currency)
          ) {
            let o = i.currency;
            (i.num !== 1 && (o = i.plural || o + "s"), (a.textFmt += " " + o));
          }
          n.push(a);
        }),
        t !== null ? n[t] || {} : n
      );
    },
  },
  Qr = {};
const ei = ho,
  XA = Dc;
((Qr.toText = function (e) {
  if (!e.numerator || !e.denominator) return "";
  let t = ei(e.numerator),
    n = XA(e.denominator);
  return (
    e.denominator === 2 && (n = "half"),
    t && n ? (e.numerator !== 1 && (n += "s"), `${t} ${n}`) : ""
  );
}),
  (Qr.textCardinal = function (e) {
    return !e.numerator || !e.denominator
      ? ""
      : `${ei(e.numerator)} out of ${ei(e.denominator)}`;
  }),
  (Qr.toDecimal = function (e) {
    return e.decimal;
  }));
const fn = Cc,
  Fn = Qr,
  Li = {
    get: function (e) {
      let t = [];
      return (
        this.forEach((n) => {
          t.push(fn(n));
        }),
        e !== void 0 ? t[e] || null : t || null
      );
    },
    toDecimal() {
      return (
        this.forEach((e) => {
          let t = fn(e);
          if (t) {
            let n = Fn.toDecimal(t);
            (e.replaceWith(String(n), !0),
              e.tag("NumericValue"),
              e.unTag("Fraction"));
          }
        }),
        this
      );
    },
    json: function (e) {
      let t = null;
      (typeof e == "number" && ((t = e), (e = null)),
        (e = e || { text: !0, normal: !0, trim: !0, terms: !0 }));
      let n = [];
      return (
        this.forEach((r) => {
          let a = r.json(e)[0],
            i = fn(r) || {},
            o = Fn.toDecimal(i);
          ((a.numerator = i.numerator),
            (a.denominator = i.denominator),
            (a.number = o),
            (a.textOrdinal = Fn.toText(i)),
            (a.textCardinal = Fn.textCardinal(i)),
            n.push(a));
        }),
        t !== null ? n[t] || {} : n
      );
    },
    normalize: function () {
      return (
        this.forEach((e) => {
          let t = fn(e);
          if (
            t &&
            typeof t.numerator == "number" &&
            typeof t.denominator == "number"
          ) {
            let n = `${t.numerator}/${t.denominator}`;
            this.replace(e, n);
          }
        }),
        this
      );
    },
    toText: function (e) {
      let t = [];
      return (
        this.forEach((n) => {
          let r = fn(n) || {},
            a = Fn.toText(r);
          (n.replaceWith(a, !0), n.tag("Fraction"));
        }),
        e !== void 0 ? t[e] : t
      );
    },
    toPercentage: function () {
      return (
        this.forEach((e) => {
          let t = fn(e);
          if (t.decimal || t.decimal === 0) {
            let n = 100 * t.decimal;
            ((n = Math.round(100 * n) / 100), this.replace(e, `${n}%`));
          }
        }),
        this
      );
    },
  };
Li.toNumber = Li.toDecimal;
var e4 = Li;
const t4 = function (e) {
    return (
      e
        .match(
          "(hundred|thousand|million|billion|trillion|quadrillion|quintillion|sextillion|septillion)",
        )
        .tag("#Multiple", "fraction-tagger"),
      e.match("[(half|quarter)] of? (a|an)", 0).tag("Fraction", "millionth"),
      e.match("#Adverb [half]", 0).tag("Fraction", "nearly-half"),
      e.match("[half] the", 0).tag("Fraction", "half-the"),
      e.match("#Value (halves|halfs|quarters)").tag("Fraction", "two-halves"),
      e.match("a #Ordinal").tag("Fraction", "a-quarter"),
      e.match("(#Fraction && /s$/)").lookBefore("#Cardinal+$").tag("Fraction"),
      e.match("[#Cardinal+ #Ordinal] of .", 0).tag("Fraction", "ordinal-of"),
      e
        .match("[(#NumericValue && #Ordinal)] of .", 0)
        .tag("Fraction", "num-ordinal-of"),
      e.match("(a|one) #Cardinal?+ #Ordinal").tag("Fraction", "a-ordinal"),
      e
        .match("#Cardinal+ out? of every? #Cardinal")
        .tag("Fraction", "fraction-tagger"),
      e
    );
  },
  n4 = function (e) {
    const t = "money-tagger";
    (e.match("#Money and #Money #Currency?").tag("Money", "money-and-money"),
      e
        .match("#Money")
        .not("#TextValue")
        .match("/\\.[0-9]{3}$/")
        .unTag("#Money", "three-decimal money"),
      e
        .ifNo("#Value")
        .match("#Currency #Verb")
        .unTag("Currency", "no-currency"),
      e
        .match("#Value #Currency [and] #Value (cents|ore|centavos|sens)", 0)
        .tag("Money", t));
    let n = e.match("[<num>#Value] [<currency>(mark|rand|won|rub|ore)]");
    return (
      n.group("num").tag("Money", t),
      n.group("currency").tag("Currency", t),
      e
    );
  };
var r4 = function (e) {
  ((e = n4(e)).match("the [/[0-9]+s$/]").tag("#Plural", "number-tag"),
    e.match("half a? #Value").tag("Value", "half-a-value"),
    e
      .match("#Value [and a (half|quarter)]", 0)
      .tag(["TextValue", "#Fraction"], "value-and-a-half"),
    (e = t4(e))
      .match("#Cardinal and #Fraction #Fraction")
      .tag("Value", "number-tag"));
};
const vu = {
  mark: !0,
  sucre: !0,
  leone: !0,
  afghani: !0,
  rand: !0,
  try: !0,
  mop: !0,
  won: !0,
  all: !0,
  rub: !0,
  eek: !0,
  sit: !0,
  bam: !0,
  npr: !0,
  leu: !0,
};
let Mt = { kronor: "Currency" };
Nc.forEach((e) => {
  e.iso && !vu[e.iso] && (Mt[e.iso] = ["Acronym", "Currency"]);
  let t = e.name;
  if (
    (t && !vu[t] && ((Mt[t] = "Currency"), (Mt[t + "s"] = "Currency")), e.dem)
  ) {
    let n = e.dem;
    ((Mt[`${n} ${t}`] = "Currency"), (Mt[`${n} ${t}s`] = "Currency"));
  }
  e.sub && (Mt[e.sub] = "Currency");
});
const a4 = $A,
  i4 = jA,
  o4 = NA,
  s4 = TA,
  l4 = UA,
  u4 = YA,
  c4 = ZA,
  h4 = e4,
  d4 = r4,
  f4 = { Fraction: { isA: ["Value"] }, Multiple: { isA: "Value" } },
  m4 = Mt;
var p4 = function (e, t) {
  (t.addWords(m4), t.addTags(f4), t.postProcess(d4));
  class n extends e {}
  Object.assign(n.prototype, l4);
  class r extends n {}
  Object.assign(r.prototype, c4);
  class a extends n {}
  Object.assign(a.prototype, h4);
  class i extends n {}
  Object.assign(i.prototype, u4);
  const o = {
    numbers: function (s) {
      let l = i4(this, s);
      return new n(l.list, this, this.world);
    },
    percentages: function (s) {
      let l = s4(this, s);
      return new i(l.list, this, this.world);
    },
    fractions: function (s) {
      let l = o4(this, s);
      return new a(l.list, this, this.world);
    },
    money: function (s) {
      let l = a4(this, s);
      return new r(l.list, this, this.world);
    },
  };
  return (
    (o.values = o.numbers),
    (o.percents = o.percentages),
    Object.assign(e.prototype, o),
    e
  );
};
k.plugin(DA);
k.plugin(p4);
export { k as default };
//# sourceMappingURL=compromise-CldSR42k.js.map
