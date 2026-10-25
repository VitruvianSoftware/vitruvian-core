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

"""//tools/license:verify (Rust) against verify.sh, side by side.

Each case builds a throwaway git repository (the first-party LICENSE files in
some state, plus tracked source files with assorted headers and paths), runs
verify.sh and the Rust binary against it, and requires the same exit code,
stdout and stderr. Fixed cases cover each rule and exemption; a seeded
generator then mixes them.
"""

import os
import random
import shutil
import subprocess
import tempfile
import unittest

HERE = os.getcwd()
SH = os.path.join(HERE, os.environ["VERIFY_SH"])
RS = os.path.join(HERE, os.environ["VERIFY_RS"])
BASH = shutil.which("bash")

APPS = [
    "apps/suites/tabula",
    "apps/web/oauth-user-inspector",
    "apps/cli/devx",
    "apps/cli/homelab",
    "apps/mcp/slack",
    "apps/desktop/nexus-agent",
    "apps/desktop/home-speaker",
]
MIT_BODY = (
    "//\n// Permission is hereby granted, free of charge, to any person obtaining a copy\n"
    '// of this software and associated documentation files (the "Software"), to deal\n'
)
GOOD_LICENSE = "MIT License\n\nCopyright (c) 2026 VitruvianSoftware\n"

HEADERS = {
    "valid": "// Copyright (c) 2026 VitruvianSoftware\n"
    + MIT_BODY
    + "\npackage main\n",
    "wrong-holder": "// Copyright (c) 2026 Somebody Else\n"
    + MIT_BODY
    + "\npackage main\n",
    "apache": "// Copyright 2026 VitruvianSoftware\n//\n// Licensed under the Apache License, Version 2.0\n",
    "spdx": "// SPDX-License-Identifier: GPL-3.0-or-later\n// Copyright (C) 2026 X\n",
    "none": "package main\n\nfunc main() {}\n",
    "lower": "// copyright notice only\n",
    "late-header": "x\n" * 30 + "// Copyright (c) 2026 VitruvianSoftware\n",
    "header-at-30": "x\n" * 29 + "// Copyright 2026 nobody\n",
    "mit-no-year": "// Copyright (c) VitruvianSoftware\n" + MIT_BODY,
    "five-digit-year": "// Copyright (c) 20266 VitruvianSoftware\n" + MIT_BODY,
    "crlf": "// Copyright (c) 2026 VitruvianSoftware\r\n"
    + MIT_BODY.replace("\n", "\r\n"),
    "empty": "",
    "no-newline": "// Copyright (c) 2026 VitruvianSoftware Permission is hereby granted, free of charge",
    "big-valid": "// Copyright (c) 2026 VitruvianSoftware\n"
    + MIT_BODY
    + ("// " + "x" * 8192 + "\n") * 25,
    "big-wrong": "// Copyright (c) 2026 Somebody Else\n"
    + MIT_BODY
    + ("// " + "x" * 8192 + "\n") * 25,
    "licensed-under": "/* Licensed under MIT, see LICENSE */\n",
}

LICENSES = {
    "good": GOOD_LICENSE,
    "crlf": GOOD_LICENSE.replace("\n", "\r\n"),
    "apache": "Apache License\nCopyright (c) 2026 VitruvianSoftware\n",
    "no-holder": "MIT License\n\nCopyright (c) 2026 Someone\n",
    "lower": "mit license\nCopyright (c) 2026 VitruvianSoftware\n",
    "empty": "",
    "dir": None,
    "missing": False,
}

PATHS = [
    "a.go",
    "web/b.ts",
    "web/c.tsx",
    "x/d.js",
    "x/e.mjs",
    "x/f.cjs",
    "mac/g.swift",
    "types.d.ts",
    "notes.txt",
    "node_modules/m/h.js",
    "pkg/dist/i.js",
    "dist-server/j.js",
    "bazel-out/k.go",
    "pkg/bazel-/l.go",
    "distx/m.go",
    "pulumi/library/n.go",
    "packages/pulumi/examples/o.ts",
    "x/pulumi/library/p.go",
    "apps/desktop/vitruvian/q.swift",
    "apps/desktop/vitruvian-tool-github/r.swift",
    "apps/desktop/vitruvian-x/s.swift",
    "apps/desktop/nexus-agent/macos/Sources/NexusAgentUI/Resources/t.js",
    "apps/desktop/courier/u.swift",
    "tools/internal/scaffold/templates/v.go",
    "dir with space/w.go",
]


def build_repo(root, licenses, files, extra=None):
    subprocess.run(["git", "init", "-q", root], check=True)
    for app in APPS:
        os.makedirs(os.path.join(root, app), exist_ok=True)
        kind = licenses.get(app, "good")
        content = LICENSES[kind]
        path = os.path.join(root, app, "LICENSE")
        if content is None:
            os.makedirs(path)
        elif content is not False:
            with open(path, "w", newline="") as f:
                f.write(content)
    for rel, header in files.items():
        path = os.path.join(root, rel)
        os.makedirs(os.path.dirname(path) or root, exist_ok=True)
        with open(path, "w", newline="") as f:
            f.write(HEADERS[header])
    if extra:
        extra(root)
    subprocess.run(["git", "-C", root, "add", "-A"], check=True)


def run(cmd, root):
    env = {k: v for k, v in os.environ.items() if k != "BUILD_WORKSPACE_DIRECTORY"}
    env["BUILD_WORKSPACE_DIRECTORY"] = root
    p = subprocess.run(cmd, cwd=HERE, env=env, capture_output=True, timeout=120)
    return p.returncode, p.stdout, p.stderr


class Parity(unittest.TestCase):
    maxDiff = None

    def compare(self, licenses, files, extra=None, label=""):
        results = []
        for cmd in ([BASH, SH], [RS]):
            root = tempfile.mkdtemp()
            try:
                build_repo(root, licenses, files, extra)
                rc, out, err = run(cmd, root)
                results.append(
                    (
                        rc,
                        out.replace(root.encode(), b"ROOT"),
                        err.replace(root.encode(), b"ROOT"),
                    )
                )
            finally:
                shutil.rmtree(root)
        self.assertEqual(
            results[0], results[1], f"{label} licenses={licenses} files={files}"
        )
        return results[0]

    def test_each_header(self):
        for name in HEADERS:
            self.compare({}, {"src/x.go": name}, label=name)

    def test_each_license(self):
        for kind in LICENSES:
            for app in (APPS[0], APPS[-1]):
                self.compare({app: kind}, {}, label=kind)
        self.compare({a: "missing" for a in APPS}, {"a.go": "wrong-holder"})

    def test_each_path(self):
        for path in PATHS:
            for header in ("wrong-holder", "apache"):
                self.compare({}, {path: header}, label=path)

    def test_all_at_once(self):
        files = {p: h for p, h in zip(PATHS, list(HEADERS) * 3)}
        self.compare({APPS[2]: "apache", APPS[3]: "no-holder"}, files)

    def test_unreadable_entries(self):
        def deleted_after_add(root):
            with open(os.path.join(root, "gone.go"), "w") as f:
                f.write(HEADERS["wrong-holder"])
            subprocess.run(["git", "-C", root, "add", "gone.go"], check=True)
            os.remove(os.path.join(root, "gone.go"))

        res = []
        for cmd in ([BASH, SH], [RS]):
            root = tempfile.mkdtemp()
            try:
                build_repo(root, {}, {"a.go": "wrong-holder"})
                deleted_after_add(root)
                rc, out, err = run(cmd, root)
                res.append((rc, out, err.replace(root.encode(), b"ROOT")))
            finally:
                shutil.rmtree(root)
        # Both stop at the file `head` cannot open, after reporting a.go.
        self.assertEqual(res[0][:2], res[1][:2])
        for r in res:
            self.assertIn(b"a.go: license header holder is not", r[2])
            self.assertIn(b"gone.go", r[2])
            self.assertNotIn(b"license-verify: FAILED", r[2])

    def test_generated(self):
        rng = random.Random(457)
        for i in range(60):
            licenses = {
                a: rng.choice(list(LICENSES))
                for a in rng.sample(APPS, rng.randint(0, 3))
            }
            files = {}
            for _ in range(rng.randint(0, 8)):
                files[rng.choice(PATHS)] = rng.choice(list(HEADERS))
            self.compare(licenses, files, label=f"generated #{i}")


if __name__ == "__main__":
    unittest.main()
