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

"""lint-naming-rs, the Rust port, against lint_naming.py: same exit code,
same stdout, same stderr, byte for byte.

    bazel test //tools/lint-naming:lint_naming_rs_parity_test

The inputs:

  * every case in tests/. The four tiers run here with each rule function,
    the scanner and lint_naming.main wrapped: every rule call is replayed
    through lint-naming-rs-probe (which calls the port's function of the
    same name) and the results compared; every scan and every main() is
    rerun, at the time, through both programs;
  * testdata/clean_repo and testdata/violations, through both programs;
  * trees built here to break them: every rule's good and bad names,
    Unicode, newlines and backslashes in names, symlinks (to directories,
    broken, looping), unreadable files and directories, BUILD files that
    parse, that fall back to the regular expressions, and that make
    ast.parse print SyntaxWarnings (with and without the source line),
    workflows, CRLF, BOMs and bytes that are not UTF-8;
  * command lines: help at many terminal widths, abbreviations, every
    argparse error this parser can raise, BUILD_WORKSPACE_DIRECTORY;
  * BUILD-file parsing directly: a corpus of awkward snippets and a seeded
    mutation fuzz, compared with ast.parse and ast.walk;
  * this repository's own tree, when the test can see it.

Both programs run from copies in a directory of their own, the Rust one
under the name lint_naming.py so argparse's usage line reads the same.
When Python crashes (an uncaught exception) its traceback names its own
files and lines, which the port cannot have, so there only the last line,
the exception, is compared.
"""

import ast
import contextlib
import io
import os
import random
import shutil
import subprocess
import sys
import tempfile
import unittest
import warnings
from concurrent.futures import ThreadPoolExecutor

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import gen_unicode_tables  # noqa: E402
import lint_naming  # noqa: E402
import scanner as scanner_mod  # noqa: E402
from rules import bazel, configs, directories, environment, migration, source_files  # noqa: E402
from tests import (  # noqa: E402
    tier1_feature_test,
    tier2_boundary_test,
    tier3_pairwise_test,
    tier4_realworld_test,
)

TRACEBACK = b"Traceback (most recent call last):"


def _path_env(name):
    path = os.environ.get(name, "")
    if not path:
        raise unittest.SkipTest(f"{name} is not set; run this under bazel test")
    return os.path.abspath(path)


# ---- running the two programs ------------------------------------------------


class Programs:
    """lint_naming.py and lint-naming-rs, each in a directory of its own."""

    def __init__(self):
        self.tmp = tempfile.mkdtemp(prefix="lint-naming-parity-")
        self.py_dir = os.path.join(self.tmp, "py")
        self.rs_dir = os.path.join(self.tmp, "rs")
        os.makedirs(os.path.join(self.py_dir, "rules"))
        os.makedirs(self.rs_dir)
        for name in ("lint_naming.py", "scanner.py", "__init__.py"):
            shutil.copy(os.path.join(HERE, name), self.py_dir)
        for name in os.listdir(os.path.join(HERE, "rules")):
            if name.endswith(".py"):
                shutil.copy(
                    os.path.join(HERE, "rules", name),
                    os.path.join(self.py_dir, "rules"),
                )
        self.rs = os.path.join(self.rs_dir, "lint_naming.py")
        shutil.copy(_path_env("LINT_NAMING_RS"), self.rs)
        os.chmod(self.rs, 0o755)
        self.probe_bin = _path_env("LINT_NAMING_RS_PROBE")
        self.count = 0

    def case_dir(self):
        self.count += 1
        path = os.path.join(self.tmp, "cases", str(self.count))
        os.makedirs(path)
        return path

    def env(self, extra=None, drop=()):
        env = {
            k: v
            for k, v in os.environ.items()
            if not k.startswith("PYTHON")
            and k not in ("COLUMNS", "LINES", "BUILD_WORKSPACE_DIRECTORY")
            and k not in drop
        }
        env.update(extra or {})
        return env

    def run(self, kind, args, cwd, env):
        if kind == "py":
            argv = [sys.executable, os.path.join(self.py_dir, "lint_naming.py")] + args
        else:
            argv = [self.rs] + args
        proc = subprocess.run(argv, cwd=cwd, env=env, capture_output=True, timeout=60)
        return proc.returncode, proc.stdout, proc.stderr

    def both(self, args, cwd=None, extra_env=None, drop_env=()):
        cwd = cwd or self.tmp
        env = self.env(extra_env, drop_env)
        return self.run("py", args, cwd, env), self.run("rs", args, cwd, env)


def differs(py, rs):
    """None when the two runs agree, else what differs."""
    if py[0] != rs[0]:
        return f"exit {py[0]} (python) != {rs[0]} (rust)\n--- python stderr\n{py[2][-2000:]!r}\n--- rust stderr\n{rs[2][-2000:]!r}"
    if py[1] != rs[1]:
        return f"stdout differs:\n--- python\n{py[1][-3000:]!r}\n--- rust\n{rs[1][-3000:]!r}"
    if py[2].startswith(TRACEBACK):
        last = lambda e: e.rstrip(b"\n").split(b"\n")[-1]  # noqa: E731
        if not rs[2].startswith(TRACEBACK) or last(py[2]) != last(rs[2]):
            return f"crash differs:\n--- python\n{py[2]!r}\n--- rust\n{rs[2]!r}"
        return None
    if py[2] != rs[2]:
        return f"stderr differs:\n--- python\n{py[2][-3000:]!r}\n--- rust\n{rs[2][-3000:]!r}"
    return None


# ---- the probe ---------------------------------------------------------------


def _enc(x):
    if x is None:
        return "=-"
    if isinstance(x, bool):
        return "=1" if x else "=0"
    if isinstance(x, int):
        return f"={x}"
    return x.encode("utf-8", "surrogatepass").hex()


def violations_repr(vs):
    return repr(
        [
            (
                v.rule_id,
                v.file_path,
                v.line_number,
                v.severity.value,
                v.message,
                v.suggested_fix,
            )
            for v in vs
        ]
    )


def probe(programs, calls):
    """Run each call ([verb, args...]) through the probe; its output lines."""
    if not calls:
        return []
    text = "".join("\t".join([c[0]] + [_enc(a) for a in c[1:]]) + "\n" for c in calls)
    proc = subprocess.run(
        [programs.probe_bin], input=text.encode(), capture_output=True, timeout=120
    )
    if proc.returncode != 0:
        raise AssertionError(f"probe failed: {proc.stderr.decode(errors='replace')}")
    return proc.stdout.decode("utf-8", "surrogateescape").split("\n")[: len(calls)]


def syntax_warnings(caught):
    """The SyntaxWarnings: the ones Python prints by default. (rules/bazel.py
    also touches ast.Str, a DeprecationWarning, which it does not.)"""
    return [
        (w.lineno, str(w.message))
        for w in caught
        if issubclass(w.category, SyntaxWarning)
    ]


def build_expected(file_path, content):
    """validate_build_file_content's result and the warnings ast.parse raised."""
    with warnings.catch_warnings(record=True) as caught:
        warnings.simplefilter("always")
        result = ORIGINALS["build"](file_path, content)
    vs = [
        (
            v.rule_id,
            v.file_path,
            v.line_number,
            v.severity.value,
            v.message,
            v.suggested_fix,
        )
        for v in result
    ]
    return result, repr((vs, syntax_warnings(caught)))


def pyast_expected(content):
    """ast.parse and ast.walk, as the probe's "pyast" call reports them."""
    with warnings.catch_warnings(record=True) as caught:
        warnings.simplefilter("always")
        try:
            tree = ast.parse(content)
        except Exception:
            return repr((None, syntax_warnings(caught)))
    calls = []
    for node in ast.walk(tree):
        if isinstance(node, ast.Call):
            f = node.func
            rt = (
                f.id
                if isinstance(f, ast.Name)
                else f.attr
                if isinstance(f, ast.Attribute)
                else None
            )
            kws = [
                (
                    kw.arg,
                    kw.lineno,
                    kw.value.value
                    if isinstance(kw.value, ast.Constant)
                    and isinstance(kw.value.value, str)
                    else None,
                )
                for kw in node.keywords
            ]
            calls.append((rt, kws))
    return repr((calls, syntax_warnings(caught)))


# ---- recording the test suites' calls ---------------------------------------

ORIGINALS = {
    "dir": directories.validate_directory_name,
    "file": source_files.validate_file_name,
    "config": configs.validate_config_file_name,
    "workflow": configs.validate_workflow_yaml_content,
    "k8s": configs.validate_k8s_resource_name,
    "pulumi": configs.validate_pulumi_config_key,
    "target": bazel.validate_bazel_target_name,
    "starlark": bazel.validate_starlark_file_name,
    "build": bazel.validate_build_file_content,
    "env": environment.validate_env_var_name,
    "flag": environment.validate_cli_flag_name,
    "risk": migration.assess_rename_risk,
    "alias": migration.validate_alias_compatibility,
    "symlink": migration.validate_symlink_alias,
}

FUNC_NAMES = {f.__name__: verb for verb, f in ORIGINALS.items()}


class Recorder:
    def __init__(self, programs):
        self.programs = programs
        self.calls = []  # (verb, args, expected repr)
        self.failures = []
        self.scans = 0
        self.mains = 0

    def wrap(self, verb):
        original = ORIGINALS[verb]

        def defaults(args, kwargs):
            # Fill in the defaults the probe needs spelled out.
            import inspect

            bound = inspect.signature(original).bind(*args, **kwargs)
            bound.apply_defaults()
            return list(bound.arguments.values())

        def wrapper(*args, **kwargs):
            full = defaults(args, kwargs)
            if verb == "build":
                result, expected = build_expected(*full)
            else:
                result = original(*args, **kwargs)
                if verb == "risk":
                    expected = repr(result.value)
                else:
                    expected = violations_repr(result)
            if verb == "alias":
                old, new, mapping = full
                flat = [old, new]
                for k, v in mapping.items():
                    flat += [k, v]
                full = flat
            if verb == "symlink":
                # The filesystem may be gone by replay time: probe now.
                got = probe(self.programs, [[verb] + full])[0]
                if got != expected:
                    self.failures.append(
                        f"{verb}{tuple(full)!r}: python {expected} rust {got}"
                    )
                return result
            self.calls.append(([verb] + full, expected))
            return result

        wrapper.__name__ = original.__name__
        return wrapper

    def replay(self):
        got = probe(self.programs, [c for c, _ in self.calls])
        for (call, expected), line in zip(self.calls, got):
            if expected != line:
                self.failures.append(f"{call!r}:\n  python {expected}\n  rust   {line}")


@contextlib.contextmanager
def recording(recorder):
    """Wrap the rule functions, the scanner and main() everywhere they are bound."""
    modules = [
        directories,
        source_files,
        configs,
        bazel,
        environment,
        migration,
        scanner_mod,
        tier1_feature_test,
        tier2_boundary_test,
        tier3_pairwise_test,
        tier4_realworld_test,
    ]
    saved = []
    for module in modules:
        for name, verb in FUNC_NAMES.items():
            if getattr(module, name, None) is ORIGINALS[verb]:
                saved.append((module, name, ORIGINALS[verb]))
                setattr(module, name, recorder.wrap(verb))

    cls = scanner_mod.RepositoryNamingScanner
    orig_scan, orig_ignore, orig_format, orig_init = (
        cls.scan,
        cls.should_ignore,
        cls.format_report,
        cls.__init__,
    )
    programs = recorder.programs

    def init(self, root_dir, ignores=None, ignore_violation_fixtures=True):
        orig_init(self, root_dir, ignores, ignore_violation_fixtures)
        self._parity_args = (root_dir, ignores, ignore_violation_fixtures)
        got = probe(
            programs, [["rootdir", root_dir, ignore_violation_fixtures, "default"]]
        )[0]
        if got != repr(self.root_dir):
            recorder.failures.append(
                f"root_dir({root_dir!r}): python {self.root_dir!r} rust {got}"
            )

    def ignore_args(self):
        root, ignores, flag = self._parity_args
        return [root, flag] + (["default"] if ignores is None else sorted(ignores))

    def scan(self):
        result = orig_scan(self)
        recorder.scans += 1
        root, ignores, flag = self._parity_args
        a = ignore_args(self)
        got = probe(programs, [["scan"] + a])[0]
        if got != violations_repr(result):
            recorder.failures.append(
                f"scan{tuple(a)!r}:\n  python {violations_repr(result)}\n  rust   {got}"
            )
        if ignores is None and flag:
            for args in (
                ["--root", root],
                ["--root", root, "--format", "json"],
                ["--root", root, "--strict"],
            ):
                why = differs(*programs.both(args))
                if why:
                    recorder.failures.append(f"main{args!r}: {why}")
        return result

    def should_ignore(self, rel_path):
        result = orig_ignore(self, rel_path)
        a = ignore_args(self)
        got = probe(programs, [["ignore", a[0], a[1], rel_path] + a[2:]])[0]
        if got != repr(result):
            recorder.failures.append(
                f"should_ignore({rel_path!r}): python {result} rust {got}"
            )
        return result

    def format_report(self, violations, output_format="text"):
        result = orig_format(self, violations, output_format)
        flat = [output_format]
        for v in violations:
            flat += [
                v.rule_id,
                v.file_path,
                v.line_number,
                v.severity.value,
                v.message,
                "-" if v.suggested_fix is None else v.suggested_fix,
            ]
        recorder.calls.append((["format"] + flat, repr(result)))
        return result

    orig_main = lint_naming.main

    def main(argv=None):
        recorder.mains += 1
        why = differs(*programs.both(list(argv or [])))
        if why:
            recorder.failures.append(f"main({argv!r}): {why}")
        return orig_main(argv)

    cls.__init__, cls.scan, cls.format_report = init, scan, format_report
    scanner_mod.RepositoryNamingScanner.should_ignore = should_ignore
    lint_naming.main = main
    try:
        yield
    finally:
        cls.__init__, cls.scan, cls.should_ignore, cls.format_report = (
            orig_init,
            orig_scan,
            orig_ignore,
            orig_format,
        )
        lint_naming.main = orig_main
        for module, name, original in saved:
            setattr(module, name, original)


# ---- inputs built here -------------------------------------------------------

BUILD_SNIPPETS = [
    'sh_binary(name = "bad_name", srcs = ["a.sh"])\n',
    'sh_binary(\n    srcs = ["s.sh"],\n    # c\n    name = "bad_binary_name",\n)\n',
    'load("@x//:y.bzl", "z")\nnative.go_library(name = "a-b")\nx = [go_test(name = "c-d")]\n',
    'sh_test(name = "Bad")\nsh_test(name = "good_test")\nsh_test(name = "a-b_test")\n',
    'oci_image(name = "my_image")\nfoo_binary(name = "x_y")\nrust_library(name = "a_b")\n',
    'cc_binary(name = "a" "_b")\ncc_binary(name = f"x_y")\ncc_binary(name = b"x_y")\ncc_binary(name = "")\n',
    'cc_binary(name = "x\\x5fy")\ncc_binary(name = ("p_q"))\ncc_binary(**{"name": "r_s"})\n',
    'f(g(name = "a_b"), sh_binary(name = "c_d"))\nsh_binary(name = "e_f"); sh_binary(name = "g_h")\n',
    'def m(name):\n    sh_binary(name = "in_def")\n[sh_binary(name = "i_" + x) for x in y]\n',
    'x = "\\d"\nsh_binary(name = "after_warning")\n',
    'x = "\\d" + "\\q"\ny = b"\\400"\nz = f"\\{w}"\nsh_binary(name = "w_w")\n',
    'x = 1if 1 else 2\ny = = 1\nsh_binary(name = "fallback_one")\n',
    'sh_binary(name = "unclosed_one"\n',
    "$\nsh_binary(\n  name = 'bad_one')\nload(name = \"a_b\")\n",
    'x = "\\d"\nif True:\nsh_binary(name = "indent_err")\n',
    'sh_binary(name = "a_b")\x00\n',
    'match x:\n    case [a, *b] if a:\n        sh_binary(name = "m_x")\n    case {"k": 1, **r}:\n        pass\n',
    'type X = int\ndef f[T](x: T, /, *, y=1) -> T: ...\nsh_binary(name = "t_t")\n',
    "\ufeffsh_binary(name = 'bom_x')\n",
    'sh_binary(name = """multi\nline_x""")\n',
    'go_library(name = "x-y",\n           srcs = glob(["*.go"]),\n           deps = select({"//c": [":a"]}))\n',
    "sh_binary(name = 'q_q')\r\nsh_binary(name = 'r_r')\rsh_binary(name = 's_s')\n",
    'x = f"""a\n{1}\\d\n"""\nsh_binary(name = "f_f")\n',
    "print 'x'\nsh_binary(name = 'py2_x')\n",
    "# only comments\n\n   \n",
    "",
    " \x1c\n",
]

WORKFLOWS = [
    "name: CI\non:\n  workflow_dispatch:\n    inputs:\n      target_environment:\n        description: x\njobs:\n  build_image:\n    runs-on: x\n    steps:\n      - id: run_test\n        run: |\n          id: inner_var\n      - name: x\n        id: 'quoted_id'\n",
    "jobs:\n  ok-job:\n    outputs:\n      some_output: x\n    steps:\n      - id: ${{ matrix.step_id }}\n",
    "\ufeffjobs:\r\n  crlf_job:\r\n    runs-on: x\r\n",
    "on:\n  workflow_call:\n    outputs:\n      out_key:\n        value: x\n",
]

NAMES = [
    "net-hubs.go",
    "cloud_dns.go",
    "cloud_dns_test.go",
    "A.GO",
    "stream-hook.py",
    "__init__.py",
    "ok_mod.py",
    "affected_targets.sh",
    "check_version_maps_test.sh",
    "fine-name.sh",
    "run_me.zsh",
    "x.bash",
    "bad_component.tsx",
    "App.tsx",
    "App.test.tsx",
    "page.tsx",
    "__x.tsx",
    "api-client.ts",
    "bad_name.ts",
    "x_y.d.ts",
    "postcss.config.mjs",
    "w_x.cjs",
    "core.swift",
    "Core2D.swift",
    "My_Doc.md",
    "README.md",
    "v1.0.0-release.md",
    "2026-01-02-plan.md",
    "TODO_LIST.md",
    "bad-macro.bzl",
    "defs.bzl",
    "Pulumi.dev.yaml",
    "values.yaml",
    ".DS_Store",
    "noext",
    "..sh",
    "ünïcode_x.go",
    "🚀-rocket.md",
    "tab\there.py",
    "back\\slash.go",
    "new\nline.go",
    "trailing.go\n",
]


def write(path, content, mode="w"):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    if isinstance(content, bytes):
        with open(path, "wb") as f:
            f.write(content)
    else:
        with open(path, "w", encoding="utf-8", newline="") as f:
            f.write(content)


def build_tree(root, rnd):
    """A tree touching every rule, and the walker's corners."""
    for i, name in enumerate(NAMES):
        try:
            write(os.path.join(root, "files", f"d{i % 5}", name), "x\n")
        except OSError:
            pass
    for d in [
        "tools/ci_preflight",
        "Bad_Root",
        "pkg/cloud_dns",
        "infrastructure/pulumi/net_hubs/mod_x",
        "macos/Sources/NexusAgent",
        "app/[id]",
        "app/[...slug]",
        "app/(group)",
        "web/__tests__",
        "tabula/web/prisma/migrations/20260524120000_init",
        ".hidden/x",
        ".github/workflows",
        ".gitlab",
        "node_modules/bad_x",
        "a/testdata/violations/bad_y",
        "a/b/testdata/q",
        "sdk/x_y",
        "dist/q_r",
        "deep/" + "/".join(f"l{i}" for i in range(20)),
        "Sources/Mixed_Case",
        "ünï/çödé",
    ]:
        os.makedirs(os.path.join(root, d), exist_ok=True)
    for i, content in enumerate(BUILD_SNIPPETS):
        write(
            os.path.join(root, "builds", f"b{i}", "BUILD" if i % 2 else "BUILD.bazel"),
            content,
        )
    write(
        os.path.join(root, "builds", "latin", "BUILD"),
        b"x = '\xe9\\d'\nsh_binary(name = 'lat_in')\n",
    )
    write(
        os.path.join(root, "builds", "cookie", "BUILD"),
        b"# -*- coding: latin-1 -*-\nx = '\\d'\n",
    )
    for i, content in enumerate(WORKFLOWS):
        write(
            os.path.join(
                root, ".github", "workflows", f"w{i}_bad.yaml" if i % 2 else f"w{i}.yml"
            ),
            content,
        )
    write(
        os.path.join(root, "nested", ".github", "workflows", "_reusable-ok.yaml"),
        WORKFLOWS[0],
    )
    write(os.path.join(root, "x.github/workflowsy", "Mixed.yaml"), WORKFLOWS[1])
    write(
        os.path.join(root, "bytes", ".github", "workflows", "bin.yaml"),
        b"jobs:\n  a_\xff_b:\n    x: y\n",
    )
    # Symlinks: to a directory, broken, a loop, and a BUILD that is a link.
    os.symlink(os.path.join(root, "pkg"), os.path.join(root, "link_to_pkg"))
    os.symlink("nowhere", os.path.join(root, "broken_link.go"))
    os.symlink(root, os.path.join(root, "loop_link"))
    os.makedirs(os.path.join(root, "linked"), exist_ok=True)
    os.symlink(
        os.path.join(root, "builds", "b0", "BUILD.bazel"),
        os.path.join(root, "linked", "BUILD"),
    )
    # Random names.
    alphabet = "abcXYZ019_-.é"
    for i in range(40):
        name = "".join(rnd.choice(alphabet) for _ in range(rnd.randrange(1, 10)))
        ext = rnd.choice(
            [".go", ".py", ".sh", ".ts", ".tsx", ".md", ".swift", ".bzl", ".yaml", ""]
        )
        try:
            write(os.path.join(root, "random", name + ext), "")
        except OSError:
            pass
        try:
            os.makedirs(os.path.join(root, "random", name, "sub" + name), exist_ok=True)
        except OSError:
            pass


def try_make_unreadable(root):
    """An unreadable file and directory; False when permissions do not bite (root)."""
    f = os.path.join(root, "locked", "BUILD")
    write(f, 'sh_binary(name = "locked_x")\n')
    d = os.path.join(root, "locked_dir", "inner_x")
    os.makedirs(d)
    write(os.path.join(d, "bad-name.go"), "")
    os.chmod(f, 0)
    os.chmod(os.path.join(root, "locked_dir"), 0)
    return lambda: (
        os.chmod(f, 0o644),
        os.chmod(os.path.join(root, "locked_dir"), 0o755),
    )


ARGVS = [
    [],
    ["-h"],
    ["--help"],
    ["--he"],
    ["--h"],
    ["-hx"],
    ["-hh"],
    ["-h=1"],
    ["-h-"],
    ["-hh=x"],
    ["--format", "xml"],
    ["--format"],
    ["--format="],
    ["--format=json"],
    ["--f=json"],
    ["--fo", "json"],
    ["--root"],
    ["--ro"],
    ["--root="],
    ["--root", "-x"],
    ["--root", "-1"],
    ["--root", "-1.5"],
    ["--root", "--"],
    ["--strict=1"],
    ["--strict="],
    ["--check=x"],
    ["--s"],
    ["--c"],
    ["--bogus"],
    ["-x"],
    ["-"],
    ["--"],
    ["--", "--strict"],
    ["pos1", "pos2"],
    ["a", "--bogus", "b"],
    ["--=x"],
    ["--="],
    ["---x"],
    ["-x=1"],
    ["--root", "a b"],
    ["has space"],
    ["--format", "text", "--format", "json"],
    ["--bogus", "-h"],
    ["--format", "xml", "-h"],
    ["-h", "--format", "xml"],
    ["--format", "Text"],
    ["--format", "jsön"],
    ["--format", "a\nb"],
    ["--format", "it's"],
    ["--root", "/nonexistent/dir"],
    ["--root", "BUILD"],
    ["--strict", "--check", "--format", "json"],
]


class ParityTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.programs = Programs()

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.programs.tmp, ignore_errors=True)

    def assertSame(self, args, **kw):
        why = differs(*self.programs.both(args, **kw))
        self.assertIsNone(why, f"{args!r} {kw!r}: {why}")

    def test_unicode_tables_are_current(self):
        with open(
            os.path.join(HERE, "src", "unicode_tables.rs"), encoding="utf-8"
        ) as f:
            self.assertEqual(
                f.read(),
                gen_unicode_tables.render(),
                "regenerate src/unicode_tables.rs",
            )

    def test_every_case_in_tests(self):
        recorder = Recorder(self.programs)
        suite = unittest.TestSuite()
        loader = unittest.TestLoader()
        for module in (
            tier1_feature_test,
            tier2_boundary_test,
            tier3_pairwise_test,
            tier4_realworld_test,
        ):
            suite.addTests(loader.loadTestsFromModule(module))
        with recording(recorder):
            result = unittest.TextTestRunner(stream=io.StringIO(), verbosity=0).run(
                suite
            )
        self.assertTrue(
            result.wasSuccessful(),
            f"the Python suites themselves fail: {result.failures + result.errors}",
        )
        self.assertGreaterEqual(result.testsRun, 145)
        recorder.replay()
        self.assertGreater(len(recorder.calls), 300)
        self.assertGreater(recorder.scans, 10)
        self.assertGreater(recorder.mains, 1)
        self.assertEqual(recorder.failures, [], "\n\n".join(recorder.failures[:20]))

    def test_testdata(self):
        for name in ("clean_repo", "violations"):
            root = os.path.join(HERE, "testdata", name)
            for extra in ([], ["--format", "json"], ["--strict"]):
                self.assertSame(["--root", root] + extra)
            # Relative to the working directory too, so SyntaxWarnings could
            # print their source lines.
            self.assertSame(["--root", "."], cwd=root)
        self.assertSame(
            [],
            cwd=os.path.join(HERE, "testdata"),
            extra_env={"BUILD_WORKSPACE_DIRECTORY": "violations"},
        )

    def test_generated_trees(self):
        for seed in range(3):
            root = self.programs.case_dir()
            build_tree(root, random.Random(seed))
            for extra in ([], ["--format", "json"], ["--strict"]):
                self.assertSame(["--root", root] + extra)
            self.assertSame(["--root", "."], cwd=root)
            self.assertSame(["--root", "builds"], cwd=root)
            self.assertSame(["--root", "builds/b10"], cwd=root)
            self.assertSame(
                ["--format", "json"], extra_env={"BUILD_WORKSPACE_DIRECTORY": root}
            )
            self.assertSame(["--root", root + "/./builds/../builds"])

    def test_unreadable_entries(self):
        root = self.programs.case_dir()
        build_tree(root, random.Random(7))
        restore = try_make_unreadable(root)
        try:
            self.assertSame(["--root", root])
            self.assertSame(["--root", "."], cwd=root)
        finally:
            restore()

    def test_names_that_are_not_utf8(self):
        root = self.programs.case_dir()
        try:
            os.makedirs(os.path.join(os.fsencode(root), b"bad\xffdir_x"))
            with open(
                os.path.join(os.fsencode(root), b"bad\xffdir_x", b"BUILD"), "w"
            ) as f:
                f.write("x = '\\d'\nsh_binary(name = 'nonutf_x')\n")
            open(os.path.join(os.fsencode(root), b"x\xfe-y.go"), "w").close()
        except OSError:
            self.skipTest("this file system rejects names that are not UTF-8")
        for env in (
            {"LC_ALL": "C"},
            {"LC_ALL": "en_US.UTF-8"},
            {"PYTHONUTF8": "1"},
            {"PYTHONIOENCODING": "utf-8:backslashreplace"},
        ):
            self.assertSame(["--root", root], extra_env=env)
            self.assertSame(["--root", root, "--format", "json"], extra_env=env)

    def test_command_lines(self):
        cwd = os.path.join(HERE, "testdata", "clean_repo")
        jobs = [(argv, {}) for argv in ARGVS]
        jobs += [
            (["-h"], {"COLUMNS": str(c)})
            for c in list(range(1, 60)) + [61, 70, 78, 80, 81, 99, 100, 120, 200]
        ]
        jobs += [
            (["--bogus"], {"COLUMNS": str(c)})
            for c in (1, 10, 20, 30, 40, 50, 60, 72, 73, 74, 75, 76)
        ]
        jobs += [
            (["-h"], {"COLUMNS": c}) for c in (" 40 ", "4_0", "-5", "0", "x", "٤٠", "")
        ]
        jobs += [
            ([], {"BUILD_WORKSPACE_DIRECTORY": ""}),
            ([], {"BUILD_WORKSPACE_DIRECTORY": cwd}),
        ]

        def run(job):
            argv, env = job
            return argv, env, differs(*self.programs.both(argv, cwd=cwd, extra_env=env))

        with ThreadPoolExecutor(max_workers=8) as pool:
            for argv, env, why in pool.map(run, jobs):
                self.assertIsNone(why, f"{argv!r} {env!r}: {why}")

    def test_build_parsing_directly(self):
        corpus = list(BUILD_SNIPPETS)
        for path in sorted(os.listdir(HERE)) + [
            os.path.join("rules", n)
            for n in sorted(os.listdir(os.path.join(HERE, "rules")))
        ]:
            full = os.path.join(HERE, path)
            if path.endswith(".py") or os.path.basename(path) == "BUILD":
                with open(full, encoding="utf-8", errors="ignore") as f:
                    corpus.append(f.read())
        rnd = random.Random(20261024)
        alphabet = list("()[]{},:;=.*+-/%@!~^&|<>\"'#\\\n\t abfjrxN019_") + [
            "if ",
            "else ",
            "for ",
            " in ",
            "lambda",
            "f'",
            '"""',
            "\\d",
            "\\x4",
            "1if",
            "{{",
            "}}",
            "match ",
            "case ",
            ":=",
            "**",
            "é",
            "€",
            "\r",
            "\x0c",
        ]
        fuzzed = []
        for _ in range(1500):
            s = rnd.choice(corpus)
            if len(s) > 2500:
                a = rnd.randrange(len(s) - 2000)
                s = s[a : a + rnd.randrange(100, 2000)]
            for _ in range(rnd.choice([1, 1, 2, 3])):
                pos = rnd.randrange(len(s) + 1)
                if rnd.random() < 0.5:
                    s = s[:pos] + s[pos + 1 :]
                else:
                    s = s[:pos] + rnd.choice(alphabet) + s[pos:]
            fuzzed.append(s)
        calls = [["pyast", c] for c in corpus + fuzzed] + [
            ["build", "pkg/BUILD", c] for c in corpus + fuzzed
        ]
        expected = [pyast_expected(c) for c in corpus + fuzzed] + [
            build_expected("pkg/BUILD", c)[1] for c in corpus + fuzzed
        ]
        got = probe(self.programs, calls)
        bad = [(c, e, g) for c, e, g in zip(calls, expected, got) if e != g]
        # Files ast.parse rejects can make CPython's error-reporting pass
        # decode strings beyond where parsing failed; the port follows the
        # common case of that, not every path of the pass. So a rejected
        # file may differ in its SyntaxWarnings alone, never in violations.
        strict = [
            (c, e, g)
            for c, e, g in bad
            if not (e.startswith("(None,") and g.startswith("(None,"))
        ]
        strict += [
            (c, e, g)
            for c, e, g in bad
            if c[0] == "build" and ast.literal_eval(e)[0] != ast.literal_eval(g)[0]
        ]
        self.assertEqual(
            strict,
            [],
            "\n".join(f"{c!r}\n  python {e}\n  rust   {g}" for c, e, g in strict[:10]),
        )
        self.assertLess(
            len(bad),
            len(calls) // 200,
            "\n".join(f"{c!r}\n  python {e}\n  rust   {g}" for c, e, g in bad[:10]),
        )

    def test_this_repository(self):
        repo = os.path.dirname(
            os.path.dirname(
                os.path.dirname(os.path.realpath(os.path.join(HERE, "BUILD")))
            )
        )
        if not os.path.exists(os.path.join(repo, "MODULE.bazel")):
            self.skipTest("the source tree is not visible from this sandbox")
        self.assertSame(["--root", repo])
        self.assertSame(["--root", repo, "--format", "json"])
        self.assertSame(["--root", "."], cwd=repo)


if __name__ == "__main__":
    unittest.main()
