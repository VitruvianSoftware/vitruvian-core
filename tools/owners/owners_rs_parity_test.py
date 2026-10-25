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

"""//tools/owners (Rust) against //tools/owners:owners-go, side by side.

Every case builds a throwaway tree of OWNERS files, runs both binaries with
the same arguments from the same directory, and requires the same exit code,
stdout, stderr (argv[0] masked: Go's usage text names the binary) and, where
the run writes one, the same CODEOWNERS file. Fixed cases cover each rule
and message; a seeded generator then writes OWNERS files from the shapes
real ones take (block and flow lists, quoting, comments, inheritance flags,
per-file rules, legacy line format) plus deliberate breakage.
"""

import os
import random
import shutil
import subprocess
import tempfile
import unittest

HERE = os.getcwd()
GO = os.path.join(HERE, os.environ["OWNERS_GO"])
RS = os.path.join(HERE, os.environ["OWNERS_RS"])

FLAG_SETS = [
    [],
    ["--check"],
    ["--coverage-check"],
    ["--validate-only"],
    ["--out", ".github/CODEOWNERS"],
    ["--coverage-check", "--out", "gen/deep/CODEOWNERS"],
    ["--coverage-check", "--check"],
]


def run(binary, args, cwd, env_extra=None):
    env = {k: v for k, v in os.environ.items() if k != "BUILD_WORKSPACE_DIRECTORY"}
    env["PWD"] = cwd
    if env_extra:
        env.update(env_extra)
    p = subprocess.run(
        [binary] + args, cwd=cwd, env=env, capture_output=True, timeout=60
    )
    return p.returncode, p.stdout, p.stderr.replace(binary.encode(), b"ARGV0")


def write_tree(root, files):
    for rel, content in files.items():
        path = os.path.join(root, rel)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        if content is None:
            os.makedirs(path, exist_ok=True)
            continue
        with open(path, "wb") as f:
            f.write(content.encode() if isinstance(content, str) else content)


class Parity(unittest.TestCase):
    maxDiff = None

    def compare_tree(self, files, flag_sets=FLAG_SETS, label=""):
        for flags in flag_sets:
            results = []
            for binary in (GO, RS):
                root = tempfile.mkdtemp()
                try:
                    write_tree(root, files)
                    rc, out, err = run(binary, ["--root", root] + flags, root)
                    out = out.replace(root.encode(), b"ROOT")
                    err = err.replace(root.encode(), b"ROOT")
                    written = {}
                    for rel in (".github/CODEOWNERS", "gen/deep/CODEOWNERS"):
                        p = os.path.join(root, rel)
                        if os.path.isfile(p):
                            with open(p, "rb") as f:
                                written[rel] = f.read()
                    results.append((rc, out, err, written))
                finally:
                    shutil.rmtree(root)
            self.assertEqual(
                results[0], results[1], f"{label} flags={flags} files={files!r}"
            )

    # ---- fixed cases -------------------------------------------------------

    def test_go_suite_trees(self):
        self.compare_tree(
            {
                "OWNERS": "\napprovers:\n  - @VitruvianSoftware/platform-team\n",
                "devx/OWNERS": '\napprovers:\n  - @VitruvianSoftware/devx-team\nper_file:\n  - pattern: "*.md"\n    approvers:\n      - @VitruvianSoftware/docs-team\n',
                "tabula/OWNERS": "\napprovers:\n  - @VitruvianSoftware/tabula-team\noptions:\n  no_parent_owners: true\n",
            }
        )
        self.compare_tree({"devx": None, "tabula": None})

    def test_full_required_layout(self):
        files = {"OWNERS": "approvers:\n  - @VitruvianSoftware/platform-team\n"}
        for sub in [
            "apps",
            "apps/cli/devx",
            "packages/pulumi",
            "tools",
            "gitops",
            "infrastructure",
            "apps/suites/tabula",
        ]:
            files[sub + "/OWNERS"] = (
                f"approvers:\n  - @VitruvianSoftware/{sub.replace('/', '-')}\n"
            )
        files["apps/web/backstage/x.txt"] = "x"  # required, exists, no OWNERS
        self.compare_tree(files)
        del files["apps/web/backstage/x.txt"]
        files[".github/CODEOWNERS"] = "stale\n"
        self.compare_tree(files)

    def test_messages(self):
        cases = {
            "empty": "  \n\t\n",
            "nothing": "# just a comment\nfoo bar\n",
            "bad-handle": "approvers:\n  - '@bad handle'\n",
            "bad-reviewer": "approvers: [a]\nreviewers: ['@x y']\n",
            "empty-reviewer": "approvers: [a]\nreviewers: [' ']\n",
            "null-only": "approvers: [~]\n",
            "noparent-only": "options:\n  no_parent_owners: true\n",
            "per-file-empty": "approvers: [a]\nper_file:\n  - approvers: [b]\n",
            "per-file-null": "approvers: [a]\nper_file:\n  -\n",
            "per-file-bad-glob": "approvers: [a]\nper_file:\n  - pattern: '[a-'\n    owners: [b]\n",
            "per-file-bad-owner": "approvers: [a]\nper_file:\n  - pattern: '*.go'\n    owners: ['b c']\n",
            "per-file-bad-approver": "approvers: [a]\nper_file:\n  - pattern: '*.go'\n    approvers: ['@']\n",
            "quote-escapes": 'approvers:\n  - "a\\tb\\u00e9\\""\n',
            "unicode": 'approvers:\n  - "café"\n',
            "scalar-list": "approvers: @a\n",
            "flow-at": "approvers: [@a, @b]\n",
            "legacy": "set noparent\n@VitruvianSoftware/platform-team\n@bob\n",
            "legacy-mixed": "# owners\n- @a, @b/c\n'x/y': z\nno_parent_owners: true\n",
            "dup-key": "approvers: [a]\napprovers: [b]\n",
            "yes-bool": "approvers: [a]\noptions:\n  no_parent_owners: yes\n",
            "quoted-true": "approvers: [a]\noptions:\n  no_parent_owners: 'true'\n",
            "int-bool": "approvers: [a]\noptions:\n  no_parent_owners: 1\n",
            "options-scalar": "approvers: [a]\noptions: true\n",
            "same-indent": "approvers:\n- a\n- b\nowners:\n- c\n",
            "unknown-keys": "labels: [x]\napprovers:\n  - a # trailing\n  - 'it''s'\n",
            "doc-markers": "---\napprovers: [a]\n...\n",
            "two-docs": "approvers: [a]\n---\napprovers: [b]\n",
            "numbers": "approvers:\n  - 123\n  - 0x1F\n  - true\n",
            "anchor": "approvers: &x [a]\nowners: *x\n",
            "tab-indent": "approvers:\n\t- a\n",
            "crlf": "approvers:\r\n  - a\r\n  - b\r\n",
            "email": "owners:\n  - dev@example.com\n  - bad@example\n",
            "long-user": "approvers:\n  - " + "a" * 39 + "\n  - " + "b" * 40 + "\n",
            "dash-user": "approvers:\n  - -a\n",
            "multi-line-plain": "approvers:\n  - a\n    b\n",
            "empty-flow": "approvers: []\nowners: {}\n",
            "nested-list": "approvers:\n  - [a, b]\n",
            "map-item": "approvers:\n  - a: b\n",
            "bom": "﻿approvers: [a]\n",
        }
        for name, text in cases.items():
            self.compare_tree(
                {"OWNERS": "approvers: [root]\n", "sub/OWNERS": text}, label=name
            )

    def test_walk_order_and_ignores(self):
        self.compare_tree(
            {
                "OWNERS": "approvers: [root]\n",
                "b/OWNERS": "approvers: [bad handle]\n",
                "a/OWNERS.yml": "approvers: ['another bad']\n",
                "node_modules/OWNERS": "approvers: ['ignored one']\n",
                "bazel-x/OWNERS": "approvers: ['ignored two']\n",
            }
        )
        self.compare_tree(
            {
                "OWNERS": "approvers: [root]\n",
                "a/OWNERS": "approvers: [one]\n",
                "a/OWNERS.yaml": "approvers: [two]\n",
                "a/b/c/OWNERS": "owners: [three]\n",
                "a/b/OWNERS": None,
                "dist/OWNERS": "approvers: [no]\n",
                "x/bin/OWNERS": "approvers: [no]\n",
            }
        )

    def test_root_defaults_and_errors(self):
        self.compare_tree(
            {
                "OWNERS.yaml": "options:\n  no_parent_owners: true\n",
                "s/OWNERS": "approvers: [x]\n",
            }
        )
        self.compare_tree({"OWNERS.yml": "approvers: [x]\n", "tools": None})
        self.compare_tree({})
        self.compare_tree(
            {".github": None, "OWNERS": "approvers: [x]\n"}, flag_sets=[["--check"]]
        )

    def test_flags_and_roots(self):
        root = tempfile.mkdtemp()
        try:
            write_tree(root, {"OWNERS": "approvers: [x]\n", "file": "f"})
            arg_sets = [
                ["-h"],
                ["--help"],
                ["-help"],
                ["-x"],
                ["---bad"],
                ["--root"],
                ["-check=nope"],
                ["-check=false"],
                ["--", "--check"],
                ["positional", "--check"],
                ["-"],
                ["--root", root + "/missing"],
                ["--root", root + "/file"],
                ["--root=" + root, "--validate-only=1"],
                ["--root", "."],
                ["--root", root, "--out", root + "/file/x"],
                ["--root", root, "--out", "file"],
                ["--root", root, "--out", root + "//abs//out"],
            ]
            for args in arg_sets:
                outs = []
                for binary in (GO, RS):
                    rc, out, err = run(binary, args, root)
                    outs.append(
                        (
                            rc,
                            out.replace(root.encode(), b"ROOT"),
                            err.replace(root.encode(), b"ROOT"),
                        )
                    )
                    if os.path.isfile(os.path.join(root, "file")):
                        os.remove(os.path.join(root, "file"))
                    shutil.rmtree(os.path.join(root, "abs"), ignore_errors=True)
                    write_tree(root, {"file": "f"})
                self.assertEqual(outs[0], outs[1], args)
            for env in (
                {"BUILD_WORKSPACE_DIRECTORY": root},
                {"BUILD_WORKSPACE_DIRECTORY": ""},
            ):
                outs = [run(b, [], root, env) for b in (GO, RS)]
                self.assertEqual(outs[0], outs[1], env)
        finally:
            shutil.rmtree(root)

    # ---- generated cases ---------------------------------------------------

    def test_generated(self):
        rng = random.Random(457)
        handles = [
            "@VitruvianSoftware/platform-team",
            "@VitruvianSoftware/devx-team",
            "@alice",
            "bob",
            "dev@example.com",
            "@org/",
            "bad handle",
            "@x@y",
            "",
            "~",
            "null",
            "-",
            "a-",
            "123",
            "@a_b/c-d",
            "x/y",
            "@" + "z" * 39,
            "true",
        ]
        patterns = ["*.md", "docs/**", "[a-z]*.go", "[", "x\\", "*", "a[]b", "?", ""]

        def scalar(h):
            style = rng.choice(["plain", "dq", "sq"])
            if style == "dq":
                return '"' + h.replace("\\", "\\\\").replace('"', '\\"') + '"'
            if style == "sq":
                return "'" + h.replace("'", "''") + "'"
            return h

        def handle_list(indent):
            items = rng.sample(handles, rng.randint(0, 4))
            if rng.random() < 0.3:
                return " [" + ", ".join(scalar(h) for h in items) + "]\n"
            out = "\n"
            dash_indent = rng.choice([indent, indent + 2])
            for h in items:
                comment = " # c" if rng.random() < 0.2 else ""
                out += " " * dash_indent + "- " + scalar(h) + comment + "\n"
            return out

        def yaml_file():
            parts = []
            if rng.random() < 0.1:
                parts.append("---\n")
            for key in rng.sample(
                ["approvers", "owners", "reviewers", "options", "per_file", "labels"],
                rng.randint(1, 4),
            ):
                if key == "options":
                    val = rng.choice(
                        ["true", "false", "yes", "off", "'true'", "1", "~"]
                    )
                    parts.append(f"options:\n  no_parent_owners: {val}\n")
                elif key == "per_file":
                    s = "per_file:\n"
                    for _ in range(rng.randint(0, 2)):
                        s += f"  - pattern: {scalar(rng.choice(patterns))}\n"
                        s += (
                            "    "
                            + rng.choice(["approvers", "owners", "reviewers"])
                            + ":"
                            + handle_list(4)
                        )
                    parts.append(s)
                else:
                    parts.append(key + ":" + handle_list(0))
                if rng.random() < 0.1:
                    parts.append("# a comment line\n\n")
            return "".join(parts)

        def legacy_file():
            lines = []
            for _ in range(rng.randint(0, 4)):
                lines.append(
                    rng.choice(
                        ["set noparent", "# c", "", "  " + rng.choice(handles)]
                        + [" ".join(rng.sample(handles, 2))]
                    )
                )
            return "\n".join(lines) + rng.choice(["", "\n"])

        for i in range(150):
            files = {"OWNERS": yaml_file() if rng.random() < 0.8 else legacy_file()}
            for d in rng.sample(
                ["apps", "apps/web", "apps/web/x", "tools", "tools/y/z", "packages"],
                rng.randint(0, 4),
            ):
                files[d + "/OWNERS"] = (
                    yaml_file() if rng.random() < 0.85 else legacy_file()
                )
            self.compare_tree(
                files, flag_sets=[[], ["--coverage-check"]], label=f"generated #{i}"
            )


if __name__ == "__main__":
    unittest.main()
