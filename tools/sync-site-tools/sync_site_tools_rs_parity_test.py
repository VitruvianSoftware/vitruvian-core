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

"""sync (the Rust port) against sync.py: the same files written, byte for
byte, the same stdout, the same stderr and the same exit status.

    bazel test //tools/sync-site-tools:sync_site_tools_rs_parity_test

Every case builds a tree (a copy of this repository's site sources, then a
change), runs sync.py on it, snapshots the tree, builds it again at the same
path and runs the Rust sync on it. Both run in write mode and with --check.
The cases:

  * every test of sync_test.py, as a run of both programs;
  * this repository's own files, from the runfiles and from a copy;
  * Markdown built to break the copies: headings, fences, links of every
    kind, Unicode, CRLF, BOMs, bad UTF-8, `{% endraw`;
  * the samples, methods.json, catalog/tools.json and public-key.txt with
    every shape and type a value can have, and seeded random mutations of
    the real JSON files;
  * plugin folders: manifests of every type, marketplace blocks, hooks,
    skills, rules, sidecars, MCP files, symlinks, unreadable folders,
    names that sort oddly, ids that do not compare;
  * command lines, and writes that fail.

When Python stops with a traceback, its frames name its own files and
lines, which the port cannot have; there only the last line, the exception,
is compared.
"""

import concurrent.futures
import ctypes
import importlib.util
import json
import os
import random
import shutil
import stat
import subprocess
import sys
import tempfile
import threading
import unittest

ROOT = os.getcwd()
HERE = os.path.join(ROOT, "tools", "sync-site-tools")
SYNC_PY = os.path.join(HERE, "sync.py")
SYNC_RS = os.path.abspath(os.environ["SYNC_RS"])


def load(name):
    """A module of this folder by its file: sync_test.py and
    gen_unicode_tables.py are scripts, not libraries a test can depend on."""
    spec = importlib.util.spec_from_file_location(
        name, os.path.join(HERE, f"{name}.py")
    )
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


sys.path.insert(0, HERE)
import sync  # noqa: E402

sync_test = load("sync_test")

SDK = "packages/vitruvian-sdk"
SITE = "apps/web/vitruviansoftware-dev"
PLUGINS = "apps/desktop/antigravity/plugins"
COPIED = [
    ".claude-plugin",
    SITE,
    PLUGINS,
    "catalog",
    SDK,
]
TRACEBACK = b"Traceback (most recent call last):\n"

TMP = ""
BASE = ""
OUTPUTS = []


def setUpModule():
    global TMP, BASE, OUTPUTS
    TMP = tempfile.mkdtemp(dir=os.environ.get("TEST_TMPDIR"))
    BASE = os.path.join(TMP, "base")
    for top in COPIED:
        shutil.copytree(os.path.join(ROOT, top), os.path.join(BASE, top))
    OUTPUTS = sorted(sync.wanted(ROOT))


def tearDownModule():
    # Under Bazel the trees are in TEST_TMPDIR, which Bazel removes with the
    # sandbox, off the test's clock: deleting some 200,000 small files here
    # would take longer than every case together.
    if not os.environ.get("TEST_TMPDIR"):
        discard(TMP)


def shell(script, *args):
    # Copies, deletes and chmods run in a child process: in this one they
    # would hold the GIL, and every worker thread would wait on them.
    subprocess.run(["sh", "-c", script, "sh"] + list(args), check=False)


def discard(tree):
    shell('chmod -R u+rwX "$1" 2>/dev/null; rm -rf "$1"', tree)


def _clonefile():
    """macOS's clonefile(2), which copies a whole tree in one call, copy on
    write; None where there is none."""
    if sys.platform != "darwin":
        return None
    try:
        libc = ctypes.CDLL(None, use_errno=True)
        clone = libc.clonefile
    except (OSError, AttributeError):
        return None
    clone.argtypes = [ctypes.c_char_p, ctypes.c_char_p, ctypes.c_uint32]
    clone.restype = ctypes.c_int
    return clone


CLONEFILE = _clonefile()


def build(tree):
    """A fresh copy of BASE at tree. Writes to it never reach BASE."""
    if (
        CLONEFILE is not None
        and CLONEFILE(os.fsencode(BASE), os.fsencode(tree), 0) == 0
    ):
        return
    shell('cp -R "$1" "$2"', BASE, tree)


def make_writable(tree):
    shell('chmod -R u+rwX "$1" 2>/dev/null', tree)


def snapshot(top):
    """What the programs may have changed: every file sync writes, and the
    folders above it, as what each is and, for a file, its bytes."""
    found = {}
    paths = set()
    for path in OUTPUTS:
        parts = path.split("/")
        for i in range(1, len(parts) + 1):
            paths.add("/".join(parts[:i]))
    for rel in sorted(paths):
        path = os.path.join(top, rel)
        try:
            if os.path.islink(path):
                found[rel] = ("link", os.readlink(path))
            elif os.path.isdir(path):
                found[rel] = ("dir", stat.S_IMODE(os.stat(path).st_mode))
            elif os.path.exists(path):
                with open(path, "rb") as handle:
                    found[rel] = ("file", handle.read())
            else:
                found[rel] = ("missing",)
        except OSError as error:
            found[rel] = ("error", error.errno)
    return found


# --- tree helpers ----------------------------------------------------------


def write(tree, rel, data):
    path = (
        os.path.join(tree, rel)
        if isinstance(rel, str)
        else os.fsencode(tree) + b"/" + rel
    )
    parent = os.path.dirname(path)
    os.makedirs(parent, exist_ok=True)
    if os.path.isdir(path) and not os.path.islink(path):
        shutil.rmtree(path)
    elif os.path.lexists(path):
        os.remove(path)
    with open(path, "wb") as handle:
        handle.write(data.encode("utf-8") if isinstance(data, str) else data)


def read(tree, rel):
    with open(os.path.join(tree, rel), "rb") as handle:
        return handle.read()


def remove(tree, rel):
    path = os.path.join(tree, rel)
    if os.path.isdir(path) and not os.path.islink(path):
        shutil.rmtree(path)
    else:
        os.remove(path)


def dump(value):
    return json.dumps(value, indent=2, ensure_ascii=False)


def catalog_with(tools, **extra):
    data = {"generated": "2026-11-02T10:00:00Z", "tools": tools}
    data.update(extra)
    return dump(data)


def entry(**changes):
    found = json.loads(json.dumps(sync_test.ENTRY))
    for key, value in changes.items():
        if value is DELETE:
            del found[key]
        else:
            found[key] = value
    return found


DELETE = object()


def plugin(tree, name, manifest, where="plugin.json", folder=PLUGINS):
    text = manifest if isinstance(manifest, (str, bytes)) else json.dumps(manifest)
    write(tree, f"{folder}/{name}/{where}", text)


# --- running both ----------------------------------------------------------


def run(program, tree, args, env_root):
    env = {
        "PATH": os.environ.get("PATH", "/usr/bin:/bin"),
        "PYTHONUTF8": "1",
        "PYTHONDONTWRITEBYTECODE": "1",
    }
    if env_root is True:
        env["BUILD_WORKSPACE_DIRECTORY"] = tree
    elif env_root is not None:
        env["BUILD_WORKSPACE_DIRECTORY"] = env_root
    command = [sys.executable, SYNC_PY] if program == "py" else [SYNC_RS]
    done = subprocess.run(
        command + list(args),
        env=env,
        cwd=TMP,
        capture_output=True,
        timeout=60,
    )
    return done.returncode, done.stdout, done.stderr


def stderr_matches(py_err, rs_err):
    if py_err.startswith(TRACEBACK):
        if not rs_err.startswith(TRACEBACK):
            return False
        return (
            py_err.rstrip(b"\n").split(b"\n")[-1]
            == rs_err.rstrip(b"\n").split(b"\n")[-1]
        )
    return py_err == rs_err


_COUNTER = iter(range(1, 1 << 30))
_COUNTER_LOCK = threading.Lock()


def compare(name, mutate, args, env_root=True, snapshot_tree=True, locks=False):
    """Runs both programs on the same tree, rebuilt at the same path for
    each; returns a description of every difference."""
    with _COUNTER_LOCK:
        number = next(_COUNTER)
    tree = os.path.join(TMP, f"case-{number:05d}")
    results = {}
    for program in ("py", "rs"):
        build(tree)
        try:
            mutate(tree)
        except OSError as error:
            # The file system refuses the case (a name it will not hold):
            # nothing to compare.
            discard(tree)
            return [], f"skipped: {error}"
        code, out, err = run(program, tree, args, env_root)
        if locks:
            make_writable(tree)
        results[program] = (code, out, err, snapshot(tree) if snapshot_tree else None)
        # Set aside, not deleted: one rename, where a delete is a call per
        # file (see tearDownModule).
        os.rename(tree, f"{tree}.{program}")
    py, rs = results["py"], results["rs"]
    problems = []
    if py[0] != rs[0]:
        problems.append(f"exit status: py {py[0]} rs {rs[0]}")
    if py[1] != rs[1]:
        problems.append(f"stdout:\n  py {py[1]!r}\n  rs {rs[1]!r}")
    if not stderr_matches(py[2], rs[2]):
        problems.append(f"stderr:\n  py {py[2]!r}\n  rs {rs[2]!r}")
    py_tree, rs_tree = py[3] or {}, rs[3] or {}
    if py_tree != rs_tree:
        keys = sorted(set(py_tree) | set(rs_tree))
        differ = [k for k in keys if py_tree.get(k) != rs_tree.get(k)]
        problems.append(f"tree differs at {differ[:5]}")
    return problems, py


WRITE = (("write", []),)
CHECK = (("check", ["--check"]),)
BOTH = WRITE + CHECK


class Parity(unittest.TestCase):
    def check_cases(self, cases, modes=WRITE, locks=False):
        jobs = []
        for name, mutate in cases:
            for mode, args in modes:
                jobs.append((f"{name} [{mode}]", mutate, args))
        with concurrent.futures.ThreadPoolExecutor(
            max_workers=max(4, os.cpu_count() or 4)
        ) as pool:
            futures = {
                pool.submit(compare, label, mutate, args, locks=locks): label
                for label, mutate, args in jobs
            }
            outcomes = {
                futures[f]: f.result() for f in concurrent.futures.as_completed(futures)
            }
        for label in sorted(outcomes):
            problems, _ = outcomes[label]
            with self.subTest(case=label):
                self.assertEqual(problems, [], label)
        return outcomes


# --- sync_test.py, through both programs -----------------------------------


class SyncTestCases(Parity):
    def test_the_committed_files_are_what_sync_writes(self):
        """sync_test.test_the_committed_files_are_what_sync_writes: --check
        on the runfiles themselves (no BUILD_WORKSPACE_DIRECTORY, so both
        find the repository three folders up from themselves) and on a
        copy."""
        for env_root in (None, ""):
            py = run("py", ROOT, ["--check"], env_root)
            rs = run("rs", ROOT, ["--check"], env_root)
            self.assertEqual(py, (0, b"site tools: in sync\n", b""))
            self.assertEqual(rs, py)
        outcomes = self.check_cases([("committed copy", lambda t: None)], modes=BOTH)
        for label, (_, py) in outcomes.items():
            if label.endswith("[check]"):
                self.assertEqual(py[:3], (0, b"site tools: in sync\n", b""))

    def test_no_copied_file_is_bumped_by_a_release(self):
        """sync_test.test_no_copied_file_is_bumped_by_a_release reads
        sync.sources(): the port must read exactly those files. Each,
        removed or changed, changes both programs the same way."""
        cases = []
        for source in sync.sources():
            path = f"{SDK}/{source}"
            cases.append((f"missing {source}", lambda t, p=path: remove(t, p)))

            def changed(t, p=path):
                text = read(t, p).decode("utf-8")
                if p.endswith(".json") and "methods" in p:
                    data = json.loads(text)
                    data["methods"].append(
                        {
                            "method": "x/é",
                            "sender": "tool",
                            "kind": "notice",
                            "uses": "storage",
                        }
                    )
                    write(t, p, dump(data))
                elif p.endswith(".md"):
                    write(t, p, text + "\nMore, with a [link](../samples/hello-go).\n")
                else:
                    write(t, p, text + "// changed\n")

            cases.append((f"changed {source}", changed))
        self.check_cases(cases, modes=BOTH)

        config = json.loads(read(ROOT, f"{SDK}/release-please-config.json"))
        bumped = {
            e if isinstance(e, str) else e["path"]
            for e in config["packages"][SDK]["extra-files"]
        }
        self.assertEqual(sorted(bumped & set(sync.sources())), [])

    def test_an_entry_as_the_page_reads_it(self):
        """sync_test.test_an_entry_as_the_page_reads_it, as a catalog."""
        cases = [
            (
                "entry",
                lambda t: (
                    write(t, "catalog/tools.json", catalog_with([sync_test.ENTRY])),
                    write(t, "catalog/public-key.txt", "KEY=\n"),
                ),
            ),
            ("no tools", lambda t: write(t, "catalog/tools.json", catalog_with([]))),
            (
                "4000 bytes",
                lambda t: write(
                    t,
                    "catalog/tools.json",
                    catalog_with(
                        [entry(download={"url": "u", "sha256": "s", "size": 4000})]
                    ),
                ),
            ),
        ]
        outcomes = self.check_cases(cases, modes=WRITE)
        tree_py = outcomes["entry [write]"][1][3]
        data = tree_py[f"{SITE}/_data/tools.yml"][1].decode("utf-8")
        self.assertEqual(
            data.splitlines()[2:6],
            [
                'generated: "2026-11-02T10:00:00Z"',
                'public_key: "KEY="',
                "tools:",
                '  - id: "dev.vitruvian.reference"',
            ],
        )
        self.assertIn('    size: "1.7 MB"', data)
        empty = outcomes["no tools [write]"][1][3][f"{SITE}/_data/tools.yml"][1]
        self.assertIn(b"tools: []", empty)
        small = outcomes["4000 bytes [write]"][1][3][f"{SITE}/_data/tools.yml"][1]
        self.assertIn(b'size: "4 KB"', small)

    def test_every_service_has_its_words(self):
        schema = json.loads(read(ROOT, "catalog/catalog.schema.json"))
        services = schema["$defs"]["tool"]["properties"]["uses"]["items"]["enum"]
        cases = [
            (
                "every service",
                lambda t: write(
                    t,
                    "catalog/tools.json",
                    catalog_with([entry(uses=services + ["unknown", "storage"])]),
                ),
            )
        ]
        self.check_cases(cases)

    def test_registry_discovers_all_plugins_and_renders_marketplaces(self):
        outcomes = self.check_cases(
            [
                ("registry as committed", lambda t: None),
                (
                    "claude-code plugins folder",
                    lambda t: (
                        plugin(
                            t,
                            "cc-one",
                            {"name": "cc-one", "description": "One"},
                            ".claude-plugin/plugin.json",
                            "apps/claude-code/plugins",
                        ),
                        write(
                            t,
                            "apps/claude-code/plugins/cc-one/skills/s/SKILL.md",
                            "# s\n",
                        ),
                        write(
                            t, "apps/claude-code/plugins/README.md", "# not a plugin\n"
                        ),
                    ),
                ),
            ],
            modes=WRITE,
        )
        tree = outcomes["registry as committed [write]"][1][3]
        catalog = json.loads(tree[f"{SITE}/ai/catalog.json"][1])
        ids = [e["id"] for e in catalog["extensions"]]
        for expected in (
            "ext-marketplace",
            "gh-watch",
            "mcp-roborock",
            "nexus-agent",
            "mcp-slack",
            "devx",
        ):
            self.assertIn(expected, ids)

    def test_registry_ignores_release_please_version_bumps(self):
        def sample(version):
            def mutate(t):
                d = f"{PLUGINS}/sample-ext"
                write(t, f"{d}/skills/sample-ext/SKILL.md", "# skill\n")
                write(
                    t,
                    f"{d}/.claude-plugin/plugin.json",
                    json.dumps({"name": "sample-ext", "description": "Sample"}),
                )
                write(
                    t,
                    f"{d}/plugin.json",
                    json.dumps(
                        {
                            "name": "sample-ext",
                            "version": version,
                            "description": "Sample",
                        }
                    ),
                )

            return mutate

        outcomes = self.check_cases(
            [("sample 0.1.0", sample("0.1.0")), ("sample 0.2.0", sample("0.2.0"))],
            modes=WRITE,
        )
        before = outcomes["sample 0.1.0 [write]"][1][3]
        after = outcomes["sample 0.2.0 [write]"][1][3]
        for path in (
            f"{SITE}/_data/extensions.yml",
            f"{SITE}/ai/catalog.json",
            ".claude-plugin/marketplace.json",
        ):
            self.assertEqual(before[path], after[path])


# --- Markdown --------------------------------------------------------------

GUIDE = f"{SDK}/docs/writing-a-tool.md"
PROTOCOL = f"{SDK}/protocol/README.md"
KIT = f"{SDK}/samples/hello-go/README.md"


def md(rel, text):
    return lambda t: write(t, rel, text)


class MarkdownCases(Parity):
    def test_markdown(self):
        links = (
            "# Links\n\n"
            "[guide](../docs/writing-a-tool.md) [proto](../protocol/README.md#top)\n"
            "[`../samples/hello-python`](../samples/hello-python) [`../kits/`](../kits/)\n"
            "[a](https://x.y) [b](#anchor) [c](/abs) [d](mailto:x@y) [e](ftp:x) [F](Http:x) [s](a:b) [t](:x) [u](a1:b) [v](é:x)\n"
            "[a [b](c.md) [x](y z) [](d) [e]() [f](g)h) [[n]](m.json#)\n"
            "[ü](./ü.md) [t](a\u2003b) [nested](`code`)\n"
            "`[in code](x.md)` and [x](dir/) and [y](dir/file.tar.gz#a#b)\n"
        )
        texts = {
            "no heading": "Title\n\nbody\n",
            "hash no space": "#Title\nbody\n",
            "empty heading": "# \nbody\n",
            "empty file": "",
            "heading only": "# Only",
            "heading newline only": "# Only\n",
            "unicode title": "#  Ünïcödé “quotes” \\ back\tslash 😀 \u2003\n\nbody\n",
            "control title": "# a\x01b\x7fc\x1fd\n\nbody\n",
            "crlf": "# CRLF\r\n\r\nline one\r\n```python  x\r\ncode\r\n```\r\n",
            "cr only": "# CR\rbody\rmore\r",
            "bom": "\ufeff# BOM\n\nbody\n",
            "endraw": "# T\n\nsome {% endraw %} here\n",
            "endraw in fence": "# T\n\n```\n{% endraw\n```\n",
            "fences": (
                "# Fences\n\n"
                "```python extra words\ncode [x](y)\n```\n"
                "  ```  js  \n  indented\n  ```\n"
                "````\nfour\n````\n"
                "\u3000```x\nideographic space\n```\n"
                "- ```\nnot a fence\n"
                "```\nunclosed [z](w)\n"
            ),
            "leading blank lines": "# T\n\n\n\nbody\n\n\n",
            "links": links,
            "leaves sdk": "# T\n\n[out](../../../etc/passwd)\n",
            "leaves sdk later": "# T\n\nfine [a](b.md)\n\n[out](../../x)\n",
            "dotdot name": "# T\n\n[x](../..foo/bar)\n",
            "liquid": "# T\n\n{{ page.title }} {% if x %}\n",
            "long": "# Long\n\n"
            + "".join(f"line {i} [l{i}](f{i}.md)\n" for i in range(500)),
        }
        cases = []
        for i, (label, text) in enumerate(texts.items()):
            # Each text in one of the three kinds of page, the first few in all.
            for rel in (
                (GUIDE, PROTOCOL, KIT) if i < 6 else [(GUIDE, PROTOCOL, KIT)[i % 3]]
            ):
                cases.append((f"{label} in {rel}", md(rel, text)))
            if label in ("links", "fences", "endraw", "leaves sdk"):
                cases.append(
                    (f"{label}, again", md((GUIDE, PROTOCOL, KIT)[(i + 1) % 3], text))
                )
        bad_bytes = {
            "invalid start": b"# T\n\n\xff\n",
            "truncated": b"# T\n\nabc\xe2\x82",
            "bad continuation": b"# T\n\n\xe2\x28\xa1\n",
            "surrogate bytes": b"# T\n\n\xed\xa0\x80\n",
            "four byte cut": b"# T\n\n\xf0\x9f\x98x\n",
            "overlong": b"# T\n\n\xc0\xaf\n",
        }
        for label, data in bad_bytes.items():
            cases.append((f"{label} in guide", md(GUIDE, data)))
        cases.append(
            (
                "guide is a folder",
                lambda t: (remove(t, GUIDE), os.makedirs(os.path.join(t, GUIDE))),
            )
        )
        cases.append(("protocol heading endraw", md(PROTOCOL, "# {% endraw %}\n")))
        cases.append(("protocol body twice", md(PROTOCOL, "# P\n\nx\n{% endraw %}\n")))
        self.check_cases(cases)

    def test_random_markdown(self):
        rng = random.Random(20261024)
        pieces = [
            "[",
            "]",
            "(",
            ")",
            "`",
            "```",
            "\n",
            " ",
            "#",
            "../",
            "./",
            ".md",
            "{% endraw",
            "é",
            "\u2003",
            "\t",
            "\r\n",
            "x",
            "/",
            ":",
            "a:",
        ]
        cases = []
        for i in range(30):
            rel = rng.choice([GUIDE, PROTOCOL, KIT])

            def mutate(t, rel=rel, seed=rng.random()):
                r = random.Random(seed)
                text = read(t, rel).decode("utf-8")
                for _ in range(r.randint(1, 6)):
                    at = r.randrange(len(text) + 1)
                    if r.random() < 0.3 and text:
                        text = text[:at] + text[at + 1 :]
                    else:
                        text = text[:at] + r.choice(pieces) + text[at:]
                write(t, rel, text)

            cases.append((f"random markdown {i}", mutate))
        self.check_cases(cases)


# --- samples, methods.json -------------------------------------------------

SWIFT_MAIN = f"{SDK}/samples/hello-swift/main.swift"
SWIFT_JSON = f"{SDK}/samples/hello-swift/vitruvian-tool.json"
PY_TOOL = f"{SDK}/samples/hello-python/bin/tool.py"
METHODS = f"{SDK}/protocol/methods.json"


class SampleCases(Parity):
    def test_samples(self):
        cases = [
            ("fence in sample", md(SWIFT_MAIN, "let x = 1\n```\n")),
            ("no final newline", md(SWIFT_MAIN, "let x = 1")),
            ("empty sample", md(SWIFT_MAIN, "")),
            ("newline only", md(SWIFT_MAIN, "\n")),
            ("crlf sample", md(PY_TOOL, "print('a')\r\nprint('b')\r\n")),
            ("unicode sample", md(PY_TOOL, "print('é 😀 \u2028')\n")),
            ("two backticks", md(PY_TOOL, "x = '``'\n")),
            ("bad utf-8 sample", md(SWIFT_JSON, b'{"a": "\xff"}\n')),
            ("missing sample", lambda t: remove(t, PY_TOOL)),
            (
                "sample is a folder",
                lambda t: (
                    remove(t, SWIFT_JSON),
                    os.makedirs(os.path.join(t, SWIFT_JSON)),
                ),
            ),
            ("sample endraw", md(SWIFT_MAIN, "// {% endraw %}\n")),
        ]
        self.check_cases(cases)

    def test_methods(self):
        def methods(value):
            return md(
                METHODS, value if isinstance(value, (str, bytes)) else dump(value)
            )

        row = {"method": "m", "sender": "app", "kind": "request", "uses": None}
        uses_values = [
            None,
            "",
            "storage",
            0,
            1,
            -0.0,
            1.5,
            1e20,
            1e-7,
            True,
            False,
            [],
            {},
            ["a", "b'c", 'd"e', "f'g\"h"],
            {"k": None, "l": [1, 2.5, True]},
            "tab\there",
            "nl\nhere",
            "\x01\x7f\x85\xa0\u2028é😀",
            10**30,
        ]
        cases = []
        for i, uses in enumerate(uses_values):
            cases.append(
                (
                    f"uses {i} {uses!r}"[:60],
                    methods({"methods": [dict(row, uses=uses)]}),
                )
            )
        for key in ("uses", "method", "sender", "kind"):
            broken = dict(row)
            del broken[key]
            cases.append((f"row without {key}", methods({"methods": [broken]})))
        cases += [
            ("methods list", methods([1, 2])),
            ("methods missing", methods({"other": 1})),
            ("methods dict", methods({"methods": {"a": 1}})),
            ("methods empty dict", methods({"methods": {}})),
            ("methods string", methods({"methods": "ab"})),
            ("methods empty string", methods({"methods": ""})),
            ("methods null", methods({"methods": None})),
            ("methods int", methods({"methods": 3})),
            ("methods number", methods("5")),
            ("methods string top", methods('"x"')),
            ("methods null top", methods("null")),
            ("row is list", methods({"methods": [[1]]})),
            ("row is string", methods({"methods": ["abc"]})),
            ("row is null", methods({"methods": [None]})),
            (
                "method values",
                methods(
                    {
                        "methods": [
                            dict(row, method=[1, "x"], sender={"a": "b"}, kind=2.5)
                        ]
                    }
                ),
            ),
            (
                "surrogate method",
                methods(
                    '{"methods": [{"method": "\\ud800", "sender": "a", "kind": "b", "uses": null}]}'
                ),
            ),
            (
                "surrogate in uses list",
                methods(
                    '{"methods": [{"method": "m", "sender": "a", "kind": "b", "uses": ["\\udcff"]}]}'
                ),
            ),
            (
                "nan uses",
                methods(
                    '{"methods": [{"method": NaN, "sender": Infinity, "kind": -Infinity, "uses": NaN}]}'
                ),
            ),
            (
                "duplicate keys",
                methods(
                    '{"methods": [{"method": "a", "method": "b", "sender": "s", "kind": "k", "uses": 1, "uses": 0}]}'
                ),
            ),
            ("bad json", methods("{")),
            ("bom json", methods(b"\xef\xbb\xbf{}")),
            (
                "big int",
                methods(
                    '{"methods": [{"method": 123456789012345678901234567890, "sender": -0, "kind": 1E400, "uses": 0.000001}]}'
                ),
            ),
            (
                "too many digits",
                methods('{"methods": [{"method": ' + "9" * 4301 + "}]}"),
            ),
            (
                "exactly 4300 digits",
                methods(
                    '{"methods": [{"method": '
                    + "9" * 4300
                    + ', "sender": 1, "kind": 1, "uses": 1}]}'
                ),
            ),
        ]
        self.check_cases(cases)


# --- catalog/tools.json, public-key.txt ------------------------------------

CATALOG = "catalog/tools.json"
KEY = "catalog/public-key.txt"


class CatalogCases(Parity):
    def test_catalog_shapes(self):
        def cat(text):
            return md(CATALOG, text)

        sizes = [
            0,
            -5,
            1023,
            1024,
            1535,
            1536,
            2560,
            1048575,
            1048576,
            2359296,
            1834021,
            10**9,
            1.5,
            1e6,
            1048575.9,
            2.5e15,
            True,
            False,
            None,
            "12",
            [1],
            {"a": 1},
            10**30,
            -(10**30),
            -(10**400),
        ]
        cases = []
        for value in sizes:
            cases.append(
                (
                    f"size {value!r}"[:50],
                    cat(
                        catalog_with(
                            [entry(download={"url": "u", "sha256": "s", "size": value})]
                        )
                    ),
                )
            )
        for literal in (
            "NaN",
            "Infinity",
            "-Infinity",
            "1E400",
            "-1e400",
            "1" + "0" * 400,
            "-" + "1" + "0" * 400,
            "1" + "0" * 309,
            "-" + "1" + "0" * 309,
            "4503599627370497",
            "1e-400",
        ):
            text = catalog_with(
                [entry(download={"url": "u", "sha256": "s", "size": 0})]
            ).replace('"size": 0', f'"size": {literal}')
            cases.append((f"size literal {literal[:20]}", cat(text)))
        for key in (
            "id",
            "name",
            "publisher",
            "summary",
            "version",
            "source",
            "download",
            "uses",
        ):
            cases.append(
                (f"entry without {key}", cat(catalog_with([entry(**{key: DELETE})])))
            )
        for key in ("url", "sha256", "size"):
            cases.append(
                (
                    f"download without {key}",
                    cat(
                        catalog_with(
                            [
                                entry(
                                    download={
                                        k: v
                                        for k, v in {
                                            "url": "u",
                                            "sha256": "s",
                                            "size": 1,
                                        }.items()
                                        if k != key
                                    }
                                )
                            ]
                        )
                    ),
                )
            )
        cases += [
            ("name not dict", cat(catalog_with([entry(name="x")]))),
            ("name list", cat(catalog_with([entry(name=["en"])]))),
            ("name without en", cat(catalog_with([entry(name={"fr": "x"})]))),
            ("summary null", cat(catalog_with([entry(summary=None)]))),
            ("download number", cat(catalog_with([entry(download=5)]))),
            (
                "values of every type",
                cat(
                    catalog_with(
                        [
                            entry(
                                id=5,
                                publisher=None,
                                version=1.5,
                                source=[1, "a"],
                                name={"en": {"x": [True]}},
                            )
                        ]
                    )
                ),
            ),
            (
                "unicode values",
                cat(
                    catalog_with(
                        [entry(id="é😀\u2028\x7f", publisher='tab\tnl\n"q"\\')]
                    )
                ),
            ),
            (
                "surrogate value",
                cat(
                    catalog_with([entry()]).replace(
                        '"VitruvianSoftware"', '"\\udc80x"', 1
                    )
                ),
            ),
            (
                "surrogate pair escape",
                cat(
                    catalog_with([entry()]).replace(
                        '"VitruvianSoftware"', '"\\ud83d\\ude00"', 1
                    )
                ),
            ),
            (
                "uses unknown",
                cat(catalog_with([entry(uses=["nope", 1, None, 2.5, True])])),
            ),
            (
                "uses unhashable",
                cat(catalog_with([entry(uses=["notify", ["storage"]])])),
            ),
            ("uses dict item", cat(catalog_with([entry(uses=[{"a": 1}])]))),
            ("uses dict", cat(catalog_with([entry(uses={"notify": 1, "open": 2})]))),
            ("uses string", cat(catalog_with([entry(uses="notify")]))),
            ("uses null", cat(catalog_with([entry(uses=None)]))),
            ("uses number", cat(catalog_with([entry(uses=3)]))),
            ("uses empty", cat(catalog_with([entry(uses=[])]))),
            (
                "two entries",
                cat(catalog_with([entry(), entry(id="second", uses=["open"])])),
            ),
            ("tools absent", cat(dump({"generated": "g"}))),
            ("tools null", cat(dump({"generated": "g", "tools": None}))),
            ("tools zero", cat(dump({"generated": "g", "tools": 0}))),
            ("tools one", cat(dump({"generated": "g", "tools": 1}))),
            ("tools empty string", cat(dump({"generated": "g", "tools": ""}))),
            ("tools string", cat(dump({"generated": "g", "tools": "ab"}))),
            ("tools dict", cat(dump({"generated": "g", "tools": {"a": 1}}))),
            ("tools empty dict", cat(dump({"generated": "g", "tools": {}}))),
            ("tool is string", cat(dump({"generated": "g", "tools": ["x"]}))),
            ("tool is null", cat(dump({"generated": "g", "tools": [None]}))),
            ("generated missing", cat(dump({"tools": []}))),
            (
                "generated types",
                cat(dump({"generated": [1, {"a": None}], "tools": []})),
            ),
            ("catalog list", cat("[1]")),
            ("catalog string", cat('"x"')),
            ("catalog number", cat("1.5")),
            ("catalog null", cat("null")),
            ("missing catalog", lambda t: remove(t, CATALOG)),
            (
                "catalog folder",
                lambda t: (remove(t, CATALOG), os.makedirs(os.path.join(t, CATALOG))),
            ),
            ("catalog crlf", cat(catalog_with([entry()]).replace("\n", "\r\n"))),
            ("catalog bad utf-8", cat(b'{"generated": "\xc3("}')),
            ("key missing", lambda t: remove(t, KEY)),
            ("key non-ascii", md(KEY, "KÉY\n")),
            ("key whitespace", md(KEY, " \x1c\x1d\x1e\x1f\x0b\x0c KEY \t\r\n\n")),
            ("key empty", md(KEY, "")),
            ("key quotes", md(KEY, 'a"b\\c\n')),
            ("key cr", md(KEY, "a\rb\n")),
        ]
        self.check_cases(cases)

    def test_json_errors(self):
        texts = [
            "",
            " ",
            "{",
            "}",
            "[",
            "]",
            "{]",
            "[}",
            '{"a"}',
            '{"a":}',
            '{"a":1,}',
            "[1,]",
            "[1 2]",
            '{"a" 1}',
            '{"a":1 "b":2}',
            "nul",
            "tru",
            "fals",
            "NaN",
            "Infinity",
            "-Infinity",
            "-",
            "-x",
            "01",
            "1.",
            "1.e5",
            "1e",
            "1e+",
            "1e+5",
            ".5",
            "+1",
            '"\\x"',
            '"\\u12"',
            '"\\u12',
            '"\\ud83d\\ude00',
            '"\\ud83d\\u12"',
            '"\\ud83d\\uzzzz"x',
            '"\\ud83d\\ude0',
            '"\\ud83d\\u"',
            '"\\ud800\\u0041"',
            '"\\udc00\\ud800"',
            '"a\x01"',
            '"a\tb"',
            '"abc',
            '"\\',
            '"\\"',
            "1 x",
            "[1] [2]",
            '{"a":[}',
            "\n\n  x",
            '{"a"\n:\n1\n,\n}',
            "\ufeff{}",
            "{}\ufeff",
            "[1,\r\n2,\r\n]",
            '{"\\u00e9": 1, "\\u00e9": 2}',
            "[" * 50 + "]" * 49,
            '{"a": "' + "é" * 30 + '\\q"}',
            "1\x00",
            "\x00",
        ]
        cases = [(f"json {i} {t[:20]!r}", md(CATALOG, t)) for i, t in enumerate(texts)]
        self.check_cases(cases, modes=CHECK)

    def test_random_json(self):
        rng = random.Random(4300)
        palette = [
            '"',
            "\\",
            "{",
            "}",
            "[",
            "]",
            ",",
            ":",
            " ",
            "\n",
            "\r",
            "0",
            "-",
            "e",
            "E",
            ".",
            "u",
            "x",
            "\x01",
            "N",
            "é",
            "1",
            "+",
            "t",
            "n",
            "/",
            "\\u",
            "\\ud83d",
            "😀",
        ]
        targets = [
            CATALOG,
            METHODS,
            f"{PLUGINS}/gh-watch/plugin.json",
            f"{PLUGINS}/hookify/.claude-plugin/plugin.json",
        ]
        cases = []
        for i in range(60):
            rel = targets[i % len(targets)]

            def mutate(t, rel=rel, seed=rng.random()):
                r = random.Random(seed)
                path = os.path.join(t, rel)
                if not os.path.exists(path):
                    return
                text = read(t, rel).decode("utf-8")
                for _ in range(r.randint(1, 4)):
                    at = r.randrange(len(text) + 1)
                    roll = r.random()
                    if roll < 0.3 and text:
                        text = text[:at] + text[at + 1 :]
                    elif roll < 0.4:
                        text = text[:at]
                    else:
                        text = text[:at] + r.choice(palette) + text[at:]
                data = text.encode("utf-8")
                if r.random() < 0.1:
                    at = r.randrange(len(data) + 1)
                    data = (
                        data[:at]
                        + r.choice([b"\xff", b"\xe2\x82", b"\xc3", b"\xed\xa0\x80"])
                        + data[at:]
                    )
                write(t, rel, data)

            cases.append((f"random json {i} {rel}", mutate))
        self.check_cases(cases, modes=WRITE)


# --- plugin folders --------------------------------------------------------


class PluginCases(Parity):
    def test_manifests(self):
        names = [5, 5.5, True, None, [1], {"a": 1}, "x", "", "é😀", "gh-watch"]
        cases = []
        for value in names:
            cases.append(
                (f"name {value!r}", lambda t, v=value: plugin(t, "zz", {"name": v}))
            )
        cases.append(("name NaN", lambda t: plugin(t, "zz", '{"name": NaN}')))
        cases.append(("name missing", lambda t: plugin(t, "zz", {"description": "d"})))
        for text in ("[1]", '"abc"', "5", "null", "{", b"\xff", "\ufeff{}"):
            cases.append((f"manifest {text!r}", lambda t, x=text: plugin(t, "zz", x)))
        customs = [
            "str",
            [1],
            5,
            True,
            {},
            0,
            "",
            None,
            [],
            {"ecosystems": "abc"},
            {"ecosystems": 5},
            {"ecosystems": {"antigravity": 1}},
            {"ecosystems": ["mcp"]},
            {"ecosystems": [None, 1, ["antigravity"]]},
            {"installs": "ab"},
            {"installs": 3},
            {
                "installs": [
                    {
                        "tool": "t",
                        "ecosystem": "e",
                        "label": "l",
                        "command": "c",
                        "extra": [1],
                    }
                ]
            },
            {
                "installs": [
                    {"tool": "t", "ecosystem": "e", "label": "l", "command": "c"},
                    "bad",
                ]
            },
            {"installs": [{"tool": 1}]},
            {"installs": [None]},
            {
                "title": {"nested": [1, 2.5]},
                "status": "released",
                "repo": 7,
                "summary": None,
                "needs": 0,
                "note": "n",
                "category": ["c"],
            },
            {"status": "mirror", "repo": "https://example.com/r"},
            {"status": ["released"]},
            {"status": "released"},
            {"title": "", "category": "", "needs": "", "note": "", "summary": ""},
            {"needs": "custom needs", "note": "custom note", "summary": "s"},
        ]
        for value in customs:
            for key in ("marketplace", "x-vitruvian"):
                cases.append(
                    (
                        f"{key} {value!r}"[:70],
                        lambda t, k=key, v=value: plugin(t, "zz", {"name": "zz", k: v}),
                    )
                )
        cases.append(
            (
                "marketplace falsy then x-vitruvian",
                lambda t: plugin(
                    t,
                    "zz",
                    {"name": "zz", "marketplace": {}, "x-vitruvian": {"title": "X"}},
                ),
            )
        )
        for value in ("str", None, 5, {"a": 1}, ["k", 1, None], "https://r"):
            cases.append(
                (
                    f"repository {value!r}",
                    lambda t, v=value: plugin(t, "zz", {"name": "zz", "repository": v}),
                )
            )
            cases.append(
                (
                    f"keywords {value!r}",
                    lambda t, v=value: plugin(
                        t,
                        "zz",
                        {"name": "zz", "keywords": v},
                        ".claude-plugin/plugin.json",
                    ),
                )
            )
            cases.append(
                (
                    f"description {value!r}",
                    lambda t, v=value: plugin(
                        t, "zz", {"name": "zz", "description": v}
                    ),
                )
            )
        cases += [
            (
                "known id elsewhere",
                lambda t: plugin(
                    t, "other-folder", {"name": "hookify", "description": "dup"}
                ),
            ),
            (
                "claude only",
                lambda t: plugin(t, "zz", {"name": "zz"}, ".claude-plugin/plugin.json"),
            ),
            (
                "both manifests differ",
                lambda t: (
                    plugin(t, "zz", {"name": "a"}),
                    plugin(t, "zz", {"name": "b"}, ".claude-plugin/plugin.json"),
                ),
            ),
            ("no manifest", lambda t: write(t, f"{PLUGINS}/zz/README.md", "x")),
            (
                "manifest is folder",
                lambda t: os.makedirs(os.path.join(t, PLUGINS, "zz", "plugin.json")),
            ),
            ("file among plugins", lambda t: write(t, f"{PLUGINS}/zz-file", "x")),
            (
                "surrogate in manifest",
                lambda t: plugin(t, "zz", '{"name": "zz", "description": "\\udcff"}'),
            ),
            (
                "surrogate id",
                lambda t: plugin(
                    t, "zz", '{"name": "\\ud800"}', ".claude-plugin/plugin.json"
                ),
            ),
            (
                "unicode in manifest",
                lambda t: plugin(
                    t, "zz", {"name": "zz", "description": "é “q” \\ \t 😀 \u2028"}
                ),
            ),
            ("no plugins folder", lambda t: remove(t, PLUGINS)),
            (
                "plugins folder is a file",
                lambda t: (remove(t, PLUGINS), write(t, PLUGINS, "x")),
            ),
            (
                "empty plugins folder",
                lambda t: (remove(t, PLUGINS), os.makedirs(os.path.join(t, PLUGINS))),
            ),
        ]
        self.check_cases(cases)

    def test_capabilities(self):
        def caps(build):
            def mutate(t):
                plugin(t, "zz", {"name": "zz"})
                build(os.path.join(t, PLUGINS, "zz"))

            return mutate

        def files(*pairs):
            def build(d):
                for rel, text in pairs:
                    write(d, rel, text)

            return build

        cases = [
            (
                "hooks dict",
                caps(files(("hooks.json", '{"b": 1, "a": 2, "é": 3, "B": 4}'))),
            ),
            ("hooks list", caps(files(("hooks.json", "[1]")))),
            ("hooks invalid", caps(files(("hooks.json", "{")))),
            ("hooks bad utf-8", caps(files(("hooks.json", b"\xff")))),
            ("hooks empty dict", caps(files(("hooks.json", "{}")))),
            (
                "hooks folder",
                caps(lambda d: os.makedirs(os.path.join(d, "hooks.json"))),
            ),
            (
                "skills",
                caps(
                    files(
                        ("skills/b/SKILL.md", "x"),
                        ("skills/a/SKILL.md", "x"),
                        ("skills/é/SKILL.md", "x"),
                        ("skills/Z/SKILL.md", "x"),
                        ("skills/no-skill/README.md", "x"),
                        ("skills/file.md", "x"),
                    )
                ),
            ),
            ("one skill", caps(files(("skills/only/SKILL.md", "x")))),
            (
                "skill md is folder",
                caps(lambda d: os.makedirs(os.path.join(d, "skills", "s", "SKILL.md"))),
            ),
            ("no skills", caps(lambda d: os.makedirs(os.path.join(d, "skills")))),
            (
                "rules",
                caps(
                    files(
                        ("rules/b.md", "x"),
                        ("rules/a.md", "x"),
                        ("rules/c.txt", "x"),
                        ("rules/.md", "x"),
                        ("rules/d.MD", "x"),
                    )
                ),
            ),
            (
                "rules folder named md",
                caps(lambda d: os.makedirs(os.path.join(d, "rules", "x.md"))),
            ),
            (
                "sidecar",
                caps(
                    files(
                        ("sidecars/b/sidecar.json", "{}"),
                        ("sidecars/a/other.json", "{}"),
                    )
                ),
            ),
            ("sidecar file only", caps(files(("sidecars/sidecar.json", "{}")))),
            ("mcp", caps(files((".mcp.json", "{}")))),
            ("mcp plain", caps(files(("mcp.json", "{}")))),
            (
                "everything",
                caps(
                    files(
                        ("hooks.json", '{"x": 1}'),
                        ("skills/s/SKILL.md", "x"),
                        ("rules/r.md", "x"),
                        ("sidecars/p/sidecar.json", "{}"),
                        (".mcp.json", "{}"),
                        (".claude-plugin/plugin.json", '{"name": "zz"}'),
                    )
                ),
            ),
            (
                "skills with custom ecosystems",
                lambda t: (
                    plugin(
                        t,
                        "zz",
                        {
                            "name": "zz",
                            "marketplace": {"ecosystems": ["codex-opencode"]},
                        },
                    ),
                    write(t, f"{PLUGINS}/zz/skills/s/SKILL.md", "x"),
                ),
            ),
            (
                "symlinked skill",
                caps(
                    lambda d: (
                        write(d, "real/SKILL.md", "x"),
                        os.makedirs(os.path.join(d, "skills")),
                        os.symlink("../real", os.path.join(d, "skills", "linked")),
                    )
                ),
            ),
            (
                "broken symlink skill",
                caps(
                    lambda d: (
                        os.makedirs(os.path.join(d, "skills")),
                        os.symlink("nowhere", os.path.join(d, "skills", "gone")),
                    )
                ),
            ),
            (
                "looping symlink",
                caps(
                    lambda d: (
                        os.makedirs(os.path.join(d, "skills")),
                        os.symlink("loop", os.path.join(d, "skills", "loop")),
                    )
                ),
            ),
            (
                "symlinked plugin",
                lambda t: os.symlink("gh-watch", os.path.join(t, PLUGINS, "zz-link")),
            ),
            (
                "broken plugin symlink",
                lambda t: os.symlink("nowhere", os.path.join(t, PLUGINS, "zz-gone")),
            ),
        ]
        self.check_cases(cases)

    def test_unreadable(self):
        if os.geteuid() == 0:
            self.skipTest("root reads everything: both programs would just read")

        def locked(rel, mode=0):
            return lambda t: os.chmod(os.path.join(t, rel), mode)

        cases = [
            ("plugins folder unreadable", locked(PLUGINS)),
            (
                "plugin folder unreadable",
                lambda t: (
                    plugin(t, "zz", {"name": "zz"}),
                    os.chmod(os.path.join(t, PLUGINS, "zz"), 0),
                ),
            ),
            (
                "plugin folder unlistable",
                lambda t: (
                    plugin(t, "zz", {"name": "zz"}),
                    write(t, f"{PLUGINS}/zz/skills/s/SKILL.md", "x"),
                    os.chmod(os.path.join(t, PLUGINS, "zz", "skills"), 0o311),
                ),
            ),
            (
                "manifest unreadable",
                lambda t: (
                    plugin(t, "zz", {"name": "zz"}),
                    os.chmod(os.path.join(t, PLUGINS, "zz", "plugin.json"), 0),
                ),
            ),
            (
                "hooks unreadable",
                lambda t: (
                    plugin(t, "zz", {"name": "zz"}),
                    write(t, f"{PLUGINS}/zz/hooks.json", "{}"),
                    os.chmod(os.path.join(t, PLUGINS, "zz", "hooks.json"), 0),
                ),
            ),
            ("guide unreadable", locked(GUIDE)),
            ("docs unreadable", locked(f"{SDK}/docs")),
            ("catalog unreadable", locked(CATALOG)),
            ("key unreadable", locked(KEY)),
            ("committed copy unreadable", locked(f"{SITE}/tools/guide.md")),
            ("site tools folder read-only", locked(f"{SITE}/tools", 0o555)),
            ("committed copy read-only", locked(f"{SITE}/_data/tools.yml", 0o444)),
        ]
        self.check_cases(cases, modes=BOTH, locks=True)

    def test_ordering(self):
        def several(*ids):
            def mutate(t):
                for i, value in enumerate(ids):
                    text = (
                        value
                        if isinstance(value, str) and value.startswith("{")
                        else json.dumps({"name": value})
                    )
                    plugin(t, f"p{i:03d}", text)

            return mutate

        cases = [
            ("str and int ids", several("zzz", 5)),
            ("int and str ids", several(5, "zzz")),
            ("three mixed", several(3, "b", 2.5)),
            ("equal numbers", several(5, 5.0, True, 1)),
            ("nan ids", several('{"name": NaN}', '{"name": NaN}', "a")),
            ("nan and number", several('{"name": NaN}', 1, '{"name": NaN}', 0)),
            ("null ids", several(None, None)),
            ("null and str", several(None, "a")),
            ("bool ids", several(True, False, 2)),
            (
                "preferred and unknown",
                several(
                    "zeta",
                    "savvy-fleet",
                    "alpha",
                    "ext-marketplace",
                    "Beta",
                    "é",
                    "日本",
                ),
            ),
            ("descending run", several("e", "d", "c", "b", "a", "f")),
            ("ascending then not", several("a", "b", "c", "a", "b")),
            ("big ints", several(10**30, 10**30 + 1, -(10**30), 1e30)),
            (
                "many plugins",
                several(*[f"plugin-{(i * 37) % 70:02d}" for i in range(70)]),
            ),
        ]
        self.check_cases(cases, modes=WRITE)

    def test_odd_names(self):
        names = [
            "Zed",
            "a b",
            "é",
            "e\u0301",
            "日本",
            "-dash",
            ".hidden",
            "x\ty",
            "1",
            "~",
        ]

        def mutate(t):
            for name in names:
                plugin(t, name, {"name": "n-" + name, "description": name})
                write(t, f"{PLUGINS}/{name}/skills/{name}/SKILL.md", "x")
                write(t, f"{PLUGINS}/{name}/rules/{name}.md", "x")

        def undecodable(t):
            base = os.fsencode(os.path.join(t, PLUGINS))
            os.makedirs(base + b"/bad\xff/skills/s\xfe", exist_ok=True)
            with open(base + b"/bad\xff/plugin.json", "w") as handle:
                handle.write('{"name": "bad"}')
            with open(base + b"/bad\xff/skills/s\xfe/SKILL.md", "w") as handle:
                handle.write("x")

        def undecodable_skill(t):
            plugin(t, "zz", {"name": "zz"})
            base = os.fsencode(os.path.join(t, PLUGINS, "zz"))
            os.makedirs(base + b"/skills/s\xfe", exist_ok=True)
            with open(base + b"/skills/s\xfe/SKILL.md", "w") as handle:
                handle.write("x")

        outcomes = self.check_cases(
            [
                ("odd names", mutate),
                ("undecodable folder", undecodable),
                ("undecodable skill", undecodable_skill),
            ]
        )
        self.assertTrue(any(not label.startswith("undecodable") for label in outcomes))


# --- command lines and writes ----------------------------------------------


class CommandLineCases(Parity):
    def test_arguments(self):
        jobs = [
            ["--check", "x"],
            ["x", "--check"],
            ["--CHECK"],
            ["--check="],
            ["-h"],
            ["--help"],
            [b"\xff", "--check"],
            ["--check", "--check"],
            ["", "--check"],
        ]
        for args in jobs:
            with self.subTest(args=args):
                problems, _ = compare(f"args {args!r}", lambda t: None, args)
                self.assertEqual(problems, [])
        for env_root in (os.path.join(TMP, "nowhere"), "relative/path", "."):
            with self.subTest(env_root=env_root):
                problems, _ = compare(
                    f"root {env_root}",
                    lambda t: None,
                    ["--check"],
                    env_root=env_root,
                    snapshot_tree=False,
                )
                self.assertEqual(problems, [])

    def test_check_finds_stale_files(self):
        cases = [
            ("stale guide", md(f"{SITE}/tools/guide.md", "old\n")),
            ("missing copy", lambda t: remove(t, f"{SITE}/tools/examples/go.md")),
            (
                "copy is a folder",
                lambda t: (
                    remove(t, f"{SITE}/ai/catalog.json"),
                    os.makedirs(os.path.join(t, SITE, "ai", "catalog.json")),
                ),
            ),
            (
                "copy is a symlink",
                lambda t: (
                    remove(t, ".claude-plugin/marketplace.json"),
                    os.symlink(
                        os.path.join(t, SITE, ".claude-plugin", "marketplace.json"),
                        os.path.join(t, ".claude-plugin", "marketplace.json"),
                    ),
                ),
            ),
            (
                "copy is a broken symlink",
                lambda t: (
                    remove(t, f"{SITE}/_data/tools.yml"),
                    os.symlink("nowhere", os.path.join(t, SITE, "_data", "tools.yml")),
                ),
            ),
            (
                "every copy missing",
                lambda t: (
                    remove(t, f"{SITE}/tools"),
                    remove(t, f"{SITE}/_data"),
                    remove(t, f"{SITE}/ai"),
                    remove(t, ".claude-plugin"),
                    remove(t, f"{SITE}/.claude-plugin"),
                ),
            ),
        ]
        outcomes = self.check_cases(cases, modes=BOTH)
        self.assertEqual(outcomes["stale guide [check]"][1][0], 1)

    def test_writes_that_fail(self):
        cases = [
            (
                "target is a folder",
                lambda t: (
                    remove(t, f"{SITE}/tools/guide.md"),
                    os.makedirs(os.path.join(t, SITE, "tools", "guide.md", "x")),
                ),
            ),
            (
                "parent is a file",
                lambda t: (
                    remove(t, f"{SITE}/tools/examples"),
                    write(t, f"{SITE}/tools/examples", "x"),
                ),
            ),
            (
                "grandparent is a file",
                lambda t: (remove(t, f"{SITE}/tools"), write(t, f"{SITE}/tools", "x")),
            ),
            (
                "parent is a broken symlink",
                lambda t: (
                    remove(t, f"{SITE}/ai"),
                    os.symlink("nowhere", os.path.join(t, SITE, "ai")),
                ),
            ),
            (
                "parent is a symlinked folder",
                lambda t: (
                    shutil.move(
                        os.path.join(t, SITE, "ai"), os.path.join(t, "elsewhere")
                    ),
                    os.symlink(
                        os.path.join(t, "elsewhere"), os.path.join(t, SITE, "ai")
                    ),
                ),
            ),
            ("folders to make", lambda t: remove(t, SITE)),
        ]
        self.check_cases(cases, modes=WRITE)


class UnicodeTables(unittest.TestCase):
    def test_tables_are_this_pythons(self):
        gen_unicode_tables = load("gen_unicode_tables")

        with open(
            os.path.join(HERE, "src", "unicode_tables.rs"), encoding="utf-8"
        ) as handle:
            self.assertEqual(
                handle.read(),
                gen_unicode_tables.render(),
                "run: python3 tools/sync-site-tools/gen_unicode_tables.py > tools/sync-site-tools/src/unicode_tables.rs",
            )


if __name__ == "__main__":
    unittest.main()
