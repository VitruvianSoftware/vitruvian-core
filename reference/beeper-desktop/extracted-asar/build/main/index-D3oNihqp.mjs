import { a as Y } from "./_commonjsHelpers-CBUqixCJ.mjs";
import k from "child_process";
import q from "crypto";
import G from "fs";
import K from "os";
import _ from "path";
import $ from "util";
(function () {
  try {
    var n =
      typeof window < "u"
        ? window
        : typeof global < "u"
          ? global
          : typeof globalThis < "u"
            ? globalThis
            : typeof self < "u"
              ? self
              : {};
    n.SENTRY_RELEASE = { id: "4.3.209" };
    var c = new n.Error().stack;
    c &&
      ((n._sentryDebugIds = n._sentryDebugIds || {}),
      (n._sentryDebugIds[c] = "239bfa5d-5f24-4154-bd68-6e02ce84427c"),
      (n._sentryDebugIdIdentifier =
        "sentry-dbid-239bfa5d-5f24-4154-bd68-6e02ce84427c"));
  } catch {}
})();
function AA(n, c) {
  for (var s = 0; s < c.length; s++) {
    const m = c[s];
    if (typeof m != "string" && !Array.isArray(m)) {
      for (const l in m)
        if (l !== "default" && !(l in n)) {
          const h = Object.getOwnPropertyDescriptor(m, l);
          h &&
            Object.defineProperty(
              n,
              l,
              h.get ? h : { enumerable: !0, get: () => m[l] },
            );
        }
    }
  }
  return Object.freeze(
    Object.defineProperty(n, Symbol.toStringTag, { value: "Module" }),
  );
}
var w = {},
  F;
function tA() {
  if (F) return w;
  F = 1;
  var n = { child: k, crypto: q, fs: G, os: K, path: _, process, util: $ };
  function c(A, t) {
    var e = n.process.platform;
    if (e === "darwin") return y(A, t);
    if (e === "linux") return l(A, t);
    if (e === "win32") return z(A, t);
    t(new Error("Platform not yet supported."));
  }
  function s(A) {
    if (typeof A != "string") throw new Error("Expected a string.");
    return A.replace(/"/g, '\\"');
  }
  function m() {
    if (arguments.length < 1 || arguments.length > 3)
      throw new Error("Wrong number of arguments.");
    var A = arguments[0],
      t = {},
      e = function () {};
    if (typeof A != "string") throw new Error("Command should be a string.");
    if (arguments.length === 2)
      if (n.util.isObject(arguments[1])) t = arguments[1];
      else if (n.util.isFunction(arguments[1])) e = arguments[1];
      else throw new Error("Expected options or callback.");
    else if (arguments.length === 3) {
      if (n.util.isObject(arguments[1])) t = arguments[1];
      else throw new Error("Expected options to be an object.");
      if (n.util.isFunction(arguments[2])) e = arguments[2];
      else throw new Error("Expected callback to be a function.");
    }
    if (/^sudo/i.test(A))
      return e(new Error('Command should not be prefixed with "sudo".'));
    if (typeof t.name > "u") {
      var r = n.process.title;
      if (b(r)) t.name = r;
      else return e(new Error("process.title cannot be used as a valid name."));
    } else if (!b(t.name)) {
      var o = "";
      return (
        (o += "options.name must be alphanumeric only "),
        (o += "(spaces are allowed) and <= 70 characters."),
        e(new Error(o))
      );
    }
    if (typeof t.icns < "u") {
      if (typeof t.icns != "string")
        return e(new Error("options.icns must be a string if provided."));
      if (t.icns.trim().length === 0)
        return e(new Error("options.icns must not be empty if provided."));
    }
    if (typeof t.env < "u") {
      if (typeof t.env != "object")
        return e(new Error("options.env must be an object if provided."));
      if (Object.keys(t.env).length === 0)
        return e(new Error("options.env must not be empty if provided."));
      for (var u in t.env) {
        var i = t.env[u];
        if (typeof u != "string" || typeof i != "string")
          return e(
            new Error("options.env environment variables must be strings."),
          );
        if (!/^[a-zA-Z_][a-zA-Z0-9_]*$/.test(u))
          return e(
            new Error(
              "options.env has an invalid environment variable name: " +
                JSON.stringify(u),
            ),
          );
        if (/[\r\n]/.test(i))
          return e(
            new Error(
              "options.env has an invalid environment variable value: " +
                JSON.stringify(i),
            ),
          );
      }
    }
    var f = n.process.platform;
    if (f !== "darwin" && f !== "linux" && f !== "win32")
      return e(new Error("Platform not yet supported."));
    var a = { command: A, options: t, uuid: void 0, path: void 0 };
    c(a, e);
  }
  function l(A, t) {
    h(A, function (e, r) {
      if (e) return t(e);
      var o = [];
      o.push('cd "' + s(n.process.cwd()) + '";');
      for (var u in A.options.env) {
        var i = A.options.env[u];
        o.push("export " + u + '="' + s(i) + '";');
      }
      (o.push('"' + s(r) + '"'),
        /kdesudo/i.test(r)
          ? (o.push(
              "--comment",
              '"' +
                A.options.name +
                ' wants to make changes. Enter your password to allow this."',
            ),
            o.push("-d"),
            o.push("--"))
          : /pkexec/i.test(r) && o.push("--disable-internal-agent"));
      var f = `SUDOPROMPT
`;
      (o.push('/bin/bash -c "echo ' + s(f.trim()) + "; " + s(A.command) + '"'),
        (o = o.join(" ")),
        n.child.exec(
          o,
          { encoding: "utf-8", maxBuffer: M },
          function (a, p, d) {
            var v = p && p.slice(0, f.length) === f;
            (v && (p = p.slice(f.length)),
              a &&
                !v &&
                (/No authentication agent found/.test(d)
                  ? (a.message = W)
                  : (a.message = E)),
              t(a, p, d));
          },
        ));
    });
  }
  function h(A, t) {
    var e = 0,
      r = ["/usr/bin/kdesudo", "/usr/bin/pkexec"];
    function o() {
      if (e === r.length)
        return t(new Error("Unable to find pkexec or kdesudo."));
      var u = r[e++];
      n.fs.stat(u, function (i) {
        if (i) {
          if (i.code === "ENOTDIR" || i.code === "ENOENT") return o();
          t(i);
        } else t(void 0, u);
      });
    }
    o();
  }
  function y(A, t) {
    var e = n.os.tmpdir();
    if (!e) return t(new Error("os.tmpdir() not defined."));
    var r = n.process.env.USER;
    if (!r) return t(new Error("env['USER'] not defined."));
    Q(A, function (o, u) {
      if (o) return t(o);
      ((A.uuid = u),
        (A.path = n.path.join(e, A.uuid, A.options.name + ".app")));
      function i(f, a, p) {
        V(n.path.dirname(A.path), function (d) {
          if (f) return t(f);
          if (d) return t(d);
          t(void 0, a, p);
        });
      }
      P(A, function (f, a, p) {
        if (f) return i(f, a, p);
        R(A, function (d) {
          if (d) return i(d);
          D(A, function (v, B, S) {
            if (v) return i(v, B, S);
            Z(A, function (X) {
              if (X) return i(X);
              x(A, function (U, J, I) {
                if (U) return i(U, J, I);
                j(A, i);
              });
            });
          });
        });
      });
    });
  }
  function P(A, t) {
    var e = n.path.dirname(A.path);
    n.fs.mkdir(e, function (r) {
      if (r) return t(r);
      var o = n.path.join(e, "sudo-prompt-applet.zip");
      n.fs.writeFile(o, T, "base64", function (u) {
        if (u) return t(u);
        var i = [];
        (i.push("/usr/bin/unzip"),
          i.push("-o"),
          i.push('"' + s(o) + '"'),
          i.push('-d "' + s(A.path) + '"'),
          (i = i.join(" ")),
          n.child.exec(i, { encoding: "utf-8" }, t));
      });
    });
  }
  function Z(A, t) {
    var e = n.path.join(A.path, "Contents", "MacOS", "sudo-prompt-command"),
      r = [];
    r.push('cd "' + s(n.process.cwd()) + '"');
    for (var o in A.options.env) {
      var u = A.options.env[o];
      r.push("export " + o + '="' + s(u) + '"');
    }
    (r.push(A.command),
      (r = r.join(`
`)),
      n.fs.writeFile(e, r, "utf-8", t));
  }
  function R(A, t) {
    if (!A.options.icns) return t();
    n.fs.readFile(A.options.icns, function (e, r) {
      if (e) return t(e);
      var o = n.path.join(A.path, "Contents", "Resources", "applet.icns");
      n.fs.writeFile(o, r, t);
    });
  }
  function x(A, t) {
    var e = n.path.join(A.path, "Contents", "MacOS", "applet"),
      r = { cwd: n.path.dirname(e), encoding: "utf-8" };
    n.child.exec("./" + n.path.basename(e), r, t);
  }
  function D(A, t) {
    var e = n.path.join(A.path, "Contents", "Info.plist"),
      r = s(e),
      o = s("CFBundleName"),
      u = A.options.name + " Password Prompt";
    if (/'/.test(u))
      return t(new Error("Value should not contain single quotes."));
    var i = [];
    (i.push("/usr/bin/defaults"),
      i.push("write"),
      i.push('"' + r + '"'),
      i.push('"' + o + '"'),
      i.push("'" + u + "'"),
      (i = i.join(" ")),
      n.child.exec(i, { encoding: "utf-8" }, t));
  }
  function j(A, t) {
    var e = n.path.join(A.path, "Contents", "MacOS");
    n.fs.readFile(n.path.join(e, "code"), "utf-8", function (r, o) {
      if (r) {
        if (r.code === "ENOENT") return t(new Error(E));
        t(r);
      } else
        n.fs.readFile(n.path.join(e, "stdout"), "utf-8", function (u, i) {
          if (u) return t(u);
          n.fs.readFile(n.path.join(e, "stderr"), "utf-8", function (f, a) {
            if (f) return t(f);
            ((o = parseInt(o.trim(), 10)),
              o === 0
                ? t(void 0, i, a)
                : ((f = new Error(
                    "Command failed: " +
                      A.command +
                      `
` +
                      a,
                  )),
                  (f.code = o),
                  t(f, i, a)));
          });
        });
    });
  }
  function V(A, t) {
    if (typeof A != "string" || !A.trim())
      return t(new Error("Argument path not defined."));
    var e = [];
    if (n.process.platform === "win32") {
      if (/"/.test(A))
        return t(new Error("Argument path cannot contain double-quotes."));
      e.push('rmdir /s /q "' + A + '"');
    } else
      (e.push("/bin/rm"),
        e.push("-rf"),
        e.push('"' + s(n.path.normalize(A)) + '"'));
    ((e = e.join(" ")), n.child.exec(e, { encoding: "utf-8" }, t));
  }
  function Q(A, t) {
    n.crypto.randomBytes(256, function (e, r) {
      e && (r = Date.now() + "" + Math.random());
      var o = n.crypto.createHash("SHA256");
      (o.update("sudo-prompt-3"),
        o.update(A.options.name),
        o.update(A.command),
        o.update(r));
      var u = o.digest("hex").slice(-32);
      if (!u || typeof u != "string" || u.length !== 32)
        return t(new Error("Expected a valid UUID."));
      t(void 0, u);
    });
  }
  function b(A) {
    return !(
      !/^[a-z0-9 ]+$/i.test(A) ||
      A.trim().length === 0 ||
      A.length > 70
    );
  }
  function z(A, t) {
    var e = n.os.tmpdir();
    if (!e) return t(new Error("os.tmpdir() not defined."));
    Q(A, function (r, o) {
      if (r) return t(r);
      if (((A.uuid = o), (A.path = n.path.join(e, A.uuid)), /"/.test(A.path)))
        return t(new Error("instance.path cannot contain double-quotes."));
      ((A.pathElevate = n.path.join(A.path, "elevate.vbs")),
        (A.pathExecute = n.path.join(A.path, "execute.bat")),
        (A.pathCommand = n.path.join(A.path, "command.bat")),
        (A.pathStdout = n.path.join(A.path, "stdout")),
        (A.pathStderr = n.path.join(A.path, "stderr")),
        (A.pathStatus = n.path.join(A.path, "status")),
        n.fs.mkdir(A.path, function (u) {
          if (u) return t(u);
          function i(f, a, p) {
            V(A.path, function (d) {
              if (f) return t(f);
              if (d) return t(d);
              t(void 0, a, p);
            });
          }
          H(A, function (f) {
            if (f) return i(f);
            L(A, function (a) {
              if (a) return i(a);
              O(A, function (p, d, v) {
                if (p) return i(p, d, v);
                g(A, function (B) {
                  if (B) return i(B);
                  C(A, i);
                });
              });
            });
          });
        }));
    });
  }
  function O(A, t) {
    var e = [];
    (e.push("powershell.exe"),
      e.push("Start-Process"),
      e.push("-FilePath"),
      e.push(`"'` + A.pathExecute.replace(/'/g, "`'") + `'"`),
      e.push("-WindowStyle hidden"),
      e.push("-Verb runAs"),
      (e = e.join(" ")));
    var r = n.child.exec(e, { encoding: "utf-8" }, function (o, u, i) {
      if (o) return t(new Error(E), u, i);
      t();
    });
    r.stdin.end();
  }
  function C(A, t) {
    n.fs.readFile(A.pathStatus, "utf-8", function (e, r) {
      if (e) return t(e);
      n.fs.readFile(A.pathStdout, "utf-8", function (o, u) {
        if (o) return t(o);
        n.fs.readFile(A.pathStderr, "utf-8", function (i, f) {
          if (i) return t(i);
          ((r = parseInt(r.trim(), 10)),
            r === 0
              ? t(void 0, u, f)
              : ((i = new Error(
                  "Command failed: " +
                    A.command +
                    `\r
` +
                    f,
                )),
                (i.code = r),
                t(i, u, f)));
        });
      });
    });
  }
  function g(A, t) {
    n.fs.stat(A.pathStatus, function (e, r) {
      (e && e.code === "ENOENT") || r.size < 2
        ? setTimeout(function () {
            n.fs.stat(A.pathStdout, function (o) {
              if (o) return t(new Error(E));
              g(A, t);
            });
          }, 1e3)
        : e
          ? t(e)
          : t();
    });
  }
  function L(A, t) {
    var e = n.process.cwd();
    if (/"/.test(e))
      return t(new Error("process.cwd() cannot contain double-quotes."));
    var r = [];
    (r.push("@echo off"),
      r.push("chcp 65001>nul"),
      r.push('cd /d "' + e + '"'));
    for (var o in A.options.env) {
      var u = A.options.env[o];
      r.push("set " + o + "=" + u.replace(/([<>\\|&^])/g, "^$1"));
    }
    (r.push(A.command),
      (r = r.join(`\r
`)),
      n.fs.writeFile(A.pathCommand, r, "utf-8", t));
  }
  function H(A, t) {
    var e = [];
    (e.push("@echo off"),
      e.push(
        'call "' +
          A.pathCommand +
          '" > "' +
          A.pathStdout +
          '" 2> "' +
          A.pathStderr +
          '"',
      ),
      e.push('(echo %ERRORLEVEL%) > "' + A.pathStatus + '"'),
      (e = e.join(`\r
`)),
      n.fs.writeFile(A.pathExecute, e, "utf-8", t));
  }
  w.exec = m;
  var T =
      "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",
    E = "User did not grant permission.",
    W = "No polkit authentication agent found.",
    M = 134217728;
  return w;
}
var N = tA();
const eA = Y(N),
  sA = AA({ __proto__: null, default: eA }, [N]);
export { sA as i };
//# sourceMappingURL=index-D3oNihqp.mjs.map
