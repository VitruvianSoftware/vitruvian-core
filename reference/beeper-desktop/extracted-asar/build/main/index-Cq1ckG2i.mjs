import {
  ce as Ti,
  o as ki,
  e as nr,
  aw as Fi,
  bg as ge,
  ab as or,
  aG as ca,
  aT as Mi,
  av as Ri,
  bF as Ur,
  cC as ur,
  j as la,
  m as B,
  a3 as Ae,
  cu as da,
  ax as et,
  aL as Oi,
  n as lr,
  c as Li,
  ae as Pr,
  aO as qr,
  E as hs,
  cz as ms,
  aI as gs,
  aA as fs,
  ad as xr,
  ag as pa,
  b6 as Ni,
  l as tt,
  cD as Ne,
  D as Er,
  bp as Ui,
  a_ as bs,
  aZ as Pi,
  bH as qi,
  aC as ji,
  bu as Vi,
  bA as Zi,
  at as $i,
  f as Ds,
  bc as Gi,
  bd as zi,
  ah as Hi,
  bh as Wi,
  ak as Ki,
  a$ as rr,
  bD as Yi,
  O as bt,
  aJ as Ji,
  br as me,
  b4 as Qi,
  W as Ze,
  bt as Xi,
  af as en,
  aq as tn,
} from "./Keychain-CHHka2u7.mjs";
import { pathToFileURL as jr, fileURLToPath as rn } from "node:url";
import { randomUUID as St, createHash as sn } from "node:crypto";
import { promises as le } from "node:fs";
import W from "node:path";
import { m as ys } from "./index-DaNOOrJg.mjs";
import { a as ha, c as As } from "./_commonjsHelpers-CBUqixCJ.mjs";
import {
  a2 as an,
  a3 as vs,
  H as ma,
  j as nn,
  D as on,
  G as un,
  q as cn,
  w as Dt,
  a6 as ln,
  S as dn,
  g as pn,
  r as hn,
  C as mn,
  u as gn,
  s as fn,
  t as bn,
} from "./index-BJhQkpW6.mjs";
import { g as Dn, c as yn } from "./utils-D8MokWSu.mjs";
import {
  IS_MAC_OS as Cs,
  DEEP_LINK_PROTOCOL as ws,
} from "./constants-BL_pdRyX.mjs";
import { f as Ge, k as An, i as vn, h as Cn } from "./util-CrY9x2BW.mjs";
import { f as wn } from "./macos-contacts-server-D9gt4gn9.mjs";
import Is from "crypto";
import { c as In } from "./rolling-logger-C9NTeNo3.mjs";
(function () {
  try {
    var s =
      typeof window < "u"
        ? window
        : typeof global < "u"
          ? global
          : typeof globalThis < "u"
            ? globalThis
            : typeof self < "u"
              ? self
              : {};
    s.SENTRY_RELEASE = { id: "4.3.209" };
    var e = new s.Error().stack;
    e &&
      ((s._sentryDebugIds = s._sentryDebugIds || {}),
      (s._sentryDebugIds[e] = "49a4af6d-f166-491f-aef6-c17ff38f6879"),
      (s._sentryDebugIdIdentifier =
        "sentry-dbid-49a4af6d-f166-491f-aef6-c17ff38f6879"));
  } catch {}
})();
const es = ["cloud", "self-hosted", "local", "platform-sdk"];
var Sr, xs;
function xn() {
  if (xs) return Sr;
  xs = 1;
  var s = an(),
    e = Ti();
  function t(r, a) {
    return r && r.length ? e(r, s(a, 2)) : [];
  }
  return ((Sr = t), Sr);
}
var En = xn();
const ga = ha(En);
var j;
(function (s) {
  s.assertEqual = (a) => {};
  function e(a) {}
  s.assertIs = e;
  function t(a) {
    throw new Error();
  }
  ((s.assertNever = t),
    (s.arrayToEnum = (a) => {
      const i = {};
      for (const o of a) i[o] = o;
      return i;
    }),
    (s.getValidEnumValues = (a) => {
      const i = s.objectKeys(a).filter((u) => typeof a[a[u]] != "number"),
        o = {};
      for (const u of i) o[u] = a[u];
      return s.objectValues(o);
    }),
    (s.objectValues = (a) =>
      s.objectKeys(a).map(function (i) {
        return a[i];
      })),
    (s.objectKeys =
      typeof Object.keys == "function"
        ? (a) => Object.keys(a)
        : (a) => {
            const i = [];
            for (const o in a)
              Object.prototype.hasOwnProperty.call(a, o) && i.push(o);
            return i;
          }),
    (s.find = (a, i) => {
      for (const o of a) if (i(o)) return o;
    }),
    (s.isInteger =
      typeof Number.isInteger == "function"
        ? (a) => Number.isInteger(a)
        : (a) =>
            typeof a == "number" && Number.isFinite(a) && Math.floor(a) === a));
  function r(a, i = " | ") {
    return a.map((o) => (typeof o == "string" ? `'${o}'` : o)).join(i);
  }
  ((s.joinValues = r),
    (s.jsonStringifyReplacer = (a, i) =>
      typeof i == "bigint" ? i.toString() : i));
})(j || (j = {}));
var Vr;
(function (s) {
  s.mergeShapes = (e, t) => ({ ...e, ...t });
})(Vr || (Vr = {}));
const I = j.arrayToEnum([
    "string",
    "nan",
    "number",
    "integer",
    "float",
    "boolean",
    "date",
    "bigint",
    "symbol",
    "function",
    "undefined",
    "null",
    "array",
    "object",
    "unknown",
    "promise",
    "void",
    "never",
    "map",
    "set",
  ]),
  ke = (s) => {
    switch (typeof s) {
      case "undefined":
        return I.undefined;
      case "string":
        return I.string;
      case "number":
        return Number.isNaN(s) ? I.nan : I.number;
      case "boolean":
        return I.boolean;
      case "function":
        return I.function;
      case "bigint":
        return I.bigint;
      case "symbol":
        return I.symbol;
      case "object":
        return Array.isArray(s)
          ? I.array
          : s === null
            ? I.null
            : s.then &&
                typeof s.then == "function" &&
                s.catch &&
                typeof s.catch == "function"
              ? I.promise
              : typeof Map < "u" && s instanceof Map
                ? I.map
                : typeof Set < "u" && s instanceof Set
                  ? I.set
                  : typeof Date < "u" && s instanceof Date
                    ? I.date
                    : I.object;
      default:
        return I.unknown;
    }
  },
  b = j.arrayToEnum([
    "invalid_type",
    "invalid_literal",
    "custom",
    "invalid_union",
    "invalid_union_discriminator",
    "invalid_enum_value",
    "unrecognized_keys",
    "invalid_arguments",
    "invalid_return_type",
    "invalid_date",
    "invalid_string",
    "too_small",
    "too_big",
    "invalid_intersection_types",
    "not_multiple_of",
    "not_finite",
  ]),
  Sn = (s) => JSON.stringify(s, null, 2).replace(/"([^"]+)":/g, "$1:");
class be extends Error {
  get errors() {
    return this.issues;
  }
  constructor(e) {
    (super(),
      (this.issues = []),
      (this.addIssue = (r) => {
        this.issues = [...this.issues, r];
      }),
      (this.addIssues = (r = []) => {
        this.issues = [...this.issues, ...r];
      }));
    const t = new.target.prototype;
    (Object.setPrototypeOf
      ? Object.setPrototypeOf(this, t)
      : (this.__proto__ = t),
      (this.name = "ZodError"),
      (this.issues = e));
  }
  format(e) {
    const t =
        e ||
        function (i) {
          return i.message;
        },
      r = { _errors: [] },
      a = (i) => {
        for (const o of i.issues)
          if (o.code === "invalid_union") o.unionErrors.map(a);
          else if (o.code === "invalid_return_type") a(o.returnTypeError);
          else if (o.code === "invalid_arguments") a(o.argumentsError);
          else if (o.path.length === 0) r._errors.push(t(o));
          else {
            let u = r,
              c = 0;
            for (; c < o.path.length;) {
              const l = o.path[c];
              (c === o.path.length - 1
                ? ((u[l] = u[l] || { _errors: [] }), u[l]._errors.push(t(o)))
                : (u[l] = u[l] || { _errors: [] }),
                (u = u[l]),
                c++);
            }
          }
      };
    return (a(this), r);
  }
  static assert(e) {
    if (!(e instanceof be)) throw new Error(`Not a ZodError: ${e}`);
  }
  toString() {
    return this.message;
  }
  get message() {
    return JSON.stringify(this.issues, j.jsonStringifyReplacer, 2);
  }
  get isEmpty() {
    return this.issues.length === 0;
  }
  flatten(e = (t) => t.message) {
    const t = {},
      r = [];
    for (const a of this.issues)
      if (a.path.length > 0) {
        const i = a.path[0];
        ((t[i] = t[i] || []), t[i].push(e(a)));
      } else r.push(e(a));
    return { formErrors: r, fieldErrors: t };
  }
  get formErrors() {
    return this.flatten();
  }
}
be.create = (s) => new be(s);
const dt = (s, e) => {
  let t;
  switch (s.code) {
    case b.invalid_type:
      s.received === I.undefined
        ? (t = "Required")
        : (t = `Expected ${s.expected}, received ${s.received}`);
      break;
    case b.invalid_literal:
      t = `Invalid literal value, expected ${JSON.stringify(s.expected, j.jsonStringifyReplacer)}`;
      break;
    case b.unrecognized_keys:
      t = `Unrecognized key(s) in object: ${j.joinValues(s.keys, ", ")}`;
      break;
    case b.invalid_union:
      t = "Invalid input";
      break;
    case b.invalid_union_discriminator:
      t = `Invalid discriminator value. Expected ${j.joinValues(s.options)}`;
      break;
    case b.invalid_enum_value:
      t = `Invalid enum value. Expected ${j.joinValues(s.options)}, received '${s.received}'`;
      break;
    case b.invalid_arguments:
      t = "Invalid function arguments";
      break;
    case b.invalid_return_type:
      t = "Invalid function return type";
      break;
    case b.invalid_date:
      t = "Invalid date";
      break;
    case b.invalid_string:
      typeof s.validation == "object"
        ? "includes" in s.validation
          ? ((t = `Invalid input: must include "${s.validation.includes}"`),
            typeof s.validation.position == "number" &&
              (t = `${t} at one or more positions greater than or equal to ${s.validation.position}`))
          : "startsWith" in s.validation
            ? (t = `Invalid input: must start with "${s.validation.startsWith}"`)
            : "endsWith" in s.validation
              ? (t = `Invalid input: must end with "${s.validation.endsWith}"`)
              : j.assertNever(s.validation)
        : s.validation !== "regex"
          ? (t = `Invalid ${s.validation}`)
          : (t = "Invalid");
      break;
    case b.too_small:
      s.type === "array"
        ? (t = `Array must contain ${s.exact ? "exactly" : s.inclusive ? "at least" : "more than"} ${s.minimum} element(s)`)
        : s.type === "string"
          ? (t = `String must contain ${s.exact ? "exactly" : s.inclusive ? "at least" : "over"} ${s.minimum} character(s)`)
          : s.type === "number"
            ? (t = `Number must be ${s.exact ? "exactly equal to " : s.inclusive ? "greater than or equal to " : "greater than "}${s.minimum}`)
            : s.type === "bigint"
              ? (t = `Number must be ${s.exact ? "exactly equal to " : s.inclusive ? "greater than or equal to " : "greater than "}${s.minimum}`)
              : s.type === "date"
                ? (t = `Date must be ${s.exact ? "exactly equal to " : s.inclusive ? "greater than or equal to " : "greater than "}${new Date(Number(s.minimum))}`)
                : (t = "Invalid input");
      break;
    case b.too_big:
      s.type === "array"
        ? (t = `Array must contain ${s.exact ? "exactly" : s.inclusive ? "at most" : "less than"} ${s.maximum} element(s)`)
        : s.type === "string"
          ? (t = `String must contain ${s.exact ? "exactly" : s.inclusive ? "at most" : "under"} ${s.maximum} character(s)`)
          : s.type === "number"
            ? (t = `Number must be ${s.exact ? "exactly" : s.inclusive ? "less than or equal to" : "less than"} ${s.maximum}`)
            : s.type === "bigint"
              ? (t = `BigInt must be ${s.exact ? "exactly" : s.inclusive ? "less than or equal to" : "less than"} ${s.maximum}`)
              : s.type === "date"
                ? (t = `Date must be ${s.exact ? "exactly" : s.inclusive ? "smaller than or equal to" : "smaller than"} ${new Date(Number(s.maximum))}`)
                : (t = "Invalid input");
      break;
    case b.custom:
      t = "Invalid input";
      break;
    case b.invalid_intersection_types:
      t = "Intersection results could not be merged";
      break;
    case b.not_multiple_of:
      t = `Number must be a multiple of ${s.multipleOf}`;
      break;
    case b.not_finite:
      t = "Number must be finite";
      break;
    default:
      ((t = e.defaultError), j.assertNever(s));
  }
  return { message: t };
};
let fa = dt;
function Bn(s) {
  fa = s;
}
function dr() {
  return fa;
}
const pr = (s) => {
    const { data: e, path: t, errorMaps: r, issueData: a } = s,
      i = [...t, ...(a.path || [])],
      o = { ...a, path: i };
    if (a.message !== void 0) return { ...a, path: i, message: a.message };
    let u = "";
    const c = r
      .filter((l) => !!l)
      .slice()
      .reverse();
    for (const l of c) u = l(o, { data: e, defaultError: u }).message;
    return { ...a, path: i, message: u };
  },
  _n = [];
function v(s, e) {
  const t = dr(),
    r = pr({
      issueData: e,
      data: s.data,
      path: s.path,
      errorMaps: [
        s.common.contextualErrorMap,
        s.schemaErrorMap,
        t,
        t === dt ? void 0 : dt,
      ].filter((a) => !!a),
    });
  s.common.issues.push(r);
}
class de {
  constructor() {
    this.value = "valid";
  }
  dirty() {
    this.value === "valid" && (this.value = "dirty");
  }
  abort() {
    this.value !== "aborted" && (this.value = "aborted");
  }
  static mergeArray(e, t) {
    const r = [];
    for (const a of t) {
      if (a.status === "aborted") return _;
      (a.status === "dirty" && e.dirty(), r.push(a.value));
    }
    return { status: e.value, value: r };
  }
  static async mergeObjectAsync(e, t) {
    const r = [];
    for (const a of t) {
      const i = await a.key,
        o = await a.value;
      r.push({ key: i, value: o });
    }
    return de.mergeObjectSync(e, r);
  }
  static mergeObjectSync(e, t) {
    const r = {};
    for (const a of t) {
      const { key: i, value: o } = a;
      if (i.status === "aborted" || o.status === "aborted") return _;
      (i.status === "dirty" && e.dirty(),
        o.status === "dirty" && e.dirty(),
        i.value !== "__proto__" &&
          (typeof o.value < "u" || a.alwaysSet) &&
          (r[i.value] = o.value));
    }
    return { status: e.value, value: r };
  }
}
const _ = Object.freeze({ status: "aborted" }),
  rt = (s) => ({ status: "dirty", value: s }),
  he = (s) => ({ status: "valid", value: s }),
  Zr = (s) => s.status === "aborted",
  $r = (s) => s.status === "dirty",
  Ke = (s) => s.status === "valid",
  kt = (s) => typeof Promise < "u" && s instanceof Promise;
var x;
(function (s) {
  ((s.errToObj = (e) => (typeof e == "string" ? { message: e } : e || {})),
    (s.toString = (e) => (typeof e == "string" ? e : e?.message)));
})(x || (x = {}));
class Se {
  constructor(e, t, r, a) {
    ((this._cachedPath = []),
      (this.parent = e),
      (this.data = t),
      (this._path = r),
      (this._key = a));
  }
  get path() {
    return (
      this._cachedPath.length ||
        (Array.isArray(this._key)
          ? this._cachedPath.push(...this._path, ...this._key)
          : this._cachedPath.push(...this._path, this._key)),
      this._cachedPath
    );
  }
}
const Es = (s, e) => {
  if (Ke(e)) return { success: !0, data: e.value };
  if (!s.common.issues.length)
    throw new Error("Validation failed but no issues detected.");
  return {
    success: !1,
    get error() {
      if (this._error) return this._error;
      const t = new be(s.common.issues);
      return ((this._error = t), this._error);
    },
  };
};
function O(s) {
  if (!s) return {};
  const {
    errorMap: e,
    invalid_type_error: t,
    required_error: r,
    description: a,
  } = s;
  if (e && (t || r))
    throw new Error(
      `Can't use "invalid_type_error" or "required_error" in conjunction with custom error map.`,
    );
  return e
    ? { errorMap: e, description: a }
    : {
        errorMap: (o, u) => {
          const { message: c } = s;
          return o.code === "invalid_enum_value"
            ? { message: c ?? u.defaultError }
            : typeof u.data > "u"
              ? { message: c ?? r ?? u.defaultError }
              : o.code !== "invalid_type"
                ? { message: u.defaultError }
                : { message: c ?? t ?? u.defaultError };
        },
        description: a,
      };
}
class N {
  get description() {
    return this._def.description;
  }
  _getType(e) {
    return ke(e.data);
  }
  _getOrReturnCtx(e, t) {
    return (
      t || {
        common: e.parent.common,
        data: e.data,
        parsedType: ke(e.data),
        schemaErrorMap: this._def.errorMap,
        path: e.path,
        parent: e.parent,
      }
    );
  }
  _processInputParams(e) {
    return {
      status: new de(),
      ctx: {
        common: e.parent.common,
        data: e.data,
        parsedType: ke(e.data),
        schemaErrorMap: this._def.errorMap,
        path: e.path,
        parent: e.parent,
      },
    };
  }
  _parseSync(e) {
    const t = this._parse(e);
    if (kt(t)) throw new Error("Synchronous parse encountered promise.");
    return t;
  }
  _parseAsync(e) {
    const t = this._parse(e);
    return Promise.resolve(t);
  }
  parse(e, t) {
    const r = this.safeParse(e, t);
    if (r.success) return r.data;
    throw r.error;
  }
  safeParse(e, t) {
    const r = {
        common: {
          issues: [],
          async: t?.async ?? !1,
          contextualErrorMap: t?.errorMap,
        },
        path: t?.path || [],
        schemaErrorMap: this._def.errorMap,
        parent: null,
        data: e,
        parsedType: ke(e),
      },
      a = this._parseSync({ data: e, path: r.path, parent: r });
    return Es(r, a);
  }
  "~validate"(e) {
    const t = {
      common: { issues: [], async: !!this["~standard"].async },
      path: [],
      schemaErrorMap: this._def.errorMap,
      parent: null,
      data: e,
      parsedType: ke(e),
    };
    if (!this["~standard"].async)
      try {
        const r = this._parseSync({ data: e, path: [], parent: t });
        return Ke(r) ? { value: r.value } : { issues: t.common.issues };
      } catch (r) {
        (r?.message?.toLowerCase()?.includes("encountered") &&
          (this["~standard"].async = !0),
          (t.common = { issues: [], async: !0 }));
      }
    return this._parseAsync({ data: e, path: [], parent: t }).then((r) =>
      Ke(r) ? { value: r.value } : { issues: t.common.issues },
    );
  }
  async parseAsync(e, t) {
    const r = await this.safeParseAsync(e, t);
    if (r.success) return r.data;
    throw r.error;
  }
  async safeParseAsync(e, t) {
    const r = {
        common: { issues: [], contextualErrorMap: t?.errorMap, async: !0 },
        path: t?.path || [],
        schemaErrorMap: this._def.errorMap,
        parent: null,
        data: e,
        parsedType: ke(e),
      },
      a = this._parse({ data: e, path: r.path, parent: r }),
      i = await (kt(a) ? a : Promise.resolve(a));
    return Es(r, i);
  }
  refine(e, t) {
    const r = (a) =>
      typeof t == "string" || typeof t > "u"
        ? { message: t }
        : typeof t == "function"
          ? t(a)
          : t;
    return this._refinement((a, i) => {
      const o = e(a),
        u = () => i.addIssue({ code: b.custom, ...r(a) });
      return typeof Promise < "u" && o instanceof Promise
        ? o.then((c) => (c ? !0 : (u(), !1)))
        : o
          ? !0
          : (u(), !1);
    });
  }
  refinement(e, t) {
    return this._refinement((r, a) =>
      e(r) ? !0 : (a.addIssue(typeof t == "function" ? t(r, a) : t), !1),
    );
  }
  _refinement(e) {
    return new Ie({
      schema: this,
      typeName: k.ZodEffects,
      effect: { type: "refinement", refinement: e },
    });
  }
  superRefine(e) {
    return this._refinement(e);
  }
  constructor(e) {
    ((this.spa = this.safeParseAsync),
      (this._def = e),
      (this.parse = this.parse.bind(this)),
      (this.safeParse = this.safeParse.bind(this)),
      (this.parseAsync = this.parseAsync.bind(this)),
      (this.safeParseAsync = this.safeParseAsync.bind(this)),
      (this.spa = this.spa.bind(this)),
      (this.refine = this.refine.bind(this)),
      (this.refinement = this.refinement.bind(this)),
      (this.superRefine = this.superRefine.bind(this)),
      (this.optional = this.optional.bind(this)),
      (this.nullable = this.nullable.bind(this)),
      (this.nullish = this.nullish.bind(this)),
      (this.array = this.array.bind(this)),
      (this.promise = this.promise.bind(this)),
      (this.or = this.or.bind(this)),
      (this.and = this.and.bind(this)),
      (this.transform = this.transform.bind(this)),
      (this.brand = this.brand.bind(this)),
      (this.default = this.default.bind(this)),
      (this.catch = this.catch.bind(this)),
      (this.describe = this.describe.bind(this)),
      (this.pipe = this.pipe.bind(this)),
      (this.readonly = this.readonly.bind(this)),
      (this.isNullable = this.isNullable.bind(this)),
      (this.isOptional = this.isOptional.bind(this)),
      (this["~standard"] = {
        version: 1,
        vendor: "zod",
        validate: (t) => this["~validate"](t),
      }));
  }
  optional() {
    return Ee.create(this, this._def);
  }
  nullable() {
    return je.create(this, this._def);
  }
  nullish() {
    return this.nullable().optional();
  }
  array() {
    return we.create(this);
  }
  promise() {
    return ht.create(this, this._def);
  }
  or(e) {
    return Ot.create([this, e], this._def);
  }
  and(e) {
    return Lt.create(this, e, this._def);
  }
  transform(e) {
    return new Ie({
      ...O(this._def),
      schema: this,
      typeName: k.ZodEffects,
      effect: { type: "transform", transform: e },
    });
  }
  default(e) {
    const t = typeof e == "function" ? e : () => e;
    return new jt({
      ...O(this._def),
      innerType: this,
      defaultValue: t,
      typeName: k.ZodDefault,
    });
  }
  brand() {
    return new ts({ typeName: k.ZodBranded, type: this, ...O(this._def) });
  }
  catch(e) {
    const t = typeof e == "function" ? e : () => e;
    return new Vt({
      ...O(this._def),
      innerType: this,
      catchValue: t,
      typeName: k.ZodCatch,
    });
  }
  describe(e) {
    const t = this.constructor;
    return new t({ ...this._def, description: e });
  }
  pipe(e) {
    return $t.create(this, e);
  }
  readonly() {
    return Zt.create(this);
  }
  isOptional() {
    return this.safeParse(void 0).success;
  }
  isNullable() {
    return this.safeParse(null).success;
  }
}
const Tn = /^c[^\s-]{8,}$/i,
  kn = /^[0-9a-z]+$/,
  Fn = /^[0-9A-HJKMNP-TV-Z]{26}$/i,
  Mn =
    /^[0-9a-fA-F]{8}\b-[0-9a-fA-F]{4}\b-[0-9a-fA-F]{4}\b-[0-9a-fA-F]{4}\b-[0-9a-fA-F]{12}$/i,
  Rn = /^[a-z0-9_-]{21}$/i,
  On = /^[A-Za-z0-9-_]+\.[A-Za-z0-9-_]+\.[A-Za-z0-9-_]*$/,
  Ln =
    /^[-+]?P(?!$)(?:(?:[-+]?\d+Y)|(?:[-+]?\d+[.,]\d+Y$))?(?:(?:[-+]?\d+M)|(?:[-+]?\d+[.,]\d+M$))?(?:(?:[-+]?\d+W)|(?:[-+]?\d+[.,]\d+W$))?(?:(?:[-+]?\d+D)|(?:[-+]?\d+[.,]\d+D$))?(?:T(?=[\d+-])(?:(?:[-+]?\d+H)|(?:[-+]?\d+[.,]\d+H$))?(?:(?:[-+]?\d+M)|(?:[-+]?\d+[.,]\d+M$))?(?:[-+]?\d+(?:[.,]\d+)?S)?)??$/,
  Nn =
    /^(?!\.)(?!.*\.\.)([A-Z0-9_'+\-\.]*)[A-Z0-9_+-]@([A-Z0-9][A-Z0-9\-]*\.)+[A-Z]{2,}$/i,
  Un = "^(\\p{Extended_Pictographic}|\\p{Emoji_Component})+$";
let Br;
const Pn =
    /^(?:(?:25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9][0-9]|[0-9])\.){3}(?:25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9][0-9]|[0-9])$/,
  qn =
    /^(?:(?:25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9][0-9]|[0-9])\.){3}(?:25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9][0-9]|[0-9])\/(3[0-2]|[12]?[0-9])$/,
  jn =
    /^(([0-9a-fA-F]{1,4}:){7,7}[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,7}:|([0-9a-fA-F]{1,4}:){1,6}:[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,5}(:[0-9a-fA-F]{1,4}){1,2}|([0-9a-fA-F]{1,4}:){1,4}(:[0-9a-fA-F]{1,4}){1,3}|([0-9a-fA-F]{1,4}:){1,3}(:[0-9a-fA-F]{1,4}){1,4}|([0-9a-fA-F]{1,4}:){1,2}(:[0-9a-fA-F]{1,4}){1,5}|[0-9a-fA-F]{1,4}:((:[0-9a-fA-F]{1,4}){1,6})|:((:[0-9a-fA-F]{1,4}){1,7}|:)|fe80:(:[0-9a-fA-F]{0,4}){0,4}%[0-9a-zA-Z]{1,}|::(ffff(:0{1,4}){0,1}:){0,1}((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\.){3,3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])|([0-9a-fA-F]{1,4}:){1,4}:((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\.){3,3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9]))$/,
  Vn =
    /^(([0-9a-fA-F]{1,4}:){7,7}[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,7}:|([0-9a-fA-F]{1,4}:){1,6}:[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,5}(:[0-9a-fA-F]{1,4}){1,2}|([0-9a-fA-F]{1,4}:){1,4}(:[0-9a-fA-F]{1,4}){1,3}|([0-9a-fA-F]{1,4}:){1,3}(:[0-9a-fA-F]{1,4}){1,4}|([0-9a-fA-F]{1,4}:){1,2}(:[0-9a-fA-F]{1,4}){1,5}|[0-9a-fA-F]{1,4}:((:[0-9a-fA-F]{1,4}){1,6})|:((:[0-9a-fA-F]{1,4}){1,7}|:)|fe80:(:[0-9a-fA-F]{0,4}){0,4}%[0-9a-zA-Z]{1,}|::(ffff(:0{1,4}){0,1}:){0,1}((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\.){3,3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])|([0-9a-fA-F]{1,4}:){1,4}:((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\.){3,3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9]))\/(12[0-8]|1[01][0-9]|[1-9]?[0-9])$/,
  Zn = /^([0-9a-zA-Z+/]{4})*(([0-9a-zA-Z+/]{2}==)|([0-9a-zA-Z+/]{3}=))?$/,
  $n = /^([0-9a-zA-Z-_]{4})*(([0-9a-zA-Z-_]{2}(==)?)|([0-9a-zA-Z-_]{3}(=)?))?$/,
  ba =
    "((\\d\\d[2468][048]|\\d\\d[13579][26]|\\d\\d0[48]|[02468][048]00|[13579][26]00)-02-29|\\d{4}-((0[13578]|1[02])-(0[1-9]|[12]\\d|3[01])|(0[469]|11)-(0[1-9]|[12]\\d|30)|(02)-(0[1-9]|1\\d|2[0-8])))",
  Gn = new RegExp(`^${ba}$`);
function Da(s) {
  let e = "[0-5]\\d";
  s.precision
    ? (e = `${e}\\.\\d{${s.precision}}`)
    : s.precision == null && (e = `${e}(\\.\\d+)?`);
  const t = s.precision ? "+" : "?";
  return `([01]\\d|2[0-3]):[0-5]\\d(:${e})${t}`;
}
function zn(s) {
  return new RegExp(`^${Da(s)}$`);
}
function ya(s) {
  let e = `${ba}T${Da(s)}`;
  const t = [];
  return (
    t.push(s.local ? "Z?" : "Z"),
    s.offset && t.push("([+-]\\d{2}:?\\d{2})"),
    (e = `${e}(${t.join("|")})`),
    new RegExp(`^${e}$`)
  );
}
function Hn(s, e) {
  return !!(
    ((e === "v4" || !e) && Pn.test(s)) ||
    ((e === "v6" || !e) && jn.test(s))
  );
}
function Wn(s, e) {
  if (!On.test(s)) return !1;
  try {
    const [t] = s.split(".");
    if (!t) return !1;
    const r = t
        .replace(/-/g, "+")
        .replace(/_/g, "/")
        .padEnd(t.length + ((4 - (t.length % 4)) % 4), "="),
      a = JSON.parse(atob(r));
    return !(
      typeof a != "object" ||
      a === null ||
      ("typ" in a && a?.typ !== "JWT") ||
      !a.alg ||
      (e && a.alg !== e)
    );
  } catch {
    return !1;
  }
}
function Kn(s, e) {
  return !!(
    ((e === "v4" || !e) && qn.test(s)) ||
    ((e === "v6" || !e) && Vn.test(s))
  );
}
class Ce extends N {
  _parse(e) {
    if (
      (this._def.coerce && (e.data = String(e.data)),
      this._getType(e) !== I.string)
    ) {
      const i = this._getOrReturnCtx(e);
      return (
        v(i, {
          code: b.invalid_type,
          expected: I.string,
          received: i.parsedType,
        }),
        _
      );
    }
    const r = new de();
    let a;
    for (const i of this._def.checks)
      if (i.kind === "min")
        e.data.length < i.value &&
          ((a = this._getOrReturnCtx(e, a)),
          v(a, {
            code: b.too_small,
            minimum: i.value,
            type: "string",
            inclusive: !0,
            exact: !1,
            message: i.message,
          }),
          r.dirty());
      else if (i.kind === "max")
        e.data.length > i.value &&
          ((a = this._getOrReturnCtx(e, a)),
          v(a, {
            code: b.too_big,
            maximum: i.value,
            type: "string",
            inclusive: !0,
            exact: !1,
            message: i.message,
          }),
          r.dirty());
      else if (i.kind === "length") {
        const o = e.data.length > i.value,
          u = e.data.length < i.value;
        (o || u) &&
          ((a = this._getOrReturnCtx(e, a)),
          o
            ? v(a, {
                code: b.too_big,
                maximum: i.value,
                type: "string",
                inclusive: !0,
                exact: !0,
                message: i.message,
              })
            : u &&
              v(a, {
                code: b.too_small,
                minimum: i.value,
                type: "string",
                inclusive: !0,
                exact: !0,
                message: i.message,
              }),
          r.dirty());
      } else if (i.kind === "email")
        Nn.test(e.data) ||
          ((a = this._getOrReturnCtx(e, a)),
          v(a, {
            validation: "email",
            code: b.invalid_string,
            message: i.message,
          }),
          r.dirty());
      else if (i.kind === "emoji")
        (Br || (Br = new RegExp(Un, "u")),
          Br.test(e.data) ||
            ((a = this._getOrReturnCtx(e, a)),
            v(a, {
              validation: "emoji",
              code: b.invalid_string,
              message: i.message,
            }),
            r.dirty()));
      else if (i.kind === "uuid")
        Mn.test(e.data) ||
          ((a = this._getOrReturnCtx(e, a)),
          v(a, {
            validation: "uuid",
            code: b.invalid_string,
            message: i.message,
          }),
          r.dirty());
      else if (i.kind === "nanoid")
        Rn.test(e.data) ||
          ((a = this._getOrReturnCtx(e, a)),
          v(a, {
            validation: "nanoid",
            code: b.invalid_string,
            message: i.message,
          }),
          r.dirty());
      else if (i.kind === "cuid")
        Tn.test(e.data) ||
          ((a = this._getOrReturnCtx(e, a)),
          v(a, {
            validation: "cuid",
            code: b.invalid_string,
            message: i.message,
          }),
          r.dirty());
      else if (i.kind === "cuid2")
        kn.test(e.data) ||
          ((a = this._getOrReturnCtx(e, a)),
          v(a, {
            validation: "cuid2",
            code: b.invalid_string,
            message: i.message,
          }),
          r.dirty());
      else if (i.kind === "ulid")
        Fn.test(e.data) ||
          ((a = this._getOrReturnCtx(e, a)),
          v(a, {
            validation: "ulid",
            code: b.invalid_string,
            message: i.message,
          }),
          r.dirty());
      else if (i.kind === "url")
        try {
          new URL(e.data);
        } catch {
          ((a = this._getOrReturnCtx(e, a)),
            v(a, {
              validation: "url",
              code: b.invalid_string,
              message: i.message,
            }),
            r.dirty());
        }
      else
        i.kind === "regex"
          ? ((i.regex.lastIndex = 0),
            i.regex.test(e.data) ||
              ((a = this._getOrReturnCtx(e, a)),
              v(a, {
                validation: "regex",
                code: b.invalid_string,
                message: i.message,
              }),
              r.dirty()))
          : i.kind === "trim"
            ? (e.data = e.data.trim())
            : i.kind === "includes"
              ? e.data.includes(i.value, i.position) ||
                ((a = this._getOrReturnCtx(e, a)),
                v(a, {
                  code: b.invalid_string,
                  validation: { includes: i.value, position: i.position },
                  message: i.message,
                }),
                r.dirty())
              : i.kind === "toLowerCase"
                ? (e.data = e.data.toLowerCase())
                : i.kind === "toUpperCase"
                  ? (e.data = e.data.toUpperCase())
                  : i.kind === "startsWith"
                    ? e.data.startsWith(i.value) ||
                      ((a = this._getOrReturnCtx(e, a)),
                      v(a, {
                        code: b.invalid_string,
                        validation: { startsWith: i.value },
                        message: i.message,
                      }),
                      r.dirty())
                    : i.kind === "endsWith"
                      ? e.data.endsWith(i.value) ||
                        ((a = this._getOrReturnCtx(e, a)),
                        v(a, {
                          code: b.invalid_string,
                          validation: { endsWith: i.value },
                          message: i.message,
                        }),
                        r.dirty())
                      : i.kind === "datetime"
                        ? ya(i).test(e.data) ||
                          ((a = this._getOrReturnCtx(e, a)),
                          v(a, {
                            code: b.invalid_string,
                            validation: "datetime",
                            message: i.message,
                          }),
                          r.dirty())
                        : i.kind === "date"
                          ? Gn.test(e.data) ||
                            ((a = this._getOrReturnCtx(e, a)),
                            v(a, {
                              code: b.invalid_string,
                              validation: "date",
                              message: i.message,
                            }),
                            r.dirty())
                          : i.kind === "time"
                            ? zn(i).test(e.data) ||
                              ((a = this._getOrReturnCtx(e, a)),
                              v(a, {
                                code: b.invalid_string,
                                validation: "time",
                                message: i.message,
                              }),
                              r.dirty())
                            : i.kind === "duration"
                              ? Ln.test(e.data) ||
                                ((a = this._getOrReturnCtx(e, a)),
                                v(a, {
                                  validation: "duration",
                                  code: b.invalid_string,
                                  message: i.message,
                                }),
                                r.dirty())
                              : i.kind === "ip"
                                ? Hn(e.data, i.version) ||
                                  ((a = this._getOrReturnCtx(e, a)),
                                  v(a, {
                                    validation: "ip",
                                    code: b.invalid_string,
                                    message: i.message,
                                  }),
                                  r.dirty())
                                : i.kind === "jwt"
                                  ? Wn(e.data, i.alg) ||
                                    ((a = this._getOrReturnCtx(e, a)),
                                    v(a, {
                                      validation: "jwt",
                                      code: b.invalid_string,
                                      message: i.message,
                                    }),
                                    r.dirty())
                                  : i.kind === "cidr"
                                    ? Kn(e.data, i.version) ||
                                      ((a = this._getOrReturnCtx(e, a)),
                                      v(a, {
                                        validation: "cidr",
                                        code: b.invalid_string,
                                        message: i.message,
                                      }),
                                      r.dirty())
                                    : i.kind === "base64"
                                      ? Zn.test(e.data) ||
                                        ((a = this._getOrReturnCtx(e, a)),
                                        v(a, {
                                          validation: "base64",
                                          code: b.invalid_string,
                                          message: i.message,
                                        }),
                                        r.dirty())
                                      : i.kind === "base64url"
                                        ? $n.test(e.data) ||
                                          ((a = this._getOrReturnCtx(e, a)),
                                          v(a, {
                                            validation: "base64url",
                                            code: b.invalid_string,
                                            message: i.message,
                                          }),
                                          r.dirty())
                                        : j.assertNever(i);
    return { status: r.value, value: e.data };
  }
  _regex(e, t, r) {
    return this.refinement((a) => e.test(a), {
      validation: t,
      code: b.invalid_string,
      ...x.errToObj(r),
    });
  }
  _addCheck(e) {
    return new Ce({ ...this._def, checks: [...this._def.checks, e] });
  }
  email(e) {
    return this._addCheck({ kind: "email", ...x.errToObj(e) });
  }
  url(e) {
    return this._addCheck({ kind: "url", ...x.errToObj(e) });
  }
  emoji(e) {
    return this._addCheck({ kind: "emoji", ...x.errToObj(e) });
  }
  uuid(e) {
    return this._addCheck({ kind: "uuid", ...x.errToObj(e) });
  }
  nanoid(e) {
    return this._addCheck({ kind: "nanoid", ...x.errToObj(e) });
  }
  cuid(e) {
    return this._addCheck({ kind: "cuid", ...x.errToObj(e) });
  }
  cuid2(e) {
    return this._addCheck({ kind: "cuid2", ...x.errToObj(e) });
  }
  ulid(e) {
    return this._addCheck({ kind: "ulid", ...x.errToObj(e) });
  }
  base64(e) {
    return this._addCheck({ kind: "base64", ...x.errToObj(e) });
  }
  base64url(e) {
    return this._addCheck({ kind: "base64url", ...x.errToObj(e) });
  }
  jwt(e) {
    return this._addCheck({ kind: "jwt", ...x.errToObj(e) });
  }
  ip(e) {
    return this._addCheck({ kind: "ip", ...x.errToObj(e) });
  }
  cidr(e) {
    return this._addCheck({ kind: "cidr", ...x.errToObj(e) });
  }
  datetime(e) {
    return typeof e == "string"
      ? this._addCheck({
          kind: "datetime",
          precision: null,
          offset: !1,
          local: !1,
          message: e,
        })
      : this._addCheck({
          kind: "datetime",
          precision: typeof e?.precision > "u" ? null : e?.precision,
          offset: e?.offset ?? !1,
          local: e?.local ?? !1,
          ...x.errToObj(e?.message),
        });
  }
  date(e) {
    return this._addCheck({ kind: "date", message: e });
  }
  time(e) {
    return typeof e == "string"
      ? this._addCheck({ kind: "time", precision: null, message: e })
      : this._addCheck({
          kind: "time",
          precision: typeof e?.precision > "u" ? null : e?.precision,
          ...x.errToObj(e?.message),
        });
  }
  duration(e) {
    return this._addCheck({ kind: "duration", ...x.errToObj(e) });
  }
  regex(e, t) {
    return this._addCheck({ kind: "regex", regex: e, ...x.errToObj(t) });
  }
  includes(e, t) {
    return this._addCheck({
      kind: "includes",
      value: e,
      position: t?.position,
      ...x.errToObj(t?.message),
    });
  }
  startsWith(e, t) {
    return this._addCheck({ kind: "startsWith", value: e, ...x.errToObj(t) });
  }
  endsWith(e, t) {
    return this._addCheck({ kind: "endsWith", value: e, ...x.errToObj(t) });
  }
  min(e, t) {
    return this._addCheck({ kind: "min", value: e, ...x.errToObj(t) });
  }
  max(e, t) {
    return this._addCheck({ kind: "max", value: e, ...x.errToObj(t) });
  }
  length(e, t) {
    return this._addCheck({ kind: "length", value: e, ...x.errToObj(t) });
  }
  nonempty(e) {
    return this.min(1, x.errToObj(e));
  }
  trim() {
    return new Ce({
      ...this._def,
      checks: [...this._def.checks, { kind: "trim" }],
    });
  }
  toLowerCase() {
    return new Ce({
      ...this._def,
      checks: [...this._def.checks, { kind: "toLowerCase" }],
    });
  }
  toUpperCase() {
    return new Ce({
      ...this._def,
      checks: [...this._def.checks, { kind: "toUpperCase" }],
    });
  }
  get isDatetime() {
    return !!this._def.checks.find((e) => e.kind === "datetime");
  }
  get isDate() {
    return !!this._def.checks.find((e) => e.kind === "date");
  }
  get isTime() {
    return !!this._def.checks.find((e) => e.kind === "time");
  }
  get isDuration() {
    return !!this._def.checks.find((e) => e.kind === "duration");
  }
  get isEmail() {
    return !!this._def.checks.find((e) => e.kind === "email");
  }
  get isURL() {
    return !!this._def.checks.find((e) => e.kind === "url");
  }
  get isEmoji() {
    return !!this._def.checks.find((e) => e.kind === "emoji");
  }
  get isUUID() {
    return !!this._def.checks.find((e) => e.kind === "uuid");
  }
  get isNANOID() {
    return !!this._def.checks.find((e) => e.kind === "nanoid");
  }
  get isCUID() {
    return !!this._def.checks.find((e) => e.kind === "cuid");
  }
  get isCUID2() {
    return !!this._def.checks.find((e) => e.kind === "cuid2");
  }
  get isULID() {
    return !!this._def.checks.find((e) => e.kind === "ulid");
  }
  get isIP() {
    return !!this._def.checks.find((e) => e.kind === "ip");
  }
  get isCIDR() {
    return !!this._def.checks.find((e) => e.kind === "cidr");
  }
  get isBase64() {
    return !!this._def.checks.find((e) => e.kind === "base64");
  }
  get isBase64url() {
    return !!this._def.checks.find((e) => e.kind === "base64url");
  }
  get minLength() {
    let e = null;
    for (const t of this._def.checks)
      t.kind === "min" && (e === null || t.value > e) && (e = t.value);
    return e;
  }
  get maxLength() {
    let e = null;
    for (const t of this._def.checks)
      t.kind === "max" && (e === null || t.value < e) && (e = t.value);
    return e;
  }
}
Ce.create = (s) =>
  new Ce({
    checks: [],
    typeName: k.ZodString,
    coerce: s?.coerce ?? !1,
    ...O(s),
  });
function Yn(s, e) {
  const t = (s.toString().split(".")[1] || "").length,
    r = (e.toString().split(".")[1] || "").length,
    a = t > r ? t : r,
    i = Number.parseInt(s.toFixed(a).replace(".", "")),
    o = Number.parseInt(e.toFixed(a).replace(".", ""));
  return (i % o) / 10 ** a;
}
class Ue extends N {
  constructor() {
    (super(...arguments),
      (this.min = this.gte),
      (this.max = this.lte),
      (this.step = this.multipleOf));
  }
  _parse(e) {
    if (
      (this._def.coerce && (e.data = Number(e.data)),
      this._getType(e) !== I.number)
    ) {
      const i = this._getOrReturnCtx(e);
      return (
        v(i, {
          code: b.invalid_type,
          expected: I.number,
          received: i.parsedType,
        }),
        _
      );
    }
    let r;
    const a = new de();
    for (const i of this._def.checks)
      i.kind === "int"
        ? j.isInteger(e.data) ||
          ((r = this._getOrReturnCtx(e, r)),
          v(r, {
            code: b.invalid_type,
            expected: "integer",
            received: "float",
            message: i.message,
          }),
          a.dirty())
        : i.kind === "min"
          ? (i.inclusive ? e.data < i.value : e.data <= i.value) &&
            ((r = this._getOrReturnCtx(e, r)),
            v(r, {
              code: b.too_small,
              minimum: i.value,
              type: "number",
              inclusive: i.inclusive,
              exact: !1,
              message: i.message,
            }),
            a.dirty())
          : i.kind === "max"
            ? (i.inclusive ? e.data > i.value : e.data >= i.value) &&
              ((r = this._getOrReturnCtx(e, r)),
              v(r, {
                code: b.too_big,
                maximum: i.value,
                type: "number",
                inclusive: i.inclusive,
                exact: !1,
                message: i.message,
              }),
              a.dirty())
            : i.kind === "multipleOf"
              ? Yn(e.data, i.value) !== 0 &&
                ((r = this._getOrReturnCtx(e, r)),
                v(r, {
                  code: b.not_multiple_of,
                  multipleOf: i.value,
                  message: i.message,
                }),
                a.dirty())
              : i.kind === "finite"
                ? Number.isFinite(e.data) ||
                  ((r = this._getOrReturnCtx(e, r)),
                  v(r, { code: b.not_finite, message: i.message }),
                  a.dirty())
                : j.assertNever(i);
    return { status: a.value, value: e.data };
  }
  gte(e, t) {
    return this.setLimit("min", e, !0, x.toString(t));
  }
  gt(e, t) {
    return this.setLimit("min", e, !1, x.toString(t));
  }
  lte(e, t) {
    return this.setLimit("max", e, !0, x.toString(t));
  }
  lt(e, t) {
    return this.setLimit("max", e, !1, x.toString(t));
  }
  setLimit(e, t, r, a) {
    return new Ue({
      ...this._def,
      checks: [
        ...this._def.checks,
        { kind: e, value: t, inclusive: r, message: x.toString(a) },
      ],
    });
  }
  _addCheck(e) {
    return new Ue({ ...this._def, checks: [...this._def.checks, e] });
  }
  int(e) {
    return this._addCheck({ kind: "int", message: x.toString(e) });
  }
  positive(e) {
    return this._addCheck({
      kind: "min",
      value: 0,
      inclusive: !1,
      message: x.toString(e),
    });
  }
  negative(e) {
    return this._addCheck({
      kind: "max",
      value: 0,
      inclusive: !1,
      message: x.toString(e),
    });
  }
  nonpositive(e) {
    return this._addCheck({
      kind: "max",
      value: 0,
      inclusive: !0,
      message: x.toString(e),
    });
  }
  nonnegative(e) {
    return this._addCheck({
      kind: "min",
      value: 0,
      inclusive: !0,
      message: x.toString(e),
    });
  }
  multipleOf(e, t) {
    return this._addCheck({
      kind: "multipleOf",
      value: e,
      message: x.toString(t),
    });
  }
  finite(e) {
    return this._addCheck({ kind: "finite", message: x.toString(e) });
  }
  safe(e) {
    return this._addCheck({
      kind: "min",
      inclusive: !0,
      value: Number.MIN_SAFE_INTEGER,
      message: x.toString(e),
    })._addCheck({
      kind: "max",
      inclusive: !0,
      value: Number.MAX_SAFE_INTEGER,
      message: x.toString(e),
    });
  }
  get minValue() {
    let e = null;
    for (const t of this._def.checks)
      t.kind === "min" && (e === null || t.value > e) && (e = t.value);
    return e;
  }
  get maxValue() {
    let e = null;
    for (const t of this._def.checks)
      t.kind === "max" && (e === null || t.value < e) && (e = t.value);
    return e;
  }
  get isInt() {
    return !!this._def.checks.find(
      (e) =>
        e.kind === "int" || (e.kind === "multipleOf" && j.isInteger(e.value)),
    );
  }
  get isFinite() {
    let e = null,
      t = null;
    for (const r of this._def.checks) {
      if (r.kind === "finite" || r.kind === "int" || r.kind === "multipleOf")
        return !0;
      r.kind === "min"
        ? (t === null || r.value > t) && (t = r.value)
        : r.kind === "max" && (e === null || r.value < e) && (e = r.value);
    }
    return Number.isFinite(t) && Number.isFinite(e);
  }
}
Ue.create = (s) =>
  new Ue({
    checks: [],
    typeName: k.ZodNumber,
    coerce: s?.coerce || !1,
    ...O(s),
  });
class Pe extends N {
  constructor() {
    (super(...arguments), (this.min = this.gte), (this.max = this.lte));
  }
  _parse(e) {
    if (this._def.coerce)
      try {
        e.data = BigInt(e.data);
      } catch {
        return this._getInvalidInput(e);
      }
    if (this._getType(e) !== I.bigint) return this._getInvalidInput(e);
    let r;
    const a = new de();
    for (const i of this._def.checks)
      i.kind === "min"
        ? (i.inclusive ? e.data < i.value : e.data <= i.value) &&
          ((r = this._getOrReturnCtx(e, r)),
          v(r, {
            code: b.too_small,
            type: "bigint",
            minimum: i.value,
            inclusive: i.inclusive,
            message: i.message,
          }),
          a.dirty())
        : i.kind === "max"
          ? (i.inclusive ? e.data > i.value : e.data >= i.value) &&
            ((r = this._getOrReturnCtx(e, r)),
            v(r, {
              code: b.too_big,
              type: "bigint",
              maximum: i.value,
              inclusive: i.inclusive,
              message: i.message,
            }),
            a.dirty())
          : i.kind === "multipleOf"
            ? e.data % i.value !== BigInt(0) &&
              ((r = this._getOrReturnCtx(e, r)),
              v(r, {
                code: b.not_multiple_of,
                multipleOf: i.value,
                message: i.message,
              }),
              a.dirty())
            : j.assertNever(i);
    return { status: a.value, value: e.data };
  }
  _getInvalidInput(e) {
    const t = this._getOrReturnCtx(e);
    return (
      v(t, {
        code: b.invalid_type,
        expected: I.bigint,
        received: t.parsedType,
      }),
      _
    );
  }
  gte(e, t) {
    return this.setLimit("min", e, !0, x.toString(t));
  }
  gt(e, t) {
    return this.setLimit("min", e, !1, x.toString(t));
  }
  lte(e, t) {
    return this.setLimit("max", e, !0, x.toString(t));
  }
  lt(e, t) {
    return this.setLimit("max", e, !1, x.toString(t));
  }
  setLimit(e, t, r, a) {
    return new Pe({
      ...this._def,
      checks: [
        ...this._def.checks,
        { kind: e, value: t, inclusive: r, message: x.toString(a) },
      ],
    });
  }
  _addCheck(e) {
    return new Pe({ ...this._def, checks: [...this._def.checks, e] });
  }
  positive(e) {
    return this._addCheck({
      kind: "min",
      value: BigInt(0),
      inclusive: !1,
      message: x.toString(e),
    });
  }
  negative(e) {
    return this._addCheck({
      kind: "max",
      value: BigInt(0),
      inclusive: !1,
      message: x.toString(e),
    });
  }
  nonpositive(e) {
    return this._addCheck({
      kind: "max",
      value: BigInt(0),
      inclusive: !0,
      message: x.toString(e),
    });
  }
  nonnegative(e) {
    return this._addCheck({
      kind: "min",
      value: BigInt(0),
      inclusive: !0,
      message: x.toString(e),
    });
  }
  multipleOf(e, t) {
    return this._addCheck({
      kind: "multipleOf",
      value: e,
      message: x.toString(t),
    });
  }
  get minValue() {
    let e = null;
    for (const t of this._def.checks)
      t.kind === "min" && (e === null || t.value > e) && (e = t.value);
    return e;
  }
  get maxValue() {
    let e = null;
    for (const t of this._def.checks)
      t.kind === "max" && (e === null || t.value < e) && (e = t.value);
    return e;
  }
}
Pe.create = (s) =>
  new Pe({
    checks: [],
    typeName: k.ZodBigInt,
    coerce: s?.coerce ?? !1,
    ...O(s),
  });
class Ft extends N {
  _parse(e) {
    if (
      (this._def.coerce && (e.data = !!e.data), this._getType(e) !== I.boolean)
    ) {
      const r = this._getOrReturnCtx(e);
      return (
        v(r, {
          code: b.invalid_type,
          expected: I.boolean,
          received: r.parsedType,
        }),
        _
      );
    }
    return he(e.data);
  }
}
Ft.create = (s) =>
  new Ft({ typeName: k.ZodBoolean, coerce: s?.coerce || !1, ...O(s) });
class Ye extends N {
  _parse(e) {
    if (
      (this._def.coerce && (e.data = new Date(e.data)),
      this._getType(e) !== I.date)
    ) {
      const i = this._getOrReturnCtx(e);
      return (
        v(i, {
          code: b.invalid_type,
          expected: I.date,
          received: i.parsedType,
        }),
        _
      );
    }
    if (Number.isNaN(e.data.getTime())) {
      const i = this._getOrReturnCtx(e);
      return (v(i, { code: b.invalid_date }), _);
    }
    const r = new de();
    let a;
    for (const i of this._def.checks)
      i.kind === "min"
        ? e.data.getTime() < i.value &&
          ((a = this._getOrReturnCtx(e, a)),
          v(a, {
            code: b.too_small,
            message: i.message,
            inclusive: !0,
            exact: !1,
            minimum: i.value,
            type: "date",
          }),
          r.dirty())
        : i.kind === "max"
          ? e.data.getTime() > i.value &&
            ((a = this._getOrReturnCtx(e, a)),
            v(a, {
              code: b.too_big,
              message: i.message,
              inclusive: !0,
              exact: !1,
              maximum: i.value,
              type: "date",
            }),
            r.dirty())
          : j.assertNever(i);
    return { status: r.value, value: new Date(e.data.getTime()) };
  }
  _addCheck(e) {
    return new Ye({ ...this._def, checks: [...this._def.checks, e] });
  }
  min(e, t) {
    return this._addCheck({
      kind: "min",
      value: e.getTime(),
      message: x.toString(t),
    });
  }
  max(e, t) {
    return this._addCheck({
      kind: "max",
      value: e.getTime(),
      message: x.toString(t),
    });
  }
  get minDate() {
    let e = null;
    for (const t of this._def.checks)
      t.kind === "min" && (e === null || t.value > e) && (e = t.value);
    return e != null ? new Date(e) : null;
  }
  get maxDate() {
    let e = null;
    for (const t of this._def.checks)
      t.kind === "max" && (e === null || t.value < e) && (e = t.value);
    return e != null ? new Date(e) : null;
  }
}
Ye.create = (s) =>
  new Ye({ checks: [], coerce: s?.coerce || !1, typeName: k.ZodDate, ...O(s) });
class hr extends N {
  _parse(e) {
    if (this._getType(e) !== I.symbol) {
      const r = this._getOrReturnCtx(e);
      return (
        v(r, {
          code: b.invalid_type,
          expected: I.symbol,
          received: r.parsedType,
        }),
        _
      );
    }
    return he(e.data);
  }
}
hr.create = (s) => new hr({ typeName: k.ZodSymbol, ...O(s) });
class Mt extends N {
  _parse(e) {
    if (this._getType(e) !== I.undefined) {
      const r = this._getOrReturnCtx(e);
      return (
        v(r, {
          code: b.invalid_type,
          expected: I.undefined,
          received: r.parsedType,
        }),
        _
      );
    }
    return he(e.data);
  }
}
Mt.create = (s) => new Mt({ typeName: k.ZodUndefined, ...O(s) });
class Rt extends N {
  _parse(e) {
    if (this._getType(e) !== I.null) {
      const r = this._getOrReturnCtx(e);
      return (
        v(r, {
          code: b.invalid_type,
          expected: I.null,
          received: r.parsedType,
        }),
        _
      );
    }
    return he(e.data);
  }
}
Rt.create = (s) => new Rt({ typeName: k.ZodNull, ...O(s) });
class pt extends N {
  constructor() {
    (super(...arguments), (this._any = !0));
  }
  _parse(e) {
    return he(e.data);
  }
}
pt.create = (s) => new pt({ typeName: k.ZodAny, ...O(s) });
class We extends N {
  constructor() {
    (super(...arguments), (this._unknown = !0));
  }
  _parse(e) {
    return he(e.data);
  }
}
We.create = (s) => new We({ typeName: k.ZodUnknown, ...O(s) });
class Me extends N {
  _parse(e) {
    const t = this._getOrReturnCtx(e);
    return (
      v(t, { code: b.invalid_type, expected: I.never, received: t.parsedType }),
      _
    );
  }
}
Me.create = (s) => new Me({ typeName: k.ZodNever, ...O(s) });
class mr extends N {
  _parse(e) {
    if (this._getType(e) !== I.undefined) {
      const r = this._getOrReturnCtx(e);
      return (
        v(r, {
          code: b.invalid_type,
          expected: I.void,
          received: r.parsedType,
        }),
        _
      );
    }
    return he(e.data);
  }
}
mr.create = (s) => new mr({ typeName: k.ZodVoid, ...O(s) });
class we extends N {
  _parse(e) {
    const { ctx: t, status: r } = this._processInputParams(e),
      a = this._def;
    if (t.parsedType !== I.array)
      return (
        v(t, {
          code: b.invalid_type,
          expected: I.array,
          received: t.parsedType,
        }),
        _
      );
    if (a.exactLength !== null) {
      const o = t.data.length > a.exactLength.value,
        u = t.data.length < a.exactLength.value;
      (o || u) &&
        (v(t, {
          code: o ? b.too_big : b.too_small,
          minimum: u ? a.exactLength.value : void 0,
          maximum: o ? a.exactLength.value : void 0,
          type: "array",
          inclusive: !0,
          exact: !0,
          message: a.exactLength.message,
        }),
        r.dirty());
    }
    if (
      (a.minLength !== null &&
        t.data.length < a.minLength.value &&
        (v(t, {
          code: b.too_small,
          minimum: a.minLength.value,
          type: "array",
          inclusive: !0,
          exact: !1,
          message: a.minLength.message,
        }),
        r.dirty()),
      a.maxLength !== null &&
        t.data.length > a.maxLength.value &&
        (v(t, {
          code: b.too_big,
          maximum: a.maxLength.value,
          type: "array",
          inclusive: !0,
          exact: !1,
          message: a.maxLength.message,
        }),
        r.dirty()),
      t.common.async)
    )
      return Promise.all(
        [...t.data].map((o, u) => a.type._parseAsync(new Se(t, o, t.path, u))),
      ).then((o) => de.mergeArray(r, o));
    const i = [...t.data].map((o, u) =>
      a.type._parseSync(new Se(t, o, t.path, u)),
    );
    return de.mergeArray(r, i);
  }
  get element() {
    return this._def.type;
  }
  min(e, t) {
    return new we({
      ...this._def,
      minLength: { value: e, message: x.toString(t) },
    });
  }
  max(e, t) {
    return new we({
      ...this._def,
      maxLength: { value: e, message: x.toString(t) },
    });
  }
  length(e, t) {
    return new we({
      ...this._def,
      exactLength: { value: e, message: x.toString(t) },
    });
  }
  nonempty(e) {
    return this.min(1, e);
  }
}
we.create = (s, e) =>
  new we({
    type: s,
    minLength: null,
    maxLength: null,
    exactLength: null,
    typeName: k.ZodArray,
    ...O(e),
  });
function Qe(s) {
  if (s instanceof ee) {
    const e = {};
    for (const t in s.shape) {
      const r = s.shape[t];
      e[t] = Ee.create(Qe(r));
    }
    return new ee({ ...s._def, shape: () => e });
  } else
    return s instanceof we
      ? new we({ ...s._def, type: Qe(s.element) })
      : s instanceof Ee
        ? Ee.create(Qe(s.unwrap()))
        : s instanceof je
          ? je.create(Qe(s.unwrap()))
          : s instanceof Be
            ? Be.create(s.items.map((e) => Qe(e)))
            : s;
}
class ee extends N {
  constructor() {
    (super(...arguments),
      (this._cached = null),
      (this.nonstrict = this.passthrough),
      (this.augment = this.extend));
  }
  _getCached() {
    if (this._cached !== null) return this._cached;
    const e = this._def.shape(),
      t = j.objectKeys(e);
    return ((this._cached = { shape: e, keys: t }), this._cached);
  }
  _parse(e) {
    if (this._getType(e) !== I.object) {
      const l = this._getOrReturnCtx(e);
      return (
        v(l, {
          code: b.invalid_type,
          expected: I.object,
          received: l.parsedType,
        }),
        _
      );
    }
    const { status: r, ctx: a } = this._processInputParams(e),
      { shape: i, keys: o } = this._getCached(),
      u = [];
    if (!(
      this._def.catchall instanceof Me && this._def.unknownKeys === "strip"
    ))
      for (const l in a.data) o.includes(l) || u.push(l);
    const c = [];
    for (const l of o) {
      const d = i[l],
        p = a.data[l];
      c.push({
        key: { status: "valid", value: l },
        value: d._parse(new Se(a, p, a.path, l)),
        alwaysSet: l in a.data,
      });
    }
    if (this._def.catchall instanceof Me) {
      const l = this._def.unknownKeys;
      if (l === "passthrough")
        for (const d of u)
          c.push({
            key: { status: "valid", value: d },
            value: { status: "valid", value: a.data[d] },
          });
      else if (l === "strict")
        u.length > 0 &&
          (v(a, { code: b.unrecognized_keys, keys: u }), r.dirty());
      else if (l !== "strip")
        throw new Error("Internal ZodObject error: invalid unknownKeys value.");
    } else {
      const l = this._def.catchall;
      for (const d of u) {
        const p = a.data[d];
        c.push({
          key: { status: "valid", value: d },
          value: l._parse(new Se(a, p, a.path, d)),
          alwaysSet: d in a.data,
        });
      }
    }
    return a.common.async
      ? Promise.resolve()
          .then(async () => {
            const l = [];
            for (const d of c) {
              const p = await d.key,
                h = await d.value;
              l.push({ key: p, value: h, alwaysSet: d.alwaysSet });
            }
            return l;
          })
          .then((l) => de.mergeObjectSync(r, l))
      : de.mergeObjectSync(r, c);
  }
  get shape() {
    return this._def.shape();
  }
  strict(e) {
    return (
      x.errToObj,
      new ee({
        ...this._def,
        unknownKeys: "strict",
        ...(e !== void 0
          ? {
              errorMap: (t, r) => {
                const a = this._def.errorMap?.(t, r).message ?? r.defaultError;
                return t.code === "unrecognized_keys"
                  ? { message: x.errToObj(e).message ?? a }
                  : { message: a };
              },
            }
          : {}),
      })
    );
  }
  strip() {
    return new ee({ ...this._def, unknownKeys: "strip" });
  }
  passthrough() {
    return new ee({ ...this._def, unknownKeys: "passthrough" });
  }
  extend(e) {
    return new ee({
      ...this._def,
      shape: () => ({ ...this._def.shape(), ...e }),
    });
  }
  merge(e) {
    return new ee({
      unknownKeys: e._def.unknownKeys,
      catchall: e._def.catchall,
      shape: () => ({ ...this._def.shape(), ...e._def.shape() }),
      typeName: k.ZodObject,
    });
  }
  setKey(e, t) {
    return this.augment({ [e]: t });
  }
  catchall(e) {
    return new ee({ ...this._def, catchall: e });
  }
  pick(e) {
    const t = {};
    for (const r of j.objectKeys(e))
      e[r] && this.shape[r] && (t[r] = this.shape[r]);
    return new ee({ ...this._def, shape: () => t });
  }
  omit(e) {
    const t = {};
    for (const r of j.objectKeys(this.shape)) e[r] || (t[r] = this.shape[r]);
    return new ee({ ...this._def, shape: () => t });
  }
  deepPartial() {
    return Qe(this);
  }
  partial(e) {
    const t = {};
    for (const r of j.objectKeys(this.shape)) {
      const a = this.shape[r];
      e && !e[r] ? (t[r] = a) : (t[r] = a.optional());
    }
    return new ee({ ...this._def, shape: () => t });
  }
  required(e) {
    const t = {};
    for (const r of j.objectKeys(this.shape))
      if (e && !e[r]) t[r] = this.shape[r];
      else {
        let i = this.shape[r];
        for (; i instanceof Ee;) i = i._def.innerType;
        t[r] = i;
      }
    return new ee({ ...this._def, shape: () => t });
  }
  keyof() {
    return Aa(j.objectKeys(this.shape));
  }
}
ee.create = (s, e) =>
  new ee({
    shape: () => s,
    unknownKeys: "strip",
    catchall: Me.create(),
    typeName: k.ZodObject,
    ...O(e),
  });
ee.strictCreate = (s, e) =>
  new ee({
    shape: () => s,
    unknownKeys: "strict",
    catchall: Me.create(),
    typeName: k.ZodObject,
    ...O(e),
  });
ee.lazycreate = (s, e) =>
  new ee({
    shape: s,
    unknownKeys: "strip",
    catchall: Me.create(),
    typeName: k.ZodObject,
    ...O(e),
  });
class Ot extends N {
  _parse(e) {
    const { ctx: t } = this._processInputParams(e),
      r = this._def.options;
    function a(i) {
      for (const u of i) if (u.result.status === "valid") return u.result;
      for (const u of i)
        if (u.result.status === "dirty")
          return (t.common.issues.push(...u.ctx.common.issues), u.result);
      const o = i.map((u) => new be(u.ctx.common.issues));
      return (v(t, { code: b.invalid_union, unionErrors: o }), _);
    }
    if (t.common.async)
      return Promise.all(
        r.map(async (i) => {
          const o = { ...t, common: { ...t.common, issues: [] }, parent: null };
          return {
            result: await i._parseAsync({
              data: t.data,
              path: t.path,
              parent: o,
            }),
            ctx: o,
          };
        }),
      ).then(a);
    {
      let i;
      const o = [];
      for (const c of r) {
        const l = { ...t, common: { ...t.common, issues: [] }, parent: null },
          d = c._parseSync({ data: t.data, path: t.path, parent: l });
        if (d.status === "valid") return d;
        (d.status === "dirty" && !i && (i = { result: d, ctx: l }),
          l.common.issues.length && o.push(l.common.issues));
      }
      if (i) return (t.common.issues.push(...i.ctx.common.issues), i.result);
      const u = o.map((c) => new be(c));
      return (v(t, { code: b.invalid_union, unionErrors: u }), _);
    }
  }
  get options() {
    return this._def.options;
  }
}
Ot.create = (s, e) => new Ot({ options: s, typeName: k.ZodUnion, ...O(e) });
const Te = (s) =>
  s instanceof Ut
    ? Te(s.schema)
    : s instanceof Ie
      ? Te(s.innerType())
      : s instanceof Pt
        ? [s.value]
        : s instanceof qe
          ? s.options
          : s instanceof qt
            ? j.objectValues(s.enum)
            : s instanceof jt
              ? Te(s._def.innerType)
              : s instanceof Mt
                ? [void 0]
                : s instanceof Rt
                  ? [null]
                  : s instanceof Ee
                    ? [void 0, ...Te(s.unwrap())]
                    : s instanceof je
                      ? [null, ...Te(s.unwrap())]
                      : s instanceof ts || s instanceof Zt
                        ? Te(s.unwrap())
                        : s instanceof Vt
                          ? Te(s._def.innerType)
                          : [];
class Cr extends N {
  _parse(e) {
    const { ctx: t } = this._processInputParams(e);
    if (t.parsedType !== I.object)
      return (
        v(t, {
          code: b.invalid_type,
          expected: I.object,
          received: t.parsedType,
        }),
        _
      );
    const r = this.discriminator,
      a = t.data[r],
      i = this.optionsMap.get(a);
    return i
      ? t.common.async
        ? i._parseAsync({ data: t.data, path: t.path, parent: t })
        : i._parseSync({ data: t.data, path: t.path, parent: t })
      : (v(t, {
          code: b.invalid_union_discriminator,
          options: Array.from(this.optionsMap.keys()),
          path: [r],
        }),
        _);
  }
  get discriminator() {
    return this._def.discriminator;
  }
  get options() {
    return this._def.options;
  }
  get optionsMap() {
    return this._def.optionsMap;
  }
  static create(e, t, r) {
    const a = new Map();
    for (const i of t) {
      const o = Te(i.shape[e]);
      if (!o.length)
        throw new Error(
          `A discriminator value for key \`${e}\` could not be extracted from all schema options`,
        );
      for (const u of o) {
        if (a.has(u))
          throw new Error(
            `Discriminator property ${String(e)} has duplicate value ${String(u)}`,
          );
        a.set(u, i);
      }
    }
    return new Cr({
      typeName: k.ZodDiscriminatedUnion,
      discriminator: e,
      options: t,
      optionsMap: a,
      ...O(r),
    });
  }
}
function Gr(s, e) {
  const t = ke(s),
    r = ke(e);
  if (s === e) return { valid: !0, data: s };
  if (t === I.object && r === I.object) {
    const a = j.objectKeys(e),
      i = j.objectKeys(s).filter((u) => a.indexOf(u) !== -1),
      o = { ...s, ...e };
    for (const u of i) {
      const c = Gr(s[u], e[u]);
      if (!c.valid) return { valid: !1 };
      o[u] = c.data;
    }
    return { valid: !0, data: o };
  } else if (t === I.array && r === I.array) {
    if (s.length !== e.length) return { valid: !1 };
    const a = [];
    for (let i = 0; i < s.length; i++) {
      const o = s[i],
        u = e[i],
        c = Gr(o, u);
      if (!c.valid) return { valid: !1 };
      a.push(c.data);
    }
    return { valid: !0, data: a };
  } else
    return t === I.date && r === I.date && +s == +e
      ? { valid: !0, data: s }
      : { valid: !1 };
}
class Lt extends N {
  _parse(e) {
    const { status: t, ctx: r } = this._processInputParams(e),
      a = (i, o) => {
        if (Zr(i) || Zr(o)) return _;
        const u = Gr(i.value, o.value);
        return u.valid
          ? (($r(i) || $r(o)) && t.dirty(), { status: t.value, value: u.data })
          : (v(r, { code: b.invalid_intersection_types }), _);
      };
    return r.common.async
      ? Promise.all([
          this._def.left._parseAsync({ data: r.data, path: r.path, parent: r }),
          this._def.right._parseAsync({
            data: r.data,
            path: r.path,
            parent: r,
          }),
        ]).then(([i, o]) => a(i, o))
      : a(
          this._def.left._parseSync({ data: r.data, path: r.path, parent: r }),
          this._def.right._parseSync({ data: r.data, path: r.path, parent: r }),
        );
  }
}
Lt.create = (s, e, t) =>
  new Lt({ left: s, right: e, typeName: k.ZodIntersection, ...O(t) });
class Be extends N {
  _parse(e) {
    const { status: t, ctx: r } = this._processInputParams(e);
    if (r.parsedType !== I.array)
      return (
        v(r, {
          code: b.invalid_type,
          expected: I.array,
          received: r.parsedType,
        }),
        _
      );
    if (r.data.length < this._def.items.length)
      return (
        v(r, {
          code: b.too_small,
          minimum: this._def.items.length,
          inclusive: !0,
          exact: !1,
          type: "array",
        }),
        _
      );
    !this._def.rest &&
      r.data.length > this._def.items.length &&
      (v(r, {
        code: b.too_big,
        maximum: this._def.items.length,
        inclusive: !0,
        exact: !1,
        type: "array",
      }),
      t.dirty());
    const i = [...r.data]
      .map((o, u) => {
        const c = this._def.items[u] || this._def.rest;
        return c ? c._parse(new Se(r, o, r.path, u)) : null;
      })
      .filter((o) => !!o);
    return r.common.async
      ? Promise.all(i).then((o) => de.mergeArray(t, o))
      : de.mergeArray(t, i);
  }
  get items() {
    return this._def.items;
  }
  rest(e) {
    return new Be({ ...this._def, rest: e });
  }
}
Be.create = (s, e) => {
  if (!Array.isArray(s))
    throw new Error("You must pass an array of schemas to z.tuple([ ... ])");
  return new Be({ items: s, typeName: k.ZodTuple, rest: null, ...O(e) });
};
class Nt extends N {
  get keySchema() {
    return this._def.keyType;
  }
  get valueSchema() {
    return this._def.valueType;
  }
  _parse(e) {
    const { status: t, ctx: r } = this._processInputParams(e);
    if (r.parsedType !== I.object)
      return (
        v(r, {
          code: b.invalid_type,
          expected: I.object,
          received: r.parsedType,
        }),
        _
      );
    const a = [],
      i = this._def.keyType,
      o = this._def.valueType;
    for (const u in r.data)
      a.push({
        key: i._parse(new Se(r, u, r.path, u)),
        value: o._parse(new Se(r, r.data[u], r.path, u)),
        alwaysSet: u in r.data,
      });
    return r.common.async
      ? de.mergeObjectAsync(t, a)
      : de.mergeObjectSync(t, a);
  }
  get element() {
    return this._def.valueType;
  }
  static create(e, t, r) {
    return t instanceof N
      ? new Nt({ keyType: e, valueType: t, typeName: k.ZodRecord, ...O(r) })
      : new Nt({
          keyType: Ce.create(),
          valueType: e,
          typeName: k.ZodRecord,
          ...O(t),
        });
  }
}
class gr extends N {
  get keySchema() {
    return this._def.keyType;
  }
  get valueSchema() {
    return this._def.valueType;
  }
  _parse(e) {
    const { status: t, ctx: r } = this._processInputParams(e);
    if (r.parsedType !== I.map)
      return (
        v(r, { code: b.invalid_type, expected: I.map, received: r.parsedType }),
        _
      );
    const a = this._def.keyType,
      i = this._def.valueType,
      o = [...r.data.entries()].map(([u, c], l) => ({
        key: a._parse(new Se(r, u, r.path, [l, "key"])),
        value: i._parse(new Se(r, c, r.path, [l, "value"])),
      }));
    if (r.common.async) {
      const u = new Map();
      return Promise.resolve().then(async () => {
        for (const c of o) {
          const l = await c.key,
            d = await c.value;
          if (l.status === "aborted" || d.status === "aborted") return _;
          ((l.status === "dirty" || d.status === "dirty") && t.dirty(),
            u.set(l.value, d.value));
        }
        return { status: t.value, value: u };
      });
    } else {
      const u = new Map();
      for (const c of o) {
        const l = c.key,
          d = c.value;
        if (l.status === "aborted" || d.status === "aborted") return _;
        ((l.status === "dirty" || d.status === "dirty") && t.dirty(),
          u.set(l.value, d.value));
      }
      return { status: t.value, value: u };
    }
  }
}
gr.create = (s, e, t) =>
  new gr({ valueType: e, keyType: s, typeName: k.ZodMap, ...O(t) });
class Je extends N {
  _parse(e) {
    const { status: t, ctx: r } = this._processInputParams(e);
    if (r.parsedType !== I.set)
      return (
        v(r, { code: b.invalid_type, expected: I.set, received: r.parsedType }),
        _
      );
    const a = this._def;
    (a.minSize !== null &&
      r.data.size < a.minSize.value &&
      (v(r, {
        code: b.too_small,
        minimum: a.minSize.value,
        type: "set",
        inclusive: !0,
        exact: !1,
        message: a.minSize.message,
      }),
      t.dirty()),
      a.maxSize !== null &&
        r.data.size > a.maxSize.value &&
        (v(r, {
          code: b.too_big,
          maximum: a.maxSize.value,
          type: "set",
          inclusive: !0,
          exact: !1,
          message: a.maxSize.message,
        }),
        t.dirty()));
    const i = this._def.valueType;
    function o(c) {
      const l = new Set();
      for (const d of c) {
        if (d.status === "aborted") return _;
        (d.status === "dirty" && t.dirty(), l.add(d.value));
      }
      return { status: t.value, value: l };
    }
    const u = [...r.data.values()].map((c, l) =>
      i._parse(new Se(r, c, r.path, l)),
    );
    return r.common.async ? Promise.all(u).then((c) => o(c)) : o(u);
  }
  min(e, t) {
    return new Je({
      ...this._def,
      minSize: { value: e, message: x.toString(t) },
    });
  }
  max(e, t) {
    return new Je({
      ...this._def,
      maxSize: { value: e, message: x.toString(t) },
    });
  }
  size(e, t) {
    return this.min(e, t).max(e, t);
  }
  nonempty(e) {
    return this.min(1, e);
  }
}
Je.create = (s, e) =>
  new Je({
    valueType: s,
    minSize: null,
    maxSize: null,
    typeName: k.ZodSet,
    ...O(e),
  });
class it extends N {
  constructor() {
    (super(...arguments), (this.validate = this.implement));
  }
  _parse(e) {
    const { ctx: t } = this._processInputParams(e);
    if (t.parsedType !== I.function)
      return (
        v(t, {
          code: b.invalid_type,
          expected: I.function,
          received: t.parsedType,
        }),
        _
      );
    function r(u, c) {
      return pr({
        data: u,
        path: t.path,
        errorMaps: [
          t.common.contextualErrorMap,
          t.schemaErrorMap,
          dr(),
          dt,
        ].filter((l) => !!l),
        issueData: { code: b.invalid_arguments, argumentsError: c },
      });
    }
    function a(u, c) {
      return pr({
        data: u,
        path: t.path,
        errorMaps: [
          t.common.contextualErrorMap,
          t.schemaErrorMap,
          dr(),
          dt,
        ].filter((l) => !!l),
        issueData: { code: b.invalid_return_type, returnTypeError: c },
      });
    }
    const i = { errorMap: t.common.contextualErrorMap },
      o = t.data;
    if (this._def.returns instanceof ht) {
      const u = this;
      return he(async function (...c) {
        const l = new be([]),
          d = await u._def.args.parseAsync(c, i).catch((m) => {
            throw (l.addIssue(r(c, m)), l);
          }),
          p = await Reflect.apply(o, this, d);
        return await u._def.returns._def.type.parseAsync(p, i).catch((m) => {
          throw (l.addIssue(a(p, m)), l);
        });
      });
    } else {
      const u = this;
      return he(function (...c) {
        const l = u._def.args.safeParse(c, i);
        if (!l.success) throw new be([r(c, l.error)]);
        const d = Reflect.apply(o, this, l.data),
          p = u._def.returns.safeParse(d, i);
        if (!p.success) throw new be([a(d, p.error)]);
        return p.data;
      });
    }
  }
  parameters() {
    return this._def.args;
  }
  returnType() {
    return this._def.returns;
  }
  args(...e) {
    return new it({ ...this._def, args: Be.create(e).rest(We.create()) });
  }
  returns(e) {
    return new it({ ...this._def, returns: e });
  }
  implement(e) {
    return this.parse(e);
  }
  strictImplement(e) {
    return this.parse(e);
  }
  static create(e, t, r) {
    return new it({
      args: e || Be.create([]).rest(We.create()),
      returns: t || We.create(),
      typeName: k.ZodFunction,
      ...O(r),
    });
  }
}
class Ut extends N {
  get schema() {
    return this._def.getter();
  }
  _parse(e) {
    const { ctx: t } = this._processInputParams(e);
    return this._def.getter()._parse({ data: t.data, path: t.path, parent: t });
  }
}
Ut.create = (s, e) => new Ut({ getter: s, typeName: k.ZodLazy, ...O(e) });
class Pt extends N {
  _parse(e) {
    if (e.data !== this._def.value) {
      const t = this._getOrReturnCtx(e);
      return (
        v(t, {
          received: t.data,
          code: b.invalid_literal,
          expected: this._def.value,
        }),
        _
      );
    }
    return { status: "valid", value: e.data };
  }
  get value() {
    return this._def.value;
  }
}
Pt.create = (s, e) => new Pt({ value: s, typeName: k.ZodLiteral, ...O(e) });
function Aa(s, e) {
  return new qe({ values: s, typeName: k.ZodEnum, ...O(e) });
}
class qe extends N {
  _parse(e) {
    if (typeof e.data != "string") {
      const t = this._getOrReturnCtx(e),
        r = this._def.values;
      return (
        v(t, {
          expected: j.joinValues(r),
          received: t.parsedType,
          code: b.invalid_type,
        }),
        _
      );
    }
    if (
      (this._cache || (this._cache = new Set(this._def.values)),
      !this._cache.has(e.data))
    ) {
      const t = this._getOrReturnCtx(e),
        r = this._def.values;
      return (
        v(t, { received: t.data, code: b.invalid_enum_value, options: r }),
        _
      );
    }
    return he(e.data);
  }
  get options() {
    return this._def.values;
  }
  get enum() {
    const e = {};
    for (const t of this._def.values) e[t] = t;
    return e;
  }
  get Values() {
    const e = {};
    for (const t of this._def.values) e[t] = t;
    return e;
  }
  get Enum() {
    const e = {};
    for (const t of this._def.values) e[t] = t;
    return e;
  }
  extract(e, t = this._def) {
    return qe.create(e, { ...this._def, ...t });
  }
  exclude(e, t = this._def) {
    return qe.create(
      this.options.filter((r) => !e.includes(r)),
      { ...this._def, ...t },
    );
  }
}
qe.create = Aa;
class qt extends N {
  _parse(e) {
    const t = j.getValidEnumValues(this._def.values),
      r = this._getOrReturnCtx(e);
    if (r.parsedType !== I.string && r.parsedType !== I.number) {
      const a = j.objectValues(t);
      return (
        v(r, {
          expected: j.joinValues(a),
          received: r.parsedType,
          code: b.invalid_type,
        }),
        _
      );
    }
    if (
      (this._cache ||
        (this._cache = new Set(j.getValidEnumValues(this._def.values))),
      !this._cache.has(e.data))
    ) {
      const a = j.objectValues(t);
      return (
        v(r, { received: r.data, code: b.invalid_enum_value, options: a }),
        _
      );
    }
    return he(e.data);
  }
  get enum() {
    return this._def.values;
  }
}
qt.create = (s, e) => new qt({ values: s, typeName: k.ZodNativeEnum, ...O(e) });
class ht extends N {
  unwrap() {
    return this._def.type;
  }
  _parse(e) {
    const { ctx: t } = this._processInputParams(e);
    if (t.parsedType !== I.promise && t.common.async === !1)
      return (
        v(t, {
          code: b.invalid_type,
          expected: I.promise,
          received: t.parsedType,
        }),
        _
      );
    const r = t.parsedType === I.promise ? t.data : Promise.resolve(t.data);
    return he(
      r.then((a) =>
        this._def.type.parseAsync(a, {
          path: t.path,
          errorMap: t.common.contextualErrorMap,
        }),
      ),
    );
  }
}
ht.create = (s, e) => new ht({ type: s, typeName: k.ZodPromise, ...O(e) });
class Ie extends N {
  innerType() {
    return this._def.schema;
  }
  sourceType() {
    return this._def.schema._def.typeName === k.ZodEffects
      ? this._def.schema.sourceType()
      : this._def.schema;
  }
  _parse(e) {
    const { status: t, ctx: r } = this._processInputParams(e),
      a = this._def.effect || null,
      i = {
        addIssue: (o) => {
          (v(r, o), o.fatal ? t.abort() : t.dirty());
        },
        get path() {
          return r.path;
        },
      };
    if (((i.addIssue = i.addIssue.bind(i)), a.type === "preprocess")) {
      const o = a.transform(r.data, i);
      if (r.common.async)
        return Promise.resolve(o).then(async (u) => {
          if (t.value === "aborted") return _;
          const c = await this._def.schema._parseAsync({
            data: u,
            path: r.path,
            parent: r,
          });
          return c.status === "aborted"
            ? _
            : c.status === "dirty" || t.value === "dirty"
              ? rt(c.value)
              : c;
        });
      {
        if (t.value === "aborted") return _;
        const u = this._def.schema._parseSync({
          data: o,
          path: r.path,
          parent: r,
        });
        return u.status === "aborted"
          ? _
          : u.status === "dirty" || t.value === "dirty"
            ? rt(u.value)
            : u;
      }
    }
    if (a.type === "refinement") {
      const o = (u) => {
        const c = a.refinement(u, i);
        if (r.common.async) return Promise.resolve(c);
        if (c instanceof Promise)
          throw new Error(
            "Async refinement encountered during synchronous parse operation. Use .parseAsync instead.",
          );
        return u;
      };
      if (r.common.async === !1) {
        const u = this._def.schema._parseSync({
          data: r.data,
          path: r.path,
          parent: r,
        });
        return u.status === "aborted"
          ? _
          : (u.status === "dirty" && t.dirty(),
            o(u.value),
            { status: t.value, value: u.value });
      } else
        return this._def.schema
          ._parseAsync({ data: r.data, path: r.path, parent: r })
          .then((u) =>
            u.status === "aborted"
              ? _
              : (u.status === "dirty" && t.dirty(),
                o(u.value).then(() => ({ status: t.value, value: u.value }))),
          );
    }
    if (a.type === "transform")
      if (r.common.async === !1) {
        const o = this._def.schema._parseSync({
          data: r.data,
          path: r.path,
          parent: r,
        });
        if (!Ke(o)) return _;
        const u = a.transform(o.value, i);
        if (u instanceof Promise)
          throw new Error(
            "Asynchronous transform encountered during synchronous parse operation. Use .parseAsync instead.",
          );
        return { status: t.value, value: u };
      } else
        return this._def.schema
          ._parseAsync({ data: r.data, path: r.path, parent: r })
          .then((o) =>
            Ke(o)
              ? Promise.resolve(a.transform(o.value, i)).then((u) => ({
                  status: t.value,
                  value: u,
                }))
              : _,
          );
    j.assertNever(a);
  }
}
Ie.create = (s, e, t) =>
  new Ie({ schema: s, typeName: k.ZodEffects, effect: e, ...O(t) });
Ie.createWithPreprocess = (s, e, t) =>
  new Ie({
    schema: e,
    effect: { type: "preprocess", transform: s },
    typeName: k.ZodEffects,
    ...O(t),
  });
class Ee extends N {
  _parse(e) {
    return this._getType(e) === I.undefined
      ? he(void 0)
      : this._def.innerType._parse(e);
  }
  unwrap() {
    return this._def.innerType;
  }
}
Ee.create = (s, e) =>
  new Ee({ innerType: s, typeName: k.ZodOptional, ...O(e) });
class je extends N {
  _parse(e) {
    return this._getType(e) === I.null
      ? he(null)
      : this._def.innerType._parse(e);
  }
  unwrap() {
    return this._def.innerType;
  }
}
je.create = (s, e) =>
  new je({ innerType: s, typeName: k.ZodNullable, ...O(e) });
class jt extends N {
  _parse(e) {
    const { ctx: t } = this._processInputParams(e);
    let r = t.data;
    return (
      t.parsedType === I.undefined && (r = this._def.defaultValue()),
      this._def.innerType._parse({ data: r, path: t.path, parent: t })
    );
  }
  removeDefault() {
    return this._def.innerType;
  }
}
jt.create = (s, e) =>
  new jt({
    innerType: s,
    typeName: k.ZodDefault,
    defaultValue: typeof e.default == "function" ? e.default : () => e.default,
    ...O(e),
  });
class Vt extends N {
  _parse(e) {
    const { ctx: t } = this._processInputParams(e),
      r = { ...t, common: { ...t.common, issues: [] } },
      a = this._def.innerType._parse({
        data: r.data,
        path: r.path,
        parent: { ...r },
      });
    return kt(a)
      ? a.then((i) => ({
          status: "valid",
          value:
            i.status === "valid"
              ? i.value
              : this._def.catchValue({
                  get error() {
                    return new be(r.common.issues);
                  },
                  input: r.data,
                }),
        }))
      : {
          status: "valid",
          value:
            a.status === "valid"
              ? a.value
              : this._def.catchValue({
                  get error() {
                    return new be(r.common.issues);
                  },
                  input: r.data,
                }),
        };
  }
  removeCatch() {
    return this._def.innerType;
  }
}
Vt.create = (s, e) =>
  new Vt({
    innerType: s,
    typeName: k.ZodCatch,
    catchValue: typeof e.catch == "function" ? e.catch : () => e.catch,
    ...O(e),
  });
class fr extends N {
  _parse(e) {
    if (this._getType(e) !== I.nan) {
      const r = this._getOrReturnCtx(e);
      return (
        v(r, { code: b.invalid_type, expected: I.nan, received: r.parsedType }),
        _
      );
    }
    return { status: "valid", value: e.data };
  }
}
fr.create = (s) => new fr({ typeName: k.ZodNaN, ...O(s) });
const Jn = Symbol("zod_brand");
class ts extends N {
  _parse(e) {
    const { ctx: t } = this._processInputParams(e),
      r = t.data;
    return this._def.type._parse({ data: r, path: t.path, parent: t });
  }
  unwrap() {
    return this._def.type;
  }
}
class $t extends N {
  _parse(e) {
    const { status: t, ctx: r } = this._processInputParams(e);
    if (r.common.async)
      return (async () => {
        const i = await this._def.in._parseAsync({
          data: r.data,
          path: r.path,
          parent: r,
        });
        return i.status === "aborted"
          ? _
          : i.status === "dirty"
            ? (t.dirty(), rt(i.value))
            : this._def.out._parseAsync({
                data: i.value,
                path: r.path,
                parent: r,
              });
      })();
    {
      const a = this._def.in._parseSync({
        data: r.data,
        path: r.path,
        parent: r,
      });
      return a.status === "aborted"
        ? _
        : a.status === "dirty"
          ? (t.dirty(), { status: "dirty", value: a.value })
          : this._def.out._parseSync({
              data: a.value,
              path: r.path,
              parent: r,
            });
    }
  }
  static create(e, t) {
    return new $t({ in: e, out: t, typeName: k.ZodPipeline });
  }
}
class Zt extends N {
  _parse(e) {
    const t = this._def.innerType._parse(e),
      r = (a) => (Ke(a) && (a.value = Object.freeze(a.value)), a);
    return kt(t) ? t.then((a) => r(a)) : r(t);
  }
  unwrap() {
    return this._def.innerType;
  }
}
Zt.create = (s, e) =>
  new Zt({ innerType: s, typeName: k.ZodReadonly, ...O(e) });
function Ss(s, e) {
  const t =
    typeof s == "function" ? s(e) : typeof s == "string" ? { message: s } : s;
  return typeof t == "string" ? { message: t } : t;
}
function va(s, e = {}, t) {
  return s
    ? pt.create().superRefine((r, a) => {
        const i = s(r);
        if (i instanceof Promise)
          return i.then((o) => {
            if (!o) {
              const u = Ss(e, r),
                c = u.fatal ?? t ?? !0;
              a.addIssue({ code: "custom", ...u, fatal: c });
            }
          });
        if (!i) {
          const o = Ss(e, r),
            u = o.fatal ?? t ?? !0;
          a.addIssue({ code: "custom", ...o, fatal: u });
        }
      })
    : pt.create();
}
const Qn = { object: ee.lazycreate };
var k;
(function (s) {
  ((s.ZodString = "ZodString"),
    (s.ZodNumber = "ZodNumber"),
    (s.ZodNaN = "ZodNaN"),
    (s.ZodBigInt = "ZodBigInt"),
    (s.ZodBoolean = "ZodBoolean"),
    (s.ZodDate = "ZodDate"),
    (s.ZodSymbol = "ZodSymbol"),
    (s.ZodUndefined = "ZodUndefined"),
    (s.ZodNull = "ZodNull"),
    (s.ZodAny = "ZodAny"),
    (s.ZodUnknown = "ZodUnknown"),
    (s.ZodNever = "ZodNever"),
    (s.ZodVoid = "ZodVoid"),
    (s.ZodArray = "ZodArray"),
    (s.ZodObject = "ZodObject"),
    (s.ZodUnion = "ZodUnion"),
    (s.ZodDiscriminatedUnion = "ZodDiscriminatedUnion"),
    (s.ZodIntersection = "ZodIntersection"),
    (s.ZodTuple = "ZodTuple"),
    (s.ZodRecord = "ZodRecord"),
    (s.ZodMap = "ZodMap"),
    (s.ZodSet = "ZodSet"),
    (s.ZodFunction = "ZodFunction"),
    (s.ZodLazy = "ZodLazy"),
    (s.ZodLiteral = "ZodLiteral"),
    (s.ZodEnum = "ZodEnum"),
    (s.ZodEffects = "ZodEffects"),
    (s.ZodNativeEnum = "ZodNativeEnum"),
    (s.ZodOptional = "ZodOptional"),
    (s.ZodNullable = "ZodNullable"),
    (s.ZodDefault = "ZodDefault"),
    (s.ZodCatch = "ZodCatch"),
    (s.ZodPromise = "ZodPromise"),
    (s.ZodBranded = "ZodBranded"),
    (s.ZodPipeline = "ZodPipeline"),
    (s.ZodReadonly = "ZodReadonly"));
})(k || (k = {}));
const Xn = (s, e = { message: `Input not instance of ${s.name}` }) =>
    va((t) => t instanceof s, e),
  Ca = Ce.create,
  wa = Ue.create,
  eo = fr.create,
  to = Pe.create,
  Ia = Ft.create,
  ro = Ye.create,
  so = hr.create,
  ao = Mt.create,
  io = Rt.create,
  no = pt.create,
  oo = We.create,
  uo = Me.create,
  co = mr.create,
  lo = we.create,
  po = ee.create,
  ho = ee.strictCreate,
  mo = Ot.create,
  go = Cr.create,
  fo = Lt.create,
  bo = Be.create,
  Do = Nt.create,
  yo = gr.create,
  Ao = Je.create,
  vo = it.create,
  Co = Ut.create,
  wo = Pt.create,
  Io = qe.create,
  xo = qt.create,
  Eo = ht.create,
  Bs = Ie.create,
  So = Ee.create,
  Bo = je.create,
  _o = Ie.createWithPreprocess,
  To = $t.create,
  ko = () => Ca().optional(),
  Fo = () => wa().optional(),
  Mo = () => Ia().optional(),
  Ro = {
    string: (s) => Ce.create({ ...s, coerce: !0 }),
    number: (s) => Ue.create({ ...s, coerce: !0 }),
    boolean: (s) => Ft.create({ ...s, coerce: !0 }),
    bigint: (s) => Pe.create({ ...s, coerce: !0 }),
    date: (s) => Ye.create({ ...s, coerce: !0 }),
  },
  Oo = _,
  xa = Object.freeze(
    Object.defineProperty(
      {
        __proto__: null,
        BRAND: Jn,
        DIRTY: rt,
        EMPTY_PATH: _n,
        INVALID: _,
        NEVER: Oo,
        OK: he,
        ParseStatus: de,
        Schema: N,
        ZodAny: pt,
        ZodArray: we,
        ZodBigInt: Pe,
        ZodBoolean: Ft,
        ZodBranded: ts,
        ZodCatch: Vt,
        ZodDate: Ye,
        ZodDefault: jt,
        ZodDiscriminatedUnion: Cr,
        ZodEffects: Ie,
        ZodEnum: qe,
        ZodError: be,
        get ZodFirstPartyTypeKind() {
          return k;
        },
        ZodFunction: it,
        ZodIntersection: Lt,
        ZodIssueCode: b,
        ZodLazy: Ut,
        ZodLiteral: Pt,
        ZodMap: gr,
        ZodNaN: fr,
        ZodNativeEnum: qt,
        ZodNever: Me,
        ZodNull: Rt,
        ZodNullable: je,
        ZodNumber: Ue,
        ZodObject: ee,
        ZodOptional: Ee,
        ZodParsedType: I,
        ZodPipeline: $t,
        ZodPromise: ht,
        ZodReadonly: Zt,
        ZodRecord: Nt,
        ZodSchema: N,
        ZodSet: Je,
        ZodString: Ce,
        ZodSymbol: hr,
        ZodTransformer: Ie,
        ZodTuple: Be,
        ZodType: N,
        ZodUndefined: Mt,
        ZodUnion: Ot,
        ZodUnknown: We,
        ZodVoid: mr,
        addIssueToContext: v,
        any: no,
        array: lo,
        bigint: to,
        boolean: Ia,
        coerce: Ro,
        custom: va,
        date: ro,
        datetimeRegex: ya,
        defaultErrorMap: dt,
        discriminatedUnion: go,
        effect: Bs,
        enum: Io,
        function: vo,
        getErrorMap: dr,
        getParsedType: ke,
        instanceof: Xn,
        intersection: fo,
        isAborted: Zr,
        isAsync: kt,
        isDirty: $r,
        isValid: Ke,
        late: Qn,
        lazy: Co,
        literal: wo,
        makeIssue: pr,
        map: yo,
        nan: eo,
        nativeEnum: xo,
        never: uo,
        null: io,
        nullable: Bo,
        number: wa,
        object: po,
        get objectUtil() {
          return Vr;
        },
        oboolean: Mo,
        onumber: Fo,
        optional: So,
        ostring: ko,
        pipeline: To,
        preprocess: _o,
        promise: Eo,
        quotelessJson: Sn,
        record: Do,
        set: Ao,
        setErrorMap: Bn,
        strictObject: ho,
        string: Ca,
        symbol: so,
        transformer: Bs,
        tuple: bo,
        undefined: ao,
        union: mo,
        unknown: oo,
        get util() {
          return j;
        },
        void: co,
      },
      Symbol.toStringTag,
      { value: "Module" },
    ),
  );
function It(s, e) {
  var t = {};
  for (var r in s)
    Object.prototype.hasOwnProperty.call(s, r) &&
      e.indexOf(r) < 0 &&
      (t[r] = s[r]);
  if (s != null && typeof Object.getOwnPropertySymbols == "function")
    for (var a = 0, r = Object.getOwnPropertySymbols(s); a < r.length; a++)
      e.indexOf(r[a]) < 0 &&
        Object.prototype.propertyIsEnumerable.call(s, r[a]) &&
        (t[r[a]] = s[r[a]]);
  return t;
}
function L(s, e) {
  var t;
  return ((t = s?._def) === null || t === void 0 ? void 0 : t.typeName) === e;
}
function Lo(s) {
  return "_def" in s;
}
function yt(s, e) {
  const t = s.ZodType.prototype[e];
  s.ZodType.prototype[e] = function (...r) {
    const a = t.apply(this, r);
    return ((a._def.openapi = this._def.openapi), a);
  };
}
function No(s) {
  if (typeof s.ZodType.prototype.openapi < "u") return;
  ((s.ZodType.prototype.openapi = function (a, i) {
    var o, u, c, l, d, p;
    const h = typeof a == "string" ? i : a,
      m = h ?? {},
      { param: g } = m,
      f = It(m, ["param"]),
      A = Object.assign(
        Object.assign(
          {},
          (o = this._def.openapi) === null || o === void 0
            ? void 0
            : o._internal,
        ),
        typeof a == "string" ? { refId: a } : void 0,
      ),
      T = Object.assign(
        Object.assign(
          Object.assign(
            {},
            (u = this._def.openapi) === null || u === void 0
              ? void 0
              : u.metadata,
          ),
          f,
        ),
        (!(
          (l =
            (c = this._def.openapi) === null || c === void 0
              ? void 0
              : c.metadata) === null || l === void 0
        ) &&
          l.param) ||
          g
          ? {
              param: Object.assign(
                Object.assign(
                  {},
                  (p =
                    (d = this._def.openapi) === null || d === void 0
                      ? void 0
                      : d.metadata) === null || p === void 0
                    ? void 0
                    : p.param,
                ),
                g,
              ),
            }
          : void 0,
      ),
      E = new this.constructor(
        Object.assign(Object.assign({}, this._def), {
          openapi: Object.assign(
            Object.assign(
              {},
              Object.keys(A).length > 0 ? { _internal: A } : void 0,
            ),
            Object.keys(T).length > 0 ? { metadata: T } : void 0,
          ),
        }),
      );
    if (L(this, "ZodObject")) {
      const R = this.extend;
      E.extend = function (...P) {
        var Y, z, M, q, V, te, oe;
        const re = R.apply(this, P);
        return (
          (re._def.openapi = {
            _internal: {
              extendedFrom:
                !(
                  (z =
                    (Y = this._def.openapi) === null || Y === void 0
                      ? void 0
                      : Y._internal) === null || z === void 0
                ) && z.refId
                  ? {
                      refId:
                        (q =
                          (M = this._def.openapi) === null || M === void 0
                            ? void 0
                            : M._internal) === null || q === void 0
                          ? void 0
                          : q.refId,
                      schema: this,
                    }
                  : (te =
                        (V = this._def.openapi) === null || V === void 0
                          ? void 0
                          : V._internal) === null || te === void 0
                    ? void 0
                    : te.extendedFrom,
            },
            metadata:
              (oe = re._def.openapi) === null || oe === void 0
                ? void 0
                : oe.metadata,
          }),
          re
        );
      };
    }
    return E;
  }),
    yt(s, "optional"),
    yt(s, "nullable"),
    yt(s, "default"),
    yt(s, "transform"),
    yt(s, "refine"));
  const e = s.ZodObject.prototype.deepPartial;
  s.ZodObject.prototype.deepPartial = function () {
    const a = this._def.shape(),
      i = e.apply(this),
      o = i._def.shape();
    return (
      Object.entries(o).forEach(([u, c]) => {
        var l, d;
        c._def.openapi =
          (d = (l = a[u]) === null || l === void 0 ? void 0 : l._def) ===
            null || d === void 0
            ? void 0
            : d.openapi;
      }),
      (i._def.openapi = void 0),
      i
    );
  };
  const t = s.ZodObject.prototype.pick;
  s.ZodObject.prototype.pick = function (...a) {
    const i = t.apply(this, a);
    return ((i._def.openapi = void 0), i);
  };
  const r = s.ZodObject.prototype.omit;
  s.ZodObject.prototype.omit = function (...a) {
    const i = r.apply(this, a);
    return ((i._def.openapi = void 0), i);
  };
}
function br(s, e) {
  if (s == null || e === null || e === void 0) return s === e;
  if (s === e || s.valueOf() === e.valueOf()) return !0;
  if (
    (Array.isArray(s) && (!Array.isArray(e) || s.length !== e.length)) ||
    !(s instanceof Object) ||
    !(e instanceof Object)
  )
    return !1;
  const t = Object.keys(s);
  return (
    Object.keys(e).every((r) => t.indexOf(r) !== -1) &&
    t.every((r) => br(s[r], e[r]))
  );
}
class Uo {
  constructor() {
    this.buckets = new Map();
  }
  put(e) {
    const t = this.hashCodeOf(e),
      r = this.buckets.get(t);
    if (!r) {
      this.buckets.set(t, [e]);
      return;
    }
    r.some((i) => br(i, e)) || r.push(e);
  }
  contains(e) {
    const t = this.hashCodeOf(e),
      r = this.buckets.get(t);
    return r ? r.some((a) => br(a, e)) : !1;
  }
  values() {
    return [...this.buckets.values()].flat();
  }
  stats() {
    let e = 0,
      t = 0,
      r = 0;
    for (const i of this.buckets.values())
      ((e += 1), (t += i.length), i.length > 1 && (r += 1));
    const a = e / t;
    return {
      totalBuckets: e,
      collisions: r,
      totalValues: t,
      hashEffectiveness: a,
    };
  }
  hashCodeOf(e) {
    let t = 0;
    if (Array.isArray(e)) {
      for (let r = 0; r < e.length; r++) t ^= this.hashCodeOf(e[r]) * r;
      return t;
    }
    if (typeof e == "string") {
      for (let r = 0; r < e.length; r++) t ^= e.charCodeAt(r) * r;
      return t;
    }
    if (typeof e == "number") return e;
    if (typeof e == "object")
      for (const [r, a] of Object.entries(e))
        t ^= this.hashCodeOf(r) + this.hashCodeOf(a ?? "");
    return t;
  }
}
function Bt(s) {
  return s === void 0;
}
function _t(s, e) {
  const t = {};
  return (
    Object.entries(s).forEach(([r, a]) => {
      t[r] = e(a);
    }),
    t
  );
}
function Po(s, e) {
  const t = {};
  return (
    Object.entries(s).forEach(([r, a]) => {
      e.some((i) => i === r) || (t[r] = a);
    }),
    t
  );
}
function nt(s, e) {
  const t = {};
  return (
    Object.entries(s).forEach(([r, a]) => {
      e(a, r) || (t[r] = a);
    }),
    t
  );
}
function _s(s) {
  return s.filter((e) => !Bt(e));
}
const zr = br;
function qo(s) {
  const e = new Uo();
  return (s.forEach((t) => e.put(t)), [...e.values()]);
}
function Ea(s) {
  return typeof s == "string";
}
class kp {
  constructor(e) {
    ((this.parents = e), (this._definitions = []));
  }
  get definitions() {
    var e, t;
    return [
      ...((t =
        (e = this.parents) === null || e === void 0
          ? void 0
          : e.flatMap((a) => a.definitions)) !== null && t !== void 0
        ? t
        : []),
      ...this._definitions,
    ];
  }
  register(e, t) {
    const r = this.schemaWithRefId(e, t);
    return (this._definitions.push({ type: "schema", schema: r }), r);
  }
  registerParameter(e, t) {
    var r, a, i;
    const o = this.schemaWithRefId(e, t),
      u = (r = o._def.openapi) === null || r === void 0 ? void 0 : r.metadata,
      c = o.openapi(
        Object.assign(Object.assign({}, u), {
          param: Object.assign(Object.assign({}, u?.param), {
            name:
              (i =
                (a = u?.param) === null || a === void 0 ? void 0 : a.name) !==
                null && i !== void 0
                ? i
                : e,
          }),
        }),
      );
    return (this._definitions.push({ type: "parameter", schema: c }), c);
  }
  registerPath(e) {
    this._definitions.push({ type: "route", route: e });
  }
  registerWebhook(e) {
    this._definitions.push({ type: "webhook", webhook: e });
  }
  registerComponent(e, t, r) {
    return (
      this._definitions.push({
        type: "component",
        componentType: e,
        name: t,
        component: r,
      }),
      { name: t, ref: { $ref: `#/components/${e}/${t}` } }
    );
  }
  schemaWithRefId(e, t) {
    return t.openapi(e);
  }
}
class wr {
  constructor(e) {
    this.message = e;
  }
}
class At extends wr {
  constructor(e, t) {
    (super(e), (this.data = t));
  }
}
class Dr extends wr {
  constructor(e) {
    (super(
      `Missing parameter data, please specify \`${e.missingField}\` and other OpenAPI parameter props using the \`param\` field of \`ZodSchema.openapi\``,
    ),
      (this.data = e));
  }
}
function vt(s, e) {
  try {
    return s();
  } catch (t) {
    throw t instanceof Dr
      ? new Dr(Object.assign(Object.assign({}, t.data), e))
      : t;
  }
}
class jo extends wr {
  constructor(e) {
    (super(
      "Unknown zod object type, please specify `type` and other OpenAPI props using `ZodSchema.openapi`.",
    ),
      (this.data = e));
  }
}
class Q {
  static getMetadata(e) {
    var t;
    const r = this.unwrapChained(e),
      a = e._def.openapi ? e._def.openapi : r._def.openapi,
      i = (t = e.description) !== null && t !== void 0 ? t : r.description;
    return {
      _internal: a?._internal,
      metadata: Object.assign({ description: i }, a?.metadata),
    };
  }
  static getInternalMetadata(e) {
    const t = this.unwrapChained(e),
      r = e._def.openapi ? e._def.openapi : t._def.openapi;
    return r?._internal;
  }
  static getParamMetadata(e) {
    var t, r;
    const a = this.unwrapChained(e),
      i = e._def.openapi ? e._def.openapi : a._def.openapi,
      o = (t = e.description) !== null && t !== void 0 ? t : a.description;
    return {
      _internal: i?._internal,
      metadata: Object.assign(Object.assign({}, i?.metadata), {
        param: Object.assign(
          { description: o },
          (r = i?.metadata) === null || r === void 0 ? void 0 : r.param,
        ),
      }),
    };
  }
  static buildSchemaMetadata(e) {
    return nt(Po(e, ["param"]), Bt);
  }
  static buildParameterMetadata(e) {
    return nt(e, Bt);
  }
  static applySchemaMetadata(e, t) {
    return nt(
      Object.assign(Object.assign({}, e), this.buildSchemaMetadata(t)),
      Bt,
    );
  }
  static getRefId(e) {
    var t;
    return (t = this.getInternalMetadata(e)) === null || t === void 0
      ? void 0
      : t.refId;
  }
  static unwrapChained(e) {
    return this.unwrapUntil(e);
  }
  static getDefaultValue(e) {
    const t = this.unwrapUntil(e, "ZodDefault");
    return t?._def.defaultValue();
  }
  static unwrapUntil(e, t) {
    return t && L(e, t)
      ? e
      : L(e, "ZodOptional") || L(e, "ZodNullable") || L(e, "ZodBranded")
        ? this.unwrapUntil(e.unwrap(), t)
        : L(e, "ZodDefault") || L(e, "ZodReadonly")
          ? this.unwrapUntil(e._def.innerType, t)
          : L(e, "ZodEffects")
            ? this.unwrapUntil(e._def.schema, t)
            : L(e, "ZodPipeline")
              ? this.unwrapUntil(e._def.in, t)
              : t
                ? void 0
                : e;
  }
  static isOptionalSchema(e) {
    return e.isOptional();
  }
}
class Vo {
  transform(e, t, r) {
    var a, i;
    const o = e._def.type;
    return Object.assign(Object.assign({}, t("array")), {
      items: r(o),
      minItems:
        (a = e._def.minLength) === null || a === void 0 ? void 0 : a.value,
      maxItems:
        (i = e._def.maxLength) === null || i === void 0 ? void 0 : i.value,
    });
  }
}
class Zo {
  transform(e) {
    return Object.assign(Object.assign({}, e("string")), { pattern: "^d+$" });
  }
}
class $o {
  transform(e, t, r, a, i) {
    const o = [...e.options.values()],
      u = o.map(a);
    return t
      ? { oneOf: r(u, t) }
      : {
          oneOf: u,
          discriminator: this.mapDiscriminator(o, e.discriminator, i),
        };
  }
  mapDiscriminator(e, t, r) {
    if (e.some((i) => Q.getRefId(i) === void 0)) return;
    const a = {};
    return (
      e.forEach((i) => {
        var o;
        const u = Q.getRefId(i),
          c = (o = i.shape) === null || o === void 0 ? void 0 : o[t];
        if (L(c, "ZodEnum") || L(c, "ZodNativeEnum")) {
          Object.values(c.enum)
            .filter(Ea)
            .forEach((p) => {
              a[p] = r(u);
            });
          return;
        }
        const l = c?._def.value;
        if (typeof l != "string")
          throw new Error(
            `Discriminator ${t} could not be found in one of the values of a discriminated union`,
          );
        a[l] = r(u);
      }),
      { propertyName: t, mapping: a }
    );
  }
}
class Go {
  transform(e, t) {
    return Object.assign(Object.assign({}, t("string")), {
      enum: e._def.values,
    });
  }
}
class zo {
  transform(e, t, r, a) {
    const o = { allOf: this.flattenIntersectionTypes(e).map(a) };
    return t ? { anyOf: r([o], t) } : o;
  }
  flattenIntersectionTypes(e) {
    if (!L(e, "ZodIntersection")) return [e];
    const t = this.flattenIntersectionTypes(e._def.left),
      r = this.flattenIntersectionTypes(e._def.right);
    return [...t, ...r];
  }
}
class Ho {
  transform(e, t) {
    return Object.assign(Object.assign({}, t(typeof e._def.value)), {
      enum: [e._def.value],
    });
  }
}
function Wo(s) {
  const t = Object.keys(s)
      .filter((i) => typeof s[s[i]] != "number")
      .map((i) => s[i]),
    r = t.filter((i) => typeof i == "number").length,
    a = r === 0 ? "string" : r === t.length ? "numeric" : "mixed";
  return { values: t, type: a };
}
class Ko {
  transform(e, t) {
    const { type: r, values: a } = Wo(e._def.values);
    if (r === "mixed")
      throw new wr(
        "Enum has mixed string and number values, please specify the OpenAPI type manually",
      );
    return Object.assign(
      Object.assign({}, t(r === "numeric" ? "integer" : "string")),
      { enum: a },
    );
  }
}
class Yo {
  transform(e, t, r) {
    return Object.assign(
      Object.assign({}, t(e.isInt ? "integer" : "number")),
      r(e._def.checks),
    );
  }
}
class Jo {
  transform(e, t, r, a) {
    var i;
    const o =
        (i = Q.getInternalMetadata(e)) === null || i === void 0
          ? void 0
          : i.extendedFrom,
      u = this.requiredKeysOf(e),
      c = _t(e._def.shape(), a);
    if (!o)
      return Object.assign(
        Object.assign(
          Object.assign(Object.assign({}, r("object")), {
            properties: c,
            default: t,
          }),
          u.length > 0 ? { required: u } : {},
        ),
        this.generateAdditionalProperties(e, a),
      );
    const l = o.schema;
    a(l);
    const d = this.requiredKeysOf(l),
      p = _t(l?._def.shape(), a),
      h = Object.fromEntries(
        Object.entries(c).filter(([f, A]) => !zr(p[f], A)),
      ),
      m = u.filter((f) => !d.includes(f)),
      g = Object.assign(
        Object.assign(
          Object.assign(Object.assign({}, r("object")), {
            default: t,
            properties: h,
          }),
          m.length > 0 ? { required: m } : {},
        ),
        this.generateAdditionalProperties(e, a),
      );
    return { allOf: [{ $ref: `#/components/schemas/${o.refId}` }, g] };
  }
  generateAdditionalProperties(e, t) {
    const r = e._def.unknownKeys,
      a = e._def.catchall;
    return L(a, "ZodNever")
      ? r === "strict"
        ? { additionalProperties: !1 }
        : {}
      : { additionalProperties: t(a) };
  }
  requiredKeysOf(e) {
    return Object.entries(e._def.shape())
      .filter(([t, r]) => !Q.isOptionalSchema(r))
      .map(([t, r]) => t);
  }
}
class Qo {
  transform(e, t, r) {
    const a = e._def.valueType,
      i = e._def.keyType,
      o = r(a);
    if (L(i, "ZodEnum") || L(i, "ZodNativeEnum")) {
      const c = Object.values(i.enum)
        .filter(Ea)
        .reduce((l, d) => Object.assign(Object.assign({}, l), { [d]: o }), {});
      return Object.assign(Object.assign({}, t("object")), { properties: c });
    }
    return Object.assign(Object.assign({}, t("object")), {
      additionalProperties: o,
    });
  }
}
class Xo {
  transform(e, t) {
    var r, a, i;
    const o = this.getZodStringCheck(e, "regex"),
      u =
        (r = this.getZodStringCheck(e, "length")) === null || r === void 0
          ? void 0
          : r.value,
      c =
        Number.isFinite(e.minLength) &&
        (a = e.minLength) !== null &&
        a !== void 0
          ? a
          : void 0,
      l =
        Number.isFinite(e.maxLength) &&
        (i = e.maxLength) !== null &&
        i !== void 0
          ? i
          : void 0;
    return Object.assign(Object.assign({}, t("string")), {
      minLength: u ?? c,
      maxLength: u ?? l,
      format: this.mapStringFormat(e),
      pattern: o?.regex.source,
    });
  }
  mapStringFormat(e) {
    if (e.isUUID) return "uuid";
    if (e.isEmail) return "email";
    if (e.isURL) return "uri";
    if (e.isDate) return "date";
    if (e.isDatetime) return "date-time";
    if (e.isCUID) return "cuid";
    if (e.isCUID2) return "cuid2";
    if (e.isULID) return "ulid";
    if (e.isIP) return "ip";
    if (e.isEmoji) return "emoji";
  }
  getZodStringCheck(e, t) {
    return e._def.checks.find((r) => r.kind === t);
  }
}
class eu {
  constructor(e) {
    this.versionSpecifics = e;
  }
  transform(e, t, r) {
    const { items: a } = e._def,
      i = a.map(r);
    return Object.assign(
      Object.assign({}, t("array")),
      this.versionSpecifics.mapTupleItems(i),
    );
  }
}
class tu {
  transform(e, t, r) {
    const i = this.flattenUnionTypes(e).map((o) => {
      const u = this.unwrapNullable(o);
      return r(u);
    });
    return { anyOf: t(i) };
  }
  flattenUnionTypes(e) {
    return L(e, "ZodUnion")
      ? e._def.options.flatMap((r) => this.flattenUnionTypes(r))
      : [e];
  }
  unwrapNullable(e) {
    return L(e, "ZodNullable") ? this.unwrapNullable(e.unwrap()) : e;
  }
}
class ru {
  constructor(e) {
    ((this.versionSpecifics = e),
      (this.objectTransformer = new Jo()),
      (this.stringTransformer = new Xo()),
      (this.numberTransformer = new Yo()),
      (this.bigIntTransformer = new Zo()),
      (this.literalTransformer = new Ho()),
      (this.enumTransformer = new Go()),
      (this.nativeEnumTransformer = new Ko()),
      (this.arrayTransformer = new Vo()),
      (this.unionTransformer = new tu()),
      (this.discriminatedUnionTransformer = new $o()),
      (this.intersectionTransformer = new zo()),
      (this.recordTransformer = new Qo()),
      (this.tupleTransformer = new eu(e)));
  }
  transform(e, t, r, a, i) {
    if (L(e, "ZodNull")) return this.versionSpecifics.nullType;
    if (L(e, "ZodUnknown") || L(e, "ZodAny"))
      return this.versionSpecifics.mapNullableType(void 0, t);
    if (L(e, "ZodObject"))
      return this.objectTransformer.transform(
        e,
        i,
        (u) => this.versionSpecifics.mapNullableType(u, t),
        r,
      );
    const o = this.transformSchemaWithoutDefault(e, t, r, a);
    return Object.assign(Object.assign({}, o), { default: i });
  }
  transformSchemaWithoutDefault(e, t, r, a) {
    if (L(e, "ZodUnknown") || L(e, "ZodAny"))
      return this.versionSpecifics.mapNullableType(void 0, t);
    if (L(e, "ZodString"))
      return this.stringTransformer.transform(e, (o) =>
        this.versionSpecifics.mapNullableType(o, t),
      );
    if (L(e, "ZodNumber"))
      return this.numberTransformer.transform(
        e,
        (o) => this.versionSpecifics.mapNullableType(o, t),
        (o) => this.versionSpecifics.getNumberChecks(o),
      );
    if (L(e, "ZodBigInt"))
      return this.bigIntTransformer.transform((o) =>
        this.versionSpecifics.mapNullableType(o, t),
      );
    if (L(e, "ZodBoolean"))
      return this.versionSpecifics.mapNullableType("boolean", t);
    if (L(e, "ZodLiteral"))
      return this.literalTransformer.transform(e, (o) =>
        this.versionSpecifics.mapNullableType(o, t),
      );
    if (L(e, "ZodEnum"))
      return this.enumTransformer.transform(e, (o) =>
        this.versionSpecifics.mapNullableType(o, t),
      );
    if (L(e, "ZodNativeEnum"))
      return this.nativeEnumTransformer.transform(e, (o) =>
        this.versionSpecifics.mapNullableType(o, t),
      );
    if (L(e, "ZodArray"))
      return this.arrayTransformer.transform(
        e,
        (o) => this.versionSpecifics.mapNullableType(o, t),
        r,
      );
    if (L(e, "ZodTuple"))
      return this.tupleTransformer.transform(
        e,
        (o) => this.versionSpecifics.mapNullableType(o, t),
        r,
      );
    if (L(e, "ZodUnion"))
      return this.unionTransformer.transform(
        e,
        (o) => this.versionSpecifics.mapNullableOfArray(o, t),
        r,
      );
    if (L(e, "ZodDiscriminatedUnion"))
      return this.discriminatedUnionTransformer.transform(
        e,
        t,
        (o) => this.versionSpecifics.mapNullableOfArray(o, t),
        r,
        a,
      );
    if (L(e, "ZodIntersection"))
      return this.intersectionTransformer.transform(
        e,
        t,
        (o) => this.versionSpecifics.mapNullableOfArray(o, t),
        r,
      );
    if (L(e, "ZodRecord"))
      return this.recordTransformer.transform(
        e,
        (o) => this.versionSpecifics.mapNullableType(o, t),
        r,
      );
    if (L(e, "ZodDate"))
      return this.versionSpecifics.mapNullableType("string", t);
    const i = Q.getRefId(e);
    throw new jo({ currentSchema: e._def, schemaName: i });
  }
}
class su {
  constructor(e, t) {
    ((this.definitions = e),
      (this.versionSpecifics = t),
      (this.schemaRefs = {}),
      (this.paramRefs = {}),
      (this.pathRefs = {}),
      (this.rawComponents = []),
      (this.openApiTransformer = new ru(t)),
      this.sortDefinitions());
  }
  generateDocumentData() {
    return (
      this.definitions.forEach((e) => this.generateSingle(e)),
      { components: this.buildComponents(), paths: this.pathRefs }
    );
  }
  generateComponents() {
    return (
      this.definitions.forEach((e) => this.generateSingle(e)),
      { components: this.buildComponents() }
    );
  }
  buildComponents() {
    var e, t;
    const r = {};
    return (
      this.rawComponents.forEach(
        ({ componentType: a, name: i, component: o }) => {
          var u;
          (((u = r[a]) !== null && u !== void 0) || (r[a] = {}), (r[a][i] = o));
        },
      ),
      Object.assign(Object.assign({}, r), {
        schemas: Object.assign(
          Object.assign({}, (e = r.schemas) !== null && e !== void 0 ? e : {}),
          this.schemaRefs,
        ),
        parameters: Object.assign(
          Object.assign(
            {},
            (t = r.parameters) !== null && t !== void 0 ? t : {},
          ),
          this.paramRefs,
        ),
      })
    );
  }
  sortDefinitions() {
    const e = ["schema", "parameter", "component", "route"];
    this.definitions.sort((t, r) => {
      if (!("type" in t)) return "type" in r ? -1 : 0;
      if (!("type" in r)) return 1;
      const a = e.findIndex((o) => o === t.type),
        i = e.findIndex((o) => o === r.type);
      return a - i;
    });
  }
  generateSingle(e) {
    if (!("type" in e)) {
      this.generateSchemaWithRef(e);
      return;
    }
    switch (e.type) {
      case "parameter":
        this.generateParameterDefinition(e.schema);
        return;
      case "schema":
        this.generateSchemaWithRef(e.schema);
        return;
      case "route":
        this.generateSingleRoute(e.route);
        return;
      case "component":
        this.rawComponents.push(e);
        return;
    }
  }
  generateParameterDefinition(e) {
    const t = Q.getRefId(e),
      r = this.generateParameter(e);
    return (t && (this.paramRefs[t] = r), r);
  }
  getParameterRef(e, t) {
    var r, a, i, o, u;
    const c = (r = e?.metadata) === null || r === void 0 ? void 0 : r.param,
      l =
        !((a = e?._internal) === null || a === void 0) && a.refId
          ? this.paramRefs[
              (i = e._internal) === null || i === void 0 ? void 0 : i.refId
            ]
          : void 0;
    if (!(!(!((o = e?._internal) === null || o === void 0) && o.refId) || !l)) {
      if ((c && l.in !== c.in) || (t?.in && l.in !== t.in))
        throw new At(`Conflicting location for parameter ${l.name}`, {
          key: "in",
          values: _s([l.in, t?.in, c?.in]),
        });
      if ((c && l.name !== c.name) || (t?.name && l.name !== t?.name))
        throw new At("Conflicting names for parameter", {
          key: "name",
          values: _s([l.name, t?.name, c?.name]),
        });
      return {
        $ref: `#/components/parameters/${(u = e._internal) === null || u === void 0 ? void 0 : u.refId}`,
      };
    }
  }
  generateInlineParameters(e, t) {
    var r;
    const a = Q.getMetadata(e),
      i = (r = a?.metadata) === null || r === void 0 ? void 0 : r.param,
      o = this.getParameterRef(a, { in: t });
    if (o) return [o];
    if (L(e, "ZodObject")) {
      const u = e._def.shape();
      return Object.entries(u).map(([l, d]) => {
        var p, h;
        const m = Q.getMetadata(d),
          g = this.getParameterRef(m, { in: t, name: l });
        if (g) return g;
        const f = (p = m?.metadata) === null || p === void 0 ? void 0 : p.param;
        if (f?.name && f.name !== l)
          throw new At("Conflicting names for parameter", {
            key: "name",
            values: [l, f.name],
          });
        if (f?.in && f.in !== t)
          throw new At(
            `Conflicting location for parameter ${(h = f.name) !== null && h !== void 0 ? h : l}`,
            { key: "in", values: [t, f.in] },
          );
        return this.generateParameter(d.openapi({ param: { name: l, in: t } }));
      });
    }
    if (i?.in && i.in !== t)
      throw new At(`Conflicting location for parameter ${i.name}`, {
        key: "in",
        values: [t, i.in],
      });
    return [this.generateParameter(e.openapi({ param: { in: t } }))];
  }
  generateSimpleParameter(e) {
    var t;
    const r = Q.getParamMetadata(e),
      a = (t = r?.metadata) === null || t === void 0 ? void 0 : t.param,
      i = !Q.isOptionalSchema(e) && !e.isNullable(),
      o = this.generateSchemaWithRef(e);
    return Object.assign(
      { schema: o, required: i },
      a ? Q.buildParameterMetadata(a) : {},
    );
  }
  generateParameter(e) {
    var t;
    const r = Q.getMetadata(e),
      a = (t = r?.metadata) === null || t === void 0 ? void 0 : t.param,
      i = a?.name,
      o = a?.in;
    if (!i) throw new Dr({ missingField: "name" });
    if (!o) throw new Dr({ missingField: "in", paramName: i });
    const u = this.generateSimpleParameter(e);
    return Object.assign(Object.assign({}, u), { in: o, name: i });
  }
  generateSchemaWithMetadata(e) {
    var t;
    const r = Q.unwrapChained(e),
      a = Q.getMetadata(e),
      i = Q.getDefaultValue(e),
      o =
        !((t = a?.metadata) === null || t === void 0) && t.type
          ? { type: a?.metadata.type }
          : this.toOpenAPISchema(r, e.isNullable(), i);
    return a?.metadata ? Q.applySchemaMetadata(o, a.metadata) : nt(o, Bt);
  }
  constructReferencedOpenAPISchema(e) {
    var t;
    const r = Q.getMetadata(e),
      a = Q.unwrapChained(e),
      i = Q.getDefaultValue(e),
      o = e.isNullable();
    return !((t = r?.metadata) === null || t === void 0) && t.type
      ? this.versionSpecifics.mapNullableType(r.metadata.type, o)
      : this.toOpenAPISchema(a, o, i);
  }
  generateSimpleSchema(e) {
    var t;
    const r = Q.getMetadata(e),
      a = Q.getRefId(e);
    if (!a || !this.schemaRefs[a]) return this.generateSchemaWithMetadata(e);
    const i = this.schemaRefs[a],
      o = { $ref: this.generateSchemaRef(a) },
      u = nt(
        Q.buildSchemaMetadata(
          (t = r?.metadata) !== null && t !== void 0 ? t : {},
        ),
        (d, p) => d === void 0 || zr(d, i[p]),
      );
    if (u.type) return { allOf: [o, u] };
    const c = nt(
        this.constructReferencedOpenAPISchema(e),
        (d, p) => d === void 0 || zr(d, i[p]),
      ),
      l = Q.applySchemaMetadata(c, u);
    return Object.keys(l).length > 0 ? { allOf: [o, l] } : o;
  }
  generateSchemaWithRef(e) {
    const t = Q.getRefId(e),
      r = this.generateSimpleSchema(e);
    return t && this.schemaRefs[t] === void 0
      ? ((this.schemaRefs[t] = r), { $ref: this.generateSchemaRef(t) })
      : r;
  }
  generateSchemaRef(e) {
    return `#/components/schemas/${e}`;
  }
  getRequestBody(e) {
    if (!e) return;
    const { content: t } = e,
      r = It(e, ["content"]),
      a = this.getBodyContent(t);
    return Object.assign(Object.assign({}, r), { content: a });
  }
  getParameters(e) {
    if (!e) return [];
    const { headers: t } = e,
      r = this.cleanParameter(e.query),
      a = this.cleanParameter(e.params),
      i = this.cleanParameter(e.cookies),
      o = vt(() => (r ? this.generateInlineParameters(r, "query") : []), {
        location: "query",
      }),
      u = vt(() => (a ? this.generateInlineParameters(a, "path") : []), {
        location: "path",
      }),
      c = vt(() => (i ? this.generateInlineParameters(i, "cookie") : []), {
        location: "cookie",
      }),
      l = vt(
        () => {
          if (Array.isArray(t))
            return t.flatMap((p) => this.generateInlineParameters(p, "header"));
          const d = this.cleanParameter(t);
          return d ? this.generateInlineParameters(d, "header") : [];
        },
        { location: "header" },
      );
    return [...u, ...o, ...l, ...c];
  }
  cleanParameter(e) {
    if (e) return L(e, "ZodEffects") ? this.cleanParameter(e._def.schema) : e;
  }
  generatePath(e) {
    const { method: t, path: r, request: a, responses: i } = e,
      o = It(e, ["method", "path", "request", "responses"]),
      u = _t(i, (p) => this.getResponse(p)),
      c = vt(() => this.getParameters(a), { route: `${t} ${r}` }),
      l = this.getRequestBody(a?.body);
    return {
      [t]: Object.assign(
        Object.assign(
          Object.assign(
            Object.assign({}, o),
            c.length > 0 ? { parameters: [...(o.parameters || []), ...c] } : {},
          ),
          l ? { requestBody: l } : {},
        ),
        { responses: u },
      ),
    };
  }
  generateSingleRoute(e) {
    const t = this.generatePath(e);
    return (
      (this.pathRefs[e.path] = Object.assign(
        Object.assign({}, this.pathRefs[e.path]),
        t,
      )),
      t
    );
  }
  getResponse(e) {
    if (this.isReferenceObject(e)) return e;
    const { content: t, headers: r } = e,
      a = It(e, ["content", "headers"]),
      i = t ? { content: this.getBodyContent(t) } : {};
    if (!r) return Object.assign(Object.assign({}, a), i);
    const o = L(r, "ZodObject") ? this.getResponseHeaders(r) : r;
    return Object.assign(
      Object.assign(Object.assign({}, a), { headers: o }),
      i,
    );
  }
  isReferenceObject(e) {
    return "$ref" in e;
  }
  getResponseHeaders(e) {
    const t = e._def.shape();
    return _t(t, (a) => this.generateSimpleParameter(a));
  }
  getBodyContent(e) {
    return _t(e, (t) => {
      if (!t || !Lo(t.schema)) return t;
      const { schema: r } = t,
        a = It(t, ["schema"]),
        i = this.generateSchemaWithRef(r);
      return Object.assign({ schema: i }, a);
    });
  }
  toOpenAPISchema(e, t, r) {
    return this.openApiTransformer.transform(
      e,
      t,
      (a) => this.generateSchemaWithRef(a),
      (a) => this.generateSchemaRef(a),
      r,
    );
  }
}
class au {
  get nullType() {
    return { nullable: !0 };
  }
  mapNullableOfArray(e, t) {
    return t ? [...e, this.nullType] : e;
  }
  mapNullableType(e, t) {
    return Object.assign(
      Object.assign({}, e ? { type: e } : void 0),
      t ? this.nullType : void 0,
    );
  }
  mapTupleItems(e) {
    const t = qo(e);
    return {
      items: t.length === 1 ? t[0] : { anyOf: t },
      minItems: e.length,
      maxItems: e.length,
    };
  }
  getNumberChecks(e) {
    return Object.assign(
      {},
      ...e.map((t) => {
        switch (t.kind) {
          case "min":
            return t.inclusive
              ? { minimum: Number(t.value) }
              : { minimum: Number(t.value), exclusiveMinimum: !0 };
          case "max":
            return t.inclusive
              ? { maximum: Number(t.value) }
              : { maximum: Number(t.value), exclusiveMaximum: !0 };
          default:
            return {};
        }
      }),
    );
  }
}
class Fp {
  constructor(e) {
    const t = new au();
    this.generator = new su(e, t);
  }
  generateDocument(e) {
    const t = this.generator.generateDocumentData();
    return Object.assign(Object.assign({}, e), t);
  }
  generateComponents() {
    return this.generator.generateComponents();
  }
}
No(xa);
const iu = 50,
  yr = 200,
  nu = 20,
  ou = 200,
  mt =
    "May be temporary or available only on this device; download promptly if durable access is needed.",
  Xe = "Beeper Desktop v4.2.785+",
  Ts = "Beeper Desktop v4.2.808+",
  uu =
    "Opaque pagination cursor; do not inspect. Use together with 'direction'.",
  n = xa,
  K = n
    .string()
    .describe(
      "Chat ID. Input routes also accept the local chat ID from this installation when available.",
    )
    .openapi({ example: "!NCdzlIaMjZUmvmvyHU:beeper.com" }),
  gt = K.openapi({
    param: {
      name: "chatID",
      in: "path",
      description: "Chat ID or local chat ID.",
      required: !0,
    },
  }),
  Oe = n.string().describe("Account ID this resource belongs to."),
  rs = Oe.openapi({
    param: {
      name: "accountID",
      in: "path",
      description: "Account ID this resource belongs to.",
      required: !0,
      examples: {
        AccountIDExample: {
          value: "local-whatsapp_ba_EvYDBBsZbRQAy3UOSWqG0LuTVkc",
          summary: "Sample account ID",
        },
      },
    },
  }),
  De = n.string().describe("Message ID.").openapi({ example: "1343993" }),
  Gt = De.openapi({
    param: {
      name: "messageID",
      in: "path",
      description: "Message ID.",
      required: !0,
    },
  }),
  cu = n
    .string()
    .describe(
      "Fully qualified sender user ID. Network-backed IDs usually include the network prefix and homeserver.",
    )
    .openapi({ example: "@kishanbagaria:local-whatsapp.localhost" }),
  Fe = n
    .string()
    .datetime()
    .describe("ISO 8601 timestamp.")
    .openapi({ example: "2025-08-31T23:30:12.520Z" }),
  lu = n
    .number()
    .int()
    .describe("Number of unread messages.")
    .openapi({ example: 3 }),
  du = n
    .preprocess(
      (s) => (typeof s == "string" ? [s] : s),
      n.array(n.string()).optional(),
    )
    .describe("Limit search to specific chat IDs.")
    .openapi({ example: ["!NCdzlIaMjZUmvmvyHU:beeper.com", "1231073"] }),
  ss = n
    .preprocess((s) => {
      if (typeof s == "string") return [s];
      if (!(
        s &&
        typeof s == "object" &&
        !Array.isArray(s) &&
        Object.keys(s).length === 0
      ))
        return s;
    }, n.array(Oe).optional())
    .describe("Limit search to specific account IDs.")
    .openapi({
      example: [
        "matrix",
        "discordgo",
        "local-whatsapp_ba_EvYDBBsZbRQAy3UOSWqG0LuTVkc",
      ],
    }),
  zt = n
    .object({
      id: n
        .string()
        .describe(
          "Stable Beeper user ID. Use as the primary key when referencing a person.",
        ),
      username: n
        .string()
        .optional()
        .describe(
          "Human-readable handle if available (e.g., '@alice'). May be network-specific and not globally unique.",
        ),
      phoneNumber: n
        .string()
        .optional()
        .describe(
          "User's phone number in E.164 format (e.g., '+14155552671'). Omit if unknown.",
        ),
      email: n
        .string()
        .optional()
        .describe("Email address if known. Not guaranteed verified."),
      fullName: n
        .string()
        .optional()
        .describe(
          "Display name as shown in clients (e.g., 'Alice Example'). May include emojis.",
        ),
      imgURL: n
        .string()
        .optional()
        .describe(
          `Avatar image URL if available. This may be a remote URL, media URL, data URL, or local file URL depending on the source. ${mt}`,
        ),
      cannotMessage: n
        .boolean()
        .optional()
        .describe(
          "True if Beeper cannot initiate messages to this user (e.g., blocked, network restriction, or no DM path). The user may still message you.",
        ),
      isSelf: n
        .boolean()
        .optional()
        .describe(
          "True if this user represents the authenticated account's own identity.",
        ),
    })
    .describe(
      "A person on or reachable through Beeper. Values are best-effort and can vary by network.",
    )
    .openapi("User"),
  pu = zt
    .extend({
      isAdmin: n
        .boolean()
        .optional()
        .describe("True if this participant has admin privileges in the chat."),
      isPending: n
        .boolean()
        .optional()
        .describe(
          "True if this participant has been invited but has not joined yet.",
        ),
      isNetworkBot: n
        .boolean()
        .optional()
        .describe(
          "True if this participant represents an automated network account.",
        ),
    })
    .describe("A chat participant. Extends User with chat membership metadata.")
    .openapi("Participant"),
  hu = n
    .object({
      id: n
        .string()
        .describe(
          `Bridge identifier. Beeper Cloud accounts often use the network type (for example matrix or discordgo); on-device accounts use a local bridge ID (for example local-whatsapp). Available in ${Xe}.`,
        ),
      type: n
        .string()
        .describe(
          `Bridge type, such as matrix, discordgo, slackgo, whatsapp, telegram, or twitter. Available in ${Xe}.`,
        ),
      provider: n
        .enum(es)
        .describe(
          `Where this account runs: on this device or in Beeper Cloud. Available in ${Xe}.`,
        ),
    })
    .describe(`Bridge metadata for a chat account. Available in ${Xe}.`)
    .openapi("AccountBridge", { "x-beeper-available-since": Xe }),
  mu = n
    .enum([
      "connected",
      "connecting",
      "backfilling",
      "connection_required",
      "reconnect_required",
      "attention_required",
      "disconnected",
      "disabled",
    ])
    .describe("Current connection status for this account."),
  Ht = n
    .object({
      accountID: Oe.describe(
        "Chat account added to Beeper. Use this to route account-scoped actions. Examples include matrix for Beeper/Matrix, discordgo for a cloud bridge, slackgo.TEAM-USER for workspace-scoped cloud bridges, and local-whatsapp_ba_... for local bridges.",
      ),
      loginID: n
        .string()
        .optional()
        .describe(
          "Bridge login ID for this account, when known. One bridge login can contain multiple chat accounts.",
        ),
      bridge: hu.describe(
        `Bridge metadata for the account. Available in ${Xe}.`,
      ),
      network: n
        .string()
        .optional()
        .describe(
          "Human-friendly network name for the account. Omitted when the network is unknown.",
        ),
      user: zt.describe("User the account belongs to."),
      status: mu,
      statusText: n
        .string()
        .optional()
        .describe("Human-friendly account status text."),
      capabilities: n
        .record(n.string(), n.unknown().openapi({ "x-stainless-any": !0 }))
        .optional()
        .describe(
          "Runtime chat/message capabilities for this connected account, when available.",
        ),
    })
    .describe("A chat account added to Beeper.")
    .openapi("Account"),
  gu = n
    .array(Ht)
    .describe(
      "Chat accounts configured on this device. Includes accountID, bridge metadata, optional network name, and user identity.",
    )
    .openapi({
      example: [
        {
          accountID: "matrix",
          loginID: "matrix",
          bridge: { id: "matrix", type: "matrix", provider: "cloud" },
          network: "Beeper",
          user: {
            id: "@batuhan:beeper.com",
            username: "batuhan:beeper.com",
            email: "batuhan@example.com",
            fullName: "Batuhan İçöz",
            isSelf: !0,
          },
          status: "connected",
        },
        {
          accountID: "discordgo",
          loginID: "discordgo",
          bridge: { id: "discordgo", type: "discordgo", provider: "cloud" },
          network: "Discord",
          user: {
            id: "221590782384013314",
            username: "batuhanicoz",
            fullName: "Batuhan İçöz",
            imgURL:
              "file:///Users/batuhan/Library/Application%20Support/BeeperTexts/media/local.beeper.com/batuhan_jmaNwqQPUITme6VV5OSXhH3ZYpmi9UyaYQ43S2UA9qkkzy11Q9JUAiv8TYmOkoQr",
            isSelf: !0,
          },
          status: "connected",
        },
        {
          accountID: "local-whatsapp_ba_EvYDBBsZbRQAy3UOSWqG0LuTVkc",
          loginID: "ba_EvYDBBsZbRQAy3UOSWqG0LuTVkc",
          bridge: { id: "local-whatsapp", type: "whatsapp", provider: "local" },
          network: "WhatsApp",
          user: {
            id: "ba_EvYDBBsZbRQAy3UOSWqG0LuTVkc",
            phoneNumber: "+15550101001",
            fullName: "Batuhan İçöz",
            imgURL:
              "file:///Users/batuhan/Library/Application%20Support/BeeperTexts/media/localhostlocal-whatsapp/_gkBAAAAB1xsnfQKMTcwOTkzODU5MAkBAAAAB1xsnfQ",
            isSelf: !0,
          },
          status: "connected",
        },
      ],
    }),
  fu = n.object({ accountID: Oe }).openapi("GetAccountInput"),
  bu = Ht.openapi("GetAccountOutput"),
  Du = n
    .enum([
      "available",
      "connected",
      "limit_reached",
      "temporarily_unavailable",
      "disabled",
    ])
    .describe(
      "Whether this bridge can currently be used to connect new accounts.",
    );
n.enum(es).describe(
  "Where accounts for this bridge run: on this device or in Beeper Cloud.",
);
const Sa = n
    .object({
      id: n.string().describe("Bridge ID. Use with bridge endpoints."),
      type: n
        .string()
        .describe(
          "Underlying bridge type, such as matrix, discordgo, slackgo, whatsapp, telegram, or twitter.",
        ),
      provider: n
        .enum(es)
        .describe(
          "Where accounts for this bridge run: on this device or in Beeper Cloud.",
        ),
      displayName: n
        .string()
        .describe("Human-friendly bridge name shown in Beeper."),
      network: n
        .string()
        .optional()
        .describe("Network grouping used for account counts and limits."),
      activeAccountCount: n
        .number()
        .int()
        .nonnegative()
        .describe("Number of active accounts for this network on this device."),
      supportsMultipleAccounts: n
        .boolean()
        .describe(
          "Whether this bridge can have multiple active accounts for the same network.",
        ),
      status: Du,
      statusText: n
        .string()
        .optional()
        .describe(
          "Human-friendly status text matching Beeper account management language.",
        ),
      accounts: n
        .array(Ht)
        .describe(
          "Connected accounts for this bridge. Uses the same Account schema as GET /v1/accounts.",
        ),
    })
    .describe("Available bridge that can connect or reconnect chat accounts.")
    .openapi("Bridge"),
  yu = n
    .object({ items: n.array(Sa) })
    .describe("Available bridges and their connected accounts.")
    .openapi("ListBridgesOutput"),
  Le = n
    .string()
    .min(1)
    .regex(
      /^[A-Za-z0-9_-]+$/,
      "Bridge ID may only contain letters, numbers, underscores, and hyphens",
    )
    .describe("Bridge ID.")
    .openapi({
      param: { name: "bridgeID", in: "path", required: !0 },
      example: "local-whatsapp",
    }),
  Ba = n
    .string()
    .min(1)
    .describe("Bridge login ID.")
    .openapi({
      param: { name: "loginID", in: "path", required: !0 },
      example: "ba_EvYDBBsZbRQAy3UOSWqG0LuTVkc",
    }),
  _a = n
    .string()
    .min(1)
    .describe("Temporary bridge login session ID.")
    .openapi({
      param: { name: "loginSessionID", in: "path", required: !0 },
      example: "123",
    }),
  Au = n
    .string()
    .min(1)
    .describe("Current bridge login session step ID.")
    .openapi({ param: { name: "stepID", in: "path", required: !0 } }),
  as = n
    .enum(["current-device", "all-devices"])
    .describe("Where this bridge login should be removed."),
  vu = n
    .object({
      create_dm: n.boolean(),
      lookup_phone: n.boolean(),
      lookup_email: n.boolean(),
      lookup_username: n.boolean(),
      any_phone: n.boolean(),
      contact_list: n.boolean(),
      search: n.boolean(),
    })
    .describe("Identifier lookup capabilities for this bridge.")
    .openapi("ResolveIdentifierCapabilities"),
  Cu = n
    .object({
      types: n.array(
        n.enum(["", "after_read", "after_read_by_recipient", "after_send"]),
      ),
      timers: n.array(n.number().int()).optional(),
      omit_empty_timer: n
        .literal(!0)
        .optional()
        .openapi({ "x-stainless-const": !0 }),
    })
    .describe("Disappearing-message timer capability.")
    .openapi("DisappearingTimerCapability"),
  $e = n
    .object({
      allowed: n.boolean(),
      required: n.boolean().optional(),
      min_length: n.number().int().optional(),
      max_length: n.number().int().optional(),
      settings: Cu.optional(),
    })
    .describe("Group creation field capability.")
    .openapi("GroupFieldCapability"),
  wu = n
    .object({
      type_description: n.string(),
      name: $e.optional(),
      username: $e.optional(),
      avatar: $e.optional(),
      topic: $e.optional(),
      disappear: $e.optional(),
      participants: $e.optional(),
      parent: $e.optional(),
    })
    .describe("Group creation capabilities for one group type.")
    .openapi("GroupTypeCapabilities"),
  Ta = n
    .object({
      resolve_identifier: vu,
      group_creation: n.record(n.string(), wu),
      image_pack_import: n.boolean().optional(),
    })
    .describe(
      "Advanced network capabilities for account lookup and group creation.",
    )
    .openapi("ProvisioningCapabilities"),
  is = n.object({ bridgeID: Le }).openapi("GetBridgeInput"),
  Iu = Sa.openapi("GetBridgeOutput"),
  xu = n.object({ bridgeID: Le }).openapi("GetBridgeCapabilitiesInput"),
  Eu = n
    .object({
      id: n
        .string()
        .describe("Flow ID to pass when creating a bridge login session."),
      name: n
        .string()
        .optional()
        .describe("Display name for the flow, when provided."),
      description: n
        .string()
        .optional()
        .describe(
          "Short explanation for when to use this flow, when provided.",
        ),
    })
    .describe("Connect or reconnect flow option for a bridge.")
    .openapi("LoginFlow"),
  Su = n.object({ bridgeID: Le }).openapi("ListLoginFlowsInput"),
  Bu = n.object({ items: n.array(Eu) }).openapi("ListLoginFlowsOutput"),
  _u = n.enum([
    "connected",
    "connecting",
    "needs_login",
    "logged_out",
    "unknown",
  ]),
  Ir = n
    .object({
      loginID: n.string().describe("Bridge login ID."),
      bridgeID: n.string().describe("Bridge ID."),
      accountIDs: n
        .array(n.string())
        .optional()
        .describe(
          "Chat accounts that belong to this bridge login, when known.",
        ),
      user: zt.optional(),
      status: _u,
      statusText: n
        .string()
        .optional()
        .describe("Human-friendly bridge login status text."),
      removeScopes: n.array(as),
    })
    .describe(
      "Signed-in identity for a bridge. One bridge login can contain multiple chat accounts.",
    )
    .openapi("BridgeLogin"),
  Tu = n.object({ bridgeID: Le }).openapi("ListBridgeLoginsInput"),
  ku = n.object({ items: n.array(Ir) }).openapi("ListBridgeLoginsOutput"),
  ns = n.object({ bridgeID: Le, loginID: Ba }).openapi("GetBridgeLoginInput"),
  ka = n
    .object({ bridgeID: Le, loginID: Ba, scope: as })
    .openapi("RemoveBridgeLoginInput"),
  Fu = n
    .object({
      bridgeID: n.string(),
      loginID: n.string(),
      affectedAccountIDs: n.array(n.string()).optional(),
      status: n.literal("removed").openapi({ "x-stainless-const": !0 }),
      scope: as,
    })
    .openapi("RemoveBridgeLoginOutput"),
  Fa = n
    .object({
      bridgeID: Le,
      flowID: n
        .string()
        .min(1)
        .optional()
        .describe(
          "Optional flow ID returned by the list login flows endpoint. If omitted, Beeper chooses the default flow.",
        ),
      loginID: n
        .string()
        .min(1)
        .optional()
        .describe(
          "Existing bridge login ID to reconnect. Omit to connect a new account.",
        ),
      accountID: n
        .string()
        .min(1)
        .optional()
        .describe(
          "Existing chat account ID to reconnect. Omit to connect a new account.",
        ),
    })
    .openapi("CreateLoginSessionInput"),
  Mu = n
    .object({
      id: n.string().describe("Field ID to send back in the fields object."),
      type: n
        .string()
        .optional()
        .describe("Suggested input type, such as text, password, or email."),
      label: n.string().optional().describe("Field label to show to the user."),
      placeholder: n
        .string()
        .optional()
        .describe("Placeholder text to show when the field is empty."),
      initialValue: n
        .string()
        .optional()
        .describe("Initial field value, when provided by the network."),
      optional: n
        .boolean()
        .optional()
        .describe("True if the user can leave this field empty."),
    })
    .openapi("LoginInputField"),
  Ru = n
    .object({
      id: n.string().describe("Field ID to send back in the fields object."),
      type: n
        .enum(["cookie", "header", "local_storage"])
        .optional()
        .describe("Browser storage source for this value."),
      name: n
        .string()
        .optional()
        .describe("Cookie, header, or local storage key to collect."),
    })
    .openapi("CookieField"),
  Ou = n
    .discriminatedUnion("type", [
      n
        .object({
          type: n.literal("user_input").openapi({ "x-stainless-const": !0 }),
          stepID: n.string(),
          instructions: n
            .string()
            .optional()
            .describe("User-facing instructions for this step."),
          fields: n.array(Mu),
          attachments: n
            .array(n.unknown().openapi({ "x-stainless-any": !0 }))
            .optional(),
        })
        .openapi({
          title: "UserInputLoginStep",
          "x-stainless-variantName": "UserInput",
        }),
      n
        .object({
          type: n.literal("cookies").openapi({ "x-stainless-const": !0 }),
          stepID: n.string(),
          instructions: n
            .string()
            .optional()
            .describe("User-facing instructions for this browser step."),
          url: n.string().describe("URL to open for the user."),
          userAgent: n
            .string()
            .optional()
            .describe("Suggested user agent for the browser session."),
          fields: n.array(Ru),
          expectedFinalURLRegex: n
            .string()
            .optional()
            .describe(
              "Regular expression that identifies the final URL after sign-in.",
            ),
          extractJS: n
            .string()
            .optional()
            .describe(
              "Optional extraction script for browser-based sign-in helpers. Treat as an opaque helper value.",
            ),
        })
        .openapi({
          title: "CookiesLoginStep",
          "x-stainless-variantName": "Cookies",
        }),
      n
        .object({
          type: n
            .literal("display_and_wait")
            .openapi({ "x-stainless-const": !0 }),
          stepID: n.string(),
          instructions: n
            .string()
            .optional()
            .describe("User-facing instructions for this step."),
          display: n.discriminatedUnion("type", [
            n
              .object({
                type: n.literal("qr").openapi({ "x-stainless-const": !0 }),
                data: n.string(),
              })
              .openapi({
                title: "QRCodeLoginDisplay",
                "x-stainless-variantName": "QRCode",
              }),
            n
              .object({
                type: n.literal("emoji").openapi({ "x-stainless-const": !0 }),
                imageURL: n.string(),
              })
              .openapi({
                title: "EmojiLoginDisplay",
                "x-stainless-variantName": "Emoji",
              }),
            n
              .object({
                type: n.literal("code").openapi({ "x-stainless-const": !0 }),
                data: n.string(),
              })
              .openapi({
                title: "CodeLoginDisplay",
                "x-stainless-variantName": "Code",
              }),
            n
              .object({
                type: n.literal("nothing").openapi({ "x-stainless-const": !0 }),
              })
              .openapi({
                title: "EmptyLoginDisplay",
                "x-stainless-variantName": "Empty",
              }),
          ]),
        })
        .openapi({
          title: "DisplayAndWaitLoginStep",
          "x-stainless-variantName": "DisplayAndWait",
        }),
      n
        .object({
          type: n.literal("complete").openapi({ "x-stainless-const": !0 }),
          stepID: n.string().optional(),
          instructions: n
            .string()
            .optional()
            .describe("Completion instructions, when provided."),
          account: Ht.optional(),
          login: Ir.optional(),
        })
        .openapi({
          title: "CompleteLoginStep",
          "x-stainless-variantName": "Complete",
        }),
    ])
    .openapi("LoginStep"),
  Lu = n
    .object({
      code: n.string(),
      message: n.string(),
      details: n
        .record(n.string(), n.unknown().openapi({ "x-stainless-any": !0 }))
        .optional(),
    })
    .openapi("APIError"),
  Nu = n.enum([
    "waiting_for_input",
    "waiting_for_cookies",
    "waiting_for_display",
    "complete",
    "cancelled",
    "failed",
  ]),
  _r = n
    .object({
      loginSessionID: n.string().describe("Temporary bridge login session ID."),
      bridgeID: n.string().describe("Bridge ID."),
      loginID: n
        .string()
        .optional()
        .describe("Bridge login ID for reconnect flows, when known."),
      accountID: n
        .string()
        .optional()
        .describe("Chat account ID for reconnect flows, when known."),
      status: Nu,
      currentStep: Ou.optional().describe(
        "Step the client should show or complete next. Omitted when the session is complete, cancelled, or failed.",
      ),
      account: Ht.optional(),
      login: Ir.optional(),
      error: Lu.optional(),
    })
    .openapi("LoginSession"),
  os = n
    .object({ bridgeID: Le, loginSessionID: _a })
    .openapi("GetLoginSessionInput"),
  us = n
    .object({
      bridgeID: Le,
      loginSessionID: _a,
      stepID: Au,
      type: n.enum(["user_input", "cookies", "display_and_wait"]),
      fields: n
        .record(n.string(), n.string())
        .optional()
        .describe("Field values keyed by the field IDs from the current step."),
      source: n
        .enum(["api", "webview", "browser_extension"])
        .optional()
        .describe(
          "How the step was completed. Omit unless the client needs to distinguish an embedded webview or browser extension.",
        ),
      lastURL: n
        .string()
        .optional()
        .describe(
          "Last browser URL reached during a cookies step, if available.",
        ),
    })
    .openapi("SubmitLoginStepInput"),
  Uu = os,
  Pu = n
    .object({
      bridgeID: n.string(),
      loginSessionID: n.string(),
      status: n.literal("cancelled").openapi({ "x-stainless-const": !0 }),
    })
    .openapi("CancelLoginSessionOutput"),
  Tr = n
    .object({
      chatID: K.optional().describe(
        "Optional Beeper chat ID (or local chat ID) to focus after opening the app. If omitted, only opens/focuses the app.",
      ),
      messageID: n
        .string()
        .optional()
        .describe(
          "Optional message ID. Jumps to that message in the chat when opening.",
        ),
      draftText: n
        .string()
        .optional()
        .describe(
          "Optional plain text to populate in the message input field.",
        ),
      draftAttachmentPath: n
        .string()
        .optional()
        .describe(
          "Optional local image path to populate in the message input field.",
        ),
    })
    .describe(
      "Focus Beeper Desktop and optionally open a specific chat, jump to a message, or pre-fill text and an image.",
    )
    .openapi("FocusAppInput"),
  qu = n
    .object({
      success: n
        .boolean()
        .describe("Whether the app was successfully opened/focused."),
    })
    .describe("Response indicating successful app focus action.")
    .openapi("FocusAppOutput"),
  Mp = n
    .object({
      token: n.string().describe("The token to revoke"),
      token_type_hint: n
        .enum(["access_token"])
        .optional()
        .describe("Hint about the type of token being revoked"),
    })
    .openapi("RevokeTokenInput"),
  Rp = n
    .object({
      sub: n.string().describe("Subject identifier (token ID)"),
      aud: n.string().optional().describe("Audience (client ID)"),
      scope: n.string().describe("Granted scopes"),
      exp: n
        .number()
        .optional()
        .describe("Expiration timestamp (Unix epoch seconds)"),
      iat: n.number().describe("Issued at timestamp (Unix epoch seconds)"),
      client_id: n.string().optional().describe("Client identifier"),
      token_use: n.literal("access").describe("Token type"),
    })
    .openapi("UserInfoOutput"),
  Op = n
    .object({
      token: n.string().describe("The token to introspect"),
      token_type_hint: n
        .string()
        .optional()
        .describe(
          "Token type hint. 'access_token' is supported; other values are ignored.",
        ),
    })
    .openapi("IntrospectTokenInput"),
  ju = n.object({
    active: n.literal(!0),
    scope: n.string().describe("Granted scopes"),
    token_type: n.literal("Bearer").describe("Token type"),
    exp: n
      .number()
      .optional()
      .describe("Expiration timestamp (Unix epoch seconds)"),
    iat: n
      .number()
      .optional()
      .describe("Issued at timestamp (Unix epoch seconds)"),
    nbf: n
      .number()
      .optional()
      .describe("Not-before timestamp (Unix epoch seconds)"),
    sub: n.string().describe("Subject identifier (token ID)"),
    aud: n.string().optional().describe("Audience (client ID)"),
    client_id: n.string().optional().describe("Client identifier"),
    iss: n.string().describe("Token issuer"),
    app: n
      .object({
        version: n.string().describe("App version"),
        name: n.string().describe("App name"),
        bundle_id: n.string().describe("App bundle identifier"),
      })
      .describe("Desktop app metadata"),
    client: n
      .object({
        id: n.string().optional().describe("Client identifier"),
        name: n.string().optional().describe("Client display name"),
        user_agent: n.string().optional().describe("Client user agent"),
        remote_address: n.string().optional().describe("Client remote address"),
      })
      .describe("OAuth client metadata"),
  }),
  Vu = n.object({ active: n.literal(!1) }),
  Lp = n.union([ju, Vu]).openapi("IntrospectTokenOutput"),
  Np = n
    .object({
      app: n.object({
        name: n.string().describe("App name"),
        version: n.string().describe("App version"),
        bundle_id: n.string().describe("App bundle identifier"),
      }),
      platform: n.object({
        os: n.string().describe("Operating system identifier"),
        arch: n.string().describe("CPU architecture"),
        release: n.string().optional().describe("Runtime release version"),
      }),
      server: n.object({
        status: n.string().describe("Server status"),
        base_url: n
          .string()
          .describe("Base URL of the Beeper Client API server"),
        port: n.number().int().describe("Listening port"),
        hostname: n.string().describe("Listening host"),
        remote_access: n.boolean().describe("Whether remote access is enabled"),
        mcp_enabled: n.boolean().describe("Whether MCP endpoint is enabled"),
      }),
      endpoints: n.object({
        oauth: n.object({
          authorization_endpoint: n
            .string()
            .describe("OAuth authorization endpoint"),
          token_endpoint: n.string().describe("OAuth token endpoint"),
          introspection_endpoint: n
            .string()
            .describe("OAuth introspection endpoint"),
          userinfo_endpoint: n.string().describe("OAuth userinfo endpoint"),
          revocation_endpoint: n
            .string()
            .describe("OAuth token revocation endpoint"),
          registration_endpoint: n
            .string()
            .describe("OAuth dynamic client registration endpoint"),
        }),
        spec: n.string().describe("OpenAPI spec endpoint"),
        mcp: n.string().describe("MCP endpoint"),
        ws_events: n.string().describe("WebSocket events endpoint"),
      }),
    })
    .openapi("ConnectInfoOutput"),
  Up = n
    .object({
      message: n.string().describe("Error message"),
      code: n.string().describe("Machine-readable error code"),
      details: n
        .union([
          n
            .object({
              issues: n
                .array(
                  n
                    .object({
                      code: n
                        .string()
                        .describe("Validation issue code")
                        .openapi({ example: "invalid_type" }),
                      message: n
                        .string()
                        .describe(
                          "Human-readable description of the validation issue",
                        ),
                      path: n
                        .array(
                          n.union([
                            n
                              .string()
                              .openapi({ "x-stainless-variantName": "field" }),
                            n
                              .number()
                              .openapi({ "x-stainless-variantName": "index" }),
                          ]),
                        )
                        .describe(
                          "Path pointing to the invalid field within the payload",
                        )
                        .openapi({ example: ["body", "chatID"] }),
                    })
                    .passthrough(),
                )
                .describe("List of validation issues"),
            })
            .describe("Validation error details")
            .openapi({ "x-stainless-variantName": "validation_details" }),
          n
            .record(n.string(), n.unknown().openapi({ "x-stainless-any": !0 }))
            .describe("Additional error context")
            .openapi({ "x-stainless-variantName": "context" }),
          n
            .unknown()
            .openapi({
              "x-stainless-any": !0,
              "x-stainless-variantName": "arbitrary",
            })
            .describe("Arbitrary details payload supplied by the server"),
        ])
        .nullable()
        .optional()
        .describe("Additional error details for debugging"),
    })
    .openapi("Error"),
  Zu = n
    .string()
    .describe(uu)
    .openapi({
      example: "1725489123456|c29tZUltc2dQYWdl",
      "x-stainless-pagination-property": { purpose: "next_cursor_param" },
      param: { name: "cursor", in: "query", required: !1 },
    }),
  Wt = Zu.optional(),
  $u = n
    .enum(["after", "before"])
    .describe(
      "Pagination direction used with 'cursor': 'before' fetches older results, 'after' fetches newer results. Defaults to 'before' when only 'cursor' is provided.",
    )
    .openapi({
      example: "before",
      param: { name: "direction", in: "query", required: !1 },
    }),
  Kt = $u.optional(),
  Ma = { cursor: Wt, direction: Kt },
  ks = (s, e) =>
    `Cursor for fetching ${s} results (use with direction='${e}'). Opaque string; do not inspect.`,
  Yt = (s, e, t, r) =>
    n.object({
      items: s
        .describe(e)
        .openapi({ "x-stainless-pagination-property": { purpose: "items" } }),
      hasMore: n
        .boolean()
        .describe(
          "True if additional results can be fetched using the provided cursors.",
        )
        .openapi({
          "x-stainless-pagination-property": { purpose: "has_next_page" },
        }),
      oldestCursor: n
        .string()
        .nullable()
        .describe(ks("older", "before"))
        .openapi({
          ...(t ? { example: t } : {}),
          "x-stainless-pagination-property": { purpose: "next_cursor_field" },
        }),
      newestCursor: n
        .string()
        .nullable()
        .describe(ks("newer", "after"))
        .openapi(r ? { example: r } : {}),
    });
n.object(Ma);
const Gu = {
    query: n
      .string()
      .min(0)
      .optional()
      .describe(
        'Literal word search. Finds messages containing these words in any order. Use words the user actually typed, not inferred concepts. Example: use "dinner" rather than "dinner plans". If omitted, returns results filtered only by the other parameters.',
      )
      .openapi({ example: "dinner" }),
    ...Ma,
    chatIDs: du,
    accountIDs: ss,
    chatType: n
      .enum(["group", "single"])
      .optional()
      .describe(
        "Filter by chat type: 'group' for group chats, 'single' for 1:1 chats.",
      ),
    mediaTypes: n
      .preprocess(
        (s) => (typeof s == "string" ? [s] : s),
        n.array(n.enum(["any", "video", "image", "link", "file"])).optional(),
      )
      .describe(
        "Filter messages by media types. Use ['any'] for any media type, or specify exact types like ['video', 'image']. Omit for no media filtering.",
      ),
    sender: n
      .string()
      .optional()
      .describe(
        "Filter by sender: 'me' (messages sent by the authenticated user), 'others' (messages sent by others), or a specific user ID string (user.id).",
      ),
    dateAfter: n
      .string()
      .datetime({ offset: !0 })
      .optional()
      .describe(
        "Only include messages with timestamp strictly after this ISO 8601 datetime (e.g., '2024-07-01T00:00:00Z' or '2024-07-01T00:00:00+02:00').",
      )
      .openapi({ example: "2025-08-01T00:00:00Z" }),
    dateBefore: n
      .string()
      .datetime({ offset: !0 })
      .optional()
      .describe(
        "Only include messages with timestamp strictly before this ISO 8601 datetime (e.g., '2024-07-31T23:59:59Z' or '2024-07-31T23:59:59+02:00').",
      )
      .openapi({ example: "2025-08-31T23:59:59Z" }),
    limit: n.coerce
      .number()
      .int()
      .positive()
      .max(nu)
      .optional()
      .default(20)
      .describe("Maximum number of messages to return.")
      .openapi({ example: 20 }),
    excludeLowPriority: n.coerce
      .boolean()
      .default(!0)
      .describe(
        "Exclude messages marked Low Priority by the user. Default: true. Set to false to include all.",
      ),
    includeMuted: n.coerce
      .boolean()
      .default(!0)
      .describe(
        "Include messages in chats marked as Muted by the user, which are usually less important. Default: true. Set to false if the user wants a more refined search.",
      ),
  },
  Fs = n
    .object(Gu)
    .superRefine((s, e) => {
      if (s.dateAfter && s.dateBefore) {
        const t = Date.parse(s.dateAfter),
          r = Date.parse(s.dateBefore);
        !Number.isNaN(t) &&
          !Number.isNaN(r) &&
          t >= r &&
          e.addIssue({
            code: b.custom,
            message:
              "'dateAfter' must be earlier than 'dateBefore' when both are provided.",
            path: ["dateAfter"],
          });
      }
    })
    .openapi("SearchMessagesInput"),
  zu = n
    .enum(["image", "video", "audio", "file", "gif", "voice-note", "sticker"])
    .describe(
      "Attachment type hint. Regular media types are optional hints; gif, voice-note, and sticker enable platform-specific handling.",
    )
    .openapi("MessageAttachmentType"),
  Ra = n
    .object({
      uploadID: n
        .string()
        .describe(
          "Upload ID from uploadAsset endpoint. Required to reference uploaded files.",
        ),
      mimeType: n
        .string()
        .optional()
        .describe("MIME type (optional override of cached value)"),
      fileName: n
        .string()
        .optional()
        .describe("Filename (optional override of cached value)"),
      size: n
        .object({ width: n.number(), height: n.number() })
        .optional()
        .describe("Dimensions (optional override of cached value)"),
      duration: n
        .number()
        .optional()
        .describe("Duration in seconds (optional override of cached value)"),
      type: zu
        .optional()
        .describe(
          "Attachment type hint (image, video, audio, file, gif, voice-note, sticker). If omitted, auto-detected from mimeType",
        ),
    })
    .openapi("MessageAttachmentInput"),
  Oa = (s, e) => {
    !s.attachment &&
      (!s.text || s.text.length === 0) &&
      e.addIssue({
        code: b.custom,
        message: "Either text or attachment is required.",
        path: [],
      });
  },
  La = n
    .string()
    .describe(
      "Message text. Plain text and Markdown are accepted and converted to Beeper rich text for networks that support formatting.",
    )
    .openapi("MessageTextInput"),
  Na = n.object({
    chatID: K.optional(),
    text: La.optional(),
    replyToMessageID: n
      .string()
      .optional()
      .describe(
        "Provide a message ID to send this as a reply to an existing message",
      ),
    attachment: Ra.optional().describe(
      "Single attachment to send with the message",
    ),
  }),
  Hu = Na.superRefine(Oa).openapi("SendMessageInput"),
  Wu = Na.omit({ chatID: !0 }).superRefine(Oa),
  Ua = n
    .object({
      chatID: K.describe(
        "The identifier of the chat to archive or unarchive (accepts both chatID and local chat ID)",
      ),
      archived: n
        .boolean()
        .default(!0)
        .describe("True to archive, false to unarchive"),
    })
    .openapi("ArchiveChatInput"),
  Ku = n
    .object({
      id: n.string().describe("Draft attachment identifier."),
      type: n
        .enum(["file", "gif", "recorded_audio"])
        .describe(
          "Draft attachment type. GIF and recorded audio are mutually exclusive types.",
        ),
      mimeType: n.string().optional().describe("MIME type if known."),
      fileName: n
        .string()
        .optional()
        .describe("Original filename if available."),
      filePath: n
        .string()
        .optional()
        .describe("Local filesystem path for the draft attachment."),
      fileSize: n.number().optional().describe("File size in bytes if known."),
      stickerID: n
        .string()
        .optional()
        .describe("Sticker identifier if the draft attachment is a sticker."),
      audioDurationSeconds: n
        .number()
        .optional()
        .describe("Audio duration in seconds if known."),
      size: n
        .object({ width: n.number().optional(), height: n.number().optional() })
        .optional()
        .describe("Pixel dimensions of the attachment."),
    })
    .openapi("DraftAttachment"),
  Yu = Ra.extend({
    id: n
      .string()
      .optional()
      .describe(
        "Optional draft attachment identifier. If omitted, a new identifier is generated.",
      ),
  }).openapi("DraftAttachmentInput"),
  Ju = n
    .object({
      text: n.string().describe("Rich-text draft body as returned by Beeper."),
      attachments: n
        .record(n.string(), Ku)
        .optional()
        .describe("Draft attachments keyed by attachment ID."),
    })
    .openapi("ChatDraft"),
  Qu = n
    .object({
      text: La.describe(
        "Draft text. Plain text and Markdown are converted to Beeper rich text with the same rules used by send and edit.",
      ),
      attachments: n
        .record(n.string(), Yu)
        .optional()
        .describe(
          "Draft attachments keyed by attachment ID. Each attachment must reference an uploadID returned by the upload file endpoint.",
        ),
    })
    .openapi("ChatDraftInput"),
  Pa = n
    .object({
      chatID: K.describe(
        "The identifier of the chat to update (accepts both chatID and local chat ID)",
      ),
      draft: Qu.nullable()
        .optional()
        .describe(
          "Draft object to set or clear. Non-empty drafts are only accepted when the current draft is empty. Send draft=null to clear text and attachments together before setting a new draft.",
        ),
      title: n
        .string()
        .nullable()
        .optional()
        .describe(
          "Custom chat title. Support depends on the chat account and chat permissions.",
        ),
      description: n
        .string()
        .nullable()
        .optional()
        .describe(
          "Group chat description/topic. Support depends on the chat account and chat permissions.",
        ),
      imgURL: n
        .string()
        .nullable()
        .optional()
        .describe(
          "Local filesystem path to a group chat avatar image. Support depends on the chat account and chat permissions.",
        ),
      isArchived: n
        .boolean()
        .optional()
        .describe("Archive or unarchive the chat."),
      isLowPriority: n
        .boolean()
        .optional()
        .describe(
          "Mark or unmark the chat as low priority when supported by the account.",
        ),
      isPinned: n
        .boolean()
        .optional()
        .describe("Pin or unpin the chat when supported by the account."),
      isMuted: n.boolean().optional().describe("Mute or unmute the chat."),
      messageExpirySeconds: n
        .number()
        .int()
        .nonnegative()
        .nullable()
        .optional()
        .describe(
          "Disappearing-message timer in seconds, or null to clear when supported.",
        ),
    })
    .openapi("PatchChatInput"),
  qa = n
    .object({
      chatID: K.describe(
        "The identifier of the chat to set reminder for (accepts both chatID and local chat ID)",
      ),
      reminder: n
        .object({
          remindAt: Fe.describe("Timestamp when the reminder should trigger."),
          dismissOnIncomingMessage: n
            .boolean()
            .optional()
            .describe("Cancel reminder if someone messages in the chat"),
        })
        .describe("Reminder configuration"),
    })
    .openapi("SetChatReminderInput"),
  Xu = n
    .object({
      chatID: K.describe(
        "The identifier of the chat to clear reminder from (accepts both chatID and local chat ID)",
      ),
    })
    .openapi("ClearChatReminderInput"),
  ja = (s, e) =>
    n.object({
      chatID: K.describe(
        `The identifier of the chat to mark as ${s} (accepts both chatID and local chat ID)`,
      ),
      messageID: De.optional().describe(e),
    }),
  Va = ja("read", "Optional message ID to mark read through.").openapi(
    "MarkChatReadInput",
  ),
  Za = ja("unread", "Optional message ID to mark unread from.").openapi(
    "MarkChatUnreadInput",
  ),
  $a = n
    .object({
      chatID: K.describe(
        "The identifier of the chat to notify anyway (accepts both chatID and local chat ID)",
      ),
    })
    .openapi("NotifyAnywayInput"),
  ec = n
    .object({
      chatID: K.describe(
        "Chat the message was actually sent to. When sending to a merged chat, this is the member chat the send was routed to.",
      ),
      pendingMessageID: De.describe(
        "Pending ID assigned to the message before the network confirms the send. Pass it to GET /v1/chats/{chatID}/messages/{messageID} to resolve, or wait for the matching message.upserted over the WebSocket.",
      ),
    })
    .openapi("SendMessageOutput", {
      example: {
        chatID:
          "!whatsapp_15550101002:ba_EvYDBBsZbRQAy3UOSWqG0LuTVkc.local-whatsapp.localhost",
        pendingMessageID: "m1694783291234567",
      },
    }),
  tc = De.describe(
    "DEPRECATED - use id instead. Compatibility alias for older clients.",
  ).openapi({
    deprecated: !0,
    "x-stainless-deprecation-message": "Use id instead.",
  }),
  rc = n
    .object({
      chatID: K.describe("Chat ID or local chat ID that contains the message."),
      messageID: De.describe(
        "Final message ID, pendingMessageID, or Matrix event ID to resolve.",
      ),
    })
    .openapi("GetMessageInput"),
  Ga = n
    .object({
      chatID: K.optional(),
      messageID: De.describe(
        "Final message ID to edit. Pending message IDs are not accepted because messages cannot be edited while sending.",
      ),
      text: n.string().min(1).describe("New text content for the message"),
    })
    .openapi("EditMessageInput"),
  za = n
    .object({
      chatID: K.optional(),
      messageID: De.describe(
        "Final message ID to delete. Pending message IDs are not accepted because messages cannot be deleted while sending.",
      ),
      forEveryone: n.coerce
        .boolean()
        .optional()
        .default(!0)
        .describe(
          "True to request deletion for everyone when the network supports it; false to delete only for the authenticated user when supported.",
        ),
    })
    .openapi("DeleteMessageInput"),
  Ha = n
    .object({
      chatID: K.optional(),
      messageID: De.describe(
        "Final message ID to add a reaction to. Pending message IDs are not accepted because messages cannot be reacted to while sending.",
      ),
      reactionKey: n
        .string()
        .min(1)
        .describe(
          "Reaction key to add (emoji, shortcode, or custom emoji key)",
        ),
      transactionID: n
        .string()
        .optional()
        .describe(
          "Optional transaction ID for deduplication and send tracking",
        ),
    })
    .openapi("AddReactionInput"),
  sc = n
    .object({
      chatID: K.optional(),
      messageID: De.describe(
        "Final message ID to remove a reaction from. Pending message IDs are not accepted because messages cannot be reacted to while sending.",
      ),
      reactionKey: n
        .string()
        .min(1)
        .describe(
          "Reaction key to remove (emoji, shortcode, or custom emoji key)",
        ),
    })
    .openapi("RemoveReactionInput"),
  ac = n
    .object({
      transcription: n.string().describe("Transcribed text."),
      engine: n.string().describe("Transcription engine."),
      language: n
        .string()
        .optional()
        .describe("Detected or selected language."),
    })
    .describe("Attachment transcription.")
    .openapi("Transcription"),
  ic = n
    .object({
      id: n
        .string()
        .optional()
        .describe(
          "Attachment identifier, typically an mxc:// URL. Use the download file endpoint to get a local file path.",
        ),
      type: n.nativeEnum(nr).describe("Attachment type."),
      srcURL: n
        .string()
        .optional()
        .describe(`Public URL or local file path to fetch the file. ${mt}`),
      mimeType: n
        .string()
        .optional()
        .describe("MIME type if known (e.g., 'image/png')."),
      fileName: n
        .string()
        .optional()
        .describe("Original filename if available."),
      fileSize: n.number().optional().describe("File size in bytes if known."),
      isGif: n
        .boolean()
        .optional()
        .describe("True if the attachment is a GIF."),
      isSticker: n
        .boolean()
        .optional()
        .describe("True if the attachment is a sticker."),
      isVoiceNote: n
        .boolean()
        .optional()
        .describe("True if the attachment is a voice note."),
      duration: n
        .number()
        .optional()
        .describe("Duration in seconds (audio/video)."),
      transcription: ac
        .optional()
        .describe("Attachment transcription if available."),
      posterImg: n
        .string()
        .optional()
        .describe(
          `Preview image URL for video attachments (poster frame). ${mt}`,
        ),
      size: n
        .object({ width: n.number().optional(), height: n.number().optional() })
        .optional()
        .describe("Pixel dimensions of the attachment: width/height in px."),
    })
    .openapi("Attachment"),
  nc = n
    .object({
      id: n
        .string()
        .describe(
          "Reaction ID. When a participant can react more than once, the ID is the participant ID concatenated with the reaction key; otherwise it equals the participant ID.",
        ),
      reactionKey: n
        .string()
        .describe(
          'The reaction key: an emoji (😄), a network-specific key, or a shortcode like "smiling-face".',
        ),
      imgURL: n
        .string()
        .optional()
        .describe(`URL to the reaction's image. ${mt}`),
      participantID: n
        .string()
        .describe("User ID of the participant who reacted."),
      emoji: n
        .boolean()
        .optional()
        .describe("True if the reactionKey is an emoji."),
    })
    .openapi("Reaction"),
  oc = n
    .object({
      reason: n
        .string()
        .optional()
        .describe(
          "Machine-readable failure reason. Present when the send status is a failure.",
        ),
      message: n
        .string()
        .optional()
        .describe("Human-readable send status or failure message."),
      status: n
        .enum(["SUCCESS", "PENDING", "FAIL_RETRIABLE", "FAIL_PERMANENT"])
        .describe("Current status of the message send attempt."),
      timestamp: Fe.describe("Timestamp for the send status event."),
      deliveredToUsers: n
        .array(n.string())
        .optional()
        .describe(
          "User IDs the message was delivered to, when reported by the network.",
        ),
      internalError: n
        .string()
        .optional()
        .describe(
          "Diagnostic error detail from the messaging network adapter. Do not show directly to users.",
        ),
    })
    .describe("Message send status reported by the bridge.")
    .openapi("SendStatus"),
  Wa = n.union([
    n.boolean().openapi({ "x-stainless-variantName": "boolean" }),
    Fe.openapi({ "x-stainless-variantName": "timestamp" }),
  ]),
  uc = n
    .record(n.string(), Wa)
    .describe("Group read receipt state keyed by participant ID.")
    .openapi("MessageSeenByParticipant", {
      "x-stainless-variantName": "by_participant",
    }),
  cc = n
    .union([Wa.openapi({ "x-stainless-variantName": "direct" }), uc])
    .describe(
      "Read receipt state for this message. For 1:1 chats this may be a boolean or timestamp; for group chats this is keyed by participant ID.",
    )
    .openapi("MessageSeen"),
  lc = n
    .object({
      url: n.string().describe("Resolved link URL."),
      originalURL: n
        .string()
        .optional()
        .describe(
          "Original URL when the displayed URL is shortened or redirected.",
        ),
      favicon: n
        .string()
        .optional()
        .describe(`Favicon URL if available. ${mt}`),
      img: n
        .string()
        .optional()
        .describe(`Preview image URL if available. ${mt}`),
      imgSize: n
        .object({ width: n.number().optional(), height: n.number().optional() })
        .optional()
        .describe("Preview image dimensions."),
      title: n.string().describe("Link preview title."),
      summary: n.string().optional().describe("Link preview summary."),
    })
    .describe("Link preview included with a message.")
    .openapi("LinkPreview"),
  Jt = n
    .object({
      id: De,
      chatID: K,
      accountID: Oe.describe("Beeper account ID the message belongs to."),
      senderID: cu,
      senderName: n
        .string()
        .optional()
        .describe("Resolved sender display name."),
      timestamp: Fe.describe("Message timestamp."),
      sortKey: n
        .string()
        .describe("A unique, sortable key used to sort messages.")
        .openapi({ example: "821744079" }),
      type: n
        .enum([
          "TEXT",
          "NOTICE",
          "IMAGE",
          "VIDEO",
          "VOICE",
          "AUDIO",
          "FILE",
          "STICKER",
          "LOCATION",
          "REACTION",
        ])
        .optional()
        .describe(
          "Message content type. Useful for distinguishing reactions, media messages, and state events from regular text messages.",
        ),
      text: n
        .string()
        .optional()
        .describe("Rich-text message body if present."),
      fullTitle: n
        .string()
        .optional()
        .describe(
          "Complete title of a shared post or card. `text` may show it shortened.",
        ),
      editedTimestamp: Fe.optional().describe(
        "Timestamp when the message was edited, if known.",
      ),
      isSender: n
        .boolean()
        .optional()
        .describe("True if the authenticated user sent the message."),
      sendStatus: oc
        .optional()
        .describe(
          "Message send status for this message, when reported by the bridge.",
        ),
      isHidden: n
        .boolean()
        .optional()
        .describe("True if the message is hidden from normal display."),
      isDeleted: n
        .boolean()
        .optional()
        .describe("True if the message has been deleted."),
      attachments: n
        .array(ic)
        .optional()
        .describe("Attachments included with this message, if any."),
      isUnread: n
        .boolean()
        .optional()
        .describe(
          "True if the message is unread for the authenticated user. May be omitted.",
        ),
      linkedMessageID: De.optional().describe(
        "ID of the message this is a reply to, if any.",
      ),
      mentions: n
        .array(n.string())
        .nullable()
        .optional()
        .describe(
          "Mentioned user IDs, @room, or null for legacy messages that require text scanning.",
        ),
      links: n
        .array(lc)
        .optional()
        .describe("Link previews included with this message, if any."),
      reactions: n
        .array(nc)
        .optional()
        .describe("Reactions to the message, if any."),
      seen: cc
        .optional()
        .describe("Read receipt state for this message, when available."),
    })
    .openapi("Message", {
      example: {
        id: "241392",
        sortKey: "455171049984",
        chatID: "!discord_109876543210987654:beeper.com",
        accountID: "discordgo",
        senderID: "@discord_221590782384013314:beeper.com",
        senderName: "Kishan Bagaria",
        timestamp: "2026-05-05T20:20:12.497Z",
        type: "TEXT",
        text: "The OAuth fix is deployed. Can you verify the desktop flow?",
        isSender: !1,
        isDeleted: !1,
        mentions: ["@discord_337451892017545216:beeper.com"],
        isUnread: !1,
      },
    }),
  dc = Jt.extend({
    success: n
      .literal(!0)
      .describe(
        "DEPRECATED - compatibility field. Successful responses are already represented by the 200 status code.",
      )
      .openapi({
        deprecated: !0,
        "x-stainless-const": !0,
        "x-stainless-deprecation-message":
          "Use the HTTP 200 response status instead.",
      }),
    messageID: tc,
  }).openapi("EditMessageOutput", {
    example: {
      id: "1343993",
      messageID: "1343993",
      success: !0,
      sortKey: "aaaa1",
      chatID:
        "!whatsapp_15550101002:ba_EvYDBBsZbRQAy3UOSWqG0LuTVkc.local-whatsapp.localhost",
      accountID: "local-whatsapp_ba_EvYDBBsZbRQAy3UOSWqG0LuTVkc",
      senderID: "@ba_EvYDBBsZbRQAy3UOSWqG0LuTVkc:local-whatsapp.localhost",
      senderName: "Adam Van Ymeren",
      timestamp: "2025-08-28T11:04:29.621Z",
      text: "Updated message text",
      isSender: !0,
      isUnread: !1,
    },
  }),
  pc = n
    .object({
      success: n
        .literal(!0)
        .describe(
          "Always true. Indicates the reaction was queued; failures return an error response.",
        )
        .openapi({ "x-stainless-const": !0 }),
      chatID: K,
      messageID: De,
      reactionKey: n.string().describe("Reaction key that was added."),
      transactionID: n
        .string()
        .describe("Transaction ID used for send tracking."),
    })
    .openapi("AddReactionOutput", {
      example: {
        success: !0,
        chatID:
          "!whatsapp_15550101002:ba_EvYDBBsZbRQAy3UOSWqG0LuTVkc.local-whatsapp.localhost",
        messageID: "1343993",
        reactionKey: "❤️",
        transactionID: "txn_v3a8f4c9d2e1",
      },
    }),
  hc = n
    .object({
      success: n
        .literal(!0)
        .describe(
          "Always true. Indicates the reaction removal was queued; failures return an error response.",
        )
        .openapi({ "x-stainless-const": !0 }),
      chatID: K,
      messageID: De,
      reactionKey: n.string().describe("Reaction key that was removed."),
    })
    .openapi("RemoveReactionOutput", {
      example: {
        success: !0,
        chatID:
          "!whatsapp_15550101002:ba_EvYDBBsZbRQAy3UOSWqG0LuTVkc.local-whatsapp.localhost",
        messageID: "1343993",
        reactionKey: "❤️",
      },
    }),
  se = n
    .nativeEnum(ki)
    .describe(
      "Capability support level. Positive values are supported; zero or negative values are unsupported, dropped, or rejected.",
    )
    .openapi("CapabilitySupportLevel", {
      description: [
        "-2: rejected, -1: dropped, 0: unsupported, 1: partially supported, 2: fully supported.",
      ].join(" "),
    }),
  mc = n
    .object({
      mimeTypes: n
        .record(n.string(), se)
        .describe(
          "Supported MIME types or MIME patterns for this file message type. Missing MIME types should be treated as rejected.",
        ),
      caption: se
        .optional()
        .describe("Support level for captions on this file message type."),
      maxCaptionLength: n
        .number()
        .int()
        .optional()
        .describe("Maximum caption length when captions are supported."),
      maxSize: n
        .number()
        .int()
        .optional()
        .describe("Maximum file size in bytes."),
      maxWidth: n
        .number()
        .int()
        .optional()
        .describe("Maximum image or video width in pixels."),
      maxHeight: n
        .number()
        .int()
        .optional()
        .describe("Maximum image or video height in pixels."),
      maxDuration: n
        .number()
        .int()
        .optional()
        .describe("Maximum audio or video duration in seconds."),
      viewLimitedTypes: n
        .array(
          n.object({
            type: n
              .enum(["time", "count"])
              .describe(
                "Whether the limit is a number of views or a viewing time.",
              ),
            count: n
              .number()
              .int()
              .optional()
              .describe("How many times the media can be viewed."),
            time: n
              .number()
              .int()
              .optional()
              .describe("How long the media can be viewed, in milliseconds."),
          }),
        )
        .optional()
        .describe(
          "View-limited options this file type can be sent with, such as view once or view for 10 seconds.",
        ),
    })
    .describe("Capabilities for one attachment message type.")
    .openapi("AttachmentCapabilities"),
  gc = n
    .object({
      disappearingTimer: n
        .object({
          level: se.describe(
            "Support level for changing the disappearing-message timer.",
          ),
        })
        .optional()
        .describe("Disappearing-message timer state capability."),
      avatar: n
        .object({
          level: se.describe("Support level for changing the chat avatar."),
        })
        .optional()
        .describe("Chat avatar state capability."),
      title: n
        .object({
          level: se.describe("Support level for changing the chat title."),
        })
        .optional()
        .describe("Chat title state capability."),
      description: n
        .object({
          level: se.describe(
            "Support level for changing the chat description/topic.",
          ),
        })
        .optional()
        .describe("Chat description/topic state capability."),
    })
    .describe("Chat state update capabilities with stable public field names.")
    .openapi("ChatStateCapabilities"),
  Ka = n
    .object({
      formatting: n
        .record(n.string(), se)
        .optional()
        .describe(
          "Supported rich-text formatting features keyed by feature name (for example bold, inline_code, code_block.syntax_highlighting). Omitted means no formatting support is advertised.",
        ),
      attachments: n
        .record(n.string(), mc)
        .optional()
        .describe(
          "Supported attachment message types and their per-type constraints, keyed by Matrix msgtype or pseudo-msgtype (for example m.image, m.video, org.matrix.msc3245.voice). Missing message types should be treated as rejected.",
        ),
      maxTextLength: n
        .number()
        .int()
        .optional()
        .describe("Maximum length of normal text messages."),
      locationMessage: se
        .optional()
        .describe("Support level for location messages."),
      poll: se.optional().describe("Support level for polls."),
      thread: se.optional().describe("Support level for threaded replies."),
      reply: se
        .optional()
        .describe("Support level for replies to specific messages."),
      edit: se.optional().describe("Support level for message edits."),
      editMaxCount: n
        .number()
        .int()
        .optional()
        .describe("Maximum number of edits allowed for one message."),
      editMaxAge: n
        .number()
        .int()
        .optional()
        .describe("Maximum message age for edits, in seconds."),
      delete: se
        .optional()
        .describe("Support level for deleting messages for everyone."),
      deleteMaxAge: n
        .number()
        .int()
        .optional()
        .describe("Maximum message age for delete-for-everyone, in seconds."),
      deleteForMe: n
        .boolean()
        .optional()
        .describe(
          "True if deleting messages only for the authenticated user is supported.",
        ),
      messageRequest: n
        .object({
          acceptWithMessage: se
            .optional()
            .describe(
              "Support level for accepting message requests by sending a message.",
            ),
          acceptWithButton: se
            .optional()
            .describe(
              "Support level for accepting message requests with an explicit action.",
            ),
        })
        .optional()
        .describe("Message request capabilities."),
      reaction: se.optional().describe("Support level for reactions."),
      reactionCount: n
        .number()
        .int()
        .optional()
        .describe("Maximum number of reactions allowed on a single message."),
      allowedReactions: n
        .array(n.string())
        .optional()
        .describe(
          "Allowed Unicode reactions. Omitted means all emoji reactions are allowed.",
        ),
      customEmojiReactions: n
        .boolean()
        .optional()
        .describe("True if custom emoji reactions are supported."),
      disappearingTimer: n
        .object({
          types: n
            .array(n.enum(["afterRead", "afterReadByRecipient", "afterSend"]))
            .optional()
            .describe("Supported disappearing timer types."),
          timers: n
            .array(n.number().int())
            .optional()
            .describe(
              "Allowed disappearing timer values in milliseconds. Omitted means any timer is allowed.",
            ),
          omitEmptyTimer: n
            .boolean()
            .optional()
            .describe(
              "True if empty timer objects should be omitted from message content.",
            ),
        })
        .optional()
        .describe("Disappearing-message timer capabilities."),
      readReceipts: n
        .boolean()
        .optional()
        .describe("True if read receipts are supported."),
      typingNotifications: n
        .boolean()
        .optional()
        .describe("True if typing notifications are supported."),
      archive: n
        .boolean()
        .optional()
        .describe("True if archive/unarchive is supported."),
      markAsUnread: n
        .boolean()
        .optional()
        .describe("True if marking chats unread is supported."),
      deleteChat: n
        .boolean()
        .optional()
        .describe(
          "True if deleting chats for the authenticated user is supported.",
        ),
      deleteChatForEveryone: n
        .boolean()
        .optional()
        .describe("True if deleting chats for everyone is supported."),
      participantActions: n
        .object({
          ban: se
            .optional()
            .describe("Support level for banning participants."),
          invite: se
            .optional()
            .describe("Support level for inviting participants."),
          kick: se
            .optional()
            .describe("Support level for kicking participants."),
          leave: se.optional().describe("Support level for leaving the chat."),
          revokeInvite: se
            .optional()
            .describe("Support level for revoking invites."),
        })
        .optional()
        .describe("Participant management capabilities."),
      state: gc.optional().describe("Chat state update capabilities."),
    })
    .describe("Chat capabilities reported by the platform.")
    .openapi("ChatCapabilities"),
  fc = n
    .enum(["single", "group"])
    .describe(
      "Chat type: 'single' for direct messages, 'group' for group chats.",
    ),
  bc = n
    .object({
      items: n
        .array(pu)
        .describe(
          "Participants returned for this chat (limited by the request; may be a subset).",
        ),
      hasMore: n
        .boolean()
        .describe(
          "True if there are more participants than included in items.",
        ),
      total: n
        .number()
        .int()
        .describe("Total number of participants in the chat."),
    })
    .describe("Chat participants information."),
  Ya = n
    .object({
      id: n.string().describe("Unique identifier of the label."),
      name: n.string().describe("Display name of the label."),
    })
    .describe("A user-created label that organizes chats across accounts.")
    .openapi("Label"),
  Dc = n.array(Ya).describe("Labels the user has created, sorted by name."),
  ve = n
    .object({
      id: K.describe("Unique identifier of the chat across Beeper."),
      localChatID: n
        .string()
        .nullable()
        .optional()
        .describe("Local chat ID specific to this installation."),
      accountID: Oe.describe("Account ID this chat belongs to."),
      network: n
        .string()
        .describe("Display-only human-readable account/network name."),
      title: n
        .string()
        .describe(
          "Display title of the chat as computed by the client/server.",
        ),
      description: n
        .string()
        .nullable()
        .optional()
        .describe("Group chat description/topic when available."),
      imgURL: n
        .string()
        .nullable()
        .optional()
        .describe(
          "Local filesystem path to the chat avatar image when available.",
        ),
      type: fc,
      isReadOnly: n
        .boolean()
        .optional()
        .describe("True if messages cannot be sent in this chat."),
      participants: bc,
      lastActivity: Fe.optional().describe("Timestamp of last activity."),
      unreadCount: lu,
      unreadMentionsCount: n
        .number()
        .int()
        .optional()
        .describe(
          "Number of unread messages that mention the authenticated user or @room.",
        ),
      lastReadMessageSortKey: n
        .string()
        .optional()
        .describe("Last read message sortKey."),
      draft: Ju.nullable()
        .optional()
        .describe(
          "Current draft object for this chat, or null when no draft is set.",
        ),
      reminder: n
        .object({
          remindAt: Fe.optional().describe(
            "Timestamp when the reminder should trigger.",
          ),
          dismissOnIncomingMessage: n
            .boolean()
            .optional()
            .describe("Cancel reminder if someone messages in the chat."),
        })
        .nullable()
        .optional()
        .describe(
          "Current reminder for this chat, or null when no reminder is set.",
        ),
      snooze: n
        .object({
          snoozeUntil: Fe.optional().describe(
            "Timestamp when the snooze expires.",
          ),
          userSnoozedAt: Fe.optional().describe(
            "Timestamp when the user set the snooze.",
          ),
        })
        .nullable()
        .optional()
        .describe(
          "Current snooze state for this chat, or null when no snooze is set.",
        ),
      isArchived: n.boolean().optional().describe("True if chat is archived."),
      isMarkedUnread: n
        .boolean()
        .optional()
        .describe(
          "True if the chat was explicitly marked unread by the authenticated user.",
        ),
      isMuted: n
        .boolean()
        .optional()
        .describe("True if chat notifications are muted."),
      isPinned: n.boolean().optional().describe("True if chat is pinned."),
      isLowPriority: n
        .boolean()
        .optional()
        .describe("True if chat is marked low priority."),
      labels: n
        .array(Ya)
        .optional()
        .describe(
          "Labels applied to this chat. Absent when the chat has none, or when labels are not enabled for this user.",
        ),
      messageExpirySeconds: n
        .number()
        .int()
        .nullable()
        .optional()
        .describe("Disappearing-message timer in seconds when available."),
      capabilities: Ka.optional().describe(
        "Chat capabilities reported by the platform.",
      ),
      merge: n
        .object({
          chatIDs: n
            .array(K)
            .describe(
              "Chat IDs of the member chats grouped by this merged chat.",
            ),
          defaultChatID: K.optional().describe(
            "Member chat that receives messages sent to the merged chat, when the user has picked one. This preference is per-device; when absent, sends route to the most recently active member.",
          ),
        })
        .optional()
        .describe(
          "Present when this chat is a merged chat: one person whose conversations across networks (or across accounts on the same network) are grouped into a single chat. A merged chat holds no messages of its own - read messages from the member chats, and send either to a member directly or to the merged chat ID to route automatically.",
        ),
      mergedIntoChatID: K.optional().describe(
        "When this chat is a member of a merged chat, the ID of that merged chat. Clients that render merged chats as one conversation should list the merged chat and hide chats carrying this field.",
      ),
    })
    .openapi("Chat", {
      example: {
        id: "!whatsapp_15550101002:ba_EvYDBBsZbRQAy3UOSWqG0LuTVkc.local-whatsapp.localhost",
        localChatID: "5639",
        accountID: "local-whatsapp_ba_EvYDBBsZbRQAy3UOSWqG0LuTVkc",
        network: "WhatsApp",
        title: "Kishan Bagaria",
        type: "single",
        participants: {
          items: [
            {
              id: "@15550101002:local-whatsapp.localhost",
              phoneNumber: "+15550101002",
              fullName: "Kishan Bagaria",
              cannotMessage: !1,
              isSelf: !1,
            },
            {
              id: "@ba_EvYDBBsZbRQAy3UOSWqG0LuTVkc:local-whatsapp.localhost",
              fullName: "Batuhan İçöz",
              cannotMessage: !1,
              isSelf: !0,
            },
          ],
          hasMore: !1,
          total: 2,
        },
        lastActivity: "2026-05-05T20:11:54.000Z",
        unreadCount: 0,
        lastReadMessageSortKey: "455171049984",
        draft: null,
        isArchived: !1,
        isMuted: !1,
        isPinned: !1,
      },
    }),
  yc = ve
    .extend({
      preview: Jt.optional().describe(
        "Last message preview for this chat, if available.",
      ),
    })
    .describe("Chat with optional last message preview.")
    .openapi("ChatWithPreview"),
  Ja = n
    .object({
      chatID: K.describe(
        "Unique identifier of the chat to retrieve. Not available for iMessage chats.",
      ),
      maxParticipantCount: n.coerce
        .number()
        .int()
        .min(-1)
        .max(500)
        .optional()
        .default(100)
        .describe(
          "Maximum number of participants to return. Use -1 for all; otherwise 0-500. Defaults to 100. List and search endpoints return up to 20 participants per chat.",
        )
        .openapi({ example: 100 }),
    })
    .openapi("GetChatInput"),
  Qa = Yt(
    n.array(Jt),
    "Messages matching the query and filters.",
    "1725489123456|c29tZUltc2dQYWdl",
    "1725489123456|c29tZUltc2dQYWdl",
  )
    .extend({
      chats: n
        .record(n.string(), ve)
        .describe(
          "Map of chatID -> chat details for chats referenced in items.",
        ),
    })
    .openapi("SearchMessagesOutput", {
      example: {
        items: [
          {
            id: "241392",
            chatID: "!discord_109876543210987654:beeper.com",
            accountID: "discordgo",
            senderID: "@discord_221590782384013314:beeper.com",
            senderName: "Kishan Bagaria",
            timestamp: "2025-08-28T11:04:29.621Z",
            sortKey: "455171049984",
            text: "The OAuth fix is deployed. Can you verify the desktop flow?",
            isSender: !1,
            isUnread: !1,
          },
          {
            id: "241393",
            chatID:
              "!whatsapp_15550101002:ba_EvYDBBsZbRQAy3UOSWqG0LuTVkc.local-whatsapp.localhost",
            accountID: "local-whatsapp_ba_EvYDBBsZbRQAy3UOSWqG0LuTVkc",
            senderID: "@15550101002:local-whatsapp.localhost",
            senderName: "Adam Van Ymeren",
            timestamp: "2025-08-28T14:22:15.432Z",
            sortKey: "455171050240",
            text: "Dinner at 7 still works for me.",
            isSender: !1,
            isUnread: !0,
          },
        ],
        chats: {
          "!discord_109876543210987654:beeper.com": {
            id: "!discord_109876543210987654:beeper.com",
            localChatID: "1229720",
            accountID: "discordgo",
            network: "Discord",
            title: "Beeper Client API",
            type: "group",
            participants: {
              items: [
                {
                  id: "@discord_221590782384013314:beeper.com",
                  username: "kishan",
                  fullName: "Kishan Bagaria",
                  cannotMessage: !1,
                  isSelf: !1,
                },
                {
                  id: "@discord_337451892017545216:beeper.com",
                  username: "batuhanicoz",
                  fullName: "Batuhan İçöz",
                  cannotMessage: !1,
                  isSelf: !0,
                },
              ],
              hasMore: !0,
              total: 6,
            },
            lastActivity: "2025-08-31T17:38:20.393Z",
            unreadCount: 0,
            isArchived: !1,
            isMuted: !1,
            isPinned: !0,
          },
          "!whatsapp_15550101002:ba_EvYDBBsZbRQAy3UOSWqG0LuTVkc.local-whatsapp.localhost":
            {
              id: "!whatsapp_15550101002:ba_EvYDBBsZbRQAy3UOSWqG0LuTVkc.local-whatsapp.localhost",
              localChatID: "1229721",
              accountID: "local-whatsapp_ba_EvYDBBsZbRQAy3UOSWqG0LuTVkc",
              network: "WhatsApp",
              title: "Adam Van Ymeren",
              type: "single",
              participants: {
                items: [
                  {
                    id: "@15550101002:local-whatsapp.localhost",
                    phoneNumber: "+15550101002",
                    fullName: "Adam Van Ymeren",
                    cannotMessage: !1,
                    isSelf: !1,
                  },
                  {
                    id: "@ba_EvYDBBsZbRQAy3UOSWqG0LuTVkc:local-whatsapp.localhost",
                    fullName: "Batuhan İçöz",
                    cannotMessage: !1,
                    isSelf: !0,
                  },
                ],
                hasMore: !1,
                total: 2,
              },
              lastActivity: "2025-08-31T16:45:10.123Z",
              unreadCount: 2,
              isArchived: !1,
              isMuted: !0,
              isPinned: !1,
            },
        },
        hasMore: !0,
        oldestCursor: "1756379069621",
        newestCursor: null,
      },
    }),
  Ac = {
    cursor: Wt,
    direction: Kt,
    inbox: n
      .enum(["primary", "low-priority", "archive"])
      .optional()
      .describe(
        'Filter by inbox type: "primary" (the chats the Beeper inbox shows: non-archived, non-low-priority, honoring inbox visibility rules and labels), "low-priority", or "archive". If not specified, shows all chats.',
      ),
    labelID: n
      .string()
      .optional()
      .describe(
        "Only include chats that carry this label. Label IDs come from GET /v1/labels.",
      ),
    unreadOnly: n.coerce
      .boolean()
      .optional()
      .describe("Set to true to only retrieve chats that have unread messages"),
    limit: n.coerce
      .number()
      .int()
      .min(1)
      .max(yr)
      .optional()
      .default(50)
      .describe(
        `Set the maximum number of chats to retrieve. Valid range: 1-${yr}, default is 50`,
      ),
    type: n
      .enum(["single", "group", "any"])
      .default("any")
      .optional()
      .describe(
        'Specify the type of chats to retrieve: use "single" for direct messages, "group" for group chats, or "any" to get all types',
      ),
    query: n
      .string()
      .trim()
      .min(1)
      .optional()
      .describe(
        'Literal chat search. Use words the user typed, such as "dinner". When multiple words are provided, all must match. Case-insensitive.',
      ),
    scope: n
      .enum(["titles", "participants"])
      .optional()
      .default("titles")
      .describe(
        "Search scope: 'titles' matches title + network; 'participants' matches participant names.",
      ),
    lastActivityBefore: n
      .string()
      .datetime()
      .optional()
      .describe(
        "Only include chats with last activity before this ISO 8601 datetime.",
      ),
    lastActivityAfter: n
      .string()
      .datetime()
      .optional()
      .describe(
        "Only include chats with last activity after this ISO 8601 datetime.",
      ),
    accountIDs: ss
      .describe("Limit results to specific chat accounts.")
      .openapi({
        example: [
          "matrix",
          "discordgo",
          "local-whatsapp_ba_EvYDBBsZbRQAy3UOSWqG0LuTVkc",
        ],
      }),
    includeMuted: n.coerce
      .boolean()
      .default(!0)
      .optional()
      .describe(
        "Include chats marked as Muted by the user, which are usually less important. Default: true. Set to false if the user wants a more refined search.",
      ),
  },
  Ms = n.object(Ac).openapi("SearchChatsInput"),
  vc = Yt(n.array(ve), "Chats matching the filters.").openapi(
    "SearchChatsOutput",
    {
      example: {
        items: [
          {
            id: "!KPFTtZYWuERwib8T702N9IfqiCc:ba_EvYDBBsZbRQAy3UOSWqG0LuTVkc.local-whatsapp.localhost",
            localChatID: "1229391",
            accountID: "local-whatsapp_ba_EvYDBBsZbRQAy3UOSWqG0LuTVkc",
            network: "WhatsApp",
            title: "Family Travel Planning",
            type: "group",
            participants: {
              items: [
                {
                  id: "@15550101002:local-whatsapp.localhost",
                  phoneNumber: "+15550101002",
                  fullName: "Kishan Bagaria",
                  cannotMessage: !1,
                  isSelf: !1,
                },
                {
                  id: "@15550101003:local-whatsapp.localhost",
                  phoneNumber: "+15550101003",
                  fullName: "Gerardo Rodrigez",
                  cannotMessage: !1,
                  isSelf: !1,
                },
              ],
              hasMore: !0,
              total: 5,
            },
            lastActivity: "2025-08-31T19:41:41.000Z",
            unreadCount: 3,
            lastReadMessageSortKey: "449706228480",
            isArchived: !1,
            isMuted: !1,
            isPinned: !0,
          },
          {
            id: "!discord_109876543210987654:beeper.com",
            localChatID: "1229078",
            accountID: "discordgo",
            network: "Discord",
            title: "Beeper Client API",
            type: "group",
            participants: {
              items: [
                {
                  id: "@discord_221590782384013314:beeper.com",
                  username: "kishan",
                  fullName: "Kishan Bagaria",
                  cannotMessage: !1,
                  isSelf: !1,
                },
                {
                  id: "@discord_854231905641922560:beeper.com",
                  username: "mattwondra",
                  fullName: "Matt Wondra",
                  cannotMessage: !1,
                  isSelf: !1,
                },
              ],
              hasMore: !0,
              total: 6,
            },
            lastActivity: "2025-08-31T18:05:20.648Z",
            unreadCount: 0,
            lastReadMessageSortKey: "449706782720",
            isArchived: !0,
            isMuted: !1,
            isPinned: !1,
          },
          {
            id: "!twitter_dm_photomatt:local-twitter.localhost",
            localChatID: "1228956",
            accountID: "local-twitter_ba_gUU1IHNGo_CsTZLp0vDFUYk9EuE",
            network: "Twitter/X",
            title: "Matt Mullenweg",
            type: "single",
            participants: {
              items: [
                {
                  id: "@photomatt:local-twitter.localhost",
                  username: "photomatt",
                  fullName: "Matt Mullenweg",
                  cannotMessage: !1,
                  isSelf: !1,
                },
              ],
              hasMore: !1,
              total: 2,
            },
            lastActivity: "2025-08-31T12:30:15.123Z",
            unreadCount: 1,
            lastReadMessageSortKey: "449705982340",
            isArchived: !1,
            isMuted: !0,
            isPinned: !1,
          },
        ],
        hasMore: !0,
        oldestCursor:
          "eyJ0cyI6MTc1NjY2NzEyMDY0OCwiaWQiOiIhS1BGVHRaWVd1RVJ3aWI4VDcwMjlOSWZxaUNjOmJhX0V2WURCQnNamlFSd0F5M1VPU1dxRzBMdVRWa2MiLCJzY29yZSI6MTJ9",
        newestCursor:
          "eyJ0cyI6MTc1NjY2OTMwMTAwMCwiaWQiOiIhblplWDdkZDY3X1JhUG5tV0dKSWpVa1Yyc3ZFOmJhX3NYZjBhZG5icjI4Ny5sb2NhbC10ZWxlZ3JhbS5sb2NhbGhvc3QiLCJzY29yZSI6MTAuNX0=",
      },
    },
  ),
  Rs = n
    .object({
      url: n
        .string()
        .min(1)
        .refine(
          (s) => /^(mxc|localmxc):\/\//.test(s),
          "URL must start with mxc:// or localmxc://",
        )
        .describe(
          "Beeper media URL (mxc:// or localmxc://) for the file to download.",
        ),
    })
    .openapi("DownloadAssetInput", {
      example: { url: "mxc://example.org/Q4x9CqGz1pB3Oa6XgJ" },
    }),
  Os = n
    .object({
      url: n
        .string()
        .min(1)
        .refine(
          (s) => /^(mxc|localmxc|file):\/\//.test(s),
          "URL must start with mxc://, localmxc://, or file://",
        )
        .describe(
          "File URL to serve. Accepts mxc://, localmxc://, or file:// URLs.",
        ),
    })
    .openapi("ServeAssetInput", {
      example: { url: "mxc://example.org/Q4x9CqGz1pB3Oa6XgJ" },
    }),
  Cc = n
    .object({
      srcURL: n
        .string()
        .optional()
        .describe("Local file URL to the downloaded file."),
      error: n
        .string()
        .optional()
        .describe("Error message if the download failed."),
    })
    .openapi("DownloadAssetOutput"),
  Ls = n
    .object({
      content: n
        .string()
        .min(1, "content must not be empty")
        .max(
          75e7,
          "Base64 content too large. Maximum size is ~500MB (750M base64 characters)",
        )
        .describe("Base64-encoded file content (max ~500MB decoded)"),
      fileName: n
        .string()
        .optional()
        .describe("Original filename. Generated if omitted"),
      mimeType: n
        .string()
        .optional()
        .describe("MIME type. Auto-detected from magic bytes if omitted"),
    })
    .describe(
      "Upload a temporary file. Upload IDs can be referenced by send-message and draft attachment requests while the temporary upload remains available.",
    )
    .openapi("UploadAssetInput");
n.object({
  content: n
    .string()
    .min(1, "content must not be empty")
    .max(
      75e7,
      "Base64 content too large. Maximum size is ~500MB (750M base64 characters)",
    )
    .describe("Base64-encoded file content (max ~500MB decoded)"),
  fileName: n
    .string()
    .min(1)
    .describe(
      "Original filename. Required for the JSON form of /v1/assets/upload.",
    ),
  mimeType: n
    .string()
    .min(1)
    .describe("MIME type. Required for the JSON form of /v1/assets/upload."),
}).openapi("UploadAssetCompatJSONInput");
const wc = n
    .object({
      file: n
        .string()
        .openapi({
          type: "string",
          format: "binary",
          description: "The file to upload (max 500 MB).",
        }),
      fileName: n
        .string()
        .optional()
        .describe(
          "Original filename. Defaults to the uploaded file name if omitted",
        ),
      mimeType: n
        .string()
        .optional()
        .describe("MIME type. Auto-detected from magic bytes if omitted"),
    })
    .describe(
      "Upload a temporary file. Upload IDs can be referenced by send-message and draft attachment requests while the temporary upload remains available.",
    )
    .openapi("UploadAssetMultipart"),
  Ns = n
    .object({
      uploadID: n
        .string()
        .optional()
        .describe("Unique upload ID for this temporary file"),
      srcURL: n
        .string()
        .optional()
        .describe("Local file URL (file://) for the uploaded file"),
      fileName: n.string().optional().describe("Resolved filename"),
      mimeType: n
        .string()
        .optional()
        .describe("Detected or provided MIME type"),
      fileSize: n.number().optional().describe("File size in bytes"),
      width: n.number().optional().describe("Width in pixels (images/videos)"),
      height: n
        .number()
        .optional()
        .describe("Height in pixels (images/videos)"),
      duration: n
        .number()
        .optional()
        .describe("Duration in seconds (audio/videos)"),
      error: n.string().optional().describe("Error message if upload failed"),
    })
    .openapi("UploadAssetOutput");
n.enum(["chats", "in_groups", "messages"])
  .describe(
    "Sections to return. 'chats' searches titles/network; 'in_groups' searches participants; 'messages' returns first page of message results.",
  )
  .openapi("UnifiedSearchCategory");
const Us = n
    .object({
      query: n
        .string()
        .min(1)
        .describe("User-typed search text. Uses literal word matching."),
    })
    .openapi("UnifiedSearchInput"),
  Ic = n
    .object({
      results: n.object({
        chats: n.array(ve).describe("Top chat results."),
        in_groups: n
          .array(ve)
          .describe("Top group results by participant matches."),
        messages: Qa,
      }),
    })
    .openapi("UnifiedSearchOutput"),
  Xa = n
    .object({
      accountID: Oe,
      query: n
        .string()
        .min(1)
        .describe(
          "Text to search contacts by. A phone number, email address, or username written with a leading @ is additionally looked up as an exact identifier on the network; any other text, such as a bare handle or a person or business name, searches existing contacts only. Matching behavior depends on the network.",
        ),
    })
    .openapi("SearchContactsInput"),
  xc = n.object({ items: n.array(zt) }).openapi("SearchContactsOutput"),
  Ec = {
    accountID: Oe.describe("Account to list contacts from."),
    cursor: Wt,
    direction: Kt,
    limit: n.coerce
      .number()
      .int()
      .min(1)
      .max(ou)
      .optional()
      .default(iu)
      .describe("Maximum contacts to return per page."),
    query: n
      .string()
      .min(1)
      .optional()
      .describe("Optional search query for contact lookup."),
  },
  ei = n.object(Ec).openapi("ListContactsInput"),
  Sc = Yt(n.array(zt), "Merged contacts for the selected account.").openapi(
    "ListContactsOutput",
  ),
  ti = n
    .object({
      id: n.string().optional().describe("Known user ID when available."),
      username: n.string().optional().describe("Username/handle candidate."),
      phoneNumber: n
        .string()
        .optional()
        .describe("Phone number candidate (E.164 preferred)."),
      email: n.string().optional().describe("Email candidate."),
      fullName: n
        .string()
        .optional()
        .describe("Display name hint used for ranking only."),
    })
    .superRefine((s, e) => {
      !s.id &&
        !s.username &&
        !s.phoneNumber &&
        !s.email &&
        e.addIssue({
          code: b.custom,
          message:
            "At least one of id, username, phoneNumber, or email is required.",
          path: ["id"],
        });
    }),
  cs = {
    accountID: Oe.describe("Account to create or start the chat on."),
    messageText: n
      .string()
      .optional()
      .describe(
        "Optional first message content if the platform requires it to create the chat.",
      ),
  };
n.object({
  ...cs,
  user: ti.describe(
    "Contact-like user payload used to resolve the best identifier.",
  ),
  allowInvite: n
    .boolean()
    .optional()
    .default(!0)
    .describe(
      "Whether invite-based DM creation is allowed when required by the platform. Used for mode='start'.",
    ),
}).openapi("CreateChatStartInput");
const Hr = n
    .object({
      ...cs,
      user: ti.describe(
        "Contact-like user payload used to resolve the best identifier.",
      ),
      allowInvite: n
        .boolean()
        .optional()
        .default(!0)
        .describe(
          "Whether invite-based DM creation is allowed when required by the platform.",
        ),
    })
    .describe(
      `Start a direct chat from a user/contact payload. Available in ${Ts}.`,
    )
    .openapi("StartChatInput", { "x-beeper-available-since": Ts }),
  Bc = (s, e) => {
    s.type === "single" &&
      s.participantIDs.length !== 1 &&
      e.addIssue({
        code: b.custom,
        message: "'single' chat must have exactly one participantID.",
        path: ["participantIDs"],
      });
  },
  Ps = n
    .object({
      ...cs,
      type: n
        .enum(["single", "group"])
        .describe(
          "'single' requires exactly one participantID; 'group' supports multiple participants and optional title.",
        ),
      participantIDs: n
        .array(n.string())
        .min(1)
        .describe("User IDs to include in the new chat."),
      title: n
        .string()
        .optional()
        .describe(
          "Optional title for group chats; ignored for single chats on most networks.",
        ),
    })
    .superRefine(Bc)
    .openapi("CreateChatInput"),
  qs = ve
    .extend({
      chatID: K.describe(
        "DEPRECATED - use id instead. Compatibility alias for older clients.",
      ).openapi({
        deprecated: !0,
        "x-stainless-deprecation-message": "Use id instead.",
      }),
      status: n
        .enum(["existing", "created"])
        .optional()
        .describe(
          "DEPRECATED - legacy start-chat status for older clients. New clients should inspect the returned Chat instead.",
        )
        .openapi({
          deprecated: !0,
          "x-stainless-deprecation-message":
            "Inspect the returned Chat instead.",
        }),
    })
    .openapi("CreateChatOutput", {
      example: {
        id: "!team_launch_planning:beeper.com",
        chatID: "!team_launch_planning:beeper.com",
        status: "created",
        localChatID: "5541",
        accountID: "matrix",
        network: "Beeper",
        title: "Launch Planning",
        type: "group",
        participants: {
          items: [
            {
              id: "@kishanbagaria:beeper.com",
              username: "kishanbagaria:beeper.com",
              fullName: "Kishan Bagaria",
              cannotMessage: !1,
              isSelf: !1,
            },
            {
              id: "@batuhan:beeper.com",
              username: "batuhan:beeper.com",
              fullName: "Batuhan İçöz",
              cannotMessage: !1,
              isSelf: !0,
            },
            {
              id: "@mattwondra:beeper.com",
              username: "mattwondra:beeper.com",
              fullName: "Matt Wondra",
              cannotMessage: !1,
              isSelf: !1,
            },
            {
              id: "@adamvy:beeper.com",
              username: "adamvy:beeper.com",
              fullName: "Adam Van Ymeren",
              cannotMessage: !1,
              isSelf: !1,
            },
          ],
          hasMore: !1,
          total: 4,
        },
        lastActivity: "2026-05-05T20:12:30.969Z",
        unreadCount: 0,
        lastReadMessageSortKey: "862756563",
        draft: null,
        isArchived: !1,
        isMuted: !1,
        isPinned: !1,
      },
    }),
  _c = {
    cursor: Wt,
    direction: Kt,
    limit: n.coerce
      .number()
      .int()
      .min(1)
      .max(yr)
      .optional()
      .default(25)
      .describe(
        `Set the maximum number of chats to retrieve. Valid range: 1-${yr}, default is 25`,
      ),
    accountIDs: ss.describe(
      "Limit to specific account IDs. If omitted, fetches from all accounts.",
    ),
  },
  js = n.object(_c).openapi("ListChatsInput"),
  Tc = Yt(
    n.array(yc),
    "Chats ordered by last activity timestamp (most recent first).",
    "1725489123456",
    "1725489123456",
  ).openapi("ListChatsOutput"),
  kc = {
    chatID: K.describe("Chat ID to list messages from"),
    cursor: Wt,
    direction: Kt,
  },
  ri = n.object(kc).openapi("ListMessagesInput"),
  Fc = Yt(
    n.array(Jt),
    "Messages from the chat, sorted by timestamp. Use oldestCursor/newestCursor for pagination and treat both as opaque values.",
  ).openapi("ListMessagesOutput"),
  ue = (s) => ({ content: { "application/json": { schema: s } } }),
  Mc = n.object({ accountID: rs }),
  Rc = Xa.pick({ query: !0 }),
  Oc = n.object({ accountID: rs }),
  Lc = ei.omit({ accountID: !0 }),
  _e = n.object({ chatID: gt }),
  Nc = _e,
  Uc = ri.omit({ chatID: !0 }),
  Pc = _e,
  qc = Ja.omit({ chatID: !0 }),
  jc = _e,
  Vc = n.object({ chatID: gt, messageID: Gt }),
  Zc = n.object({ chatID: gt, messageID: Gt }),
  $c = Ga.omit({ chatID: !0, messageID: !0 }),
  Gc = n.object({ chatID: gt, messageID: Gt }),
  zc = za.omit({ chatID: !0, messageID: !0 }),
  Hc = n.object({ chatID: gt, messageID: Gt }),
  Wc = Ha.omit({ chatID: !0, messageID: !0 }),
  Kc = n.object({
    chatID: gt,
    messageID: Gt,
    reactionKey: n
      .string()
      .min(1)
      .describe(
        "Reaction key to remove (emoji, shortcode, or custom emoji key)",
      )
      .openapi({ param: { name: "reactionKey", in: "path", required: !0 } }),
  }),
  Yc = _e,
  Jc = Ua.omit({ chatID: !0 }),
  Qc = _e,
  Xc = Pa.omit({ chatID: !0 }),
  el = _e,
  tl = qa.omit({ chatID: !0 }),
  rl = _e,
  sl = _e,
  al = Va.omit({ chatID: !0 }),
  il = _e,
  nl = Za.omit({ chatID: !0 }),
  ol = _e,
  ul = $a.omit({ chatID: !0 }).openapi({ "x-stainless-empty-object": !0 }),
  cl = n.object({ accountID: rs }),
  sr = is,
  ll = ns,
  dl = ns,
  pl = ka.omit({ bridgeID: !0, loginID: !0 }),
  hl = is,
  ml = Fa.omit({ bridgeID: !0 }),
  Vs = os,
  gl = us.pick({ bridgeID: !0, loginSessionID: !0, stepID: !0 }),
  fl = us.omit({ bridgeID: !0, loginSessionID: !0, stepID: !0 });
const si = {
  getAccounts: {
    method: "get",
    path: "/v1/accounts",
    summary: "List chat accounts",
    description:
      "List chat accounts connected to this Beeper Client API server, including bridge, network, user identity, and connection status.",
    scopes: ["read"],
    tags: ["Accounts"],
    outputSchema: gu.openapi("GetAccountsOutput"),
  },
  getAccount: {
    method: "get",
    path: "/v1/accounts/:accountID",
    summary: "Get chat account",
    description:
      "Get one chat account connected to this Beeper Client API server.",
    scopes: ["read"],
    tags: ["Accounts"],
    inputSchema: fu,
    request: { params: cl },
    outputSchema: bu,
  },
  listBridges: {
    method: "get",
    path: "/v1/bridges",
    summary: "List available bridges",
    description:
      "List available bridges. A bridge is a chat-network connector that can connect or reconnect chat accounts. Connected accounts use the same Account schema as GET /v1/accounts.",
    scopes: ["read"],
    tags: ["Bridges"],
    outputSchema: yu,
  },
  getBridge: {
    method: "get",
    path: "/v1/bridges/:bridgeID",
    summary: "Get bridge",
    description:
      "Get one bridge, including the chat accounts connected through it.",
    scopes: ["read"],
    tags: ["Bridges"],
    inputSchema: is,
    request: { params: sr },
    outputSchema: Iu,
  },
  getBridgeCapabilities: {
    method: "get",
    path: "/v1/bridges/:bridgeID/capabilities",
    summary: "Get bridge capabilities",
    description:
      "Get advanced network capabilities for a bridge. This endpoint is intended for clients that build custom connect or chat-creation flows.",
    scopes: ["read"],
    tags: ["Bridges"],
    inputSchema: xu,
    request: { params: sr },
    outputSchema: Ta,
  },
  listBridgeLoginFlows: {
    method: "get",
    path: "/v1/bridges/:bridgeID/login-flows",
    summary: "List login flows",
    description:
      "List connect and reconnect flow options for a bridge. Use a flowID when creating a bridge login session.",
    scopes: ["read"],
    tags: ["Bridges"],
    inputSchema: Su,
    request: { params: sr },
    outputSchema: Bu,
  },
  listBridgeLogins: {
    method: "get",
    path: "/v1/bridges/:bridgeID/logins",
    summary: "List bridge logins",
    description:
      "List bridge logins. A bridge login is a signed-in identity for a bridge and can contain one or more chat accounts.",
    scopes: ["read"],
    tags: ["Bridges"],
    inputSchema: Tu,
    request: { params: sr },
    outputSchema: ku,
  },
  getBridgeLogin: {
    method: "get",
    path: "/v1/bridges/:bridgeID/logins/:loginID",
    summary: "Get bridge login",
    description: "Get one bridge login.",
    scopes: ["read"],
    tags: ["Bridges"],
    inputSchema: ns,
    request: { params: ll },
    outputSchema: Ir,
  },
  removeBridgeLogin: {
    method: "post",
    path: "/v1/bridges/:bridgeID/logins/:loginID/remove",
    summary: "Remove bridge login",
    description:
      "Remove a bridge login from this device or, when supported by the bridge, from all devices.",
    scopes: ["write"],
    tags: ["Bridges"],
    inputSchema: ka,
    request: { params: dl, body: ue(pl) },
    outputSchema: Fu,
  },
  createLoginSession: {
    method: "post",
    path: "/v1/bridges/:bridgeID/login-sessions",
    summary: "Create bridge login session",
    description:
      "Start a temporary bridge login session to connect a new chat account or reconnect an existing bridge login. Omit loginID and accountID to connect a new account.",
    scopes: ["write"],
    tags: ["Bridges"],
    inputSchema: Fa,
    request: { params: hl, body: ue(ml) },
    outputSchema: _r,
  },
  getLoginSession: {
    method: "get",
    path: "/v1/bridges/:bridgeID/login-sessions/:loginSessionID",
    summary: "Get bridge login session",
    description: "Get the current state of a temporary bridge login session.",
    scopes: ["read"],
    tags: ["Bridges"],
    inputSchema: os,
    request: { params: Vs },
    outputSchema: _r,
  },
  submitLoginStep: {
    method: "post",
    path: "/v1/bridges/:bridgeID/login-sessions/:loginSessionID/steps/:stepID",
    summary: "Submit login step",
    description: "Submit input for the current step of a bridge login session.",
    scopes: ["write"],
    tags: ["Bridges"],
    inputSchema: us,
    request: { params: gl, body: ue(fl) },
    outputSchema: _r,
  },
  cancelLoginSession: {
    method: "delete",
    path: "/v1/bridges/:bridgeID/login-sessions/:loginSessionID",
    summary: "Cancel bridge login session",
    description: "Cancel a temporary bridge login session.",
    scopes: ["write"],
    tags: ["Bridges"],
    inputSchema: Uu,
    request: { params: Vs },
    outputSchema: Pu,
  },
  searchMessages: {
    method: "get",
    path: "/v1/messages/search",
    summary: "Search messages",
    description: "Search messages across chats.",
    scopes: ["read"],
    tags: ["Messages"],
    inputSchema: Fs,
    request: { query: Fs },
    outputSchema: Qa.openapi("SearchMessagesOutput"),
  },
  searchChats: {
    method: "get",
    path: "/v1/chats/search",
    summary: "Search chats",
    description: "Search chats by title, network, or participant names.",
    scopes: ["read"],
    tags: ["Chats"],
    inputSchema: Ms,
    request: { query: Ms },
    outputSchema: vc.openapi("SearchChatsOutput"),
  },
  listLabels: {
    method: "get",
    path: "/v1/labels",
    summary: "List labels",
    description:
      "List the labels the user has created for organizing chats. Filter chats by label via GET /v1/chats/search with labelID.",
    scopes: ["read"],
    tags: ["Labels"],
    outputSchema: Dc.openapi("ListLabelsOutput"),
  },
  searchContacts: {
    method: "get",
    path: "/v1/accounts/:accountID/contacts",
    summary: "Search contacts",
    description:
      "Search contacts on a specific account using merged account contacts, network search, and exact identifier lookup. The exact lookup only runs when the query is a phone number, email address, or username; pass one of those to resolve a specific person.",
    scopes: ["read"],
    tags: ["Contacts"],
    inputSchema: Xa,
    request: { params: Mc, query: Rc },
    outputSchema: xc.openapi("SearchContactsOutput"),
  },
  listContacts: {
    method: "get",
    path: "/v1/accounts/:accountID/contacts/list",
    summary: "List contacts",
    description:
      "List merged contacts for a specific account with cursor-based pagination.",
    scopes: ["read"],
    tags: ["Contacts"],
    inputSchema: ei,
    request: { params: Oc, query: Lc },
    outputSchema: Sc.openapi("ListContactsOutput"),
  },
  search: {
    method: "get",
    path: "/v1/search",
    summary: "Search",
    description:
      "Return matching chats, participant matches in group chats, and the first page of message results in one call. Use the dedicated chat and message search endpoints for pagination.",
    scopes: ["read"],
    tags: ["App"],
    inputSchema: Us,
    request: { query: Us },
    outputSchema: Ic.openapi("UnifiedSearchOutput"),
  },
  focusApp: {
    method: "post",
    path: "/v1/focus",
    summary: "Focus Beeper Desktop app",
    description: Tr.description,
    scopes: ["read"],
    tags: ["App"],
    inputSchema: Tr,
    request: { body: ue(Tr) },
    outputSchema: qu.openapi("FocusAppOutput"),
  },
  listChats: {
    method: "get",
    path: "/v1/chats",
    summary: "List chats",
    description:
      "List all chats sorted by last activity (most recent first). Combines all accounts into a single paginated list.",
    scopes: ["read"],
    tags: ["Chats"],
    inputSchema: js,
    request: { query: js },
    outputSchema: Tc.openapi("ListChatsOutput"),
  },
  createChat: {
    method: "post",
    path: "/v1/chats",
    summary: "Create a chat",
    description:
      "Create a direct or group chat from participant IDs. Returns the created chat.",
    scopes: ["write"],
    tags: ["Chats"],
    inputSchema: Ps,
    request: { body: ue(Ps) },
    outputSchema: qs.openapi("CreateChatOutput"),
  },
  startChat: {
    method: "post",
    path: "/v1/chats/start",
    summary: "Start a direct chat",
    description:
      "Resolve a user/contact and open a direct chat. Reuses and returns an existing direct chat when one is found. Available in Beeper v4.2.808+.",
    scopes: ["write"],
    tags: ["Chats"],
    inputSchema: Hr,
    request: { body: ue(Hr) },
    outputSchema: qs,
  },
  getChat: {
    method: "get",
    path: "/v1/chats/:chatID",
    summary: "Retrieve chat details",
    description:
      "Retrieve chat details, including metadata, participants, and the latest message.",
    scopes: ["read"],
    tags: ["Chats"],
    inputSchema: Ja,
    request: { params: Pc, query: qc },
    outputSchema: ve,
  },
  archiveChat: {
    method: "post",
    path: "/v1/chats/:chatID/archive",
    summary: "Archive or unarchive a chat",
    description:
      "Archive or unarchive a chat. Set archived=true to move it to Archive, or archived=false to move it back to the inbox.",
    scopes: ["write"],
    tags: ["Chats"],
    inputSchema: Ua,
    request: { params: Yc, body: ue(Jc) },
    outputSchema: n.void(),
  },
  patchChat: {
    method: "patch",
    path: "/v1/chats/:chatID",
    summary: "Update chat",
    description:
      "Update supported chat fields. Non-empty drafts are accepted only when the current draft is empty. Send draft=null to clear the draft before setting new draft text or attachments.",
    scopes: ["write"],
    tags: ["Chats"],
    inputSchema: Pa,
    request: { params: Qc, body: ue(Xc) },
    outputSchema: ve,
  },
  setChatReminder: {
    method: "post",
    path: "/v1/chats/:chatID/reminders",
    summary: "Create a chat reminder",
    description: "Set a reminder for a chat at a specific time.",
    scopes: ["write"],
    tags: ["Chats"],
    inputSchema: qa,
    request: { params: el, body: ue(tl) },
    outputSchema: n.void(),
  },
  clearChatReminder: {
    method: "delete",
    path: "/v1/chats/:chatID/reminders",
    summary: "Delete a chat reminder",
    description: "Clear an existing reminder from a chat.",
    scopes: ["write"],
    tags: ["Chats"],
    inputSchema: Xu,
    request: { params: rl },
    outputSchema: n.void(),
  },
  markChatRead: {
    method: "post",
    path: "/v1/chats/:chatID/read",
    summary: "Mark a chat as read",
    description:
      "Mark a chat as read, optionally through a specific message ID.",
    scopes: ["write"],
    tags: ["Chats"],
    inputSchema: Va,
    request: { params: sl, body: ue(al) },
    outputSchema: ve,
  },
  markChatUnread: {
    method: "post",
    path: "/v1/chats/:chatID/unread",
    summary: "Mark a chat as unread",
    description:
      "Mark a chat as unread, optionally from a specific message ID.",
    scopes: ["write"],
    tags: ["Chats"],
    inputSchema: Za,
    request: { params: il, body: ue(nl) },
    outputSchema: ve,
  },
  notifyAnyway: {
    method: "post",
    path: "/v1/chats/:chatID/notify-anyway",
    summary: "Notify anyway",
    description:
      "Send a notification despite the recipient focus state when the network supports it. Currently intended for iMessage on macOS; unsupported networks return an error.",
    scopes: ["write"],
    tags: ["Chats"],
    inputSchema: $a,
    request: { params: ol, body: ue(ul) },
    outputSchema: ve,
  },
  listMessages: {
    method: "get",
    path: "/v1/chats/:chatID/messages",
    summary: "List messages",
    description:
      "List all messages in a chat with cursor-based pagination. Sorted by timestamp.",
    scopes: ["read"],
    tags: ["Messages"],
    inputSchema: ri,
    request: { params: Nc, query: Uc },
    outputSchema: Fc.openapi("ListMessagesOutput"),
  },
  sendMessage: {
    method: "post",
    path: "/v1/chats/:chatID/messages",
    summary: "Send a message",
    description:
      "Send a text message to a specific chat. Supports replying to existing messages. Returns a pending message ID.",
    scopes: ["write"],
    tags: ["Messages"],
    inputSchema: Hu,
    request: { params: jc, body: ue(Wu) },
    outputSchema: ec,
  },
  getMessage: {
    method: "get",
    path: "/v1/chats/:chatID/messages/:messageID",
    summary: "Retrieve a message",
    description:
      "Retrieve a message by final message ID, pendingMessageID, or Matrix event ID. chatID may be a Beeper chat ID or a local chat ID.",
    scopes: ["read"],
    tags: ["Messages"],
    inputSchema: rc,
    request: { params: Vc },
    outputSchema: Jt,
  },
  editMessage: {
    method: "put",
    path: "/v1/chats/:chatID/messages/:messageID",
    summary: "Edit a message",
    description:
      "Edit the text content of an existing message. Messages with attachments cannot be edited.",
    scopes: ["write"],
    tags: ["Messages"],
    inputSchema: Ga,
    request: { params: Zc, body: ue($c) },
    outputSchema: dc,
  },
  deleteMessage: {
    method: "delete",
    path: "/v1/chats/:chatID/messages/:messageID",
    summary: "Delete a message",
    description:
      "Delete a message by final message ID. Pending message IDs are not accepted because messages cannot be deleted while sending.",
    scopes: ["write"],
    tags: ["Messages"],
    inputSchema: za,
    request: { params: Gc, query: zc },
    outputSchema: n.void(),
  },
  addReaction: {
    method: "post",
    path: "/v1/chats/:chatID/messages/:messageID/reactions",
    summary: "Add a reaction",
    description: "Add a reaction to an existing message.",
    scopes: ["write"],
    tags: ["Messages"],
    inputSchema: Ha,
    request: { params: Hc, body: ue(Wc) },
    outputSchema: pc,
  },
  removeReaction: {
    method: "delete",
    path: "/v1/chats/:chatID/messages/:messageID/reactions/:reactionKey",
    summary: "Remove a reaction",
    description:
      "Remove the reaction added by the authenticated user from an existing message.",
    scopes: ["write"],
    tags: ["Messages"],
    inputSchema: sc,
    request: { params: Kc },
    outputSchema: hc,
  },
  downloadAsset: {
    method: "post",
    path: "/v1/assets/download",
    summary: "Download a file",
    description:
      "Download a file from an mxc:// or localmxc:// URL to the device running the Beeper Client API and return the local file URL.",
    scopes: ["read"],
    tags: ["Files"],
    inputSchema: Rs,
    request: { body: ue(Rs) },
    outputSchema: Cc,
  },
  serveAsset: {
    method: "get",
    path: "/v1/assets/serve",
    summary: "Serve a file",
    description:
      "Stream a file given an mxc://, localmxc://, or file:// URL. Downloads first if not cached. Supports Range requests for seeking in large files.",
    scopes: ["read"],
    tags: ["Files"],
    inputSchema: Os,
    request: { query: Os },
    outputSchema: n.void(),
    openApiSuccessResponses: {
      200: {
        description: "File stream",
        content: {
          "application/octet-stream": {
            schema: { type: "string", format: "binary" },
          },
        },
      },
      206: {
        description: "Partial file stream",
        content: {
          "application/octet-stream": {
            schema: { type: "string", format: "binary" },
          },
        },
      },
      304: { description: "File not modified" },
      416: { description: "Requested range not satisfiable" },
    },
  },
  uploadAsset: {
    method: "post",
    path: "/v1/assets/upload",
    summary: "Upload a file",
    description:
      "Upload a file to a temporary location using multipart/form-data. Returns an uploadID that can be referenced when sending a message or creating a draft attachment.",
    scopes: ["write"],
    tags: ["Files"],
    request: { body: { content: { "multipart/form-data": { schema: wc } } } },
    outputSchema: Ns,
  },
  uploadAssetBase64: {
    method: "post",
    path: "/v1/assets/upload/base64",
    summary: "Upload a file (base64)",
    description:
      "Upload a file using a JSON body with base64-encoded content. Returns an uploadID that can be referenced when sending a message or creating a draft attachment. Alternative to the multipart upload endpoint.",
    scopes: ["write"],
    tags: ["Files"],
    inputSchema: Ls,
    request: { body: ue(Ls) },
    outputSchema: Ns,
  },
};
function Re(s) {
  return Array.isArray ? Array.isArray(s) : ni(s) === "[object Array]";
}
function bl(s) {
  if (typeof s == "string") return s;
  let e = s + "";
  return e == "0" && 1 / s == -1 / 0 ? "-0" : e;
}
function Dl(s) {
  return s == null ? "" : bl(s);
}
function xe(s) {
  return typeof s == "string";
}
function ai(s) {
  return typeof s == "number";
}
function yl(s) {
  return s === !0 || s === !1 || (Al(s) && ni(s) == "[object Boolean]");
}
function ii(s) {
  return typeof s == "object";
}
function Al(s) {
  return ii(s) && s !== null;
}
function fe(s) {
  return s != null;
}
function kr(s) {
  return !s.trim().length;
}
function ni(s) {
  return s == null
    ? s === void 0
      ? "[object Undefined]"
      : "[object Null]"
    : Object.prototype.toString.call(s);
}
const vl = "Incorrect 'index' type",
  Cl = (s) => `Invalid value for key ${s}`,
  wl = (s) => `Pattern length exceeds max of ${s}.`,
  Il = (s) => `Missing ${s} property in key`,
  xl = (s) => `Property 'weight' in key '${s}' must be a positive integer`,
  Zs = Object.prototype.hasOwnProperty;
class El {
  constructor(e) {
    ((this._keys = []), (this._keyMap = {}));
    let t = 0;
    (e.forEach((r) => {
      let a = oi(r);
      (this._keys.push(a), (this._keyMap[a.id] = a), (t += a.weight));
    }),
      this._keys.forEach((r) => {
        r.weight /= t;
      }));
  }
  get(e) {
    return this._keyMap[e];
  }
  keys() {
    return this._keys;
  }
  toJSON() {
    return JSON.stringify(this._keys);
  }
}
function oi(s) {
  let e = null,
    t = null,
    r = null,
    a = 1,
    i = null;
  if (xe(s) || Re(s)) ((r = s), (e = $s(s)), (t = Wr(s)));
  else {
    if (!Zs.call(s, "name")) throw new Error(Il("name"));
    const o = s.name;
    if (((r = o), Zs.call(s, "weight") && ((a = s.weight), a <= 0)))
      throw new Error(xl(o));
    ((e = $s(o)), (t = Wr(o)), (i = s.getFn));
  }
  return { path: e, id: t, weight: a, src: r, getFn: i };
}
function $s(s) {
  return Re(s) ? s : s.split(".");
}
function Wr(s) {
  return Re(s) ? s.join(".") : s;
}
function Sl(s, e) {
  let t = [],
    r = !1;
  const a = (i, o, u) => {
    if (fe(i))
      if (!o[u]) t.push(i);
      else {
        let c = o[u];
        const l = i[c];
        if (!fe(l)) return;
        if (u === o.length - 1 && (xe(l) || ai(l) || yl(l))) t.push(Dl(l));
        else if (Re(l)) {
          r = !0;
          for (let d = 0, p = l.length; d < p; d += 1) a(l[d], o, u + 1);
        } else o.length && a(l, o, u + 1);
      }
  };
  return (a(s, xe(e) ? e.split(".") : e, 0), r ? t : t[0]);
}
const Bl = { includeMatches: !1, findAllMatches: !1, minMatchCharLength: 1 },
  _l = {
    isCaseSensitive: !1,
    ignoreDiacritics: !1,
    includeScore: !1,
    keys: [],
    shouldSort: !0,
    sortFn: (s, e) =>
      s.score === e.score
        ? s.idx < e.idx
          ? -1
          : 1
        : s.score < e.score
          ? -1
          : 1,
  },
  Tl = { location: 0, threshold: 0.6, distance: 100 },
  kl = {
    useExtendedSearch: !1,
    getFn: Sl,
    ignoreLocation: !1,
    ignoreFieldNorm: !1,
    fieldNormWeight: 1,
  };
var F = { ..._l, ...Bl, ...Tl, ...kl };
const Fl = /[^ ]+/g;
function Ml(s = 1, e = 3) {
  const t = new Map(),
    r = Math.pow(10, e);
  return {
    get(a) {
      const i = a.match(Fl).length;
      if (t.has(i)) return t.get(i);
      const o = 1 / Math.pow(i, 0.5 * s),
        u = parseFloat(Math.round(o * r) / r);
      return (t.set(i, u), u);
    },
    clear() {
      t.clear();
    },
  };
}
class ls {
  constructor({
    getFn: e = F.getFn,
    fieldNormWeight: t = F.fieldNormWeight,
  } = {}) {
    ((this.norm = Ml(t, 3)),
      (this.getFn = e),
      (this.isCreated = !1),
      this.setIndexRecords());
  }
  setSources(e = []) {
    this.docs = e;
  }
  setIndexRecords(e = []) {
    this.records = e;
  }
  setKeys(e = []) {
    ((this.keys = e),
      (this._keysMap = {}),
      e.forEach((t, r) => {
        this._keysMap[t.id] = r;
      }));
  }
  create() {
    this.isCreated ||
      !this.docs.length ||
      ((this.isCreated = !0),
      xe(this.docs[0])
        ? this.docs.forEach((e, t) => {
            this._addString(e, t);
          })
        : this.docs.forEach((e, t) => {
            this._addObject(e, t);
          }),
      this.norm.clear());
  }
  add(e) {
    const t = this.size();
    xe(e) ? this._addString(e, t) : this._addObject(e, t);
  }
  removeAt(e) {
    this.records.splice(e, 1);
    for (let t = e, r = this.size(); t < r; t += 1) this.records[t].i -= 1;
  }
  getValueForItemAtKeyId(e, t) {
    return e[this._keysMap[t]];
  }
  size() {
    return this.records.length;
  }
  _addString(e, t) {
    if (!fe(e) || kr(e)) return;
    let r = { v: e, i: t, n: this.norm.get(e) };
    this.records.push(r);
  }
  _addObject(e, t) {
    let r = { i: t, $: {} };
    (this.keys.forEach((a, i) => {
      let o = a.getFn ? a.getFn(e) : this.getFn(e, a.path);
      if (fe(o)) {
        if (Re(o)) {
          let u = [];
          const c = [{ nestedArrIndex: -1, value: o }];
          for (; c.length;) {
            const { nestedArrIndex: l, value: d } = c.pop();
            if (fe(d))
              if (xe(d) && !kr(d)) {
                let p = { v: d, i: l, n: this.norm.get(d) };
                u.push(p);
              } else
                Re(d) &&
                  d.forEach((p, h) => {
                    c.push({ nestedArrIndex: h, value: p });
                  });
          }
          r.$[i] = u;
        } else if (xe(o) && !kr(o)) {
          let u = { v: o, n: this.norm.get(o) };
          r.$[i] = u;
        }
      }
    }),
      this.records.push(r));
  }
  toJSON() {
    return { keys: this.keys, records: this.records };
  }
}
function ui(
  s,
  e,
  { getFn: t = F.getFn, fieldNormWeight: r = F.fieldNormWeight } = {},
) {
  const a = new ls({ getFn: t, fieldNormWeight: r });
  return (a.setKeys(s.map(oi)), a.setSources(e), a.create(), a);
}
function Rl(
  s,
  { getFn: e = F.getFn, fieldNormWeight: t = F.fieldNormWeight } = {},
) {
  const { keys: r, records: a } = s,
    i = new ls({ getFn: e, fieldNormWeight: t });
  return (i.setKeys(r), i.setIndexRecords(a), i);
}
function ar(
  s,
  {
    errors: e = 0,
    currentLocation: t = 0,
    expectedLocation: r = 0,
    distance: a = F.distance,
    ignoreLocation: i = F.ignoreLocation,
  } = {},
) {
  const o = e / s.length;
  if (i) return o;
  const u = Math.abs(r - t);
  return a ? o + u / a : u ? 1 : o;
}
function Ol(s = [], e = F.minMatchCharLength) {
  let t = [],
    r = -1,
    a = -1,
    i = 0;
  for (let o = s.length; i < o; i += 1) {
    let u = s[i];
    u && r === -1
      ? (r = i)
      : !u &&
        r !== -1 &&
        ((a = i - 1), a - r + 1 >= e && t.push([r, a]), (r = -1));
  }
  return (s[i - 1] && i - r >= e && t.push([r, i - 1]), t);
}
const He = 32;
function Ll(
  s,
  e,
  t,
  {
    location: r = F.location,
    distance: a = F.distance,
    threshold: i = F.threshold,
    findAllMatches: o = F.findAllMatches,
    minMatchCharLength: u = F.minMatchCharLength,
    includeMatches: c = F.includeMatches,
    ignoreLocation: l = F.ignoreLocation,
  } = {},
) {
  if (e.length > He) throw new Error(wl(He));
  const d = e.length,
    p = s.length,
    h = Math.max(0, Math.min(r, p));
  let m = i,
    g = h;
  const f = u > 1 || c,
    A = f ? Array(p) : [];
  let T;
  for (; (T = s.indexOf(e, g)) > -1;) {
    let M = ar(e, {
      currentLocation: T,
      expectedLocation: h,
      distance: a,
      ignoreLocation: l,
    });
    if (((m = Math.min(M, m)), (g = T + d), f)) {
      let q = 0;
      for (; q < d;) ((A[T + q] = 1), (q += 1));
    }
  }
  g = -1;
  let E = [],
    R = 1,
    P = d + p;
  const Y = 1 << (d - 1);
  for (let M = 0; M < d; M += 1) {
    let q = 0,
      V = P;
    for (; q < V;)
      (ar(e, {
        errors: M,
        currentLocation: h + V,
        expectedLocation: h,
        distance: a,
        ignoreLocation: l,
      }) <= m
        ? (q = V)
        : (P = V),
        (V = Math.floor((P - q) / 2 + q)));
    P = V;
    let te = Math.max(1, h - V + 1),
      oe = o ? p : Math.min(h + V, p) + d,
      re = Array(oe + 2);
    re[oe + 1] = (1 << M) - 1;
    for (let ie = oe; ie >= te; ie -= 1) {
      let G = ie - 1,
        U = t[s.charAt(G)];
      if (
        (f && (A[G] = +!!U),
        (re[ie] = ((re[ie + 1] << 1) | 1) & U),
        M && (re[ie] |= ((E[ie + 1] | E[ie]) << 1) | 1 | E[ie + 1]),
        re[ie] & Y &&
          ((R = ar(e, {
            errors: M,
            currentLocation: G,
            expectedLocation: h,
            distance: a,
            ignoreLocation: l,
          })),
          R <= m))
      ) {
        if (((m = R), (g = G), g <= h)) break;
        te = Math.max(1, 2 * h - g);
      }
    }
    if (
      ar(e, {
        errors: M + 1,
        currentLocation: h,
        expectedLocation: h,
        distance: a,
        ignoreLocation: l,
      }) > m
    )
      break;
    E = re;
  }
  const z = { isMatch: g >= 0, score: Math.max(0.001, R) };
  if (f) {
    const M = Ol(A, u);
    M.length ? c && (z.indices = M) : (z.isMatch = !1);
  }
  return z;
}
function Nl(s) {
  let e = {};
  for (let t = 0, r = s.length; t < r; t += 1) {
    const a = s.charAt(t);
    e[a] = (e[a] || 0) | (1 << (r - t - 1));
  }
  return e;
}
const Ar = String.prototype.normalize
  ? (s) =>
      s
        .normalize("NFD")
        .replace(
          /[\u0300-\u036F\u0483-\u0489\u0591-\u05BD\u05BF\u05C1\u05C2\u05C4\u05C5\u05C7\u0610-\u061A\u064B-\u065F\u0670\u06D6-\u06DC\u06DF-\u06E4\u06E7\u06E8\u06EA-\u06ED\u0711\u0730-\u074A\u07A6-\u07B0\u07EB-\u07F3\u07FD\u0816-\u0819\u081B-\u0823\u0825-\u0827\u0829-\u082D\u0859-\u085B\u08D3-\u08E1\u08E3-\u0903\u093A-\u093C\u093E-\u094F\u0951-\u0957\u0962\u0963\u0981-\u0983\u09BC\u09BE-\u09C4\u09C7\u09C8\u09CB-\u09CD\u09D7\u09E2\u09E3\u09FE\u0A01-\u0A03\u0A3C\u0A3E-\u0A42\u0A47\u0A48\u0A4B-\u0A4D\u0A51\u0A70\u0A71\u0A75\u0A81-\u0A83\u0ABC\u0ABE-\u0AC5\u0AC7-\u0AC9\u0ACB-\u0ACD\u0AE2\u0AE3\u0AFA-\u0AFF\u0B01-\u0B03\u0B3C\u0B3E-\u0B44\u0B47\u0B48\u0B4B-\u0B4D\u0B56\u0B57\u0B62\u0B63\u0B82\u0BBE-\u0BC2\u0BC6-\u0BC8\u0BCA-\u0BCD\u0BD7\u0C00-\u0C04\u0C3E-\u0C44\u0C46-\u0C48\u0C4A-\u0C4D\u0C55\u0C56\u0C62\u0C63\u0C81-\u0C83\u0CBC\u0CBE-\u0CC4\u0CC6-\u0CC8\u0CCA-\u0CCD\u0CD5\u0CD6\u0CE2\u0CE3\u0D00-\u0D03\u0D3B\u0D3C\u0D3E-\u0D44\u0D46-\u0D48\u0D4A-\u0D4D\u0D57\u0D62\u0D63\u0D82\u0D83\u0DCA\u0DCF-\u0DD4\u0DD6\u0DD8-\u0DDF\u0DF2\u0DF3\u0E31\u0E34-\u0E3A\u0E47-\u0E4E\u0EB1\u0EB4-\u0EB9\u0EBB\u0EBC\u0EC8-\u0ECD\u0F18\u0F19\u0F35\u0F37\u0F39\u0F3E\u0F3F\u0F71-\u0F84\u0F86\u0F87\u0F8D-\u0F97\u0F99-\u0FBC\u0FC6\u102B-\u103E\u1056-\u1059\u105E-\u1060\u1062-\u1064\u1067-\u106D\u1071-\u1074\u1082-\u108D\u108F\u109A-\u109D\u135D-\u135F\u1712-\u1714\u1732-\u1734\u1752\u1753\u1772\u1773\u17B4-\u17D3\u17DD\u180B-\u180D\u1885\u1886\u18A9\u1920-\u192B\u1930-\u193B\u1A17-\u1A1B\u1A55-\u1A5E\u1A60-\u1A7C\u1A7F\u1AB0-\u1ABE\u1B00-\u1B04\u1B34-\u1B44\u1B6B-\u1B73\u1B80-\u1B82\u1BA1-\u1BAD\u1BE6-\u1BF3\u1C24-\u1C37\u1CD0-\u1CD2\u1CD4-\u1CE8\u1CED\u1CF2-\u1CF4\u1CF7-\u1CF9\u1DC0-\u1DF9\u1DFB-\u1DFF\u20D0-\u20F0\u2CEF-\u2CF1\u2D7F\u2DE0-\u2DFF\u302A-\u302F\u3099\u309A\uA66F-\uA672\uA674-\uA67D\uA69E\uA69F\uA6F0\uA6F1\uA802\uA806\uA80B\uA823-\uA827\uA880\uA881\uA8B4-\uA8C5\uA8E0-\uA8F1\uA8FF\uA926-\uA92D\uA947-\uA953\uA980-\uA983\uA9B3-\uA9C0\uA9E5\uAA29-\uAA36\uAA43\uAA4C\uAA4D\uAA7B-\uAA7D\uAAB0\uAAB2-\uAAB4\uAAB7\uAAB8\uAABE\uAABF\uAAC1\uAAEB-\uAAEF\uAAF5\uAAF6\uABE3-\uABEA\uABEC\uABED\uFB1E\uFE00-\uFE0F\uFE20-\uFE2F]/g,
          "",
        )
  : (s) => s;
class ci {
  constructor(
    e,
    {
      location: t = F.location,
      threshold: r = F.threshold,
      distance: a = F.distance,
      includeMatches: i = F.includeMatches,
      findAllMatches: o = F.findAllMatches,
      minMatchCharLength: u = F.minMatchCharLength,
      isCaseSensitive: c = F.isCaseSensitive,
      ignoreDiacritics: l = F.ignoreDiacritics,
      ignoreLocation: d = F.ignoreLocation,
    } = {},
  ) {
    if (
      ((this.options = {
        location: t,
        threshold: r,
        distance: a,
        includeMatches: i,
        findAllMatches: o,
        minMatchCharLength: u,
        isCaseSensitive: c,
        ignoreDiacritics: l,
        ignoreLocation: d,
      }),
      (e = c ? e : e.toLowerCase()),
      (e = l ? Ar(e) : e),
      (this.pattern = e),
      (this.chunks = []),
      !this.pattern.length)
    )
      return;
    const p = (m, g) => {
        this.chunks.push({ pattern: m, alphabet: Nl(m), startIndex: g });
      },
      h = this.pattern.length;
    if (h > He) {
      let m = 0;
      const g = h % He,
        f = h - g;
      for (; m < f;) (p(this.pattern.substr(m, He), m), (m += He));
      if (g) {
        const A = h - He;
        p(this.pattern.substr(A), A);
      }
    } else p(this.pattern, 0);
  }
  searchIn(e) {
    const {
      isCaseSensitive: t,
      ignoreDiacritics: r,
      includeMatches: a,
    } = this.options;
    if (
      ((e = t ? e : e.toLowerCase()), (e = r ? Ar(e) : e), this.pattern === e)
    ) {
      let f = { isMatch: !0, score: 0 };
      return (a && (f.indices = [[0, e.length - 1]]), f);
    }
    const {
      location: i,
      distance: o,
      threshold: u,
      findAllMatches: c,
      minMatchCharLength: l,
      ignoreLocation: d,
    } = this.options;
    let p = [],
      h = 0,
      m = !1;
    this.chunks.forEach(({ pattern: f, alphabet: A, startIndex: T }) => {
      const {
        isMatch: E,
        score: R,
        indices: P,
      } = Ll(e, f, A, {
        location: i + T,
        distance: o,
        threshold: u,
        findAllMatches: c,
        minMatchCharLength: l,
        includeMatches: a,
        ignoreLocation: d,
      });
      (E && (m = !0), (h += R), E && P && (p = [...p, ...P]));
    });
    let g = { isMatch: m, score: m ? h / this.chunks.length : 1 };
    return (m && a && (g.indices = p), g);
  }
}
class Ve {
  constructor(e) {
    this.pattern = e;
  }
  static isMultiMatch(e) {
    return Gs(e, this.multiRegex);
  }
  static isSingleMatch(e) {
    return Gs(e, this.singleRegex);
  }
  search() {}
}
function Gs(s, e) {
  const t = s.match(e);
  return t ? t[1] : null;
}
class Ul extends Ve {
  constructor(e) {
    super(e);
  }
  static get type() {
    return "exact";
  }
  static get multiRegex() {
    return /^="(.*)"$/;
  }
  static get singleRegex() {
    return /^=(.*)$/;
  }
  search(e) {
    const t = e === this.pattern;
    return {
      isMatch: t,
      score: t ? 0 : 1,
      indices: [0, this.pattern.length - 1],
    };
  }
}
class Pl extends Ve {
  constructor(e) {
    super(e);
  }
  static get type() {
    return "inverse-exact";
  }
  static get multiRegex() {
    return /^!"(.*)"$/;
  }
  static get singleRegex() {
    return /^!(.*)$/;
  }
  search(e) {
    const r = e.indexOf(this.pattern) === -1;
    return { isMatch: r, score: r ? 0 : 1, indices: [0, e.length - 1] };
  }
}
class ql extends Ve {
  constructor(e) {
    super(e);
  }
  static get type() {
    return "prefix-exact";
  }
  static get multiRegex() {
    return /^\^"(.*)"$/;
  }
  static get singleRegex() {
    return /^\^(.*)$/;
  }
  search(e) {
    const t = e.startsWith(this.pattern);
    return {
      isMatch: t,
      score: t ? 0 : 1,
      indices: [0, this.pattern.length - 1],
    };
  }
}
class jl extends Ve {
  constructor(e) {
    super(e);
  }
  static get type() {
    return "inverse-prefix-exact";
  }
  static get multiRegex() {
    return /^!\^"(.*)"$/;
  }
  static get singleRegex() {
    return /^!\^(.*)$/;
  }
  search(e) {
    const t = !e.startsWith(this.pattern);
    return { isMatch: t, score: t ? 0 : 1, indices: [0, e.length - 1] };
  }
}
class Vl extends Ve {
  constructor(e) {
    super(e);
  }
  static get type() {
    return "suffix-exact";
  }
  static get multiRegex() {
    return /^"(.*)"\$$/;
  }
  static get singleRegex() {
    return /^(.*)\$$/;
  }
  search(e) {
    const t = e.endsWith(this.pattern);
    return {
      isMatch: t,
      score: t ? 0 : 1,
      indices: [e.length - this.pattern.length, e.length - 1],
    };
  }
}
class Zl extends Ve {
  constructor(e) {
    super(e);
  }
  static get type() {
    return "inverse-suffix-exact";
  }
  static get multiRegex() {
    return /^!"(.*)"\$$/;
  }
  static get singleRegex() {
    return /^!(.*)\$$/;
  }
  search(e) {
    const t = !e.endsWith(this.pattern);
    return { isMatch: t, score: t ? 0 : 1, indices: [0, e.length - 1] };
  }
}
class li extends Ve {
  constructor(
    e,
    {
      location: t = F.location,
      threshold: r = F.threshold,
      distance: a = F.distance,
      includeMatches: i = F.includeMatches,
      findAllMatches: o = F.findAllMatches,
      minMatchCharLength: u = F.minMatchCharLength,
      isCaseSensitive: c = F.isCaseSensitive,
      ignoreDiacritics: l = F.ignoreDiacritics,
      ignoreLocation: d = F.ignoreLocation,
    } = {},
  ) {
    (super(e),
      (this._bitapSearch = new ci(e, {
        location: t,
        threshold: r,
        distance: a,
        includeMatches: i,
        findAllMatches: o,
        minMatchCharLength: u,
        isCaseSensitive: c,
        ignoreDiacritics: l,
        ignoreLocation: d,
      })));
  }
  static get type() {
    return "fuzzy";
  }
  static get multiRegex() {
    return /^"(.*)"$/;
  }
  static get singleRegex() {
    return /^(.*)$/;
  }
  search(e) {
    return this._bitapSearch.searchIn(e);
  }
}
class di extends Ve {
  constructor(e) {
    super(e);
  }
  static get type() {
    return "include";
  }
  static get multiRegex() {
    return /^'"(.*)"$/;
  }
  static get singleRegex() {
    return /^'(.*)$/;
  }
  search(e) {
    let t = 0,
      r;
    const a = [],
      i = this.pattern.length;
    for (; (r = e.indexOf(this.pattern, t)) > -1;)
      ((t = r + i), a.push([r, t - 1]));
    const o = !!a.length;
    return { isMatch: o, score: o ? 0 : 1, indices: a };
  }
}
const Kr = [Ul, di, ql, jl, Zl, Vl, Pl, li],
  zs = Kr.length,
  $l = / +(?=(?:[^\"]*\"[^\"]*\")*[^\"]*$)/,
  Gl = "|";
function zl(s, e = {}) {
  return s.split(Gl).map((t) => {
    let r = t
        .trim()
        .split($l)
        .filter((i) => i && !!i.trim()),
      a = [];
    for (let i = 0, o = r.length; i < o; i += 1) {
      const u = r[i];
      let c = !1,
        l = -1;
      for (; !c && ++l < zs;) {
        const d = Kr[l];
        let p = d.isMultiMatch(u);
        p && (a.push(new d(p, e)), (c = !0));
      }
      if (!c)
        for (l = -1; ++l < zs;) {
          const d = Kr[l];
          let p = d.isSingleMatch(u);
          if (p) {
            a.push(new d(p, e));
            break;
          }
        }
    }
    return a;
  });
}
const Hl = new Set([li.type, di.type]);
class Wl {
  constructor(
    e,
    {
      isCaseSensitive: t = F.isCaseSensitive,
      ignoreDiacritics: r = F.ignoreDiacritics,
      includeMatches: a = F.includeMatches,
      minMatchCharLength: i = F.minMatchCharLength,
      ignoreLocation: o = F.ignoreLocation,
      findAllMatches: u = F.findAllMatches,
      location: c = F.location,
      threshold: l = F.threshold,
      distance: d = F.distance,
    } = {},
  ) {
    ((this.query = null),
      (this.options = {
        isCaseSensitive: t,
        ignoreDiacritics: r,
        includeMatches: a,
        minMatchCharLength: i,
        findAllMatches: u,
        ignoreLocation: o,
        location: c,
        threshold: l,
        distance: d,
      }),
      (e = t ? e : e.toLowerCase()),
      (e = r ? Ar(e) : e),
      (this.pattern = e),
      (this.query = zl(this.pattern, this.options)));
  }
  static condition(e, t) {
    return t.useExtendedSearch;
  }
  searchIn(e) {
    const t = this.query;
    if (!t) return { isMatch: !1, score: 1 };
    const {
      includeMatches: r,
      isCaseSensitive: a,
      ignoreDiacritics: i,
    } = this.options;
    ((e = a ? e : e.toLowerCase()), (e = i ? Ar(e) : e));
    let o = 0,
      u = [],
      c = 0;
    for (let l = 0, d = t.length; l < d; l += 1) {
      const p = t[l];
      ((u.length = 0), (o = 0));
      for (let h = 0, m = p.length; h < m; h += 1) {
        const g = p[h],
          { isMatch: f, indices: A, score: T } = g.search(e);
        if (f) {
          if (((o += 1), (c += T), r)) {
            const E = g.constructor.type;
            Hl.has(E) ? (u = [...u, ...A]) : u.push(A);
          }
        } else {
          ((c = 0), (o = 0), (u.length = 0));
          break;
        }
      }
      if (o) {
        let h = { isMatch: !0, score: c / o };
        return (r && (h.indices = u), h);
      }
    }
    return { isMatch: !1, score: 1 };
  }
}
const Yr = [];
function Kl(...s) {
  Yr.push(...s);
}
function Jr(s, e) {
  for (let t = 0, r = Yr.length; t < r; t += 1) {
    let a = Yr[t];
    if (a.condition(s, e)) return new a(s, e);
  }
  return new ci(s, e);
}
const vr = { AND: "$and", OR: "$or" },
  Qr = { PATH: "$path", PATTERN: "$val" },
  Xr = (s) => !!(s[vr.AND] || s[vr.OR]),
  Yl = (s) => !!s[Qr.PATH],
  Jl = (s) => !Re(s) && ii(s) && !Xr(s),
  Hs = (s) => ({ [vr.AND]: Object.keys(s).map((e) => ({ [e]: s[e] })) });
function pi(s, e, { auto: t = !0 } = {}) {
  const r = (a) => {
    let i = Object.keys(a);
    const o = Yl(a);
    if (!o && i.length > 1 && !Xr(a)) return r(Hs(a));
    if (Jl(a)) {
      const c = o ? a[Qr.PATH] : i[0],
        l = o ? a[Qr.PATTERN] : a[c];
      if (!xe(l)) throw new Error(Cl(c));
      const d = { keyId: Wr(c), pattern: l };
      return (t && (d.searcher = Jr(l, e)), d);
    }
    let u = { children: [], operator: i[0] };
    return (
      i.forEach((c) => {
        const l = a[c];
        Re(l) &&
          l.forEach((d) => {
            u.children.push(r(d));
          });
      }),
      u
    );
  };
  return (Xr(s) || (s = Hs(s)), r(s));
}
function Ql(s, { ignoreFieldNorm: e = F.ignoreFieldNorm }) {
  s.forEach((t) => {
    let r = 1;
    (t.matches.forEach(({ key: a, norm: i, score: o }) => {
      const u = a ? a.weight : null;
      r *= Math.pow(o === 0 && u ? Number.EPSILON : o, (u || 1) * (e ? 1 : i));
    }),
      (t.score = r));
  });
}
function Xl(s, e) {
  const t = s.matches;
  ((e.matches = []),
    fe(t) &&
      t.forEach((r) => {
        if (!fe(r.indices) || !r.indices.length) return;
        const { indices: a, value: i } = r;
        let o = { indices: a, value: i };
        (r.key && (o.key = r.key.src),
          r.idx > -1 && (o.refIndex = r.idx),
          e.matches.push(o));
      }));
}
function ed(s, e) {
  e.score = s.score;
}
function td(
  s,
  e,
  {
    includeMatches: t = F.includeMatches,
    includeScore: r = F.includeScore,
  } = {},
) {
  const a = [];
  return (
    t && a.push(Xl),
    r && a.push(ed),
    s.map((i) => {
      const { idx: o } = i,
        u = { item: e[o], refIndex: o };
      return (
        a.length &&
          a.forEach((c) => {
            c(i, u);
          }),
        u
      );
    })
  );
}
class ft {
  constructor(e, t = {}, r) {
    ((this.options = { ...F, ...t }),
      this.options.useExtendedSearch,
      (this._keyStore = new El(this.options.keys)),
      this.setCollection(e, r));
  }
  setCollection(e, t) {
    if (((this._docs = e), t && !(t instanceof ls))) throw new Error(vl);
    this._myIndex =
      t ||
      ui(this.options.keys, this._docs, {
        getFn: this.options.getFn,
        fieldNormWeight: this.options.fieldNormWeight,
      });
  }
  add(e) {
    fe(e) && (this._docs.push(e), this._myIndex.add(e));
  }
  remove(e = () => !1) {
    const t = [];
    for (let r = 0, a = this._docs.length; r < a; r += 1) {
      const i = this._docs[r];
      e(i, r) && (this.removeAt(r), (r -= 1), (a -= 1), t.push(i));
    }
    return t;
  }
  removeAt(e) {
    (this._docs.splice(e, 1), this._myIndex.removeAt(e));
  }
  getIndex() {
    return this._myIndex;
  }
  search(e, { limit: t = -1 } = {}) {
    const {
      includeMatches: r,
      includeScore: a,
      shouldSort: i,
      sortFn: o,
      ignoreFieldNorm: u,
    } = this.options;
    let c = xe(e)
      ? xe(this._docs[0])
        ? this._searchStringList(e)
        : this._searchObjectList(e)
      : this._searchLogical(e);
    return (
      Ql(c, { ignoreFieldNorm: u }),
      i && c.sort(o),
      ai(t) && t > -1 && (c = c.slice(0, t)),
      td(c, this._docs, { includeMatches: r, includeScore: a })
    );
  }
  _searchStringList(e) {
    const t = Jr(e, this.options),
      { records: r } = this._myIndex,
      a = [];
    return (
      r.forEach(({ v: i, i: o, n: u }) => {
        if (!fe(i)) return;
        const { isMatch: c, score: l, indices: d } = t.searchIn(i);
        c &&
          a.push({
            item: i,
            idx: o,
            matches: [{ score: l, value: i, norm: u, indices: d }],
          });
      }),
      a
    );
  }
  _searchLogical(e) {
    const t = pi(e, this.options),
      r = (u, c, l) => {
        if (!u.children) {
          const { keyId: p, searcher: h } = u,
            m = this._findMatches({
              key: this._keyStore.get(p),
              value: this._myIndex.getValueForItemAtKeyId(c, p),
              searcher: h,
            });
          return m && m.length ? [{ idx: l, item: c, matches: m }] : [];
        }
        const d = [];
        for (let p = 0, h = u.children.length; p < h; p += 1) {
          const m = u.children[p],
            g = r(m, c, l);
          if (g.length) d.push(...g);
          else if (u.operator === vr.AND) return [];
        }
        return d;
      },
      a = this._myIndex.records,
      i = {},
      o = [];
    return (
      a.forEach(({ $: u, i: c }) => {
        if (fe(u)) {
          let l = r(t, u, c);
          l.length &&
            (i[c] || ((i[c] = { idx: c, item: u, matches: [] }), o.push(i[c])),
            l.forEach(({ matches: d }) => {
              i[c].matches.push(...d);
            }));
        }
      }),
      o
    );
  }
  _searchObjectList(e) {
    const t = Jr(e, this.options),
      { keys: r, records: a } = this._myIndex,
      i = [];
    return (
      a.forEach(({ $: o, i: u }) => {
        if (!fe(o)) return;
        let c = [];
        (r.forEach((l, d) => {
          c.push(...this._findMatches({ key: l, value: o[d], searcher: t }));
        }),
          c.length && i.push({ idx: u, item: o, matches: c }));
      }),
      i
    );
  }
  _findMatches({ key: e, value: t, searcher: r }) {
    if (!fe(t)) return [];
    let a = [];
    if (Re(t))
      t.forEach(({ v: i, i: o, n: u }) => {
        if (!fe(i)) return;
        const { isMatch: c, score: l, indices: d } = r.searchIn(i);
        c &&
          a.push({ score: l, key: e, value: i, idx: o, norm: u, indices: d });
      });
    else {
      const { v: i, n: o } = t,
        { isMatch: u, score: c, indices: l } = r.searchIn(i);
      u && a.push({ score: c, key: e, value: i, norm: o, indices: l });
    }
    return a;
  }
}
ft.version = "7.1.0";
ft.createIndex = ui;
ft.parseIndex = Rl;
ft.config = F;
ft.parseQuery = pi;
Kl(Wl);
const hi = Object.freeze({
  af: "Afrikaans",
  ar: "Arabic",
  hy: "Armenian",
  az: "Azerbaijani",
  be: "Belarusian",
  bs: "Bosnian",
  bg: "Bulgarian",
  ca: "Catalan",
  zh: "Chinese",
  hr: "Croatian",
  cs: "Czech",
  da: "Danish",
  nl: "Dutch",
  en: "English",
  et: "Estonian",
  fi: "Finnish",
  fr: "French",
  gl: "Galician",
  de: "German",
  el: "Greek",
  he: "Hebrew",
  hi: "Hindi",
  hu: "Hungarian",
  is: "Icelandic",
  id: "Indonesian",
  it: "Italian",
  ja: "Japanese",
  kn: "Kannada",
  kk: "Kazakh",
  ko: "Korean",
  lv: "Latvian",
  lt: "Lithuanian",
  mk: "Macedonian",
  ms: "Malay",
  mr: "Marathi",
  mi: "Maori",
  ne: "Nepali",
  no: "Norwegian",
  fa: "Persian",
  pl: "Polish",
  pt: "Portuguese",
  "pt-BR": "Portuguese (Brazil)",
  ro: "Romanian",
  ru: "Russian",
  sr: "Serbian",
  sk: "Slovak",
  sl: "Slovenian",
  es: "Spanish",
  sw: "Swahili",
  sv: "Swedish",
  tl: "Tagalog",
  ta: "Tamil",
  th: "Thai",
  tr: "Turkish",
  uk: "Ukrainian",
  ur: "Urdu",
  vi: "Vietnamese",
  cy: "Welsh",
});
Object.freeze({ ...hi, "en-pirate": "Pirate English" });
Object.freeze(
  Object.fromEntries(Object.entries(hi).filter(([s]) => !s.includes("-"))),
);
const rd = {
    Á: "A",
    Ă: "A",
    Ắ: "A",
    Ặ: "A",
    Ằ: "A",
    Ẳ: "A",
    Ẵ: "A",
    Ǎ: "A",
    Â: "A",
    Ấ: "A",
    Ậ: "A",
    Ầ: "A",
    Ẩ: "A",
    Ẫ: "A",
    Ä: "A",
    Ǟ: "A",
    Ȧ: "A",
    Ǡ: "A",
    Ạ: "A",
    Ȁ: "A",
    À: "A",
    Ả: "A",
    Ȃ: "A",
    Ā: "A",
    Ą: "A",
    Å: "A",
    Ǻ: "A",
    Ḁ: "A",
    Ⱥ: "A",
    Ã: "A",
    Ꜳ: "AA",
    Æ: "AE",
    Ǽ: "AE",
    Ǣ: "AE",
    Ꜵ: "AO",
    Ꜷ: "AU",
    Ꜹ: "AV",
    Ꜻ: "AV",
    Ꜽ: "AY",
    Ḃ: "B",
    Ḅ: "B",
    Ɓ: "B",
    Ḇ: "B",
    Ƀ: "B",
    Ƃ: "B",
    Ć: "C",
    Č: "C",
    Ç: "C",
    Ḉ: "C",
    Ĉ: "C",
    Ċ: "C",
    Ƈ: "C",
    Ȼ: "C",
    Ď: "D",
    Ḑ: "D",
    Ḓ: "D",
    Ḋ: "D",
    Ḍ: "D",
    Ɗ: "D",
    Ḏ: "D",
    ǲ: "D",
    ǅ: "D",
    Đ: "D",
    Ð: "D",
    Ƌ: "D",
    Ǳ: "DZ",
    Ǆ: "DZ",
    É: "E",
    Ĕ: "E",
    Ě: "E",
    Ȩ: "E",
    Ḝ: "E",
    Ê: "E",
    Ế: "E",
    Ệ: "E",
    Ề: "E",
    Ể: "E",
    Ễ: "E",
    Ḙ: "E",
    Ë: "E",
    Ė: "E",
    Ẹ: "E",
    Ȅ: "E",
    È: "E",
    Ẻ: "E",
    Ȇ: "E",
    Ē: "E",
    Ḗ: "E",
    Ḕ: "E",
    Ę: "E",
    Ɇ: "E",
    Ẽ: "E",
    Ḛ: "E",
    Ꝫ: "ET",
    Ḟ: "F",
    Ƒ: "F",
    Ǵ: "G",
    Ğ: "G",
    Ǧ: "G",
    Ģ: "G",
    Ĝ: "G",
    Ġ: "G",
    Ɠ: "G",
    Ḡ: "G",
    Ǥ: "G",
    Ḫ: "H",
    Ȟ: "H",
    Ḩ: "H",
    Ĥ: "H",
    Ⱨ: "H",
    Ḧ: "H",
    Ḣ: "H",
    Ḥ: "H",
    Ħ: "H",
    Í: "I",
    Ĭ: "I",
    Ǐ: "I",
    Î: "I",
    Ï: "I",
    Ḯ: "I",
    İ: "I",
    Ị: "I",
    Ȉ: "I",
    Ì: "I",
    Ỉ: "I",
    Ȋ: "I",
    Ī: "I",
    Į: "I",
    Ɨ: "I",
    Ĩ: "I",
    Ḭ: "I",
    І: "I",
    Ꝺ: "D",
    Ꝼ: "F",
    Ᵹ: "G",
    Ꞃ: "R",
    Ꞅ: "S",
    Ꞇ: "T",
    Ꝭ: "IS",
    Ĵ: "J",
    Ɉ: "J",
    Ḱ: "K",
    Ǩ: "K",
    Ķ: "K",
    Ⱪ: "K",
    Ꝃ: "K",
    Ḳ: "K",
    Ƙ: "K",
    Ḵ: "K",
    Ꝁ: "K",
    Ꝅ: "K",
    Ĺ: "L",
    Ƚ: "L",
    Ľ: "L",
    Ļ: "L",
    Ḽ: "L",
    Ḷ: "L",
    Ḹ: "L",
    Ⱡ: "L",
    Ꝉ: "L",
    Ḻ: "L",
    Ŀ: "L",
    Ɫ: "L",
    ǈ: "L",
    Ł: "L",
    Ǉ: "LJ",
    Ḿ: "M",
    Ṁ: "M",
    Ṃ: "M",
    Ɱ: "M",
    Ń: "N",
    Ň: "N",
    Ņ: "N",
    Ṋ: "N",
    Ṅ: "N",
    Ṇ: "N",
    Ǹ: "N",
    Ɲ: "N",
    Ṉ: "N",
    Ƞ: "N",
    ǋ: "N",
    Ñ: "N",
    Ǌ: "NJ",
    Ó: "O",
    Ŏ: "O",
    Ǒ: "O",
    Ô: "O",
    Ố: "O",
    Ộ: "O",
    Ồ: "O",
    Ổ: "O",
    Ỗ: "O",
    Ö: "O",
    Ȫ: "O",
    Ȯ: "O",
    Ȱ: "O",
    Ọ: "O",
    Ő: "O",
    Ȍ: "O",
    Ò: "O",
    Ỏ: "O",
    Ơ: "O",
    Ớ: "O",
    Ợ: "O",
    Ờ: "O",
    Ở: "O",
    Ỡ: "O",
    Ȏ: "O",
    Ꝋ: "O",
    Ꝍ: "O",
    Ō: "O",
    Ṓ: "O",
    Ṑ: "O",
    Ɵ: "O",
    Ǫ: "O",
    Ǭ: "O",
    Ø: "O",
    Ǿ: "O",
    Õ: "O",
    Ṍ: "O",
    Ṏ: "O",
    Ȭ: "O",
    Ƣ: "OI",
    Ꝏ: "OO",
    Ɛ: "E",
    Ɔ: "O",
    Ȣ: "OU",
    Ṕ: "P",
    Ṗ: "P",
    Ꝓ: "P",
    Ƥ: "P",
    Ꝕ: "P",
    Ᵽ: "P",
    Ꝑ: "P",
    Ꝙ: "Q",
    Ꝗ: "Q",
    Ŕ: "R",
    Ř: "R",
    Ŗ: "R",
    Ṙ: "R",
    Ṛ: "R",
    Ṝ: "R",
    Ȑ: "R",
    Ȓ: "R",
    Ṟ: "R",
    Ɍ: "R",
    Ɽ: "R",
    Ꜿ: "C",
    Ǝ: "E",
    Ś: "S",
    Ṥ: "S",
    Š: "S",
    Ṧ: "S",
    Ş: "S",
    Ŝ: "S",
    Ș: "S",
    Ṡ: "S",
    Ṣ: "S",
    Ṩ: "S",
    ß: "ss",
    Ť: "T",
    Ţ: "T",
    Ṱ: "T",
    Ț: "T",
    Ⱦ: "T",
    Ṫ: "T",
    Ṭ: "T",
    Ƭ: "T",
    Ṯ: "T",
    Ʈ: "T",
    Ŧ: "T",
    Ɐ: "A",
    Ꞁ: "L",
    Ɯ: "M",
    Ʌ: "V",
    Ꜩ: "TZ",
    Ú: "U",
    Ŭ: "U",
    Ǔ: "U",
    Û: "U",
    Ṷ: "U",
    Ü: "U",
    Ǘ: "U",
    Ǚ: "U",
    Ǜ: "U",
    Ǖ: "U",
    Ṳ: "U",
    Ụ: "U",
    Ű: "U",
    Ȕ: "U",
    Ù: "U",
    Ủ: "U",
    Ư: "U",
    Ứ: "U",
    Ự: "U",
    Ừ: "U",
    Ử: "U",
    Ữ: "U",
    Ȗ: "U",
    Ū: "U",
    Ṻ: "U",
    Ų: "U",
    Ů: "U",
    Ũ: "U",
    Ṹ: "U",
    Ṵ: "U",
    Ꝟ: "V",
    Ṿ: "V",
    Ʋ: "V",
    Ṽ: "V",
    Ꝡ: "VY",
    Ẃ: "W",
    Ŵ: "W",
    Ẅ: "W",
    Ẇ: "W",
    Ẉ: "W",
    Ẁ: "W",
    Ⱳ: "W",
    Ẍ: "X",
    Ẋ: "X",
    Ý: "Y",
    Ŷ: "Y",
    Ÿ: "Y",
    Ẏ: "Y",
    Ỵ: "Y",
    Ỳ: "Y",
    Ƴ: "Y",
    Ỷ: "Y",
    Ỿ: "Y",
    Ȳ: "Y",
    Ɏ: "Y",
    Ỹ: "Y",
    Ї: "YI",
    Ź: "Z",
    Ž: "Z",
    Ẑ: "Z",
    Ⱬ: "Z",
    Ż: "Z",
    Ẓ: "Z",
    Ȥ: "Z",
    Ẕ: "Z",
    Ƶ: "Z",
    Þ: "TH",
    Ĳ: "IJ",
    Œ: "OE",
    ᴀ: "A",
    ᴁ: "AE",
    ʙ: "B",
    ᴃ: "B",
    ᴄ: "C",
    ᴅ: "D",
    ᴇ: "E",
    ꜰ: "F",
    ɢ: "G",
    ʛ: "G",
    ʜ: "H",
    ɪ: "I",
    ʁ: "R",
    ᴊ: "J",
    ᴋ: "K",
    ʟ: "L",
    ᴌ: "L",
    ᴍ: "M",
    ɴ: "N",
    ᴏ: "O",
    ɶ: "OE",
    ᴐ: "O",
    ᴕ: "OU",
    ᴘ: "P",
    ʀ: "R",
    ᴎ: "N",
    ᴙ: "R",
    ꜱ: "S",
    ᴛ: "T",
    ⱻ: "E",
    ᴚ: "R",
    ᴜ: "U",
    ᴠ: "V",
    ᴡ: "W",
    ʏ: "Y",
    ᴢ: "Z",
    á: "a",
    ă: "a",
    ắ: "a",
    ặ: "a",
    ằ: "a",
    ẳ: "a",
    ẵ: "a",
    ǎ: "a",
    â: "a",
    ấ: "a",
    ậ: "a",
    ầ: "a",
    ẩ: "a",
    ẫ: "a",
    ä: "a",
    ǟ: "a",
    ȧ: "a",
    ǡ: "a",
    ạ: "a",
    ȁ: "a",
    à: "a",
    ả: "a",
    ȃ: "a",
    ā: "a",
    ą: "a",
    ᶏ: "a",
    ẚ: "a",
    å: "a",
    ǻ: "a",
    ḁ: "a",
    ⱥ: "a",
    ã: "a",
    ꜳ: "aa",
    æ: "ae",
    ǽ: "ae",
    ǣ: "ae",
    ꜵ: "ao",
    ꜷ: "au",
    ꜹ: "av",
    ꜻ: "av",
    ꜽ: "ay",
    ḃ: "b",
    ḅ: "b",
    ɓ: "b",
    ḇ: "b",
    ᵬ: "b",
    ᶀ: "b",
    ƀ: "b",
    ƃ: "b",
    ɵ: "o",
    ć: "c",
    č: "c",
    ç: "c",
    ḉ: "c",
    ĉ: "c",
    ɕ: "c",
    ċ: "c",
    ƈ: "c",
    ȼ: "c",
    ď: "d",
    ḑ: "d",
    ḓ: "d",
    ȡ: "d",
    ḋ: "d",
    ḍ: "d",
    ɗ: "d",
    ᶑ: "d",
    ḏ: "d",
    ᵭ: "d",
    ᶁ: "d",
    đ: "d",
    ɖ: "d",
    ƌ: "d",
    ð: "d",
    ı: "i",
    ȷ: "j",
    ɟ: "j",
    ʄ: "j",
    ǳ: "dz",
    ǆ: "dz",
    é: "e",
    ĕ: "e",
    ě: "e",
    ȩ: "e",
    ḝ: "e",
    ê: "e",
    ế: "e",
    ệ: "e",
    ề: "e",
    ể: "e",
    ễ: "e",
    ḙ: "e",
    ë: "e",
    ė: "e",
    ẹ: "e",
    ȅ: "e",
    è: "e",
    ẻ: "e",
    ȇ: "e",
    ē: "e",
    ḗ: "e",
    ḕ: "e",
    ⱸ: "e",
    ę: "e",
    ᶒ: "e",
    ɇ: "e",
    ẽ: "e",
    ḛ: "e",
    ꝫ: "et",
    ḟ: "f",
    ƒ: "f",
    ᵮ: "f",
    ᶂ: "f",
    ǵ: "g",
    ğ: "g",
    ǧ: "g",
    ģ: "g",
    ĝ: "g",
    ġ: "g",
    ɠ: "g",
    ḡ: "g",
    ᶃ: "g",
    ǥ: "g",
    ḫ: "h",
    ȟ: "h",
    ḩ: "h",
    ĥ: "h",
    ⱨ: "h",
    ḧ: "h",
    ḣ: "h",
    ḥ: "h",
    ɦ: "h",
    ẖ: "h",
    ħ: "h",
    ƕ: "hv",
    í: "i",
    ĭ: "i",
    ǐ: "i",
    î: "i",
    ï: "i",
    ḯ: "i",
    ị: "i",
    ȉ: "i",
    ì: "i",
    ỉ: "i",
    ȋ: "i",
    ī: "i",
    į: "i",
    ᶖ: "i",
    ɨ: "i",
    ĩ: "i",
    ḭ: "i",
    і: "i",
    ꝺ: "d",
    ꝼ: "f",
    ᵹ: "g",
    ꞃ: "r",
    ꞅ: "s",
    ꞇ: "t",
    ꝭ: "is",
    ǰ: "j",
    ĵ: "j",
    ʝ: "j",
    ɉ: "j",
    ḱ: "k",
    ǩ: "k",
    ķ: "k",
    ⱪ: "k",
    ꝃ: "k",
    ḳ: "k",
    ƙ: "k",
    ḵ: "k",
    ᶄ: "k",
    ꝁ: "k",
    ꝅ: "k",
    ĺ: "l",
    ƚ: "l",
    ɬ: "l",
    ľ: "l",
    ļ: "l",
    ḽ: "l",
    ȴ: "l",
    ḷ: "l",
    ḹ: "l",
    ⱡ: "l",
    ꝉ: "l",
    ḻ: "l",
    ŀ: "l",
    ɫ: "l",
    ᶅ: "l",
    ɭ: "l",
    ł: "l",
    ǉ: "lj",
    ſ: "s",
    ẜ: "s",
    ẛ: "s",
    ẝ: "s",
    ḿ: "m",
    ṁ: "m",
    ṃ: "m",
    ɱ: "m",
    ᵯ: "m",
    ᶆ: "m",
    ń: "n",
    ň: "n",
    ņ: "n",
    ṋ: "n",
    ȵ: "n",
    ṅ: "n",
    ṇ: "n",
    ǹ: "n",
    ɲ: "n",
    ṉ: "n",
    ƞ: "n",
    ᵰ: "n",
    ᶇ: "n",
    ɳ: "n",
    ñ: "n",
    ǌ: "nj",
    ó: "o",
    ŏ: "o",
    ǒ: "o",
    ô: "o",
    ố: "o",
    ộ: "o",
    ồ: "o",
    ổ: "o",
    ỗ: "o",
    ö: "o",
    ȫ: "o",
    ȯ: "o",
    ȱ: "o",
    ọ: "o",
    ő: "o",
    ȍ: "o",
    ò: "o",
    ỏ: "o",
    ơ: "o",
    ớ: "o",
    ợ: "o",
    ờ: "o",
    ở: "o",
    ỡ: "o",
    ȏ: "o",
    ꝋ: "o",
    ꝍ: "o",
    ⱺ: "o",
    ō: "o",
    ṓ: "o",
    ṑ: "o",
    ǫ: "o",
    ǭ: "o",
    ø: "o",
    ǿ: "o",
    õ: "o",
    ṍ: "o",
    ṏ: "o",
    ȭ: "o",
    ƣ: "oi",
    ꝏ: "oo",
    ɛ: "e",
    ᶓ: "e",
    ɔ: "o",
    ᶗ: "o",
    ȣ: "ou",
    ṕ: "p",
    ṗ: "p",
    ꝓ: "p",
    ƥ: "p",
    ᵱ: "p",
    ᶈ: "p",
    ꝕ: "p",
    ᵽ: "p",
    ꝑ: "p",
    ꝙ: "q",
    ʠ: "q",
    ɋ: "q",
    ꝗ: "q",
    ŕ: "r",
    ř: "r",
    ŗ: "r",
    ṙ: "r",
    ṛ: "r",
    ṝ: "r",
    ȑ: "r",
    ɾ: "r",
    ᵳ: "r",
    ȓ: "r",
    ṟ: "r",
    ɼ: "r",
    ᵲ: "r",
    ᶉ: "r",
    ɍ: "r",
    ɽ: "r",
    ↄ: "c",
    ꜿ: "c",
    ɘ: "e",
    ɿ: "r",
    ś: "s",
    ṥ: "s",
    š: "s",
    ṧ: "s",
    ş: "s",
    ŝ: "s",
    ș: "s",
    ṡ: "s",
    ṣ: "s",
    ṩ: "s",
    ʂ: "s",
    ᵴ: "s",
    ᶊ: "s",
    ȿ: "s",
    ɡ: "g",
    ᴑ: "o",
    ᴓ: "o",
    ᴝ: "u",
    ť: "t",
    ţ: "t",
    ṱ: "t",
    ț: "t",
    ȶ: "t",
    ẗ: "t",
    ⱦ: "t",
    ṫ: "t",
    ṭ: "t",
    ƭ: "t",
    ṯ: "t",
    ᵵ: "t",
    ƫ: "t",
    ʈ: "t",
    ŧ: "t",
    ᵺ: "th",
    ɐ: "a",
    ᴂ: "ae",
    ǝ: "e",
    ᵷ: "g",
    ɥ: "h",
    ʮ: "h",
    ʯ: "h",
    ᴉ: "i",
    ʞ: "k",
    ꞁ: "l",
    ɯ: "m",
    ɰ: "m",
    ᴔ: "oe",
    ɹ: "r",
    ɻ: "r",
    ɺ: "r",
    ⱹ: "r",
    ʇ: "t",
    ʌ: "v",
    ʍ: "w",
    ʎ: "y",
    ꜩ: "tz",
    ú: "u",
    ŭ: "u",
    ǔ: "u",
    û: "u",
    ṷ: "u",
    ü: "u",
    ǘ: "u",
    ǚ: "u",
    ǜ: "u",
    ǖ: "u",
    ṳ: "u",
    ụ: "u",
    ű: "u",
    ȕ: "u",
    ù: "u",
    ủ: "u",
    ư: "u",
    ứ: "u",
    ự: "u",
    ừ: "u",
    ử: "u",
    ữ: "u",
    ȗ: "u",
    ū: "u",
    ṻ: "u",
    ų: "u",
    ᶙ: "u",
    ů: "u",
    ũ: "u",
    ṹ: "u",
    ṵ: "u",
    ᵫ: "ue",
    ꝸ: "um",
    ⱴ: "v",
    ꝟ: "v",
    ṿ: "v",
    ʋ: "v",
    ᶌ: "v",
    ⱱ: "v",
    ṽ: "v",
    ꝡ: "vy",
    ẃ: "w",
    ŵ: "w",
    ẅ: "w",
    ẇ: "w",
    ẉ: "w",
    ẁ: "w",
    ⱳ: "w",
    ẘ: "w",
    ẍ: "x",
    ẋ: "x",
    ᶍ: "x",
    ý: "y",
    ŷ: "y",
    ÿ: "y",
    ẏ: "y",
    ỵ: "y",
    ỳ: "y",
    ƴ: "y",
    ỷ: "y",
    ỿ: "y",
    ȳ: "y",
    ẙ: "y",
    ɏ: "y",
    ỹ: "y",
    ї: "yi",
    ź: "z",
    ž: "z",
    ẑ: "z",
    ʑ: "z",
    ⱬ: "z",
    ż: "z",
    ẓ: "z",
    ȥ: "z",
    ẕ: "z",
    ᵶ: "z",
    ᶎ: "z",
    ʐ: "z",
    ƶ: "z",
    ɀ: "z",
    þ: "th",
    ﬀ: "ff",
    ﬃ: "ffi",
    ﬄ: "ffl",
    ﬁ: "fi",
    ﬂ: "fl",
    ĳ: "ij",
    œ: "oe",
    ﬆ: "st",
    ₐ: "a",
    ₑ: "e",
    ᵢ: "i",
    ⱼ: "j",
    ₒ: "o",
    ᵣ: "r",
    ᵤ: "u",
    ᵥ: "v",
    ₓ: "x",
    Ё: "YO",
    Й: "I",
    Ц: "TS",
    У: "U",
    К: "K",
    Е: "E",
    Н: "N",
    Г: "G",
    Ґ: "G",
    Ш: "SH",
    Щ: "SCH",
    З: "Z",
    Х: "H",
    Ъ: "'",
    ё: "yo",
    й: "i",
    ц: "ts",
    у: "u",
    к: "k",
    е: "e",
    н: "n",
    г: "g",
    ґ: "g",
    ш: "sh",
    щ: "sch",
    з: "z",
    х: "h",
    ъ: "'",
    Ф: "F",
    Ы: "I",
    В: "V",
    А: "a",
    П: "P",
    Р: "R",
    О: "O",
    Л: "L",
    Д: "D",
    Ж: "ZH",
    Э: "E",
    ф: "f",
    ы: "i",
    в: "v",
    а: "a",
    п: "p",
    р: "r",
    о: "o",
    л: "l",
    д: "d",
    ж: "zh",
    э: "e",
    Я: "Ya",
    Ч: "CH",
    С: "S",
    М: "M",
    И: "I",
    Т: "T",
    Ь: "'",
    Б: "B",
    Ю: "YU",
    я: "ya",
    ч: "ch",
    с: "s",
    м: "m",
    и: "i",
    т: "t",
    ь: "'",
    б: "b",
    ю: "yu",
  },
  sd = /[^A-Za-z0-9]/g,
  ot = (s) => s.replace(sd, (e) => rd[e] || e),
  ad = new Set(["and"]),
  id = 0.32,
  nd = 4,
  mi = { title: 1, network: 0.35, participants: 0.55 },
  gi = {
    exact: 1200,
    prefix: 1e3,
    word: 800,
    "token-prefix": 650,
    substring: 450,
    fuzzy: 260,
  };
function od(s) {
  return ot(s)
    .toLowerCase()
    .replace(/[|!'^=]/g, " ")
    .replace(/[,;!?(){}[\]"'`~#$%^&*+=<>\\]/g, " ")
    .replace(/\s+/g, " ")
    .trim()
    .split(/\s+/)
    .filter(Boolean);
}
function ud(s) {
  return ot(s).toLowerCase().replace(/\s+/g, " ").trim();
}
function cd(s) {
  return /[^\p{L}\p{N}_\-\s]/u.test(s);
}
function ld(s) {
  const e = ot(s.title ?? "").toLowerCase(),
    t = ot(s.networkDisplayName ?? "").toLowerCase(),
    r = [];
  for (const a of (s.participants ?? []).slice(0, 50)) {
    const i = [
      a?.fullName ?? void 0,
      a?.nickname ?? void 0,
      a?.username ?? void 0,
      a?.email ?? void 0,
      a?.phoneNumber ? String(a.phoneNumber).replace(/\D/g, "") : void 0,
    ]
      .filter(Boolean)
      .map((o) => ot(String(o)).toLowerCase());
    i.length > 0 && r.push(i.join(" "));
  }
  return { title: e, network: t, participants: r };
}
function ut(s) {
  return !s || s.length === 0
    ? { minScore: Number.MAX_SAFE_INTEGER, hits: 0 }
    : { minScore: Math.min(...s), hits: s.length };
}
function dd(s) {
  return {
    title: ut(s.title),
    network: ut(s.network),
    participants: ut(s.participants),
  };
}
function Ws(s) {
  return 1 / (1 + s);
}
function Fr(s, e, t) {
  const r = Array.isArray(e) ? e : [e];
  let a = null;
  for (const i of r) {
    const o = pd(s, String(i ?? ""), t);
    o != null && (a == null || o > a) && (a = o);
  }
  return a;
}
function pd(s, e, t) {
  if (!e || !t) return null;
  const r = ot(e).toLowerCase(),
    a = mi[s],
    i = t.trim();
  return i
    ? r === i
      ? Ct("exact", a)
      : r.startsWith(i)
        ? Ct("prefix", a)
        : md(r, i)
          ? Ct("word", a)
          : gd(r, i)
            ? Ct("token-prefix", a)
            : r.includes(i)
              ? Ct("substring", a)
              : null
    : null;
}
function hd(s) {
  const e = od(s),
    t = e.filter((r) => !ad.has(r));
  return { requiredTerms: t, termsToMatch: t.length > 0 ? t : e };
}
function Ct(s, e) {
  return gi[s] * e;
}
function md(s, e) {
  let t = s.indexOf(e);
  for (; t >= 0;) {
    const r = t === 0 ? "" : s[t - 1],
      a = s[t + e.length] ?? "";
    if (!Ks(r) && !Ks(a)) return !0;
    t = s.indexOf(e, t + 1);
  }
  return !1;
}
function Ks(s) {
  return /^[a-z0-9_-]$/.test(s);
}
function gd(s, e) {
  const t = /[a-z0-9]+/g;
  let r;
  for (; (r = t.exec(s)) !== null;) if (r[0].startsWith(e)) return !0;
  return !1;
}
function fd(s, e, t) {
  if (e.length < nd) return null;
  const r = Math.max(0, 1 - Math.min(t, 1));
  return r <= 0 ? null : gi.fuzzy * mi[s] * r;
}
class bd {
  constructor(e = [], t = {}) {
    ((this.itemsByID = new Map()),
      (this.fuzzy = t.fuzzy ?? !0),
      this.fuzzy &&
        (this.fuse = new ft(e, {
          ignoreDiacritics: !0,
          includeScore: !0,
          ignoreLocation: !0,
          ignoreFieldNorm: !0,
          threshold: id,
          keys: [
            "searchFields.title",
            "searchFields.network",
            "searchFields.participants",
          ],
        })));
    for (const r of e) this.itemsByID.set(r.id, r);
  }
  setCollection(e) {
    this.itemsByID.clear();
    for (const t of e) this.itemsByID.set(t.id, t);
    this.fuse?.setCollection(e);
  }
  upsert(e) {
    (this.itemsByID.set(e.id, e),
      this.fuse?.remove((t) => t.id === e.id),
      this.fuse?.add(e));
  }
  remove(e) {
    this.itemsByID.has(e) &&
      (this.itemsByID.delete(e), this.fuse?.remove((t) => t.id === e));
  }
  search(e, t) {
    if (!e?.trim()) return [];
    const { requiredTerms: r, termsToMatch: a } = hd(e),
      i = new Map(),
      o = (d) => {
        let p = i.get(d);
        return (
          p ||
            ((p = {
              id: d,
              title: [],
              network: [],
              participants: [],
              matchedSearchTerms: new Set(),
              relevance: 0,
            }),
            i.set(d, p)),
          p
        );
      },
      u = ud(e);
    if (t.includes("title") && cd(u)) {
      const d = [];
      for (const p of this.itemsByID.values()) {
        const h = { title: [], network: [], participants: [] };
        let m = 0;
        for (const g of t) {
          const f = Fr(g, p.searchFields[g], u);
          f != null && (h[g].push(Ws(f)), (m += f));
        }
        m !== 0 &&
          d.push({
            id: p.id,
            score: {
              title: ut(h.title),
              network: ut(h.network),
              participants: ut(h.participants),
            },
            relevance: m,
            matchSearchTerms: new Set([u]),
          });
      }
      if (d.length > 0) return d;
    }
    for (const d of a)
      for (const p of t)
        if (this.fuzzy && this.fuse) {
          const h = this.fuse.search({ [`searchFields.${p}`]: d });
          for (const m of h) {
            if (m.score == null) continue;
            const g = Fr(p, m.item.searchFields[p], d) ?? fd(p, d, m.score);
            if (g == null) continue;
            const f = o(m.item.id);
            (f[p].push(m.score),
              f.matchedSearchTerms.add(d),
              (f.relevance += g));
          }
        } else
          for (const h of this.itemsByID.values()) {
            const m = Fr(p, h.searchFields[p], d);
            if (m == null) continue;
            const g = o(h.id);
            (g[p].push(Ws(m)), g.matchedSearchTerms.add(d), (g.relevance += m));
          }
    const l = [];
    for (const d of i.values())
      (r.length > 0 && !r.every((p) => d.matchedSearchTerms.has(p))) ||
        l.push({
          id: d.id,
          score: dd(d),
          relevance: d.relevance,
          matchSearchTerms: d.matchedSearchTerms,
        });
    return l;
  }
}
class st {
  constructor() {
    ((this.index = new bd([])),
      (this.idToMeta = new Map()),
      (this.accountToIDs = new Map()));
  }
  static keyOf(e, t) {
    return `${e}:${t}`;
  }
  setItems(e) {
    const t = e.map((r) => ({
      id: st.keyOf(r.accountID, r.threadID),
      searchFields: r.searchFields,
    }));
    (this.index.setCollection(t),
      this.idToMeta.clear(),
      this.accountToIDs.clear());
    for (const r of e) {
      const a = st.keyOf(r.accountID, r.threadID);
      this.idToMeta.set(a, { accountID: r.accountID, threadID: r.threadID });
      let i = this.accountToIDs.get(r.accountID);
      (i || ((i = new Set()), this.accountToIDs.set(r.accountID, i)), i.add(a));
    }
  }
  upsert(e) {
    const t = st.keyOf(e.accountID, e.threadID);
    (this.index.upsert({ id: t, searchFields: e.searchFields }),
      this.idToMeta.set(t, { accountID: e.accountID, threadID: e.threadID }));
    let r = this.accountToIDs.get(e.accountID);
    (r || ((r = new Set()), this.accountToIDs.set(e.accountID, r)), r.add(t));
  }
  replaceAccountItems(e, t) {
    const r = this.accountToIDs.get(e);
    if (r) {
      for (const a of r) (this.index.remove(a), this.idToMeta.delete(a));
      r.clear();
    }
    if (t.length === 0) {
      this.accountToIDs.delete(e);
      return;
    }
    for (const a of t) this.upsert(a);
  }
  remove(e, t) {
    const r = st.keyOf(e, t);
    (this.index.remove(r), this.idToMeta.delete(r));
    const a = this.accountToIDs.get(e);
    a && a.delete(r);
  }
  searchTitlesOrNetworkDetailed(e) {
    return this.index
      .search(e, ["title", "network"])
      .map((r) => {
        const a = this.idToMeta.get(r.id);
        return a ? { meta: a, result: r } : null;
      })
      .filter((r) => !!r);
  }
  searchParticipantsDetailed(e) {
    return this.index
      .search(e, ["participants"])
      .map((r) => {
        const a = this.idToMeta.get(r.id);
        return a ? { meta: a, result: r } : null;
      })
      .filter((r) => !!r);
  }
}
var xt = { exports: {} };
var Dd = xt.exports,
  Ys;
function yd() {
  return (
    Ys ||
      ((Ys = 1),
      (function (s, e) {
        (function (t) {
          var r = e,
            a = s && s.exports == r && s,
            i = typeof As == "object" && As;
          (i.global === i || i.window === i) && (t = i);
          var o = /[\uD800-\uDBFF][\uDC00-\uDFFF]/g,
            u = /[\x01-\x7F]/g,
            c = /[\x01-\t\x0B\f\x0E-\x1F\x7F\x81\x8D\x8F\x90\x9D\xA0-\uFFFF]/g,
            l =
              /<\u20D2|=\u20E5|>\u20D2|\u205F\u200A|\u219D\u0338|\u2202\u0338|\u2220\u20D2|\u2229\uFE00|\u222A\uFE00|\u223C\u20D2|\u223D\u0331|\u223E\u0333|\u2242\u0338|\u224B\u0338|\u224D\u20D2|\u224E\u0338|\u224F\u0338|\u2250\u0338|\u2261\u20E5|\u2264\u20D2|\u2265\u20D2|\u2266\u0338|\u2267\u0338|\u2268\uFE00|\u2269\uFE00|\u226A\u0338|\u226A\u20D2|\u226B\u0338|\u226B\u20D2|\u227F\u0338|\u2282\u20D2|\u2283\u20D2|\u228A\uFE00|\u228B\uFE00|\u228F\u0338|\u2290\u0338|\u2293\uFE00|\u2294\uFE00|\u22B4\u20D2|\u22B5\u20D2|\u22D8\u0338|\u22D9\u0338|\u22DA\uFE00|\u22DB\uFE00|\u22F5\u0338|\u22F9\u0338|\u2933\u0338|\u29CF\u0338|\u29D0\u0338|\u2A6D\u0338|\u2A70\u0338|\u2A7D\u0338|\u2A7E\u0338|\u2AA1\u0338|\u2AA2\u0338|\u2AAC\uFE00|\u2AAD\uFE00|\u2AAF\u0338|\u2AB0\u0338|\u2AC5\u0338|\u2AC6\u0338|\u2ACB\uFE00|\u2ACC\uFE00|\u2AFD\u20E5|[\xA0-\u0113\u0116-\u0122\u0124-\u012B\u012E-\u014D\u0150-\u017E\u0192\u01B5\u01F5\u0237\u02C6\u02C7\u02D8-\u02DD\u0311\u0391-\u03A1\u03A3-\u03A9\u03B1-\u03C9\u03D1\u03D2\u03D5\u03D6\u03DC\u03DD\u03F0\u03F1\u03F5\u03F6\u0401-\u040C\u040E-\u044F\u0451-\u045C\u045E\u045F\u2002-\u2005\u2007-\u2010\u2013-\u2016\u2018-\u201A\u201C-\u201E\u2020-\u2022\u2025\u2026\u2030-\u2035\u2039\u203A\u203E\u2041\u2043\u2044\u204F\u2057\u205F-\u2063\u20AC\u20DB\u20DC\u2102\u2105\u210A-\u2113\u2115-\u211E\u2122\u2124\u2127-\u2129\u212C\u212D\u212F-\u2131\u2133-\u2138\u2145-\u2148\u2153-\u215E\u2190-\u219B\u219D-\u21A7\u21A9-\u21AE\u21B0-\u21B3\u21B5-\u21B7\u21BA-\u21DB\u21DD\u21E4\u21E5\u21F5\u21FD-\u2205\u2207-\u2209\u220B\u220C\u220F-\u2214\u2216-\u2218\u221A\u221D-\u2238\u223A-\u2257\u2259\u225A\u225C\u225F-\u2262\u2264-\u228B\u228D-\u229B\u229D-\u22A5\u22A7-\u22B0\u22B2-\u22BB\u22BD-\u22DB\u22DE-\u22E3\u22E6-\u22F7\u22F9-\u22FE\u2305\u2306\u2308-\u2310\u2312\u2313\u2315\u2316\u231C-\u231F\u2322\u2323\u232D\u232E\u2336\u233D\u233F\u237C\u23B0\u23B1\u23B4-\u23B6\u23DC-\u23DF\u23E2\u23E7\u2423\u24C8\u2500\u2502\u250C\u2510\u2514\u2518\u251C\u2524\u252C\u2534\u253C\u2550-\u256C\u2580\u2584\u2588\u2591-\u2593\u25A1\u25AA\u25AB\u25AD\u25AE\u25B1\u25B3-\u25B5\u25B8\u25B9\u25BD-\u25BF\u25C2\u25C3\u25CA\u25CB\u25EC\u25EF\u25F8-\u25FC\u2605\u2606\u260E\u2640\u2642\u2660\u2663\u2665\u2666\u266A\u266D-\u266F\u2713\u2717\u2720\u2736\u2758\u2772\u2773\u27C8\u27C9\u27E6-\u27ED\u27F5-\u27FA\u27FC\u27FF\u2902-\u2905\u290C-\u2913\u2916\u2919-\u2920\u2923-\u292A\u2933\u2935-\u2939\u293C\u293D\u2945\u2948-\u294B\u294E-\u2976\u2978\u2979\u297B-\u297F\u2985\u2986\u298B-\u2996\u299A\u299C\u299D\u29A4-\u29B7\u29B9\u29BB\u29BC\u29BE-\u29C5\u29C9\u29CD-\u29D0\u29DC-\u29DE\u29E3-\u29E5\u29EB\u29F4\u29F6\u2A00-\u2A02\u2A04\u2A06\u2A0C\u2A0D\u2A10-\u2A17\u2A22-\u2A27\u2A29\u2A2A\u2A2D-\u2A31\u2A33-\u2A3C\u2A3F\u2A40\u2A42-\u2A4D\u2A50\u2A53-\u2A58\u2A5A-\u2A5D\u2A5F\u2A66\u2A6A\u2A6D-\u2A75\u2A77-\u2A9A\u2A9D-\u2AA2\u2AA4-\u2AB0\u2AB3-\u2AC8\u2ACB\u2ACC\u2ACF-\u2ADB\u2AE4\u2AE6-\u2AE9\u2AEB-\u2AF3\u2AFD\uFB00-\uFB04]|\uD835[\uDC9C\uDC9E\uDC9F\uDCA2\uDCA5\uDCA6\uDCA9-\uDCAC\uDCAE-\uDCB9\uDCBB\uDCBD-\uDCC3\uDCC5-\uDCCF\uDD04\uDD05\uDD07-\uDD0A\uDD0D-\uDD14\uDD16-\uDD1C\uDD1E-\uDD39\uDD3B-\uDD3E\uDD40-\uDD44\uDD46\uDD4A-\uDD50\uDD52-\uDD6B]/g,
            d = {
              "­": "shy",
              "‌": "zwnj",
              "‍": "zwj",
              "‎": "lrm",
              "⁣": "ic",
              "⁢": "it",
              "⁡": "af",
              "‏": "rlm",
              "​": "ZeroWidthSpace",
              "⁠": "NoBreak",
              "̑": "DownBreve",
              "⃛": "tdot",
              "⃜": "DotDot",
              "	": "Tab",
              "\n": "NewLine",
              " ": "puncsp",
              " ": "MediumSpace",
              " ": "thinsp",
              " ": "hairsp",
              " ": "emsp13",
              " ": "ensp",
              " ": "emsp14",
              " ": "emsp",
              " ": "numsp",
              " ": "nbsp",
              "  ": "ThickSpace",
              "‾": "oline",
              _: "lowbar",
              "‐": "dash",
              "–": "ndash",
              "—": "mdash",
              "―": "horbar",
              ",": "comma",
              ";": "semi",
              "⁏": "bsemi",
              ":": "colon",
              "⩴": "Colone",
              "!": "excl",
              "¡": "iexcl",
              "?": "quest",
              "¿": "iquest",
              ".": "period",
              "‥": "nldr",
              "…": "mldr",
              "·": "middot",
              "'": "apos",
              "‘": "lsquo",
              "’": "rsquo",
              "‚": "sbquo",
              "‹": "lsaquo",
              "›": "rsaquo",
              '"': "quot",
              "“": "ldquo",
              "”": "rdquo",
              "„": "bdquo",
              "«": "laquo",
              "»": "raquo",
              "(": "lpar",
              ")": "rpar",
              "[": "lsqb",
              "]": "rsqb",
              "{": "lcub",
              "}": "rcub",
              "⌈": "lceil",
              "⌉": "rceil",
              "⌊": "lfloor",
              "⌋": "rfloor",
              "⦅": "lopar",
              "⦆": "ropar",
              "⦋": "lbrke",
              "⦌": "rbrke",
              "⦍": "lbrkslu",
              "⦎": "rbrksld",
              "⦏": "lbrksld",
              "⦐": "rbrkslu",
              "⦑": "langd",
              "⦒": "rangd",
              "⦓": "lparlt",
              "⦔": "rpargt",
              "⦕": "gtlPar",
              "⦖": "ltrPar",
              "⟦": "lobrk",
              "⟧": "robrk",
              "⟨": "lang",
              "⟩": "rang",
              "⟪": "Lang",
              "⟫": "Rang",
              "⟬": "loang",
              "⟭": "roang",
              "❲": "lbbrk",
              "❳": "rbbrk",
              "‖": "Vert",
              "§": "sect",
              "¶": "para",
              "@": "commat",
              "*": "ast",
              "/": "sol",
              undefined: null,
              "&": "amp",
              "#": "num",
              "%": "percnt",
              "‰": "permil",
              "‱": "pertenk",
              "†": "dagger",
              "‡": "Dagger",
              "•": "bull",
              "⁃": "hybull",
              "′": "prime",
              "″": "Prime",
              "‴": "tprime",
              "⁗": "qprime",
              "‵": "bprime",
              "⁁": "caret",
              "`": "grave",
              "´": "acute",
              "˜": "tilde",
              "^": "Hat",
              "¯": "macr",
              "˘": "breve",
              "˙": "dot",
              "¨": "die",
              "˚": "ring",
              "˝": "dblac",
              "¸": "cedil",
              "˛": "ogon",
              ˆ: "circ",
              ˇ: "caron",
              "°": "deg",
              "©": "copy",
              "®": "reg",
              "℗": "copysr",
              "℘": "wp",
              "℞": "rx",
              "℧": "mho",
              "℩": "iiota",
              "←": "larr",
              "↚": "nlarr",
              "→": "rarr",
              "↛": "nrarr",
              "↑": "uarr",
              "↓": "darr",
              "↔": "harr",
              "↮": "nharr",
              "↕": "varr",
              "↖": "nwarr",
              "↗": "nearr",
              "↘": "searr",
              "↙": "swarr",
              "↝": "rarrw",
              "↝̸": "nrarrw",
              "↞": "Larr",
              "↟": "Uarr",
              "↠": "Rarr",
              "↡": "Darr",
              "↢": "larrtl",
              "↣": "rarrtl",
              "↤": "mapstoleft",
              "↥": "mapstoup",
              "↦": "map",
              "↧": "mapstodown",
              "↩": "larrhk",
              "↪": "rarrhk",
              "↫": "larrlp",
              "↬": "rarrlp",
              "↭": "harrw",
              "↰": "lsh",
              "↱": "rsh",
              "↲": "ldsh",
              "↳": "rdsh",
              "↵": "crarr",
              "↶": "cularr",
              "↷": "curarr",
              "↺": "olarr",
              "↻": "orarr",
              "↼": "lharu",
              "↽": "lhard",
              "↾": "uharr",
              "↿": "uharl",
              "⇀": "rharu",
              "⇁": "rhard",
              "⇂": "dharr",
              "⇃": "dharl",
              "⇄": "rlarr",
              "⇅": "udarr",
              "⇆": "lrarr",
              "⇇": "llarr",
              "⇈": "uuarr",
              "⇉": "rrarr",
              "⇊": "ddarr",
              "⇋": "lrhar",
              "⇌": "rlhar",
              "⇐": "lArr",
              "⇍": "nlArr",
              "⇑": "uArr",
              "⇒": "rArr",
              "⇏": "nrArr",
              "⇓": "dArr",
              "⇔": "iff",
              "⇎": "nhArr",
              "⇕": "vArr",
              "⇖": "nwArr",
              "⇗": "neArr",
              "⇘": "seArr",
              "⇙": "swArr",
              "⇚": "lAarr",
              "⇛": "rAarr",
              "⇝": "zigrarr",
              "⇤": "larrb",
              "⇥": "rarrb",
              "⇵": "duarr",
              "⇽": "loarr",
              "⇾": "roarr",
              "⇿": "hoarr",
              "∀": "forall",
              "∁": "comp",
              "∂": "part",
              "∂̸": "npart",
              "∃": "exist",
              "∄": "nexist",
              "∅": "empty",
              "∇": "Del",
              "∈": "in",
              "∉": "notin",
              "∋": "ni",
              "∌": "notni",
              "϶": "bepsi",
              "∏": "prod",
              "∐": "coprod",
              "∑": "sum",
              "+": "plus",
              "±": "pm",
              "÷": "div",
              "×": "times",
              "<": "lt",
              "≮": "nlt",
              "<⃒": "nvlt",
              "=": "equals",
              "≠": "ne",
              "=⃥": "bne",
              "⩵": "Equal",
              ">": "gt",
              "≯": "ngt",
              ">⃒": "nvgt",
              "¬": "not",
              "|": "vert",
              "¦": "brvbar",
              "−": "minus",
              "∓": "mp",
              "∔": "plusdo",
              "⁄": "frasl",
              "∖": "setmn",
              "∗": "lowast",
              "∘": "compfn",
              "√": "Sqrt",
              "∝": "prop",
              "∞": "infin",
              "∟": "angrt",
              "∠": "ang",
              "∠⃒": "nang",
              "∡": "angmsd",
              "∢": "angsph",
              "∣": "mid",
              "∤": "nmid",
              "∥": "par",
              "∦": "npar",
              "∧": "and",
              "∨": "or",
              "∩": "cap",
              "∩︀": "caps",
              "∪": "cup",
              "∪︀": "cups",
              "∫": "int",
              "∬": "Int",
              "∭": "tint",
              "⨌": "qint",
              "∮": "oint",
              "∯": "Conint",
              "∰": "Cconint",
              "∱": "cwint",
              "∲": "cwconint",
              "∳": "awconint",
              "∴": "there4",
              "∵": "becaus",
              "∶": "ratio",
              "∷": "Colon",
              "∸": "minusd",
              "∺": "mDDot",
              "∻": "homtht",
              "∼": "sim",
              "≁": "nsim",
              "∼⃒": "nvsim",
              "∽": "bsim",
              "∽̱": "race",
              "∾": "ac",
              "∾̳": "acE",
              "∿": "acd",
              "≀": "wr",
              "≂": "esim",
              "≂̸": "nesim",
              "≃": "sime",
              "≄": "nsime",
              "≅": "cong",
              "≇": "ncong",
              "≆": "simne",
              "≈": "ap",
              "≉": "nap",
              "≊": "ape",
              "≋": "apid",
              "≋̸": "napid",
              "≌": "bcong",
              "≍": "CupCap",
              "≭": "NotCupCap",
              "≍⃒": "nvap",
              "≎": "bump",
              "≎̸": "nbump",
              "≏": "bumpe",
              "≏̸": "nbumpe",
              "≐": "doteq",
              "≐̸": "nedot",
              "≑": "eDot",
              "≒": "efDot",
              "≓": "erDot",
              "≔": "colone",
              "≕": "ecolon",
              "≖": "ecir",
              "≗": "cire",
              "≙": "wedgeq",
              "≚": "veeeq",
              "≜": "trie",
              "≟": "equest",
              "≡": "equiv",
              "≢": "nequiv",
              "≡⃥": "bnequiv",
              "≤": "le",
              "≰": "nle",
              "≤⃒": "nvle",
              "≥": "ge",
              "≱": "nge",
              "≥⃒": "nvge",
              "≦": "lE",
              "≦̸": "nlE",
              "≧": "gE",
              "≧̸": "ngE",
              "≨︀": "lvnE",
              "≨": "lnE",
              "≩": "gnE",
              "≩︀": "gvnE",
              "≪": "ll",
              "≪̸": "nLtv",
              "≪⃒": "nLt",
              "≫": "gg",
              "≫̸": "nGtv",
              "≫⃒": "nGt",
              "≬": "twixt",
              "≲": "lsim",
              "≴": "nlsim",
              "≳": "gsim",
              "≵": "ngsim",
              "≶": "lg",
              "≸": "ntlg",
              "≷": "gl",
              "≹": "ntgl",
              "≺": "pr",
              "⊀": "npr",
              "≻": "sc",
              "⊁": "nsc",
              "≼": "prcue",
              "⋠": "nprcue",
              "≽": "sccue",
              "⋡": "nsccue",
              "≾": "prsim",
              "≿": "scsim",
              "≿̸": "NotSucceedsTilde",
              "⊂": "sub",
              "⊄": "nsub",
              "⊂⃒": "vnsub",
              "⊃": "sup",
              "⊅": "nsup",
              "⊃⃒": "vnsup",
              "⊆": "sube",
              "⊈": "nsube",
              "⊇": "supe",
              "⊉": "nsupe",
              "⊊︀": "vsubne",
              "⊊": "subne",
              "⊋︀": "vsupne",
              "⊋": "supne",
              "⊍": "cupdot",
              "⊎": "uplus",
              "⊏": "sqsub",
              "⊏̸": "NotSquareSubset",
              "⊐": "sqsup",
              "⊐̸": "NotSquareSuperset",
              "⊑": "sqsube",
              "⋢": "nsqsube",
              "⊒": "sqsupe",
              "⋣": "nsqsupe",
              "⊓": "sqcap",
              "⊓︀": "sqcaps",
              "⊔": "sqcup",
              "⊔︀": "sqcups",
              "⊕": "oplus",
              "⊖": "ominus",
              "⊗": "otimes",
              "⊘": "osol",
              "⊙": "odot",
              "⊚": "ocir",
              "⊛": "oast",
              "⊝": "odash",
              "⊞": "plusb",
              "⊟": "minusb",
              "⊠": "timesb",
              "⊡": "sdotb",
              "⊢": "vdash",
              "⊬": "nvdash",
              "⊣": "dashv",
              "⊤": "top",
              "⊥": "bot",
              "⊧": "models",
              "⊨": "vDash",
              "⊭": "nvDash",
              "⊩": "Vdash",
              "⊮": "nVdash",
              "⊪": "Vvdash",
              "⊫": "VDash",
              "⊯": "nVDash",
              "⊰": "prurel",
              "⊲": "vltri",
              "⋪": "nltri",
              "⊳": "vrtri",
              "⋫": "nrtri",
              "⊴": "ltrie",
              "⋬": "nltrie",
              "⊴⃒": "nvltrie",
              "⊵": "rtrie",
              "⋭": "nrtrie",
              "⊵⃒": "nvrtrie",
              "⊶": "origof",
              "⊷": "imof",
              "⊸": "mumap",
              "⊹": "hercon",
              "⊺": "intcal",
              "⊻": "veebar",
              "⊽": "barvee",
              "⊾": "angrtvb",
              "⊿": "lrtri",
              "⋀": "Wedge",
              "⋁": "Vee",
              "⋂": "xcap",
              "⋃": "xcup",
              "⋄": "diam",
              "⋅": "sdot",
              "⋆": "Star",
              "⋇": "divonx",
              "⋈": "bowtie",
              "⋉": "ltimes",
              "⋊": "rtimes",
              "⋋": "lthree",
              "⋌": "rthree",
              "⋍": "bsime",
              "⋎": "cuvee",
              "⋏": "cuwed",
              "⋐": "Sub",
              "⋑": "Sup",
              "⋒": "Cap",
              "⋓": "Cup",
              "⋔": "fork",
              "⋕": "epar",
              "⋖": "ltdot",
              "⋗": "gtdot",
              "⋘": "Ll",
              "⋘̸": "nLl",
              "⋙": "Gg",
              "⋙̸": "nGg",
              "⋚︀": "lesg",
              "⋚": "leg",
              "⋛": "gel",
              "⋛︀": "gesl",
              "⋞": "cuepr",
              "⋟": "cuesc",
              "⋦": "lnsim",
              "⋧": "gnsim",
              "⋨": "prnsim",
              "⋩": "scnsim",
              "⋮": "vellip",
              "⋯": "ctdot",
              "⋰": "utdot",
              "⋱": "dtdot",
              "⋲": "disin",
              "⋳": "isinsv",
              "⋴": "isins",
              "⋵": "isindot",
              "⋵̸": "notindot",
              "⋶": "notinvc",
              "⋷": "notinvb",
              "⋹": "isinE",
              "⋹̸": "notinE",
              "⋺": "nisd",
              "⋻": "xnis",
              "⋼": "nis",
              "⋽": "notnivc",
              "⋾": "notnivb",
              "⌅": "barwed",
              "⌆": "Barwed",
              "⌌": "drcrop",
              "⌍": "dlcrop",
              "⌎": "urcrop",
              "⌏": "ulcrop",
              "⌐": "bnot",
              "⌒": "profline",
              "⌓": "profsurf",
              "⌕": "telrec",
              "⌖": "target",
              "⌜": "ulcorn",
              "⌝": "urcorn",
              "⌞": "dlcorn",
              "⌟": "drcorn",
              "⌢": "frown",
              "⌣": "smile",
              "⌭": "cylcty",
              "⌮": "profalar",
              "⌶": "topbot",
              "⌽": "ovbar",
              "⌿": "solbar",
              "⍼": "angzarr",
              "⎰": "lmoust",
              "⎱": "rmoust",
              "⎴": "tbrk",
              "⎵": "bbrk",
              "⎶": "bbrktbrk",
              "⏜": "OverParenthesis",
              "⏝": "UnderParenthesis",
              "⏞": "OverBrace",
              "⏟": "UnderBrace",
              "⏢": "trpezium",
              "⏧": "elinters",
              "␣": "blank",
              "─": "boxh",
              "│": "boxv",
              "┌": "boxdr",
              "┐": "boxdl",
              "└": "boxur",
              "┘": "boxul",
              "├": "boxvr",
              "┤": "boxvl",
              "┬": "boxhd",
              "┴": "boxhu",
              "┼": "boxvh",
              "═": "boxH",
              "║": "boxV",
              "╒": "boxdR",
              "╓": "boxDr",
              "╔": "boxDR",
              "╕": "boxdL",
              "╖": "boxDl",
              "╗": "boxDL",
              "╘": "boxuR",
              "╙": "boxUr",
              "╚": "boxUR",
              "╛": "boxuL",
              "╜": "boxUl",
              "╝": "boxUL",
              "╞": "boxvR",
              "╟": "boxVr",
              "╠": "boxVR",
              "╡": "boxvL",
              "╢": "boxVl",
              "╣": "boxVL",
              "╤": "boxHd",
              "╥": "boxhD",
              "╦": "boxHD",
              "╧": "boxHu",
              "╨": "boxhU",
              "╩": "boxHU",
              "╪": "boxvH",
              "╫": "boxVh",
              "╬": "boxVH",
              "▀": "uhblk",
              "▄": "lhblk",
              "█": "block",
              "░": "blk14",
              "▒": "blk12",
              "▓": "blk34",
              "□": "squ",
              "▪": "squf",
              "▫": "EmptyVerySmallSquare",
              "▭": "rect",
              "▮": "marker",
              "▱": "fltns",
              "△": "xutri",
              "▴": "utrif",
              "▵": "utri",
              "▸": "rtrif",
              "▹": "rtri",
              "▽": "xdtri",
              "▾": "dtrif",
              "▿": "dtri",
              "◂": "ltrif",
              "◃": "ltri",
              "◊": "loz",
              "○": "cir",
              "◬": "tridot",
              "◯": "xcirc",
              "◸": "ultri",
              "◹": "urtri",
              "◺": "lltri",
              "◻": "EmptySmallSquare",
              "◼": "FilledSmallSquare",
              "★": "starf",
              "☆": "star",
              "☎": "phone",
              "♀": "female",
              "♂": "male",
              "♠": "spades",
              "♣": "clubs",
              "♥": "hearts",
              "♦": "diams",
              "♪": "sung",
              "✓": "check",
              "✗": "cross",
              "✠": "malt",
              "✶": "sext",
              "❘": "VerticalSeparator",
              "⟈": "bsolhsub",
              "⟉": "suphsol",
              "⟵": "xlarr",
              "⟶": "xrarr",
              "⟷": "xharr",
              "⟸": "xlArr",
              "⟹": "xrArr",
              "⟺": "xhArr",
              "⟼": "xmap",
              "⟿": "dzigrarr",
              "⤂": "nvlArr",
              "⤃": "nvrArr",
              "⤄": "nvHarr",
              "⤅": "Map",
              "⤌": "lbarr",
              "⤍": "rbarr",
              "⤎": "lBarr",
              "⤏": "rBarr",
              "⤐": "RBarr",
              "⤑": "DDotrahd",
              "⤒": "UpArrowBar",
              "⤓": "DownArrowBar",
              "⤖": "Rarrtl",
              "⤙": "latail",
              "⤚": "ratail",
              "⤛": "lAtail",
              "⤜": "rAtail",
              "⤝": "larrfs",
              "⤞": "rarrfs",
              "⤟": "larrbfs",
              "⤠": "rarrbfs",
              "⤣": "nwarhk",
              "⤤": "nearhk",
              "⤥": "searhk",
              "⤦": "swarhk",
              "⤧": "nwnear",
              "⤨": "toea",
              "⤩": "tosa",
              "⤪": "swnwar",
              "⤳": "rarrc",
              "⤳̸": "nrarrc",
              "⤵": "cudarrr",
              "⤶": "ldca",
              "⤷": "rdca",
              "⤸": "cudarrl",
              "⤹": "larrpl",
              "⤼": "curarrm",
              "⤽": "cularrp",
              "⥅": "rarrpl",
              "⥈": "harrcir",
              "⥉": "Uarrocir",
              "⥊": "lurdshar",
              "⥋": "ldrushar",
              "⥎": "LeftRightVector",
              "⥏": "RightUpDownVector",
              "⥐": "DownLeftRightVector",
              "⥑": "LeftUpDownVector",
              "⥒": "LeftVectorBar",
              "⥓": "RightVectorBar",
              "⥔": "RightUpVectorBar",
              "⥕": "RightDownVectorBar",
              "⥖": "DownLeftVectorBar",
              "⥗": "DownRightVectorBar",
              "⥘": "LeftUpVectorBar",
              "⥙": "LeftDownVectorBar",
              "⥚": "LeftTeeVector",
              "⥛": "RightTeeVector",
              "⥜": "RightUpTeeVector",
              "⥝": "RightDownTeeVector",
              "⥞": "DownLeftTeeVector",
              "⥟": "DownRightTeeVector",
              "⥠": "LeftUpTeeVector",
              "⥡": "LeftDownTeeVector",
              "⥢": "lHar",
              "⥣": "uHar",
              "⥤": "rHar",
              "⥥": "dHar",
              "⥦": "luruhar",
              "⥧": "ldrdhar",
              "⥨": "ruluhar",
              "⥩": "rdldhar",
              "⥪": "lharul",
              "⥫": "llhard",
              "⥬": "rharul",
              "⥭": "lrhard",
              "⥮": "udhar",
              "⥯": "duhar",
              "⥰": "RoundImplies",
              "⥱": "erarr",
              "⥲": "simrarr",
              "⥳": "larrsim",
              "⥴": "rarrsim",
              "⥵": "rarrap",
              "⥶": "ltlarr",
              "⥸": "gtrarr",
              "⥹": "subrarr",
              "⥻": "suplarr",
              "⥼": "lfisht",
              "⥽": "rfisht",
              "⥾": "ufisht",
              "⥿": "dfisht",
              "⦚": "vzigzag",
              "⦜": "vangrt",
              "⦝": "angrtvbd",
              "⦤": "ange",
              "⦥": "range",
              "⦦": "dwangle",
              "⦧": "uwangle",
              "⦨": "angmsdaa",
              "⦩": "angmsdab",
              "⦪": "angmsdac",
              "⦫": "angmsdad",
              "⦬": "angmsdae",
              "⦭": "angmsdaf",
              "⦮": "angmsdag",
              "⦯": "angmsdah",
              "⦰": "bemptyv",
              "⦱": "demptyv",
              "⦲": "cemptyv",
              "⦳": "raemptyv",
              "⦴": "laemptyv",
              "⦵": "ohbar",
              "⦶": "omid",
              "⦷": "opar",
              "⦹": "operp",
              "⦻": "olcross",
              "⦼": "odsold",
              "⦾": "olcir",
              "⦿": "ofcir",
              "⧀": "olt",
              "⧁": "ogt",
              "⧂": "cirscir",
              "⧃": "cirE",
              "⧄": "solb",
              "⧅": "bsolb",
              "⧉": "boxbox",
              "⧍": "trisb",
              "⧎": "rtriltri",
              "⧏": "LeftTriangleBar",
              "⧏̸": "NotLeftTriangleBar",
              "⧐": "RightTriangleBar",
              "⧐̸": "NotRightTriangleBar",
              "⧜": "iinfin",
              "⧝": "infintie",
              "⧞": "nvinfin",
              "⧣": "eparsl",
              "⧤": "smeparsl",
              "⧥": "eqvparsl",
              "⧫": "lozf",
              "⧴": "RuleDelayed",
              "⧶": "dsol",
              "⨀": "xodot",
              "⨁": "xoplus",
              "⨂": "xotime",
              "⨄": "xuplus",
              "⨆": "xsqcup",
              "⨍": "fpartint",
              "⨐": "cirfnint",
              "⨑": "awint",
              "⨒": "rppolint",
              "⨓": "scpolint",
              "⨔": "npolint",
              "⨕": "pointint",
              "⨖": "quatint",
              "⨗": "intlarhk",
              "⨢": "pluscir",
              "⨣": "plusacir",
              "⨤": "simplus",
              "⨥": "plusdu",
              "⨦": "plussim",
              "⨧": "plustwo",
              "⨩": "mcomma",
              "⨪": "minusdu",
              "⨭": "loplus",
              "⨮": "roplus",
              "⨯": "Cross",
              "⨰": "timesd",
              "⨱": "timesbar",
              "⨳": "smashp",
              "⨴": "lotimes",
              "⨵": "rotimes",
              "⨶": "otimesas",
              "⨷": "Otimes",
              "⨸": "odiv",
              "⨹": "triplus",
              "⨺": "triminus",
              "⨻": "tritime",
              "⨼": "iprod",
              "⨿": "amalg",
              "⩀": "capdot",
              "⩂": "ncup",
              "⩃": "ncap",
              "⩄": "capand",
              "⩅": "cupor",
              "⩆": "cupcap",
              "⩇": "capcup",
              "⩈": "cupbrcap",
              "⩉": "capbrcup",
              "⩊": "cupcup",
              "⩋": "capcap",
              "⩌": "ccups",
              "⩍": "ccaps",
              "⩐": "ccupssm",
              "⩓": "And",
              "⩔": "Or",
              "⩕": "andand",
              "⩖": "oror",
              "⩗": "orslope",
              "⩘": "andslope",
              "⩚": "andv",
              "⩛": "orv",
              "⩜": "andd",
              "⩝": "ord",
              "⩟": "wedbar",
              "⩦": "sdote",
              "⩪": "simdot",
              "⩭": "congdot",
              "⩭̸": "ncongdot",
              "⩮": "easter",
              "⩯": "apacir",
              "⩰": "apE",
              "⩰̸": "napE",
              "⩱": "eplus",
              "⩲": "pluse",
              "⩳": "Esim",
              "⩷": "eDDot",
              "⩸": "equivDD",
              "⩹": "ltcir",
              "⩺": "gtcir",
              "⩻": "ltquest",
              "⩼": "gtquest",
              "⩽": "les",
              "⩽̸": "nles",
              "⩾": "ges",
              "⩾̸": "nges",
              "⩿": "lesdot",
              "⪀": "gesdot",
              "⪁": "lesdoto",
              "⪂": "gesdoto",
              "⪃": "lesdotor",
              "⪄": "gesdotol",
              "⪅": "lap",
              "⪆": "gap",
              "⪇": "lne",
              "⪈": "gne",
              "⪉": "lnap",
              "⪊": "gnap",
              "⪋": "lEg",
              "⪌": "gEl",
              "⪍": "lsime",
              "⪎": "gsime",
              "⪏": "lsimg",
              "⪐": "gsiml",
              "⪑": "lgE",
              "⪒": "glE",
              "⪓": "lesges",
              "⪔": "gesles",
              "⪕": "els",
              "⪖": "egs",
              "⪗": "elsdot",
              "⪘": "egsdot",
              "⪙": "el",
              "⪚": "eg",
              "⪝": "siml",
              "⪞": "simg",
              "⪟": "simlE",
              "⪠": "simgE",
              "⪡": "LessLess",
              "⪡̸": "NotNestedLessLess",
              "⪢": "GreaterGreater",
              "⪢̸": "NotNestedGreaterGreater",
              "⪤": "glj",
              "⪥": "gla",
              "⪦": "ltcc",
              "⪧": "gtcc",
              "⪨": "lescc",
              "⪩": "gescc",
              "⪪": "smt",
              "⪫": "lat",
              "⪬": "smte",
              "⪬︀": "smtes",
              "⪭": "late",
              "⪭︀": "lates",
              "⪮": "bumpE",
              "⪯": "pre",
              "⪯̸": "npre",
              "⪰": "sce",
              "⪰̸": "nsce",
              "⪳": "prE",
              "⪴": "scE",
              "⪵": "prnE",
              "⪶": "scnE",
              "⪷": "prap",
              "⪸": "scap",
              "⪹": "prnap",
              "⪺": "scnap",
              "⪻": "Pr",
              "⪼": "Sc",
              "⪽": "subdot",
              "⪾": "supdot",
              "⪿": "subplus",
              "⫀": "supplus",
              "⫁": "submult",
              "⫂": "supmult",
              "⫃": "subedot",
              "⫄": "supedot",
              "⫅": "subE",
              "⫅̸": "nsubE",
              "⫆": "supE",
              "⫆̸": "nsupE",
              "⫇": "subsim",
              "⫈": "supsim",
              "⫋︀": "vsubnE",
              "⫋": "subnE",
              "⫌︀": "vsupnE",
              "⫌": "supnE",
              "⫏": "csub",
              "⫐": "csup",
              "⫑": "csube",
              "⫒": "csupe",
              "⫓": "subsup",
              "⫔": "supsub",
              "⫕": "subsub",
              "⫖": "supsup",
              "⫗": "suphsub",
              "⫘": "supdsub",
              "⫙": "forkv",
              "⫚": "topfork",
              "⫛": "mlcp",
              "⫤": "Dashv",
              "⫦": "Vdashl",
              "⫧": "Barv",
              "⫨": "vBar",
              "⫩": "vBarv",
              "⫫": "Vbar",
              "⫬": "Not",
              "⫭": "bNot",
              "⫮": "rnmid",
              "⫯": "cirmid",
              "⫰": "midcir",
              "⫱": "topcir",
              "⫲": "nhpar",
              "⫳": "parsim",
              "⫽": "parsl",
              "⫽⃥": "nparsl",
              "♭": "flat",
              "♮": "natur",
              "♯": "sharp",
              "¤": "curren",
              "¢": "cent",
              $: "dollar",
              "£": "pound",
              "¥": "yen",
              "€": "euro",
              "¹": "sup1",
              "½": "half",
              "⅓": "frac13",
              "¼": "frac14",
              "⅕": "frac15",
              "⅙": "frac16",
              "⅛": "frac18",
              "²": "sup2",
              "⅔": "frac23",
              "⅖": "frac25",
              "³": "sup3",
              "¾": "frac34",
              "⅗": "frac35",
              "⅜": "frac38",
              "⅘": "frac45",
              "⅚": "frac56",
              "⅝": "frac58",
              "⅞": "frac78",
              "𝒶": "ascr",
              "𝕒": "aopf",
              "𝔞": "afr",
              "𝔸": "Aopf",
              "𝔄": "Afr",
              "𝒜": "Ascr",
              ª: "ordf",
              á: "aacute",
              Á: "Aacute",
              à: "agrave",
              À: "Agrave",
              ă: "abreve",
              Ă: "Abreve",
              â: "acirc",
              Â: "Acirc",
              å: "aring",
              Å: "angst",
              ä: "auml",
              Ä: "Auml",
              ã: "atilde",
              Ã: "Atilde",
              ą: "aogon",
              Ą: "Aogon",
              ā: "amacr",
              Ā: "Amacr",
              æ: "aelig",
              Æ: "AElig",
              "𝒷": "bscr",
              "𝕓": "bopf",
              "𝔟": "bfr",
              "𝔹": "Bopf",
              ℬ: "Bscr",
              "𝔅": "Bfr",
              "𝔠": "cfr",
              "𝒸": "cscr",
              "𝕔": "copf",
              ℭ: "Cfr",
              "𝒞": "Cscr",
              ℂ: "Copf",
              ć: "cacute",
              Ć: "Cacute",
              ĉ: "ccirc",
              Ĉ: "Ccirc",
              č: "ccaron",
              Č: "Ccaron",
              ċ: "cdot",
              Ċ: "Cdot",
              ç: "ccedil",
              Ç: "Ccedil",
              "℅": "incare",
              "𝔡": "dfr",
              ⅆ: "dd",
              "𝕕": "dopf",
              "𝒹": "dscr",
              "𝒟": "Dscr",
              "𝔇": "Dfr",
              ⅅ: "DD",
              "𝔻": "Dopf",
              ď: "dcaron",
              Ď: "Dcaron",
              đ: "dstrok",
              Đ: "Dstrok",
              ð: "eth",
              Ð: "ETH",
              ⅇ: "ee",
              ℯ: "escr",
              "𝔢": "efr",
              "𝕖": "eopf",
              ℰ: "Escr",
              "𝔈": "Efr",
              "𝔼": "Eopf",
              é: "eacute",
              É: "Eacute",
              è: "egrave",
              È: "Egrave",
              ê: "ecirc",
              Ê: "Ecirc",
              ě: "ecaron",
              Ě: "Ecaron",
              ë: "euml",
              Ë: "Euml",
              ė: "edot",
              Ė: "Edot",
              ę: "eogon",
              Ę: "Eogon",
              ē: "emacr",
              Ē: "Emacr",
              "𝔣": "ffr",
              "𝕗": "fopf",
              "𝒻": "fscr",
              "𝔉": "Ffr",
              "𝔽": "Fopf",
              ℱ: "Fscr",
              ﬀ: "fflig",
              ﬃ: "ffilig",
              ﬄ: "ffllig",
              ﬁ: "filig",
              fj: "fjlig",
              ﬂ: "fllig",
              ƒ: "fnof",
              ℊ: "gscr",
              "𝕘": "gopf",
              "𝔤": "gfr",
              "𝒢": "Gscr",
              "𝔾": "Gopf",
              "𝔊": "Gfr",
              ǵ: "gacute",
              ğ: "gbreve",
              Ğ: "Gbreve",
              ĝ: "gcirc",
              Ĝ: "Gcirc",
              ġ: "gdot",
              Ġ: "Gdot",
              Ģ: "Gcedil",
              "𝔥": "hfr",
              ℎ: "planckh",
              "𝒽": "hscr",
              "𝕙": "hopf",
              ℋ: "Hscr",
              ℌ: "Hfr",
              ℍ: "Hopf",
              ĥ: "hcirc",
              Ĥ: "Hcirc",
              ℏ: "hbar",
              ħ: "hstrok",
              Ħ: "Hstrok",
              "𝕚": "iopf",
              "𝔦": "ifr",
              "𝒾": "iscr",
              ⅈ: "ii",
              "𝕀": "Iopf",
              ℐ: "Iscr",
              ℑ: "Im",
              í: "iacute",
              Í: "Iacute",
              ì: "igrave",
              Ì: "Igrave",
              î: "icirc",
              Î: "Icirc",
              ï: "iuml",
              Ï: "Iuml",
              ĩ: "itilde",
              Ĩ: "Itilde",
              İ: "Idot",
              į: "iogon",
              Į: "Iogon",
              ī: "imacr",
              Ī: "Imacr",
              ĳ: "ijlig",
              Ĳ: "IJlig",
              ı: "imath",
              "𝒿": "jscr",
              "𝕛": "jopf",
              "𝔧": "jfr",
              "𝒥": "Jscr",
              "𝔍": "Jfr",
              "𝕁": "Jopf",
              ĵ: "jcirc",
              Ĵ: "Jcirc",
              ȷ: "jmath",
              "𝕜": "kopf",
              "𝓀": "kscr",
              "𝔨": "kfr",
              "𝒦": "Kscr",
              "𝕂": "Kopf",
              "𝔎": "Kfr",
              ķ: "kcedil",
              Ķ: "Kcedil",
              "𝔩": "lfr",
              "𝓁": "lscr",
              ℓ: "ell",
              "𝕝": "lopf",
              ℒ: "Lscr",
              "𝔏": "Lfr",
              "𝕃": "Lopf",
              ĺ: "lacute",
              Ĺ: "Lacute",
              ľ: "lcaron",
              Ľ: "Lcaron",
              ļ: "lcedil",
              Ļ: "Lcedil",
              ł: "lstrok",
              Ł: "Lstrok",
              ŀ: "lmidot",
              Ŀ: "Lmidot",
              "𝔪": "mfr",
              "𝕞": "mopf",
              "𝓂": "mscr",
              "𝔐": "Mfr",
              "𝕄": "Mopf",
              ℳ: "Mscr",
              "𝔫": "nfr",
              "𝕟": "nopf",
              "𝓃": "nscr",
              ℕ: "Nopf",
              "𝒩": "Nscr",
              "𝔑": "Nfr",
              ń: "nacute",
              Ń: "Nacute",
              ň: "ncaron",
              Ň: "Ncaron",
              ñ: "ntilde",
              Ñ: "Ntilde",
              ņ: "ncedil",
              Ņ: "Ncedil",
              "№": "numero",
              ŋ: "eng",
              Ŋ: "ENG",
              "𝕠": "oopf",
              "𝔬": "ofr",
              ℴ: "oscr",
              "𝒪": "Oscr",
              "𝔒": "Ofr",
              "𝕆": "Oopf",
              º: "ordm",
              ó: "oacute",
              Ó: "Oacute",
              ò: "ograve",
              Ò: "Ograve",
              ô: "ocirc",
              Ô: "Ocirc",
              ö: "ouml",
              Ö: "Ouml",
              ő: "odblac",
              Ő: "Odblac",
              õ: "otilde",
              Õ: "Otilde",
              ø: "oslash",
              Ø: "Oslash",
              ō: "omacr",
              Ō: "Omacr",
              œ: "oelig",
              Œ: "OElig",
              "𝔭": "pfr",
              "𝓅": "pscr",
              "𝕡": "popf",
              ℙ: "Popf",
              "𝔓": "Pfr",
              "𝒫": "Pscr",
              "𝕢": "qopf",
              "𝔮": "qfr",
              "𝓆": "qscr",
              "𝒬": "Qscr",
              "𝔔": "Qfr",
              ℚ: "Qopf",
              ĸ: "kgreen",
              "𝔯": "rfr",
              "𝕣": "ropf",
              "𝓇": "rscr",
              ℛ: "Rscr",
              ℜ: "Re",
              ℝ: "Ropf",
              ŕ: "racute",
              Ŕ: "Racute",
              ř: "rcaron",
              Ř: "Rcaron",
              ŗ: "rcedil",
              Ŗ: "Rcedil",
              "𝕤": "sopf",
              "𝓈": "sscr",
              "𝔰": "sfr",
              "𝕊": "Sopf",
              "𝔖": "Sfr",
              "𝒮": "Sscr",
              "Ⓢ": "oS",
              ś: "sacute",
              Ś: "Sacute",
              ŝ: "scirc",
              Ŝ: "Scirc",
              š: "scaron",
              Š: "Scaron",
              ş: "scedil",
              Ş: "Scedil",
              ß: "szlig",
              "𝔱": "tfr",
              "𝓉": "tscr",
              "𝕥": "topf",
              "𝒯": "Tscr",
              "𝔗": "Tfr",
              "𝕋": "Topf",
              ť: "tcaron",
              Ť: "Tcaron",
              ţ: "tcedil",
              Ţ: "Tcedil",
              "™": "trade",
              ŧ: "tstrok",
              Ŧ: "Tstrok",
              "𝓊": "uscr",
              "𝕦": "uopf",
              "𝔲": "ufr",
              "𝕌": "Uopf",
              "𝔘": "Ufr",
              "𝒰": "Uscr",
              ú: "uacute",
              Ú: "Uacute",
              ù: "ugrave",
              Ù: "Ugrave",
              ŭ: "ubreve",
              Ŭ: "Ubreve",
              û: "ucirc",
              Û: "Ucirc",
              ů: "uring",
              Ů: "Uring",
              ü: "uuml",
              Ü: "Uuml",
              ű: "udblac",
              Ű: "Udblac",
              ũ: "utilde",
              Ũ: "Utilde",
              ų: "uogon",
              Ų: "Uogon",
              ū: "umacr",
              Ū: "Umacr",
              "𝔳": "vfr",
              "𝕧": "vopf",
              "𝓋": "vscr",
              "𝔙": "Vfr",
              "𝕍": "Vopf",
              "𝒱": "Vscr",
              "𝕨": "wopf",
              "𝓌": "wscr",
              "𝔴": "wfr",
              "𝒲": "Wscr",
              "𝕎": "Wopf",
              "𝔚": "Wfr",
              ŵ: "wcirc",
              Ŵ: "Wcirc",
              "𝔵": "xfr",
              "𝓍": "xscr",
              "𝕩": "xopf",
              "𝕏": "Xopf",
              "𝔛": "Xfr",
              "𝒳": "Xscr",
              "𝔶": "yfr",
              "𝓎": "yscr",
              "𝕪": "yopf",
              "𝒴": "Yscr",
              "𝔜": "Yfr",
              "𝕐": "Yopf",
              ý: "yacute",
              Ý: "Yacute",
              ŷ: "ycirc",
              Ŷ: "Ycirc",
              ÿ: "yuml",
              Ÿ: "Yuml",
              "𝓏": "zscr",
              "𝔷": "zfr",
              "𝕫": "zopf",
              ℨ: "Zfr",
              ℤ: "Zopf",
              "𝒵": "Zscr",
              ź: "zacute",
              Ź: "Zacute",
              ž: "zcaron",
              Ž: "Zcaron",
              ż: "zdot",
              Ż: "Zdot",
              Ƶ: "imped",
              þ: "thorn",
              Þ: "THORN",
              ŉ: "napos",
              α: "alpha",
              Α: "Alpha",
              β: "beta",
              Β: "Beta",
              γ: "gamma",
              Γ: "Gamma",
              δ: "delta",
              Δ: "Delta",
              ε: "epsi",
              ϵ: "epsiv",
              Ε: "Epsilon",
              ϝ: "gammad",
              Ϝ: "Gammad",
              ζ: "zeta",
              Ζ: "Zeta",
              η: "eta",
              Η: "Eta",
              θ: "theta",
              ϑ: "thetav",
              Θ: "Theta",
              ι: "iota",
              Ι: "Iota",
              κ: "kappa",
              ϰ: "kappav",
              Κ: "Kappa",
              λ: "lambda",
              Λ: "Lambda",
              μ: "mu",
              µ: "micro",
              Μ: "Mu",
              ν: "nu",
              Ν: "Nu",
              ξ: "xi",
              Ξ: "Xi",
              ο: "omicron",
              Ο: "Omicron",
              π: "pi",
              ϖ: "piv",
              Π: "Pi",
              ρ: "rho",
              ϱ: "rhov",
              Ρ: "Rho",
              σ: "sigma",
              Σ: "Sigma",
              ς: "sigmaf",
              τ: "tau",
              Τ: "Tau",
              υ: "upsi",
              Υ: "Upsilon",
              ϒ: "Upsi",
              φ: "phi",
              ϕ: "phiv",
              Φ: "Phi",
              χ: "chi",
              Χ: "Chi",
              ψ: "psi",
              Ψ: "Psi",
              ω: "omega",
              Ω: "ohm",
              а: "acy",
              А: "Acy",
              б: "bcy",
              Б: "Bcy",
              в: "vcy",
              В: "Vcy",
              г: "gcy",
              Г: "Gcy",
              ѓ: "gjcy",
              Ѓ: "GJcy",
              д: "dcy",
              Д: "Dcy",
              ђ: "djcy",
              Ђ: "DJcy",
              е: "iecy",
              Е: "IEcy",
              ё: "iocy",
              Ё: "IOcy",
              є: "jukcy",
              Є: "Jukcy",
              ж: "zhcy",
              Ж: "ZHcy",
              з: "zcy",
              З: "Zcy",
              ѕ: "dscy",
              Ѕ: "DScy",
              и: "icy",
              И: "Icy",
              і: "iukcy",
              І: "Iukcy",
              ї: "yicy",
              Ї: "YIcy",
              й: "jcy",
              Й: "Jcy",
              ј: "jsercy",
              Ј: "Jsercy",
              к: "kcy",
              К: "Kcy",
              ќ: "kjcy",
              Ќ: "KJcy",
              л: "lcy",
              Л: "Lcy",
              љ: "ljcy",
              Љ: "LJcy",
              м: "mcy",
              М: "Mcy",
              н: "ncy",
              Н: "Ncy",
              њ: "njcy",
              Њ: "NJcy",
              о: "ocy",
              О: "Ocy",
              п: "pcy",
              П: "Pcy",
              р: "rcy",
              Р: "Rcy",
              с: "scy",
              С: "Scy",
              т: "tcy",
              Т: "Tcy",
              ћ: "tshcy",
              Ћ: "TSHcy",
              у: "ucy",
              У: "Ucy",
              ў: "ubrcy",
              Ў: "Ubrcy",
              ф: "fcy",
              Ф: "Fcy",
              х: "khcy",
              Х: "KHcy",
              ц: "tscy",
              Ц: "TScy",
              ч: "chcy",
              Ч: "CHcy",
              џ: "dzcy",
              Џ: "DZcy",
              ш: "shcy",
              Ш: "SHcy",
              щ: "shchcy",
              Щ: "SHCHcy",
              ъ: "hardcy",
              Ъ: "HARDcy",
              ы: "ycy",
              Ы: "Ycy",
              ь: "softcy",
              Ь: "SOFTcy",
              э: "ecy",
              Э: "Ecy",
              ю: "yucy",
              Ю: "YUcy",
              я: "yacy",
              Я: "YAcy",
              ℵ: "aleph",
              ℶ: "beth",
              ℷ: "gimel",
              ℸ: "daleth",
            },
            p = /["&'<>`]/g,
            h = {
              '"': "&quot;",
              "&": "&amp;",
              "'": "&#x27;",
              "<": "&lt;",
              ">": "&gt;",
              "`": "&#x60;",
            },
            m = /&#(?:[xX][^a-fA-F0-9]|[^0-9xX])/,
            g =
              /[\0-\x08\x0B\x0E-\x1F\x7F-\x9F\uFDD0-\uFDEF\uFFFE\uFFFF]|[\uD83F\uD87F\uD8BF\uD8FF\uD93F\uD97F\uD9BF\uD9FF\uDA3F\uDA7F\uDABF\uDAFF\uDB3F\uDB7F\uDBBF\uDBFF][\uDFFE\uDFFF]|[\uD800-\uDBFF](?![\uDC00-\uDFFF])|(?:[^\uD800-\uDBFF]|^)[\uDC00-\uDFFF]/,
            f =
              /&(CounterClockwiseContourIntegral|DoubleLongLeftRightArrow|ClockwiseContourIntegral|NotNestedGreaterGreater|NotSquareSupersetEqual|DiacriticalDoubleAcute|NotRightTriangleEqual|NotSucceedsSlantEqual|NotPrecedesSlantEqual|CloseCurlyDoubleQuote|NegativeVeryThinSpace|DoubleContourIntegral|FilledVerySmallSquare|CapitalDifferentialD|OpenCurlyDoubleQuote|EmptyVerySmallSquare|NestedGreaterGreater|DoubleLongRightArrow|NotLeftTriangleEqual|NotGreaterSlantEqual|ReverseUpEquilibrium|DoubleLeftRightArrow|NotSquareSubsetEqual|NotDoubleVerticalBar|RightArrowLeftArrow|NotGreaterFullEqual|NotRightTriangleBar|SquareSupersetEqual|DownLeftRightVector|DoubleLongLeftArrow|leftrightsquigarrow|LeftArrowRightArrow|NegativeMediumSpace|blacktriangleright|RightDownVectorBar|PrecedesSlantEqual|RightDoubleBracket|SucceedsSlantEqual|NotLeftTriangleBar|RightTriangleEqual|SquareIntersection|RightDownTeeVector|ReverseEquilibrium|NegativeThickSpace|longleftrightarrow|Longleftrightarrow|LongLeftRightArrow|DownRightTeeVector|DownRightVectorBar|GreaterSlantEqual|SquareSubsetEqual|LeftDownVectorBar|LeftDoubleBracket|VerticalSeparator|rightleftharpoons|NotGreaterGreater|NotSquareSuperset|blacktriangleleft|blacktriangledown|NegativeThinSpace|LeftDownTeeVector|NotLessSlantEqual|leftrightharpoons|DoubleUpDownArrow|DoubleVerticalBar|LeftTriangleEqual|FilledSmallSquare|twoheadrightarrow|NotNestedLessLess|DownLeftTeeVector|DownLeftVectorBar|RightAngleBracket|NotTildeFullEqual|NotReverseElement|RightUpDownVector|DiacriticalTilde|NotSucceedsTilde|circlearrowright|NotPrecedesEqual|rightharpoondown|DoubleRightArrow|NotSucceedsEqual|NonBreakingSpace|NotRightTriangle|LessEqualGreater|RightUpTeeVector|LeftAngleBracket|GreaterFullEqual|DownArrowUpArrow|RightUpVectorBar|twoheadleftarrow|GreaterEqualLess|downharpoonright|RightTriangleBar|ntrianglerighteq|NotSupersetEqual|LeftUpDownVector|DiacriticalAcute|rightrightarrows|vartriangleright|UpArrowDownArrow|DiacriticalGrave|UnderParenthesis|EmptySmallSquare|LeftUpVectorBar|leftrightarrows|DownRightVector|downharpoonleft|trianglerighteq|ShortRightArrow|OverParenthesis|DoubleLeftArrow|DoubleDownArrow|NotSquareSubset|bigtriangledown|ntrianglelefteq|UpperRightArrow|curvearrowright|vartriangleleft|NotLeftTriangle|nleftrightarrow|LowerRightArrow|NotHumpDownHump|NotGreaterTilde|rightthreetimes|LeftUpTeeVector|NotGreaterEqual|straightepsilon|LeftTriangleBar|rightsquigarrow|ContourIntegral|rightleftarrows|CloseCurlyQuote|RightDownVector|LeftRightVector|nLeftrightarrow|leftharpoondown|circlearrowleft|SquareSuperset|OpenCurlyQuote|hookrightarrow|HorizontalLine|DiacriticalDot|NotLessGreater|ntriangleright|DoubleRightTee|InvisibleComma|InvisibleTimes|LowerLeftArrow|DownLeftVector|NotSubsetEqual|curvearrowleft|trianglelefteq|NotVerticalBar|TildeFullEqual|downdownarrows|NotGreaterLess|RightTeeVector|ZeroWidthSpace|looparrowright|LongRightArrow|doublebarwedge|ShortLeftArrow|ShortDownArrow|RightVectorBar|GreaterGreater|ReverseElement|rightharpoonup|LessSlantEqual|leftthreetimes|upharpoonright|rightarrowtail|LeftDownVector|Longrightarrow|NestedLessLess|UpperLeftArrow|nshortparallel|leftleftarrows|leftrightarrow|Leftrightarrow|LeftRightArrow|longrightarrow|upharpoonleft|RightArrowBar|ApplyFunction|LeftTeeVector|leftarrowtail|NotEqualTilde|varsubsetneqq|varsupsetneqq|RightTeeArrow|SucceedsEqual|SucceedsTilde|LeftVectorBar|SupersetEqual|hookleftarrow|DifferentialD|VerticalTilde|VeryThinSpace|blacktriangle|bigtriangleup|LessFullEqual|divideontimes|leftharpoonup|UpEquilibrium|ntriangleleft|RightTriangle|measuredangle|shortparallel|longleftarrow|Longleftarrow|LongLeftArrow|DoubleLeftTee|Poincareplane|PrecedesEqual|triangleright|DoubleUpArrow|RightUpVector|fallingdotseq|looparrowleft|PrecedesTilde|NotTildeEqual|NotTildeTilde|smallsetminus|Proportional|triangleleft|triangledown|UnderBracket|NotHumpEqual|exponentiale|ExponentialE|NotLessTilde|HilbertSpace|RightCeiling|blacklozenge|varsupsetneq|HumpDownHump|GreaterEqual|VerticalLine|LeftTeeArrow|NotLessEqual|DownTeeArrow|LeftTriangle|varsubsetneq|Intersection|NotCongruent|DownArrowBar|LeftUpVector|LeftArrowBar|risingdotseq|GreaterTilde|RoundImplies|SquareSubset|ShortUpArrow|NotSuperset|quaternions|precnapprox|backepsilon|preccurlyeq|OverBracket|blacksquare|MediumSpace|VerticalBar|circledcirc|circleddash|CircleMinus|CircleTimes|LessGreater|curlyeqprec|curlyeqsucc|diamondsuit|UpDownArrow|Updownarrow|RuleDelayed|Rrightarrow|updownarrow|RightVector|nRightarrow|nrightarrow|eqslantless|LeftCeiling|Equilibrium|SmallCircle|expectation|NotSucceeds|thickapprox|GreaterLess|SquareUnion|NotPrecedes|NotLessLess|straightphi|succnapprox|succcurlyeq|SubsetEqual|sqsupseteq|Proportion|Laplacetrf|ImaginaryI|supsetneqq|NotGreater|gtreqqless|NotElement|ThickSpace|TildeEqual|TildeTilde|Fouriertrf|rmoustache|EqualTilde|eqslantgtr|UnderBrace|LeftVector|UpArrowBar|nLeftarrow|nsubseteqq|subsetneqq|nsupseteqq|nleftarrow|succapprox|lessapprox|UpTeeArrow|upuparrows|curlywedge|lesseqqgtr|varepsilon|varnothing|RightFloor|complement|CirclePlus|sqsubseteq|Lleftarrow|circledast|RightArrow|Rightarrow|rightarrow|lmoustache|Bernoullis|precapprox|mapstoleft|mapstodown|longmapsto|dotsquare|downarrow|DoubleDot|nsubseteq|supsetneq|leftarrow|nsupseteq|subsetneq|ThinSpace|ngeqslant|subseteqq|HumpEqual|NotSubset|triangleq|NotCupCap|lesseqgtr|heartsuit|TripleDot|Leftarrow|Coproduct|Congruent|varpropto|complexes|gvertneqq|LeftArrow|LessTilde|supseteqq|MinusPlus|CircleDot|nleqslant|NotExists|gtreqless|nparallel|UnionPlus|LeftFloor|checkmark|CenterDot|centerdot|Mellintrf|gtrapprox|bigotimes|OverBrace|spadesuit|therefore|pitchfork|rationals|PlusMinus|Backslash|Therefore|DownBreve|backsimeq|backprime|DownArrow|nshortmid|Downarrow|lvertneqq|eqvparsl|imagline|imagpart|infintie|integers|Integral|intercal|LessLess|Uarrocir|intlarhk|sqsupset|angmsdaf|sqsubset|llcorner|vartheta|cupbrcap|lnapprox|Superset|SuchThat|succnsim|succneqq|angmsdag|biguplus|curlyvee|trpezium|Succeeds|NotTilde|bigwedge|angmsdah|angrtvbd|triminus|cwconint|fpartint|lrcorner|smeparsl|subseteq|urcorner|lurdshar|laemptyv|DDotrahd|approxeq|ldrushar|awconint|mapstoup|backcong|shortmid|triangle|geqslant|gesdotol|timesbar|circledR|circledS|setminus|multimap|naturals|scpolint|ncongdot|RightTee|boxminus|gnapprox|boxtimes|andslope|thicksim|angmsdaa|varsigma|cirfnint|rtriltri|angmsdab|rppolint|angmsdac|barwedge|drbkarow|clubsuit|thetasym|bsolhsub|capbrcup|dzigrarr|doteqdot|DotEqual|dotminus|UnderBar|NotEqual|realpart|otimesas|ulcorner|hksearow|hkswarow|parallel|PartialD|elinters|emptyset|plusacir|bbrktbrk|angmsdad|pointint|bigoplus|angmsdae|Precedes|bigsqcup|varkappa|notindot|supseteq|precneqq|precnsim|profalar|profline|profsurf|leqslant|lesdotor|raemptyv|subplus|notnivb|notnivc|subrarr|zigrarr|vzigzag|submult|subedot|Element|between|cirscir|larrbfs|larrsim|lotimes|lbrksld|lbrkslu|lozenge|ldrdhar|dbkarow|bigcirc|epsilon|simrarr|simplus|ltquest|Epsilon|luruhar|gtquest|maltese|npolint|eqcolon|npreceq|bigodot|ddagger|gtrless|bnequiv|harrcir|ddotseq|equivDD|backsim|demptyv|nsqsube|nsqsupe|Upsilon|nsubset|upsilon|minusdu|nsucceq|swarrow|nsupset|coloneq|searrow|boxplus|napprox|natural|asympeq|alefsym|congdot|nearrow|bigstar|diamond|supplus|tritime|LeftTee|nvinfin|triplus|NewLine|nvltrie|nvrtrie|nwarrow|nexists|Diamond|ruluhar|Implies|supmult|angzarr|suplarr|suphsub|questeq|because|digamma|Because|olcross|bemptyv|omicron|Omicron|rotimes|NoBreak|intprod|angrtvb|orderof|uwangle|suphsol|lesdoto|orslope|DownTee|realine|cudarrl|rdldhar|OverBar|supedot|lessdot|supdsub|topfork|succsim|rbrkslu|rbrksld|pertenk|cudarrr|isindot|planckh|lessgtr|pluscir|gesdoto|plussim|plustwo|lesssim|cularrp|rarrsim|Cayleys|notinva|notinvb|notinvc|UpArrow|Uparrow|uparrow|NotLess|dwangle|precsim|Product|curarrm|Cconint|dotplus|rarrbfs|ccupssm|Cedilla|cemptyv|notniva|quatint|frac35|frac38|frac45|frac56|frac58|frac78|tridot|xoplus|gacute|gammad|Gammad|lfisht|lfloor|bigcup|sqsupe|gbreve|Gbreve|lharul|sqsube|sqcups|Gcedil|apacir|llhard|lmidot|Lmidot|lmoust|andand|sqcaps|approx|Abreve|spades|circeq|tprime|divide|topcir|Assign|topbot|gesdot|divonx|xuplus|timesd|gesles|atilde|solbar|SOFTcy|loplus|timesb|lowast|lowbar|dlcorn|dlcrop|softcy|dollar|lparlt|thksim|lrhard|Atilde|lsaquo|smashp|bigvee|thinsp|wreath|bkarow|lsquor|lstrok|Lstrok|lthree|ltimes|ltlarr|DotDot|simdot|ltrPar|weierp|xsqcup|angmsd|sigmav|sigmaf|zeetrf|Zcaron|zcaron|mapsto|vsupne|thetav|cirmid|marker|mcomma|Zacute|vsubnE|there4|gtlPar|vsubne|bottom|gtrarr|SHCHcy|shchcy|midast|midcir|middot|minusb|minusd|gtrdot|bowtie|sfrown|mnplus|models|colone|seswar|Colone|mstpos|searhk|gtrsim|nacute|Nacute|boxbox|telrec|hairsp|Tcedil|nbumpe|scnsim|ncaron|Ncaron|ncedil|Ncedil|hamilt|Scedil|nearhk|hardcy|HARDcy|tcedil|Tcaron|commat|nequiv|nesear|tcaron|target|hearts|nexist|varrho|scedil|Scaron|scaron|hellip|Sacute|sacute|hercon|swnwar|compfn|rtimes|rthree|rsquor|rsaquo|zacute|wedgeq|homtht|barvee|barwed|Barwed|rpargt|horbar|conint|swarhk|roplus|nltrie|hslash|hstrok|Hstrok|rmoust|Conint|bprime|hybull|hyphen|iacute|Iacute|supsup|supsub|supsim|varphi|coprod|brvbar|agrave|Supset|supset|igrave|Igrave|notinE|Agrave|iiiint|iinfin|copysr|wedbar|Verbar|vangrt|becaus|incare|verbar|inodot|bullet|drcorn|intcal|drcrop|cularr|vellip|Utilde|bumpeq|cupcap|dstrok|Dstrok|CupCap|cupcup|cupdot|eacute|Eacute|supdot|iquest|easter|ecaron|Ecaron|ecolon|isinsv|utilde|itilde|Itilde|curarr|succeq|Bumpeq|cacute|ulcrop|nparsl|Cacute|nprcue|egrave|Egrave|nrarrc|nrarrw|subsup|subsub|nrtrie|jsercy|nsccue|Jsercy|kappav|kcedil|Kcedil|subsim|ulcorn|nsimeq|egsdot|veebar|kgreen|capand|elsdot|Subset|subset|curren|aacute|lacute|Lacute|emptyv|ntilde|Ntilde|lagran|lambda|Lambda|capcap|Ugrave|langle|subdot|emsp13|numero|emsp14|nvdash|nvDash|nVdash|nVDash|ugrave|ufisht|nvHarr|larrfs|nvlArr|larrhk|larrlp|larrpl|nvrArr|Udblac|nwarhk|larrtl|nwnear|oacute|Oacute|latail|lAtail|sstarf|lbrace|odblac|Odblac|lbrack|udblac|odsold|eparsl|lcaron|Lcaron|ograve|Ograve|lcedil|Lcedil|Aacute|ssmile|ssetmn|squarf|ldquor|capcup|ominus|cylcty|rharul|eqcirc|dagger|rfloor|rfisht|Dagger|daleth|equals|origof|capdot|equest|dcaron|Dcaron|rdquor|oslash|Oslash|otilde|Otilde|otimes|Otimes|urcrop|Ubreve|ubreve|Yacute|Uacute|uacute|Rcedil|rcedil|urcorn|parsim|Rcaron|Vdashl|rcaron|Tstrok|percnt|period|permil|Exists|yacute|rbrack|rbrace|phmmat|ccaron|Ccaron|planck|ccedil|plankv|tstrok|female|plusdo|plusdu|ffilig|plusmn|ffllig|Ccedil|rAtail|dfisht|bernou|ratail|Rarrtl|rarrtl|angsph|rarrpl|rarrlp|rarrhk|xwedge|xotime|forall|ForAll|Vvdash|vsupnE|preceq|bigcap|frac12|frac13|frac14|primes|rarrfs|prnsim|frac15|Square|frac16|square|lesdot|frac18|frac23|propto|prurel|rarrap|rangle|puncsp|frac25|Racute|qprime|racute|lesges|frac34|abreve|AElig|eqsim|utdot|setmn|urtri|Equal|Uring|seArr|uring|searr|dashv|Dashv|mumap|nabla|iogon|Iogon|sdote|sdotb|scsim|napid|napos|equiv|natur|Acirc|dblac|erarr|nbump|iprod|erDot|ucirc|awint|esdot|angrt|ncong|isinE|scnap|Scirc|scirc|ndash|isins|Ubrcy|nearr|neArr|isinv|nedot|ubrcy|acute|Ycirc|iukcy|Iukcy|xutri|nesim|caret|jcirc|Jcirc|caron|twixt|ddarr|sccue|exist|jmath|sbquo|ngeqq|angst|ccaps|lceil|ngsim|UpTee|delta|Delta|rtrif|nharr|nhArr|nhpar|rtrie|jukcy|Jukcy|kappa|rsquo|Kappa|nlarr|nlArr|TSHcy|rrarr|aogon|Aogon|fflig|xrarr|tshcy|ccirc|nleqq|filig|upsih|nless|dharl|nlsim|fjlig|ropar|nltri|dharr|robrk|roarr|fllig|fltns|roang|rnmid|subnE|subne|lAarr|trisb|Ccirc|acirc|ccups|blank|VDash|forkv|Vdash|langd|cedil|blk12|blk14|laquo|strns|diams|notin|vDash|larrb|blk34|block|disin|uplus|vdash|vBarv|aelig|starf|Wedge|check|xrArr|lates|lbarr|lBarr|notni|lbbrk|bcong|frasl|lbrke|frown|vrtri|vprop|vnsup|gamma|Gamma|wedge|xodot|bdquo|srarr|doteq|ldquo|boxdl|boxdL|gcirc|Gcirc|boxDl|boxDL|boxdr|boxdR|boxDr|TRADE|trade|rlhar|boxDR|vnsub|npart|vltri|rlarr|boxhd|boxhD|nprec|gescc|nrarr|nrArr|boxHd|boxHD|boxhu|boxhU|nrtri|boxHu|clubs|boxHU|times|colon|Colon|gimel|xlArr|Tilde|nsime|tilde|nsmid|nspar|THORN|thorn|xlarr|nsube|nsubE|thkap|xhArr|comma|nsucc|boxul|boxuL|nsupe|nsupE|gneqq|gnsim|boxUl|boxUL|grave|boxur|boxuR|boxUr|boxUR|lescc|angle|bepsi|boxvh|varpi|boxvH|numsp|Theta|gsime|gsiml|theta|boxVh|boxVH|boxvl|gtcir|gtdot|boxvL|boxVl|boxVL|crarr|cross|Cross|nvsim|boxvr|nwarr|nwArr|sqsup|dtdot|Uogon|lhard|lharu|dtrif|ocirc|Ocirc|lhblk|duarr|odash|sqsub|Hacek|sqcup|llarr|duhar|oelig|OElig|ofcir|boxvR|uogon|lltri|boxVr|csube|uuarr|ohbar|csupe|ctdot|olarr|olcir|harrw|oline|sqcap|omacr|Omacr|omega|Omega|boxVR|aleph|lneqq|lnsim|loang|loarr|rharu|lobrk|hcirc|operp|oplus|rhard|Hcirc|orarr|Union|order|ecirc|Ecirc|cuepr|szlig|cuesc|breve|reals|eDDot|Breve|hoarr|lopar|utrif|rdquo|Umacr|umacr|efDot|swArr|ultri|alpha|rceil|ovbar|swarr|Wcirc|wcirc|smtes|smile|bsemi|lrarr|aring|parsl|lrhar|bsime|uhblk|lrtri|cupor|Aring|uharr|uharl|slarr|rbrke|bsolb|lsime|rbbrk|RBarr|lsimg|phone|rBarr|rbarr|icirc|lsquo|Icirc|emacr|Emacr|ratio|simne|plusb|simlE|simgE|simeq|pluse|ltcir|ltdot|empty|xharr|xdtri|iexcl|Alpha|ltrie|rarrw|pound|ltrif|xcirc|bumpe|prcue|bumpE|asymp|amacr|cuvee|Sigma|sigma|iiint|udhar|iiota|ijlig|IJlig|supnE|imacr|Imacr|prime|Prime|image|prnap|eogon|Eogon|rarrc|mdash|mDDot|cuwed|imath|supne|imped|Amacr|udarr|prsim|micro|rarrb|cwint|raquo|infin|eplus|range|rangd|Ucirc|radic|minus|amalg|veeeq|rAarr|epsiv|ycirc|quest|sharp|quot|zwnj|Qscr|race|qscr|Qopf|qopf|qint|rang|Rang|Zscr|zscr|Zopf|zopf|rarr|rArr|Rarr|Pscr|pscr|prop|prod|prnE|prec|ZHcy|zhcy|prap|Zeta|zeta|Popf|popf|Zdot|plus|zdot|Yuml|yuml|phiv|YUcy|yucy|Yscr|yscr|perp|Yopf|yopf|part|para|YIcy|Ouml|rcub|yicy|YAcy|rdca|ouml|osol|Oscr|rdsh|yacy|real|oscr|xvee|andd|rect|andv|Xscr|oror|ordm|ordf|xscr|ange|aopf|Aopf|rHar|Xopf|opar|Oopf|xopf|xnis|rhov|oopf|omid|xmap|oint|apid|apos|ogon|ascr|Ascr|odot|odiv|xcup|xcap|ocir|oast|nvlt|nvle|nvgt|nvge|nvap|Wscr|wscr|auml|ntlg|ntgl|nsup|nsub|nsim|Nscr|nscr|nsce|Wopf|ring|npre|wopf|npar|Auml|Barv|bbrk|Nopf|nopf|nmid|nLtv|beta|ropf|Ropf|Beta|beth|nles|rpar|nleq|bnot|bNot|nldr|NJcy|rscr|Rscr|Vscr|vscr|rsqb|njcy|bopf|nisd|Bopf|rtri|Vopf|nGtv|ngtr|vopf|boxh|boxH|boxv|nges|ngeq|boxV|bscr|scap|Bscr|bsim|Vert|vert|bsol|bull|bump|caps|cdot|ncup|scnE|ncap|nbsp|napE|Cdot|cent|sdot|Vbar|nang|vBar|chcy|Mscr|mscr|sect|semi|CHcy|Mopf|mopf|sext|circ|cire|mldr|mlcp|cirE|comp|shcy|SHcy|vArr|varr|cong|copf|Copf|copy|COPY|malt|male|macr|lvnE|cscr|ltri|sime|ltcc|simg|Cscr|siml|csub|Uuml|lsqb|lsim|uuml|csup|Lscr|lscr|utri|smid|lpar|cups|smte|lozf|darr|Lopf|Uscr|solb|lopf|sopf|Sopf|lneq|uscr|spar|dArr|lnap|Darr|dash|Sqrt|LJcy|ljcy|lHar|dHar|Upsi|upsi|diam|lesg|djcy|DJcy|leqq|dopf|Dopf|dscr|Dscr|dscy|ldsh|ldca|squf|DScy|sscr|Sscr|dsol|lcub|late|star|Star|Uopf|Larr|lArr|larr|uopf|dtri|dzcy|sube|subE|Lang|lang|Kscr|kscr|Kopf|kopf|KJcy|kjcy|KHcy|khcy|DZcy|ecir|edot|eDot|Jscr|jscr|succ|Jopf|jopf|Edot|uHar|emsp|ensp|Iuml|iuml|eopf|isin|Iscr|iscr|Eopf|epar|sung|epsi|escr|sup1|sup2|sup3|Iota|iota|supe|supE|Iopf|iopf|IOcy|iocy|Escr|esim|Esim|imof|Uarr|QUOT|uArr|uarr|euml|IEcy|iecy|Idot|Euml|euro|excl|Hscr|hscr|Hopf|hopf|TScy|tscy|Tscr|hbar|tscr|flat|tbrk|fnof|hArr|harr|half|fopf|Fopf|tdot|gvnE|fork|trie|gtcc|fscr|Fscr|gdot|gsim|Gscr|gscr|Gopf|gopf|gneq|Gdot|tosa|gnap|Topf|topf|geqq|toea|GJcy|gjcy|tint|gesl|mid|Sfr|ggg|top|ges|gla|glE|glj|geq|gne|gEl|gel|gnE|Gcy|gcy|gap|Tfr|tfr|Tcy|tcy|Hat|Tau|Ffr|tau|Tab|hfr|Hfr|ffr|Fcy|fcy|icy|Icy|iff|ETH|eth|ifr|Ifr|Eta|eta|int|Int|Sup|sup|ucy|Ucy|Sum|sum|jcy|ENG|ufr|Ufr|eng|Jcy|jfr|els|ell|egs|Efr|efr|Jfr|uml|kcy|Kcy|Ecy|ecy|kfr|Kfr|lap|Sub|sub|lat|lcy|Lcy|leg|Dot|dot|lEg|leq|les|squ|div|die|lfr|Lfr|lgE|Dfr|dfr|Del|deg|Dcy|dcy|lne|lnE|sol|loz|smt|Cup|lrm|cup|lsh|Lsh|sim|shy|map|Map|mcy|Mcy|mfr|Mfr|mho|gfr|Gfr|sfr|cir|Chi|chi|nap|Cfr|vcy|Vcy|cfr|Scy|scy|ncy|Ncy|vee|Vee|Cap|cap|nfr|scE|sce|Nfr|nge|ngE|nGg|vfr|Vfr|ngt|bot|nGt|nis|niv|Rsh|rsh|nle|nlE|bne|Bfr|bfr|nLl|nlt|nLt|Bcy|bcy|not|Not|rlm|wfr|Wfr|npr|nsc|num|ocy|ast|Ocy|ofr|xfr|Xfr|Ofr|ogt|ohm|apE|olt|Rho|ape|rho|Rfr|rfr|ord|REG|ang|reg|orv|And|and|AMP|Rcy|amp|Afr|ycy|Ycy|yen|yfr|Yfr|rcy|par|pcy|Pcy|pfr|Pfr|phi|Phi|afr|Acy|acy|zcy|Zcy|piv|acE|acd|zfr|Zfr|pre|prE|psi|Psi|qfr|Qfr|zwj|Or|ge|Gg|gt|gg|el|oS|lt|Lt|LT|Re|lg|gl|eg|ne|Im|it|le|DD|wp|wr|nu|Nu|dd|lE|Sc|sc|pi|Pi|ee|af|ll|Ll|rx|gE|xi|pm|Xi|ic|pr|Pr|in|ni|mp|mu|ac|Mu|or|ap|Gt|GT|ii);|&(Aacute|Agrave|Atilde|Ccedil|Eacute|Egrave|Iacute|Igrave|Ntilde|Oacute|Ograve|Oslash|Otilde|Uacute|Ugrave|Yacute|aacute|agrave|atilde|brvbar|ccedil|curren|divide|eacute|egrave|frac12|frac14|frac34|iacute|igrave|iquest|middot|ntilde|oacute|ograve|oslash|otilde|plusmn|uacute|ugrave|yacute|AElig|Acirc|Aring|Ecirc|Icirc|Ocirc|THORN|Ucirc|acirc|acute|aelig|aring|cedil|ecirc|icirc|iexcl|laquo|micro|ocirc|pound|raquo|szlig|thorn|times|ucirc|Auml|COPY|Euml|Iuml|Ouml|QUOT|Uuml|auml|cent|copy|euml|iuml|macr|nbsp|ordf|ordm|ouml|para|quot|sect|sup1|sup2|sup3|uuml|yuml|AMP|ETH|REG|amp|deg|eth|not|reg|shy|uml|yen|GT|LT|gt|lt)(?!;)([=a-zA-Z0-9]?)|&#([0-9]+)(;?)|&#[xX]([a-fA-F0-9]+)(;?)|&([0-9a-zA-Z]+)/g,
            A = {
              aacute: "á",
              Aacute: "Á",
              abreve: "ă",
              Abreve: "Ă",
              ac: "∾",
              acd: "∿",
              acE: "∾̳",
              acirc: "â",
              Acirc: "Â",
              acute: "´",
              acy: "а",
              Acy: "А",
              aelig: "æ",
              AElig: "Æ",
              af: "⁡",
              afr: "𝔞",
              Afr: "𝔄",
              agrave: "à",
              Agrave: "À",
              alefsym: "ℵ",
              aleph: "ℵ",
              alpha: "α",
              Alpha: "Α",
              amacr: "ā",
              Amacr: "Ā",
              amalg: "⨿",
              amp: "&",
              AMP: "&",
              and: "∧",
              And: "⩓",
              andand: "⩕",
              andd: "⩜",
              andslope: "⩘",
              andv: "⩚",
              ang: "∠",
              ange: "⦤",
              angle: "∠",
              angmsd: "∡",
              angmsdaa: "⦨",
              angmsdab: "⦩",
              angmsdac: "⦪",
              angmsdad: "⦫",
              angmsdae: "⦬",
              angmsdaf: "⦭",
              angmsdag: "⦮",
              angmsdah: "⦯",
              angrt: "∟",
              angrtvb: "⊾",
              angrtvbd: "⦝",
              angsph: "∢",
              angst: "Å",
              angzarr: "⍼",
              aogon: "ą",
              Aogon: "Ą",
              aopf: "𝕒",
              Aopf: "𝔸",
              ap: "≈",
              apacir: "⩯",
              ape: "≊",
              apE: "⩰",
              apid: "≋",
              apos: "'",
              ApplyFunction: "⁡",
              approx: "≈",
              approxeq: "≊",
              aring: "å",
              Aring: "Å",
              ascr: "𝒶",
              Ascr: "𝒜",
              Assign: "≔",
              ast: "*",
              asymp: "≈",
              asympeq: "≍",
              atilde: "ã",
              Atilde: "Ã",
              auml: "ä",
              Auml: "Ä",
              awconint: "∳",
              awint: "⨑",
              backcong: "≌",
              backepsilon: "϶",
              backprime: "‵",
              backsim: "∽",
              backsimeq: "⋍",
              Backslash: "∖",
              Barv: "⫧",
              barvee: "⊽",
              barwed: "⌅",
              Barwed: "⌆",
              barwedge: "⌅",
              bbrk: "⎵",
              bbrktbrk: "⎶",
              bcong: "≌",
              bcy: "б",
              Bcy: "Б",
              bdquo: "„",
              becaus: "∵",
              because: "∵",
              Because: "∵",
              bemptyv: "⦰",
              bepsi: "϶",
              bernou: "ℬ",
              Bernoullis: "ℬ",
              beta: "β",
              Beta: "Β",
              beth: "ℶ",
              between: "≬",
              bfr: "𝔟",
              Bfr: "𝔅",
              bigcap: "⋂",
              bigcirc: "◯",
              bigcup: "⋃",
              bigodot: "⨀",
              bigoplus: "⨁",
              bigotimes: "⨂",
              bigsqcup: "⨆",
              bigstar: "★",
              bigtriangledown: "▽",
              bigtriangleup: "△",
              biguplus: "⨄",
              bigvee: "⋁",
              bigwedge: "⋀",
              bkarow: "⤍",
              blacklozenge: "⧫",
              blacksquare: "▪",
              blacktriangle: "▴",
              blacktriangledown: "▾",
              blacktriangleleft: "◂",
              blacktriangleright: "▸",
              blank: "␣",
              blk12: "▒",
              blk14: "░",
              blk34: "▓",
              block: "█",
              bne: "=⃥",
              bnequiv: "≡⃥",
              bnot: "⌐",
              bNot: "⫭",
              bopf: "𝕓",
              Bopf: "𝔹",
              bot: "⊥",
              bottom: "⊥",
              bowtie: "⋈",
              boxbox: "⧉",
              boxdl: "┐",
              boxdL: "╕",
              boxDl: "╖",
              boxDL: "╗",
              boxdr: "┌",
              boxdR: "╒",
              boxDr: "╓",
              boxDR: "╔",
              boxh: "─",
              boxH: "═",
              boxhd: "┬",
              boxhD: "╥",
              boxHd: "╤",
              boxHD: "╦",
              boxhu: "┴",
              boxhU: "╨",
              boxHu: "╧",
              boxHU: "╩",
              boxminus: "⊟",
              boxplus: "⊞",
              boxtimes: "⊠",
              boxul: "┘",
              boxuL: "╛",
              boxUl: "╜",
              boxUL: "╝",
              boxur: "└",
              boxuR: "╘",
              boxUr: "╙",
              boxUR: "╚",
              boxv: "│",
              boxV: "║",
              boxvh: "┼",
              boxvH: "╪",
              boxVh: "╫",
              boxVH: "╬",
              boxvl: "┤",
              boxvL: "╡",
              boxVl: "╢",
              boxVL: "╣",
              boxvr: "├",
              boxvR: "╞",
              boxVr: "╟",
              boxVR: "╠",
              bprime: "‵",
              breve: "˘",
              Breve: "˘",
              brvbar: "¦",
              bscr: "𝒷",
              Bscr: "ℬ",
              bsemi: "⁏",
              bsim: "∽",
              bsime: "⋍",
              bsol: "\\",
              bsolb: "⧅",
              bsolhsub: "⟈",
              bull: "•",
              bullet: "•",
              bump: "≎",
              bumpe: "≏",
              bumpE: "⪮",
              bumpeq: "≏",
              Bumpeq: "≎",
              cacute: "ć",
              Cacute: "Ć",
              cap: "∩",
              Cap: "⋒",
              capand: "⩄",
              capbrcup: "⩉",
              capcap: "⩋",
              capcup: "⩇",
              capdot: "⩀",
              CapitalDifferentialD: "ⅅ",
              caps: "∩︀",
              caret: "⁁",
              caron: "ˇ",
              Cayleys: "ℭ",
              ccaps: "⩍",
              ccaron: "č",
              Ccaron: "Č",
              ccedil: "ç",
              Ccedil: "Ç",
              ccirc: "ĉ",
              Ccirc: "Ĉ",
              Cconint: "∰",
              ccups: "⩌",
              ccupssm: "⩐",
              cdot: "ċ",
              Cdot: "Ċ",
              cedil: "¸",
              Cedilla: "¸",
              cemptyv: "⦲",
              cent: "¢",
              centerdot: "·",
              CenterDot: "·",
              cfr: "𝔠",
              Cfr: "ℭ",
              chcy: "ч",
              CHcy: "Ч",
              check: "✓",
              checkmark: "✓",
              chi: "χ",
              Chi: "Χ",
              cir: "○",
              circ: "ˆ",
              circeq: "≗",
              circlearrowleft: "↺",
              circlearrowright: "↻",
              circledast: "⊛",
              circledcirc: "⊚",
              circleddash: "⊝",
              CircleDot: "⊙",
              circledR: "®",
              circledS: "Ⓢ",
              CircleMinus: "⊖",
              CirclePlus: "⊕",
              CircleTimes: "⊗",
              cire: "≗",
              cirE: "⧃",
              cirfnint: "⨐",
              cirmid: "⫯",
              cirscir: "⧂",
              ClockwiseContourIntegral: "∲",
              CloseCurlyDoubleQuote: "”",
              CloseCurlyQuote: "’",
              clubs: "♣",
              clubsuit: "♣",
              colon: ":",
              Colon: "∷",
              colone: "≔",
              Colone: "⩴",
              coloneq: "≔",
              comma: ",",
              commat: "@",
              comp: "∁",
              compfn: "∘",
              complement: "∁",
              complexes: "ℂ",
              cong: "≅",
              congdot: "⩭",
              Congruent: "≡",
              conint: "∮",
              Conint: "∯",
              ContourIntegral: "∮",
              copf: "𝕔",
              Copf: "ℂ",
              coprod: "∐",
              Coproduct: "∐",
              copy: "©",
              COPY: "©",
              copysr: "℗",
              CounterClockwiseContourIntegral: "∳",
              crarr: "↵",
              cross: "✗",
              Cross: "⨯",
              cscr: "𝒸",
              Cscr: "𝒞",
              csub: "⫏",
              csube: "⫑",
              csup: "⫐",
              csupe: "⫒",
              ctdot: "⋯",
              cudarrl: "⤸",
              cudarrr: "⤵",
              cuepr: "⋞",
              cuesc: "⋟",
              cularr: "↶",
              cularrp: "⤽",
              cup: "∪",
              Cup: "⋓",
              cupbrcap: "⩈",
              cupcap: "⩆",
              CupCap: "≍",
              cupcup: "⩊",
              cupdot: "⊍",
              cupor: "⩅",
              cups: "∪︀",
              curarr: "↷",
              curarrm: "⤼",
              curlyeqprec: "⋞",
              curlyeqsucc: "⋟",
              curlyvee: "⋎",
              curlywedge: "⋏",
              curren: "¤",
              curvearrowleft: "↶",
              curvearrowright: "↷",
              cuvee: "⋎",
              cuwed: "⋏",
              cwconint: "∲",
              cwint: "∱",
              cylcty: "⌭",
              dagger: "†",
              Dagger: "‡",
              daleth: "ℸ",
              darr: "↓",
              dArr: "⇓",
              Darr: "↡",
              dash: "‐",
              dashv: "⊣",
              Dashv: "⫤",
              dbkarow: "⤏",
              dblac: "˝",
              dcaron: "ď",
              Dcaron: "Ď",
              dcy: "д",
              Dcy: "Д",
              dd: "ⅆ",
              DD: "ⅅ",
              ddagger: "‡",
              ddarr: "⇊",
              DDotrahd: "⤑",
              ddotseq: "⩷",
              deg: "°",
              Del: "∇",
              delta: "δ",
              Delta: "Δ",
              demptyv: "⦱",
              dfisht: "⥿",
              dfr: "𝔡",
              Dfr: "𝔇",
              dHar: "⥥",
              dharl: "⇃",
              dharr: "⇂",
              DiacriticalAcute: "´",
              DiacriticalDot: "˙",
              DiacriticalDoubleAcute: "˝",
              DiacriticalGrave: "`",
              DiacriticalTilde: "˜",
              diam: "⋄",
              diamond: "⋄",
              Diamond: "⋄",
              diamondsuit: "♦",
              diams: "♦",
              die: "¨",
              DifferentialD: "ⅆ",
              digamma: "ϝ",
              disin: "⋲",
              div: "÷",
              divide: "÷",
              divideontimes: "⋇",
              divonx: "⋇",
              djcy: "ђ",
              DJcy: "Ђ",
              dlcorn: "⌞",
              dlcrop: "⌍",
              dollar: "$",
              dopf: "𝕕",
              Dopf: "𝔻",
              dot: "˙",
              Dot: "¨",
              DotDot: "⃜",
              doteq: "≐",
              doteqdot: "≑",
              DotEqual: "≐",
              dotminus: "∸",
              dotplus: "∔",
              dotsquare: "⊡",
              doublebarwedge: "⌆",
              DoubleContourIntegral: "∯",
              DoubleDot: "¨",
              DoubleDownArrow: "⇓",
              DoubleLeftArrow: "⇐",
              DoubleLeftRightArrow: "⇔",
              DoubleLeftTee: "⫤",
              DoubleLongLeftArrow: "⟸",
              DoubleLongLeftRightArrow: "⟺",
              DoubleLongRightArrow: "⟹",
              DoubleRightArrow: "⇒",
              DoubleRightTee: "⊨",
              DoubleUpArrow: "⇑",
              DoubleUpDownArrow: "⇕",
              DoubleVerticalBar: "∥",
              downarrow: "↓",
              Downarrow: "⇓",
              DownArrow: "↓",
              DownArrowBar: "⤓",
              DownArrowUpArrow: "⇵",
              DownBreve: "̑",
              downdownarrows: "⇊",
              downharpoonleft: "⇃",
              downharpoonright: "⇂",
              DownLeftRightVector: "⥐",
              DownLeftTeeVector: "⥞",
              DownLeftVector: "↽",
              DownLeftVectorBar: "⥖",
              DownRightTeeVector: "⥟",
              DownRightVector: "⇁",
              DownRightVectorBar: "⥗",
              DownTee: "⊤",
              DownTeeArrow: "↧",
              drbkarow: "⤐",
              drcorn: "⌟",
              drcrop: "⌌",
              dscr: "𝒹",
              Dscr: "𝒟",
              dscy: "ѕ",
              DScy: "Ѕ",
              dsol: "⧶",
              dstrok: "đ",
              Dstrok: "Đ",
              dtdot: "⋱",
              dtri: "▿",
              dtrif: "▾",
              duarr: "⇵",
              duhar: "⥯",
              dwangle: "⦦",
              dzcy: "џ",
              DZcy: "Џ",
              dzigrarr: "⟿",
              eacute: "é",
              Eacute: "É",
              easter: "⩮",
              ecaron: "ě",
              Ecaron: "Ě",
              ecir: "≖",
              ecirc: "ê",
              Ecirc: "Ê",
              ecolon: "≕",
              ecy: "э",
              Ecy: "Э",
              eDDot: "⩷",
              edot: "ė",
              eDot: "≑",
              Edot: "Ė",
              ee: "ⅇ",
              efDot: "≒",
              efr: "𝔢",
              Efr: "𝔈",
              eg: "⪚",
              egrave: "è",
              Egrave: "È",
              egs: "⪖",
              egsdot: "⪘",
              el: "⪙",
              Element: "∈",
              elinters: "⏧",
              ell: "ℓ",
              els: "⪕",
              elsdot: "⪗",
              emacr: "ē",
              Emacr: "Ē",
              empty: "∅",
              emptyset: "∅",
              EmptySmallSquare: "◻",
              emptyv: "∅",
              EmptyVerySmallSquare: "▫",
              emsp: " ",
              emsp13: " ",
              emsp14: " ",
              eng: "ŋ",
              ENG: "Ŋ",
              ensp: " ",
              eogon: "ę",
              Eogon: "Ę",
              eopf: "𝕖",
              Eopf: "𝔼",
              epar: "⋕",
              eparsl: "⧣",
              eplus: "⩱",
              epsi: "ε",
              epsilon: "ε",
              Epsilon: "Ε",
              epsiv: "ϵ",
              eqcirc: "≖",
              eqcolon: "≕",
              eqsim: "≂",
              eqslantgtr: "⪖",
              eqslantless: "⪕",
              Equal: "⩵",
              equals: "=",
              EqualTilde: "≂",
              equest: "≟",
              Equilibrium: "⇌",
              equiv: "≡",
              equivDD: "⩸",
              eqvparsl: "⧥",
              erarr: "⥱",
              erDot: "≓",
              escr: "ℯ",
              Escr: "ℰ",
              esdot: "≐",
              esim: "≂",
              Esim: "⩳",
              eta: "η",
              Eta: "Η",
              eth: "ð",
              ETH: "Ð",
              euml: "ë",
              Euml: "Ë",
              euro: "€",
              excl: "!",
              exist: "∃",
              Exists: "∃",
              expectation: "ℰ",
              exponentiale: "ⅇ",
              ExponentialE: "ⅇ",
              fallingdotseq: "≒",
              fcy: "ф",
              Fcy: "Ф",
              female: "♀",
              ffilig: "ﬃ",
              fflig: "ﬀ",
              ffllig: "ﬄ",
              ffr: "𝔣",
              Ffr: "𝔉",
              filig: "ﬁ",
              FilledSmallSquare: "◼",
              FilledVerySmallSquare: "▪",
              fjlig: "fj",
              flat: "♭",
              fllig: "ﬂ",
              fltns: "▱",
              fnof: "ƒ",
              fopf: "𝕗",
              Fopf: "𝔽",
              forall: "∀",
              ForAll: "∀",
              fork: "⋔",
              forkv: "⫙",
              Fouriertrf: "ℱ",
              fpartint: "⨍",
              frac12: "½",
              frac13: "⅓",
              frac14: "¼",
              frac15: "⅕",
              frac16: "⅙",
              frac18: "⅛",
              frac23: "⅔",
              frac25: "⅖",
              frac34: "¾",
              frac35: "⅗",
              frac38: "⅜",
              frac45: "⅘",
              frac56: "⅚",
              frac58: "⅝",
              frac78: "⅞",
              frasl: "⁄",
              frown: "⌢",
              fscr: "𝒻",
              Fscr: "ℱ",
              gacute: "ǵ",
              gamma: "γ",
              Gamma: "Γ",
              gammad: "ϝ",
              Gammad: "Ϝ",
              gap: "⪆",
              gbreve: "ğ",
              Gbreve: "Ğ",
              Gcedil: "Ģ",
              gcirc: "ĝ",
              Gcirc: "Ĝ",
              gcy: "г",
              Gcy: "Г",
              gdot: "ġ",
              Gdot: "Ġ",
              ge: "≥",
              gE: "≧",
              gel: "⋛",
              gEl: "⪌",
              geq: "≥",
              geqq: "≧",
              geqslant: "⩾",
              ges: "⩾",
              gescc: "⪩",
              gesdot: "⪀",
              gesdoto: "⪂",
              gesdotol: "⪄",
              gesl: "⋛︀",
              gesles: "⪔",
              gfr: "𝔤",
              Gfr: "𝔊",
              gg: "≫",
              Gg: "⋙",
              ggg: "⋙",
              gimel: "ℷ",
              gjcy: "ѓ",
              GJcy: "Ѓ",
              gl: "≷",
              gla: "⪥",
              glE: "⪒",
              glj: "⪤",
              gnap: "⪊",
              gnapprox: "⪊",
              gne: "⪈",
              gnE: "≩",
              gneq: "⪈",
              gneqq: "≩",
              gnsim: "⋧",
              gopf: "𝕘",
              Gopf: "𝔾",
              grave: "`",
              GreaterEqual: "≥",
              GreaterEqualLess: "⋛",
              GreaterFullEqual: "≧",
              GreaterGreater: "⪢",
              GreaterLess: "≷",
              GreaterSlantEqual: "⩾",
              GreaterTilde: "≳",
              gscr: "ℊ",
              Gscr: "𝒢",
              gsim: "≳",
              gsime: "⪎",
              gsiml: "⪐",
              gt: ">",
              Gt: "≫",
              GT: ">",
              gtcc: "⪧",
              gtcir: "⩺",
              gtdot: "⋗",
              gtlPar: "⦕",
              gtquest: "⩼",
              gtrapprox: "⪆",
              gtrarr: "⥸",
              gtrdot: "⋗",
              gtreqless: "⋛",
              gtreqqless: "⪌",
              gtrless: "≷",
              gtrsim: "≳",
              gvertneqq: "≩︀",
              gvnE: "≩︀",
              Hacek: "ˇ",
              hairsp: " ",
              half: "½",
              hamilt: "ℋ",
              hardcy: "ъ",
              HARDcy: "Ъ",
              harr: "↔",
              hArr: "⇔",
              harrcir: "⥈",
              harrw: "↭",
              Hat: "^",
              hbar: "ℏ",
              hcirc: "ĥ",
              Hcirc: "Ĥ",
              hearts: "♥",
              heartsuit: "♥",
              hellip: "…",
              hercon: "⊹",
              hfr: "𝔥",
              Hfr: "ℌ",
              HilbertSpace: "ℋ",
              hksearow: "⤥",
              hkswarow: "⤦",
              hoarr: "⇿",
              homtht: "∻",
              hookleftarrow: "↩",
              hookrightarrow: "↪",
              hopf: "𝕙",
              Hopf: "ℍ",
              horbar: "―",
              HorizontalLine: "─",
              hscr: "𝒽",
              Hscr: "ℋ",
              hslash: "ℏ",
              hstrok: "ħ",
              Hstrok: "Ħ",
              HumpDownHump: "≎",
              HumpEqual: "≏",
              hybull: "⁃",
              hyphen: "‐",
              iacute: "í",
              Iacute: "Í",
              ic: "⁣",
              icirc: "î",
              Icirc: "Î",
              icy: "и",
              Icy: "И",
              Idot: "İ",
              iecy: "е",
              IEcy: "Е",
              iexcl: "¡",
              iff: "⇔",
              ifr: "𝔦",
              Ifr: "ℑ",
              igrave: "ì",
              Igrave: "Ì",
              ii: "ⅈ",
              iiiint: "⨌",
              iiint: "∭",
              iinfin: "⧜",
              iiota: "℩",
              ijlig: "ĳ",
              IJlig: "Ĳ",
              Im: "ℑ",
              imacr: "ī",
              Imacr: "Ī",
              image: "ℑ",
              ImaginaryI: "ⅈ",
              imagline: "ℐ",
              imagpart: "ℑ",
              imath: "ı",
              imof: "⊷",
              imped: "Ƶ",
              Implies: "⇒",
              in: "∈",
              incare: "℅",
              infin: "∞",
              infintie: "⧝",
              inodot: "ı",
              int: "∫",
              Int: "∬",
              intcal: "⊺",
              integers: "ℤ",
              Integral: "∫",
              intercal: "⊺",
              Intersection: "⋂",
              intlarhk: "⨗",
              intprod: "⨼",
              InvisibleComma: "⁣",
              InvisibleTimes: "⁢",
              iocy: "ё",
              IOcy: "Ё",
              iogon: "į",
              Iogon: "Į",
              iopf: "𝕚",
              Iopf: "𝕀",
              iota: "ι",
              Iota: "Ι",
              iprod: "⨼",
              iquest: "¿",
              iscr: "𝒾",
              Iscr: "ℐ",
              isin: "∈",
              isindot: "⋵",
              isinE: "⋹",
              isins: "⋴",
              isinsv: "⋳",
              isinv: "∈",
              it: "⁢",
              itilde: "ĩ",
              Itilde: "Ĩ",
              iukcy: "і",
              Iukcy: "І",
              iuml: "ï",
              Iuml: "Ï",
              jcirc: "ĵ",
              Jcirc: "Ĵ",
              jcy: "й",
              Jcy: "Й",
              jfr: "𝔧",
              Jfr: "𝔍",
              jmath: "ȷ",
              jopf: "𝕛",
              Jopf: "𝕁",
              jscr: "𝒿",
              Jscr: "𝒥",
              jsercy: "ј",
              Jsercy: "Ј",
              jukcy: "є",
              Jukcy: "Є",
              kappa: "κ",
              Kappa: "Κ",
              kappav: "ϰ",
              kcedil: "ķ",
              Kcedil: "Ķ",
              kcy: "к",
              Kcy: "К",
              kfr: "𝔨",
              Kfr: "𝔎",
              kgreen: "ĸ",
              khcy: "х",
              KHcy: "Х",
              kjcy: "ќ",
              KJcy: "Ќ",
              kopf: "𝕜",
              Kopf: "𝕂",
              kscr: "𝓀",
              Kscr: "𝒦",
              lAarr: "⇚",
              lacute: "ĺ",
              Lacute: "Ĺ",
              laemptyv: "⦴",
              lagran: "ℒ",
              lambda: "λ",
              Lambda: "Λ",
              lang: "⟨",
              Lang: "⟪",
              langd: "⦑",
              langle: "⟨",
              lap: "⪅",
              Laplacetrf: "ℒ",
              laquo: "«",
              larr: "←",
              lArr: "⇐",
              Larr: "↞",
              larrb: "⇤",
              larrbfs: "⤟",
              larrfs: "⤝",
              larrhk: "↩",
              larrlp: "↫",
              larrpl: "⤹",
              larrsim: "⥳",
              larrtl: "↢",
              lat: "⪫",
              latail: "⤙",
              lAtail: "⤛",
              late: "⪭",
              lates: "⪭︀",
              lbarr: "⤌",
              lBarr: "⤎",
              lbbrk: "❲",
              lbrace: "{",
              lbrack: "[",
              lbrke: "⦋",
              lbrksld: "⦏",
              lbrkslu: "⦍",
              lcaron: "ľ",
              Lcaron: "Ľ",
              lcedil: "ļ",
              Lcedil: "Ļ",
              lceil: "⌈",
              lcub: "{",
              lcy: "л",
              Lcy: "Л",
              ldca: "⤶",
              ldquo: "“",
              ldquor: "„",
              ldrdhar: "⥧",
              ldrushar: "⥋",
              ldsh: "↲",
              le: "≤",
              lE: "≦",
              LeftAngleBracket: "⟨",
              leftarrow: "←",
              Leftarrow: "⇐",
              LeftArrow: "←",
              LeftArrowBar: "⇤",
              LeftArrowRightArrow: "⇆",
              leftarrowtail: "↢",
              LeftCeiling: "⌈",
              LeftDoubleBracket: "⟦",
              LeftDownTeeVector: "⥡",
              LeftDownVector: "⇃",
              LeftDownVectorBar: "⥙",
              LeftFloor: "⌊",
              leftharpoondown: "↽",
              leftharpoonup: "↼",
              leftleftarrows: "⇇",
              leftrightarrow: "↔",
              Leftrightarrow: "⇔",
              LeftRightArrow: "↔",
              leftrightarrows: "⇆",
              leftrightharpoons: "⇋",
              leftrightsquigarrow: "↭",
              LeftRightVector: "⥎",
              LeftTee: "⊣",
              LeftTeeArrow: "↤",
              LeftTeeVector: "⥚",
              leftthreetimes: "⋋",
              LeftTriangle: "⊲",
              LeftTriangleBar: "⧏",
              LeftTriangleEqual: "⊴",
              LeftUpDownVector: "⥑",
              LeftUpTeeVector: "⥠",
              LeftUpVector: "↿",
              LeftUpVectorBar: "⥘",
              LeftVector: "↼",
              LeftVectorBar: "⥒",
              leg: "⋚",
              lEg: "⪋",
              leq: "≤",
              leqq: "≦",
              leqslant: "⩽",
              les: "⩽",
              lescc: "⪨",
              lesdot: "⩿",
              lesdoto: "⪁",
              lesdotor: "⪃",
              lesg: "⋚︀",
              lesges: "⪓",
              lessapprox: "⪅",
              lessdot: "⋖",
              lesseqgtr: "⋚",
              lesseqqgtr: "⪋",
              LessEqualGreater: "⋚",
              LessFullEqual: "≦",
              LessGreater: "≶",
              lessgtr: "≶",
              LessLess: "⪡",
              lesssim: "≲",
              LessSlantEqual: "⩽",
              LessTilde: "≲",
              lfisht: "⥼",
              lfloor: "⌊",
              lfr: "𝔩",
              Lfr: "𝔏",
              lg: "≶",
              lgE: "⪑",
              lHar: "⥢",
              lhard: "↽",
              lharu: "↼",
              lharul: "⥪",
              lhblk: "▄",
              ljcy: "љ",
              LJcy: "Љ",
              ll: "≪",
              Ll: "⋘",
              llarr: "⇇",
              llcorner: "⌞",
              Lleftarrow: "⇚",
              llhard: "⥫",
              lltri: "◺",
              lmidot: "ŀ",
              Lmidot: "Ŀ",
              lmoust: "⎰",
              lmoustache: "⎰",
              lnap: "⪉",
              lnapprox: "⪉",
              lne: "⪇",
              lnE: "≨",
              lneq: "⪇",
              lneqq: "≨",
              lnsim: "⋦",
              loang: "⟬",
              loarr: "⇽",
              lobrk: "⟦",
              longleftarrow: "⟵",
              Longleftarrow: "⟸",
              LongLeftArrow: "⟵",
              longleftrightarrow: "⟷",
              Longleftrightarrow: "⟺",
              LongLeftRightArrow: "⟷",
              longmapsto: "⟼",
              longrightarrow: "⟶",
              Longrightarrow: "⟹",
              LongRightArrow: "⟶",
              looparrowleft: "↫",
              looparrowright: "↬",
              lopar: "⦅",
              lopf: "𝕝",
              Lopf: "𝕃",
              loplus: "⨭",
              lotimes: "⨴",
              lowast: "∗",
              lowbar: "_",
              LowerLeftArrow: "↙",
              LowerRightArrow: "↘",
              loz: "◊",
              lozenge: "◊",
              lozf: "⧫",
              lpar: "(",
              lparlt: "⦓",
              lrarr: "⇆",
              lrcorner: "⌟",
              lrhar: "⇋",
              lrhard: "⥭",
              lrm: "‎",
              lrtri: "⊿",
              lsaquo: "‹",
              lscr: "𝓁",
              Lscr: "ℒ",
              lsh: "↰",
              Lsh: "↰",
              lsim: "≲",
              lsime: "⪍",
              lsimg: "⪏",
              lsqb: "[",
              lsquo: "‘",
              lsquor: "‚",
              lstrok: "ł",
              Lstrok: "Ł",
              lt: "<",
              Lt: "≪",
              LT: "<",
              ltcc: "⪦",
              ltcir: "⩹",
              ltdot: "⋖",
              lthree: "⋋",
              ltimes: "⋉",
              ltlarr: "⥶",
              ltquest: "⩻",
              ltri: "◃",
              ltrie: "⊴",
              ltrif: "◂",
              ltrPar: "⦖",
              lurdshar: "⥊",
              luruhar: "⥦",
              lvertneqq: "≨︀",
              lvnE: "≨︀",
              macr: "¯",
              male: "♂",
              malt: "✠",
              maltese: "✠",
              map: "↦",
              Map: "⤅",
              mapsto: "↦",
              mapstodown: "↧",
              mapstoleft: "↤",
              mapstoup: "↥",
              marker: "▮",
              mcomma: "⨩",
              mcy: "м",
              Mcy: "М",
              mdash: "—",
              mDDot: "∺",
              measuredangle: "∡",
              MediumSpace: " ",
              Mellintrf: "ℳ",
              mfr: "𝔪",
              Mfr: "𝔐",
              mho: "℧",
              micro: "µ",
              mid: "∣",
              midast: "*",
              midcir: "⫰",
              middot: "·",
              minus: "−",
              minusb: "⊟",
              minusd: "∸",
              minusdu: "⨪",
              MinusPlus: "∓",
              mlcp: "⫛",
              mldr: "…",
              mnplus: "∓",
              models: "⊧",
              mopf: "𝕞",
              Mopf: "𝕄",
              mp: "∓",
              mscr: "𝓂",
              Mscr: "ℳ",
              mstpos: "∾",
              mu: "μ",
              Mu: "Μ",
              multimap: "⊸",
              mumap: "⊸",
              nabla: "∇",
              nacute: "ń",
              Nacute: "Ń",
              nang: "∠⃒",
              nap: "≉",
              napE: "⩰̸",
              napid: "≋̸",
              napos: "ŉ",
              napprox: "≉",
              natur: "♮",
              natural: "♮",
              naturals: "ℕ",
              nbsp: " ",
              nbump: "≎̸",
              nbumpe: "≏̸",
              ncap: "⩃",
              ncaron: "ň",
              Ncaron: "Ň",
              ncedil: "ņ",
              Ncedil: "Ņ",
              ncong: "≇",
              ncongdot: "⩭̸",
              ncup: "⩂",
              ncy: "н",
              Ncy: "Н",
              ndash: "–",
              ne: "≠",
              nearhk: "⤤",
              nearr: "↗",
              neArr: "⇗",
              nearrow: "↗",
              nedot: "≐̸",
              NegativeMediumSpace: "​",
              NegativeThickSpace: "​",
              NegativeThinSpace: "​",
              NegativeVeryThinSpace: "​",
              nequiv: "≢",
              nesear: "⤨",
              nesim: "≂̸",
              NestedGreaterGreater: "≫",
              NestedLessLess: "≪",
              NewLine: `
`,
              nexist: "∄",
              nexists: "∄",
              nfr: "𝔫",
              Nfr: "𝔑",
              nge: "≱",
              ngE: "≧̸",
              ngeq: "≱",
              ngeqq: "≧̸",
              ngeqslant: "⩾̸",
              nges: "⩾̸",
              nGg: "⋙̸",
              ngsim: "≵",
              ngt: "≯",
              nGt: "≫⃒",
              ngtr: "≯",
              nGtv: "≫̸",
              nharr: "↮",
              nhArr: "⇎",
              nhpar: "⫲",
              ni: "∋",
              nis: "⋼",
              nisd: "⋺",
              niv: "∋",
              njcy: "њ",
              NJcy: "Њ",
              nlarr: "↚",
              nlArr: "⇍",
              nldr: "‥",
              nle: "≰",
              nlE: "≦̸",
              nleftarrow: "↚",
              nLeftarrow: "⇍",
              nleftrightarrow: "↮",
              nLeftrightarrow: "⇎",
              nleq: "≰",
              nleqq: "≦̸",
              nleqslant: "⩽̸",
              nles: "⩽̸",
              nless: "≮",
              nLl: "⋘̸",
              nlsim: "≴",
              nlt: "≮",
              nLt: "≪⃒",
              nltri: "⋪",
              nltrie: "⋬",
              nLtv: "≪̸",
              nmid: "∤",
              NoBreak: "⁠",
              NonBreakingSpace: " ",
              nopf: "𝕟",
              Nopf: "ℕ",
              not: "¬",
              Not: "⫬",
              NotCongruent: "≢",
              NotCupCap: "≭",
              NotDoubleVerticalBar: "∦",
              NotElement: "∉",
              NotEqual: "≠",
              NotEqualTilde: "≂̸",
              NotExists: "∄",
              NotGreater: "≯",
              NotGreaterEqual: "≱",
              NotGreaterFullEqual: "≧̸",
              NotGreaterGreater: "≫̸",
              NotGreaterLess: "≹",
              NotGreaterSlantEqual: "⩾̸",
              NotGreaterTilde: "≵",
              NotHumpDownHump: "≎̸",
              NotHumpEqual: "≏̸",
              notin: "∉",
              notindot: "⋵̸",
              notinE: "⋹̸",
              notinva: "∉",
              notinvb: "⋷",
              notinvc: "⋶",
              NotLeftTriangle: "⋪",
              NotLeftTriangleBar: "⧏̸",
              NotLeftTriangleEqual: "⋬",
              NotLess: "≮",
              NotLessEqual: "≰",
              NotLessGreater: "≸",
              NotLessLess: "≪̸",
              NotLessSlantEqual: "⩽̸",
              NotLessTilde: "≴",
              NotNestedGreaterGreater: "⪢̸",
              NotNestedLessLess: "⪡̸",
              notni: "∌",
              notniva: "∌",
              notnivb: "⋾",
              notnivc: "⋽",
              NotPrecedes: "⊀",
              NotPrecedesEqual: "⪯̸",
              NotPrecedesSlantEqual: "⋠",
              NotReverseElement: "∌",
              NotRightTriangle: "⋫",
              NotRightTriangleBar: "⧐̸",
              NotRightTriangleEqual: "⋭",
              NotSquareSubset: "⊏̸",
              NotSquareSubsetEqual: "⋢",
              NotSquareSuperset: "⊐̸",
              NotSquareSupersetEqual: "⋣",
              NotSubset: "⊂⃒",
              NotSubsetEqual: "⊈",
              NotSucceeds: "⊁",
              NotSucceedsEqual: "⪰̸",
              NotSucceedsSlantEqual: "⋡",
              NotSucceedsTilde: "≿̸",
              NotSuperset: "⊃⃒",
              NotSupersetEqual: "⊉",
              NotTilde: "≁",
              NotTildeEqual: "≄",
              NotTildeFullEqual: "≇",
              NotTildeTilde: "≉",
              NotVerticalBar: "∤",
              npar: "∦",
              nparallel: "∦",
              nparsl: "⫽⃥",
              npart: "∂̸",
              npolint: "⨔",
              npr: "⊀",
              nprcue: "⋠",
              npre: "⪯̸",
              nprec: "⊀",
              npreceq: "⪯̸",
              nrarr: "↛",
              nrArr: "⇏",
              nrarrc: "⤳̸",
              nrarrw: "↝̸",
              nrightarrow: "↛",
              nRightarrow: "⇏",
              nrtri: "⋫",
              nrtrie: "⋭",
              nsc: "⊁",
              nsccue: "⋡",
              nsce: "⪰̸",
              nscr: "𝓃",
              Nscr: "𝒩",
              nshortmid: "∤",
              nshortparallel: "∦",
              nsim: "≁",
              nsime: "≄",
              nsimeq: "≄",
              nsmid: "∤",
              nspar: "∦",
              nsqsube: "⋢",
              nsqsupe: "⋣",
              nsub: "⊄",
              nsube: "⊈",
              nsubE: "⫅̸",
              nsubset: "⊂⃒",
              nsubseteq: "⊈",
              nsubseteqq: "⫅̸",
              nsucc: "⊁",
              nsucceq: "⪰̸",
              nsup: "⊅",
              nsupe: "⊉",
              nsupE: "⫆̸",
              nsupset: "⊃⃒",
              nsupseteq: "⊉",
              nsupseteqq: "⫆̸",
              ntgl: "≹",
              ntilde: "ñ",
              Ntilde: "Ñ",
              ntlg: "≸",
              ntriangleleft: "⋪",
              ntrianglelefteq: "⋬",
              ntriangleright: "⋫",
              ntrianglerighteq: "⋭",
              nu: "ν",
              Nu: "Ν",
              num: "#",
              numero: "№",
              numsp: " ",
              nvap: "≍⃒",
              nvdash: "⊬",
              nvDash: "⊭",
              nVdash: "⊮",
              nVDash: "⊯",
              nvge: "≥⃒",
              nvgt: ">⃒",
              nvHarr: "⤄",
              nvinfin: "⧞",
              nvlArr: "⤂",
              nvle: "≤⃒",
              nvlt: "<⃒",
              nvltrie: "⊴⃒",
              nvrArr: "⤃",
              nvrtrie: "⊵⃒",
              nvsim: "∼⃒",
              nwarhk: "⤣",
              nwarr: "↖",
              nwArr: "⇖",
              nwarrow: "↖",
              nwnear: "⤧",
              oacute: "ó",
              Oacute: "Ó",
              oast: "⊛",
              ocir: "⊚",
              ocirc: "ô",
              Ocirc: "Ô",
              ocy: "о",
              Ocy: "О",
              odash: "⊝",
              odblac: "ő",
              Odblac: "Ő",
              odiv: "⨸",
              odot: "⊙",
              odsold: "⦼",
              oelig: "œ",
              OElig: "Œ",
              ofcir: "⦿",
              ofr: "𝔬",
              Ofr: "𝔒",
              ogon: "˛",
              ograve: "ò",
              Ograve: "Ò",
              ogt: "⧁",
              ohbar: "⦵",
              ohm: "Ω",
              oint: "∮",
              olarr: "↺",
              olcir: "⦾",
              olcross: "⦻",
              oline: "‾",
              olt: "⧀",
              omacr: "ō",
              Omacr: "Ō",
              omega: "ω",
              Omega: "Ω",
              omicron: "ο",
              Omicron: "Ο",
              omid: "⦶",
              ominus: "⊖",
              oopf: "𝕠",
              Oopf: "𝕆",
              opar: "⦷",
              OpenCurlyDoubleQuote: "“",
              OpenCurlyQuote: "‘",
              operp: "⦹",
              oplus: "⊕",
              or: "∨",
              Or: "⩔",
              orarr: "↻",
              ord: "⩝",
              order: "ℴ",
              orderof: "ℴ",
              ordf: "ª",
              ordm: "º",
              origof: "⊶",
              oror: "⩖",
              orslope: "⩗",
              orv: "⩛",
              oS: "Ⓢ",
              oscr: "ℴ",
              Oscr: "𝒪",
              oslash: "ø",
              Oslash: "Ø",
              osol: "⊘",
              otilde: "õ",
              Otilde: "Õ",
              otimes: "⊗",
              Otimes: "⨷",
              otimesas: "⨶",
              ouml: "ö",
              Ouml: "Ö",
              ovbar: "⌽",
              OverBar: "‾",
              OverBrace: "⏞",
              OverBracket: "⎴",
              OverParenthesis: "⏜",
              par: "∥",
              para: "¶",
              parallel: "∥",
              parsim: "⫳",
              parsl: "⫽",
              part: "∂",
              PartialD: "∂",
              pcy: "п",
              Pcy: "П",
              percnt: "%",
              period: ".",
              permil: "‰",
              perp: "⊥",
              pertenk: "‱",
              pfr: "𝔭",
              Pfr: "𝔓",
              phi: "φ",
              Phi: "Φ",
              phiv: "ϕ",
              phmmat: "ℳ",
              phone: "☎",
              pi: "π",
              Pi: "Π",
              pitchfork: "⋔",
              piv: "ϖ",
              planck: "ℏ",
              planckh: "ℎ",
              plankv: "ℏ",
              plus: "+",
              plusacir: "⨣",
              plusb: "⊞",
              pluscir: "⨢",
              plusdo: "∔",
              plusdu: "⨥",
              pluse: "⩲",
              PlusMinus: "±",
              plusmn: "±",
              plussim: "⨦",
              plustwo: "⨧",
              pm: "±",
              Poincareplane: "ℌ",
              pointint: "⨕",
              popf: "𝕡",
              Popf: "ℙ",
              pound: "£",
              pr: "≺",
              Pr: "⪻",
              prap: "⪷",
              prcue: "≼",
              pre: "⪯",
              prE: "⪳",
              prec: "≺",
              precapprox: "⪷",
              preccurlyeq: "≼",
              Precedes: "≺",
              PrecedesEqual: "⪯",
              PrecedesSlantEqual: "≼",
              PrecedesTilde: "≾",
              preceq: "⪯",
              precnapprox: "⪹",
              precneqq: "⪵",
              precnsim: "⋨",
              precsim: "≾",
              prime: "′",
              Prime: "″",
              primes: "ℙ",
              prnap: "⪹",
              prnE: "⪵",
              prnsim: "⋨",
              prod: "∏",
              Product: "∏",
              profalar: "⌮",
              profline: "⌒",
              profsurf: "⌓",
              prop: "∝",
              Proportion: "∷",
              Proportional: "∝",
              propto: "∝",
              prsim: "≾",
              prurel: "⊰",
              pscr: "𝓅",
              Pscr: "𝒫",
              psi: "ψ",
              Psi: "Ψ",
              puncsp: " ",
              qfr: "𝔮",
              Qfr: "𝔔",
              qint: "⨌",
              qopf: "𝕢",
              Qopf: "ℚ",
              qprime: "⁗",
              qscr: "𝓆",
              Qscr: "𝒬",
              quaternions: "ℍ",
              quatint: "⨖",
              quest: "?",
              questeq: "≟",
              quot: '"',
              QUOT: '"',
              rAarr: "⇛",
              race: "∽̱",
              racute: "ŕ",
              Racute: "Ŕ",
              radic: "√",
              raemptyv: "⦳",
              rang: "⟩",
              Rang: "⟫",
              rangd: "⦒",
              range: "⦥",
              rangle: "⟩",
              raquo: "»",
              rarr: "→",
              rArr: "⇒",
              Rarr: "↠",
              rarrap: "⥵",
              rarrb: "⇥",
              rarrbfs: "⤠",
              rarrc: "⤳",
              rarrfs: "⤞",
              rarrhk: "↪",
              rarrlp: "↬",
              rarrpl: "⥅",
              rarrsim: "⥴",
              rarrtl: "↣",
              Rarrtl: "⤖",
              rarrw: "↝",
              ratail: "⤚",
              rAtail: "⤜",
              ratio: "∶",
              rationals: "ℚ",
              rbarr: "⤍",
              rBarr: "⤏",
              RBarr: "⤐",
              rbbrk: "❳",
              rbrace: "}",
              rbrack: "]",
              rbrke: "⦌",
              rbrksld: "⦎",
              rbrkslu: "⦐",
              rcaron: "ř",
              Rcaron: "Ř",
              rcedil: "ŗ",
              Rcedil: "Ŗ",
              rceil: "⌉",
              rcub: "}",
              rcy: "р",
              Rcy: "Р",
              rdca: "⤷",
              rdldhar: "⥩",
              rdquo: "”",
              rdquor: "”",
              rdsh: "↳",
              Re: "ℜ",
              real: "ℜ",
              realine: "ℛ",
              realpart: "ℜ",
              reals: "ℝ",
              rect: "▭",
              reg: "®",
              REG: "®",
              ReverseElement: "∋",
              ReverseEquilibrium: "⇋",
              ReverseUpEquilibrium: "⥯",
              rfisht: "⥽",
              rfloor: "⌋",
              rfr: "𝔯",
              Rfr: "ℜ",
              rHar: "⥤",
              rhard: "⇁",
              rharu: "⇀",
              rharul: "⥬",
              rho: "ρ",
              Rho: "Ρ",
              rhov: "ϱ",
              RightAngleBracket: "⟩",
              rightarrow: "→",
              Rightarrow: "⇒",
              RightArrow: "→",
              RightArrowBar: "⇥",
              RightArrowLeftArrow: "⇄",
              rightarrowtail: "↣",
              RightCeiling: "⌉",
              RightDoubleBracket: "⟧",
              RightDownTeeVector: "⥝",
              RightDownVector: "⇂",
              RightDownVectorBar: "⥕",
              RightFloor: "⌋",
              rightharpoondown: "⇁",
              rightharpoonup: "⇀",
              rightleftarrows: "⇄",
              rightleftharpoons: "⇌",
              rightrightarrows: "⇉",
              rightsquigarrow: "↝",
              RightTee: "⊢",
              RightTeeArrow: "↦",
              RightTeeVector: "⥛",
              rightthreetimes: "⋌",
              RightTriangle: "⊳",
              RightTriangleBar: "⧐",
              RightTriangleEqual: "⊵",
              RightUpDownVector: "⥏",
              RightUpTeeVector: "⥜",
              RightUpVector: "↾",
              RightUpVectorBar: "⥔",
              RightVector: "⇀",
              RightVectorBar: "⥓",
              ring: "˚",
              risingdotseq: "≓",
              rlarr: "⇄",
              rlhar: "⇌",
              rlm: "‏",
              rmoust: "⎱",
              rmoustache: "⎱",
              rnmid: "⫮",
              roang: "⟭",
              roarr: "⇾",
              robrk: "⟧",
              ropar: "⦆",
              ropf: "𝕣",
              Ropf: "ℝ",
              roplus: "⨮",
              rotimes: "⨵",
              RoundImplies: "⥰",
              rpar: ")",
              rpargt: "⦔",
              rppolint: "⨒",
              rrarr: "⇉",
              Rrightarrow: "⇛",
              rsaquo: "›",
              rscr: "𝓇",
              Rscr: "ℛ",
              rsh: "↱",
              Rsh: "↱",
              rsqb: "]",
              rsquo: "’",
              rsquor: "’",
              rthree: "⋌",
              rtimes: "⋊",
              rtri: "▹",
              rtrie: "⊵",
              rtrif: "▸",
              rtriltri: "⧎",
              RuleDelayed: "⧴",
              ruluhar: "⥨",
              rx: "℞",
              sacute: "ś",
              Sacute: "Ś",
              sbquo: "‚",
              sc: "≻",
              Sc: "⪼",
              scap: "⪸",
              scaron: "š",
              Scaron: "Š",
              sccue: "≽",
              sce: "⪰",
              scE: "⪴",
              scedil: "ş",
              Scedil: "Ş",
              scirc: "ŝ",
              Scirc: "Ŝ",
              scnap: "⪺",
              scnE: "⪶",
              scnsim: "⋩",
              scpolint: "⨓",
              scsim: "≿",
              scy: "с",
              Scy: "С",
              sdot: "⋅",
              sdotb: "⊡",
              sdote: "⩦",
              searhk: "⤥",
              searr: "↘",
              seArr: "⇘",
              searrow: "↘",
              sect: "§",
              semi: ";",
              seswar: "⤩",
              setminus: "∖",
              setmn: "∖",
              sext: "✶",
              sfr: "𝔰",
              Sfr: "𝔖",
              sfrown: "⌢",
              sharp: "♯",
              shchcy: "щ",
              SHCHcy: "Щ",
              shcy: "ш",
              SHcy: "Ш",
              ShortDownArrow: "↓",
              ShortLeftArrow: "←",
              shortmid: "∣",
              shortparallel: "∥",
              ShortRightArrow: "→",
              ShortUpArrow: "↑",
              shy: "­",
              sigma: "σ",
              Sigma: "Σ",
              sigmaf: "ς",
              sigmav: "ς",
              sim: "∼",
              simdot: "⩪",
              sime: "≃",
              simeq: "≃",
              simg: "⪞",
              simgE: "⪠",
              siml: "⪝",
              simlE: "⪟",
              simne: "≆",
              simplus: "⨤",
              simrarr: "⥲",
              slarr: "←",
              SmallCircle: "∘",
              smallsetminus: "∖",
              smashp: "⨳",
              smeparsl: "⧤",
              smid: "∣",
              smile: "⌣",
              smt: "⪪",
              smte: "⪬",
              smtes: "⪬︀",
              softcy: "ь",
              SOFTcy: "Ь",
              sol: "/",
              solb: "⧄",
              solbar: "⌿",
              sopf: "𝕤",
              Sopf: "𝕊",
              spades: "♠",
              spadesuit: "♠",
              spar: "∥",
              sqcap: "⊓",
              sqcaps: "⊓︀",
              sqcup: "⊔",
              sqcups: "⊔︀",
              Sqrt: "√",
              sqsub: "⊏",
              sqsube: "⊑",
              sqsubset: "⊏",
              sqsubseteq: "⊑",
              sqsup: "⊐",
              sqsupe: "⊒",
              sqsupset: "⊐",
              sqsupseteq: "⊒",
              squ: "□",
              square: "□",
              Square: "□",
              SquareIntersection: "⊓",
              SquareSubset: "⊏",
              SquareSubsetEqual: "⊑",
              SquareSuperset: "⊐",
              SquareSupersetEqual: "⊒",
              SquareUnion: "⊔",
              squarf: "▪",
              squf: "▪",
              srarr: "→",
              sscr: "𝓈",
              Sscr: "𝒮",
              ssetmn: "∖",
              ssmile: "⌣",
              sstarf: "⋆",
              star: "☆",
              Star: "⋆",
              starf: "★",
              straightepsilon: "ϵ",
              straightphi: "ϕ",
              strns: "¯",
              sub: "⊂",
              Sub: "⋐",
              subdot: "⪽",
              sube: "⊆",
              subE: "⫅",
              subedot: "⫃",
              submult: "⫁",
              subne: "⊊",
              subnE: "⫋",
              subplus: "⪿",
              subrarr: "⥹",
              subset: "⊂",
              Subset: "⋐",
              subseteq: "⊆",
              subseteqq: "⫅",
              SubsetEqual: "⊆",
              subsetneq: "⊊",
              subsetneqq: "⫋",
              subsim: "⫇",
              subsub: "⫕",
              subsup: "⫓",
              succ: "≻",
              succapprox: "⪸",
              succcurlyeq: "≽",
              Succeeds: "≻",
              SucceedsEqual: "⪰",
              SucceedsSlantEqual: "≽",
              SucceedsTilde: "≿",
              succeq: "⪰",
              succnapprox: "⪺",
              succneqq: "⪶",
              succnsim: "⋩",
              succsim: "≿",
              SuchThat: "∋",
              sum: "∑",
              Sum: "∑",
              sung: "♪",
              sup: "⊃",
              Sup: "⋑",
              sup1: "¹",
              sup2: "²",
              sup3: "³",
              supdot: "⪾",
              supdsub: "⫘",
              supe: "⊇",
              supE: "⫆",
              supedot: "⫄",
              Superset: "⊃",
              SupersetEqual: "⊇",
              suphsol: "⟉",
              suphsub: "⫗",
              suplarr: "⥻",
              supmult: "⫂",
              supne: "⊋",
              supnE: "⫌",
              supplus: "⫀",
              supset: "⊃",
              Supset: "⋑",
              supseteq: "⊇",
              supseteqq: "⫆",
              supsetneq: "⊋",
              supsetneqq: "⫌",
              supsim: "⫈",
              supsub: "⫔",
              supsup: "⫖",
              swarhk: "⤦",
              swarr: "↙",
              swArr: "⇙",
              swarrow: "↙",
              swnwar: "⤪",
              szlig: "ß",
              Tab: "	",
              target: "⌖",
              tau: "τ",
              Tau: "Τ",
              tbrk: "⎴",
              tcaron: "ť",
              Tcaron: "Ť",
              tcedil: "ţ",
              Tcedil: "Ţ",
              tcy: "т",
              Tcy: "Т",
              tdot: "⃛",
              telrec: "⌕",
              tfr: "𝔱",
              Tfr: "𝔗",
              there4: "∴",
              therefore: "∴",
              Therefore: "∴",
              theta: "θ",
              Theta: "Θ",
              thetasym: "ϑ",
              thetav: "ϑ",
              thickapprox: "≈",
              thicksim: "∼",
              ThickSpace: "  ",
              thinsp: " ",
              ThinSpace: " ",
              thkap: "≈",
              thksim: "∼",
              thorn: "þ",
              THORN: "Þ",
              tilde: "˜",
              Tilde: "∼",
              TildeEqual: "≃",
              TildeFullEqual: "≅",
              TildeTilde: "≈",
              times: "×",
              timesb: "⊠",
              timesbar: "⨱",
              timesd: "⨰",
              tint: "∭",
              toea: "⤨",
              top: "⊤",
              topbot: "⌶",
              topcir: "⫱",
              topf: "𝕥",
              Topf: "𝕋",
              topfork: "⫚",
              tosa: "⤩",
              tprime: "‴",
              trade: "™",
              TRADE: "™",
              triangle: "▵",
              triangledown: "▿",
              triangleleft: "◃",
              trianglelefteq: "⊴",
              triangleq: "≜",
              triangleright: "▹",
              trianglerighteq: "⊵",
              tridot: "◬",
              trie: "≜",
              triminus: "⨺",
              TripleDot: "⃛",
              triplus: "⨹",
              trisb: "⧍",
              tritime: "⨻",
              trpezium: "⏢",
              tscr: "𝓉",
              Tscr: "𝒯",
              tscy: "ц",
              TScy: "Ц",
              tshcy: "ћ",
              TSHcy: "Ћ",
              tstrok: "ŧ",
              Tstrok: "Ŧ",
              twixt: "≬",
              twoheadleftarrow: "↞",
              twoheadrightarrow: "↠",
              uacute: "ú",
              Uacute: "Ú",
              uarr: "↑",
              uArr: "⇑",
              Uarr: "↟",
              Uarrocir: "⥉",
              ubrcy: "ў",
              Ubrcy: "Ў",
              ubreve: "ŭ",
              Ubreve: "Ŭ",
              ucirc: "û",
              Ucirc: "Û",
              ucy: "у",
              Ucy: "У",
              udarr: "⇅",
              udblac: "ű",
              Udblac: "Ű",
              udhar: "⥮",
              ufisht: "⥾",
              ufr: "𝔲",
              Ufr: "𝔘",
              ugrave: "ù",
              Ugrave: "Ù",
              uHar: "⥣",
              uharl: "↿",
              uharr: "↾",
              uhblk: "▀",
              ulcorn: "⌜",
              ulcorner: "⌜",
              ulcrop: "⌏",
              ultri: "◸",
              umacr: "ū",
              Umacr: "Ū",
              uml: "¨",
              UnderBar: "_",
              UnderBrace: "⏟",
              UnderBracket: "⎵",
              UnderParenthesis: "⏝",
              Union: "⋃",
              UnionPlus: "⊎",
              uogon: "ų",
              Uogon: "Ų",
              uopf: "𝕦",
              Uopf: "𝕌",
              uparrow: "↑",
              Uparrow: "⇑",
              UpArrow: "↑",
              UpArrowBar: "⤒",
              UpArrowDownArrow: "⇅",
              updownarrow: "↕",
              Updownarrow: "⇕",
              UpDownArrow: "↕",
              UpEquilibrium: "⥮",
              upharpoonleft: "↿",
              upharpoonright: "↾",
              uplus: "⊎",
              UpperLeftArrow: "↖",
              UpperRightArrow: "↗",
              upsi: "υ",
              Upsi: "ϒ",
              upsih: "ϒ",
              upsilon: "υ",
              Upsilon: "Υ",
              UpTee: "⊥",
              UpTeeArrow: "↥",
              upuparrows: "⇈",
              urcorn: "⌝",
              urcorner: "⌝",
              urcrop: "⌎",
              uring: "ů",
              Uring: "Ů",
              urtri: "◹",
              uscr: "𝓊",
              Uscr: "𝒰",
              utdot: "⋰",
              utilde: "ũ",
              Utilde: "Ũ",
              utri: "▵",
              utrif: "▴",
              uuarr: "⇈",
              uuml: "ü",
              Uuml: "Ü",
              uwangle: "⦧",
              vangrt: "⦜",
              varepsilon: "ϵ",
              varkappa: "ϰ",
              varnothing: "∅",
              varphi: "ϕ",
              varpi: "ϖ",
              varpropto: "∝",
              varr: "↕",
              vArr: "⇕",
              varrho: "ϱ",
              varsigma: "ς",
              varsubsetneq: "⊊︀",
              varsubsetneqq: "⫋︀",
              varsupsetneq: "⊋︀",
              varsupsetneqq: "⫌︀",
              vartheta: "ϑ",
              vartriangleleft: "⊲",
              vartriangleright: "⊳",
              vBar: "⫨",
              Vbar: "⫫",
              vBarv: "⫩",
              vcy: "в",
              Vcy: "В",
              vdash: "⊢",
              vDash: "⊨",
              Vdash: "⊩",
              VDash: "⊫",
              Vdashl: "⫦",
              vee: "∨",
              Vee: "⋁",
              veebar: "⊻",
              veeeq: "≚",
              vellip: "⋮",
              verbar: "|",
              Verbar: "‖",
              vert: "|",
              Vert: "‖",
              VerticalBar: "∣",
              VerticalLine: "|",
              VerticalSeparator: "❘",
              VerticalTilde: "≀",
              VeryThinSpace: " ",
              vfr: "𝔳",
              Vfr: "𝔙",
              vltri: "⊲",
              vnsub: "⊂⃒",
              vnsup: "⊃⃒",
              vopf: "𝕧",
              Vopf: "𝕍",
              vprop: "∝",
              vrtri: "⊳",
              vscr: "𝓋",
              Vscr: "𝒱",
              vsubne: "⊊︀",
              vsubnE: "⫋︀",
              vsupne: "⊋︀",
              vsupnE: "⫌︀",
              Vvdash: "⊪",
              vzigzag: "⦚",
              wcirc: "ŵ",
              Wcirc: "Ŵ",
              wedbar: "⩟",
              wedge: "∧",
              Wedge: "⋀",
              wedgeq: "≙",
              weierp: "℘",
              wfr: "𝔴",
              Wfr: "𝔚",
              wopf: "𝕨",
              Wopf: "𝕎",
              wp: "℘",
              wr: "≀",
              wreath: "≀",
              wscr: "𝓌",
              Wscr: "𝒲",
              xcap: "⋂",
              xcirc: "◯",
              xcup: "⋃",
              xdtri: "▽",
              xfr: "𝔵",
              Xfr: "𝔛",
              xharr: "⟷",
              xhArr: "⟺",
              xi: "ξ",
              Xi: "Ξ",
              xlarr: "⟵",
              xlArr: "⟸",
              xmap: "⟼",
              xnis: "⋻",
              xodot: "⨀",
              xopf: "𝕩",
              Xopf: "𝕏",
              xoplus: "⨁",
              xotime: "⨂",
              xrarr: "⟶",
              xrArr: "⟹",
              xscr: "𝓍",
              Xscr: "𝒳",
              xsqcup: "⨆",
              xuplus: "⨄",
              xutri: "△",
              xvee: "⋁",
              xwedge: "⋀",
              yacute: "ý",
              Yacute: "Ý",
              yacy: "я",
              YAcy: "Я",
              ycirc: "ŷ",
              Ycirc: "Ŷ",
              ycy: "ы",
              Ycy: "Ы",
              yen: "¥",
              yfr: "𝔶",
              Yfr: "𝔜",
              yicy: "ї",
              YIcy: "Ї",
              yopf: "𝕪",
              Yopf: "𝕐",
              yscr: "𝓎",
              Yscr: "𝒴",
              yucy: "ю",
              YUcy: "Ю",
              yuml: "ÿ",
              Yuml: "Ÿ",
              zacute: "ź",
              Zacute: "Ź",
              zcaron: "ž",
              Zcaron: "Ž",
              zcy: "з",
              Zcy: "З",
              zdot: "ż",
              Zdot: "Ż",
              zeetrf: "ℨ",
              ZeroWidthSpace: "​",
              zeta: "ζ",
              Zeta: "Ζ",
              zfr: "𝔷",
              Zfr: "ℨ",
              zhcy: "ж",
              ZHcy: "Ж",
              zigrarr: "⇝",
              zopf: "𝕫",
              Zopf: "ℤ",
              zscr: "𝓏",
              Zscr: "𝒵",
              zwj: "‍",
              zwnj: "‌",
            },
            T = {
              aacute: "á",
              Aacute: "Á",
              acirc: "â",
              Acirc: "Â",
              acute: "´",
              aelig: "æ",
              AElig: "Æ",
              agrave: "à",
              Agrave: "À",
              amp: "&",
              AMP: "&",
              aring: "å",
              Aring: "Å",
              atilde: "ã",
              Atilde: "Ã",
              auml: "ä",
              Auml: "Ä",
              brvbar: "¦",
              ccedil: "ç",
              Ccedil: "Ç",
              cedil: "¸",
              cent: "¢",
              copy: "©",
              COPY: "©",
              curren: "¤",
              deg: "°",
              divide: "÷",
              eacute: "é",
              Eacute: "É",
              ecirc: "ê",
              Ecirc: "Ê",
              egrave: "è",
              Egrave: "È",
              eth: "ð",
              ETH: "Ð",
              euml: "ë",
              Euml: "Ë",
              frac12: "½",
              frac14: "¼",
              frac34: "¾",
              gt: ">",
              GT: ">",
              iacute: "í",
              Iacute: "Í",
              icirc: "î",
              Icirc: "Î",
              iexcl: "¡",
              igrave: "ì",
              Igrave: "Ì",
              iquest: "¿",
              iuml: "ï",
              Iuml: "Ï",
              laquo: "«",
              lt: "<",
              LT: "<",
              macr: "¯",
              micro: "µ",
              middot: "·",
              nbsp: " ",
              not: "¬",
              ntilde: "ñ",
              Ntilde: "Ñ",
              oacute: "ó",
              Oacute: "Ó",
              ocirc: "ô",
              Ocirc: "Ô",
              ograve: "ò",
              Ograve: "Ò",
              ordf: "ª",
              ordm: "º",
              oslash: "ø",
              Oslash: "Ø",
              otilde: "õ",
              Otilde: "Õ",
              ouml: "ö",
              Ouml: "Ö",
              para: "¶",
              plusmn: "±",
              pound: "£",
              quot: '"',
              QUOT: '"',
              raquo: "»",
              reg: "®",
              REG: "®",
              sect: "§",
              shy: "­",
              sup1: "¹",
              sup2: "²",
              sup3: "³",
              szlig: "ß",
              thorn: "þ",
              THORN: "Þ",
              times: "×",
              uacute: "ú",
              Uacute: "Ú",
              ucirc: "û",
              Ucirc: "Û",
              ugrave: "ù",
              Ugrave: "Ù",
              uml: "¨",
              uuml: "ü",
              Uuml: "Ü",
              yacute: "ý",
              Yacute: "Ý",
              yen: "¥",
              yuml: "ÿ",
            },
            E = {
              0: "�",
              128: "€",
              130: "‚",
              131: "ƒ",
              132: "„",
              133: "…",
              134: "†",
              135: "‡",
              136: "ˆ",
              137: "‰",
              138: "Š",
              139: "‹",
              140: "Œ",
              142: "Ž",
              145: "‘",
              146: "’",
              147: "“",
              148: "”",
              149: "•",
              150: "–",
              151: "—",
              152: "˜",
              153: "™",
              154: "š",
              155: "›",
              156: "œ",
              158: "ž",
              159: "Ÿ",
            },
            R = [
              1, 2, 3, 4, 5, 6, 7, 8, 11, 13, 14, 15, 16, 17, 18, 19, 20, 21,
              22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 127, 128, 129, 130, 131,
              132, 133, 134, 135, 136, 137, 138, 139, 140, 141, 142, 143, 144,
              145, 146, 147, 148, 149, 150, 151, 152, 153, 154, 155, 156, 157,
              158, 159, 64976, 64977, 64978, 64979, 64980, 64981, 64982, 64983,
              64984, 64985, 64986, 64987, 64988, 64989, 64990, 64991, 64992,
              64993, 64994, 64995, 64996, 64997, 64998, 64999, 65e3, 65001,
              65002, 65003, 65004, 65005, 65006, 65007, 65534, 65535, 131070,
              131071, 196606, 196607, 262142, 262143, 327678, 327679, 393214,
              393215, 458750, 458751, 524286, 524287, 589822, 589823, 655358,
              655359, 720894, 720895, 786430, 786431, 851966, 851967, 917502,
              917503, 983038, 983039, 1048574, 1048575, 1114110, 1114111,
            ],
            P = String.fromCharCode,
            Y = {},
            z = Y.hasOwnProperty,
            M = function (S, $) {
              return z.call(S, $);
            },
            q = function (S, $) {
              for (var J = -1, ce = S.length; ++J < ce;)
                if (S[J] == $) return !0;
              return !1;
            },
            V = function (S, $) {
              if (!S) return $;
              var J = {},
                ce;
              for (ce in $) J[ce] = M(S, ce) ? S[ce] : $[ce];
              return J;
            },
            te = function (S, $) {
              var J = "";
              return (S >= 55296 && S <= 57343) || S > 1114111
                ? ($ &&
                    ae(
                      "character reference outside the permissible Unicode range",
                    ),
                  "�")
                : M(E, S)
                  ? ($ && ae("disallowed character reference"), E[S])
                  : ($ && q(R, S) && ae("disallowed character reference"),
                    S > 65535 &&
                      ((S -= 65536),
                      (J += P(((S >>> 10) & 1023) | 55296)),
                      (S = 56320 | (S & 1023))),
                    (J += P(S)),
                    J);
            },
            oe = function (S) {
              return "&#x" + S.toString(16).toUpperCase() + ";";
            },
            re = function (S) {
              return "&#" + S + ";";
            },
            ae = function (S) {
              throw Error("Parse error: " + S);
            },
            ie = function (S, $) {
              $ = V($, ie.options);
              var J = $.strict;
              J && g.test(S) && ae("forbidden code point");
              var ce = $.encodeEverything,
                C = $.useNamedReferences,
                w = $.allowUnsafeSymbols,
                H = $.decimal ? re : oe,
                D = function (y) {
                  return H(y.charCodeAt(0));
                };
              return (
                ce
                  ? ((S = S.replace(u, function (y) {
                      return C && M(d, y) ? "&" + d[y] + ";" : D(y);
                    })),
                    C &&
                      (S = S.replace(/&gt;\u20D2/g, "&nvgt;")
                        .replace(/&lt;\u20D2/g, "&nvlt;")
                        .replace(/&#x66;&#x6A;/g, "&fjlig;")),
                    C &&
                      (S = S.replace(l, function (y) {
                        return "&" + d[y] + ";";
                      })))
                  : C
                    ? (w ||
                        (S = S.replace(p, function (y) {
                          return "&" + d[y] + ";";
                        })),
                      (S = S.replace(/&gt;\u20D2/g, "&nvgt;").replace(
                        /&lt;\u20D2/g,
                        "&nvlt;",
                      )),
                      (S = S.replace(l, function (y) {
                        return "&" + d[y] + ";";
                      })))
                    : w || (S = S.replace(p, D)),
                S.replace(o, function (y) {
                  var Z = y.charCodeAt(0),
                    X = y.charCodeAt(1),
                    ye = (Z - 55296) * 1024 + X - 56320 + 65536;
                  return H(ye);
                }).replace(c, D)
              );
            };
          ie.options = {
            allowUnsafeSymbols: !1,
            encodeEverything: !1,
            strict: !1,
            useNamedReferences: !1,
            decimal: !1,
          };
          var G = function (S, $) {
            $ = V($, G.options);
            var J = $.strict;
            return (
              J && m.test(S) && ae("malformed character reference"),
              S.replace(f, function (ce, C, w, H, D, y, Z, X, ye) {
                var Qt, Xt, ds, ps, er, tr;
                return C
                  ? ((er = C), A[er])
                  : w
                    ? ((er = w),
                      (tr = H),
                      tr && $.isAttributeValue
                        ? (J &&
                            tr == "=" &&
                            ae("`&` did not start a character reference"),
                          ce)
                        : (J &&
                            ae(
                              "named character reference was not terminated by a semicolon",
                            ),
                          T[er] + (tr || "")))
                    : D
                      ? ((ds = D),
                        (Xt = y),
                        J &&
                          !Xt &&
                          ae(
                            "character reference was not terminated by a semicolon",
                          ),
                        (Qt = parseInt(ds, 10)),
                        te(Qt, J))
                      : Z
                        ? ((ps = Z),
                          (Xt = X),
                          J &&
                            !Xt &&
                            ae(
                              "character reference was not terminated by a semicolon",
                            ),
                          (Qt = parseInt(ps, 16)),
                          te(Qt, J))
                        : (J &&
                            ae(
                              "named character reference was not terminated by a semicolon",
                            ),
                          ce);
              })
            );
          };
          G.options = { isAttributeValue: !1, strict: !1 };
          var U = function (S) {
              return S.replace(p, function ($) {
                return h[$];
              });
            },
            ne = {
              version: "1.2.0",
              encode: ie,
              decode: G,
              escape: U,
              unescape: G,
            };
          if (r && !r.nodeType)
            if (a) a.exports = ne;
            else for (var pe in ne) M(ne, pe) && (r[pe] = ne[pe]);
          else t.he = ne;
        })(Dd);
      })(xt, xt.exports)),
    xt.exports
  );
}
var Ad = yd();
const fi = ha(Ad),
  vd = "org.matrix.custom.html",
  bi = (s) =>
    fi.decode(
      s
        .replace(
          /<\s*br\s*\/?>/gi,
          `
`,
        )
        .replace(
          /<\/\s*(p|div|li|blockquote|h[1-6])\s*>/gi,
          `
`,
        )
        .replace(/<[^>]*>/g, "")
        .replace(
          /\n{3,}/g,
          `

`,
        )
        .trim(),
    ),
  Cd = (s) => {
    try {
      const e = JSON.parse(s);
      return typeof e == "string" ? e : void 0;
    } catch {
      return;
    }
  },
  Di = async (s) => {
    const e = Cd(s);
    return e !== void 0 ? await vs(e) : await vs(Fi(s));
  },
  wd = async (s) => {
    if (s.text) {
      const e = await Di(s.text);
      return {
        text: bi(e),
        formatText: !1,
        eventExtra: { format: vd, formatted_body: e },
      };
    }
    return {};
  },
  cr = (s) => ge(s) && Object.keys(s).length > 0,
  Id = (s) =>
    s?.type === "gif" || s?.isGif
      ? "gif"
      : s?.type === "recorded_audio" || s?.isRecordedAudio || s?.isVoiceNote
        ? "recorded_audio"
        : "file",
  yi = (s) => {
    if (!(!ge(s) || !cr(s)))
      return Object.fromEntries(
        Object.entries(s).flatMap(([e, t]) =>
          ge(t)
            ? [
                [
                  e,
                  {
                    id: typeof t.id == "string" ? t.id : e,
                    type: Id(t),
                    mimeType:
                      typeof t.mimeType == "string" ? t.mimeType : void 0,
                    fileName:
                      typeof t.fileName == "string" ? t.fileName : void 0,
                    filePath:
                      typeof t.filePath == "string" ? t.filePath : void 0,
                    fileSize:
                      typeof t.fileSize == "number" ? t.fileSize : void 0,
                    stickerID:
                      typeof t.stickerID == "string" ? t.stickerID : void 0,
                    audioDurationSeconds:
                      typeof t.audioDurationSeconds == "number"
                        ? t.audioDurationSeconds
                        : void 0,
                    size: ge(t.size) ? t.size : void 0,
                  },
                ],
              ]
            : [],
        ),
      );
  },
  Ai = (s) => (s?.contents ?? []).filter(ma),
  xd = (s) => {
    const e = Ai(s).find((t) => t.body != null)?.body ?? "";
    return e.length > 0 ? e : null;
  },
  Ed = (s) => {
    const e = Ai(s),
      t = e.find(
        (a) => a.format === on && a.formatted_body != null,
      )?.formatted_body;
    if (t != null) return t;
    const r = e.find((a) => a.body != null)?.body;
    return r
      ? r
          .split(
            `
`,
          )
          .map((a) => `<p>${ca(a)}</p>`)
          .join("")
      : "";
  },
  vi = (s) => {
    const e = (s?.contents ?? [])
      .filter((t) => !ma(t))
      .map((t) => t[nn]?.attachment)
      .filter((t) => t != null);
    if (e.length) return Object.fromEntries(e.map((t) => [t.id, t]));
  },
  Sd = async (s) => {
    const e = s[or.DRAFT];
    return e?.contents?.length ? { text: Ed(e), attachments: yi(vi(e)) } : null;
  },
  Bd = async (s) => {
    if (s !== void 0) {
      if (s === null) return null;
      if ("text" in s) return s.text ? await Di(s.text) : null;
    }
  },
  _d = (s) =>
    s == null ? s : "attachments" in s ? (s.attachments ?? null) : void 0,
  Td = (s) => {
    if (!s) return St();
    const e = W.basename(s);
    return !e || e === "." || e === ".." || e.includes("\0") ? St() : e;
  },
  kd = new Set([
    "TEXT",
    "NOTICE",
    "IMAGE",
    "VIDEO",
    "VOICE",
    "AUDIO",
    "FILE",
    "STICKER",
    "LOCATION",
    "REACTION",
  ]),
  Fd = (s) => typeof s == "string" && kd.has(s),
  Md = (s) => {
    if (!s) return;
    const e = ur(s.timestamp ?? s.ts);
    return e
      ? {
          reason: s.reason,
          message: s.message,
          status: s.status,
          timestamp: e,
          deliveredToUsers: s.deliveredToUsers,
          internalError: s.internalError,
        }
      : void 0;
  },
  Js = (s) => (s instanceof Date ? s.toISOString() : s),
  Rd = (s) => {
    if (s != null)
      return typeof s == "boolean" || s instanceof Date
        ? Js(s)
        : Object.fromEntries(Object.entries(s).map(([e, t]) => [e, Js(t)]));
  },
  Od = async (s, e) => {
    const t =
        s?.size && (s.size.width || s.size.height)
          ? { width: s.size.width, height: s.size.height }
          : void 0,
      r = await e(s.srcURL, typeof s.id == "string" ? s.id : void 0),
      a = Ur(typeof s.id == "string" ? s.id : void 0),
      i =
        typeof s.id == "string" && s.id
          ? s.id
          : (a?.baseURL ?? s.srcURL ?? s.fileName ?? "attachment"),
      o =
        r ??
        (typeof s.srcURL == "string"
          ? s.srcURL
          : typeof s.id == "string"
            ? s.id
            : i);
    return {
      id: i,
      type: s.type,
      mimeType: s.mimeType,
      fileName: s.fileName,
      fileSize: s.fileSize,
      isGif: s.isGif,
      isSticker: s.isSticker,
      isVoiceNote: s.isVoiceNote,
      duration: s.duration,
      transcription: s.transcription,
      posterImg:
        typeof s.posterImg == "string"
          ? await e(s.posterImg)
          : (s.posterImg ?? void 0),
      size: t,
      srcURL: o,
    };
  },
  Ld = async (s, e) => {
    const t = String(s.threadID || ""),
      r = await e.getCachedChat(t),
      a =
        Array.isArray(s.attachments) &&
        s.attachments.length > 0 &&
        !s.extra?.viewLimitedMedia
          ? (
              await Promise.all(
                s.attachments.map((f) => Od(f, e.resolveAssetURL)),
              )
            ).filter((f) => !!f)
          : void 0,
      i =
        typeof s.extra?.sanitizedFormattedBody == "string"
          ? s.extra.sanitizedFormattedBody
          : void 0,
      o = s.textAttributes?.heDecode ? fi.decode(s.text || "") : s.text,
      u = i ?? (o ? ca(o) : void 0),
      c = s.impersonator?.fullName?.trim() || void 0,
      l = c ? void 0 : r?.participants?.items?.find((f) => f.id === s.senderID),
      d = l ? (Mi(l) ?? void 0) : void 0,
      p = c ?? d ?? String(s.senderID),
      h = String(s.sortKey ?? s.id),
      m = e.accountID || r?.accountID;
    !s.accountID &&
      m &&
      e.onMissingAccountIDFallback?.({
        messageID: String(s.id),
        chatID: t,
        fallbackAccountID: m,
      });
    const g = {
      id: String(s.id),
      chatID: t,
      accountID: String(s.accountID || m || ""),
      senderID: String(s.senderID),
      senderName: p,
      timestamp:
        s.timestamp instanceof Date
          ? s.timestamp.toISOString()
          : new Date(s.timestamp).toISOString(),
      sortKey: h,
      type: Fd(s.extra?.type) ? s.extra.type : void 0,
      text: u,
      fullTitle: s.extra?.fullPostTitle,
      editedTimestamp:
        s.editedTimestamp instanceof Date
          ? s.editedTimestamp.toISOString()
          : s.editedTimestamp
            ? new Date(s.editedTimestamp).toISOString()
            : void 0,
      isSender: !!s.isSender,
      sendStatus: Md(s.sendStatus),
      isHidden: typeof s.isHidden == "boolean" ? s.isHidden : void 0,
      isDeleted: typeof s.isDeleted == "boolean" ? s.isDeleted : void 0,
      linkedMessageID: s.linkedMessageID ? String(s.linkedMessageID) : void 0,
      mentions:
        Array.isArray(s.mentions) || s.mentions === null ? s.mentions : void 0,
      links: Array.isArray(s.links) && s.links.length > 0 ? s.links : void 0,
      reactions: s.reactions,
      seen: Rd(s.seen),
      attachments: a,
    };
    return (
      r?.lastReadMessageSortKey !== void 0 &&
        s.isSender === !1 &&
        (g.isUnread = Ri({ ...s, sortKey: h }, r.lastReadMessageSortKey)),
      g
    );
  },
  Nd = [la, un, "bridge-imessagecloud", "bridge-ai"].filter(Boolean),
  Ci = "matrix",
  wi = "hungryserv",
  Ud = (s) => (s === Ci ? wi : s),
  Et = (s) => (s === wi ? Ci : s),
  Pd = (s) => s && Et(s);
class qd {
  constructor(e) {
    ((this.connect = e), (this.loginSessions = new Map()));
  }
  get bc() {
    return this.connect.beeperClient;
  }
  parseBridgeJSON(e) {
    if (!e) return {};
    try {
      return JSON.parse(e);
    } catch {
      throw new B(
        "Bridge API returned invalid JSON",
        "invalid_bridge_response",
        502,
      );
    }
  }
  mapAccountStatus(e) {
    if (e.disabled) return "disabled";
    switch (e.state?.state) {
      case Ae.Connected:
        return "connected";
      case Ae.Connecting:
        return "connecting";
      case Ae.Backfilling:
        return "backfilling";
      case Ae.BadCredentials:
        return "reconnect_required";
      case Ae.Unconfigured:
      case void 0:
        return "connection_required";
      case Ae.TransientDisconnect:
      case Ae.UnknownError:
      case Ae.LoggedOut:
        return "disconnected";
      default:
        return "attention_required";
    }
  }
  getRemoveScopes(e) {
    if (e.bridge.provider === "local") {
      const t = this.bc.state.device_id,
        r = !!(t && e.devices?.[t]);
      return e.state?.state === Ae.Unconfigured
        ? ["all-devices"]
        : r
          ? ["current-device", "all-devices"]
          : ["all-devices"];
    }
    return e.bridge.provider === "platform-sdk" ? [] : ["all-devices"];
  }
  findBridgeAccountByPublicAccountID(e) {
    const t = da(Ud(e), this.accountsConfiguredOnThisDevice);
    return this.accountsConfiguredOnThisDevice.find(
      (r) => et(r) === t || Et(et(r)) === e,
    );
  }
  findBridgeAccountsByLoginID(e, t) {
    return this.bc.bridgeStateManager.bridgeAccounts.filter(
      (r) => r.bridgeID === e && r.accountID === t,
    );
  }
  async mapBridgeAccountToAccount(e) {
    const t = et(e),
      r = cn(e),
      a = e.bridge.type,
      i = a ? qr(a) : void 0,
      o = e.network?.displayName ?? (i && i !== a ? i : void 0);
    return {
      accountID: Et(t),
      loginID: e.accountID,
      bridge: {
        id: Et(e.bridgeID),
        type: Pd(a) ?? a,
        provider: e.bridge.provider,
      },
      network: o,
      user: {
        ...r,
        imgURL: await this.bc.mediaManager.resolveAssetURL(r.imgURL),
      },
      status: this.mapAccountStatus(e),
      statusText: e.state?.message,
    };
  }
  async mapBridgeAccountsToLogin(e) {
    const [t] = e;
    if (!t) throw new B("Bridge login not found", "NOT_FOUND", 404);
    const r = await Promise.all(
        e.map((o) => this.mapBridgeAccountToAccount(o)),
      ),
      a = r.map((o) => o.status),
      i = a.includes("connected")
        ? "connected"
        : a.some((o) => o === "connecting" || o === "backfilling")
          ? "connecting"
          : a.some(
                (o) =>
                  o === "reconnect_required" || o === "connection_required",
              )
            ? "needs_login"
            : a.includes("disconnected")
              ? "logged_out"
              : "unknown";
    return {
      loginID: t.accountID,
      bridgeID: t.bridgeID,
      accountIDs: r.map((o) => o.accountID),
      user: r[0]?.user,
      status: i,
      statusText: r.find((o) => o.statusText)?.statusText,
      removeScopes: this.getRemoveScopes(t),
    };
  }
  mapLoginStep(e) {
    if (!e || typeof e != "object") return;
    const t =
        typeof e.step_id == "string"
          ? e.step_id
          : typeof e.stepID == "string"
            ? e.stepID
            : void 0,
      r = typeof e.instructions == "string" ? e.instructions : void 0;
    switch (e.type) {
      case "user_input":
        return {
          type: "user_input",
          stepID: t ?? "",
          instructions: r,
          fields: Array.isArray(e.user_input?.fields)
            ? e.user_input.fields.map((a) => ({
                id: String(a.id ?? ""),
                type: typeof a.type == "string" ? a.type : void 0,
                label: typeof a.label == "string" ? a.label : void 0,
                placeholder:
                  typeof a.placeholder == "string" ? a.placeholder : void 0,
                initialValue:
                  typeof a.initial_value == "string" ? a.initial_value : void 0,
                optional: typeof a.optional == "boolean" ? a.optional : void 0,
              }))
            : [],
          attachments: Array.isArray(e.user_input?.attachments)
            ? e.user_input.attachments
            : void 0,
        };
      case "cookies":
        return {
          type: "cookies",
          stepID: t ?? "",
          instructions: r,
          url: String(e.cookies?.url ?? ""),
          userAgent:
            typeof e.cookies?.user_agent == "string"
              ? e.cookies.user_agent
              : void 0,
          fields: Array.isArray(e.cookies?.fields)
            ? e.cookies.fields.map((a) => ({
                id: String(a.id ?? a.name ?? ""),
                type: ["cookie", "header", "local_storage"].includes(a.type)
                  ? a.type
                  : void 0,
                name: typeof a.name == "string" ? a.name : void 0,
              }))
            : [],
          expectedFinalURLRegex:
            typeof e.cookies?.wait_for_url_pattern == "string"
              ? e.cookies.wait_for_url_pattern
              : void 0,
          extractJS:
            typeof e.cookies?.extract_js == "string"
              ? e.cookies.extract_js
              : void 0,
        };
      case "display_and_wait": {
        const a = e.display_and_wait?.type;
        return {
          type: "display_and_wait",
          stepID: t ?? "",
          instructions: r,
          display:
            a === "qr"
              ? { type: "qr", data: String(e.display_and_wait?.data ?? "") }
              : a === "emoji"
                ? {
                    type: "emoji",
                    imageURL: String(e.display_and_wait?.image_url ?? ""),
                  }
                : a === "code"
                  ? {
                      type: "code",
                      data: String(e.display_and_wait?.data ?? ""),
                    }
                  : { type: "nothing" },
        };
      }
      case "complete":
        return { type: "complete", stepID: t, instructions: r };
      default:
        return;
    }
  }
  loginSessionStatusForStep(e) {
    switch (e?.type) {
      case "user_input":
        return "waiting_for_input";
      case "cookies":
        return "waiting_for_cookies";
      case "display_and_wait":
        return "waiting_for_display";
      case "complete":
        return "complete";
      default:
        return "failed";
    }
  }
  assertSupportedBridgeID(e) {
    if (!Object.values(Dt).some((t) => t.bridgeID === e))
      throw new B("Invalid bridgeID", "invalid_parameter", 400);
  }
  async ensureBridgeStarted(e) {
    (this.assertSupportedBridgeID(e),
      Oi(e) === "local" && (await this.bc.bridgeStateManager.startBridge(e)));
  }
  get accountsConfiguredOnThisDevice() {
    const {
      state: { device_id: e },
      bridgeStateManager: { bridgeAccounts: t },
    } = this.bc;
    return t.filter(
      (r) =>
        !(
          !r ||
          !r.bridge ||
          r.state?.state === Ae.Unconfigured ||
          [lr.Deleted, lr.Unconfigured].includes(r.bridge.state) ||
          (r.bridge.provider === "local" && (!e || !r.devices?.[e]))
        ),
    );
  }
  async getAccounts() {
    const e = await Promise.all(
        this.accountsConfiguredOnThisDevice.map(async (r) => {
          try {
            return r?.bridge ? await this.mapBridgeAccountToAccount(r) : null;
          } catch (a) {
            return (logger.error("Error mapping account:", a), null);
          }
        }),
      ),
      t = await this.getImessageAccount();
    return [...e, t].filter((r) => r != null);
  }
  async getAccount(e) {
    const t = this.findBridgeAccountByPublicAccountID(e.accountID);
    if (t) return await this.mapBridgeAccountToAccount(t);
    const r = await this.getImessageAccount();
    if (r?.accountID === e.accountID) return r;
    throw new B("Account not found", "NOT_FOUND", 404);
  }
  async getImessageAccount() {
    if (!Dt.imessage) return null;
    try {
      const e = Object.values(await this.bc.indexDB.getAllTextsAccounts()).find(
        (a) => a.platformName === "imessage" && a.user,
      );
      if (!e) return null;
      const t = e.user,
        r = this.bc.pas.platformAPIStore.getInstances().includes(e.id);
      return {
        accountID: e.id,
        bridge: {
          id: Dt.imessage?.bridgeID ?? "local-imessage",
          type: "imessage",
          provider: "platform-sdk",
        },
        network: "iMessage",
        user: {
          ...t,
          id: t?.id ?? e.id,
          isSelf: !0,
          imgURL: await this.bc.mediaManager.resolveAssetURL(t?.imgURL),
        },
        status:
          e.state === Li.DISABLED
            ? "disabled"
            : r
              ? "connected"
              : "disconnected",
      };
    } catch (e) {
      return (logger.error("Error mapping iMessage account:", e), null);
    }
  }
  async listBridges() {
    const e = await this.getAccounts(),
      t = await this.bc.indexDB.getAccountData(Pr.FEATURE_FLAGS),
      { "*": r, "appType:desktop": a } = t?.features ?? {},
      i = { ...r, ...a },
      o = new Map(),
      u = new Map(),
      c = new Map(
        Object.values(Dt)
          .filter((h) => h.bridgeID)
          .map((h) => [h.bridgeID, h]),
      );
    for (const h of e) {
      const m = h.bridge.id,
        g = o.get(m) ?? [];
      (g.push(h), o.set(m, g));
      const f = c.get(m),
        A = f?.network ?? f?.bridgeType ?? h.bridge.type ?? m;
      u.set(A, (u.get(A) ?? 0) + 1);
    }
    const l = new Set(Nd),
      d = (h) =>
        !(
          l.has(h.name) ||
          h.name.startsWith("bridge-sh-") ||
          h.bridgeProvider === "platform-sdk" ||
          !h.bridgeID ||
          !h.bridgeType ||
          !h.bridgeProvider
        );
    return {
      items: Object.values(Dt)
        .filter(d)
        .map((h) => {
          const m = o.get(h.bridgeID) ?? [],
            g = h.network ?? h.bridgeType,
            f = u.get(g) ?? m.length,
            A = ln(h.bridgeID, i);
          return {
            id: h.bridgeID,
            type: h.bridgeType,
            provider: h.bridgeProvider,
            displayName: h.displayName || h.bridgeID,
            network: h.network,
            activeAccountCount: f,
            supportsMultipleAccounts: A,
            status: m.length > 0 && !A ? "connected" : "available",
            accounts: m,
          };
        }),
    };
  }
  async getBridge(e) {
    const t = (await this.listBridges()).items.find((r) => r.id === e.bridgeID);
    if (!t) throw new B("Bridge not found", "NOT_FOUND", 404);
    return t;
  }
  async getBridgeCapabilities(e) {
    await this.ensureBridgeStarted(e.bridgeID);
    const t = this.parseBridgeJSON(
        await this.bc.sdk.getProvisioningCapabilities(e.bridgeID),
      ),
      r = Ta.safeParse(t);
    if (!r.success)
      throw new B(
        "Bridge API returned invalid provisioning capabilities",
        "invalid_bridge_response",
        502,
      );
    return r.data;
  }
  async listBridgeLoginFlows(e) {
    await this.ensureBridgeStarted(e.bridgeID);
    const t = this.parseBridgeJSON(
      await this.bc.sdk.getBridgeLoginFlows(e.bridgeID),
    );
    return {
      items: (Array.isArray(t) ? t : [])
        .map((a) => ({
          id: String(a.id ?? a.ID ?? ""),
          name:
            typeof a.name == "string"
              ? a.name
              : typeof a.Name == "string"
                ? a.Name
                : void 0,
          description:
            typeof a.description == "string" ? a.description : void 0,
        }))
        .filter((a) => a.id),
    };
  }
  async listBridgeLogins(e) {
    const t = new Map();
    for (const r of this.bc.bridgeStateManager.bridgeAccounts.filter(
      (a) => a.bridgeID === e.bridgeID,
    )) {
      const a = t.get(r.accountID) ?? [];
      (a.push(r), t.set(r.accountID, a));
    }
    return {
      items: await Promise.all(
        [...t.values()].map((r) => this.mapBridgeAccountsToLogin(r)),
      ),
    };
  }
  async getBridgeLogin(e) {
    const t = this.findBridgeAccountsByLoginID(e.bridgeID, e.loginID);
    if (!t.length) throw new B("Bridge login not found", "NOT_FOUND", 404);
    return await this.mapBridgeAccountsToLogin(t);
  }
  async removeBridgeLogin(e) {
    const t = this.findBridgeAccountsByLoginID(e.bridgeID, e.loginID),
      r = t[0];
    if (!r) throw new B("Bridge login not found", "NOT_FOUND", 404);
    if (!this.getRemoveScopes(r).includes(e.scope))
      throw new B(
        `Remove scope ${e.scope} is not available for this bridge login`,
        "INVALID_SCOPE",
        400,
      );
    if (r.bridge.provider === "local")
      e.scope === "all-devices"
        ? await this.bc.sdk.deleteBridgeAccount(e.bridgeID, e.loginID)
        : await this.bc.sdk.disconnectBridgeAccount(e.bridgeID, e.loginID);
    else if (
      r.bridge.provider === "cloud" ||
      r.bridge.provider === "self-hosted"
    )
      await this.bc.bridgeStateManager.logoutCloudBridgeAccount(
        e.bridgeID,
        e.loginID,
      );
    else
      throw new B(
        "Remove is not supported for this bridge login",
        "UNSUPPORTED_OPERATION",
        400,
      );
    return {
      bridgeID: e.bridgeID,
      loginID: e.loginID,
      affectedAccountIDs: t.map((i) => Et(et(i))),
      status: "removed",
      scope: e.scope,
    };
  }
  async buildLoginSession(e) {
    const t = this.mapLoginStep(e.rawStep),
      r = e.accountID
        ? this.findBridgeAccountByPublicAccountID(e.accountID)
        : void 0,
      a = e.loginID
        ? this.findBridgeAccountsByLoginID(e.bridgeID, e.loginID)
        : [],
      i = r ? await this.mapBridgeAccountToAccount(r) : void 0,
      o = a.length ? await this.mapBridgeAccountsToLogin(a) : void 0;
    t?.type === "complete" && ((t.account = i), (t.login = o));
    const u = {
      loginSessionID: e.loginSessionID,
      bridgeID: e.bridgeID,
      loginID: e.loginID,
      accountID: e.accountID,
      status: this.loginSessionStatusForStep(t),
      currentStep: t,
      account: i,
      login: o,
    };
    return (this.loginSessions.set(`${e.bridgeID}\0${e.loginSessionID}`, u), u);
  }
  getStoredLoginSession(e, t) {
    const r = this.loginSessions.get(`${e}\0${t}`);
    if (!r) throw new B("Bridge login session not found", "NOT_FOUND", 404);
    return r;
  }
  async createLoginSession(e) {
    await this.ensureBridgeStarted(e.bridgeID);
    const t = e.accountID
      ? this.findBridgeAccountByPublicAccountID(e.accountID)
      : void 0;
    if (e.accountID && !t)
      throw new B(
        "Account not found or has no bridge login ID",
        "NOT_FOUND",
        404,
      );
    if (t && t.bridgeID !== e.bridgeID)
      throw new B(
        "Account does not belong to this bridge",
        "INVALID_ACCOUNT",
        400,
      );
    const r = e.loginID ?? t?.accountID;
    if (!(await this.bc.bridgeStateManager.canAddAccount(e.bridgeID, r)))
      throw new B(
        "Adding another account to this bridge is disabled",
        "MULTI_ACCOUNT_DISABLED",
        409,
      );
    const a =
      e.flowID ??
      (await this.listBridgeLoginFlows({ bridgeID: e.bridgeID })).items[0]?.id;
    if (!a)
      throw new B(
        "No login flow is available for this bridge",
        "NO_LOGIN_FLOW",
        409,
      );
    const i = this.parseBridgeJSON(
      await this.bc.sdk.bridgeLoginStartProcess(e.bridgeID, a, r ?? "", !1),
    );
    if (!ge(i))
      throw new B(
        "Bridge API returned invalid login session",
        "invalid_bridge_response",
        502,
      );
    const o = typeof i.login_process_id == "string" ? i.login_process_id : "";
    if (!o)
      throw new B(
        "Bridge API did not return a login session ID",
        "invalid_bridge_response",
        502,
      );
    return await this.buildLoginSession({
      bridgeID: e.bridgeID,
      loginSessionID: o,
      loginID: r,
      accountID: e.accountID,
      rawStep: i.next_step,
    });
  }
  getLoginSession(e) {
    return this.getStoredLoginSession(e.bridgeID, e.loginSessionID);
  }
  async submitLoginStep(e) {
    const t = this.getStoredLoginSession(e.bridgeID, e.loginSessionID),
      r = t.currentStep;
    if (!r || r.stepID !== e.stepID || r.type !== e.type)
      throw new B(
        "Login step does not match the current session state",
        "INVALID_LOGIN_STEP",
        409,
      );
    let a;
    return (
      e.type === "user_input"
        ? (a = this.parseBridgeJSON(
            await this.bc.sdk.bridgeLoginProcessSubmitUserInput(
              e.bridgeID,
              e.loginSessionID,
              e.stepID,
              JSON.stringify(e.fields ?? {}),
            ),
          ))
        : e.type === "cookies"
          ? (a = this.parseBridgeJSON(
              await this.bc.sdk.bridgeLoginProcessSubmitCookies(
                e.bridgeID,
                e.loginSessionID,
                e.stepID,
                JSON.stringify(e.fields ?? {}),
                e.source ?? "api",
              ),
            ))
          : (a = this.parseBridgeJSON(
              await this.bc.sdk.bridgeLoginProcessWaitAndBlock(
                e.bridgeID,
                e.loginSessionID,
                e.stepID,
              ),
            )),
      await this.buildLoginSession({
        bridgeID: e.bridgeID,
        loginSessionID: e.loginSessionID,
        loginID: t.loginID,
        accountID: t.accountID,
        rawStep: a,
      })
    );
  }
  async cancelLoginSession(e) {
    return (
      await this.bc.sdk.bridgeLoginCancelProcess(
        e.bridgeID,
        e.loginSessionID,
        !1,
      ),
      this.loginSessions.delete(`${e.bridgeID}\0${e.loginSessionID}`),
      {
        bridgeID: e.bridgeID,
        loginSessionID: e.loginSessionID,
        status: "cancelled",
      }
    );
  }
}
const jd = (s) =>
    s.reduce((e, t) =>
      (Ne(t.timestamp) ?? 0) > (Ne(e.timestamp) ?? 0) ? t : e,
    ),
  Qs = 30,
  Vd = 20,
  Zd = 6e4,
  Ii = "matrix",
  xi = "hungryserv",
  wt = (s, e) => `${s}\0${e}`,
  ir = ({ beeper: s, imessage: e }) => {
    const t = s ?? "",
      r = e ?? "";
    return !t && !r ? null : r ? (t ? `${t}|${r}` : `|${r}`) : t || null;
  },
  Xs = (s) => {
    const e = {};
    if (!s) return e;
    const t = s.indexOf("|");
    if (t === -1) return ((e.beeper = s), e);
    const r = s.slice(0, t),
      a = s.slice(t + 1);
    return (r && (e.beeper = r), a && (e.imessage = a), e);
  },
  $d = 978307200000n,
  Gd = (s) => String((BigInt(s) - $d) * 1000000n),
  ea = /^-?\d+$/,
  Mr = (s, e) => {
    const t = String(s),
      r = String(e);
    if (ea.test(t) && ea.test(r)) {
      const a = BigInt(r) - BigInt(t);
      return a > 0n ? 1 : a < 0n ? -1 : 0;
    }
    return r.localeCompare(t, void 0, { numeric: !0 });
  };
function ct(s) {
  if (!s || typeof s != "string") return;
  const e = s.trim();
  if (!e) return;
  const t = e.replace(/[^\d+]/g, "");
  if (t) return (t.startsWith("+"), t);
}
function lt(s) {
  return !s || typeof s != "string" ? void 0 : s.trim().toLowerCase() || void 0;
}
function Tt(s) {
  if (!s || typeof s != "string") return;
  const e = s.trim().toLowerCase();
  if (e) return e.startsWith("@") ? e.slice(1) : e;
}
const ta = (s) => (s === xi ? Ii : s);
function Rr({ phoneNumber: s, email: e, username: t }) {
  return { phoneNumber: ct(s), email: lt(e), username: Tt(t) };
}
function Ei(s) {
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(s);
}
function zd(s) {
  const e = s.trim();
  return e ? zi(e) || vn(e) || !!Cn(e) : !1;
}
function Si(s) {
  return s.replace(/[^\d+]/g, "").replace(/\D/g, "").length >= 7;
}
function Hd(s) {
  return /^@?[a-z0-9._-]{2,}$/i.test(s);
}
function Wd(s = []) {
  let e, t, r;
  for (const a of s) {
    if (typeof a != "string") continue;
    const i = a.trim();
    if (i) {
      if (!e && i.startsWith("tel:")) {
        e = ct(i.slice(4));
        continue;
      }
      if (!t && i.startsWith("mailto:")) {
        t = lt(i.slice(7));
        continue;
      }
      if (!e && Si(i)) {
        e = ct(i);
        continue;
      }
      if (!t && Ei(i)) {
        t = lt(i);
        continue;
      }
      !r && Hd(i) && (r = Tt(i));
    }
  }
  return { phoneNumber: e, email: t, username: r };
}
const ra = (s) => ({ srcURL: void 0, error: s }),
  Kd = new Set([
    "media",
    "api-uploads",
    "report_a_problem_attachments",
    "draft_attachments",
    "app_icons",
    "user_avatar",
    "quick_reply_attachments",
    "temp_avatar_uploads",
    "transcoded_cache",
    "transcribed_notes",
    "linkpreviews",
  ]),
  Yd = /^\.|::|~|^(con|prn|aux|nul|com\d|lpt\d)$/i;
function Jd(s, e) {
  const t = W.normalize(s),
    r = W.normalize(e);
  if (!t.startsWith(r + W.sep) && t !== r) return !1;
  const a = W.relative(r, t);
  if (a.startsWith("..") || a === "" || W.isAbsolute(a)) return !1;
  const i = a.split(W.sep)[0];
  return Kd.has(i);
}
const Qd = [
    "title",
    "description",
    "imgURL",
    "isArchived",
    "isLowPriority",
    "isPinned",
    "isMuted",
    "messageExpirySeconds",
  ],
  Xd = (s, e) => {
    const t = {};
    return (
      "mutedUntil" in e && (t.isMuted = !!e.mutedUntil),
      "isLowPriority" in e && (t.isLowPriority = !!e.isLowPriority),
      "isPinned" in e && (t.isPinned = !!e.isPinned),
      (t.isPinned ?? s.isPinned)
        ? (t.isArchived = !1)
        : "isArchived" in e && (t.isArchived = !!e.isArchived),
      Object.keys(t).length ? { ...s, ...t } : s
    );
  },
  ep = (s) =>
    Math.max(
      s.extra?.lastNotifiableMessageHsOrder ?? 0,
      ...(s.messages?.items ?? [])
        .filter((e) => e.extra?.shouldNotify === !0)
        .map((e) => Number(e.sortKey) || 0),
    ),
  Or = (s) =>
    Wi({
      isArchivedUpToOrder: s.extra?.isArchivedUpToOrder,
      isArchivedUpto: s.extra?.isArchivedUpto,
      lastNotifiableMessageHsOrder: ep(s),
      markedUnreadUpdatedAt: s.extra?.markedUnreadUpdatedAt,
      isPinned: s.isPinned,
      isUnread: (s.unreadCount || 0) > 0,
    }),
  sa = (s) => !!s.isLowPriority || !!s.extra?.tags?.["m.lowpriority"],
  aa = { all: 0, dmOnly: 1, none: 2 },
  tp = (s) => {
    if (!s) return;
    const e = ge(s.state) ? s.state : void 0,
      t = ge(s.file)
        ? Object.fromEntries(
            Object.entries(s.file).flatMap(([c, l]) =>
              ge(l)
                ? [
                    [
                      c,
                      {
                        mimeTypes: l.mime_types,
                        caption: l.caption,
                        maxCaptionLength: l.max_caption_length,
                        maxSize: l.max_size,
                        maxWidth: l.max_width,
                        maxHeight: l.max_height,
                        maxDuration: l.max_duration,
                        viewLimitedTypes: l.view_limited_types,
                      },
                    ],
                  ]
                : [],
            ),
          )
        : void 0,
      r = ge(s.message_request) ? s.message_request : void 0,
      a = ge(s.disappearing_timer) ? s.disappearing_timer : void 0,
      i = ge(s.member_actions) ? s.member_actions : void 0,
      o = {
        formatting: s.formatting,
        attachments: t,
        maxTextLength: s.max_text_length,
        locationMessage: s.location_message,
        poll: s.poll,
        thread: s.thread,
        reply: s.reply,
        edit: s.edit,
        editMaxCount: s.edit_max_count,
        editMaxAge: s.edit_max_age,
        delete: s.delete,
        deleteMaxAge: s.delete_max_age,
        deleteForMe: s.delete_for_me,
        messageRequest: r
          ? {
              acceptWithMessage: r.accept_with_message,
              acceptWithButton: r.accept_with_button,
            }
          : void 0,
        reaction: s.reaction,
        reactionCount: s.reaction_count,
        allowedReactions: s.allowed_reactions,
        customEmojiReactions: s.custom_emoji_reactions,
        disappearingTimer: a
          ? {
              types: Array.isArray(a.types)
                ? a.types.map((c) =>
                    c === "after_read"
                      ? "afterRead"
                      : c === "after_read_by_recipient"
                        ? "afterReadByRecipient"
                        : c === "after_send"
                          ? "afterSend"
                          : c,
                  )
                : void 0,
              timers: a.timers,
              omitEmptyTimer: a.omit_empty_timer,
            }
          : void 0,
        readReceipts: s.read_receipts,
        typingNotifications: s.typing_notifications,
        archive: s.archive,
        markAsUnread: s.mark_as_unread,
        deleteChat: s.delete_chat,
        deleteChatForEveryone: s.delete_chat_for_everyone,
        participantActions: i
          ? {
              ban: i.ban,
              invite: i.invite,
              kick: i.kick,
              leave: i.leave,
              revokeInvite: i.revoke_invite,
            }
          : void 0,
        state: e
          ? {
              disappearingTimer: e["com.beeper.disappearing_timer"],
              avatar: e["m.room.avatar"],
              title: e["m.room.name"],
              description: e["m.room.topic"],
            }
          : void 0,
      },
      u = Ka.safeParse(o);
    if (!u.success) {
      logger.warn(
        "[BeeperConnectTools] Dropping invalid chat capabilities:",
        u.error,
      );
      return;
    }
    return u.data;
  },
  Lr = 500,
  rp = (s) => Buffer.from(JSON.stringify(s)).toString("base64"),
  sp = (s) => {
    if (!s) return null;
    try {
      const e = JSON.parse(Buffer.from(s, "base64").toString());
      return ge(e?.oldest) && ge(e?.newest) ? e : null;
    } catch {
      return null;
    }
  },
  ia = (s) => ga(s, (e) => `${e.accountID ?? ""}\0${e.chatID ?? ""}\0${e.id}`),
  na = (s) => String("rowID" in s && s.rowID != null ? s.rowID : s.id),
  ap = (s) => {
    const e = {};
    for (const t of Qd) {
      if (!(t in s)) continue;
      const r = s[t];
      if (t === "isMuted") {
        e.mutedUntil = r ? "forever" : void 0;
        continue;
      }
      if (t === "imgURL" && typeof r == "string") {
        e[t] = W.isAbsolute(r) ? jr(r).href : r;
        continue;
      }
      e[t] = r;
    }
    return e;
  };
class Bi {
  constructor(e) {
    ((this.connect = e),
      (this.toInternalAccountID = (t) =>
        t === Ii ? xi : da(t, this.bc.bridgeStateManager.bridgeAccounts)),
      (this.toInternalAccountIDs = (t) => t?.map(this.toInternalAccountID)),
      (this.accountNetworkNames = new Map()),
      (this.matrixAssetCache = new dn({ limit: 1e3 })),
      (this.macOSContactsCache = null),
      (this.chatMetaCache = new Map()),
      (this.bridgeLifecycle = new qd(e)));
  }
  get bc() {
    return this.connect.beeperClient;
  }
  async getThreadPropsForMappedChats(e) {
    const t = Array.from(
        new Map(e.map((i) => [wt(i.accountID, i.threadID), i])).values(),
      ),
      r = new Map();
    if (t.length === 0) return r;
    const a = new Map();
    for (const { accountID: i, threadID: o } of t) {
      r.set(wt(i, o), {});
      const u = a.get(i) ?? new Set();
      (u.add(o), a.set(i, u));
    }
    return (
      await Promise.all(
        Array.from(a).map(async ([i, o]) => {
          const u = await this.bc.indexDB.getThreadPropsForAccount(i);
          for (const [c, l] of u)
            o.has(c) && r.set(wt(i, c), l ? JSON.parse(l) : {});
        }),
      ),
      r
    );
  }
  async getThreadPropsForMappedChat(e, t) {
    return (
      (
        await this.getThreadPropsForMappedChats([{ accountID: e, threadID: t }])
      ).get(wt(e, t)) ?? {}
    );
  }
  getResolveIdentifierCapabilities(e) {
    const t = this.bc.bridgeStateManager.findByDesktopAccountID(e),
      r = t
        ? this.bc.bridgeStateManager.provisioningCapabilitiesMap?.[t.bridgeID]
            ?.resolve_identifier
        : void 0;
    return {
      createDM: !!r?.create_dm,
      lookupEmail: !!r?.lookup_email,
      lookupPhone: !!r?.lookup_phone,
      lookupUsername: !!r?.lookup_username,
      anyPhone: !!r?.any_phone,
    };
  }
  getCandidateKey(e) {
    const t =
      typeof e.mxid == "string" && e.mxid.trim()
        ? e.mxid.trim().toLowerCase()
        : null;
    if (t) return `mxid:${t}`;
    const r = typeof e.id == "string" && e.id.trim() ? e.id.trim() : null;
    if (r) return `id:${r}`;
    const a = ct(e.phoneNumber);
    if (a) return `phone:${a}`;
    const i = lt(e.email);
    if (i) return `email:${i}`;
    const o = Tt(e.username);
    return o ? `username:${o}` : null;
  }
  normalizeUser(e) {
    const { phoneNumber: t, email: r, username: a } = Rr(e),
      i =
        typeof e?.id == "string" && e.id.trim()
          ? e.id.trim()
          : typeof e?.mxid == "string" && e.mxid.trim()
            ? e.mxid.trim()
            : t || r || a;
    return i
      ? {
          id: i,
          username: a || void 0,
          phoneNumber: t || void 0,
          email: r || void 0,
          fullName:
            typeof e?.fullName == "string" && e.fullName.trim()
              ? e.fullName.trim()
              : void 0,
          imgURL:
            typeof e?.imgURL == "string" && e.imgURL.trim() ? e.imgURL : void 0,
          cannotMessage:
            typeof e?.cannotMessage == "boolean" ? e.cannotMessage : void 0,
          isSelf: typeof e?.isSelf == "boolean" ? e.isSelf : void 0,
          isAdmin: typeof e?.isAdmin == "boolean" ? e.isAdmin : void 0,
          isPending: typeof e?.isPending == "boolean" ? e.isPending : void 0,
          isNetworkBot:
            typeof e?.isNetworkBot == "boolean" ? e.isNetworkBot : void 0,
        }
      : null;
  }
  scoreUserForQuery(e, t, r) {
    const a = t.trim().toLowerCase();
    if (!a) return r;
    const i = [e.id, e.fullName, e.username, e.email, e.phoneNumber]
      .filter((o) => typeof o == "string" && o.length > 0)
      .map((o) => o.toLowerCase());
    return i.some((o) => o === a)
      ? r + 300
      : i.some((o) => o.startsWith(a))
        ? r + 200
        : i.some((o) => o.includes(a))
          ? r + 100
          : -1;
  }
  mergeCandidates(e) {
    const t = new Map();
    for (const r of e) {
      const a = t.get(r.key);
      if (!a) {
        t.set(r.key, { user: { ...r.user }, score: r.score });
        continue;
      }
      const i = r.score > a.score,
        o = i ? { ...r.user } : a.user,
        u = i ? a.user : r.user;
      ((o.username ||= u.username),
        (o.phoneNumber ||= u.phoneNumber),
        (o.email ||= u.email),
        (o.fullName ||= u.fullName),
        (o.imgURL ||= u.imgURL),
        (o.cannotMessage ??= u.cannotMessage),
        (o.isSelf ??= u.isSelf),
        t.set(r.key, { user: o, score: Math.max(a.score, r.score) }));
    }
    return Array.from(t.values())
      .sort((r, a) => {
        if (a.score !== r.score) return a.score - r.score;
        const i = (
            r.user.fullName ||
            r.user.username ||
            r.user.email ||
            r.user.phoneNumber ||
            r.user.id
          ).toLowerCase(),
          o = (
            a.user.fullName ||
            a.user.username ||
            a.user.email ||
            a.user.phoneNumber ||
            a.user.id
          ).toLowerCase();
        return i.localeCompare(o);
      })
      .map((r) => r.user);
  }
  async getRemoteContactsPage(e, t) {
    try {
      return (
        (await this.bc.pas.platformAPIStore.callMethod({
          accountID: this.toInternalAccountID(e),
          methodName: "getContacts",
          args: t ? [t] : [],
        })) || null
      );
    } catch {
      return null;
    }
  }
  remoteContactToUser(e) {
    if (!e || typeof e != "object") return null;
    const t = Array.isArray(e.identifiers) ? e.identifiers : [],
      r = Wd(t);
    return this.normalizeUser({
      id: e.mxid || e.id || r.phoneNumber || r.email || r.username,
      username: r.username,
      phoneNumber: r.phoneNumber,
      email: r.email,
      fullName: e.name,
      imgURL: e.avatar_url,
    });
  }
  async getMacOSContactsAsUsers() {
    if (!Cs) return [];
    if (
      this.macOSContactsCache &&
      this.macOSContactsCache.expiresAt > Date.now()
    )
      return this.macOSContactsCache.users;
    try {
      const t = (await wn()).data.response
        .map((r) => {
          const a =
              r.fullName ||
              [r.firstName, r.middleName, r.lastName].filter(Boolean).join(" "),
            {
              phoneNumber: i,
              email: o,
              username: u,
            } = Rr({
              phoneNumber: r.phoneNumbers?.[0],
              email: r.emailAddresses?.[0],
              username: r.socialProfiles?.[0]?.username,
            }),
            c = i || o || u || r.id || r.identifier;
          return c
            ? this.normalizeUser({
                id: c,
                fullName: a || void 0,
                phoneNumber: i,
                email: o,
                username: u,
              })
            : null;
        })
        .filter((r) => !!r);
      return (
        (this.macOSContactsCache = { users: t, expiresAt: Date.now() + Zd }),
        t
      );
    } catch {
      return [];
    }
  }
  async getProjectedMacOSContacts(e) {
    const t = this.getResolveIdentifierCapabilities(e);
    return (await this.getMacOSContactsAsUsers()).flatMap((a) => {
      const i = { fullName: a.fullName };
      ((t.lookupPhone || t.anyPhone) && (i.phoneNumber = a.phoneNumber),
        t.lookupEmail && (i.email = a.email),
        t.lookupUsername && (i.username = a.username),
        t.createDM && (i.id = a.id));
      const o = this.normalizeUser(i);
      return o ? [o] : [];
    });
  }
  async getExactLookupUsers(e, t) {
    const r = this.getResolveIdentifierCapabilities(e),
      a = [],
      i = t.trim(),
      o = ct(i),
      u = lt(i),
      c = Tt(i);
    if (!zd(i)) return [];
    (o && Si(i) && (r.lookupPhone || r.anyPhone) && a.push({ phoneNumber: o }),
      u && Ei(i) && r.lookupEmail && a.push({ email: u }));
    const l = !!c && r.lookupUsername;
    return (
      l && a.push({ username: c }),
      r.createDM && !l && a.push({ userID: i }),
      a.length === 0
        ? []
        : (
            await Promise.allSettled(
              a.map(
                async (p) =>
                  await this.bc.pas.platformAPIStore.callMethod({
                    accountID: this.toInternalAccountID(e),
                    methodName: "getUser",
                    args: [p],
                  }),
              ),
            )
          )
            .filter((p) => p.status === "fulfilled")
            .map((p) => this.normalizeUser(p.value))
            .filter((p) => !!p)
    );
  }
  async resolveMergedContactsForAccount(e) {
    const t = e.query?.trim() || "",
      r = e.includeSearch ?? !!t,
      a = e.includeLookup ?? !!t,
      [i, o, u, c] = await Promise.all([
        this.getRemoteContactsPage(e.accountID, e.pagination),
        r
          ? Promise.resolve()
              .then(() =>
                this.bc.pas.platformAPIStore.callMethod({
                  accountID: this.toInternalAccountID(e.accountID),
                  methodName: "searchUsers",
                  args: [t],
                }),
              )
              .catch(() => [])
          : Promise.resolve([]),
        a
          ? this.getExactLookupUsers(e.accountID, t).catch(() => [])
          : Promise.resolve([]),
        this.getProjectedMacOSContacts(e.accountID).catch(() => []),
      ]),
      l = (i?.items || [])
        .map((f) => this.remoteContactToUser(f))
        .filter((f) => !!f),
      d = (Array.isArray(o) ? o : [])
        .map((f) => this.normalizeUser(f))
        .filter((f) => !!f),
      p = [],
      h = (f, A) => {
        for (const T of f) {
          const E = this.getCandidateKey(T);
          if (!E) continue;
          const R = t ? this.scoreUserForQuery(T, t, A) : A;
          R < 0 || p.push({ key: E, user: T, score: R });
        }
      };
    (h(l, 100), h(d, 200), h(u, 300), h(c, 80));
    const m = this.mergeCandidates(p);
    return {
      items: typeof e.limit == "number" ? m.slice(0, e.limit) : m,
      hasMore: t ? !1 : !!i?.hasMore,
      oldestCursor: t ? null : (i?.oldestCursor ?? null),
      newestCursor: t ? null : (i?.newestCursor ?? null),
    };
  }
  get imessageAccountID() {
    return this.bc.pas.platformAPIStore
      .getInstances()
      .find((e) => e.startsWith("imessage_"));
  }
  async paginateAllChatsFromPAPI(e, t = 1e4) {
    const r = [];
    let a = null,
      i = null;
    for (; !(r.length >= t);) {
      const o = a ? { cursor: a, direction: i } : void 0,
        u = await this.bc.pas.platformAPIStore.callMethod({
          accountID: e,
          methodName: "getThreads",
          args: [hs.NORMAL, o],
        }),
        c = u?.items || [];
      for (const l of c) if ((r.push(l), r.length >= t)) break;
      if (!u?.hasMore) break;
      ((a = u?.oldestCursor ?? null), (i = "before"));
    }
    return r;
  }
  async getImessageThreads(e, t, r, a) {
    const i = [];
    let o = t != null ? Gd(t) : null,
      u = !1;
    do {
      const c = await this.bc.pas.platformAPIStore.callMethod({
        accountID: e,
        methodName: "getThreads",
        args: [hs.NORMAL, o ? { cursor: o, direction: r } : void 0],
      });
      (i.push(...(c?.items ?? [])),
        (u = c?.hasMore ?? !1),
        (o = c?.oldestCursor ?? null));
    } while (r === "before" && u && o && i.length < a);
    return { items: i, hasMore: u };
  }
  refreshAccountNetworkNames() {
    this.accountNetworkNames.clear();
    for (const e of this.bc.bridgeStateManager.bridgeAccounts) {
      const t = et(e);
      e?.accountID &&
        this.accountNetworkNames.set(t, qr(e.bridge.type || "unknown"));
    }
    this.imessageAccountID &&
      !this.accountNetworkNames.has(this.imessageAccountID) &&
      this.accountNetworkNames.set(this.imessageAccountID, "iMessage");
  }
  getNetworkDisplayName(e, t) {
    const r = t.extra;
    if (r?.bridge?.network?.displayname) {
      const a = r?.bridge?.protocol?.displayname ?? "";
      return `${r.bridge.network.displayname} ${a}`.trim();
    }
    return e.startsWith("imessage_") || t.id?.startsWith("imsg##")
      ? "iMessage"
      : this.accountNetworkNames.get(e) || "";
  }
  computeThreadSearchFields(e, t) {
    const r = (t.participants?.items || [])
        .filter((o) => !o.hasExited)
        .sort(ms),
      a =
        gs({
          personalTitle: void 0,
          title: t.title,
          isGroup: t.type === "group",
          participants: r,
          currentUserID: this.bc.currentUserID,
          NAMED_CANDIDATE_LIMIT: 3,
        }) ?? "",
      i = this.getNetworkDisplayName(e, t);
    return ld({ title: a, participants: r, networkDisplayName: i });
  }
  get bridgedAccountIDs() {
    return this.bc.pas.platformAPIStore
      .getInstances()
      .filter((e) => e !== this.imessageAccountID);
  }
  async buildChatIndex(e) {
    this.refreshAccountNetworkNames();
    const t = new Map(),
      r = new st(),
      a = this.bridgedAccountIDs,
      i = e?.length ? e.filter((c) => a.includes(c)) : a,
      o =
        i.length > 0
          ? await this.bc.chatPreviewRepo.getRooms(i, void 0, 1e5)
          : { items: [] };
    for (const c of o.items)
      try {
        if (!c.accountID) continue;
        const l = this.computeThreadSearchFields(c.accountID, c);
        t.set(c.id, { chat: c, accountID: c.accountID });
        const d = c.rowID ?? c.id;
        (this.chatMetaCache.set(d, {
          chatID: c.id,
          localChatID: d,
          accountID: c.accountID,
          url: fs(this.connect.serverURL, d),
        }),
          r.upsert({
            accountID: c.accountID,
            threadID: c.id,
            searchFields: l,
          }));
      } catch {}
    const u =
      !e?.length ||
      (this.imessageAccountID && e?.includes(this.imessageAccountID));
    if (this.imessageAccountID && u)
      try {
        const c = await this.paginateAllChatsFromPAPI(this.imessageAccountID);
        for (const l of c)
          try {
            const d = this.computeThreadSearchFields(this.imessageAccountID, l);
            (t.set(l.id, { chat: l, accountID: this.imessageAccountID }),
              r.upsert({
                accountID: this.imessageAccountID,
                threadID: l.id,
                searchFields: d,
              }));
          } catch {}
      } catch (c) {
        logger.warn(
          "[BeeperConnectTools] Failed to fetch iMessage threads:",
          c,
        );
      }
    return { chatCache: t, chatIndex: r };
  }
  async searchUsers(e) {
    return this.searchContacts(e);
  }
  async searchContacts(e) {
    try {
      return {
        items: (
          await this.resolveMergedContactsForAccount({
            accountID: this.toInternalAccountID(e.accountID),
            query: e.query,
            includeSearch: !0,
            includeLookup: !0,
          })
        ).items,
      };
    } catch (t) {
      this.handleToolError(t, "searchContacts");
    }
  }
  async listContacts(e) {
    try {
      const t = e.direction ?? "before",
        r = e.cursor ? { cursor: e.cursor, direction: t } : void 0;
      return await this.resolveMergedContactsForAccount({
        accountID: this.toInternalAccountID(e.accountID),
        query: e.query,
        pagination: r,
        includeSearch: !!e.query?.trim(),
        includeLookup: !!e.query?.trim(),
        limit: e.limit,
      });
    } catch (t) {
      this.handleToolError(t, "listContacts");
    }
  }
  parseChatIDFromCreateResult(e) {
    return typeof e == "string" && e
      ? e
      : e && typeof e == "object" && "id" in e && typeof e.id == "string"
        ? e.id
        : null;
  }
  matchesIdentifier(e, t) {
    return !e || !t ? !1 : e.toLowerCase() === t.toLowerCase();
  }
  async findExistingSingleChatID(e, t) {
    try {
      const r = await this.bc.chatPreviewRepo.getRooms([e], void 0, 5e3);
      for (const a of r.items) {
        if (!a || a.type === "group") continue;
        const i = (a.participants?.items || []).filter(
          (u) => !u.isSelf && !u.hasExited,
        );
        if (i.length !== 1) continue;
        const o = i[0];
        if (
          this.matchesIdentifier(o.id, t.id) ||
          this.matchesIdentifier(o.mxid, t.id) ||
          this.matchesIdentifier(ct(o.phoneNumber), t.phoneNumber) ||
          this.matchesIdentifier(lt(o.email), t.email) ||
          this.matchesIdentifier(Tt(o.username), t.username)
        )
          return a.id;
      }
    } catch {}
    return null;
  }
  mapStartChatError(e) {
    const t = Ge(e).toLowerCase();
    return t.includes("invite")
      ? new B(
          "Chat creation requires sending an invite",
          "INVITE_REQUIRED",
          409,
        )
      : t.includes("message") && t.includes("require")
        ? new B(
            "A message is required to start this chat",
            "MESSAGE_REQUIRED",
            400,
          )
        : t.includes("cannot") && t.includes("message")
          ? new B(
              "Cannot message this user on the selected account",
              "CANNOT_MESSAGE_USER",
              403,
            )
          : t.includes("not found") || t.includes("unknown user")
            ? new B("User not found", "USER_NOT_FOUND", 404)
            : new B(Ge(e), "CREATE_CHAT_FAILED", 500);
  }
  async startChatInternal(e) {
    const t = this.toInternalAccountID(e.accountID),
      r = this.getResolveIdentifierCapabilities(t),
      a = e.user || {},
      i = {
        id: typeof a.id == "string" && a.id.trim() ? a.id.trim() : void 0,
        ...Rr(a),
      },
      o = [
        r.createDM && i.id ? i.id : void 0,
        (r.lookupPhone || r.anyPhone) && i.phoneNumber ? i.phoneNumber : void 0,
        r.lookupEmail && i.email ? i.email : void 0,
        r.lookupUsername && i.username ? i.username : void 0,
      ].filter((l) => !!l);
    if (o.length === 0)
      throw new B(
        "No supported identifiers for this account",
        "UNSUPPORTED_IDENTIFIER",
        400,
      );
    const u = await this.findExistingSingleChatID(t, i);
    if (u) {
      const l = await this.getChat({ chatID: u, maxParticipantCount: 100 });
      return { ...l, chatID: l.id, status: "existing" };
    }
    const c = o[0];
    try {
      const l = await this.bc.pas.platformAPIStore.callMethod({
          accountID: t,
          methodName: "createThread",
          args: [[c], void 0, e.messageText],
        }),
        d = this.parseChatIDFromCreateResult(l);
      if (!d)
        throw new xr(
          "createChat",
          new Error(
            "Unexpected createThread result type or no chat ID returned",
          ),
        );
      const p = await this.getChat({ chatID: d, maxParticipantCount: 100 });
      return { ...p, chatID: p.id, status: "created" };
    } catch (l) {
      throw this.mapStartChatError(l);
    }
  }
  async createChat(e) {
    try {
      const t = { ...e, accountID: this.toInternalAccountID(e.accountID) },
        r = await this.bc.pas.platformAPIStore.callMethod({
          accountID: t.accountID,
          methodName: "createThread",
          args: [
            t.participantIDs,
            t.type === "group" ? t.title : void 0,
            t.messageText,
            void 0,
            { isGroup: t.type === "group" },
          ],
        }),
        a = this.parseChatIDFromCreateResult(r);
      if (!a)
        throw new xr(
          "createChat",
          new Error(
            "Unexpected createThread result type or no chat ID returned",
          ),
        );
      const i = await this.getChat({ chatID: a, maxParticipantCount: 100 });
      return { ...i, chatID: i.id };
    } catch (t) {
      this.handleToolError(t, "createChat");
    }
  }
  async startChat(e) {
    try {
      return await this.startChatInternal(e);
    } catch (t) {
      this.handleToolError(t, "startChat");
    }
  }
  createPerRequestChatResolver(e) {
    const t = new Map(),
      r = (a) =>
        t.set(
          a,
          this.getChat({ chatID: a, maxParticipantCount: -1 }).catch(
            (i) => (
              logger.warn(
                `[BeeperConnectTools] Failed to hydrate chat ${a}:`,
                i,
              ),
              null
            ),
          ),
        );
    return (
      e.forEach((a) => r(a)),
      {
        get: (a) => (t.has(a) || r(a), t.get(a)),
        getAll: async () => {
          const a = await Promise.all(
            Array.from(t.entries()).map(async ([i, o]) => {
              const u = await o;
              return u ? [i, u] : null;
            }),
          );
          return Object.fromEntries(a.filter((i) => !!i));
        },
      }
    );
  }
  async hydrateMessagesForWSEvent(e, t) {
    const r = Array.from(new Set(t.filter((c) => typeof c == "string")));
    if (r.length === 0) return [];
    const a = this.createPerRequestChatResolver([e]),
      i = await Promise.allSettled(
        r.map(async (c) => {
          const {
            result: l,
            error: d,
            meta: p,
          } = await this.callPAPIForChat(e, "getMessage", c);
          if (d || !l) return null;
          const h = p?.accountID;
          return this.mapMessage(l, { accountID: h, getCachedChat: a.get });
        }),
      ),
      o = [],
      u = new Set();
    for (const c of i) {
      if (c.status !== "fulfilled") continue;
      const l = c.value;
      l && (u.has(l.id) || (u.add(l.id), o.push(l)));
    }
    return o;
  }
  async mapMessage(e, t) {
    const r = this.bc.mediaManager?.resolveAssetURL
        ? this.bc.mediaManager.resolveAssetURL.bind(this.bc.mediaManager)
        : async () => {},
      a = await Ld(e, {
        ...t,
        accountID: t.accountID ? this.toInternalAccountID(t.accountID) : void 0,
        resolveAssetURL: r,
        onMissingAccountIDFallback: (i) =>
          logger.debug(
            "[BeeperConnectTools] Filled missing message.accountID",
            i,
          ),
      });
    return { ...a, accountID: ta(a.accountID) };
  }
  async getMappedMessage(e, t, r) {
    const { result: a, error: i } = await this.callPAPIForChat(
      e,
      "getMessage",
      t,
    );
    if (i) throw i;
    if (!a) throw new B("Message not found", "NOT_FOUND", 404);
    return await this.mapMessage(a, {
      accountID: r,
      getCachedChat: async () =>
        await this.getChat({ chatID: e, maxParticipantCount: 100 }),
    });
  }
  messageMatchesIdentifier(e, t) {
    return (
      String(e.id) === t ||
      String(e.eventID || "") === t ||
      String(e.extra?.eventID || "") === t ||
      String(e.extra?.echoID || "") === t
    );
  }
  async getMessage(e) {
    try {
      const { chatID: t, messageID: r } = e,
        { meta: a, error: i } = await this.getChatMeta(t);
      if (i) throw i;
      const o = (await this.resolveUnionMessageTarget(a.chatID, r)) ?? a.chatID,
        u =
          o === a.chatID
            ? a.accountID
            : ((await this.getChatMeta(o)).meta?.accountID ?? a.accountID);
      try {
        return await this.getMappedMessage(o, r, u);
      } catch (h) {
        logger.debug(
          "[BeeperConnectTools] Exact getMessage failed, falling back to room page lookup:",
          h,
        );
      }
      const { result: c, error: l } = await this.callPAPIForChat(
        o,
        "getMessages",
      );
      if (l) throw l;
      const d = (c?.items || []).find((h) =>
        this.messageMatchesIdentifier(h, r),
      );
      if (!d) throw new B("Message not found", "NOT_FOUND", 404);
      const p = this.createPerRequestChatResolver([o]);
      return await this.mapMessage(d, { accountID: u, getCachedChat: p.get });
    } catch (t) {
      this.handleToolError(t, "getMessage");
    }
  }
  async getLatestMessageIDForReadReceipt(e) {
    const { result: t, error: r } = await this.callPAPIForChat(e, "getThread");
    if (r) throw r;
    const a = t?.messages?.items?.[0]?.id ?? t?.partialLastMessage?.id;
    if (a != null) return String(a);
    const { result: i, error: o } = await this.callPAPIForChat(
      e,
      "getMessages",
    );
    if (o) throw o;
    const u = (i?.items || []).filter((l) => l.id !== void 0 && l.id !== null);
    u.sort((l, d) => {
      const p = l.sortKey ?? l.id,
        h = d.sortKey ?? d.id;
      return Mr(p, h);
    });
    const c = u[0]?.id;
    if (c == null)
      throw new B(
        "Cannot mark chat read because no messages were found",
        "NOT_FOUND",
        404,
      );
    return String(c);
  }
  get accountsConfiguredOnThisDevice() {
    const {
      state: { device_id: e },
      bridgeStateManager: { bridgeAccounts: t },
    } = this.connect.beeperClient;
    return t.filter(
      (r) =>
        !(
          !r ||
          !r.bridge ||
          r.state?.state === Ae.Unconfigured ||
          [lr.Deleted, lr.Unconfigured].includes(r.bridge.state) ||
          (r.bridge.provider === "local" && (!e || !r.devices?.[e]))
        ),
    );
  }
  async getAccounts() {
    try {
      return await this.bridgeLifecycle.getAccounts();
    } catch (e) {
      this.handleToolError(e, "getAccounts");
    }
  }
  async getAccount(e) {
    try {
      return await this.bridgeLifecycle.getAccount(e);
    } catch (t) {
      this.handleToolError(t, "getAccount");
    }
  }
  async listBridges() {
    try {
      return await this.bridgeLifecycle.listBridges();
    } catch (e) {
      this.handleToolError(e, "listBridges");
    }
  }
  async getBridge(e) {
    try {
      return await this.bridgeLifecycle.getBridge(e);
    } catch (t) {
      this.handleToolError(t, "getBridge");
    }
  }
  async getBridgeCapabilities(e) {
    try {
      return await this.bridgeLifecycle.getBridgeCapabilities(e);
    } catch (t) {
      this.handleToolError(t, "getBridgeCapabilities");
    }
  }
  async listBridgeLoginFlows(e) {
    try {
      return await this.bridgeLifecycle.listBridgeLoginFlows(e);
    } catch (t) {
      this.handleToolError(t, "listBridgeLoginFlows");
    }
  }
  async listBridgeLogins(e) {
    try {
      return await this.bridgeLifecycle.listBridgeLogins(e);
    } catch (t) {
      this.handleToolError(t, "listBridgeLogins");
    }
  }
  async getBridgeLogin(e) {
    try {
      return await this.bridgeLifecycle.getBridgeLogin(e);
    } catch (t) {
      this.handleToolError(t, "getBridgeLogin");
    }
  }
  async removeBridgeLogin(e) {
    try {
      return await this.bridgeLifecycle.removeBridgeLogin(e);
    } catch (t) {
      this.handleToolError(t, "removeBridgeLogin");
    }
  }
  async createLoginSession(e) {
    try {
      return await this.bridgeLifecycle.createLoginSession(e);
    } catch (t) {
      this.handleToolError(t, "createLoginSession");
    }
  }
  async getLoginSession(e) {
    try {
      return this.bridgeLifecycle.getLoginSession(e);
    } catch (t) {
      this.handleToolError(t, "getLoginSession");
    }
  }
  async submitLoginStep(e) {
    try {
      return await this.bridgeLifecycle.submitLoginStep(e);
    } catch (t) {
      this.handleToolError(t, "submitLoginStep");
    }
  }
  async cancelLoginSession(e) {
    try {
      return await this.bridgeLifecycle.cancelLoginSession(e);
    } catch (t) {
      this.handleToolError(t, "cancelLoginSession");
    }
  }
  handleToolError(e, t) {
    throw _i(e)
      ? new pa("Invalid input", { issues: e.issues })
      : e instanceof B
        ? e
        : new xr(t, e);
  }
  async getChatMessageSortKey(e, t) {
    const { result: r, error: a } = await this.callPAPIForChat(
      e,
      "getMessage",
      t,
    );
    if (a) throw a;
    return String(r?.sortKey ?? "");
  }
  async getDeeplinkForChat(e, t, r, a) {
    const { meta: i, error: o } = await this.getChatMeta(e);
    if (o) throw o;
    const { accountID: u } = i;
    if (!u) return null;
    const l =
        this.accountsConfiguredOnThisDevice.find((h) => et(h) === u)
          ?.bridgeID ?? la,
      d = r ? `&text=${encodeURIComponent(r)}` : "",
      p = t ? await this.getChatMessageSortKey(e, t) : void 0;
    return `${ws}select-thread/${l}/${encodeURIComponent(e)}${p ? `/${p}` : ""}?accountID=${u}${d}${a ? `&attachmentPath=${a}` : ""}`;
  }
  async archiveChat(e) {
    logger.log(
      `[BeeperConnectTools] Archive chat requested${e.chatID ? ` for chat ${e.chatID.substring(0, 12)}...` : ""} (archived: ${e.archived ?? !0})`,
    );
    const t = e,
      { error: r } = await this.callPAPIForChat(
        t.chatID,
        "archiveThread",
        t.archived ?? !0,
      );
    if (r) throw r;
  }
  async patchChat(e) {
    try {
      const { chatID: t, draft: r } = e;
      if (!t) throw new B("chatID is required", "INVALID_INPUT", 400);
      const { meta: a, error: i } = await this.getChatMeta(t);
      if (i) throw i;
      const { chatID: o, accountID: u } = a;
      let c;
      const l = _d(r);
      if (r !== void 0 || l !== void 0) {
        const A =
            (await this.getThreadPropsForMappedChat(u, o))[or.DRAFT] ?? null,
          T = vi(A) ?? null,
          E = xd(A),
          R = cr(T);
        if ((!!(r && "text" in r ? r.text : null) || cr(l)) && (E || R))
          throw new B(
            "Cannot overwrite a non-empty draft. Clear the draft first by setting draft to null or draft.text to an empty string.",
            "DRAFT_NOT_EMPTY",
            409,
          );
        const [z, M] = await Promise.all([
            Bd(r),
            this.resolveDraftAttachmentsFromUploads(l),
          ]),
          q = z && bi(z),
          V = cr(M),
          te = !q && !V,
          oe = E === null && z === null && (M === void 0 || Ni(T, M));
        if (!te && !oe && (E || R))
          throw new B(
            "Cannot overwrite a non-empty draft. Clear the draft first by setting draft to null or draft.text to an empty string.",
            "DRAFT_NOT_EMPTY",
            409,
          );
        const re = V && M ? M : void 0;
        (this.bc.onAppEvent({
          type: tt.BEEPER_CONNECT_DRAFT_REQUESTED,
          accountID: u,
          threadID: o,
          draft: te ? null : { text: z ?? "", attachments: re },
        }),
          (c = te ? null : { text: z ?? "", attachments: yi(M) }));
      }
      const d = ap(e),
        { isArchived: p, isPinned: h, ...m } = d;
      if (p !== void 0) {
        const { error: f } = await this.callPAPIForChat(o, "archiveThread", p);
        if (f) throw f;
      }
      if (h !== void 0) {
        const { error: f } = await this.callPAPIForChat(o, "pinThread", h);
        if (f) throw f;
      }
      if (Object.keys(m).length > 0) {
        const { error: f } = await this.callPAPIForChat(o, "updateThread", m);
        if (f) throw f;
      }
      const g = Xd(
        await this.getChat({ chatID: o, maxParticipantCount: 100 }),
        d,
      );
      return c !== void 0 ? { ...g, draft: c } : g;
    } catch (t) {
      this.handleToolError(t, "patchChat");
    }
  }
  async setChatReminder(e) {
    logger.log(
      `[BeeperConnectTools] Set chat reminder requested${e.chatID ? ` for chat ${e.chatID.substring(0, 12)}...` : ""}`,
    );
    const t = e,
      r = Ne(t.reminder.remindAt);
    if (r == null)
      throw new B(
        "reminder.remindAt must be a valid ISO timestamp",
        "INVALID_INPUT",
        400,
      );
    const { error: a } = await this.callPAPIForChat(
      t.chatID,
      "setThreadReminder",
      {
        remindAtMs: r,
        dismissOnIncomingMessage: t.reminder.dismissOnIncomingMessage,
      },
    );
    if (a) throw a;
  }
  async clearChatReminder(e) {
    logger.log(
      `[BeeperConnectTools] Clear chat reminder requested${e.chatID ? ` for chat ${e.chatID.substring(0, 12)}...` : ""}`,
    );
    const t = e,
      { error: r } = await this.callPAPIForChat(
        t.chatID,
        "clearThreadReminder",
      );
    if (r) throw r;
  }
  async markChatRead(e) {
    try {
      const t =
        e.messageID ?? (await this.getLatestMessageIDForReadReceipt(e.chatID));
      return await this.callPAPIAndRefreshChat(e.chatID, "sendReadReceipt", t);
    } catch (t) {
      this.handleToolError(t, "markChatRead");
    }
  }
  async markChatUnread(e) {
    try {
      return await this.callPAPIAndRefreshChat(
        e.chatID,
        "markAsUnread",
        e.messageID,
      );
    } catch (t) {
      this.handleToolError(t, "markChatUnread");
    }
  }
  async notifyAnyway(e) {
    try {
      return await this.callPAPIAndRefreshChat(e.chatID, "notifyAnyway");
    } catch (t) {
      this.handleToolError(t, "notifyAnyway");
    }
  }
  async focusApp(e) {
    try {
      logger.log(
        `[BeeperConnectTools] Focus app requested${e.chatID ? ` for chat ${e.chatID.substring(0, 12)}...` : ""}${e.draftText ? " with draft text" : ""}`,
      );
      let t = `${ws}focus`;
      if (e.chatID) {
        const { meta: r, error: a } = await this.getChatMeta(e.chatID);
        if (a) throw a;
        const { chatID: i } = r,
          o = await this.getDeeplinkForChat(
            i,
            e.messageID,
            e.draftText,
            e.draftAttachmentPath,
          );
        if (!o) throw new Error("Chat not found");
        t = o;
      } else if (e.draftText) throw new Error("Draft text requires a chat ID");
      return (
        logger.log(`[BeeperConnectTools] Emitting deeplink: ${t}`),
        this.bc.onAppEvent({ type: tt.DEEPLINK_REQUESTED, url: t }),
        { success: !0 }
      );
    } catch (t) {
      this.handleToolError(t, "focusApp");
    }
  }
  async getChatMeta(e) {
    if (this.chatMetaCache.has(e))
      return { meta: this.chatMetaCache.get(e), error: null };
    const t = ({ chatID: i, localChatID: o, accountID: u }) => {
        const c = String(o ?? i),
          l = fs(this.connect.serverURL, c),
          d = { chatID: i, localChatID: c, accountID: u, url: l };
        return (
          this.chatMetaCache.set(d.chatID, d),
          d.chatID !== c && this.chatMetaCache.set(c, d),
          { meta: d, error: null }
        );
      },
      r = () => ({
        meta: null,
        error: new B(`Chat not found: ${e}`, "NOT_FOUND", 404),
      });
    if (e.startsWith("imsg##"))
      return !Cs || !this.imessageAccountID
        ? r()
        : t({ chatID: e, accountID: this.imessageAccountID });
    if (/^\d+$/.test(e)) {
      const i = await this.bc.chatPreviewRepo.resolveMetaByLocalChatID(
        Number(e),
      );
      return i
        ? t({
            chatID: i.threadID,
            localChatID: i.localChatID,
            accountID: i.accountID,
          })
        : r();
    }
    const a = await this.bc.chatPreviewRepo.getChatMetaByChatID(e);
    return a?.localChatID == null ? r() : t(a);
  }
  async callPAPIForChat(e, t, ...r) {
    const { meta: a, error: i } = await this.getChatMeta(e);
    if (i) return { result: null, error: i };
    const { accountID: o, chatID: u } = a;
    return (
      logger.log(`[BeeperConnectTools] Calling ${t} for chat ${u}`),
      {
        result: await this.bc.pas.platformAPIStore.callMethod({
          accountID: o,
          methodName: t,
          args: [u, ...r],
        }),
        meta: a,
        error: null,
      }
    );
  }
  async callPAPIAndRefreshChat(e, t, ...r) {
    if (!e) throw new B("chatID is required", "INVALID_INPUT", 400);
    const { meta: a, error: i } = await this.getChatMeta(e);
    if (i) throw i;
    const { error: o } = await this.callPAPIForChat(a.chatID, t, ...r);
    if (o) throw o;
    return await this.getChat({ chatID: a.chatID, maxParticipantCount: 100 });
  }
  async requireReactionInputs(e) {
    const { chatID: t, messageID: r, reactionKey: a } = e;
    if (!t) throw new B("chatID is required", "INVALID_INPUT", 400);
    if (!r) throw new B("messageID is required", "INVALID_INPUT", 400);
    if (!a) throw new B("reactionKey is required", "INVALID_INPUT", 400);
    const { meta: i, error: o } = await this.getChatMeta(t);
    if (o) throw o;
    return { inputChatID: t, messageID: r, reactionKey: a, meta: i };
  }
  async listLabels() {
    try {
      return (await this.labelThreads()).map(
        ({ threadID: e, labelData: t }) => ({ id: e, name: t.displayName }),
      );
    } catch (e) {
      this.handleToolError(e, "listLabels");
    }
  }
  async labelsAccessEnabled() {
    const e = await this.bc.indexDB?.getAccountData?.(Pr.FEATURE_FLAGS),
      { "*": t = {}, "appType:desktop": r = {} } = e?.features ?? {};
    return { ...t, ...r }[pn.LABELS_V2]
      ? !0
      : (e?.freebies ?? []).some((a) => a.name === "labels");
  }
  async labelThreads() {
    return (await this.labelsAccessEnabled())
      ? ((await this.bc.indexDB?.getLabelThreads?.()) ?? []).sort((t, r) =>
          t.labelData.displayName.localeCompare(r.labelData.displayName),
        )
      : [];
  }
  async getLabelContext() {
    const e = new Map(),
      t = new Map();
    for (const { threadID: r, labelData: a } of await this.labelThreads()) {
      const i = { id: r, name: a.displayName },
        o = a.inboxVisibility ?? "all";
      for (const u of a.rooms) {
        const c = e.get(u);
        c ? c.push(i) : e.set(u, [i]);
        const l = t.get(u);
        (l === void 0 || aa[o] > aa[l]) && t.set(u, o);
      }
    }
    return { labelsByRoom: e, visibilityByRoom: t };
  }
  async getUnionContext() {
    const e = new Map(),
      t = new Map();
    for (const {
      unionRoomID: r,
      memberRoomID: a,
    } of (await this.bc.spaceChildRepo?.getUnionMemberships?.()) ?? []) {
      const i = e.get(r);
      (i ? i.push(a) : e.set(r, [a]), t.set(a, r));
    }
    return { members: e, memberOf: t };
  }
  isUnionThread(e) {
    return e.extra?.roomType === "com.beeper.union";
  }
  async enrichUnionThreads(e, t, r) {
    const a = new Set(
      e.filter((u) => this.isUnionThread(u) && t.members.has(u.id)),
    );
    if (a.size === 0) return e;
    const i =
        r ??
        (await this.bc.chatPreviewRepo.getRoomsByID([
          ...new Set([...a].flatMap((u) => t.members.get(u.id))),
        ])),
      o = new Map(i.map((u) => [u.id, u]));
    return e.map((u) => {
      if (!a.has(u)) return u;
      const c = (t.members.get(u.id) ?? [])
        .map((h) => o.get(h))
        .filter((h) => !!h);
      if (c.length === 0) return u;
      const l = jd(c),
        d = c.reduce((h, m) => h + (m.unreadMentionsCount || 0), 0),
        p = c.every((h) => Or({ ...h, isPinned: !1 }));
      return {
        ...u,
        timestamp: l.timestamp ?? u.timestamp,
        participants: {
          ...u.participants,
          items: ga(
            [
              ...(u.participants?.items ?? []),
              ...c.flatMap(
                (h) => h.participants?.items?.filter((m) => !m.isSelf) ?? [],
              ),
            ],
            "id",
          ),
        },
        unreadCount: c.reduce((h, m) => h + (m.unreadCount || 0), 0),
        unreadMentionsCount: d || u.unreadMentionsCount,
        partialLastMessage:
          l.messages?.items?.[0] ??
          l.partialLastMessage ??
          u.partialLastMessage,
        extra: p
          ? { ...u.extra, isArchivedUpToOrder: 1 / 0 }
          : { ...u.extra, isArchivedUpToOrder: null, isArchivedUpto: null },
      };
    });
  }
  async resolveUnionSendTarget(e, t) {
    const r = (await this.bc.spaceChildRepo?.getUnionMembers?.(e)) ?? [];
    if (r.length === 0) return null;
    const a = await this.bc.chatPreviewRepo.getRoomsByID(r);
    let i;
    for (const l of a) {
      const d = l.messages?.items?.[0] ?? l.partialLastMessage;
      if (!d) continue;
      const p = Ne(d.timestamp) ?? 0;
      (!i || p > i.time) && (i = { id: l.id, time: p, isSender: !!d.isSender });
    }
    const o = i?.isSender && i.time + 1800 * 1e3 <= Date.now();
    if (i && !o) return i.id;
    const c = (await this.getThreadPropsForMappedChat(t, e))[
      or.UNION_DEFAULT_MEMBER_ROOM_ID
    ];
    return c && r.includes(c) ? c : r[0];
  }
  async resolveUnionMessageTarget(e, t) {
    const r = (await this.bc.spaceChildRepo?.getUnionMembers?.(e)) ?? [];
    if (r.length === 0) return null;
    for (const a of r) {
      const { result: i } = await this.callPAPIForChat(a, "getMessage", t);
      if (i) return a;
    }
    throw new B(
      "Message not found in any member of the merged chat",
      "NOT_FOUND",
      404,
    );
  }
  async mapChat(e, t = -1, r, a, i, o, u) {
    const c = (e.participants?.items || [])
        .filter((q) => !q.hasExited)
        .sort(ms),
      l = t === -1 ? c : c.slice(0, t),
      d = await Promise.all(
        l.map(
          async (q) =>
            this.normalizeUser({
              ...q,
              imgURL: await this.bc.mediaManager.resolveAssetURL(q.imgURL),
            }) || { id: String(q.id || "") },
        ),
      ),
      p = Or(e),
      h = a ?? (await this.getChatMeta(e.id)).meta;
    if (!h) throw new B("Chat not found", "NOT_FOUND", 404);
    const m = this.bc.bridgeStateManager.findByDesktopAccountID(h.accountID),
      g = this.getNetworkDisplayName(h.accountID, e);
    let f = m?.bridge.type ? qr(m?.bridge.type || "unknown") : void 0;
    ((!f || f === Er) && (f = g || Er),
      f === Er &&
        (h.accountID.startsWith("imessage_") || e.id?.startsWith("imsg##")) &&
        (f = "iMessage"));
    const A =
        r?.get(wt(h.accountID, e.id)) ??
        (await this.getThreadPropsForMappedChat(h.accountID, e.id)),
      T = i ?? (await this.bc.roomMessageRepo?.getMutedRoomIDsSet?.()),
      E = o ?? (await this.getLabelContext()),
      R = u ?? (await this.getUnionContext()),
      P = this.isUnionThread(e) ? R.members.get(e.id) : void 0,
      Y = R.memberOf.get(e.id),
      z = A?.[or.UNION_DEFAULT_MEMBER_ROOM_ID];
    return {
      id: e.id,
      localChatID: h.localChatID,
      accountID: ta(h.accountID),
      network: f,
      title:
        gs({
          title: e.title,
          isGroup: e.type === "group",
          participants: c,
          currentUserID: this.bc.currentUserID,
          NAMED_CANDIDATE_LIMIT: 3,
        }) ?? "",
      description: e.description ?? null,
      imgURL: Ui(
        e.imgURL ? await this.bc.mediaManager.resolveAssetURL(e.imgURL) : null,
      ),
      type: e.type === "group" ? "group" : "single",
      isReadOnly: e.isReadOnly,
      participants: {
        items: d,
        hasMore: t === -1 ? !1 : c.length > d.length,
        total: c.length,
      },
      lastActivity: e.timestamp ? new Date(e.timestamp).toISOString() : void 0,
      unreadCount: e.unreadCount || 0,
      unreadMentionsCount: e.unreadMentionsCount,
      lastReadMessageSortKey:
        e.lastReadMessageSortKey != null
          ? String(e.lastReadMessageSortKey)
          : void 0,
      draft: await Sd(A),
      reminder: e.reminder
        ? {
            remindAt: ur(e.reminder.remindAtMs),
            dismissOnIncomingMessage: e.reminder.dismissOnIncomingMessage,
          }
        : null,
      snooze: e.snooze
        ? {
            snoozeUntil: ur(e.snooze.snoozeUntilMs),
            userSnoozedAt: ur(e.snooze.userSnoozedAt),
          }
        : null,
      isArchived: p,
      isMarkedUnread: e.isMarkedUnread,
      isMuted: T?.has(e.id) ?? !!e.mutedUntil,
      isPinned: e.isPinned || !1,
      isLowPriority: sa(e),
      labels: E.labelsByRoom.get(e.id),
      messageExpirySeconds: e.messageExpirySeconds ?? null,
      capabilities: tp(e.features),
      merge: P?.length
        ? { chatIDs: P, defaultChatID: z && P.includes(z) ? z : void 0 }
        : void 0,
      mergedIntoChatID: Y,
    };
  }
  async getChat(e) {
    try {
      logger.log(`[BeeperConnectTools] Getting chat ${e.chatID}`);
      const { result: t, error: r } = await this.callPAPIForChat(
        e.chatID,
        "getThread",
      );
      if (r) throw r;
      if (!t) throw new B("Chat not found", "NOT_FOUND", 404);
      const a = await this.getUnionContext(),
        [i] = await this.enrichUnionThreads([t], a);
      return await this.mapChat(
        i,
        e.maxParticipantCount ?? 100,
        void 0,
        void 0,
        void 0,
        void 0,
        a,
      );
    } catch (t) {
      this.handleToolError(t, "getChat");
    }
  }
  async searchChats(e) {
    try {
      const t = { ...e, accountIDs: this.toInternalAccountIDs(e.accountIDs) },
        r = (t?.query || "").trim(),
        a = t.direction ?? "before",
        i = t.inbox,
        { chatCache: o, chatIndex: u } = await this.buildChatIndex(
          t.accountIDs,
        ),
        c = Math.min(t.limit ?? 50, 200),
        l = t.accountIDs?.length ? new Set(t.accountIDs) : null,
        d = t.includeMuted ?? !0,
        p = await this.bc.roomMessageRepo.getMutedRoomIDsSet(),
        h = await this.bc.indexDB.getAccountData(Pr.CHAT_LIST_RULES),
        m = await this.getLabelContext(),
        g = t.lastActivityBefore
          ? new Date(t.lastActivityBefore).getTime()
          : null,
        f = t.lastActivityAfter
          ? new Date(t.lastActivityAfter).getTime()
          : null,
        A = (C, w) => {
          const H = w.extra,
            D = H?.bridge?.network?.id || void 0,
            y = H?.bridge?.protocol?.id || void 0;
          let Z = bs(C);
          y !== "slackgo" &&
            D &&
            !C.endsWith(`.${D}`) &&
            y !== "whatsapp" &&
            (Z = bs(C, D));
          const X = h?.visibility ? Pi(h.visibility, Z, C) : void 0;
          return X || (y === "slackgo" || y === "discordgo" ? "dmOnly" : "all");
        };
      let T = r
        ? (t?.scope === "participants"
            ? u.searchParticipantsDetailed(r)
            : u.searchTitlesOrNetworkDetailed(r)
          )
            .map((w) => ({
              ...o.get(w.meta.threadID),
              hits: w.result.score.title.hits,
            }))
            .filter((w) => !!w)
        : Array.from(o.values());
      const E = await this.getUnionContext();
      if (E.members.size > 0) {
        const C = [],
          w = new Map();
        for (const y of T) {
          const Z = this.isUnionThread(y.chat)
            ? y.chat.id
            : E.memberOf.get(y.chat.id);
          if (!Z) {
            C.push(y);
            continue;
          }
          if (l && !this.isUnionThread(y.chat) && !l.has(y.accountID)) continue;
          const X = w.get(Z),
            ye = y.hits ?? 0;
          (X === void 0 || ye > X) && w.set(Z, ye);
        }
        const H = [...w.keys()].filter((y) => !o.get(y)),
          D = new Map(
            (H.length ? await this.bc.chatPreviewRepo.getRoomsByID(H) : []).map(
              (y) => [y.id, y],
            ),
          );
        T = [
          ...C,
          ...[...w].flatMap(([y, Z]) => {
            const X = o.get(y),
              ye = X?.chat ?? D.get(y);
            return ye
              ? [
                  {
                    chat: ye,
                    accountID: X?.accountID ?? ye.accountID ?? "",
                    hits: Z,
                  },
                ]
              : [];
          }),
        ];
      }
      const R = T.filter((C) => this.isUnionThread(C.chat)).map((C) => C.chat);
      if (R.length > 0) {
        const C = new Map(
          (await this.enrichUnionThreads(R, E)).map((w) => [w.id, w]),
        );
        for (const w of T) {
          const H = C.get(w.chat.id);
          H && (w.chat = H);
        }
      }
      const P = (C, w) => {
        const H = Number(new Date(C.chat.timestamp)) || 0,
          D = Number(new Date(w.chat.timestamp)) || 0;
        return D !== H
          ? D - H
          : String(C.chat.id).localeCompare(String(w.chat.id));
      };
      r
        ? t?.scope === "participants"
          ? T.sort(P)
          : T.sort((C, w) => {
              const H = C.hits || 0,
                D = w.hits || 0;
              return D !== H ? D - H : P(C, w);
            })
        : T.sort(P);
      const Y = (C) => {
          const w = C.chat;
          if (
            w.extra?.roomType === "m.space" ||
            (l && !l.has(C.accountID) && !this.isUnionThread(w)) ||
            (t.type && t.type !== "any" && w.type !== t.type) ||
            (t.unreadOnly && !(Number(w.unreadCount || 0) > 0)) ||
            (t.labelID &&
              !m.labelsByRoom.get(w.id)?.some((H) => H.id === t.labelID)) ||
            (!d && p?.has(w.id)) ||
            (g != null && Number(new Date(w.timestamp)) >= g) ||
            (f != null && Number(new Date(w.timestamp)) <= f)
          )
            return !1;
          if (i) {
            const H = Or(w),
              D = sa(w);
            if (i === "primary") {
              if (H || D) return !1;
              const y = m.visibilityByRoom.get(w.id) ?? A(C.accountID, C.chat);
              if (
                y === "none" ||
                (y === "dmOnly" &&
                  w.type === "group" &&
                  w.extra?.bridge?.["com.beeper.room_type.v2"] !== "group_dm")
              )
                return !1;
            } else if (i === "low-priority") {
              if (!D) return !1;
            } else if (i === "archive" && !H) return !1;
          }
          return !0;
        },
        z = r && t?.scope !== "participants" ? "titles" : "time",
        M = (C) => Buffer.from(JSON.stringify(C)).toString("base64"),
        q = (C) => {
          if (!C) return null;
          try {
            const w = JSON.parse(Buffer.from(C, "base64").toString());
            if (w && typeof w == "object") return w;
          } catch {}
          return null;
        },
        V = (C, w) =>
          w.ts !== C.ts
            ? w.ts - C.ts
            : String(C.id).localeCompare(String(w.id)),
        te = (C, w) =>
          w.score !== C.score
            ? w.score - C.score
            : w.ts !== C.ts
              ? w.ts - C.ts
              : String(C.id).localeCompare(String(w.id)),
        oe = (C) => Number(new Date(C)) || 0,
        re = T.reduce((C, w, H) => {
          if (!Y(w)) return C;
          const D = String(w.chat.id),
            y = oe(w.chat.timestamp),
            Z =
              z === "titles"
                ? { score: Number(w.hits || 0), ts: y, id: D }
                : { ts: y, id: D };
          return (C.push({ candidate: w, index: H, key: Z }), C);
        }, []),
        ae = q(t.cursor),
        ie = z === "titles" ? (C, w) => te(C, w) : (C, w) => V(C, w),
        G = ae
          ? re.filter((C) => {
              const w = ie(C.key, ae);
              return a === "before" ? w > 0 : w < 0;
            })
          : re,
        U = G.slice(0, c),
        ne = U.map((C) => C.candidate),
        pe = await this.getThreadPropsForMappedChats(
          ne.map((C) => ({ accountID: C.accountID, threadID: C.chat.id })),
        ),
        S = await Promise.all(
          ne.map((C) =>
            this.mapChat(
              C.chat,
              20,
              pe,
              {
                chatID: C.chat.id,
                localChatID: na(C.chat),
                accountID: C.accountID,
              },
              p,
              m,
              E,
            ),
          ),
        ),
        $ = G.length > c,
        J = U.length > 0 ? M(U[U.length - 1].key) : null,
        ce = U.length > 0 ? M(U[0].key) : null;
      return { items: S, hasMore: $, oldestCursor: J, newestCursor: ce };
    } catch (t) {
      this.handleToolError(t, "searchChats");
    }
  }
  async listChats(e) {
    try {
      const t = this.toInternalAccountIDs(e.accountIDs),
        r = e.direction ?? "before",
        a = e.limit ?? 25,
        i = this.bc.pas.platformAPIStore.getInstances(),
        o = t?.filter((D) => D && D.trim().length > 0),
        u = o?.length ? o : i,
        c = this.bridgedAccountIDs.filter((D) => u.includes(D)),
        l = this.imessageAccountID,
        d = l ? u.includes(l) : !1;
      if (u.length === 0)
        return {
          items: [],
          hasMore: !1,
          oldestCursor: null,
          newestCursor: null,
        };
      const p = Xs(e.cursor),
        m = ((D) => {
          if (!D || typeof D != "string" || D.includes("|")) return !1;
          const y = Number(D);
          return Number.isFinite(y);
        })(e.cursor),
        g = c.length > 0 ? (m ? e.cursor : p.beeper) : void 0,
        f = d ? (m ? e.cursor : p.imessage) : void 0,
        A = g ? { cursor: g, direction: r } : void 0,
        T = f && Number.isInteger(Number(f)) ? Number(f) : null,
        E = { items: [], hasMore: !1, oldestCursor: null, newestCursor: null },
        [R, P] = await Promise.all([
          c.length
            ? this.bc.chatPreviewRepo.getRooms(c, A, a)
            : Promise.resolve(E),
          d && l ? this.getImessageThreads(l, T, r, a) : Promise.resolve(E),
        ]),
        Y = (D, y, Z) => ({
          source: D,
          accountID: Z,
          thread: y,
          timestampMs: z(y),
          localChatID:
            D === "beeper" &&
            "rowID" in y &&
            y.rowID != null &&
            Number.isInteger(Number(y.rowID))
              ? Number(y.rowID)
              : null,
        }),
        z = (D) => Ne(D.timestamp) ?? 0,
        M = await this.getUnionContext(),
        q = R.items.filter(
          (D) => !this.isUnionThread(D) && !M.memberOf.has(D.id),
        ),
        V =
          qi(g) ??
          (g && Number.isFinite(+g)
            ? { timestamp: +g, id: r === "before" ? -1 / 0 : 1 / 0 }
            : null),
        te =
          M.members.size === 0
            ? []
            : await this.bc.chatPreviewRepo.getRoomsByID([
                ...M.memberOf.keys(),
              ]),
        oe = new Map(te.map((D) => [D.id, D.accountID ?? ""])),
        re =
          M.members.size === 0
            ? []
            : (
                await this.bc.chatPreviewRepo.getRoomsByID([
                  ...M.members.keys(),
                ])
              ).filter((D) =>
                (M.members.get(D.id) ?? []).some((y) =>
                  c.includes(oe.get(y) ?? ""),
                ),
              ),
        ae = (await this.enrichUnionThreads(re, M, te)).filter((D) => {
          if (V === null) return !0;
          const y = Ne(D.timestamp) ?? 0;
          if (y !== V.timestamp)
            return r === "before" ? y < V.timestamp : y > V.timestamp;
          const Z = Number(D.rowID);
          return Number.isFinite(Z)
            ? r === "before"
              ? Z < V.id
              : Z > V.id
            : !1;
        }),
        G = [
          ...q.map((D) => Y("beeper", D, D.accountID)),
          ...ae.map((D) => Y("beeper", D, D.accountID)),
          ...P.items.map((D) => Y("imessage", D, l)),
        ]
          .sort((D, y) =>
            y.timestampMs !== D.timestampMs
              ? y.timestampMs - D.timestampMs
              : D.source !== y.source
                ? D.source < y.source
                  ? -1
                  : 1
                : D.source === "beeper" &&
                    D.localChatID != null &&
                    y.localChatID != null
                  ? y.localChatID - D.localChatID
                  : String(D.thread.id).localeCompare(String(y.thread.id)),
          )
          .slice(0, a),
        U = {
          beeper: {
            fetched: q.length + ae.length,
            used: 0,
            firstCursor: null,
            lastCursor: null,
          },
          imessage: {
            fetched: P.items.length,
            used: 0,
            firstCursor: null,
            lastCursor: null,
          },
        },
        ne = (D) =>
          D.source !== "beeper" || D.localChatID == null
            ? String(D.timestampMs)
            : (ji(D.timestampMs, D.localChatID) ?? String(D.timestampMs));
      if (
        (G.forEach((D) => {
          const y = U[D.source];
          y.used += 1;
          const Z = ne(D);
          (y.firstCursor || (y.firstCursor = Z), (y.lastCursor = Z));
        }),
        U.beeper.used === 0 && q.length + ae.length === 0 && R.items.length > 0)
      ) {
        const D = R.items[r === "before" ? R.items.length - 1 : 0],
          y = ne(Y("beeper", D, D.accountID));
        r === "before" ? (U.beeper.lastCursor = y) : (U.beeper.firstCursor = y);
      }
      const pe = (D, y) => {
          const Z = D.messages?.items?.[0];
          if (Z)
            return {
              ...Z,
              threadID: Z.threadID ?? y.id,
              accountID: Z.accountID ?? y.accountID,
            };
          const X = D.partialLastMessage;
          if (!X) return null;
          const ye = Ne(X.timestamp) ?? Ne(y.lastActivity);
          return ye == null
            ? null
            : {
                id: String(X.id ?? y.id),
                threadID: y.id,
                accountID: y.accountID,
                senderID: X.senderID ?? "none",
                timestamp: new Date(ye),
                text: X.text,
                isSender: X.isSender ?? !1,
                impersonator: X.impersonator,
                sortKey: X.sortKey,
              };
        },
        S = await this.getThreadPropsForMappedChats(
          G.filter((D) => !!D.accountID).map((D) => ({
            accountID: D.accountID,
            threadID: D.thread.id,
          })),
        ),
        $ = await this.bc.roomMessageRepo.getMutedRoomIDsSet(),
        J = await this.getLabelContext(),
        ce = await Promise.all(
          G.map(async (D) => {
            const y = await this.mapChat(
                D.thread,
                20,
                S,
                D.accountID
                  ? {
                      chatID: D.thread.id,
                      localChatID: na(D.thread),
                      accountID: D.accountID,
                    }
                  : void 0,
                $,
                J,
                M,
              ),
              Z = pe(D.thread, y);
            if (!Z) return y;
            const X = await this.mapMessage(Z, {
              getCachedChat: async () => y,
            });
            return { ...y, preview: X };
          }),
        ),
        C =
          R.hasMore ||
          P.hasMore ||
          U.beeper.used < U.beeper.fetched ||
          U.imessage.used < U.imessage.fetched,
        w = ir({
          beeper: U.beeper.lastCursor ?? g,
          imessage: U.imessage.lastCursor ?? f,
        }),
        H = ir({
          beeper: U.beeper.firstCursor ?? g,
          imessage: U.imessage.firstCursor ?? f,
        });
      return { items: ce, hasMore: C, oldestCursor: w, newestCursor: H };
    } catch (t) {
      this.handleToolError(t, "listChats");
    }
  }
  async fetchMessagesPage(e, t) {
    const r = async () => {
      const o = t
        ? await this.callPAPIForChat(e, "getMessages", t)
        : await this.callPAPIForChat(e, "getMessages");
      if (o.error) throw o.error;
      return o;
    };
    let a = await r(),
      i = !1;
    if (!e.startsWith("imsg##") && (!t || t.direction === "before")) {
      if ((a.result?.items || []).length === 0)
        a.result?.hasMore &&
          ((i = !0), await this.waitForBackfill(e), (a = await r()));
      else if (!a.result?.hasMore) {
        let o;
        try {
          o = await this.bc.hitEndOfRoomWithState(e);
        } catch (u) {
          logger.warn(
            `[BeeperConnectTools] hitEndOfRoomWithState failed for ${e}:`,
            u,
          );
        }
        o?.did_request_backfill &&
          ((i = !o.is_fully_paginated),
          await this.waitForBackfill(e),
          (a = await r()));
      }
    }
    return {
      items: a.result?.items || [],
      hasMore: (a.result?.hasMore ?? !1) || i,
    };
  }
  async listMergedMessages(e, t) {
    const r = t.direction ?? "before",
      a = sp(t.cursor),
      i = !!a && r === "after",
      o = i ? a.newest : a?.oldest,
      u = await Promise.all(
        e.map(async (A) => {
          const T = o?.[A];
          if (i && T) {
            let E = [],
              R = 0,
              P;
            for (;;) {
              const { result: Y, error: z } = await this.callPAPIForChat(
                A,
                "getMessages",
                P,
                T,
              );
              if (z) throw z;
              const M = Y?.items || [],
                q = M.filter((V) => Number(V.sortKey) > Number(T));
              if (
                ((R += q.length),
                (E = [...q, ...E].slice(0, Lr)),
                q.length === 0 || q.length < M.length)
              )
                break;
              P = { cursor: String(M[0].sortKey), direction: "before" };
            }
            return { memberID: A, items: E, hasMore: R > Lr, capped: R > Lr };
          }
          return {
            memberID: A,
            capped: !1,
            ...(await this.fetchMessagesPage(
              A,
              T ? { cursor: T, direction: r } : void 0,
            )),
          };
        }),
      ),
      c = (A) => new Date(A.timestamp).getTime(),
      l = i
        ? Math.min(
            ...u
              .filter((A) => A.capped)
              .map((A) => Math.max(...A.items.map(c))),
          )
        : Vi(
            u.map((A) => ({
              hasOlderMessages: A.hasMore,
              oldestLoadedTime: Zi(A.items),
            })),
          ),
      d = { oldest: { ...a?.oldest }, newest: { ...a?.newest } },
      p = [];
    let h = !1;
    for (const A of u) {
      let T = 0,
        E = A.items.length;
      if (i) for (E = 0; E < A.items.length && c(A.items[E]) <= l;) E++;
      else for (T = E; T > 0 && c(A.items[T - 1]) >= l;) T--;
      const R = A.items.slice(T, E);
      (p.push(...R),
        (h ||= (i ? A.capped : A.hasMore) || R.length < A.items.length),
        R.length > 0 &&
          (!i || d.oldest[A.memberID] == null) &&
          (d.oldest[A.memberID] = String(R[0].sortKey)));
      const P = i ? R.at(-1) : A.items.at(-1);
      P &&
        (i || d.newest[A.memberID] == null) &&
        (d.newest[A.memberID] = String(P.sortKey));
    }
    p.sort($i);
    const m = this.createPerRequestChatResolver(e),
      g = await Promise.all(
        p.map((A) => this.mapMessage(A, { getCachedChat: m.get })),
      ),
      f = rp(d);
    return { items: g, hasMore: h, oldestCursor: f, newestCursor: f };
  }
  async listMessages(e) {
    try {
      const { meta: t, error: r } = await this.getChatMeta(e.chatID);
      if (r) throw r;
      const { chatID: a } = t,
        i = (await this.bc.spaceChildRepo?.getUnionMembers?.(a)) ?? [],
        o = new Set(
          (await this.bc.chatPreviewRepo.getRoomsByID(i)).map((E) => E.id),
        ),
        u = i.filter((E) => o.has(E));
      if (u.length > 0) return await this.listMergedMessages(u, e);
      const c = e.direction ?? "before",
        l = e.cursor ? { cursor: e.cursor, direction: c } : void 0,
        { items: d, hasMore: p } = await this.fetchMessagesPage(a, l),
        h = this.createPerRequestChatResolver([a]),
        m = await Promise.all(
          d.map((E) => this.mapMessage(E, { getCachedChat: h.get })),
        );
      m.sort((E, R) => {
        const P = E.sortKey ?? String(E.id),
          Y = R.sortKey ?? String(R.id);
        return Mr(P, Y);
      });
      const g = ia(m),
        f = (E) => (E?.sortKey != null ? String(E.sortKey) : null),
        A = f(g.at(-1)),
        T = f(g[0]);
      return { items: g, hasMore: p, oldestCursor: A, newestCursor: T };
    } catch (t) {
      this.handleToolError(t, "listMessages");
    }
  }
  async waitForBackfill(e) {
    const i = Date.now();
    let o = !1;
    for (;;) {
      const u = Date.now() - i,
        c = this.bc.currentlyPaginatingRooms.has(e);
      if ((c && (o = !0), !c && (o || u > 1e3))) break;
      if (u > 1e4) {
        logger.warn(
          `[BeeperConnectTools] Timed out waiting for pagination to finish for ${e}`,
        );
        break;
      }
      await An(100);
    }
  }
  async searchMessages(e) {
    try {
      const t = this.toInternalAccountIDs(e.accountIDs),
        r = e.direction || "before",
        a = Xs(e.cursor),
        i = "beeper" in a || "imessage" in a,
        o = a.beeper
          ? { cursor: a.beeper, direction: r }
          : !i && e.cursor
            ? { cursor: e.cursor, direction: r }
            : void 0,
        u = a.imessage ? { cursor: a.imessage, direction: r } : void 0;
      let c;
      e.mediaTypes &&
        e.mediaTypes.length > 0 &&
        (e.mediaTypes.includes("any")
          ? (c = "all")
          : (c = {
              video: e.mediaTypes.includes("video"),
              image: e.mediaTypes.includes("image"),
              link: e.mediaTypes.includes("link"),
              file: e.mediaTypes.includes("file"),
            }));
      let l;
      e.chatIDs &&
        e.chatIDs.length > 0 &&
        (l = (
          await Promise.all(
            e.chatIDs.map(async (G) => {
              const { meta: U, error: ne } = await this.getChatMeta(G);
              if (ne) throw ne;
              const { chatID: pe } = U,
                S = (await this.bc.spaceChildRepo?.getUnionMembers?.(pe)) ?? [];
              return S.length > 0 ? S : [pe];
            }),
          )
        ).flat());
      const d = this.imessageAccountID,
        p = Math.min(e.limit ?? 50, 20),
        h = await this.bc.searchRoomMessages(e.query || "", o, {
          roomIDs: l,
          accountIDs: t,
          roomType: e.chatType,
          media: c,
          partialMatchesEnabled: !0,
          sender: e.sender,
          date: {
            after: e.dateAfter ? new Date(e.dateAfter) : void 0,
            before: e.dateBefore ? new Date(e.dateBefore) : void 0,
          },
          useFts: !0,
          limit: p,
          excludeLowPriority: e.excludeLowPriority ?? !0,
          excludeMuted: !e.includeMuted,
        });
      let g = [...h.items.slice(0, p)],
        f = h.hasMore || h.items.length > p;
      const A = h.oldestCursor ?? null,
        T = h.newestCursor ?? null,
        E = a.imessage ?? null;
      let R = E,
        P = E,
        Y = !1;
      if (!!(d && (!t || t.includes(d))) && d)
        try {
          const G = {
              threadID: l?.[0],
              sender:
                e.sender === "me"
                  ? "me"
                  : e.sender === "others"
                    ? void 0
                    : e.sender,
              mediaType: c === "all" ? "all" : void 0,
            },
            U = await this.bc.pas.platformAPIStore.callMethod({
              accountID: d,
              methodName: "searchMessages",
              args: [e.query || "", u, G],
            });
          if (U?.items) {
            const ne = U.items.map((pe) => ({
              ...pe,
              accountID: d,
              threadID: pe.threadID || "",
            }));
            ((g = [...g, ...ne]),
              (Y = U.hasMore ?? !1),
              (f = f || Y),
              typeof U.oldestCursor == "string" && (R = U.oldestCursor),
              typeof U.newestCursor == "string" && (P = U.newestCursor));
          }
        } catch (G) {
          logger.warn(`[BeeperConnectTools] iMessage search failed: ${G}`);
        }
      g.sort((G, U) => {
        const ne = G.sortKey ?? String(G.id),
          pe = U.sortKey ?? String(U.id);
        return Mr(ne, pe);
      });
      const q = g.slice(0, p),
        V = f || g.length > p,
        te = this.createPerRequestChatResolver([
          ...new Set(q.map((G) => G.threadID)),
        ]),
        oe = await Promise.all(
          q.map((G) => this.mapMessage(G, { getCachedChat: te.get })),
        ),
        re = ia(oe),
        ae = ir({ beeper: A, imessage: R }),
        ie = ir({ beeper: T, imessage: P });
      return {
        items: re,
        chats: await te.getAll(),
        hasMore: V,
        oldestCursor: ae,
        newestCursor: ie,
      };
    } catch (t) {
      this.handleToolError(t, "searchMessages");
    }
  }
  async sendMessage(e) {
    try {
      const { chatID: t, replyToMessageID: r, attachment: a } = e;
      if (!t) throw new B("chatID is required", "INVALID_INPUT", 400);
      const { meta: i, error: o } = await this.getChatMeta(t);
      if (o) throw o;
      const { chatID: u } = i,
        l =
          (r
            ? await this.resolveUnionMessageTarget(u, r)
            : await this.resolveUnionSendTarget(u, i.accountID)) ?? u,
        d = await wd(e),
        p = { text: d.text };
      if (a) {
        const g = await this.resolveUploadedMessageAttachment(a),
          f = await this.bc.chatPreviewRepo.getRoomFeatures(l),
          A = hn(
            {
              mimeType: g.mimeType,
              fileSize: g.fileSize,
              size: g.size,
              duration: g.duration,
              isVoiceNote: g.isVoiceNote,
              isSticker: g.isSticker,
            },
            f,
            !1,
            !0,
          );
        if (A.action === "REJECT")
          throw new Ds(`Attachment validation failed: ${A.reason}`, {
            errorType: A.errorType,
          });
        if (A.action === "MISSING_INFO")
          throw new Ds(
            `Missing attachment information: ${A.missingOrInvalidFields.join(", ")}`,
            { missingFields: A.missingOrInvalidFields },
          );
        ((p.filePath = g.filePath),
          (p.fileName = g.fileName),
          (p.mimeType = g.mimeType),
          (p.size = g.size),
          (p.isGif = g.isGif),
          (p.isRecordedAudio = g.isVoiceNote),
          (p.stickerID = g.isSticker ? g.fileName : void 0),
          g.duration && (p.audioDurationSeconds = g.duration));
      }
      const h = {
          quotedMessageID: r,
          pendingMessageID: l.startsWith("imsg##")
            ? St()
            : await this.bc.generatePendingMessageID(l),
          formatText: d.formatText,
          eventExtra: d.eventExtra,
        },
        m = await this.callPAPIForChat(l, "sendMessage", p, h);
      if (m.error) throw m.error;
      return (
        logger.log(
          `[BeeperConnectTools] Message sent successfully, txnID: ${h.pendingMessageID}`,
        ),
        { chatID: l, pendingMessageID: h.pendingMessageID }
      );
    } catch (t) {
      this.handleToolError(t, "sendMessage");
    }
  }
  async editMessage(e) {
    try {
      const { chatID: t, messageID: r, text: a } = e;
      if (!t) throw new B("chatID is required", "INVALID_INPUT", 400);
      if (!r) throw new B("messageID is required", "INVALID_INPUT", 400);
      if (!a) throw new B("text is required", "INVALID_INPUT", 400);
      const { meta: i, error: o } = await this.getChatMeta(t);
      if (o) throw o;
      const u = (await this.resolveUnionMessageTarget(i.chatID, r)) ?? i.chatID,
        { result: c, error: l } = await this.callPAPIForChat(
          u,
          "getMessage",
          r,
        );
      if (l) throw l;
      if (!c) throw new B("Message not found", "NOT_FOUND", 404);
      const d = c.attachments?.length ?? 0;
      if (d > 1 || (d === 1 && !mn.includes(c.extra?.type ?? "")))
        throw new B(
          "Cannot edit messages with attachments",
          "EDIT_NOT_ALLOWED",
          400,
        );
      const p = { text: a },
        h = await this.callPAPIForChat(u, "editMessage", r, p);
      if (h.error) throw h.error;
      logger.log(`[BeeperConnectTools] Message edited successfully: ${r}`);
      const m = this.createPerRequestChatResolver([u]),
        [g] = await Promise.all([
          this.callPAPIForChat(u, "getMessage", r),
          m.get(u),
        ]);
      if (g.error) throw g.error;
      if (!g.result) throw new B("Message not found", "NOT_FOUND", 404);
      const f = await this.mapMessage(g.result, {
        accountID: i.accountID,
        getCachedChat: m.get,
      });
      return { ...f, success: !0, messageID: f.id };
    } catch (t) {
      this.handleToolError(t, "editMessage");
    }
  }
  async deleteMessage(e) {
    try {
      const { chatID: t, messageID: r, forEveryone: a } = e;
      if (!t) throw new B("chatID is required", "INVALID_INPUT", 400);
      if (!r) throw new B("messageID is required", "INVALID_INPUT", 400);
      const { meta: i, error: o } = await this.getChatMeta(t);
      if (o) throw o;
      const u = (await this.resolveUnionMessageTarget(i.chatID, r)) ?? i.chatID,
        { error: c } = await this.callPAPIForChat(
          u,
          "deleteMessage",
          r,
          a ?? !0,
        );
      if (c) throw c;
    } catch (t) {
      this.handleToolError(t, "deleteMessage");
    }
  }
  async addReaction(e) {
    try {
      const {
          messageID: t,
          reactionKey: r,
          meta: a,
        } = await this.requireReactionInputs(e),
        i = (await this.resolveUnionMessageTarget(a.chatID, t)) ?? a.chatID;
      let o = e.transactionID;
      if (!o)
        try {
          o = await this.bc.generatePendingReactionID(i);
        } catch {
          o = St();
        }
      const { error: u } = await this.callPAPIForChat(
        i,
        "addReaction",
        t,
        r,
        o,
      );
      if (u) throw u;
      return {
        success: !0,
        chatID: i,
        messageID: t,
        reactionKey: r,
        transactionID: o,
      };
    } catch (t) {
      this.handleToolError(t, "addReaction");
    }
  }
  async removeReaction(e) {
    try {
      const {
          messageID: t,
          reactionKey: r,
          meta: a,
        } = await this.requireReactionInputs(e),
        i = (await this.resolveUnionMessageTarget(a.chatID, t)) ?? a.chatID,
        { error: o } = await this.callPAPIForChat(i, "removeReaction", t, r);
      if (o) throw o;
      return { success: !0, chatID: i, messageID: t, reactionKey: r };
    } catch (t) {
      this.handleToolError(t, "removeReaction");
    }
  }
  async search(e) {
    try {
      const t = e,
        [r, a, i] = await Promise.all([
          this.searchChats({ query: t.query, scope: "titles", limit: Qs }),
          this.searchChats({
            query: t.query,
            scope: "participants",
            limit: Qs,
          }),
          this.searchMessages({
            query: t.query,
            limit: Vd,
            includeMuted: !0,
            excludeLowPriority: !0,
          }),
        ]);
      return {
        results: {
          chats: r?.items || [],
          in_groups: a?.items || [],
          messages: i,
        },
      };
    } catch (t) {
      this.handleToolError(t, "search");
    }
  }
  async resolveMatrixAsset(e) {
    const t = Ur(e),
      r = t?.baseURL ?? e;
    if (!r || !Gi(r))
      return {
        success: !1,
        error: "URL must be mxc:// or localmxc://",
        statusCode: 400,
      };
    const a = this.matrixAssetCache.get(r);
    if (a)
      try {
        return (await le.access(a), { success: !0, filePath: a });
      } catch {
        this.matrixAssetCache.delete(r);
      }
    const i = await this.bc.mediaManager.getLocalPathIfDownloaded(r);
    if (i)
      return (this.matrixAssetCache.set(r, i), { success: !0, filePath: i });
    let o = t?.encryptedFileInfoJSON;
    if (!o) {
      const u = await this.bc.roomMessageRepo.findAttachmentByMXC(r);
      u?.attachment?.srcURL &&
        (o = Ur(u.attachment.srcURL)?.encryptedFileInfoJSON);
    }
    try {
      const u = await this.bc.mediaManager.getAsset(r, o);
      return (this.matrixAssetCache.set(r, u), { success: !0, filePath: u });
    } catch (u) {
      return {
        success: !1,
        error: `Failed to download asset: ${Ge(u)}`,
        statusCode: 502,
      };
    }
  }
  async downloadAsset(e) {
    try {
      const t = await this.resolveMatrixAsset(e.url);
      return t.success ? { srcURL: jr(t.filePath).toString() } : ra(t.error);
    } catch (t) {
      return ra(Ge(t));
    }
  }
  async serveAsset(e) {
    const { url: t } = e;
    if (t.startsWith("file://")) {
      let a;
      try {
        a = rn(t);
      } catch {
        return { success: !1, error: "Malformed file URL", statusCode: 400 };
      }
      const i = this.bc.pas.options.dataDirPath;
      let o, u;
      try {
        ((o = await le.realpath(a)), (u = await le.realpath(i)));
      } catch {
        return { success: !1, error: "File not found", statusCode: 404 };
      }
      return !(o === u || o.startsWith(u + W.sep)) || !Jd(o, u)
        ? (logger.warn(
            `[BeeperConnectTools] Rejected file access attempt: ${o}`,
          ),
          {
            success: !1,
            error:
              "Access denied: Path must be within allowed attachment directories",
            statusCode: 403,
          })
        : { success: !0, filePath: o };
    }
    const r = await this.resolveMatrixAsset(t);
    return r.success
      ? { success: !0, filePath: r.filePath }
      : { success: !1, error: r.error, statusCode: r.statusCode };
  }
  async uploadAsset(e) {
    try {
      const { content: t, buffer: r, fileName: a, mimeType: i } = e;
      let o,
        u = a || "file";
      if (
        ((u = W.basename(u)),
        (u === "" || u === "." || u === "..") && (u = "file"),
        Yd.test(u))
      )
        throw new B(
          "Invalid filename: hidden files or reserved names not allowed",
          "INVALID_FILENAME",
          400,
        );
      if (u.includes("\0") || u.length > 255)
        throw new B("Invalid filename", "INVALID_FILENAME", 400);
      if (t) o = Buffer.from(t, "base64");
      else if (r) o = r;
      else return { error: "Either content or buffer must be provided" };
      const { default: c } = await import("./utils-D8MokWSu.mjs").then(
          (A) => A.i,
        ),
        l = await c.fromBuffer(o);
      let d = i || l?.mime || "application/octet-stream";
      if (!W.extname(u)) {
        const A = l?.ext || ys.extension(d);
        A && (u = `${u}.${A}`);
      }
      const p = St(),
        h = W.join(await this.getConnectUploadDir(), p);
      await le.mkdir(h, { recursive: !0 });
      const m = W.join(h, u);
      (await le.writeFile(m, o), (d = (await Dn(m, d)) || d));
      const g = o.length,
        f = await this.extractAndCacheMetadata(m, u, d, p);
      return (
        this.cleanupOldUploads().catch((A) => {
          logger.warn("[BeeperConnectTools] Background cleanup failed:", A);
        }),
        logger.log(
          `[BeeperConnectTools] Uploaded asset: ${m} (${d}, ${g} bytes)`,
        ),
        {
          uploadID: p,
          srcURL: jr(m).toString(),
          fileName: u,
          mimeType: d,
          fileSize: g,
          ...f,
        }
      );
    } catch (t) {
      return (
        logger.error("[BeeperConnectTools] uploadAsset error:", t),
        { error: Ge(t) }
      );
    }
  }
  async uploadAssetBase64(e) {
    return this.uploadAsset(e);
  }
  async resolveUploadedMessageAttachment(e) {
    if (!e?.uploadID)
      throw new B("uploadID is required", "MISSING_UPLOAD_ID", 400);
    const t = await this.loadCachedMetadataByUploadID(e.uploadID);
    if (!t?.filePath)
      throw new B(
        `Upload not found: ${e.uploadID}. File may have expired.`,
        "UPLOAD_NOT_FOUND",
        404,
      );
    let r;
    try {
      r = await le.stat(t.filePath);
    } catch {
      throw new B(`Upload expired: ${e.uploadID}`, "UPLOAD_EXPIRED", 410);
    }
    const a =
        W.basename(e.fileName || t.fileName || W.basename(t.filePath)) ||
        "file",
      i =
        e.mimeType || t.mimeType || ys.lookup(a) || "application/octet-stream",
      o = e.duration ?? t.duration;
    return {
      filePath: t.filePath,
      fileName: a,
      mimeType: i,
      fileSize: r.size,
      size: e.size || t.size,
      duration: o,
      isGif: e.type === "gif" || i === "image/gif",
      isVoiceNote: e.type === "voice-note",
      isSticker: e.type === "sticker",
    };
  }
  async resolveDraftAttachmentsFromUploads(e) {
    if (e == null) return e;
    const t = await Promise.all(
      Object.entries(e).map(async ([r, a]) => {
        const i = await this.resolveUploadedMessageAttachment(a),
          o = Td(a.id ?? r),
          u = W.join(this.bc.pas.options.dataDirPath, "draft_attachments", o),
          c = W.join(u, i.fileName);
        return (
          await le.rm(u, { recursive: !0, force: !0 }),
          await le.mkdir(u, { recursive: !0 }),
          await le.copyFile(i.filePath, c),
          [
            o,
            {
              id: o,
              filePath: c,
              fileName: i.fileName,
              mimeType: i.mimeType,
              fileSize: i.fileSize,
              size: i.size,
              type: i.isVoiceNote ? "recorded_audio" : i.isGif ? "gif" : "file",
              audioDurationSeconds: i.duration,
              stickerID: i.isSticker ? i.fileName : void 0,
            },
          ]
        );
      }),
    );
    return Object.fromEntries(t);
  }
  async getConnectUploadDir() {
    return (
      (this.connectUploadDirPromise ??= (async () => {
        const e = W.join(this.bc.pas.options.dataDirPath, "api-uploads");
        return (await le.mkdir(e, { recursive: !0 }), e);
      })().catch((e) => {
        throw ((this.connectUploadDirPromise = void 0), e);
      })),
      this.connectUploadDirPromise
    );
  }
  async cleanupOldUploads() {
    return (
      (this.cleanupOldUploadsPromise ??= this.runCleanupOldUploads().finally(
        () => {
          this.cleanupOldUploadsPromise = void 0;
        },
      )),
      this.cleanupOldUploadsPromise
    );
  }
  async runCleanupOldUploads() {
    const e = await this.getConnectUploadDir(),
      t = Date.now() - 10080 * 60 * 1e3;
    try {
      const r = await le.readdir(e, { withFileTypes: !0 });
      await Promise.all(
        r
          .filter((a) => a.isDirectory())
          .map(async (a) => {
            const i = W.join(e, a.name);
            try {
              const o = await le.stat(i);
              o.birthtimeMs < t &&
                o.atimeMs < t &&
                (await le.rm(i, { recursive: !0, force: !0 }),
                logger.log(`[BeeperConnectTools] Cleaned up old upload: ${i}`));
            } catch (o) {
              logger.warn(
                `[BeeperConnectTools] Failed to stat upload directory ${i}:`,
                o,
              );
            }
          }),
      );
    } catch (r) {
      logger.warn("[BeeperConnectTools] Cleanup failed:", r);
    }
  }
  async extractAndCacheMetadata(e, t, r, a) {
    let i = {},
      o;
    try {
      i = await Promise.race([
        this.extractMediaDimensions(e, t, r),
        new Promise((c, l) =>
          setTimeout(
            () => l(new Error("Metadata extraction timeout (30s)")),
            3e4,
          ),
        ),
      ]);
    } catch (c) {
      (logger.warn(
        `[BeeperConnectTools] Failed to extract metadata for ${e}:`,
        c,
      ),
        (o = Ge(c)));
    }
    const u = W.join(W.dirname(e), "metadata.json");
    return (
      await le.writeFile(
        u,
        JSON.stringify(
          {
            fileName: t,
            mimeType: r,
            uploadID: a,
            extractedAt: new Date().toISOString(),
            ...i,
            ...(o && { error: o }),
          },
          null,
          2,
        ),
      ),
      i
    );
  }
  async extractMediaDimensions(e, t, r) {
    switch (gn(t, r)) {
      case nr.IMG: {
        const { width: i, height: o } = await bn(e);
        return i && o ? { width: i, height: o } : {};
      }
      case nr.VIDEO: {
        const { width: i, height: o, duration: u } = await yn(e);
        return { width: i, height: o, duration: u };
      }
      case nr.AUDIO: {
        const { duration: i } = await fn(e);
        return { duration: i };
      }
      default:
        return {};
    }
  }
  parseUploadMetadata(e) {
    const t = JSON.parse(e),
      r = t.width && t.height;
    return {
      fileName: t.fileName,
      mimeType: t.mimeType,
      size: r ? { width: t.width, height: t.height } : void 0,
      duration: t.duration,
    };
  }
  async loadCachedMetadataByUploadID(e) {
    try {
      const t = await this.getConnectUploadDir(),
        r = W.join(t, e),
        a = W.resolve(r);
      if (!a.startsWith(t + W.sep) && a !== t)
        return (
          logger.warn(`[BeeperConnectTools] Invalid uploadID rejected: ${e}`),
          null
        );
      const i = W.join(r, "metadata.json"),
        o = await le.readFile(i, "utf-8"),
        u = this.parseUploadMetadata(o),
        l = (await le.readdir(r, { withFileTypes: !0 })).find(
          (p) => p.isFile() && p.name !== "metadata.json",
        );
      return l
        ? { filePath: W.join(r, l.name), ...u }
        : (logger.warn(
            `[BeeperConnectTools] No file found in upload directory: ${r}`,
          ),
          null);
    } catch (t) {
      return (
        logger.debug(
          `[BeeperConnectTools] No cached metadata for uploadID ${e}:`,
          t,
        ),
        null
      );
    }
  }
}
const ip = new Set(["serveAsset", "uploadAsset"]),
  oa = (s) => s in si,
  _i = (s) =>
    s instanceof Hi ||
    (s instanceof Error && s.name === "ZodError" && Array.isArray(s.issues)),
  np = (s, e) => {
    if (s !== "setChatReminder") return e;
    const t = e.reminder;
    if (!ge(t) || t.remindAt !== void 0 || t.remindAtMs === void 0) return e;
    const r =
      typeof t.remindAtMs == "string" ? Number(t.remindAtMs) : t.remindAtMs;
    return typeof r != "number" || !Number.isFinite(r)
      ? e
      : { ...e, reminder: { ...t, remindAt: new Date(r).toISOString() } };
  },
  op = (s, e) => s === "createChat" && e.mode === "start",
  up = () =>
    Object.entries(si)
      .filter(([s]) => oa(s) && !ip.has(s))
      .map(([s, e]) => {
        if (!oa(s)) throw new Error(`Invalid route name: ${s}`);
        if (typeof Bi.prototype[s] != "function")
          throw new Error(`Missing BeeperConnectTools handler for route ${s}`);
        return {
          ...e,
          handler: async (r, a, i) => {
            let o, u;
            if (e.inputSchema)
              try {
                const p = np(s, { ...a.query, ...a.params, ...a.body });
                op(s, p) ? (u = Hr.parse(p)) : (o = e.inputSchema.parse(p));
              } catch (p) {
                throw _i(p) ? new pa("Invalid input", { issues: p.issues }) : p;
              }
            const c = r[s];
            if (typeof c != "function")
              throw new Error(
                `Missing BeeperConnectTools handler for route ${s}`,
              );
            const l = u ? await r.startChat(u) : await c.call(r, o);
            e.outputSchema instanceof Ki ? i.status(204).end() : i.json(l);
          },
        };
      }),
  Pp = up();
let cp = "useandom-26T198340PX75pxJACKVERYMINDBUSHWOLF_GQZbfghjklqvwyzrict";
const lp = 128;
let ze,
  at,
  dp = (s) => {
    (!ze || ze.length < s
      ? ((ze = Buffer.allocUnsafe(s * lp)), Is.randomFillSync(ze), (at = 0))
      : at + s > ze.length && (Is.randomFillSync(ze), (at = 0)),
      (at += s));
  },
  Nr = (s = 21) => {
    dp((s |= 0));
    let e = "";
    for (let t = at - s; t < at; t++) e += cp[ze[t] & 63];
    return e;
  };
const qp = 1440 * 60 * 1e3,
  pp = 30,
  ua = 300 * 1e3,
  hp = 120 * 1e3;
function mp(s, e, t = "S256") {
  if (!s || !e) return !1;
  if (t !== "S256") throw new Error("Only S256 method is supported");
  return sn("sha256").update(s).digest("base64url") === e;
}
class gp {
  constructor(e) {
    ((this.beeperConnect = e),
      (this.tokenCache = new Map()),
      (this.tokenHashToIDMap = new Map()),
      (this.pendingTokens = new Map()),
      (this.authorizationCodes = new Map()),
      (this.oauth2Clients = new Map()),
      (this.initialLoadPromise = this.loadTokens()));
  }
  async loadTokens() {
    const e =
        (await this.beeperConnect.beeperClient.indexDB.getKeyValue(
          "conn:tokens",
        )) ?? {},
      t =
        (await this.beeperConnect.beeperClient.indexDB.getKeyValue(
          "conn:clients",
        )) ?? {};
    (this.tokenCache.clear(),
      this.tokenHashToIDMap.clear(),
      this.oauth2Clients.clear());
    for (const r of Object.values(e))
      ((!r.scopes || !Array.isArray(r.scopes) || r.scopes.length === 0) &&
        ((r.scopes = ["read"]),
        this.beeperConnect.logger.warn(
          `[BeeperConnectAuth] Token ${r.id} had invalid/missing scopes, defaulting to ['read']`,
        )),
        this.tokenCache.set(r.id, r),
        this.tokenHashToIDMap.set(r.tokenHash, r.id));
    for (const r of Object.values(t)) this.oauth2Clients.set(r.clientID, r);
    this.beeperConnect.logger.log(
      `[BeeperConnectAuth] Loaded ${this.tokenCache.size} existing access tokens and ${this.oauth2Clients.size} OAuth2 clients`,
    );
  }
  async persist() {
    const e = Date.now() - pp * 24 * 60 * 60 * 1e3,
      t = {};
    for (const [r, a] of this.tokenCache.entries())
      a.expiresAt && a.expiresAt < e
        ? this.removeTokenFromCache(r)
        : (t[r] = { ...a, token: void 0 });
    await this.beeperConnect.beeperClient.indexDB.setKeyValue("conn:tokens", t);
  }
  async persistClients() {
    const e = {};
    for (const [t, r] of this.oauth2Clients.entries()) e[t] = r;
    await this.beeperConnect.beeperClient.indexDB.setKeyValue(
      "conn:clients",
      e,
    );
  }
  async waitForInitialLoad() {
    await this.initialLoadPromise;
  }
  async getTokens() {
    return (
      await this.initialLoadPromise,
      Array.from(this.tokenCache.values()).map((e) => ({ ...e, token: void 0 }))
    );
  }
  async getTokenByAccessToken(e) {
    await this.initialLoadPromise;
    const t = this.getMatrixAccessToken(e);
    if (t) return t;
    const r = rr(e),
      a = this.tokenHashToIDMap.get(r);
    if (!a) throw new Error("Token not found");
    const i = this.tokenCache.get(a);
    if (!i) throw new Error("Token found in hash map but not in cache");
    return i;
  }
  async getTokenByID(e) {
    await this.initialLoadPromise;
    const t = this.tokenCache.get(e);
    if (!t) throw new Error("Token not found");
    return t;
  }
  async validateTokenFromRequest(e) {
    const { accessToken: t } = Yi(e);
    return t
      ? this.validateToken(t)
      : {
          success: !1,
          error: {
            code: 401,
            errorCode: bt.UNAUTHORIZED,
            message: "Unauthorized: Invalid or missing token",
          },
        };
  }
  async validateToken(e) {
    const t = this.getMatrixAccessToken(e);
    if (t) return { success: !0, token: t };
    try {
      const r = await this.getTokenByAccessToken(e);
      return r.expiresAt && r.expiresAt < Date.now()
        ? {
            success: !1,
            error: {
              code: 401,
              errorCode: bt.UNAUTHORIZED,
              message: "Token expired",
            },
          }
        : { success: !0, token: { ...r, token: e } };
    } catch (r) {
      return (
        this.beeperConnect.logger.error(
          "[BeeperConnectAuth] Token validation error:",
          r,
        ),
        r instanceof Error && r.message.includes("Token not found")
          ? {
              success: !1,
              error: {
                code: 401,
                errorCode: bt.UNAUTHORIZED,
                message: "Invalid token",
              },
            }
          : {
              success: !1,
              error: {
                code: 500,
                errorCode: bt.INTERNAL_ERROR,
                message: Ge(r),
              },
            }
      );
    }
  }
  getMatrixAccessToken(e) {
    const t = this.beeperConnect.beeperClient.state;
    if (!t?.access_token) return null;
    const r = rr(e);
    return r !== rr(t.access_token)
      ? null
      : {
          id: t.user_id || "matrix",
          token: e,
          tokenHash: r,
          createdAt: Date.now(),
          scopes: ["read", "write"],
          clientInfo: {
            name: "Beeper Matrix session",
            clientID: "beeper-matrix-session",
          },
        };
  }
  verifyScopes(e, t) {
    if (!t.every((a) => e.scopes.includes(a))) {
      const a = t.filter((i) => !e.scopes.includes(i));
      return {
        valid: !1,
        message: `Insufficient permissions. Required scopes: ${t.join(", ")}, missing: ${a.join(", ")}`,
        missingScopes: a,
      };
    }
    return { valid: !0 };
  }
  async validateAndAuthorize(e, t) {
    const r = await this.validateTokenFromRequest(e);
    if (!r.success) return r;
    const a = this.verifyScopes(r.token, t);
    return a.valid
      ? { success: !0, token: r.token }
      : {
          success: !1,
          error: { code: 403, errorCode: bt.FORBIDDEN, message: a.message },
        };
  }
  async createAndPersistToken(e, t, r) {
    await this.initialLoadPromise;
    const { accessToken: a, tokenHash: i } = Ji(),
      o = Nr(),
      u = e,
      c = {
        id: o,
        token: void 0,
        tokenHash: i,
        createdAt: Date.now(),
        scopes: u,
        expiresAt: t > 0 ? Date.now() + t * 1e3 : void 0,
        clientInfo: r,
      };
    return (
      this.tokenCache.set(o, c),
      this.tokenHashToIDMap.set(i, o),
      await this.persist(),
      this.beeperConnect.logger.log(
        `[BeeperConnectAuth] Token ${o} stored: ${me(i)}`,
      ),
      { accessToken: a, tokenHash: i, tokenID: o }
    );
  }
  async createToken(e) {
    this.beeperConnect.logger.log(
      "[BeeperConnectAuth] Creating token from app (auto-approved)",
    );
    const {
        accessToken: t,
        tokenHash: r,
        tokenID: a,
      } = await this.createAndPersistToken(
        e.scopes,
        e.expiresInSeconds || 0,
        e.clientInfo,
      ),
      i = e.scopes;
    return {
      id: a,
      token: t,
      tokenHash: r,
      createdAt: Date.now(),
      scopes: i,
      expiresAt:
        e.expiresInSeconds > 0 ? Date.now() + e.expiresInSeconds * 1e3 : void 0,
      clientInfo: e.clientInfo,
    };
  }
  removeTokenFromCache(e) {
    const t = this.tokenCache.get(e);
    t &&
      (this.tokenCache.delete(e),
      t.tokenHash && this.tokenHashToIDMap.delete(t.tokenHash));
  }
  async revokeToken(e) {
    await this.initialLoadPromise;
    const t = this.tokenCache.get(e);
    if (!t) {
      this.beeperConnect.logger.log(
        `[BeeperConnectAuth] Token not found for revocation with ID: ${e}`,
      );
      return;
    }
    (this.beeperConnect.logger.log(
      `[BeeperConnectAuth] Revoking token with ID: ${e}`,
    ),
      this.tokenCache.delete(e),
      this.tokenHashToIDMap.delete(t.tokenHash),
      await this.persist());
  }
  async revokeTokenByAccessToken(e) {
    await this.initialLoadPromise;
    try {
      const t = rr(e),
        r = this.tokenHashToIDMap.get(t);
      r
        ? await this.revokeToken(r)
        : this.beeperConnect.logger.debug(
            "[BeeperConnectAuth] Token not found for revocation, returning success anyway per RFC 7009",
          );
    } catch (t) {
      this.beeperConnect.logger.error(
        "[BeeperConnectAuth] Error during token revocation:",
        t,
      );
    }
  }
  async requestTokenVerification(e, t, r = 0, a) {
    const i = a
      ? [...this.pendingTokens.values()].find(
          (u) =>
            u.clientInfo.clientID &&
            u.clientInfo.clientID === e.clientID &&
            u.redirectURI === a &&
            u.scopes.join(" ") === t.join(" "),
        )
      : void 0;
    if (i)
      return new Promise((u, c) => {
        const { resolve: l, reject: d } = i;
        ((i.resolve = (p) => {
          (l(p), u(p?.token || null));
        }),
          (i.reject = (p) => {
            (d(p), c(p));
          }));
      });
    const o = Nr();
    return (
      this.beeperConnect.logger.log(
        `[BeeperConnectAuth] Requesting token verification with requestID ${o}`,
      ),
      new Promise((u, c) => {
        const l = setTimeout(() => {
          const d = this.pendingTokens.get(o);
          d &&
            (this.pendingTokens.delete(o),
            this.beeperConnect.beeperClient.onAppEvent({
              type: tt.BEEPER_CONNECT_TOKEN_REQUEST_FINISHED,
              requestID: o,
              result: "timeout",
            }),
            d.reject(
              new Error("The token verification request has timed out"),
            ));
        }, hp);
        (this.pendingTokens.set(o, {
          requestID: o,
          clientInfo: e,
          scopes: t,
          redirectURI: a,
          expiresInSeconds: r,
          resolve: (d) => u(d?.token || null),
          reject: c,
          timeoutID: l,
        }),
          this.beeperConnect.beeperClient.onAppEvent({
            type: tt.BEEPER_CONNECT_TOKEN_REQUESTED,
            requestID: o,
            clientInfo: e,
            scopes: t,
          }));
      })
    );
  }
  async approveToken(e, t) {
    const r = this.pendingTokens.get(e);
    if (!r) throw new Error(`No pending token request found: ${e}`);
    (r.timeoutID && clearTimeout(r.timeoutID), this.pendingTokens.delete(e));
    const a = t?.scopes ?? r.scopes,
      i = t?.expiresInSeconds ?? r.expiresInSeconds,
      {
        accessToken: o,
        tokenHash: u,
        tokenID: c,
      } = await this.createAndPersistToken(a, i, r.clientInfo),
      l = a,
      d = {
        id: c,
        token: o,
        tokenHash: u,
        createdAt: Date.now(),
        scopes: l,
        expiresAt: i > 0 ? Date.now() + i * 1e3 : void 0,
        clientInfo: r.clientInfo,
      };
    r.resolve(d);
    const p = {
      id: c,
      tokenHash: u,
      createdAt: d.createdAt,
      scopes: d.scopes,
      expiresAt: d.expiresAt,
      clientInfo: d.clientInfo,
    };
    return (
      this.beeperConnect.beeperClient.onAppEvent({
        type: tt.BEEPER_CONNECT_TOKEN_REQUEST_FINISHED,
        requestID: e,
        result: "approved",
        token: p,
      }),
      u
    );
  }
  async rejectToken(e) {
    const t = this.pendingTokens.get(e);
    if (!t) throw new Error(`No pending token request found: ${e}`);
    (t.timeoutID && clearTimeout(t.timeoutID),
      t.resolve(null),
      this.pendingTokens.delete(e),
      this.beeperConnect.beeperClient.onAppEvent({
        type: tt.BEEPER_CONNECT_TOKEN_REQUEST_FINISHED,
        requestID: e,
        result: "rejected",
      }));
  }
  async registerOAuth2Client(e) {
    await this.initialLoadPromise;
    const t = e.client_name || "MCP Client",
      r = e.client_uri,
      a = e.redirect_uris || [],
      i = ["authorization_code"],
      o = ["code"],
      u = e.scope || "read write",
      c = e.token_endpoint_auth_method || "none";
    if (
      !Array.isArray(a) ||
      a.length === 0 ||
      a.some((m) => typeof m != "string" || !Qi(m))
    )
      throw new Error(
        "redirect_uris must contain at least one loopback HTTP/HTTPS or private-use URI scheme redirect",
      );
    if (c !== "none")
      throw new Error(
        'Only public clients with token_endpoint_auth_method "none" are supported',
      );
    if (e.grant_types && !e.grant_types.includes("authorization_code"))
      throw new Error("authorization_code grant type is required");
    if (e.response_types && !e.response_types.includes("code"))
      throw new Error("code response type is required");
    if (
      u
        .split(" ")
        .filter(Boolean)
        .some((m) => m !== "read" && m !== "write")
    )
      throw new Error("Only read and write scopes are supported");
    const d = Nr(),
      p = Date.now(),
      h = {
        clientID: d,
        clientName: t,
        clientURI: r,
        redirectURIs: a,
        grantTypes: i,
        responseTypes: o,
        scope: u,
        tokenEndpointAuthMethod: c,
        createdAt: p,
      };
    return (
      this.oauth2Clients.set(d, h),
      await this.persistClients(),
      this.beeperConnect.logger.log(
        `[BeeperConnectAuth] OAuth2 client registered: ${d} (${t})`,
      ),
      {
        client_id: d,
        client_name: t,
        client_uri: r,
        grant_types: i,
        response_types: o,
        redirect_uris: a,
        scope: u,
        token_endpoint_auth_method: c,
        client_id_issued_at: Math.floor(p / 1e3),
      }
    );
  }
  async getOAuth2Client(e) {
    return (await this.initialLoadPromise, this.oauth2Clients.get(e) || null);
  }
  storeAuthorizationCode(e, t) {
    return this.authorizationCodes.has(e)
      ? (this.beeperConnect.logger.warn(
          `[BeeperConnectAuth] Attempted to store duplicate authorization code: ${me(e)}`,
        ),
        !1)
      : (t.resource && !t.audience && (t.audience = t.resource),
        this.authorizationCodes.set(e, t),
        this.beeperConnect.logger.debug(
          `[BeeperConnectAuth] Auth code stored: ${me(e)} → token: ${me(t.token)}`,
        ),
        !0);
  }
  exchangeAuthorizationCode(e, t) {
    this.cleanupAuthorizationCodes();
    const r = this.authorizationCodes.get(e);
    if (!r)
      return (
        this.beeperConnect.logger.error(
          `[BeeperConnectAuth] Code exchange failed: ${me(e)} not found`,
        ),
        null
      );
    const a = Date.now();
    return r.createdAt + ua < a
      ? (this.beeperConnect.logger.error(
          `[BeeperConnectAuth] Authorization code expired: ${me(e)}`,
        ),
        this.authorizationCodes.delete(e),
        null)
      : r.codeChallenge
        ? t
          ? mp(t, r.codeChallenge, r.codeChallengeMethod || "S256")
            ? (this.beeperConnect.logger.debug(
                `[BeeperConnectAuth] PKCE verification successful for code: ${me(e)}`,
              ),
              this.authorizationCodes.delete(e),
              this.beeperConnect.logger.log(
                `[BeeperConnectAuth] Exchanged authorization code: ${me(e)}`,
              ),
              r)
            : (this.beeperConnect.logger.warn(
                `[BeeperConnectAuth] Invalid PKCE code verifier for code: ${me(e)}`,
              ),
              null)
          : (this.beeperConnect.logger.warn(
              `[BeeperConnectAuth] Code verifier required but not provided for code: ${me(e)}`,
            ),
            null)
        : (this.beeperConnect.logger.error(
            `[BeeperConnectAuth] Authorization code was created without PKCE challenge: ${me(e)}`,
          ),
          null);
  }
  cleanupAuthorizationCodes() {
    const e = Date.now();
    for (const [t, r] of this.authorizationCodes)
      r.createdAt + ua < e &&
        (this.authorizationCodes.delete(t),
        this.beeperConnect.logger.debug(
          `[BeeperConnectAuth] Cleaned up expired authorization code: ${me(t)}`,
        ));
  }
  async handleOAuth2TokenRequest(e) {
    if (e.grant_type !== "authorization_code")
      return (
        this.beeperConnect.logger.warn(
          `[BeeperConnectAuth] Unsupported grant_type: ${e.grant_type}`,
        ),
        {
          error: Ze.UNSUPPORTED_GRANT_TYPE,
          error_description: "Only authorization_code grant type is supported.",
        }
      );
    if (!e.code)
      return {
        error: Ze.INVALID_REQUEST,
        error_description: "Authorization code is required",
      };
    if (!e.code_verifier)
      return (
        this.beeperConnect.logger.error(
          "[BeeperConnectAuth] Missing code_verifier for PKCE",
        ),
        {
          error: Ze.INVALID_REQUEST,
          error_description: "code_verifier is required",
        }
      );
    e.client_id &&
      ((await this.getOAuth2Client(e.client_id)) ||
        this.beeperConnect.logger.debug(
          `[BeeperConnectAuth] Unregistered client_id with PKCE: ${e.client_id}`,
        ));
    const t = this.exchangeAuthorizationCode(e.code, e.code_verifier);
    if (!t)
      return (
        this.beeperConnect.logger.error(
          "[BeeperConnectAuth] Failed to exchange authorization code",
        ),
        {
          error: Ze.INVALID_GRANT,
          error_description: "Invalid or expired authorization code",
        }
      );
    if (t.clientID && t.clientID !== e.client_id)
      return (
        this.beeperConnect.logger.error(
          `[BeeperConnectAuth] Client ID mismatch: expected ${t.clientID}, got ${e.client_id}`,
        ),
        { error: Ze.INVALID_GRANT, error_description: "Client mismatch" }
      );
    if (e.resource && t.resource && e.resource !== t.resource)
      return (
        this.beeperConnect.logger.error(
          `[BeeperConnectAuth] Resource mismatch: expected ${t.resource}, got ${e.resource}`,
        ),
        {
          error: Ze.INVALID_GRANT,
          error_description: "Resource parameter mismatch",
        }
      );
    this.beeperConnect.logger.log(
      `[BeeperConnectAuth] Code exchanged: ${me(e.code)} → token: ${me(t.token)}`,
    );
    let r;
    try {
      r = await this.getTokenByAccessToken(t.token);
    } catch (o) {
      return (
        this.beeperConnect.logger.error(
          "[BeeperConnectAuth] Failed to retrieve token details after code exchange:",
          o,
        ),
        {
          error: Ze.SERVER_ERROR,
          error_description: "Failed to retrieve token details",
        }
      );
    }
    const a = r.scopes.join(" "),
      i = r.expiresAt
        ? Math.max(0, Math.floor((r.expiresAt - Date.now()) / 1e3))
        : void 0;
    return {
      access_token: t.token,
      token_type: "Bearer",
      expires_in: i,
      scope: a,
    };
  }
  async dispose() {
    this.beeperConnect.logger.log(
      "[BeeperConnectAuth] Disposing BeeperConnectAuth",
    );
    for (const [, e] of this.pendingTokens)
      (e.timeoutID && clearTimeout(e.timeoutID),
        e.reject(new Error("Beeper Client API was turned off")));
    (this.pendingTokens.clear(),
      this.tokenCache.clear(),
      this.tokenHashToIDMap.clear(),
      this.authorizationCodes.clear(),
      this.oauth2Clients.clear(),
      this.beeperConnect.logger.log(
        "[BeeperConnectAuth] BeeperConnectAuth disposed",
      ));
  }
}
class fp {
  constructor(e) {
    ((this.beeperClient = e),
      (this.logger = In("desktop-api")),
      (this.sharedHTTPServer = null),
      (this.loadSharedHTTPServer = Xi(async () => {
        const { BeeperConnectHTTPServer: t } =
          await import("./http-server-yJjafArR.mjs").then((r) => r.v);
        return ((this.sharedHTTPServer = new t(this)), this.sharedHTTPServer);
      })),
      (this.tools = new Bi(this)),
      (this.auth = new gp(this)),
      (this.readyPromise = this.initialize()));
  }
  async getToken(e) {
    return this.auth.getTokenByAccessToken(e);
  }
  async initialize() {
    (await this.beeperClient.indexDB.waitForInit(),
      await this.auth.waitForInitialLoad());
  }
  async waitForReady() {
    await this.readyPromise;
  }
  get state() {
    return this.buildState();
  }
  get enabled() {
    return !en.conf.desktop_api_disabled;
  }
  get serverURL() {
    return this.getConfiguredBaseURL();
  }
  get transportOptions() {
    return this.beeperClient.pas.options.transportOptions;
  }
  get hostname() {
    return this.transportOptions.hostname?.trim();
  }
  get port() {
    return this.transportOptions.port;
  }
  getConfiguredBaseURL() {
    return tn("http", this.hostname || "localhost", this.port);
  }
  buildState() {
    return this.enabled
      ? {
          status: "running",
          url: this.getConfiguredBaseURL(),
          port: this.port,
          errorMessage: void 0,
        }
      : { status: "stopped", url: void 0, port: void 0, errorMessage: void 0 };
  }
  async handleRequest(e, t, r) {
    if (((this.getServer = r), await this.waitForReady(), !this.enabled)) {
      (t.writeHead(404, { "Content-Type": "application/json" }),
        t.end(
          JSON.stringify({
            message: "Beeper Client API is disabled",
            code: "disabled",
          }),
        ));
      return;
    }
    (await this.loadSharedHTTPServer()).handleRequest(e, t);
  }
  async handleUpgrade(e, t, r, a) {
    if (((this.getServer = a), await this.waitForReady(), !this.enabled)) {
      (t.writable &&
        t.write(`HTTP/1.1 404 Not Found\r
Connection: close\r
\r
`),
        t.destroy());
      return;
    }
    await (await this.loadSharedHTTPServer()).handleUpgrade(e, t, r);
  }
  async dispose() {
    if (
      (this.logger.log("[BeeperConnect] Disposing BeeperConnect"),
      this.sharedHTTPServer)
    ) {
      try {
        await this.sharedHTTPServer.dispose();
      } catch (e) {
        this.logger.error(
          "[BeeperConnect] Error disposing shared HTTP server:",
          e,
        );
      }
      this.sharedHTTPServer = null;
    }
    (await this.auth.dispose(),
      this.logger.log("[BeeperConnect] BeeperConnect disposed"));
  }
}
const jp = Object.freeze(
  Object.defineProperty(
    { __proto__: null, BeeperConnect: fp },
    Symbol.toStringTag,
    { value: "Module" },
  ),
);
export {
  rs as A,
  gt as C,
  qp as D,
  Up as E,
  Op as I,
  kp as O,
  Pp as R,
  Rp as U,
  Np as a,
  Wt as b,
  Kt as c,
  Lp as d,
  Fp as e,
  Mp as f,
  No as g,
  xa as h,
  jp as i,
  Nr as n,
  si as r,
  n as z,
};
//# sourceMappingURL=index-Cq1ckG2i.mjs.map
