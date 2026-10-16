import { ac as J, a7 as vo } from "./sentry-common-BNqrY_yc.js";
import { k as wo, m as bo, O as So } from "./client-Czi1iXro.js";
import {
  a0 as x,
  c0 as h,
  ag as fe,
  a9 as D,
  cN as u,
  cl as P,
  a8 as A,
  bS as g,
  ay as G,
  aB as N,
  cT as ye,
  b$ as w,
  bs as Bn,
  bR as To,
} from "./matrix-util-8DbIGEm-.js";
import "./index-Cw3pknxT.js";
import "./main-process-state-BDOn7dvV.js";
import "./index-5FBEE1WD.js";
import "./index-Ch31Akxs.js";
(function () {
  try {
    var t =
      typeof window < "u"
        ? window
        : typeof global < "u"
          ? global
          : typeof globalThis < "u"
            ? globalThis
            : typeof self < "u"
              ? self
              : {};
    t.SENTRY_RELEASE = { id: "4.3.209" };
    var e = new t.Error().stack;
    e &&
      ((t._sentryDebugIds = t._sentryDebugIds || {}),
      (t._sentryDebugIds[e] = "eee5a283-b339-48d8-b94b-3d0ef909f413"),
      (t._sentryDebugIdIdentifier =
        "sentry-dbid-eee5a283-b339-48d8-b94b-3d0ef909f413"));
  } catch {}
})();
async function Ot(t) {
  try {
    return [null, await t()];
  } catch (e) {
    return [e, null];
  }
}
function Io(t) {
  const e = Object.values(t).filter((r) => typeof r == "number");
  return Object.entries(t)
    .filter(([r, o]) => e.indexOf(+r) === -1)
    .map(([r, o]) => o);
}
class zn {
  constructor() {
    ((this._map = new Map()), (this._idmap = new Map()));
  }
  add(e, ...n) {
    const r = n[0];
    if ((this._map.set(e, r), r && typeof r == "object" && "id" in r)) {
      if (this._idmap.has(r.id))
        throw new Error(`ID ${r.id} already exists in the registry`);
      this._idmap.set(r.id, e);
    }
    return this;
  }
  clear() {
    return ((this._map = new Map()), (this._idmap = new Map()), this);
  }
  remove(e) {
    const n = this._map.get(e);
    return (
      n && typeof n == "object" && "id" in n && this._idmap.delete(n.id),
      this._map.delete(e),
      this
    );
  }
  get(e) {
    const n = e._zod.parent;
    if (n) {
      const r = { ...(this.get(n) ?? {}) };
      return (delete r.id, { ...r, ...this._map.get(e) });
    }
    return this._map.get(e);
  }
  has(e) {
    return this._map.has(e);
  }
}
function xo() {
  return new zn();
}
const Ao = xo();
class Vt {
  constructor(e) {
    ((this.counter = 0),
      (this.metadataRegistry = e?.metadata ?? Ao),
      (this.target = e?.target ?? "draft-2020-12"),
      (this.unrepresentable = e?.unrepresentable ?? "throw"),
      (this.override = e?.override ?? (() => {})),
      (this.io = e?.io ?? "output"),
      (this.seen = new Map()));
  }
  process(e, n = { path: [], schemaPath: [] }) {
    var r;
    const o = e._zod.def,
      s = {
        guid: "uuid",
        url: "uri",
        datetime: "date-time",
        json_string: "json-string",
        regex: "",
      },
      a = this.seen.get(e);
    if (a)
      return (
        a.count++,
        n.schemaPath.includes(e) && (a.cycle = n.path),
        a.schema
      );
    const i = { schema: {}, count: 1, cycle: void 0, path: n.path };
    this.seen.set(e, i);
    const f = e._zod.toJSONSchema?.();
    if (f) i.schema = f;
    else {
      const d = { ...n, schemaPath: [...n.schemaPath, e], path: n.path },
        m = e._zod.parent;
      if (m)
        ((i.ref = m), this.process(m, d), (this.seen.get(m).isParent = !0));
      else {
        const y = i.schema;
        switch (o.type) {
          case "string": {
            const p = y;
            p.type = "string";
            const {
              minimum: v,
              maximum: _,
              format: T,
              patterns: b,
              contentEncoding: I,
            } = e._zod.bag;
            if (
              (typeof v == "number" && (p.minLength = v),
              typeof _ == "number" && (p.maxLength = _),
              T && ((p.format = s[T] ?? T), p.format === "" && delete p.format),
              I && (p.contentEncoding = I),
              b && b.size > 0)
            ) {
              const E = [...b];
              E.length === 1
                ? (p.pattern = E[0].source)
                : E.length > 1 &&
                  (i.schema.allOf = [
                    ...E.map((U) => ({
                      ...(this.target === "draft-7" ? { type: "string" } : {}),
                      pattern: U.source,
                    })),
                  ]);
            }
            break;
          }
          case "number": {
            const p = y,
              {
                minimum: v,
                maximum: _,
                format: T,
                multipleOf: b,
                exclusiveMaximum: I,
                exclusiveMinimum: E,
              } = e._zod.bag;
            (typeof T == "string" && T.includes("int")
              ? (p.type = "integer")
              : (p.type = "number"),
              typeof E == "number" && (p.exclusiveMinimum = E),
              typeof v == "number" &&
                ((p.minimum = v),
                typeof E == "number" &&
                  (E >= v ? delete p.minimum : delete p.exclusiveMinimum)),
              typeof I == "number" && (p.exclusiveMaximum = I),
              typeof _ == "number" &&
                ((p.maximum = _),
                typeof I == "number" &&
                  (I <= _ ? delete p.maximum : delete p.exclusiveMaximum)),
              typeof b == "number" && (p.multipleOf = b));
            break;
          }
          case "boolean": {
            const p = y;
            p.type = "boolean";
            break;
          }
          case "bigint": {
            if (this.unrepresentable === "throw")
              throw new Error("BigInt cannot be represented in JSON Schema");
            break;
          }
          case "symbol": {
            if (this.unrepresentable === "throw")
              throw new Error("Symbols cannot be represented in JSON Schema");
            break;
          }
          case "null": {
            y.type = "null";
            break;
          }
          case "any":
            break;
          case "unknown":
            break;
          case "undefined": {
            if (this.unrepresentable === "throw")
              throw new Error("Undefined cannot be represented in JSON Schema");
            break;
          }
          case "void": {
            if (this.unrepresentable === "throw")
              throw new Error("Void cannot be represented in JSON Schema");
            break;
          }
          case "never": {
            y.not = {};
            break;
          }
          case "date": {
            if (this.unrepresentable === "throw")
              throw new Error("Date cannot be represented in JSON Schema");
            break;
          }
          case "array": {
            const p = y,
              { minimum: v, maximum: _ } = e._zod.bag;
            (typeof v == "number" && (p.minItems = v),
              typeof _ == "number" && (p.maxItems = _),
              (p.type = "array"),
              (p.items = this.process(o.element, {
                ...d,
                path: [...d.path, "items"],
              })));
            break;
          }
          case "object": {
            const p = y;
            ((p.type = "object"), (p.properties = {}));
            const v = o.shape;
            for (const b in v)
              p.properties[b] = this.process(v[b], {
                ...d,
                path: [...d.path, "properties", b],
              });
            const _ = new Set(Object.keys(v)),
              T = new Set(
                [..._].filter((b) => {
                  const I = o.shape[b]._zod;
                  return this.io === "input"
                    ? I.optin === void 0
                    : I.optout === void 0;
                }),
              );
            (T.size > 0 && (p.required = Array.from(T)),
              o.catchall?._zod.def.type === "never"
                ? (p.additionalProperties = !1)
                : o.catchall
                  ? o.catchall &&
                    (p.additionalProperties = this.process(o.catchall, {
                      ...d,
                      path: [...d.path, "additionalProperties"],
                    }))
                  : this.io === "output" && (p.additionalProperties = !1));
            break;
          }
          case "union": {
            const p = y;
            p.anyOf = o.options.map((v, _) =>
              this.process(v, { ...d, path: [...d.path, "anyOf", _] }),
            );
            break;
          }
          case "intersection": {
            const p = y,
              v = this.process(o.left, { ...d, path: [...d.path, "allOf", 0] }),
              _ = this.process(o.right, {
                ...d,
                path: [...d.path, "allOf", 1],
              }),
              T = (I) => "allOf" in I && Object.keys(I).length === 1,
              b = [...(T(v) ? v.allOf : [v]), ...(T(_) ? _.allOf : [_])];
            p.allOf = b;
            break;
          }
          case "tuple": {
            const p = y;
            p.type = "array";
            const v = o.items.map((b, I) =>
              this.process(b, { ...d, path: [...d.path, "prefixItems", I] }),
            );
            if (
              (this.target === "draft-2020-12"
                ? (p.prefixItems = v)
                : (p.items = v),
              o.rest)
            ) {
              const b = this.process(o.rest, {
                ...d,
                path: [...d.path, "items"],
              });
              this.target === "draft-2020-12"
                ? (p.items = b)
                : (p.additionalItems = b);
            }
            o.rest &&
              (p.items = this.process(o.rest, {
                ...d,
                path: [...d.path, "items"],
              }));
            const { minimum: _, maximum: T } = e._zod.bag;
            (typeof _ == "number" && (p.minItems = _),
              typeof T == "number" && (p.maxItems = T));
            break;
          }
          case "record": {
            const p = y;
            ((p.type = "object"),
              (p.propertyNames = this.process(o.keyType, {
                ...d,
                path: [...d.path, "propertyNames"],
              })),
              (p.additionalProperties = this.process(o.valueType, {
                ...d,
                path: [...d.path, "additionalProperties"],
              })));
            break;
          }
          case "map": {
            if (this.unrepresentable === "throw")
              throw new Error("Map cannot be represented in JSON Schema");
            break;
          }
          case "set": {
            if (this.unrepresentable === "throw")
              throw new Error("Set cannot be represented in JSON Schema");
            break;
          }
          case "enum": {
            const p = y,
              v = Io(o.entries);
            (v.every((_) => typeof _ == "number") && (p.type = "number"),
              v.every((_) => typeof _ == "string") && (p.type = "string"),
              (p.enum = v));
            break;
          }
          case "literal": {
            const p = y,
              v = [];
            for (const _ of o.values)
              if (_ === void 0) {
                if (this.unrepresentable === "throw")
                  throw new Error(
                    "Literal `undefined` cannot be represented in JSON Schema",
                  );
              } else if (typeof _ == "bigint") {
                if (this.unrepresentable === "throw")
                  throw new Error(
                    "BigInt literals cannot be represented in JSON Schema",
                  );
                v.push(Number(_));
              } else v.push(_);
            if (v.length !== 0)
              if (v.length === 1) {
                const _ = v[0];
                ((p.type = _ === null ? "null" : typeof _), (p.const = _));
              } else
                (v.every((_) => typeof _ == "number") && (p.type = "number"),
                  v.every((_) => typeof _ == "string") && (p.type = "string"),
                  v.every((_) => typeof _ == "boolean") && (p.type = "string"),
                  v.every((_) => _ === null) && (p.type = "null"),
                  (p.enum = v));
            break;
          }
          case "file": {
            const p = y,
              v = {
                type: "string",
                format: "binary",
                contentEncoding: "binary",
              },
              { minimum: _, maximum: T, mime: b } = e._zod.bag;
            (_ !== void 0 && (v.minLength = _),
              T !== void 0 && (v.maxLength = T),
              b
                ? b.length === 1
                  ? ((v.contentMediaType = b[0]), Object.assign(p, v))
                  : (p.anyOf = b.map((I) => ({ ...v, contentMediaType: I })))
                : Object.assign(p, v));
            break;
          }
          case "transform": {
            if (this.unrepresentable === "throw")
              throw new Error(
                "Transforms cannot be represented in JSON Schema",
              );
            break;
          }
          case "nullable": {
            const p = this.process(o.innerType, d);
            y.anyOf = [p, { type: "null" }];
            break;
          }
          case "nonoptional": {
            (this.process(o.innerType, d), (i.ref = o.innerType));
            break;
          }
          case "success": {
            const p = y;
            p.type = "boolean";
            break;
          }
          case "default": {
            (this.process(o.innerType, d),
              (i.ref = o.innerType),
              (y.default = JSON.parse(JSON.stringify(o.defaultValue))));
            break;
          }
          case "prefault": {
            (this.process(o.innerType, d),
              (i.ref = o.innerType),
              this.io === "input" &&
                (y._prefault = JSON.parse(JSON.stringify(o.defaultValue))));
            break;
          }
          case "catch": {
            (this.process(o.innerType, d), (i.ref = o.innerType));
            let p;
            try {
              p = o.catchValue(void 0);
            } catch {
              throw new Error(
                "Dynamic catch values are not supported in JSON Schema",
              );
            }
            y.default = p;
            break;
          }
          case "nan": {
            if (this.unrepresentable === "throw")
              throw new Error("NaN cannot be represented in JSON Schema");
            break;
          }
          case "template_literal": {
            const p = y,
              v = e._zod.pattern;
            if (!v) throw new Error("Pattern not found in template literal");
            ((p.type = "string"), (p.pattern = v.source));
            break;
          }
          case "pipe": {
            const p =
              this.io === "input"
                ? o.in._zod.def.type === "transform"
                  ? o.out
                  : o.in
                : o.out;
            (this.process(p, d), (i.ref = p));
            break;
          }
          case "readonly": {
            (this.process(o.innerType, d),
              (i.ref = o.innerType),
              (y.readOnly = !0));
            break;
          }
          case "promise": {
            (this.process(o.innerType, d), (i.ref = o.innerType));
            break;
          }
          case "optional": {
            (this.process(o.innerType, d), (i.ref = o.innerType));
            break;
          }
          case "lazy": {
            const p = e._zod.innerType;
            (this.process(p, d), (i.ref = p));
            break;
          }
          case "custom": {
            if (this.unrepresentable === "throw")
              throw new Error(
                "Custom types cannot be represented in JSON Schema",
              );
            break;
          }
        }
      }
    }
    const c = this.metadataRegistry.get(e);
    return (
      c && Object.assign(i.schema, c),
      this.io === "input" &&
        F(e) &&
        (delete i.schema.examples, delete i.schema.default),
      this.io === "input" &&
        i.schema._prefault &&
        ((r = i.schema).default ?? (r.default = i.schema._prefault)),
      delete i.schema._prefault,
      this.seen.get(e).schema
    );
  }
  emit(e, n) {
    const r = {
        cycles: n?.cycles ?? "ref",
        reused: n?.reused ?? "inline",
        external: n?.external ?? void 0,
      },
      o = this.seen.get(e);
    if (!o) throw new Error("Unprocessed schema. This is a bug in Zod.");
    const s = (l) => {
        const d = this.target === "draft-2020-12" ? "$defs" : "definitions";
        if (r.external) {
          const v = r.external.registry.get(l[0])?.id,
            _ = r.external.uri ?? ((b) => b);
          if (v) return { ref: _(v) };
          const T = l[1].defId ?? l[1].schema.id ?? `schema${this.counter++}`;
          return (
            (l[1].defId = T),
            { defId: T, ref: `${_("__shared")}#/${d}/${T}` }
          );
        }
        if (l[1] === o) return { ref: "#" };
        const y = `#/${d}/`,
          p = l[1].schema.id ?? `__schema${this.counter++}`;
        return { defId: p, ref: y + p };
      },
      a = (l) => {
        if (l[1].schema.$ref) return;
        const d = l[1],
          { ref: m, defId: y } = s(l);
        ((d.def = { ...d.schema }), y && (d.defId = y));
        const p = d.schema;
        for (const v in p) delete p[v];
        p.$ref = m;
      };
    if (r.cycles === "throw")
      for (const l of this.seen.entries()) {
        const d = l[1];
        if (d.cycle)
          throw new Error(`Cycle detected: #/${d.cycle?.join("/")}/<root>

Set the \`cycles\` parameter to \`"ref"\` to resolve cyclical schemas with defs.`);
      }
    for (const l of this.seen.entries()) {
      const d = l[1];
      if (e === l[0]) {
        a(l);
        continue;
      }
      if (r.external) {
        const y = r.external.registry.get(l[0])?.id;
        if (e !== l[0] && y) {
          a(l);
          continue;
        }
      }
      if (this.metadataRegistry.get(l[0])?.id) {
        a(l);
        continue;
      }
      if (d.cycle) {
        a(l);
        continue;
      }
      if (d.count > 1 && r.reused === "ref") {
        a(l);
        continue;
      }
    }
    const i = (l, d) => {
      const m = this.seen.get(l),
        y = m.def ?? m.schema,
        p = { ...y };
      if (m.ref === null) return;
      const v = m.ref;
      if (((m.ref = null), v)) {
        i(v, d);
        const _ = this.seen.get(v).schema;
        _.$ref && d.target === "draft-7"
          ? ((y.allOf = y.allOf ?? []), y.allOf.push(_))
          : (Object.assign(y, _), Object.assign(y, p));
      }
      m.isParent ||
        this.override({ zodSchema: l, jsonSchema: y, path: m.path ?? [] });
    };
    for (const l of [...this.seen.entries()].reverse())
      i(l[0], { target: this.target });
    const f = {};
    if (
      (this.target === "draft-2020-12"
        ? (f.$schema = "https://json-schema.org/draft/2020-12/schema")
        : this.target === "draft-7"
          ? (f.$schema = "http://json-schema.org/draft-07/schema#")
          : console.warn(`Invalid target: ${this.target}`),
      r.external?.uri)
    ) {
      const l = r.external.registry.get(e)?.id;
      if (!l) throw new Error("Schema is missing an `id` property");
      f.$id = r.external.uri(l);
    }
    Object.assign(f, o.def);
    const c = r.external?.defs ?? {};
    for (const l of this.seen.entries()) {
      const d = l[1];
      d.def && d.defId && (c[d.defId] = d.def);
    }
    r.external ||
      (Object.keys(c).length > 0 &&
        (this.target === "draft-2020-12"
          ? (f.$defs = c)
          : (f.definitions = c)));
    try {
      return JSON.parse(JSON.stringify(f));
    } catch {
      throw new Error("Error converting schema to JSON.");
    }
  }
}
function Do(t, e) {
  if (t instanceof zn) {
    const r = new Vt(e),
      o = {};
    for (const i of t._idmap.entries()) {
      const [f, c] = i;
      r.process(c);
    }
    const s = {},
      a = { registry: t, uri: e?.uri, defs: o };
    for (const i of t._idmap.entries()) {
      const [f, c] = i;
      s[f] = r.emit(c, { ...e, external: a });
    }
    if (Object.keys(o).length > 0) {
      const i = r.target === "draft-2020-12" ? "$defs" : "definitions";
      s.__shared = { [i]: o };
    }
    return { schemas: s };
  }
  const n = new Vt(e);
  return (n.process(t), n.emit(t, e));
}
function F(t, e) {
  const n = e ?? { seen: new Set() };
  if (n.seen.has(t)) return !1;
  n.seen.add(t);
  const o = t._zod.def;
  switch (o.type) {
    case "string":
    case "number":
    case "bigint":
    case "boolean":
    case "date":
    case "symbol":
    case "undefined":
    case "null":
    case "any":
    case "unknown":
    case "never":
    case "void":
    case "literal":
    case "enum":
    case "nan":
    case "file":
    case "template_literal":
      return !1;
    case "array":
      return F(o.element, n);
    case "object": {
      for (const s in o.shape) if (F(o.shape[s], n)) return !0;
      return !1;
    }
    case "union": {
      for (const s of o.options) if (F(s, n)) return !0;
      return !1;
    }
    case "intersection":
      return F(o.left, n) || F(o.right, n);
    case "tuple": {
      for (const s of o.items) if (F(s, n)) return !0;
      return !!(o.rest && F(o.rest, n));
    }
    case "record":
      return F(o.keyType, n) || F(o.valueType, n);
    case "map":
      return F(o.keyType, n) || F(o.valueType, n);
    case "set":
      return F(o.valueType, n);
    case "promise":
    case "optional":
    case "nonoptional":
    case "nullable":
    case "readonly":
      return F(o.innerType, n);
    case "lazy":
      return F(o.getter(), n);
    case "default":
      return F(o.innerType, n);
    case "prefault":
      return F(o.innerType, n);
    case "custom":
      return !1;
    case "transform":
      return !0;
    case "pipe":
      return F(o.in, n) || F(o.out, n);
    case "success":
      return !1;
    case "catch":
      return !1;
  }
  throw new Error(`Unknown schema type: ${o.type}`);
}
const ko = Symbol("Let zodToJsonSchema decide on which parser to use"),
  Yt = {
    name: void 0,
    $refStrategy: "root",
    effectStrategy: "input",
    pipeStrategy: "all",
    dateStrategy: "format:date-time",
    mapStrategy: "entries",
    nullableStrategy: "from-target",
    removeAdditionalStrategy: "passthrough",
    definitionPath: "definitions",
    target: "jsonSchema7",
    strictUnions: !1,
    errorMessages: !1,
    markdownDescription: !1,
    patternStrategy: "escape",
    applyRegexFlags: !1,
    emailStrategy: "format:email",
    base64Strategy: "contentEncoding:base64",
    nameStrategy: "ref",
  },
  Eo = (t) =>
    typeof t == "string"
      ? { ...Yt, basePath: ["#"], definitions: {}, name: t }
      : { ...Yt, basePath: ["#"], definitions: {}, ...t },
  vt = (t) => ("_def" in t ? t._def : t);
function Oo(t) {
  if (!t) return !0;
  for (const e in t) return !1;
  return !0;
}
const Co = (t) => {
  const e = Eo(t),
    n =
      e.name !== void 0
        ? [...e.basePath, e.definitionPath, e.name]
        : e.basePath;
  return {
    ...e,
    currentPath: n,
    propertyPath: void 0,
    seenRefs: new Set(),
    seen: new Map(
      Object.entries(e.definitions).map(([r, o]) => [
        vt(o),
        {
          def: vt(o),
          path: [...e.basePath, e.definitionPath, r],
          jsonSchema: void 0,
        },
      ]),
    ),
  };
};
function Zn(t, e, n, r) {
  r?.errorMessages && n && (t.errorMessage = { ...t.errorMessage, [e]: n });
}
function C(t, e, n, r, o) {
  ((t[e] = n), Zn(t, e, r, o));
}
function Ro() {
  return {};
}
function No(t, e) {
  const n = { type: "array" };
  return (
    t.type?._def?.typeName !== x.ZodAny &&
      (n.items = O(t.type._def, {
        ...e,
        currentPath: [...e.currentPath, "items"],
      })),
    t.minLength && C(n, "minItems", t.minLength.value, t.minLength.message, e),
    t.maxLength && C(n, "maxItems", t.maxLength.value, t.maxLength.message, e),
    t.exactLength &&
      (C(n, "minItems", t.exactLength.value, t.exactLength.message, e),
      C(n, "maxItems", t.exactLength.value, t.exactLength.message, e)),
    n
  );
}
function Po(t, e) {
  const n = { type: "integer", format: "int64" };
  if (!t.checks) return n;
  for (const r of t.checks)
    switch (r.kind) {
      case "min":
        e.target === "jsonSchema7"
          ? r.inclusive
            ? C(n, "minimum", r.value, r.message, e)
            : C(n, "exclusiveMinimum", r.value, r.message, e)
          : (r.inclusive || (n.exclusiveMinimum = !0),
            C(n, "minimum", r.value, r.message, e));
        break;
      case "max":
        e.target === "jsonSchema7"
          ? r.inclusive
            ? C(n, "maximum", r.value, r.message, e)
            : C(n, "exclusiveMaximum", r.value, r.message, e)
          : (r.inclusive || (n.exclusiveMaximum = !0),
            C(n, "maximum", r.value, r.message, e));
        break;
      case "multipleOf":
        C(n, "multipleOf", r.value, r.message, e);
        break;
    }
  return n;
}
function Mo() {
  return { type: "boolean" };
}
function Fo(t, e) {
  return O(t.type._def, e);
}
const Lo = (t, e) => O(t.innerType._def, e);
function qn(t, e, n) {
  const r = n ?? e.dateStrategy;
  if (Array.isArray(r)) return { anyOf: r.map((o, s) => qn(t, e, o)) };
  switch (r) {
    case "string":
    case "format:date-time":
      return { type: "string", format: "date-time" };
    case "format:date":
      return { type: "string", format: "date" };
    case "integer":
      return $o(t, e);
  }
}
const $o = (t, e) => {
  const n = { type: "integer", format: "unix-time" };
  if (e.target === "openApi3") return n;
  for (const r of t.checks)
    switch (r.kind) {
      case "min":
        C(n, "minimum", r.value, r.message, e);
        break;
      case "max":
        C(n, "maximum", r.value, r.message, e);
        break;
    }
  return n;
};
function jo(t, e) {
  return { ...O(t.innerType._def, e), default: t.defaultValue() };
}
function Uo(t, e, n) {
  return e.effectStrategy === "input" ? O(t.schema._def, e, n) : {};
}
function Jo(t) {
  return { type: "string", enum: [...t.values] };
}
const Go = (t) => ("type" in t && t.type === "string" ? !1 : "allOf" in t);
function Bo(t, e) {
  const n = [
    O(t.left._def, { ...e, currentPath: [...e.currentPath, "allOf", "0"] }),
    O(t.right._def, { ...e, currentPath: [...e.currentPath, "allOf", "1"] }),
  ].filter((s) => !!s);
  let r =
    e.target === "jsonSchema2019-09" ? { unevaluatedProperties: !1 } : void 0;
  const o = [];
  return (
    n.forEach((s) => {
      if (Go(s))
        (o.push(...s.allOf),
          s.unevaluatedProperties === void 0 && (r = void 0));
      else {
        let a = s;
        if ("additionalProperties" in s && s.additionalProperties === !1) {
          const { additionalProperties: i, ...f } = s;
          a = f;
        } else r = void 0;
        o.push(a);
      }
    }),
    o.length ? { allOf: o, ...r } : void 0
  );
}
function zo(t, e) {
  const n = typeof t.value;
  return n !== "bigint" && n !== "number" && n !== "boolean" && n !== "string"
    ? { type: Array.isArray(t.value) ? "array" : "object" }
    : e.target === "openApi3"
      ? { type: n === "bigint" ? "integer" : n, enum: [t.value] }
      : { type: n === "bigint" ? "integer" : n, const: t.value };
}
let lt;
const ie = {
  cuid: /^[cC][^\s-]{8,}$/,
  cuid2: /^[0-9a-z]+$/,
  ulid: /^[0-9A-HJKMNP-TV-Z]{26}$/,
  email:
    /^(?!\.)(?!.*\.\.)([a-zA-Z0-9_'+\-\.]*)[a-zA-Z0-9_+-]@([a-zA-Z0-9][a-zA-Z0-9\-]*\.)+[a-zA-Z]{2,}$/,
  emoji: () => (
    lt === void 0 &&
      (lt = RegExp(
        "^(\\p{Extended_Pictographic}|\\p{Emoji_Component})+$",
        "u",
      )),
    lt
  ),
  base64: /^([0-9a-zA-Z+/]{4})*(([0-9a-zA-Z+/]{2}==)|([0-9a-zA-Z+/]{3}=))?$/,
  nanoid: /^[a-zA-Z0-9_-]{21}$/,
};
function Hn(t, e) {
  const n = { type: "string" };
  function r(o) {
    return e.patternStrategy === "escape" ? Zo(o) : o;
  }
  if (t.checks)
    for (const o of t.checks)
      switch (o.kind) {
        case "min":
          C(
            n,
            "minLength",
            typeof n.minLength == "number"
              ? Math.max(n.minLength, o.value)
              : o.value,
            o.message,
            e,
          );
          break;
        case "max":
          C(
            n,
            "maxLength",
            typeof n.maxLength == "number"
              ? Math.min(n.maxLength, o.value)
              : o.value,
            o.message,
            e,
          );
          break;
        case "email":
          switch (e.emailStrategy) {
            case "format:email":
              H(n, "email", o.message, e);
              break;
            case "format:idn-email":
              H(n, "idn-email", o.message, e);
              break;
            case "pattern:zod":
              K(n, ie.email, o.message, e);
              break;
          }
          break;
        case "url":
          H(n, "uri", o.message, e);
          break;
        case "uuid":
          H(n, "uuid", o.message, e);
          break;
        case "regex":
          K(n, o.regex, o.message, e);
          break;
        case "cuid":
          K(n, ie.cuid, o.message, e);
          break;
        case "cuid2":
          K(n, ie.cuid2, o.message, e);
          break;
        case "startsWith":
          K(n, RegExp(`^${r(o.value)}`), o.message, e);
          break;
        case "endsWith":
          K(n, RegExp(`${r(o.value)}$`), o.message, e);
          break;
        case "datetime":
          H(n, "date-time", o.message, e);
          break;
        case "date":
          H(n, "date", o.message, e);
          break;
        case "time":
          H(n, "time", o.message, e);
          break;
        case "duration":
          H(n, "duration", o.message, e);
          break;
        case "length":
          (C(
            n,
            "minLength",
            typeof n.minLength == "number"
              ? Math.max(n.minLength, o.value)
              : o.value,
            o.message,
            e,
          ),
            C(
              n,
              "maxLength",
              typeof n.maxLength == "number"
                ? Math.min(n.maxLength, o.value)
                : o.value,
              o.message,
              e,
            ));
          break;
        case "includes": {
          K(n, RegExp(r(o.value)), o.message, e);
          break;
        }
        case "ip": {
          (o.version !== "v6" && H(n, "ipv4", o.message, e),
            o.version !== "v4" && H(n, "ipv6", o.message, e));
          break;
        }
        case "emoji":
          K(n, ie.emoji, o.message, e);
          break;
        case "ulid": {
          K(n, ie.ulid, o.message, e);
          break;
        }
        case "base64": {
          switch (e.base64Strategy) {
            case "format:binary": {
              H(n, "binary", o.message, e);
              break;
            }
            case "contentEncoding:base64": {
              C(n, "contentEncoding", "base64", o.message, e);
              break;
            }
            case "pattern:zod": {
              K(n, ie.base64, o.message, e);
              break;
            }
          }
          break;
        }
        case "nanoid":
          K(n, ie.nanoid, o.message, e);
      }
  return n;
}
const Zo = (t) =>
    Array.from(t)
      .map((e) => (/[a-zA-Z0-9]/.test(e) ? e : `\\${e}`))
      .join(""),
  H = (t, e, n, r) => {
    t.format || t.anyOf?.some((o) => o.format)
      ? (t.anyOf || (t.anyOf = []),
        t.format &&
          (t.anyOf.push({
            format: t.format,
            ...(t.errorMessage &&
              r.errorMessages && {
                errorMessage: { format: t.errorMessage.format },
              }),
          }),
          delete t.format,
          t.errorMessage &&
            (delete t.errorMessage.format,
            Object.keys(t.errorMessage).length === 0 && delete t.errorMessage)),
        t.anyOf.push({
          format: e,
          ...(n && r.errorMessages && { errorMessage: { format: n } }),
        }))
      : C(t, "format", e, n, r);
  },
  K = (t, e, n, r) => {
    t.pattern || t.allOf?.some((o) => o.pattern)
      ? (t.allOf || (t.allOf = []),
        t.pattern &&
          (t.allOf.push({
            pattern: t.pattern,
            ...(t.errorMessage &&
              r.errorMessages && {
                errorMessage: { pattern: t.errorMessage.pattern },
              }),
          }),
          delete t.pattern,
          t.errorMessage &&
            (delete t.errorMessage.pattern,
            Object.keys(t.errorMessage).length === 0 && delete t.errorMessage)),
        t.allOf.push({
          pattern: Xt(e, r),
          ...(n && r.errorMessages && { errorMessage: { pattern: n } }),
        }))
      : C(t, "pattern", Xt(e, r), n, r);
  },
  Xt = (t, e) => {
    const n = typeof t == "function" ? t() : t;
    if (!e.applyRegexFlags || !n.flags) return n.source;
    const r = {
        i: n.flags.includes("i"),
        m: n.flags.includes("m"),
        s: n.flags.includes("s"),
      },
      o = r.i ? n.source.toLowerCase() : n.source;
    let s = "",
      a = !1,
      i = !1,
      f = !1;
    for (let c = 0; c < o.length; c++) {
      if (a) {
        ((s += o[c]), (a = !1));
        continue;
      }
      if (r.i) {
        if (i) {
          if (o[c].match(/[a-z]/)) {
            f
              ? ((s += o[c]),
                (s += `${o[c - 2]}-${o[c]}`.toUpperCase()),
                (f = !1))
              : o[c + 1] === "-" && o[c + 2]?.match(/[a-z]/)
                ? ((s += o[c]), (f = !0))
                : (s += `${o[c]}${o[c].toUpperCase()}`);
            continue;
          }
        } else if (o[c].match(/[a-z]/)) {
          s += `[${o[c]}${o[c].toUpperCase()}]`;
          continue;
        }
      }
      if (r.m) {
        if (o[c] === "^") {
          s += `(^|(?<=[\r
]))`;
          continue;
        } else if (o[c] === "$") {
          s += `($|(?=[\r
]))`;
          continue;
        }
      }
      if (r.s && o[c] === ".") {
        s += i
          ? `${o[c]}\r
`
          : `[${o[c]}\r
]`;
        continue;
      }
      ((s += o[c]),
        o[c] === "\\"
          ? (a = !0)
          : i && o[c] === "]"
            ? (i = !1)
            : !i && o[c] === "[" && (i = !0));
    }
    try {
      const c = new RegExp(s);
    } catch {
      return (
        console.warn(
          `Could not convert regex pattern at ${e.currentPath.join("/")} to a flag-independent form! Falling back to the flag-ignorant source`,
        ),
        n.source
      );
    }
    return s;
  };
function Kn(t, e) {
  if (e.target === "openApi3" && t.keyType?._def.typeName === x.ZodEnum)
    return {
      type: "object",
      required: t.keyType._def.values,
      properties: t.keyType._def.values.reduce(
        (r, o) => ({
          ...r,
          [o]:
            O(t.valueType._def, {
              ...e,
              currentPath: [...e.currentPath, "properties", o],
            }) ?? {},
        }),
        {},
      ),
      additionalProperties: !1,
    };
  const n = {
    type: "object",
    additionalProperties:
      O(t.valueType._def, {
        ...e,
        currentPath: [...e.currentPath, "additionalProperties"],
      }) ?? {},
  };
  if (e.target === "openApi3") return n;
  if (
    t.keyType?._def.typeName === x.ZodString &&
    t.keyType._def.checks?.length
  ) {
    const r = Object.entries(Hn(t.keyType._def, e)).reduce(
      (o, [s, a]) => (s === "type" ? o : { ...o, [s]: a }),
      {},
    );
    return { ...n, propertyNames: r };
  } else if (t.keyType?._def.typeName === x.ZodEnum)
    return { ...n, propertyNames: { enum: t.keyType._def.values } };
  return n;
}
function qo(t, e) {
  if (e.mapStrategy === "record") return Kn(t, e);
  const n =
      O(t.keyType._def, {
        ...e,
        currentPath: [...e.currentPath, "items", "items", "0"],
      }) || {},
    r =
      O(t.valueType._def, {
        ...e,
        currentPath: [...e.currentPath, "items", "items", "1"],
      }) || {};
  return {
    type: "array",
    maxItems: 125,
    items: { type: "array", items: [n, r], minItems: 2, maxItems: 2 },
  };
}
function Ho(t) {
  const e = t.values,
    r = Object.keys(t.values)
      .filter((s) => typeof e[e[s]] != "number")
      .map((s) => e[s]),
    o = Array.from(new Set(r.map((s) => typeof s)));
  return {
    type:
      o.length === 1
        ? o[0] === "string"
          ? "string"
          : "number"
        : ["string", "number"],
    enum: r,
  };
}
function Ko() {
  return { not: {} };
}
function Wo(t) {
  return t.target === "openApi3"
    ? { enum: ["null"], nullable: !0 }
    : { type: "null" };
}
const He = {
  ZodString: "string",
  ZodNumber: "number",
  ZodBigInt: "integer",
  ZodBoolean: "boolean",
  ZodNull: "null",
};
function Vo(t, e) {
  if (e.target === "openApi3") return Qt(t, e);
  const n =
    t.options instanceof Map ? Array.from(t.options.values()) : t.options;
  if (
    n.every(
      (r) => r._def.typeName in He && (!r._def.checks || !r._def.checks.length),
    )
  ) {
    const r = n.reduce((o, s) => {
      const a = He[s._def.typeName];
      return a && !o.includes(a) ? [...o, a] : o;
    }, []);
    return { type: r.length > 1 ? r : r[0] };
  } else if (
    n.every((r) => r._def.typeName === "ZodLiteral" && !r.description)
  ) {
    const r = n.reduce((o, s) => {
      const a = typeof s._def.value;
      switch (a) {
        case "string":
        case "number":
        case "boolean":
          return [...o, a];
        case "bigint":
          return [...o, "integer"];
        case "object":
          if (s._def.value === null) return [...o, "null"];
        default:
          return o;
      }
    }, []);
    if (r.length === n.length) {
      const o = r.filter((s, a, i) => i.indexOf(s) === a);
      return {
        type: o.length > 1 ? o : o[0],
        enum: n.reduce(
          (s, a) => (s.includes(a._def.value) ? s : [...s, a._def.value]),
          [],
        ),
      };
    }
  } else if (n.every((r) => r._def.typeName === "ZodEnum"))
    return {
      type: "string",
      enum: n.reduce(
        (r, o) => [...r, ...o._def.values.filter((s) => !r.includes(s))],
        [],
      ),
    };
  return Qt(t, e);
}
const Qt = (t, e) => {
  const n = (
    t.options instanceof Map ? Array.from(t.options.values()) : t.options
  )
    .map((r, o) =>
      O(r._def, { ...e, currentPath: [...e.currentPath, "anyOf", `${o}`] }),
    )
    .filter(
      (r) =>
        !!r &&
        (!e.strictUnions ||
          (typeof r == "object" && Object.keys(r).length > 0)),
    );
  return n.length ? { anyOf: n } : void 0;
};
function Yo(t, e) {
  if (
    ["ZodString", "ZodNumber", "ZodBigInt", "ZodBoolean", "ZodNull"].includes(
      t.innerType._def.typeName,
    ) &&
    (!t.innerType._def.checks || !t.innerType._def.checks.length)
  )
    return e.target === "openApi3" || e.nullableStrategy === "property"
      ? { type: He[t.innerType._def.typeName], nullable: !0 }
      : { type: [He[t.innerType._def.typeName], "null"] };
  if (e.target === "openApi3") {
    const r = O(t.innerType._def, { ...e, currentPath: [...e.currentPath] });
    return r && "$ref" in r
      ? { allOf: [r], nullable: !0 }
      : r && { ...r, nullable: !0 };
  }
  const n = O(t.innerType._def, {
    ...e,
    currentPath: [...e.currentPath, "anyOf", "0"],
  });
  return n && { anyOf: [n, { type: "null" }] };
}
function Xo(t, e) {
  const n = { type: "number" };
  if (!t.checks) return n;
  for (const r of t.checks)
    switch (r.kind) {
      case "int":
        ((n.type = "integer"), Zn(n, "type", r.message, e));
        break;
      case "min":
        e.target === "jsonSchema7"
          ? r.inclusive
            ? C(n, "minimum", r.value, r.message, e)
            : C(n, "exclusiveMinimum", r.value, r.message, e)
          : (r.inclusive || (n.exclusiveMinimum = !0),
            C(n, "minimum", r.value, r.message, e));
        break;
      case "max":
        e.target === "jsonSchema7"
          ? r.inclusive
            ? C(n, "maximum", r.value, r.message, e)
            : C(n, "exclusiveMaximum", r.value, r.message, e)
          : (r.inclusive || (n.exclusiveMaximum = !0),
            C(n, "maximum", r.value, r.message, e));
        break;
      case "multipleOf":
        C(n, "multipleOf", r.value, r.message, e);
        break;
    }
  return n;
}
function Qo(t, e) {
  return e.removeAdditionalStrategy === "strict"
    ? t.catchall._def.typeName === "ZodNever"
      ? t.unknownKeys !== "strict"
      : (O(t.catchall._def, {
          ...e,
          currentPath: [...e.currentPath, "additionalProperties"],
        }) ?? !0)
    : t.catchall._def.typeName === "ZodNever"
      ? t.unknownKeys === "passthrough"
      : (O(t.catchall._def, {
          ...e,
          currentPath: [...e.currentPath, "additionalProperties"],
        }) ?? !0);
}
function es(t, e) {
  const n = {
    type: "object",
    ...Object.entries(t.shape()).reduce(
      (r, [o, s]) => {
        if (s === void 0 || s._def === void 0) return r;
        const a = [...e.currentPath, "properties", o],
          i = O(s._def, { ...e, currentPath: a, propertyPath: a });
        if (i === void 0) return r;
        if (
          e.openaiStrictMode &&
          s.isOptional() &&
          !s.isNullable() &&
          typeof s._def?.defaultValue > "u"
        )
          throw new Error(
            `Zod field at \`${a.join("/")}\` uses \`.optional()\` without \`.nullable()\` which is not supported by the API. See: https://platform.openai.com/docs/guides/structured-outputs?api-mode=responses#all-fields-must-be-required`,
          );
        return {
          properties: { ...r.properties, [o]: i },
          required:
            s.isOptional() && !e.openaiStrictMode
              ? r.required
              : [...r.required, o],
        };
      },
      { properties: {}, required: [] },
    ),
    additionalProperties: Qo(t, e),
  };
  return (n.required.length || delete n.required, n);
}
const ts = (t, e) => {
    if (
      e.propertyPath &&
      e.currentPath.slice(0, e.propertyPath.length).toString() ===
        e.propertyPath.toString()
    )
      return O(t.innerType._def, { ...e, currentPath: e.currentPath });
    const n = O(t.innerType._def, {
      ...e,
      currentPath: [...e.currentPath, "anyOf", "1"],
    });
    return n ? { anyOf: [{ not: {} }, n] } : {};
  },
  ns = (t, e) => {
    if (e.pipeStrategy === "input") return O(t.in._def, e);
    if (e.pipeStrategy === "output") return O(t.out._def, e);
    const n = O(t.in._def, {
        ...e,
        currentPath: [...e.currentPath, "allOf", "0"],
      }),
      r = O(t.out._def, {
        ...e,
        currentPath: [...e.currentPath, "allOf", n ? "1" : "0"],
      });
    return { allOf: [n, r].filter((o) => o !== void 0) };
  };
function rs(t, e) {
  return O(t.type._def, e);
}
function os(t, e) {
  const r = {
    type: "array",
    uniqueItems: !0,
    items: O(t.valueType._def, {
      ...e,
      currentPath: [...e.currentPath, "items"],
    }),
  };
  return (
    t.minSize && C(r, "minItems", t.minSize.value, t.minSize.message, e),
    t.maxSize && C(r, "maxItems", t.maxSize.value, t.maxSize.message, e),
    r
  );
}
function ss(t, e) {
  return t.rest
    ? {
        type: "array",
        minItems: t.items.length,
        items: t.items
          .map((n, r) =>
            O(n._def, {
              ...e,
              currentPath: [...e.currentPath, "items", `${r}`],
            }),
          )
          .reduce((n, r) => (r === void 0 ? n : [...n, r]), []),
        additionalItems: O(t.rest._def, {
          ...e,
          currentPath: [...e.currentPath, "additionalItems"],
        }),
      }
    : {
        type: "array",
        minItems: t.items.length,
        maxItems: t.items.length,
        items: t.items
          .map((n, r) =>
            O(n._def, {
              ...e,
              currentPath: [...e.currentPath, "items", `${r}`],
            }),
          )
          .reduce((n, r) => (r === void 0 ? n : [...n, r]), []),
      };
}
function as() {
  return { not: {} };
}
function is() {
  return {};
}
const us = (t, e) => O(t.innerType._def, e);
function O(t, e, n = !1) {
  const r = e.seen.get(t);
  if (e.override) {
    const a = e.override?.(t, e, r, n);
    if (a !== ko) return a;
  }
  if (r && !n) {
    const a = cs(r, e);
    if (a !== void 0) return ("$ref" in a && e.seenRefs.add(a.$ref), a);
  }
  const o = { def: t, path: e.currentPath, jsonSchema: void 0 };
  e.seen.set(t, o);
  const s = ps(t, t.typeName, e, n);
  return (s && ds(t, e, s), (o.jsonSchema = s), s);
}
const cs = (t, e) => {
    switch (e.$refStrategy) {
      case "root":
        return { $ref: t.path.join("/") };
      case "extract-to-root":
        const n = t.path.slice(e.basePath.length + 1).join("_");
        return (
          n !== e.name &&
            e.nameStrategy === "duplicate-ref" &&
            (e.definitions[n] = t.def),
          { $ref: [...e.basePath, e.definitionPath, n].join("/") }
        );
      case "relative":
        return { $ref: ls(e.currentPath, t.path) };
      case "none":
      case "seen":
        return t.path.length < e.currentPath.length &&
          t.path.every((r, o) => e.currentPath[o] === r)
          ? (console.warn(
              `Recursive reference detected at ${e.currentPath.join("/")}! Defaulting to any`,
            ),
            {})
          : e.$refStrategy === "seen"
            ? {}
            : void 0;
    }
  },
  ls = (t, e) => {
    let n = 0;
    for (; n < t.length && n < e.length && t[n] === e[n]; n++);
    return [(t.length - n).toString(), ...e.slice(n)].join("/");
  },
  ps = (t, e, n, r) => {
    switch (e) {
      case x.ZodString:
        return Hn(t, n);
      case x.ZodNumber:
        return Xo(t, n);
      case x.ZodObject:
        return es(t, n);
      case x.ZodBigInt:
        return Po(t, n);
      case x.ZodBoolean:
        return Mo();
      case x.ZodDate:
        return qn(t, n);
      case x.ZodUndefined:
        return as();
      case x.ZodNull:
        return Wo(n);
      case x.ZodArray:
        return No(t, n);
      case x.ZodUnion:
      case x.ZodDiscriminatedUnion:
        return Vo(t, n);
      case x.ZodIntersection:
        return Bo(t, n);
      case x.ZodTuple:
        return ss(t, n);
      case x.ZodRecord:
        return Kn(t, n);
      case x.ZodLiteral:
        return zo(t, n);
      case x.ZodEnum:
        return Jo(t);
      case x.ZodNativeEnum:
        return Ho(t);
      case x.ZodNullable:
        return Yo(t, n);
      case x.ZodOptional:
        return ts(t, n);
      case x.ZodMap:
        return qo(t, n);
      case x.ZodSet:
        return os(t, n);
      case x.ZodLazy:
        return O(t.getter()._def, n);
      case x.ZodPromise:
        return rs(t, n);
      case x.ZodNaN:
      case x.ZodNever:
        return Ko();
      case x.ZodEffects:
        return Uo(t, n, r);
      case x.ZodAny:
        return Ro();
      case x.ZodUnknown:
        return is();
      case x.ZodDefault:
        return jo(t, n);
      case x.ZodBranded:
        return Fo(t, n);
      case x.ZodReadonly:
        return us(t, n);
      case x.ZodCatch:
        return Lo(t, n);
      case x.ZodPipeline:
        return ns(t, n);
      case x.ZodFunction:
      case x.ZodVoid:
      case x.ZodSymbol:
        return;
      default:
        return ((o) => {})();
    }
  },
  ds = (t, e, n) => (
    t.description &&
      ((n.description = t.description),
      e.markdownDescription && (n.markdownDescription = t.description)),
    n
  ),
  fs = (t, e) => {
    const n = Co(e),
      r =
        typeof e == "string"
          ? e
          : e?.nameStrategy === "title"
            ? void 0
            : e?.name,
      o =
        O(
          t._def,
          r === void 0
            ? n
            : { ...n, currentPath: [...n.basePath, n.definitionPath, r] },
          !1,
        ) ?? {},
      s =
        typeof e == "object" && e.name !== void 0 && e.nameStrategy === "title"
          ? e.name
          : void 0;
    s !== void 0 && (o.title = s);
    const a = (() => {
        if (Oo(n.definitions)) return;
        const f = {},
          c = new Set();
        for (let l = 0; l < 500; l++) {
          const d = Object.entries(n.definitions).filter(([m]) => !c.has(m));
          if (d.length === 0) break;
          for (const [m, y] of d)
            ((f[m] =
              O(
                vt(y),
                { ...n, currentPath: [...n.basePath, n.definitionPath, m] },
                !0,
              ) ?? {}),
              c.add(m));
        }
        return f;
      })(),
      i =
        r === void 0
          ? a
            ? { ...o, [n.definitionPath]: a }
            : o
          : n.nameStrategy === "duplicate-ref"
            ? {
                ...o,
                ...(a || n.seenRefs.size
                  ? {
                      [n.definitionPath]: {
                        ...a,
                        ...(n.seenRefs.size ? { [r]: o } : void 0),
                      },
                    }
                  : void 0),
              }
            : {
                $ref: [
                  ...(n.$refStrategy === "relative" ? [] : n.basePath),
                  n.definitionPath,
                  r,
                ].join("/"),
                [n.definitionPath]: { ...a, [r]: o },
              };
    return (
      n.target === "jsonSchema7"
        ? (i.$schema = "http://json-schema.org/draft-07/schema#")
        : n.target === "jsonSchema2019-09" &&
          (i.$schema = "https://json-schema.org/draft/2019-09/schema#"),
      i
    );
  };
function ms(t) {
  if (t.type !== "object")
    throw new Error(
      `Root schema must have type: 'object' but got type: ${t.type ? `'${t.type}'` : "undefined"}`,
    );
  const e = structuredClone(t);
  return ee(e, [], e);
}
function wt(t) {
  if (typeof t == "boolean") return !1;
  if (t.type === "null") return !0;
  for (const e of t.oneOf ?? []) if (wt(e)) return !0;
  for (const e of t.anyOf ?? []) if (wt(e)) return !0;
  return !1;
}
function ee(t, e, n) {
  if (typeof t == "boolean")
    throw new TypeError(
      `Expected object schema but got boolean; path=${e.join("/")}`,
    );
  if (!ce(t))
    throw new TypeError(
      `Expected ${JSON.stringify(t)} to be an object; path=${e.join("/")}`,
    );
  const r = t.$defs;
  if (ce(r))
    for (const [m, y] of Object.entries(r)) ee(y, [...e, "$defs", m], n);
  const o = t.definitions;
  if (ce(o))
    for (const [m, y] of Object.entries(o)) ee(y, [...e, "definitions", m], n);
  t.type === "object" &&
    !("additionalProperties" in t) &&
    (t.additionalProperties = !1);
  const a = t.required ?? [],
    i = t.properties;
  if (ce(i)) {
    for (const [m, y] of Object.entries(i))
      if (!wt(y) && !a.includes(m))
        throw new Error(
          `Zod field at \`${[...e, "properties", m].join("/")}\` uses \`.optional()\` without \`.nullable()\` which is not supported by the API. See: https://platform.openai.com/docs/guides/structured-outputs?api-mode=responses#all-fields-must-be-required`,
        );
    ((t.required = Object.keys(i)),
      (t.properties = Object.fromEntries(
        Object.entries(i).map(([m, y]) => [
          m,
          ee(y, [...e, "properties", m], n),
        ]),
      )));
  }
  const f = t.items;
  ce(f) && (t.items = ee(f, [...e, "items"], n));
  const c = t.anyOf;
  Array.isArray(c) &&
    (t.anyOf = c.map((m, y) => ee(m, [...e, "anyOf", String(y)], n)));
  const l = t.allOf;
  if (Array.isArray(l))
    if (l.length === 1) {
      const m = ee(l[0], [...e, "allOf", "0"], n);
      (Object.assign(t, m), delete t.allOf);
    } else t.allOf = l.map((m, y) => ee(m, [...e, "allOf", String(y)], n));
  t.default === null && delete t.default;
  const d = t.$ref;
  if (d && gs(t, 1)) {
    if (typeof d != "string")
      throw new TypeError(
        `Received non-string $ref - ${d}; path=${e.join("/")}`,
      );
    const m = hs(n, d);
    if (typeof m == "boolean")
      throw new Error(
        `Expected \`$ref: ${d}\` to resolve to an object schema but got boolean`,
      );
    if (!ce(m))
      throw new Error(
        `Expected \`$ref: ${d}\` to resolve to an object but got ${JSON.stringify(m)}`,
      );
    return (Object.assign(t, { ...m, ...t }), delete t.$ref, ee(t, e, n));
  }
  return t;
}
function hs(t, e) {
  if (!e.startsWith("#/"))
    throw new Error(
      `Unexpected $ref format ${JSON.stringify(e)}; Does not start with #/`,
    );
  const n = e.slice(2).split("/");
  let r = t;
  for (const o of n) {
    if (!ce(r))
      throw new Error(
        `encountered non-object entry while resolving ${e} - ${JSON.stringify(r)}`,
      );
    const s = r[o];
    if (s === void 0)
      throw new Error(`Key ${o} not found while resolving ${e}`);
    r = s;
  }
  return r;
}
function ce(t) {
  return typeof t == "object" && t !== null && !Array.isArray(t);
}
function gs(t, e) {
  let n = 0;
  for (const r in t) if ((n++, n > e)) return !0;
  return !1;
}
function Wn(t, e) {
  return fs(t, {
    openaiStrictMode: !0,
    name: e.name,
    nameStrategy: "duplicate-ref",
    $refStrategy: "extract-to-root",
    nullableStrategy: "property",
  });
}
function Vn(t) {
  return ms(Do(t, { target: "draft-7" }));
}
function Yn(t) {
  return "_zod" in t;
}
function ys(t, e, n) {
  return wo(
    {
      type: "json_schema",
      ...n,
      name: e,
      strict: !0,
      schema: Yn(t) ? Vn(t) : Wn(t, { name: e }),
    },
    (r) => t.parse(JSON.parse(r)),
  );
}
function _s(t) {
  return bo(
    {
      type: "function",
      name: t.name,
      parameters: Yn(t.parameters)
        ? Vn(t.parameters)
        : Wn(t.parameters, { name: t.name }),
      strict: !0,
      ...(t.description ? { description: t.description } : void 0),
    },
    { callback: t.function, parser: (e) => t.parameters.parse(JSON.parse(e)) },
  );
}
class se extends Error {
  state;
  constructor(e, n) {
    (super(e), (this.state = n));
  }
}
class vs extends se {}
class en extends se {}
class B extends se {}
class k extends se {}
class tn extends se {
  error;
  constructor(e, n, r) {
    (super(e, r), (this.error = n));
  }
}
class ws extends se {
  error;
  constructor(e, n, r) {
    (super(e, r), (this.error = n));
  }
}
class nn extends se {
  result;
  constructor(e, n, r) {
    (super(e, r), (this.result = n));
  }
}
class Ke extends se {
  result;
  constructor(e, n, r) {
    (super(e, r), (this.result = n));
  }
}
function ke(t) {
  if (typeof t != "object" || t === null) return;
  const e = t;
  return e._zod?.def || e._def || e.def;
}
function et(t) {
  const e = ke(t);
  if (!e) return;
  const n =
    (typeof e.typeName == "string" && e.typeName) ||
    (typeof e.type == "string" && e.type);
  if (typeof n != "string") return;
  const r = n.toLowerCase();
  return r.startsWith("zod") ? r.slice(3) : r;
}
function he(t) {
  return ke(t) ? et(t) === "object" : !1;
}
function bs(t) {
  return (
    typeof t == "object" &&
    t !== null &&
    "input" in t &&
    typeof t.input == "string"
  );
}
const Ss = "http://json-schema.org/draft-07/schema#",
  Ts = new Set(["optional"]),
  Is = new Set([
    "brand",
    "branded",
    "catch",
    "default",
    "effects",
    "pipeline",
    "pipe",
    "prefault",
    "readonly",
    "refinement",
    "transform",
  ]),
  rn = {
    string: { type: "string" },
    number: { type: "number" },
    bigint: { type: "integer" },
    boolean: { type: "boolean" },
    date: { type: "string", format: "date-time" },
  };
function Xn(t) {
  return (
    typeof t == "object" &&
    t !== null &&
    t.type === "object" &&
    "properties" in t &&
    "additionalProperties" in t
  );
}
function xs(t) {
  const e = Qn(t);
  if (e)
    return (
      Array.isArray(e.required) || (e.required = []),
      typeof e.additionalProperties > "u" && (e.additionalProperties = !1),
      typeof e.$schema != "string" && (e.$schema = Ss),
      e
    );
}
function Qn(t) {
  const e = Ls(t);
  if (!e) return;
  const n = {},
    r = [];
  for (const [o, s] of Object.entries(e)) {
    const { schema: a, optional: i } = As(s);
    if (!a) return;
    ((n[o] = a), i || r.push(o));
  }
  return {
    type: "object",
    properties: n,
    required: r,
    additionalProperties: !1,
  };
}
function As(t) {
  let e = bt(t),
    n = !1;
  for (; Ts.has(et(e) ?? "");) {
    n = !0;
    const r = ke(e),
      o = bt(r?.innerType);
    if (!o || o === e) break;
    e = o;
  }
  return { schema: X(e), optional: n };
}
function X(t) {
  if (t === void 0) return;
  const e = bt(t),
    n = et(e),
    r = ke(e);
  if (n) {
    if (n in rn) return rn[n];
    switch (n) {
      case "object":
        return Qn(e);
      case "array":
        return Ds(r);
      case "tuple":
        return ks(r);
      case "union":
        return Es(r);
      case "intersection":
        return Os(r);
      case "literal":
        return Ms(r);
      case "enum":
      case "nativeenum":
        return Fs(r);
      case "record":
        return Cs(r);
      case "map":
        return Rs(r);
      case "set":
        return Ns(r);
      case "nullable":
        return Ps(r);
      default:
        return;
    }
  }
}
function Ds(t) {
  const e = X(er(t, "element", "items", "type"));
  return e ? { type: "array", items: e } : void 0;
}
function ks(t) {
  const e = tr(t?.items)
    .map((r) => X(r))
    .filter(Boolean);
  if (!e.length) return;
  const n = { type: "array", items: e, minItems: e.length };
  return (t?.rest || (n.maxItems = e.length), n);
}
function Es(t) {
  const e = tr(t?.options ?? t?.schemas)
    .map((n) => X(n))
    .filter(Boolean);
  return e.length ? { anyOf: e } : void 0;
}
function Os(t) {
  const e = X(t?.left),
    n = X(t?.right);
  return e && n ? { allOf: [e, n] } : void 0;
}
function Cs(t) {
  const e = X(t?.valueType ?? t?.values);
  return e ? { type: "object", additionalProperties: e } : void 0;
}
function Rs(t) {
  const e = X(t?.valueType ?? t?.values);
  return e ? { type: "array", items: e } : void 0;
}
function Ns(t) {
  const e = X(t?.valueType);
  return e ? { type: "array", items: e, uniqueItems: !0 } : void 0;
}
function Ps(t) {
  const e = X(t?.innerType ?? t?.type);
  return e ? { anyOf: [e, { type: "null" }] } : void 0;
}
function bt(t) {
  let e = t;
  for (; Is.has(et(e) ?? "");) {
    const n = ke(e),
      r =
        n?.innerType ??
        n?.schema ??
        n?.base ??
        n?.type ??
        n?.wrapped ??
        n?.underlying;
    if (!r || r === e) return e;
    e = r;
  }
  return e;
}
function er(t, ...e) {
  if (t) {
    for (const n of e) if (n in t && t[n] !== void 0) return t[n];
  }
}
function tr(t) {
  return Array.isArray(t) ? t : t === void 0 ? [] : [t];
}
function Ms(t) {
  if (!t) return;
  const e = er(t, "value", "literal");
  if (e !== void 0) return { const: e, type: e === null ? "null" : typeof e };
}
function Fs(t) {
  if (t) {
    if (Array.isArray(t.values)) return { enum: t.values };
    if (Array.isArray(t.options)) return { enum: t.options };
    if (t.values && typeof t.values == "object")
      return { enum: Object.values(t.values) };
    if (t.enum && typeof t.enum == "object")
      return { enum: Object.values(t.enum) };
  }
}
function Ls(t) {
  if (typeof t != "object" || t === null) return;
  const e = t;
  if (e.shape && typeof e.shape == "object") return e.shape;
  if (typeof e.shape == "function")
    try {
      return e.shape();
    } catch {
      return;
    }
  const r = ke(e)?.shape;
  if (r && typeof r == "object") return r;
  if (typeof r == "function")
    try {
      return r();
    } catch {
      return;
    }
}
const $s = _s,
  js = ys;
function nr(t) {
  return xs(t);
}
function We(t) {
  if (
    ((t = t.replace(/\s/g, "_")),
    (t = t.replace(/[^a-zA-Z0-9]/g, "_")),
    t.length === 0)
  )
    throw new Error("Tool name cannot be empty");
  return t;
}
function Ct(t, e) {
  const n = (r) => JSON.parse(r);
  if (he(t)) {
    const r = (s) => {
      const a = nr(t);
      if (a) return { schema: a, parser: (f) => t.parse(JSON.parse(f)) };
      const i =
        s instanceof Error ? ` Upstream helper error: ${s.message}` : "";
      throw new k(
        `Unable to convert the provided Zod schema to JSON Schema. Ensure that the \`zod\` package is available at runtime or provide a JSON schema object instead.${i}`,
      );
    };
    let o;
    try {
      o = $s({ name: e, parameters: t, function: () => {}, description: "" });
    } catch (s) {
      return r(s);
    }
    return Xn(o.parameters)
      ? { schema: o.parameters, parser: o.$parseRaw }
      : r();
  } else if (typeof t == "object" && t !== null)
    return { schema: t, parser: n };
  throw new k("Input type is not a ZodObject or a valid JSON schema");
}
function on(t) {
  if (t === "text") return "text";
  if (he(t)) {
    const e = (r, o) => {
      const s = nr(t);
      if (s)
        return {
          type: r?.type ?? "json_schema",
          name: r?.name ?? "output",
          strict: r?.strict ?? !1,
          schema: s,
        };
      const a =
        o instanceof Error ? ` Upstream helper error: ${o.message}` : "";
      throw new k(
        `Unable to convert the provided Zod schema to JSON Schema. Ensure that the \`zod\` package is available at runtime or provide a JSON schema object instead.${a}`,
      );
    };
    let n;
    try {
      n = js(t, "output");
    } catch (r) {
      return e(void 0, r);
    }
    return Xn(n.schema)
      ? { type: n.type, name: n.name, strict: n.strict || !1, schema: n.schema }
      : e(n);
  }
  return t;
}
var Ue = { exports: {} },
  pt,
  sn;
function Us() {
  if (sn) return pt;
  sn = 1;
  var t = 1e3,
    e = t * 60,
    n = e * 60,
    r = n * 24,
    o = r * 7,
    s = r * 365.25;
  pt = function (l, d) {
    d = d || {};
    var m = typeof l;
    if (m === "string" && l.length > 0) return a(l);
    if (m === "number" && isFinite(l)) return d.long ? f(l) : i(l);
    throw new Error(
      "val is not a non-empty string or a valid number. val=" +
        JSON.stringify(l),
    );
  };
  function a(l) {
    if (((l = String(l)), !(l.length > 100))) {
      var d =
        /^(-?(?:\d+)?\.?\d+) *(milliseconds?|msecs?|ms|seconds?|secs?|s|minutes?|mins?|m|hours?|hrs?|h|days?|d|weeks?|w|years?|yrs?|y)?$/i.exec(
          l,
        );
      if (d) {
        var m = parseFloat(d[1]),
          y = (d[2] || "ms").toLowerCase();
        switch (y) {
          case "years":
          case "year":
          case "yrs":
          case "yr":
          case "y":
            return m * s;
          case "weeks":
          case "week":
          case "w":
            return m * o;
          case "days":
          case "day":
          case "d":
            return m * r;
          case "hours":
          case "hour":
          case "hrs":
          case "hr":
          case "h":
            return m * n;
          case "minutes":
          case "minute":
          case "mins":
          case "min":
          case "m":
            return m * e;
          case "seconds":
          case "second":
          case "secs":
          case "sec":
          case "s":
            return m * t;
          case "milliseconds":
          case "millisecond":
          case "msecs":
          case "msec":
          case "ms":
            return m;
          default:
            return;
        }
      }
    }
  }
  function i(l) {
    var d = Math.abs(l);
    return d >= r
      ? Math.round(l / r) + "d"
      : d >= n
        ? Math.round(l / n) + "h"
        : d >= e
          ? Math.round(l / e) + "m"
          : d >= t
            ? Math.round(l / t) + "s"
            : l + "ms";
  }
  function f(l) {
    var d = Math.abs(l);
    return d >= r
      ? c(l, d, r, "day")
      : d >= n
        ? c(l, d, n, "hour")
        : d >= e
          ? c(l, d, e, "minute")
          : d >= t
            ? c(l, d, t, "second")
            : l + " ms";
  }
  function c(l, d, m, y) {
    var p = d >= m * 1.5;
    return Math.round(l / m) + " " + y + (p ? "s" : "");
  }
  return pt;
}
var dt, an;
function Js() {
  if (an) return dt;
  an = 1;
  function t(e) {
    ((r.debug = r),
      (r.default = r),
      (r.coerce = c),
      (r.disable = i),
      (r.enable = s),
      (r.enabled = f),
      (r.humanize = Us()),
      (r.destroy = l),
      Object.keys(e).forEach((d) => {
        r[d] = e[d];
      }),
      (r.names = []),
      (r.skips = []),
      (r.formatters = {}));
    function n(d) {
      let m = 0;
      for (let y = 0; y < d.length; y++)
        ((m = (m << 5) - m + d.charCodeAt(y)), (m |= 0));
      return r.colors[Math.abs(m) % r.colors.length];
    }
    r.selectColor = n;
    function r(d) {
      let m,
        y = null,
        p,
        v;
      function _(...T) {
        if (!_.enabled) return;
        const b = _,
          I = Number(new Date()),
          E = I - (m || I);
        ((b.diff = E),
          (b.prev = m),
          (b.curr = I),
          (m = I),
          (T[0] = r.coerce(T[0])),
          typeof T[0] != "string" && T.unshift("%O"));
        let U = 0;
        ((T[0] = T[0].replace(/%([a-zA-Z%])/g, (ct, yo) => {
          if (ct === "%%") return "%";
          U++;
          const Wt = r.formatters[yo];
          if (typeof Wt == "function") {
            const _o = T[U];
            ((ct = Wt.call(b, _o)), T.splice(U, 1), U--);
          }
          return ct;
        })),
          r.formatArgs.call(b, T),
          (b.log || r.log).apply(b, T));
      }
      return (
        (_.namespace = d),
        (_.useColors = r.useColors()),
        (_.color = r.selectColor(d)),
        (_.extend = o),
        (_.destroy = r.destroy),
        Object.defineProperty(_, "enabled", {
          enumerable: !0,
          configurable: !1,
          get: () =>
            y !== null
              ? y
              : (p !== r.namespaces && ((p = r.namespaces), (v = r.enabled(d))),
                v),
          set: (T) => {
            y = T;
          },
        }),
        typeof r.init == "function" && r.init(_),
        _
      );
    }
    function o(d, m) {
      const y = r(this.namespace + (typeof m > "u" ? ":" : m) + d);
      return ((y.log = this.log), y);
    }
    function s(d) {
      (r.save(d), (r.namespaces = d), (r.names = []), (r.skips = []));
      const m = (typeof d == "string" ? d : "")
        .trim()
        .replace(/\s+/g, ",")
        .split(",")
        .filter(Boolean);
      for (const y of m)
        y[0] === "-" ? r.skips.push(y.slice(1)) : r.names.push(y);
    }
    function a(d, m) {
      let y = 0,
        p = 0,
        v = -1,
        _ = 0;
      for (; y < d.length;)
        if (p < m.length && (m[p] === d[y] || m[p] === "*"))
          m[p] === "*" ? ((v = p), (_ = y), p++) : (y++, p++);
        else if (v !== -1) ((p = v + 1), _++, (y = _));
        else return !1;
      for (; p < m.length && m[p] === "*";) p++;
      return p === m.length;
    }
    function i() {
      const d = [...r.names, ...r.skips.map((m) => "-" + m)].join(",");
      return (r.enable(""), d);
    }
    function f(d) {
      for (const m of r.skips) if (a(d, m)) return !1;
      for (const m of r.names) if (a(d, m)) return !0;
      return !1;
    }
    function c(d) {
      return d instanceof Error ? d.stack || d.message : d;
    }
    function l() {
      console.warn(
        "Instance method `debug.destroy()` is deprecated and no longer does anything. It will be removed in the next major version of `debug`.",
      );
    }
    return (r.enable(r.load()), r);
  }
  return ((dt = t), dt);
}
var un;
function Gs() {
  return (
    un ||
      ((un = 1),
      (function (t, e) {
        var n = {};
        ((e.formatArgs = o),
          (e.save = s),
          (e.load = a),
          (e.useColors = r),
          (e.storage = i()),
          (e.destroy = (() => {
            let c = !1;
            return () => {
              c ||
                ((c = !0),
                console.warn(
                  "Instance method `debug.destroy()` is deprecated and no longer does anything. It will be removed in the next major version of `debug`.",
                ));
            };
          })()),
          (e.colors = [
            "#0000CC",
            "#0000FF",
            "#0033CC",
            "#0033FF",
            "#0066CC",
            "#0066FF",
            "#0099CC",
            "#0099FF",
            "#00CC00",
            "#00CC33",
            "#00CC66",
            "#00CC99",
            "#00CCCC",
            "#00CCFF",
            "#3300CC",
            "#3300FF",
            "#3333CC",
            "#3333FF",
            "#3366CC",
            "#3366FF",
            "#3399CC",
            "#3399FF",
            "#33CC00",
            "#33CC33",
            "#33CC66",
            "#33CC99",
            "#33CCCC",
            "#33CCFF",
            "#6600CC",
            "#6600FF",
            "#6633CC",
            "#6633FF",
            "#66CC00",
            "#66CC33",
            "#9900CC",
            "#9900FF",
            "#9933CC",
            "#9933FF",
            "#99CC00",
            "#99CC33",
            "#CC0000",
            "#CC0033",
            "#CC0066",
            "#CC0099",
            "#CC00CC",
            "#CC00FF",
            "#CC3300",
            "#CC3333",
            "#CC3366",
            "#CC3399",
            "#CC33CC",
            "#CC33FF",
            "#CC6600",
            "#CC6633",
            "#CC9900",
            "#CC9933",
            "#CCCC00",
            "#CCCC33",
            "#FF0000",
            "#FF0033",
            "#FF0066",
            "#FF0099",
            "#FF00CC",
            "#FF00FF",
            "#FF3300",
            "#FF3333",
            "#FF3366",
            "#FF3399",
            "#FF33CC",
            "#FF33FF",
            "#FF6600",
            "#FF6633",
            "#FF9900",
            "#FF9933",
            "#FFCC00",
            "#FFCC33",
          ]));
        function r() {
          if (
            typeof window < "u" &&
            window.process &&
            (window.process.type === "renderer" || window.process.__nwjs)
          )
            return !0;
          if (
            typeof navigator < "u" &&
            navigator.userAgent &&
            navigator.userAgent.toLowerCase().match(/(edge|trident)\/(\d+)/)
          )
            return !1;
          let c;
          return (
            (typeof document < "u" &&
              document.documentElement &&
              document.documentElement.style &&
              document.documentElement.style.WebkitAppearance) ||
            (typeof window < "u" &&
              window.console &&
              (window.console.firebug ||
                (window.console.exception && window.console.table))) ||
            (typeof navigator < "u" &&
              navigator.userAgent &&
              (c = navigator.userAgent.toLowerCase().match(/firefox\/(\d+)/)) &&
              parseInt(c[1], 10) >= 31) ||
            (typeof navigator < "u" &&
              navigator.userAgent &&
              navigator.userAgent.toLowerCase().match(/applewebkit\/(\d+)/))
          );
        }
        function o(c) {
          if (
            ((c[0] =
              (this.useColors ? "%c" : "") +
              this.namespace +
              (this.useColors ? " %c" : " ") +
              c[0] +
              (this.useColors ? "%c " : " ") +
              "+" +
              t.exports.humanize(this.diff)),
            !this.useColors)
          )
            return;
          const l = "color: " + this.color;
          c.splice(1, 0, l, "color: inherit");
          let d = 0,
            m = 0;
          (c[0].replace(/%[a-zA-Z%]/g, (y) => {
            y !== "%%" && (d++, y === "%c" && (m = d));
          }),
            c.splice(m, 0, l));
        }
        e.log = console.debug || console.log || (() => {});
        function s(c) {
          try {
            c ? e.storage.setItem("debug", c) : e.storage.removeItem("debug");
          } catch {}
        }
        function a() {
          let c;
          try {
            c = e.storage.getItem("debug") || e.storage.getItem("DEBUG");
          } catch {}
          return (!c && typeof J < "u" && "env" in J && (c = n.DEBUG), c);
        }
        function i() {
          try {
            return localStorage;
          } catch {}
        }
        t.exports = Js()(e);
        const { formatters: f } = t.exports;
        f.j = function (c) {
          try {
            return JSON.stringify(c);
          } catch (l) {
            return "[UnexpectedJSONParseError]: " + l.message;
          }
        };
      })(Ue, Ue.exports)),
    Ue.exports
  );
}
var Bs = Gs();
const tt = vo(Bs);
function rr() {
  return Rt();
}
function cn(t) {
  const e = rr();
  return typeof e < "u" && (e[t] === "true" || e[t] === "1");
}
const or = {
    get disabled() {
      return !0;
    },
  },
  sr = {
    get dontLogModelData() {
      return cn("OPENAI_AGENTS_DONT_LOG_MODEL_DATA");
    },
    get dontLogToolData() {
      return cn("OPENAI_AGENTS_DONT_LOG_TOOL_DATA");
    },
  },
  zs = sr.dontLogModelData,
  Zs = sr.dontLogToolData;
function Ee(t = "openai-agents") {
  return {
    namespace: t,
    debug: tt(t),
    error: console.error,
    warn: console.warn,
    dontLogModelData: zs,
    dontLogToolData: Zs,
  };
}
const S = Ee("openai-agents:core"),
  ln = 20;
function oe(t) {
  if (t == null) return String(t);
  if (ar(t)) return Ce(new Uint8Array(t));
  if (ir(t)) {
    const e = t;
    return Ce(new Uint8Array(e.buffer, e.byteOffset, e.byteLength));
  }
  if (typeof t == "string") return t;
  if (typeof t == "object")
    try {
      return JSON.stringify(t, Ks);
    } catch {
      return "[object with circular references]";
    }
  return String(t);
}
function ar(t) {
  if (t instanceof ArrayBuffer) return !0;
  const e = globalThis.SharedArrayBuffer;
  return !!(e && t instanceof e);
}
function ir(t) {
  return typeof ArrayBuffer < "u" && ArrayBuffer.isView(t);
}
function qs(t) {
  return (
    typeof t == "object" &&
    t !== null &&
    t.type === "Buffer" &&
    Array.isArray(t.data)
  );
}
function Ce(t) {
  if (t.length === 0) return "[byte array (0 bytes)]";
  const e = Math.min(t.length, ln),
    n = [];
  for (let s = 0; s < e; s++) n.push(Hs(t[s]));
  const r = t.length > ln ? " …" : "";
  return `[byte array ${n.join(" ")}${r} (${t.length} bytes)]`;
}
function Hs(t) {
  return `0x${t.toString(16).padStart(2, "0")}`;
}
function Ks(t, e) {
  if (ar(e)) return Ce(new Uint8Array(e));
  if (ir(e)) {
    const n = e;
    return Ce(new Uint8Array(n.buffer, n.byteOffset, n.byteLength));
  }
  return qs(e) ? Ce(Uint8Array.from(e.data)) : e;
}
function qc(t) {
  return {
    type: "computer",
    name: t.name ?? "computer_use_preview",
    computer: t.computer,
  };
}
function Hc(t) {
  return "serverUrl" in t
    ? {
        type: "hosted_tool",
        name: "hosted_mcp",
        providerData:
          typeof t.requireApproval > "u" || t.requireApproval === "never"
            ? {
                type: "mcp",
                server_label: t.serverLabel,
                server_url: t.serverUrl,
                authorization: t.authorization,
                require_approval: "never",
                allowed_tools: ve(t.allowedTools),
                headers: t.headers,
              }
            : {
                type: "mcp",
                server_label: t.serverLabel,
                server_url: t.serverUrl,
                authorization: t.authorization,
                allowed_tools: ve(t.allowedTools),
                headers: t.headers,
                require_approval:
                  typeof t.requireApproval == "string"
                    ? "always"
                    : ft(t.requireApproval),
                on_approval: t.onApproval,
              },
      }
    : "connectorId" in t
      ? {
          type: "hosted_tool",
          name: "hosted_mcp",
          providerData:
            typeof t.requireApproval > "u" || t.requireApproval === "never"
              ? {
                  type: "mcp",
                  server_label: t.serverLabel,
                  connector_id: t.connectorId,
                  authorization: t.authorization,
                  require_approval: "never",
                  allowed_tools: ve(t.allowedTools),
                  headers: t.headers,
                }
              : {
                  type: "mcp",
                  server_label: t.serverLabel,
                  connector_id: t.connectorId,
                  authorization: t.authorization,
                  allowed_tools: ve(t.allowedTools),
                  headers: t.headers,
                  require_approval:
                    typeof t.requireApproval == "string"
                      ? "always"
                      : ft(t.requireApproval),
                  on_approval: t.onApproval,
                },
        }
      : {
          type: "hosted_tool",
          name: "hosted_mcp",
          providerData:
            typeof t.requireApproval > "u" || t.requireApproval === "never"
              ? {
                  type: "mcp",
                  server_label: t.serverLabel,
                  require_approval: "never",
                  allowed_tools: ve(t.allowedTools),
                }
              : {
                  type: "mcp",
                  server_label: t.serverLabel,
                  allowed_tools: ve(t.allowedTools),
                  require_approval:
                    typeof t.requireApproval == "string"
                      ? "always"
                      : ft(t.requireApproval),
                  on_approval: t.onApproval,
                },
        };
}
function Ws(t, e) {
  return `An error occurred while running the tool. Please try again. Error: ${e instanceof Error ? e.toString() : String(e)}`;
}
function Ve(t) {
  const e = t.name ? We(t.name) : We(t.execute.name),
    n = typeof t.errorFunction > "u" ? Ws : t.errorFunction;
  if (!e)
    throw new Error(
      "Tool name cannot be empty. Either name your function or provide a name in the options.",
    );
  const r = t.strict ?? !0;
  if (!r && he(t.parameters))
    throw new k("Strict mode is required for Zod parameters");
  const { parser: o, schema: s } = Ct(t.parameters, e);
  async function a(l, d, m) {
    const [y, p] = await Ot(() => o(d));
    if (y !== null)
      throw (
        S.dontLogToolData
          ? S.debug(`Invalid JSON input for tool ${e}`)
          : S.debug(`Invalid JSON input for tool ${e}: ${d}`),
        new B("Invalid JSON input for tool")
      );
    S.dontLogToolData
      ? S.debug(`Invoking tool ${e}`)
      : S.debug(`Invoking tool ${e} with input ${d}`);
    const v = await t.execute(p, l, m),
      _ = oe(v);
    return (
      S.dontLogToolData
        ? S.debug(`Tool ${e} completed`)
        : S.debug(`Tool ${e} returned: ${_}`),
      v
    );
  }
  async function i(l, d, m) {
    return a(l, d, m).catch((y) => {
      if (n)
        return (
          Me()?.setError({
            message: "Error running tool (non-fatal)",
            data: { tool_name: e, error: y.toString() },
          }),
          n(l, y)
        );
      throw y;
    });
  }
  const f =
      typeof t.needsApproval == "function"
        ? t.needsApproval
        : async () =>
            typeof t.needsApproval == "boolean" ? t.needsApproval : !1,
    c =
      typeof t.isEnabled == "function"
        ? async (l, d) => {
            const m = t.isEnabled;
            return !!(await m({ runContext: l, agent: d }));
          }
        : async () => (typeof t.isEnabled == "boolean" ? t.isEnabled : !0);
  return {
    type: "function",
    name: e,
    description: t.description,
    parameters: s,
    strict: r,
    invoke: i,
    needsApproval: f,
    isEnabled: c,
  };
}
function ft(t) {
  const e = {};
  return (
    t.always && (e.always = { tool_names: t.always.toolNames }),
    t.never && (e.never = { tool_names: t.never.toolNames }),
    e
  );
}
function ve(t) {
  if (!(typeof t > "u"))
    return Array.isArray(t)
      ? { tool_names: t }
      : { tool_names: t?.toolNames ?? [] };
}
const Vs = "openai-agents:stdio-mcp-client",
  Ys = "openai-agents:streamable-http-mcp-client",
  Xs = "openai-agents:sse-mcp-client";
class ur {
  cacheToolsList;
  _cachedTools = void 0;
  toolFilter;
  logger;
  constructor(e) {
    ((this.logger = e.logger ?? Ee(Vs)),
      (this.cacheToolsList = e.cacheToolsList ?? !1),
      (this.toolFilter = e.toolFilter));
  }
  debugLog(e) {
    tt.enabled(this.logger.namespace) && this.logger.debug(e());
  }
}
class cr {
  cacheToolsList;
  _cachedTools = void 0;
  toolFilter;
  logger;
  constructor(e) {
    ((this.logger = e.logger ?? Ee(Ys)),
      (this.cacheToolsList = e.cacheToolsList ?? !1),
      (this.toolFilter = e.toolFilter));
  }
  debugLog(e) {
    tt.enabled(this.logger.namespace) && this.logger.debug(e());
  }
}
class lr {
  cacheToolsList;
  _cachedTools = void 0;
  toolFilter;
  logger;
  constructor(e) {
    ((this.logger = e.logger ?? Ee(Xs)),
      (this.cacheToolsList = e.cacheToolsList ?? !1),
      (this.toolFilter = e.toolFilter));
  }
  debugLog(e) {
    tt.enabled(this.logger.namespace) && this.logger.debug(e());
  }
}
h({
  name: u(),
  description: u().optional(),
  inputSchema: h({
    type: g("object"),
    properties: P(u(), A()),
    required: D(u()),
    additionalProperties: fe(),
  }),
});
class Kc extends ur {
  underlying;
  constructor(e) {
    (super(e), (this.underlying = new na(e)));
  }
  get name() {
    return this.underlying.name;
  }
  connect() {
    return this.underlying.connect();
  }
  close() {
    return this.underlying.close();
  }
  async listTools() {
    if (this.cacheToolsList && this._cachedTools) return this._cachedTools;
    const e = await this.underlying.listTools();
    return (this.cacheToolsList && (this._cachedTools = e), e);
  }
  callTool(e, n) {
    return this.underlying.callTool(e, n);
  }
  invalidateToolsCache() {
    return this.underlying.invalidateToolsCache();
  }
}
class Wc extends cr {
  underlying;
  constructor(e) {
    (super(e), (this.underlying = new ra(e)));
  }
  get name() {
    return this.underlying.name;
  }
  connect() {
    return this.underlying.connect();
  }
  close() {
    return this.underlying.close();
  }
  async listTools() {
    if (this.cacheToolsList && this._cachedTools) return this._cachedTools;
    const e = await this.underlying.listTools();
    return (this.cacheToolsList && (this._cachedTools = e), e);
  }
  callTool(e, n) {
    return this.underlying.callTool(e, n);
  }
  invalidateToolsCache() {
    return this.underlying.invalidateToolsCache();
  }
}
class Vc extends lr {
  underlying;
  constructor(e) {
    (super(e), (this.underlying = new oa(e)));
  }
  get name() {
    return this.underlying.name;
  }
  connect() {
    return this.underlying.connect();
  }
  close() {
    return this.underlying.close();
  }
  async listTools() {
    if (this.cacheToolsList && this._cachedTools) return this._cachedTools;
    const e = await this.underlying.listTools();
    return (this.cacheToolsList && (this._cachedTools = e), e);
  }
  callTool(e, n) {
    return this.underlying.callTool(e, n);
  }
  invalidateToolsCache() {
    return this.underlying.invalidateToolsCache();
  }
}
const Ze = {};
async function Yc(t) {
  delete Ze[t];
}
async function Qs({
  server: t,
  convertSchemasToStrict: e,
  runContext: n,
  agent: r,
}) {
  return t.cacheToolsList && Ze[t.name]
    ? Ze[t.name].map((o) => pn(o, t, e))
    : qa(
        async (o) => {
          const s = await t.listTools();
          let a = s;
          if (n && r) {
            const f = { runContext: n, agent: r, serverName: t.name },
              c = [];
            for (const l of s) {
              const d = t.toolFilter;
              if (d)
                if (typeof d == "function") {
                  if (!(await d(f, l))) {
                    S.debug(
                      `MCP Tool (server: ${t.name}, tool: ${l.name}) is blocked by the callable filter.`,
                    );
                    continue;
                  }
                } else {
                  const m = d.allowedToolNames ?? [],
                    y = d.blockedToolNames ?? [];
                  if (m.length > 0 || y.length > 0) {
                    const p = m.length > 0 ? m.includes(l.name) : !0,
                      v = y.length > 0 ? y.includes(l.name) : !1;
                    if (!p || v) {
                      v
                        ? S.debug(
                            `MCP Tool (server: ${t.name}, tool: ${l.name}) is blocked by the static filter.`,
                          )
                        : p ||
                          S.debug(
                            `MCP Tool (server: ${t.name}, tool: ${l.name}) is not allowed by the static filter.`,
                          );
                      continue;
                    }
                  }
                }
              c.push(l);
            }
            a = c;
          }
          o.spanData.result = a.map((f) => f.name);
          const i = a.map((f) => pn(f, t, e));
          return (t.cacheToolsList && (Ze[t.name] = a), i);
        },
        { data: { server: t.name } },
      );
}
async function ea(t, e, n, r = !1) {
  const o = Array.isArray(t)
      ? { mcpServers: t, runContext: e, agent: n, convertSchemasToStrict: r }
      : t,
    {
      mcpServers: s,
      convertSchemasToStrict: a = !1,
      runContext: i,
      agent: f,
    } = o,
    c = [],
    l = new Set();
  for (const d of s) {
    const m = await Qs({
        server: d,
        convertSchemasToStrict: a,
        runContext: i,
        agent: f,
      }),
      p = [...new Set(m.map((v) => v.name))].filter((v) => l.has(v));
    if (p.length > 0)
      throw new k(
        `Duplicate tool names found across MCP servers: ${p.join(", ")}`,
      );
    for (const v of m) (l.add(v.name), c.push(v));
  }
  return c;
}
function pn(t, e, n) {
  async function r(a, i) {
    let f = {};
    typeof a == "string" && a
      ? (f = JSON.parse(a))
      : typeof a == "object" && a != null && (f = a);
    const c = Me();
    c && (c.spanData.mcp_data = { server: e.name });
    const l = await e.callTool(t.name, f);
    return l.length === 1 ? l[0] : l;
  }
  const o = {
    ...t.inputSchema,
    type: t.inputSchema?.type ?? "object",
    properties: t.inputSchema?.properties ?? {},
    required: t.inputSchema?.required ?? [],
    additionalProperties: t.inputSchema?.additionalProperties ?? !1,
  };
  if (n || o.additionalProperties === !0)
    try {
      const a = ta(o);
      return Ve({
        name: t.name,
        description: t.description || "",
        parameters: a,
        strict: !0,
        execute: r,
      });
    } catch (a) {
      S.warn(`Error converting MCP schema to strict mode: ${a}`);
    }
  const s = { ...o, additionalProperties: !0 };
  return Ve({
    name: t.name,
    description: t.description || "",
    parameters: s,
    strict: !1,
    execute: r,
  });
}
function ta(t) {
  const e = { ...t, additionalProperties: !1 };
  return (e.required || (e.required = []), e);
}
let na = class extends ur {
    constructor(e) {
      super(e);
    }
    get name() {
      return "MCPServerStdio";
    }
    connect() {
      throw new Error("Method not implemented.");
    }
    close() {
      throw new Error("Method not implemented.");
    }
    listTools() {
      throw new Error("Method not implemented.");
    }
    callTool(e, n) {
      throw new Error("Method not implemented.");
    }
    invalidateToolsCache() {
      throw new Error("Method not implemented.");
    }
  },
  ra = class extends cr {
    constructor(e) {
      super(e);
    }
    get name() {
      return "MCPServerStdio";
    }
    connect() {
      throw new Error("Method not implemented.");
    }
    close() {
      throw new Error("Method not implemented.");
    }
    listTools() {
      throw new Error("Method not implemented.");
    }
    callTool(e, n) {
      throw new Error("Method not implemented.");
    }
    invalidateToolsCache() {
      throw new Error("Method not implemented.");
    }
  },
  oa = class extends lr {
    constructor(e) {
      super(e);
    }
    get name() {
      return "MCPServerSSE";
    }
    connect() {
      throw new Error("Method not implemented.");
    }
    close() {
      throw new Error("Method not implemented.");
    }
    listTools() {
      throw new Error("Method not implemented.");
    }
    callTool(e, n) {
      throw new Error("Method not implemented.");
    }
    invalidateToolsCache() {
      throw new Error("Method not implemented.");
    }
  };
function Rt() {
  return {};
}
class nt {
  #e = new EventTarget();
  #t = new Map();
  on(e, n) {
    const r = e;
    let o = this.#t.get(r);
    o || ((o = new Map()), this.#t.set(r, o));
    let s = o.get(n);
    s || ((s = new Set()), o.set(n, s));
    const a = (i) => n(...(i.detail ?? []));
    return (s.add(a), this.#e.addEventListener(r, a), this);
  }
  off(e, n) {
    const r = e,
      o = this.#t.get(r),
      s = o?.get(n);
    if (s?.size) {
      for (const a of s) this.#e.removeEventListener(r, a);
      (o?.delete(n), o?.size === 0 && this.#t.delete(r));
    }
    return this;
  }
  emit(e, ...n) {
    const r = new CustomEvent(e, { detail: n });
    return this.#e.dispatchEvent(r);
  }
  once(e, n) {
    const r = (...o) => {
      (this.off(e, r), n(...o));
    };
    return (this.on(e, r), this);
  }
}
const Nt = () =>
    typeof crypto < "u" && crypto.randomUUID
      ? crypto.randomUUID()
      : "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx".replace(/[xy]/g, function (t) {
          const e = (Math.random() * 16) | 0;
          return (t === "x" ? e : (e & 3) | 8).toString(16);
        }),
  sa = class {
    constructor() {}
    pipeTo(e, n) {}
    pipeThrough(e, n) {}
  },
  aa = globalThis.ReadableStream,
  ia = globalThis.TransformStream;
class ua {
  context = null;
  constructor() {}
  run(e, n) {
    return ((this.context = e), n());
  }
  getStore() {
    return this.context;
  }
  enterWith(e) {
    this.context = e;
  }
}
class ca {
  constructor() {}
  setTimeout(e, n) {
    const r = setTimeout(e, n);
    return (
      (r.ref = typeof r.ref == "function" ? r.ref : () => r),
      (r.unref = typeof r.unref == "function" ? r.unref : () => r),
      (r.hasRef = typeof r.hasRef == "function" ? r.hasRef : () => !0),
      (r.refresh = typeof r.refresh == "function" ? r.refresh : () => r),
      r
    );
  }
  clearTimeout(e) {
    window.clearTimeout(e);
  }
}
const la = new ca();
class Pt {
  on(e, n) {
    return (this.eventEmitter.on(e, n), this.eventEmitter);
  }
  off(e, n) {
    return (this.eventEmitter.off(e, n), this.eventEmitter);
  }
  emit(e, ...n) {
    return this.eventEmitter.emit(e, ...n);
  }
  once(e, n) {
    return (this.eventEmitter.once(e, n), this.eventEmitter);
  }
}
class pa extends Pt {
  eventEmitter = new nt();
}
class da extends Pt {
  eventEmitter = new nt();
}
const fa = "OPENAI_DEFAULT_MODEL";
function rt(t) {
  return t.startsWith("gpt-5-chat") ? !1 : t.startsWith("gpt-5");
}
function pr() {
  return rt(Mt());
}
function Mt() {
  return rr()[fa]?.toLowerCase() ?? "gpt-4.1";
}
function ma(t) {
  const e = t ?? Mt();
  return rt(e)
    ? { reasoning: { effort: "low" }, text: { verbosity: "low" } }
    : {};
}
function dr(t) {
  return JSON.stringify({ assistant: t.name });
}
function ha(t) {
  return `transfer_to_${We(t.name)}`;
}
function ga(t) {
  return `Handoff to the ${t.name} agent to handle the request. ${t.handoffDescription ?? ""}`;
}
class fr {
  toolName;
  toolDescription;
  inputJsonSchema = {
    type: "object",
    properties: {},
    required: [],
    additionalProperties: !1,
  };
  strictJsonSchema = !0;
  onInvokeHandoff;
  agentName;
  inputFilter;
  agent;
  getHandoffAsFunctionTool() {
    return {
      type: "function",
      name: this.toolName,
      description: this.toolDescription,
      parameters: this.inputJsonSchema,
      strict: this.strictJsonSchema,
    };
  }
  isEnabled = async () => !0;
  constructor(e, n) {
    ((this.agentName = e.name),
      (this.onInvokeHandoff = n),
      (this.toolName = ha(e)),
      (this.toolDescription = ga(e)),
      (this.agent = e));
  }
}
function mr(t, e = {}) {
  let n;
  const r = !!e.onHandoff,
    o = !!e.inputType;
  if (!(r === o))
    throw new k(
      "You must provide either both `onHandoff` and `inputType` or neither.",
    );
  async function a(f, c) {
    if (n) {
      if (!c)
        throw (
          Ie({
            message: `Handoff function expected non empty input but got: ${c}`,
            data: { details: "input is empty" },
          }),
          new B("Handoff function expected non empty input")
        );
      try {
        const l = await n(c);
        e.onHandoff && (await e.onHandoff(f, l));
      } catch (l) {
        throw (
          Ie({ message: "Invalid JSON provided", data: {} }),
          S.dontLogToolData ||
            S.error(`Invalid JSON when parsing: ${c}. Error: ${l}`),
          new B("Invalid JSON provided")
        );
      }
    } else await e.onHandoff?.(f);
    return t;
  }
  const i = new fr(t, a);
  if (typeof e.isEnabled == "function") {
    const f = e.isEnabled;
    i.isEnabled = async ({ runContext: c, agent: l }) =>
      !!(await f({ runContext: c, agent: l }));
  } else
    typeof e.isEnabled == "boolean" && (i.isEnabled = async () => e.isEnabled);
  if (e.inputType) {
    const f = Ct(e.inputType, i.toolName);
    ((i.inputJsonSchema = f.schema), (i.strictJsonSchema = !0), (n = f.parser));
  }
  return (
    e.toolNameOverride && (i.toolName = e.toolNameOverride),
    e.toolDescriptionOverride &&
      (i.toolDescription = e.toolDescriptionOverride),
    e.inputFilter && (i.inputFilter = e.inputFilter),
    i
  );
}
function ya(t) {
  return t instanceof fr ? t : mr(t);
}
function hr(t) {
  if (t.type !== "message" || t.role !== "assistant") return;
  const e = t.content[t.content.length - 1];
  if (e.type === "output_text") return e.text;
}
function _a(t) {
  return t.output.length === 0 ? "" : hr(t.output[t.output.length - 1]) || "";
}
const St = new WeakMap();
function va(t, e) {
  t && St.set(t, e);
}
function wa(t) {
  const e = St.get(t);
  return (e && St.delete(t), e);
}
const ba = h({ input: u() });
class te extends pa {
  static create(e) {
    return new te({
      ...e,
      handoffs: e.handoffs,
      outputType: e.outputType,
      handoffOutputTypeWarningEnabled: !1,
    });
  }
  static DEFAULT_MODEL_PLACEHOLDER = "";
  name;
  instructions;
  prompt;
  handoffDescription;
  handoffs;
  model;
  modelSettings;
  tools;
  mcpServers;
  inputGuardrails;
  outputGuardrails;
  outputType = "text";
  toolUseBehavior;
  resetToolChoice;
  constructor(e) {
    if ((super(), typeof e.name != "string" || e.name.trim() === ""))
      throw new k("Agent must have a name.");
    if (
      ((this.name = e.name),
      (this.instructions = e.instructions ?? te.DEFAULT_MODEL_PLACEHOLDER),
      (this.prompt = e.prompt),
      (this.handoffDescription = e.handoffDescription ?? ""),
      (this.handoffs = e.handoffs ?? []),
      (this.model = e.model ?? ""),
      (this.modelSettings = e.modelSettings ?? ma()),
      (this.tools = e.tools ?? []),
      (this.mcpServers = e.mcpServers ?? []),
      (this.inputGuardrails = e.inputGuardrails ?? []),
      (this.outputGuardrails = e.outputGuardrails ?? []),
      e.outputType && (this.outputType = e.outputType),
      (this.toolUseBehavior = e.toolUseBehavior ?? "run_llm_again"),
      (this.resetToolChoice = e.resetToolChoice ?? !0),
      e.model !== void 0 &&
        pr() &&
        (typeof e.model != "string" || !rt(e.model)) &&
        e.modelSettings === void 0 &&
        (this.modelSettings = {}),
      (e.handoffOutputTypeWarningEnabled === void 0 ||
        e.handoffOutputTypeWarningEnabled) &&
        this.handoffs &&
        this.outputType)
    ) {
      const n = new Set([JSON.stringify(this.outputType)]);
      for (const r of this.handoffs)
        "outputType" in r && r.outputType
          ? n.add(JSON.stringify(r.outputType))
          : "agent" in r &&
            r.agent.outputType &&
            n.add(JSON.stringify(r.agent.outputType));
      n.size > 1 &&
        S.warn(
          `[Agent] Warning: Handoff agents have different output types: ${Array.from(n).join(", ")}. You can make it type-safe by using Agent.create({ ... }) method instead.`,
        );
    }
  }
  get outputSchemaName() {
    if (this.outputType === "text") return "text";
    if (he(this.outputType)) return "ZodOutput";
    if (typeof this.outputType == "object") return this.outputType.name;
    throw new Error(`Unknown output type: ${this.outputType}`);
  }
  clone(e) {
    return new te({ ...this, ...e });
  }
  asTool(e) {
    const {
      toolName: n,
      toolDescription: r,
      customOutputExtractor: o,
      needsApproval: s,
      runConfig: a,
      runOptions: i,
      isEnabled: f,
    } = e;
    return Ve({
      name: n ?? We(this.name),
      description: r ?? "",
      parameters: ba,
      strict: !0,
      needsApproval: s,
      isEnabled: f,
      execute: async (c, l, d) => {
        if (!bs(c)) throw new B("Agent tool called with invalid input");
        const p = await new Hr(a ?? {}).run(this, c.input, {
            context: l,
            ...(i ?? {}),
          }),
          v =
            typeof this.toolUseBehavior == "object" &&
            this.toolUseBehavior !== null &&
            "stopAtToolNames" in this.toolUseBehavior;
        typeof o != "function" &&
          v &&
          S.debug(
            `You're passing the agent (name: ${this.name}) with toolUseBehavior.stopAtToolNames configured as a tool to a different agent; this may not work as you expect. You may want to have a wrapper function tool to consistently return the final output.`,
          );
        const _ =
          typeof o == "function"
            ? await o(p)
            : _a(p.rawResponses[p.rawResponses.length - 1]);
        return (d?.toolCall && va(d.toolCall, p), _);
      },
    });
  }
  async getSystemPrompt(e) {
    return typeof this.instructions == "function"
      ? await this.instructions(e, this)
      : this.instructions;
  }
  async getPrompt(e) {
    return typeof this.prompt == "function"
      ? await this.prompt(e, this)
      : this.prompt;
  }
  async getMcpTools(e) {
    return this.mcpServers.length > 0
      ? ea({
          mcpServers: this.mcpServers,
          runContext: e,
          agent: this,
          convertSchemasToStrict: !1,
        })
      : [];
  }
  async getAllTools(e) {
    const n = await this.getMcpTools(e),
      r = [];
    for (const o of this.tools) {
      if (o.type === "function") {
        const s = o.isEnabled;
        if (
          !(typeof s == "function"
            ? await s(e, this)
            : typeof s == "boolean"
              ? s
              : !0)
        )
          continue;
      }
      r.push(o);
    }
    return [...n, ...r];
  }
  async getEnabledHandoffs(e) {
    const n = this.handoffs?.map((o) => ya(o)) ?? [],
      r = [];
    for (const o of n)
      (await o.isEnabled({ runContext: e, agent: this })) && r.push(o);
    return r;
  }
  processFinalOutput(e) {
    if (this.outputType === "text") return e;
    if (typeof this.outputType == "object") {
      const n = JSON.parse(e);
      return he(this.outputType) ? this.outputType.parse(n) : n;
    }
    throw new Error(`Unknown output type: ${this.outputType}`);
  }
  toJSON() {
    return { name: this.name };
  }
}
function dn({ name: t, execute: e }) {
  return {
    type: "input",
    name: t,
    guardrailFunction: e,
    async run(n) {
      return { guardrail: { type: "input", name: t }, output: await e(n) };
    },
  };
}
function Tt({ name: t, execute: e }) {
  return {
    type: "output",
    name: t,
    guardrailFunction: e,
    async run(n) {
      return {
        guardrail: { type: "output", name: t },
        agent: n.agent,
        agentOutput: n.agentOutput,
        output: await e(n),
      };
    },
  };
}
let It;
function Sa(t) {
  It = t;
}
function Ta() {
  if (typeof It > "u")
    throw new Error(
      "No default model provider set. Make sure to set a provider using setDefaultModelProvider before calling getDefaultModelProvider or pass an explicit provider.",
    );
  return It;
}
const M = h({ providerData: P(u(), A()).optional() }),
  ae = M.extend({ id: u().optional() }),
  gr = M.extend({ type: g("refusal"), refusal: u() }),
  yr = M.extend({ type: g("output_text"), text: u() }),
  ot = M.extend({ type: g("input_text"), text: u() }),
  _r = M.extend({ type: g("reasoning_text"), text: u() }),
  Ft = M.extend({
    type: g("input_image"),
    image: u()
      .or(h({ id: u().describe("OpenAI file ID") }))
      .describe(
        "Either base64 encoded image data, a data URL, or an object with a file ID.",
      )
      .optional(),
    detail: u().optional(),
  }),
  Lt = M.extend({
    type: g("input_file"),
    file: u()
      .describe(
        "Either base64 encoded file data or a publicly accessible file URL",
      )
      .or(h({ id: u().describe("OpenAI file ID") }))
      .or(h({ url: u().describe("Publicly accessible file URL") }))
      .describe("Contents of the file or an object with a file ID.")
      .optional(),
    filename: u().optional(),
  }),
  $t = M.extend({
    type: g("audio"),
    audio: u()
      .or(h({ id: u() }))
      .describe("Base64 encoded audio data or file id"),
    format: u().nullable().optional(),
    transcript: u().nullable().optional(),
  }),
  vr = M.extend({
    type: g("image"),
    image: u().describe("Base64 encoded image data"),
  }),
  wr = M.extend({ type: g("text"), text: u() }),
  Ia = h({
    data: ye([u(), Bn(Uint8Array)]).describe(
      "Base64 image data, or raw bytes that will be base64 encoded automatically.",
    ),
    mediaType: u().optional(),
  }),
  xa = h({
    url: u().describe("Publicly accessible URL pointing to the image content"),
  }),
  Aa = h({
    fileId: u().describe("OpenAI file ID referencing uploaded image content"),
  }),
  Da = ye([Ia, xa, Aa]).describe(
    "Inline image data or references to uploaded content.",
  ),
  ka = h({
    data: ye([u(), Bn(Uint8Array)]).describe(
      "Base64 encoded file data, or raw bytes that will be encoded automatically.",
    ),
    mediaType: u().describe("IANA media type describing the file contents"),
    filename: u().describe("Filename associated with the inline data"),
  }),
  Ea = h({
    url: u().describe("Publicly accessible URL for the file content"),
    filename: u().optional(),
  }),
  Oa = h({
    id: u().describe("OpenAI file ID referencing uploaded content"),
    filename: u().optional(),
  }),
  Ca = ye([
    u().describe("Existing data URL or base64 string"),
    ka,
    Ea,
    Oa,
  ]).describe(
    "Inline data (with metadata) or references pointing to file contents.",
  ),
  Ra = (...t) => u(),
  br = M.extend({
    type: g("image"),
    image: u().or(Da).optional(),
    detail: Ra("low", "high", "auto").optional(),
  }),
  Sr = M.extend({ type: g("file"), file: Ca }),
  Tr = M.extend({
    type: g("computer_screenshot"),
    data: u().describe("Base64 encoded image data or URL"),
  }),
  Ir = G("type", [
    h({ type: g("screenshot") }),
    h({
      type: g("click"),
      x: w(),
      y: w(),
      button: N(["left", "right", "wheel", "back", "forward"]),
    }),
    h({ type: g("double_click"), x: w(), y: w() }),
    h({ type: g("scroll"), x: w(), y: w(), scroll_x: w(), scroll_y: w() }),
    h({ type: g("type"), text: u() }),
    h({ type: g("wait") }),
    h({ type: g("move"), x: w(), y: w() }),
    h({ type: g("keypress"), keys: D(u()) }),
    h({ type: g("drag"), path: D(h({ x: w(), y: w() })) }),
  ]),
  xr = G("type", [yr, gr, $t, vr]),
  jt = ae.extend({ type: g("message").optional() }),
  $e = jt.extend({
    role: g("assistant"),
    status: N(["in_progress", "completed", "incomplete"]),
    content: D(xr),
  }),
  Ar = G("type", [ot, Ft, Lt, $t]),
  Ut = jt.extend({ role: g("user"), content: D(Ar).or(u()) }),
  Dr = jt.extend({ role: g("system"), content: u() }),
  Na = G("role", [Dr, $e, Ut]),
  xe = ae.extend({
    type: g("hosted_tool_call"),
    name: u().describe("The name of the hosted tool"),
    arguments: u().describe("The arguments of the hosted tool call").optional(),
    status: u().optional(),
    output: u().optional(),
  }),
  Ae = ae.extend({
    type: g("function_call"),
    callId: u().describe("The ID of the tool call"),
    name: u().describe("The name of the function"),
    status: N(["in_progress", "completed", "incomplete"]).optional(),
    arguments: u(),
  }),
  kr = G("type", [wr, br, Sr]),
  Er = G("type", [ot, Ft, Lt]),
  Ye = ae.extend({
    type: g("function_call_result"),
    name: u().describe("The name of the tool"),
    callId: u().describe("The ID of the tool call"),
    status: N(["in_progress", "completed", "incomplete"]),
    output: ye([u(), kr, D(Er)]).describe(
      "Output returned by the tool call. Supports plain strings, legacy ToolOutput items, or structured input_* items.",
    ),
  }),
  st = ae.extend({
    type: g("computer_call"),
    callId: u().describe("The ID of the computer call"),
    status: N(["in_progress", "completed", "incomplete"]),
    action: Ir,
  }),
  Or = ae.extend({
    type: g("computer_call_result"),
    callId: u().describe("The ID of the computer call"),
    output: Tr,
  }),
  Cr = G("type", [st, Ae, xe]),
  at = M.extend({
    id: u().optional(),
    type: g("reasoning"),
    content: D(ot),
    rawContent: D(_r).optional(),
  }),
  Jt = ae.extend({ type: g("unknown") }),
  it = G("type", [$e, xe, Ae, st, at, Jt]),
  Rr = ye([Ut, $e, Dr, xe, Ae, st, Ye, Or, at, Jt]),
  Nr = h({
    requests: w().optional(),
    inputTokens: w(),
    outputTokens: w(),
    totalTokens: w(),
    inputTokensDetails: P(u(), w()).optional(),
    outputTokensDetails: P(u(), w()).optional(),
  }),
  Gt = M.extend({ type: g("output_text_delta"), delta: u() }),
  Pr = M.extend({ type: g("response_started") }),
  Bt = M.extend({
    type: g("response_done"),
    response: M.extend({ id: u(), usage: Nr, output: D(it) }),
  }),
  Mr = M.extend({
    type: g("model"),
    event: A().describe("The event from the model"),
  }),
  Pa = G("type", [Gt, Bt, Pr, Mr]),
  nl = Object.freeze(
    Object.defineProperty(
      {
        __proto__: null,
        AssistantContent: xr,
        AssistantMessageItem: $e,
        AudioContent: $t,
        ComputerCallResultItem: Or,
        ComputerToolOutput: Tr,
        ComputerUseCallItem: st,
        FunctionCallItem: Ae,
        FunctionCallResultItem: Ye,
        HostedToolCallItem: xe,
        ImageContent: vr,
        InputFile: Lt,
        InputImage: Ft,
        InputText: ot,
        ItemBase: ae,
        MessageItem: Na,
        ModelItem: Rr,
        OutputModelItem: it,
        OutputText: yr,
        ReasoningItem: at,
        ReasoningText: _r,
        Refusal: gr,
        SharedBase: M,
        StreamEvent: Pa,
        StreamEventGenericItem: Mr,
        StreamEventResponseCompleted: Bt,
        StreamEventResponseStarted: Pr,
        StreamEventTextStream: Gt,
        ToolCallItem: Cr,
        ToolCallOutputContent: kr,
        ToolCallStructuredOutput: Er,
        ToolOutputFileContent: Sr,
        ToolOutputImage: br,
        ToolOutputText: wr,
        UnknownItem: Jt,
        UsageData: Nr,
        UserContent: Ar,
        UserMessageItem: Ut,
        computerActions: Ir,
      },
      Symbol.toStringTag,
      { value: "Module" },
    ),
  );
class ge {
  requests;
  inputTokens;
  outputTokens;
  totalTokens;
  inputTokensDetails = [];
  outputTokensDetails = [];
  constructor(e) {
    if (typeof e > "u")
      ((this.requests = 0),
        (this.inputTokens = 0),
        (this.outputTokens = 0),
        (this.totalTokens = 0),
        (this.inputTokensDetails = []),
        (this.outputTokensDetails = []));
    else {
      ((this.requests = e?.requests ?? 1),
        (this.inputTokens = e?.inputTokens ?? e?.input_tokens ?? 0),
        (this.outputTokens = e?.outputTokens ?? e?.output_tokens ?? 0),
        (this.totalTokens = e?.totalTokens ?? e?.total_tokens ?? 0));
      const n = e?.inputTokensDetails ?? e?.input_tokens_details;
      this.inputTokensDetails = n ? [n] : [];
      const r = e?.outputTokensDetails ?? e?.output_tokens_details;
      this.outputTokensDetails = r ? [r] : [];
    }
  }
  add(e) {
    ((this.requests += e.requests),
      (this.inputTokens += e.inputTokens),
      (this.outputTokens += e.outputTokens),
      (this.totalTokens += e.totalTokens),
      e.inputTokensDetails &&
        this.inputTokensDetails.push(...e.inputTokensDetails),
      e.outputTokensDetails &&
        this.outputTokensDetails.push(...e.outputTokensDetails));
  }
}
class we {
  context;
  usage;
  #e;
  constructor(e = {}) {
    ((this.context = e), (this.usage = new ge()), (this.#e = new Map()));
  }
  _rebuildApprovals(e) {
    this.#e = new Map(Object.entries(e));
  }
  isToolApproved(e) {
    const { toolName: n, callId: r } = e,
      o = this.#e.get(n);
    if (o?.approved === !0 && o.rejected === !0)
      return (
        S.warn(
          "Tool is permanently approved and rejected at the same time. Approval takes precedence",
        ),
        !0
      );
    if (o?.approved === !0) return !0;
    if (o?.rejected === !0) return !1;
    const s = Array.isArray(o?.approved) ? o.approved.includes(r) : !1,
      a = Array.isArray(o?.rejected) ? o.rejected.includes(r) : !1;
    if (s && a)
      return (
        S.warn(
          `Tool call ${r} is both approved and rejected at the same time. Approval takes precedence`,
        ),
        !0
      );
    if (s) return !0;
    if (a) return !1;
  }
  approveTool(e, { alwaysApprove: n = !1 } = {}) {
    const r = e.rawItem.name;
    if (n) {
      this.#e.set(r, { approved: !0, rejected: [] });
      return;
    }
    const o = this.#e.get(r) ?? { approved: [], rejected: [] };
    if (Array.isArray(o.approved)) {
      const s = "callId" in e.rawItem ? e.rawItem.callId : e.rawItem.id;
      o.approved.push(s);
    }
    this.#e.set(r, o);
  }
  rejectTool(e, { alwaysReject: n = !1 } = {}) {
    const r = e.rawItem.name;
    if (n) {
      this.#e.set(r, { approved: !1, rejected: !0 });
      return;
    }
    const o = this.#e.get(r) ?? { approved: [], rejected: [] };
    if (Array.isArray(o.rejected)) {
      const s = "callId" in e.rawItem ? e.rawItem.callId : e.rawItem.id;
      o.rejected.push(s);
    }
    this.#e.set(r, o);
  }
  toJSON() {
    return {
      context: this.context,
      usage: this.usage,
      approvals: Object.fromEntries(this.#e.entries()),
    };
  }
}
function fn(t) {
  return t.type === "function"
    ? {
        type: "function",
        name: t.name,
        description: t.description,
        parameters: t.parameters,
        strict: t.strict,
      }
    : t.type === "computer"
      ? {
          type: "computer",
          name: t.name,
          environment: t.computer.environment,
          dimensions: t.computer.dimensions,
        }
      : { type: "hosted_tool", name: t.name, providerData: t.providerData };
}
function mn(t) {
  return {
    toolName: t.toolName,
    toolDescription: t.toolDescription,
    inputJsonSchema: t.inputJsonSchema,
    strictJsonSchema: t.strictJsonSchema,
  };
}
class _e {
  type = "base_item";
  rawItem;
  toJSON() {
    return { type: this.type, rawItem: this.rawItem };
  }
}
class ut extends _e {
  rawItem;
  agent;
  type = "message_output_item";
  constructor(e, n) {
    (super(), (this.rawItem = e), (this.agent = n));
  }
  toJSON() {
    return { ...super.toJSON(), agent: this.agent.toJSON() };
  }
  get content() {
    let e = "";
    for (const n of this.rawItem.content)
      n.type === "output_text" && (e += n.text);
    return e;
  }
}
class me extends _e {
  rawItem;
  agent;
  type = "tool_call_item";
  constructor(e, n) {
    (super(), (this.rawItem = e), (this.agent = n));
  }
  toJSON() {
    return { ...super.toJSON(), agent: this.agent.toJSON() };
  }
}
class De extends _e {
  rawItem;
  agent;
  output;
  type = "tool_call_output_item";
  constructor(e, n, r) {
    (super(), (this.rawItem = e), (this.agent = n), (this.output = r));
  }
  toJSON() {
    return {
      ...super.toJSON(),
      agent: this.agent.toJSON(),
      output: oe(this.output),
    };
  }
}
class zt extends _e {
  rawItem;
  agent;
  type = "reasoning_item";
  constructor(e, n) {
    (super(), (this.rawItem = e), (this.agent = n));
  }
  toJSON() {
    return { ...super.toJSON(), agent: this.agent.toJSON() };
  }
}
class Zt extends _e {
  rawItem;
  agent;
  type = "handoff_call_item";
  constructor(e, n) {
    (super(), (this.rawItem = e), (this.agent = n));
  }
  toJSON() {
    return { ...super.toJSON(), agent: this.agent.toJSON() };
  }
}
class qt extends _e {
  rawItem;
  sourceAgent;
  targetAgent;
  type = "handoff_output_item";
  constructor(e, n, r) {
    (super(),
      (this.rawItem = e),
      (this.sourceAgent = n),
      (this.targetAgent = r));
  }
  toJSON() {
    return {
      ...super.toJSON(),
      sourceAgent: this.sourceAgent.toJSON(),
      targetAgent: this.targetAgent.toJSON(),
    };
  }
}
class q extends _e {
  rawItem;
  agent;
  type = "tool_approval_item";
  constructor(e, n) {
    (super(), (this.rawItem = e), (this.agent = n));
  }
  toJSON() {
    return { ...super.toJSON(), agent: this.agent.toJSON() };
  }
}
function rl(t) {
  return t
    .filter((e) => e.type === "message_output_item")
    .map((e) => e.content)
    .join("");
}
function V(t) {
  return async (e, ...n) =>
    Dt(async () => {
      const r = t(...n);
      Te(r);
      try {
        return (r.start(), await e(r));
      } catch (o) {
        throw (r.setError({ message: o.message, data: o.data }), o);
      } finally {
        (r.end(), de());
      }
    });
}
function Fr(t, e) {
  return (
    (t = {}),
    $().createSpan({ ...t, data: { type: "response", ...t.data } }, e)
  );
}
const Ma = V(Fr);
function xt(t, e) {
  return $().createSpan(
    {
      ...t,
      data: { type: "agent", name: t?.data?.name ?? "Agent", ...t?.data },
    },
    e,
  );
}
const ol = V(xt);
function Fa(t, e) {
  return $().createSpan(
    {
      ...t,
      data: {
        type: "function",
        input: t?.data?.input ?? "",
        output: t?.data?.output ?? "",
        ...t?.data,
      },
    },
    e,
  );
}
const hn = V(Fa);
function La(t, e) {
  return $().createSpan({ ...t, data: { type: "handoff", ...t?.data } }, e);
}
const $a = V(La);
function Lr(t, e) {
  return $().createSpan({ ...t, data: { type: "generation", ...t?.data } }, e);
}
const ja = V(Lr);
function Ua(t, e) {
  return $().createSpan(
    { ...t, data: { type: "custom", data: {}, ...t?.data } },
    e,
  );
}
const sl = V(Ua);
function Ja(t, e) {
  return $().createSpan(
    { ...t, data: { type: "guardrail", triggered: !1, ...t?.data } },
    e,
  );
}
const gn = V(Ja);
function Ga(t, e) {
  return $().createSpan(
    { ...t, data: { type: "transcription", ...t.data } },
    e,
  );
}
const al = V(Ga);
function Ba(t, e) {
  return $().createSpan({ ...t, data: { type: "speech", ...t.data } }, e);
}
const il = V(Ba);
function za(t, e) {
  return $().createSpan(
    { ...t, data: { type: "speech_group", ...t?.data } },
    e,
  );
}
const ul = V(za);
function Za(t, e) {
  return $().createSpan({ ...t, data: { type: "mcp_tools", ...t?.data } }, e);
}
const qa = V(Za);
function Re(t) {
  if (t.length === 0) return "";
  const e =
    typeof globalThis < "u" && globalThis.Buffer ? globalThis.Buffer : void 0;
  if (e) return e.from(t).toString("base64");
  let n = "";
  for (let a = 0; a < t.length; a += 1) n += String.fromCharCode(t[a]);
  if (typeof globalThis.btoa == "function") return globalThis.btoa(n);
  const r = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=";
  let o = "",
    s = 0;
  for (; s < n.length;) {
    const a = n.charCodeAt(s++),
      i = n.charCodeAt(s++),
      f = n.charCodeAt(s++),
      c = a >> 2,
      l = ((a & 3) << 4) | (i >> 4),
      d = isNaN(i) ? 64 : ((i & 15) << 2) | (f >> 6),
      m = isNaN(f) ? 64 : f & 63;
    o += r.charAt(c) + r.charAt(l) + r.charAt(d) + r.charAt(m);
  }
  return o;
}
class Ha {
  data;
  type = "raw_model_stream_event";
  constructor(e) {
    this.data = e;
  }
}
class Ka {
  name;
  item;
  type = "run_item_stream_event";
  constructor(e, n) {
    ((this.name = e), (this.item = n));
  }
}
class Wa {
  agent;
  type = "agent_updated_stream_event";
  constructor(e) {
    this.agent = e;
  }
}
function yn(t, e, n, r) {
  const o = [],
    s = [],
    a = [],
    i = [],
    f = [],
    c = [],
    l = new Map(r.map((p) => [p.toolName, p])),
    d = new Map(n.filter((p) => p.type === "function").map((p) => [p.name, p])),
    m = n.find((p) => p.type === "computer"),
    y = new Map(
      n
        .filter(
          (p) => p.type === "hosted_tool" && p.providerData?.type === "mcp",
        )
        .map((p) => p)
        .map((p) => [p.providerData.server_label, p]),
    );
  for (const p of t.output) {
    if (p.type === "message") p.role === "assistant" && o.push(new ut(p, e));
    else if (p.type === "hosted_tool_call") {
      o.push(new me(p, e));
      const _ = p.name;
      if (
        (c.push(_),
        p.providerData?.type === "mcp_approval_request" ||
          p.name === "mcp_approval_request")
      ) {
        const T = p.providerData,
          b = T.server_label,
          I = y.get(b);
        if (typeof I > "u") {
          const U = `MCP server (${b}) not found in Agent (${e.name})`;
          throw (Ie({ message: U, data: { mcp_server_label: b } }), new B(U));
        }
        const E = new q(
          {
            type: "hosted_tool_call",
            name: T.name,
            id: T.id,
            status: "in_progress",
            providerData: T,
          },
          e,
        );
        (f.push({ requestItem: E, mcpTool: I }),
          I.providerData.on_approval || o.push(E));
      }
    } else if (p.type === "reasoning") o.push(new zt(p, e));
    else if (p.type === "computer_call") {
      if ((o.push(new me(p, e)), c.push("computer_use"), !m))
        throw (
          Ie({
            message: "Model produced computer action without a computer tool.",
            data: { agent_name: e.name },
          }),
          new B("Model produced computer action without a computer tool.")
        );
      i.push({ toolCall: p, computer: m });
    }
    if (p.type !== "function_call") continue;
    c.push(p.name);
    const v = l.get(p.name);
    if (v) (o.push(new Zt(p, e)), s.push({ toolCall: p, handoff: v }));
    else {
      const _ = d.get(p.name);
      if (!_)
        throw (
          Ie({
            message: `Tool ${p.name} not found in agent ${e.name}.`,
            data: { tool_name: p.name, agent_name: e.name },
          }),
          new B(`Tool ${p.name} not found in agent ${e.name}.`)
        );
      (o.push(new me(p, e)), a.push({ toolCall: p, tool: _ }));
    }
  }
  return {
    newItems: o,
    handoffs: s,
    functions: a,
    computerActions: i,
    mcpApprovalRequests: f,
    toolsUsed: c,
    hasToolsOrApprovalsToRun() {
      return s.length > 0 || a.length > 0 || f.length > 0 || i.length > 0;
    },
  };
}
const Va = G("type", [
  h({ type: g("next_step_handoff"), newAgent: A() }),
  h({ type: g("next_step_final_output"), output: u() }),
  h({ type: g("next_step_run_again") }),
  h({ type: g("next_step_interruption"), data: P(u(), A()) }),
]);
class z {
  originalInput;
  modelResponse;
  preStepItems;
  newStepItems;
  nextStep;
  constructor(e, n, r, o, s) {
    ((this.originalInput = e),
      (this.modelResponse = n),
      (this.preStepItems = r),
      (this.newStepItems = o),
      (this.nextStep = s));
  }
  get generatedItems() {
    return this.preStepItems.concat(this.newStepItems);
  }
}
function _n(t, e, n) {
  return t.resetToolChoice && e.hasUsedTools(t)
    ? { ...n, toolChoice: void 0 }
    : n;
}
async function vn(t, e, n, r, o, s, a) {
  const i = n
      .filter(
        (p) =>
          p instanceof q &&
          "callId" in p.rawItem &&
          p.rawItem.type === "function_call",
      )
      .map((p) => p.rawItem.callId),
    f = o.functions.filter((p) => i.includes(p.toolCall.callId)),
    c = await $r(t, f, s, a),
    l = c.map((p) => p.runItem),
    d = o.mcpApprovalRequests.filter(
      (p) =>
        p.requestItem.type === "tool_approval_item" &&
        p.requestItem.rawItem.type === "hosted_tool_call" &&
        p.requestItem.rawItem.providerData?.type === "mcp_approval_request",
    );
  for (const p of d) {
    const v = p.requestItem.rawItem.id,
      _ = a._context.isToolApproved({
        toolName: p.requestItem.rawItem.name,
        callId: v,
      });
    if (typeof _ < "u") {
      const T = { approve: _, approval_request_id: v, reason: void 0 };
      l.push(
        new me(
          {
            type: "hosted_tool_call",
            name: "mcp_approval_response",
            providerData: T,
          },
          t,
        ),
      );
    }
  }
  const m = await jr(t, c, a),
    y = n.filter((p) => !(p instanceof q));
  return m.isFinalOutput
    ? (s.emit("agent_end", a._context, t, m.finalOutput),
      t.emit("agent_end", a._context, m.finalOutput),
      new z(e, r, y, l, {
        type: "next_step_final_output",
        output: m.finalOutput,
      }))
    : m.isInterrupted
      ? new z(e, r, y, l, {
          type: "next_step_interruption",
          data: { interruptions: m.interruptions },
        })
      : new z(e, r, y, l, { type: "next_step_run_again" });
}
async function wn(t, e, n, r, o, s, a) {
  const i = n;
  let f = o.newItems;
  const [c, l] = await Promise.all([
    $r(t, o.functions, s, a),
    ri(t, o.computerActions, s, a._context),
  ]);
  if (
    ((f = f.concat(c.map((_) => _.runItem))),
    (f = f.concat(l)),
    o.mcpApprovalRequests.length > 0)
  )
    for (const _ of o.mcpApprovalRequests) {
      const T = _.mcpTool.providerData,
        b = _.requestItem.rawItem.providerData;
      if (T.on_approval) {
        const I = await T.on_approval(a._context, _.requestItem),
          E = {
            approve: I.approve,
            approval_request_id: b.id,
            reason: I.reason,
          };
        f.push(
          new me(
            {
              type: "hosted_tool_call",
              name: "mcp_approval_response",
              providerData: E,
            },
            t,
          ),
        );
      } else {
        f.push(_.requestItem);
        const I = {
          type: "hosted_mcp_tool_approval",
          tool: _.mcpTool,
          runItem: new q(
            {
              type: "hosted_tool_call",
              name: b.name,
              id: b.id,
              arguments: b.arguments,
              status: "in_progress",
              providerData: b,
            },
            t,
          ),
        };
        c.push(I);
      }
    }
  if (o.handoffs.length > 0)
    return await oi(t, e, i, f, r, o.handoffs, s, a._context);
  const d = await jr(t, c, a);
  if (d.isFinalOutput)
    return (
      s.emit("agent_end", a._context, t, d.finalOutput),
      t.emit("agent_end", a._context, d.finalOutput),
      new z(e, r, i, f, {
        type: "next_step_final_output",
        output: d.finalOutput,
      })
    );
  if (d.isInterrupted)
    return new z(e, r, i, f, {
      type: "next_step_interruption",
      data: { interruptions: d.interruptions },
    });
  if (
    (o.functions?.length ?? 0) > 0 ||
    (o.computerActions?.length ?? 0) > 0 ||
    (o.mcpApprovalRequests?.length ?? 0) > 0 ||
    (o.handoffs?.length ?? 0) > 0
  )
    return new z(e, r, i, f, { type: "next_step_run_again" });
  const y = f.filter((_) => _ instanceof ut),
    p = y.length > 0 ? hr(y[y.length - 1].rawItem) : void 0;
  if (typeof p > "u") return new z(e, r, i, f, { type: "next_step_run_again" });
  if (!c.some((_) => _.runItem instanceof q)) {
    if (t.outputType === "text")
      return new z(e, r, i, f, { type: "next_step_final_output", output: p });
    if (t.outputType !== "text" && p) {
      const { parser: _ } = Ct(t.outputType, "final_output"),
        [T] = await Ot(() => _(p));
      if (T)
        throw (
          Ie({ message: "Invalid output type", data: { error: String(T) } }),
          new B("Invalid output type")
        );
      return new z(e, r, i, f, { type: "next_step_final_output", output: p });
    }
  }
  return new z(e, r, i, f, { type: "next_step_run_again" });
}
function Xe(t, e) {
  const n = Ya(e);
  if (n) {
    const r = n.map(Xa);
    return {
      type: "function_call_result",
      name: t.name,
      callId: t.callId,
      status: "completed",
      output: r,
    };
  }
  return {
    type: "function_call_result",
    name: t.name,
    callId: t.callId,
    status: "completed",
    output: { type: "text", text: oe(e) },
  };
}
function Ya(t) {
  if (Array.isArray(t)) {
    const n = [];
    for (const r of t) {
      const o = bn(r);
      if (!o) return null;
      n.push(o);
    }
    return n;
  }
  const e = bn(t);
  return e ? [e] : null;
}
function bn(t) {
  if (!le(t)) return null;
  const e = t.type;
  if (e === "text" && typeof t.text == "string") {
    const n = { type: "text", text: t.text };
    return (le(t.providerData) && (n.providerData = t.providerData), n);
  }
  if (e === "image") {
    const n = { type: "image" };
    let r, o;
    const s = j(t.mediaType) ? t.mediaType : void 0,
      a = t.image;
    if (typeof a == "string" && a.length > 0) r = a;
    else if (le(a)) {
      const i = a,
        f = j(i.mediaType) ? i.mediaType : s;
      if (
        (j(i.url)
          ? (r = i.url)
          : (j(i.data) ||
              (i.data instanceof Uint8Array && i.data.length > 0)) &&
            (r = Je(i.data, f)),
        !r)
      ) {
        const c = (j(i.fileId) && i.fileId) || (j(i.id) && i.id) || void 0;
        c && (o = c);
      }
    }
    if (
      (!r &&
        typeof t.imageUrl == "string" &&
        t.imageUrl.length > 0 &&
        (r = t.imageUrl),
      !o &&
        typeof t.fileId == "string" &&
        t.fileId.length > 0 &&
        (o = t.fileId),
      !r && typeof t.data == "string" && t.data.length > 0
        ? (r = s ? Je(t.data, s) : t.data)
        : !r &&
          t.data instanceof Uint8Array &&
          t.data.length > 0 &&
          (r = Je(t.data, s)),
      typeof t.detail == "string" &&
        t.detail.length > 0 &&
        (n.detail = t.detail),
      r)
    )
      n.image = r;
    else if (o) n.image = { fileId: o };
    else return null;
    return (le(t.providerData) && (n.providerData = t.providerData), n);
  }
  if (e === "file") {
    const n = Qa(t);
    if (!n) return null;
    const r = { type: "file", file: n };
    return (le(t.providerData) && (r.providerData = t.providerData), r);
  }
  return null;
}
function Xa(t) {
  if (t.type === "text") {
    const n = { type: "input_text", text: t.text };
    return (t.providerData && (n.providerData = t.providerData), n);
  }
  if (t.type === "image") {
    const n = { type: "input_image" };
    if (
      (typeof t.detail == "string" &&
        t.detail.length > 0 &&
        (n.detail = t.detail),
      typeof t.image == "string" && t.image.length > 0)
    )
      n.image = t.image;
    else if (le(t.image)) {
      const r = t.image,
        o = j(r.mediaType) ? r.mediaType : void 0;
      if (j(r.url)) n.image = r.url;
      else if (j(r.data))
        n.image = o && !r.data.startsWith("data:") ? be(r.data, o) : r.data;
      else if (r.data instanceof Uint8Array && r.data.length > 0) {
        const s = Re(r.data);
        n.image = be(s, o);
      } else {
        const s = (j(r.fileId) && r.fileId) || (j(r.id) && r.id) || void 0;
        s && (n.image = { id: s });
      }
    }
    return (t.providerData && (n.providerData = t.providerData), n);
  }
  if (t.type === "file") {
    const n = { type: "input_file" },
      r = t.file;
    if (typeof r == "string") n.file = r;
    else if (r && typeof r == "object") {
      const o = r;
      if ("data" in o && o.data) {
        const s = o.mediaType ?? "text/plain";
        if (typeof o.data == "string") n.file = be(o.data, s);
        else {
          const a = Re(o.data);
          n.file = be(a, s);
        }
      } else if (typeof o.url == "string" && o.url.length > 0)
        n.file = { url: o.url };
      else {
        const s =
          (typeof o.id == "string" && o.id.length > 0 && o.id) ||
          (typeof o.fileId == "string" && o.fileId.length > 0
            ? o.fileId
            : void 0);
        s && (n.file = { id: s });
      }
      typeof o.filename == "string" &&
        o.filename.length > 0 &&
        (n.filename = o.filename);
    }
    return (t.providerData && (n.providerData = t.providerData), n);
  }
  return t;
}
function Qa(t) {
  const e = t.file;
  if (typeof e == "string" && e.length > 0) return e;
  const n = ei(e);
  if (n) return n;
  const r = ti(t);
  return r || null;
}
function ei(t) {
  if (!le(t)) return null;
  if ("data" in t && t.data !== void 0) {
    const n = t.data,
      r = typeof n == "string" && n.length > 0,
      o = n instanceof Uint8Array && n.length > 0;
    return (!r && !o) || !j(t.mediaType) || !j(t.filename)
      ? null
      : {
          data: typeof n == "string" ? n : new Uint8Array(n),
          mediaType: t.mediaType,
          filename: t.filename,
        };
  }
  if (j(t.url)) {
    const n = { url: t.url };
    return (j(t.filename) && (n.filename = t.filename), n);
  }
  const e = (j(t.id) && t.id) || (j(t.fileId) && t.fileId);
  if (e) {
    const n = { id: e };
    return (j(t.filename) && (n.filename = t.filename), n);
  }
  return null;
}
function ti(t) {
  const e =
      typeof t.filename == "string" && t.filename.length > 0
        ? t.filename
        : void 0,
    n =
      typeof t.mediaType == "string" && t.mediaType.length > 0
        ? t.mediaType
        : void 0;
  if (typeof t.fileData == "string" && t.fileData.length > 0)
    return !n || !e ? null : { data: t.fileData, mediaType: n, filename: e };
  if (t.fileData instanceof Uint8Array && t.fileData.length > 0)
    return !n || !e
      ? null
      : { data: new Uint8Array(t.fileData), mediaType: n, filename: e };
  if (typeof t.fileUrl == "string" && t.fileUrl.length > 0) {
    const r = { url: t.fileUrl };
    return (e && (r.filename = e), r);
  }
  if (typeof t.fileId == "string" && t.fileId.length > 0) {
    const r = { id: t.fileId };
    return (e && (r.filename = e), r);
  }
  return null;
}
function le(t) {
  return typeof t == "object" && t !== null;
}
function j(t) {
  return typeof t == "string" && t.length > 0;
}
function Je(t, e) {
  if (typeof t == "string") return e && !t.startsWith("data:") ? be(t, e) : t;
  const n = Re(t);
  return be(n, e);
}
function be(t, e) {
  return e ? `data:${e};base64,${t}` : t;
}
async function $r(t, e, n, r) {
  async function o(s) {
    let a = s.toolCall.arguments;
    if (
      (s.tool.parameters &&
        (he(s.tool.parameters)
          ? (a = s.tool.parameters.parse(a))
          : (a = JSON.parse(a))),
      await s.tool.needsApproval(r._context, a, s.toolCall.callId))
    ) {
      const f = r._context.isToolApproved({
        toolName: s.tool.name,
        callId: s.toolCall.callId,
      });
      if (f === !1)
        return hn(
          async (c) => {
            const l = "Tool execution was not approved.";
            return (
              c.setError({
                message: l,
                data: {
                  tool_name: s.tool.name,
                  error: `Tool execution for ${s.toolCall.callId} was manually rejected by user.`,
                },
              }),
              (c.spanData.output = l),
              {
                type: "function_output",
                tool: s.tool,
                output: l,
                runItem: new De(Xe(s.toolCall, l), t, l),
              }
            );
          },
          { data: { name: s.tool.name } },
        );
      if (f !== !0)
        return {
          type: "function_approval",
          tool: s.tool,
          runItem: new q(s.toolCall, t),
        };
    }
    return hn(
      async (f) => {
        n.config.traceIncludeSensitiveData &&
          (f.spanData.input = s.toolCall.arguments);
        try {
          (n.emit("agent_tool_start", r._context, t, s.tool, {
            toolCall: s.toolCall,
          }),
            t.emit("agent_tool_start", r._context, s.tool, {
              toolCall: s.toolCall,
            }));
          const c = await s.tool.invoke(r._context, s.toolCall.arguments, {
              toolCall: s.toolCall,
            }),
            l = oe(c);
          (n.emit("agent_tool_end", r._context, t, s.tool, l, {
            toolCall: s.toolCall,
          }),
            t.emit("agent_tool_end", r._context, s.tool, l, {
              toolCall: s.toolCall,
            }),
            n.config.traceIncludeSensitiveData && (f.spanData.output = l));
          const d = {
              type: "function_output",
              tool: s.tool,
              output: c,
              runItem: new De(Xe(s.toolCall, c), t, c),
            },
            m = wa(s.toolCall);
          if (m) {
            d.agentRunResult = m;
            const y = m.interruptions;
            y.length > 0 && (d.interruptions = y);
          }
          return d;
        } catch (c) {
          throw (
            f.setError({
              message: "Error running tool",
              data: { tool_name: s.tool.name, error: String(c) },
            }),
            c
          );
        }
      },
      { data: { name: s.tool.name } },
    );
  }
  try {
    return await Promise.all(e.map(o));
  } catch (s) {
    throw new ws(`Failed to run function tools: ${s}`, s, r);
  }
}
async function ni(t, e) {
  const n = e.action;
  let r;
  switch (n.type) {
    case "click":
      await t.click(n.x, n.y, n.button);
      break;
    case "double_click":
      await t.doubleClick(n.x, n.y);
      break;
    case "drag":
      await t.drag(n.path.map((o) => [o.x, o.y]));
      break;
    case "keypress":
      await t.keypress(n.keys);
      break;
    case "move":
      await t.move(n.x, n.y);
      break;
    case "screenshot":
      r = await t.screenshot();
      break;
    case "scroll":
      await t.scroll(n.x, n.y, n.scroll_x, n.scroll_y);
      break;
    case "type":
      await t.type(n.text);
      break;
    case "wait":
      await t.wait();
      break;
  }
  if (
    typeof r < "u" ||
    (typeof t.screenshot == "function" &&
      ((r = await t.screenshot()), typeof r < "u"))
  )
    return r;
  throw new Error("Computer does not implement screenshot()");
}
async function ri(t, e, n, r, o = void 0) {
  const s = o ?? S,
    a = [];
  for (const i of e) {
    const f = i.computer.computer,
      c = i.toolCall;
    (n.emit("agent_tool_start", r, t, i.computer, { toolCall: c }),
      typeof t.emit == "function" &&
        t.emit("agent_tool_start", r, i.computer, { toolCall: c }));
    let l;
    try {
      l = await ni(f, c);
    } catch (y) {
      (s.error("Failed to execute computer action:", y), (l = ""));
    }
    (n.emit("agent_tool_end", r, t, i.computer, l, { toolCall: c }),
      typeof t.emit == "function" &&
        t.emit("agent_tool_end", r, i.computer, l, { toolCall: c }));
    const d = l ? `data:image/png;base64,${l}` : "",
      m = {
        type: "computer_call_result",
        callId: c.callId,
        output: { type: "computer_screenshot", data: d },
      };
    a.push(new De(m, t, d));
  }
  return a;
}
async function oi(t, e, n, r, o, s, a, i) {
  if (((r = [...r]), s.length === 0))
    return (
      S.warn(
        "Incorrectly called executeHandoffCalls with no handoffs. This should not happen. Moving on.",
      ),
      new z(e, o, n, r, { type: "next_step_run_again" })
    );
  if (s.length > 1) {
    const c = "Multiple handoffs detected, ignoring this one.";
    for (let l = 1; l < s.length; l++)
      r.push(new De(Xe(s[l].toolCall, c), t, c));
  }
  const f = s[0];
  return $a(
    async (c) => {
      const l = f.handoff,
        d = await l.onInvokeHandoff(i, f.toolCall.arguments);
      if (((c.spanData.to_agent = d.name), s.length > 1)) {
        const y = s.map((p) => p.handoff.agentName);
        c.setError({
          message: "Multiple handoffs requested",
          data: { requested_agents: y },
        });
      }
      (r.push(new qt(Xe(f.toolCall, dr(d)), t, d)),
        a.emit("agent_handoff", i, t, d),
        t.emit("agent_handoff", i, d));
      const m = l.inputFilter ?? a.config.handoffInputFilter;
      if (m) {
        (S.debug("Filtering inputs for handoff"),
          typeof m != "function" &&
            c.setError({
              message: "Invalid input filter",
              data: { details: "not callable" },
            }));
        const y = {
            inputHistory: Array.isArray(e) ? [...e] : e,
            preHandoffItems: [...n],
            newItems: [...r],
            runContext: i,
          },
          p = m(y);
        ((e = p.inputHistory), (n = p.preHandoffItems), (r = p.newItems));
      }
      return new z(e, o, n, r, { type: "next_step_handoff", newAgent: d });
    },
    { data: { from_agent: t.name } },
  );
}
const Ge = { isFinalOutput: !1, isInterrupted: void 0 };
async function jr(t, e, n) {
  if (e.length === 0) return Ge;
  const r = [];
  for (const a of e)
    if (
      (a.runItem instanceof q && r.push(a.runItem),
      a.type === "function_output")
    ) {
      if (Array.isArray(a.interruptions)) r.push(...a.interruptions);
      else if (a.agentRunResult) {
        const i = a.agentRunResult.interruptions;
        i.length > 0 && r.push(...i);
      }
    }
  if (r.length > 0)
    return { isFinalOutput: !1, isInterrupted: !0, interruptions: r };
  if (t.toolUseBehavior === "run_llm_again") return Ge;
  const o = e[0];
  if (t.toolUseBehavior === "stop_on_first_tool")
    return o?.type === "function_output"
      ? { isFinalOutput: !0, isInterrupted: void 0, finalOutput: oe(o.output) }
      : Ge;
  const s = t.toolUseBehavior;
  if (typeof s == "object") {
    const a = e.find((i) => s.stopAtToolNames.includes(i.tool.name));
    return a?.type === "function_output"
      ? { isFinalOutput: !0, isInterrupted: void 0, finalOutput: oe(a.output) }
      : Ge;
  }
  if (typeof s == "function") return s(n._context, e);
  throw new k(`Invalid toolUseBehavior: ${s}`, n);
}
function si(t) {
  if (t instanceof ut) return "message_output_created";
  if (t instanceof Zt) return "handoff_requested";
  if (t instanceof qt) return "handoff_occurred";
  if (t instanceof me) return "tool_called";
  if (t instanceof De) return "tool_output";
  if (t instanceof zt) return "reasoning_item_created";
  if (t instanceof q) return "tool_approval_requested";
}
function Ur(t, e) {
  const n = si(e);
  if (!n) {
    S.warn("Unknown item type: ", e);
    return;
  }
  t._addItem(new Ka(n, e));
}
function ai(t, e) {
  for (const n of e) Ur(t, n);
}
function Sn(t, e, n) {
  const r = n?.skipItems;
  for (const o of e.newStepItems) r?.has(o) || Ur(t, o);
}
class Tn {
  #e = new Map();
  addToolUse(e, n) {
    this.#e.set(e, n);
  }
  hasUsedTools(e) {
    return this.#e.has(e);
  }
  toJSON() {
    return Object.fromEntries(
      Array.from(this.#e.entries()).map(([e, n]) => [e.name, n]),
    );
  }
}
const qe = "1.0",
  ii = g(qe),
  Y = h({ name: u() }),
  ui = h({
    object: g("trace.span"),
    id: u(),
    trace_id: u(),
    parent_id: u().nullable(),
    started_at: u().nullable(),
    ended_at: u().nullable(),
    error: h({ message: u(), data: P(u(), A()).optional() }).nullable(),
    span_data: P(u(), A()),
  }),
  Jr = ui.extend({ previous_span: To(() => Jr).optional() }),
  Gr = h({
    requests: w(),
    inputTokens: w(),
    outputTokens: w(),
    totalTokens: w(),
  }),
  In = h({
    usage: Gr,
    output: D(it),
    responseId: u().optional(),
    providerData: P(u(), A()).optional(),
  }),
  Br = G("type", [
    h({ type: g("message_output_item"), rawItem: $e, agent: Y }),
    h({ type: g("tool_call_item"), rawItem: Cr.or(xe), agent: Y }),
    h({ type: g("tool_call_output_item"), rawItem: Ye, agent: Y, output: u() }),
    h({ type: g("reasoning_item"), rawItem: at, agent: Y }),
    h({ type: g("handoff_call_item"), rawItem: Ae, agent: Y }),
    h({
      type: g("handoff_output_item"),
      rawItem: Ye,
      sourceAgent: Y,
      targetAgent: Y,
    }),
    h({ type: g("tool_approval_item"), rawItem: Ae.or(xe), agent: Y }),
  ]),
  ci = h({
    object: g("trace"),
    id: u(),
    workflow_name: u(),
    group_id: u().nullable(),
    metadata: P(u(), A()),
  }),
  li = h({
    newItems: D(Br),
    toolsUsed: D(u()),
    handoffs: D(h({ toolCall: A(), handoff: A() })),
    functions: D(h({ toolCall: A(), tool: A() })),
    computerActions: D(h({ toolCall: A(), computer: A() })),
    mcpApprovalRequests: D(
      h({
        requestItem: h({
          rawItem: h({
            type: g("hosted_tool_call"),
            name: u(),
            arguments: u().optional(),
            status: u().optional(),
            output: u().optional(),
            providerData: P(u(), A()).nullable().optional(),
          }),
        }),
        mcpTool: h({
          type: g("hosted_tool"),
          name: g("hosted_mcp"),
          providerData: P(u(), A()),
        }),
      }),
    ).optional(),
  }),
  zr = h({ tripwireTriggered: fe(), outputInfo: A() }),
  pi = h({ guardrail: h({ type: g("input"), name: u() }), output: zr }),
  di = h({
    guardrail: h({ type: g("output"), name: u() }),
    agentOutput: A(),
    agent: Y,
    output: zr,
  }),
  xn = h({
    $schemaVersion: ii,
    currentTurn: w(),
    currentAgent: Y,
    originalInput: u().or(D(Rr)),
    modelResponses: D(In),
    context: h({
      usage: Gr,
      approvals: P(
        u(),
        h({ approved: D(u()).or(fe()), rejected: D(u()).or(fe()) }),
      ),
      context: P(u(), A()),
    }),
    toolUseTracker: P(u(), D(u())),
    maxTurns: w(),
    currentAgentSpan: Jr.nullable().optional(),
    noActiveAgentRun: fe(),
    inputGuardrailResults: D(pi),
    outputGuardrailResults: D(di),
    currentStep: Va.optional(),
    lastModelResponse: In.optional(),
    generatedItems: D(Br),
    lastProcessedResponse: li.optional(),
    trace: ci.nullable(),
  });
class pe {
  _currentTurn = 0;
  _currentAgent;
  _originalInput;
  _modelResponses;
  _currentAgentSpan;
  _context;
  _toolUseTracker;
  _generatedItems;
  _maxTurns;
  _noActiveAgentRun = !0;
  _lastTurnResponse;
  _inputGuardrailResults;
  _outputGuardrailResults;
  _currentStep = void 0;
  _lastProcessedResponse = void 0;
  _trace = null;
  constructor(e, n, r, o) {
    ((this._context = e),
      (this._originalInput = structuredClone(n)),
      (this._modelResponses = []),
      (this._currentAgentSpan = void 0),
      (this._currentAgent = r),
      (this._toolUseTracker = new Tn()),
      (this._generatedItems = []),
      (this._maxTurns = o),
      (this._inputGuardrailResults = []),
      (this._outputGuardrailResults = []),
      (this._trace = Pe()));
  }
  get history() {
    return Ne(this._originalInput, this._generatedItems);
  }
  getInterruptions() {
    return this._currentStep?.type !== "next_step_interruption"
      ? []
      : this._currentStep.data.interruptions;
  }
  approve(e, n = { alwaysApprove: !1 }) {
    this._context.approveTool(e, n);
  }
  reject(e, n = { alwaysReject: !1 }) {
    this._context.rejectTool(e, n);
  }
  toJSON() {
    const e = {
        $schemaVersion: qe,
        currentTurn: this._currentTurn,
        currentAgent: { name: this._currentAgent.name },
        originalInput: this._originalInput,
        modelResponses: this._modelResponses.map((r) => ({
          usage: {
            requests: r.usage.requests,
            inputTokens: r.usage.inputTokens,
            outputTokens: r.usage.outputTokens,
            totalTokens: r.usage.totalTokens,
          },
          output: r.output,
          responseId: r.responseId,
          providerData: r.providerData,
        })),
        context: this._context.toJSON(),
        toolUseTracker: this._toolUseTracker.toJSON(),
        maxTurns: this._maxTurns,
        currentAgentSpan: this._currentAgentSpan?.toJSON(),
        noActiveAgentRun: this._noActiveAgentRun,
        inputGuardrailResults: this._inputGuardrailResults,
        outputGuardrailResults: this._outputGuardrailResults.map((r) => ({
          ...r,
          agent: r.agent.toJSON(),
        })),
        currentStep: this._currentStep,
        lastModelResponse: this._lastTurnResponse,
        generatedItems: this._generatedItems.map((r) => r.toJSON()),
        lastProcessedResponse: this._lastProcessedResponse,
        trace: this._trace ? this._trace.toJSON() : null,
      },
      n = xn.safeParse(e);
    if (!n.success)
      throw new vs(`Failed to serialize run state. ${n.error.message}`);
    return n.data;
  }
  toString() {
    return JSON.stringify(this.toJSON());
  }
  static async fromString(e, n) {
    const [r, o] = await Ot(() => JSON.parse(n));
    if (r)
      throw new k(
        `Failed to parse run state. ${r instanceof Error ? r.message : String(r)}`,
      );
    const s = o.$schemaVersion;
    if (!s) throw new k("Run state is missing schema version");
    if (s !== qe)
      throw new k(
        `Run state schema version ${s} is not supported. Please use version ${qe}`,
      );
    const a = xn.parse(JSON.parse(n)),
      i = fi(e),
      f = new we(a.context.context);
    f._rebuildApprovals(a.context.approvals);
    const c = i.get(a.currentAgent.name);
    if (!c) throw new k(`Agent ${a.currentAgent.name} not found`);
    const l = new pe(f, "", c, a.maxTurns);
    ((l._currentTurn = a.currentTurn), (l._toolUseTracker = new Tn()));
    for (const [d, m] of Object.entries(a.toolUseTracker))
      l._toolUseTracker.addToolUse(i.get(d), m);
    if (a.currentAgentSpan) {
      a.trace || S.warn("Trace is not set, skipping tracing setup");
      const d = $().createTrace({
        traceId: a.trace?.id,
        name: a.trace?.workflow_name,
        groupId: a.trace?.group_id ?? void 0,
        metadata: a.trace?.metadata,
      });
      ((l._currentAgentSpan = Zr(d, a.currentAgentSpan)), (l._trace = d));
    }
    return (
      (l._noActiveAgentRun = a.noActiveAgentRun),
      (l._inputGuardrailResults = a.inputGuardrailResults),
      (l._outputGuardrailResults = a.outputGuardrailResults.map((d) => ({
        ...d,
        agent: i.get(d.agent.name),
      }))),
      (l._currentStep = a.currentStep),
      (l._originalInput = a.originalInput),
      (l._modelResponses = a.modelResponses.map(An)),
      (l._lastTurnResponse = a.lastModelResponse
        ? An(a.lastModelResponse)
        : void 0),
      (l._generatedItems = a.generatedItems.map((d) => qr(d, i))),
      (l._lastProcessedResponse = a.lastProcessedResponse
        ? await mi(i, l._currentAgent, l._context, a.lastProcessedResponse)
        : void 0),
      a.currentStep?.type === "next_step_handoff" &&
        (l._currentStep = {
          type: "next_step_handoff",
          newAgent: i.get(a.currentStep.newAgent.name),
        }),
      l
    );
  }
}
function fi(t) {
  const e = new Map(),
    n = [t];
  for (; n.length > 0;) {
    const r = n.shift();
    if (!e.has(r.name)) {
      e.set(r.name, r);
      for (const o of r.handoffs)
        o instanceof te
          ? e.has(o.name) || n.push(o)
          : o.agent && (e.has(o.agent.name) || n.push(o.agent));
    }
  }
  return e;
}
function Zr(t, e) {
  const n = e.span_data,
    r = e.previous_span ? Zr(t, e.previous_span) : void 0,
    o = $().createSpan(
      {
        spanId: e.id,
        traceId: e.trace_id,
        parentId: e.parent_id ?? void 0,
        startedAt: e.started_at ?? void 0,
        endedAt: e.ended_at ?? void 0,
        data: n,
      },
      t,
    );
  return ((o.previousSpan = r), o);
}
function An(t) {
  const e = new ge();
  return (
    (e.requests = t.usage.requests),
    (e.inputTokens = t.usage.inputTokens),
    (e.outputTokens = t.usage.outputTokens),
    (e.totalTokens = t.usage.totalTokens),
    {
      usage: e,
      output: t.output.map((n) => it.parse(n)),
      responseId: t.responseId,
      providerData: t.providerData,
    }
  );
}
function qr(t, e) {
  switch (t.type) {
    case "message_output_item":
      return new ut(t.rawItem, e.get(t.agent.name));
    case "tool_call_item":
      return new me(t.rawItem, e.get(t.agent.name));
    case "tool_call_output_item":
      return new De(t.rawItem, e.get(t.agent.name), t.output);
    case "reasoning_item":
      return new zt(t.rawItem, e.get(t.agent.name));
    case "handoff_call_item":
      return new Zt(t.rawItem, e.get(t.agent.name));
    case "handoff_output_item":
      return new qt(
        t.rawItem,
        e.get(t.sourceAgent.name),
        e.get(t.targetAgent.name),
      );
    case "tool_approval_item":
      return new q(t.rawItem, e.get(t.agent.name));
  }
}
async function mi(t, e, n, r) {
  const o = await e.getAllTools(n),
    s = new Map(o.filter((c) => c.type === "function").map((c) => [c.name, c])),
    a = new Map(o.filter((c) => c.type === "computer").map((c) => [c.name, c])),
    i = new Map(
      e.handoffs.map((c) =>
        c instanceof te ? [c.name, mr(c)] : [c.toolName, c],
      ),
    ),
    f = {
      newItems: r.newItems.map((c) => qr(c, t)),
      toolsUsed: r.toolsUsed,
      handoffs: r.handoffs.map((c) => {
        if (!i.has(c.handoff.toolName))
          throw new k(`Handoff ${c.handoff.toolName} not found`);
        return { toolCall: c.toolCall, handoff: i.get(c.handoff.toolName) };
      }),
      functions: await Promise.all(
        r.functions.map(async (c) => {
          if (!s.has(c.tool.name)) throw new k(`Tool ${c.tool.name} not found`);
          return { toolCall: c.toolCall, tool: s.get(c.tool.name) };
        }),
      ),
      computerActions: r.computerActions.map((c) => {
        const l = c.computer.name;
        if (!a.has(l)) throw new k(`Computer tool ${l} not found`);
        return { toolCall: c.toolCall, computer: a.get(l) };
      }),
      mcpApprovalRequests: (r.mcpApprovalRequests ?? []).map((c) => ({
        requestItem: new q(c.requestItem.rawItem, e),
        mcpTool: c.mcpTool,
      })),
    };
  return {
    ...f,
    hasToolsOrApprovalsToRun() {
      return (
        f.handoffs.length > 0 ||
        f.functions.length > 0 ||
        f.mcpApprovalRequests.length > 0 ||
        f.computerActions.length > 0
      );
    },
  };
}
const Dn = 10;
function kn(t, e) {
  return t ? !1 : e ? !0 : "enabled_without_data";
}
function At(t) {
  return typeof t == "string"
    ? [{ type: "message", role: "user", content: t }]
    : [...t];
}
class En {
  conversationId;
  previousResponseId;
  sentInitialInput = !1;
  sentItems = new WeakSet();
  serverItems = new WeakSet();
  constructor({ conversationId: e, previousResponseId: n }) {
    ((this.conversationId = e ?? void 0),
      (this.previousResponseId = n ?? void 0));
  }
  primeFromState({ originalInput: e, generatedItems: n, modelResponses: r }) {
    if (this.sentInitialInput) return;
    for (const s of At(e)) s && typeof s == "object" && this.sentItems.add(s);
    this.sentInitialInput = !0;
    const o = r[r.length - 1];
    for (const s of r)
      for (const a of s.output)
        a && typeof a == "object" && this.serverItems.add(a);
    !this.conversationId &&
      o?.responseId &&
      (this.previousResponseId = o.responseId);
    for (const s of n) {
      const a = s.rawItem;
      !a ||
        typeof a != "object" ||
        (this.serverItems.has(a) && this.sentItems.add(a));
    }
  }
  trackServerItems(e) {
    if (e) {
      for (const n of e.output)
        n && typeof n == "object" && this.serverItems.add(n);
      !this.conversationId &&
        this.previousResponseId !== void 0 &&
        e.responseId &&
        (this.previousResponseId = e.responseId);
    }
  }
  prepareInput(e, n) {
    const r = [];
    if (!this.sentInitialInput) {
      const o = At(e);
      for (const s of o)
        (r.push(s), s && typeof s == "object" && this.sentItems.add(s));
      this.sentInitialInput = !0;
    }
    for (const o of n) {
      if (o.type === "tool_approval_item") continue;
      const s = o.rawItem;
      !s ||
        typeof s != "object" ||
        this.sentItems.has(s) ||
        this.serverItems.has(s) ||
        (r.push(s), this.sentItems.add(s));
    }
    return r;
  }
}
function Ne(t, e) {
  const n = e
    .filter((r) => r.type !== "tool_approval_item")
    .map((r) => r.rawItem);
  return [...At(t), ...n];
}
class Hr extends da {
  config;
  inputGuardrailDefs;
  outputGuardrailDefs;
  constructor(e = {}) {
    (super(),
      (this.config = {
        modelProvider: e.modelProvider ?? Ta(),
        model: e.model,
        modelSettings: e.modelSettings,
        handoffInputFilter: e.handoffInputFilter,
        inputGuardrails: e.inputGuardrails,
        outputGuardrails: e.outputGuardrails,
        tracingDisabled: e.tracingDisabled ?? !1,
        traceIncludeSensitiveData: e.traceIncludeSensitiveData ?? !0,
        workflowName: e.workflowName ?? "Agent workflow",
        traceId: e.traceId,
        groupId: e.groupId,
        traceMetadata: e.traceMetadata,
      }),
      (this.inputGuardrailDefs = (e.inputGuardrails ?? []).map(dn)),
      (this.outputGuardrailDefs = (e.outputGuardrails ?? []).map(Tt)));
  }
  async #e(e, n, r) {
    return Dt(async () => {
      const o = n instanceof pe,
        s = o
          ? n
          : new pe(
              r.context instanceof we ? r.context : new we(r.context),
              n,
              e,
              r.maxTurns ?? Dn,
            ),
        a =
          r.conversationId || r.previousResponseId
            ? new En({
                conversationId: r.conversationId,
                previousResponseId: r.previousResponseId,
              })
            : void 0;
      a &&
        o &&
        a.primeFromState({
          originalInput: s._originalInput,
          generatedItems: s._generatedItems,
          modelResponses: s._modelResponses,
        });
      try {
        for (;;) {
          const i =
            (s._currentAgent.model !== void 0 &&
              s._currentAgent.model !== "") ||
            (this.config.model !== void 0 && this.config.model !== "");
          let f = On(s._currentAgent.model, this.config.model);
          if (
            (typeof f == "string" &&
              (f = await this.config.modelProvider.getModel(f)),
            (s._currentStep = s._currentStep ?? {
              type: "next_step_run_again",
            }),
            s._currentStep.type === "next_step_interruption")
          ) {
            if (
              (S.debug("Continuing from interruption"),
              !s._lastTurnResponse || !s._lastProcessedResponse)
            )
              throw new k("No model response found in previous state", s);
            const c = await vn(
              s._currentAgent,
              s._originalInput,
              s._generatedItems,
              s._lastTurnResponse,
              s._lastProcessedResponse,
              this,
              s,
            );
            if (
              (s._toolUseTracker.addToolUse(
                s._currentAgent,
                s._lastProcessedResponse.toolsUsed,
              ),
              (s._originalInput = c.originalInput),
              (s._generatedItems = c.generatedItems),
              (s._currentStep = c.nextStep),
              c.nextStep.type === "next_step_interruption")
            )
              return new mt(s);
            continue;
          }
          if (s._currentStep.type === "next_step_run_again") {
            const c = await s._currentAgent.getEnabledHandoffs(s._context);
            if (!s._currentAgentSpan) {
              const E = c.map((U) => U.agentName);
              ((s._currentAgentSpan = xt({
                data: {
                  name: s._currentAgent.name,
                  handoffs: E,
                  output_type: s._currentAgent.outputSchemaName,
                },
              })),
                s._currentAgentSpan.start(),
                Te(s._currentAgentSpan));
            }
            const l = await s._currentAgent.getAllTools(s._context),
              d = l.map((E) => fn(E)),
              m = c.map((E) => mn(E));
            if (
              (s._currentAgentSpan &&
                (s._currentAgentSpan.spanData.tools = l.map((E) => E.name)),
              s._currentTurn++,
              s._currentTurn > s._maxTurns)
            )
              throw (
                s._currentAgentSpan?.setError({
                  message: "Max turns exceeded",
                  data: { max_turns: s._maxTurns },
                }),
                new en(`Max turns (${s._maxTurns}) exceeded`, s)
              );
            (S.debug(
              `Running agent ${s._currentAgent.name} (turn ${s._currentTurn})`,
            ),
              s._currentTurn === 1 && (await this.#t(s)));
            const y = a
              ? a.prepareInput(s._originalInput, s._generatedItems)
              : Ne(s._originalInput, s._generatedItems);
            s._noActiveAgentRun &&
              (s._currentAgent.emit("agent_start", s._context, s._currentAgent),
              this.emit("agent_start", s._context, s._currentAgent));
            let p = {
              ...this.config.modelSettings,
              ...s._currentAgent.modelSettings,
            };
            const v = s._currentAgent.modelSettings;
            ((p = Cn(i, v, f, p)),
              (p = _n(s._currentAgent, s._toolUseTracker, p)));
            const _ = a?.previousResponseId ?? r.previousResponseId,
              T = a?.conversationId ?? r.conversationId;
            ((s._lastTurnResponse = await f.getResponse({
              systemInstructions: await s._currentAgent.getSystemPrompt(
                s._context,
              ),
              prompt: await s._currentAgent.getPrompt(s._context),
              ...(i ? { overridePromptModel: !0 } : {}),
              input: y,
              previousResponseId: _,
              conversationId: T,
              modelSettings: p,
              tools: d,
              outputType: on(s._currentAgent.outputType),
              handoffs: m,
              tracing: kn(
                this.config.tracingDisabled,
                this.config.traceIncludeSensitiveData,
              ),
              signal: r.signal,
            })),
              s._modelResponses.push(s._lastTurnResponse),
              s._context.usage.add(s._lastTurnResponse.usage),
              (s._noActiveAgentRun = !1),
              a?.trackServerItems(s._lastTurnResponse));
            const b = yn(s._lastTurnResponse, s._currentAgent, l, c);
            s._lastProcessedResponse = b;
            const I = await wn(
              s._currentAgent,
              s._originalInput,
              s._generatedItems,
              s._lastTurnResponse,
              s._lastProcessedResponse,
              this,
              s,
            );
            (s._toolUseTracker.addToolUse(
              s._currentAgent,
              s._lastProcessedResponse.toolsUsed,
            ),
              (s._originalInput = I.originalInput),
              (s._generatedItems = I.generatedItems),
              (s._currentStep = I.nextStep));
          }
          if (
            s._currentStep &&
            s._currentStep.type === "next_step_final_output"
          )
            return (
              await this.#n(s, s._currentStep.output),
              this.emit(
                "agent_end",
                s._context,
                s._currentAgent,
                s._currentStep.output,
              ),
              s._currentAgent.emit(
                "agent_end",
                s._context,
                s._currentStep.output,
              ),
              new mt(s)
            );
          if (s._currentStep && s._currentStep.type === "next_step_handoff")
            ((s._currentAgent = s._currentStep.newAgent),
              s._currentAgentSpan &&
                (s._currentAgentSpan.end(),
                de(),
                (s._currentAgentSpan = void 0)),
              (s._noActiveAgentRun = !0),
              (s._currentStep = { type: "next_step_run_again" }));
          else {
            if (
              s._currentStep &&
              s._currentStep.type === "next_step_interruption"
            )
              return new mt(s);
            S.debug("Running next loop");
          }
        }
      } catch (i) {
        throw (
          s._currentAgentSpan &&
            s._currentAgentSpan.setError({
              message: "Error in agent run",
              data: { error: String(i) },
            }),
          i
        );
      } finally {
        s._currentAgentSpan &&
          (s._currentStep?.type !== "next_step_interruption" &&
            s._currentAgentSpan.end(),
          de());
      }
    });
  }
  async #t(e) {
    const n = this.inputGuardrailDefs.concat(
      e._currentAgent.inputGuardrails.map(dn),
    );
    if (n.length > 0) {
      const r = {
        agent: e._currentAgent,
        input: e._originalInput,
        context: e._context,
      };
      try {
        const o = await Promise.all(
          n.map(async (s) =>
            gn(
              async (a) => {
                const i = await s.run(r);
                return ((a.spanData.triggered = i.output.tripwireTriggered), i);
              },
              { data: { name: s.name } },
              e._currentAgentSpan,
            ),
          ),
        );
        for (const s of o)
          if (s.output.tripwireTriggered)
            throw (
              e._currentAgentSpan &&
                e._currentAgentSpan.setError({
                  message: "Guardrail tripwire triggered",
                  data: { guardrail: s.guardrail.name },
                }),
              new nn(
                `Input guardrail triggered: ${JSON.stringify(s.output.outputInfo)}`,
                s,
                e,
              )
            );
      } catch (o) {
        throw o instanceof nn
          ? o
          : (e._currentTurn--,
            new tn(`Input guardrail failed to complete: ${o}`, o, e));
      }
    }
  }
  async #n(e, n) {
    const r = this.outputGuardrailDefs.concat(
      e._currentAgent.outputGuardrails.map(Tt),
    );
    if (r.length > 0) {
      const o = e._currentAgent.processFinalOutput(n),
        s = {
          agent: e._currentAgent,
          agentOutput: o,
          context: e._context,
          details: { modelResponse: e._lastTurnResponse },
        };
      try {
        const a = await Promise.all(
          r.map(async (i) =>
            gn(
              async (f) => {
                const c = await i.run(s);
                return ((f.spanData.triggered = c.output.tripwireTriggered), c);
              },
              { data: { name: i.name } },
              e._currentAgentSpan,
            ),
          ),
        );
        for (const i of a)
          if (i.output.tripwireTriggered)
            throw (
              e._currentAgentSpan &&
                e._currentAgentSpan.setError({
                  message: "Guardrail tripwire triggered",
                  data: { guardrail: i.guardrail.name },
                }),
              new Ke(
                `Output guardrail triggered: ${JSON.stringify(i.output.outputInfo)}`,
                i,
                e,
              )
            );
      } catch (a) {
        throw a instanceof Ke
          ? a
          : new tn(`Output guardrail failed to complete: ${a}`, a, e);
      }
    }
  }
  async #r(e, n, r) {
    const o =
      n.conversationId || n.previousResponseId
        ? new En({
            conversationId: n.conversationId,
            previousResponseId: n.previousResponseId,
          })
        : void 0;
    o &&
      r &&
      o.primeFromState({
        originalInput: e.state._originalInput,
        generatedItems: e.state._generatedItems,
        modelResponses: e.state._modelResponses,
      });
    try {
      for (;;) {
        const s = e.state._currentAgent,
          a = await s.getEnabledHandoffs(e.state._context),
          i = await s.getAllTools(e.state._context),
          f = i.map((l) => fn(l)),
          c = a.map((l) => mn(l));
        if (
          ((e.state._currentStep = e.state._currentStep ?? {
            type: "next_step_run_again",
          }),
          e.state._currentStep.type === "next_step_interruption")
        ) {
          if (
            (S.debug("Continuing from interruption"),
            !e.state._lastTurnResponse || !e.state._lastProcessedResponse)
          )
            throw new k("No model response found in previous state", e.state);
          const l = await vn(
            e.state._currentAgent,
            e.state._originalInput,
            e.state._generatedItems,
            e.state._lastTurnResponse,
            e.state._lastProcessedResponse,
            this,
            e.state,
          );
          if (
            (Sn(e, l),
            e.state._toolUseTracker.addToolUse(
              e.state._currentAgent,
              e.state._lastProcessedResponse.toolsUsed,
            ),
            (e.state._originalInput = l.originalInput),
            (e.state._generatedItems = l.generatedItems),
            (e.state._currentStep = l.nextStep),
            l.nextStep.type === "next_step_interruption")
          )
            return;
          continue;
        }
        if (e.state._currentStep.type === "next_step_run_again") {
          if (!e.state._currentAgentSpan) {
            const U = a.map((ne) => ne.agentName);
            ((e.state._currentAgentSpan = xt({
              data: {
                name: s.name,
                handoffs: U,
                tools: i.map((ne) => ne.name),
                output_type: s.outputSchemaName,
              },
            })),
              e.state._currentAgentSpan.start(),
              Te(e.state._currentAgentSpan));
          }
          if (
            (e.state._currentTurn++, e.state._currentTurn > e.state._maxTurns)
          )
            throw (
              e.state._currentAgentSpan?.setError({
                message: "Max turns exceeded",
                data: { max_turns: e.state._maxTurns },
              }),
              new en(`Max turns (${e.state._maxTurns}) exceeded`, e.state)
            );
          S.debug(`Running agent ${s.name} (turn ${e.state._currentTurn})`);
          const l =
            (s.model !== void 0 && s.model !== "") ||
            (this.config.model !== void 0 && this.config.model !== "");
          let d = On(s.model, this.config.model);
          (typeof d == "string" &&
            (d = await this.config.modelProvider.getModel(d)),
            e.state._currentTurn === 1 && (await this.#t(e.state)));
          let m = { ...this.config.modelSettings, ...s.modelSettings };
          const y = s.modelSettings;
          ((m = Cn(l, y, d, m)), (m = _n(s, e.state._toolUseTracker, m)));
          const p = o
            ? o.prepareInput(e.input, e.newItems)
            : Ne(e.input, e.newItems);
          e.state._noActiveAgentRun &&
            (s.emit("agent_start", e.state._context, s),
            this.emit("agent_start", e.state._context, s));
          let v;
          const _ = o?.previousResponseId ?? n.previousResponseId,
            T = o?.conversationId ?? n.conversationId;
          for await (const U of d.getStreamedResponse({
            systemInstructions: await s.getSystemPrompt(e.state._context),
            prompt: await s.getPrompt(e.state._context),
            ...(l ? { overridePromptModel: !0 } : {}),
            input: p,
            previousResponseId: _,
            conversationId: T,
            modelSettings: m,
            tools: f,
            handoffs: c,
            outputType: on(s.outputType),
            tracing: kn(
              this.config.tracingDisabled,
              this.config.traceIncludeSensitiveData,
            ),
            signal: n.signal,
          })) {
            if (U.type === "response_done") {
              const ne = Bt.parse(U);
              v = {
                usage: new ge(ne.response.usage),
                output: ne.response.output,
                responseId: ne.response.id,
              };
            }
            if (e.cancelled) return;
            e._addItem(new Ha(U));
          }
          if (((e.state._noActiveAgentRun = !1), !v))
            throw new B("Model did not produce a final response!", e.state);
          ((e.state._lastTurnResponse = v),
            o?.trackServerItems(v),
            e.state._modelResponses.push(e.state._lastTurnResponse));
          const b = yn(e.state._lastTurnResponse, s, i, a);
          e.state._lastProcessedResponse = b;
          const I = new Set(b.newItems);
          I.size > 0 && ai(e, b.newItems);
          const E = await wn(
            s,
            e.state._originalInput,
            e.state._generatedItems,
            e.state._lastTurnResponse,
            e.state._lastProcessedResponse,
            this,
            e.state,
          );
          (Sn(e, E, { skipItems: I }),
            e.state._toolUseTracker.addToolUse(s, b.toolsUsed),
            (e.state._originalInput = E.originalInput),
            (e.state._generatedItems = E.generatedItems),
            (e.state._currentStep = E.nextStep));
        }
        if (e.state._currentStep.type === "next_step_final_output") {
          (await this.#n(e.state, e.state._currentStep.output),
            this.emit(
              "agent_end",
              e.state._context,
              s,
              e.state._currentStep.output,
            ),
            s.emit("agent_end", e.state._context, e.state._currentStep.output));
          return;
        } else {
          if (e.state._currentStep.type === "next_step_interruption") return;
          e.state._currentStep.type === "next_step_handoff"
            ? ((e.state._currentAgent = e.state._currentStep?.newAgent),
              e.state._currentAgentSpan &&
                (e.state._currentAgentSpan.end(), de()),
              (e.state._currentAgentSpan = void 0),
              e._addItem(new Wa(e.state._currentAgent)),
              (e.state._noActiveAgentRun = !0),
              (e.state._currentStep = { type: "next_step_run_again" }))
            : S.debug("Running next loop");
        }
      }
    } catch (s) {
      throw (
        e.state._currentAgentSpan &&
          e.state._currentAgentSpan.setError({
            message: "Error in agent run",
            data: { error: String(s) },
          }),
        s
      );
    } finally {
      e.state._currentAgentSpan &&
        (e.state._currentStep?.type !== "next_step_interruption" &&
          e.state._currentAgentSpan.end(),
        de());
    }
  }
  async #a(e, n, r) {
    return (
      (r = r ?? {}),
      Dt(async () => {
        const o = n instanceof pe,
          s = o
            ? n
            : new pe(
                r.context instanceof we ? r.context : new we(r.context),
                n,
                e,
                r.maxTurns ?? Dn,
              ),
          a = new Wr({ signal: r.signal, state: s });
        a.maxTurns = r.maxTurns ?? s._maxTurns;
        const i = this.#r(a, r, o).then(
          () => {
            a._done();
          },
          (f) => {
            a._raiseError(f);
          },
        );
        return (a._setStreamLoopPromise(i), a);
      })
    );
  }
  run(e, n, r = { stream: !1, context: void 0 }) {
    return n instanceof pe && n._trace
      ? gi(
          n._trace,
          async () => (
            n._currentAgentSpan && Te(n._currentAgentSpan),
            r?.stream ? this.#a(e, n, r) : this.#e(e, n, r)
          ),
        )
      : yi(async () => (r?.stream ? this.#a(e, n, r) : this.#e(e, n, r)), {
          traceId: this.config.traceId,
          name: this.config.workflowName,
          groupId: this.config.groupId,
          metadata: this.config.traceMetadata,
        });
  }
}
let Be;
function hi() {
  return Be || ((Be = new Hr()), Be);
}
function On(t, e) {
  return (typeof t == "string" && t !== te.DEFAULT_MODEL_PLACEHOLDER) || t
    ? t
    : (e ?? t ?? te.DEFAULT_MODEL_PLACEHOLDER);
}
async function cl(t, e, n) {
  const r = hi();
  return n?.stream ? await r.run(t, e, n) : await r.run(t, e, n);
}
function Cn(t, e, n, r) {
  if (
    pr() &&
    t &&
    (typeof n != "string" || !rt(n)) &&
    (e.providerData?.reasoning ||
      e.providerData?.text?.verbosity ||
      e.providerData?.reasoning_effort)
  ) {
    const o = { ...r };
    return (
      delete o.providerData?.reasoning,
      delete o.providerData?.text?.verbosity,
      delete o.providerData?.reasoning_effort,
      o.reasoning && (delete o.reasoning.effort, delete o.reasoning.summary),
      o.text && delete o.text.verbosity,
      o
    );
  }
  return r;
}
class Kr {
  state;
  constructor(e) {
    this.state = e;
  }
  get history() {
    return Ne(this.input, this.newItems);
  }
  get output() {
    return Ne([], this.newItems);
  }
  get input() {
    return this.state._originalInput;
  }
  get newItems() {
    return this.state._generatedItems;
  }
  get rawResponses() {
    return this.state._modelResponses;
  }
  get lastResponseId() {
    const e = this.rawResponses;
    return e && e.length > 0 ? e[e.length - 1].responseId : void 0;
  }
  get lastAgent() {
    return this.state._currentAgent;
  }
  get inputGuardrailResults() {
    return this.state._inputGuardrailResults;
  }
  get outputGuardrailResults() {
    return this.state._outputGuardrailResults;
  }
  get interruptions() {
    return this.state._currentStep?.type === "next_step_interruption"
      ? this.state._currentStep.data.interruptions
      : [];
  }
  get finalOutput() {
    if (this.state._currentStep?.type === "next_step_final_output")
      return this.state._currentAgent.processFinalOutput(
        this.state._currentStep.output,
      );
    S.warn("Accessed finalOutput before agent run is completed.");
  }
}
class mt extends Kr {
  constructor(e) {
    super(e);
  }
}
class Wr extends Kr {
  get currentAgent() {
    return this.lastAgent;
  }
  currentTurn = 0;
  maxTurns;
  #e = null;
  #t;
  #n;
  #r;
  #a;
  #s;
  #i;
  #o = !1;
  #u;
  constructor(e = {}) {
    if (
      (super(e.state),
      (this.#t = e.signal),
      (this.#r = new aa({
        start: (n) => {
          this.#n = n;
        },
        cancel: () => {
          this.#o = !0;
        },
      })),
      (this.#a = new Promise((n, r) => {
        ((this.#s = n), (this.#i = r));
      })),
      this.#t)
    ) {
      const n = () => {
        if (this.#o) return;
        this.#o = !0;
        const r = this.#n;
        if (((this.#n = void 0), this.#r.locked)) {
          if (r)
            try {
              r.close();
            } catch (o) {
              S.debug(`Failed to close readable stream on abort: ${o}`);
            }
        } else
          this.#r.cancel(this.#t?.reason).catch((o) => {
            S.debug(`Failed to cancel readable stream on abort: ${o}`);
          });
        this.#s?.();
      };
      this.#t.aborted
        ? n()
        : this.#t.addEventListener("abort", n, { once: !0 });
    }
  }
  _addItem(e) {
    this.cancelled || this.#n?.enqueue(e);
  }
  _done() {
    !this.cancelled &&
      this.#n &&
      (this.#n.close(), (this.#n = void 0), this.#s?.());
  }
  _raiseError(e) {
    (!this.cancelled && this.#n && (this.#n.error(e), (this.#n = void 0)),
      (this.#e = e),
      this.#i?.(e),
      this.#a.catch((n) => {
        S.debug(`Resulted in an error: ${n}`);
      }));
  }
  get cancelled() {
    return this.#o;
  }
  toStream() {
    return this.#r;
  }
  get completed() {
    return this.#a;
  }
  get error() {
    return this.#e;
  }
  toTextStream(e = {}) {
    const n = this.#r.pipeThrough(
      new ia({
        transform(r, o) {
          if (
            r.type === "raw_model_stream_event" &&
            r.data.type === "output_text_delta"
          ) {
            const s = Gt.parse(r.data);
            o.enqueue(s.delta);
          }
        },
      }),
    );
    return e.compatibleWithNodeStreams ? sa.fromWeb(n) : n;
  }
  [Symbol.asyncIterator]() {
    return this.#r[Symbol.asyncIterator]();
  }
  _setStreamLoopPromise(e) {
    this.#u = e;
  }
  _getStreamLoopPromise() {
    return this.#u;
  }
}
let Rn;
function Q() {
  return ((Rn ??= new ua()), Rn);
}
function Pe() {
  const t = Q().getStore();
  return t?.trace ? t.trace : null;
}
function Me() {
  const t = Q().getStore();
  return t?.span ? t.span : null;
}
function Vr(t) {
  return async () => {
    const e = Pe();
    if (!e) throw new Error("No trace found");
    await e.start();
    const n = await t(e);
    if (n instanceof Wr) {
      const r = n._getStreamLoopPromise();
      if (r) return (r.finally(() => e.end()), n);
    }
    return (await e.end(), n);
  };
}
async function gi(t, e, n = {}) {
  const r = typeof t == "string" ? $().createTrace({ ...n, name: t }) : t;
  return Q().run({ trace: r }, Vr(e));
}
async function yi(t, e = {}) {
  if (Pe()) return await t();
  const r = $().createTrace(e);
  return Q().run({ trace: r }, Vr(t));
}
function Te(t) {
  const e = Q().getStore();
  if (!e) throw new Error("No existing trace found");
  (e.span &&
    ((e.span.previousSpan = e.previousSpan), (e.previousSpan = e.span)),
    (e.span = t),
    Q().enterWith(e));
}
function de() {
  const t = Q().getStore();
  t &&
    ((t.span = t.previousSpan),
    (t.previousSpan = t.previousSpan?.previousSpan),
    Q().enterWith(t));
}
function Ie(t) {
  const e = Me();
  e && e.setError(t);
}
function _i(t) {
  return {
    trace: t.trace?.clone(),
    span: t.span?.clone(),
    previousSpan: t.previousSpan?.clone(),
  };
}
function Dt(t) {
  const e = Q().getStore();
  if (!e) throw new Error("No existing trace found");
  const n = _i(e);
  return Q().run(n, t);
}
class vi {
  async export(e) {
    if (or.disabled) {
      S.debug("Tracing is disabled. Skipping export");
      return;
    }
    for (const n of e)
      n.type === "trace"
        ? console.log(
            `[Exporter] Export trace traceId=${n.traceId} name=${n.name}${n.groupId ? ` groupId=${n.groupId}` : ""}`,
          )
        : console.log(`[Exporter] Export span: ${JSON.stringify(n)}`);
  }
}
class Yr {
  #e;
  #t;
  #n;
  #r;
  #a;
  #s = [];
  #i;
  #o = null;
  #u = !1;
  #p = null;
  constructor(
    e,
    {
      maxQueueSize: n = 1e3,
      maxBatchSize: r = 100,
      scheduleDelay: o = 5e3,
      exportTriggerRatio: s = 0.8,
    } = {},
  ) {
    ((this.#e = n),
      (this.#t = r),
      (this.#n = o),
      (this.#r = n * s),
      (this.#a = e),
      (this.#i = la),
      S.debug(
        "Automatic trace export loop is not supported in this environment. You need to manually call `getGlobalTraceProvider().forceFlush()` to export traces.",
      ));
  }
  start() {
    ((this.#p = new AbortController()), this.#d());
  }
  async #c(e) {
    if (this.#s.length + 1 > this.#e) {
      S.error("Dropping trace because buffer is full");
      return;
    }
    (this.#s.push(e), this.#s.length > this.#r && (await this.#l()));
  }
  #d() {
    ((this.#o = this.#i.setTimeout(async () => {
      (await this.#l(), this.#d());
    }, this.#n)),
      typeof this.#o.unref == "function" && this.#o.unref());
  }
  async #l(e = !1) {
    if (this.#s.length !== 0) {
      if (
        (S.debug(
          `Exporting batches. Force: ${e}. Buffer size: ${this.#s.length}`,
        ),
        e || this.#s.length < this.#t)
      ) {
        const n = [...this.#s];
        ((this.#s = []),
          (this.#u = !0),
          await this.#a.export(n),
          (this.#u = !1));
      } else if (this.#s.length > 0) {
        const n = this.#s.splice(0, this.#t);
        ((this.#u = !0), await this.#a.export(n), (this.#u = !1));
      }
    }
  }
  async onTraceStart(e) {
    await this.#c(e);
  }
  async onTraceEnd(e) {}
  async onSpanStart(e) {}
  async onSpanEnd(e) {
    await this.#c(e);
  }
  async shutdown(e) {
    for (
      e &&
        this.#i.setTimeout(() => {
          this.#p?.abort();
        }, e),
        S.debug("Shutting down gracefully");
      this.#s.length > 0;
    ) {
      if (
        (S.debug(`Waiting for buffer to empty. Items left: ${this.#s.length}`),
        this.#u || (await this.#l(!0)),
        this.#p?.signal.aborted)
      ) {
        (S.debug("Timeout reached, force flushing"), await this.#l(!0));
        break;
      }
      await new Promise((n) => this.#i.setTimeout(n, 500));
    }
    (S.debug("Buffer empty. Exiting"),
      this.#i && this.#o && this.#i.clearTimeout(this.#o));
  }
  async forceFlush() {
    this.#s.length > 0 && (await this.#l(!0));
  }
}
class wi {
  #e = [];
  start() {
    for (const e of this.#e) e.start && e.start();
  }
  addTraceProcessor(e) {
    this.#e.push(e);
  }
  setProcessors(e) {
    S.debug("Shutting down old processors");
    for (const n of this.#e) n.shutdown();
    this.#e = e;
  }
  async onTraceStart(e) {
    for (const n of this.#e) await n.onTraceStart(e);
  }
  async onTraceEnd(e) {
    for (const n of this.#e) await n.onTraceEnd(e);
  }
  async onSpanStart(e) {
    for (const n of this.#e) await n.onSpanStart(e);
  }
  async onSpanEnd(e) {
    for (const n of this.#e) await n.onSpanEnd(e);
  }
  async shutdown(e) {
    for (const n of this.#e) await n.shutdown(e);
  }
  async forceFlush() {
    for (const e of this.#e) await e.forceFlush();
  }
}
let ht = null,
  gt = null;
function bi() {
  return (ht || (ht = new vi()), ht);
}
function Xr() {
  return (gt || (gt = new Yr(bi())), gt);
}
function Nn() {
  return new Date().toISOString();
}
function Qr() {
  return `trace_${Nt().replace(/-/g, "")}`;
}
function Si() {
  return `span_${Nt().replace(/-/g, "").slice(0, 24)}`;
}
function ll() {
  return `group_${Nt().replace(/-/g, "").slice(0, 24)}`;
}
function Ti(t) {
  return Object.fromEntries(
    Object.entries(t).filter(([e]) => !e.startsWith("_")),
  );
}
class Fe {
  type = "trace.span";
  #e;
  #t;
  #n;
  #r;
  #a;
  #s;
  #i;
  #o;
  #u;
  constructor(e, n) {
    ((this.#t = e.traceId),
      (this.#n = e.spanId ?? Si()),
      (this.#e = e.data),
      (this.#a = n),
      (this.#r = e.parentId ?? null),
      (this.#o = e.error ?? null),
      (this.#s = e.startedAt ?? null),
      (this.#i = e.endedAt ?? null));
  }
  get traceId() {
    return this.#t;
  }
  get spanData() {
    return this.#e;
  }
  get spanId() {
    return this.#n;
  }
  get parentId() {
    return this.#r;
  }
  get previousSpan() {
    return this.#u;
  }
  set previousSpan(e) {
    this.#u = e;
  }
  start() {
    if (this.#s) {
      S.warn("Span already started");
      return;
    }
    ((this.#s = Nn()), this.#a.onSpanStart(this));
  }
  end() {
    if (this.#i) {
      S.debug("Span already finished", this.spanData);
      return;
    }
    ((this.#i = Nn()), this.#a.onSpanEnd(this));
  }
  setError(e) {
    this.#o = e;
  }
  get error() {
    return this.#o;
  }
  get startedAt() {
    return this.#s;
  }
  get endedAt() {
    return this.#i;
  }
  clone() {
    const e = new Fe(
      {
        traceId: this.traceId,
        spanId: this.spanId,
        parentId: this.parentId ?? void 0,
        data: this.spanData,
        startedAt: this.#s ?? void 0,
        endedAt: this.#i ?? void 0,
        error: this.#o ?? void 0,
      },
      this.#a,
    );
    return ((e.previousSpan = this.previousSpan?.clone()), e);
  }
  toJSON() {
    return {
      object: this.type,
      id: this.spanId,
      trace_id: this.traceId,
      parent_id: this.parentId,
      started_at: this.startedAt,
      ended_at: this.endedAt,
      span_data: Ti(this.spanData),
      error: this.error,
    };
  }
}
class re extends Fe {
  constructor(e, n) {
    super({ traceId: "no-op", spanId: "no-op", data: e }, n);
  }
  start() {}
  end() {}
  setError() {}
  toJSON() {
    return null;
  }
}
class Le {
  type = "trace";
  traceId;
  name;
  groupId = null;
  metadata;
  #e;
  #t;
  constructor(e, n) {
    ((this.traceId = e.traceId ?? Qr()),
      (this.name = e.name ?? "Agent workflow"),
      (this.groupId = e.groupId ?? null),
      (this.metadata = e.metadata ?? {}),
      (this.#e = n ?? Xr()),
      (this.#t = e.started ?? !1));
  }
  async start() {
    this.#t || ((this.#t = !0), await this.#e.onTraceStart(this));
  }
  async end() {
    this.#t && ((this.#t = !1), await this.#e.onTraceEnd(this));
  }
  clone() {
    return new Le({
      traceId: this.traceId,
      name: this.name,
      groupId: this.groupId ?? void 0,
      metadata: this.metadata,
      started: this.#t,
    });
  }
  toJSON() {
    return {
      object: this.type,
      id: this.traceId,
      workflow_name: this.name,
      group_id: this.groupId,
      metadata: this.metadata,
    };
  }
}
class yt extends Le {
  constructor() {
    super({});
  }
  async start() {}
  async end() {}
  toJSON() {
    return null;
  }
}
class Ii {
  #e;
  #t;
  constructor() {
    ((this.#e = new wi()), (this.#t = or.disabled), this.#n());
  }
  registerProcessor(e) {
    this.#e.addTraceProcessor(e);
  }
  setProcessors(e) {
    this.#e.setProcessors(e);
  }
  getCurrentTrace() {
    return Pe();
  }
  getCurrentSpan() {
    return Me();
  }
  setDisabled(e) {
    this.#t = e;
  }
  startExportLoop() {
    this.#e.start();
  }
  createTrace(e) {
    if (this.#t)
      return (
        S.debug("Tracing is disabled, Not creating trace %o", e),
        new yt()
      );
    const n = e.traceId ?? Qr(),
      r = e.name ?? "Agent workflow";
    return (
      S.debug("Creating trace %s with name %s", n, r),
      new Le({ ...e, name: r, traceId: n }, this.#e)
    );
  }
  createSpan(e, n) {
    if (this.#t || e.disabled)
      return (
        S.debug("Tracing is disabled, Not creating span %o", e),
        new re(e.data, this.#e)
      );
    let r, o;
    if (n) {
      if (n instanceof Le) {
        if (n instanceof yt)
          return (
            S.debug("Parent trace is no-op, returning NoopSpan"),
            new re(e.data, this.#e)
          );
        o = n.traceId;
      } else if (n instanceof Fe) {
        if (n instanceof re)
          return (
            S.debug("Parent span is no-op, returning NoopSpan"),
            new re(e.data, this.#e)
          );
        ((r = n.spanId), (o = n.traceId));
      }
    } else {
      const s = Pe(),
        a = Me();
      if (!s)
        return (
          S.error(
            "No active trace. Make sure to start a trace with `withTrace()` first. Returning NoopSpan.",
          ),
          new re(e.data, this.#e)
        );
      if (a instanceof re || s instanceof yt)
        return (
          S.debug(`Parent ${a} or ${s} is no-op, returning NoopSpan`),
          new re(e.data, this.#e)
        );
      ((o = s.traceId),
        a
          ? (S.debug("Using parent span %s", a.spanId), (r = a.spanId))
          : S.debug("No parent span, using current trace %s", s.traceId));
    }
    return o
      ? (S.debug(
          `Creating span ${JSON.stringify(e.data)} with id ${e.spanId ?? o}`,
        ),
        new Fe({ ...e, traceId: o, parentId: r }, this.#e))
      : (S.error(
          "No traceId found. Make sure to start a trace with `withTrace()` first. Returning NoopSpan.",
        ),
        new re(e.data, this.#e));
  }
  async shutdown(e) {
    try {
      (S.debug("Shutting down tracing provider"), await this.#e.shutdown(e));
    } catch (n) {
      S.error("Error shutting down tracing provider %o", n);
    }
  }
  #n() {
    if (typeof J < "u" && typeof J.on == "function") {
      const e = async () => {
        const n = setTimeout(() => {
          (console.warn("Cleanup timeout, forcing exit"), J.exit(1));
        }, 5e3);
        try {
          await this.shutdown();
        } finally {
          clearTimeout(n);
        }
      };
      (J.on("beforeExit", e),
        J.on("SIGINT", async () => {
          (await e(), Pn("SIGINT") || J.exit(130));
        }),
        J.on("SIGTERM", async () => {
          (await e(), Pn("SIGTERM") || J.exit(0));
        }),
        J.on("unhandledRejection", async (n, r) => {
          (S.error("Unhandled rejection", n, r),
            await e(),
            xi("unhandledRejection") || J.exit(1));
        }));
    }
  }
  async forceFlush() {
    await this.#e.forceFlush();
  }
}
function Pn(t) {
  return J.listeners(t).length > 1;
}
function xi(t) {
  return J.listeners(t).length > 1;
}
let _t;
function $() {
  return (_t || (_t = new Ii()), _t);
}
function Ai(t) {
  $().registerProcessor(t);
}
function Di(t) {
  $().setProcessors(t);
}
function pl(t) {
  $().setDisabled(t);
}
function dl() {
  $().startExportLoop();
}
function fl(t, e) {
  return {
    type: "message",
    role: "user",
    content: typeof t == "string" ? [{ type: "input_text", text: t }] : t,
    providerData: e,
  };
}
function ml(t, e) {
  return { type: "message", role: "system", content: t, providerData: e };
}
function hl(t, e) {
  return {
    type: "message",
    role: "assistant",
    content: typeof t == "string" ? [{ type: "output_text", text: t }] : t,
    status: "completed",
    providerData: e,
  };
}
function gl(t) {
  if (!t?.allowed && !t?.blocked) return;
  const e = {};
  return (
    t?.allowed && (e.allowedToolNames = t.allowed),
    t?.blocked && (e.blockedToolNames = t.blocked),
    e
  );
}
Ai(Xr());
const ki = { version: "0.2.1" },
  Ei = "responses";
let eo = Ei,
  to,
  no,
  ro;
function yl(t) {
  ro = t;
}
function Oi() {
  return ro ?? Rt().OPENAI_API_KEY;
}
function Ci() {
  return eo === "responses";
}
function _l(t) {
  eo = t;
}
function vl(t) {
  to = t;
}
function Ri() {
  return to;
}
function wl(t) {
  no = t;
}
function Ni() {
  return no ?? Rt().OPENAI_API_KEY;
}
const Ht = { "User-Agent": `Agents/JavaScript ${ki.version}` },
  L = Ee("openai-agents:openai"),
  Pi = N(["in_progress", "completed", "searching", "failed"]).default("failed"),
  Mi = N([
    "in_progress",
    "completed",
    "searching",
    "failed",
    "incomplete",
  ]).default("failed"),
  Fi = N(["in_progress", "completed", "interpreting"]).default("in_progress"),
  Li = N(["in_progress", "completed", "generating", "failed"]).default(
    "failed",
  );
function bl(t = {}) {
  const e = {
    type: "web_search",
    name: t.name ?? "web_search",
    user_location: t.userLocation,
    filters: t.filters?.allowedDomains
      ? { allowed_domains: t.filters.allowedDomains }
      : void 0,
    search_context_size: t.searchContextSize ?? "medium",
  };
  return { type: "hosted_tool", name: t.name ?? "web_search", providerData: e };
}
function Sl(t, e = {}) {
  const n = Array.isArray(t) ? t : [t],
    r = {
      type: "file_search",
      name: e.name ?? "file_search",
      vector_store_ids: n,
      max_num_results: e.maxNumResults,
      include_search_results: e.includeSearchResults,
      ranking_options: e.rankingOptions,
      filters: e.filters,
    };
  return {
    type: "hosted_tool",
    name: e.name ?? "file_search",
    providerData: r,
  };
}
function Tl(t = {}) {
  const e = {
    type: "code_interpreter",
    name: t.name ?? "code_interpreter",
    container: t.container ?? { type: "auto" },
  };
  return {
    type: "hosted_tool",
    name: t.name ?? "code_interpreter",
    providerData: e,
  };
}
function Il(t = {}) {
  const e = {
    type: "image_generation",
    name: t.name ?? "image_generation",
    background: t.background,
    input_fidelity: t.inputFidelity,
    input_image_mask: t.inputImageMask,
    model: t.model,
    moderation: t.moderation,
    output_compression: t.outputCompression,
    output_format: t.outputFormat,
    partial_images: t.partialImages,
    quality: t.quality,
    size: t.size,
  };
  return {
    type: "hosted_tool",
    name: t.name ?? "image_generation",
    providerData: e,
  };
}
function R(t) {
  if (!t || typeof t != "object" || Array.isArray(t)) return t;
  const e = {};
  for (const [n, r] of Object.entries(t)) {
    const o = n.replace(/([A-Z])/g, "_$1").toLowerCase();
    e[o] = R(r);
  }
  return e;
}
const $i = N([
    "file_search",
    "web_search",
    "web_search_preview",
    "computer_use_preview",
    "code_interpreter",
    "image_generation",
    "mcp",
  ]),
  ji = N(["auto", "required", "none"]);
function Ui(t) {
  if (typeof t > "u") return;
  const e = ji.safeParse(t);
  if (e.success) return e.data;
  const n = $i.safeParse(t);
  return n.success ? { type: n.data } : { type: "function", name: t };
}
function Ji(t, e) {
  return t === "text" ? e : { ...e, format: t };
}
function Gi(t) {
  if (typeof t == "string") return t;
  if (Array.isArray(t)) return t.map(Mn);
  if (Qe(t) && typeof t.type == "string") {
    if (t.type === "text" && typeof t.text == "string") return t.text;
    if (t.type === "image" || t.type === "file") return Bi(t).map(Mn);
  }
  return String(t);
}
function Bi(t) {
  if (t.type === "text") {
    const e = { type: "input_text", text: t.text };
    return (t.providerData && (e.providerData = t.providerData), [e]);
  }
  if (t.type === "image") {
    const e = { type: "input_image" };
    t.detail && (e.detail = t.detail);
    const n = t.imageUrl,
      r = t.fileId,
      o = t.data;
    if (typeof t.image == "string" && t.image.length > 0) e.image = t.image;
    else if (Qe(t.image)) {
      const s = t.image,
        a = Zi(s);
      if (typeof s.url == "string" && s.url.length > 0) e.image = s.url;
      else if (typeof s.data == "string" && s.data.length > 0)
        e.image = Se(s.data, a);
      else if (s.data instanceof Uint8Array && s.data.length > 0)
        e.image = Se(s.data, a);
      else {
        const i =
          (typeof s.fileId == "string" && s.fileId.length > 0 && s.fileId) ||
          (typeof s.id == "string" && s.id.length > 0 ? s.id : void 0);
        i && (e.image = { id: i });
      }
    } else if (typeof n == "string" && n.length > 0) e.image = n;
    else if (typeof r == "string" && r.length > 0) e.image = { id: r };
    else {
      let s;
      (typeof o == "string" && o.length > 0
        ? (s = o)
        : o instanceof Uint8Array && o.length > 0 && (s = Re(o)),
        s && (e.image = s));
    }
    return (t.providerData && (e.providerData = t.providerData), [e]);
  }
  if (t.type === "file") {
    const e = { type: "input_file" },
      n = t.file ?? t.file;
    if (typeof n == "string") e.file = n;
    else if (Qe(n)) {
      if (typeof n.data == "string" && n.data.length > 0)
        e.file = Se(n.data, n.mediaType ?? "text/plain");
      else if (n.data instanceof Uint8Array && n.data.length > 0)
        e.file = Se(n.data, n.mediaType ?? "text/plain");
      else if (typeof n.url == "string" && n.url.length > 0)
        e.file = { url: n.url };
      else {
        const r =
          (typeof n.id == "string" && n.id.length > 0 && n.id) ||
          (typeof n.fileId == "string" && n.fileId.length > 0
            ? n.fileId
            : void 0);
        r && (e.file = { id: r });
      }
      typeof n.filename == "string" &&
        n.filename.length > 0 &&
        (e.filename = n.filename);
    }
    if (!e.file) {
      const r = zi(t);
      (r.file && (e.file = r.file), r.filename && (e.filename = r.filename));
    }
    return (t.providerData && (e.providerData = t.providerData), [e]);
  }
  throw new k(`Unsupported tool output type: ${JSON.stringify(t)}`);
}
function Mn(t) {
  if (t.type === "input_text") return { type: "input_text", text: t.text };
  if (t.type === "input_image") {
    const e = { type: "input_image" },
      n = t.image ?? t.imageUrl;
    typeof n == "string"
      ? (e.image_url = n)
      : Qe(n) && typeof n.id == "string" && (e.file_id = n.id);
    const r = t.fileId;
    return (
      typeof r == "string" && (e.file_id = r),
      t.detail && (e.detail = t.detail),
      e
    );
  }
  if (t.type === "input_file") {
    const e = { type: "input_file" };
    if (typeof t.file == "string") {
      const s = t.file.trim();
      s.startsWith("data:")
        ? (e.file_data = s)
        : s.startsWith("http://") || s.startsWith("https://")
          ? (e.file_url = s)
          : /^[A-Za-z0-9+/=]+$/.test(s)
            ? (e.file_data = s)
            : (e.file_url = s);
    } else
      t.file &&
      typeof t.file == "object" &&
      "id" in t.file &&
      typeof t.file.id == "string"
        ? (e.file_id = t.file.id)
        : t.file &&
          typeof t.file == "object" &&
          "url" in t.file &&
          typeof t.file.url == "string" &&
          (e.file_url = t.file.url);
    const n = t.fileData;
    typeof n == "string" && (e.file_data = n);
    const r = t.fileUrl;
    typeof r == "string" && (e.file_url = r);
    const o = t.fileId;
    return (
      typeof o == "string" && (e.file_id = o),
      t.filename && (e.filename = t.filename),
      e
    );
  }
  throw new k(`Unsupported structured tool output: ${JSON.stringify(t)}`);
}
function zi(t) {
  const e =
      typeof t.filename == "string" && t.filename.length > 0
        ? t.filename
        : void 0,
    n =
      (typeof t.id == "string" && t.id.length > 0 && t.id) ??
      (typeof t.fileId == "string" && t.fileId.length > 0 ? t.fileId : void 0);
  return n
    ? { file: { id: n }, filename: e }
    : typeof t.fileUrl == "string" && t.fileUrl.length > 0
      ? { file: { url: t.fileUrl }, filename: e }
      : typeof t.fileData == "string" && t.fileData.length > 0
        ? { file: Se(t.fileData, t.mediaType ?? "text/plain"), filename: e }
        : t.fileData instanceof Uint8Array && t.fileData.length > 0
          ? { file: Se(t.fileData, t.mediaType ?? "text/plain"), filename: e }
          : {};
}
function Qe(t) {
  return typeof t == "object" && t !== null;
}
function Zi(t) {
  if (typeof t.mediaType == "string" && t.mediaType.length > 0)
    return t.mediaType;
}
function Se(t, e) {
  const n = typeof t == "string" ? t : Re(t);
  return e ? `data:${e};base64,${n}` : n;
}
function qi(t, e) {
  const n = [],
    r = [];
  for (const o of t) {
    const { tool: s, include: a } = Hi(o);
    if ((n.push(s), a && a.length > 0)) for (const i of a) r.push(i);
  }
  return { tools: [...n, ...e.map(Wi)], include: r };
}
function Hi(t) {
  if (t.type === "function")
    return {
      tool: {
        type: "function",
        name: t.name,
        description: t.description,
        parameters: t.parameters,
        strict: t.strict,
      },
      include: void 0,
    };
  if (t.type === "computer")
    return {
      tool: {
        type: "computer_use_preview",
        environment: t.environment,
        display_width: t.dimensions[0],
        display_height: t.dimensions[1],
      },
      include: void 0,
    };
  if (t.type === "hosted_tool") {
    if (t.providerData?.type === "web_search")
      return {
        tool: {
          type: "web_search",
          user_location: t.providerData.user_location,
          filters: t.providerData.filters,
          search_context_size: t.providerData.search_context_size,
        },
        include: void 0,
      };
    if (t.providerData?.type === "web_search_preview")
      return {
        tool: {
          type: "web_search_preview",
          user_location: t.providerData.user_location,
          search_context_size: t.providerData.search_context_size,
        },
        include: void 0,
      };
    if (t.providerData?.type === "file_search")
      return {
        tool: {
          type: "file_search",
          vector_store_ids:
            t.providerData.vector_store_ids ||
            (typeof t.providerData.vector_store_id == "string"
              ? [t.providerData.vector_store_id]
              : t.providerData.vector_store_id),
          max_num_results: t.providerData.max_num_results,
          ranking_options: t.providerData.ranking_options,
          filters: t.providerData.filters,
        },
        include: t.providerData.include_search_results
          ? ["file_search_call.results"]
          : void 0,
      };
    if (t.providerData?.type === "code_interpreter")
      return {
        tool: { type: "code_interpreter", container: t.providerData.container },
        include: void 0,
      };
    if (t.providerData?.type === "image_generation")
      return {
        tool: {
          type: "image_generation",
          background: t.providerData.background,
          input_fidelity: t.providerData.input_fidelity,
          input_image_mask: t.providerData.input_image_mask,
          model: t.providerData.model,
          moderation: t.providerData.moderation,
          output_compression: t.providerData.output_compression,
          output_format: t.providerData.output_format,
          partial_images: t.providerData.partial_images,
          quality: t.providerData.quality,
          size: t.providerData.size,
        },
        include: void 0,
      };
    if (t.providerData?.type === "mcp")
      return {
        tool: {
          type: "mcp",
          server_label: t.providerData.server_label,
          server_url: t.providerData.server_url,
          connector_id: t.providerData.connector_id,
          authorization: t.providerData.authorization,
          allowed_tools: t.providerData.allowed_tools,
          headers: t.providerData.headers,
          require_approval: Ki(t.providerData.require_approval),
        },
        include: void 0,
      };
    if (t.providerData) return { tool: t.providerData, include: void 0 };
  }
  throw new Error(`Unsupported tool type: ${JSON.stringify(t)}`);
}
function Ki(t) {
  return t === "never" || t === void 0
    ? "never"
    : t === "always"
      ? "always"
      : {
          never: { tool_names: t.never?.tool_names },
          always: { tool_names: t.always?.tool_names },
        };
}
function Wi(t) {
  return {
    name: t.toolName,
    description: t.toolDescription,
    parameters: t.inputJsonSchema,
    strict: t.strictJsonSchema,
    type: "function",
  };
}
function oo(t) {
  if (t.type === "input_text")
    return { type: "input_text", text: t.text, ...R(t.providerData) };
  if (t.type === "input_image") {
    const e = { type: "input_image", detail: t.detail ?? "auto" };
    return (
      typeof t.image == "string"
        ? (e.image_url = t.image)
        : t.image && "id" in t.image
          ? (e.file_id = t.image.id)
          : typeof t.imageUrl == "string"
            ? (e.image_url = t.imageUrl)
            : typeof t.fileId == "string" && (e.file_id = t.fileId),
      { ...e, ...R(t.providerData) }
    );
  } else if (t.type === "input_file") {
    const e = { type: "input_file" };
    if (typeof t.file == "string")
      if (t.file.startsWith("data:")) e.file_data = t.file;
      else if (t.file.startsWith("https://")) e.file_url = t.file;
      else
        throw new k(
          "Unsupported string data for file input. If you're trying to pass an uploaded file's ID, use an object with the ID property instead.",
        );
    else
      t.file && typeof t.file == "object" && "id" in t.file
        ? (e.file_id = t.file.id)
        : t.file &&
          typeof t.file == "object" &&
          "url" in t.file &&
          (e.file_url = t.file.url);
    const n = t.fileData;
    typeof n == "string" && (e.file_data = n);
    const r = t.fileUrl;
    typeof r == "string" && (e.file_url = r);
    const o = t.fileId;
    return (
      typeof o == "string" && (e.file_id = o),
      t.filename && (e.filename = t.filename),
      { ...e, ...R(t.providerData) }
    );
  }
  throw new k(`Unsupported input content type: ${JSON.stringify(t)}`);
}
function Vi(t) {
  if (t.type === "output_text")
    return {
      type: "output_text",
      text: t.text,
      annotations: [],
      ...R(t.providerData),
    };
  if (t.type === "refusal")
    return { type: "refusal", refusal: t.refusal, ...R(t.providerData) };
  throw new k(`Unsupported output content type: ${JSON.stringify(t)}`);
}
function Yi(t) {
  if (t.role === "system")
    return {
      id: t.id,
      role: "system",
      content: t.content,
      ...R(t.providerData),
    };
  if (t.role === "user")
    return typeof t.content == "string"
      ? { id: t.id, role: "user", content: t.content, ...R(t.providerData) }
      : {
          id: t.id,
          role: "user",
          content: t.content.map(oo),
          ...R(t.providerData),
        };
  if (t.role === "assistant")
    return {
      type: "message",
      id: t.id,
      role: "assistant",
      content: t.content.map(Vi),
      status: t.status,
      ...R(t.providerData),
    };
  throw new k(`Unsupported item ${JSON.stringify(t)}`);
}
function Xi(t) {
  return (
    t.type === "message" || (typeof t.type > "u" && typeof t.role == "string")
  );
}
function Qi(t) {
  if (!t) return;
  const e = {};
  for (const [n, r] of Object.entries(t.variables ?? {}))
    typeof r == "string" ? (e[n] = r) : typeof r == "object" && (e[n] = oo(r));
  return { id: t.promptId, version: t.version, variables: e };
}
function eu(t) {
  return typeof t == "string"
    ? [{ role: "user", content: t }]
    : t.map((e) => {
        if (Xi(e)) return Yi(e);
        if (e.type === "function_call")
          return {
            id: e.id,
            type: "function_call",
            name: e.name,
            call_id: e.callId,
            arguments: e.arguments,
            status: e.status,
            ...R(e.providerData),
          };
        if (e.type === "function_call_result") {
          const r = Gi(e.output);
          return {
            type: "function_call_output",
            id: e.id,
            call_id: e.callId,
            output: r,
            status: e.status,
            ...R(e.providerData),
          };
        }
        if (e.type === "reasoning")
          return {
            id: e.id,
            type: "reasoning",
            summary: e.content.map((o) => ({
              type: "summary_text",
              text: o.text,
              ...R(o.providerData),
            })),
            encrypted_content: e.providerData?.encryptedContent,
            ...R(e.providerData),
          };
        if (e.type === "computer_call")
          return {
            type: "computer_call",
            call_id: e.callId,
            id: e.id,
            action: e.action,
            status: e.status,
            pending_safety_checks: [],
            ...R(e.providerData),
          };
        if (e.type === "computer_call_result")
          return {
            type: "computer_call_output",
            id: e.id,
            call_id: e.callId,
            output: tu(e),
            status: e.providerData?.status,
            acknowledged_safety_checks:
              e.providerData?.acknowledgedSafetyChecks,
            ...R(e.providerData),
          };
        if (e.type === "hosted_tool_call") {
          if (
            e.providerData?.type === "web_search_call" ||
            e.providerData?.type === "web_search"
          )
            return {
              ...R(e.providerData),
              type: "web_search_call",
              id: e.id,
              status: Pi.parse(e.status ?? "failed"),
            };
          if (
            e.providerData?.type === "file_search_call" ||
            e.providerData?.type === "file_search"
          )
            return {
              ...R(e.providerData),
              type: "file_search_call",
              id: e.id,
              status: Mi.parse(e.status ?? "failed"),
              queries: e.providerData?.queries ?? [],
              results: e.providerData?.results,
            };
          if (
            e.providerData?.type === "code_interpreter_call" ||
            e.providerData?.type === "code_interpreter"
          )
            return {
              ...R(e.providerData),
              type: "code_interpreter_call",
              id: e.id,
              code: e.providerData?.code ?? "",
              outputs: e.providerData?.outputs ?? e.providerData?.results ?? [],
              status: Fi.parse(e.status ?? "failed"),
              container_id: e.providerData?.container_id,
            };
          if (
            e.providerData?.type === "image_generation_call" ||
            e.providerData?.type === "image_generation"
          )
            return {
              ...R(e.providerData),
              type: "image_generation_call",
              id: e.id,
              result: e.providerData?.result ?? null,
              status: Li.parse(e.status ?? "failed"),
            };
          if (
            e.providerData?.type === "mcp_list_tools" ||
            e.name === "mcp_list_tools"
          ) {
            const r = e.providerData;
            return {
              ...R(e.providerData),
              type: "mcp_list_tools",
              id: e.id,
              tools: R(r.tools),
              server_label: r.server_label,
              error: r.error,
            };
          } else if (
            e.providerData?.type === "mcp_approval_request" ||
            e.name === "mcp_approval_request"
          ) {
            const r = e.providerData;
            return {
              ...R(e.providerData),
              type: "mcp_approval_request",
              id: r.id ?? e.id,
              name: r.name,
              arguments: r.arguments,
              server_label: r.server_label,
            };
          } else if (
            e.providerData?.type === "mcp_approval_response" ||
            e.name === "mcp_approval_response"
          ) {
            const r = e.providerData;
            return {
              ...R(r),
              type: "mcp_approval_response",
              id: r.id,
              approve: r.approve,
              approval_request_id: r.approval_request_id,
              reason: r.reason,
            };
          } else if (
            e.providerData?.type === "mcp_call" ||
            e.name === "mcp_call"
          ) {
            const r = e.providerData;
            return {
              ...R(r),
              type: "mcp_call",
              id: r.id ?? e.id,
              name: r.name,
              arguments: r.arguments,
              server_label: r.server_label,
              error: r.error,
            };
          }
          throw new k(
            `Unsupported built-in tool call type: ${JSON.stringify(e)}`,
          );
        }
        if (e.type === "unknown") return { ...R(e.providerData), id: e.id };
        const n = e;
        throw new k(`Unsupported item ${JSON.stringify(n)}`);
      });
}
function tu(t) {
  return { type: "computer_screenshot", image_url: t.output.data };
}
function nu(t) {
  if (t.type === "output_text") {
    const { type: e, text: n, ...r } = t;
    return { type: e, text: n, ...r };
  }
  if (t.type === "refusal") {
    const { type: e, refusal: n, ...r } = t;
    return { type: e, refusal: n, ...r };
  }
  throw new Error(`Unsupported message content type: ${JSON.stringify(t)}`);
}
function Fn(t) {
  return t.map((e) => {
    if (e.type === "message") {
      const { id: n, type: r, role: o, content: s, status: a, ...i } = e;
      return {
        id: n,
        type: r,
        role: o,
        content: s.map(nu),
        status: a,
        providerData: i,
      };
    } else if (
      e.type === "file_search_call" ||
      e.type === "web_search_call" ||
      e.type === "image_generation_call" ||
      e.type === "code_interpreter_call"
    ) {
      const { status: n, ...r } = e;
      let o;
      return (
        "result" in r && r.result !== null && ((o = r.result), delete r.result),
        {
          type: "hosted_tool_call",
          id: e.id,
          name: e.type,
          status: n,
          output: o,
          providerData: r,
        }
      );
    } else if (e.type === "function_call") {
      const { call_id: n, name: r, status: o, arguments: s, ...a } = e;
      return {
        type: "function_call",
        id: e.id,
        callId: n,
        name: r,
        status: o,
        arguments: s,
        providerData: a,
      };
    } else if (e.type === "computer_call") {
      const { call_id: n, status: r, action: o, ...s } = e;
      return {
        type: "computer_call",
        id: e.id,
        callId: n,
        status: r,
        action: o,
        providerData: s,
      };
    } else if (e.type === "mcp_list_tools") {
      const { ...n } = e;
      return {
        type: "hosted_tool_call",
        id: e.id,
        name: e.type,
        status: "completed",
        output: void 0,
        providerData: n,
      };
    } else if (e.type === "mcp_approval_request") {
      const { ...n } = e;
      return {
        type: "hosted_tool_call",
        id: e.id,
        name: "mcp_approval_request",
        status: "completed",
        output: void 0,
        providerData: n,
      };
    } else if (e.type === "mcp_call") {
      const { output: n, ...r } = e;
      return {
        type: "hosted_tool_call",
        id: e.id,
        name: e.type,
        status: "completed",
        output: n || void 0,
        providerData: r,
      };
    } else if (e.type === "reasoning") {
      const { summary: n, ...r } = e;
      return {
        type: "reasoning",
        id: e.id,
        content: n.map((s) => {
          const { text: a, ...i } = s;
          return { type: "input_text", text: a, providerData: i };
        }),
        providerData: r,
      };
    }
    return { type: "unknown", providerData: e };
  });
}
class ru {
  #e;
  #t;
  constructor(e, n) {
    ((this.#e = e), (this.#t = n));
  }
  async #n(e, n) {
    const r = eu(e.input),
      { tools: o, include: s } = qi(e.tools, e.handoffs),
      a = Ui(e.modelSettings.toolChoice),
      { text: i, ...f } = e.modelSettings.providerData ?? {};
    e.modelSettings.reasoning &&
      (f.reasoning = { ...e.modelSettings.reasoning, ...f.reasoning });
    let c = i;
    e.modelSettings.text && (c = { ...e.modelSettings.text, ...i });
    const l = Ji(e.outputType, c),
      d = Qi(e.prompt);
    let m;
    if (typeof e.modelSettings.parallelToolCalls == "boolean") {
      if (e.modelSettings.parallelToolCalls && o.length === 0)
        throw new Error("Parallel tool calls are not supported without tools");
      m = e.modelSettings.parallelToolCalls;
    }
    const p = {
      ...(!e.prompt || e.overridePromptModel === !0 ? { model: this.#t } : {}),
      instructions: ou(e.systemInstructions),
      input: r,
      include: s,
      tools: o,
      previous_response_id: e.previousResponseId,
      conversation: e.conversationId,
      prompt: d,
      temperature: e.modelSettings.temperature,
      top_p: e.modelSettings.topP,
      truncation: e.modelSettings.truncation,
      max_output_tokens: e.modelSettings.maxTokens,
      tool_choice: a,
      parallel_tool_calls: m,
      stream: n,
      text: l,
      store: e.modelSettings.store,
      ...f,
    };
    L.dontLogModelData
      ? L.debug("Calling LLM")
      : L.debug(`Calling LLM. Request data: ${JSON.stringify(p, null, 2)}`);
    const v = await this.#e.responses.create(p, {
      headers: Ht,
      signal: e.signal,
    });
    return (
      L.dontLogModelData
        ? L.debug("Response received")
        : L.debug(`Response received: ${JSON.stringify(v, null, 2)}`),
      v
    );
  }
  async getResponse(e) {
    const n = await Ma(async (o) => {
      const s = await this.#n(e, !1);
      return (
        e.tracing &&
          ((o.spanData.response_id = s.id),
          (o.spanData._input = e.input),
          (o.spanData._response = s)),
        s
      );
    });
    return {
      usage: new ge({
        inputTokens: n.usage?.input_tokens ?? 0,
        outputTokens: n.usage?.output_tokens ?? 0,
        totalTokens: n.usage?.total_tokens ?? 0,
        inputTokensDetails: { ...n.usage?.input_tokens_details },
        outputTokensDetails: { ...n.usage?.output_tokens_details },
      }),
      output: Fn(n.output),
      responseId: n.id,
      providerData: n,
    };
  }
  async *getStreamedResponse(e) {
    const n = e.tracing ? Fr() : void 0;
    try {
      n &&
        (n.start(), Te(n), e.tracing === !0 && (n.spanData._input = e.input));
      const r = await this.#n(e, !0);
      let o;
      for await (const s of r) {
        if (s.type === "response.created")
          yield { type: "response_started", providerData: { ...s } };
        else if (s.type === "response.completed") {
          o = s.response;
          const { response: a, ...i } = s,
            { output: f, usage: c, id: l, ...d } = a;
          (yield {
            type: "response_done",
            response: {
              id: l,
              output: Fn(f),
              usage: {
                inputTokens: c?.input_tokens ?? 0,
                outputTokens: c?.output_tokens ?? 0,
                totalTokens: c?.total_tokens ?? 0,
                inputTokensDetails: { ...c?.input_tokens_details },
                outputTokensDetails: { ...c?.output_tokens_details },
              },
              providerData: d,
            },
            providerData: i,
          },
            yield { type: "model", event: s });
        } else if (s.type === "response.output_text.delta") {
          const { delta: a, ...i } = s;
          yield { type: "output_text_delta", delta: a, providerData: i };
        }
        yield { type: "model", event: s };
      }
      e.tracing &&
        n &&
        o &&
        ((n.spanData.response_id = o.id), (n.spanData._response = o));
    } catch (r) {
      throw (
        n &&
          n.setError({
            message: "Error streaming response",
            data: {
              error: e.tracing
                ? String(r)
                : r instanceof Error
                  ? r.name
                  : void 0,
            },
          }),
        r
      );
    } finally {
      n && (n.end(), de());
    }
  }
}
function ou(t) {
  if (typeof t == "string") return t.trim() === "" ? void 0 : t;
}
async function* su(t, e) {
  let n;
  const r = {
    started: !1,
    text_content_index_and_output: null,
    refusal_content_index_and_output: null,
    function_calls: {},
    reasoning: "",
  };
  for await (const a of e) {
    if (
      (r.started ||
        ((r.started = !0),
        yield { type: "response_started", providerData: { ...a } }),
      yield { type: "model", event: a },
      (n = a.usage || void 0),
      !a.choices?.[0]?.delta)
    )
      continue;
    const i = a.choices[0].delta;
    if (
      (i.content &&
        (r.text_content_index_and_output ||
          (r.text_content_index_and_output = [
            r.refusal_content_index_and_output ? 1 : 0,
            {
              text: "",
              type: "output_text",
              providerData: { annotations: [] },
            },
          ]),
        yield {
          type: "output_text_delta",
          delta: i.content,
          providerData: { ...a },
        },
        (r.text_content_index_and_output[1].text += i.content)),
      "reasoning" in i &&
        i.reasoning &&
        typeof i.reasoning == "string" &&
        (r.reasoning += i.reasoning),
      "refusal" in i &&
        i.refusal &&
        (r.refusal_content_index_and_output ||
          (r.refusal_content_index_and_output = [
            r.text_content_index_and_output ? 1 : 0,
            { refusal: "", type: "refusal" },
          ]),
        (r.refusal_content_index_and_output[1].refusal += i.refusal)),
      i.tool_calls)
    )
      for (const f of i.tool_calls) {
        f.index in r.function_calls ||
          (r.function_calls[f.index] = {
            id: kt,
            arguments: "",
            name: "",
            type: "function_call",
            callId: "",
          });
        const c = f.function;
        ((r.function_calls[f.index].arguments += c?.arguments || ""),
          (r.function_calls[f.index].name += c?.name || ""),
          (r.function_calls[f.index].callId += f.id || ""));
      }
  }
  const o = [];
  if (
    (r.reasoning &&
      o.push({
        type: "reasoning",
        content: [],
        rawContent: [{ type: "reasoning_text", text: r.reasoning }],
      }),
    r.text_content_index_and_output || r.refusal_content_index_and_output)
  ) {
    const a = {
      id: kt,
      content: [],
      role: "assistant",
      type: "message",
      status: "completed",
    };
    (r.text_content_index_and_output &&
      a.content.push(r.text_content_index_and_output[1]),
      r.refusal_content_index_and_output &&
        a.content.push(r.refusal_content_index_and_output[1]),
      o.push(a));
  }
  for (const a of Object.values(r.function_calls)) o.push(a);
  yield {
    type: "response_done",
    response: {
      id: t.id,
      usage: {
        inputTokens: n?.prompt_tokens ?? 0,
        outputTokens: n?.completion_tokens ?? 0,
        totalTokens: n?.total_tokens ?? 0,
        inputTokensDetails: {
          cached_tokens: n?.prompt_tokens_details?.cached_tokens ?? 0,
        },
        outputTokensDetails: {
          reasoning_tokens: n?.completion_tokens_details?.reasoning_tokens ?? 0,
        },
      },
      output: o,
    },
  };
}
function au(t) {
  if (!(t == null || t == null))
    return t === "auto" || t === "required" || t === "none"
      ? t
      : { type: "function", function: { name: t } };
}
function iu(t) {
  if (typeof t == "string") return t;
  const e = [];
  for (const n of t)
    if (n.type === "output_text")
      e.push({ type: "text", text: n.text, ...n.providerData });
    else if (n.type === "refusal")
      e.push({ type: "refusal", refusal: n.refusal, ...n.providerData });
    else {
      if (n.type === "audio" || n.type === "image") continue;
      {
        const r = n;
        throw new Error(`Unknown content: ${JSON.stringify(r)}`);
      }
    }
  return e;
}
function uu(t) {
  if (typeof t == "string") return t;
  const e = [];
  for (const n of t)
    if (n.type === "input_text")
      e.push({ type: "text", text: n.text, ...n.providerData });
    else if (n.type === "input_image") {
      const r =
        typeof n.image == "string"
          ? n.image
          : typeof n.imageUrl == "string"
            ? n.imageUrl
            : void 0;
      if (!r)
        throw new Error(
          `Only image URLs are supported for input_image: ${JSON.stringify(n)}`,
        );
      const { image_url: o, ...s } = n.providerData || {};
      e.push({ type: "image_url", image_url: { url: r, ...o }, ...s });
    } else {
      if (n.type === "input_file")
        throw new Error(
          `File uploads are not supported for chat completions: ${JSON.stringify(n)}`,
        );
      if (n.type === "audio") {
        const { input_audio: r, ...o } = n.providerData || {};
        e.push({
          type: "input_audio",
          input_audio: { data: n.audio, ...r },
          ...o,
        });
      } else {
        const r = n;
        throw new Error(`Unknown content: ${JSON.stringify(r)}`);
      }
    }
  return e;
}
function cu(t) {
  return (
    t.type === "message" || (typeof t.type > "u" && typeof t.role == "string")
  );
}
function lu(t) {
  if (typeof t == "string") return [{ role: "user", content: t }];
  const e = [];
  let n = null;
  const r = () => {
      n &&
        ((!n.tool_calls || n.tool_calls.length === 0) && delete n.tool_calls,
        e.push(n),
        (n = null));
    },
    o = () => (n || (n = { role: "assistant", tool_calls: [] }), n);
  for (const s of t)
    if (cu(s)) {
      const { content: a, role: i, providerData: f } = s;
      if ((r(), i === "assistant")) {
        const c = { role: "assistant", content: iu(a), ...f };
        if (Array.isArray(a)) {
          const l = a.find((d) => d.type === "audio");
          l && (c.audio = { id: "", ...l.providerData });
        }
        e.push(c);
      } else
        i === "user"
          ? e.push({ role: i, content: uu(a), ...f })
          : i === "system" && e.push({ role: "system", content: a, ...f });
    } else if (s.type === "reasoning") {
      const a = o();
      a.reasoning = s.rawContent?.[0]?.text;
      continue;
    } else if (s.type === "hosted_tool_call")
      if (s.name === "file_search_call") {
        const a = o(),
          i = a.tool_calls ?? [],
          f = s,
          { function: c, ...l } = f.providerData ?? {},
          { arguments: d, ...m } = c ?? {};
        (i.push({
          id: f.id || "",
          type: "function",
          function: {
            name: "file_search_call",
            arguments: JSON.stringify({
              queries: f.providerData?.queries ?? [],
              status: f.status,
              ...d,
            }),
            ...m,
          },
          ...l,
        }),
          (a.tool_calls = i));
        continue;
      } else
        throw new k(
          "Hosted tool calls are not supported for chat completions. Got item: " +
            JSON.stringify(s),
        );
    else {
      if (s.type === "computer_call" || s.type === "computer_call_result")
        throw new k(
          "Computer use calls are not supported for chat completions. Got item: " +
            JSON.stringify(s),
        );
      if (s.type === "function_call") {
        const a = o(),
          i = a.tool_calls ?? [],
          f = s;
        (i.push({
          id: f.callId,
          type: "function",
          function: { name: f.name, arguments: f.arguments ?? "{}" },
        }),
          (a.tool_calls = i));
      } else if (s.type === "function_call_result") {
        r();
        const a = s,
          i = pu(a.output);
        e.push({
          role: "tool",
          tool_call_id: a.callId,
          content: i,
          ...a.providerData,
        });
      } else if (s.type === "unknown") e.push({ ...s.providerData });
      else {
        const a = s;
        throw new Error(`Unknown item type: ${JSON.stringify(a)}`);
      }
    }
  return (r(), e);
}
function pu(t) {
  if (typeof t == "string") return t;
  if (Array.isArray(t)) {
    if (!t.every((n) => n.type === "input_text"))
      throw new k("Only text tool outputs are supported for chat completions.");
    return t.map((n) => n.text).join("");
  }
  if (du(t) && t.type === "text" && typeof t.text == "string") return t.text;
  throw new k(
    "Only text tool outputs are supported for chat completions. Got item: " +
      JSON.stringify(t),
  );
}
function du(t) {
  return typeof t == "object" && t !== null;
}
function fu(t) {
  if (t.type === "function")
    return {
      type: "function",
      function: {
        name: t.name,
        description: t.description || "",
        parameters: t.parameters,
        strict: t.strict,
      },
    };
  throw new Error(
    `Hosted tools are not supported with the ChatCompletions API. Got tool type: ${t.type}, tool: ${JSON.stringify(t)}`,
  );
}
function mu(t) {
  return {
    type: "function",
    function: {
      name: t.toolName,
      description: t.toolDescription || "",
      parameters: t.inputJsonSchema,
    },
  };
}
const kt = "FAKE_ID";
function hu(t) {
  return (
    "reasoning" in t && typeof t.reasoning == "string" && t.reasoning !== ""
  );
}
class gu {
  #e;
  #t;
  constructor(e, n) {
    ((this.#e = e), (this.#t = n));
  }
  async getResponse(e) {
    const n = await ja(async (s) => {
        ((s.spanData.model = this.#t),
          (s.spanData.model_config = e.modelSettings
            ? {
                temperature: e.modelSettings.temperature,
                top_p: e.modelSettings.topP,
                frequency_penalty: e.modelSettings.frequencyPenalty,
                presence_penalty: e.modelSettings.presencePenalty,
                reasoning_effort: e.modelSettings.reasoning?.effort,
                verbosity: e.modelSettings.text?.verbosity,
              }
            : { base_url: this.#e.baseURL }));
        const a = await this.#n(e, s, !1);
        return (s && e.tracing === !0 && (s.spanData.output = [a]), a);
      }),
      r = [];
    if (n.choices && n.choices[0]) {
      const s = n.choices[0].message;
      if (
        (hu(s) &&
          r.push({
            type: "reasoning",
            content: [],
            rawContent: [{ type: "reasoning_text", text: s.reasoning }],
          }),
        s.content !== void 0 &&
          s.content !== null &&
          !(s.tool_calls && s.content === ""))
      ) {
        const { content: a, ...i } = s;
        r.push({
          id: n.id,
          type: "message",
          role: "assistant",
          content: [{ type: "output_text", text: a || "", providerData: i }],
          status: "completed",
        });
      } else if (s.refusal) {
        const { refusal: a, ...i } = s;
        r.push({
          id: n.id,
          type: "message",
          role: "assistant",
          content: [{ type: "refusal", refusal: a || "", providerData: i }],
          status: "completed",
        });
      } else if (s.audio) {
        const { data: a, ...i } = s.audio;
        r.push({
          id: n.id,
          type: "message",
          role: "assistant",
          content: [{ type: "audio", audio: a, providerData: i }],
          status: "completed",
        });
      } else if (s.tool_calls) {
        for (const a of s.tool_calls)
          if (a.type === "function") {
            const { id: i, ...f } = a,
              { arguments: c, name: l, ...d } = a.function;
            r.push({
              id: n.id,
              type: "function_call",
              arguments: c,
              name: l,
              callId: i,
              status: "completed",
              providerData: { ...f, ...d },
            });
          }
      }
    }
    return {
      usage: n.usage ? new ge(_u(n.usage)) : new ge(),
      output: r,
      responseId: n.id,
      providerData: n,
    };
  }
  async *getStreamedResponse(e) {
    const n = e.tracing ? Lr() : void 0;
    try {
      n && (n.start(), Te(n));
      const r = await this.#n(e, n, !0),
        o = {
          id: kt,
          created: Math.floor(Date.now() / 1e3),
          model: this.#t,
          object: "chat.completion",
          choices: [],
          usage: { prompt_tokens: 0, completion_tokens: 0, total_tokens: 0 },
        };
      for await (const s of su(o, r)) yield s;
      n && o && e.tracing === !0 && (n.spanData.output = [o]);
    } catch (r) {
      throw (
        n &&
          n.setError({
            message: "Error streaming response",
            data: {
              error:
                e.tracing === !0
                  ? String(r)
                  : r instanceof Error
                    ? r.name
                    : void 0,
            },
          }),
        r
      );
    } finally {
      n && (n.end(), de());
    }
  }
  async #n(e, n, r) {
    const o = [];
    if (e.tools) for (const d of e.tools) o.push(fu(d));
    if (e.handoffs) for (const d of e.handoffs) o.push(mu(d));
    const s = yu(e.outputType);
    let a;
    if (typeof e.modelSettings.parallelToolCalls == "boolean") {
      if (e.modelSettings.parallelToolCalls && o.length === 0)
        throw new Error("Parallel tool calls are not supported without tools");
      a = e.modelSettings.parallelToolCalls;
    }
    const i = lu(e.input);
    (e.systemInstructions &&
      i.unshift({ content: e.systemInstructions, role: "system" }),
      n && e.tracing === !0 && (n.spanData.input = i));
    const f = e.modelSettings.providerData ?? {};
    (e.modelSettings.reasoning &&
      e.modelSettings.reasoning.effort &&
      (f.reasoning_effort = e.modelSettings.reasoning.effort),
      e.modelSettings.text &&
        e.modelSettings.text.verbosity &&
        (f.verbosity = e.modelSettings.text.verbosity));
    const c = {
      model: this.#t,
      messages: i,
      tools: o.length ? o : void 0,
      temperature: e.modelSettings.temperature,
      top_p: e.modelSettings.topP,
      frequency_penalty: e.modelSettings.frequencyPenalty,
      presence_penalty: e.modelSettings.presencePenalty,
      max_tokens: e.modelSettings.maxTokens,
      tool_choice: au(e.modelSettings.toolChoice),
      response_format: s,
      parallel_tool_calls: a,
      stream: r,
      store: e.modelSettings.store,
      ...f,
    };
    L.dontLogModelData
      ? L.debug("Calling LLM")
      : L.debug(`Calling LLM. Request data: ${JSON.stringify(c, null, 2)}`);
    const l = await this.#e.chat.completions.create(c, {
      headers: Ht,
      signal: e.signal,
    });
    return (
      L.dontLogModelData
        ? L.debug("Response received")
        : L.debug(`Response received: ${JSON.stringify(l, null, 2)}`),
      l
    );
  }
}
function yu(t) {
  return t === "text"
    ? { type: "text" }
    : t.type === "json_schema"
      ? {
          type: "json_schema",
          json_schema: { name: t.name, strict: t.strict, schema: t.schema },
        }
      : { type: "json_object" };
}
function _u(t) {
  return {
    requests: 1,
    input_tokens: t.prompt_tokens,
    output_tokens: t.completion_tokens,
    total_tokens: t.total_tokens,
    input_tokens_details: {
      cached_tokens: t.prompt_tokens_details?.cached_tokens || 0,
    },
    output_tokens_details: {
      reasoning_tokens: t.completion_tokens_details?.reasoning_tokens || 0,
    },
  };
}
class vu {
  #e;
  #t;
  #n;
  constructor(e = {}) {
    if (((this.#n = e), this.#n.openAIClient)) {
      if (this.#n.apiKey)
        throw new Error("Cannot provide both apiKey and openAIClient");
      if (this.#n.baseURL)
        throw new Error("Cannot provide both baseURL and openAIClient");
      this.#e = this.#n.openAIClient;
    }
    this.#t = this.#n.useResponses;
  }
  #r() {
    return (
      this.#e ||
        (this.#e =
          Ri() ??
          new So({
            apiKey: this.#n.apiKey ?? Ni(),
            baseURL: this.#n.baseURL,
            organization: this.#n.organization,
            project: this.#n.project,
          })),
      this.#e
    );
  }
  async getModel(e) {
    const n = e || Mt();
    return (this.#t ?? Ci()) ? new ru(this.#r(), n) : new gu(this.#r(), n);
  }
}
class wu {
  #e;
  constructor(e = {}) {
    this.#e = {
      apiKey: e.apiKey ?? void 0,
      organization: e.organization ?? "",
      project: e.project ?? "",
      endpoint: e.endpoint ?? "https://api.openai.com/v1/traces/ingest",
      maxRetries: e.maxRetries ?? 3,
      baseDelay: e.baseDelay ?? 1e3,
      maxDelay: e.maxDelay ?? 3e4,
    };
  }
  async export(e, n) {
    const r = this.#e.apiKey ?? Oi();
    if (!r) {
      L.error(
        "No API key provided for OpenAI tracing exporter. Exports will be skipped",
      );
      return;
    }
    const o = { data: e.map((i) => i.toJSON()).filter((i) => !!i) };
    let s = 0,
      a = this.#e.baseDelay;
    for (; s < this.#e.maxRetries;) {
      try {
        const f = await fetch(this.#e.endpoint, {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            Authorization: `Bearer ${r}`,
            "OpenAI-Beta": "traces=v1",
            ...Ht,
          },
          body: JSON.stringify(o),
          signal: n,
        });
        if (f.ok) {
          L.debug(`Exported ${o.data.length} items`);
          return;
        }
        if (f.status >= 400 && f.status < 500) {
          L.error(
            `[non-fatal] Tracing client error ${f.status}: ${await f.text()}`,
          );
          return;
        }
        L.warn(`[non-fatal] Tracing: server error ${f.status}, retrying.`);
      } catch (f) {
        L.error("[non-fatal] Tracing: request failed: ", f);
      }
      if (n?.aborted) {
        L.error("Tracing: request aborted");
        return;
      }
      const i = a + Math.random() * 0.1 * a;
      (await new Promise((f) => setTimeout(f, i)),
        (a = Math.min(a * 2, this.#e.maxDelay)),
        s++);
    }
    L.error(
      `Tracing: failed to export traces after ${this.#e.maxRetries} attempts`,
    );
  }
}
function bu() {
  const t = new wu(),
    e = new Yr(t);
  Di([e]);
}
const Et = { version: "0.2.1" };
function so(t) {
  const e = atob(t),
    n = e.length,
    r = new Uint8Array(n);
  for (let o = 0; o < n; o++) r[o] = e.charCodeAt(o);
  return r.buffer;
}
function ao(t) {
  const e = String.fromCharCode(...new Uint8Array(t));
  return btoa(e);
}
function io(t) {
  if (
    typeof t > "u" ||
    t === null ||
    typeof t != "object" ||
    !("type" in t) ||
    typeof t.type != "string" ||
    !t.type ||
    t.type !== "message" ||
    !("content" in t) ||
    !Array.isArray(t.content) ||
    t.content.length < 1
  )
    return;
  const e = t.content[t.content.length - 1];
  if (!(!("type" in e) || typeof e.type != "string")) {
    if (e.type === "output_text")
      return typeof e.text == "string" ? e.text : void 0;
    if (e.type === "output_audio")
      return typeof e.transcript == "string" ? e.transcript : void 0;
  }
}
function Su(t, e) {
  const n = t.filter((s) => !e.some((a) => a.itemId === s.itemId)),
    r = e.filter((s) => !t.some((a) => a.itemId === s.itemId)),
    o = e.filter((s) =>
      t.some(
        (a) => a.itemId === s.itemId && JSON.stringify(a) !== JSON.stringify(s),
      ),
    );
  return { removals: n, additions: r, updates: o };
}
function Tu() {
  return typeof window > "u" ? !1 : typeof window.RTCPeerConnection < "u";
}
function Ln(t) {
  return t.role === "system"
    ? t
    : t.role === "assistant"
      ? {
          ...t,
          content: t.content.map((e) =>
            e.type === "output_audio" ? { ...e, audio: null } : e,
          ),
        }
      : t.role === "user"
        ? {
            ...t,
            content: t.content.map((e) =>
              e.type === "input_audio" ? { ...e, audio: null } : e,
            ),
          }
        : t;
}
function $n(t, e, n) {
  if (e.type === "conversation.item.input_audio_transcription.completed")
    return t.map((s) => {
      if (
        s.itemId === e.item_id &&
        s.type === "message" &&
        "role" in s &&
        s.role === "user"
      ) {
        const a = s.content.map((i) =>
          i.type === "input_audio" ? { ...i, transcript: e.transcript } : i,
        );
        return { ...s, content: a, status: "completed" };
      }
      return s;
    });
  const r = !n && e.type === "message" ? Ln(e) : e,
    o = t.findIndex((s) => s.itemId === e.itemId);
  if (o !== -1)
    return t.map((s, a) =>
      a === o ? r : !n && s.type === "message" ? Ln(s) : s,
    );
  if (e.previousItemId) {
    const s = t.findIndex((a) => a.itemId === e.previousItemId);
    return s !== -1 ? [...t.slice(0, s + 1), r, ...t.slice(s + 1)] : [...t, r];
  } else return [...t, r];
}
const uo = {
    "User-Agent": `Agents/JavaScript ${Et.version}`,
    "X-OpenAI-Agents-SDK": `openai-agents-sdk.${Et.version}`,
  },
  Iu = `openai-agents-sdk.${Et.version}`;
function xu(t, e) {
  const { name: n, arguments: r, ...o } = e;
  return new q(
    {
      type: "hosted_tool_call",
      name: n,
      arguments: JSON.stringify(r),
      status: "in_progress",
      providerData: { ...o },
    },
    t,
  );
}
function jn(t) {
  const { name: e, arguments: n, providerData: r } = t.rawItem,
    { itemId: o, serverLabel: s, ...a } = r ?? {};
  if (!o || !s)
    throw new Error("Invalid approval item for Realtime MCP approval request");
  return {
    type: "mcp_approval_request",
    itemId: o,
    serverLabel: s,
    ...a,
    name: e,
    arguments: n ? JSON.parse(n) : {},
    approved: null,
  };
}
class Au extends te {
  voice;
  constructor(e) {
    (super(e), (this.voice = e.voice));
  }
}
function Du(t) {
  return { debounceTextLength: t.debounceTextLength ?? 100 };
}
function ku({ policyHint: t, ...e }) {
  const n = Tt(e),
    r = t ?? n.name;
  return {
    ...n,
    policyHint: r,
    run: async (o) => {
      const s = await n.run(o);
      return { ...s, guardrail: { ...s.guardrail, policyHint: r } };
    },
  };
}
function Eu(t) {
  return `
⚠️ Your last answer was blocked. 
Failed Guardrail Reason: ${t.guardrail.policyHint}. 
Failure Details: ${JSON.stringify(t.output.outputInfo ?? {})}. 
Please respond again following policy. Apologize for not being able to answer the question (while avoiding the specific reason) and divert discussion back to an approved topic immediately and not invite more discussion.
`.trim();
}
function ue(t, e) {
  return t in e && typeof e[t] < "u";
}
function Ou(t) {
  return (
    ue("modalities", t) ||
    ue("inputAudioFormat", t) ||
    ue("outputAudioFormat", t) ||
    ue("inputAudioTranscription", t) ||
    ue("turnDetection", t) ||
    ue("inputAudioNoiseReduction", t) ||
    ue("speed", t)
  );
}
function Cu(t) {
  if (!Ou(t)) {
    const e = t.audio?.input
        ? {
            format: ze(t.audio.input.format),
            noiseReduction: t.audio.input.noiseReduction ?? null,
            transcription: t.audio.input.transcription,
            turnDetection: t.audio.input.turnDetection,
          }
        : void 0,
      n = t.audio?.output?.voice ?? t.voice,
      r =
        t.audio?.output || typeof n < "u"
          ? {
              format: ze(t.audio?.output?.format),
              voice: n,
              speed: t.audio?.output?.speed,
            }
          : void 0;
    return {
      model: t.model,
      instructions: t.instructions,
      toolChoice: t.toolChoice,
      tools: t.tools,
      tracing: t.tracing,
      providerData: t.providerData,
      prompt: t.prompt,
      outputModalities: t.outputModalities,
      audio: e || r ? { input: e, output: r } : void 0,
    };
  }
  return {
    model: t.model,
    instructions: t.instructions,
    toolChoice: t.toolChoice,
    tools: t.tools,
    tracing: t.tracing,
    providerData: t.providerData,
    prompt: t.prompt,
    outputModalities: t.modalities,
    audio: {
      input: {
        format: ze(t.inputAudioFormat),
        noiseReduction: t.inputAudioNoiseReduction ?? null,
        transcription: t.inputAudioTranscription,
        turnDetection: t.turnDetection,
      },
      output: {
        format: ze(t.outputAudioFormat),
        voice: t.voice,
        speed: t.speed,
      },
    },
  };
}
function ze(t) {
  if (!t) return;
  if (typeof t == "object") return t;
  const e = String(t);
  return e === "pcm16"
    ? { type: "audio/pcm", rate: 24e3 }
    : e === "g711_ulaw"
      ? { type: "audio/pcmu" }
      : e === "g711_alaw"
        ? { type: "audio/pcma" }
        : { type: "audio/pcm", rate: 24e3 };
}
h({ itemId: u() });
const Un = G("role", [
    h({
      itemId: u(),
      previousItemId: u().nullable().optional(),
      type: g("message"),
      role: g("system"),
      content: D(h({ type: g("input_text"), text: u() })),
    }),
    h({
      itemId: u(),
      previousItemId: u().nullable().optional(),
      type: g("message"),
      role: g("user"),
      status: N(["in_progress", "completed"]),
      content: D(
        h({ type: g("input_text"), text: u() }).or(
          h({
            type: g("input_audio"),
            audio: u().nullable().optional(),
            transcript: u().nullable(),
          }),
        ),
      ),
    }),
    h({
      itemId: u(),
      previousItemId: u().nullable().optional(),
      type: g("message"),
      role: g("assistant"),
      status: N(["in_progress", "completed", "incomplete"]),
      content: D(
        h({ type: g("output_text"), text: u() }).or(
          h({
            type: g("output_audio"),
            audio: u().nullable().optional(),
            transcript: u().nullable().optional(),
          }),
        ),
      ),
    }),
  ]),
  Jn = h({
    itemId: u(),
    previousItemId: u().nullable().optional(),
    type: g("function_call"),
    status: N(["in_progress", "completed", "incomplete"]),
    arguments: u(),
    name: u(),
    output: u().nullable(),
  }),
  Gn = h({
    itemId: u(),
    previousItemId: u().nullable().optional(),
    type: N(["mcp_call", "mcp_tool_call"]),
    status: N(["in_progress", "completed", "incomplete"]),
    arguments: u(),
    name: u(),
    output: u().nullable(),
  }),
  Ru = h({
    itemId: u(),
    type: g("mcp_approval_request"),
    serverLabel: u(),
    name: u(),
    arguments: P(u(), A()),
    approved: fe().optional().nullable(),
  }),
  Z = Ee("openai-agents:realtime"),
  co = h({
    id: u().optional().nullable(),
    conversation_id: u().optional().nullable(),
    max_output_tokens: w().or(g("inf")).optional().nullable(),
    metadata: P(u(), A()).optional().nullable(),
    output_modalities: D(u()).optional().nullable(),
    object: g("realtime.response").optional().nullable(),
    output: D(A()).optional().nullable(),
    audio: h({
      output: h({
        format: A().optional().nullable(),
        voice: u().optional().nullable(),
      })
        .optional()
        .nullable(),
    })
      .optional()
      .nullable(),
    status: N(["completed", "incomplete", "failed", "cancelled", "in_progress"])
      .optional()
      .nullable(),
    status_details: P(u(), A()).optional().nullable(),
    usage: h({
      input_tokens: w().optional(),
      input_token_details: P(u(), A()).optional().nullable(),
      output_tokens: w().optional(),
      output_token_details: P(u(), A()).optional().nullable(),
    })
      .optional()
      .nullable(),
  }),
  Nu = h({
    id: u().optional(),
    audio: u().nullable().optional(),
    text: u().nullable().optional(),
    transcript: u().nullable().optional(),
    type: ye([
      g("input_text"),
      g("input_audio"),
      g("item_reference"),
      g("output_text"),
      g("output_audio"),
    ]),
  }),
  Oe = h({
    id: u().optional(),
    arguments: u().optional(),
    call_id: u().optional(),
    content: D(Nu).optional(),
    name: u().optional(),
    output: u().nullable().optional(),
    role: N(["user", "assistant", "system"]).optional(),
    status: N(["completed", "incomplete", "in_progress"]).optional(),
    type: N([
      "message",
      "function_call",
      "function_call_output",
      "mcp_list_tools",
      "mcp_tool_call",
      "mcp_call",
      "mcp_approval_request",
      "mcp_approval_response",
    ]).optional(),
    approval_request_id: u().nullable().optional(),
    approve: fe().nullable().optional(),
    reason: u().nullable().optional(),
    server_label: u().optional(),
    error: A().nullable().optional(),
    tools: D(
      h({
        name: u(),
        description: u(),
        input_schema: P(A()).optional(),
      }).passthrough(),
    ).optional(),
  }).passthrough(),
  Pu = h({
    type: g("conversation.created"),
    event_id: u(),
    conversation: h({
      id: u().optional(),
      object: g("realtime.conversation").optional(),
    }),
  }),
  Mu = h({
    type: g("conversation.item.added"),
    event_id: u(),
    item: Oe,
    previous_item_id: u().nullable().optional(),
  }),
  Fu = h({
    type: g("conversation.item.done"),
    event_id: u(),
    item: Oe,
    previous_item_id: u().nullable().optional(),
  }),
  Lu = h({ type: g("conversation.item.deleted"), event_id: u(), item_id: u() }),
  $u = h({
    type: g("conversation.item.input_audio_transcription.completed"),
    event_id: u(),
    item_id: u(),
    content_index: w(),
    transcript: u(),
    logprobs: D(A()).nullable().optional(),
  }),
  ju = h({
    type: g("conversation.item.input_audio_transcription.delta"),
    event_id: u(),
    item_id: u(),
    content_index: w().optional(),
    delta: u().optional(),
    logprobs: D(A()).nullable().optional(),
  }),
  Uu = h({
    type: g("conversation.item.input_audio_transcription.failed"),
    event_id: u(),
    item_id: u(),
    content_index: w(),
    error: h({
      code: u().optional(),
      message: u().optional(),
      param: u().optional(),
      type: u().optional(),
    }),
  }),
  Ju = h({ type: g("conversation.item.retrieved"), event_id: u(), item: Oe }),
  Gu = h({
    type: g("conversation.item.truncated"),
    event_id: u(),
    item_id: u(),
    audio_end_ms: w(),
    content_index: w(),
  }),
  Bu = h({
    type: g("conversation.item.create"),
    item: Oe,
    event_id: u().optional(),
    previous_item_id: u().nullable().optional(),
  }),
  zu = h({
    type: g("conversation.item.delete"),
    item_id: u(),
    event_id: u().optional(),
  }),
  Zu = h({
    type: g("conversation.item.retrieve"),
    item_id: u(),
    event_id: u().optional(),
  }),
  qu = h({
    type: g("conversation.item.truncate"),
    item_id: u(),
    audio_end_ms: w(),
    content_index: w(),
    event_id: u().optional(),
  }),
  Hu = h({ type: g("error"), event_id: u().optional(), error: A().optional() }),
  Ku = h({ type: g("input_audio_buffer.cleared"), event_id: u() }),
  Wu = h({
    type: g("input_audio_buffer.append"),
    audio: u(),
    event_id: u().optional(),
  }),
  Vu = h({ type: g("input_audio_buffer.clear"), event_id: u().optional() }),
  Yu = h({ type: g("input_audio_buffer.commit"), event_id: u().optional() }),
  Xu = h({
    type: g("input_audio_buffer.committed"),
    event_id: u(),
    item_id: u(),
    previous_item_id: u().nullable().optional(),
  }),
  Qu = h({
    type: g("input_audio_buffer.speech_started"),
    event_id: u(),
    item_id: u(),
    audio_start_ms: w(),
  }),
  ec = h({
    type: g("input_audio_buffer.speech_stopped"),
    event_id: u(),
    item_id: u(),
    audio_end_ms: w(),
  }),
  tc = h({
    type: g("output_audio_buffer.started"),
    event_id: u(),
  }).passthrough(),
  nc = h({
    type: g("output_audio_buffer.stopped"),
    event_id: u(),
  }).passthrough(),
  rc = h({ type: g("output_audio_buffer.cleared"), event_id: u() }),
  oc = h({
    type: g("rate_limits.updated"),
    event_id: u(),
    rate_limits: D(
      h({
        limit: w().optional(),
        name: N(["requests", "tokens"]).optional(),
        remaining: w().optional(),
        reset_seconds: w().optional(),
      }),
    ),
  }),
  sc = h({
    type: g("response.output_audio.delta"),
    event_id: u(),
    item_id: u(),
    content_index: w(),
    delta: u(),
    output_index: w(),
    response_id: u(),
  }),
  ac = h({
    type: g("response.output_audio.done"),
    event_id: u(),
    item_id: u(),
    content_index: w(),
    output_index: w(),
    response_id: u(),
  }),
  ic = h({
    type: g("response.output_audio_transcript.delta"),
    event_id: u(),
    item_id: u(),
    content_index: w(),
    delta: u(),
    output_index: w(),
    response_id: u(),
  }),
  uc = h({
    type: g("response.output_audio_transcript.done"),
    event_id: u(),
    item_id: u(),
    content_index: w(),
    transcript: u(),
    output_index: w(),
    response_id: u(),
  }),
  cc = h({
    type: g("response.content_part.added"),
    event_id: u(),
    item_id: u(),
    content_index: w(),
    output_index: w(),
    response_id: u(),
    part: h({
      audio: u().optional(),
      text: u().optional(),
      transcript: u().optional(),
      type: N(["text", "audio"]).optional(),
    }),
  }),
  lc = h({
    type: g("response.content_part.done"),
    event_id: u(),
    item_id: u(),
    content_index: w(),
    output_index: w(),
    response_id: u(),
    part: h({
      audio: u().optional(),
      text: u().optional(),
      transcript: u().optional(),
      type: N(["text", "audio"]).optional(),
    }),
  }),
  pc = h({ type: g("response.created"), event_id: u(), response: co }),
  lo = h({ type: g("response.done"), event_id: u(), response: co }),
  dc = h({
    type: g("response.function_call_arguments.delta"),
    event_id: u(),
    item_id: u(),
    call_id: u(),
    delta: u(),
    output_index: w(),
    response_id: u(),
  }),
  fc = h({
    type: g("response.function_call_arguments.done"),
    event_id: u(),
    item_id: u(),
    call_id: u(),
    arguments: u(),
    output_index: w(),
    response_id: u(),
  }),
  mc = h({
    type: g("response.output_item.added"),
    event_id: u(),
    item: Oe,
    output_index: w(),
    response_id: u(),
  }),
  hc = h({
    type: g("response.output_item.done"),
    event_id: u(),
    item: Oe,
    output_index: w(),
    response_id: u(),
  }),
  gc = h({
    type: g("response.output_text.delta"),
    event_id: u(),
    item_id: u(),
    content_index: w(),
    delta: u(),
    output_index: w(),
    response_id: u(),
  }),
  yc = h({
    type: g("response.output_text.done"),
    event_id: u(),
    item_id: u(),
    content_index: w(),
    text: u(),
    output_index: w(),
    response_id: u(),
  }),
  _c = h({ type: g("session.created"), event_id: u(), session: A() }),
  vc = h({ type: g("session.updated"), event_id: u(), session: A() }),
  wc = h({
    type: g("response.cancel"),
    event_id: u().optional(),
    response_id: u().optional(),
  }),
  bc = h({
    type: g("response.create"),
    event_id: u().optional(),
    response: A().optional(),
  }),
  Sc = h({ type: g("session.update"), event_id: u().optional(), session: A() }),
  Tc = h({
    type: g("mcp_list_tools.in_progress"),
    event_id: u().optional(),
    item_id: u().optional(),
  }),
  Ic = h({
    type: g("mcp_list_tools.completed"),
    event_id: u().optional(),
    item_id: u().optional(),
  }),
  xc = h({
    type: g("response.mcp_call_arguments.delta"),
    event_id: u(),
    response_id: u(),
    item_id: u(),
    output_index: w(),
    delta: u(),
    obfuscation: u(),
  }),
  Ac = h({
    type: g("response.mcp_call_arguments.done"),
    event_id: u(),
    response_id: u(),
    item_id: u(),
    output_index: w(),
    arguments: u(),
  }),
  Dc = h({
    type: g("response.mcp_call.in_progress"),
    event_id: u(),
    output_index: w(),
    item_id: u(),
  }),
  kc = h({
    type: g("response.mcp_call.completed"),
    event_id: u(),
    output_index: w(),
    item_id: u(),
  }),
  Ec = h({
    type: g("mcp_list_tools.failed"),
    event_id: u().optional(),
    item_id: u().optional(),
  }),
  Oc = h({ type: u(), event_id: u().optional().nullable() }).passthrough(),
  Cc = G("type", [
    Pu,
    Mu,
    Fu,
    Lu,
    $u,
    ju,
    Uu,
    Ju,
    Gu,
    Hu,
    Ku,
    Xu,
    Qu,
    ec,
    tc,
    nc,
    rc,
    oc,
    sc,
    ac,
    ic,
    uc,
    cc,
    lc,
    pc,
    lo,
    dc,
    fc,
    mc,
    hc,
    gc,
    yc,
    _c,
    vc,
    Tc,
    Ic,
    Ec,
    xc,
    Ac,
    Dc,
    kc,
  ]);
G("type", [Bu, zu, Zu, qu, Wu, Vu, Yu, wc, bc, Sc]);
function Kt(t) {
  const e = JSON.parse(t.data.toString()),
    n = Cc.safeParse(e);
  if (!n.success) {
    const r = Oc.safeParse(e);
    return r.success
      ? { data: r.data, isGeneric: !0 }
      : { data: null, isGeneric: !0 };
  }
  return { data: n.data, isGeneric: !1 };
}
const po = "gpt-realtime",
  W = {
    outputModalities: ["audio"],
    audio: {
      input: {
        format: { type: "audio/pcm", rate: 24e3 },
        transcription: { model: "gpt-4o-mini-transcribe" },
        turnDetection: { type: "semantic_vad" },
        noiseReduction: null,
      },
      output: { format: { type: "audio/pcm", rate: 24e3 }, speed: 1 },
    },
  };
class je extends Pt {
  #e;
  #t;
  #n = null;
  #r = null;
  eventEmitter = new nt();
  constructor(e = {}) {
    (super(), (this.#e = e.model ?? po), (this.#t = e.apiKey));
  }
  get currentModel() {
    return this.#e;
  }
  set currentModel(e) {
    this.#e = e;
  }
  get _rawSessionConfig() {
    return this.#r ?? null;
  }
  async _getApiKey(e) {
    const n = e.apiKey ?? this.#t;
    return typeof n == "function" ? await n() : n;
  }
  _onMessage(e) {
    const { data: n, isGeneric: r } = Kt(e);
    if (n !== null && (this.emit("*", n), !r)) {
      if (
        (n.type === "error"
          ? this.emit("error", { type: "error", error: n })
          : this.emit(n.type, n),
        n.type === "response.created")
      ) {
        this.emit("turn_started", {
          type: "response_started",
          providerData: { ...n },
        });
        return;
      }
      if (
        (n.type === "session.updated" && (this.#r = n.session),
        n.type === "response.done")
      ) {
        const o = lo.safeParse(n);
        if (!o.success) {
          Z.error("Error parsing response done event", o.error);
          return;
        }
        const s = o.data.response.usage?.input_tokens ?? 0,
          a = o.data.response.usage?.output_tokens ?? 0,
          i = s + a,
          f = new ge({
            inputTokens: s,
            inputTokensDetails:
              o.data.response.usage?.input_token_details ?? {},
            outputTokens: a,
            outputTokensDetails:
              o.data.response.usage?.output_token_details ?? {},
            totalTokens: i,
          });
        (this.emit("usage_update", f),
          this.emit("turn_done", {
            type: "response_done",
            response: {
              id: o.data.response.id ?? "",
              output: o.data.response.output ?? [],
              usage: {
                inputTokens: s,
                inputTokensDetails:
                  o.data.response.usage?.input_token_details ?? {},
                outputTokens: a,
                outputTokensDetails:
                  o.data.response.usage?.output_token_details ?? {},
                totalTokens: i,
              },
            },
          }));
        return;
      }
      if (n.type === "response.output_audio.done") {
        this.emit("audio_done");
        return;
      }
      if (n.type === "conversation.item.deleted") {
        this.emit("item_deleted", { itemId: n.item_id });
        return;
      }
      if (
        n.type === "conversation.item.input_audio_transcription.completed" ||
        n.type === "conversation.item.truncated"
      ) {
        this.sendEvent({
          type: "conversation.item.retrieve",
          item_id: n.item_id,
        });
        return;
      }
      if (
        n.type === "conversation.item.input_audio_transcription.delta" ||
        n.type === "response.output_text.delta" ||
        n.type === "response.output_audio_transcript.delta" ||
        n.type === "response.function_call_arguments.delta"
      ) {
        n.type === "response.output_audio_transcript.delta" &&
          this.emit("audio_transcript_delta", {
            type: "transcript_delta",
            delta: n.delta,
            itemId: n.item_id,
            responseId: n.response_id,
          });
        return;
      }
      if (
        n.type === "conversation.item.added" ||
        n.type === "conversation.item.done" ||
        n.type === "conversation.item.retrieved"
      ) {
        if (
          n.item.type === "mcp_list_tools" &&
          n.type === "conversation.item.done"
        ) {
          const o = n.item.server_label ?? "",
            s = n.item.tools ?? [];
          try {
            this.emit("mcp_tools_listed", { serverLabel: o, tools: s });
          } catch (a) {
            Z.error("Error emitting mcp_tools_listed", a, n.item);
          }
          return;
        }
        if (n.item.type === "message") {
          const o =
              n.type === "conversation.item.added" ||
              n.type === "conversation.item.done"
                ? n.previous_item_id
                : null,
            s = Un.parse({
              itemId: n.item.id,
              previousItemId: o,
              type: n.item.type,
              role: n.item.role,
              content: n.item.content,
              status: n.item.status,
            });
          this.emit("item_update", s);
          return;
        }
        if (
          n.item.type === "mcp_approval_request" &&
          n.type === "conversation.item.done"
        ) {
          const o = n.item,
            s = Ru.parse({
              itemId: o.id,
              type: o.type,
              serverLabel: o.server_label,
              name: o.name,
              arguments: JSON.parse(o.arguments || "{}"),
              approved: o.approved,
            });
          (this.emit("item_update", s), this.emit("mcp_approval_request", s));
          return;
        }
        if (n.item.type === "mcp_tool_call" || n.item.type === "mcp_call") {
          const o =
              n.type === "conversation.item.done" ? "completed" : "in_progress",
            s = Gn.parse({
              itemId: n.item.id,
              type: n.item.type,
              status: o,
              arguments: n.item.arguments,
              name: n.item.name,
              output: n.item.output,
            });
          (this.emit("item_update", s),
            n.type === "conversation.item.done" &&
              this.emit("mcp_tool_call_completed", s));
          return;
        }
      }
      if (n.type === "response.mcp_call.in_progress") {
        const o = n;
        this.sendEvent({
          type: "conversation.item.retrieve",
          item_id: o.item_id,
        });
        return;
      }
      if (n.type === "mcp_list_tools.in_progress") {
        const o = n;
        o.item_id &&
          this.sendEvent({
            type: "conversation.item.retrieve",
            item_id: o.item_id,
          });
        return;
      }
      if (
        n.type === "response.output_item.done" ||
        n.type === "response.output_item.added"
      ) {
        const o = n.item;
        if (o.type === "function_call" && o.status === "completed") {
          const s = Jn.parse({
            itemId: o.id,
            type: o.type,
            status: "in_progress",
            arguments: o.arguments,
            name: o.name,
            output: null,
          });
          (this.emit("item_update", s),
            this.emit("function_call", {
              id: o.id,
              type: "function_call",
              callId: o.call_id ?? "",
              arguments: o.arguments ?? "",
              name: o.name ?? "",
            }));
          return;
        }
        if (o.type === "mcp_tool_call" || o.type === "mcp_call") {
          const s = Gn.parse({
            itemId: o.id,
            type: o.type,
            status:
              n.type === "response.output_item.done"
                ? "completed"
                : "in_progress",
            arguments: o.arguments,
            name: o.name,
            output: o.output,
          });
          this.emit("item_update", s);
          return;
        }
        if (o.type === "message") {
          const s = Un.parse({
            itemId: n.item.id,
            type: n.item.type,
            role: n.item.role,
            content: n.item.content,
            status:
              n.type === "response.output_item.done"
                ? (o.status ?? "completed")
                : (o.status ?? "in_progress"),
          });
          this.emit("item_update", s);
          return;
        }
      }
    }
  }
  _onError(e) {
    this.emit("error", { type: "error", error: e });
  }
  _onOpen() {
    this.emit("connected");
  }
  _onClose() {
    this.emit("disconnected");
  }
  sendMessage(e, n, { triggerResponse: r = !0 } = {}) {
    const o =
      typeof e == "string"
        ? [{ type: "input_text", text: e }]
        : e.content.map((s) =>
            s.type === "input_image"
              ? {
                  type: "input_image",
                  image_url: s.image,
                  ...(s.providerData ?? {}),
                }
              : s,
          );
    (this.sendEvent({
      type: "conversation.item.create",
      item: { type: "message", role: "user", content: o },
      ...n,
    }),
      r && this.sendEvent({ type: "response.create" }));
  }
  addImage(e, { triggerResponse: n = !0 } = {}) {
    this.sendMessage(
      {
        type: "message",
        role: "user",
        content: [{ type: "input_image", image: e }],
      },
      {},
      { triggerResponse: n },
    );
  }
  _getMergedSessionConfig(e) {
    const n = Cu(e),
      r = {
        type: "realtime",
        instructions: n.instructions,
        model: n.model ?? this.#e,
        output_modalities: n.outputModalities ?? W.outputModalities,
        audio: {
          input: {
            format: n.audio?.input?.format ?? W.audio?.input?.format,
            noise_reduction:
              n.audio?.input?.noiseReduction ?? W.audio?.input?.noiseReduction,
            transcription:
              n.audio?.input?.transcription ?? W.audio?.input?.transcription,
            turn_detection:
              je.buildTurnDetectionConfig(n.audio?.input?.turnDetection) ??
              W.audio?.input?.turnDetection,
          },
          output: {
            format: n.audio?.output?.format ?? W.audio?.output?.format,
            voice: n.audio?.output?.voice ?? W.audio?.output?.voice,
            speed: n.audio?.output?.speed ?? W.audio?.output?.speed,
          },
        },
        tool_choice: n.toolChoice ?? W.toolChoice,
        ...(n.providerData ?? {}),
      };
    return (
      n.prompt &&
        (r.prompt = {
          id: n.prompt.promptId,
          version: n.prompt.version,
          variables: n.prompt.variables,
        }),
      n.tools &&
        n.tools.length > 0 &&
        (r.tools = n.tools.map((o) => ({ ...o, strict: void 0 }))),
      r
    );
  }
  static buildTurnDetectionConfig(e) {
    if (typeof e > "u") return;
    const {
        type: n,
        createResponse: r,
        create_response: o,
        eagerness: s,
        interruptResponse: a,
        interrupt_response: i,
        prefixPaddingMs: f,
        prefix_padding_ms: c,
        silenceDurationMs: l,
        silence_duration_ms: d,
        threshold: m,
        idleTimeoutMs: y,
        idle_timeout_ms: p,
        ...v
      } = e,
      _ = {
        type: n,
        create_response: r || o,
        eagerness: s,
        interrupt_response: a || i,
        prefix_padding_ms: f || c,
        silence_duration_ms: l || d,
        idle_timeout_ms: y || p,
        threshold: m,
        ...v,
      };
    return (
      Object.keys(_).forEach((T) => {
        _[T] === void 0 && delete _[T];
      }),
      Object.keys(_).length > 0 ? _ : void 0
    );
  }
  set _tracingConfig(e) {
    this.#n = e;
  }
  _updateTracingConfig(e) {
    if ((typeof this.#n > "u" && (this.#n = null), e === "auto")) {
      this.sendEvent({
        type: "session.update",
        session: { type: "realtime", tracing: "auto" },
      });
      return;
    }
    if (
      this.#n !== null &&
      typeof this.#n != "string" &&
      typeof e != "string"
    ) {
      Z.warn(
        "Tracing config is already set, skipping setting it again. This likely happens when you already set a tracing config on session creation.",
      );
      return;
    }
    if (e === null) {
      (Z.debug(
        "Disabling tracing for this session. It cannot be turned on for this session from this point on.",
      ),
        this.sendEvent({
          type: "session.update",
          session: { type: "realtime", tracing: null },
        }));
      return;
    }
    if (this.#n === null || typeof this.#n == "string") {
      this.sendEvent({
        type: "session.update",
        session: { type: "realtime", tracing: e },
      });
      return;
    }
    if (
      e?.group_id !== this.#n?.group_id ||
      e?.metadata !== this.#n?.metadata ||
      e?.workflow_name !== this.#n?.workflow_name
    ) {
      Z.warn(
        "Mismatch in tracing config. Ignoring the new tracing config. This likely happens when you already set a tracing config on session creation. Current tracing config: %s, new tracing config: %s",
        JSON.stringify(this.#n),
        JSON.stringify(e),
      );
      return;
    }
    this.sendEvent({
      type: "session.update",
      session: { type: "realtime", tracing: e },
    });
  }
  updateSessionConfig(e) {
    const n = this._getMergedSessionConfig(e);
    this.sendEvent({ type: "session.update", session: n });
  }
  sendFunctionCallOutput(e, n, r = !0) {
    this.sendEvent({
      type: "conversation.item.create",
      item: { type: "function_call_output", output: n, call_id: e.callId },
    });
    try {
      const o = Jn.parse({
        itemId: e.id,
        previousItemId: e.previousItemId,
        type: "function_call",
        status: "completed",
        arguments: e.arguments,
        name: e.name,
        output: n,
      });
      this.emit("item_update", o);
    } catch (o) {
      Z.error("Error parsing tool call item", o, e);
    }
    r && this.sendEvent({ type: "response.create" });
  }
  sendAudio(e, { commit: n = !1 } = {}) {
    (this.sendEvent({ type: "input_audio_buffer.append", audio: ao(e) }),
      n && this.sendEvent({ type: "input_audio_buffer.commit" }));
  }
  resetHistory(e, n) {
    const { removals: r, additions: o, updates: s } = Su(e, n),
      a = new Set(r.map((f) => f.itemId));
    for (const f of s) a.add(f.itemId);
    if (a.size > 0)
      for (const f of a)
        this.sendEvent({ type: "conversation.item.delete", item_id: f });
    const i = [...o, ...s];
    for (const f of i)
      if (f.type === "message") {
        const c = {
          type: "message",
          role: f.role,
          content: f.content,
          id: f.itemId,
        };
        (f.role !== "system" && f.status && (c.status = f.status),
          this.sendEvent({ type: "conversation.item.create", item: c }));
      } else
        f.type === "function_call" &&
          Z.warn(
            "Function calls cannot be manually added or updated at the moment. Ignoring.",
          );
  }
  sendMcpResponse(e, n) {
    this.sendEvent({
      type: "conversation.item.create",
      previous_item_id: e.itemId,
      item: {
        type: "mcp_approval_response",
        approval_request_id: e.itemId,
        approve: n,
      },
    });
  }
}
class fo extends je {
  options;
  #e;
  #t = {
    status: "disconnected",
    peerConnection: void 0,
    dataChannel: void 0,
    callId: void 0,
  };
  #n;
  #r = !1;
  #a = !1;
  constructor(e = {}) {
    if (typeof RTCPeerConnection > "u")
      throw new Error("WebRTC is not supported in this environment");
    (super(e),
      (this.options = e),
      (this.#e = e.baseUrl ?? "https://api.openai.com/v1/realtime/calls"),
      (this.#n = e.useInsecureApiKey ?? !1));
  }
  get callId() {
    return this.#t.callId;
  }
  get status() {
    return this.#t.status;
  }
  get connectionState() {
    return this.#t;
  }
  get muted() {
    return this.#a;
  }
  async connect(e) {
    if (this.#t.status === "connected") return;
    this.#t.status === "connecting" &&
      Z.warn(
        "Realtime connection already in progress. Please await original promise",
      );
    const n = e.model ?? this.currentModel;
    this.currentModel = n;
    const r = e.url ?? this.#e,
      o = await this._getApiKey(e),
      s = typeof o == "string" && o.startsWith("ek_");
    if (!this.#n && !s)
      throw new k(
        "Using the WebRTC connection in a browser environment requires an ephemeral client key. If you need to use a regular API key, use the WebSocket transport or set the `useInsecureApiKey` option to true.",
      );
    return new Promise(async (a, i) => {
      try {
        const f = {
            ...(e.initialSessionConfig || {}),
            model: this.currentModel,
          },
          c = new URL(r);
        let l = new RTCPeerConnection();
        const d = l.createDataChannel("oai-events");
        let m;
        ((this.#t = {
          status: "connecting",
          peerConnection: l,
          dataChannel: d,
          callId: m,
        }),
          this.emit("connection_change", this.#t.status),
          d.addEventListener("open", () => {
            ((this.#t = {
              status: "connected",
              peerConnection: l,
              dataChannel: d,
              callId: m,
            }),
              this.updateSessionConfig(f),
              this.emit("connection_change", this.#t.status),
              this._onOpen(),
              a());
          }),
          d.addEventListener("error", (b) => {
            (this.close(), this._onError(b), i(b));
          }),
          d.addEventListener("message", (b) => {
            this._onMessage(b);
            const { data: I, isGeneric: E } = Kt(b);
            !I ||
              E ||
              (I.type === "response.created"
                ? (this.#r = !0)
                : I.type === "response.done" && (this.#r = !1),
              I.type === "session.created" &&
                ((this._tracingConfig = I.session.tracing),
                this._updateTracingConfig(f.tracing ?? "auto")));
          }));
        const y = this.options.audioElement ?? document.createElement("audio");
        ((y.autoplay = !0),
          (l.ontrack = (b) => {
            y.srcObject = b.streams[0];
          }));
        const p =
          this.options.mediaStream ??
          (await navigator.mediaDevices.getUserMedia({ audio: !0 }));
        (l.addTrack(p.getAudioTracks()[0]),
          this.options.changePeerConnection &&
            ((l = await this.options.changePeerConnection(l)),
            (this.#t = { ...this.#t, peerConnection: l })));
        const v = await l.createOffer();
        if ((await l.setLocalDescription(v), !v.sdp))
          throw new Error("Failed to create offer");
        const _ = await fetch(c, {
          method: "POST",
          body: v.sdp,
          headers: {
            "Content-Type": "application/sdp",
            Authorization: `Bearer ${o}`,
            "X-OpenAI-Agents-SDK": uo["X-OpenAI-Agents-SDK"],
          },
        });
        ((m = _.headers?.get("Location")?.split("/").pop()),
          (this.#t = { ...this.#t, callId: m }));
        const T = { type: "answer", sdp: await _.text() };
        await l.setRemoteDescription(T);
      } catch (f) {
        (this.close(), this._onError(f), i(f));
      }
    });
  }
  sendEvent(e) {
    if (!this.#t.dataChannel || this.#t.dataChannel.readyState !== "open")
      throw new Error(
        "WebRTC data channel is not connected. Make sure you call `connect()` before sending events.",
      );
    this.#t.dataChannel.send(JSON.stringify(e));
  }
  mute(e) {
    ((this.#a = e),
      this.#t.peerConnection &&
        this.#t.peerConnection.getSenders().forEach((r) => {
          r.track && (r.track.enabled = !e);
        }));
  }
  close() {
    if (
      (this.#t.dataChannel && this.#t.dataChannel.close(),
      this.#t.peerConnection)
    ) {
      const e = this.#t.peerConnection;
      (e.getSenders().forEach((n) => {
        n.track?.stop();
      }),
        e.close());
    }
    this.#t.status !== "disconnected" &&
      ((this.#t = {
        status: "disconnected",
        peerConnection: void 0,
        dataChannel: void 0,
        callId: void 0,
      }),
      this.emit("connection_change", this.#t.status),
      this._onClose());
  }
  interrupt() {
    (this.#r && (this.sendEvent({ type: "response.cancel" }), (this.#r = !1)),
      this.sendEvent({ type: "output_audio_buffer.clear" }));
  }
}
const Rc = globalThis.WebSocket;
class mo extends je {
  #e;
  #t;
  #n = { status: "disconnected", websocket: void 0 };
  #r;
  #a;
  #s;
  _firstAudioTimestamp;
  _audioLengthMs = 0;
  #i = !1;
  #o;
  #u;
  constructor(e = {}) {
    (super(e),
      (this.#t = e.url),
      (this.#r = e.useInsecureApiKey ?? !1),
      (this.#o = e.createWebSocket),
      (this.#u = e.skipOpenEventListeners ?? !1));
  }
  getCommonRequestHeaders() {
    return uo;
  }
  get status() {
    return this.#n.status;
  }
  get connectionState() {
    return this.#n;
  }
  get muted() {
    return null;
  }
  get currentItemId() {
    return this.#a;
  }
  _onAudio(e) {
    this.emit("audio", e);
  }
  async #p(e, n, r) {
    if (this.#n.websocket) {
      e();
      return;
    }
    if (!this.#e)
      throw new k(
        "API key is not set. Please call `connect()` with an API key first.",
      );
    if (!this.#e.startsWith("ek_") && !this.#r)
      throw new k(
        "Using the WebSocket connection in a browser environment requires an ephemeral client key. If you have to use a regular API key, set the `useInsecureApiKey` option to true.",
      );
    let o = null;
    if (this.#o) o = await this.#o({ url: this.#t, apiKey: this.#e });
    else {
      const a = ["realtime", "openai-insecure-api-key." + this.#e, Iu];
      o = new Rc(this.#t, a);
    }
    ((this.#n = { status: "connecting", websocket: o }),
      this.emit("connection_change", this.#n.status));
    const s = () => {
      ((this.#n = { status: "connected", websocket: o }),
        this.emit("connection_change", this.#n.status),
        this._onOpen(),
        e());
    };
    (this.#u === !0 ? s() : o.addEventListener("open", s),
      o.addEventListener("error", (a) => {
        (this._onError(a),
          (this.#n = { status: "disconnected", websocket: void 0 }),
          this.emit("connection_change", this.#n.status),
          n(a));
      }),
      o.addEventListener("message", (a) => {
        this._onMessage(a);
        const { data: i, isGeneric: f } = Kt(a);
        if (!(!i || f))
          if (i.type === "response.output_audio.delta") {
            ((this.#s = i.content_index),
              (this.#a = i.item_id),
              this._firstAudioTimestamp === void 0 &&
                ((this._firstAudioTimestamp = Date.now()),
                (this._audioLengthMs = 0)));
            const c = so(i.delta),
              l = this._rawSessionConfig?.audio?.output?.format;
            if (l && typeof l == "object") {
              const m = l.type;
              if (m === "audio/pcmu" || m === "audio/pcma")
                this._audioLengthMs += c.byteLength / 8;
              else if (m === "audio/pcm") {
                const y = l.rate ?? 24e3;
                this._audioLengthMs += (c.byteLength / 2 / y) * 1e3;
              } else this._audioLengthMs += c.byteLength / 24 / 2;
            } else
              typeof l == "string"
                ? l.startsWith("g711_")
                  ? (this._audioLengthMs += c.byteLength / 8)
                  : (this._audioLengthMs += c.byteLength / 24 / 2)
                : (this._audioLengthMs += c.byteLength / 24 / 2);
            const d = { type: "audio", data: c, responseId: i.response_id };
            this._onAudio(d);
          } else if (i.type === "input_audio_buffer.speech_started") {
            const c =
              this._rawSessionConfig?.audio?.input?.turn_detection
                ?.interrupt_response ?? !1;
            this.interrupt(!c);
          } else
            i.type === "response.created"
              ? (this.#i = !0)
              : i.type === "response.done"
                ? (this.#i = !1)
                : i.type === "session.created" &&
                  ((this._tracingConfig = i.session.tracing),
                  this._updateTracingConfig(r.tracing ?? "auto"));
      }),
      o.addEventListener("close", () => {
        ((this.#n = { status: "disconnected", websocket: void 0 }),
          this.emit("connection_change", this.#n.status),
          this._onClose());
      }));
  }
  async connect(e) {
    const n = e.model ?? this.currentModel;
    ((this.currentModel = n), (this.#e = await this._getApiKey(e)));
    const r =
      e.url ??
      this.#t ??
      `wss://api.openai.com/v1/realtime?model=${this.currentModel}`;
    this.#t = r;
    const o = { ...(e.initialSessionConfig || {}), model: this.currentModel };
    (await new Promise((s, a) => {
      this.#p(s, a, o).catch(a);
    }),
      await this.updateSessionConfig(o));
  }
  sendEvent(e) {
    if (!this.#n.websocket)
      throw new Error(
        "WebSocket is not connected. Make sure you call `connect()` before sending events.",
      );
    this.#n.websocket.send(JSON.stringify(e));
  }
  close() {
    (this.#n.websocket?.close(),
      (this.#a = void 0),
      (this._firstAudioTimestamp = void 0),
      (this._audioLengthMs = 0),
      (this.#s = void 0));
  }
  mute(e) {
    throw new Error(
      "Mute is not supported for the WebSocket transport. You have to mute the audio input yourself.",
    );
  }
  sendAudio(e, n = {}) {
    this.#n.status === "connected" && super.sendAudio(e, n);
  }
  _cancelResponse() {
    this.#i && (this.sendEvent({ type: "response.cancel" }), (this.#i = !1));
  }
  _interrupt(e, n = !0) {
    if (e < 0) return;
    n && this._cancelResponse();
    const r = this._audioLengthMs ?? Number.POSITIVE_INFINITY,
      o = Math.max(0, Math.floor(Math.min(e, r)));
    (this.emit("audio_interrupted"),
      this.sendEvent({
        type: "conversation.item.truncate",
        item_id: this.#a,
        content_index: this.#s,
        audio_end_ms: o,
      }));
  }
  interrupt(e = !0) {
    if (!this.#a || typeof this._firstAudioTimestamp != "number") return;
    const n = Date.now() - this._firstAudioTimestamp;
    (n >= 0 && this._interrupt(n, e),
      (this.#a = void 0),
      (this._firstAudioTimestamp = void 0),
      (this._audioLengthMs = 0),
      (this.#s = void 0));
  }
}
const ho = Symbol("backgroundResult");
function Nc(t) {
  return { [ho]: !0, content: t };
}
function go(t) {
  return typeof t == "object" && t !== null && ho in t;
}
function Pc(t) {
  return (
    t.type === "function" ||
    (t.type === "hosted_tool" && t.name === "hosted_mcp")
  );
}
function Mc(t) {
  if (t.type === "function") return t;
  if (t.type === "hosted_tool" && t.name === "hosted_mcp") {
    const e =
      t.providerData.server_url && t.providerData.server_url.length > 0
        ? t.providerData.server_url
        : void 0;
    return {
      type: "mcp",
      server_label: t.providerData.server_label,
      server_url: e,
      headers: t.providerData.headers,
      allowed_tools: t.providerData.allowed_tools,
      require_approval: t.providerData.require_approval,
    };
  }
  throw new k(`Invalid tool type: ${t}`);
}
function Fc() {
  return JSON.parse(JSON.stringify(W));
}
class Lc extends nt {
  initialAgent;
  options;
  #e;
  #t;
  #n;
  #r;
  #a = [];
  #s;
  #i = {};
  #o = [];
  #u;
  #p = {};
  #c = !1;
  #d = new Map();
  #l = [];
  #g = Fc();
  #y = !0;
  constructor(e, n = {}) {
    (super(),
      (this.initialAgent = e),
      (this.options = n),
      (typeof n.transport > "u" && Tu()) || n.transport === "webrtc"
        ? (this.#e = new fo())
        : n.transport === "websocket" || typeof n.transport > "u"
          ? (this.#e = new mo())
          : (this.#e = n.transport),
      (this.#t = e),
      (this.#r = new we({ ...(n.context ?? {}), history: this.#o })),
      (this.#a = (n.outputGuardrails ?? []).map(ku)),
      (this.#s = Du(n.outputGuardrailSettings ?? {})),
      (this.#u = n.historyStoreAudio ?? !1),
      (this.#y = n.automaticallyTriggerResponseForMcpToolCalls ?? !0));
  }
  get transport() {
    return this.#e;
  }
  get currentAgent() {
    return this.#t;
  }
  get usage() {
    return this.#r.usage;
  }
  get context() {
    return this.#r;
  }
  get muted() {
    return this.#e.muted;
  }
  get history() {
    return this.#o;
  }
  get availableMcpTools() {
    return this.#l;
  }
  async #f(e) {
    this.#t = e;
    const n = await this.#t.getEnabledHandoffs(this.#r),
      r = n.map((i) => i.getHandoffAsFunctionTool()),
      o = (await this.#t.getAllTools(this.#r)).filter(Pc).map(Mc),
      s = typeof this.#t.tools < "u" || typeof this.#t.mcpServers < "u",
      a = n.length > 0;
    ((this.#n = s || a ? [...o, ...r] : void 0), this.#v());
  }
  async #m(e = {}) {
    const n = await this.#t.getSystemPrompt(this.#r),
      r = this.options.tracingDisabled
        ? null
        : this.options.workflowName
          ? { workflow_name: this.options.workflowName }
          : "auto";
    r !== null && r !== "auto"
      ? (this.options.groupId && (r.group_id = this.options.groupId),
        this.options.traceMetadata && (r.metadata = this.options.traceMetadata))
      : (this.options.groupId || this.options.traceMetadata) &&
        Z.warn(
          "In order to set traceMetadata or a groupId you need to specify a workflowName.",
        );
    const s = {
      ...{ ...(this.#g ?? {}), ...(this.options.config ?? {}), ...(e ?? {}) },
      instructions: n,
      voice: this.#t.voice,
      model: this.options.model,
      tools: this.#n,
      tracing: r,
      prompt:
        typeof this.#t.prompt == "function"
          ? await this.#t.prompt(this.#r, this.#t)
          : this.#t.prompt,
    };
    return ((this.#g = s), s);
  }
  async updateAgent(e) {
    return (
      this.#t.emit("agent_handoff", this.#r, e),
      this.emit("agent_handoff", this.#r, this.#t, e),
      await this.#f(e),
      await this.#e.updateSessionConfig(await this.#m()),
      e
    );
  }
  async #w(e, n) {
    const r = await n.onInvokeHandoff(this.#r, e.arguments);
    (this.#t.emit("agent_handoff", this.#r, r),
      this.emit("agent_handoff", this.#r, this.#t, r),
      await this.#f(r),
      await this.#e.updateSessionConfig(await this.#m()));
    const o = dr(r);
    return (this.#e.sendFunctionCallOutput(e, o, !0), r);
  }
  async #h(e, n) {
    this.#r.context.history = JSON.parse(JSON.stringify(this.#o));
    let r = e.arguments;
    if (
      (n.parameters &&
        (he(n.parameters) ? (r = n.parameters.parse(r)) : (r = JSON.parse(r))),
      await n.needsApproval(this.#r, r, e.callId))
    ) {
      const i = this.context.isToolApproved({
        toolName: n.name,
        callId: e.callId,
      });
      if (i === !1) {
        (this.emit("agent_tool_start", this.#r, this.#t, n, { toolCall: e }),
          this.#t.emit("agent_tool_start", this.#r, n, { toolCall: e }));
        const f = "Tool execution was not approved.";
        (this.#e.sendFunctionCallOutput(e, f, !0),
          this.emit("agent_tool_end", this.#r, this.#t, n, f, { toolCall: e }),
          this.#t.emit("agent_tool_end", this.#r, n, f, { toolCall: e }));
        return;
      } else if (typeof i > "u") {
        this.emit("tool_approval_requested", this.#r, this.#t, {
          type: "function_approval",
          tool: n,
          approvalItem: new q(e, this.#t),
        });
        return;
      }
    }
    (this.emit("agent_tool_start", this.#r, this.#t, n, { toolCall: e }),
      this.#t.emit("agent_tool_start", this.#r, n, { toolCall: e }),
      (this.#r.context.history = JSON.parse(JSON.stringify(this.#o))));
    const s = await n.invoke(this.#r, e.arguments, { toolCall: e });
    let a;
    (go(s)
      ? ((a = oe(s.content)), this.#e.sendFunctionCallOutput(e, a, !1))
      : ((a = oe(s)), this.#e.sendFunctionCallOutput(e, a, !0)),
      this.emit("agent_tool_end", this.#r, this.#t, n, a, { toolCall: e }),
      this.#t.emit("agent_tool_end", this.#r, n, a, { toolCall: e }));
  }
  async #b(e) {
    const n = await this.#t.getEnabledHandoffs(this.#r),
      r = new Map(n.map((i) => [i.toolName, i])),
      o = await this.#t.getAllTools(this.#r),
      s = new Map(o.map((i) => [i.name, i])),
      a = r.get(e.name);
    if (a) await this.#w(e, a);
    else {
      const i = s.get(e.name);
      if (i && i.type === "function") await this.#h(e, i);
      else throw new B(`Tool ${e.name} not found`);
    }
  }
  async #_(e, n, r) {
    if (this.#a.length === 0) return;
    const o = { agent: this.#t, agentOutput: e, context: this.#r },
      a = (await Promise.all(this.#a.map((i) => i.run(o)))).find(
        (i) => i.output.tripwireTriggered,
      );
    if (a) {
      if (this.#p[n]) return;
      this.#p[n] = !0;
      const i = new Ke(
        `Output guardrail triggered: ${JSON.stringify(a.output.outputInfo)}`,
        a,
      );
      (this.emit("guardrail_tripped", this.#r, this.#t, i, { itemId: r }),
        this.interrupt());
      const f = Eu(a);
      this.sendMessage(f);
      return;
    }
  }
  #S() {
    (this.#e.on("*", (r) => {
      if (
        (this.emit("transport_event", r),
        r.type === "conversation.item.input_audio_transcription.completed")
      )
        try {
          const o = r;
          ((this.#o = $n(this.#o, o, this.#u)),
            (this.#r.context.history = this.#o),
            this.emit("history_updated", this.#o));
        } catch (o) {
          this.emit("error", { type: "error", error: o });
        }
    }),
      this.#e.on("mcp_tools_listed", ({ serverLabel: r, tools: o }) => {
        try {
          (this.#d.set(r, o ?? []), this.#v());
        } catch (s) {
          this.emit("error", { type: "error", error: s });
        }
      }),
      this.#e.on("audio", (r) => {
        (this.#c ||
          ((this.#c = !0), this.emit("audio_start", this.#r, this.#t)),
          this.emit("audio", r));
      }),
      this.#e.on("turn_started", () => {
        ((this.#c = !1),
          this.emit("agent_start", this.#r, this.#t),
          this.#t.emit("agent_start", this.#r, this.#t));
      }),
      this.#e.on("turn_done", (r) => {
        const o = r.response.output[r.response.output.length - 1],
          s = io(o) ?? "",
          a = o?.id ?? "";
        (this.emit("agent_end", this.#r, this.#t, s),
          this.#t.emit("agent_end", this.#r, s),
          this.#_(s, r.response.id, a));
      }),
      this.#e.on("audio_done", () => {
        (this.#c && (this.#c = !1),
          this.emit("audio_stopped", this.#r, this.#t));
      }));
    let e = 0,
      n;
    (this.#e.on("audio_transcript_delta", (r) => {
      try {
        const o = r.delta,
          s = r.itemId,
          a = r.responseId;
        n !== s && ((n = s), (e = 0));
        const f = (this.#i[s] ?? "") + o;
        if (((this.#i[s] = f), this.#s.debounceTextLength < 0)) return;
        const c = Math.floor(f.length / this.#s.debounceTextLength);
        c > e && ((e = c), this.#_(f, a, s));
      } catch (o) {
        this.emit("error", { type: "error", error: o });
      }
    }),
      this.#e.on("item_update", (r) => {
        try {
          const o = !this.#o.some((s) => s.itemId === r.itemId);
          if (
            ((this.#o = $n(this.#o, r, this.#u)),
            (this.#r.context.history = this.#o),
            o)
          ) {
            const s = this.#o.find((a) => a.itemId === r.itemId);
            s && this.emit("history_added", s);
          }
          this.emit("history_updated", this.#o);
        } catch (o) {
          this.emit("error", { type: "error", error: o });
        }
      }),
      this.#e.on("item_deleted", (r) => {
        try {
          ((this.#o = this.#o.filter((o) => o.itemId !== r.itemId)),
            (this.#r.context.history = this.#o),
            this.emit("history_updated", this.#o));
        } catch (o) {
          this.emit("error", { type: "error", error: o });
        }
      }),
      this.#e.on("function_call", async (r) => {
        try {
          await this.#b(r);
        } catch (o) {
          (Z.error("Error handling function call", o),
            this.emit("error", { type: "error", error: o }));
        }
      }),
      this.#e.on("usage_update", (r) => {
        this.#r.usage.add(r);
      }),
      this.#e.on("audio_interrupted", () => {
        (this.#c && (this.#c = !1),
          this.emit("audio_interrupted", this.#r, this.#t));
      }),
      this.#e.on("error", (r) => {
        this.emit("error", r);
      }),
      this.#e.on("mcp_tool_call_completed", (r) => {
        (this.emit("mcp_tool_call_completed", this.#r, this.#t, r),
          this.#y && this.#e.sendEvent({ type: "response.create" }));
      }),
      this.#e.on("mcp_approval_request", (r) => {
        this.emit("tool_approval_requested", this.#r, this.#t, {
          type: "mcp_approval_request",
          approvalItem: xu(this.#t, r),
        });
      }));
  }
  #v() {
    const e = this.#n?.filter((i) => i.type === "mcp"),
      n = (i) => {
        const f = i.allowed_tools;
        if (f) {
          if (Array.isArray(f)) return f;
          if (f && Array.isArray(f.tool_names)) return f.tool_names;
        }
      },
      r = new Map();
    for (const i of e) {
      const f = this.#d.get(i.server_label) ?? [],
        c = n(i);
      for (const l of f)
        (c && !c.includes(l.name)) || r.has(l.name) || r.set(l.name, l);
    }
    const o = Array.from(r.values()),
      s = this.#l;
    (s.length !== o.length ||
      JSON.stringify(s.map((i) => i.name).sort()) !==
        JSON.stringify(o.map((i) => i.name).sort())) &&
      ((this.#l = o), this.emit("mcp_tools_changed", this.#l));
  }
  async connect(e) {
    (await this.#f(this.initialAgent),
      this.#S(),
      await this.#e.connect({
        apiKey: e.apiKey ?? this.options.apiKey,
        model: this.options.model,
        url: e.url,
        initialSessionConfig: await this.#m(this.options.config),
      }),
      (this.#o = []),
      this.emit("history_updated", this.#o));
  }
  updateHistory(e) {
    let n;
    (typeof e == "function" ? (n = e(this.#o)) : (n = e),
      this.#e.resetHistory(this.#o, n));
  }
  sendMessage(e, n = {}) {
    this.#e.sendMessage(e, n);
  }
  addImage(e, { triggerResponse: n = !0 } = {}) {
    this.#e.addImage(e, { triggerResponse: n });
  }
  mute(e) {
    this.#e.mute(e);
  }
  close() {
    ((this.#p = {}), this.#e.close());
  }
  sendAudio(e, n = {}) {
    this.#e.sendAudio(e, n);
  }
  interrupt() {
    this.#e.interrupt();
  }
  async approve(e, n = { alwaysApprove: !1 }) {
    this.#r.approveTool(e, n);
    const r = this.#t.tools.find((o) => o.name === e.rawItem.name);
    if (r && r.type === "function" && e.rawItem.type === "function_call")
      await this.#h(e.rawItem, r);
    else if (e.rawItem.type === "hosted_tool_call") {
      n.alwaysApprove &&
        Z.warn(
          "Always approving MCP tools is not supported. Use the allowed tools configuration instead.",
        );
      const o = jn(e);
      this.#e.sendMcpResponse(o, !0);
    } else throw new B(`Tool ${e.rawItem.name} not found`);
  }
  async reject(e, n = { alwaysReject: !1 }) {
    this.#r.rejectTool(e, n);
    const r = this.#t.tools.find((o) => o.name === e.rawItem.name);
    if (r && r.type === "function" && e.rawItem.type === "function_call")
      await this.#h(e.rawItem, r);
    else if (e.rawItem.type === "hosted_tool_call") {
      n.alwaysReject &&
        Z.warn(
          "Always rejecting MCP tools is not supported. Use the allowed tools configuration instead.",
        );
      const o = jn(e);
      this.#e.sendMcpResponse(o, !1);
    } else throw new B(`Tool ${e.rawItem.name} not found`);
  }
}
const $c = {
    base64ToArrayBuffer: so,
    arrayBufferToBase64: ao,
    getLastTextFromAudioOutputMessage: io,
  },
  xl = Object.freeze(
    Object.defineProperty(
      {
        __proto__: null,
        DEFAULT_OPENAI_REALTIME_MODEL: po,
        DEFAULT_OPENAI_REALTIME_SESSION_CONFIG: W,
        ModelBehaviorError: B,
        OpenAIRealtimeBase: je,
        OpenAIRealtimeWebRTC: fo,
        OpenAIRealtimeWebSocket: mo,
        OutputGuardrailTripwireTriggered: Ke,
        RealtimeAgent: Au,
        RealtimeSession: Lc,
        UserError: k,
        backgroundResult: Nc,
        isBackgroundResult: go,
        tool: Ve,
        utils: $c,
      },
      Symbol.toStringTag,
      { value: "Module" },
    ),
  );
Sa(new vu());
bu();
export {
  te as Agent,
  pa as AgentHooks,
  se as AgentsError,
  Yr as BatchTraceProcessor,
  vi as ConsoleSpanExporter,
  tn as GuardrailExecutionError,
  fr as Handoff,
  nn as InputGuardrailTripwireTriggered,
  Vc as MCPServerSSE,
  Kc as MCPServerStdio,
  Wc as MCPServerStreamableHttp,
  en as MaxTurnsExceededError,
  B as ModelBehaviorError,
  re as NoopSpan,
  yt as NoopTrace,
  fa as OPENAI_DEFAULT_MODEL_ENV_VARIABLE_NAME,
  gu as OpenAIChatCompletionsModel,
  vu as OpenAIProvider,
  ru as OpenAIResponsesModel,
  wu as OpenAITracingExporter,
  Ke as OutputGuardrailTripwireTriggered,
  Wa as RunAgentUpdatedStreamEvent,
  we as RunContext,
  Zt as RunHandoffCallItem,
  qt as RunHandoffOutputItem,
  Ka as RunItemStreamEvent,
  ut as RunMessageOutputItem,
  Ha as RunRawModelStreamEvent,
  zt as RunReasoningItem,
  mt as RunResult,
  pe as RunState,
  q as RunToolApprovalItem,
  me as RunToolCallItem,
  De as RunToolCallOutputItem,
  Hr as Runner,
  nt as RuntimeEventEmitter,
  Fe as Span,
  Wr as StreamedRunResult,
  vs as SystemError,
  ws as ToolCallError,
  Le as Trace,
  Ii as TraceProvider,
  ge as Usage,
  k as UserError,
  Ai as addTraceProcessor,
  hl as assistant,
  Tl as codeInterpreterTool,
  qc as computerTool,
  xt as createAgentSpan,
  Ua as createCustomSpan,
  Fa as createFunctionSpan,
  Lr as createGenerationSpan,
  Ja as createGuardrailSpan,
  La as createHandoffSpan,
  Za as createMCPListToolsSpan,
  gl as createMCPToolStaticFilter,
  Fr as createResponseSpan,
  za as createSpeechGroupSpan,
  Ba as createSpeechSpan,
  Ga as createTranscriptionSpan,
  Tt as defineOutputGuardrail,
  rl as extractAllTextOutput,
  Sl as fileSearchTool,
  ll as generateGroupId,
  Si as generateSpanId,
  Qr as generateTraceId,
  ea as getAllMcpTools,
  Me as getCurrentSpan,
  Pe as getCurrentTrace,
  Mt as getDefaultModel,
  ma as getDefaultModelSettings,
  $ as getGlobalTraceProvider,
  ya as getHandoff,
  Ee as getLogger,
  yi as getOrCreateTrace,
  dr as getTransferMessage,
  rt as gpt5ReasoningSettingsRequired,
  mr as handoff,
  Hc as hostedMcpTool,
  Il as imageGenerationTool,
  Yc as invalidateServerToolsCache,
  pr as isGpt5Default,
  pn as mcpToFunctionTool,
  nl as protocol,
  xl as realtime,
  de as resetCurrentSpan,
  cl as run,
  Te as setCurrentSpan,
  Sa as setDefaultModelProvider,
  vl as setDefaultOpenAIClient,
  wl as setDefaultOpenAIKey,
  bu as setDefaultOpenAITracingExporter,
  _l as setOpenAIAPI,
  Di as setTraceProcessors,
  pl as setTracingDisabled,
  yl as setTracingExportApiKey,
  dl as startTraceExportLoop,
  ml as system,
  Ve as tool,
  fl as user,
  bl as webSearchTool,
  ol as withAgentSpan,
  sl as withCustomSpan,
  hn as withFunctionSpan,
  ja as withGenerationSpan,
  gn as withGuardrailSpan,
  $a as withHandoffSpan,
  qa as withMCPListToolsSpan,
  Ma as withResponseSpan,
  ul as withSpeechGroupSpan,
  il as withSpeechSpan,
  gi as withTrace,
  al as withTranscriptionSpan,
};
//# sourceMappingURL=index-CO447ynw.js.map
