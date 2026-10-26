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

"""//tools/doctor (Rust) against doctor.sh, side by side.

Every scenario builds a throwaway workspace (.bazelversion, .nvmrc,
package.json, go.mod, user.bazelrc as the case needs) and a directory of
`#!/bin/sh` stand-ins for the tools, each of which logs its argv. Both
programs run in that workspace with the same minimal environment: PATH is the
stand-ins plus a directory holding only the text utilities doctor.sh itself
uses (so no real bazel, node, git or python3 is ever found), no LANG. The exit
code, stdout, stderr and the stand-ins' invocation log must match byte for
byte. One case runs both on a pseudo-terminal to compare the coloured report.

Runs on macOS (/bin/bash 3.2, BSD utilities) and Linux (GNU bash 5.x).
"""

import os
import pty
import shutil
import subprocess
import tempfile
import unittest

HERE = os.getcwd()
SH = os.path.join(HERE, os.environ["DOCTOR_SH"])
RS = os.path.join(HERE, os.environ["DOCTOR_RS"])
BASH = (
    os.environ.get("PARITY_BASH")
    or shutil.which("bash", path="/bin:/usr/bin")
    or shutil.which("bash")
)
UTILS = ["awk", "sed", "grep", "tr", "head", "cut", "cat"]

OK_BAZEL = "printf 'Bazelisk version: 1.25.0\\nBuild label: 9.3.0\\n'"
DOCKER = (
    'case "$1" in info) exit "${DOCKER_INFO_RC:-0}";; esac\n'
    "echo 'Docker version 29.6.0, build abc123'"
)
FULL_FILES = {
    ".bazelversion": b"9.3.0\n",
    ".nvmrc": b"v22.21.1\n",
    "package.json": b'{\n  "name": "x",\n  "packageManager": "pnpm@10.20.0+sha512.deadbeef"\n}\n',
    "app/go.mod": b"module example.com/app\n\ngo 1.25.5\n",
}
FULL_STUBS = {
    "bazel": OK_BAZEL,
    "node": "echo v22.21.1",
    "pnpm": "echo 10.20.0",
    "go": "echo 'go version go1.25.5 darwin/arm64'",
    "git": "echo 'git version 2.54.0'",
}


def S(name, args, stubs=None, files=None, bwd=True, env=None, tty=False, cwd_sub=""):
    return dict(
        name=name,
        args=args,
        stubs=stubs or {},
        files=files or {},
        bwd=bwd,
        env=env or {},
        tty=tty,
        cwd_sub=cwd_sub,
    )


REQ_ALL = [
    "--label",
    "core",
    "--required",
    "bazel,node,pnpm,go,git",
    "--gomod",
    "app/go.mod",
]

SCENARIOS = [
    S("all-ok", REQ_ALL, FULL_STUBS, FULL_FILES),
    S("no-args-no-tools", []),
    S("multi-word-label", ["--label", "vitruvian-core", "(core", "toolchain)"]),
    S(
        "label-empty-tokens",
        ["--label", "", "a", "", "b", "--required", "git"],
        {"git": "echo 2.1.0"},
    ),
    S("label-twice", ["--label", "a", "b", "--label", "c"]),
    S("label-then-unknown", ["--label", "x", "--bogus", "y", ""]),
    S("unknown-only", ["oops", "-v", "--"]),
    S(
        "empty-csv-entries",
        ["--required", ",,git,,", "--optional", ","],
        {"git": "echo 2.1.0"},
    ),
    S(
        "csv-with-blanks",
        ["--required", "git bazel", "--optional", "node\tpnpm"],
        FULL_STUBS,
        FULL_FILES,
    ),
    S(
        "required-missing-all",
        [
            "--required",
            "bazel,node,pnpm,go,git,gh,gcloud,docker,direnv,mage,mise,lima,swift,python3,goreleaser,zig",
        ],
        {},
        FULL_FILES,
    ),
    S(
        "optional-missing-all",
        [
            "--optional",
            "bazel,node,pnpm,go,git,gh,gcloud,docker,direnv,mage,mise,lima,swift,python3,goreleaser,zig",
        ],
        {},
        FULL_FILES,
    ),
    S(
        "go-missing-with-gomod",
        ["--required", "go", "--gomod", "app/go.mod"],
        {},
        FULL_FILES,
    ),
    S(
        "go-missing-gomod-absent-file",
        ["--required", "go", "--gomod", "nope/go.mod"],
        {},
        FULL_FILES,
    ),
    S(
        "go-present-no-gomod-flag",
        ["--required", "go"],
        {"go": "echo 'go version go1.20.1 linux/amd64'"},
        FULL_FILES,
    ),
    S(
        "go-mismatch",
        ["--required", "go", "--gomod", "app/go.mod"],
        {"go": "echo 'go version go1.24.0 linux/amd64'"},
        FULL_FILES,
    ),
    S(
        "go-patch",
        ["--required", "go", "--gomod", "app/go.mod"],
        {"go": "echo 'go version go1.25.9 linux/amd64'"},
        FULL_FILES,
    ),
    S(
        "gomod-crlf-indented",
        ["--required", "go", "--gomod", "go.mod"],
        {"go": "echo go1.25.5"},
        {"go.mod": b"module x\r\n\r\n  go\t1.25.5\r\n"},
    ),
    S(
        "gomod-go-no-version",
        ["--required", "go", "--gomod", "go.mod"],
        {"go": "echo go1.25.5"},
        {"go.mod": b"module x\ngo\n"},
    ),
    S(
        "bazel-fallback-no-label",
        ["--required", "bazel"],
        {"bazel": "echo 'bazel 9.3.0'"},
        FULL_FILES,
    ),
    S(
        "bazel-empty-label",
        ["--required", "bazel"],
        {"bazel": "printf 'Build label: \\nsomething 9.3.1\\n'"},
        FULL_FILES,
    ),
    S(
        "bazel-two-labels",
        ["--required", "bazel"],
        {"bazel": "printf 'Build label: 9.2.0\\nBuild label: 9.3.0\\n'"},
        FULL_FILES,
    ),
    S(
        "bazel-mismatch-required",
        ["--required", "bazel"],
        {"bazel": "echo 'Build label: 8.4.2'"},
        FULL_FILES,
    ),
    S(
        "bazel-mismatch-optional",
        ["--optional", "bazel"],
        {"bazel": "echo 'Build label: 8.4.2'"},
        FULL_FILES,
    ),
    S(
        "bazel-patch",
        ["--required", "bazel"],
        {"bazel": "echo 'Build label: 9.3.4'"},
        FULL_FILES,
    ),
    S(
        "bazel-no-version",
        ["--required", "bazel"],
        {"bazel": "echo 'development version'"},
        FULL_FILES,
    ),
    S(
        "bazel-no-source",
        ["--required", "bazel"],
        {"bazel": "echo 'Build label: 1.0.0'"},
        {},
    ),
    S(
        "bazelversion-blanks-cr",
        ["--required", "bazel"],
        {"bazel": OK_BAZEL},
        {".bazelversion": b" \t9.3.0 \t\r\nignored\n"},
    ),
    S(
        "bazelversion-empty",
        ["--required", "bazel"],
        {"bazel": OK_BAZEL},
        {".bazelversion": b""},
    ),
    S(
        "bazelversion-no-newline",
        ["--required", "bazel"],
        {"bazel": OK_BAZEL},
        {".bazelversion": b"9.3"},
    ),
    S(
        "bazelversion-garbage",
        ["--required", "bazel"],
        {"bazel": OK_BAZEL},
        {".bazelversion": b"latest\n"},
    ),
    S(
        "bazelversion-is-dir",
        ["--required", "bazel"],
        {"bazel": OK_BAZEL},
        {".bazelversion/x": b"9.3.0\n"},
    ),
    S(
        "node-v-prefix",
        ["--required", "node"],
        {"node": "echo v26.4.0"},
        {".nvmrc": b"  vv26.4.0\r\n"},
    ),
    S("node-mismatch", ["--required", "node"], {"node": "echo v20.1.0"}, FULL_FILES),
    S(
        "node-short",
        ["--required", "node"],
        {"node": "echo v22.21"},
        {".nvmrc": b"22.21.0\n"},
    ),
    S(
        "pnpm-no-packagemanager",
        ["--required", "pnpm"],
        {"pnpm": "echo 10.20.0"},
        {"package.json": b'{"name": "x"}\n'},
    ),
    S(
        "pnpm-other-manager",
        ["--required", "pnpm"],
        {"pnpm": "echo 10.20.0"},
        {"package.json": b'{"packageManager": "yarn@4.1.0"}'},
    ),
    S(
        "pnpm-two-on-line",
        ["--required", "pnpm"],
        {"pnpm": "echo 10.20.0"},
        {"package.json": b'{"packageManager": "pnpm@9.1.0", "x": "pnpm@10.20.0"}\n'},
    ),
    S("pnpm-mismatch", ["--required", "pnpm"], {"pnpm": "echo 9.0.0"}, FULL_FILES),
    S("docker-up-required", ["--required", "docker"], {"docker": DOCKER}),
    S(
        "docker-down-required",
        ["--required", "docker"],
        {"docker": DOCKER},
        env={"DOCKER_INFO_RC": "1"},
    ),
    S(
        "docker-down-optional",
        ["--optional", "docker"],
        {"docker": DOCKER},
        env={"DOCKER_INFO_RC": "3"},
    ),
    S(
        "docker-no-version",
        ["--optional", "docker"],
        {"docker": 'case "$1" in info) exit 0;; esac\necho docker'},
    ),
    S(
        "lima-limactl",
        ["--optional", "lima"],
        {"limactl": "printf 'limactl version 2.1.3\\nextra 9.9.9\\n'"},
    ),
    S("lima-without-limactl", ["--optional", "lima"], {"lima": "echo 1.0.0"}),
    S(
        "mage-two-lines",
        ["--optional", "mage"],
        {"mage": "printf 'Mage Build Tool\\nv1.15.0\\nCommit: 1.2.3\\n'"},
    ),
    S(
        "mage-third-line-only",
        ["--optional", "mage"],
        {"mage": "printf 'Mage\\nBuild\\n1.15.0\\n'"},
    ),
    S(
        "goreleaser-five-lines",
        ["--optional", "goreleaser"],
        {"goreleaser": "printf 'a\\nb\\nc\\nGitVersion: 2.12.0\\ne\\n'"},
    ),
    S(
        "goreleaser-sixth-line",
        ["--optional", "goreleaser"],
        {"goreleaser": "printf 'a\\nb\\nc\\nd\\ne\\n2.12.0\\n'"},
    ),
    S(
        "python3-stderr",
        ["--required", "python3"],
        {"python3": "echo 'Python 3.14.6' >&2"},
    ),
    S("python3-stdout", ["--required", "python3"], {"python3": "echo 'Python 3.12.1'"}),
    S(
        "python3-interleaved",
        ["--required", "python3"],
        {"python3": "echo 'noise' >&2; echo 'Python 3.12.1'"},
    ),
    S(
        "gh-first-line",
        ["--optional", "gh,gcloud,mise,swift,direnv"],
        {
            "gh": "printf 'gh version 2.95.0 (2026-01-01)\\nhttps://x/v9.9.9\\n'",
            "gcloud": "printf 'Google Cloud SDK 530.0.0\\nbq 2.1.0\\n'",
            "mise": "printf '2026.10.1 macos-arm64\\n'",
            "swift": "printf 'swift-driver version: 1.120.5 Apple Swift version 6.2\\n'",
            "direnv": "echo 2.36.0",
        },
    ),
    S(
        "gh-version-second-line",
        ["--optional", "gh"],
        {"gh": "printf 'gh\\n2.95.0\\n'"},
    ),
    S(
        "generic-key",
        ["--required", "zig", "--optional", "ruff"],
        {"zig": "echo 0.13.0", "ruff": "printf 'ruff\\n0.6.1\\n'"},
    ),
    S(
        "no-dot-version",
        ["--required", "git,node", "--gomod", "x"],
        {"git": "echo 'git version 2'", "node": "echo v22"},
        FULL_FILES,
    ),
    S(
        "empty-output",
        ["--required", "git,bazel"],
        {"git": "", "bazel": ""},
        FULL_FILES,
    ),
    S("trailing-dots", ["--required", "git"], {"git": "echo 'git 1.2...'"}),
    S(
        "stderr-noise-discarded",
        ["--required", "git,node"],
        {"git": "echo junk >&2; echo 2.1.0", "node": "echo bad >&2; exit 3"},
        FULL_FILES,
    ),
    S(
        "nonzero-exit-still-parsed",
        ["--required", "node"],
        {"node": "echo v22.21.1; exit 7"},
        FULL_FILES,
    ),
    S("non-executable-stub", ["--required", "direnv"], {"direnv": None}),
    S("directory-on-path", ["--required", "direnv"], {"direnv/": None}),
    S(
        "long-names",
        ["--optional", "averyveryverylongtoolname,x"],
        {"averyveryverylongtoolname": "echo 'version 123.456.789012'"},
    ),
    S(
        "cache-configured",
        [],
        {},
        {
            "user.bazelrc": b"build --x\n# >>> build cache (managed by tools/remote:setup)\nbuild --y\n"
        },
    ),
    S(
        "cache-marker-indented",
        [],
        {},
        {"user.bazelrc": b"  # >>> build cache (managed by tools/remote:setup)\n"},
    ),
    S(
        "cache-marker-no-newline",
        [],
        {},
        {"user.bazelrc": b"# >>> build cache (managed by tools/remote:setup) v2"},
    ),
    S("cache-other-file", [], {}, {"user.bazelrc": b"build --remote_cache=x\n"}),
    S(
        "nobwd-git-toplevel",
        ["--required", "bazel"],
        {"bazel": OK_BAZEL, "git": 'case "$1" in rev-parse) echo "$GIT_TOP";; esac'},
        {
            ".bazelversion": b"9.2.0\n",
            "top/user.bazelrc": b"# >>> build cache (managed by tools/remote:setup)\n",
        },
        bwd=False,
    ),
    S(
        "nobwd-git-fails",
        [],
        {"git": "exit 128"},
        {"user.bazelrc": b"# >>> build cache (managed by tools/remote:setup)\n"},
        bwd=False,
    ),
    S(
        "nobwd-no-git",
        ["--required", "bazel"],
        {"bazel": OK_BAZEL},
        {
            ".bazelversion": b"9.3.0\n",
            "user.bazelrc": b"# >>> build cache (managed by tools/remote:setup)\n",
        },
        bwd=False,
    ),
    S(
        "nobwd-subdir-root-is-pwd",
        ["--required", "bazel"],
        {"bazel": OK_BAZEL},
        {"sub/.bazelversion": b"9.3.0\n", ".bazelversion": b"1.0.0\n"},
        bwd=False,
        cwd_sub="sub",
    ),
    S(
        "all-ok-tty",
        REQ_ALL + ["--optional", "docker,zig"],
        dict(FULL_STUBS, docker=DOCKER),
        FULL_FILES,
        tty=True,
        env={"DOCKER_INFO_RC": "1"},
    ),
    S(
        "fail-tty",
        ["--required", "bazel,zig"],
        {"bazel": "echo 'Build label: 1.0.0'"},
        FULL_FILES,
        tty=True,
    ),
]


class Parity(unittest.TestCase):
    maxDiff = None

    @classmethod
    def setUpClass(cls):
        cls.top = os.path.realpath(tempfile.mkdtemp())
        cls.sysbin = os.path.join(cls.top, "sysbin")
        os.makedirs(cls.sysbin)
        for u in UTILS:
            real = shutil.which(u, path="/usr/bin:/bin")
            assert real, u
            os.symlink(real, os.path.join(cls.sysbin, u))

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.top, ignore_errors=True)

    def build(self, sc):
        work = os.path.join(self.top, sc["name"])
        root = os.path.join(work, "ws")
        stubs = os.path.join(work, "stubs")
        os.makedirs(root)
        os.makedirs(stubs)
        for rel, data in sc["files"].items():
            p = os.path.join(root, rel)
            os.makedirs(os.path.dirname(p), exist_ok=True)
            with open(p, "wb") as f:
                f.write(data)
        for name, body in sc["stubs"].items():
            if name.endswith("/"):
                os.makedirs(os.path.join(stubs, name))
                continue
            p = os.path.join(stubs, name)
            with open(p, "w") as f:
                f.write('#!/bin/sh\necho "%s $*" >> "$STUB_LOG"\n' % name)
                f.write((body or "") + "\n")
            os.chmod(p, 0o644 if body is None else 0o755)
        env = {
            "PATH": stubs + ":" + self.sysbin,
            "HOME": work,
            "TMPDIR": work,
            "STUB_LOG": os.path.join(work, "stub.log"),
            "GIT_TOP": os.path.join(root, "top"),
        }
        if sc["bwd"]:
            env["BUILD_WORKSPACE_DIRECTORY"] = root
        env.update(sc["env"])
        return work, os.path.join(root, sc["cwd_sub"]), env

    def run_one(self, argv, cwd, env):
        log = env["STUB_LOG"]
        if os.path.exists(log):
            os.remove(log)
        p = subprocess.run(
            argv, cwd=cwd, env=env, capture_output=True, stdin=subprocess.DEVNULL
        )
        logged = b""
        if os.path.exists(log):
            with open(log, "rb") as f:
                logged = f.read()
        return p.returncode, p.stdout, p.stderr, logged

    def run_tty(self, argv, cwd, env):
        master, slave = pty.openpty()
        p = subprocess.Popen(
            argv,
            cwd=cwd,
            env=env,
            stdout=slave,
            stderr=subprocess.PIPE,
            stdin=subprocess.DEVNULL,
        )
        os.close(slave)
        out = b""
        while True:
            try:
                chunk = os.read(master, 4096)
            except OSError:
                break
            if not chunk:
                break
            out += chunk
        assert p.stderr is not None
        err = p.stderr.read()
        p.stderr.close()
        p.wait()
        os.close(master)
        return p.returncode, out, err

    def test_scenarios(self):
        assert BASH, "bash not found"
        seen = 0
        for sc in SCENARIOS:
            with self.subTest(sc["name"]):
                _, cwd, env = self.build(sc)
                sh_argv = [BASH, SH] + sc["args"]
                rs_argv = [RS] + sc["args"]
                if sc["tty"]:
                    a, b = (
                        self.run_tty(sh_argv, cwd, env),
                        self.run_tty(rs_argv, cwd, env),
                    )
                    self.assertIn(b"\x1b[", a[1], "the tty case did not colour")
                else:
                    a, b = (
                        self.run_one(sh_argv, cwd, env),
                        self.run_one(rs_argv, cwd, env),
                    )
                self.assertEqual(a, b, sc["name"])
                seen += 1
        self.assertEqual(seen, len(SCENARIOS))
        print("%d scenarios matched" % seen)


if __name__ == "__main__":
    unittest.main()
