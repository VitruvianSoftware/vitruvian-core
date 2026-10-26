# Copyright (c) 2026 VitruvianSoftware
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

"""//tools/delivery/orchestrate (Rust) against :orchestrate-go, side by side.

Every case runs both binaries the way CI does (`orchestrate --out ...` from a
repo root) over the same scratch git repo, the same fake bazel and the same
decision engine, and requires the same exit code, stdout, stderr, manifest
bytes and $GITHUB_OUTPUT bytes.

The engine is the REAL tools/ci/deploy-affected.sh (committed into each
scratch repo at the path the binary resolves) for every main_test.go
scenario, and a stub engine for the shapes the real one never prints (a
signal, no verdict line, odd reasons). The metadata cases go well past
main_test.go: the manifest quotes Go's JSON decoder errors, so each syntax
and type error Go can report is exercised.
"""

import os
import shutil
import stat
import subprocess
import tempfile
import unittest

HERE = os.getcwd()
GO = os.path.join(HERE, os.environ["ORCHESTRATE_GO"])
RS = os.path.join(HERE, os.environ["ORCHESTRATE_RS"])
ENGINE = os.path.join(HERE, os.environ["DEPLOY_AFFECTED"])
TD_LIB = os.path.join(HERE, os.environ["TD_LIB"])

ROOT = tempfile.mkdtemp(prefix="orch-parity-", dir=os.environ.get("TEST_TMPDIR"))
ROOT = os.path.realpath(ROOT)
GIT_ENV = {
    "GIT_CONFIG_GLOBAL": "/dev/null",
    "GIT_CONFIG_NOSYSTEM": "1",
    "PATH": os.environ.get("PATH", "/usr/bin:/bin"),
    "HOME": ROOT,
}


def git(d, *args):
    return subprocess.run(
        ["git", *args], cwd=d, env=GIT_ENV, check=True, capture_output=True, text=True
    ).stdout.strip()


def write(path, content, mode=0o644):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(content.encode() if isinstance(content, str) else content)
    os.chmod(path, mode)


STUB_ENGINE = """#!/usr/bin/env bash
# A stand-in engine; STUB_MODE comes through EXTRA_PATH_REGEX.
echo "stub: DEPLOY_TARGETS=[${DEPLOY_TARGETS-<unset>}] BEFORE_REV=[${BEFORE_REV}] FORCED_PUSH=[${FORCED_PUSH-<unset>}]"
echo "stub: EXTRA=[${EXTRA_PATH_REGEX}] EXCLUDE=[${EXCLUDE_PATH_REGEX}] LEAK=[${LEAKY-<unset>}]"
case "${EXTRA_PATH_REGEX}" in
  exit3) echo "deploy-affected: affected=true (about to fail)"; exit 3 ;;
  signal) echo "dying" >&2; kill -TERM $$ ;;
  noverdict) echo "nothing to say" ;;
  garbage) echo "affected=maybe" >> "$GITHUB_OUTPUT" ;;
  twice) echo "affected=true" >> "$GITHUB_OUTPUT"; echo "  affected=false  " >> "$GITHUB_OUTPUT"
         echo "deploy-affected: affected=false (first (nested) reason)"; echo "deploy-affected: affected=true (second)" ;;
  interleave) for i in 1 2 3; do echo "out $i"; echo "err $i" >&2; done
              echo "deploy-affected: affected=true (<html> & \\"quotes\\" \\u2028)"; echo "affected=true" >> "$GITHUB_OUTPUT" ;;
  tabs) printf 'deploy-affected: affected=false (a\\tb  c\\r)\\n'; printf 'x\\r\\n\\n\\n'; echo "affected=false" >> "$GITHUB_OUTPUT" ;;
  unicode) echo "deploy-affected: affected=true (héllo wörld — ✓ 日本)"; echo "affected=true" >> "$GITHUB_OUTPUT" ;;
  nonl) printf 'deploy-affected: affected=true (no newline)'; echo "affected=true" >> "$GITHUB_OUTPUT" ;;
  empty) echo "affected=false" >> "$GITHUB_OUTPUT" ;;
  badverdict) echo "deploy-affected: affected=TRUE (caps)"; echo "affected=TRUE" >> "$GITHUB_OUTPUT" ;;
  *) echo "deploy-affected: affected=false (stub ok)"; echo "affected=false" >> "$GITHUB_OUTPUT" ;;
esac
"""


def new_repo(name, touched, engine=None):
    d = os.path.join(ROOT, "repos", name)
    os.makedirs(d)
    git(d, "-c", "init.defaultBranch=main", "init")
    git(d, "config", "user.email", "test@example.com")
    git(d, "config", "user.name", "Test")
    write(os.path.join(d, "README.md"), "init\n")
    if engine is None:
        os.makedirs(os.path.join(d, "tools/ci"))
        shutil.copy(ENGINE, os.path.join(d, "tools/ci/deploy-affected.sh"))
        shutil.copy(TD_LIB, os.path.join(d, "tools/ci/td-lib.sh"))
    else:
        write(os.path.join(d, "tools/ci/deploy-affected.sh"), engine, 0o755)
    git(d, "add", ".")
    git(d, "commit", "-m", "test: initial commit")
    base = git(d, "rev-parse", "HEAD")
    write(os.path.join(d, touched), "changed\n")
    git(d, "add", ".")
    git(d, "commit", "-m", "test: touch " + touched)
    return d, base


REPOS = {
    "declared": new_repo("declared", "oauth-user-inspector/infra/app/main.go"),
    "undeclared": new_repo("undeclared", "docs/notes.md"),
    "excluded": new_repo("excluded", "oauth-user-inspector/infra/identity/main.go"),
    "global": new_repo("global-impact", "MODULE.bazel"),
    "stub": new_repo("stub", "docs/notes.md", engine=STUB_ENGINE),
}


def decl(name, **over):
    m = {
        "schema": 1,
        "name": name,
        "kind": "cloud-run",
        "run": "//%s/infra/app:deploy" % name,
        "build": "",
        "environments": ["development", "nonproduction", "production"],
        "github_environment": name + "-{env}",
        "promotion": "release:%s-v" % name,
        "companions": [],
        "extra_paths": [],
        "exclude_paths": [],
        "preflight": "",
        "package": name + "/infra/app",
    }
    m.update(over)
    return m


def to_json(m):
    import json

    return json.dumps(m, indent=2)


def sh_quote(s):
    return "'" + s.replace("'", "'\\''") + "'"


class Case:
    """One scenario: metadata in a bazel-bin, a fake bazel, an environment."""

    _n = 0

    def __init__(
        self,
        repo="undeclared",
        units=(),
        raw=(),
        labels=None,
        fail_query=False,
        fail_build=False,
        fail_info=False,
        info=None,
        query_stderr=None,
        env=None,
        args=("--out", "delivery-manifest.json"),
        cwd="repo",
        shebang="#!/usr/bin/env bash",
        bazel_via="flag",
        gh_output="file",
    ):
        Case._n += 1
        self.dir = os.path.join(ROOT, "cases", str(Case._n))
        self.bin = os.path.join(self.dir, "bazel-bin")
        os.makedirs(self.bin)
        found = []
        for m in units:
            pkg, name = m.get("package", ""), m.get("name", "")
            write(os.path.join(self.bin, pkg, name + ".delivery.json"), to_json(m))
            found.append("//%s:%s.delivery_unit" % (pkg, name))
        for label, rel, content in raw:
            write(os.path.join(self.bin, rel), content)
            found.append(label)
        self.labels = found if labels is None else labels
        query = "true"
        if self.labels:
            query = "printf '%s\\n' " + " ".join(sh_quote(l) for l in self.labels)
        if fail_query:
            query = "echo %s >&2; exit 1" % sh_quote(
                query_stderr or "ERROR: package contains errors"
            )
        build = (
            "echo 'ERROR: analysis   of\n  target failed' >&2; exit 1"
            if fail_build
            else "true"
        )
        info_out = self.bin if info is None else info
        info_cmd = (
            "echo 'no info' >&2; exit 2"
            if fail_info
            else "echo %s" % sh_quote(info_out)
        )
        self.fake = os.path.join(self.dir, "fake-bazel")
        write(
            self.fake,
            shebang
            + '\nset -uo pipefail\ncase "${1:-}" in\n  query) %s ;;\n  build) %s ;;\n  info)  %s ;;\n'
            '  *) echo "fake bazel: unexpected invocation: $*" >&2; exit 64 ;;\nesac\n'
            % (query, build, info_cmd),
            0o755,
        )
        self.repo, self.base = REPOS[repo]
        self.env = env or {}
        self.args = list(args)
        self.cwd = cwd
        self.bazel_via = bazel_via
        self.gh_output = gh_output


def run(binary, case):
    work = os.path.join(case.dir, "work")
    shutil.rmtree(work, ignore_errors=True)
    os.makedirs(work)
    gh = os.path.join(work, "github_output")
    if case.gh_output == "file":
        write(gh, "")
    elif case.gh_output == "dir":
        os.makedirs(gh)
    env = {
        "PATH": os.environ.get("PATH", "/usr/bin:/bin"),
        "HOME": work,
        "TMPDIR": work,
        "GIT_CONFIG_GLOBAL": os.path.join(work, "nonexistent-gitconfig"),
        "GIT_CONFIG_SYSTEM": os.path.join(work, "nonexistent-gitconfig"),
        "BEFORE_REV": case.base,
        "GITHUB_OUTPUT": gh,
        "LEAKY": "should-not-reach-the-engine",
        "DEPLOY_TARGETS": "//leaked:target",
    }
    args = list(case.args)
    if case.bazel_via == "flag":
        args = ["--bazel", case.fake] + args
    elif case.bazel_via == "env":
        env["ORCHESTRATE_BAZEL"] = case.fake
    cwd = case.repo
    if case.cwd == "elsewhere":
        cwd = work
        env["BUILD_WORKSPACE_DIRECTORY"] = case.repo
    elif case.cwd == "symlink":
        link = os.path.join(work, "repo-link")
        os.symlink(case.repo, link)
        cwd = link
    env["PWD"] = cwd
    for k, v in case.env.items():
        if v is None:
            env.pop(k, None)
        else:
            env[k] = v.replace("@WORK@", work).replace("@FAKE@", case.fake)
    args = [a.replace("@WORK@", work) for a in args]
    p = subprocess.run(
        [binary] + args, cwd=cwd, env=env, capture_output=True, timeout=120
    )
    files = {}
    for root, _, names in os.walk(work):
        for n in names:
            path = os.path.join(root, n)
            if os.path.islink(path):
                continue
            with open(path, "rb") as f:
                files[os.path.relpath(path, work)] = f.read()
    manifest = None
    mp = os.path.join(case.repo, "delivery-manifest.json")
    if os.path.exists(mp):
        with open(mp, "rb") as f:
            manifest = f.read()
        os.remove(mp)
    return {
        "code": p.returncode,
        "stdout": p.stdout,
        "stderr": p.stderr,
        "files": files,
        "repo-manifest": manifest,
    }


def u(name="oauth-user-inspector", **over):
    over.setdefault("extra_paths", ["oauth-user-inspector/", "tools/deploy/"])
    return decl(name, **over)


def meta_case(text, label="//p/q:m.delivery_unit", rel="p/q/m.delivery.json"):
    return Case(raw=[(label, rel, text)])


def cases():
    c = {}
    # --- main_test.go: happy paths, with the real engine -------------------
    c["path_match_affected"] = Case("declared", [u()])
    c["no_path_match"] = Case("undeclared", [u()])
    c["exclude_paths"] = Case(
        "excluded",
        [
            u(
                extra_paths=["oauth-user-inspector/"],
                exclude_paths=["oauth-user-inspector/infra/identity/"],
            )
        ],
    )
    c["graph_mode_build"] = Case(
        "global",
        [
            u(
                build="//oauth-user-inspector:image",
                extra_paths=["oauth-user-inspector/"],
            )
        ],
    )
    c["graph_targets"] = Case(
        "global",
        [
            decl(
                "tabula-api",
                build="",
                shared_build="tabula",
                graph_targets=[
                    "//tabula/api:image_push",
                    "//tabula/extension:chrome_zip",
                ],
                extra_paths=["tabula/infra/app/"],
            )
        ],
    )
    two = [
        decl("oauth-user-inspector", extra_paths=["oauth-user-inspector/"]),
        decl("tabula-api", extra_paths=["tabula/api/"]),
    ]
    c["two_units"] = Case("declared", two)
    c["filter_named"] = Case("declared", two, env={"ORCHESTRATE_UNITS": "tabula-api"})
    c["filter_unknown"] = Case(
        "declared", two, env={"ORCHESTRATE_UNITS": "tabula-api ghost"}
    )
    c["filter_query_fails"] = Case(
        "declared",
        two,
        fail_query=True,
        env={"ORCHESTRATE_UNITS": "oauth-user-inspector tabula-api"},
    )
    c["filter_whitespace_dupes"] = Case(
        "declared",
        two,
        env={"ORCHESTRATE_UNITS": "\t tabula-api\n tabula-api  ghost ghost2 "},
    )
    c["filter_spaces_only"] = Case("declared", two, env={"ORCHESTRATE_UNITS": "   "})
    # --- main_test.go: fail-open rows ------------------------------------------
    c["unresolvable_before"] = Case(
        "undeclared",
        [u()],
        env={"BEFORE_REV": "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef"},
    )
    c["no_base"] = Case("undeclared", [u()], env={"BEFORE_REV": None, "BASE_REF": None})
    c["empty_bases"] = Case(
        "undeclared", [u()], env={"BEFORE_REV": "  ", "BASE_REF": "\t"}
    )
    c["base_ref_fallback"] = Case(
        "declared", [u()], env={"BEFORE_REV": None, "BASE_REF": REPOS["declared"][1]}
    )
    c["base_padded"] = Case(
        "declared", [u()], env={"BEFORE_REV": "  " + REPOS["declared"][1] + " \n"}
    )
    c["base_symbolic"] = Case("declared", [u()], env={"BEFORE_REV": "HEAD~1"})
    c["base_quoted"] = Case("declared", [u()], env={"BEFORE_REV": 'no"such<ref>é\t'})
    c["forced_push"] = Case("undeclared", [u()], env={"FORCED_PUSH": "true"})
    c["forced_push_other"] = Case("declared", [u()], env={"FORCED_PUSH": "TRUE"})
    c["query_fails"] = Case("undeclared", [u()], fail_query=True)
    c["query_fails_multiline"] = Case(
        "undeclared",
        [u()],
        fail_query=True,
        query_stderr="ERROR:  one\n\n  two\tthree  ",
    )
    c["build_fails"] = Case("undeclared", [u()], fail_build=True)
    c["info_fails"] = Case("undeclared", [u()], fail_info=True)
    c["info_empty"] = Case("undeclared", [u()], info="")
    c["info_padded"] = Case("declared", [u()], info=None)
    c["metadata_unparsable"] = meta_case("{ this is not json")
    c["metadata_missing"] = Case(
        "undeclared", labels=["//some/pkg:ghost.delivery_unit"]
    )
    c["engine_non_zero"] = Case(
        "undeclared",
        [
            decl("tabula-api", extra_paths=["tabula/api/"]),
            decl("no-signal", extra_paths=[]),
        ],
    )
    c["empty_universe"] = Case("undeclared")
    # --- per-unit bases ------------------------------------------------------------
    head = git(REPOS["declared"][0], "rev-parse", "HEAD")
    for name, raw in {
        "override": '{"oauth-user-inspector":"%s"}' % head,
        "unresolvable": '{"oauth-user-inspector":"0000000000000000000000000000000000000000"}',
        "malformed": "{not json",
        "null": "null",
        "array": '["x"]',
        "number_value": '{"oauth-user-inspector":1}',
        "null_value": '{"oauth-user-inspector":null}',
        "empty_value": '{"oauth-user-inspector":""}',
        "dupes": '{"oauth-user-inspector":"nope","oauth-user-inspector":"%s"}' % head,
        "case": '{"OAUTH-USER-INSPECTOR":"%s"}' % head,
        "symbolic": '{"oauth-user-inspector":"HEAD"}',
        "trailing": '{"oauth-user-inspector":"%s"} x' % head,
    }.items():
        c["unit_bases_" + name] = Case("declared", [u()], env={"UNIT_BASES_JSON": raw})
    # --- labels ----------------------------------------------------------------------
    c["labels_shapes"] = Case(
        "undeclared",
        raw=[
            (
                "@@//a/b:c.delivery_unit",
                "a/b/c.delivery.json",
                to_json(decl("c", extra_paths=["a/"])),
            ),
            (
                "@//d/e:f.delivery_unit",
                "d/e/f.delivery.json",
                to_json(decl("f", extra_paths=["d/"])),
            ),
            ("//g/h", "g/h/h.delivery.json", to_json(decl("h", extra_paths=["g/"]))),
            (
                "//i/j:weird",
                "i/j/weird.delivery.json",
                to_json(decl("weird", extra_paths=["i/"])),
            ),
            (
                "@repo//k/l:m.delivery_unit",
                "repo/k/l/m.delivery.json",
                to_json(decl("m", extra_paths=["k/"])),
            ),
        ],
    )
    c["label_empty_target"] = Case("undeclared", labels=["//a/b:"])
    c["label_bare_slashes"] = Case("undeclared", labels=["//"])
    c["label_padded_lines"] = Case(
        "undeclared", labels=["", "  //x:y.delivery_unit  ", ""]
    )
    # --- metadata decoding: Go's syntax errors ----------------------------------------
    for i, text in enumerate(
        [
            "",
            " ",
            "{",
            "[",
            "-",
            "1.",
            "1e",
            "1e+",
            "tru",
            "fx",
            "nul",
            "nulL",
            "{}x",
            "[1 2]",
            '{"a" 1}',
            '{"a":1 2}',
            '"\\q"',
            '"\\u12x4"',
            '"a\nb"',
            "'",
            "\x00",
            "\xc3\xa9",
            "\x80",
            '{"name":"x",}',
            "[,]",
            '{"name":"x"}}',
            "01",
            "-01",
            ".5",
            "+1",
            '{"a":[1,]}',
            '"\\',
            '"\\u',
            '{"name":"x"',
            '{"\x7f":1}',
            '{"name":"tab\there"}',
            "{,}",
            "﻿{}",
        ]
    ):
        c["meta_syntax_%02d" % i] = meta_case(text)
    # --- metadata decoding: Go's struct rules ----------------------------------------
    for i, text in enumerate(
        [
            "null",
            "[]",
            '"x"',
            "1",
            "true",
            "{}",
            '{"name":""}',
            '{"name":null}',
            '{"name":3}',
            '{"name":true}',
            '{"name":[]}',
            '{"name":{}}',
            '{"name":"x","schema":"1"}',
            '{"name":"x","schema":1.5}',
            '{"name":"x","schema":1e2}',
            '{"name":"x","schema":99999999999999999999}',
            '{"name":"x","schema":-0}',
            '{"name":"x","schema":true}',
            '{"name":"x","schema":-9223372036854775808}',
            '{"name":"x","schema":9223372036854775808}',
            '{"name":"x","environments":"dev"}',
            '{"name":"x","environments":[1]}',
            '{"name":"x","environments":[[]]}',
            '{"name":"x","environments":{}}',
            '{"name":"x","environments":null}',
            '{"name":"x","environments":[null,"a"]}',
            '{"name":"x","environments":["a","b","c"],"environments":["z",null]}',
            '{"name":"x","environments":["a","b","c","d","e"],"environments":[null,null,null,null,null,null,null]}',
            '{"NAME":"upper","Kind":"k","GITHUB_ENVIRONMENT":"g","name":"lower"}',
            '{"na\\u006de":"escaped key","unknown":{"deep":[1,{"x":null}]},"schema":2}',
            '{"name":"ſchema-key","ſchema":5,"Kind":"kelvin"}',
            '{"name":"x","schema":"bad","kind":7,"run":false}',
            '{"name":"<b>&amp;</b>\\u2028\\u2029","run":"\\ud83d\\ude00 \\ud800 \\udc00x \\ud800\\u0041","kind":"\\u0001\\b\\f\\n\\r\\t\\/"}',
            '{"name":"inv\xff\xfeutf8","kind":"\xe2\x82"}',
            '{"name":"a\\tb","kind":"tab name"}',
            '{"name":"x\\ny","kind":"newline name"}',
            '{"name":"wide—名前","kind":"unicode"}',
            '{"name":"x","companions":["a"],"graph_targets":[],"preflight":"p","promotion":"q"}',
        ]
    ):
        c["meta_decode_%02d" % i] = meta_case(text)
    # Metadata that decodes fine but then runs through the engine.
    c["meta_mixed_case_runs"] = Case(
        "declared",
        raw=[
            (
                "//p:m.delivery_unit",
                "p/m.delivery.json",
                '{"Name":"Mixed","Extra_Paths":["oauth-user-inspector/"],"ENVIRONMENTS":null}',
            )
        ],
    )
    # --- the stub engine: shapes the real one never prints ----------------------------
    for mode in [
        "ok",
        "exit3",
        "signal",
        "noverdict",
        "garbage",
        "twice",
        "interleave",
        "tabs",
        "unicode",
        "nonl",
        "empty",
        "badverdict",
    ]:
        c["engine_" + mode] = Case(
            "stub",
            [decl("unit-" + mode, extra_paths=[mode], exclude_paths=["x", "y|z"])],
        )
    c["engine_graph_targets"] = Case(
        "stub", [decl("g1", graph_targets=["//a:b", "//c:d"], build="//ignored:x")]
    )
    c["engine_build_derivation"] = Case(
        "stub", [decl("g2", build="//app:image", run="//app/infra:deploy")]
    )
    c["engine_build_no_run"] = Case("stub", [decl("g3", build="//app:image", run="")])
    c["engine_empty_graph_targets"] = Case(
        "stub", [decl("g4", graph_targets=[], build="")]
    )
    c["engine_mixed_modes"] = Case(
        "stub", [decl("p1"), decl("g5", build="//b:c"), decl("p2")]
    )
    c["engine_second_fails"] = Case(
        "stub", [decl("first"), decl("second", extra_paths=["exit3"]), decl("third")]
    )
    c["engine_forced_false"] = Case("stub", [decl("fp")], env={"FORCED_PUSH": "false"})
    c["engine_many_units"] = Case(
        "stub", [decl("u%02d-%s" % (i, "x" * (i % 7))) for i in range(12)]
    )
    c["engine_unit_bases"] = Case(
        "stub", [decl("ub")], env={"UNIT_BASES_JSON": '{"ub":"HEAD"}'}
    )
    # --- the command line and the workspace root -----------------------------------
    for name, args in {
        "no_args": [],
        "out_relative_nested": ["--out", "sub/../m.json"],
        "out_absolute": ["--out", "@WORK@/abs/../abs-manifest.json"],
        "out_equals": ["-out=@WORK@/eq.json"],
        "out_empty": ["-out="],
        "out_missing_arg": ["--out"],
        "out_twice": ["--out", "@WORK@/a.json", "-out", "@WORK@/b.json"],
        "help_short": ["-h"],
        "help_long": ["--help"],
        "help_word": ["-help"],
        "help_after_flag": ["--out", "@WORK@/x.json", "-help"],
        "unknown_flag": ["-nope"],
        "unknown_flag_value": ["--nope=1"],
        "bad_syntax_dashes": ["---out"],
        "bad_syntax_equals": ["-=x"],
        "positional_first": ["pos", "--out", "@WORK@/never.json"],
        "double_dash": ["--", "--out", "@WORK@/never.json"],
        "single_dash": ["-", "--out", "@WORK@/never.json"],
    }.items():
        c["cli_" + name] = Case("declared", [u()], args=args)
    c["cli_bazel_env"] = Case("declared", [u()], bazel_via="env")
    c["cli_bazel_env_and_flag"] = Case(
        "declared",
        [u()],
        bazel_via="flag",
        env={"ORCHESTRATE_BAZEL": "/nonexistent/bazel"},
    )
    c["cli_bazel_env_help"] = Case("declared", [u()], bazel_via="env", args=["-h"])
    c["cli_bazel_env_blank"] = Case(
        "declared",
        [u()],
        bazel_via="none",
        env={"ORCHESTRATE_BAZEL": "  ", "PATH": "/usr/bin:/bin"},
        args=["-x"],
    )
    c["bazel_missing_path"] = Case(
        "declared", [u()], bazel_via="none", args=["--bazel", "/nonexistent/bazel"]
    )
    c["bazel_not_on_path"] = Case(
        "declared", [u()], bazel_via="none", args=["--bazel", "no-such-bazel-binary"]
    )
    c["bazel_empty"] = Case("declared", [u()], bazel_via="none", args=["--bazel="])
    c["bazel_is_dir"] = Case("declared", [u()], bazel_via="none", args=["--bazel", "/"])
    c["bazel_default_name"] = Case(
        "declared", [u()], bazel_via="none", env={"PATH": "/usr/bin:/bin"}
    )
    c["root_from_bazel_run"] = Case("declared", [u()], cwd="elsewhere")
    c["root_relative_out_bazel_run"] = Case(
        "declared", [u()], cwd="elsewhere", args=["--out", "x/../rel.json"]
    )
    c["root_symlinked_pwd"] = Case("declared", [u()], cwd="symlink")
    c["root_missing_workspace"] = Case(
        "declared",
        [u()],
        cwd="elsewhere",
        env={"BUILD_WORKSPACE_DIRECTORY": "@WORK@/does-not-exist"},
    )
    c["out_unwritable"] = Case(
        "declared", [u()], args=["--out", "/nonexistent-dir/x/m.json"]
    )
    c["gh_output_unset"] = Case("declared", [u()], env={"GITHUB_OUTPUT": None})
    c["gh_output_is_dir"] = Case("declared", [u()], gh_output="dir")
    c["gh_output_missing_dir"] = Case(
        "declared", [u()], env={"GITHUB_OUTPUT": "@WORK@/nope/gh"}
    )
    c["gh_output_created"] = Case("declared", [u()], gh_output="absent")
    # No bash on PATH: the fake bazel finds its shell by absolute path, git
    # resolves through a one-entry PATH, and the engine cannot start.
    gitdir = os.path.join(ROOT, "only-git")
    if not os.path.exists(gitdir):
        os.makedirs(gitdir)
        os.symlink(shutil.which("git"), os.path.join(gitdir, "git"))
    c["no_bash_on_path"] = Case(
        "declared", [u()], shebang="#!/bin/bash", env={"PATH": gitdir}
    )
    c["no_path_at_all"] = Case(
        "declared", [u()], shebang="#!/bin/bash", env={"PATH": None}
    )
    c["not_a_git_repo_root"] = Case(
        "declared", [u()], cwd="elsewhere", env={"BUILD_WORKSPACE_DIRECTORY": "/"}
    )
    return c


class Parity(unittest.TestCase):
    maxDiff = None

    def test_side_by_side(self):
        all_cases = cases()
        failures = []
        for name, case in all_cases.items():
            go = run(GO, case)
            rs = run(RS, case)
            for key in ("code", "stdout", "stderr", "files", "repo-manifest"):
                if go[key] != rs[key]:
                    failures.append(
                        "%s: %s differs\n--- go\n%r\n--- rs\n%r"
                        % (name, key, go[key], rs[key])
                    )
        print(
            "orchestrate parity: %d cases, %d mismatches"
            % (len(all_cases), len(failures))
        )
        self.assertEqual(failures, [], "\n\n".join(failures))
        self.assertGreater(len(all_cases), 150)

    def test_cases_reach_the_real_engine(self):
        # Guard against a harness that silently stops exercising the engine.
        case = Case("declared", [u()])
        out = run(RS, case)
        self.assertEqual(out["code"], 0)
        self.assertIn(b"deploy-affected: affected=true (path matched", out["stdout"])
        self.assertIn(b"computed_by=paths", out["stdout"])


if __name__ == "__main__":
    unittest.main()
