#!/usr/bin/env python3
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
"""Side-by-side parity harness for the shell tools ported to Rust.

Each case runs twice -- once as `bash <script>`, once as the Rust binary --
in two sandboxes built the same way: <base>/<n>/sh and <base>/<n>/rs. Same
length, so a path printed in either reads the same once the sandbox is
replaced with <ROOT>. A case's `setup(root)` writes whatever fakes it needs
(a `gh`, a `gcloud`, an identity map, ...) into its sandbox; the fakes log
their argv and stdin there, so what the tool DID is part of what is compared.

Compared, byte for byte after normalising the sandbox path and mktemp
names: exit code, stdout, stderr, and every file left in the sandbox (path,
permission bits, contents). A difference fails the case with a diff.
"""

import difflib
import os
import re
import shutil
import stat
import subprocess
import sys
import tempfile
from dataclasses import dataclass, field
from typing import Callable, Dict, List, Optional

# mktemp's random part: tmp.XXXXXXXXXX (mktemp -d) and any NAME.XXXXXX
# template a tool passes.
MKTEMP_RE = re.compile(rb"(tmp|github-app-create|github-app-key)\.[A-Za-z0-9]{6,10}")


MKTEMP_DIR_RE = re.compile(rb"(?:/[^\s/<>]+)*/tmp\.[A-Za-z0-9]{6,10}")
BASH_DIAG_RE = re.compile(rb"(?m)^[^\n:]*: line ([0-9]+): ")


@dataclass
class Case:
    name: str
    args: List[str] = field(default_factory=list)
    # Values may say {root} for the sandbox.
    env: Dict[str, str] = field(default_factory=dict)
    stdin: Optional[bytes] = None
    setup: Optional[Callable[[str], None]] = None
    # Extra (pattern, replacement) pairs applied to every compared blob.
    normalise: List = field(default_factory=list)
    # Sandbox paths (regexes, relative to the sandbox) left out of the
    # comparison: a file only one side is expected to leave.
    ignore: List[str] = field(default_factory=list)
    timeout: int = 120


def write_exec(path: str, text: str) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        f.write(text)
    os.chmod(path, 0o755)


def write(path: str, data, mode: int = 0o644) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(data.encode() if isinstance(data, str) else data)
    os.chmod(path, mode)


def snapshot(root: str) -> Dict[str, bytes]:
    files = {}
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames.sort()
        for d in dirnames:
            p = os.path.join(dirpath, d)
            rel = os.path.relpath(p, root)
            files[rel + "/"] = b"dir %o" % (os.lstat(p).st_mode & 0o7777)
        for fn in sorted(filenames):
            p = os.path.join(dirpath, fn)
            rel = os.path.relpath(p, root)
            st = os.lstat(p)
            if stat.S_ISLNK(st.st_mode):
                files[rel] = b"link -> " + os.readlink(p).encode()
                continue
            try:
                with open(p, "rb") as f:
                    body = f.read()
            except PermissionError:
                body = b"<unreadable>"
            files[rel] = b"%o\n" % (st.st_mode & 0o7777) + body
    return files


def resolve(path: str) -> str:
    if not path:
        return path
    if os.path.isabs(path):
        return path
    return os.path.abspath(path)


class Harness:
    def __init__(
        self, title: str, script: str, binary: str, base_path: Optional[str] = None
    ):
        self.title = title
        self.script = resolve(script)
        self.binary = resolve(binary)
        self.base = tempfile.mkdtemp(
            prefix="parity.", dir=os.environ.get("TEST_TMPDIR")
        )
        self.bash = shutil.which("bash") or "/bin/bash"
        self.base_path = base_path or "/usr/bin:/bin:/usr/sbin:/sbin"
        self.failures = 0
        self.count = 0

    def _norm(self, blob: bytes, root: str, case: Case) -> bytes:
        # `mktemp -d` makes $TMPDIR/tmp.XXXXXXXXXX -- except macOS's, which
        # ignores TMPDIR for the per-user temp dir. Where is not the point;
        # that it is a fresh private directory, gone at exit, is.
        blob = MKTEMP_DIR_RE.sub(rb"<TMP>/tmp.XXXXXX", blob)
        blob = blob.replace(root.encode(), b"<ROOT>")
        blob = MKTEMP_RE.sub(rb"\1.XXXXXX", blob)
        # bash names itself (the script path, a line in it) in its own
        # diagnostics; the port names its binary. Same message otherwise.
        blob = BASH_DIAG_RE.sub(rb"<PROG>: line <N>: ", blob)
        for pat, rep in case.normalise:
            blob = re.sub(pat, rep, blob)
        return blob

    def _run_one(self, case: Case, impl: str, n: int):
        root = os.path.join(self.base, "%03d" % n, impl)
        os.makedirs(os.path.join(root, "bin"))
        os.makedirs(os.path.join(root, "home"))
        os.makedirs(os.path.join(root, "tmp"))
        if case.setup:
            case.setup(root)
        env = {
            "PATH": root + "/bin:" + self.base_path,
            "HOME": root + "/home",
            "TMPDIR": root + "/tmp",
        }
        for k, v in case.env.items():
            if v is None:
                env.pop(k, None)
            else:
                env[k] = v.replace("{root}", root)
        argv = [a.replace("{root}", root) for a in case.args]
        cmd = [self.bash, self.script] + argv if impl == "sh" else [self.binary] + argv
        p = subprocess.run(
            cmd,
            input=case.stdin,
            stdin=None if case.stdin is not None else subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env=env,
            cwd=root,
            timeout=case.timeout,
        )
        files = {
            k: v
            for k, v in snapshot(root).items()
            if not any(re.match(p, k) for p in case.ignore)
        }

        def norm(b: bytes) -> bytes:
            return self._norm(b, root, case)

        return (
            p.returncode,
            norm(p.stdout),
            norm(p.stderr),
            {
                norm(k.encode()).decode("utf-8", "replace"): norm(v)
                for k, v in files.items()
            },
        )

    def check(self, case: Case) -> None:
        self.count += 1
        n = self.count
        sh = self._run_one(case, "sh", n)
        rs = self._run_one(case, "rs", n)
        if sh == rs:
            print("  ok    %s  (rc=%d)" % (case.name, sh[0]))
            return
        self.failures += 1
        print("  DIFF  %s" % case.name)
        if sh[0] != rs[0]:
            print("        exit code: sh=%d rs=%d" % (sh[0], rs[0]))
        for label, a, b in (("stdout", sh[1], rs[1]), ("stderr", sh[2], rs[2])):
            if a != b:
                self._diff(label, a, b)
        for k in sorted(set(sh[3]) | set(rs[3])):
            a, b = sh[3].get(k), rs[3].get(k)
            if a != b:
                if a is None or b is None:
                    print(
                        "        file %s: only in %s" % (k, "rs" if a is None else "sh")
                    )
                else:
                    self._diff("file " + k, a, b)

    @staticmethod
    def _diff(label: str, a: bytes, b: bytes) -> None:
        print("        --- %s differs:" % label)
        for line in difflib.unified_diff(
            a.decode("utf-8", "replace").splitlines(),
            b.decode("utf-8", "replace").splitlines(),
            "sh",
            "rs",
            lineterm="",
        ):
            print("          " + line)

    def finish(self) -> int:
        shutil.rmtree(self.base, ignore_errors=True)
        print()
        if self.failures:
            print(
                "%s: %d of %d case(s) differ" % (self.title, self.failures, self.count)
            )
            return 1
        print("%s: all %d case(s) identical" % (self.title, self.count))
        return 0


_WITHOUT_CACHE: Dict[tuple, str] = {}


def path_without(*names: str, base: str = "/usr/bin:/bin:/usr/sbin:/sbin") -> str:
    """A PATH like the harness default with `names` missing from it: one
    directory of links to everything else on `base`. For the cases where a
    tool must be absent -- and must not be found on a machine that really has
    it (a CI runner's /usr/bin/gh would otherwise get called for real)."""
    key = (base,) + tuple(sorted(names))
    if key in _WITHOUT_CACHE:
        return _WITHOUT_CACHE[key]
    d = tempfile.mkdtemp(prefix="path-without.", dir=os.environ.get("TEST_TMPDIR"))
    for src in base.split(":"):
        if not os.path.isdir(src):
            continue
        for n in sorted(os.listdir(src)):
            if n in names or os.path.lexists(os.path.join(d, n)):
                continue
            p = os.path.join(src, n)
            if os.access(p, os.X_OK) and not os.path.isdir(p):
                os.symlink(p, os.path.join(d, n))
    _WITHOUT_CACHE[key] = d
    return d


def need_env(name: str) -> str:
    v = os.environ.get(name)
    if not v:
        print("%s is not set (the BUILD target passes it)" % name, file=sys.stderr)
        sys.exit(2)
    return v
