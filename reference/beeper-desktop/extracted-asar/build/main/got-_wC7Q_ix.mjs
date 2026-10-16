import { a as cs } from "./_commonjsHelpers-CBUqixCJ.mjs";
import Fe from "url";
import We from "events";
import Ve from "util";
import fe from "stream";
import St from "fs";
import Rt from "http";
import Mr from "https";
import us from "dns";
import fs from "os";
import hs from "buffer";
import ds from "zlib";
import Tt from "http2";
import Nr from "tls";
import zr from "net";
import { rejectUnauthorizedCerts as ls } from "./constants-BL_pdRyX.mjs";
import ms from "node:module";
(function () {
  try {
    var c =
      typeof window < "u"
        ? window
        : typeof global < "u"
          ? global
          : typeof globalThis < "u"
            ? globalThis
            : typeof self < "u"
              ? self
              : {};
    c.SENTRY_RELEASE = { id: "4.3.209" };
    var u = new c.Error().stack;
    u &&
      ((c._sentryDebugIds = c._sentryDebugIds || {}),
      (c._sentryDebugIds[u] = "3335c817-c218-4ad1-9c5d-f9e99a1e4eee"),
      (c._sentryDebugIdIdentifier =
        "sentry-dbid-3335c817-c218-4ad1-9c5d-f9e99a1e4eee"));
  } catch {}
})();
const Rn = import.meta.filename,
  Sn = import.meta.dirname,
  ps = ms.createRequire(import.meta.url);
var ge = { exports: {} },
  oe = {},
  we = { exports: {} },
  $t;
function ne() {
  return (
    $t ||
      (($t = 1),
      (function (c, u) {
        Object.defineProperty(u, "__esModule", { value: !0 });
        const s = [
          "Int8Array",
          "Uint8Array",
          "Uint8ClampedArray",
          "Int16Array",
          "Uint16Array",
          "Int32Array",
          "Uint32Array",
          "Float32Array",
          "Float64Array",
          "BigInt64Array",
          "BigUint64Array",
        ];
        function h(e) {
          return s.includes(e);
        }
        const f = [
          "Function",
          "Generator",
          "AsyncGenerator",
          "GeneratorFunction",
          "AsyncGeneratorFunction",
          "AsyncFunction",
          "Observable",
          "Array",
          "Buffer",
          "Blob",
          "Object",
          "RegExp",
          "Date",
          "Error",
          "Map",
          "Set",
          "WeakMap",
          "WeakSet",
          "ArrayBuffer",
          "SharedArrayBuffer",
          "DataView",
          "Promise",
          "URL",
          "FormData",
          "URLSearchParams",
          "HTMLElement",
          ...s,
        ];
        function i(e) {
          return f.includes(e);
        }
        const n = [
          "null",
          "undefined",
          "string",
          "number",
          "bigint",
          "boolean",
          "symbol",
        ];
        function d(e) {
          return n.includes(e);
        }
        function R(e) {
          return (y) => typeof y === e;
        }
        const { toString: b } = Object.prototype,
          m = (e) => {
            const y = b.call(e).slice(8, -1);
            if (/HTML\w+Element/.test(y) && t.domElement(e))
              return "HTMLElement";
            if (i(y)) return y;
          },
          o = (e) => (y) => m(y) === e;
        function t(e) {
          if (e === null) return "null";
          switch (typeof e) {
            case "undefined":
              return "undefined";
            case "string":
              return "string";
            case "number":
              return "number";
            case "boolean":
              return "boolean";
            case "function":
              return "Function";
            case "bigint":
              return "bigint";
            case "symbol":
              return "symbol";
          }
          if (t.observable(e)) return "Observable";
          if (t.array(e)) return "Array";
          if (t.buffer(e)) return "Buffer";
          const y = m(e);
          if (y) return y;
          if (
            e instanceof String ||
            e instanceof Boolean ||
            e instanceof Number
          )
            throw new TypeError(
              "Please don't use object wrappers for primitive types",
            );
          return "Object";
        }
        ((t.undefined = R("undefined")), (t.string = R("string")));
        const T = R("number");
        ((t.number = (e) => T(e) && !t.nan(e)),
          (t.bigint = R("bigint")),
          (t.function_ = R("function")),
          (t.null_ = (e) => e === null),
          (t.class_ = (e) =>
            t.function_(e) && e.toString().startsWith("class ")),
          (t.boolean = (e) => e === !0 || e === !1),
          (t.symbol = R("symbol")),
          (t.numericString = (e) =>
            t.string(e) &&
            !t.emptyStringOrWhitespace(e) &&
            !Number.isNaN(Number(e))),
          (t.array = (e, y) =>
            Array.isArray(e) ? (t.function_(y) ? e.every(y) : !0) : !1),
          (t.buffer = (e) => {
            var y, x, C, D;
            return (D =
              (C =
                (x =
                  (y = e) === null || y === void 0 ? void 0 : y.constructor) ===
                  null || x === void 0
                  ? void 0
                  : x.isBuffer) === null || C === void 0
                ? void 0
                : C.call(x, e)) !== null && D !== void 0
              ? D
              : !1;
          }),
          (t.blob = (e) => o("Blob")(e)),
          (t.nullOrUndefined = (e) => t.null_(e) || t.undefined(e)),
          (t.object = (e) =>
            !t.null_(e) && (typeof e == "object" || t.function_(e))),
          (t.iterable = (e) => {
            var y;
            return t.function_(
              (y = e) === null || y === void 0 ? void 0 : y[Symbol.iterator],
            );
          }),
          (t.asyncIterable = (e) => {
            var y;
            return t.function_(
              (y = e) === null || y === void 0
                ? void 0
                : y[Symbol.asyncIterator],
            );
          }),
          (t.generator = (e) => {
            var y, x;
            return (
              t.iterable(e) &&
              t.function_((y = e) === null || y === void 0 ? void 0 : y.next) &&
              t.function_((x = e) === null || x === void 0 ? void 0 : x.throw)
            );
          }),
          (t.asyncGenerator = (e) =>
            t.asyncIterable(e) && t.function_(e.next) && t.function_(e.throw)),
          (t.nativePromise = (e) => o("Promise")(e)));
        const a = (e) => {
          var y, x;
          return (
            t.function_((y = e) === null || y === void 0 ? void 0 : y.then) &&
            t.function_((x = e) === null || x === void 0 ? void 0 : x.catch)
          );
        };
        ((t.promise = (e) => t.nativePromise(e) || a(e)),
          (t.generatorFunction = o("GeneratorFunction")),
          (t.asyncGeneratorFunction = (e) => m(e) === "AsyncGeneratorFunction"),
          (t.asyncFunction = (e) => m(e) === "AsyncFunction"),
          (t.boundFunction = (e) =>
            t.function_(e) && !e.hasOwnProperty("prototype")),
          (t.regExp = o("RegExp")),
          (t.date = o("Date")),
          (t.error = o("Error")),
          (t.map = (e) => o("Map")(e)),
          (t.set = (e) => o("Set")(e)),
          (t.weakMap = (e) => o("WeakMap")(e)),
          (t.weakSet = (e) => o("WeakSet")(e)),
          (t.int8Array = o("Int8Array")),
          (t.uint8Array = o("Uint8Array")),
          (t.uint8ClampedArray = o("Uint8ClampedArray")),
          (t.int16Array = o("Int16Array")),
          (t.uint16Array = o("Uint16Array")),
          (t.int32Array = o("Int32Array")),
          (t.uint32Array = o("Uint32Array")),
          (t.float32Array = o("Float32Array")),
          (t.float64Array = o("Float64Array")),
          (t.bigInt64Array = o("BigInt64Array")),
          (t.bigUint64Array = o("BigUint64Array")),
          (t.arrayBuffer = o("ArrayBuffer")),
          (t.sharedArrayBuffer = o("SharedArrayBuffer")),
          (t.dataView = o("DataView")),
          (t.enumCase = (e, y) => Object.values(y).includes(e)),
          (t.directInstanceOf = (e, y) =>
            Object.getPrototypeOf(e) === y.prototype),
          (t.urlInstance = (e) => o("URL")(e)),
          (t.urlString = (e) => {
            if (!t.string(e)) return !1;
            try {
              return (new URL(e), !0);
            } catch {
              return !1;
            }
          }),
          (t.truthy = (e) => !!e),
          (t.falsy = (e) => !e),
          (t.nan = (e) => Number.isNaN(e)),
          (t.primitive = (e) => t.null_(e) || d(typeof e)),
          (t.integer = (e) => Number.isInteger(e)),
          (t.safeInteger = (e) => Number.isSafeInteger(e)),
          (t.plainObject = (e) => {
            if (b.call(e) !== "[object Object]") return !1;
            const y = Object.getPrototypeOf(e);
            return y === null || y === Object.getPrototypeOf({});
          }),
          (t.typedArray = (e) => h(m(e))));
        const O = (e) => t.safeInteger(e) && e >= 0;
        ((t.arrayLike = (e) =>
          !t.nullOrUndefined(e) && !t.function_(e) && O(e.length)),
          (t.inRange = (e, y) => {
            if (t.number(y)) return e >= Math.min(0, y) && e <= Math.max(y, 0);
            if (t.array(y) && y.length === 2)
              return e >= Math.min(...y) && e <= Math.max(...y);
            throw new TypeError(`Invalid range: ${JSON.stringify(y)}`);
          }));
        const P = 1,
          v = [
            "innerHTML",
            "ownerDocument",
            "style",
            "attributes",
            "nodeValue",
          ];
        ((t.domElement = (e) =>
          t.object(e) &&
          e.nodeType === P &&
          t.string(e.nodeName) &&
          !t.plainObject(e) &&
          v.every((y) => y in e)),
          (t.observable = (e) => {
            var y, x, C, D;
            return e
              ? e ===
                  ((x = (y = e)[Symbol.observable]) === null || x === void 0
                    ? void 0
                    : x.call(y)) ||
                  e ===
                    ((D = (C = e)["@@observable"]) === null || D === void 0
                      ? void 0
                      : D.call(C))
              : !1;
          }),
          (t.nodeStream = (e) =>
            t.object(e) && t.function_(e.pipe) && !t.observable(e)),
          (t.infinite = (e) => e === 1 / 0 || e === -1 / 0));
        const w = (e) => (y) => t.integer(y) && Math.abs(y % 2) === e;
        ((t.evenInteger = w(0)),
          (t.oddInteger = w(1)),
          (t.emptyArray = (e) => t.array(e) && e.length === 0),
          (t.nonEmptyArray = (e) => t.array(e) && e.length > 0),
          (t.emptyString = (e) => t.string(e) && e.length === 0));
        const _ = (e) => t.string(e) && !/\S/.test(e);
        ((t.emptyStringOrWhitespace = (e) => t.emptyString(e) || _(e)),
          (t.nonEmptyString = (e) => t.string(e) && e.length > 0),
          (t.nonEmptyStringAndNotWhitespace = (e) =>
            t.string(e) && !t.emptyStringOrWhitespace(e)),
          (t.emptyObject = (e) =>
            t.object(e) &&
            !t.map(e) &&
            !t.set(e) &&
            Object.keys(e).length === 0),
          (t.nonEmptyObject = (e) =>
            t.object(e) && !t.map(e) && !t.set(e) && Object.keys(e).length > 0),
          (t.emptySet = (e) => t.set(e) && e.size === 0),
          (t.nonEmptySet = (e) => t.set(e) && e.size > 0),
          (t.emptyMap = (e) => t.map(e) && e.size === 0),
          (t.nonEmptyMap = (e) => t.map(e) && e.size > 0),
          (t.propertyKey = (e) => t.any([t.string, t.number, t.symbol], e)),
          (t.formData = (e) => o("FormData")(e)),
          (t.urlSearchParams = (e) => o("URLSearchParams")(e)));
        const E = (e, y, x) => {
          if (!t.function_(y))
            throw new TypeError(`Invalid predicate: ${JSON.stringify(y)}`);
          if (x.length === 0) throw new TypeError("Invalid number of values");
          return e.call(x, y);
        };
        ((t.any = (e, ...y) =>
          (t.array(e) ? e : [e]).some((C) => E(Array.prototype.some, C, y))),
          (t.all = (e, ...y) => E(Array.prototype.every, e, y)));
        const l = (e, y, x, C = {}) => {
          if (!e) {
            const { multipleValues: D } = C,
              I = D
                ? `received values of types ${[...new Set(x.map((g) => `\`${t(g)}\``))].join(", ")}`
                : `received value of type \`${t(x)}\``;
            throw new TypeError(`Expected value which is \`${y}\`, ${I}.`);
          }
        };
        ((u.assert = {
          undefined: (e) => l(t.undefined(e), "undefined", e),
          string: (e) => l(t.string(e), "string", e),
          number: (e) => l(t.number(e), "number", e),
          bigint: (e) => l(t.bigint(e), "bigint", e),
          function_: (e) => l(t.function_(e), "Function", e),
          null_: (e) => l(t.null_(e), "null", e),
          class_: (e) => l(t.class_(e), "Class", e),
          boolean: (e) => l(t.boolean(e), "boolean", e),
          symbol: (e) => l(t.symbol(e), "symbol", e),
          numericString: (e) =>
            l(t.numericString(e), "string with a number", e),
          array: (e, y) => {
            (l(t.array(e), "Array", e), y && e.forEach(y));
          },
          buffer: (e) => l(t.buffer(e), "Buffer", e),
          blob: (e) => l(t.blob(e), "Blob", e),
          nullOrUndefined: (e) =>
            l(t.nullOrUndefined(e), "null or undefined", e),
          object: (e) => l(t.object(e), "Object", e),
          iterable: (e) => l(t.iterable(e), "Iterable", e),
          asyncIterable: (e) => l(t.asyncIterable(e), "AsyncIterable", e),
          generator: (e) => l(t.generator(e), "Generator", e),
          asyncGenerator: (e) => l(t.asyncGenerator(e), "AsyncGenerator", e),
          nativePromise: (e) => l(t.nativePromise(e), "native Promise", e),
          promise: (e) => l(t.promise(e), "Promise", e),
          generatorFunction: (e) =>
            l(t.generatorFunction(e), "GeneratorFunction", e),
          asyncGeneratorFunction: (e) =>
            l(t.asyncGeneratorFunction(e), "AsyncGeneratorFunction", e),
          asyncFunction: (e) => l(t.asyncFunction(e), "AsyncFunction", e),
          boundFunction: (e) => l(t.boundFunction(e), "Function", e),
          regExp: (e) => l(t.regExp(e), "RegExp", e),
          date: (e) => l(t.date(e), "Date", e),
          error: (e) => l(t.error(e), "Error", e),
          map: (e) => l(t.map(e), "Map", e),
          set: (e) => l(t.set(e), "Set", e),
          weakMap: (e) => l(t.weakMap(e), "WeakMap", e),
          weakSet: (e) => l(t.weakSet(e), "WeakSet", e),
          int8Array: (e) => l(t.int8Array(e), "Int8Array", e),
          uint8Array: (e) => l(t.uint8Array(e), "Uint8Array", e),
          uint8ClampedArray: (e) =>
            l(t.uint8ClampedArray(e), "Uint8ClampedArray", e),
          int16Array: (e) => l(t.int16Array(e), "Int16Array", e),
          uint16Array: (e) => l(t.uint16Array(e), "Uint16Array", e),
          int32Array: (e) => l(t.int32Array(e), "Int32Array", e),
          uint32Array: (e) => l(t.uint32Array(e), "Uint32Array", e),
          float32Array: (e) => l(t.float32Array(e), "Float32Array", e),
          float64Array: (e) => l(t.float64Array(e), "Float64Array", e),
          bigInt64Array: (e) => l(t.bigInt64Array(e), "BigInt64Array", e),
          bigUint64Array: (e) => l(t.bigUint64Array(e), "BigUint64Array", e),
          arrayBuffer: (e) => l(t.arrayBuffer(e), "ArrayBuffer", e),
          sharedArrayBuffer: (e) =>
            l(t.sharedArrayBuffer(e), "SharedArrayBuffer", e),
          dataView: (e) => l(t.dataView(e), "DataView", e),
          enumCase: (e, y) => l(t.enumCase(e, y), "EnumCase", e),
          urlInstance: (e) => l(t.urlInstance(e), "URL", e),
          urlString: (e) => l(t.urlString(e), "string with a URL", e),
          truthy: (e) => l(t.truthy(e), "truthy", e),
          falsy: (e) => l(t.falsy(e), "falsy", e),
          nan: (e) => l(t.nan(e), "NaN", e),
          primitive: (e) => l(t.primitive(e), "primitive", e),
          integer: (e) => l(t.integer(e), "integer", e),
          safeInteger: (e) => l(t.safeInteger(e), "integer", e),
          plainObject: (e) => l(t.plainObject(e), "plain object", e),
          typedArray: (e) => l(t.typedArray(e), "TypedArray", e),
          arrayLike: (e) => l(t.arrayLike(e), "array-like", e),
          domElement: (e) => l(t.domElement(e), "HTMLElement", e),
          observable: (e) => l(t.observable(e), "Observable", e),
          nodeStream: (e) => l(t.nodeStream(e), "Node.js Stream", e),
          infinite: (e) => l(t.infinite(e), "infinite number", e),
          emptyArray: (e) => l(t.emptyArray(e), "empty array", e),
          nonEmptyArray: (e) => l(t.nonEmptyArray(e), "non-empty array", e),
          emptyString: (e) => l(t.emptyString(e), "empty string", e),
          emptyStringOrWhitespace: (e) =>
            l(t.emptyStringOrWhitespace(e), "empty string or whitespace", e),
          nonEmptyString: (e) => l(t.nonEmptyString(e), "non-empty string", e),
          nonEmptyStringAndNotWhitespace: (e) =>
            l(
              t.nonEmptyStringAndNotWhitespace(e),
              "non-empty string and not whitespace",
              e,
            ),
          emptyObject: (e) => l(t.emptyObject(e), "empty object", e),
          nonEmptyObject: (e) => l(t.nonEmptyObject(e), "non-empty object", e),
          emptySet: (e) => l(t.emptySet(e), "empty set", e),
          nonEmptySet: (e) => l(t.nonEmptySet(e), "non-empty set", e),
          emptyMap: (e) => l(t.emptyMap(e), "empty map", e),
          nonEmptyMap: (e) => l(t.nonEmptyMap(e), "non-empty map", e),
          propertyKey: (e) => l(t.propertyKey(e), "PropertyKey", e),
          formData: (e) => l(t.formData(e), "FormData", e),
          urlSearchParams: (e) => l(t.urlSearchParams(e), "URLSearchParams", e),
          evenInteger: (e) => l(t.evenInteger(e), "even integer", e),
          oddInteger: (e) => l(t.oddInteger(e), "odd integer", e),
          directInstanceOf: (e, y) => l(t.directInstanceOf(e, y), "T", e),
          inRange: (e, y) => l(t.inRange(e, y), "in range", e),
          any: (e, ...y) =>
            l(t.any(e, ...y), "predicate returns truthy for any value", y, {
              multipleValues: !0,
            }),
          all: (e, ...y) =>
            l(t.all(e, ...y), "predicate returns truthy for all values", y, {
              multipleValues: !0,
            }),
        }),
          Object.defineProperties(t, {
            class: { value: t.class_ },
            function: { value: t.function_ },
            null: { value: t.null_ },
          }),
          Object.defineProperties(u.assert, {
            class: { value: u.assert.class_ },
            function: { value: u.assert.function_ },
            null: { value: u.assert.null_ },
          }),
          (u.default = t),
          (c.exports = t),
          (c.exports.default = t),
          (c.exports.assert = u.assert));
      })(we, we.exports)),
    we.exports
  );
}
var ae = {},
  ve = { exports: {} },
  Lt;
function ys() {
  if (Lt) return ve.exports;
  Lt = 1;
  class c extends Error {
    constructor(h) {
      (super(h || "Promise was canceled"), (this.name = "CancelError"));
    }
    get isCanceled() {
      return !0;
    }
  }
  class u {
    static fn(h) {
      return (...f) =>
        new u((i, n, d) => {
          (f.push(d), h(...f).then(i, n));
        });
    }
    constructor(h) {
      ((this._cancelHandlers = []),
        (this._isPending = !0),
        (this._isCanceled = !1),
        (this._rejectOnCancel = !0),
        (this._promise = new Promise((f, i) => {
          this._reject = i;
          const n = (b) => {
              (!this._isCanceled || !R.shouldReject) &&
                ((this._isPending = !1), f(b));
            },
            d = (b) => {
              ((this._isPending = !1), i(b));
            },
            R = (b) => {
              if (!this._isPending)
                throw new Error(
                  "The `onCancel` handler was attached after the promise settled.",
                );
              this._cancelHandlers.push(b);
            };
          return (
            Object.defineProperties(R, {
              shouldReject: {
                get: () => this._rejectOnCancel,
                set: (b) => {
                  this._rejectOnCancel = b;
                },
              },
            }),
            h(n, d, R)
          );
        })));
    }
    then(h, f) {
      return this._promise.then(h, f);
    }
    catch(h) {
      return this._promise.catch(h);
    }
    finally(h) {
      return this._promise.finally(h);
    }
    cancel(h) {
      if (!(!this._isPending || this._isCanceled)) {
        if (((this._isCanceled = !0), this._cancelHandlers.length > 0))
          try {
            for (const f of this._cancelHandlers) f();
          } catch (f) {
            this._reject(f);
            return;
          }
        this._rejectOnCancel && this._reject(new c(h));
      }
    }
    get isCanceled() {
      return this._isCanceled;
    }
  }
  return (
    Object.setPrototypeOf(u.prototype, Promise.prototype),
    (ve.exports = u),
    (ve.exports.CancelError = c),
    ve.exports
  );
}
var ce = {},
  Ke = {},
  Ee = { exports: {} },
  Re = { exports: {} },
  Ut;
function gs() {
  return (
    Ut ||
      ((Ut = 1),
      (function (c, u) {
        Object.defineProperty(u, "__esModule", { value: !0 });
        function s(f) {
          return f.encrypted;
        }
        const h = (f, i) => {
          let n;
          typeof i == "function" ? (n = { connect: i }) : (n = i);
          const d = typeof n.connect == "function",
            R = typeof n.secureConnect == "function",
            b = typeof n.close == "function",
            m = () => {
              (d && n.connect(),
                s(f) &&
                  R &&
                  (f.authorized
                    ? n.secureConnect()
                    : f.authorizationError ||
                      f.once("secureConnect", n.secureConnect)),
                b && f.once("close", n.close));
            };
          f.writable && !f.connecting
            ? m()
            : f.connecting
              ? f.once("connect", m)
              : f.destroyed && b && n.close(f._hadError);
        };
        ((u.default = h), (c.exports = h), (c.exports.default = h));
      })(Re, Re.exports)),
    Re.exports
  );
}
var Dt;
function _s() {
  return (
    Dt ||
      ((Dt = 1),
      (function (c, u) {
        Object.defineProperty(u, "__esModule", { value: !0 });
        const s = gs(),
          h = Ve,
          f = Number(process.versions.node.split(".")[0]),
          i = (n) => {
            if (n.timings) return n.timings;
            const d = {
              start: Date.now(),
              socket: void 0,
              lookup: void 0,
              connect: void 0,
              secureConnect: void 0,
              upload: void 0,
              response: void 0,
              end: void 0,
              error: void 0,
              abort: void 0,
              phases: {
                wait: void 0,
                dns: void 0,
                tcp: void 0,
                tls: void 0,
                request: void 0,
                firstByte: void 0,
                download: void 0,
                total: void 0,
              },
            };
            n.timings = d;
            const R = (T) => {
              const a = T.emit.bind(T);
              T.emit = (O, ...P) => (
                O === "error" &&
                  ((d.error = Date.now()),
                  (d.phases.total = d.error - d.start),
                  (T.emit = a)),
                a(O, ...P)
              );
            };
            R(n);
            const b = () => {
              ((d.abort = Date.now()),
                (!d.response || f >= 13) &&
                  (d.phases.total = Date.now() - d.start));
            };
            n.prependOnceListener("abort", b);
            const m = (T) => {
              if (
                ((d.socket = Date.now()),
                (d.phases.wait = d.socket - d.start),
                h.types.isProxy(T))
              )
                return;
              const a = () => {
                ((d.lookup = Date.now()), (d.phases.dns = d.lookup - d.socket));
              };
              (T.prependOnceListener("lookup", a),
                s.default(T, {
                  connect: () => {
                    ((d.connect = Date.now()),
                      d.lookup === void 0 &&
                        (T.removeListener("lookup", a),
                        (d.lookup = d.connect),
                        (d.phases.dns = d.lookup - d.socket)),
                      (d.phases.tcp = d.connect - d.lookup));
                  },
                  secureConnect: () => {
                    ((d.secureConnect = Date.now()),
                      (d.phases.tls = d.secureConnect - d.connect));
                  },
                }));
            };
            n.socket ? m(n.socket) : n.prependOnceListener("socket", m);
            const o = () => {
              var T;
              ((d.upload = Date.now()),
                (d.phases.request =
                  d.upload -
                  ((T = d.secureConnect) !== null && T !== void 0
                    ? T
                    : d.connect)));
            };
            return (
              (
                typeof n.writableFinished == "boolean"
                  ? n.writableFinished
                  : n.finished &&
                    n.outputSize === 0 &&
                    (!n.socket || n.socket.writableLength === 0)
              )
                ? o()
                : n.prependOnceListener("finish", o),
              n.prependOnceListener("response", (T) => {
                ((d.response = Date.now()),
                  (d.phases.firstByte = d.response - d.upload),
                  (T.timings = d),
                  R(T),
                  T.prependOnceListener("end", () => {
                    ((d.end = Date.now()),
                      (d.phases.download = d.end - d.response),
                      (d.phases.total = d.end - d.start));
                  }),
                  T.prependOnceListener("aborted", b));
              }),
              d
            );
          };
        ((u.default = i), (c.exports = i), (c.exports.default = i));
      })(Ee, Ee.exports)),
    Ee.exports
  );
}
var Se = { exports: {} },
  Mt;
function bs() {
  if (Mt) return Se.exports;
  Mt = 1;
  const {
      V4MAPPED: c,
      ADDRCONFIG: u,
      ALL: s,
      promises: { Resolver: h },
      lookup: f,
    } = us,
    { promisify: i } = Ve,
    n = fs,
    d = Symbol("cacheableLookupCreateConnection"),
    R = Symbol("cacheableLookupInstance"),
    b = Symbol("expires"),
    m = typeof s == "number",
    o = (w) => {
      if (!(w && typeof w.createConnection == "function"))
        throw new Error("Expected an Agent instance as the first argument");
    },
    t = (w) => {
      for (const _ of w)
        _.family !== 6 && ((_.address = `::ffff:${_.address}`), (_.family = 6));
    },
    T = () => {
      let w = !1,
        _ = !1;
      for (const E of Object.values(n.networkInterfaces()))
        for (const l of E)
          if (
            !l.internal &&
            (l.family === "IPv6" ? (_ = !0) : (w = !0), w && _)
          )
            return { has4: w, has6: _ };
      return { has4: w, has6: _ };
    },
    a = (w) => Symbol.iterator in w,
    O = { ttl: !0 },
    P = { all: !0 };
  class v {
    constructor({
      cache: _ = new Map(),
      maxTtl: E = 1 / 0,
      fallbackDuration: l = 3600,
      errorTtl: e = 0.15,
      resolver: y = new h(),
      lookup: x = f,
    } = {}) {
      if (
        ((this.maxTtl = E),
        (this.errorTtl = e),
        (this._cache = _),
        (this._resolver = y),
        (this._dnsLookup = i(x)),
        this._resolver instanceof h
          ? ((this._resolve4 = this._resolver.resolve4.bind(this._resolver)),
            (this._resolve6 = this._resolver.resolve6.bind(this._resolver)))
          : ((this._resolve4 = i(this._resolver.resolve4.bind(this._resolver))),
            (this._resolve6 = i(this._resolver.resolve6.bind(this._resolver)))),
        (this._iface = T()),
        (this._pending = {}),
        (this._nextRemovalTime = !1),
        (this._hostnamesToFallback = new Set()),
        l < 1)
      )
        this._fallback = !1;
      else {
        this._fallback = !0;
        const C = setInterval(() => {
          this._hostnamesToFallback.clear();
        }, l * 1e3);
        C.unref && C.unref();
      }
      ((this.lookup = this.lookup.bind(this)),
        (this.lookupAsync = this.lookupAsync.bind(this)));
    }
    set servers(_) {
      (this.clear(), this._resolver.setServers(_));
    }
    get servers() {
      return this._resolver.getServers();
    }
    lookup(_, E, l) {
      if (
        (typeof E == "function"
          ? ((l = E), (E = {}))
          : typeof E == "number" && (E = { family: E }),
        !l)
      )
        throw new Error("Callback must be a function.");
      this.lookupAsync(_, E).then((e) => {
        E.all ? l(null, e) : l(null, e.address, e.family, e.expires, e.ttl);
      }, l);
    }
    async lookupAsync(_, E = {}) {
      typeof E == "number" && (E = { family: E });
      let l = await this.query(_);
      if (E.family === 6) {
        const e = l.filter((y) => y.family === 6);
        E.hints & c && ((m && E.hints & s) || e.length === 0) ? t(l) : (l = e);
      } else E.family === 4 && (l = l.filter((e) => e.family === 4));
      if (E.hints & u) {
        const { _iface: e } = this;
        l = l.filter((y) => (y.family === 6 ? e.has6 : e.has4));
      }
      if (l.length === 0) {
        const e = new Error(`cacheableLookup ENOTFOUND ${_}`);
        throw ((e.code = "ENOTFOUND"), (e.hostname = _), e);
      }
      return E.all ? l : l[0];
    }
    async query(_) {
      let E = await this._cache.get(_);
      if (!E) {
        const l = this._pending[_];
        if (l) E = await l;
        else {
          const e = this.queryAndCache(_);
          this._pending[_] = e;
          try {
            E = await e;
          } finally {
            delete this._pending[_];
          }
        }
      }
      return ((E = E.map((l) => ({ ...l }))), E);
    }
    async _resolve(_) {
      const E = async (I) => {
          try {
            return await I;
          } catch (g) {
            if (g.code === "ENODATA" || g.code === "ENOTFOUND") return [];
            throw g;
          }
        },
        [l, e] = await Promise.all(
          [this._resolve4(_, O), this._resolve6(_, O)].map((I) => E(I)),
        );
      let y = 0,
        x = 0,
        C = 0;
      const D = Date.now();
      for (const I of l)
        ((I.family = 4),
          (I.expires = D + I.ttl * 1e3),
          (y = Math.max(y, I.ttl)));
      for (const I of e)
        ((I.family = 6),
          (I.expires = D + I.ttl * 1e3),
          (x = Math.max(x, I.ttl)));
      return (
        l.length > 0
          ? e.length > 0
            ? (C = Math.min(y, x))
            : (C = y)
          : (C = x),
        { entries: [...l, ...e], cacheTtl: C }
      );
    }
    async _lookup(_) {
      try {
        return { entries: await this._dnsLookup(_, { all: !0 }), cacheTtl: 0 };
      } catch {
        return { entries: [], cacheTtl: 0 };
      }
    }
    async _set(_, E, l) {
      if (this.maxTtl > 0 && l > 0) {
        ((l = Math.min(l, this.maxTtl) * 1e3), (E[b] = Date.now() + l));
        try {
          await this._cache.set(_, E, l);
        } catch (e) {
          this.lookupAsync = async () => {
            const y = new Error(
              "Cache Error. Please recreate the CacheableLookup instance.",
            );
            throw ((y.cause = e), y);
          };
        }
        a(this._cache) && this._tick(l);
      }
    }
    async queryAndCache(_) {
      if (this._hostnamesToFallback.has(_)) return this._dnsLookup(_, P);
      let E = await this._resolve(_);
      E.entries.length === 0 &&
        this._fallback &&
        ((E = await this._lookup(_)),
        E.entries.length !== 0 && this._hostnamesToFallback.add(_));
      const l = E.entries.length === 0 ? this.errorTtl : E.cacheTtl;
      return (await this._set(_, E.entries, l), E.entries);
    }
    _tick(_) {
      const E = this._nextRemovalTime;
      (!E || _ < E) &&
        (clearTimeout(this._removalTimeout),
        (this._nextRemovalTime = _),
        (this._removalTimeout = setTimeout(() => {
          this._nextRemovalTime = !1;
          let l = 1 / 0;
          const e = Date.now();
          for (const [y, x] of this._cache) {
            const C = x[b];
            e >= C ? this._cache.delete(y) : C < l && (l = C);
          }
          l !== 1 / 0 && this._tick(l - e);
        }, _)),
        this._removalTimeout.unref && this._removalTimeout.unref());
    }
    install(_) {
      if ((o(_), d in _))
        throw new Error("CacheableLookup has been already installed");
      ((_[d] = _.createConnection),
        (_[R] = this),
        (_.createConnection = (E, l) => (
          "lookup" in E || (E.lookup = this.lookup),
          _[d](E, l)
        )));
    }
    uninstall(_) {
      if ((o(_), _[d])) {
        if (_[R] !== this)
          throw new Error(
            "The agent is not owned by this CacheableLookup instance",
          );
        ((_.createConnection = _[d]), delete _[d], delete _[R]);
      }
    }
    updateInterfaceInfo() {
      const { _iface: _ } = this;
      ((this._iface = T()),
        ((_.has4 && !this._iface.has4) || (_.has6 && !this._iface.has6)) &&
          this._cache.clear());
    }
    clear(_) {
      if (_) {
        this._cache.delete(_);
        return;
      }
      this._cache.clear();
    }
  }
  return ((Se.exports = v), (Se.exports.default = v), Se.exports);
}
var Qe, Nt;
function ws() {
  if (Nt) return Qe;
  Nt = 1;
  const c = "text/plain",
    u = "us-ascii",
    s = (i, n) => n.some((d) => (d instanceof RegExp ? d.test(i) : d === i)),
    h = (i, { stripHash: n }) => {
      const d = /^data:(?<type>[^,]*?),(?<data>[^#]*?)(?:#(?<hash>.*))?$/.exec(
        i,
      );
      if (!d) throw new Error(`Invalid URL: ${i}`);
      let { type: R, data: b, hash: m } = d.groups;
      const o = R.split(";");
      m = n ? "" : m;
      let t = !1;
      o[o.length - 1] === "base64" && (o.pop(), (t = !0));
      const T = (o.shift() || "").toLowerCase(),
        O = [
          ...o
            .map((P) => {
              let [v, w = ""] = P.split("=").map((_) => _.trim());
              return v === "charset" && ((w = w.toLowerCase()), w === u)
                ? ""
                : `${v}${w ? `=${w}` : ""}`;
            })
            .filter(Boolean),
        ];
      return (
        t && O.push("base64"),
        (O.length !== 0 || (T && T !== c)) && O.unshift(T),
        `data:${O.join(";")},${t ? b.trim() : b}${m ? `#${m}` : ""}`
      );
    };
  return (
    (Qe = (i, n) => {
      if (
        ((n = {
          defaultProtocol: "http:",
          normalizeProtocol: !0,
          forceHttp: !1,
          forceHttps: !1,
          stripAuthentication: !0,
          stripHash: !1,
          stripTextFragment: !0,
          stripWWW: !0,
          removeQueryParameters: [/^utm_\w+/i],
          removeTrailingSlash: !0,
          removeSingleSlash: !0,
          removeDirectoryIndex: !1,
          sortQueryParameters: !0,
          ...n,
        }),
        (i = i.trim()),
        /^data:/i.test(i))
      )
        return h(i, n);
      if (/^view-source:/i.test(i))
        throw new Error(
          "`view-source:` is not supported as it is a non-standard protocol",
        );
      const d = i.startsWith("//");
      (!d && /^\.*\//.test(i)) ||
        (i = i.replace(/^(?!(?:\w+:)?\/\/)|^\/\//, n.defaultProtocol));
      const b = new URL(i);
      if (n.forceHttp && n.forceHttps)
        throw new Error(
          "The `forceHttp` and `forceHttps` options cannot be used together",
        );
      if (
        (n.forceHttp && b.protocol === "https:" && (b.protocol = "http:"),
        n.forceHttps && b.protocol === "http:" && (b.protocol = "https:"),
        n.stripAuthentication && ((b.username = ""), (b.password = "")),
        n.stripHash
          ? (b.hash = "")
          : n.stripTextFragment &&
            (b.hash = b.hash.replace(/#?:~:text.*?$/i, "")),
        b.pathname &&
          (b.pathname = b.pathname.replace(
            /(?<!\b(?:[a-z][a-z\d+\-.]{1,50}:))\/{2,}/g,
            "/",
          )),
        b.pathname)
      )
        try {
          b.pathname = decodeURI(b.pathname);
        } catch {}
      if (
        (n.removeDirectoryIndex === !0 &&
          (n.removeDirectoryIndex = [/^index\.[a-z]+$/]),
        Array.isArray(n.removeDirectoryIndex) &&
          n.removeDirectoryIndex.length > 0)
      ) {
        let o = b.pathname.split("/");
        const t = o[o.length - 1];
        s(t, n.removeDirectoryIndex) &&
          ((o = o.slice(0, o.length - 1)),
          (b.pathname = o.slice(1).join("/") + "/"));
      }
      if (
        (b.hostname &&
          ((b.hostname = b.hostname.replace(/\.$/, "")),
          n.stripWWW &&
            /^www\.(?!www\.)(?:[a-z\-\d]{1,63})\.(?:[a-z.\-\d]{2,63})$/.test(
              b.hostname,
            ) &&
            (b.hostname = b.hostname.replace(/^www\./, ""))),
        Array.isArray(n.removeQueryParameters))
      )
        for (const o of [...b.searchParams.keys()])
          s(o, n.removeQueryParameters) && b.searchParams.delete(o);
      (n.removeQueryParameters === !0 && (b.search = ""),
        n.sortQueryParameters && b.searchParams.sort(),
        n.removeTrailingSlash && (b.pathname = b.pathname.replace(/\/$/, "")));
      const m = i;
      return (
        (i = b.toString()),
        !n.removeSingleSlash &&
          b.pathname === "/" &&
          !m.endsWith("/") &&
          b.hash === "" &&
          (i = i.replace(/\/$/, "")),
        (n.removeTrailingSlash || b.pathname === "/") &&
          b.hash === "" &&
          n.removeSingleSlash &&
          (i = i.replace(/\/$/, "")),
        d && !n.normalizeProtocol && (i = i.replace(/^http:\/\//, "//")),
        n.stripProtocol && (i = i.replace(/^(?:https?:)?\/\//, "")),
        i
      );
    }),
    Qe
  );
}
var ue = { exports: {} },
  Te = { exports: {} },
  Ye,
  zt;
function vs() {
  if (zt) return Ye;
  ((zt = 1), (Ye = c));
  function c(u, s) {
    if (u && s) return c(u)(s);
    if (typeof u != "function") throw new TypeError("need wrapper function");
    return (
      Object.keys(u).forEach(function (f) {
        h[f] = u[f];
      }),
      h
    );
    function h() {
      for (var f = new Array(arguments.length), i = 0; i < f.length; i++)
        f[i] = arguments[i];
      var n = u.apply(this, f),
        d = f[f.length - 1];
      return (
        typeof n == "function" &&
          n !== d &&
          Object.keys(d).forEach(function (R) {
            n[R] = d[R];
          }),
        n
      );
    }
  }
  return Ye;
}
var Bt;
function Br() {
  if (Bt) return Te.exports;
  Bt = 1;
  var c = vs();
  ((Te.exports = c(u)),
    (Te.exports.strict = c(s)),
    (u.proto = u(function () {
      (Object.defineProperty(Function.prototype, "once", {
        value: function () {
          return u(this);
        },
        configurable: !0,
      }),
        Object.defineProperty(Function.prototype, "onceStrict", {
          value: function () {
            return s(this);
          },
          configurable: !0,
        }));
    })));
  function u(h) {
    var f = function () {
      return f.called
        ? f.value
        : ((f.called = !0), (f.value = h.apply(this, arguments)));
    };
    return ((f.called = !1), f);
  }
  function s(h) {
    var f = function () {
        if (f.called) throw new Error(f.onceError);
        return ((f.called = !0), (f.value = h.apply(this, arguments)));
      },
      i = h.name || "Function wrapped with `once`";
    return (
      (f.onceError = i + " shouldn't be called more than once"),
      (f.called = !1),
      f
    );
  }
  return Te.exports;
}
var Xe, Ft;
function Es() {
  if (Ft) return Xe;
  Ft = 1;
  var c = Br(),
    u = function () {},
    s = function (i) {
      return i.setHeader && typeof i.abort == "function";
    },
    h = function (i) {
      return i.stdio && Array.isArray(i.stdio) && i.stdio.length === 3;
    },
    f = function (i, n, d) {
      if (typeof n == "function") return f(i, null, n);
      (n || (n = {}), (d = c(d || u)));
      var R = i._writableState,
        b = i._readableState,
        m = n.readable || (n.readable !== !1 && i.readable),
        o = n.writable || (n.writable !== !1 && i.writable),
        t = !1,
        T = function () {
          i.writable || a();
        },
        a = function () {
          ((o = !1), m || d.call(i));
        },
        O = function () {
          ((m = !1), o || d.call(i));
        },
        P = function (l) {
          d.call(i, l ? new Error("exited with error code: " + l) : null);
        },
        v = function (l) {
          d.call(i, l);
        },
        w = function () {
          process.nextTick(_);
        },
        _ = function () {
          if (!t) {
            if (m && !(b && b.ended && !b.destroyed))
              return d.call(i, new Error("premature close"));
            if (o && !(R && R.ended && !R.destroyed))
              return d.call(i, new Error("premature close"));
          }
        },
        E = function () {
          i.req.on("finish", a);
        };
      return (
        s(i)
          ? (i.on("complete", a),
            i.on("abort", w),
            i.req ? E() : i.on("request", E))
          : o && !R && (i.on("end", T), i.on("close", T)),
        h(i) && i.on("exit", P),
        i.on("end", O),
        i.on("finish", a),
        n.error !== !1 && i.on("error", v),
        i.on("close", w),
        function () {
          ((t = !0),
            i.removeListener("complete", a),
            i.removeListener("abort", w),
            i.removeListener("request", E),
            i.req && i.req.removeListener("finish", a),
            i.removeListener("end", T),
            i.removeListener("close", T),
            i.removeListener("finish", a),
            i.removeListener("exit", P),
            i.removeListener("end", O),
            i.removeListener("error", v),
            i.removeListener("close", w));
        }
      );
    };
  return ((Xe = f), Xe);
}
var Ze, Wt;
function Rs() {
  if (Wt) return Ze;
  Wt = 1;
  var c = Br(),
    u = Es(),
    s = St,
    h = function () {},
    f = /^v?\.0/.test(process.version),
    i = function (t) {
      return typeof t == "function";
    },
    n = function (t) {
      return !f || !s
        ? !1
        : (t instanceof (s.ReadStream || h) ||
            t instanceof (s.WriteStream || h)) &&
            i(t.close);
    },
    d = function (t) {
      return t.setHeader && i(t.abort);
    },
    R = function (t, T, a, O) {
      O = c(O);
      var P = !1;
      (t.on("close", function () {
        P = !0;
      }),
        u(t, { readable: T, writable: a }, function (w) {
          if (w) return O(w);
          ((P = !0), O());
        }));
      var v = !1;
      return function (w) {
        if (!P && !v) {
          if (((v = !0), n(t))) return t.close(h);
          if (d(t)) return t.abort();
          if (i(t.destroy)) return t.destroy();
          O(w || new Error("stream was destroyed"));
        }
      };
    },
    b = function (t) {
      t();
    },
    m = function (t, T) {
      return t.pipe(T);
    },
    o = function () {
      var t = Array.prototype.slice.call(arguments),
        T = (i(t[t.length - 1] || h) && t.pop()) || h;
      if ((Array.isArray(t[0]) && (t = t[0]), t.length < 2))
        throw new Error("pump requires two streams per minimum");
      var a,
        O = t.map(function (P, v) {
          var w = v < t.length - 1,
            _ = v > 0;
          return R(P, w, _, function (E) {
            (a || (a = E), E && O.forEach(b), !w && (O.forEach(b), T(a)));
          });
        });
      return t.reduce(m);
    };
  return ((Ze = o), Ze);
}
var et, Vt;
function Ss() {
  if (Vt) return et;
  Vt = 1;
  const { PassThrough: c } = fe;
  return (
    (et = (u) => {
      u = { ...u };
      const { array: s } = u;
      let { encoding: h } = u;
      const f = h === "buffer";
      let i = !1;
      (s ? (i = !(h || f)) : (h = h || "utf8"), f && (h = null));
      const n = new c({ objectMode: i });
      h && n.setEncoding(h);
      let d = 0;
      const R = [];
      return (
        n.on("data", (b) => {
          (R.push(b), i ? (d = R.length) : (d += b.length));
        }),
        (n.getBufferedValue = () =>
          s ? R : f ? Buffer.concat(R, d) : R.join("")),
        (n.getBufferedLength = () => d),
        n
      );
    }),
    et
  );
}
var Gt;
function Ts() {
  if (Gt) return ue.exports;
  Gt = 1;
  const { constants: c } = hs,
    u = Rs(),
    s = Ss();
  class h extends Error {
    constructor() {
      (super("maxBuffer exceeded"), (this.name = "MaxBufferError"));
    }
  }
  async function f(i, n) {
    if (!i) return Promise.reject(new Error("Expected a stream"));
    n = { maxBuffer: 1 / 0, ...n };
    const { maxBuffer: d } = n;
    let R;
    return (
      await new Promise((b, m) => {
        const o = (t) => {
          (t &&
            R.getBufferedLength() <= c.MAX_LENGTH &&
            (t.bufferedData = R.getBufferedValue()),
            m(t));
        };
        ((R = u(i, s(n), (t) => {
          if (t) {
            o(t);
            return;
          }
          b();
        })),
          R.on("data", () => {
            R.getBufferedLength() > d && o(new h());
          }));
      }),
      R.getBufferedValue()
    );
  }
  return (
    (ue.exports = f),
    (ue.exports.default = f),
    (ue.exports.buffer = (i, n) => f(i, { ...n, encoding: "buffer" })),
    (ue.exports.array = (i, n) => f(i, { ...n, array: !0 })),
    (ue.exports.MaxBufferError = h),
    ue.exports
  );
}
var tt, Jt;
function Ps() {
  if (Jt) return tt;
  Jt = 1;
  const c = new Set([
      200, 203, 204, 206, 300, 301, 308, 404, 405, 410, 414, 501,
    ]),
    u = new Set([
      200, 203, 204, 300, 301, 302, 303, 307, 308, 404, 405, 410, 414, 501,
    ]),
    s = new Set([500, 502, 503, 504]),
    h = {
      date: !0,
      connection: !0,
      "keep-alive": !0,
      "proxy-authenticate": !0,
      "proxy-authorization": !0,
      te: !0,
      trailer: !0,
      "transfer-encoding": !0,
      upgrade: !0,
    },
    f = {
      "content-length": !0,
      "content-encoding": !0,
      "transfer-encoding": !0,
      "content-range": !0,
    };
  function i(b) {
    const m = parseInt(b, 10);
    return isFinite(m) ? m : 0;
  }
  function n(b) {
    return b ? s.has(b.status) : !0;
  }
  function d(b) {
    const m = {};
    if (!b) return m;
    const o = b.trim().split(/,/);
    for (const t of o) {
      const [T, a] = t.split(/=/, 2);
      m[T.trim()] = a === void 0 ? !0 : a.trim().replace(/^"|"$/g, "");
    }
    return m;
  }
  function R(b) {
    let m = [];
    for (const o in b) {
      const t = b[o];
      m.push(t === !0 ? o : o + "=" + t);
    }
    if (m.length) return m.join(", ");
  }
  return (
    (tt = class {
      constructor(
        m,
        o,
        {
          shared: t,
          cacheHeuristic: T,
          immutableMinTimeToLive: a,
          ignoreCargoCult: O,
          _fromObject: P,
        } = {},
      ) {
        if (P) {
          this._fromObject(P);
          return;
        }
        if (!o || !o.headers) throw Error("Response headers missing");
        (this._assertRequestHasHeaders(m),
          (this._responseTime = this.now()),
          (this._isShared = t !== !1),
          (this._cacheHeuristic = T !== void 0 ? T : 0.1),
          (this._immutableMinTtl = a !== void 0 ? a : 24 * 3600 * 1e3),
          (this._status = "status" in o ? o.status : 200),
          (this._resHeaders = o.headers),
          (this._rescc = d(o.headers["cache-control"])),
          (this._method = "method" in m ? m.method : "GET"),
          (this._url = m.url),
          (this._host = m.headers.host),
          (this._noAuthorization = !m.headers.authorization),
          (this._reqHeaders = o.headers.vary ? m.headers : null),
          (this._reqcc = d(m.headers["cache-control"])),
          O &&
            "pre-check" in this._rescc &&
            "post-check" in this._rescc &&
            (delete this._rescc["pre-check"],
            delete this._rescc["post-check"],
            delete this._rescc["no-cache"],
            delete this._rescc["no-store"],
            delete this._rescc["must-revalidate"],
            (this._resHeaders = Object.assign({}, this._resHeaders, {
              "cache-control": R(this._rescc),
            })),
            delete this._resHeaders.expires,
            delete this._resHeaders.pragma),
          o.headers["cache-control"] == null &&
            /no-cache/.test(o.headers.pragma) &&
            (this._rescc["no-cache"] = !0));
      }
      now() {
        return Date.now();
      }
      storable() {
        return !!(
          !this._reqcc["no-store"] &&
          (this._method === "GET" ||
            this._method === "HEAD" ||
            (this._method === "POST" && this._hasExplicitExpiration())) &&
          u.has(this._status) &&
          !this._rescc["no-store"] &&
          (!this._isShared || !this._rescc.private) &&
          (!this._isShared ||
            this._noAuthorization ||
            this._allowsStoringAuthenticated()) &&
          (this._resHeaders.expires ||
            this._rescc["max-age"] ||
            (this._isShared && this._rescc["s-maxage"]) ||
            this._rescc.public ||
            c.has(this._status))
        );
      }
      _hasExplicitExpiration() {
        return (
          (this._isShared && this._rescc["s-maxage"]) ||
          this._rescc["max-age"] ||
          this._resHeaders.expires
        );
      }
      _assertRequestHasHeaders(m) {
        if (!m || !m.headers) throw Error("Request headers missing");
      }
      satisfiesWithoutRevalidation(m) {
        this._assertRequestHasHeaders(m);
        const o = d(m.headers["cache-control"]);
        return o["no-cache"] ||
          /no-cache/.test(m.headers.pragma) ||
          (o["max-age"] && this.age() > o["max-age"]) ||
          (o["min-fresh"] && this.timeToLive() < 1e3 * o["min-fresh"]) ||
          (this.stale() &&
            !(
              o["max-stale"] &&
              !this._rescc["must-revalidate"] &&
              (o["max-stale"] === !0 ||
                o["max-stale"] > this.age() - this.maxAge())
            ))
          ? !1
          : this._requestMatches(m, !1);
      }
      _requestMatches(m, o) {
        return (
          (!this._url || this._url === m.url) &&
          this._host === m.headers.host &&
          (!m.method ||
            this._method === m.method ||
            (o && m.method === "HEAD")) &&
          this._varyMatches(m)
        );
      }
      _allowsStoringAuthenticated() {
        return (
          this._rescc["must-revalidate"] ||
          this._rescc.public ||
          this._rescc["s-maxage"]
        );
      }
      _varyMatches(m) {
        if (!this._resHeaders.vary) return !0;
        if (this._resHeaders.vary === "*") return !1;
        const o = this._resHeaders.vary
          .trim()
          .toLowerCase()
          .split(/\s*,\s*/);
        for (const t of o) if (m.headers[t] !== this._reqHeaders[t]) return !1;
        return !0;
      }
      _copyWithoutHopByHopHeaders(m) {
        const o = {};
        for (const t in m) h[t] || (o[t] = m[t]);
        if (m.connection) {
          const t = m.connection.trim().split(/\s*,\s*/);
          for (const T of t) delete o[T];
        }
        if (o.warning) {
          const t = o.warning
            .split(/,/)
            .filter((T) => !/^\s*1[0-9][0-9]/.test(T));
          t.length ? (o.warning = t.join(",").trim()) : delete o.warning;
        }
        return o;
      }
      responseHeaders() {
        const m = this._copyWithoutHopByHopHeaders(this._resHeaders),
          o = this.age();
        return (
          o > 3600 * 24 &&
            !this._hasExplicitExpiration() &&
            this.maxAge() > 3600 * 24 &&
            (m.warning =
              (m.warning ? `${m.warning}, ` : "") + '113 - "rfc7234 5.5.4"'),
          (m.age = `${Math.round(o)}`),
          (m.date = new Date(this.now()).toUTCString()),
          m
        );
      }
      date() {
        const m = Date.parse(this._resHeaders.date);
        return isFinite(m) ? m : this._responseTime;
      }
      age() {
        let m = this._ageValue();
        const o = (this.now() - this._responseTime) / 1e3;
        return m + o;
      }
      _ageValue() {
        return i(this._resHeaders.age);
      }
      maxAge() {
        if (
          !this.storable() ||
          this._rescc["no-cache"] ||
          (this._isShared &&
            this._resHeaders["set-cookie"] &&
            !this._rescc.public &&
            !this._rescc.immutable) ||
          this._resHeaders.vary === "*"
        )
          return 0;
        if (this._isShared) {
          if (this._rescc["proxy-revalidate"]) return 0;
          if (this._rescc["s-maxage"]) return i(this._rescc["s-maxage"]);
        }
        if (this._rescc["max-age"]) return i(this._rescc["max-age"]);
        const m = this._rescc.immutable ? this._immutableMinTtl : 0,
          o = this.date();
        if (this._resHeaders.expires) {
          const t = Date.parse(this._resHeaders.expires);
          return Number.isNaN(t) || t < o ? 0 : Math.max(m, (t - o) / 1e3);
        }
        if (this._resHeaders["last-modified"]) {
          const t = Date.parse(this._resHeaders["last-modified"]);
          if (isFinite(t) && o > t)
            return Math.max(m, ((o - t) / 1e3) * this._cacheHeuristic);
        }
        return m;
      }
      timeToLive() {
        const m = this.maxAge() - this.age(),
          o = m + i(this._rescc["stale-if-error"]),
          t = m + i(this._rescc["stale-while-revalidate"]);
        return Math.max(0, m, o, t) * 1e3;
      }
      stale() {
        return this.maxAge() <= this.age();
      }
      _useStaleIfError() {
        return this.maxAge() + i(this._rescc["stale-if-error"]) > this.age();
      }
      useStaleWhileRevalidate() {
        return (
          this.maxAge() + i(this._rescc["stale-while-revalidate"]) > this.age()
        );
      }
      static fromObject(m) {
        return new this(void 0, void 0, { _fromObject: m });
      }
      _fromObject(m) {
        if (this._responseTime) throw Error("Reinitialized");
        if (!m || m.v !== 1) throw Error("Invalid serialization");
        ((this._responseTime = m.t),
          (this._isShared = m.sh),
          (this._cacheHeuristic = m.ch),
          (this._immutableMinTtl = m.imm !== void 0 ? m.imm : 24 * 3600 * 1e3),
          (this._status = m.st),
          (this._resHeaders = m.resh),
          (this._rescc = m.rescc),
          (this._method = m.m),
          (this._url = m.u),
          (this._host = m.h),
          (this._noAuthorization = m.a),
          (this._reqHeaders = m.reqh),
          (this._reqcc = m.reqcc));
      }
      toObject() {
        return {
          v: 1,
          t: this._responseTime,
          sh: this._isShared,
          ch: this._cacheHeuristic,
          imm: this._immutableMinTtl,
          st: this._status,
          resh: this._resHeaders,
          rescc: this._rescc,
          m: this._method,
          u: this._url,
          h: this._host,
          a: this._noAuthorization,
          reqh: this._reqHeaders,
          reqcc: this._reqcc,
        };
      }
      revalidationHeaders(m) {
        this._assertRequestHasHeaders(m);
        const o = this._copyWithoutHopByHopHeaders(m.headers);
        if (
          (delete o["if-range"],
          !this._requestMatches(m, !0) || !this.storable())
        )
          return (delete o["if-none-match"], delete o["if-modified-since"], o);
        if (
          (this._resHeaders.etag &&
            (o["if-none-match"] = o["if-none-match"]
              ? `${o["if-none-match"]}, ${this._resHeaders.etag}`
              : this._resHeaders.etag),
          o["accept-ranges"] ||
            o["if-match"] ||
            o["if-unmodified-since"] ||
            (this._method && this._method != "GET"))
        ) {
          if ((delete o["if-modified-since"], o["if-none-match"])) {
            const T = o["if-none-match"]
              .split(/,/)
              .filter((a) => !/^\s*W\//.test(a));
            T.length
              ? (o["if-none-match"] = T.join(",").trim())
              : delete o["if-none-match"];
          }
        } else
          this._resHeaders["last-modified"] &&
            !o["if-modified-since"] &&
            (o["if-modified-since"] = this._resHeaders["last-modified"]);
        return o;
      }
      revalidatedPolicy(m, o) {
        if ((this._assertRequestHasHeaders(m), this._useStaleIfError() && n(o)))
          return { modified: !1, matches: !1, policy: this };
        if (!o || !o.headers) throw Error("Response headers missing");
        let t = !1;
        if (
          (o.status !== void 0 && o.status != 304
            ? (t = !1)
            : o.headers.etag && !/^\s*W\//.test(o.headers.etag)
              ? (t =
                  this._resHeaders.etag &&
                  this._resHeaders.etag.replace(/^\s*W\//, "") ===
                    o.headers.etag)
              : this._resHeaders.etag && o.headers.etag
                ? (t =
                    this._resHeaders.etag.replace(/^\s*W\//, "") ===
                    o.headers.etag.replace(/^\s*W\//, ""))
                : this._resHeaders["last-modified"]
                  ? (t =
                      this._resHeaders["last-modified"] ===
                      o.headers["last-modified"])
                  : !this._resHeaders.etag &&
                    !this._resHeaders["last-modified"] &&
                    !o.headers.etag &&
                    !o.headers["last-modified"] &&
                    (t = !0),
          !t)
        )
          return {
            policy: new this.constructor(m, o),
            modified: o.status != 304,
            matches: !1,
          };
        const T = {};
        for (const O in this._resHeaders)
          T[O] = O in o.headers && !f[O] ? o.headers[O] : this._resHeaders[O];
        const a = Object.assign({}, o, {
          status: this._status,
          method: this._method,
          headers: T,
        });
        return {
          policy: new this.constructor(m, a, {
            shared: this._isShared,
            cacheHeuristic: this._cacheHeuristic,
            immutableMinTimeToLive: this._immutableMinTtl,
          }),
          modified: !1,
          matches: !0,
        };
      }
    }),
    tt
  );
}
var rt, Kt;
function Pt() {
  return (
    Kt ||
      ((Kt = 1),
      (rt = (c) => {
        const u = {};
        for (const [s, h] of Object.entries(c)) u[s.toLowerCase()] = h;
        return u;
      })),
    rt
  );
}
var st, Qt;
function Cs() {
  if (Qt) return st;
  Qt = 1;
  const c = fe.Readable,
    u = Pt();
  class s extends c {
    constructor(f, i, n, d) {
      if (typeof f != "number")
        throw new TypeError("Argument `statusCode` should be a number");
      if (typeof i != "object")
        throw new TypeError("Argument `headers` should be an object");
      if (!(n instanceof Buffer))
        throw new TypeError("Argument `body` should be a buffer");
      if (typeof d != "string")
        throw new TypeError("Argument `url` should be a string");
      (super(),
        (this.statusCode = f),
        (this.headers = u(i)),
        (this.body = n),
        (this.url = d));
    }
    _read() {
      (this.push(this.body), this.push(null));
    }
  }
  return ((st = s), st);
}
var nt, Yt;
function ks() {
  if (Yt) return nt;
  Yt = 1;
  const c = [
    "destroy",
    "setTimeout",
    "socket",
    "headers",
    "trailers",
    "rawHeaders",
    "statusCode",
    "httpVersion",
    "httpVersionMinor",
    "httpVersionMajor",
    "rawTrailers",
    "statusMessage",
  ];
  return (
    (nt = (u, s) => {
      const h = new Set(Object.keys(u).concat(c));
      for (const f of h)
        f in s || (s[f] = typeof u[f] == "function" ? u[f].bind(u) : u[f]);
    }),
    nt
  );
}
var it, Xt;
function As() {
  if (Xt) return it;
  Xt = 1;
  const c = fe.PassThrough,
    u = ks();
  return (
    (it = (h) => {
      if (!(h && h.pipe))
        throw new TypeError("Parameter `response` must be a response stream.");
      const f = new c();
      return (u(h, f), h.pipe(f));
    }),
    it
  );
}
var Pe = {},
  Zt;
function Os() {
  return (
    Zt ||
      ((Zt = 1),
      (Pe.stringify = function c(u) {
        if (typeof u > "u") return u;
        if (u && Buffer.isBuffer(u))
          return JSON.stringify(":base64:" + u.toString("base64"));
        if ((u && u.toJSON && (u = u.toJSON()), u && typeof u == "object")) {
          var s = "",
            h = Array.isArray(u);
          s = h ? "[" : "{";
          var f = !0;
          for (var i in u) {
            var n = typeof u[i] == "function" || (!h && typeof u[i] > "u");
            Object.hasOwnProperty.call(u, i) &&
              !n &&
              (f || (s += ","),
              (f = !1),
              h
                ? u[i] == null
                  ? (s += "null")
                  : (s += c(u[i]))
                : u[i] !== void 0 && (s += c(i) + ":" + c(u[i])));
          }
          return ((s += h ? "]" : "}"), s);
        } else
          return typeof u == "string"
            ? JSON.stringify(/^:/.test(u) ? ":" + u : u)
            : typeof u > "u"
              ? "null"
              : JSON.stringify(u);
      }),
      (Pe.parse = function (c) {
        return JSON.parse(c, function (u, s) {
          return typeof s == "string"
            ? /^:base64:/.test(s)
              ? Buffer.from(s.substring(8), "base64")
              : /^:/.test(s)
                ? s.substring(1)
                : s
            : s;
        });
      })),
    Pe
  );
}
var ot, er;
function xs() {
  if (er) return ot;
  er = 1;
  const c = We,
    u = Os(),
    s = (i) => {
      const n = {
        redis: "@keyv/redis",
        rediss: "@keyv/redis",
        mongodb: "@keyv/mongo",
        mongo: "@keyv/mongo",
        sqlite: "@keyv/sqlite",
        postgresql: "@keyv/postgres",
        postgres: "@keyv/postgres",
        mysql: "@keyv/mysql",
        etcd: "@keyv/etcd",
        offline: "@keyv/offline",
        tiered: "@keyv/tiered",
      };
      if (i.adapter || i.uri) {
        const d = i.adapter || /^[^:+]*/.exec(i.uri)[0];
        return new (ps(n[d]))(i);
      }
      return new Map();
    },
    h = ["sqlite", "postgres", "mysql", "mongo", "redis", "tiered"];
  class f extends c {
    constructor(n, { emitErrors: d = !0, ...R } = {}) {
      if (
        (super(),
        (this.opts = {
          namespace: "keyv",
          serialize: u.stringify,
          deserialize: u.parse,
          ...(typeof n == "string" ? { uri: n } : n),
          ...R,
        }),
        !this.opts.store)
      ) {
        const m = { ...this.opts };
        this.opts.store = s(m);
      }
      if (this.opts.compression) {
        const m = this.opts.compression;
        ((this.opts.serialize = m.serialize.bind(m)),
          (this.opts.deserialize = m.deserialize.bind(m)));
      }
      (typeof this.opts.store.on == "function" &&
        d &&
        this.opts.store.on("error", (m) => this.emit("error", m)),
        (this.opts.store.namespace = this.opts.namespace));
      const b = (m) =>
        async function* () {
          for await (const [o, t] of typeof m == "function"
            ? m(this.opts.store.namespace)
            : m) {
            const T = await this.opts.deserialize(t);
            if (!(
              this.opts.store.namespace &&
              !o.includes(this.opts.store.namespace)
            )) {
              if (typeof T.expires == "number" && Date.now() > T.expires) {
                this.delete(o);
                continue;
              }
              yield [this._getKeyUnprefix(o), T.value];
            }
          }
        };
      typeof this.opts.store[Symbol.iterator] == "function" &&
      this.opts.store instanceof Map
        ? (this.iterator = b(this.opts.store))
        : typeof this.opts.store.iterator == "function" &&
          this.opts.store.opts &&
          this._checkIterableAdaptar() &&
          (this.iterator = b(this.opts.store.iterator.bind(this.opts.store)));
    }
    _checkIterableAdaptar() {
      return (
        h.includes(this.opts.store.opts.dialect) ||
        h.findIndex((n) => this.opts.store.opts.url.includes(n)) >= 0
      );
    }
    _getKeyPrefix(n) {
      return `${this.opts.namespace}:${n}`;
    }
    _getKeyPrefixArray(n) {
      return n.map((d) => `${this.opts.namespace}:${d}`);
    }
    _getKeyUnprefix(n) {
      return n.split(":").splice(1).join(":");
    }
    get(n, d) {
      const { store: R } = this.opts,
        b = Array.isArray(n),
        m = b ? this._getKeyPrefixArray(n) : this._getKeyPrefix(n);
      if (b && R.getMany === void 0) {
        const o = [];
        for (const t of m)
          o.push(
            Promise.resolve()
              .then(() => R.get(t))
              .then((T) =>
                typeof T == "string"
                  ? this.opts.deserialize(T)
                  : this.opts.compression
                    ? this.opts.deserialize(T)
                    : T,
              )
              .then((T) => {
                if (T != null)
                  return typeof T.expires == "number" && Date.now() > T.expires
                    ? this.delete(t).then(() => {})
                    : d && d.raw
                      ? T
                      : T.value;
              }),
          );
        return Promise.allSettled(o).then((t) => {
          const T = [];
          for (const a of t) T.push(a.value);
          return T;
        });
      }
      return Promise.resolve()
        .then(() => (b ? R.getMany(m) : R.get(m)))
        .then((o) =>
          typeof o == "string"
            ? this.opts.deserialize(o)
            : this.opts.compression
              ? this.opts.deserialize(o)
              : o,
        )
        .then((o) => {
          if (o != null)
            return b
              ? o.map((t, T) => {
                  if (
                    (typeof t == "string" && (t = this.opts.deserialize(t)),
                    t != null)
                  ) {
                    if (
                      typeof t.expires == "number" &&
                      Date.now() > t.expires
                    ) {
                      this.delete(n[T]).then(() => {});
                      return;
                    }
                    return d && d.raw ? t : t.value;
                  }
                })
              : typeof o.expires == "number" && Date.now() > o.expires
                ? this.delete(n).then(() => {})
                : d && d.raw
                  ? o
                  : o.value;
        });
    }
    set(n, d, R) {
      const b = this._getKeyPrefix(n);
      (typeof R > "u" && (R = this.opts.ttl), R === 0 && (R = void 0));
      const { store: m } = this.opts;
      return Promise.resolve()
        .then(() => {
          const o = typeof R == "number" ? Date.now() + R : null;
          return (
            typeof d == "symbol" &&
              this.emit("error", "symbol cannot be serialized"),
            (d = { value: d, expires: o }),
            this.opts.serialize(d)
          );
        })
        .then((o) => m.set(b, o, R))
        .then(() => !0);
    }
    delete(n) {
      const { store: d } = this.opts;
      if (Array.isArray(n)) {
        const b = this._getKeyPrefixArray(n);
        if (d.deleteMany === void 0) {
          const m = [];
          for (const o of b) m.push(d.delete(o));
          return Promise.allSettled(m).then((o) =>
            o.every((t) => t.value === !0),
          );
        }
        return Promise.resolve().then(() => d.deleteMany(b));
      }
      const R = this._getKeyPrefix(n);
      return Promise.resolve().then(() => d.delete(R));
    }
    clear() {
      const { store: n } = this.opts;
      return Promise.resolve().then(() => n.clear());
    }
    has(n) {
      const d = this._getKeyPrefix(n),
        { store: R } = this.opts;
      return Promise.resolve().then(async () =>
        typeof R.has == "function" ? R.has(d) : (await R.get(d)) !== void 0,
      );
    }
    disconnect() {
      const { store: n } = this.opts;
      if (typeof n.disconnect == "function") return n.disconnect();
    }
  }
  return ((ot = f), ot);
}
var at, tr;
function qs() {
  if (tr) return at;
  tr = 1;
  const c = We,
    u = Fe,
    s = ws(),
    h = Ts(),
    f = Ps(),
    i = Cs(),
    n = Pt(),
    d = As(),
    R = xs();
  class b {
    constructor(T, a) {
      if (typeof T != "function")
        throw new TypeError("Parameter `request` must be a function");
      return (
        (this.cache = new R({
          uri: typeof a == "string" && a,
          store: typeof a != "string" && a,
          namespace: "cacheable-request",
        })),
        this.createCacheableRequest(T)
      );
    }
    createCacheableRequest(T) {
      return (a, O) => {
        let P;
        if (typeof a == "string") ((P = o(u.parse(a))), (a = {}));
        else if (a instanceof u.URL) ((P = o(u.parse(a.toString()))), (a = {}));
        else {
          const [y, ...x] = (a.path || "").split("?"),
            C = x.length > 0 ? `?${x.join("?")}` : "";
          P = o({ ...a, pathname: y, search: C });
        }
        ((a = {
          headers: {},
          method: "GET",
          cache: !0,
          strictTtl: !1,
          automaticFailover: !1,
          ...a,
          ...m(P),
        }),
          (a.headers = n(a.headers)));
        const v = new c(),
          w = s(u.format(P), {
            stripWWW: !1,
            removeTrailingSlash: !1,
            stripAuthentication: !1,
          }),
          _ = `${a.method}:${w}`;
        let E = !1,
          l = !1;
        const e = (y) => {
          l = !0;
          let x = !1,
            C;
          const D = new Promise((g) => {
              C = () => {
                x || ((x = !0), g());
              };
            }),
            I = (g) => {
              if (E && !y.forceRefresh) {
                g.status = g.statusCode;
                const q = f.fromObject(E.cachePolicy).revalidatedPolicy(y, g);
                if (!q.modified) {
                  const z = q.policy.responseHeaders();
                  ((g = new i(E.statusCode, z, E.body, E.url)),
                    (g.cachePolicy = q.policy),
                    (g.fromCache = !0));
                }
              }
              g.fromCache ||
                ((g.cachePolicy = new f(y, g, y)), (g.fromCache = !1));
              let S;
              (y.cache && g.cachePolicy.storable()
                ? ((S = d(g)),
                  (async () => {
                    try {
                      const q = h.buffer(g);
                      if (
                        (await Promise.race([
                          D,
                          new Promise((F) => g.once("end", F)),
                        ]),
                        x)
                      )
                        return;
                      const z = await q,
                        M = {
                          cachePolicy: g.cachePolicy.toObject(),
                          url: g.url,
                          statusCode: g.fromCache ? E.statusCode : g.statusCode,
                          body: z,
                        };
                      let $ = y.strictTtl ? g.cachePolicy.timeToLive() : void 0;
                      (y.maxTtl && ($ = $ ? Math.min($, y.maxTtl) : y.maxTtl),
                        await this.cache.set(_, M, $));
                    } catch (q) {
                      v.emit("error", new b.CacheError(q));
                    }
                  })())
                : y.cache &&
                  E &&
                  (async () => {
                    try {
                      await this.cache.delete(_);
                    } catch (q) {
                      v.emit("error", new b.CacheError(q));
                    }
                  })(),
                v.emit("response", S || g),
                typeof O == "function" && O(S || g));
            };
          try {
            const g = T(y, I);
            (g.once("error", C), g.once("abort", C), v.emit("request", g));
          } catch (g) {
            v.emit("error", new b.RequestError(g));
          }
        };
        return (
          (async () => {
            const y = async (C) => {
                await Promise.resolve();
                const D = C.cache ? await this.cache.get(_) : void 0;
                if (typeof D > "u") return e(C);
                const I = f.fromObject(D.cachePolicy);
                if (I.satisfiesWithoutRevalidation(C) && !C.forceRefresh) {
                  const g = I.responseHeaders(),
                    S = new i(D.statusCode, g, D.body, D.url);
                  ((S.cachePolicy = I),
                    (S.fromCache = !0),
                    v.emit("response", S),
                    typeof O == "function" && O(S));
                } else ((E = D), (C.headers = I.revalidationHeaders(C)), e(C));
              },
              x = (C) => v.emit("error", new b.CacheError(C));
            (this.cache.once("error", x),
              v.on("response", () => this.cache.removeListener("error", x)));
            try {
              await y(a);
            } catch (C) {
              (a.automaticFailover && !l && e(a),
                v.emit("error", new b.CacheError(C)));
            }
          })(),
          v
        );
      };
    }
  }
  function m(t) {
    const T = { ...t };
    return (
      (T.path = `${t.pathname || "/"}${t.search || ""}`),
      delete T.pathname,
      delete T.search,
      T
    );
  }
  function o(t) {
    return {
      protocol: t.protocol,
      auth: t.auth,
      hostname: t.hostname || t.host || "localhost",
      port: t.port,
      pathname: t.pathname,
      search: t.search,
    };
  }
  return (
    (b.RequestError = class extends Error {
      constructor(t) {
        (super(t.message),
          (this.name = "RequestError"),
          Object.assign(this, t));
      }
    }),
    (b.CacheError = class extends Error {
      constructor(t) {
        (super(t.message), (this.name = "CacheError"), Object.assign(this, t));
      }
    }),
    (at = b),
    at
  );
}
var ct, rr;
function js() {
  if (rr) return ct;
  rr = 1;
  const c = [
    "aborted",
    "complete",
    "headers",
    "httpVersion",
    "httpVersionMinor",
    "httpVersionMajor",
    "method",
    "rawHeaders",
    "rawTrailers",
    "setTimeout",
    "socket",
    "statusCode",
    "statusMessage",
    "trailers",
    "url",
  ];
  return (
    (ct = (u, s) => {
      if (s._readableState.autoDestroy)
        throw new Error(
          "The second stream must have the `autoDestroy` option set to `false`",
        );
      const h = new Set(Object.keys(u).concat(c)),
        f = {};
      for (const i of h)
        i in s ||
          (f[i] = {
            get() {
              const n = u[i];
              return typeof n == "function" ? n.bind(u) : n;
            },
            set(n) {
              u[i] = n;
            },
            enumerable: !0,
            configurable: !1,
          });
      return (
        Object.defineProperties(s, f),
        u.once("aborted", () => {
          (s.destroy(), s.emit("aborted"));
        }),
        u.once("close", () => {
          u.complete && s.readable
            ? s.once("end", () => {
                s.emit("close");
              })
            : s.emit("close");
        }),
        s
      );
    }),
    ct
  );
}
var ut, sr;
function Hs() {
  if (sr) return ut;
  sr = 1;
  const { Transform: c, PassThrough: u } = fe,
    s = ds,
    h = js();
  return (
    (ut = (f) => {
      const i = (f.headers["content-encoding"] || "").toLowerCase();
      if (!["gzip", "deflate", "br"].includes(i)) return f;
      const n = i === "br";
      if (n && typeof s.createBrotliDecompress != "function")
        return (
          f.destroy(new Error("Brotli is not supported on Node.js < 12")),
          f
        );
      let d = !0;
      const R = new c({
          transform(o, t, T) {
            ((d = !1), T(null, o));
          },
          flush(o) {
            o();
          },
        }),
        b = new u({
          autoDestroy: !1,
          destroy(o, t) {
            (f.destroy(), t(o));
          },
        }),
        m = n ? s.createBrotliDecompress() : s.createUnzip();
      return (
        m.once("error", (o) => {
          if (d && !f.readable) {
            b.end();
            return;
          }
          b.destroy(o);
        }),
        h(f, b),
        f.pipe(R).pipe(m).pipe(b),
        b
      );
    }),
    ut
  );
}
var ft, nr;
function Fr() {
  if (nr) return ft;
  nr = 1;
  class c {
    constructor(s = {}) {
      if (!(s.maxSize && s.maxSize > 0))
        throw new TypeError("`maxSize` must be a number greater than 0");
      ((this.maxSize = s.maxSize),
        (this.onEviction = s.onEviction),
        (this.cache = new Map()),
        (this.oldCache = new Map()),
        (this._size = 0));
    }
    _set(s, h) {
      if ((this.cache.set(s, h), this._size++, this._size >= this.maxSize)) {
        if (((this._size = 0), typeof this.onEviction == "function"))
          for (const [f, i] of this.oldCache.entries()) this.onEviction(f, i);
        ((this.oldCache = this.cache), (this.cache = new Map()));
      }
    }
    get(s) {
      if (this.cache.has(s)) return this.cache.get(s);
      if (this.oldCache.has(s)) {
        const h = this.oldCache.get(s);
        return (this.oldCache.delete(s), this._set(s, h), h);
      }
    }
    set(s, h) {
      return (this.cache.has(s) ? this.cache.set(s, h) : this._set(s, h), this);
    }
    has(s) {
      return this.cache.has(s) || this.oldCache.has(s);
    }
    peek(s) {
      if (this.cache.has(s)) return this.cache.get(s);
      if (this.oldCache.has(s)) return this.oldCache.get(s);
    }
    delete(s) {
      const h = this.cache.delete(s);
      return (h && this._size--, this.oldCache.delete(s) || h);
    }
    clear() {
      (this.cache.clear(), this.oldCache.clear(), (this._size = 0));
    }
    *keys() {
      for (const [s] of this) yield s;
    }
    *values() {
      for (const [, s] of this) yield s;
    }
    *[Symbol.iterator]() {
      for (const s of this.cache) yield s;
      for (const s of this.oldCache) {
        const [h] = s;
        this.cache.has(h) || (yield s);
      }
    }
    get size() {
      let s = 0;
      for (const h of this.oldCache.keys()) this.cache.has(h) || s++;
      return Math.min(this._size + s, this.maxSize);
    }
  }
  return ((ft = c), ft);
}
var ht, ir;
function Wr() {
  if (ir) return ht;
  ir = 1;
  const c = We,
    u = Nr,
    s = Tt,
    h = Fr(),
    f = Symbol("currentStreamsCount"),
    i = Symbol("request"),
    n = Symbol("cachedOriginSet"),
    d = Symbol("gracefullyClosing"),
    R = [
      "maxDeflateDynamicTableSize",
      "maxSessionMemory",
      "maxHeaderListPairs",
      "maxOutstandingPings",
      "maxReservedRemoteStreams",
      "maxSendHeaderBlockLength",
      "paddingStrategy",
      "localAddress",
      "path",
      "rejectUnauthorized",
      "minDHSize",
      "ca",
      "cert",
      "clientCertEngine",
      "ciphers",
      "key",
      "pfx",
      "servername",
      "minVersion",
      "maxVersion",
      "secureProtocol",
      "crl",
      "honorCipherOrder",
      "ecdhCurve",
      "dhparam",
      "secureOptions",
      "sessionIdContext",
    ],
    b = (P, v, w) => {
      let _ = 0,
        E = P.length;
      for (; _ < E;) {
        const l = (_ + E) >>> 1;
        w(P[l], v) ? (_ = l + 1) : (E = l);
      }
      return _;
    },
    m = (P, v) =>
      P.remoteSettings.maxConcurrentStreams >
      v.remoteSettings.maxConcurrentStreams,
    o = (P, v) => {
      for (const w of P)
        w[n].length < v[n].length &&
          w[n].every((_) => v[n].includes(_)) &&
          w[f] + v[f] <= v.remoteSettings.maxConcurrentStreams &&
          a(w);
    },
    t = (P, v) => {
      for (const w of P)
        v[n].length < w[n].length &&
          v[n].every((_) => w[n].includes(_)) &&
          v[f] + w[f] <= w.remoteSettings.maxConcurrentStreams &&
          a(v);
    },
    T = ({ agent: P, isFree: v }) => {
      const w = {};
      for (const _ in P.sessions) {
        const l = P.sessions[_].filter((e) => {
          const y =
            e[O.kCurrentStreamsCount] < e.remoteSettings.maxConcurrentStreams;
          return v ? y : !y;
        });
        l.length !== 0 && (w[_] = l);
      }
      return w;
    },
    a = (P) => {
      ((P[d] = !0), P[f] === 0 && P.close());
    };
  class O extends c {
    constructor({
      timeout: v = 6e4,
      maxSessions: w = 1 / 0,
      maxFreeSessions: _ = 10,
      maxCachedTlsSessions: E = 100,
    } = {}) {
      (super(),
        (this.sessions = {}),
        (this.queue = {}),
        (this.timeout = v),
        (this.maxSessions = w),
        (this.maxFreeSessions = _),
        (this._freeSessionsCount = 0),
        (this._sessionsCount = 0),
        (this.settings = { enablePush: !1 }),
        (this.tlsSessionCache = new h({ maxSize: E })));
    }
    static normalizeOrigin(v, w) {
      return (
        typeof v == "string" && (v = new URL(v)),
        w && v.hostname !== w && (v.hostname = w),
        v.origin
      );
    }
    normalizeOptions(v) {
      let w = "";
      if (v) for (const _ of R) v[_] && (w += `:${v[_]}`);
      return w;
    }
    _tryToCreateNewSession(v, w) {
      if (!(v in this.queue) || !(w in this.queue[v])) return;
      const _ = this.queue[v][w];
      this._sessionsCount < this.maxSessions &&
        !_.completed &&
        ((_.completed = !0), _());
    }
    getSession(v, w, _) {
      return new Promise((E, l) => {
        Array.isArray(_)
          ? ((_ = [..._]), E())
          : (_ = [{ resolve: E, reject: l }]);
        const e = this.normalizeOptions(w),
          y = O.normalizeOrigin(v, w && w.servername);
        if (y === void 0) {
          for (const { reject: D } of _)
            D(
              new TypeError(
                "The `origin` argument needs to be a string or an URL object",
              ),
            );
          return;
        }
        if (e in this.sessions) {
          const D = this.sessions[e];
          let I = -1,
            g = -1,
            S;
          for (const q of D) {
            const z = q.remoteSettings.maxConcurrentStreams;
            if (z < I) break;
            if (q[n].includes(y)) {
              const M = q[f];
              if (M >= z || q[d] || q.destroyed) continue;
              (S || (I = z), M > g && ((S = q), (g = M)));
            }
          }
          if (S) {
            if (_.length !== 1) {
              for (const { reject: q } of _) {
                const z =
                  new Error(`Expected the length of listeners to be 1, got ${_.length}.
Please report this to https://github.com/szmarczak/http2-wrapper/`);
                q(z);
              }
              return;
            }
            _[0].resolve(S);
            return;
          }
        }
        if (e in this.queue) {
          if (y in this.queue[e]) {
            (this.queue[e][y].listeners.push(..._),
              this._tryToCreateNewSession(e, y));
            return;
          }
        } else this.queue[e] = {};
        const x = () => {
            e in this.queue &&
              this.queue[e][y] === C &&
              (delete this.queue[e][y],
              Object.keys(this.queue[e]).length === 0 && delete this.queue[e]);
          },
          C = () => {
            const D = `${y}:${e}`;
            let I = !1;
            try {
              const g = s.connect(v, {
                createConnection: this.createConnection,
                settings: this.settings,
                session: this.tlsSessionCache.get(D),
                ...w,
              });
              ((g[f] = 0), (g[d] = !1));
              const S = () => g[f] < g.remoteSettings.maxConcurrentStreams;
              let q = !0;
              (g.socket.once("session", (M) => {
                this.tlsSessionCache.set(D, M);
              }),
                g.once("error", (M) => {
                  for (const { reject: $ } of _) $(M);
                  this.tlsSessionCache.delete(D);
                }),
                g.setTimeout(this.timeout, () => {
                  g.destroy();
                }),
                g.once("close", () => {
                  if (I) {
                    (q && this._freeSessionsCount--, this._sessionsCount--);
                    const M = this.sessions[e];
                    (M.splice(M.indexOf(g), 1),
                      M.length === 0 && delete this.sessions[e]);
                  } else {
                    const M = new Error(
                      "Session closed without receiving a SETTINGS frame",
                    );
                    M.code = "HTTP2WRAPPER_NOSETTINGS";
                    for (const { reject: $ } of _) $(M);
                    x();
                  }
                  this._tryToCreateNewSession(e, y);
                }));
              const z = () => {
                if (!(!(e in this.queue) || !S())) {
                  for (const M of g[n])
                    if (M in this.queue[e]) {
                      const { listeners: $ } = this.queue[e][M];
                      for (; $.length !== 0 && S();) $.shift().resolve(g);
                      const F = this.queue[e];
                      if (
                        F[M].listeners.length === 0 &&
                        (delete F[M], Object.keys(F).length === 0)
                      ) {
                        delete this.queue[e];
                        break;
                      }
                      if (!S()) break;
                    }
                }
              };
              (g.on("origin", () => {
                ((g[n] = g.originSet), S() && (z(), o(this.sessions[e], g)));
              }),
                g.once("remoteSettings", () => {
                  if (
                    (g.ref(), g.unref(), this._sessionsCount++, C.destroyed)
                  ) {
                    const M = new Error("Agent has been destroyed");
                    for (const $ of _) $.reject(M);
                    g.destroy();
                    return;
                  }
                  g[n] = g.originSet;
                  {
                    const M = this.sessions;
                    if (e in M) {
                      const $ = M[e];
                      $.splice(b($, g, m), 0, g);
                    } else M[e] = [g];
                  }
                  ((this._freeSessionsCount += 1),
                    (I = !0),
                    this.emit("session", g),
                    z(),
                    x(),
                    g[f] === 0 &&
                      this._freeSessionsCount > this.maxFreeSessions &&
                      g.close(),
                    _.length !== 0 &&
                      (this.getSession(y, w, _), (_.length = 0)),
                    g.on("remoteSettings", () => {
                      (z(), o(this.sessions[e], g));
                    }));
                }),
                (g[i] = g.request),
                (g.request = (M, $) => {
                  if (g[d])
                    throw new Error(
                      "The session is gracefully closing. No new streams are allowed.",
                    );
                  const F = g[i](M, $);
                  return (
                    g.ref(),
                    ++g[f],
                    g[f] === g.remoteSettings.maxConcurrentStreams &&
                      this._freeSessionsCount--,
                    F.once("close", () => {
                      if (
                        ((q = S()),
                        --g[f],
                        !g.destroyed &&
                          !g.closed &&
                          (t(this.sessions[e], g), S() && !g.closed))
                      ) {
                        q || (this._freeSessionsCount++, (q = !0));
                        const ee = g[f] === 0;
                        (ee && g.unref(),
                          ee &&
                          (this._freeSessionsCount > this.maxFreeSessions ||
                            g[d])
                            ? g.close()
                            : (o(this.sessions[e], g), z()));
                      }
                    }),
                    F
                  );
                }));
            } catch (g) {
              for (const S of _) S.reject(g);
              x();
            }
          };
        ((C.listeners = _),
          (C.completed = !1),
          (C.destroyed = !1),
          (this.queue[e][y] = C),
          this._tryToCreateNewSession(e, y));
      });
    }
    request(v, w, _, E) {
      return new Promise((l, e) => {
        this.getSession(v, w, [
          {
            reject: e,
            resolve: (y) => {
              try {
                l(y.request(_, E));
              } catch (x) {
                e(x);
              }
            },
          },
        ]);
      });
    }
    createConnection(v, w) {
      return O.connect(v, w);
    }
    static connect(v, w) {
      w.ALPNProtocols = ["h2"];
      const _ = v.port || 443,
        E = v.hostname || v.host;
      return (
        typeof w.servername > "u" && (w.servername = E),
        u.connect(_, E, w)
      );
    }
    closeFreeSessions() {
      for (const v of Object.values(this.sessions))
        for (const w of v) w[f] === 0 && w.close();
    }
    destroy(v) {
      for (const w of Object.values(this.sessions))
        for (const _ of w) _.destroy(v);
      for (const w of Object.values(this.queue))
        for (const _ of Object.values(w)) _.destroyed = !0;
      this.queue = {};
    }
    get freeSessions() {
      return T({ agent: this, isFree: !0 });
    }
    get busySessions() {
      return T({ agent: this, isFree: !1 });
    }
  }
  return (
    (O.kCurrentStreamsCount = f),
    (O.kGracefullyClosing = d),
    (ht = { Agent: O, globalAgent: new O() }),
    ht
  );
}
var dt, or;
function Vr() {
  if (or) return dt;
  or = 1;
  const { Readable: c } = fe;
  class u extends c {
    constructor(h, f) {
      (super({ highWaterMark: f, autoDestroy: !1 }),
        (this.statusCode = null),
        (this.statusMessage = ""),
        (this.httpVersion = "2.0"),
        (this.httpVersionMajor = 2),
        (this.httpVersionMinor = 0),
        (this.headers = {}),
        (this.trailers = {}),
        (this.req = null),
        (this.aborted = !1),
        (this.complete = !1),
        (this.upgrade = null),
        (this.rawHeaders = []),
        (this.rawTrailers = []),
        (this.socket = h),
        (this.connection = h),
        (this._dumped = !1));
    }
    _destroy(h) {
      this.req._request.destroy(h);
    }
    setTimeout(h, f) {
      return (this.req.setTimeout(h, f), this);
    }
    _dump() {
      this._dumped ||
        ((this._dumped = !0), this.removeAllListeners("data"), this.resume());
    }
    _read() {
      this.req && this.req._request.resume();
    }
  }
  return ((dt = u), dt);
}
var lt, ar;
function Gr() {
  return (
    ar ||
      ((ar = 1),
      (lt = (c) => {
        const u = {
          protocol: c.protocol,
          hostname:
            typeof c.hostname == "string" && c.hostname.startsWith("[")
              ? c.hostname.slice(1, -1)
              : c.hostname,
          host: c.host,
          hash: c.hash,
          search: c.search,
          pathname: c.pathname,
          href: c.href,
          path: `${c.pathname || ""}${c.search || ""}`,
        };
        return (
          typeof c.port == "string" &&
            c.port.length !== 0 &&
            (u.port = Number(c.port)),
          (c.username || c.password) &&
            (u.auth = `${c.username || ""}:${c.password || ""}`),
          u
        );
      })),
    lt
  );
}
var mt, cr;
function Is() {
  return (
    cr ||
      ((cr = 1),
      (mt = (c, u, s) => {
        for (const h of s) c.on(h, (...f) => u.emit(h, ...f));
      })),
    mt
  );
}
var pt, ur;
function $s() {
  return (
    ur ||
      ((ur = 1),
      (pt = (c) => {
        switch (c) {
          case ":method":
          case ":scheme":
          case ":authority":
          case ":path":
            return !0;
          default:
            return !1;
        }
      })),
    pt
  );
}
var yt = { exports: {} },
  fr;
function Ls() {
  return (
    fr ||
      ((fr = 1),
      (function (c) {
        const u = (s, h, f) => {
          c.exports[h] = class extends s {
            constructor(...n) {
              (super(typeof f == "string" ? f : f(n)),
                (this.name = `${super.name} [${h}]`),
                (this.code = h));
            }
          };
        };
        (u(TypeError, "ERR_INVALID_ARG_TYPE", (s) => {
          const h = s[0].includes(".") ? "property" : "argument";
          let f = s[1];
          const i = Array.isArray(f);
          return (
            i && (f = `${f.slice(0, -1).join(", ")} or ${f.slice(-1)}`),
            `The "${s[0]}" ${h} must be ${i ? "one of" : "of"} type ${f}. Received ${typeof s[2]}`
          );
        }),
          u(
            TypeError,
            "ERR_INVALID_PROTOCOL",
            (s) => `Protocol "${s[0]}" not supported. Expected "${s[1]}"`,
          ),
          u(
            Error,
            "ERR_HTTP_HEADERS_SENT",
            (s) => `Cannot ${s[0]} headers after they are sent to the client`,
          ),
          u(
            TypeError,
            "ERR_INVALID_HTTP_TOKEN",
            (s) => `${s[0]} must be a valid HTTP token [${s[1]}]`,
          ),
          u(
            TypeError,
            "ERR_HTTP_INVALID_HEADER_VALUE",
            (s) => `Invalid value "${s[0]} for header "${s[1]}"`,
          ),
          u(
            TypeError,
            "ERR_INVALID_CHAR",
            (s) => `Invalid character in ${s[0]} [${s[1]}]`,
          ));
      })(yt)),
    yt.exports
  );
}
var gt, hr;
function Jr() {
  if (hr) return gt;
  hr = 1;
  const c = Tt,
    { Writable: u } = fe,
    { Agent: s, globalAgent: h } = Wr(),
    f = Vr(),
    i = Gr(),
    n = Is(),
    d = $s(),
    {
      ERR_INVALID_ARG_TYPE: R,
      ERR_INVALID_PROTOCOL: b,
      ERR_HTTP_HEADERS_SENT: m,
      ERR_INVALID_HTTP_TOKEN: o,
      ERR_HTTP_INVALID_HEADER_VALUE: t,
      ERR_INVALID_CHAR: T,
    } = Ls(),
    {
      HTTP2_HEADER_STATUS: a,
      HTTP2_HEADER_METHOD: O,
      HTTP2_HEADER_PATH: P,
      HTTP2_METHOD_CONNECT: v,
    } = c.constants,
    w = Symbol("headers"),
    _ = Symbol("origin"),
    E = Symbol("session"),
    l = Symbol("options"),
    e = Symbol("flushedHeaders"),
    y = Symbol("jobs"),
    x = /^[\^`\-\w!#$%&*+.|~]+$/,
    C = /[^\t\u0020-\u007E\u0080-\u00FF]/;
  class D extends u {
    constructor(g, S, q) {
      super({ autoDestroy: !1 });
      const z = typeof g == "string" || g instanceof URL;
      if (
        (z && (g = i(g instanceof URL ? g : new URL(g))),
        typeof S == "function" || S === void 0
          ? ((q = S), (S = z ? g : { ...g }))
          : (S = { ...g, ...S }),
        S.h2session)
      )
        this[E] = S.h2session;
      else if (S.agent === !1) this.agent = new s({ maxFreeSessions: 0 });
      else if (typeof S.agent > "u" || S.agent === null)
        typeof S.createConnection == "function"
          ? ((this.agent = new s({ maxFreeSessions: 0 })),
            (this.agent.createConnection = S.createConnection))
          : (this.agent = h);
      else if (typeof S.agent.request == "function") this.agent = S.agent;
      else
        throw new R(
          "options.agent",
          ["Agent-like Object", "undefined", "false"],
          S.agent,
        );
      if (S.protocol && S.protocol !== "https:")
        throw new b(S.protocol, "https:");
      const M =
          S.port ||
          S.defaultPort ||
          (this.agent && this.agent.defaultPort) ||
          443,
        $ = S.hostname || S.host || "localhost";
      (delete S.hostname, delete S.host, delete S.port);
      const { timeout: F } = S;
      if (
        ((S.timeout = void 0),
        (this[w] = Object.create(null)),
        (this[y] = []),
        (this.socket = null),
        (this.connection = null),
        (this.method = S.method || "GET"),
        (this.path = S.path),
        (this.res = null),
        (this.aborted = !1),
        (this.reusedSocket = !1),
        S.headers)
      )
        for (const [ee, G] of Object.entries(S.headers)) this.setHeader(ee, G);
      (S.auth &&
        !("authorization" in this[w]) &&
        (this[w].authorization =
          "Basic " + Buffer.from(S.auth).toString("base64")),
        (S.session = S.tlsSession),
        (S.path = S.socketPath),
        (this[l] = S),
        M === 443
          ? ((this[_] = `https://${$}`),
            ":authority" in this[w] || (this[w][":authority"] = $))
          : ((this[_] = `https://${$}:${M}`),
            ":authority" in this[w] || (this[w][":authority"] = `${$}:${M}`)),
        F && this.setTimeout(F),
        q && this.once("response", q),
        (this[e] = !1));
    }
    get method() {
      return this[w][O];
    }
    set method(g) {
      g && (this[w][O] = g.toUpperCase());
    }
    get path() {
      return this[w][P];
    }
    set path(g) {
      g && (this[w][P] = g);
    }
    get _mustNotHaveABody() {
      return (
        this.method === "GET" ||
        this.method === "HEAD" ||
        this.method === "DELETE"
      );
    }
    _write(g, S, q) {
      if (this._mustNotHaveABody) {
        q(new Error("The GET, HEAD and DELETE methods must NOT have a body"));
        return;
      }
      this.flushHeaders();
      const z = () => this._request.write(g, S, q);
      this._request ? z() : this[y].push(z);
    }
    _final(g) {
      if (this.destroyed) return;
      this.flushHeaders();
      const S = () => {
        if (this._mustNotHaveABody) {
          g();
          return;
        }
        this._request.end(g);
      };
      this._request ? S() : this[y].push(S);
    }
    abort() {
      (this.res && this.res.complete) ||
        (this.aborted || process.nextTick(() => this.emit("abort")),
        (this.aborted = !0),
        this.destroy());
    }
    _destroy(g, S) {
      (this.res && this.res._dump(),
        this._request && this._request.destroy(),
        S(g));
    }
    async flushHeaders() {
      if (this[e] || this.destroyed) return;
      this[e] = !0;
      const g = this.method === v,
        S = (q) => {
          if (((this._request = q), this.destroyed)) {
            q.destroy();
            return;
          }
          g || n(q, this, ["timeout", "continue", "close", "error"]);
          const z =
            ($) =>
            (...F) => {
              !this.writable && !this.destroyed
                ? $(...F)
                : this.once("finish", () => {
                    $(...F);
                  });
            };
          (q.once(
            "response",
            z(($, F, ee) => {
              const G = new f(this.socket, q.readableHighWaterMark);
              ((this.res = G),
                (G.req = this),
                (G.statusCode = $[a]),
                (G.headers = $),
                (G.rawHeaders = ee),
                G.once("end", () => {
                  this.aborted
                    ? ((G.aborted = !0), G.emit("aborted"))
                    : ((G.complete = !0),
                      (G.socket = null),
                      (G.connection = null));
                }),
                g
                  ? ((G.upgrade = !0),
                    this.emit("connect", G, q, Buffer.alloc(0))
                      ? this.emit("close")
                      : q.destroy())
                  : (q.on("data", (te) => {
                      !G._dumped && !G.push(te) && q.pause();
                    }),
                    q.once("end", () => {
                      G.push(null);
                    }),
                    this.emit("response", G) || G._dump()));
            }),
          ),
            q.once(
              "headers",
              z(($) => this.emit("information", { statusCode: $[a] })),
            ),
            q.once(
              "trailers",
              z(($, F, ee) => {
                const { res: G } = this;
                ((G.trailers = $), (G.rawTrailers = ee));
              }),
            ));
          const { socket: M } = q.session;
          ((this.socket = M), (this.connection = M));
          for (const $ of this[y]) $();
          this.emit("socket", this.socket);
        };
      if (this[E])
        try {
          S(this[E].request(this[w]));
        } catch (q) {
          this.emit("error", q);
        }
      else {
        this.reusedSocket = !0;
        try {
          S(await this.agent.request(this[_], this[l], this[w]));
        } catch (q) {
          this.emit("error", q);
        }
      }
    }
    getHeader(g) {
      if (typeof g != "string") throw new R("name", "string", g);
      return this[w][g.toLowerCase()];
    }
    get headersSent() {
      return this[e];
    }
    removeHeader(g) {
      if (typeof g != "string") throw new R("name", "string", g);
      if (this.headersSent) throw new m("remove");
      delete this[w][g.toLowerCase()];
    }
    setHeader(g, S) {
      if (this.headersSent) throw new m("set");
      if (typeof g != "string" || (!x.test(g) && !d(g)))
        throw new o("Header name", g);
      if (typeof S > "u") throw new t(S, g);
      if (C.test(S)) throw new T("header content", g);
      this[w][g.toLowerCase()] = S;
    }
    setNoDelay() {}
    setSocketKeepAlive() {}
    setTimeout(g, S) {
      const q = () => this._request.setTimeout(g, S);
      return (this._request ? q() : this[y].push(q), this);
    }
    get maxHeadersCount() {
      if (!this.destroyed && this._request)
        return this._request.session.localSettings.maxHeaderListSize;
    }
    set maxHeadersCount(g) {}
  }
  return ((gt = D), gt);
}
var Ce = { exports: {} },
  _t,
  dr;
function Us() {
  if (dr) return _t;
  dr = 1;
  const c = Nr;
  return (
    (_t = (u = {}, s = c.connect) =>
      new Promise((h, f) => {
        let i = !1,
          n;
        const d = async () => {
            (await b,
              n.off("timeout", R),
              n.off("error", f),
              u.resolveSocket
                ? (h({ alpnProtocol: n.alpnProtocol, socket: n, timeout: i }),
                  i && (await Promise.resolve(), n.emit("timeout")))
                : (n.destroy(),
                  h({ alpnProtocol: n.alpnProtocol, timeout: i })));
          },
          R = async () => {
            ((i = !0), d());
          },
          b = (async () => {
            try {
              ((n = await s(u, d)), n.on("error", f), n.once("timeout", R));
            } catch (m) {
              f(m);
            }
          })();
      })),
    _t
  );
}
var bt, lr;
function Ds() {
  if (lr) return bt;
  lr = 1;
  const c = zr;
  return (
    (bt = (u) => {
      let s = u.host;
      const h = u.headers && u.headers.host;
      return (
        h &&
          (h.startsWith("[")
            ? h.indexOf("]") === -1
              ? (s = h)
              : (s = h.slice(1, -1))
            : (s = h.split(":", 1)[0])),
        c.isIP(s) ? "" : s
      );
    }),
    bt
  );
}
var mr;
function Ms() {
  if (mr) return Ce.exports;
  mr = 1;
  const c = Rt,
    u = Mr,
    s = Us(),
    h = Fr(),
    f = Jr(),
    i = Ds(),
    n = Gr(),
    d = new h({ maxSize: 100 }),
    R = new Map(),
    b = (o, t, T) => {
      t._httpMessage = { shouldKeepAlive: !0 };
      const a = () => {
        o.emit("free", t, T);
      };
      t.on("free", a);
      const O = () => {
        o.removeSocket(t, T);
      };
      t.on("close", O);
      const P = () => {
        (o.removeSocket(t, T),
          t.off("close", O),
          t.off("free", a),
          t.off("agentRemove", P));
      };
      (t.on("agentRemove", P), o.emit("free", t, T));
    },
    m = async (o) => {
      const t = `${o.host}:${o.port}:${o.ALPNProtocols.sort()}`;
      if (!d.has(t)) {
        if (R.has(t)) return (await R.get(t)).alpnProtocol;
        const { path: T, agent: a } = o;
        o.path = o.socketPath;
        const O = s(o);
        R.set(t, O);
        try {
          const { socket: P, alpnProtocol: v } = await O;
          if ((d.set(t, v), (o.path = T), v === "h2")) P.destroy();
          else {
            const { globalAgent: w } = u,
              _ = u.Agent.prototype.createConnection;
            a
              ? a.createConnection === _
                ? b(a, P, o)
                : P.destroy()
              : w.createConnection === _
                ? b(w, P, o)
                : P.destroy();
          }
          return (R.delete(t), v);
        } catch (P) {
          throw (R.delete(t), P);
        }
      }
      return d.get(t);
    };
  return (
    (Ce.exports = async (o, t, T) => {
      if (
        ((typeof o == "string" || o instanceof URL) && (o = n(new URL(o))),
        typeof t == "function" && ((T = t), (t = void 0)),
        (t = {
          ALPNProtocols: ["h2", "http/1.1"],
          ...o,
          ...t,
          resolveSocket: !0,
        }),
        !Array.isArray(t.ALPNProtocols) || t.ALPNProtocols.length === 0)
      )
        throw new Error(
          "The `ALPNProtocols` option must be an Array with at least one entry",
        );
      t.protocol = t.protocol || "https:";
      const a = t.protocol === "https:";
      ((t.host = t.hostname || t.host || "localhost"),
        (t.session = t.tlsSession),
        (t.servername = t.servername || i(t)),
        (t.port = t.port || (a ? 443 : 80)),
        (t._defaultAgent = a ? u.globalAgent : c.globalAgent));
      const O = t.agent;
      if (O) {
        if (O.addRequest)
          throw new Error(
            "The `options.agent` object can contain only `http`, `https` or `http2` properties",
          );
        t.agent = O[a ? "https" : "http"];
      }
      return a && (await m(t)) === "h2"
        ? (O && (t.agent = O.http2), new f(t, T))
        : c.request(t, T);
    }),
    (Ce.exports.protocolCache = d),
    Ce.exports
  );
}
var wt, pr;
function Ns() {
  if (pr) return wt;
  pr = 1;
  const c = Tt,
    u = Wr(),
    s = Jr(),
    h = Vr(),
    f = Ms();
  return (
    (wt = {
      ...c,
      ClientRequest: s,
      IncomingMessage: h,
      ...u,
      request: (d, R, b) => new s(d, R, b),
      get: (d, R, b) => {
        const m = new s(d, R, b);
        return (m.end(), m);
      },
      auto: f,
    }),
    wt
  );
}
var ke = {},
  Ae = {},
  yr;
function Kr() {
  if (yr) return Ae;
  ((yr = 1), Object.defineProperty(Ae, "__esModule", { value: !0 }));
  const c = ne();
  return (
    (Ae.default = (u) =>
      c.default.nodeStream(u) && c.default.function_(u.getBoundary)),
    Ae
  );
}
var gr;
function zs() {
  if (gr) return ke;
  ((gr = 1), Object.defineProperty(ke, "__esModule", { value: !0 }));
  const c = St,
    u = Ve,
    s = ne(),
    h = Kr(),
    f = u.promisify(c.stat);
  return (
    (ke.default = async (i, n) => {
      if (n && "content-length" in n) return Number(n["content-length"]);
      if (!i) return 0;
      if (s.default.string(i)) return Buffer.byteLength(i);
      if (s.default.buffer(i)) return i.length;
      if (h.default(i)) return u.promisify(i.getLength.bind(i))();
      if (i instanceof c.ReadStream) {
        const { size: d } = await f(i.path);
        return d === 0 ? void 0 : d;
      }
    }),
    ke
  );
}
var Oe = {},
  _r;
function Qr() {
  if (_r) return Oe;
  ((_r = 1), Object.defineProperty(Oe, "__esModule", { value: !0 }));
  function c(u, s, h) {
    const f = {};
    for (const i of h)
      ((f[i] = (...n) => {
        s.emit(i, ...n);
      }),
        u.on(i, f[i]));
    return () => {
      for (const i of h) u.off(i, f[i]);
    };
  }
  return ((Oe.default = c), Oe);
}
var le = {},
  xe = {},
  br;
function Bs() {
  return (
    br ||
      ((br = 1),
      Object.defineProperty(xe, "__esModule", { value: !0 }),
      (xe.default = () => {
        const c = [];
        return {
          once(u, s, h) {
            (u.once(s, h), c.push({ origin: u, event: s, fn: h }));
          },
          unhandleAll() {
            for (const u of c) {
              const { origin: s, event: h, fn: f } = u;
              s.removeListener(h, f);
            }
            c.length = 0;
          },
        };
      })),
    xe
  );
}
var wr;
function Fs() {
  if (wr) return le;
  ((wr = 1),
    Object.defineProperty(le, "__esModule", { value: !0 }),
    (le.TimeoutError = void 0));
  const c = zr,
    u = Bs(),
    s = Symbol("reentry"),
    h = () => {};
  class f extends Error {
    constructor(n, d) {
      (super(`Timeout awaiting '${d}' for ${n}ms`),
        (this.event = d),
        (this.name = "TimeoutError"),
        (this.code = "ETIMEDOUT"));
    }
  }
  return (
    (le.TimeoutError = f),
    (le.default = (i, n, d) => {
      if (s in i) return h;
      i[s] = !0;
      const R = [],
        { once: b, unhandleAll: m } = u.default(),
        o = (P, v, w) => {
          var _;
          const E = setTimeout(v, P, P, w);
          (_ = E.unref) === null || _ === void 0 || _.call(E);
          const l = () => {
            clearTimeout(E);
          };
          return (R.push(l), l);
        },
        { host: t, hostname: T } = d,
        a = (P, v) => {
          i.destroy(new f(P, v));
        },
        O = () => {
          for (const P of R) P();
          m();
        };
      if (
        (i.once("error", (P) => {
          if ((O(), i.listenerCount("error") === 0)) throw P;
        }),
        i.once("close", O),
        b(i, "response", (P) => {
          b(P, "end", O);
        }),
        typeof n.request < "u" && o(n.request, a, "request"),
        typeof n.socket < "u")
      ) {
        const P = () => {
          a(n.socket, "socket");
        };
        (i.setTimeout(n.socket, P),
          R.push(() => {
            i.removeListener("timeout", P);
          }));
      }
      return (
        b(i, "socket", (P) => {
          var v;
          const { socketPath: w } = i;
          if (P.connecting) {
            const _ = !!(
              w ?? c.isIP((v = T ?? t) !== null && v !== void 0 ? v : "") !== 0
            );
            if (
              typeof n.lookup < "u" &&
              !_ &&
              typeof P.address().address > "u"
            ) {
              const E = o(n.lookup, a, "lookup");
              b(P, "lookup", E);
            }
            if (typeof n.connect < "u") {
              const E = () => o(n.connect, a, "connect");
              _
                ? b(P, "connect", E())
                : b(P, "lookup", (l) => {
                    l === null && b(P, "connect", E());
                  });
            }
            typeof n.secureConnect < "u" &&
              d.protocol === "https:" &&
              b(P, "connect", () => {
                const E = o(n.secureConnect, a, "secureConnect");
                b(P, "secureConnect", E);
              });
          }
          if (typeof n.send < "u") {
            const _ = () => o(n.send, a, "send");
            P.connecting
              ? b(P, "connect", () => {
                  b(i, "upload-complete", _());
                })
              : b(i, "upload-complete", _());
          }
        }),
        typeof n.response < "u" &&
          b(i, "upload-complete", () => {
            const P = o(n.response, a, "response");
            b(i, "response", P);
          }),
        O
      );
    }),
    le
  );
}
var qe = {},
  vr;
function Ws() {
  if (vr) return qe;
  ((vr = 1), Object.defineProperty(qe, "__esModule", { value: !0 }));
  const c = ne();
  return (
    (qe.default = (u) => {
      u = u;
      const s = {
        protocol: u.protocol,
        hostname:
          c.default.string(u.hostname) && u.hostname.startsWith("[")
            ? u.hostname.slice(1, -1)
            : u.hostname,
        host: u.host,
        hash: u.hash,
        search: u.search,
        pathname: u.pathname,
        href: u.href,
        path: `${u.pathname || ""}${u.search || ""}`,
      };
      return (
        c.default.string(u.port) &&
          u.port.length > 0 &&
          (s.port = Number(u.port)),
        (u.username || u.password) &&
          (s.auth = `${u.username || ""}:${u.password || ""}`),
        s
      );
    }),
    qe
  );
}
var je = {},
  Er;
function Vs() {
  if (Er) return je;
  ((Er = 1), Object.defineProperty(je, "__esModule", { value: !0 }));
  const c = Fe,
    u = ["protocol", "host", "hostname", "port", "pathname", "search"];
  return (
    (je.default = (s, h) => {
      var f, i;
      if (h.path) {
        if (h.pathname)
          throw new TypeError(
            "Parameters `path` and `pathname` are mutually exclusive.",
          );
        if (h.search)
          throw new TypeError(
            "Parameters `path` and `search` are mutually exclusive.",
          );
        if (h.searchParams)
          throw new TypeError(
            "Parameters `path` and `searchParams` are mutually exclusive.",
          );
      }
      if (h.search && h.searchParams)
        throw new TypeError(
          "Parameters `search` and `searchParams` are mutually exclusive.",
        );
      if (!s) {
        if (!h.protocol) throw new TypeError("No URL protocol specified");
        s = `${h.protocol}//${(i = (f = h.hostname) !== null && f !== void 0 ? f : h.host) !== null && i !== void 0 ? i : ""}`;
      }
      const n = new c.URL(s);
      if (h.path) {
        const d = h.path.indexOf("?");
        (d === -1
          ? (h.pathname = h.path)
          : ((h.pathname = h.path.slice(0, d)),
            (h.search = h.path.slice(d + 1))),
          delete h.path);
      }
      for (const d of u) h[d] && (n[d] = h[d].toString());
      return n;
    }),
    je
  );
}
var He = {},
  Rr;
function Gs() {
  if (Rr) return He;
  ((Rr = 1), Object.defineProperty(He, "__esModule", { value: !0 }));
  class c {
    constructor() {
      ((this.weakMap = new WeakMap()), (this.map = new Map()));
    }
    set(s, h) {
      typeof s == "object" ? this.weakMap.set(s, h) : this.map.set(s, h);
    }
    get(s) {
      return typeof s == "object" ? this.weakMap.get(s) : this.map.get(s);
    }
    has(s) {
      return typeof s == "object" ? this.weakMap.has(s) : this.map.has(s);
    }
  }
  return ((He.default = c), He);
}
var Ie = {},
  Sr;
function Yr() {
  if (Sr) return Ie;
  ((Sr = 1), Object.defineProperty(Ie, "__esModule", { value: !0 }));
  const c = async (u) => {
    const s = [];
    let h = 0;
    for await (const f of u) (s.push(f), (h += Buffer.byteLength(f)));
    return Buffer.isBuffer(s[0])
      ? Buffer.concat(s, h)
      : Buffer.from(s.join(""));
  };
  return ((Ie.default = c), Ie);
}
var vt = {},
  Tr;
function Js() {
  return (
    Tr ||
      ((Tr = 1),
      (function (c) {
        (Object.defineProperty(c, "__esModule", { value: !0 }),
          (c.dnsLookupIpVersionToFamily = c.isDnsLookupIpVersion = void 0));
        const u = { auto: 0, ipv4: 4, ipv6: 6 };
        ((c.isDnsLookupIpVersion = (s) => s in u),
          (c.dnsLookupIpVersionToFamily = (s) => {
            if (c.isDnsLookupIpVersion(s)) return u[s];
            throw new Error("Invalid DNS lookup IP version");
          }));
      })(vt)),
    vt
  );
}
var ye = {},
  Pr;
function Xr() {
  return (
    Pr ||
      ((Pr = 1),
      Object.defineProperty(ye, "__esModule", { value: !0 }),
      (ye.isResponseOk = void 0),
      (ye.isResponseOk = (c) => {
        const { statusCode: u } = c,
          s = c.request.options.followRedirect ? 299 : 399;
        return (u >= 200 && u <= s) || u === 304;
      })),
    ye
  );
}
var $e = {},
  Cr;
function Ks() {
  if (Cr) return $e;
  ((Cr = 1), Object.defineProperty($e, "__esModule", { value: !0 }));
  const c = new Set();
  return (
    ($e.default = (u) => {
      c.has(u) ||
        (c.add(u),
        process.emitWarning(`Got: ${u}`, { type: "DeprecationWarning" }));
    }),
    $e
  );
}
var Le = {},
  kr;
function Qs() {
  if (kr) return Le;
  ((kr = 1), Object.defineProperty(Le, "__esModule", { value: !0 }));
  const c = ne(),
    u = (s, h) => {
      if (c.default.null_(s.encoding))
        throw new TypeError(
          "To get a Buffer, set `options.responseType` to `buffer` instead",
        );
      (c.assert.any([c.default.string, c.default.undefined], s.encoding),
        c.assert.any(
          [c.default.boolean, c.default.undefined],
          s.resolveBodyOnly,
        ),
        c.assert.any(
          [c.default.boolean, c.default.undefined],
          s.methodRewriting,
        ),
        c.assert.any([c.default.boolean, c.default.undefined], s.isStream),
        c.assert.any([c.default.string, c.default.undefined], s.responseType),
        s.responseType === void 0 && (s.responseType = "text"));
      const { retry: f } = s;
      if (
        (h
          ? (s.retry = { ...h.retry })
          : (s.retry = {
              calculateDelay: (i) => i.computedValue,
              limit: 0,
              methods: [],
              statusCodes: [],
              errorCodes: [],
              maxRetryAfter: void 0,
            }),
        c.default.object(f)
          ? ((s.retry = { ...s.retry, ...f }),
            (s.retry.methods = [
              ...new Set(s.retry.methods.map((i) => i.toUpperCase())),
            ]),
            (s.retry.statusCodes = [...new Set(s.retry.statusCodes)]),
            (s.retry.errorCodes = [...new Set(s.retry.errorCodes)]))
          : c.default.number(f) && (s.retry.limit = f),
        c.default.undefined(s.retry.maxRetryAfter) &&
          (s.retry.maxRetryAfter = Math.min(
            ...[s.timeout.request, s.timeout.connect].filter(c.default.number),
          )),
        c.default.object(s.pagination))
      ) {
        h && (s.pagination = { ...h.pagination, ...s.pagination });
        const { pagination: i } = s;
        if (!c.default.function_(i.transform))
          throw new Error("`options.pagination.transform` must be implemented");
        if (!c.default.function_(i.shouldContinue))
          throw new Error(
            "`options.pagination.shouldContinue` must be implemented",
          );
        if (!c.default.function_(i.filter))
          throw new TypeError(
            "`options.pagination.filter` must be implemented",
          );
        if (!c.default.function_(i.paginate))
          throw new Error("`options.pagination.paginate` must be implemented");
      }
      return (
        s.responseType === "json" &&
          s.headers.accept === void 0 &&
          (s.headers.accept = "application/json"),
        s
      );
    };
  return ((Le.default = u), Le);
}
var me = {},
  Ar;
function Ys() {
  if (Ar) return me;
  ((Ar = 1),
    Object.defineProperty(me, "__esModule", { value: !0 }),
    (me.retryAfterStatusCodes = void 0),
    (me.retryAfterStatusCodes = new Set([413, 429, 503])));
  const c = ({ attemptCount: u, retryOptions: s, error: h, retryAfter: f }) => {
    if (u > s.limit) return 0;
    const i = s.methods.includes(h.options.method),
      n = s.errorCodes.includes(h.code),
      d = h.response && s.statusCodes.includes(h.response.statusCode);
    if (!i || (!n && !d)) return 0;
    if (h.response) {
      if (f) return s.maxRetryAfter === void 0 || f > s.maxRetryAfter ? 0 : f;
      if (h.response.statusCode === 413) return 0;
    }
    const R = Math.random() * 100;
    return 2 ** (u - 1) * 1e3 + R;
  };
  return ((me.default = c), me);
}
var Or;
function ze() {
  return (
    Or ||
      ((Or = 1),
      (function (c) {
        (Object.defineProperty(c, "__esModule", { value: !0 }),
          (c.UnsupportedProtocolError =
            c.ReadError =
            c.TimeoutError =
            c.UploadError =
            c.CacheError =
            c.HTTPError =
            c.MaxRedirectsError =
            c.RequestError =
            c.setNonEnumerableProperties =
            c.knownHookEvents =
            c.withoutBody =
            c.kIsNormalizedAlready =
              void 0));
        const u = Ve,
          s = fe,
          h = St,
          f = Fe,
          i = Rt,
          n = Rt,
          d = Mr,
          R = _s(),
          b = bs(),
          m = qs(),
          o = Hs(),
          t = Ns(),
          T = Pt(),
          a = ne(),
          O = zs(),
          P = Kr(),
          v = Qr(),
          w = Fs(),
          _ = Ws(),
          E = Vs(),
          l = Gs(),
          e = Yr(),
          y = Js(),
          x = Xr(),
          C = Ks(),
          D = Qs(),
          I = Ys();
        let g;
        const S = Symbol("request"),
          q = Symbol("response"),
          z = Symbol("responseSize"),
          M = Symbol("downloadedSize"),
          $ = Symbol("bodySize"),
          F = Symbol("uploadedSize"),
          ee = Symbol("serverResponsesPiped"),
          G = Symbol("unproxyEvents"),
          te = Symbol("isFromCache"),
          ie = Symbol("cancelTimeouts"),
          _e = Symbol("startedReading"),
          he = Symbol("stopReading"),
          be = Symbol("triggerRead"),
          se = Symbol("body"),
          pe = Symbol("jobs"),
          Ct = Symbol("originalResponse"),
          kt = Symbol("retryTimeout");
        c.kIsNormalizedAlready = Symbol("isNormalizedAlready");
        const es = a.default.string(process.versions.brotli);
        ((c.withoutBody = new Set(["GET", "HEAD"])),
          (c.knownHookEvents = [
            "init",
            "beforeRequest",
            "beforeRedirect",
            "beforeError",
            "beforeRetry",
            "afterResponse",
          ]));
        function ts(K) {
          for (const p in K) {
            const r = K[p];
            if (
              !a.default.string(r) &&
              !a.default.number(r) &&
              !a.default.boolean(r) &&
              !a.default.null_(r) &&
              !a.default.undefined(r)
            )
              throw new TypeError(
                `The \`searchParams\` value '${String(r)}' must be a string, number, boolean or null`,
              );
          }
        }
        function rs(K) {
          return a.default.object(K) && !("statusCode" in K);
        }
        const Ge = new l.default(),
          ss = async (K) =>
            new Promise((p, r) => {
              const k = (L) => {
                r(L);
              };
              (K.pending || p(),
                K.once("error", k),
                K.once("ready", () => {
                  (K.off("error", k), p());
                }));
            }),
          ns = new Set([300, 301, 302, 303, 304, 307, 308]),
          is = ["context", "body", "json", "form"];
        c.setNonEnumerableProperties = (K, p) => {
          const r = {};
          for (const k of K)
            if (k)
              for (const L of is)
                L in k &&
                  (r[L] = {
                    writable: !0,
                    configurable: !0,
                    enumerable: !1,
                    value: k[L],
                  });
          Object.defineProperties(p, r);
        };
        class Y extends Error {
          constructor(p, r, k) {
            var L, j;
            if (
              (super(p),
              Error.captureStackTrace(this, this.constructor),
              (this.name = "RequestError"),
              (this.code =
                (L = r.code) !== null && L !== void 0
                  ? L
                  : "ERR_GOT_REQUEST_ERROR"),
              k instanceof It
                ? (Object.defineProperty(this, "request", {
                    enumerable: !1,
                    value: k,
                  }),
                  Object.defineProperty(this, "response", {
                    enumerable: !1,
                    value: k[q],
                  }),
                  Object.defineProperty(this, "options", {
                    enumerable: !1,
                    value: k.options,
                  }))
                : Object.defineProperty(this, "options", {
                    enumerable: !1,
                    value: k,
                  }),
              (this.timings =
                (j = this.request) === null || j === void 0
                  ? void 0
                  : j.timings),
              a.default.string(r.stack) && a.default.string(this.stack))
            ) {
              const A = this.stack.indexOf(this.message) + this.message.length,
                H = this.stack
                  .slice(A)
                  .split(
                    `
`,
                  )
                  .reverse(),
                U = r.stack
                  .slice(r.stack.indexOf(r.message) + r.message.length)
                  .split(
                    `
`,
                  )
                  .reverse();
              for (; U.length !== 0 && U[0] === H[0];) H.shift();
              this.stack = `${this.stack.slice(0, A)}${H.reverse().join(`
`)}${U.reverse().join(`
`)}`;
            }
          }
        }
        c.RequestError = Y;
        class At extends Y {
          constructor(p) {
            (super(
              `Redirected ${p.options.maxRedirects} times. Aborting.`,
              {},
              p,
            ),
              (this.name = "MaxRedirectsError"),
              (this.code = "ERR_TOO_MANY_REDIRECTS"));
          }
        }
        c.MaxRedirectsError = At;
        class Ot extends Y {
          constructor(p) {
            (super(
              `Response code ${p.statusCode} (${p.statusMessage})`,
              {},
              p.request,
            ),
              (this.name = "HTTPError"),
              (this.code = "ERR_NON_2XX_3XX_RESPONSE"));
          }
        }
        c.HTTPError = Ot;
        class xt extends Y {
          constructor(p, r) {
            (super(p.message, p, r),
              (this.name = "CacheError"),
              (this.code =
                this.code === "ERR_GOT_REQUEST_ERROR"
                  ? "ERR_CACHE_ACCESS"
                  : this.code));
          }
        }
        c.CacheError = xt;
        class qt extends Y {
          constructor(p, r) {
            (super(p.message, p, r),
              (this.name = "UploadError"),
              (this.code =
                this.code === "ERR_GOT_REQUEST_ERROR"
                  ? "ERR_UPLOAD"
                  : this.code));
          }
        }
        c.UploadError = qt;
        class jt extends Y {
          constructor(p, r, k) {
            (super(p.message, p, k),
              (this.name = "TimeoutError"),
              (this.event = p.event),
              (this.timings = r));
          }
        }
        c.TimeoutError = jt;
        class Je extends Y {
          constructor(p, r) {
            (super(p.message, p, r),
              (this.name = "ReadError"),
              (this.code =
                this.code === "ERR_GOT_REQUEST_ERROR"
                  ? "ERR_READING_RESPONSE_STREAM"
                  : this.code));
          }
        }
        c.ReadError = Je;
        class Ht extends Y {
          constructor(p) {
            (super(`Unsupported protocol "${p.url.protocol}"`, {}, p),
              (this.name = "UnsupportedProtocolError"),
              (this.code = "ERR_UNSUPPORTED_PROTOCOL"));
          }
        }
        c.UnsupportedProtocolError = Ht;
        const os = [
          "socket",
          "connect",
          "continue",
          "information",
          "upgrade",
          "timeout",
        ];
        class It extends s.Duplex {
          constructor(p, r = {}, k) {
            (super({ autoDestroy: !1, highWaterMark: 0 }),
              (this[M] = 0),
              (this[F] = 0),
              (this.requestInitialized = !1),
              (this[ee] = new Set()),
              (this.redirects = []),
              (this[he] = !1),
              (this[be] = !1),
              (this[pe] = []),
              (this.retryCount = 0),
              (this._progressCallbacks = []));
            const L = () => this._unlockWrite(),
              j = () => this._lockWrite();
            (this.on("pipe", (B) => {
              (B.prependListener("data", L),
                B.on("data", j),
                B.prependListener("end", L),
                B.on("end", j));
            }),
              this.on("unpipe", (B) => {
                (B.off("data", L),
                  B.off("data", j),
                  B.off("end", L),
                  B.off("end", j));
              }),
              this.on("pipe", (B) => {
                B instanceof n.IncomingMessage &&
                  (this.options.headers = {
                    ...B.headers,
                    ...this.options.headers,
                  });
              }));
            const { json: A, body: H, form: U } = r;
            if (
              ((A || H || U) && this._lockWrite(), c.kIsNormalizedAlready in r)
            )
              this.options = r;
            else
              try {
                this.options = this.constructor.normalizeArguments(p, r, k);
              } catch (B) {
                (a.default.nodeStream(r.body) && r.body.destroy(),
                  this.destroy(B));
                return;
              }
            (async () => {
              var B;
              try {
                this.options.body instanceof h.ReadStream &&
                  (await ss(this.options.body));
                const { url: X } = this.options;
                if (!X) throw new TypeError("Missing `url` property");
                if (
                  ((this.requestUrl = X.toString()),
                  decodeURI(this.requestUrl),
                  await this._finalizeBody(),
                  await this._makeRequest(),
                  this.destroyed)
                ) {
                  (B = this[S]) === null || B === void 0 || B.destroy();
                  return;
                }
                for (const Z of this[pe]) Z();
                ((this[pe].length = 0), (this.requestInitialized = !0));
              } catch (X) {
                if (X instanceof Y) {
                  this._beforeError(X);
                  return;
                }
                this.destroyed || this.destroy(X);
              }
            })();
          }
          static normalizeArguments(p, r, k) {
            var L, j, A, H, U;
            const B = r;
            if (a.default.object(p) && !a.default.urlInstance(p))
              r = { ...k, ...p, ...r };
            else {
              if (p && r && r.url !== void 0)
                throw new TypeError(
                  "The `url` option is mutually exclusive with the `input` argument",
                );
              ((r = { ...k, ...r }),
                p !== void 0 && (r.url = p),
                a.default.urlInstance(r.url) &&
                  (r.url = new f.URL(r.url.toString())));
            }
            if (
              (r.cache === !1 && (r.cache = void 0),
              r.dnsCache === !1 && (r.dnsCache = void 0),
              a.assert.any([a.default.string, a.default.undefined], r.method),
              a.assert.any([a.default.object, a.default.undefined], r.headers),
              a.assert.any(
                [a.default.string, a.default.urlInstance, a.default.undefined],
                r.prefixUrl,
              ),
              a.assert.any(
                [a.default.object, a.default.undefined],
                r.cookieJar,
              ),
              a.assert.any(
                [a.default.object, a.default.string, a.default.undefined],
                r.searchParams,
              ),
              a.assert.any(
                [a.default.object, a.default.string, a.default.undefined],
                r.cache,
              ),
              a.assert.any(
                [a.default.object, a.default.number, a.default.undefined],
                r.timeout,
              ),
              a.assert.any([a.default.object, a.default.undefined], r.context),
              a.assert.any([a.default.object, a.default.undefined], r.hooks),
              a.assert.any(
                [a.default.boolean, a.default.undefined],
                r.decompress,
              ),
              a.assert.any(
                [a.default.boolean, a.default.undefined],
                r.ignoreInvalidCookies,
              ),
              a.assert.any(
                [a.default.boolean, a.default.undefined],
                r.followRedirect,
              ),
              a.assert.any(
                [a.default.number, a.default.undefined],
                r.maxRedirects,
              ),
              a.assert.any(
                [a.default.boolean, a.default.undefined],
                r.throwHttpErrors,
              ),
              a.assert.any([a.default.boolean, a.default.undefined], r.http2),
              a.assert.any(
                [a.default.boolean, a.default.undefined],
                r.allowGetBody,
              ),
              a.assert.any(
                [a.default.string, a.default.undefined],
                r.localAddress,
              ),
              a.assert.any(
                [y.isDnsLookupIpVersion, a.default.undefined],
                r.dnsLookupIpVersion,
              ),
              a.assert.any([a.default.object, a.default.undefined], r.https),
              a.assert.any(
                [a.default.boolean, a.default.undefined],
                r.rejectUnauthorized,
              ),
              r.https &&
                (a.assert.any(
                  [a.default.boolean, a.default.undefined],
                  r.https.rejectUnauthorized,
                ),
                a.assert.any(
                  [a.default.function_, a.default.undefined],
                  r.https.checkServerIdentity,
                ),
                a.assert.any(
                  [
                    a.default.string,
                    a.default.object,
                    a.default.array,
                    a.default.undefined,
                  ],
                  r.https.certificateAuthority,
                ),
                a.assert.any(
                  [
                    a.default.string,
                    a.default.object,
                    a.default.array,
                    a.default.undefined,
                  ],
                  r.https.key,
                ),
                a.assert.any(
                  [
                    a.default.string,
                    a.default.object,
                    a.default.array,
                    a.default.undefined,
                  ],
                  r.https.certificate,
                ),
                a.assert.any(
                  [a.default.string, a.default.undefined],
                  r.https.passphrase,
                ),
                a.assert.any(
                  [
                    a.default.string,
                    a.default.buffer,
                    a.default.array,
                    a.default.undefined,
                  ],
                  r.https.pfx,
                )),
              a.assert.any(
                [a.default.object, a.default.undefined],
                r.cacheOptions,
              ),
              a.default.string(r.method)
                ? (r.method = r.method.toUpperCase())
                : (r.method = "GET"),
              r.headers === k?.headers
                ? (r.headers = { ...r.headers })
                : (r.headers = T({ ...k?.headers, ...r.headers })),
              "slashes" in r)
            )
              throw new TypeError(
                "The legacy `url.Url` has been deprecated. Use `URL` instead.",
              );
            if ("auth" in r)
              throw new TypeError(
                "Parameter `auth` is deprecated. Use `username` / `password` instead.",
              );
            if (
              "searchParams" in r &&
              r.searchParams &&
              r.searchParams !== k?.searchParams
            ) {
              let N;
              if (
                a.default.string(r.searchParams) ||
                r.searchParams instanceof f.URLSearchParams
              )
                N = new f.URLSearchParams(r.searchParams);
              else {
                (ts(r.searchParams), (N = new f.URLSearchParams()));
                for (const J in r.searchParams) {
                  const Q = r.searchParams[J];
                  Q === null ? N.append(J, "") : Q !== void 0 && N.append(J, Q);
                }
              }
              ((L = k?.searchParams) === null ||
                L === void 0 ||
                L.forEach((J, Q) => {
                  N.has(Q) || N.append(Q, J);
                }),
                (r.searchParams = N));
            }
            if (
              ((r.username =
                (j = r.username) !== null && j !== void 0 ? j : ""),
              (r.password = (A = r.password) !== null && A !== void 0 ? A : ""),
              a.default.undefined(r.prefixUrl)
                ? (r.prefixUrl =
                    (H = k?.prefixUrl) !== null && H !== void 0 ? H : "")
                : ((r.prefixUrl = r.prefixUrl.toString()),
                  r.prefixUrl !== "" &&
                    !r.prefixUrl.endsWith("/") &&
                    (r.prefixUrl += "/")),
              a.default.string(r.url))
            ) {
              if (r.url.startsWith("/"))
                throw new Error(
                  "`input` must not start with a slash when using `prefixUrl`",
                );
              r.url = E.default(r.prefixUrl + r.url, r);
            } else
              ((a.default.undefined(r.url) && r.prefixUrl !== "") ||
                r.protocol) &&
                (r.url = E.default(r.prefixUrl, r));
            if (r.url) {
              "port" in r && delete r.port;
              let { prefixUrl: N } = r;
              Object.defineProperty(r, "prefixUrl", {
                set: (Q) => {
                  const V = r.url;
                  if (!V.href.startsWith(Q))
                    throw new Error(
                      `Cannot change \`prefixUrl\` from ${N} to ${Q}: ${V.href}`,
                    );
                  ((r.url = new f.URL(Q + V.href.slice(N.length))), (N = Q));
                },
                get: () => N,
              });
              let { protocol: J } = r.url;
              if (
                (J === "unix:" &&
                  ((J = "http:"),
                  (r.url = new f.URL(
                    `http://unix${r.url.pathname}${r.url.search}`,
                  ))),
                r.searchParams && (r.url.search = r.searchParams.toString()),
                J !== "http:" && J !== "https:")
              )
                throw new Ht(r);
              (r.username === ""
                ? (r.username = r.url.username)
                : (r.url.username = r.username),
                r.password === ""
                  ? (r.password = r.url.password)
                  : (r.url.password = r.password));
            }
            const { cookieJar: X } = r;
            if (X) {
              let { setCookie: N, getCookieString: J } = X;
              (a.assert.function_(N),
                a.assert.function_(J),
                N.length === 4 &&
                  J.length === 0 &&
                  ((N = u.promisify(N.bind(r.cookieJar))),
                  (J = u.promisify(J.bind(r.cookieJar))),
                  (r.cookieJar = { setCookie: N, getCookieString: J })));
            }
            const { cache: Z } = r;
            if (
              (Z &&
                (Ge.has(Z) ||
                  Ge.set(
                    Z,
                    new m((N, J) => {
                      const Q = N[S](N, J);
                      return (
                        a.default.promise(Q) &&
                          (Q.once = (V, W) => {
                            if (V === "error") Q.catch(W);
                            else if (V === "abort")
                              (async () => {
                                try {
                                  (await Q).once("abort", W);
                                } catch {}
                              })();
                            else
                              throw new Error(
                                `Unknown HTTP2 promise event: ${V}`,
                              );
                            return Q;
                          }),
                        Q
                      );
                    }, Z),
                  )),
              (r.cacheOptions = { ...r.cacheOptions }),
              r.dnsCache === !0)
            )
              (g || (g = new b.default()), (r.dnsCache = g));
            else if (!a.default.undefined(r.dnsCache) && !r.dnsCache.lookup)
              throw new TypeError(
                `Parameter \`dnsCache\` must be a CacheableLookup instance or a boolean, got ${a.default(r.dnsCache)}`,
              );
            (a.default.number(r.timeout)
              ? (r.timeout = { request: r.timeout })
              : k && r.timeout !== k.timeout
                ? (r.timeout = { ...k.timeout, ...r.timeout })
                : (r.timeout = { ...r.timeout }),
              r.context || (r.context = {}));
            const re = r.hooks === k?.hooks;
            r.hooks = { ...r.hooks };
            for (const N of c.knownHookEvents)
              if (N in r.hooks)
                if (a.default.array(r.hooks[N])) r.hooks[N] = [...r.hooks[N]];
                else
                  throw new TypeError(
                    `Parameter \`${N}\` must be an Array, got ${a.default(r.hooks[N])}`,
                  );
              else r.hooks[N] = [];
            if (k && !re)
              for (const N of c.knownHookEvents)
                k.hooks[N].length > 0 &&
                  (r.hooks[N] = [...k.hooks[N], ...r.hooks[N]]);
            if (
              ("family" in r &&
                C.default(
                  '"options.family" was never documented, please use "options.dnsLookupIpVersion"',
                ),
              k?.https && (r.https = { ...k.https, ...r.https }),
              "rejectUnauthorized" in r &&
                C.default(
                  '"options.rejectUnauthorized" is now deprecated, please use "options.https.rejectUnauthorized"',
                ),
              "checkServerIdentity" in r &&
                C.default(
                  '"options.checkServerIdentity" was never documented, please use "options.https.checkServerIdentity"',
                ),
              "ca" in r &&
                C.default(
                  '"options.ca" was never documented, please use "options.https.certificateAuthority"',
                ),
              "key" in r &&
                C.default(
                  '"options.key" was never documented, please use "options.https.key"',
                ),
              "cert" in r &&
                C.default(
                  '"options.cert" was never documented, please use "options.https.certificate"',
                ),
              "passphrase" in r &&
                C.default(
                  '"options.passphrase" was never documented, please use "options.https.passphrase"',
                ),
              "pfx" in r &&
                C.default(
                  '"options.pfx" was never documented, please use "options.https.pfx"',
                ),
              "followRedirects" in r)
            )
              throw new TypeError(
                "The `followRedirects` option does not exist. Use `followRedirect` instead.",
              );
            if (r.agent) {
              for (const N in r.agent)
                if (N !== "http" && N !== "https" && N !== "http2")
                  throw new TypeError(
                    `Expected the \`options.agent\` properties to be \`http\`, \`https\` or \`http2\`, got \`${N}\``,
                  );
            }
            return (
              (r.maxRedirects =
                (U = r.maxRedirects) !== null && U !== void 0 ? U : 0),
              c.setNonEnumerableProperties([k, B], r),
              D.default(r, k)
            );
          }
          _lockWrite() {
            const p = () => {
              throw new TypeError("The payload has been already provided");
            };
            ((this.write = p), (this.end = p));
          }
          _unlockWrite() {
            ((this.write = super.write), (this.end = super.end));
          }
          async _finalizeBody() {
            const { options: p } = this,
              { headers: r } = p,
              k = !a.default.undefined(p.form),
              L = !a.default.undefined(p.json),
              j = !a.default.undefined(p.body),
              A = k || L || j,
              H =
                c.withoutBody.has(p.method) &&
                !(p.method === "GET" && p.allowGetBody);
            if (((this._cannotHaveBody = H), A)) {
              if (H)
                throw new TypeError(
                  `The \`${p.method}\` method cannot be used with a body`,
                );
              if ([j, k, L].filter((U) => U).length > 1)
                throw new TypeError(
                  "The `body`, `json` and `form` options are mutually exclusive",
                );
              if (
                j &&
                !(p.body instanceof s.Readable) &&
                !a.default.string(p.body) &&
                !a.default.buffer(p.body) &&
                !P.default(p.body)
              )
                throw new TypeError(
                  "The `body` option must be a stream.Readable, string or Buffer",
                );
              if (k && !a.default.object(p.form))
                throw new TypeError("The `form` option must be an Object");
              {
                const U = !a.default.string(r["content-type"]);
                j
                  ? (P.default(p.body) &&
                      U &&
                      (r["content-type"] =
                        `multipart/form-data; boundary=${p.body.getBoundary()}`),
                    (this[se] = p.body))
                  : k
                    ? (U &&
                        (r["content-type"] =
                          "application/x-www-form-urlencoded"),
                      (this[se] = new f.URLSearchParams(p.form).toString()))
                    : (U && (r["content-type"] = "application/json"),
                      (this[se] = p.stringifyJson(p.json)));
                const B = await O.default(this[se], p.headers);
                a.default.undefined(r["content-length"]) &&
                  a.default.undefined(r["transfer-encoding"]) &&
                  !H &&
                  !a.default.undefined(B) &&
                  (r["content-length"] = String(B));
              }
            } else H ? this._lockWrite() : this._unlockWrite();
            this[$] = Number(r["content-length"]) || void 0;
          }
          async _onResponseBase(p) {
            const { options: r } = this,
              { url: k } = r;
            ((this[Ct] = p), r.decompress && (p = o(p)));
            const L = p.statusCode,
              j = p;
            ((j.statusMessage = j.statusMessage
              ? j.statusMessage
              : i.STATUS_CODES[L]),
              (j.url = r.url.toString()),
              (j.requestUrl = this.requestUrl),
              (j.redirectUrls = this.redirects),
              (j.request = this),
              (j.isFromCache = p.fromCache || !1),
              (j.ip = this.ip),
              (j.retryCount = this.retryCount),
              (this[te] = j.isFromCache),
              (this[z] = Number(p.headers["content-length"]) || void 0),
              (this[q] = p),
              p.once("end", () => {
                ((this[z] = this[M]),
                  this.emit("downloadProgress", this.downloadProgress));
              }),
              p.once("error", (H) => {
                (p.destroy(), this._beforeError(new Je(H, this)));
              }),
              p.once("aborted", () => {
                this._beforeError(
                  new Je(
                    {
                      name: "Error",
                      message: "The server aborted pending request",
                      code: "ECONNRESET",
                    },
                    this,
                  ),
                );
              }),
              this.emit("downloadProgress", this.downloadProgress));
            const A = p.headers["set-cookie"];
            if (a.default.object(r.cookieJar) && A) {
              let H = A.map(async (U) =>
                r.cookieJar.setCookie(U, k.toString()),
              );
              r.ignoreInvalidCookies &&
                (H = H.map(async (U) => U.catch(() => {})));
              try {
                await Promise.all(H);
              } catch (U) {
                this._beforeError(U);
                return;
              }
            }
            if (r.followRedirect && p.headers.location && ns.has(L)) {
              if (
                (p.resume(),
                this[S] && (this[ie](), delete this[S], this[G]()),
                ((L === 303 && r.method !== "GET" && r.method !== "HEAD") ||
                  !r.methodRewriting) &&
                  ((r.method = "GET"),
                  "body" in r && delete r.body,
                  "json" in r && delete r.json,
                  "form" in r && delete r.form,
                  (this[se] = void 0),
                  delete r.headers["content-length"]),
                this.redirects.length >= r.maxRedirects)
              ) {
                this._beforeError(new At(this));
                return;
              }
              try {
                let Z = function (re) {
                  return re.protocol === "unix:" || re.hostname === "unix";
                };
                const U = Buffer.from(p.headers.location, "binary").toString(),
                  B = new f.URL(U, k),
                  X = B.toString();
                if ((decodeURI(X), !Z(k) && Z(B))) {
                  this._beforeError(
                    new Y("Cannot redirect to UNIX socket", {}, this),
                  );
                  return;
                }
                (B.hostname !== k.hostname || B.port !== k.port
                  ? ("host" in r.headers && delete r.headers.host,
                    "cookie" in r.headers && delete r.headers.cookie,
                    "authorization" in r.headers &&
                      delete r.headers.authorization,
                    (r.username || r.password) &&
                      ((r.username = ""), (r.password = "")))
                  : ((B.username = r.username), (B.password = r.password)),
                  this.redirects.push(X),
                  (r.url = B));
                for (const re of r.hooks.beforeRedirect) await re(r, j);
                (this.emit("redirect", j, r), await this._makeRequest());
              } catch (U) {
                this._beforeError(U);
                return;
              }
              return;
            }
            if (r.isStream && r.throwHttpErrors && !x.isResponseOk(j)) {
              this._beforeError(new Ot(j));
              return;
            }
            (p.on("readable", () => {
              this[be] && this._read();
            }),
              this.on("resume", () => {
                p.resume();
              }),
              this.on("pause", () => {
                p.pause();
              }),
              p.once("end", () => {
                this.push(null);
              }),
              this.emit("response", p));
            for (const H of this[ee])
              if (!H.headersSent) {
                for (const U in p.headers) {
                  const B = r.decompress ? U !== "content-encoding" : !0,
                    X = p.headers[U];
                  B && H.setHeader(U, X);
                }
                H.statusCode = L;
              }
          }
          async _onResponse(p) {
            try {
              await this._onResponseBase(p);
            } catch (r) {
              this._beforeError(r);
            }
          }
          _onRequest(p) {
            const { options: r } = this,
              { timeout: k, url: L } = r;
            (R.default(p), (this[ie] = w.default(p, k, L)));
            const j = r.cache ? "cacheableResponse" : "response";
            (p.once(j, (U) => {
              this._onResponse(U);
            }),
              p.once("error", (U) => {
                var B;
                (p.destroy(),
                  (B = p.res) === null ||
                    B === void 0 ||
                    B.removeAllListeners("end"),
                  (U =
                    U instanceof w.TimeoutError
                      ? new jt(U, this.timings, this)
                      : new Y(U.message, U, this)),
                  this._beforeError(U));
              }),
              (this[G] = v.default(p, this, os)),
              (this[S] = p),
              this.emit("uploadProgress", this.uploadProgress));
            const A = this[se],
              H = this.redirects.length === 0 ? this : p;
            (a.default.nodeStream(A)
              ? (A.pipe(H),
                A.once("error", (U) => {
                  this._beforeError(new qt(U, this));
                }))
              : (this._unlockWrite(),
                a.default.undefined(A)
                  ? (this._cannotHaveBody || this._noPipe) &&
                    (H.end(), this._lockWrite())
                  : (this._writeRequest(A, void 0, () => {}),
                    H.end(),
                    this._lockWrite())),
              this.emit("request", p));
          }
          async _createCacheableRequest(p, r) {
            return new Promise((k, L) => {
              (Object.assign(r, _.default(p)), delete r.url);
              let j;
              const A = Ge.get(r.cache)(r, async (H) => {
                ((H._readableState.autoDestroy = !1),
                  j && (await j).emit("cacheableResponse", H),
                  k(H));
              });
              ((r.url = p),
                A.once("error", L),
                A.once("request", async (H) => {
                  ((j = H), k(j));
                }));
            });
          }
          async _makeRequest() {
            var p, r, k, L, j;
            const { options: A } = this,
              { headers: H } = A;
            for (const W in H)
              if (a.default.undefined(H[W])) delete H[W];
              else if (a.default.null_(H[W]))
                throw new TypeError(
                  `Use \`undefined\` instead of \`null\` to delete the \`${W}\` header`,
                );
            if (
              (A.decompress &&
                a.default.undefined(H["accept-encoding"]) &&
                (H["accept-encoding"] = es
                  ? "gzip, deflate, br"
                  : "gzip, deflate"),
              A.cookieJar)
            ) {
              const W = await A.cookieJar.getCookieString(A.url.toString());
              a.default.nonEmptyString(W) && (A.headers.cookie = W);
            }
            for (const W of A.hooks.beforeRequest) {
              const de = await W(A);
              if (!a.default.undefined(de)) {
                A.request = () => de;
                break;
              }
            }
            A.body && this[se] !== A.body && (this[se] = A.body);
            const { agent: U, request: B, timeout: X, url: Z } = A;
            if (
              (A.dnsCache && !("lookup" in A) && (A.lookup = A.dnsCache.lookup),
              Z.hostname === "unix")
            ) {
              const W = /(?<socketPath>.+?):(?<path>.+)/.exec(
                `${Z.pathname}${Z.search}`,
              );
              if (W?.groups) {
                const { socketPath: de, path: as } = W.groups;
                Object.assign(A, { socketPath: de, path: as, host: "" });
              }
            }
            const re = Z.protocol === "https:";
            let N;
            A.http2 ? (N = t.auto) : (N = re ? d.request : i.request);
            const J = (p = A.request) !== null && p !== void 0 ? p : N,
              Q = A.cache ? this._createCacheableRequest : J;
            (U && !A.http2 && (A.agent = U[re ? "https" : "http"]),
              (A[S] = J),
              delete A.request,
              delete A.timeout);
            const V = A;
            if (
              ((V.shared =
                (r = A.cacheOptions) === null || r === void 0
                  ? void 0
                  : r.shared),
              (V.cacheHeuristic =
                (k = A.cacheOptions) === null || k === void 0
                  ? void 0
                  : k.cacheHeuristic),
              (V.immutableMinTimeToLive =
                (L = A.cacheOptions) === null || L === void 0
                  ? void 0
                  : L.immutableMinTimeToLive),
              (V.ignoreCargoCult =
                (j = A.cacheOptions) === null || j === void 0
                  ? void 0
                  : j.ignoreCargoCult),
              A.dnsLookupIpVersion !== void 0)
            )
              try {
                V.family = y.dnsLookupIpVersionToFamily(A.dnsLookupIpVersion);
              } catch {
                throw new Error("Invalid `dnsLookupIpVersion` option value");
              }
            A.https &&
              ("rejectUnauthorized" in A.https &&
                (V.rejectUnauthorized = A.https.rejectUnauthorized),
              A.https.checkServerIdentity &&
                (V.checkServerIdentity = A.https.checkServerIdentity),
              A.https.certificateAuthority &&
                (V.ca = A.https.certificateAuthority),
              A.https.certificate && (V.cert = A.https.certificate),
              A.https.key && (V.key = A.https.key),
              A.https.passphrase && (V.passphrase = A.https.passphrase),
              A.https.pfx && (V.pfx = A.https.pfx));
            try {
              let W = await Q(Z, V);
              (a.default.undefined(W) && (W = N(Z, V)),
                (A.request = B),
                (A.timeout = X),
                (A.agent = U),
                A.https &&
                  ("rejectUnauthorized" in A.https &&
                    delete V.rejectUnauthorized,
                  A.https.checkServerIdentity && delete V.checkServerIdentity,
                  A.https.certificateAuthority && delete V.ca,
                  A.https.certificate && delete V.cert,
                  A.https.key && delete V.key,
                  A.https.passphrase && delete V.passphrase,
                  A.https.pfx && delete V.pfx),
                rs(W)
                  ? this._onRequest(W)
                  : this.writable
                    ? (this.once("finish", () => {
                        this._onResponse(W);
                      }),
                      this._unlockWrite(),
                      this.end(),
                      this._lockWrite())
                    : this._onResponse(W));
            } catch (W) {
              throw W instanceof m.CacheError
                ? new xt(W, this)
                : new Y(W.message, W, this);
            }
          }
          async _error(p) {
            try {
              for (const r of this.options.hooks.beforeError) p = await r(p);
            } catch (r) {
              p = new Y(r.message, r, this);
            }
            this.destroy(p);
          }
          _beforeError(p) {
            if (this[he]) return;
            const { options: r } = this,
              k = this.retryCount + 1;
            ((this[he] = !0),
              p instanceof Y || (p = new Y(p.message, p, this)));
            const L = p,
              { response: j } = L;
            (async () => {
              if (j && !j.body) {
                j.setEncoding(this._readableState.encoding);
                try {
                  ((j.rawBody = await e.default(j)),
                    (j.body = j.rawBody.toString()));
                } catch {}
              }
              if (this.listenerCount("retry") !== 0) {
                let A;
                try {
                  let H;
                  (j &&
                    "retry-after" in j.headers &&
                    ((H = Number(j.headers["retry-after"])),
                    Number.isNaN(H)
                      ? ((H =
                          Date.parse(j.headers["retry-after"]) - Date.now()),
                        H <= 0 && (H = 1))
                      : (H *= 1e3)),
                    (A = await r.retry.calculateDelay({
                      attemptCount: k,
                      retryOptions: r.retry,
                      error: L,
                      retryAfter: H,
                      computedValue: I.default({
                        attemptCount: k,
                        retryOptions: r.retry,
                        error: L,
                        retryAfter: H,
                        computedValue: 0,
                      }),
                    })));
                } catch (H) {
                  this._error(new Y(H.message, H, this));
                  return;
                }
                if (A) {
                  const H = async () => {
                    try {
                      for (const U of this.options.hooks.beforeRetry)
                        await U(this.options, L, k);
                    } catch (U) {
                      this._error(new Y(U.message, p, this));
                      return;
                    }
                    this.destroyed ||
                      (this.destroy(), this.emit("retry", k, p));
                  };
                  this[kt] = setTimeout(H, A);
                  return;
                }
              }
              this._error(L);
            })();
          }
          _read() {
            this[be] = !0;
            const p = this[q];
            if (p && !this[he]) {
              p.readableLength && (this[be] = !1);
              let r;
              for (; (r = p.read()) !== null;) {
                ((this[M] += r.length), (this[_e] = !0));
                const k = this.downloadProgress;
                (k.percent < 1 && this.emit("downloadProgress", k),
                  this.push(r));
              }
            }
          }
          _write(p, r, k) {
            const L = () => {
              this._writeRequest(p, r, k);
            };
            this.requestInitialized ? L() : this[pe].push(L);
          }
          _writeRequest(p, r, k) {
            this[S].destroyed ||
              (this._progressCallbacks.push(() => {
                this[F] += Buffer.byteLength(p, r);
                const L = this.uploadProgress;
                L.percent < 1 && this.emit("uploadProgress", L);
              }),
              this[S].write(p, r, (L) => {
                (!L &&
                  this._progressCallbacks.length > 0 &&
                  this._progressCallbacks.shift()(),
                  k(L));
              }));
          }
          _final(p) {
            const r = () => {
              for (; this._progressCallbacks.length !== 0;)
                this._progressCallbacks.shift()();
              if (!(S in this)) {
                p();
                return;
              }
              if (this[S].destroyed) {
                p();
                return;
              }
              this[S].end((k) => {
                (k ||
                  ((this[$] = this[F]),
                  this.emit("uploadProgress", this.uploadProgress),
                  this[S].emit("upload-complete")),
                  p(k));
              });
            };
            this.requestInitialized ? r() : this[pe].push(r);
          }
          _destroy(p, r) {
            var k;
            ((this[he] = !0),
              clearTimeout(this[kt]),
              S in this &&
                (this[ie](),
                (!((k = this[q]) === null || k === void 0) && k.complete) ||
                  this[S].destroy()),
              p !== null &&
                !a.default.undefined(p) &&
                !(p instanceof Y) &&
                (p = new Y(p.message, p, this)),
              r(p));
          }
          get _isAboutToError() {
            return this[he];
          }
          get ip() {
            var p;
            return (p = this.socket) === null || p === void 0
              ? void 0
              : p.remoteAddress;
          }
          get aborted() {
            var p, r, k;
            return (
              ((r =
                (p = this[S]) === null || p === void 0
                  ? void 0
                  : p.destroyed) !== null && r !== void 0
                ? r
                : this.destroyed) &&
              !(!((k = this[Ct]) === null || k === void 0) && k.complete)
            );
          }
          get socket() {
            var p, r;
            return (r =
              (p = this[S]) === null || p === void 0 ? void 0 : p.socket) !==
              null && r !== void 0
              ? r
              : void 0;
          }
          get downloadProgress() {
            let p;
            return (
              this[z]
                ? (p = this[M] / this[z])
                : this[z] === this[M]
                  ? (p = 1)
                  : (p = 0),
              { percent: p, transferred: this[M], total: this[z] }
            );
          }
          get uploadProgress() {
            let p;
            return (
              this[$]
                ? (p = this[F] / this[$])
                : this[$] === this[F]
                  ? (p = 1)
                  : (p = 0),
              { percent: p, transferred: this[F], total: this[$] }
            );
          }
          get timings() {
            var p;
            return (p = this[S]) === null || p === void 0 ? void 0 : p.timings;
          }
          get isFromCache() {
            return this[te];
          }
          pipe(p, r) {
            if (this[_e])
              throw new Error(
                "Failed to pipe. The response has been emitted already.",
              );
            return (
              p instanceof n.ServerResponse && this[ee].add(p),
              super.pipe(p, r)
            );
          }
          unpipe(p) {
            return (
              p instanceof n.ServerResponse && this[ee].delete(p),
              super.unpipe(p),
              this
            );
          }
        }
        c.default = It;
      })(Ke)),
    Ke
  );
}
var xr;
function Be() {
  return (
    xr ||
      ((xr = 1),
      (function (c) {
        var u =
            (ce && ce.__createBinding) ||
            (Object.create
              ? function (n, d, R, b) {
                  (b === void 0 && (b = R),
                    Object.defineProperty(n, b, {
                      enumerable: !0,
                      get: function () {
                        return d[R];
                      },
                    }));
                }
              : function (n, d, R, b) {
                  (b === void 0 && (b = R), (n[b] = d[R]));
                }),
          s =
            (ce && ce.__exportStar) ||
            function (n, d) {
              for (var R in n)
                R !== "default" &&
                  !Object.prototype.hasOwnProperty.call(d, R) &&
                  u(d, n, R);
            };
        (Object.defineProperty(c, "__esModule", { value: !0 }),
          (c.CancelError = c.ParseError = void 0));
        const h = ze();
        class f extends h.RequestError {
          constructor(d, R) {
            const { options: b } = R.request;
            (super(`${d.message} in "${b.url.toString()}"`, d, R.request),
              (this.name = "ParseError"),
              (this.code =
                this.code === "ERR_GOT_REQUEST_ERROR"
                  ? "ERR_BODY_PARSE_FAILURE"
                  : this.code));
          }
        }
        c.ParseError = f;
        class i extends h.RequestError {
          constructor(d) {
            (super("Promise was canceled", {}, d),
              (this.name = "CancelError"),
              (this.code = "ERR_CANCELED"));
          }
          get isCanceled() {
            return !0;
          }
        }
        ((c.CancelError = i), s(ze(), c));
      })(ce)),
    ce
  );
}
var Ue = {},
  qr;
function Xs() {
  if (qr) return Ue;
  ((qr = 1), Object.defineProperty(Ue, "__esModule", { value: !0 }));
  const c = Be(),
    u = (s, h, f, i) => {
      const { rawBody: n } = s;
      try {
        if (h === "text") return n.toString(i);
        if (h === "json") return n.length === 0 ? "" : f(n.toString());
        if (h === "buffer") return n;
        throw new c.ParseError(
          { message: `Unknown body type '${h}'`, name: "Error" },
          s,
        );
      } catch (d) {
        throw new c.ParseError(d, s);
      }
    };
  return ((Ue.default = u), Ue);
}
var jr;
function Zr() {
  return (
    jr ||
      ((jr = 1),
      (function (c) {
        var u =
            (ae && ae.__createBinding) ||
            (Object.create
              ? function (a, O, P, v) {
                  (v === void 0 && (v = P),
                    Object.defineProperty(a, v, {
                      enumerable: !0,
                      get: function () {
                        return O[P];
                      },
                    }));
                }
              : function (a, O, P, v) {
                  (v === void 0 && (v = P), (a[v] = O[P]));
                }),
          s =
            (ae && ae.__exportStar) ||
            function (a, O) {
              for (var P in a)
                P !== "default" &&
                  !Object.prototype.hasOwnProperty.call(O, P) &&
                  u(O, a, P);
            };
        Object.defineProperty(c, "__esModule", { value: !0 });
        const h = We,
          f = ne(),
          i = ys(),
          n = Be(),
          d = Xs(),
          R = ze(),
          b = Qr(),
          m = Yr(),
          o = Xr(),
          t = [
            "request",
            "response",
            "redirect",
            "uploadProgress",
            "downloadProgress",
          ];
        function T(a) {
          let O, P;
          const v = new h.EventEmitter(),
            w = new i((E, l, e) => {
              const y = (x) => {
                const C = new R.default(void 0, a);
                ((C.retryCount = x),
                  (C._noPipe = !0),
                  e(() => C.destroy()),
                  (e.shouldReject = !1),
                  e(() => l(new n.CancelError(C))),
                  (O = C),
                  C.once("response", async (g) => {
                    var S;
                    if (((g.retryCount = x), g.request.aborted)) return;
                    let q;
                    try {
                      ((q = await m.default(C)), (g.rawBody = q));
                    } catch {
                      return;
                    }
                    if (C._isAboutToError) return;
                    const z = (
                        (S = g.headers["content-encoding"]) !== null &&
                        S !== void 0
                          ? S
                          : ""
                      ).toLowerCase(),
                      M = ["gzip", "deflate", "br"].includes(z),
                      { options: $ } = C;
                    if (M && !$.decompress) g.body = q;
                    else
                      try {
                        g.body = d.default(
                          g,
                          $.responseType,
                          $.parseJson,
                          $.encoding,
                        );
                      } catch (F) {
                        if (((g.body = q.toString()), o.isResponseOk(g))) {
                          C._beforeError(F);
                          return;
                        }
                      }
                    try {
                      for (const [F, ee] of $.hooks.afterResponse.entries())
                        g = await ee(g, async (G) => {
                          const te = R.default.normalizeArguments(
                            void 0,
                            {
                              ...G,
                              retry: { calculateDelay: () => 0 },
                              throwHttpErrors: !1,
                              resolveBodyOnly: !1,
                            },
                            $,
                          );
                          te.hooks.afterResponse = te.hooks.afterResponse.slice(
                            0,
                            F,
                          );
                          for (const _e of te.hooks.beforeRetry) await _e(te);
                          const ie = T(te);
                          return (
                            e(() => {
                              (ie.catch(() => {}), ie.cancel());
                            }),
                            ie
                          );
                        });
                    } catch (F) {
                      C._beforeError(new n.RequestError(F.message, F, C));
                      return;
                    }
                    if (((P = g), !o.isResponseOk(g))) {
                      C._beforeError(new n.HTTPError(g));
                      return;
                    }
                    (C.destroy(), E(C.options.resolveBodyOnly ? g.body : g));
                  }));
                const D = (g) => {
                  if (w.isCanceled) return;
                  const { options: S } = C;
                  if (g instanceof n.HTTPError && !S.throwHttpErrors) {
                    const { response: q } = g;
                    E(C.options.resolveBodyOnly ? q.body : q);
                    return;
                  }
                  l(g);
                };
                C.once("error", D);
                const I = C.options.body;
                (C.once("retry", (g, S) => {
                  var q, z;
                  if (
                    I ===
                      ((q = S.request) === null || q === void 0
                        ? void 0
                        : q.options.body) &&
                    f.default.nodeStream(
                      (z = S.request) === null || z === void 0
                        ? void 0
                        : z.options.body,
                    )
                  ) {
                    D(S);
                    return;
                  }
                  y(g);
                }),
                  b.default(C, v, t));
              };
              y(0);
            });
          w.on = (E, l) => (v.on(E, l), w);
          const _ = (E) => {
            const l = (async () => {
              await w;
              const { options: e } = P.request;
              return d.default(P, E, e.parseJson, e.encoding);
            })();
            return (
              Object.defineProperties(l, Object.getOwnPropertyDescriptors(w)),
              l
            );
          };
          return (
            (w.json = () => {
              const { headers: E } = O.options;
              return (
                !O.writableFinished &&
                  E.accept === void 0 &&
                  (E.accept = "application/json"),
                _("json")
              );
            }),
            (w.buffer = () => _("buffer")),
            (w.text = () => _("text")),
            w
          );
        }
        ((c.default = T), s(Be(), c));
      })(ae)),
    ae
  );
}
var De = {},
  Hr;
function Zs() {
  if (Hr) return De;
  ((Hr = 1), Object.defineProperty(De, "__esModule", { value: !0 }));
  const c = Be();
  function u(s, ...h) {
    const f = (async () => {
        if (s instanceof c.RequestError)
          try {
            for (const n of h) if (n) for (const d of n) s = await d(s);
          } catch (n) {
            s = n;
          }
        throw s;
      })(),
      i = () => f;
    return ((f.json = i), (f.text = i), (f.buffer = i), (f.on = i), f);
  }
  return ((De.default = u), De);
}
var Me = {},
  Ir;
function en() {
  if (Ir) return Me;
  ((Ir = 1), Object.defineProperty(Me, "__esModule", { value: !0 }));
  const c = ne();
  function u(s) {
    for (const h of Object.values(s))
      (c.default.plainObject(h) || c.default.array(h)) && u(h);
    return Object.freeze(s);
  }
  return ((Me.default = u), Me);
}
var Et = {},
  $r;
function tn() {
  return (
    $r || (($r = 1), Object.defineProperty(Et, "__esModule", { value: !0 })),
    Et
  );
}
var Lr;
function Ur() {
  return (
    Lr ||
      ((Lr = 1),
      (function (c) {
        var u =
            (oe && oe.__createBinding) ||
            (Object.create
              ? function (v, w, _, E) {
                  (E === void 0 && (E = _),
                    Object.defineProperty(v, E, {
                      enumerable: !0,
                      get: function () {
                        return w[_];
                      },
                    }));
                }
              : function (v, w, _, E) {
                  (E === void 0 && (E = _), (v[E] = w[_]));
                }),
          s =
            (oe && oe.__exportStar) ||
            function (v, w) {
              for (var _ in v)
                _ !== "default" &&
                  !Object.prototype.hasOwnProperty.call(w, _) &&
                  u(w, v, _);
            };
        (Object.defineProperty(c, "__esModule", { value: !0 }),
          (c.defaultHandler = void 0));
        const h = ne(),
          f = Zr(),
          i = Zs(),
          n = ze(),
          d = en(),
          R = {
            RequestError: f.RequestError,
            CacheError: f.CacheError,
            ReadError: f.ReadError,
            HTTPError: f.HTTPError,
            MaxRedirectsError: f.MaxRedirectsError,
            TimeoutError: f.TimeoutError,
            ParseError: f.ParseError,
            CancelError: f.CancelError,
            UnsupportedProtocolError: f.UnsupportedProtocolError,
            UploadError: f.UploadError,
          },
          b = async (v) =>
            new Promise((w) => {
              setTimeout(w, v);
            }),
          { normalizeArguments: m } = n.default,
          o = (...v) => {
            let w;
            for (const _ of v) w = m(void 0, _, w);
            return w;
          },
          t = (v) => (v.isStream ? new n.default(void 0, v) : f.default(v)),
          T = (v) => "defaults" in v && "options" in v.defaults,
          a = ["get", "post", "put", "patch", "head", "delete"];
        c.defaultHandler = (v, w) => w(v);
        const O = (v, w) => {
            if (v) for (const _ of v) _(w);
          },
          P = (v) => {
            ((v._rawHandlers = v.handlers),
              (v.handlers = v.handlers.map((E) => (l, e) => {
                let y;
                const x = E(l, (C) => ((y = e(C)), y));
                if (x !== y && !l.isStream && y) {
                  const C = x,
                    { then: D, catch: I, finally: g } = C;
                  (Object.setPrototypeOf(C, Object.getPrototypeOf(y)),
                    Object.defineProperties(
                      C,
                      Object.getOwnPropertyDescriptors(y),
                    ),
                    (C.then = D),
                    (C.catch = I),
                    (C.finally = g));
                }
                return x;
              })));
            const w = (E, l = {}, e) => {
              var y, x;
              let C = 0;
              const D = (I) =>
                v.handlers[C++](I, C === v.handlers.length ? t : D);
              if (h.default.plainObject(E)) {
                const I = { ...E, ...l };
                (n.setNonEnumerableProperties([E, l], I),
                  (l = I),
                  (E = void 0));
              }
              try {
                let I;
                try {
                  (O(v.options.hooks.init, l),
                    O(
                      (y = l.hooks) === null || y === void 0 ? void 0 : y.init,
                      l,
                    ));
                } catch (S) {
                  I = S;
                }
                const g = m(E, l, e ?? v.options);
                if (((g[n.kIsNormalizedAlready] = !0), I))
                  throw new f.RequestError(I.message, I, g);
                return D(g);
              } catch (I) {
                if (l.isStream) throw I;
                return i.default(
                  I,
                  v.options.hooks.beforeError,
                  (x = l.hooks) === null || x === void 0
                    ? void 0
                    : x.beforeError,
                );
              }
            };
            w.extend = (...E) => {
              const l = [v.options];
              let e = [...v._rawHandlers],
                y;
              for (const x of E)
                T(x)
                  ? (l.push(x.defaults.options),
                    e.push(...x.defaults._rawHandlers),
                    (y = x.defaults.mutableDefaults))
                  : (l.push(x),
                    "handlers" in x && e.push(...x.handlers),
                    (y = x.mutableDefaults));
              return (
                (e = e.filter((x) => x !== c.defaultHandler)),
                e.length === 0 && e.push(c.defaultHandler),
                P({ options: o(...l), handlers: e, mutableDefaults: !!y })
              );
            };
            const _ = async function* (E, l) {
              let e = m(E, l, v.options);
              e.resolveBodyOnly = !1;
              const y = e.pagination;
              if (!h.default.object(y))
                throw new TypeError("`options.pagination` must be implemented");
              const x = [];
              let { countLimit: C } = y,
                D = 0;
              for (; D < y.requestLimit;) {
                D !== 0 && (await b(y.backoff));
                const I = await w(void 0, void 0, e),
                  g = await y.transform(I),
                  S = [];
                for (const z of g)
                  if (
                    y.filter(z, x, S) &&
                    (!y.shouldContinue(z, x, S) ||
                      (yield z,
                      y.stackAllItems && x.push(z),
                      S.push(z),
                      --C <= 0))
                  )
                    return;
                const q = y.paginate(I, x, S);
                if (q === !1) return;
                (q === I.request.options
                  ? (e = I.request.options)
                  : q !== void 0 && (e = m(void 0, q, e)),
                  D++);
              }
            };
            ((w.paginate = _),
              (w.paginate.all = async (E, l) => {
                const e = [];
                for await (const y of _(E, l)) e.push(y);
                return e;
              }),
              (w.paginate.each = _),
              (w.stream = (E, l) => w(E, { ...l, isStream: !0 })));
            for (const E of a)
              ((w[E] = (l, e) => w(l, { ...e, method: E })),
                (w.stream[E] = (l, e) =>
                  w(l, { ...e, method: E, isStream: !0 })));
            return (
              Object.assign(w, R),
              Object.defineProperty(w, "defaults", {
                value: v.mutableDefaults ? v : d.default(v),
                writable: v.mutableDefaults,
                configurable: v.mutableDefaults,
                enumerable: !0,
              }),
              (w.mergeOptions = o),
              w
            );
          };
        ((c.default = P), s(tn(), c));
      })(oe)),
    oe
  );
}
var Ne = ge.exports,
  Dr;
function rn() {
  return (
    Dr ||
      ((Dr = 1),
      (function (c, u) {
        var s =
            (Ne && Ne.__createBinding) ||
            (Object.create
              ? function (R, b, m, o) {
                  (o === void 0 && (o = m),
                    Object.defineProperty(R, o, {
                      enumerable: !0,
                      get: function () {
                        return b[m];
                      },
                    }));
                }
              : function (R, b, m, o) {
                  (o === void 0 && (o = m), (R[o] = b[m]));
                }),
          h =
            (Ne && Ne.__exportStar) ||
            function (R, b) {
              for (var m in R)
                m !== "default" &&
                  !Object.prototype.hasOwnProperty.call(b, m) &&
                  s(b, R, m);
            };
        Object.defineProperty(u, "__esModule", { value: !0 });
        const f = Fe,
          i = Ur(),
          n = {
            options: {
              method: "GET",
              retry: {
                limit: 2,
                methods: ["GET", "PUT", "HEAD", "DELETE", "OPTIONS", "TRACE"],
                statusCodes: [408, 413, 429, 500, 502, 503, 504, 521, 522, 524],
                errorCodes: [
                  "ETIMEDOUT",
                  "ECONNRESET",
                  "EADDRINUSE",
                  "ECONNREFUSED",
                  "EPIPE",
                  "ENOTFOUND",
                  "ENETUNREACH",
                  "EAI_AGAIN",
                ],
                maxRetryAfter: void 0,
                calculateDelay: ({ computedValue: R }) => R,
              },
              timeout: {},
              headers: {
                "user-agent": "got (https://github.com/sindresorhus/got)",
              },
              hooks: {
                init: [],
                beforeRequest: [],
                beforeRedirect: [],
                beforeRetry: [],
                beforeError: [],
                afterResponse: [],
              },
              cache: void 0,
              dnsCache: void 0,
              decompress: !0,
              throwHttpErrors: !0,
              followRedirect: !0,
              isStream: !1,
              responseType: "text",
              resolveBodyOnly: !1,
              maxRedirects: 10,
              prefixUrl: "",
              methodRewriting: !0,
              ignoreInvalidCookies: !1,
              context: {},
              http2: !1,
              allowGetBody: !1,
              https: void 0,
              pagination: {
                transform: (R) =>
                  R.request.options.responseType === "json"
                    ? R.body
                    : JSON.parse(R.body),
                paginate: (R) => {
                  if (!Reflect.has(R.headers, "link")) return !1;
                  const b = R.headers.link.split(",");
                  let m;
                  for (const o of b) {
                    const t = o.split(";");
                    if (t[1].includes("next")) {
                      ((m = t[0].trimStart().trim()), (m = m.slice(1, -1)));
                      break;
                    }
                  }
                  return m ? { url: new f.URL(m) } : !1;
                },
                filter: () => !0,
                shouldContinue: () => !0,
                countLimit: 1 / 0,
                backoff: 0,
                requestLimit: 1e4,
                stackAllItems: !0,
              },
              parseJson: (R) => JSON.parse(R),
              stringifyJson: (R) => JSON.stringify(R),
              cacheOptions: {},
            },
            handlers: [i.defaultHandler],
            mutableDefaults: !1,
          },
          d = i.default(n);
        ((u.default = d),
          (c.exports = d),
          (c.exports.default = d),
          (c.exports.__esModule = !0),
          h(Ur(), u),
          h(Zr(), u));
      })(ge, ge.exports)),
    ge.exports
  );
}
var sn = rn();
const nn = cs(sn),
  Cn = nn.extend({ https: { rejectUnauthorized: ls } });
export { Br as a, Rs as b, Cn as g, Es as r };
//# sourceMappingURL=got-_wC7Q_ix.mjs.map
