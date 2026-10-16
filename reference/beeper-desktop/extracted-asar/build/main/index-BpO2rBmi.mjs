import {
  P as mn,
  m as pn,
  L as yn,
  I as _n,
  S as vn,
  E as Oe,
  a as gn,
  G as $n,
  c as wn,
  e as bn,
  d as En,
  R as Sn,
  C as Pn,
  M as Te,
  b as Pt,
  f as Rn,
} from "./index-o5KnLmKX.mjs";
import { Y as an } from "./index-BJhQkpW6.mjs";
import { a as Nn } from "./_commonjsHelpers-CBUqixCJ.mjs";
import "node:process";
import "node:events";
import "node:crypto";
import "node:stream";
import "node:stream/web";
import "node:async_hooks";
import "./Keychain-CHHka2u7.mjs";
import "./constants-BL_pdRyX.mjs";
import "path";
import "os";
import "url";
import "./index-DKkZ9dV1.mjs";
import "worker_threads";
import "fs";
import "./util-CrY9x2BW.mjs";
import "./sentry-common-CDPx3Glo.mjs";
import "./package-CIHfweXK.mjs";
import "./sentry-enabled-COAVq6nC.mjs";
import "tty";
import "better-sqlite3";
import "node:url";
import "node:path";
import "./logger-DoW0T1f3.mjs";
import "./startup-checkpoints-BQimOHWq.mjs";
import "./AsyncSqlite-CpInlfQ-.mjs";
import "./machine-id-DFkLVgcU.mjs";
import "perf_hooks";
import "child_process";
import "./index-CNG_AM8w.mjs";
import "timers/promises";
import "async_hooks";
import "fs/promises";
import "./index-B_PiTES1.mjs";
import "node:util";
import "node:child_process";
import "node:os";
import "./index-CMOlVndj.mjs";
import "assert";
import "events";
import "buffer";
import "stream";
import "util";
import "node:fs";
import "node:module";
import "./index-Bo2CLT1C.mjs";
import "node:timers";
import "./client-DMtubo6I.mjs";
import "https";
import "http";
import "net";
import "tls";
import "crypto";
import "zlib";
import "stream/promises";
import "node:fs/promises";
import "./index-C7dxdDjs.mjs";
import "node:string_decoder";
import "./index-DaNOOrJg.mjs";
import "./utils-D8MokWSu.mjs";
import "./index-BiKiNEmj.mjs";
import "./register-proxy-7lV9pun2.mjs";
import "domain";
import "./index-BiHJsdYm.mjs";
import "./rolling-logger-C9NTeNo3.mjs";
import "./got-_wC7Q_ix.mjs";
import "dns";
import "http2";
import "module";
import "./index-8JaOpgio.mjs";
import "node:worker_threads";
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
    var r = new e.Error().stack;
    r &&
      ((e._sentryDebugIds = e._sentryDebugIds || {}),
      (e._sentryDebugIds[r] = "bebc224a-1438-4795-9c5c-b17d08021dd3"),
      (e._sentryDebugIdIdentifier =
        "sentry-dbid-bebc224a-1438-4795-9c5c-b17d08021dd3"));
  } catch {}
})();
var je = { exports: {} },
  Rt = {},
  me = {},
  ge = {},
  Nt = {},
  kt = {},
  Ot = {},
  Kt;
function yt() {
  return (
    Kt ||
      ((Kt = 1),
      (function (e) {
        (Object.defineProperty(e, "__esModule", { value: !0 }),
          (e.regexpCode =
            e.getEsmExportName =
            e.getProperty =
            e.safeStringify =
            e.stringify =
            e.strConcat =
            e.addCodeArg =
            e.str =
            e._ =
            e.nil =
            e._Code =
            e.Name =
            e.IDENTIFIER =
            e._CodeOrName =
              void 0));
        class r {}
        ((e._CodeOrName = r), (e.IDENTIFIER = /^[a-z$_][a-z$_0-9]*$/i));
        class p extends r {
          constructor(t) {
            if ((super(), !e.IDENTIFIER.test(t)))
              throw new Error("CodeGen: name must be a valid identifier");
            this.str = t;
          }
          toString() {
            return this.str;
          }
          emptyStr() {
            return !1;
          }
          get names() {
            return { [this.str]: 1 };
          }
        }
        e.Name = p;
        class i extends r {
          constructor(t) {
            (super(), (this._items = typeof t == "string" ? [t] : t));
          }
          toString() {
            return this.str;
          }
          emptyStr() {
            if (this._items.length > 1) return !1;
            const t = this._items[0];
            return t === "" || t === '""';
          }
          get str() {
            var t;
            return (t = this._str) !== null && t !== void 0
              ? t
              : (this._str = this._items.reduce((n, d) => `${n}${d}`, ""));
          }
          get names() {
            var t;
            return (t = this._names) !== null && t !== void 0
              ? t
              : (this._names = this._items.reduce(
                  (n, d) => (
                    d instanceof p && (n[d.str] = (n[d.str] || 0) + 1),
                    n
                  ),
                  {},
                ));
          }
        }
        ((e._Code = i), (e.nil = new i("")));
        function g(a, ...t) {
          const n = [a[0]];
          let d = 0;
          for (; d < t.length;) (u(n, t[d]), n.push(a[++d]));
          return new i(n);
        }
        e._ = g;
        const o = new i("+");
        function l(a, ...t) {
          const n = [S(a[0])];
          let d = 0;
          for (; d < t.length;) (n.push(o), u(n, t[d]), n.push(o, S(a[++d])));
          return (f(n), new i(n));
        }
        e.str = l;
        function u(a, t) {
          t instanceof i
            ? a.push(...t._items)
            : t instanceof p
              ? a.push(t)
              : a.push(E(t));
        }
        e.addCodeArg = u;
        function f(a) {
          let t = 1;
          for (; t < a.length - 1;) {
            if (a[t] === o) {
              const n = v(a[t - 1], a[t + 1]);
              if (n !== void 0) {
                a.splice(t - 1, 3, n);
                continue;
              }
              a[t++] = "+";
            }
            t++;
          }
        }
        function v(a, t) {
          if (t === '""') return a;
          if (a === '""') return t;
          if (typeof a == "string")
            return t instanceof p || a[a.length - 1] !== '"'
              ? void 0
              : typeof t != "string"
                ? `${a.slice(0, -1)}${t}"`
                : t[0] === '"'
                  ? a.slice(0, -1) + t.slice(1)
                  : void 0;
          if (typeof t == "string" && t[0] === '"' && !(a instanceof p))
            return `"${a}${t.slice(1)}`;
        }
        function y(a, t) {
          return t.emptyStr() ? a : a.emptyStr() ? t : l`${a}${t}`;
        }
        e.strConcat = y;
        function E(a) {
          return typeof a == "number" || typeof a == "boolean" || a === null
            ? a
            : S(Array.isArray(a) ? a.join(",") : a);
        }
        function P(a) {
          return new i(S(a));
        }
        e.stringify = P;
        function S(a) {
          return JSON.stringify(a)
            .replace(/\u2028/g, "\\u2028")
            .replace(/\u2029/g, "\\u2029");
        }
        e.safeStringify = S;
        function h(a) {
          return typeof a == "string" && e.IDENTIFIER.test(a)
            ? new i(`.${a}`)
            : g`[${a}]`;
        }
        e.getProperty = h;
        function b(a) {
          if (typeof a == "string" && e.IDENTIFIER.test(a))
            return new i(`${a}`);
          throw new Error(
            `CodeGen: invalid export name: ${a}, use explicit $id name mapping`,
          );
        }
        e.getEsmExportName = b;
        function s(a) {
          return new i(a.toString());
        }
        e.regexpCode = s;
      })(Ot)),
    Ot
  );
}
var Tt = {},
  Ht;
function Gt() {
  return (
    Ht ||
      ((Ht = 1),
      (function (e) {
        (Object.defineProperty(e, "__esModule", { value: !0 }),
          (e.ValueScope =
            e.ValueScopeName =
            e.Scope =
            e.varKinds =
            e.UsedValueState =
              void 0));
        const r = yt();
        class p extends Error {
          constructor(v) {
            (super(`CodeGen: "code" for ${v} not defined`),
              (this.value = v.value));
          }
        }
        var i;
        ((function (f) {
          ((f[(f.Started = 0)] = "Started"),
            (f[(f.Completed = 1)] = "Completed"));
        })(i || (e.UsedValueState = i = {})),
          (e.varKinds = {
            const: new r.Name("const"),
            let: new r.Name("let"),
            var: new r.Name("var"),
          }));
        class g {
          constructor({ prefixes: v, parent: y } = {}) {
            ((this._names = {}), (this._prefixes = v), (this._parent = y));
          }
          toName(v) {
            return v instanceof r.Name ? v : this.name(v);
          }
          name(v) {
            return new r.Name(this._newName(v));
          }
          _newName(v) {
            const y = this._names[v] || this._nameGroup(v);
            return `${v}${y.index++}`;
          }
          _nameGroup(v) {
            var y, E;
            if (
              (!(
                (E =
                  (y = this._parent) === null || y === void 0
                    ? void 0
                    : y._prefixes) === null || E === void 0
              ) &&
                E.has(v)) ||
              (this._prefixes && !this._prefixes.has(v))
            )
              throw new Error(
                `CodeGen: prefix "${v}" is not allowed in this scope`,
              );
            return (this._names[v] = { prefix: v, index: 0 });
          }
        }
        e.Scope = g;
        class o extends r.Name {
          constructor(v, y) {
            (super(y), (this.prefix = v));
          }
          setValue(v, { property: y, itemIndex: E }) {
            ((this.value = v),
              (this.scopePath = (0, r._)`.${new r.Name(y)}[${E}]`));
          }
        }
        e.ValueScopeName = o;
        const l = (0, r._)`\n`;
        class u extends g {
          constructor(v) {
            (super(v),
              (this._values = {}),
              (this._scope = v.scope),
              (this.opts = { ...v, _n: v.lines ? l : r.nil }));
          }
          get() {
            return this._scope;
          }
          name(v) {
            return new o(v, this._newName(v));
          }
          value(v, y) {
            var E;
            if (y.ref === void 0)
              throw new Error("CodeGen: ref must be passed in value");
            const P = this.toName(v),
              { prefix: S } = P,
              h = (E = y.key) !== null && E !== void 0 ? E : y.ref;
            let b = this._values[S];
            if (b) {
              const t = b.get(h);
              if (t) return t;
            } else b = this._values[S] = new Map();
            b.set(h, P);
            const s = this._scope[S] || (this._scope[S] = []),
              a = s.length;
            return (
              (s[a] = y.ref),
              P.setValue(y, { property: S, itemIndex: a }),
              P
            );
          }
          getValue(v, y) {
            const E = this._values[v];
            if (E) return E.get(y);
          }
          scopeRefs(v, y = this._values) {
            return this._reduceValues(y, (E) => {
              if (E.scopePath === void 0)
                throw new Error(`CodeGen: name "${E}" has no value`);
              return (0, r._)`${v}${E.scopePath}`;
            });
          }
          scopeCode(v = this._values, y, E) {
            return this._reduceValues(
              v,
              (P) => {
                if (P.value === void 0)
                  throw new Error(`CodeGen: name "${P}" has no value`);
                return P.value.code;
              },
              y,
              E,
            );
          }
          _reduceValues(v, y, E = {}, P) {
            let S = r.nil;
            for (const h in v) {
              const b = v[h];
              if (!b) continue;
              const s = (E[h] = E[h] || new Map());
              b.forEach((a) => {
                if (s.has(a)) return;
                s.set(a, i.Started);
                let t = y(a);
                if (t) {
                  const n = this.opts.es5 ? e.varKinds.var : e.varKinds.const;
                  S = (0, r._)`${S}${n} ${a} = ${t};${this.opts._n}`;
                } else if ((t = P?.(a))) S = (0, r._)`${S}${t}${this.opts._n}`;
                else throw new p(a);
                s.set(a, i.Completed);
              });
            }
            return S;
          }
        }
        e.ValueScope = u;
      })(Tt)),
    Tt
  );
}
var Jt;
function J() {
  return (
    Jt ||
      ((Jt = 1),
      (function (e) {
        (Object.defineProperty(e, "__esModule", { value: !0 }),
          (e.or =
            e.and =
            e.not =
            e.CodeGen =
            e.operators =
            e.varKinds =
            e.ValueScopeName =
            e.ValueScope =
            e.Scope =
            e.Name =
            e.regexpCode =
            e.stringify =
            e.getProperty =
            e.nil =
            e.strConcat =
            e.str =
            e._ =
              void 0));
        const r = yt(),
          p = Gt();
        var i = yt();
        (Object.defineProperty(e, "_", {
          enumerable: !0,
          get: function () {
            return i._;
          },
        }),
          Object.defineProperty(e, "str", {
            enumerable: !0,
            get: function () {
              return i.str;
            },
          }),
          Object.defineProperty(e, "strConcat", {
            enumerable: !0,
            get: function () {
              return i.strConcat;
            },
          }),
          Object.defineProperty(e, "nil", {
            enumerable: !0,
            get: function () {
              return i.nil;
            },
          }),
          Object.defineProperty(e, "getProperty", {
            enumerable: !0,
            get: function () {
              return i.getProperty;
            },
          }),
          Object.defineProperty(e, "stringify", {
            enumerable: !0,
            get: function () {
              return i.stringify;
            },
          }),
          Object.defineProperty(e, "regexpCode", {
            enumerable: !0,
            get: function () {
              return i.regexpCode;
            },
          }),
          Object.defineProperty(e, "Name", {
            enumerable: !0,
            get: function () {
              return i.Name;
            },
          }));
        var g = Gt();
        (Object.defineProperty(e, "Scope", {
          enumerable: !0,
          get: function () {
            return g.Scope;
          },
        }),
          Object.defineProperty(e, "ValueScope", {
            enumerable: !0,
            get: function () {
              return g.ValueScope;
            },
          }),
          Object.defineProperty(e, "ValueScopeName", {
            enumerable: !0,
            get: function () {
              return g.ValueScopeName;
            },
          }),
          Object.defineProperty(e, "varKinds", {
            enumerable: !0,
            get: function () {
              return g.varKinds;
            },
          }),
          (e.operators = {
            GT: new r._Code(">"),
            GTE: new r._Code(">="),
            LT: new r._Code("<"),
            LTE: new r._Code("<="),
            EQ: new r._Code("==="),
            NEQ: new r._Code("!=="),
            NOT: new r._Code("!"),
            OR: new r._Code("||"),
            AND: new r._Code("&&"),
            ADD: new r._Code("+"),
          }));
        class o {
          optimizeNodes() {
            return this;
          }
          optimizeNames(c, w) {
            return this;
          }
        }
        class l extends o {
          constructor(c, w, j) {
            (super(), (this.varKind = c), (this.name = w), (this.rhs = j));
          }
          render({ es5: c, _n: w }) {
            const j = c ? p.varKinds.var : this.varKind,
              U = this.rhs === void 0 ? "" : ` = ${this.rhs}`;
            return `${j} ${this.name}${U};` + w;
          }
          optimizeNames(c, w) {
            if (c[this.name.str])
              return (this.rhs && (this.rhs = L(this.rhs, c, w)), this);
          }
          get names() {
            return this.rhs instanceof r._CodeOrName ? this.rhs.names : {};
          }
        }
        class u extends o {
          constructor(c, w, j) {
            (super(), (this.lhs = c), (this.rhs = w), (this.sideEffects = j));
          }
          render({ _n: c }) {
            return `${this.lhs} = ${this.rhs};` + c;
          }
          optimizeNames(c, w) {
            if (!(
              this.lhs instanceof r.Name &&
              !c[this.lhs.str] &&
              !this.sideEffects
            ))
              return ((this.rhs = L(this.rhs, c, w)), this);
          }
          get names() {
            const c = this.lhs instanceof r.Name ? {} : { ...this.lhs.names };
            return z(c, this.rhs);
          }
        }
        class f extends u {
          constructor(c, w, j, U) {
            (super(c, j, U), (this.op = w));
          }
          render({ _n: c }) {
            return `${this.lhs} ${this.op}= ${this.rhs};` + c;
          }
        }
        class v extends o {
          constructor(c) {
            (super(), (this.label = c), (this.names = {}));
          }
          render({ _n: c }) {
            return `${this.label}:` + c;
          }
        }
        class y extends o {
          constructor(c) {
            (super(), (this.label = c), (this.names = {}));
          }
          render({ _n: c }) {
            return `break${this.label ? ` ${this.label}` : ""};` + c;
          }
        }
        class E extends o {
          constructor(c) {
            (super(), (this.error = c));
          }
          render({ _n: c }) {
            return `throw ${this.error};` + c;
          }
          get names() {
            return this.error.names;
          }
        }
        class P extends o {
          constructor(c) {
            (super(), (this.code = c));
          }
          render({ _n: c }) {
            return `${this.code};` + c;
          }
          optimizeNodes() {
            return `${this.code}` ? this : void 0;
          }
          optimizeNames(c, w) {
            return ((this.code = L(this.code, c, w)), this);
          }
          get names() {
            return this.code instanceof r._CodeOrName ? this.code.names : {};
          }
        }
        class S extends o {
          constructor(c = []) {
            (super(), (this.nodes = c));
          }
          render(c) {
            return this.nodes.reduce((w, j) => w + j.render(c), "");
          }
          optimizeNodes() {
            const { nodes: c } = this;
            let w = c.length;
            for (; w--;) {
              const j = c[w].optimizeNodes();
              Array.isArray(j)
                ? c.splice(w, 1, ...j)
                : j
                  ? (c[w] = j)
                  : c.splice(w, 1);
            }
            return c.length > 0 ? this : void 0;
          }
          optimizeNames(c, w) {
            const { nodes: j } = this;
            let U = j.length;
            for (; U--;) {
              const H = j[U];
              H.optimizeNames(c, w) || (Z(c, H.names), j.splice(U, 1));
            }
            return j.length > 0 ? this : void 0;
          }
          get names() {
            return this.nodes.reduce((c, w) => V(c, w.names), {});
          }
        }
        class h extends S {
          render(c) {
            return "{" + c._n + super.render(c) + "}" + c._n;
          }
        }
        class b extends S {}
        class s extends h {}
        s.kind = "else";
        class a extends h {
          constructor(c, w) {
            (super(w), (this.condition = c));
          }
          render(c) {
            let w = `if(${this.condition})` + super.render(c);
            return (this.else && (w += "else " + this.else.render(c)), w);
          }
          optimizeNodes() {
            super.optimizeNodes();
            const c = this.condition;
            if (c === !0) return this.nodes;
            let w = this.else;
            if (w) {
              const j = w.optimizeNodes();
              w = this.else = Array.isArray(j) ? new s(j) : j;
            }
            if (w)
              return c === !1
                ? w instanceof a
                  ? w
                  : w.nodes
                : this.nodes.length
                  ? this
                  : new a(ne(c), w instanceof a ? [w] : w.nodes);
            if (!(c === !1 || !this.nodes.length)) return this;
          }
          optimizeNames(c, w) {
            var j;
            if (
              ((this.else =
                (j = this.else) === null || j === void 0
                  ? void 0
                  : j.optimizeNames(c, w)),
              !!(super.optimizeNames(c, w) || this.else))
            )
              return ((this.condition = L(this.condition, c, w)), this);
          }
          get names() {
            const c = super.names;
            return (
              z(c, this.condition),
              this.else && V(c, this.else.names),
              c
            );
          }
        }
        a.kind = "if";
        class t extends h {}
        t.kind = "for";
        class n extends t {
          constructor(c) {
            (super(), (this.iteration = c));
          }
          render(c) {
            return `for(${this.iteration})` + super.render(c);
          }
          optimizeNames(c, w) {
            if (super.optimizeNames(c, w))
              return ((this.iteration = L(this.iteration, c, w)), this);
          }
          get names() {
            return V(super.names, this.iteration.names);
          }
        }
        class d extends t {
          constructor(c, w, j, U) {
            (super(),
              (this.varKind = c),
              (this.name = w),
              (this.from = j),
              (this.to = U));
          }
          render(c) {
            const w = c.es5 ? p.varKinds.var : this.varKind,
              { name: j, from: U, to: H } = this;
            return `for(${w} ${j}=${U}; ${j}<${H}; ${j}++)` + super.render(c);
          }
          get names() {
            const c = z(super.names, this.from);
            return z(c, this.to);
          }
        }
        class _ extends t {
          constructor(c, w, j, U) {
            (super(),
              (this.loop = c),
              (this.varKind = w),
              (this.name = j),
              (this.iterable = U));
          }
          render(c) {
            return (
              `for(${this.varKind} ${this.name} ${this.loop} ${this.iterable})` +
              super.render(c)
            );
          }
          optimizeNames(c, w) {
            if (super.optimizeNames(c, w))
              return ((this.iterable = L(this.iterable, c, w)), this);
          }
          get names() {
            return V(super.names, this.iterable.names);
          }
        }
        class m extends h {
          constructor(c, w, j) {
            (super(), (this.name = c), (this.args = w), (this.async = j));
          }
          render(c) {
            return (
              `${this.async ? "async " : ""}function ${this.name}(${this.args})` +
              super.render(c)
            );
          }
        }
        m.kind = "func";
        class $ extends S {
          render(c) {
            return "return " + super.render(c);
          }
        }
        $.kind = "return";
        class T extends h {
          render(c) {
            let w = "try" + super.render(c);
            return (
              this.catch && (w += this.catch.render(c)),
              this.finally && (w += this.finally.render(c)),
              w
            );
          }
          optimizeNodes() {
            var c, w;
            return (
              super.optimizeNodes(),
              (c = this.catch) === null || c === void 0 || c.optimizeNodes(),
              (w = this.finally) === null || w === void 0 || w.optimizeNodes(),
              this
            );
          }
          optimizeNames(c, w) {
            var j, U;
            return (
              super.optimizeNames(c, w),
              (j = this.catch) === null ||
                j === void 0 ||
                j.optimizeNames(c, w),
              (U = this.finally) === null ||
                U === void 0 ||
                U.optimizeNames(c, w),
              this
            );
          }
          get names() {
            const c = super.names;
            return (
              this.catch && V(c, this.catch.names),
              this.finally && V(c, this.finally.names),
              c
            );
          }
        }
        class M extends h {
          constructor(c) {
            (super(), (this.error = c));
          }
          render(c) {
            return `catch(${this.error})` + super.render(c);
          }
        }
        M.kind = "catch";
        class F extends h {
          render(c) {
            return "finally" + super.render(c);
          }
        }
        F.kind = "finally";
        class I {
          constructor(c, w = {}) {
            ((this._values = {}),
              (this._blockStarts = []),
              (this._constants = {}),
              (this.opts = {
                ...w,
                _n: w.lines
                  ? `
`
                  : "",
              }),
              (this._extScope = c),
              (this._scope = new p.Scope({ parent: c })),
              (this._nodes = [new b()]));
          }
          toString() {
            return this._root.render(this.opts);
          }
          name(c) {
            return this._scope.name(c);
          }
          scopeName(c) {
            return this._extScope.name(c);
          }
          scopeValue(c, w) {
            const j = this._extScope.value(c, w);
            return (
              (
                this._values[j.prefix] || (this._values[j.prefix] = new Set())
              ).add(j),
              j
            );
          }
          getScopeValue(c, w) {
            return this._extScope.getValue(c, w);
          }
          scopeRefs(c) {
            return this._extScope.scopeRefs(c, this._values);
          }
          scopeCode() {
            return this._extScope.scopeCode(this._values);
          }
          _def(c, w, j, U) {
            const H = this._scope.toName(w);
            return (
              j !== void 0 && U && (this._constants[H.str] = j),
              this._leafNode(new l(c, H, j)),
              H
            );
          }
          const(c, w, j) {
            return this._def(p.varKinds.const, c, w, j);
          }
          let(c, w, j) {
            return this._def(p.varKinds.let, c, w, j);
          }
          var(c, w, j) {
            return this._def(p.varKinds.var, c, w, j);
          }
          assign(c, w, j) {
            return this._leafNode(new u(c, w, j));
          }
          add(c, w) {
            return this._leafNode(new f(c, e.operators.ADD, w));
          }
          code(c) {
            return (
              typeof c == "function"
                ? c()
                : c !== r.nil && this._leafNode(new P(c)),
              this
            );
          }
          object(...c) {
            const w = ["{"];
            for (const [j, U] of c)
              (w.length > 1 && w.push(","),
                w.push(j),
                (j !== U || this.opts.es5) &&
                  (w.push(":"), (0, r.addCodeArg)(w, U)));
            return (w.push("}"), new r._Code(w));
          }
          if(c, w, j) {
            if ((this._blockNode(new a(c)), w && j))
              this.code(w).else().code(j).endIf();
            else if (w) this.code(w).endIf();
            else if (j)
              throw new Error('CodeGen: "else" body without "then" body');
            return this;
          }
          elseIf(c) {
            return this._elseNode(new a(c));
          }
          else() {
            return this._elseNode(new s());
          }
          endIf() {
            return this._endBlockNode(a, s);
          }
          _for(c, w) {
            return (this._blockNode(c), w && this.code(w).endFor(), this);
          }
          for(c, w) {
            return this._for(new n(c), w);
          }
          forRange(
            c,
            w,
            j,
            U,
            H = this.opts.es5 ? p.varKinds.var : p.varKinds.let,
          ) {
            const X = this._scope.toName(c);
            return this._for(new d(H, X, w, j), () => U(X));
          }
          forOf(c, w, j, U = p.varKinds.const) {
            const H = this._scope.toName(c);
            if (this.opts.es5) {
              const X = w instanceof r.Name ? w : this.var("_arr", w);
              return this.forRange("_i", 0, (0, r._)`${X}.length`, (B) => {
                (this.var(H, (0, r._)`${X}[${B}]`), j(H));
              });
            }
            return this._for(new _("of", U, H, w), () => j(H));
          }
          forIn(
            c,
            w,
            j,
            U = this.opts.es5 ? p.varKinds.var : p.varKinds.const,
          ) {
            if (this.opts.ownProperties)
              return this.forOf(c, (0, r._)`Object.keys(${w})`, j);
            const H = this._scope.toName(c);
            return this._for(new _("in", U, H, w), () => j(H));
          }
          endFor() {
            return this._endBlockNode(t);
          }
          label(c) {
            return this._leafNode(new v(c));
          }
          break(c) {
            return this._leafNode(new y(c));
          }
          return(c) {
            const w = new $();
            if ((this._blockNode(w), this.code(c), w.nodes.length !== 1))
              throw new Error('CodeGen: "return" should have one node');
            return this._endBlockNode($);
          }
          try(c, w, j) {
            if (!w && !j)
              throw new Error('CodeGen: "try" without "catch" and "finally"');
            const U = new T();
            if ((this._blockNode(U), this.code(c), w)) {
              const H = this.name("e");
              ((this._currNode = U.catch = new M(H)), w(H));
            }
            return (
              j && ((this._currNode = U.finally = new F()), this.code(j)),
              this._endBlockNode(M, F)
            );
          }
          throw(c) {
            return this._leafNode(new E(c));
          }
          block(c, w) {
            return (
              this._blockStarts.push(this._nodes.length),
              c && this.code(c).endBlock(w),
              this
            );
          }
          endBlock(c) {
            const w = this._blockStarts.pop();
            if (w === void 0)
              throw new Error("CodeGen: not in self-balancing block");
            const j = this._nodes.length - w;
            if (j < 0 || (c !== void 0 && j !== c))
              throw new Error(
                `CodeGen: wrong number of nodes: ${j} vs ${c} expected`,
              );
            return ((this._nodes.length = w), this);
          }
          func(c, w = r.nil, j, U) {
            return (
              this._blockNode(new m(c, w, j)),
              U && this.code(U).endFunc(),
              this
            );
          }
          endFunc() {
            return this._endBlockNode(m);
          }
          optimize(c = 1) {
            for (; c-- > 0;)
              (this._root.optimizeNodes(),
                this._root.optimizeNames(this._root.names, this._constants));
          }
          _leafNode(c) {
            return (this._currNode.nodes.push(c), this);
          }
          _blockNode(c) {
            (this._currNode.nodes.push(c), this._nodes.push(c));
          }
          _endBlockNode(c, w) {
            const j = this._currNode;
            if (j instanceof c || (w && j instanceof w))
              return (this._nodes.pop(), this);
            throw new Error(
              `CodeGen: not in block "${w ? `${c.kind}/${w.kind}` : c.kind}"`,
            );
          }
          _elseNode(c) {
            const w = this._currNode;
            if (!(w instanceof a))
              throw new Error('CodeGen: "else" without "if"');
            return ((this._currNode = w.else = c), this);
          }
          get _root() {
            return this._nodes[0];
          }
          get _currNode() {
            const c = this._nodes;
            return c[c.length - 1];
          }
          set _currNode(c) {
            const w = this._nodes;
            w[w.length - 1] = c;
          }
        }
        e.CodeGen = I;
        function V(O, c) {
          for (const w in c) O[w] = (O[w] || 0) + (c[w] || 0);
          return O;
        }
        function z(O, c) {
          return c instanceof r._CodeOrName ? V(O, c.names) : O;
        }
        function L(O, c, w) {
          if (O instanceof r.Name) return j(O);
          if (!U(O)) return O;
          return new r._Code(
            O._items.reduce(
              (H, X) => (
                X instanceof r.Name && (X = j(X)),
                X instanceof r._Code ? H.push(...X._items) : H.push(X),
                H
              ),
              [],
            ),
          );
          function j(H) {
            const X = w[H.str];
            return X === void 0 || c[H.str] !== 1 ? H : (delete c[H.str], X);
          }
          function U(H) {
            return (
              H instanceof r._Code &&
              H._items.some(
                (X) =>
                  X instanceof r.Name && c[X.str] === 1 && w[X.str] !== void 0,
              )
            );
          }
        }
        function Z(O, c) {
          for (const w in c) O[w] = (O[w] || 0) - (c[w] || 0);
        }
        function ne(O) {
          return typeof O == "boolean" || typeof O == "number" || O === null
            ? !O
            : (0, r._)`!${C(O)}`;
        }
        e.not = ne;
        const se = N(e.operators.AND);
        function x(...O) {
          return O.reduce(se);
        }
        e.and = x;
        const de = N(e.operators.OR);
        function A(...O) {
          return O.reduce(de);
        }
        e.or = A;
        function N(O) {
          return (c, w) =>
            c === r.nil ? w : w === r.nil ? c : (0, r._)`${C(c)} ${O} ${C(w)}`;
        }
        function C(O) {
          return O instanceof r.Name ? O : (0, r._)`(${O})`;
        }
      })(kt)),
    kt
  );
}
var G = {},
  Wt;
function Y() {
  if (Wt) return G;
  ((Wt = 1),
    Object.defineProperty(G, "__esModule", { value: !0 }),
    (G.checkStrictMode =
      G.getErrorPath =
      G.Type =
      G.useFunc =
      G.setEvaluated =
      G.evaluatedPropsToName =
      G.mergeEvaluated =
      G.eachItem =
      G.unescapeJsonPointer =
      G.escapeJsonPointer =
      G.escapeFragment =
      G.unescapeFragment =
      G.schemaRefOrVal =
      G.schemaHasRulesButRef =
      G.schemaHasRules =
      G.checkUnknownRules =
      G.alwaysValidSchema =
      G.toHash =
        void 0));
  const e = J(),
    r = yt();
  function p(_) {
    const m = {};
    for (const $ of _) m[$] = !0;
    return m;
  }
  G.toHash = p;
  function i(_, m) {
    return typeof m == "boolean"
      ? m
      : Object.keys(m).length === 0
        ? !0
        : (g(_, m), !o(m, _.self.RULES.all));
  }
  G.alwaysValidSchema = i;
  function g(_, m = _.schema) {
    const { opts: $, self: T } = _;
    if (!$.strictSchema || typeof m == "boolean") return;
    const M = T.RULES.keywords;
    for (const F in m) M[F] || d(_, `unknown keyword: "${F}"`);
  }
  G.checkUnknownRules = g;
  function o(_, m) {
    if (typeof _ == "boolean") return !_;
    for (const $ in _) if (m[$]) return !0;
    return !1;
  }
  G.schemaHasRules = o;
  function l(_, m) {
    if (typeof _ == "boolean") return !_;
    for (const $ in _) if ($ !== "$ref" && m.all[$]) return !0;
    return !1;
  }
  G.schemaHasRulesButRef = l;
  function u({ topSchemaRef: _, schemaPath: m }, $, T, M) {
    if (!M) {
      if (typeof $ == "number" || typeof $ == "boolean") return $;
      if (typeof $ == "string") return (0, e._)`${$}`;
    }
    return (0, e._)`${_}${m}${(0, e.getProperty)(T)}`;
  }
  G.schemaRefOrVal = u;
  function f(_) {
    return E(decodeURIComponent(_));
  }
  G.unescapeFragment = f;
  function v(_) {
    return encodeURIComponent(y(_));
  }
  G.escapeFragment = v;
  function y(_) {
    return typeof _ == "number"
      ? `${_}`
      : _.replace(/~/g, "~0").replace(/\//g, "~1");
  }
  G.escapeJsonPointer = y;
  function E(_) {
    return _.replace(/~1/g, "/").replace(/~0/g, "~");
  }
  G.unescapeJsonPointer = E;
  function P(_, m) {
    if (Array.isArray(_)) for (const $ of _) m($);
    else m(_);
  }
  G.eachItem = P;
  function S({
    mergeNames: _,
    mergeToName: m,
    mergeValues: $,
    resultToName: T,
  }) {
    return (M, F, I, V) => {
      const z =
        I === void 0
          ? F
          : I instanceof e.Name
            ? (F instanceof e.Name ? _(M, F, I) : m(M, F, I), I)
            : F instanceof e.Name
              ? (m(M, I, F), F)
              : $(F, I);
      return V === e.Name && !(z instanceof e.Name) ? T(M, z) : z;
    };
  }
  G.mergeEvaluated = {
    props: S({
      mergeNames: (_, m, $) =>
        _.if((0, e._)`${$} !== true && ${m} !== undefined`, () => {
          _.if(
            (0, e._)`${m} === true`,
            () => _.assign($, !0),
            () =>
              _.assign($, (0, e._)`${$} || {}`).code(
                (0, e._)`Object.assign(${$}, ${m})`,
              ),
          );
        }),
      mergeToName: (_, m, $) =>
        _.if((0, e._)`${$} !== true`, () => {
          m === !0
            ? _.assign($, !0)
            : (_.assign($, (0, e._)`${$} || {}`), b(_, $, m));
        }),
      mergeValues: (_, m) => (_ === !0 ? !0 : { ..._, ...m }),
      resultToName: h,
    }),
    items: S({
      mergeNames: (_, m, $) =>
        _.if((0, e._)`${$} !== true && ${m} !== undefined`, () =>
          _.assign(
            $,
            (0, e._)`${m} === true ? true : ${$} > ${m} ? ${$} : ${m}`,
          ),
        ),
      mergeToName: (_, m, $) =>
        _.if((0, e._)`${$} !== true`, () =>
          _.assign($, m === !0 ? !0 : (0, e._)`${$} > ${m} ? ${$} : ${m}`),
        ),
      mergeValues: (_, m) => (_ === !0 ? !0 : Math.max(_, m)),
      resultToName: (_, m) => _.var("items", m),
    }),
  };
  function h(_, m) {
    if (m === !0) return _.var("props", !0);
    const $ = _.var("props", (0, e._)`{}`);
    return (m !== void 0 && b(_, $, m), $);
  }
  G.evaluatedPropsToName = h;
  function b(_, m, $) {
    Object.keys($).forEach((T) =>
      _.assign((0, e._)`${m}${(0, e.getProperty)(T)}`, !0),
    );
  }
  G.setEvaluated = b;
  const s = {};
  function a(_, m) {
    return _.scopeValue("func", {
      ref: m,
      code: s[m.code] || (s[m.code] = new r._Code(m.code)),
    });
  }
  G.useFunc = a;
  var t;
  (function (_) {
    ((_[(_.Num = 0)] = "Num"), (_[(_.Str = 1)] = "Str"));
  })(t || (G.Type = t = {}));
  function n(_, m, $) {
    if (_ instanceof e.Name) {
      const T = m === t.Num;
      return $
        ? T
          ? (0, e._)`"[" + ${_} + "]"`
          : (0, e._)`"['" + ${_} + "']"`
        : T
          ? (0, e._)`"/" + ${_}`
          : (0, e._)`"/" + ${_}.replace(/~/g, "~0").replace(/\\//g, "~1")`;
    }
    return $ ? (0, e.getProperty)(_).toString() : "/" + y(_);
  }
  G.getErrorPath = n;
  function d(_, m, $ = _.opts.strictSchema) {
    if ($) {
      if (((m = `strict mode: ${m}`), $ === !0)) throw new Error(m);
      _.self.logger.warn(m);
    }
  }
  return ((G.checkStrictMode = d), G);
}
var Ie = {},
  Bt;
function ve() {
  if (Bt) return Ie;
  ((Bt = 1), Object.defineProperty(Ie, "__esModule", { value: !0 }));
  const e = J(),
    r = {
      data: new e.Name("data"),
      valCxt: new e.Name("valCxt"),
      instancePath: new e.Name("instancePath"),
      parentData: new e.Name("parentData"),
      parentDataProperty: new e.Name("parentDataProperty"),
      rootData: new e.Name("rootData"),
      dynamicAnchors: new e.Name("dynamicAnchors"),
      vErrors: new e.Name("vErrors"),
      errors: new e.Name("errors"),
      this: new e.Name("this"),
      self: new e.Name("self"),
      scope: new e.Name("scope"),
      json: new e.Name("json"),
      jsonPos: new e.Name("jsonPos"),
      jsonLen: new e.Name("jsonLen"),
      jsonPart: new e.Name("jsonPart"),
    };
  return ((Ie.default = r), Ie);
}
var Yt;
function vt() {
  return (
    Yt ||
      ((Yt = 1),
      (function (e) {
        (Object.defineProperty(e, "__esModule", { value: !0 }),
          (e.extendErrors =
            e.resetErrorsCount =
            e.reportExtraError =
            e.reportError =
            e.keyword$DataError =
            e.keywordError =
              void 0));
        const r = J(),
          p = Y(),
          i = ve();
        ((e.keywordError = {
          message: ({ keyword: s }) =>
            (0, r.str)`must pass "${s}" keyword validation`,
        }),
          (e.keyword$DataError = {
            message: ({ keyword: s, schemaType: a }) =>
              a
                ? (0, r.str)`"${s}" keyword must be ${a} ($data)`
                : (0, r.str)`"${s}" keyword is invalid ($data)`,
          }));
        function g(s, a = e.keywordError, t, n) {
          const { it: d } = s,
            { gen: _, compositeRule: m, allErrors: $ } = d,
            T = E(s, a, t);
          (n ?? (m || $)) ? f(_, T) : v(d, (0, r._)`[${T}]`);
        }
        e.reportError = g;
        function o(s, a = e.keywordError, t) {
          const { it: n } = s,
            { gen: d, compositeRule: _, allErrors: m } = n,
            $ = E(s, a, t);
          (f(d, $), _ || m || v(n, i.default.vErrors));
        }
        e.reportExtraError = o;
        function l(s, a) {
          (s.assign(i.default.errors, a),
            s.if((0, r._)`${i.default.vErrors} !== null`, () =>
              s.if(
                a,
                () => s.assign((0, r._)`${i.default.vErrors}.length`, a),
                () => s.assign(i.default.vErrors, null),
              ),
            ));
        }
        e.resetErrorsCount = l;
        function u({
          gen: s,
          keyword: a,
          schemaValue: t,
          data: n,
          errsCount: d,
          it: _,
        }) {
          if (d === void 0) throw new Error("ajv implementation error");
          const m = s.name("err");
          s.forRange("i", d, i.default.errors, ($) => {
            (s.const(m, (0, r._)`${i.default.vErrors}[${$}]`),
              s.if((0, r._)`${m}.instancePath === undefined`, () =>
                s.assign(
                  (0, r._)`${m}.instancePath`,
                  (0, r.strConcat)(i.default.instancePath, _.errorPath),
                ),
              ),
              s.assign(
                (0, r._)`${m}.schemaPath`,
                (0, r.str)`${_.errSchemaPath}/${a}`,
              ),
              _.opts.verbose &&
                (s.assign((0, r._)`${m}.schema`, t),
                s.assign((0, r._)`${m}.data`, n)));
          });
        }
        e.extendErrors = u;
        function f(s, a) {
          const t = s.const("err", a);
          (s.if(
            (0, r._)`${i.default.vErrors} === null`,
            () => s.assign(i.default.vErrors, (0, r._)`[${t}]`),
            (0, r._)`${i.default.vErrors}.push(${t})`,
          ),
            s.code((0, r._)`${i.default.errors}++`));
        }
        function v(s, a) {
          const { gen: t, validateName: n, schemaEnv: d } = s;
          d.$async
            ? t.throw((0, r._)`new ${s.ValidationError}(${a})`)
            : (t.assign((0, r._)`${n}.errors`, a), t.return(!1));
        }
        const y = {
          keyword: new r.Name("keyword"),
          schemaPath: new r.Name("schemaPath"),
          params: new r.Name("params"),
          propertyName: new r.Name("propertyName"),
          message: new r.Name("message"),
          schema: new r.Name("schema"),
          parentSchema: new r.Name("parentSchema"),
        };
        function E(s, a, t) {
          const { createErrors: n } = s.it;
          return n === !1 ? (0, r._)`{}` : P(s, a, t);
        }
        function P(s, a, t = {}) {
          const { gen: n, it: d } = s,
            _ = [S(d, t), h(s, t)];
          return (b(s, a, _), n.object(..._));
        }
        function S({ errorPath: s }, { instancePath: a }) {
          const t = a
            ? (0, r.str)`${s}${(0, p.getErrorPath)(a, p.Type.Str)}`
            : s;
          return [
            i.default.instancePath,
            (0, r.strConcat)(i.default.instancePath, t),
          ];
        }
        function h(
          { keyword: s, it: { errSchemaPath: a } },
          { schemaPath: t, parentSchema: n },
        ) {
          let d = n ? a : (0, r.str)`${a}/${s}`;
          return (
            t && (d = (0, r.str)`${d}${(0, p.getErrorPath)(t, p.Type.Str)}`),
            [y.schemaPath, d]
          );
        }
        function b(s, { params: a, message: t }, n) {
          const { keyword: d, data: _, schemaValue: m, it: $ } = s,
            { opts: T, propertyName: M, topSchemaRef: F, schemaPath: I } = $;
          (n.push(
            [y.keyword, d],
            [y.params, typeof a == "function" ? a(s) : a || (0, r._)`{}`],
          ),
            T.messages &&
              n.push([y.message, typeof t == "function" ? t(s) : t]),
            T.verbose &&
              n.push(
                [y.schema, m],
                [y.parentSchema, (0, r._)`${F}${I}`],
                [i.default.data, _],
              ),
            M && n.push([y.propertyName, M]));
        }
      })(Nt)),
    Nt
  );
}
var Xt;
function kn() {
  if (Xt) return ge;
  ((Xt = 1),
    Object.defineProperty(ge, "__esModule", { value: !0 }),
    (ge.boolOrEmptySchema = ge.topBoolOrEmptySchema = void 0));
  const e = vt(),
    r = J(),
    p = ve(),
    i = { message: "boolean schema is false" };
  function g(u) {
    const { gen: f, schema: v, validateName: y } = u;
    v === !1
      ? l(u, !1)
      : typeof v == "object" && v.$async === !0
        ? f.return(p.default.data)
        : (f.assign((0, r._)`${y}.errors`, null), f.return(!0));
  }
  ge.topBoolOrEmptySchema = g;
  function o(u, f) {
    const { gen: v, schema: y } = u;
    y === !1 ? (v.var(f, !1), l(u)) : v.var(f, !0);
  }
  ge.boolOrEmptySchema = o;
  function l(u, f) {
    const { gen: v, data: y } = u,
      E = {
        gen: v,
        keyword: "false schema",
        data: y,
        schema: !1,
        schemaCode: !1,
        schemaValue: !1,
        params: {},
        it: u,
      };
    (0, e.reportError)(E, i, void 0, f);
  }
  return ge;
}
var re = {},
  $e = {},
  Zt;
function on() {
  if (Zt) return $e;
  ((Zt = 1),
    Object.defineProperty($e, "__esModule", { value: !0 }),
    ($e.getRules = $e.isJSONType = void 0));
  const e = [
      "string",
      "number",
      "integer",
      "boolean",
      "null",
      "object",
      "array",
    ],
    r = new Set(e);
  function p(g) {
    return typeof g == "string" && r.has(g);
  }
  $e.isJSONType = p;
  function i() {
    const g = {
      number: { type: "number", rules: [] },
      string: { type: "string", rules: [] },
      array: { type: "array", rules: [] },
      object: { type: "object", rules: [] },
    };
    return {
      types: { ...g, integer: !0, boolean: !0, null: !0 },
      rules: [{ rules: [] }, g.number, g.string, g.array, g.object],
      post: { rules: [] },
      all: {},
      keywords: {},
    };
  }
  return (($e.getRules = i), $e);
}
var pe = {},
  Qt;
function un() {
  if (Qt) return pe;
  ((Qt = 1),
    Object.defineProperty(pe, "__esModule", { value: !0 }),
    (pe.shouldUseRule = pe.shouldUseGroup = pe.schemaHasRulesForType = void 0));
  function e({ schema: i, self: g }, o) {
    const l = g.RULES.types[o];
    return l && l !== !0 && r(i, l);
  }
  pe.schemaHasRulesForType = e;
  function r(i, g) {
    return g.rules.some((o) => p(i, o));
  }
  pe.shouldUseGroup = r;
  function p(i, g) {
    var o;
    return (
      i[g.keyword] !== void 0 ||
      ((o = g.definition.implements) === null || o === void 0
        ? void 0
        : o.some((l) => i[l] !== void 0))
    );
  }
  return ((pe.shouldUseRule = p), pe);
}
var xt;
function _t() {
  if (xt) return re;
  ((xt = 1),
    Object.defineProperty(re, "__esModule", { value: !0 }),
    (re.reportTypeError =
      re.checkDataTypes =
      re.checkDataType =
      re.coerceAndCheckDataType =
      re.getJSONTypes =
      re.getSchemaTypes =
      re.DataType =
        void 0));
  const e = on(),
    r = un(),
    p = vt(),
    i = J(),
    g = Y();
  var o;
  (function (t) {
    ((t[(t.Correct = 0)] = "Correct"), (t[(t.Wrong = 1)] = "Wrong"));
  })(o || (re.DataType = o = {}));
  function l(t) {
    const n = u(t.type);
    if (n.includes("null")) {
      if (t.nullable === !1)
        throw new Error("type: null contradicts nullable: false");
    } else {
      if (!n.length && t.nullable !== void 0)
        throw new Error('"nullable" cannot be used without "type"');
      t.nullable === !0 && n.push("null");
    }
    return n;
  }
  re.getSchemaTypes = l;
  function u(t) {
    const n = Array.isArray(t) ? t : t ? [t] : [];
    if (n.every(e.isJSONType)) return n;
    throw new Error("type must be JSONType or JSONType[]: " + n.join(","));
  }
  re.getJSONTypes = u;
  function f(t, n) {
    const { gen: d, data: _, opts: m } = t,
      $ = y(n, m.coerceTypes),
      T =
        n.length > 0 &&
        !(
          $.length === 0 &&
          n.length === 1 &&
          (0, r.schemaHasRulesForType)(t, n[0])
        );
    if (T) {
      const M = h(n, _, m.strictNumbers, o.Wrong);
      d.if(M, () => {
        $.length ? E(t, n, $) : s(t);
      });
    }
    return T;
  }
  re.coerceAndCheckDataType = f;
  const v = new Set(["string", "number", "integer", "boolean", "null"]);
  function y(t, n) {
    return n
      ? t.filter((d) => v.has(d) || (n === "array" && d === "array"))
      : [];
  }
  function E(t, n, d) {
    const { gen: _, data: m, opts: $ } = t,
      T = _.let("dataType", (0, i._)`typeof ${m}`),
      M = _.let("coerced", (0, i._)`undefined`);
    ($.coerceTypes === "array" &&
      _.if(
        (0, i._)`${T} == 'object' && Array.isArray(${m}) && ${m}.length == 1`,
        () =>
          _.assign(m, (0, i._)`${m}[0]`)
            .assign(T, (0, i._)`typeof ${m}`)
            .if(h(n, m, $.strictNumbers), () => _.assign(M, m)),
      ),
      _.if((0, i._)`${M} !== undefined`));
    for (const I of d)
      (v.has(I) || (I === "array" && $.coerceTypes === "array")) && F(I);
    (_.else(),
      s(t),
      _.endIf(),
      _.if((0, i._)`${M} !== undefined`, () => {
        (_.assign(m, M), P(t, M));
      }));
    function F(I) {
      switch (I) {
        case "string":
          _.elseIf((0, i._)`${T} == "number" || ${T} == "boolean"`)
            .assign(M, (0, i._)`"" + ${m}`)
            .elseIf((0, i._)`${m} === null`)
            .assign(M, (0, i._)`""`);
          return;
        case "number":
          _.elseIf(
            (0, i._)`${T} == "boolean" || ${m} === null
              || (${T} == "string" && ${m} && ${m} == +${m})`,
          ).assign(M, (0, i._)`+${m}`);
          return;
        case "integer":
          _.elseIf(
            (0, i._)`${T} === "boolean" || ${m} === null
              || (${T} === "string" && ${m} && ${m} == +${m} && !(${m} % 1))`,
          ).assign(M, (0, i._)`+${m}`);
          return;
        case "boolean":
          _.elseIf((0, i._)`${m} === "false" || ${m} === 0 || ${m} === null`)
            .assign(M, !1)
            .elseIf((0, i._)`${m} === "true" || ${m} === 1`)
            .assign(M, !0);
          return;
        case "null":
          (_.elseIf((0, i._)`${m} === "" || ${m} === 0 || ${m} === false`),
            _.assign(M, null));
          return;
        case "array":
          _.elseIf(
            (0, i._)`${T} === "string" || ${T} === "number"
              || ${T} === "boolean" || ${m} === null`,
          ).assign(M, (0, i._)`[${m}]`);
      }
    }
  }
  function P({ gen: t, parentData: n, parentDataProperty: d }, _) {
    t.if((0, i._)`${n} !== undefined`, () => t.assign((0, i._)`${n}[${d}]`, _));
  }
  function S(t, n, d, _ = o.Correct) {
    const m = _ === o.Correct ? i.operators.EQ : i.operators.NEQ;
    let $;
    switch (t) {
      case "null":
        return (0, i._)`${n} ${m} null`;
      case "array":
        $ = (0, i._)`Array.isArray(${n})`;
        break;
      case "object":
        $ = (0, i._)`${n} && typeof ${n} == "object" && !Array.isArray(${n})`;
        break;
      case "integer":
        $ = T((0, i._)`!(${n} % 1) && !isNaN(${n})`);
        break;
      case "number":
        $ = T();
        break;
      default:
        return (0, i._)`typeof ${n} ${m} ${t}`;
    }
    return _ === o.Correct ? $ : (0, i.not)($);
    function T(M = i.nil) {
      return (0, i.and)(
        (0, i._)`typeof ${n} == "number"`,
        M,
        d ? (0, i._)`isFinite(${n})` : i.nil,
      );
    }
  }
  re.checkDataType = S;
  function h(t, n, d, _) {
    if (t.length === 1) return S(t[0], n, d, _);
    let m;
    const $ = (0, g.toHash)(t);
    if ($.array && $.object) {
      const T = (0, i._)`typeof ${n} != "object"`;
      ((m = $.null ? T : (0, i._)`!${n} || ${T}`),
        delete $.null,
        delete $.array,
        delete $.object);
    } else m = i.nil;
    $.number && delete $.integer;
    for (const T in $) m = (0, i.and)(m, S(T, n, d, _));
    return m;
  }
  re.checkDataTypes = h;
  const b = {
    message: ({ schema: t }) => `must be ${t}`,
    params: ({ schema: t, schemaValue: n }) =>
      typeof t == "string" ? (0, i._)`{type: ${t}}` : (0, i._)`{type: ${n}}`,
  };
  function s(t) {
    const n = a(t);
    (0, p.reportError)(n, b);
  }
  re.reportTypeError = s;
  function a(t) {
    const { gen: n, data: d, schema: _ } = t,
      m = (0, g.schemaRefOrVal)(t, _, "type");
    return {
      gen: n,
      keyword: "type",
      data: d,
      schema: _.type,
      schemaCode: m,
      schemaValue: m,
      parentSchema: _,
      params: {},
      it: t,
    };
  }
  return re;
}
var Re = {},
  er;
function On() {
  if (er) return Re;
  ((er = 1),
    Object.defineProperty(Re, "__esModule", { value: !0 }),
    (Re.assignDefaults = void 0));
  const e = J(),
    r = Y();
  function p(g, o) {
    const { properties: l, items: u } = g.schema;
    if (o === "object" && l) for (const f in l) i(g, f, l[f].default);
    else
      o === "array" &&
        Array.isArray(u) &&
        u.forEach((f, v) => i(g, v, f.default));
  }
  Re.assignDefaults = p;
  function i(g, o, l) {
    const { gen: u, compositeRule: f, data: v, opts: y } = g;
    if (l === void 0) return;
    const E = (0, e._)`${v}${(0, e.getProperty)(o)}`;
    if (f) {
      (0, r.checkStrictMode)(g, `default is ignored for: ${E}`);
      return;
    }
    let P = (0, e._)`${E} === undefined`;
    (y.useDefaults === "empty" &&
      (P = (0, e._)`${P} || ${E} === null || ${E} === ""`),
      u.if(P, (0, e._)`${E} = ${(0, e.stringify)(l)}`));
  }
  return Re;
}
var fe = {},
  Q = {},
  tr;
function he() {
  if (tr) return Q;
  ((tr = 1),
    Object.defineProperty(Q, "__esModule", { value: !0 }),
    (Q.validateUnion =
      Q.validateArray =
      Q.usePattern =
      Q.callValidateCode =
      Q.schemaProperties =
      Q.allSchemaProperties =
      Q.noPropertyInData =
      Q.propertyInData =
      Q.isOwnProperty =
      Q.hasPropFunc =
      Q.reportMissingProp =
      Q.checkMissingProp =
      Q.checkReportMissingProp =
        void 0));
  const e = J(),
    r = Y(),
    p = ve(),
    i = Y();
  function g(t, n) {
    const { gen: d, data: _, it: m } = t;
    d.if(y(d, _, n, m.opts.ownProperties), () => {
      (t.setParams({ missingProperty: (0, e._)`${n}` }, !0), t.error());
    });
  }
  Q.checkReportMissingProp = g;
  function o({ gen: t, data: n, it: { opts: d } }, _, m) {
    return (0, e.or)(
      ..._.map(($) =>
        (0, e.and)(y(t, n, $, d.ownProperties), (0, e._)`${m} = ${$}`),
      ),
    );
  }
  Q.checkMissingProp = o;
  function l(t, n) {
    (t.setParams({ missingProperty: n }, !0), t.error());
  }
  Q.reportMissingProp = l;
  function u(t) {
    return t.scopeValue("func", {
      ref: Object.prototype.hasOwnProperty,
      code: (0, e._)`Object.prototype.hasOwnProperty`,
    });
  }
  Q.hasPropFunc = u;
  function f(t, n, d) {
    return (0, e._)`${u(t)}.call(${n}, ${d})`;
  }
  Q.isOwnProperty = f;
  function v(t, n, d, _) {
    const m = (0, e._)`${n}${(0, e.getProperty)(d)} !== undefined`;
    return _ ? (0, e._)`${m} && ${f(t, n, d)}` : m;
  }
  Q.propertyInData = v;
  function y(t, n, d, _) {
    const m = (0, e._)`${n}${(0, e.getProperty)(d)} === undefined`;
    return _ ? (0, e.or)(m, (0, e.not)(f(t, n, d))) : m;
  }
  Q.noPropertyInData = y;
  function E(t) {
    return t ? Object.keys(t).filter((n) => n !== "__proto__") : [];
  }
  Q.allSchemaProperties = E;
  function P(t, n) {
    return E(n).filter((d) => !(0, r.alwaysValidSchema)(t, n[d]));
  }
  Q.schemaProperties = P;
  function S(
    {
      schemaCode: t,
      data: n,
      it: { gen: d, topSchemaRef: _, schemaPath: m, errorPath: $ },
      it: T,
    },
    M,
    F,
    I,
  ) {
    const V = I ? (0, e._)`${t}, ${n}, ${_}${m}` : n,
      z = [
        [p.default.instancePath, (0, e.strConcat)(p.default.instancePath, $)],
        [p.default.parentData, T.parentData],
        [p.default.parentDataProperty, T.parentDataProperty],
        [p.default.rootData, p.default.rootData],
      ];
    T.opts.dynamicRef &&
      z.push([p.default.dynamicAnchors, p.default.dynamicAnchors]);
    const L = (0, e._)`${V}, ${d.object(...z)}`;
    return F !== e.nil ? (0, e._)`${M}.call(${F}, ${L})` : (0, e._)`${M}(${L})`;
  }
  Q.callValidateCode = S;
  const h = (0, e._)`new RegExp`;
  function b({ gen: t, it: { opts: n } }, d) {
    const _ = n.unicodeRegExp ? "u" : "",
      { regExp: m } = n.code,
      $ = m(d, _);
    return t.scopeValue("pattern", {
      key: $.toString(),
      ref: $,
      code: (0,
      e._)`${m.code === "new RegExp" ? h : (0, i.useFunc)(t, m)}(${d}, ${_})`,
    });
  }
  Q.usePattern = b;
  function s(t) {
    const { gen: n, data: d, keyword: _, it: m } = t,
      $ = n.name("valid");
    if (m.allErrors) {
      const M = n.let("valid", !0);
      return (T(() => n.assign(M, !1)), M);
    }
    return (n.var($, !0), T(() => n.break()), $);
    function T(M) {
      const F = n.const("len", (0, e._)`${d}.length`);
      n.forRange("i", 0, F, (I) => {
        (t.subschema({ keyword: _, dataProp: I, dataPropType: r.Type.Num }, $),
          n.if((0, e.not)($), M));
      });
    }
  }
  Q.validateArray = s;
  function a(t) {
    const { gen: n, schema: d, keyword: _, it: m } = t;
    if (!Array.isArray(d)) throw new Error("ajv implementation error");
    if (d.some((F) => (0, r.alwaysValidSchema)(m, F)) && !m.opts.unevaluated)
      return;
    const T = n.let("valid", !1),
      M = n.name("_valid");
    (n.block(() =>
      d.forEach((F, I) => {
        const V = t.subschema(
          { keyword: _, schemaProp: I, compositeRule: !0 },
          M,
        );
        (n.assign(T, (0, e._)`${T} || ${M}`),
          t.mergeValidEvaluated(V, M) || n.if((0, e.not)(T)));
      }),
    ),
      t.result(
        T,
        () => t.reset(),
        () => t.error(!0),
      ));
  }
  return ((Q.validateUnion = a), Q);
}
var rr;
function Tn() {
  if (rr) return fe;
  ((rr = 1),
    Object.defineProperty(fe, "__esModule", { value: !0 }),
    (fe.validateKeywordUsage =
      fe.validSchemaType =
      fe.funcKeywordCode =
      fe.macroKeywordCode =
        void 0));
  const e = J(),
    r = ve(),
    p = he(),
    i = vt();
  function g(P, S) {
    const { gen: h, keyword: b, schema: s, parentSchema: a, it: t } = P,
      n = S.macro.call(t.self, s, a, t),
      d = v(h, b, n);
    t.opts.validateSchema !== !1 && t.self.validateSchema(n, !0);
    const _ = h.name("valid");
    (P.subschema(
      {
        schema: n,
        schemaPath: e.nil,
        errSchemaPath: `${t.errSchemaPath}/${b}`,
        topSchemaRef: d,
        compositeRule: !0,
      },
      _,
    ),
      P.pass(_, () => P.error(!0)));
  }
  fe.macroKeywordCode = g;
  function o(P, S) {
    var h;
    const {
      gen: b,
      keyword: s,
      schema: a,
      parentSchema: t,
      $data: n,
      it: d,
    } = P;
    f(d, S);
    const _ = !n && S.compile ? S.compile.call(d.self, a, t, d) : S.validate,
      m = v(b, s, _),
      $ = b.let("valid");
    (P.block$data($, T), P.ok((h = S.valid) !== null && h !== void 0 ? h : $));
    function T() {
      if (S.errors === !1) (I(), S.modifying && l(P), V(() => P.error()));
      else {
        const z = S.async ? M() : F();
        (S.modifying && l(P), V(() => u(P, z)));
      }
    }
    function M() {
      const z = b.let("ruleErrs", null);
      return (
        b.try(
          () => I((0, e._)`await `),
          (L) =>
            b.assign($, !1).if(
              (0, e._)`${L} instanceof ${d.ValidationError}`,
              () => b.assign(z, (0, e._)`${L}.errors`),
              () => b.throw(L),
            ),
        ),
        z
      );
    }
    function F() {
      const z = (0, e._)`${m}.errors`;
      return (b.assign(z, null), I(e.nil), z);
    }
    function I(z = S.async ? (0, e._)`await ` : e.nil) {
      const L = d.opts.passContext ? r.default.this : r.default.self,
        Z = !(("compile" in S && !n) || S.schema === !1);
      b.assign(
        $,
        (0, e._)`${z}${(0, p.callValidateCode)(P, m, L, Z)}`,
        S.modifying,
      );
    }
    function V(z) {
      var L;
      b.if((0, e.not)((L = S.valid) !== null && L !== void 0 ? L : $), z);
    }
  }
  fe.funcKeywordCode = o;
  function l(P) {
    const { gen: S, data: h, it: b } = P;
    S.if(b.parentData, () =>
      S.assign(h, (0, e._)`${b.parentData}[${b.parentDataProperty}]`),
    );
  }
  function u(P, S) {
    const { gen: h } = P;
    h.if(
      (0, e._)`Array.isArray(${S})`,
      () => {
        (h
          .assign(
            r.default.vErrors,
            (0,
            e._)`${r.default.vErrors} === null ? ${S} : ${r.default.vErrors}.concat(${S})`,
          )
          .assign(r.default.errors, (0, e._)`${r.default.vErrors}.length`),
          (0, i.extendErrors)(P));
      },
      () => P.error(),
    );
  }
  function f({ schemaEnv: P }, S) {
    if (S.async && !P.$async) throw new Error("async keyword in sync schema");
  }
  function v(P, S, h) {
    if (h === void 0) throw new Error(`keyword "${S}" failed to compile`);
    return P.scopeValue(
      "keyword",
      typeof h == "function"
        ? { ref: h }
        : { ref: h, code: (0, e.stringify)(h) },
    );
  }
  function y(P, S, h = !1) {
    return (
      !S.length ||
      S.some((b) =>
        b === "array"
          ? Array.isArray(P)
          : b === "object"
            ? P && typeof P == "object" && !Array.isArray(P)
            : typeof P == b || (h && typeof P > "u"),
      )
    );
  }
  fe.validSchemaType = y;
  function E({ schema: P, opts: S, self: h, errSchemaPath: b }, s, a) {
    if (Array.isArray(s.keyword) ? !s.keyword.includes(a) : s.keyword !== a)
      throw new Error("ajv implementation error");
    const t = s.dependencies;
    if (t?.some((n) => !Object.prototype.hasOwnProperty.call(P, n)))
      throw new Error(
        `parent schema must have dependencies of ${a}: ${t.join(",")}`,
      );
    if (s.validateSchema && !s.validateSchema(P[a])) {
      const d =
        `keyword "${a}" value is invalid at path "${b}": ` +
        h.errorsText(s.validateSchema.errors);
      if (S.validateSchema === "log") h.logger.error(d);
      else throw new Error(d);
    }
  }
  return ((fe.validateKeywordUsage = E), fe);
}
var ye = {},
  nr;
function jn() {
  if (nr) return ye;
  ((nr = 1),
    Object.defineProperty(ye, "__esModule", { value: !0 }),
    (ye.extendSubschemaMode =
      ye.extendSubschemaData =
      ye.getSubschema =
        void 0));
  const e = J(),
    r = Y();
  function p(
    o,
    {
      keyword: l,
      schemaProp: u,
      schema: f,
      schemaPath: v,
      errSchemaPath: y,
      topSchemaRef: E,
    },
  ) {
    if (l !== void 0 && f !== void 0)
      throw new Error('both "keyword" and "schema" passed, only one allowed');
    if (l !== void 0) {
      const P = o.schema[l];
      return u === void 0
        ? {
            schema: P,
            schemaPath: (0, e._)`${o.schemaPath}${(0, e.getProperty)(l)}`,
            errSchemaPath: `${o.errSchemaPath}/${l}`,
          }
        : {
            schema: P[u],
            schemaPath: (0,
            e._)`${o.schemaPath}${(0, e.getProperty)(l)}${(0, e.getProperty)(u)}`,
            errSchemaPath: `${o.errSchemaPath}/${l}/${(0, r.escapeFragment)(u)}`,
          };
    }
    if (f !== void 0) {
      if (v === void 0 || y === void 0 || E === void 0)
        throw new Error(
          '"schemaPath", "errSchemaPath" and "topSchemaRef" are required with "schema"',
        );
      return { schema: f, schemaPath: v, topSchemaRef: E, errSchemaPath: y };
    }
    throw new Error('either "keyword" or "schema" must be passed');
  }
  ye.getSubschema = p;
  function i(
    o,
    l,
    { dataProp: u, dataPropType: f, data: v, dataTypes: y, propertyName: E },
  ) {
    if (v !== void 0 && u !== void 0)
      throw new Error('both "data" and "dataProp" passed, only one allowed');
    const { gen: P } = l;
    if (u !== void 0) {
      const { errorPath: h, dataPathArr: b, opts: s } = l,
        a = P.let("data", (0, e._)`${l.data}${(0, e.getProperty)(u)}`, !0);
      (S(a),
        (o.errorPath = (0,
        e.str)`${h}${(0, r.getErrorPath)(u, f, s.jsPropertySyntax)}`),
        (o.parentDataProperty = (0, e._)`${u}`),
        (o.dataPathArr = [...b, o.parentDataProperty]));
    }
    if (v !== void 0) {
      const h = v instanceof e.Name ? v : P.let("data", v, !0);
      (S(h), E !== void 0 && (o.propertyName = E));
    }
    y && (o.dataTypes = y);
    function S(h) {
      ((o.data = h),
        (o.dataLevel = l.dataLevel + 1),
        (o.dataTypes = []),
        (l.definedProperties = new Set()),
        (o.parentData = l.data),
        (o.dataNames = [...l.dataNames, h]));
    }
  }
  ye.extendSubschemaData = i;
  function g(
    o,
    {
      jtdDiscriminator: l,
      jtdMetadata: u,
      compositeRule: f,
      createErrors: v,
      allErrors: y,
    },
  ) {
    (f !== void 0 && (o.compositeRule = f),
      v !== void 0 && (o.createErrors = v),
      y !== void 0 && (o.allErrors = y),
      (o.jtdDiscriminator = l),
      (o.jtdMetadata = u));
  }
  return ((ye.extendSubschemaMode = g), ye);
}
var ae = {},
  jt = { exports: {} },
  sr;
function In() {
  if (sr) return jt.exports;
  sr = 1;
  var e = (jt.exports = function (i, g, o) {
    (typeof g == "function" && ((o = g), (g = {})), (o = g.cb || o));
    var l = typeof o == "function" ? o : o.pre || function () {},
      u = o.post || function () {};
    r(g, l, u, i, "", i);
  });
  ((e.keywords = {
    additionalItems: !0,
    items: !0,
    contains: !0,
    additionalProperties: !0,
    propertyNames: !0,
    not: !0,
    if: !0,
    then: !0,
    else: !0,
  }),
    (e.arrayKeywords = { items: !0, allOf: !0, anyOf: !0, oneOf: !0 }),
    (e.propsKeywords = {
      $defs: !0,
      definitions: !0,
      properties: !0,
      patternProperties: !0,
      dependencies: !0,
    }),
    (e.skipKeywords = {
      default: !0,
      enum: !0,
      const: !0,
      required: !0,
      maximum: !0,
      minimum: !0,
      exclusiveMaximum: !0,
      exclusiveMinimum: !0,
      multipleOf: !0,
      maxLength: !0,
      minLength: !0,
      pattern: !0,
      format: !0,
      maxItems: !0,
      minItems: !0,
      uniqueItems: !0,
      maxProperties: !0,
      minProperties: !0,
    }));
  function r(i, g, o, l, u, f, v, y, E, P) {
    if (l && typeof l == "object" && !Array.isArray(l)) {
      g(l, u, f, v, y, E, P);
      for (var S in l) {
        var h = l[S];
        if (Array.isArray(h)) {
          if (S in e.arrayKeywords)
            for (var b = 0; b < h.length; b++)
              r(i, g, o, h[b], u + "/" + S + "/" + b, f, u, S, l, b);
        } else if (S in e.propsKeywords) {
          if (h && typeof h == "object")
            for (var s in h)
              r(i, g, o, h[s], u + "/" + S + "/" + p(s), f, u, S, l, s);
        } else
          (S in e.keywords || (i.allKeys && !(S in e.skipKeywords))) &&
            r(i, g, o, h, u + "/" + S, f, u, S, l);
      }
      o(l, u, f, v, y, E, P);
    }
  }
  function p(i) {
    return i.replace(/~/g, "~0").replace(/\//g, "~1");
  }
  return jt.exports;
}
var ar;
function gt() {
  if (ar) return ae;
  ((ar = 1),
    Object.defineProperty(ae, "__esModule", { value: !0 }),
    (ae.getSchemaRefs =
      ae.resolveUrl =
      ae.normalizeId =
      ae._getFullPath =
      ae.getFullPath =
      ae.inlineRef =
        void 0));
  const e = Y(),
    r = an(),
    p = In(),
    i = new Set([
      "type",
      "format",
      "pattern",
      "maxLength",
      "minLength",
      "maxProperties",
      "minProperties",
      "maxItems",
      "minItems",
      "maximum",
      "minimum",
      "uniqueItems",
      "multipleOf",
      "required",
      "enum",
      "const",
    ]);
  function g(b, s = !0) {
    return typeof b == "boolean" ? !0 : s === !0 ? !l(b) : s ? u(b) <= s : !1;
  }
  ae.inlineRef = g;
  const o = new Set([
    "$ref",
    "$recursiveRef",
    "$recursiveAnchor",
    "$dynamicRef",
    "$dynamicAnchor",
  ]);
  function l(b) {
    for (const s in b) {
      if (o.has(s)) return !0;
      const a = b[s];
      if ((Array.isArray(a) && a.some(l)) || (typeof a == "object" && l(a)))
        return !0;
    }
    return !1;
  }
  function u(b) {
    let s = 0;
    for (const a in b) {
      if (a === "$ref") return 1 / 0;
      if (
        (s++,
        !i.has(a) &&
          (typeof b[a] == "object" && (0, e.eachItem)(b[a], (t) => (s += u(t))),
          s === 1 / 0))
      )
        return 1 / 0;
    }
    return s;
  }
  function f(b, s = "", a) {
    a !== !1 && (s = E(s));
    const t = b.parse(s);
    return v(b, t);
  }
  ae.getFullPath = f;
  function v(b, s) {
    return b.serialize(s).split("#")[0] + "#";
  }
  ae._getFullPath = v;
  const y = /#\/?$/;
  function E(b) {
    return b ? b.replace(y, "") : "";
  }
  ae.normalizeId = E;
  function P(b, s, a) {
    return ((a = E(a)), b.resolve(s, a));
  }
  ae.resolveUrl = P;
  const S = /^[a-z_][-a-z0-9._]*$/i;
  function h(b, s) {
    if (typeof b == "boolean") return {};
    const { schemaId: a, uriResolver: t } = this.opts,
      n = E(b[a] || s),
      d = { "": n },
      _ = f(t, n, !1),
      m = {},
      $ = new Set();
    return (
      p(b, { allKeys: !0 }, (F, I, V, z) => {
        if (z === void 0) return;
        const L = _ + I;
        let Z = d[z];
        (typeof F[a] == "string" && (Z = ne.call(this, F[a])),
          se.call(this, F.$anchor),
          se.call(this, F.$dynamicAnchor),
          (d[I] = Z));
        function ne(x) {
          const de = this.opts.uriResolver.resolve;
          if (((x = E(Z ? de(Z, x) : x)), $.has(x))) throw M(x);
          $.add(x);
          let A = this.refs[x];
          return (
            typeof A == "string" && (A = this.refs[A]),
            typeof A == "object"
              ? T(F, A.schema, x)
              : x !== E(L) &&
                (x[0] === "#"
                  ? (T(F, m[x], x), (m[x] = F))
                  : (this.refs[x] = L)),
            x
          );
        }
        function se(x) {
          if (typeof x == "string") {
            if (!S.test(x)) throw new Error(`invalid anchor "${x}"`);
            ne.call(this, `#${x}`);
          }
        }
      }),
      m
    );
    function T(F, I, V) {
      if (I !== void 0 && !r(F, I)) throw M(V);
    }
    function M(F) {
      return new Error(`reference "${F}" resolves to more than one schema`);
    }
  }
  return ((ae.getSchemaRefs = h), ae);
}
var or;
function $t() {
  if (or) return me;
  ((or = 1),
    Object.defineProperty(me, "__esModule", { value: !0 }),
    (me.getData = me.KeywordCxt = me.validateFunctionCode = void 0));
  const e = kn(),
    r = _t(),
    p = un(),
    i = _t(),
    g = On(),
    o = Tn(),
    l = jn(),
    u = J(),
    f = ve(),
    v = gt(),
    y = Y(),
    E = vt();
  function P(R) {
    if (_(R) && ($(R), d(R))) {
      s(R);
      return;
    }
    S(R, () => (0, e.topBoolOrEmptySchema)(R));
  }
  me.validateFunctionCode = P;
  function S({ gen: R, validateName: k, schema: q, schemaEnv: D, opts: K }, W) {
    K.code.es5
      ? R.func(
          k,
          (0, u._)`${f.default.data}, ${f.default.valCxt}`,
          D.$async,
          () => {
            (R.code((0, u._)`"use strict"; ${t(q, K)}`), b(R, K), R.code(W));
          },
        )
      : R.func(k, (0, u._)`${f.default.data}, ${h(K)}`, D.$async, () =>
          R.code(t(q, K)).code(W),
        );
  }
  function h(R) {
    return (0,
    u._)`{${f.default.instancePath}="", ${f.default.parentData}, ${f.default.parentDataProperty}, ${f.default.rootData}=${f.default.data}${R.dynamicRef ? (0, u._)`, ${f.default.dynamicAnchors}={}` : u.nil}}={}`;
  }
  function b(R, k) {
    R.if(
      f.default.valCxt,
      () => {
        (R.var(
          f.default.instancePath,
          (0, u._)`${f.default.valCxt}.${f.default.instancePath}`,
        ),
          R.var(
            f.default.parentData,
            (0, u._)`${f.default.valCxt}.${f.default.parentData}`,
          ),
          R.var(
            f.default.parentDataProperty,
            (0, u._)`${f.default.valCxt}.${f.default.parentDataProperty}`,
          ),
          R.var(
            f.default.rootData,
            (0, u._)`${f.default.valCxt}.${f.default.rootData}`,
          ),
          k.dynamicRef &&
            R.var(
              f.default.dynamicAnchors,
              (0, u._)`${f.default.valCxt}.${f.default.dynamicAnchors}`,
            ));
      },
      () => {
        (R.var(f.default.instancePath, (0, u._)`""`),
          R.var(f.default.parentData, (0, u._)`undefined`),
          R.var(f.default.parentDataProperty, (0, u._)`undefined`),
          R.var(f.default.rootData, f.default.data),
          k.dynamicRef && R.var(f.default.dynamicAnchors, (0, u._)`{}`));
      },
    );
  }
  function s(R) {
    const { schema: k, opts: q, gen: D } = R;
    S(R, () => {
      (q.$comment && k.$comment && z(R),
        F(R),
        D.let(f.default.vErrors, null),
        D.let(f.default.errors, 0),
        q.unevaluated && a(R),
        T(R),
        L(R));
    });
  }
  function a(R) {
    const { gen: k, validateName: q } = R;
    ((R.evaluated = k.const("evaluated", (0, u._)`${q}.evaluated`)),
      k.if((0, u._)`${R.evaluated}.dynamicProps`, () =>
        k.assign((0, u._)`${R.evaluated}.props`, (0, u._)`undefined`),
      ),
      k.if((0, u._)`${R.evaluated}.dynamicItems`, () =>
        k.assign((0, u._)`${R.evaluated}.items`, (0, u._)`undefined`),
      ));
  }
  function t(R, k) {
    const q = typeof R == "object" && R[k.schemaId];
    return q && (k.code.source || k.code.process)
      ? (0, u._)`/*# sourceURL=${q} */`
      : u.nil;
  }
  function n(R, k) {
    if (_(R) && ($(R), d(R))) {
      m(R, k);
      return;
    }
    (0, e.boolOrEmptySchema)(R, k);
  }
  function d({ schema: R, self: k }) {
    if (typeof R == "boolean") return !R;
    for (const q in R) if (k.RULES.all[q]) return !0;
    return !1;
  }
  function _(R) {
    return typeof R.schema != "boolean";
  }
  function m(R, k) {
    const { schema: q, gen: D, opts: K } = R;
    (K.$comment && q.$comment && z(R), I(R), V(R));
    const W = D.const("_errs", f.default.errors);
    (T(R, W), D.var(k, (0, u._)`${W} === ${f.default.errors}`));
  }
  function $(R) {
    ((0, y.checkUnknownRules)(R), M(R));
  }
  function T(R, k) {
    if (R.opts.jtd) return ne(R, [], !1, k);
    const q = (0, r.getSchemaTypes)(R.schema),
      D = (0, r.coerceAndCheckDataType)(R, q);
    ne(R, q, !D, k);
  }
  function M(R) {
    const { schema: k, errSchemaPath: q, opts: D, self: K } = R;
    k.$ref &&
      D.ignoreKeywordsWithRef &&
      (0, y.schemaHasRulesButRef)(k, K.RULES) &&
      K.logger.warn(`$ref: keywords ignored in schema at path "${q}"`);
  }
  function F(R) {
    const { schema: k, opts: q } = R;
    k.default !== void 0 &&
      q.useDefaults &&
      q.strictSchema &&
      (0, y.checkStrictMode)(R, "default is ignored in the schema root");
  }
  function I(R) {
    const k = R.schema[R.opts.schemaId];
    k && (R.baseId = (0, v.resolveUrl)(R.opts.uriResolver, R.baseId, k));
  }
  function V(R) {
    if (R.schema.$async && !R.schemaEnv.$async)
      throw new Error("async schema in sync schema");
  }
  function z({ gen: R, schemaEnv: k, schema: q, errSchemaPath: D, opts: K }) {
    const W = q.$comment;
    if (K.$comment === !0) R.code((0, u._)`${f.default.self}.logger.log(${W})`);
    else if (typeof K.$comment == "function") {
      const ee = (0, u.str)`${D}/$comment`,
        le = R.scopeValue("root", { ref: k.root });
      R.code(
        (0, u._)`${f.default.self}.opts.$comment(${W}, ${ee}, ${le}.schema)`,
      );
    }
  }
  function L(R) {
    const {
      gen: k,
      schemaEnv: q,
      validateName: D,
      ValidationError: K,
      opts: W,
    } = R;
    q.$async
      ? k.if(
          (0, u._)`${f.default.errors} === 0`,
          () => k.return(f.default.data),
          () => k.throw((0, u._)`new ${K}(${f.default.vErrors})`),
        )
      : (k.assign((0, u._)`${D}.errors`, f.default.vErrors),
        W.unevaluated && Z(R),
        k.return((0, u._)`${f.default.errors} === 0`));
  }
  function Z({ gen: R, evaluated: k, props: q, items: D }) {
    (q instanceof u.Name && R.assign((0, u._)`${k}.props`, q),
      D instanceof u.Name && R.assign((0, u._)`${k}.items`, D));
  }
  function ne(R, k, q, D) {
    const {
        gen: K,
        schema: W,
        data: ee,
        allErrors: le,
        opts: oe,
        self: ie,
      } = R,
      { RULES: te } = ie;
    if (
      W.$ref &&
      (oe.ignoreKeywordsWithRef || !(0, y.schemaHasRulesButRef)(W, te))
    ) {
      K.block(() => U(R, "$ref", te.all.$ref.definition));
      return;
    }
    (oe.jtd || x(R, k),
      K.block(() => {
        for (const ce of te.rules) be(ce);
        be(te.post);
      }));
    function be(ce) {
      (0, p.shouldUseGroup)(W, ce) &&
        (ce.type
          ? (K.if((0, i.checkDataType)(ce.type, ee, oe.strictNumbers)),
            se(R, ce),
            k.length === 1 &&
              k[0] === ce.type &&
              q &&
              (K.else(), (0, i.reportTypeError)(R)),
            K.endIf())
          : se(R, ce),
        le || K.if((0, u._)`${f.default.errors} === ${D || 0}`));
    }
  }
  function se(R, k) {
    const {
      gen: q,
      schema: D,
      opts: { useDefaults: K },
    } = R;
    (K && (0, g.assignDefaults)(R, k.type),
      q.block(() => {
        for (const W of k.rules)
          (0, p.shouldUseRule)(D, W) && U(R, W.keyword, W.definition, k.type);
      }));
  }
  function x(R, k) {
    R.schemaEnv.meta ||
      !R.opts.strictTypes ||
      (de(R, k), R.opts.allowUnionTypes || A(R, k), N(R, R.dataTypes));
  }
  function de(R, k) {
    if (k.length) {
      if (!R.dataTypes.length) {
        R.dataTypes = k;
        return;
      }
      (k.forEach((q) => {
        O(R.dataTypes, q) ||
          w(R, `type "${q}" not allowed by context "${R.dataTypes.join(",")}"`);
      }),
        c(R, k));
    }
  }
  function A(R, k) {
    k.length > 1 &&
      !(k.length === 2 && k.includes("null")) &&
      w(R, "use allowUnionTypes to allow union type keyword");
  }
  function N(R, k) {
    const q = R.self.RULES.all;
    for (const D in q) {
      const K = q[D];
      if (typeof K == "object" && (0, p.shouldUseRule)(R.schema, K)) {
        const { type: W } = K.definition;
        W.length &&
          !W.some((ee) => C(k, ee)) &&
          w(R, `missing type "${W.join(",")}" for keyword "${D}"`);
      }
    }
  }
  function C(R, k) {
    return R.includes(k) || (k === "number" && R.includes("integer"));
  }
  function O(R, k) {
    return R.includes(k) || (k === "integer" && R.includes("number"));
  }
  function c(R, k) {
    const q = [];
    for (const D of R.dataTypes)
      O(k, D)
        ? q.push(D)
        : k.includes("integer") && D === "number" && q.push("integer");
    R.dataTypes = q;
  }
  function w(R, k) {
    const q = R.schemaEnv.baseId + R.errSchemaPath;
    ((k += ` at "${q}" (strictTypes)`),
      (0, y.checkStrictMode)(R, k, R.opts.strictTypes));
  }
  class j {
    constructor(k, q, D) {
      if (
        ((0, o.validateKeywordUsage)(k, q, D),
        (this.gen = k.gen),
        (this.allErrors = k.allErrors),
        (this.keyword = D),
        (this.data = k.data),
        (this.schema = k.schema[D]),
        (this.$data =
          q.$data && k.opts.$data && this.schema && this.schema.$data),
        (this.schemaValue = (0, y.schemaRefOrVal)(
          k,
          this.schema,
          D,
          this.$data,
        )),
        (this.schemaType = q.schemaType),
        (this.parentSchema = k.schema),
        (this.params = {}),
        (this.it = k),
        (this.def = q),
        this.$data)
      )
        this.schemaCode = k.gen.const("vSchema", B(this.$data, k));
      else if (
        ((this.schemaCode = this.schemaValue),
        !(0, o.validSchemaType)(this.schema, q.schemaType, q.allowUndefined))
      )
        throw new Error(`${D} value must be ${JSON.stringify(q.schemaType)}`);
      ("code" in q ? q.trackErrors : q.errors !== !1) &&
        (this.errsCount = k.gen.const("_errs", f.default.errors));
    }
    result(k, q, D) {
      this.failResult((0, u.not)(k), q, D);
    }
    failResult(k, q, D) {
      (this.gen.if(k),
        D ? D() : this.error(),
        q
          ? (this.gen.else(), q(), this.allErrors && this.gen.endIf())
          : this.allErrors
            ? this.gen.endIf()
            : this.gen.else());
    }
    pass(k, q) {
      this.failResult((0, u.not)(k), void 0, q);
    }
    fail(k) {
      if (k === void 0) {
        (this.error(), this.allErrors || this.gen.if(!1));
        return;
      }
      (this.gen.if(k),
        this.error(),
        this.allErrors ? this.gen.endIf() : this.gen.else());
    }
    fail$data(k) {
      if (!this.$data) return this.fail(k);
      const { schemaCode: q } = this;
      this.fail(
        (0, u._)`${q} !== undefined && (${(0, u.or)(this.invalid$data(), k)})`,
      );
    }
    error(k, q, D) {
      if (q) {
        (this.setParams(q), this._error(k, D), this.setParams({}));
        return;
      }
      this._error(k, D);
    }
    _error(k, q) {
      (k ? E.reportExtraError : E.reportError)(this, this.def.error, q);
    }
    $dataError() {
      (0, E.reportError)(this, this.def.$dataError || E.keyword$DataError);
    }
    reset() {
      if (this.errsCount === void 0)
        throw new Error('add "trackErrors" to keyword definition');
      (0, E.resetErrorsCount)(this.gen, this.errsCount);
    }
    ok(k) {
      this.allErrors || this.gen.if(k);
    }
    setParams(k, q) {
      q ? Object.assign(this.params, k) : (this.params = k);
    }
    block$data(k, q, D = u.nil) {
      this.gen.block(() => {
        (this.check$data(k, D), q());
      });
    }
    check$data(k = u.nil, q = u.nil) {
      if (!this.$data) return;
      const { gen: D, schemaCode: K, schemaType: W, def: ee } = this;
      (D.if((0, u.or)((0, u._)`${K} === undefined`, q)),
        k !== u.nil && D.assign(k, !0),
        (W.length || ee.validateSchema) &&
          (D.elseIf(this.invalid$data()),
          this.$dataError(),
          k !== u.nil && D.assign(k, !1)),
        D.else());
    }
    invalid$data() {
      const { gen: k, schemaCode: q, schemaType: D, def: K, it: W } = this;
      return (0, u.or)(ee(), le());
      function ee() {
        if (D.length) {
          if (!(q instanceof u.Name))
            throw new Error("ajv implementation error");
          const oe = Array.isArray(D) ? D : [D];
          return (0,
          u._)`${(0, i.checkDataTypes)(oe, q, W.opts.strictNumbers, i.DataType.Wrong)}`;
        }
        return u.nil;
      }
      function le() {
        if (K.validateSchema) {
          const oe = k.scopeValue("validate$data", { ref: K.validateSchema });
          return (0, u._)`!${oe}(${q})`;
        }
        return u.nil;
      }
    }
    subschema(k, q) {
      const D = (0, l.getSubschema)(this.it, k);
      ((0, l.extendSubschemaData)(D, this.it, k),
        (0, l.extendSubschemaMode)(D, k));
      const K = { ...this.it, ...D, items: void 0, props: void 0 };
      return (n(K, q), K);
    }
    mergeEvaluated(k, q) {
      const { it: D, gen: K } = this;
      D.opts.unevaluated &&
        (D.props !== !0 &&
          k.props !== void 0 &&
          (D.props = y.mergeEvaluated.props(K, k.props, D.props, q)),
        D.items !== !0 &&
          k.items !== void 0 &&
          (D.items = y.mergeEvaluated.items(K, k.items, D.items, q)));
    }
    mergeValidEvaluated(k, q) {
      const { it: D, gen: K } = this;
      if (D.opts.unevaluated && (D.props !== !0 || D.items !== !0))
        return (K.if(q, () => this.mergeEvaluated(k, u.Name)), !0);
    }
  }
  me.KeywordCxt = j;
  function U(R, k, q, D) {
    const K = new j(R, q, k);
    "code" in q
      ? q.code(K, D)
      : K.$data && q.validate
        ? (0, o.funcKeywordCode)(K, q)
        : "macro" in q
          ? (0, o.macroKeywordCode)(K, q)
          : (q.compile || q.validate) && (0, o.funcKeywordCode)(K, q);
  }
  const H = /^\/(?:[^~]|~0|~1)*$/,
    X = /^([0-9]+)(#|\/(?:[^~]|~0|~1)*)?$/;
  function B(R, { dataLevel: k, dataNames: q, dataPathArr: D }) {
    let K, W;
    if (R === "") return f.default.rootData;
    if (R[0] === "/") {
      if (!H.test(R)) throw new Error(`Invalid JSON-pointer: ${R}`);
      ((K = R), (W = f.default.rootData));
    } else {
      const ie = X.exec(R);
      if (!ie) throw new Error(`Invalid JSON-pointer: ${R}`);
      const te = +ie[1];
      if (((K = ie[2]), K === "#")) {
        if (te >= k) throw new Error(oe("property/index", te));
        return D[k - te];
      }
      if (te > k) throw new Error(oe("data", te));
      if (((W = q[k - te]), !K)) return W;
    }
    let ee = W;
    const le = K.split("/");
    for (const ie of le)
      ie &&
        ((W = (0,
        u._)`${W}${(0, u.getProperty)((0, y.unescapeJsonPointer)(ie))}`),
        (ee = (0, u._)`${ee} && ${W}`));
    return ee;
    function oe(ie, te) {
      return `Cannot access ${ie} ${te} levels up, current level is ${k}`;
    }
  }
  return ((me.getData = B), me);
}
var qe = {},
  ir;
function Vt() {
  if (ir) return qe;
  ((ir = 1), Object.defineProperty(qe, "__esModule", { value: !0 }));
  class e extends Error {
    constructor(p) {
      (super("validation failed"),
        (this.errors = p),
        (this.ajv = this.validation = !0));
    }
  }
  return ((qe.default = e), qe);
}
var Ce = {},
  ur;
function wt() {
  if (ur) return Ce;
  ((ur = 1), Object.defineProperty(Ce, "__esModule", { value: !0 }));
  const e = gt();
  class r extends Error {
    constructor(i, g, o, l) {
      (super(l || `can't resolve reference ${o} from id ${g}`),
        (this.missingRef = (0, e.resolveUrl)(i, g, o)),
        (this.missingSchema = (0, e.normalizeId)(
          (0, e.getFullPath)(i, this.missingRef),
        )));
    }
  }
  return ((Ce.default = r), Ce);
}
var ue = {},
  cr;
function zt() {
  if (cr) return ue;
  ((cr = 1),
    Object.defineProperty(ue, "__esModule", { value: !0 }),
    (ue.resolveSchema =
      ue.getCompilingSchema =
      ue.resolveRef =
      ue.compileSchema =
      ue.SchemaEnv =
        void 0));
  const e = J(),
    r = Vt(),
    p = ve(),
    i = gt(),
    g = Y(),
    o = $t();
  class l {
    constructor(a) {
      var t;
      ((this.refs = {}), (this.dynamicAnchors = {}));
      let n;
      (typeof a.schema == "object" && (n = a.schema),
        (this.schema = a.schema),
        (this.schemaId = a.schemaId),
        (this.root = a.root || this),
        (this.baseId =
          (t = a.baseId) !== null && t !== void 0
            ? t
            : (0, i.normalizeId)(n?.[a.schemaId || "$id"])),
        (this.schemaPath = a.schemaPath),
        (this.localRefs = a.localRefs),
        (this.meta = a.meta),
        (this.$async = n?.$async),
        (this.refs = {}));
    }
  }
  ue.SchemaEnv = l;
  function u(s) {
    const a = y.call(this, s);
    if (a) return a;
    const t = (0, i.getFullPath)(this.opts.uriResolver, s.root.baseId),
      { es5: n, lines: d } = this.opts.code,
      { ownProperties: _ } = this.opts,
      m = new e.CodeGen(this.scope, { es5: n, lines: d, ownProperties: _ });
    let $;
    s.$async &&
      ($ = m.scopeValue("Error", {
        ref: r.default,
        code: (0, e._)`require("ajv/dist/runtime/validation_error").default`,
      }));
    const T = m.scopeName("validate");
    s.validateName = T;
    const M = {
      gen: m,
      allErrors: this.opts.allErrors,
      data: p.default.data,
      parentData: p.default.parentData,
      parentDataProperty: p.default.parentDataProperty,
      dataNames: [p.default.data],
      dataPathArr: [e.nil],
      dataLevel: 0,
      dataTypes: [],
      definedProperties: new Set(),
      topSchemaRef: m.scopeValue(
        "schema",
        this.opts.code.source === !0
          ? { ref: s.schema, code: (0, e.stringify)(s.schema) }
          : { ref: s.schema },
      ),
      validateName: T,
      ValidationError: $,
      schema: s.schema,
      schemaEnv: s,
      rootId: t,
      baseId: s.baseId || t,
      schemaPath: e.nil,
      errSchemaPath: s.schemaPath || (this.opts.jtd ? "" : "#"),
      errorPath: (0, e._)`""`,
      opts: this.opts,
      self: this,
    };
    let F;
    try {
      (this._compilations.add(s),
        (0, o.validateFunctionCode)(M),
        m.optimize(this.opts.code.optimize));
      const I = m.toString();
      ((F = `${m.scopeRefs(p.default.scope)}return ${I}`),
        this.opts.code.process && (F = this.opts.code.process(F, s)));
      const z = new Function(`${p.default.self}`, `${p.default.scope}`, F)(
        this,
        this.scope.get(),
      );
      if (
        (this.scope.value(T, { ref: z }),
        (z.errors = null),
        (z.schema = s.schema),
        (z.schemaEnv = s),
        s.$async && (z.$async = !0),
        this.opts.code.source === !0 &&
          (z.source = {
            validateName: T,
            validateCode: I,
            scopeValues: m._values,
          }),
        this.opts.unevaluated)
      ) {
        const { props: L, items: Z } = M;
        ((z.evaluated = {
          props: L instanceof e.Name ? void 0 : L,
          items: Z instanceof e.Name ? void 0 : Z,
          dynamicProps: L instanceof e.Name,
          dynamicItems: Z instanceof e.Name,
        }),
          z.source && (z.source.evaluated = (0, e.stringify)(z.evaluated)));
      }
      return ((s.validate = z), s);
    } catch (I) {
      throw (
        delete s.validate,
        delete s.validateName,
        F && this.logger.error("Error compiling schema, function code:", F),
        I
      );
    } finally {
      this._compilations.delete(s);
    }
  }
  ue.compileSchema = u;
  function f(s, a, t) {
    var n;
    t = (0, i.resolveUrl)(this.opts.uriResolver, a, t);
    const d = s.refs[t];
    if (d) return d;
    let _ = P.call(this, s, t);
    if (_ === void 0) {
      const m = (n = s.localRefs) === null || n === void 0 ? void 0 : n[t],
        { schemaId: $ } = this.opts;
      m && (_ = new l({ schema: m, schemaId: $, root: s, baseId: a }));
    }
    if (_ !== void 0) return (s.refs[t] = v.call(this, _));
  }
  ue.resolveRef = f;
  function v(s) {
    return (0, i.inlineRef)(s.schema, this.opts.inlineRefs)
      ? s.schema
      : s.validate
        ? s
        : u.call(this, s);
  }
  function y(s) {
    for (const a of this._compilations) if (E(a, s)) return a;
  }
  ue.getCompilingSchema = y;
  function E(s, a) {
    return s.schema === a.schema && s.root === a.root && s.baseId === a.baseId;
  }
  function P(s, a) {
    let t;
    for (; typeof (t = this.refs[a]) == "string";) a = t;
    return t || this.schemas[a] || S.call(this, s, a);
  }
  function S(s, a) {
    const t = this.opts.uriResolver.parse(a),
      n = (0, i._getFullPath)(this.opts.uriResolver, t);
    let d = (0, i.getFullPath)(this.opts.uriResolver, s.baseId, void 0);
    if (Object.keys(s.schema).length > 0 && n === d) return b.call(this, t, s);
    const _ = (0, i.normalizeId)(n),
      m = this.refs[_] || this.schemas[_];
    if (typeof m == "string") {
      const $ = S.call(this, s, m);
      return typeof $?.schema != "object" ? void 0 : b.call(this, t, $);
    }
    if (typeof m?.schema == "object") {
      if ((m.validate || u.call(this, m), _ === (0, i.normalizeId)(a))) {
        const { schema: $ } = m,
          { schemaId: T } = this.opts,
          M = $[T];
        return (
          M && (d = (0, i.resolveUrl)(this.opts.uriResolver, d, M)),
          new l({ schema: $, schemaId: T, root: s, baseId: d })
        );
      }
      return b.call(this, t, m);
    }
  }
  ue.resolveSchema = S;
  const h = new Set([
    "properties",
    "patternProperties",
    "enum",
    "dependencies",
    "definitions",
  ]);
  function b(s, { baseId: a, schema: t, root: n }) {
    var d;
    if (((d = s.fragment) === null || d === void 0 ? void 0 : d[0]) !== "/")
      return;
    for (const $ of s.fragment.slice(1).split("/")) {
      if (typeof t == "boolean") return;
      const T = t[(0, g.unescapeFragment)($)];
      if (T === void 0) return;
      t = T;
      const M = typeof t == "object" && t[this.opts.schemaId];
      !h.has($) && M && (a = (0, i.resolveUrl)(this.opts.uriResolver, a, M));
    }
    let _;
    if (
      typeof t != "boolean" &&
      t.$ref &&
      !(0, g.schemaHasRulesButRef)(t, this.RULES)
    ) {
      const $ = (0, i.resolveUrl)(this.opts.uriResolver, a, t.$ref);
      _ = S.call(this, n, $);
    }
    const { schemaId: m } = this.opts;
    if (
      ((_ = _ || new l({ schema: t, schemaId: m, root: n, baseId: a })),
      _.schema !== _.root.schema)
    )
      return _;
  }
  return ue;
}
const qn =
    "https://raw.githubusercontent.com/ajv-validator/ajv/master/lib/refs/data.json#",
  Cn = "Meta-schema for $data reference (JSON AnySchema extension proposal)",
  Mn = "object",
  An = ["$data"],
  Dn = {
    $data: {
      type: "string",
      anyOf: [{ format: "relative-json-pointer" }, { format: "json-pointer" }],
    },
  },
  Vn = !1,
  zn = {
    $id: qn,
    description: Cn,
    type: Mn,
    required: An,
    properties: Dn,
    additionalProperties: Vn,
  };
var Me = {},
  Ne = { exports: {} },
  It,
  dr;
function Fn() {
  return (
    dr ||
      ((dr = 1),
      (It = {
        HEX: {
          0: 0,
          1: 1,
          2: 2,
          3: 3,
          4: 4,
          5: 5,
          6: 6,
          7: 7,
          8: 8,
          9: 9,
          a: 10,
          A: 10,
          b: 11,
          B: 11,
          c: 12,
          C: 12,
          d: 13,
          D: 13,
          e: 14,
          E: 14,
          f: 15,
          F: 15,
        },
      })),
    It
  );
}
var qt, lr;
function Ln() {
  if (lr) return qt;
  lr = 1;
  const { HEX: e } = Fn();
  function r(h) {
    if (l(h, ".") < 3) return { host: h, isIPV4: !1 };
    const b =
        h.match(
          /^(?:(?:25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9][0-9]|[0-9])\.){3}(?:25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9][0-9]|[0-9])$/u,
        ) || [],
      [s] = b;
    return s ? { host: o(s, "."), isIPV4: !0 } : { host: h, isIPV4: !1 };
  }
  function p(h, b = !1) {
    let s = "",
      a = !0;
    for (const t of h) {
      if (e[t] === void 0) return;
      (t !== "0" && a === !0 && (a = !1), a || (s += t));
    }
    return (b && s.length === 0 && (s = "0"), s);
  }
  function i(h) {
    let b = 0;
    const s = { error: !1, address: "", zone: "" },
      a = [],
      t = [];
    let n = !1,
      d = !1,
      _ = !1;
    function m() {
      if (t.length) {
        if (n === !1) {
          const $ = p(t);
          if ($ !== void 0) a.push($);
          else return ((s.error = !0), !1);
        }
        t.length = 0;
      }
      return !0;
    }
    for (let $ = 0; $ < h.length; $++) {
      const T = h[$];
      if (!(T === "[" || T === "]"))
        if (T === ":") {
          if ((d === !0 && (_ = !0), !m())) break;
          if ((b++, a.push(":"), b > 7)) {
            s.error = !0;
            break;
          }
          $ - 1 >= 0 && h[$ - 1] === ":" && (d = !0);
          continue;
        } else if (T === "%") {
          if (!m()) break;
          n = !0;
        } else {
          t.push(T);
          continue;
        }
    }
    return (
      t.length &&
        (n ? (s.zone = t.join("")) : _ ? a.push(t.join("")) : a.push(p(t))),
      (s.address = a.join("")),
      s
    );
  }
  function g(h, b = {}) {
    if (l(h, ":") < 2) return { host: h, isIPV6: !1 };
    const s = i(h);
    if (s.error) return { host: h, isIPV6: !1 };
    {
      let a = s.address,
        t = s.address;
      return (
        s.zone && ((a += "%" + s.zone), (t += "%25" + s.zone)),
        { host: a, escapedHost: t, isIPV6: !0 }
      );
    }
  }
  function o(h, b) {
    let s = "",
      a = !0;
    const t = h.length;
    for (let n = 0; n < t; n++) {
      const d = h[n];
      d === "0" && a
        ? ((n + 1 <= t && h[n + 1] === b) || n + 1 === t) &&
          ((s += d), (a = !1))
        : (d === b ? (a = !0) : (a = !1), (s += d));
    }
    return s;
  }
  function l(h, b) {
    let s = 0;
    for (let a = 0; a < h.length; a++) h[a] === b && s++;
    return s;
  }
  const u = /^\.\.?\//u,
    f = /^\/\.(?:\/|$)/u,
    v = /^\/\.\.(?:\/|$)/u,
    y = /^\/?(?:.|\n)*?(?=\/|$)/u;
  function E(h) {
    const b = [];
    for (; h.length;)
      if (h.match(u)) h = h.replace(u, "");
      else if (h.match(f)) h = h.replace(f, "/");
      else if (h.match(v)) ((h = h.replace(v, "/")), b.pop());
      else if (h === "." || h === "..") h = "";
      else {
        const s = h.match(y);
        if (s) {
          const a = s[0];
          ((h = h.slice(a.length)), b.push(a));
        } else throw new Error("Unexpected dot segment condition");
      }
    return b.join("");
  }
  function P(h, b) {
    const s = b !== !0 ? escape : unescape;
    return (
      h.scheme !== void 0 && (h.scheme = s(h.scheme)),
      h.userinfo !== void 0 && (h.userinfo = s(h.userinfo)),
      h.host !== void 0 && (h.host = s(h.host)),
      h.path !== void 0 && (h.path = s(h.path)),
      h.query !== void 0 && (h.query = s(h.query)),
      h.fragment !== void 0 && (h.fragment = s(h.fragment)),
      h
    );
  }
  function S(h, b) {
    const s = [];
    if (
      (h.userinfo !== void 0 && (s.push(h.userinfo), s.push("@")),
      h.host !== void 0)
    ) {
      let a = unescape(h.host);
      const t = r(a);
      if (t.isIPV4) a = t.host;
      else {
        const n = g(t.host, {});
        n.isIPV6 === !0 ? (a = `[${n.escapedHost}]`) : (a = h.host);
      }
      s.push(a);
    }
    return (
      (typeof h.port == "number" || typeof h.port == "string") &&
        (s.push(":"), s.push(String(h.port))),
      s.length ? s.join("") : void 0
    );
  }
  return (
    (qt = {
      recomposeAuthority: S,
      normalizeComponentEncoding: P,
      removeDotSegments: E,
      normalizeIPv4: r,
      normalizeIPv6: g,
      stringArrayToHexStripped: p,
    }),
    qt
  );
}
var Ct, fr;
function Un() {
  if (fr) return Ct;
  fr = 1;
  const e =
      /^[\da-f]{8}\b-[\da-f]{4}\b-[\da-f]{4}\b-[\da-f]{4}\b-[\da-f]{12}$/iu,
    r = /([\da-z][\d\-a-z]{0,31}):((?:[\w!$'()*+,\-.:;=@]|%[\da-f]{2})+)/iu;
  function p(t) {
    return typeof t.secure == "boolean"
      ? t.secure
      : String(t.scheme).toLowerCase() === "wss";
  }
  function i(t) {
    return (t.host || (t.error = t.error || "HTTP URIs must have a host."), t);
  }
  function g(t) {
    const n = String(t.scheme).toLowerCase() === "https";
    return (
      (t.port === (n ? 443 : 80) || t.port === "") && (t.port = void 0),
      t.path || (t.path = "/"),
      t
    );
  }
  function o(t) {
    return (
      (t.secure = p(t)),
      (t.resourceName = (t.path || "/") + (t.query ? "?" + t.query : "")),
      (t.path = void 0),
      (t.query = void 0),
      t
    );
  }
  function l(t) {
    if (
      ((t.port === (p(t) ? 443 : 80) || t.port === "") && (t.port = void 0),
      typeof t.secure == "boolean" &&
        ((t.scheme = t.secure ? "wss" : "ws"), (t.secure = void 0)),
      t.resourceName)
    ) {
      const [n, d] = t.resourceName.split("?");
      ((t.path = n && n !== "/" ? n : void 0),
        (t.query = d),
        (t.resourceName = void 0));
    }
    return ((t.fragment = void 0), t);
  }
  function u(t, n) {
    if (!t.path) return ((t.error = "URN can not be parsed"), t);
    const d = t.path.match(r);
    if (d) {
      const _ = n.scheme || t.scheme || "urn";
      ((t.nid = d[1].toLowerCase()), (t.nss = d[2]));
      const m = `${_}:${n.nid || t.nid}`,
        $ = a[m];
      ((t.path = void 0), $ && (t = $.parse(t, n)));
    } else t.error = t.error || "URN can not be parsed.";
    return t;
  }
  function f(t, n) {
    const d = n.scheme || t.scheme || "urn",
      _ = t.nid.toLowerCase(),
      m = `${d}:${n.nid || _}`,
      $ = a[m];
    $ && (t = $.serialize(t, n));
    const T = t,
      M = t.nss;
    return ((T.path = `${_ || n.nid}:${M}`), (n.skipEscape = !0), T);
  }
  function v(t, n) {
    const d = t;
    return (
      (d.uuid = d.nss),
      (d.nss = void 0),
      !n.tolerant &&
        (!d.uuid || !e.test(d.uuid)) &&
        (d.error = d.error || "UUID is not valid."),
      d
    );
  }
  function y(t) {
    const n = t;
    return ((n.nss = (t.uuid || "").toLowerCase()), n);
  }
  const E = { scheme: "http", domainHost: !0, parse: i, serialize: g },
    P = { scheme: "https", domainHost: E.domainHost, parse: i, serialize: g },
    S = { scheme: "ws", domainHost: !0, parse: o, serialize: l },
    h = {
      scheme: "wss",
      domainHost: S.domainHost,
      parse: S.parse,
      serialize: S.serialize,
    },
    a = {
      http: E,
      https: P,
      ws: S,
      wss: h,
      urn: { scheme: "urn", parse: u, serialize: f, skipNormalize: !0 },
      "urn:uuid": {
        scheme: "urn:uuid",
        parse: v,
        serialize: y,
        skipNormalize: !0,
      },
    };
  return ((Ct = a), Ct);
}
var hr;
function Kn() {
  if (hr) return Ne.exports;
  hr = 1;
  const {
      normalizeIPv6: e,
      normalizeIPv4: r,
      removeDotSegments: p,
      recomposeAuthority: i,
      normalizeComponentEncoding: g,
    } = Ln(),
    o = Un();
  function l(s, a) {
    return (
      typeof s == "string"
        ? (s = y(h(s, a), a))
        : typeof s == "object" && (s = h(y(s, a), a)),
      s
    );
  }
  function u(s, a, t) {
    const n = Object.assign({ scheme: "null" }, t),
      d = f(h(s, n), h(a, n), n, !0);
    return y(d, { ...n, skipEscape: !0 });
  }
  function f(s, a, t, n) {
    const d = {};
    return (
      n || ((s = h(y(s, t), t)), (a = h(y(a, t), t))),
      (t = t || {}),
      !t.tolerant && a.scheme
        ? ((d.scheme = a.scheme),
          (d.userinfo = a.userinfo),
          (d.host = a.host),
          (d.port = a.port),
          (d.path = p(a.path || "")),
          (d.query = a.query))
        : (a.userinfo !== void 0 || a.host !== void 0 || a.port !== void 0
            ? ((d.userinfo = a.userinfo),
              (d.host = a.host),
              (d.port = a.port),
              (d.path = p(a.path || "")),
              (d.query = a.query))
            : (a.path
                ? (a.path.charAt(0) === "/"
                    ? (d.path = p(a.path))
                    : ((s.userinfo !== void 0 ||
                        s.host !== void 0 ||
                        s.port !== void 0) &&
                      !s.path
                        ? (d.path = "/" + a.path)
                        : s.path
                          ? (d.path =
                              s.path.slice(0, s.path.lastIndexOf("/") + 1) +
                              a.path)
                          : (d.path = a.path),
                      (d.path = p(d.path))),
                  (d.query = a.query))
                : ((d.path = s.path),
                  a.query !== void 0
                    ? (d.query = a.query)
                    : (d.query = s.query)),
              (d.userinfo = s.userinfo),
              (d.host = s.host),
              (d.port = s.port)),
          (d.scheme = s.scheme)),
      (d.fragment = a.fragment),
      d
    );
  }
  function v(s, a, t) {
    return (
      typeof s == "string"
        ? ((s = unescape(s)), (s = y(g(h(s, t), !0), { ...t, skipEscape: !0 })))
        : typeof s == "object" && (s = y(g(s, !0), { ...t, skipEscape: !0 })),
      typeof a == "string"
        ? ((a = unescape(a)), (a = y(g(h(a, t), !0), { ...t, skipEscape: !0 })))
        : typeof a == "object" && (a = y(g(a, !0), { ...t, skipEscape: !0 })),
      s.toLowerCase() === a.toLowerCase()
    );
  }
  function y(s, a) {
    const t = {
        host: s.host,
        scheme: s.scheme,
        userinfo: s.userinfo,
        port: s.port,
        path: s.path,
        query: s.query,
        nid: s.nid,
        nss: s.nss,
        uuid: s.uuid,
        fragment: s.fragment,
        reference: s.reference,
        resourceName: s.resourceName,
        secure: s.secure,
        error: "",
      },
      n = Object.assign({}, a),
      d = [],
      _ = o[(n.scheme || t.scheme || "").toLowerCase()];
    (_ && _.serialize && _.serialize(t, n),
      t.path !== void 0 &&
        (n.skipEscape
          ? (t.path = unescape(t.path))
          : ((t.path = escape(t.path)),
            t.scheme !== void 0 && (t.path = t.path.split("%3A").join(":")))),
      n.reference !== "suffix" && t.scheme && (d.push(t.scheme), d.push(":")));
    const m = i(t, n);
    if (
      (m !== void 0 &&
        (n.reference !== "suffix" && d.push("//"),
        d.push(m),
        t.path && t.path.charAt(0) !== "/" && d.push("/")),
      t.path !== void 0)
    ) {
      let $ = t.path;
      (!n.absolutePath && (!_ || !_.absolutePath) && ($ = p($)),
        m === void 0 && ($ = $.replace(/^\/\//u, "/%2F")),
        d.push($));
    }
    return (
      t.query !== void 0 && (d.push("?"), d.push(t.query)),
      t.fragment !== void 0 && (d.push("#"), d.push(t.fragment)),
      d.join("")
    );
  }
  const E = Array.from({ length: 127 }, (s, a) =>
    /[^!"$&'()*+,\-.;=_`a-z{}~]/u.test(String.fromCharCode(a)),
  );
  function P(s) {
    let a = 0;
    for (let t = 0, n = s.length; t < n; ++t)
      if (((a = s.charCodeAt(t)), a > 126 || E[a])) return !0;
    return !1;
  }
  const S =
    /^(?:([^#/:?]+):)?(?:\/\/((?:([^#/?@]*)@)?(\[[^#/?\]]+\]|[^#/:?]*)(?::(\d*))?))?([^#?]*)(?:\?([^#]*))?(?:#((?:.|[\n\r])*))?/u;
  function h(s, a) {
    const t = Object.assign({}, a),
      n = {
        scheme: void 0,
        userinfo: void 0,
        host: "",
        port: void 0,
        path: "",
        query: void 0,
        fragment: void 0,
      },
      d = s.indexOf("%") !== -1;
    let _ = !1;
    t.reference === "suffix" &&
      (s = (t.scheme ? t.scheme + ":" : "") + "//" + s);
    const m = s.match(S);
    if (m) {
      if (
        ((n.scheme = m[1]),
        (n.userinfo = m[3]),
        (n.host = m[4]),
        (n.port = parseInt(m[5], 10)),
        (n.path = m[6] || ""),
        (n.query = m[7]),
        (n.fragment = m[8]),
        isNaN(n.port) && (n.port = m[5]),
        n.host)
      ) {
        const T = r(n.host);
        if (T.isIPV4 === !1) {
          const M = e(T.host, { isIPV4: !1 });
          ((n.host = M.host.toLowerCase()), (_ = M.isIPV6));
        } else ((n.host = T.host), (_ = !0));
      }
      (n.scheme === void 0 &&
      n.userinfo === void 0 &&
      n.host === void 0 &&
      n.port === void 0 &&
      !n.path &&
      n.query === void 0
        ? (n.reference = "same-document")
        : n.scheme === void 0
          ? (n.reference = "relative")
          : n.fragment === void 0
            ? (n.reference = "absolute")
            : (n.reference = "uri"),
        t.reference &&
          t.reference !== "suffix" &&
          t.reference !== n.reference &&
          (n.error = n.error || "URI is not a " + t.reference + " reference."));
      const $ = o[(t.scheme || n.scheme || "").toLowerCase()];
      if (
        !t.unicodeSupport &&
        (!$ || !$.unicodeSupport) &&
        n.host &&
        (t.domainHost || ($ && $.domainHost)) &&
        _ === !1 &&
        P(n.host)
      )
        try {
          n.host = URL.domainToASCII(n.host.toLowerCase());
        } catch (T) {
          n.error =
            n.error || "Host's domain name can not be converted to ASCII: " + T;
        }
      ((!$ || ($ && !$.skipNormalize)) &&
        (d && n.scheme !== void 0 && (n.scheme = unescape(n.scheme)),
        d && n.userinfo !== void 0 && (n.userinfo = unescape(n.userinfo)),
        d && n.host !== void 0 && (n.host = unescape(n.host)),
        n.path !== void 0 &&
          n.path.length &&
          (n.path = escape(unescape(n.path))),
        n.fragment !== void 0 &&
          n.fragment.length &&
          (n.fragment = encodeURI(decodeURIComponent(n.fragment)))),
        $ && $.parse && $.parse(n, t));
    } else n.error = n.error || "URI can not be parsed.";
    return n;
  }
  const b = {
    SCHEMES: o,
    normalize: l,
    resolve: u,
    resolveComponents: f,
    equal: v,
    serialize: y,
    parse: h,
  };
  return (
    (Ne.exports = b),
    (Ne.exports.default = b),
    (Ne.exports.fastUri = b),
    Ne.exports
  );
}
var mr;
function Hn() {
  if (mr) return Me;
  ((mr = 1), Object.defineProperty(Me, "__esModule", { value: !0 }));
  const e = Kn();
  return (
    (e.code = 'require("ajv/dist/runtime/uri").default'),
    (Me.default = e),
    Me
  );
}
var pr;
function Gn() {
  return (
    pr ||
      ((pr = 1),
      (function (e) {
        (Object.defineProperty(e, "__esModule", { value: !0 }),
          (e.CodeGen =
            e.Name =
            e.nil =
            e.stringify =
            e.str =
            e._ =
            e.KeywordCxt =
              void 0));
        var r = $t();
        Object.defineProperty(e, "KeywordCxt", {
          enumerable: !0,
          get: function () {
            return r.KeywordCxt;
          },
        });
        var p = J();
        (Object.defineProperty(e, "_", {
          enumerable: !0,
          get: function () {
            return p._;
          },
        }),
          Object.defineProperty(e, "str", {
            enumerable: !0,
            get: function () {
              return p.str;
            },
          }),
          Object.defineProperty(e, "stringify", {
            enumerable: !0,
            get: function () {
              return p.stringify;
            },
          }),
          Object.defineProperty(e, "nil", {
            enumerable: !0,
            get: function () {
              return p.nil;
            },
          }),
          Object.defineProperty(e, "Name", {
            enumerable: !0,
            get: function () {
              return p.Name;
            },
          }),
          Object.defineProperty(e, "CodeGen", {
            enumerable: !0,
            get: function () {
              return p.CodeGen;
            },
          }));
        const i = Vt(),
          g = wt(),
          o = on(),
          l = zt(),
          u = J(),
          f = gt(),
          v = _t(),
          y = Y(),
          E = zn,
          P = Hn(),
          S = (A, N) => new RegExp(A, N);
        S.code = "new RegExp";
        const h = ["removeAdditional", "useDefaults", "coerceTypes"],
          b = new Set([
            "validate",
            "serialize",
            "parse",
            "wrapper",
            "root",
            "schema",
            "keyword",
            "pattern",
            "formats",
            "validate$data",
            "func",
            "obj",
            "Error",
          ]),
          s = {
            errorDataPath: "",
            format: "`validateFormats: false` can be used instead.",
            nullable: '"nullable" keyword is supported by default.',
            jsonPointers: "Deprecated jsPropertySyntax can be used instead.",
            extendRefs: "Deprecated ignoreKeywordsWithRef can be used instead.",
            missingRefs:
              "Pass empty schema with $id that should be ignored to ajv.addSchema.",
            processCode:
              "Use option `code: {process: (code, schemaEnv: object) => string}`",
            sourceCode: "Use option `code: {source: true}`",
            strictDefaults: "It is default now, see option `strict`.",
            strictKeywords: "It is default now, see option `strict`.",
            uniqueItems: '"uniqueItems" keyword is always validated.',
            unknownFormats:
              "Disable strict mode or pass `true` to `ajv.addFormat` (or `formats` option).",
            cache: "Map is used as cache, schema object as key.",
            serialize: "Map is used as cache, schema object as key.",
            ajvErrors: "It is default now.",
          },
          a = {
            ignoreKeywordsWithRef: "",
            jsPropertySyntax: "",
            unicode:
              '"minLength"/"maxLength" account for unicode characters by default.',
          },
          t = 200;
        function n(A) {
          var N,
            C,
            O,
            c,
            w,
            j,
            U,
            H,
            X,
            B,
            R,
            k,
            q,
            D,
            K,
            W,
            ee,
            le,
            oe,
            ie,
            te,
            be,
            ce,
            bt,
            Et;
          const Pe = A.strict,
            St = (N = A.code) === null || N === void 0 ? void 0 : N.optimize,
            Lt = St === !0 || St === void 0 ? 1 : St || 0,
            Ut =
              (O =
                (C = A.code) === null || C === void 0 ? void 0 : C.regExp) !==
                null && O !== void 0
                ? O
                : S,
            hn = (c = A.uriResolver) !== null && c !== void 0 ? c : P.default;
          return {
            strictSchema:
              (j = (w = A.strictSchema) !== null && w !== void 0 ? w : Pe) !==
                null && j !== void 0
                ? j
                : !0,
            strictNumbers:
              (H = (U = A.strictNumbers) !== null && U !== void 0 ? U : Pe) !==
                null && H !== void 0
                ? H
                : !0,
            strictTypes:
              (B = (X = A.strictTypes) !== null && X !== void 0 ? X : Pe) !==
                null && B !== void 0
                ? B
                : "log",
            strictTuples:
              (k = (R = A.strictTuples) !== null && R !== void 0 ? R : Pe) !==
                null && k !== void 0
                ? k
                : "log",
            strictRequired:
              (D = (q = A.strictRequired) !== null && q !== void 0 ? q : Pe) !==
                null && D !== void 0
                ? D
                : !1,
            code: A.code
              ? { ...A.code, optimize: Lt, regExp: Ut }
              : { optimize: Lt, regExp: Ut },
            loopRequired: (K = A.loopRequired) !== null && K !== void 0 ? K : t,
            loopEnum: (W = A.loopEnum) !== null && W !== void 0 ? W : t,
            meta: (ee = A.meta) !== null && ee !== void 0 ? ee : !0,
            messages: (le = A.messages) !== null && le !== void 0 ? le : !0,
            inlineRefs: (oe = A.inlineRefs) !== null && oe !== void 0 ? oe : !0,
            schemaId: (ie = A.schemaId) !== null && ie !== void 0 ? ie : "$id",
            addUsedSchema:
              (te = A.addUsedSchema) !== null && te !== void 0 ? te : !0,
            validateSchema:
              (be = A.validateSchema) !== null && be !== void 0 ? be : !0,
            validateFormats:
              (ce = A.validateFormats) !== null && ce !== void 0 ? ce : !0,
            unicodeRegExp:
              (bt = A.unicodeRegExp) !== null && bt !== void 0 ? bt : !0,
            int32range: (Et = A.int32range) !== null && Et !== void 0 ? Et : !0,
            uriResolver: hn,
          };
        }
        class d {
          constructor(N = {}) {
            ((this.schemas = {}),
              (this.refs = {}),
              (this.formats = {}),
              (this._compilations = new Set()),
              (this._loading = {}),
              (this._cache = new Map()),
              (N = this.opts = { ...N, ...n(N) }));
            const { es5: C, lines: O } = this.opts.code;
            ((this.scope = new u.ValueScope({
              scope: {},
              prefixes: b,
              es5: C,
              lines: O,
            })),
              (this.logger = V(N.logger)));
            const c = N.validateFormats;
            ((N.validateFormats = !1),
              (this.RULES = (0, o.getRules)()),
              _.call(this, s, N, "NOT SUPPORTED"),
              _.call(this, a, N, "DEPRECATED", "warn"),
              (this._metaOpts = F.call(this)),
              N.formats && T.call(this),
              this._addVocabularies(),
              this._addDefaultMetaSchema(),
              N.keywords && M.call(this, N.keywords),
              typeof N.meta == "object" && this.addMetaSchema(N.meta),
              $.call(this),
              (N.validateFormats = c));
          }
          _addVocabularies() {
            this.addKeyword("$async");
          }
          _addDefaultMetaSchema() {
            const { $data: N, meta: C, schemaId: O } = this.opts;
            let c = E;
            (O === "id" && ((c = { ...E }), (c.id = c.$id), delete c.$id),
              C && N && this.addMetaSchema(c, c[O], !1));
          }
          defaultMeta() {
            const { meta: N, schemaId: C } = this.opts;
            return (this.opts.defaultMeta =
              typeof N == "object" ? N[C] || N : void 0);
          }
          validate(N, C) {
            let O;
            if (typeof N == "string") {
              if (((O = this.getSchema(N)), !O))
                throw new Error(`no schema with key or ref "${N}"`);
            } else O = this.compile(N);
            const c = O(C);
            return ("$async" in O || (this.errors = O.errors), c);
          }
          compile(N, C) {
            const O = this._addSchema(N, C);
            return O.validate || this._compileSchemaEnv(O);
          }
          compileAsync(N, C) {
            if (typeof this.opts.loadSchema != "function")
              throw new Error("options.loadSchema should be a function");
            const { loadSchema: O } = this.opts;
            return c.call(this, N, C);
            async function c(B, R) {
              await w.call(this, B.$schema);
              const k = this._addSchema(B, R);
              return k.validate || j.call(this, k);
            }
            async function w(B) {
              B && !this.getSchema(B) && (await c.call(this, { $ref: B }, !0));
            }
            async function j(B) {
              try {
                return this._compileSchemaEnv(B);
              } catch (R) {
                if (!(R instanceof g.default)) throw R;
                return (
                  U.call(this, R),
                  await H.call(this, R.missingSchema),
                  j.call(this, B)
                );
              }
            }
            function U({ missingSchema: B, missingRef: R }) {
              if (this.refs[B])
                throw new Error(
                  `AnySchema ${B} is loaded but ${R} cannot be resolved`,
                );
            }
            async function H(B) {
              const R = await X.call(this, B);
              (this.refs[B] || (await w.call(this, R.$schema)),
                this.refs[B] || this.addSchema(R, B, C));
            }
            async function X(B) {
              const R = this._loading[B];
              if (R) return R;
              try {
                return await (this._loading[B] = O(B));
              } finally {
                delete this._loading[B];
              }
            }
          }
          addSchema(N, C, O, c = this.opts.validateSchema) {
            if (Array.isArray(N)) {
              for (const j of N) this.addSchema(j, void 0, O, c);
              return this;
            }
            let w;
            if (typeof N == "object") {
              const { schemaId: j } = this.opts;
              if (((w = N[j]), w !== void 0 && typeof w != "string"))
                throw new Error(`schema ${j} must be string`);
            }
            return (
              (C = (0, f.normalizeId)(C || w)),
              this._checkUnique(C),
              (this.schemas[C] = this._addSchema(N, O, C, c, !0)),
              this
            );
          }
          addMetaSchema(N, C, O = this.opts.validateSchema) {
            return (this.addSchema(N, C, !0, O), this);
          }
          validateSchema(N, C) {
            if (typeof N == "boolean") return !0;
            let O;
            if (((O = N.$schema), O !== void 0 && typeof O != "string"))
              throw new Error("$schema must be a string");
            if (((O = O || this.opts.defaultMeta || this.defaultMeta()), !O))
              return (
                this.logger.warn("meta-schema not available"),
                (this.errors = null),
                !0
              );
            const c = this.validate(O, N);
            if (!c && C) {
              const w = "schema is invalid: " + this.errorsText();
              if (this.opts.validateSchema === "log") this.logger.error(w);
              else throw new Error(w);
            }
            return c;
          }
          getSchema(N) {
            let C;
            for (; typeof (C = m.call(this, N)) == "string";) N = C;
            if (C === void 0) {
              const { schemaId: O } = this.opts,
                c = new l.SchemaEnv({ schema: {}, schemaId: O });
              if (((C = l.resolveSchema.call(this, c, N)), !C)) return;
              this.refs[N] = C;
            }
            return C.validate || this._compileSchemaEnv(C);
          }
          removeSchema(N) {
            if (N instanceof RegExp)
              return (
                this._removeAllSchemas(this.schemas, N),
                this._removeAllSchemas(this.refs, N),
                this
              );
            switch (typeof N) {
              case "undefined":
                return (
                  this._removeAllSchemas(this.schemas),
                  this._removeAllSchemas(this.refs),
                  this._cache.clear(),
                  this
                );
              case "string": {
                const C = m.call(this, N);
                return (
                  typeof C == "object" && this._cache.delete(C.schema),
                  delete this.schemas[N],
                  delete this.refs[N],
                  this
                );
              }
              case "object": {
                const C = N;
                this._cache.delete(C);
                let O = N[this.opts.schemaId];
                return (
                  O &&
                    ((O = (0, f.normalizeId)(O)),
                    delete this.schemas[O],
                    delete this.refs[O]),
                  this
                );
              }
              default:
                throw new Error("ajv.removeSchema: invalid parameter");
            }
          }
          addVocabulary(N) {
            for (const C of N) this.addKeyword(C);
            return this;
          }
          addKeyword(N, C) {
            let O;
            if (typeof N == "string")
              ((O = N),
                typeof C == "object" &&
                  (this.logger.warn(
                    "these parameters are deprecated, see docs for addKeyword",
                  ),
                  (C.keyword = O)));
            else if (typeof N == "object" && C === void 0) {
              if (((C = N), (O = C.keyword), Array.isArray(O) && !O.length))
                throw new Error(
                  "addKeywords: keyword must be string or non-empty array",
                );
            } else throw new Error("invalid addKeywords parameters");
            if ((L.call(this, O, C), !C))
              return ((0, y.eachItem)(O, (w) => Z.call(this, w)), this);
            se.call(this, C);
            const c = {
              ...C,
              type: (0, v.getJSONTypes)(C.type),
              schemaType: (0, v.getJSONTypes)(C.schemaType),
            };
            return (
              (0, y.eachItem)(
                O,
                c.type.length === 0
                  ? (w) => Z.call(this, w, c)
                  : (w) => c.type.forEach((j) => Z.call(this, w, c, j)),
              ),
              this
            );
          }
          getKeyword(N) {
            const C = this.RULES.all[N];
            return typeof C == "object" ? C.definition : !!C;
          }
          removeKeyword(N) {
            const { RULES: C } = this;
            (delete C.keywords[N], delete C.all[N]);
            for (const O of C.rules) {
              const c = O.rules.findIndex((w) => w.keyword === N);
              c >= 0 && O.rules.splice(c, 1);
            }
            return this;
          }
          addFormat(N, C) {
            return (
              typeof C == "string" && (C = new RegExp(C)),
              (this.formats[N] = C),
              this
            );
          }
          errorsText(
            N = this.errors,
            { separator: C = ", ", dataVar: O = "data" } = {},
          ) {
            return !N || N.length === 0
              ? "No errors"
              : N.map((c) => `${O}${c.instancePath} ${c.message}`).reduce(
                  (c, w) => c + C + w,
                );
          }
          $dataMetaSchema(N, C) {
            const O = this.RULES.all;
            N = JSON.parse(JSON.stringify(N));
            for (const c of C) {
              const w = c.split("/").slice(1);
              let j = N;
              for (const U of w) j = j[U];
              for (const U in O) {
                const H = O[U];
                if (typeof H != "object") continue;
                const { $data: X } = H.definition,
                  B = j[U];
                X && B && (j[U] = de(B));
              }
            }
            return N;
          }
          _removeAllSchemas(N, C) {
            for (const O in N) {
              const c = N[O];
              (!C || C.test(O)) &&
                (typeof c == "string"
                  ? delete N[O]
                  : c &&
                    !c.meta &&
                    (this._cache.delete(c.schema), delete N[O]));
            }
          }
          _addSchema(
            N,
            C,
            O,
            c = this.opts.validateSchema,
            w = this.opts.addUsedSchema,
          ) {
            let j;
            const { schemaId: U } = this.opts;
            if (typeof N == "object") j = N[U];
            else {
              if (this.opts.jtd) throw new Error("schema must be object");
              if (typeof N != "boolean")
                throw new Error("schema must be object or boolean");
            }
            let H = this._cache.get(N);
            if (H !== void 0) return H;
            O = (0, f.normalizeId)(j || O);
            const X = f.getSchemaRefs.call(this, N, O);
            return (
              (H = new l.SchemaEnv({
                schema: N,
                schemaId: U,
                meta: C,
                baseId: O,
                localRefs: X,
              })),
              this._cache.set(H.schema, H),
              w &&
                !O.startsWith("#") &&
                (O && this._checkUnique(O), (this.refs[O] = H)),
              c && this.validateSchema(N, !0),
              H
            );
          }
          _checkUnique(N) {
            if (this.schemas[N] || this.refs[N])
              throw new Error(`schema with key or id "${N}" already exists`);
          }
          _compileSchemaEnv(N) {
            if (
              (N.meta
                ? this._compileMetaSchema(N)
                : l.compileSchema.call(this, N),
              !N.validate)
            )
              throw new Error("ajv implementation error");
            return N.validate;
          }
          _compileMetaSchema(N) {
            const C = this.opts;
            this.opts = this._metaOpts;
            try {
              l.compileSchema.call(this, N);
            } finally {
              this.opts = C;
            }
          }
        }
        ((d.ValidationError = i.default),
          (d.MissingRefError = g.default),
          (e.default = d));
        function _(A, N, C, O = "error") {
          for (const c in A) {
            const w = c;
            w in N && this.logger[O](`${C}: option ${c}. ${A[w]}`);
          }
        }
        function m(A) {
          return ((A = (0, f.normalizeId)(A)), this.schemas[A] || this.refs[A]);
        }
        function $() {
          const A = this.opts.schemas;
          if (A)
            if (Array.isArray(A)) this.addSchema(A);
            else for (const N in A) this.addSchema(A[N], N);
        }
        function T() {
          for (const A in this.opts.formats) {
            const N = this.opts.formats[A];
            N && this.addFormat(A, N);
          }
        }
        function M(A) {
          if (Array.isArray(A)) {
            this.addVocabulary(A);
            return;
          }
          this.logger.warn("keywords option as map is deprecated, pass array");
          for (const N in A) {
            const C = A[N];
            (C.keyword || (C.keyword = N), this.addKeyword(C));
          }
        }
        function F() {
          const A = { ...this.opts };
          for (const N of h) delete A[N];
          return A;
        }
        const I = { log() {}, warn() {}, error() {} };
        function V(A) {
          if (A === !1) return I;
          if (A === void 0) return console;
          if (A.log && A.warn && A.error) return A;
          throw new Error("logger must implement log, warn and error methods");
        }
        const z = /^[a-z_$][a-z0-9_$:-]*$/i;
        function L(A, N) {
          const { RULES: C } = this;
          if (
            ((0, y.eachItem)(A, (O) => {
              if (C.keywords[O])
                throw new Error(`Keyword ${O} is already defined`);
              if (!z.test(O)) throw new Error(`Keyword ${O} has invalid name`);
            }),
            !!N && N.$data && !("code" in N || "validate" in N))
          )
            throw new Error(
              '$data keyword must have "code" or "validate" function',
            );
        }
        function Z(A, N, C) {
          var O;
          const c = N?.post;
          if (C && c)
            throw new Error('keyword with "post" flag cannot have "type"');
          const { RULES: w } = this;
          let j = c ? w.post : w.rules.find(({ type: H }) => H === C);
          if (
            (j || ((j = { type: C, rules: [] }), w.rules.push(j)),
            (w.keywords[A] = !0),
            !N)
          )
            return;
          const U = {
            keyword: A,
            definition: {
              ...N,
              type: (0, v.getJSONTypes)(N.type),
              schemaType: (0, v.getJSONTypes)(N.schemaType),
            },
          };
          (N.before ? ne.call(this, j, U, N.before) : j.rules.push(U),
            (w.all[A] = U),
            (O = N.implements) === null ||
              O === void 0 ||
              O.forEach((H) => this.addKeyword(H)));
        }
        function ne(A, N, C) {
          const O = A.rules.findIndex((c) => c.keyword === C);
          O >= 0
            ? A.rules.splice(O, 0, N)
            : (A.rules.push(N), this.logger.warn(`rule ${C} is not defined`));
        }
        function se(A) {
          let { metaSchema: N } = A;
          N !== void 0 &&
            (A.$data && this.opts.$data && (N = de(N)),
            (A.validateSchema = this.compile(N, !0)));
        }
        const x = {
          $ref: "https://raw.githubusercontent.com/ajv-validator/ajv/master/lib/refs/data.json#",
        };
        function de(A) {
          return { anyOf: [A, x] };
        }
      })(Rt)),
    Rt
  );
}
var Ae = {},
  De = {},
  Ve = {},
  yr;
function Jn() {
  if (yr) return Ve;
  ((yr = 1), Object.defineProperty(Ve, "__esModule", { value: !0 }));
  const e = {
    keyword: "id",
    code() {
      throw new Error('NOT SUPPORTED: keyword "id", use "$id" for schema ID');
    },
  };
  return ((Ve.default = e), Ve);
}
var _e = {},
  _r;
function Wn() {
  if (_r) return _e;
  ((_r = 1),
    Object.defineProperty(_e, "__esModule", { value: !0 }),
    (_e.callRef = _e.getValidate = void 0));
  const e = wt(),
    r = he(),
    p = J(),
    i = ve(),
    g = zt(),
    o = Y(),
    l = {
      keyword: "$ref",
      schemaType: "string",
      code(v) {
        const { gen: y, schema: E, it: P } = v,
          { baseId: S, schemaEnv: h, validateName: b, opts: s, self: a } = P,
          { root: t } = h;
        if ((E === "#" || E === "#/") && S === t.baseId) return d();
        const n = g.resolveRef.call(a, t, S, E);
        if (n === void 0) throw new e.default(P.opts.uriResolver, S, E);
        if (n instanceof g.SchemaEnv) return _(n);
        return m(n);
        function d() {
          if (h === t) return f(v, b, h, h.$async);
          const $ = y.scopeValue("root", { ref: t });
          return f(v, (0, p._)`${$}.validate`, t, t.$async);
        }
        function _($) {
          const T = u(v, $);
          f(v, T, $, $.$async);
        }
        function m($) {
          const T = y.scopeValue(
              "schema",
              s.code.source === !0
                ? { ref: $, code: (0, p.stringify)($) }
                : { ref: $ },
            ),
            M = y.name("valid"),
            F = v.subschema(
              {
                schema: $,
                dataTypes: [],
                schemaPath: p.nil,
                topSchemaRef: T,
                errSchemaPath: E,
              },
              M,
            );
          (v.mergeEvaluated(F), v.ok(M));
        }
      },
    };
  function u(v, y) {
    const { gen: E } = v;
    return y.validate
      ? E.scopeValue("validate", { ref: y.validate })
      : (0, p._)`${E.scopeValue("wrapper", { ref: y })}.validate`;
  }
  _e.getValidate = u;
  function f(v, y, E, P) {
    const { gen: S, it: h } = v,
      { allErrors: b, schemaEnv: s, opts: a } = h,
      t = a.passContext ? i.default.this : p.nil;
    P ? n() : d();
    function n() {
      if (!s.$async) throw new Error("async schema referenced by sync schema");
      const $ = S.let("valid");
      (S.try(
        () => {
          (S.code((0, p._)`await ${(0, r.callValidateCode)(v, y, t)}`),
            m(y),
            b || S.assign($, !0));
        },
        (T) => {
          (S.if((0, p._)`!(${T} instanceof ${h.ValidationError})`, () =>
            S.throw(T),
          ),
            _(T),
            b || S.assign($, !1));
        },
      ),
        v.ok($));
    }
    function d() {
      v.result(
        (0, r.callValidateCode)(v, y, t),
        () => m(y),
        () => _(y),
      );
    }
    function _($) {
      const T = (0, p._)`${$}.errors`;
      (S.assign(
        i.default.vErrors,
        (0,
        p._)`${i.default.vErrors} === null ? ${T} : ${i.default.vErrors}.concat(${T})`,
      ),
        S.assign(i.default.errors, (0, p._)`${i.default.vErrors}.length`));
    }
    function m($) {
      var T;
      if (!h.opts.unevaluated) return;
      const M =
        (T = E?.validate) === null || T === void 0 ? void 0 : T.evaluated;
      if (h.props !== !0)
        if (M && !M.dynamicProps)
          M.props !== void 0 &&
            (h.props = o.mergeEvaluated.props(S, M.props, h.props));
        else {
          const F = S.var("props", (0, p._)`${$}.evaluated.props`);
          h.props = o.mergeEvaluated.props(S, F, h.props, p.Name);
        }
      if (h.items !== !0)
        if (M && !M.dynamicItems)
          M.items !== void 0 &&
            (h.items = o.mergeEvaluated.items(S, M.items, h.items));
        else {
          const F = S.var("items", (0, p._)`${$}.evaluated.items`);
          h.items = o.mergeEvaluated.items(S, F, h.items, p.Name);
        }
    }
  }
  return ((_e.callRef = f), (_e.default = l), _e);
}
var vr;
function Bn() {
  if (vr) return De;
  ((vr = 1), Object.defineProperty(De, "__esModule", { value: !0 }));
  const e = Jn(),
    r = Wn(),
    p = [
      "$schema",
      "$id",
      "$defs",
      "$vocabulary",
      { keyword: "$comment" },
      "definitions",
      e.default,
      r.default,
    ];
  return ((De.default = p), De);
}
var ze = {},
  Fe = {},
  gr;
function Yn() {
  if (gr) return Fe;
  ((gr = 1), Object.defineProperty(Fe, "__esModule", { value: !0 }));
  const e = J(),
    r = e.operators,
    p = {
      maximum: { okStr: "<=", ok: r.LTE, fail: r.GT },
      minimum: { okStr: ">=", ok: r.GTE, fail: r.LT },
      exclusiveMaximum: { okStr: "<", ok: r.LT, fail: r.GTE },
      exclusiveMinimum: { okStr: ">", ok: r.GT, fail: r.LTE },
    },
    i = {
      message: ({ keyword: o, schemaCode: l }) =>
        (0, e.str)`must be ${p[o].okStr} ${l}`,
      params: ({ keyword: o, schemaCode: l }) =>
        (0, e._)`{comparison: ${p[o].okStr}, limit: ${l}}`,
    },
    g = {
      keyword: Object.keys(p),
      type: "number",
      schemaType: "number",
      $data: !0,
      error: i,
      code(o) {
        const { keyword: l, data: u, schemaCode: f } = o;
        o.fail$data((0, e._)`${u} ${p[l].fail} ${f} || isNaN(${u})`);
      },
    };
  return ((Fe.default = g), Fe);
}
var Le = {},
  $r;
function Xn() {
  if ($r) return Le;
  (($r = 1), Object.defineProperty(Le, "__esModule", { value: !0 }));
  const e = J(),
    p = {
      keyword: "multipleOf",
      type: "number",
      schemaType: "number",
      $data: !0,
      error: {
        message: ({ schemaCode: i }) => (0, e.str)`must be multiple of ${i}`,
        params: ({ schemaCode: i }) => (0, e._)`{multipleOf: ${i}}`,
      },
      code(i) {
        const { gen: g, data: o, schemaCode: l, it: u } = i,
          f = u.opts.multipleOfPrecision,
          v = g.let("res"),
          y = f
            ? (0, e._)`Math.abs(Math.round(${v}) - ${v}) > 1e-${f}`
            : (0, e._)`${v} !== parseInt(${v})`;
        i.fail$data((0, e._)`(${l} === 0 || (${v} = ${o}/${l}, ${y}))`);
      },
    };
  return ((Le.default = p), Le);
}
var Ue = {},
  Ke = {},
  wr;
function Zn() {
  if (wr) return Ke;
  ((wr = 1), Object.defineProperty(Ke, "__esModule", { value: !0 }));
  function e(r) {
    const p = r.length;
    let i = 0,
      g = 0,
      o;
    for (; g < p;)
      (i++,
        (o = r.charCodeAt(g++)),
        o >= 55296 &&
          o <= 56319 &&
          g < p &&
          ((o = r.charCodeAt(g)), (o & 64512) === 56320 && g++));
    return i;
  }
  return (
    (Ke.default = e),
    (e.code = 'require("ajv/dist/runtime/ucs2length").default'),
    Ke
  );
}
var br;
function Qn() {
  if (br) return Ue;
  ((br = 1), Object.defineProperty(Ue, "__esModule", { value: !0 }));
  const e = J(),
    r = Y(),
    p = Zn(),
    g = {
      keyword: ["maxLength", "minLength"],
      type: "string",
      schemaType: "number",
      $data: !0,
      error: {
        message({ keyword: o, schemaCode: l }) {
          const u = o === "maxLength" ? "more" : "fewer";
          return (0, e.str)`must NOT have ${u} than ${l} characters`;
        },
        params: ({ schemaCode: o }) => (0, e._)`{limit: ${o}}`,
      },
      code(o) {
        const { keyword: l, data: u, schemaCode: f, it: v } = o,
          y = l === "maxLength" ? e.operators.GT : e.operators.LT,
          E =
            v.opts.unicode === !1
              ? (0, e._)`${u}.length`
              : (0, e._)`${(0, r.useFunc)(o.gen, p.default)}(${u})`;
        o.fail$data((0, e._)`${E} ${y} ${f}`);
      },
    };
  return ((Ue.default = g), Ue);
}
var He = {},
  Er;
function xn() {
  if (Er) return He;
  ((Er = 1), Object.defineProperty(He, "__esModule", { value: !0 }));
  const e = he(),
    r = J(),
    i = {
      keyword: "pattern",
      type: "string",
      schemaType: "string",
      $data: !0,
      error: {
        message: ({ schemaCode: g }) => (0, r.str)`must match pattern "${g}"`,
        params: ({ schemaCode: g }) => (0, r._)`{pattern: ${g}}`,
      },
      code(g) {
        const { data: o, $data: l, schema: u, schemaCode: f, it: v } = g,
          y = v.opts.unicodeRegExp ? "u" : "",
          E = l ? (0, r._)`(new RegExp(${f}, ${y}))` : (0, e.usePattern)(g, u);
        g.fail$data((0, r._)`!${E}.test(${o})`);
      },
    };
  return ((He.default = i), He);
}
var Ge = {},
  Sr;
function es() {
  if (Sr) return Ge;
  ((Sr = 1), Object.defineProperty(Ge, "__esModule", { value: !0 }));
  const e = J(),
    p = {
      keyword: ["maxProperties", "minProperties"],
      type: "object",
      schemaType: "number",
      $data: !0,
      error: {
        message({ keyword: i, schemaCode: g }) {
          const o = i === "maxProperties" ? "more" : "fewer";
          return (0, e.str)`must NOT have ${o} than ${g} properties`;
        },
        params: ({ schemaCode: i }) => (0, e._)`{limit: ${i}}`,
      },
      code(i) {
        const { keyword: g, data: o, schemaCode: l } = i,
          u = g === "maxProperties" ? e.operators.GT : e.operators.LT;
        i.fail$data((0, e._)`Object.keys(${o}).length ${u} ${l}`);
      },
    };
  return ((Ge.default = p), Ge);
}
var Je = {},
  Pr;
function ts() {
  if (Pr) return Je;
  ((Pr = 1), Object.defineProperty(Je, "__esModule", { value: !0 }));
  const e = he(),
    r = J(),
    p = Y(),
    g = {
      keyword: "required",
      type: "object",
      schemaType: "array",
      $data: !0,
      error: {
        message: ({ params: { missingProperty: o } }) =>
          (0, r.str)`must have required property '${o}'`,
        params: ({ params: { missingProperty: o } }) =>
          (0, r._)`{missingProperty: ${o}}`,
      },
      code(o) {
        const {
            gen: l,
            schema: u,
            schemaCode: f,
            data: v,
            $data: y,
            it: E,
          } = o,
          { opts: P } = E;
        if (!y && u.length === 0) return;
        const S = u.length >= P.loopRequired;
        if ((E.allErrors ? h() : b(), P.strictRequired)) {
          const t = o.parentSchema.properties,
            { definedProperties: n } = o.it;
          for (const d of u)
            if (t?.[d] === void 0 && !n.has(d)) {
              const _ = E.schemaEnv.baseId + E.errSchemaPath,
                m = `required property "${d}" is not defined at "${_}" (strictRequired)`;
              (0, p.checkStrictMode)(E, m, E.opts.strictRequired);
            }
        }
        function h() {
          if (S || y) o.block$data(r.nil, s);
          else for (const t of u) (0, e.checkReportMissingProp)(o, t);
        }
        function b() {
          const t = l.let("missing");
          if (S || y) {
            const n = l.let("valid", !0);
            (o.block$data(n, () => a(t, n)), o.ok(n));
          } else
            (l.if((0, e.checkMissingProp)(o, u, t)),
              (0, e.reportMissingProp)(o, t),
              l.else());
        }
        function s() {
          l.forOf("prop", f, (t) => {
            (o.setParams({ missingProperty: t }),
              l.if((0, e.noPropertyInData)(l, v, t, P.ownProperties), () =>
                o.error(),
              ));
          });
        }
        function a(t, n) {
          (o.setParams({ missingProperty: t }),
            l.forOf(
              t,
              f,
              () => {
                (l.assign(n, (0, e.propertyInData)(l, v, t, P.ownProperties)),
                  l.if((0, r.not)(n), () => {
                    (o.error(), l.break());
                  }));
              },
              r.nil,
            ));
        }
      },
    };
  return ((Je.default = g), Je);
}
var We = {},
  Rr;
function rs() {
  if (Rr) return We;
  ((Rr = 1), Object.defineProperty(We, "__esModule", { value: !0 }));
  const e = J(),
    p = {
      keyword: ["maxItems", "minItems"],
      type: "array",
      schemaType: "number",
      $data: !0,
      error: {
        message({ keyword: i, schemaCode: g }) {
          const o = i === "maxItems" ? "more" : "fewer";
          return (0, e.str)`must NOT have ${o} than ${g} items`;
        },
        params: ({ schemaCode: i }) => (0, e._)`{limit: ${i}}`,
      },
      code(i) {
        const { keyword: g, data: o, schemaCode: l } = i,
          u = g === "maxItems" ? e.operators.GT : e.operators.LT;
        i.fail$data((0, e._)`${o}.length ${u} ${l}`);
      },
    };
  return ((We.default = p), We);
}
var Be = {},
  Ye = {},
  Nr;
function Ft() {
  if (Nr) return Ye;
  ((Nr = 1), Object.defineProperty(Ye, "__esModule", { value: !0 }));
  const e = an();
  return (
    (e.code = 'require("ajv/dist/runtime/equal").default'),
    (Ye.default = e),
    Ye
  );
}
var kr;
function ns() {
  if (kr) return Be;
  ((kr = 1), Object.defineProperty(Be, "__esModule", { value: !0 }));
  const e = _t(),
    r = J(),
    p = Y(),
    i = Ft(),
    o = {
      keyword: "uniqueItems",
      type: "array",
      schemaType: "boolean",
      $data: !0,
      error: {
        message: ({ params: { i: l, j: u } }) =>
          (0,
          r.str)`must NOT have duplicate items (items ## ${u} and ${l} are identical)`,
        params: ({ params: { i: l, j: u } }) => (0, r._)`{i: ${l}, j: ${u}}`,
      },
      code(l) {
        const {
          gen: u,
          data: f,
          $data: v,
          schema: y,
          parentSchema: E,
          schemaCode: P,
          it: S,
        } = l;
        if (!v && !y) return;
        const h = u.let("valid"),
          b = E.items ? (0, e.getSchemaTypes)(E.items) : [];
        (l.block$data(h, s, (0, r._)`${P} === false`), l.ok(h));
        function s() {
          const d = u.let("i", (0, r._)`${f}.length`),
            _ = u.let("j");
          (l.setParams({ i: d, j: _ }),
            u.assign(h, !0),
            u.if((0, r._)`${d} > 1`, () => (a() ? t : n)(d, _)));
        }
        function a() {
          return (
            b.length > 0 && !b.some((d) => d === "object" || d === "array")
          );
        }
        function t(d, _) {
          const m = u.name("item"),
            $ = (0, e.checkDataTypes)(
              b,
              m,
              S.opts.strictNumbers,
              e.DataType.Wrong,
            ),
            T = u.const("indices", (0, r._)`{}`);
          u.for((0, r._)`;${d}--;`, () => {
            (u.let(m, (0, r._)`${f}[${d}]`),
              u.if($, (0, r._)`continue`),
              b.length > 1 &&
                u.if((0, r._)`typeof ${m} == "string"`, (0, r._)`${m} += "_"`),
              u
                .if((0, r._)`typeof ${T}[${m}] == "number"`, () => {
                  (u.assign(_, (0, r._)`${T}[${m}]`),
                    l.error(),
                    u.assign(h, !1).break());
                })
                .code((0, r._)`${T}[${m}] = ${d}`));
          });
        }
        function n(d, _) {
          const m = (0, p.useFunc)(u, i.default),
            $ = u.name("outer");
          u.label($).for((0, r._)`;${d}--;`, () =>
            u.for((0, r._)`${_} = ${d}; ${_}--;`, () =>
              u.if((0, r._)`${m}(${f}[${d}], ${f}[${_}])`, () => {
                (l.error(), u.assign(h, !1).break($));
              }),
            ),
          );
        }
      },
    };
  return ((Be.default = o), Be);
}
var Xe = {},
  Or;
function ss() {
  if (Or) return Xe;
  ((Or = 1), Object.defineProperty(Xe, "__esModule", { value: !0 }));
  const e = J(),
    r = Y(),
    p = Ft(),
    g = {
      keyword: "const",
      $data: !0,
      error: {
        message: "must be equal to constant",
        params: ({ schemaCode: o }) => (0, e._)`{allowedValue: ${o}}`,
      },
      code(o) {
        const { gen: l, data: u, $data: f, schemaCode: v, schema: y } = o;
        f || (y && typeof y == "object")
          ? o.fail$data((0, e._)`!${(0, r.useFunc)(l, p.default)}(${u}, ${v})`)
          : o.fail((0, e._)`${y} !== ${u}`);
      },
    };
  return ((Xe.default = g), Xe);
}
var Ze = {},
  Tr;
function as() {
  if (Tr) return Ze;
  ((Tr = 1), Object.defineProperty(Ze, "__esModule", { value: !0 }));
  const e = J(),
    r = Y(),
    p = Ft(),
    g = {
      keyword: "enum",
      schemaType: "array",
      $data: !0,
      error: {
        message: "must be equal to one of the allowed values",
        params: ({ schemaCode: o }) => (0, e._)`{allowedValues: ${o}}`,
      },
      code(o) {
        const {
          gen: l,
          data: u,
          $data: f,
          schema: v,
          schemaCode: y,
          it: E,
        } = o;
        if (!f && v.length === 0)
          throw new Error("enum must have non-empty array");
        const P = v.length >= E.opts.loopEnum;
        let S;
        const h = () => S ?? (S = (0, r.useFunc)(l, p.default));
        let b;
        if (P || f) ((b = l.let("valid")), o.block$data(b, s));
        else {
          if (!Array.isArray(v)) throw new Error("ajv implementation error");
          const t = l.const("vSchema", y);
          b = (0, e.or)(...v.map((n, d) => a(t, d)));
        }
        o.pass(b);
        function s() {
          (l.assign(b, !1),
            l.forOf("v", y, (t) =>
              l.if((0, e._)`${h()}(${u}, ${t})`, () => l.assign(b, !0).break()),
            ));
        }
        function a(t, n) {
          const d = v[n];
          return typeof d == "object" && d !== null
            ? (0, e._)`${h()}(${u}, ${t}[${n}])`
            : (0, e._)`${u} === ${d}`;
        }
      },
    };
  return ((Ze.default = g), Ze);
}
var jr;
function os() {
  if (jr) return ze;
  ((jr = 1), Object.defineProperty(ze, "__esModule", { value: !0 }));
  const e = Yn(),
    r = Xn(),
    p = Qn(),
    i = xn(),
    g = es(),
    o = ts(),
    l = rs(),
    u = ns(),
    f = ss(),
    v = as(),
    y = [
      e.default,
      r.default,
      p.default,
      i.default,
      g.default,
      o.default,
      l.default,
      u.default,
      { keyword: "type", schemaType: ["string", "array"] },
      { keyword: "nullable", schemaType: "boolean" },
      f.default,
      v.default,
    ];
  return ((ze.default = y), ze);
}
var Qe = {},
  Ee = {},
  Ir;
function cn() {
  if (Ir) return Ee;
  ((Ir = 1),
    Object.defineProperty(Ee, "__esModule", { value: !0 }),
    (Ee.validateAdditionalItems = void 0));
  const e = J(),
    r = Y(),
    i = {
      keyword: "additionalItems",
      type: "array",
      schemaType: ["boolean", "object"],
      before: "uniqueItems",
      error: {
        message: ({ params: { len: o } }) =>
          (0, e.str)`must NOT have more than ${o} items`,
        params: ({ params: { len: o } }) => (0, e._)`{limit: ${o}}`,
      },
      code(o) {
        const { parentSchema: l, it: u } = o,
          { items: f } = l;
        if (!Array.isArray(f)) {
          (0, r.checkStrictMode)(
            u,
            '"additionalItems" is ignored when "items" is not an array of schemas',
          );
          return;
        }
        g(o, f);
      },
    };
  function g(o, l) {
    const { gen: u, schema: f, data: v, keyword: y, it: E } = o;
    E.items = !0;
    const P = u.const("len", (0, e._)`${v}.length`);
    if (f === !1)
      (o.setParams({ len: l.length }), o.pass((0, e._)`${P} <= ${l.length}`));
    else if (typeof f == "object" && !(0, r.alwaysValidSchema)(E, f)) {
      const h = u.var("valid", (0, e._)`${P} <= ${l.length}`);
      (u.if((0, e.not)(h), () => S(h)), o.ok(h));
    }
    function S(h) {
      u.forRange("i", l.length, P, (b) => {
        (o.subschema({ keyword: y, dataProp: b, dataPropType: r.Type.Num }, h),
          E.allErrors || u.if((0, e.not)(h), () => u.break()));
      });
    }
  }
  return ((Ee.validateAdditionalItems = g), (Ee.default = i), Ee);
}
var xe = {},
  Se = {},
  qr;
function dn() {
  if (qr) return Se;
  ((qr = 1),
    Object.defineProperty(Se, "__esModule", { value: !0 }),
    (Se.validateTuple = void 0));
  const e = J(),
    r = Y(),
    p = he(),
    i = {
      keyword: "items",
      type: "array",
      schemaType: ["object", "array", "boolean"],
      before: "uniqueItems",
      code(o) {
        const { schema: l, it: u } = o;
        if (Array.isArray(l)) return g(o, "additionalItems", l);
        ((u.items = !0),
          !(0, r.alwaysValidSchema)(u, l) && o.ok((0, p.validateArray)(o)));
      },
    };
  function g(o, l, u = o.schema) {
    const { gen: f, parentSchema: v, data: y, keyword: E, it: P } = o;
    (b(v),
      P.opts.unevaluated &&
        u.length &&
        P.items !== !0 &&
        (P.items = r.mergeEvaluated.items(f, u.length, P.items)));
    const S = f.name("valid"),
      h = f.const("len", (0, e._)`${y}.length`);
    u.forEach((s, a) => {
      (0, r.alwaysValidSchema)(P, s) ||
        (f.if((0, e._)`${h} > ${a}`, () =>
          o.subschema({ keyword: E, schemaProp: a, dataProp: a }, S),
        ),
        o.ok(S));
    });
    function b(s) {
      const { opts: a, errSchemaPath: t } = P,
        n = u.length,
        d = n === s.minItems && (n === s.maxItems || s[l] === !1);
      if (a.strictTuples && !d) {
        const _ = `"${E}" is ${n}-tuple, but minItems or maxItems/${l} are not specified or different at path "${t}"`;
        (0, r.checkStrictMode)(P, _, a.strictTuples);
      }
    }
  }
  return ((Se.validateTuple = g), (Se.default = i), Se);
}
var Cr;
function is() {
  if (Cr) return xe;
  ((Cr = 1), Object.defineProperty(xe, "__esModule", { value: !0 }));
  const e = dn(),
    r = {
      keyword: "prefixItems",
      type: "array",
      schemaType: ["array"],
      before: "uniqueItems",
      code: (p) => (0, e.validateTuple)(p, "items"),
    };
  return ((xe.default = r), xe);
}
var et = {},
  Mr;
function us() {
  if (Mr) return et;
  ((Mr = 1), Object.defineProperty(et, "__esModule", { value: !0 }));
  const e = J(),
    r = Y(),
    p = he(),
    i = cn(),
    o = {
      keyword: "items",
      type: "array",
      schemaType: ["object", "boolean"],
      before: "uniqueItems",
      error: {
        message: ({ params: { len: l } }) =>
          (0, e.str)`must NOT have more than ${l} items`,
        params: ({ params: { len: l } }) => (0, e._)`{limit: ${l}}`,
      },
      code(l) {
        const { schema: u, parentSchema: f, it: v } = l,
          { prefixItems: y } = f;
        ((v.items = !0),
          !(0, r.alwaysValidSchema)(v, u) &&
            (y
              ? (0, i.validateAdditionalItems)(l, y)
              : l.ok((0, p.validateArray)(l))));
      },
    };
  return ((et.default = o), et);
}
var tt = {},
  Ar;
function cs() {
  if (Ar) return tt;
  ((Ar = 1), Object.defineProperty(tt, "__esModule", { value: !0 }));
  const e = J(),
    r = Y(),
    i = {
      keyword: "contains",
      type: "array",
      schemaType: ["object", "boolean"],
      before: "uniqueItems",
      trackErrors: !0,
      error: {
        message: ({ params: { min: g, max: o } }) =>
          o === void 0
            ? (0, e.str)`must contain at least ${g} valid item(s)`
            : (0,
              e.str)`must contain at least ${g} and no more than ${o} valid item(s)`,
        params: ({ params: { min: g, max: o } }) =>
          o === void 0
            ? (0, e._)`{minContains: ${g}}`
            : (0, e._)`{minContains: ${g}, maxContains: ${o}}`,
      },
      code(g) {
        const { gen: o, schema: l, parentSchema: u, data: f, it: v } = g;
        let y, E;
        const { minContains: P, maxContains: S } = u;
        v.opts.next ? ((y = P === void 0 ? 1 : P), (E = S)) : (y = 1);
        const h = o.const("len", (0, e._)`${f}.length`);
        if ((g.setParams({ min: y, max: E }), E === void 0 && y === 0)) {
          (0, r.checkStrictMode)(
            v,
            '"minContains" == 0 without "maxContains": "contains" keyword ignored',
          );
          return;
        }
        if (E !== void 0 && y > E) {
          ((0, r.checkStrictMode)(
            v,
            '"minContains" > "maxContains" is always invalid',
          ),
            g.fail());
          return;
        }
        if ((0, r.alwaysValidSchema)(v, l)) {
          let n = (0, e._)`${h} >= ${y}`;
          (E !== void 0 && (n = (0, e._)`${n} && ${h} <= ${E}`), g.pass(n));
          return;
        }
        v.items = !0;
        const b = o.name("valid");
        (E === void 0 && y === 1
          ? a(b, () => o.if(b, () => o.break()))
          : y === 0
            ? (o.let(b, !0), E !== void 0 && o.if((0, e._)`${f}.length > 0`, s))
            : (o.let(b, !1), s()),
          g.result(b, () => g.reset()));
        function s() {
          const n = o.name("_valid"),
            d = o.let("count", 0);
          a(n, () => o.if(n, () => t(d)));
        }
        function a(n, d) {
          o.forRange("i", 0, h, (_) => {
            (g.subschema(
              {
                keyword: "contains",
                dataProp: _,
                dataPropType: r.Type.Num,
                compositeRule: !0,
              },
              n,
            ),
              d());
          });
        }
        function t(n) {
          (o.code((0, e._)`${n}++`),
            E === void 0
              ? o.if((0, e._)`${n} >= ${y}`, () => o.assign(b, !0).break())
              : (o.if((0, e._)`${n} > ${E}`, () => o.assign(b, !1).break()),
                y === 1
                  ? o.assign(b, !0)
                  : o.if((0, e._)`${n} >= ${y}`, () => o.assign(b, !0))));
        }
      },
    };
  return ((tt.default = i), tt);
}
var Mt = {},
  Dr;
function ds() {
  return (
    Dr ||
      ((Dr = 1),
      (function (e) {
        (Object.defineProperty(e, "__esModule", { value: !0 }),
          (e.validateSchemaDeps = e.validatePropertyDeps = e.error = void 0));
        const r = J(),
          p = Y(),
          i = he();
        e.error = {
          message: ({ params: { property: f, depsCount: v, deps: y } }) => {
            const E = v === 1 ? "property" : "properties";
            return (0,
            r.str)`must have ${E} ${y} when property ${f} is present`;
          },
          params: ({
            params: { property: f, depsCount: v, deps: y, missingProperty: E },
          }) => (0, r._)`{property: ${f},
    missingProperty: ${E},
    depsCount: ${v},
    deps: ${y}}`,
        };
        const g = {
          keyword: "dependencies",
          type: "object",
          schemaType: "object",
          error: e.error,
          code(f) {
            const [v, y] = o(f);
            (l(f, v), u(f, y));
          },
        };
        function o({ schema: f }) {
          const v = {},
            y = {};
          for (const E in f) {
            if (E === "__proto__") continue;
            const P = Array.isArray(f[E]) ? v : y;
            P[E] = f[E];
          }
          return [v, y];
        }
        function l(f, v = f.schema) {
          const { gen: y, data: E, it: P } = f;
          if (Object.keys(v).length === 0) return;
          const S = y.let("missing");
          for (const h in v) {
            const b = v[h];
            if (b.length === 0) continue;
            const s = (0, i.propertyInData)(y, E, h, P.opts.ownProperties);
            (f.setParams({
              property: h,
              depsCount: b.length,
              deps: b.join(", "),
            }),
              P.allErrors
                ? y.if(s, () => {
                    for (const a of b) (0, i.checkReportMissingProp)(f, a);
                  })
                : (y.if(
                    (0, r._)`${s} && (${(0, i.checkMissingProp)(f, b, S)})`,
                  ),
                  (0, i.reportMissingProp)(f, S),
                  y.else()));
          }
        }
        e.validatePropertyDeps = l;
        function u(f, v = f.schema) {
          const { gen: y, data: E, keyword: P, it: S } = f,
            h = y.name("valid");
          for (const b in v)
            (0, p.alwaysValidSchema)(S, v[b]) ||
              (y.if(
                (0, i.propertyInData)(y, E, b, S.opts.ownProperties),
                () => {
                  const s = f.subschema({ keyword: P, schemaProp: b }, h);
                  f.mergeValidEvaluated(s, h);
                },
                () => y.var(h, !0),
              ),
              f.ok(h));
        }
        ((e.validateSchemaDeps = u), (e.default = g));
      })(Mt)),
    Mt
  );
}
var rt = {},
  Vr;
function ls() {
  if (Vr) return rt;
  ((Vr = 1), Object.defineProperty(rt, "__esModule", { value: !0 }));
  const e = J(),
    r = Y(),
    i = {
      keyword: "propertyNames",
      type: "object",
      schemaType: ["object", "boolean"],
      error: {
        message: "property name must be valid",
        params: ({ params: g }) => (0, e._)`{propertyName: ${g.propertyName}}`,
      },
      code(g) {
        const { gen: o, schema: l, data: u, it: f } = g;
        if ((0, r.alwaysValidSchema)(f, l)) return;
        const v = o.name("valid");
        (o.forIn("key", u, (y) => {
          (g.setParams({ propertyName: y }),
            g.subschema(
              {
                keyword: "propertyNames",
                data: y,
                dataTypes: ["string"],
                propertyName: y,
                compositeRule: !0,
              },
              v,
            ),
            o.if((0, e.not)(v), () => {
              (g.error(!0), f.allErrors || o.break());
            }));
        }),
          g.ok(v));
      },
    };
  return ((rt.default = i), rt);
}
var nt = {},
  zr;
function ln() {
  if (zr) return nt;
  ((zr = 1), Object.defineProperty(nt, "__esModule", { value: !0 }));
  const e = he(),
    r = J(),
    p = ve(),
    i = Y(),
    o = {
      keyword: "additionalProperties",
      type: ["object"],
      schemaType: ["boolean", "object"],
      allowUndefined: !0,
      trackErrors: !0,
      error: {
        message: "must NOT have additional properties",
        params: ({ params: l }) =>
          (0, r._)`{additionalProperty: ${l.additionalProperty}}`,
      },
      code(l) {
        const {
          gen: u,
          schema: f,
          parentSchema: v,
          data: y,
          errsCount: E,
          it: P,
        } = l;
        if (!E) throw new Error("ajv implementation error");
        const { allErrors: S, opts: h } = P;
        if (
          ((P.props = !0),
          h.removeAdditional !== "all" && (0, i.alwaysValidSchema)(P, f))
        )
          return;
        const b = (0, e.allSchemaProperties)(v.properties),
          s = (0, e.allSchemaProperties)(v.patternProperties);
        (a(), l.ok((0, r._)`${E} === ${p.default.errors}`));
        function a() {
          u.forIn("key", y, (m) => {
            !b.length && !s.length ? d(m) : u.if(t(m), () => d(m));
          });
        }
        function t(m) {
          let $;
          if (b.length > 8) {
            const T = (0, i.schemaRefOrVal)(P, v.properties, "properties");
            $ = (0, e.isOwnProperty)(u, T, m);
          } else
            b.length
              ? ($ = (0, r.or)(...b.map((T) => (0, r._)`${m} === ${T}`)))
              : ($ = r.nil);
          return (
            s.length &&
              ($ = (0, r.or)(
                $,
                ...s.map(
                  (T) => (0, r._)`${(0, e.usePattern)(l, T)}.test(${m})`,
                ),
              )),
            (0, r.not)($)
          );
        }
        function n(m) {
          u.code((0, r._)`delete ${y}[${m}]`);
        }
        function d(m) {
          if (
            h.removeAdditional === "all" ||
            (h.removeAdditional && f === !1)
          ) {
            n(m);
            return;
          }
          if (f === !1) {
            (l.setParams({ additionalProperty: m }), l.error(), S || u.break());
            return;
          }
          if (typeof f == "object" && !(0, i.alwaysValidSchema)(P, f)) {
            const $ = u.name("valid");
            h.removeAdditional === "failing"
              ? (_(m, $, !1),
                u.if((0, r.not)($), () => {
                  (l.reset(), n(m));
                }))
              : (_(m, $), S || u.if((0, r.not)($), () => u.break()));
          }
        }
        function _(m, $, T) {
          const M = {
            keyword: "additionalProperties",
            dataProp: m,
            dataPropType: i.Type.Str,
          };
          (T === !1 &&
            Object.assign(M, {
              compositeRule: !0,
              createErrors: !1,
              allErrors: !1,
            }),
            l.subschema(M, $));
        }
      },
    };
  return ((nt.default = o), nt);
}
var st = {},
  Fr;
function fs() {
  if (Fr) return st;
  ((Fr = 1), Object.defineProperty(st, "__esModule", { value: !0 }));
  const e = $t(),
    r = he(),
    p = Y(),
    i = ln(),
    g = {
      keyword: "properties",
      type: "object",
      schemaType: "object",
      code(o) {
        const { gen: l, schema: u, parentSchema: f, data: v, it: y } = o;
        y.opts.removeAdditional === "all" &&
          f.additionalProperties === void 0 &&
          i.default.code(
            new e.KeywordCxt(y, i.default, "additionalProperties"),
          );
        const E = (0, r.allSchemaProperties)(u);
        for (const s of E) y.definedProperties.add(s);
        y.opts.unevaluated &&
          E.length &&
          y.props !== !0 &&
          (y.props = p.mergeEvaluated.props(l, (0, p.toHash)(E), y.props));
        const P = E.filter((s) => !(0, p.alwaysValidSchema)(y, u[s]));
        if (P.length === 0) return;
        const S = l.name("valid");
        for (const s of P)
          (h(s)
            ? b(s)
            : (l.if((0, r.propertyInData)(l, v, s, y.opts.ownProperties)),
              b(s),
              y.allErrors || l.else().var(S, !0),
              l.endIf()),
            o.it.definedProperties.add(s),
            o.ok(S));
        function h(s) {
          return (
            y.opts.useDefaults && !y.compositeRule && u[s].default !== void 0
          );
        }
        function b(s) {
          o.subschema({ keyword: "properties", schemaProp: s, dataProp: s }, S);
        }
      },
    };
  return ((st.default = g), st);
}
var at = {},
  Lr;
function hs() {
  if (Lr) return at;
  ((Lr = 1), Object.defineProperty(at, "__esModule", { value: !0 }));
  const e = he(),
    r = J(),
    p = Y(),
    i = Y(),
    g = {
      keyword: "patternProperties",
      type: "object",
      schemaType: "object",
      code(o) {
        const { gen: l, schema: u, data: f, parentSchema: v, it: y } = o,
          { opts: E } = y,
          P = (0, e.allSchemaProperties)(u),
          S = P.filter((d) => (0, p.alwaysValidSchema)(y, u[d]));
        if (
          P.length === 0 ||
          (S.length === P.length && (!y.opts.unevaluated || y.props === !0))
        )
          return;
        const h = E.strictSchema && !E.allowMatchingProperties && v.properties,
          b = l.name("valid");
        y.props !== !0 &&
          !(y.props instanceof r.Name) &&
          (y.props = (0, i.evaluatedPropsToName)(l, y.props));
        const { props: s } = y;
        a();
        function a() {
          for (const d of P)
            (h && t(d), y.allErrors ? n(d) : (l.var(b, !0), n(d), l.if(b)));
        }
        function t(d) {
          for (const _ in h)
            new RegExp(d).test(_) &&
              (0, p.checkStrictMode)(
                y,
                `property ${_} matches pattern ${d} (use allowMatchingProperties)`,
              );
        }
        function n(d) {
          l.forIn("key", f, (_) => {
            l.if((0, r._)`${(0, e.usePattern)(o, d)}.test(${_})`, () => {
              const m = S.includes(d);
              (m ||
                o.subschema(
                  {
                    keyword: "patternProperties",
                    schemaProp: d,
                    dataProp: _,
                    dataPropType: i.Type.Str,
                  },
                  b,
                ),
                y.opts.unevaluated && s !== !0
                  ? l.assign((0, r._)`${s}[${_}]`, !0)
                  : !m && !y.allErrors && l.if((0, r.not)(b), () => l.break()));
            });
          });
        }
      },
    };
  return ((at.default = g), at);
}
var ot = {},
  Ur;
function ms() {
  if (Ur) return ot;
  ((Ur = 1), Object.defineProperty(ot, "__esModule", { value: !0 }));
  const e = Y(),
    r = {
      keyword: "not",
      schemaType: ["object", "boolean"],
      trackErrors: !0,
      code(p) {
        const { gen: i, schema: g, it: o } = p;
        if ((0, e.alwaysValidSchema)(o, g)) {
          p.fail();
          return;
        }
        const l = i.name("valid");
        (p.subschema(
          {
            keyword: "not",
            compositeRule: !0,
            createErrors: !1,
            allErrors: !1,
          },
          l,
        ),
          p.failResult(
            l,
            () => p.reset(),
            () => p.error(),
          ));
      },
      error: { message: "must NOT be valid" },
    };
  return ((ot.default = r), ot);
}
var it = {},
  Kr;
function ps() {
  if (Kr) return it;
  ((Kr = 1), Object.defineProperty(it, "__esModule", { value: !0 }));
  const r = {
    keyword: "anyOf",
    schemaType: "array",
    trackErrors: !0,
    code: he().validateUnion,
    error: { message: "must match a schema in anyOf" },
  };
  return ((it.default = r), it);
}
var ut = {},
  Hr;
function ys() {
  if (Hr) return ut;
  ((Hr = 1), Object.defineProperty(ut, "__esModule", { value: !0 }));
  const e = J(),
    r = Y(),
    i = {
      keyword: "oneOf",
      schemaType: "array",
      trackErrors: !0,
      error: {
        message: "must match exactly one schema in oneOf",
        params: ({ params: g }) => (0, e._)`{passingSchemas: ${g.passing}}`,
      },
      code(g) {
        const { gen: o, schema: l, parentSchema: u, it: f } = g;
        if (!Array.isArray(l)) throw new Error("ajv implementation error");
        if (f.opts.discriminator && u.discriminator) return;
        const v = l,
          y = o.let("valid", !1),
          E = o.let("passing", null),
          P = o.name("_valid");
        (g.setParams({ passing: E }),
          o.block(S),
          g.result(
            y,
            () => g.reset(),
            () => g.error(!0),
          ));
        function S() {
          v.forEach((h, b) => {
            let s;
            ((0, r.alwaysValidSchema)(f, h)
              ? o.var(P, !0)
              : (s = g.subschema(
                  { keyword: "oneOf", schemaProp: b, compositeRule: !0 },
                  P,
                )),
              b > 0 &&
                o
                  .if((0, e._)`${P} && ${y}`)
                  .assign(y, !1)
                  .assign(E, (0, e._)`[${E}, ${b}]`)
                  .else(),
              o.if(P, () => {
                (o.assign(y, !0),
                  o.assign(E, b),
                  s && g.mergeEvaluated(s, e.Name));
              }));
          });
        }
      },
    };
  return ((ut.default = i), ut);
}
var ct = {},
  Gr;
function _s() {
  if (Gr) return ct;
  ((Gr = 1), Object.defineProperty(ct, "__esModule", { value: !0 }));
  const e = Y(),
    r = {
      keyword: "allOf",
      schemaType: "array",
      code(p) {
        const { gen: i, schema: g, it: o } = p;
        if (!Array.isArray(g)) throw new Error("ajv implementation error");
        const l = i.name("valid");
        g.forEach((u, f) => {
          if ((0, e.alwaysValidSchema)(o, u)) return;
          const v = p.subschema({ keyword: "allOf", schemaProp: f }, l);
          (p.ok(l), p.mergeEvaluated(v));
        });
      },
    };
  return ((ct.default = r), ct);
}
var dt = {},
  Jr;
function vs() {
  if (Jr) return dt;
  ((Jr = 1), Object.defineProperty(dt, "__esModule", { value: !0 }));
  const e = J(),
    r = Y(),
    i = {
      keyword: "if",
      schemaType: ["object", "boolean"],
      trackErrors: !0,
      error: {
        message: ({ params: o }) =>
          (0, e.str)`must match "${o.ifClause}" schema`,
        params: ({ params: o }) => (0, e._)`{failingKeyword: ${o.ifClause}}`,
      },
      code(o) {
        const { gen: l, parentSchema: u, it: f } = o;
        u.then === void 0 &&
          u.else === void 0 &&
          (0, r.checkStrictMode)(
            f,
            '"if" without "then" and "else" is ignored',
          );
        const v = g(f, "then"),
          y = g(f, "else");
        if (!v && !y) return;
        const E = l.let("valid", !0),
          P = l.name("_valid");
        if ((S(), o.reset(), v && y)) {
          const b = l.let("ifClause");
          (o.setParams({ ifClause: b }), l.if(P, h("then", b), h("else", b)));
        } else v ? l.if(P, h("then")) : l.if((0, e.not)(P), h("else"));
        o.pass(E, () => o.error(!0));
        function S() {
          const b = o.subschema(
            {
              keyword: "if",
              compositeRule: !0,
              createErrors: !1,
              allErrors: !1,
            },
            P,
          );
          o.mergeEvaluated(b);
        }
        function h(b, s) {
          return () => {
            const a = o.subschema({ keyword: b }, P);
            (l.assign(E, P),
              o.mergeValidEvaluated(a, E),
              s ? l.assign(s, (0, e._)`${b}`) : o.setParams({ ifClause: b }));
          };
        }
      },
    };
  function g(o, l) {
    const u = o.schema[l];
    return u !== void 0 && !(0, r.alwaysValidSchema)(o, u);
  }
  return ((dt.default = i), dt);
}
var lt = {},
  Wr;
function gs() {
  if (Wr) return lt;
  ((Wr = 1), Object.defineProperty(lt, "__esModule", { value: !0 }));
  const e = Y(),
    r = {
      keyword: ["then", "else"],
      schemaType: ["object", "boolean"],
      code({ keyword: p, parentSchema: i, it: g }) {
        i.if === void 0 &&
          (0, e.checkStrictMode)(g, `"${p}" without "if" is ignored`);
      },
    };
  return ((lt.default = r), lt);
}
var Br;
function $s() {
  if (Br) return Qe;
  ((Br = 1), Object.defineProperty(Qe, "__esModule", { value: !0 }));
  const e = cn(),
    r = is(),
    p = dn(),
    i = us(),
    g = cs(),
    o = ds(),
    l = ls(),
    u = ln(),
    f = fs(),
    v = hs(),
    y = ms(),
    E = ps(),
    P = ys(),
    S = _s(),
    h = vs(),
    b = gs();
  function s(a = !1) {
    const t = [
      y.default,
      E.default,
      P.default,
      S.default,
      h.default,
      b.default,
      l.default,
      u.default,
      o.default,
      f.default,
      v.default,
    ];
    return (
      a ? t.push(r.default, i.default) : t.push(e.default, p.default),
      t.push(g.default),
      t
    );
  }
  return ((Qe.default = s), Qe);
}
var ft = {},
  ht = {},
  Yr;
function ws() {
  if (Yr) return ht;
  ((Yr = 1), Object.defineProperty(ht, "__esModule", { value: !0 }));
  const e = J(),
    p = {
      keyword: "format",
      type: ["number", "string"],
      schemaType: "string",
      $data: !0,
      error: {
        message: ({ schemaCode: i }) => (0, e.str)`must match format "${i}"`,
        params: ({ schemaCode: i }) => (0, e._)`{format: ${i}}`,
      },
      code(i, g) {
        const {
            gen: o,
            data: l,
            $data: u,
            schema: f,
            schemaCode: v,
            it: y,
          } = i,
          { opts: E, errSchemaPath: P, schemaEnv: S, self: h } = y;
        if (!E.validateFormats) return;
        u ? b() : s();
        function b() {
          const a = o.scopeValue("formats", {
              ref: h.formats,
              code: E.code.formats,
            }),
            t = o.const("fDef", (0, e._)`${a}[${v}]`),
            n = o.let("fType"),
            d = o.let("format");
          (o.if(
            (0, e._)`typeof ${t} == "object" && !(${t} instanceof RegExp)`,
            () =>
              o
                .assign(n, (0, e._)`${t}.type || "string"`)
                .assign(d, (0, e._)`${t}.validate`),
            () => o.assign(n, (0, e._)`"string"`).assign(d, t),
          ),
            i.fail$data((0, e.or)(_(), m())));
          function _() {
            return E.strictSchema === !1 ? e.nil : (0, e._)`${v} && !${d}`;
          }
          function m() {
            const $ = S.$async
                ? (0, e._)`(${t}.async ? await ${d}(${l}) : ${d}(${l}))`
                : (0, e._)`${d}(${l})`,
              T = (0,
              e._)`(typeof ${d} == "function" ? ${$} : ${d}.test(${l}))`;
            return (0, e._)`${d} && ${d} !== true && ${n} === ${g} && !${T}`;
          }
        }
        function s() {
          const a = h.formats[f];
          if (!a) {
            _();
            return;
          }
          if (a === !0) return;
          const [t, n, d] = m(a);
          t === g && i.pass($());
          function _() {
            if (E.strictSchema === !1) {
              h.logger.warn(T());
              return;
            }
            throw new Error(T());
            function T() {
              return `unknown format "${f}" ignored in schema at path "${P}"`;
            }
          }
          function m(T) {
            const M =
                T instanceof RegExp
                  ? (0, e.regexpCode)(T)
                  : E.code.formats
                    ? (0, e._)`${E.code.formats}${(0, e.getProperty)(f)}`
                    : void 0,
              F = o.scopeValue("formats", { key: f, ref: T, code: M });
            return typeof T == "object" && !(T instanceof RegExp)
              ? [T.type || "string", T.validate, (0, e._)`${F}.validate`]
              : ["string", T, F];
          }
          function $() {
            if (typeof a == "object" && !(a instanceof RegExp) && a.async) {
              if (!S.$async) throw new Error("async format in sync schema");
              return (0, e._)`await ${d}(${l})`;
            }
            return typeof n == "function"
              ? (0, e._)`${d}(${l})`
              : (0, e._)`${d}.test(${l})`;
          }
        }
      },
    };
  return ((ht.default = p), ht);
}
var Xr;
function bs() {
  if (Xr) return ft;
  ((Xr = 1), Object.defineProperty(ft, "__esModule", { value: !0 }));
  const r = [ws().default];
  return ((ft.default = r), ft);
}
var we = {},
  Zr;
function Es() {
  return (
    Zr ||
      ((Zr = 1),
      Object.defineProperty(we, "__esModule", { value: !0 }),
      (we.contentVocabulary = we.metadataVocabulary = void 0),
      (we.metadataVocabulary = [
        "title",
        "description",
        "default",
        "deprecated",
        "readOnly",
        "writeOnly",
        "examples",
      ]),
      (we.contentVocabulary = [
        "contentMediaType",
        "contentEncoding",
        "contentSchema",
      ])),
    we
  );
}
var Qr;
function Ss() {
  if (Qr) return Ae;
  ((Qr = 1), Object.defineProperty(Ae, "__esModule", { value: !0 }));
  const e = Bn(),
    r = os(),
    p = $s(),
    i = bs(),
    g = Es(),
    o = [
      e.default,
      r.default,
      (0, p.default)(),
      i.default,
      g.metadataVocabulary,
      g.contentVocabulary,
    ];
  return ((Ae.default = o), Ae);
}
var mt = {},
  ke = {},
  xr;
function Ps() {
  if (xr) return ke;
  ((xr = 1),
    Object.defineProperty(ke, "__esModule", { value: !0 }),
    (ke.DiscrError = void 0));
  var e;
  return (
    (function (r) {
      ((r.Tag = "tag"), (r.Mapping = "mapping"));
    })(e || (ke.DiscrError = e = {})),
    ke
  );
}
var en;
function Rs() {
  if (en) return mt;
  ((en = 1), Object.defineProperty(mt, "__esModule", { value: !0 }));
  const e = J(),
    r = Ps(),
    p = zt(),
    i = wt(),
    g = Y(),
    l = {
      keyword: "discriminator",
      type: "object",
      schemaType: "object",
      error: {
        message: ({ params: { discrError: u, tagName: f } }) =>
          u === r.DiscrError.Tag
            ? `tag "${f}" must be string`
            : `value of tag "${f}" must be in oneOf`,
        params: ({ params: { discrError: u, tag: f, tagName: v } }) =>
          (0, e._)`{error: ${u}, tag: ${v}, tagValue: ${f}}`,
      },
      code(u) {
        const { gen: f, data: v, schema: y, parentSchema: E, it: P } = u,
          { oneOf: S } = E;
        if (!P.opts.discriminator)
          throw new Error("discriminator: requires discriminator option");
        const h = y.propertyName;
        if (typeof h != "string")
          throw new Error("discriminator: requires propertyName");
        if (y.mapping)
          throw new Error("discriminator: mapping is not supported");
        if (!S) throw new Error("discriminator: requires oneOf keyword");
        const b = f.let("valid", !1),
          s = f.const("tag", (0, e._)`${v}${(0, e.getProperty)(h)}`);
        (f.if(
          (0, e._)`typeof ${s} == "string"`,
          () => a(),
          () =>
            u.error(!1, { discrError: r.DiscrError.Tag, tag: s, tagName: h }),
        ),
          u.ok(b));
        function a() {
          const d = n();
          f.if(!1);
          for (const _ in d)
            (f.elseIf((0, e._)`${s} === ${_}`), f.assign(b, t(d[_])));
          (f.else(),
            u.error(!1, {
              discrError: r.DiscrError.Mapping,
              tag: s,
              tagName: h,
            }),
            f.endIf());
        }
        function t(d) {
          const _ = f.name("valid"),
            m = u.subschema({ keyword: "oneOf", schemaProp: d }, _);
          return (u.mergeEvaluated(m, e.Name), _);
        }
        function n() {
          var d;
          const _ = {},
            m = T(E);
          let $ = !0;
          for (let I = 0; I < S.length; I++) {
            let V = S[I];
            if (V?.$ref && !(0, g.schemaHasRulesButRef)(V, P.self.RULES)) {
              const L = V.$ref;
              if (
                ((V = p.resolveRef.call(P.self, P.schemaEnv.root, P.baseId, L)),
                V instanceof p.SchemaEnv && (V = V.schema),
                V === void 0)
              )
                throw new i.default(P.opts.uriResolver, P.baseId, L);
            }
            const z =
              (d = V?.properties) === null || d === void 0 ? void 0 : d[h];
            if (typeof z != "object")
              throw new Error(
                `discriminator: oneOf subschemas (or referenced schemas) must have "properties/${h}"`,
              );
            (($ = $ && (m || T(V))), M(z, I));
          }
          if (!$) throw new Error(`discriminator: "${h}" must be required`);
          return _;
          function T({ required: I }) {
            return Array.isArray(I) && I.includes(h);
          }
          function M(I, V) {
            if (I.const) F(I.const, V);
            else if (I.enum) for (const z of I.enum) F(z, V);
            else
              throw new Error(
                `discriminator: "properties/${h}" must have "const" or "enum"`,
              );
          }
          function F(I, V) {
            if (typeof I != "string" || I in _)
              throw new Error(
                `discriminator: "${h}" values must be unique strings`,
              );
            _[I] = V;
          }
        }
      },
    };
  return ((mt.default = l), mt);
}
const Ns = "http://json-schema.org/draft-07/schema#",
  ks = "http://json-schema.org/draft-07/schema#",
  Os = "Core schema meta-schema",
  Ts = {
    schemaArray: { type: "array", minItems: 1, items: { $ref: "#" } },
    nonNegativeInteger: { type: "integer", minimum: 0 },
    nonNegativeIntegerDefault0: {
      allOf: [{ $ref: "#/definitions/nonNegativeInteger" }, { default: 0 }],
    },
    simpleTypes: {
      enum: [
        "array",
        "boolean",
        "integer",
        "null",
        "number",
        "object",
        "string",
      ],
    },
    stringArray: {
      type: "array",
      items: { type: "string" },
      uniqueItems: !0,
      default: [],
    },
  },
  js = ["object", "boolean"],
  Is = {
    $id: { type: "string", format: "uri-reference" },
    $schema: { type: "string", format: "uri" },
    $ref: { type: "string", format: "uri-reference" },
    $comment: { type: "string" },
    title: { type: "string" },
    description: { type: "string" },
    default: !0,
    readOnly: { type: "boolean", default: !1 },
    examples: { type: "array", items: !0 },
    multipleOf: { type: "number", exclusiveMinimum: 0 },
    maximum: { type: "number" },
    exclusiveMaximum: { type: "number" },
    minimum: { type: "number" },
    exclusiveMinimum: { type: "number" },
    maxLength: { $ref: "#/definitions/nonNegativeInteger" },
    minLength: { $ref: "#/definitions/nonNegativeIntegerDefault0" },
    pattern: { type: "string", format: "regex" },
    additionalItems: { $ref: "#" },
    items: {
      anyOf: [{ $ref: "#" }, { $ref: "#/definitions/schemaArray" }],
      default: !0,
    },
    maxItems: { $ref: "#/definitions/nonNegativeInteger" },
    minItems: { $ref: "#/definitions/nonNegativeIntegerDefault0" },
    uniqueItems: { type: "boolean", default: !1 },
    contains: { $ref: "#" },
    maxProperties: { $ref: "#/definitions/nonNegativeInteger" },
    minProperties: { $ref: "#/definitions/nonNegativeIntegerDefault0" },
    required: { $ref: "#/definitions/stringArray" },
    additionalProperties: { $ref: "#" },
    definitions: {
      type: "object",
      additionalProperties: { $ref: "#" },
      default: {},
    },
    properties: {
      type: "object",
      additionalProperties: { $ref: "#" },
      default: {},
    },
    patternProperties: {
      type: "object",
      additionalProperties: { $ref: "#" },
      propertyNames: { format: "regex" },
      default: {},
    },
    dependencies: {
      type: "object",
      additionalProperties: {
        anyOf: [{ $ref: "#" }, { $ref: "#/definitions/stringArray" }],
      },
    },
    propertyNames: { $ref: "#" },
    const: !0,
    enum: { type: "array", items: !0, minItems: 1, uniqueItems: !0 },
    type: {
      anyOf: [
        { $ref: "#/definitions/simpleTypes" },
        {
          type: "array",
          items: { $ref: "#/definitions/simpleTypes" },
          minItems: 1,
          uniqueItems: !0,
        },
      ],
    },
    format: { type: "string" },
    contentMediaType: { type: "string" },
    contentEncoding: { type: "string" },
    if: { $ref: "#" },
    then: { $ref: "#" },
    else: { $ref: "#" },
    allOf: { $ref: "#/definitions/schemaArray" },
    anyOf: { $ref: "#/definitions/schemaArray" },
    oneOf: { $ref: "#/definitions/schemaArray" },
    not: { $ref: "#" },
  },
  qs = {
    $schema: Ns,
    $id: ks,
    title: Os,
    definitions: Ts,
    type: js,
    properties: Is,
    default: !0,
  };
var tn;
function fn() {
  return (
    tn ||
      ((tn = 1),
      (function (e, r) {
        (Object.defineProperty(r, "__esModule", { value: !0 }),
          (r.MissingRefError =
            r.ValidationError =
            r.CodeGen =
            r.Name =
            r.nil =
            r.stringify =
            r.str =
            r._ =
            r.KeywordCxt =
            r.Ajv =
              void 0));
        const p = Gn(),
          i = Ss(),
          g = Rs(),
          o = qs,
          l = ["/properties"],
          u = "http://json-schema.org/draft-07/schema";
        class f extends p.default {
          _addVocabularies() {
            (super._addVocabularies(),
              i.default.forEach((h) => this.addVocabulary(h)),
              this.opts.discriminator && this.addKeyword(g.default));
          }
          _addDefaultMetaSchema() {
            if ((super._addDefaultMetaSchema(), !this.opts.meta)) return;
            const h = this.opts.$data ? this.$dataMetaSchema(o, l) : o;
            (this.addMetaSchema(h, u, !1),
              (this.refs["http://json-schema.org/schema"] = u));
          }
          defaultMeta() {
            return (this.opts.defaultMeta =
              super.defaultMeta() || (this.getSchema(u) ? u : void 0));
          }
        }
        ((r.Ajv = f),
          (e.exports = r = f),
          (e.exports.Ajv = f),
          Object.defineProperty(r, "__esModule", { value: !0 }),
          (r.default = f));
        var v = $t();
        Object.defineProperty(r, "KeywordCxt", {
          enumerable: !0,
          get: function () {
            return v.KeywordCxt;
          },
        });
        var y = J();
        (Object.defineProperty(r, "_", {
          enumerable: !0,
          get: function () {
            return y._;
          },
        }),
          Object.defineProperty(r, "str", {
            enumerable: !0,
            get: function () {
              return y.str;
            },
          }),
          Object.defineProperty(r, "stringify", {
            enumerable: !0,
            get: function () {
              return y.stringify;
            },
          }),
          Object.defineProperty(r, "nil", {
            enumerable: !0,
            get: function () {
              return y.nil;
            },
          }),
          Object.defineProperty(r, "Name", {
            enumerable: !0,
            get: function () {
              return y.Name;
            },
          }),
          Object.defineProperty(r, "CodeGen", {
            enumerable: !0,
            get: function () {
              return y.CodeGen;
            },
          }));
        var E = Vt();
        Object.defineProperty(r, "ValidationError", {
          enumerable: !0,
          get: function () {
            return E.default;
          },
        });
        var P = wt();
        Object.defineProperty(r, "MissingRefError", {
          enumerable: !0,
          get: function () {
            return P.default;
          },
        });
      })(je, je.exports)),
    je.exports
  );
}
var Cs = fn(),
  pt = { exports: {} },
  At = {},
  rn;
function Ms() {
  return (
    rn ||
      ((rn = 1),
      (function (e) {
        (Object.defineProperty(e, "__esModule", { value: !0 }),
          (e.formatNames = e.fastFormats = e.fullFormats = void 0));
        function r(I, V) {
          return { validate: I, compare: V };
        }
        ((e.fullFormats = {
          date: r(o, l),
          time: r(f(!0), v),
          "date-time": r(P(!0), S),
          "iso-time": r(f(), y),
          "iso-date-time": r(P(), h),
          duration:
            /^P(?!$)((\d+Y)?(\d+M)?(\d+D)?(T(?=\d)(\d+H)?(\d+M)?(\d+S)?)?|(\d+W)?)$/,
          uri: a,
          "uri-reference":
            /^(?:[a-z][a-z0-9+\-.]*:)?(?:\/?\/(?:(?:[a-z0-9\-._~!$&'()*+,;=:]|%[0-9a-f]{2})*@)?(?:\[(?:(?:(?:(?:[0-9a-f]{1,4}:){6}|::(?:[0-9a-f]{1,4}:){5}|(?:[0-9a-f]{1,4})?::(?:[0-9a-f]{1,4}:){4}|(?:(?:[0-9a-f]{1,4}:){0,1}[0-9a-f]{1,4})?::(?:[0-9a-f]{1,4}:){3}|(?:(?:[0-9a-f]{1,4}:){0,2}[0-9a-f]{1,4})?::(?:[0-9a-f]{1,4}:){2}|(?:(?:[0-9a-f]{1,4}:){0,3}[0-9a-f]{1,4})?::[0-9a-f]{1,4}:|(?:(?:[0-9a-f]{1,4}:){0,4}[0-9a-f]{1,4})?::)(?:[0-9a-f]{1,4}:[0-9a-f]{1,4}|(?:(?:25[0-5]|2[0-4]\d|[01]?\d\d?)\.){3}(?:25[0-5]|2[0-4]\d|[01]?\d\d?))|(?:(?:[0-9a-f]{1,4}:){0,5}[0-9a-f]{1,4})?::[0-9a-f]{1,4}|(?:(?:[0-9a-f]{1,4}:){0,6}[0-9a-f]{1,4})?::)|[Vv][0-9a-f]+\.[a-z0-9\-._~!$&'()*+,;=:]+)\]|(?:(?:25[0-5]|2[0-4]\d|[01]?\d\d?)\.){3}(?:25[0-5]|2[0-4]\d|[01]?\d\d?)|(?:[a-z0-9\-._~!$&'"()*+,;=]|%[0-9a-f]{2})*)(?::\d*)?(?:\/(?:[a-z0-9\-._~!$&'"()*+,;=:@]|%[0-9a-f]{2})*)*|\/(?:(?:[a-z0-9\-._~!$&'"()*+,;=:@]|%[0-9a-f]{2})+(?:\/(?:[a-z0-9\-._~!$&'"()*+,;=:@]|%[0-9a-f]{2})*)*)?|(?:[a-z0-9\-._~!$&'"()*+,;=:@]|%[0-9a-f]{2})+(?:\/(?:[a-z0-9\-._~!$&'"()*+,;=:@]|%[0-9a-f]{2})*)*)?(?:\?(?:[a-z0-9\-._~!$&'"()*+,;=:@/?]|%[0-9a-f]{2})*)?(?:#(?:[a-z0-9\-._~!$&'"()*+,;=:@/?]|%[0-9a-f]{2})*)?$/i,
          "uri-template":
            /^(?:(?:[^\x00-\x20"'<>%\\^`{|}]|%[0-9a-f]{2})|\{[+#./;?&=,!@|]?(?:[a-z0-9_]|%[0-9a-f]{2})+(?::[1-9][0-9]{0,3}|\*)?(?:,(?:[a-z0-9_]|%[0-9a-f]{2})+(?::[1-9][0-9]{0,3}|\*)?)*\})*$/i,
          url: /^(?:https?|ftp):\/\/(?:\S+(?::\S*)?@)?(?:(?!(?:10|127)(?:\.\d{1,3}){3})(?!(?:169\.254|192\.168)(?:\.\d{1,3}){2})(?!172\.(?:1[6-9]|2\d|3[0-1])(?:\.\d{1,3}){2})(?:[1-9]\d?|1\d\d|2[01]\d|22[0-3])(?:\.(?:1?\d{1,2}|2[0-4]\d|25[0-5])){2}(?:\.(?:[1-9]\d?|1\d\d|2[0-4]\d|25[0-4]))|(?:(?:[a-z0-9\u{00a1}-\u{ffff}]+-)*[a-z0-9\u{00a1}-\u{ffff}]+)(?:\.(?:[a-z0-9\u{00a1}-\u{ffff}]+-)*[a-z0-9\u{00a1}-\u{ffff}]+)*(?:\.(?:[a-z\u{00a1}-\u{ffff}]{2,})))(?::\d{2,5})?(?:\/[^\s]*)?$/iu,
          email:
            /^[a-z0-9!#$%&'*+/=?^_`{|}~-]+(?:\.[a-z0-9!#$%&'*+/=?^_`{|}~-]+)*@(?:[a-z0-9](?:[a-z0-9-]*[a-z0-9])?\.)+[a-z0-9](?:[a-z0-9-]*[a-z0-9])?$/i,
          hostname:
            /^(?=.{1,253}\.?$)[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?(?:\.[a-z0-9](?:[-0-9a-z]{0,61}[0-9a-z])?)*\.?$/i,
          ipv4: /^(?:(?:25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)\.){3}(?:25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)$/,
          ipv6: /^((([0-9a-f]{1,4}:){7}([0-9a-f]{1,4}|:))|(([0-9a-f]{1,4}:){6}(:[0-9a-f]{1,4}|((25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3})|:))|(([0-9a-f]{1,4}:){5}(((:[0-9a-f]{1,4}){1,2})|:((25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3})|:))|(([0-9a-f]{1,4}:){4}(((:[0-9a-f]{1,4}){1,3})|((:[0-9a-f]{1,4})?:((25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3}))|:))|(([0-9a-f]{1,4}:){3}(((:[0-9a-f]{1,4}){1,4})|((:[0-9a-f]{1,4}){0,2}:((25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3}))|:))|(([0-9a-f]{1,4}:){2}(((:[0-9a-f]{1,4}){1,5})|((:[0-9a-f]{1,4}){0,3}:((25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3}))|:))|(([0-9a-f]{1,4}:){1}(((:[0-9a-f]{1,4}){1,6})|((:[0-9a-f]{1,4}){0,4}:((25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3}))|:))|(:(((:[0-9a-f]{1,4}){1,7})|((:[0-9a-f]{1,4}){0,5}:((25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3}))|:)))$/i,
          regex: F,
          uuid: /^(?:urn:uuid:)?[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$/i,
          "json-pointer": /^(?:\/(?:[^~/]|~0|~1)*)*$/,
          "json-pointer-uri-fragment":
            /^#(?:\/(?:[a-z0-9_\-.!$&'()*+,;:=@]|%[0-9a-f]{2}|~0|~1)*)*$/i,
          "relative-json-pointer":
            /^(?:0|[1-9][0-9]*)(?:#|(?:\/(?:[^~/]|~0|~1)*)*)$/,
          byte: n,
          int32: { type: "number", validate: m },
          int64: { type: "number", validate: $ },
          float: { type: "number", validate: T },
          double: { type: "number", validate: T },
          password: !0,
          binary: !0,
        }),
          (e.fastFormats = {
            ...e.fullFormats,
            date: r(/^\d\d\d\d-[0-1]\d-[0-3]\d$/, l),
            time: r(
              /^(?:[0-2]\d:[0-5]\d:[0-5]\d|23:59:60)(?:\.\d+)?(?:z|[+-]\d\d(?::?\d\d)?)$/i,
              v,
            ),
            "date-time": r(
              /^\d\d\d\d-[0-1]\d-[0-3]\dt(?:[0-2]\d:[0-5]\d:[0-5]\d|23:59:60)(?:\.\d+)?(?:z|[+-]\d\d(?::?\d\d)?)$/i,
              S,
            ),
            "iso-time": r(
              /^(?:[0-2]\d:[0-5]\d:[0-5]\d|23:59:60)(?:\.\d+)?(?:z|[+-]\d\d(?::?\d\d)?)?$/i,
              y,
            ),
            "iso-date-time": r(
              /^\d\d\d\d-[0-1]\d-[0-3]\d[t\s](?:[0-2]\d:[0-5]\d:[0-5]\d|23:59:60)(?:\.\d+)?(?:z|[+-]\d\d(?::?\d\d)?)?$/i,
              h,
            ),
            uri: /^(?:[a-z][a-z0-9+\-.]*:)(?:\/?\/)?[^\s]*$/i,
            "uri-reference":
              /^(?:(?:[a-z][a-z0-9+\-.]*:)?\/?\/)?(?:[^\\\s#][^\s#]*)?(?:#[^\\\s]*)?$/i,
            email:
              /^[a-z0-9.!#$%&'*+/=?^_`{|}~-]+@[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?)*$/i,
          }),
          (e.formatNames = Object.keys(e.fullFormats)));
        function p(I) {
          return I % 4 === 0 && (I % 100 !== 0 || I % 400 === 0);
        }
        const i = /^(\d\d\d\d)-(\d\d)-(\d\d)$/,
          g = [0, 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
        function o(I) {
          const V = i.exec(I);
          if (!V) return !1;
          const z = +V[1],
            L = +V[2],
            Z = +V[3];
          return (
            L >= 1 && L <= 12 && Z >= 1 && Z <= (L === 2 && p(z) ? 29 : g[L])
          );
        }
        function l(I, V) {
          if (I && V) return I > V ? 1 : I < V ? -1 : 0;
        }
        const u =
          /^(\d\d):(\d\d):(\d\d(?:\.\d+)?)(z|([+-])(\d\d)(?::?(\d\d))?)?$/i;
        function f(I) {
          return function (z) {
            const L = u.exec(z);
            if (!L) return !1;
            const Z = +L[1],
              ne = +L[2],
              se = +L[3],
              x = L[4],
              de = L[5] === "-" ? -1 : 1,
              A = +(L[6] || 0),
              N = +(L[7] || 0);
            if (A > 23 || N > 59 || (I && !x)) return !1;
            if (Z <= 23 && ne <= 59 && se < 60) return !0;
            const C = ne - N * de,
              O = Z - A * de - (C < 0 ? 1 : 0);
            return (O === 23 || O === -1) && (C === 59 || C === -1) && se < 61;
          };
        }
        function v(I, V) {
          if (!(I && V)) return;
          const z = new Date("2020-01-01T" + I).valueOf(),
            L = new Date("2020-01-01T" + V).valueOf();
          if (z && L) return z - L;
        }
        function y(I, V) {
          if (!(I && V)) return;
          const z = u.exec(I),
            L = u.exec(V);
          if (z && L)
            return (
              (I = z[1] + z[2] + z[3]),
              (V = L[1] + L[2] + L[3]),
              I > V ? 1 : I < V ? -1 : 0
            );
        }
        const E = /t|\s/i;
        function P(I) {
          const V = f(I);
          return function (L) {
            const Z = L.split(E);
            return Z.length === 2 && o(Z[0]) && V(Z[1]);
          };
        }
        function S(I, V) {
          if (!(I && V)) return;
          const z = new Date(I).valueOf(),
            L = new Date(V).valueOf();
          if (z && L) return z - L;
        }
        function h(I, V) {
          if (!(I && V)) return;
          const [z, L] = I.split(E),
            [Z, ne] = V.split(E),
            se = l(z, Z);
          if (se !== void 0) return se || v(L, ne);
        }
        const b = /\/|:/,
          s =
            /^(?:[a-z][a-z0-9+\-.]*:)(?:\/?\/(?:(?:[a-z0-9\-._~!$&'()*+,;=:]|%[0-9a-f]{2})*@)?(?:\[(?:(?:(?:(?:[0-9a-f]{1,4}:){6}|::(?:[0-9a-f]{1,4}:){5}|(?:[0-9a-f]{1,4})?::(?:[0-9a-f]{1,4}:){4}|(?:(?:[0-9a-f]{1,4}:){0,1}[0-9a-f]{1,4})?::(?:[0-9a-f]{1,4}:){3}|(?:(?:[0-9a-f]{1,4}:){0,2}[0-9a-f]{1,4})?::(?:[0-9a-f]{1,4}:){2}|(?:(?:[0-9a-f]{1,4}:){0,3}[0-9a-f]{1,4})?::[0-9a-f]{1,4}:|(?:(?:[0-9a-f]{1,4}:){0,4}[0-9a-f]{1,4})?::)(?:[0-9a-f]{1,4}:[0-9a-f]{1,4}|(?:(?:25[0-5]|2[0-4]\d|[01]?\d\d?)\.){3}(?:25[0-5]|2[0-4]\d|[01]?\d\d?))|(?:(?:[0-9a-f]{1,4}:){0,5}[0-9a-f]{1,4})?::[0-9a-f]{1,4}|(?:(?:[0-9a-f]{1,4}:){0,6}[0-9a-f]{1,4})?::)|[Vv][0-9a-f]+\.[a-z0-9\-._~!$&'()*+,;=:]+)\]|(?:(?:25[0-5]|2[0-4]\d|[01]?\d\d?)\.){3}(?:25[0-5]|2[0-4]\d|[01]?\d\d?)|(?:[a-z0-9\-._~!$&'()*+,;=]|%[0-9a-f]{2})*)(?::\d*)?(?:\/(?:[a-z0-9\-._~!$&'()*+,;=:@]|%[0-9a-f]{2})*)*|\/(?:(?:[a-z0-9\-._~!$&'()*+,;=:@]|%[0-9a-f]{2})+(?:\/(?:[a-z0-9\-._~!$&'()*+,;=:@]|%[0-9a-f]{2})*)*)?|(?:[a-z0-9\-._~!$&'()*+,;=:@]|%[0-9a-f]{2})+(?:\/(?:[a-z0-9\-._~!$&'()*+,;=:@]|%[0-9a-f]{2})*)*)(?:\?(?:[a-z0-9\-._~!$&'()*+,;=:@/?]|%[0-9a-f]{2})*)?(?:#(?:[a-z0-9\-._~!$&'()*+,;=:@/?]|%[0-9a-f]{2})*)?$/i;
        function a(I) {
          return b.test(I) && s.test(I);
        }
        const t =
          /^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/gm;
        function n(I) {
          return ((t.lastIndex = 0), t.test(I));
        }
        const d = -2147483648,
          _ = 2 ** 31 - 1;
        function m(I) {
          return Number.isInteger(I) && I <= _ && I >= d;
        }
        function $(I) {
          return Number.isInteger(I);
        }
        function T() {
          return !0;
        }
        const M = /[^\\]\\Z/;
        function F(I) {
          if (M.test(I)) return !1;
          try {
            return (new RegExp(I), !0);
          } catch {
            return !1;
          }
        }
      })(At)),
    At
  );
}
var Dt = {},
  nn;
function As() {
  return (
    nn ||
      ((nn = 1),
      (function (e) {
        (Object.defineProperty(e, "__esModule", { value: !0 }),
          (e.formatLimitDefinition = void 0));
        const r = fn(),
          p = J(),
          i = p.operators,
          g = {
            formatMaximum: { okStr: "<=", ok: i.LTE, fail: i.GT },
            formatMinimum: { okStr: ">=", ok: i.GTE, fail: i.LT },
            formatExclusiveMaximum: { okStr: "<", ok: i.LT, fail: i.GTE },
            formatExclusiveMinimum: { okStr: ">", ok: i.GT, fail: i.LTE },
          },
          o = {
            message: ({ keyword: u, schemaCode: f }) =>
              (0, p.str)`should be ${g[u].okStr} ${f}`,
            params: ({ keyword: u, schemaCode: f }) =>
              (0, p._)`{comparison: ${g[u].okStr}, limit: ${f}}`,
          };
        e.formatLimitDefinition = {
          keyword: Object.keys(g),
          type: "string",
          schemaType: "string",
          $data: !0,
          error: o,
          code(u) {
            const { gen: f, data: v, schemaCode: y, keyword: E, it: P } = u,
              { opts: S, self: h } = P;
            if (!S.validateFormats) return;
            const b = new r.KeywordCxt(
              P,
              h.RULES.all.format.definition,
              "format",
            );
            b.$data ? s() : a();
            function s() {
              const n = f.scopeValue("formats", {
                  ref: h.formats,
                  code: S.code.formats,
                }),
                d = f.const("fmt", (0, p._)`${n}[${b.schemaCode}]`);
              u.fail$data(
                (0, p.or)(
                  (0, p._)`typeof ${d} != "object"`,
                  (0, p._)`${d} instanceof RegExp`,
                  (0, p._)`typeof ${d}.compare != "function"`,
                  t(d),
                ),
              );
            }
            function a() {
              const n = b.schema,
                d = h.formats[n];
              if (!d || d === !0) return;
              if (
                typeof d != "object" ||
                d instanceof RegExp ||
                typeof d.compare != "function"
              )
                throw new Error(
                  `"${E}": format "${n}" does not define "compare" function`,
                );
              const _ = f.scopeValue("formats", {
                key: n,
                ref: d,
                code: S.code.formats
                  ? (0, p._)`${S.code.formats}${(0, p.getProperty)(n)}`
                  : void 0,
              });
              u.fail$data(t(_));
            }
            function t(n) {
              return (0, p._)`${n}.compare(${v}, ${y}) ${g[E].fail} 0`;
            }
          },
          dependencies: ["format"],
        };
        const l = (u) => (u.addKeyword(e.formatLimitDefinition), u);
        e.default = l;
      })(Dt)),
    Dt
  );
}
var sn;
function Ds() {
  return (
    sn ||
      ((sn = 1),
      (function (e, r) {
        Object.defineProperty(r, "__esModule", { value: !0 });
        const p = Ms(),
          i = As(),
          g = J(),
          o = new g.Name("fullFormats"),
          l = new g.Name("fastFormats"),
          u = (v, y = { keywords: !0 }) => {
            if (Array.isArray(y)) return (f(v, y, p.fullFormats, o), v);
            const [E, P] =
                y.mode === "fast" ? [p.fastFormats, l] : [p.fullFormats, o],
              S = y.formats || p.formatNames;
            return (f(v, S, E, P), y.keywords && (0, i.default)(v), v);
          };
        u.get = (v, y = "full") => {
          const P = (y === "fast" ? p.fastFormats : p.fullFormats)[v];
          if (!P) throw new Error(`Unknown format "${v}"`);
          return P;
        };
        function f(v, y, E, P) {
          var S, h;
          ((S = (h = v.opts.code).formats) !== null && S !== void 0) ||
            (h.formats = (0, g._)`require("ajv-formats/dist/formats").${P}`);
          for (const b of y) v.addFormat(b, E[b]);
        }
        ((e.exports = r = u),
          Object.defineProperty(r, "__esModule", { value: !0 }),
          (r.default = u));
      })(pt, pt.exports)),
    pt.exports
  );
}
var Vs = Ds();
const zs = Nn(Vs);
function Fs() {
  const e = new Cs.Ajv({
    strict: !1,
    validateFormats: !0,
    validateSchema: !1,
    allErrors: !0,
  });
  return (zs(e), e);
}
class Ls {
  constructor(r) {
    this._ajv = r ?? Fs();
  }
  getValidator(r) {
    var p;
    const i =
      "$id" in r && typeof r.$id == "string"
        ? (p = this._ajv.getSchema(r.$id)) !== null && p !== void 0
          ? p
          : this._ajv.compile(r)
        : this._ajv.compile(r);
    return (g) =>
      i(g)
        ? { valid: !0, data: g, errorMessage: void 0 }
        : {
            valid: !1,
            data: void 0,
            errorMessage: this._ajv.errorsText(i.errors),
          };
  }
}
class io extends mn {
  constructor(r, p) {
    var i, g;
    (super(p),
      (this._clientInfo = r),
      (this._cachedToolOutputValidators = new Map()),
      (this._capabilities =
        (i = p?.capabilities) !== null && i !== void 0 ? i : {}),
      (this._jsonSchemaValidator =
        (g = p?.jsonSchemaValidator) !== null && g !== void 0 ? g : new Ls()));
  }
  registerCapabilities(r) {
    if (this.transport)
      throw new Error(
        "Cannot register capabilities after connecting to transport",
      );
    this._capabilities = pn(this._capabilities, r);
  }
  assertCapability(r, p) {
    var i;
    if (!(!((i = this._serverCapabilities) === null || i === void 0) && i[r]))
      throw new Error(`Server does not support ${r} (required for ${p})`);
  }
  async connect(r, p) {
    if ((await super.connect(r), r.sessionId === void 0))
      try {
        const i = await this.request(
          {
            method: "initialize",
            params: {
              protocolVersion: yn,
              capabilities: this._capabilities,
              clientInfo: this._clientInfo,
            },
          },
          _n,
          p,
        );
        if (i === void 0)
          throw new Error(`Server sent invalid initialize result: ${i}`);
        if (!vn.includes(i.protocolVersion))
          throw new Error(
            `Server's protocol version is not supported: ${i.protocolVersion}`,
          );
        ((this._serverCapabilities = i.capabilities),
          (this._serverVersion = i.serverInfo),
          r.setProtocolVersion && r.setProtocolVersion(i.protocolVersion),
          (this._instructions = i.instructions),
          await this.notification({ method: "notifications/initialized" }));
      } catch (i) {
        throw (this.close(), i);
      }
  }
  getServerCapabilities() {
    return this._serverCapabilities;
  }
  getServerVersion() {
    return this._serverVersion;
  }
  getInstructions() {
    return this._instructions;
  }
  assertCapabilityForMethod(r) {
    var p, i, g, o, l;
    switch (r) {
      case "logging/setLevel":
        if (!(
          !((p = this._serverCapabilities) === null || p === void 0) &&
          p.logging
        ))
          throw new Error(
            `Server does not support logging (required for ${r})`,
          );
        break;
      case "prompts/get":
      case "prompts/list":
        if (!(
          !((i = this._serverCapabilities) === null || i === void 0) &&
          i.prompts
        ))
          throw new Error(
            `Server does not support prompts (required for ${r})`,
          );
        break;
      case "resources/list":
      case "resources/templates/list":
      case "resources/read":
      case "resources/subscribe":
      case "resources/unsubscribe":
        if (!(
          !((g = this._serverCapabilities) === null || g === void 0) &&
          g.resources
        ))
          throw new Error(
            `Server does not support resources (required for ${r})`,
          );
        if (
          r === "resources/subscribe" &&
          !this._serverCapabilities.resources.subscribe
        )
          throw new Error(
            `Server does not support resource subscriptions (required for ${r})`,
          );
        break;
      case "tools/call":
      case "tools/list":
        if (!(
          !((o = this._serverCapabilities) === null || o === void 0) && o.tools
        ))
          throw new Error(`Server does not support tools (required for ${r})`);
        break;
      case "completion/complete":
        if (!(
          !((l = this._serverCapabilities) === null || l === void 0) &&
          l.completions
        ))
          throw new Error(
            `Server does not support completions (required for ${r})`,
          );
        break;
    }
  }
  assertNotificationCapability(r) {
    var p;
    switch (r) {
      case "notifications/roots/list_changed":
        if (!(
          !((p = this._capabilities.roots) === null || p === void 0) &&
          p.listChanged
        ))
          throw new Error(
            `Client does not support roots list changed notifications (required for ${r})`,
          );
        break;
    }
  }
  assertRequestHandlerCapability(r) {
    switch (r) {
      case "sampling/createMessage":
        if (!this._capabilities.sampling)
          throw new Error(
            `Client does not support sampling capability (required for ${r})`,
          );
        break;
      case "elicitation/create":
        if (!this._capabilities.elicitation)
          throw new Error(
            `Client does not support elicitation capability (required for ${r})`,
          );
        break;
      case "roots/list":
        if (!this._capabilities.roots)
          throw new Error(
            `Client does not support roots capability (required for ${r})`,
          );
        break;
    }
  }
  async ping(r) {
    return this.request({ method: "ping" }, Oe, r);
  }
  async complete(r, p) {
    return this.request({ method: "completion/complete", params: r }, gn, p);
  }
  async setLoggingLevel(r, p) {
    return this.request(
      { method: "logging/setLevel", params: { level: r } },
      Oe,
      p,
    );
  }
  async getPrompt(r, p) {
    return this.request({ method: "prompts/get", params: r }, $n, p);
  }
  async listPrompts(r, p) {
    return this.request({ method: "prompts/list", params: r }, wn, p);
  }
  async listResources(r, p) {
    return this.request({ method: "resources/list", params: r }, bn, p);
  }
  async listResourceTemplates(r, p) {
    return this.request(
      { method: "resources/templates/list", params: r },
      En,
      p,
    );
  }
  async readResource(r, p) {
    return this.request({ method: "resources/read", params: r }, Sn, p);
  }
  async subscribeResource(r, p) {
    return this.request({ method: "resources/subscribe", params: r }, Oe, p);
  }
  async unsubscribeResource(r, p) {
    return this.request({ method: "resources/unsubscribe", params: r }, Oe, p);
  }
  async callTool(r, p = Pn, i) {
    const g = await this.request({ method: "tools/call", params: r }, p, i),
      o = this.getToolOutputValidator(r.name);
    if (o) {
      if (!g.structuredContent && !g.isError)
        throw new Te(
          Pt.InvalidRequest,
          `Tool ${r.name} has an output schema but did not return structured content`,
        );
      if (g.structuredContent)
        try {
          const l = o(g.structuredContent);
          if (!l.valid)
            throw new Te(
              Pt.InvalidParams,
              `Structured content does not match the tool's output schema: ${l.errorMessage}`,
            );
        } catch (l) {
          throw l instanceof Te
            ? l
            : new Te(
                Pt.InvalidParams,
                `Failed to validate structured content: ${l instanceof Error ? l.message : String(l)}`,
              );
        }
    }
    return g;
  }
  cacheToolOutputSchemas(r) {
    this._cachedToolOutputValidators.clear();
    for (const p of r)
      if (p.outputSchema) {
        const i = this._jsonSchemaValidator.getValidator(p.outputSchema);
        this._cachedToolOutputValidators.set(p.name, i);
      }
  }
  getToolOutputValidator(r) {
    return this._cachedToolOutputValidators.get(r);
  }
  async listTools(r, p) {
    const i = await this.request({ method: "tools/list", params: r }, Rn, p);
    return (this.cacheToolOutputSchemas(i.tools), i);
  }
  async sendRootsListChanged() {
    return this.notification({ method: "notifications/roots/list_changed" });
  }
}
export { io as Client };
//# sourceMappingURL=index-BpO2rBmi.mjs.map
