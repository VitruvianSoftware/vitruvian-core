import { a as A } from "./_commonjsHelpers-CBUqixCJ.mjs";
import N from "events";
import T from "node:module";
(function () {
  try {
    var o =
      typeof window < "u"
        ? window
        : typeof global < "u"
          ? global
          : typeof globalThis < "u"
            ? globalThis
            : typeof self < "u"
              ? self
              : {};
    o.SENTRY_RELEASE = { id: "4.3.209" };
    var a = new o.Error().stack;
    a &&
      ((o._sentryDebugIds = o._sentryDebugIds || {}),
      (o._sentryDebugIds[a] = "9523dd58-aa16-4b05-aab6-9f9ccf36c632"),
      (o._sentryDebugIdIdentifier =
        "sentry-dbid-9523dd58-aa16-4b05-aab6-9f9ccf36c632"));
  } catch {}
})();
const $ = import.meta.filename,
  x = import.meta.dirname,
  j = T.createRequire(import.meta.url);
function P(o, a) {
  for (var s = 0; s < a.length; s++) {
    const c = a[s];
    if (typeof c != "string" && !Array.isArray(c)) {
      for (const e in c)
        if (e !== "default" && !(e in o)) {
          const f = Object.getOwnPropertyDescriptor(c, e);
          f &&
            Object.defineProperty(
              o,
              e,
              f.get ? f : { enumerable: !0, get: () => c[e] },
            );
        }
    }
  }
  return Object.freeze(
    Object.defineProperty(o, Symbol.toStringTag, { value: "Module" }),
  );
}
var m = { exports: {} },
  l;
function O() {
  return (
    l ||
      ((l = 1),
      (() => {
        var o = {
            750: (e, f, d) => {
              const r = j(d.ab + "build/Release/contacts.node"),
                { EventEmitter: b } = d(434),
                u = new b();
              ((u.setup = () => {
                r.setupListener(u.emit.bind(u));
              }),
                (u.remove = () => {
                  r.removeListener();
                }),
                (u.isListening = () => r.isListening()));
              const p = [
                "jobTitle",
                "departmentName",
                "organizationName",
                "middleName",
                "note",
                "contactImage",
                "contactThumbnailImage",
                "instantMessageAddresses",
                "socialProfiles",
              ];
              function w(t = []) {
                if (!Array.isArray(t))
                  throw new TypeError("extraProperties must be an array");
                if (!t.every((i) => p.includes(i)))
                  throw new TypeError(
                    `properties in extraProperties must be one of ${p.join(", ")}`,
                  );
                return r.getAllContacts.call(this, t);
              }
              function h(t, i = []) {
                if (typeof t != "string")
                  throw new TypeError("name must be a string");
                if (!Array.isArray(i))
                  throw new TypeError("extraProperties must be an array");
                if (!i.every((n) => p.includes(n)))
                  throw new TypeError(
                    `properties in extraProperties must be one of ${p.join(", ")}`,
                  );
                return r.getContactsByName.call(this, t, i);
              }
              function y(t) {
                if (!t || Object.keys(t).length === 0)
                  throw new TypeError("contact must be a non-empty object");
                for (const n of [
                  "firstName",
                  "middleName",
                  "lastName",
                  "nickname",
                  "jobTitle",
                  "departmentName",
                  "organizationName",
                ])
                  if (t.hasOwnProperty(n) && typeof t[n] != "string")
                    throw new TypeError(`${n} must be a string`);
                for (const n of ["phoneNumbers", "emailAddresses"])
                  if (t.hasOwnProperty(n) && !Array.isArray(t[n]))
                    throw new TypeError(`${n} must be an array`);
                if (t.hasOwnProperty("birthday")) {
                  const n =
                    /^\d{4}\-(0[1-9]|1[012])\-(0[1-9]|[12][0-9]|3[01])$/;
                  if (typeof t.birthday != "string")
                    throw new TypeError("birthday must be a string");
                  if (!t.birthday.match(n))
                    throw new Error("birthday must use YYYY-MM-DD format");
                }
              }
              function C(t) {
                return (y(t), r.addNewContact.call(this, t));
              }
              function _(t) {
                return (y(t), r.updateContact.call(this, t));
              }
              function E(t) {
                if (!t || Object.keys(t).length === 0)
                  throw new TypeError("contact must be a non-empty object");
                const i = t.hasOwnProperty("identifier"),
                  n = t.hasOwnProperty("name");
                if (i && typeof t.identifier != "string")
                  throw new TypeError("identifier must be a string");
                if (n && typeof t.name != "string")
                  throw new TypeError("name must be a string");
                return r.deleteContact.call(this, t);
              }
              e.exports = {
                listener: u,
                requestAccess: r.requestAccess,
                getAuthStatus: r.getAuthStatus,
                getContactImage: r.getContactImage,
                getAllContacts: w,
                getContactsByName: h,
                addNewContact: C,
                deleteContact: E,
                updateContact: _,
              };
            },
            434: (e) => {
              e.exports = N;
            },
          },
          a = {};
        function s(e) {
          var f = a[e];
          if (f !== void 0) return f.exports;
          var d = (a[e] = { exports: {} }),
            r = !0;
          try {
            (o[e](d, d.exports, s), (r = !1));
          } finally {
            r && delete a[e];
          }
          return d.exports;
        }
        typeof s < "u" && (s.ab = x + "/");
        var c = s(750);
        m.exports = c;
      })()),
    m.exports
  );
}
var g = O();
const I = A(g),
  k = P({ __proto__: null, default: I }, [g]);
export { k as i, I as n };
//# sourceMappingURL=index-8JaOpgio.mjs.map
