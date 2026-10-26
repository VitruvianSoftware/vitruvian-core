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

"""check.sh and its Rust port, side by side.

Every scenario builds a scratch repo and a stub `npm`, runs `bash check.sh`
and the Rust binary with identical environments, and requires the same exit
code, stdout, stderr and sequence of npm calls. The scenarios are
check_test.sh's, then the edge cases where a port is most likely to drift:
Python's str() of odd JSON types, `read` splitting, byte-counted padding,
find's symlink and node_modules rules, and npm misbehaving.

The one documented divergence is a manifest that does not parse as a JSON
object: both skip it, but the script's stderr is a Python traceback naming the
local stdlib's files, so for those cases stderr only has to be non-empty on
both sides. (A manifest that cannot be opened -- a directory, a dangling
symlink -- gets Python's traceback byte for byte, and is compared exactly.)
"""

import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest

HERE = os.getcwd()
CHECK_RS = os.path.abspath(os.environ["CHECK_RS"])
CHECK_SH = os.path.abspath(os.environ["CHECK_SH"])

URL = "https://github.com/o/r.git"

# A stub npm: logs its argv, then answers `view <name> ...` from REGISTRY,
# a JSON map of name -> {"out": stdout, "err": stderr, "rc": exit code}.
STUB_NPM = r"""#!/usr/bin/env python3
import json, os, sys
with open(os.environ["CALLS"], "a") as f:
    f.write(json.dumps(sys.argv[1:]) + "\n")
reg = json.load(open(os.environ["REGISTRY"]))
if len(sys.argv) > 2 and sys.argv[1] == "view" and sys.argv[2] in reg:
    e = reg[sys.argv[2]]
    sys.stdout.write(e.get("out", ""))
    sys.stderr.write(e.get("err", ""))
    sys.exit(e.get("rc", 0))
sys.stderr.write("npm error 404\n")
sys.exit(1)
"""


def pkg(name, version, private=False, url=URL, directory=None, **extra):
    d = {"name": name, "version": version, "private": private}
    if url is not None or directory is not None:
        repo = {}
        if url is not None:
            repo["url"] = url
        if directory is not None:
            repo["directory"] = directory
        d["repository"] = repo
    d.update(extra)
    return json.dumps(d)


def live(**versions):
    return {n: {"out": v + "\n"} for n, v in versions.items()}


TS = "pulumi/library/ts/packages"
BASE_FILES = {
    f"{TS}/a/package.json": pkg("@v/a", "1.2.0", directory="ts/packages/a"),
    f"{TS}/b/package.json": pkg("@v/b", "0.3.0", directory="ts/packages/b"),
    f"{TS}/priv/package.json": pkg(
        "@v/priv", "9.9.9", True, directory="ts/packages/priv"
    ),
    "mcp-slack/package.json": pkg("@v/mcp", "1.9.0"),
}
BASE_LIVE = {"@v/a": "1.2.0", "@v/b": "0.3.0", "@v/mcp": "1.9.0"}


def scenario(name, files=None, registry=None, base=True, **kw):
    f = dict(BASE_FILES) if base else {}
    f.update(files or {})
    r = live(**BASE_LIVE) if base else {}
    r.update(registry or {})
    return dict(name=name, files=f, registry=r, **kw)


def raw(text):
    """A manifest given verbatim rather than as a dict."""
    return {"raw": text}


SCENARIOS = [
    # --- check_test.sh's scenarios ---
    scenario("everything current"),
    scenario("one behind", registry=live(**{"@v/b": "0.2.0"})),
    scenario("never published", registry={"@v/b": {"out": "", "rc": 1}}),
    scenario(
        "no repository at all",
        files={"mcp-slack/package.json": pkg("@v/mcp", "1.9.0", url=None)},
    ),
    scenario(
        "wrong directory",
        files={
            f"{TS}/b/package.json": pkg("@v/b", "0.3.0", directory="ts/packages/WRONG")
        },
    ),
    scenario(
        "sdk kit counted",
        files={
            "vitruvian-sdk/kits/typescript/package.json": pkg(
                "@v/kit", "0.10.0", directory="kits/typescript"
            )
        },
        registry=live(**{"@v/kit": "0.10.0"}),
    ),
    scenario(
        "sdk kit monorepo directory",
        files={
            "vitruvian-sdk/kits/typescript/package.json": pkg(
                "@v/kit", "0.10.0", directory="packages/vitruvian-sdk/kits/typescript"
            )
        },
        registry=live(**{"@v/kit": "0.10.0"}),
    ),
    # --- every root at once ---
    scenario(
        "all six roots",
        base=False,
        files={
            "packages/pulumi/library/ts/packages/x/package.json": pkg(
                "@v/x", "1.0.0", directory="ts/packages/x"
            ),
            f"{TS}/y/package.json": pkg("@v/y", "1.0.0", directory="ts/packages/y"),
            "apps/mcp/slack/package.json": pkg("@v/s1", "2.0.0"),
            "mcp-slack/package.json": pkg("@v/s2", "2.0.0"),
            "packages/vitruvian-sdk/kits/typescript/package.json": pkg(
                "@v/k1", "0.1.0", directory="kits/typescript"
            ),
            "vitruvian-sdk/kits/typescript/package.json": pkg(
                "@v/k2", "0.1.0", directory="kits/typescript"
            ),
        },
        registry=live(
            **{"@v/x": "1.0.0", "@v/y": "0.9.0", "@v/s1": "2.0.0", "@v/k1": "0.1.0"}
        ),
    ),
    scenario(
        "no roots at all",
        base=False,
        files={"elsewhere/package.json": pkg("@v/z", "1")},
    ),
    scenario("roots but no manifests", base=False, dirs=["mcp-slack", f"{TS}/empty"]),
    # --- Python's str() of odd values, and read's splitting ---
    scenario(
        "name null",
        files={f"{TS}/c/package.json": pkg(None, "1.0.0", directory="ts/packages/c")},
    ),
    scenario(
        "name number",
        files={f"{TS}/c/package.json": pkg(42, "1.0.0", directory="ts/packages/c")},
    ),
    scenario(
        "name list",
        files={
            f"{TS}/c/package.json": pkg(
                ["a", 1, None, True], "1.0.0", directory="ts/packages/c"
            )
        },
    ),
    scenario(
        "name dict",
        files={
            f"{TS}/c/package.json": pkg(
                {"x": "it's", "y": 1.5}, "1.0.0", directory="ts/packages/c"
            )
        },
    ),
    scenario(
        "name with a space",
        files={f"{TS}/c/package.json": pkg("a b", "1.0.0", directory="ts/packages/c")},
    ),
    scenario(
        "name with a tab",
        files={f"{TS}/c/package.json": pkg("a\tb", "1.0.0", directory="ts/packages/c")},
    ),
    scenario(
        "name with a newline",
        files={
            f"{TS}/c/package.json": pkg("@v/c\nx", "1.0.0", directory="ts/packages/c")
        },
    ),
    scenario(
        "name empty",
        files={f"{TS}/c/package.json": pkg("", "1.0.0", directory="ts/packages/c")},
    ),
    scenario(
        "name missing", files={f"{TS}/c/package.json": raw('{"version":"1.0.0"}')}
    ),
    scenario(
        "version float",
        files={f"{TS}/c/package.json": pkg("@v/c", 1.0, directory="ts/packages/c")},
        registry=live(**{"@v/c": "1.0"}),
    ),
    scenario(
        "version big float",
        files={f"{TS}/c/package.json": pkg("@v/c", 1e20, directory="ts/packages/c")},
    ),
    scenario(
        "version small float",
        files={
            f"{TS}/c/package.json": raw(
                '{"name":"@v/c","version":1.5e-7,"repository":{"url":"u","directory":"ts/packages/c"}}'
            )
        },
    ),
    scenario(
        "version int",
        files={f"{TS}/c/package.json": pkg("@v/c", 3, directory="ts/packages/c")},
        registry=live(**{"@v/c": "3"}),
    ),
    scenario(
        "version bool",
        files={f"{TS}/c/package.json": pkg("@v/c", True, directory="ts/packages/c")},
    ),
    scenario(
        "version empty",
        files={f"{TS}/c/package.json": pkg("@v/c", "", directory="ts/packages/c")},
    ),
    scenario("version missing", files={f"{TS}/c/package.json": raw('{"name":"@v/c"}')}),
    scenario(
        "version with a trailing newline",
        files={
            f"{TS}/c/package.json": pkg("@v/c", "1.0.0\n", directory="ts/packages/c")
        },
        registry=live(**{"@v/c": "1.0.0"}),
    ),
    scenario(
        "version null",
        files={f"{TS}/c/package.json": pkg("@v/c", None, directory="ts/packages/c")},
    ),
    scenario(
        "long name and version",
        files={
            f"{TS}/c/package.json": pkg(
                "@v/" + "n" * 70, "1.0.0-beta.123456", directory="ts/packages/c"
            )
        },
    ),
    scenario(
        "unicode name",
        files={
            f"{TS}/c/package.json": pkg(
                "@v/ünïcødé-✓", "1.0.0", directory="ts/packages/c"
            )
        },
    ),
    scenario(
        "name exactly 56 bytes",
        files={
            f"{TS}/c/package.json": pkg(
                "@v/" + "x" * 53, "1.0.0", directory="ts/packages/c"
            )
        },
    ),
    *[
        scenario(
            f"private {label}",
            files={
                f"{TS}/c/package.json": raw(
                    '{"name":"@v/c","version":"1.0.0","private":%s,"repository":{"url":"u","directory":"ts/packages/c"}}'
                    % value
                )
            },
        )
        for label, value in [
            ("string false", '"false"'),
            ("zero", "0"),
            ("one", "1"),
            ("null", "null"),
            ("empty list", "[]"),
            ("list", "[0]"),
            ("empty dict", "{}"),
            ("empty string", '""'),
            ("float zero", "0.0"),
            ("true", "true"),
        ]
    ],
    # --- repository shapes ---
    *[
        scenario(
            f"repository {label}",
            files={
                f"{TS}/c/package.json": raw(
                    '{"name":"@v/c","version":"1.0.0","repository":%s}' % value
                )
            },
            registry=live(**{"@v/c": "1.0.0"}),
        )
        for label, value in [
            ("string", '"github:o/r"'),
            ("empty string", '""'),
            ("object without url", '{"directory":"ts/packages/c"}'),
            ("url null", '{"url":null,"directory":"ts/packages/c"}'),
            ("url zero", '{"url":0}'),
            ("url number", '{"url":5,"directory":"ts/packages/c"}'),
            ("url list", '{"url":["x"],"directory":"ts/packages/c"}'),
            ("url trailing newlines", '{"url":"u\\n\\n","directory":"ts/packages/c"}'),
            ("directory null", '{"url":"u","directory":null}'),
            ("directory number", '{"url":"u","directory":7}'),
            ("directory empty", '{"url":"u","directory":""}'),
            ("directory list", '{"url":"u","directory":["ts"]}'),
            (
                "directory trailing newline",
                '{"url":"u","directory":"ts/packages/c\\n"}',
            ),
            ("list", '["u"]'),
            ("number", "3"),
            ("null", "null"),
            ("true", "true"),
        ]
    ],
    scenario(
        "string repository under mcp-slack",
        files={
            "mcp-slack/package.json": raw(
                '{"name":"@v/mcp","version":"1.9.0","repository":"git+https://x"}'
            )
        },
    ),
    scenario(
        "duplicate keys",
        files={
            f"{TS}/c/package.json": raw(
                '{"name":"@v/x","version":"1.0.0","name":"@v/c","repository":{"url":"","url":"u","directory":"ts/packages/c"}}'
            )
        },
        registry=live(**{"@v/c": "1.0.0"}),
    ),
    # --- provenance and behind together: provenance decides the message ---
    scenario(
        "bad provenance and behind",
        files={"mcp-slack/package.json": pkg("@v/mcp", "1.9.0", url="")},
        registry=live(**{"@v/a": "1.1.0"}),
    ),
    # --- tree shapes find must agree on ---
    scenario(
        "nested depth two",
        files={
            f"{TS}/c/sub/package.json": pkg(
                "@v/sub", "1.0.0", directory="ts/packages/sub"
            )
        },
    ),
    scenario(
        "depth three is not searched",
        files={f"{TS}/c/sub/deep/package.json": pkg("@v/deep", "1.0.0")},
    ),
    scenario(
        "root-level manifest",
        files={
            f"{TS}/package.json": pkg(
                "@v/root", "1.0.0", directory="ts/packages/packages"
            )
        },
    ),
    scenario(
        "node_modules excluded",
        files={
            "mcp-slack/node_modules/package.json": pkg("@v/nm", "1.0.0"),
            f"{TS}/a/node_modules/package.json": pkg("@v/nm2", "1.0.0"),
        },
    ),
    scenario("package.json that is a directory", dirs=[f"{TS}/c/package.json"]),
    scenario(
        "symlinked package directory",
        symlinks={f"{TS}/linked": "../../../../elsewhere"},
        files={
            "elsewhere/package.json": pkg(
                "@v/else", "1.0.0", directory="ts/packages/linked"
            )
        },
    ),
    scenario(
        "symlink named package.json",
        symlinks={f"{TS}/c/package.json": "../../../../../elsewhere/real.json"},
        files={"elsewhere/real.json": pkg("@v/c", "1.0.0", directory="ts/packages/c")},
        registry=live(**{"@v/c": "1.0.0"}),
    ),
    scenario(
        "symlinked root",
        base=False,
        symlinks={"mcp-slack": "real-slack"},
        files={"real-slack/package.json": pkg("@v/mcp", "1.9.0")},
        registry=live(**{"@v/mcp": "1.9.0"}),
    ),
    scenario(
        "sorting across roots",
        files={
            f"{TS}/B/package.json": pkg("@v/B", "1.0.0", directory="ts/packages/B"),
            f"{TS}/a-b/package.json": pkg(
                "@v/ab", "1.0.0", directory="ts/packages/a-b"
            ),
            f"{TS}/a.b/package.json": pkg(
                "@v/a.b", "1.0.0", directory="ts/packages/a.b"
            ),
            f"{TS}/_z/package.json": pkg("@v/_z", "1.0.0", directory="ts/packages/_z"),
        },
    ),
    # --- manifests that are not JSON objects (stderr divergence) ---
    scenario(
        "invalid json", files={f"{TS}/c/package.json": raw("{nope")}, loose_stderr=True
    ),
    scenario(
        "empty manifest", files={f"{TS}/c/package.json": raw("")}, loose_stderr=True
    ),
    scenario(
        "top-level array",
        files={f"{TS}/c/package.json": raw("[1,2]")},
        loose_stderr=True,
    ),
    scenario(
        "byte order mark",
        files={f"{TS}/c/package.json": raw('﻿{"name":"@v/c","version":"1"}')},
        loose_stderr=True,
    ),
    scenario(
        "dangling package.json symlink",
        symlinks={f"{TS}/c/package.json": "missing.json"},
    ),
    # --- npm misbehaving ---
    scenario("npm prints several lines", registry={"@v/a": {"out": "1.2.0\nextra\n"}}),
    scenario(
        "npm prints trailing blank lines", registry={"@v/a": {"out": "1.2.0\n\n\n"}}
    ),
    scenario("npm prints without newline", registry={"@v/a": {"out": "1.2.0"}}),
    scenario(
        "npm fails but prints a version", registry={"@v/a": {"out": "1.2.0\n", "rc": 1}}
    ),
    scenario(
        "npm fails and prints a stale version",
        registry={"@v/a": {"out": "1.0.0\n", "rc": 3, "err": "warn\n"}},
    ),
    scenario("npm prints leading spaces", registry={"@v/a": {"out": "  1.2.0\n"}}),
    scenario(
        "npm stderr is discarded",
        registry={"@v/a": {"out": "1.2.0\n", "err": "npm warn something\n"}},
    ),
    # --- npm resolution ---
    scenario("NPM empty means npm", env={"NPM": ""}),
    scenario("NPM as an explicit path", env={"NPM": "@BIN@/npm"}),
    scenario("NPM missing", env={"NPM": "no-such-npm"}),
    scenario("NPM not executable", env={"NPM": "@BIN@/notexec"}),
    scenario("NPM a directory", env={"NPM": "@BIN@"}),
    scenario("no npm on PATH", no_npm=True),
    # --- where it runs ---
    scenario("arguments are ignored", args=["--whatever", "x"]),
    scenario(
        "git toplevel when BUILD_WORKSPACE_DIRECTORY is unset",
        git=True,
        cwd_sub="pulumi",
        bwd=None,
    ),
    scenario(
        "BUILD_WORKSPACE_DIRECTORY empty falls back",
        git=True,
        cwd_sub="mcp-slack",
        bwd="",
    ),
    scenario("plain cwd outside git", bwd=None),
    scenario(
        "BUILD_WORKSPACE_DIRECTORY missing", bwd="/nonexistent/npa", loose_stderr=True
    ),
]


class Parity(unittest.TestCase):
    def build(self, sc, work):
        repo = os.path.join(work, "repo")
        os.makedirs(repo)
        for rel, content in sc["files"].items():
            p = os.path.join(repo, rel)
            os.makedirs(os.path.dirname(p), exist_ok=True)
            text = content["raw"] if isinstance(content, dict) else content + "\n"
            with open(p, "w", encoding="utf-8") as f:
                f.write(text)
        for rel in sc.get("dirs", []):
            os.makedirs(os.path.join(repo, rel), exist_ok=True)
        for rel, target in sc.get("symlinks", {}).items():
            p = os.path.join(repo, rel)
            os.makedirs(os.path.dirname(p), exist_ok=True)
            os.symlink(target, p)
        if sc.get("git"):
            subprocess.run(["git", "init", "-q", repo], check=True)
        binp = os.path.join(work, "bin")
        os.makedirs(binp)
        if not sc.get("no_npm"):
            with open(os.path.join(binp, "npm"), "w") as f:
                f.write(STUB_NPM)
            os.chmod(os.path.join(binp, "npm"), 0o755)
        with open(os.path.join(binp, "notexec"), "w") as f:
            f.write("#!/bin/sh\n")
        with open(os.path.join(work, "registry.json"), "w") as f:
            json.dump(sc["registry"], f)
        return repo, binp

    def run_one(self, cmd, sc, work, repo, binp, tag):
        calls = os.path.join(work, f"calls.{tag}")
        open(calls, "w").close()
        env = {
            "PATH": f"{binp}:/usr/bin:/bin",
            "CALLS": calls,
            "REGISTRY": os.path.join(work, "registry.json"),
            "LC_ALL": "C",
            "HOME": work,
        }
        bwd = sc.get("bwd", repo)
        if bwd is not None:
            env["BUILD_WORKSPACE_DIRECTORY"] = bwd
        for k, v in sc.get("env", {}).items():
            env[k] = v.replace("@BIN@", binp)
        cwd = os.path.join(repo, sc["cwd_sub"]) if sc.get("cwd_sub") else repo
        if sc.get("cwd_sub"):
            os.makedirs(cwd, exist_ok=True)
        p = subprocess.run(
            cmd + sc.get("args", []),
            cwd=cwd,
            env=env,
            stdin=subprocess.DEVNULL,
            capture_output=True,
            timeout=60,
        )
        with open(calls) as f:
            return p.returncode, p.stdout, p.stderr, f.read()

    def test_scenarios(self):
        failures = []
        for sc in SCENARIOS:
            with self.subTest(sc["name"]):
                work = tempfile.mkdtemp(prefix="npa-parity-")
                try:
                    repo, binp = self.build(sc, work)
                    want = self.run_one(["bash", CHECK_SH], sc, work, repo, binp, "sh")
                    got = self.run_one([CHECK_RS], sc, work, repo, binp, "rs")
                finally:
                    shutil.rmtree(work, ignore_errors=True)
                labels = ["exit code", "stdout", "stderr", "npm calls"]
                for i, label in enumerate(labels):
                    if label == "stderr" and sc.get("loose_stderr"):
                        if bool(want[2]) != bool(got[2]):
                            failures.append(
                                f"{sc['name']}: stderr presence differs:\n  sh: {want[2]!r}\n  rs: {got[2]!r}"
                            )
                        continue
                    if want[i] != got[i]:
                        failures.append(
                            f"{sc['name']}: {label} differs:\n  sh: {want[i]!r}\n  rs: {got[i]!r}"
                        )
        if failures:
            self.fail(
                f"{len(failures)} mismatch(es) over {len(SCENARIOS)} scenarios:\n"
                + "\n".join(failures)
            )
        print(f"parity: {len(SCENARIOS)} scenarios identical", file=sys.stderr)

    def test_scenarios_are_not_vacuous(self):
        # A parity test whose scenarios all exit the same way proves little.
        codes = set()
        work = tempfile.mkdtemp(prefix="npa-parity-")
        try:
            for i, sc in enumerate(SCENARIOS):
                w = os.path.join(work, str(i))
                os.makedirs(w)
                repo, binp = self.build(sc, w)
                codes.add(self.run_one([CHECK_RS], sc, w, repo, binp, "rs")[0])
        finally:
            shutil.rmtree(work, ignore_errors=True)
        self.assertEqual(codes, {0, 1, 2})


if __name__ == "__main__":
    unittest.main()
