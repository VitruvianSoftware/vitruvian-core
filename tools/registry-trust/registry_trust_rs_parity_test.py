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

"""registry-trust-rs, the Rust port, against inventory.py, check.py and
setup_publishers.py: the same exit code, stdout and stderr, byte for byte,
and the same requests made, on every input here.

    bazel test //tools/registry-trust:registry_trust_rs_parity_test

The scripts run in this process with fakes for the network, as their own
tests run them; the port runs as a program with REGISTRY_TRUST_RECORDED,
which gives it the same recorded answers. Each side logs every fetch and
every crates.io request (whether the token was the expected one, never the
token), and the logs must match too. npm's hand-off runs for real on both
sides, against a stand-in setup.sh that records what it was given.

The inputs:

  * every scenario of inventory_test.py, check_test.py and
    setup_publishers_test.py that a command line can reach. Those that test
    one function from inside (parse_ledger, request_for, http_fetch's
    retries, the token's headers) have their twins in the Rust unit tests,
    registry_trust_lib_test; here they are reached through `check` and
    `setup` instead, where the command line can reach them;
  * the real copy.bara.sky, with a package under every mirror it declares;
  * inputs built to break them: configs and package files that are not
    JSON or TOML, cut short at every character; workflows written every
    way the parser has to cope with; ledgers with every kind of wrong row.
"""

import contextlib
import copy
import io
import json
import os
import random
import shutil
import subprocess
import sys
import tempfile
import traceback
import unittest
from unittest import mock

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import check  # noqa: E402
import fixture_repo  # noqa: E402
import inventory  # noqa: E402
import setup_publishers as setup  # noqa: E402

RS = os.path.abspath(os.environ.get("REGISTRY_TRUST_RS", ""))
REPO = os.path.join(HERE, "..", "..")

PUBSUB = "@vitruviansoftware/foundation-pubsub"
KIT = "@vitruviansoftware/tool-kit"
CRATE = "vitruvian-tool-kit"
NPM = "https://registry.npmjs.org/"
CRATES = "https://crates.io/api/v1/crates/"
PYPI = "https://pypi.org/"
TOKEN = "cio-test-token-that-must-never-be-shown"
LIST = "https://crates.io/api/v1/trusted_publishing/github_configs?crate=example-kit"
CREATE = "https://crates.io/api/v1/trusted_publishing/github_configs"
WANTED = {
    "crate": "example-kit",
    "repository_owner": "Example",
    "repository_name": "sdk-mirror",
    "workflow_filename": "release.yml",
    "environment": "crates-io",
}
PYPI_FILES = [
    "vitruvian_tool_kit-0.10.0-py3-none-any.whl",
    "vitruvian_tool_kit-0.10.0.tar.gz",
    "vitruvian_tool_kit-1.0.0-py3-none-any.whl",
    "vitruvian_tool_kit-1.0.0.tar.gz",
    "vitruvian_tool_kit-1.1.0-py3-none-any.whl",
    "vitruvian_tool_kit-1.1.0.tar.gz",
]

# Records what it was handed, prints nothing, and exits as .npm-exit says.
# Only bash builtins: the environment it runs in may have no PATH.
NPM_STAND_IN = """\
ran="$BUILD_WORKSPACE_DIRECTORY/.npm-ran"
{
  printf '%s\\n' "$0"
  while IFS= read -r line || [ -n "$line" ]; do printf '%s\\n' "$line"; done < "$NPM_TP_PACKAGES"
} > "$ran"
code=0
[ -f "$BUILD_WORKSPACE_DIRECTORY/.npm-exit" ] && read -r code < "$BUILD_WORKSPACE_DIRECTORY/.npm-exit"
exit "$code"
"""


def recorded(name):
    with open(os.path.join(HERE, "testdata", name), encoding="utf-8") as handle:
        return json.load(handle)


def provenance(name):
    version = name.split("-")[1].removesuffix(".tar.gz")
    return f"{PYPI}integrity/vitruvian-tool-kit/{version}/{name}/provenance"


class World:
    """Recorded answers, in the form both sides read."""

    def __init__(self, token=TOKEN):
        self.fetch = {}
        self.send = {}
        self.token = token

    def put(self, url, body, status=200):
        text = body if isinstance(body, str) else json.dumps(body)
        self.fetch[url] = [status, text]

    def answer(self, method, url, body, status=200):
        text = body if isinstance(body, str) else json.dumps(body)
        self.send[f"{method} {url}"] = [status, text]


class Run:
    def __init__(self, code, out, err, log, npm):
        self.code, self.out, self.err, self.log, self.npm = code, out, err, log, npm

    def triple(self):
        return (self.code, self.out, self.err, self.log, self.npm)


def take(path):
    if not os.path.exists(path):
        return None
    with open(path, encoding="utf-8") as handle:
        text = handle.read()
    os.remove(path)
    return text


# How many runs were compared, by exit code: printed at the end, so a run
# that compared nothing (or never reached a crash) shows in the log.
COMPARED = {}


def tearDownModule():
    total = sum(COMPARED.values())
    shown = ", ".join(f"exit {code}: {n}" for code, n in sorted(COMPARED.items()))
    print(f"\nregistry-trust parity: {total} runs compared ({shown})", file=sys.stderr)


class Parity(unittest.TestCase):
    """Runs a command through both and insists they agree."""

    maxDiff = None

    def setUp(self):
        if not os.path.isfile(RS):
            self.fail("REGISTRY_TRUST_RS is not the binary; run this under bazel test")
        self._tmp = tempfile.TemporaryDirectory(dir=os.environ.get("TEST_TMPDIR"))
        self.addCleanup(self._tmp.cleanup)
        self.tmp = self._tmp.name
        self.runs = 0

    def fresh(self, name="repo"):
        root = os.path.join(self.tmp, name)
        shutil.rmtree(root, ignore_errors=True)
        os.makedirs(root)
        return root

    def npm_stand_in(self, root, exit_code=0):
        fixture_repo.write(root, setup.NPM_SETUP, NPM_STAND_IN)
        if exit_code:
            fixture_repo.write(root, ".npm-exit", f"{exit_code}\n")

    # --- the two sides -----------------------------------------------------

    def python(self, command, argv, root, world, env):
        log = []

        def fetch(url):
            log.append(["fetch", url])
            if url not in world.fetch:
                raise AssertionError(f"asked for {url}, which no scenario recorded")
            status, body = world.fetch[url]
            return status, body.encode()

        def send(method, url, token, body=None):
            log.append(["send", method, url, token == world.token, body])
            status, text = world.send[f"{method} {url}"]
            return status, text.encode()

        out, err = io.StringIO(), io.StringIO()
        try:
            code = self.call(command, argv, root, env, fetch, send, out, err)
        except AssertionError:
            raise
        except Exception as error:  # noqa: BLE001 - the script crashed
            # Python's frames name its own files, which the port cannot;
            # what both print is the first line and the exception.
            code = 1
            err.write("Traceback (most recent call last):\n")
            err.write(traceback.format_exception_only(error)[-1])
        npm = take(os.path.join(root, ".npm-ran"))
        return Run(code, out.getvalue(), err.getvalue(), log, npm)

    @staticmethod
    def call(command, argv, root, env, fetch, send, out, err):
        if command == "inventory":
            patched = {"BUILD_WORKSPACE_DIRECTORY": root}
            with mock.patch.dict(os.environ, patched), contextlib.redirect_stderr(err):
                return inventory.main(list(argv), out=out)
        if command == "check":
            return check.main(list(argv), fetch=fetch, out=out, err=err, root=root)
        return setup.main(
            list(argv),
            root=root,
            env=dict(env),
            fetch=fetch,
            send=send,
            run_npm=setup.run_npm_setup,
            out=out,
            err=err,
        )

    def rust(self, command, argv, root, world, env, argv0=None):
        self.runs += 1
        log_path = os.path.join(self.tmp, f"log-{self.runs}.jsonl")
        answers = os.path.join(self.tmp, f"answers-{self.runs}.json")
        with open(answers, "w", encoding="utf-8") as handle:
            json.dump(
                {
                    "fetch": world.fetch,
                    "send": world.send,
                    "token": world.token,
                    "log": log_path,
                },
                handle,
            )
        child = dict(env)
        child.update(
            BUILD_WORKSPACE_DIRECTORY=root,
            REGISTRY_TRUST_RECORDED=answers,
            TEST_TMPDIR=os.environ.get("TEST_TMPDIR", self.tmp),
            TMPDIR=self.tmp,
        )
        if argv0:
            command_line = [argv0, *argv]
        else:
            command_line = [RS, command, *argv]
        done = subprocess.run(command_line, env=child, capture_output=True, timeout=60)
        log = []
        if os.path.exists(log_path):
            with open(log_path, encoding="utf-8") as handle:
                log = [json.loads(line) for line in handle if line.strip()]
        npm = take(os.path.join(root, ".npm-ran"))
        return Run(
            done.returncode, done.stdout.decode(), done.stderr.decode(), log, npm
        )

    def both(
        self, command, argv=(), root=None, world=None, env=None, code=None, argv0=None
    ):
        world = world or World()
        env = env if env is not None else {}
        py = self.python(command, argv, root, world, env)
        rs = self.rust(command, argv, root, world, env, argv0=argv0)
        label = f"{command} {' '.join(argv)}".strip()
        self.assertEqual(rs.triple(), py.triple(), label)
        COMPARED[py.code] = COMPARED.get(py.code, 0) + 1
        if code is not None:
            self.assertEqual(py.code, code, f"{label}: {py.out}{py.err}")
        return py


# --- inventory --------------------------------------------------------------------

SIMPLE_COPYBARA = """\
STANDALONE_SSH_PREFIX = "git@github.com:Example/"

COMPONENTS = [
    {
        "name": "pkgs",
        "standalone_only": [],
    },
]
"""

PUBLISH_ALL = """\
jobs:
  npm:
    runs-on: ubuntu-latest
    steps:
      - run: npm publish
  pypi:
    runs-on: ubuntu-latest
    steps:
      - run: uv publish
  crates:
    runs-on: ubuntu-latest
    steps:
      - run: cargo publish
"""


def one_package_repo(root, file, text, workflow=PUBLISH_ALL, copybara=SIMPLE_COPYBARA):
    """pkgs/ with one release-please package whose version file is `file`."""
    jsonpath = {
        "package.json": "$.version",
        "pyproject.toml": "$.project.version",
        "Cargo.toml": "$.package.version",
    }[file]
    fixture_repo.write(root, inventory.COPYBARA, copybara)
    config = {
        "release-type": "simple",
        "packages": {
            "pkgs": {"extra-files": [{"path": f"p/{file}", "jsonpath": jsonpath}]}
        },
    }
    fixture_repo.write(root, "pkgs/release-please-config.json", json.dumps(config))
    fixture_repo.write(root, f"pkgs/p/{file}", text)
    fixture_repo.write(root, "pkgs/.github/workflows/release.yml", workflow)
    return root


class InventoryParity(Parity):
    def fixture(self):
        return fixture_repo.make(self.fresh())

    def both_ways(self, root, code=0):
        for argv in ((), ("--all",), ("--json",), ("--json", "--all")):
            self.both("inventory", argv, root=root, code=code)

    def test_the_fixture_every_way_it_is_printed(self):
        root = self.fixture()
        self.both_ways(root)
        self.both("inventory", ("--frobnicate",), root=root, code=0)

    def test_a_package_added_to_release_please(self):
        root = self.fixture()
        fixture_repo.node_package(
            root, "packages/lib/ts/packages/new", "@example/new", "0.1.0"
        )
        self.both_ways(root)

    def test_two_jobs_that_publish_one_registry(self):
        root = self.fixture()
        fixture_repo.write(
            root,
            "packages/sdk/.github/workflows/again.yml",
            "jobs:\n  twice:\n    runs-on: ubuntu-latest\n    steps:\n      - run: cargo publish\n",
        )
        self.both_ways(root, code=2)

    def test_a_config_whose_version_file_is_missing(self):
        root = self.fixture()
        os.remove(os.path.join(root, "packages/sdk/kits/rs/Cargo.toml"))
        self.both_ways(root, code=2)

    def test_no_copybara_file_and_broken_ones(self):
        root = self.fixture()
        os.remove(os.path.join(root, inventory.COPYBARA))
        self.both_ways(root, code=2)
        for text in (
            "",
            'STANDALONE_SSH_PREFIX = "git@github.com:Example/"\n',
            'STANDALONE_SSH_PREFIX = "git@github.com:Example/"\nCOMPONENTS = [\n]\n',
            'STANDALONE_SSH_PREFIX = "git@github.com:Example/"\nCOMPONENTS = [\n    {\n        "repo": "x",\n    },\n]\n',
            '# STANDALONE_SSH_PREFIX = "git@github.com:Other/"\n'
            + fixture_repo.COPYBARA,
            fixture_repo.COPYBARA.replace("Example/", "Ex\nample/"),
            fixture_repo.COPYBARA.replace(
                '        "repo": "sdk-mirror",\n',
                '        "repo": "sdk-mirror",\n        # "repo": "commented",\n',
            ),
            fixture_repo.COPYBARA.replace("    {\n", "  {\n", 1),
            fixture_repo.COPYBARA
            + 'COMPONENTS = [\n    {\n        "name": "late",\n    },\n]\n',
            fixture_repo.COPYBARA.replace("\n", "\r\n"),
            fixture_repo.COPYBARA.encode().decode() + "\n\xff",
        ):
            fixture_repo.write(root, inventory.COPYBARA, text)
            self.both_ways(root, code=None)
        with open(os.path.join(root, inventory.COPYBARA), "wb") as handle:
            handle.write(b"STANDALONE \xff\xfe")
        self.both_ways(root, code=2)
        os.remove(os.path.join(root, inventory.COPYBARA))
        os.makedirs(os.path.join(root, inventory.COPYBARA))
        self.both_ways(root, code=2)

    def test_the_real_copybara_file_with_a_package_under_every_mirror(self):
        root = self.fresh()
        shutil.copy(
            os.path.join(REPO, inventory.COPYBARA), os.path.join(root, "copy.bara.sky")
        )
        fixture_repo.write(
            root, inventory.COPYBARA, open(os.path.join(root, "copy.bara.sky")).read()
        )
        found = inventory.mirrors(root)
        self.assertGreater(len(found), 10)
        for index, (subtree, _, _) in enumerate(found):
            fixture_repo.node_package(
                root, f"{subtree}/zz-parity", f"@parity/p{index}", f"0.{index}.0"
            )
            fixture_repo.write(
                root,
                f"{subtree}/.github/workflows/release.yml",
                "jobs:\n  publish:\n    environment: npm\n    steps:\n      - run: npm publish\n",
            )
        run = self.both("inventory", ("--json",), root=root, code=0)
        self.assertEqual(len(json.loads(run.out)), len(found))
        self.both("inventory", ("--all",), root=root, code=0)

    def test_a_mirror_inside_another_mirror_s_folder(self):
        """The package belongs to the mirror with the longest subtree that
        holds it, whatever order copy.bara.sky lists them in."""
        components = [
            ("outer", "packages"),
            ("inner", "packages/sdk"),
            ("deepest", "packages/sdk/kits/ts"),
        ]
        for order in (
            components,
            components[::-1],
            [components[1], components[0], components[2]],
        ):
            root = self.fresh()
            blocks = "".join(
                f'    {{\n        "name": "{name}",\n        "subtree": "{subtree}",\n    }},\n'
                for name, subtree in order
            )
            fixture_repo.write(
                root,
                inventory.COPYBARA,
                f'STANDALONE_SSH_PREFIX = "git@github.com:Example/"\nCOMPONENTS = [\n{blocks}]\n',
            )
            for name, subtree in components:
                fixture_repo.node_package(
                    root, f"{subtree}/n-{name}", f"@example/{name}", "1.0.0"
                )
                fixture_repo.write(
                    root,
                    f"{subtree}/.github/workflows/release.yml",
                    f"jobs:\n  {name}:\n    steps:\n      - run: npm publish\n",
                )
            run = self.both("inventory", ("--json",), root=root, code=0)
            repos = {p["name"]: p["repo"] for p in json.loads(run.out)}
            self.assertEqual(
                repos,
                {
                    "@example/outer": "outer",
                    "@example/inner": "inner",
                    "@example/deepest": "deepest",
                },
            )

    def test_package_files_that_are_not_public(self):
        root = self.fixture()
        cases = [
            (
                "package.json",
                json.dumps({"name": "x", "version": "1.0.0", "private": "yes"}),
            ),
            (
                "package.json",
                json.dumps({"name": "x", "version": "1.0.0", "private": 0}),
            ),
            (
                "package.json",
                json.dumps({"name": "x", "version": "1.0.0", "private": []}),
            ),
            ("package.json", json.dumps({"name": "", "version": "1.0.0"})),
            ("package.json", json.dumps({"name": "x"})),
            ("package.json", json.dumps({"name": "x", "version": None})),
            ("package.json", json.dumps(["not", "a", "dict"])),
            ("Cargo.toml", '[package]\nname = "x"\nversion = "1.0.0"\npublish = []\n'),
            (
                "Cargo.toml",
                '[package]\nname = "x"\nversion = "1.0.0"\npublish = ["crates-io"]\n',
            ),
            (
                "Cargo.toml",
                '[package]\nname = "x"\nversion = "1.0.0"\npublish = true\n',
            ),
            ("Cargo.toml", "[workspace]\nmembers = []\n"),
            ("Cargo.toml", 'package.name = "dotted"\npackage.version = "2.0.0"\n'),
            (
                "pyproject.toml",
                '[project]\nname = "x"\nversion = "1"\nclassifiers = ["Private :: Do Not Upload"]\n',
            ),
            (
                "pyproject.toml",
                '[project]\nname = "x"\nversion = "1"\nclassifiers = ["License :: MIT", "Private ::"]\n',
            ),
            (
                "pyproject.toml",
                '[project]\nname = "x"\nversion = "1"\nclassifiers = ["Private:: no space"]\n',
            ),
            (
                "pyproject.toml",
                '[project]\nname = "x"\nversion = "1"\nclassifiers = "Private :: a string"\n',
            ),
            ("pyproject.toml", '[project]\nname = "x"\ndynamic = ["version"]\n'),
            ("pyproject.toml", "[project]\nname = 'lit'\nversion = '''1.0'''\n"),
            ("pyproject.toml", '[project]\nname = "\\u00e9t\\u00e9"\nversion = "1"\n'),
        ]
        for file, text in cases:
            root = one_package_repo(self.fresh(), file, text)
            self.both_ways(root, code=None)

    def test_configs_every_way_release_please_writes_them(self):
        root = self.fresh()
        fixture_repo.write(root, inventory.COPYBARA, SIMPLE_COPYBARA)
        fixture_repo.write(root, "pkgs/.github/workflows/release.yml", PUBLISH_ALL)
        fixture_repo.write(
            root, "pkgs/a/package.json", '{"name": "a", "version": "1.0.0"}'
        )
        fixture_repo.write(
            root, "pkgs/b/pyproject.toml", '[project]\nname = "b"\nversion = "2.0.0"\n'
        )
        fixture_repo.write(
            root, "pkgs/c/Cargo.toml", '[package]\nname = "c"\nversion = "3.0.0"\n'
        )
        fixture_repo.write(
            root, "pkgs/package.json", '{"name": "root-pkg", "version": "0.0.1"}'
        )
        configs = [
            {"release-type": "node", "packages": {"pkgs/a": {}}},
            {
                "packages": {
                    "pkgs/b": {"release-type": "python"},
                    "pkgs/c": {"release-type": "rust"},
                }
            },
            {"release-type": "node", "packages": {".": {}}},
            {
                "release-type": "simple",
                "extra-files": [{"path": "a/package.json", "jsonpath": "$.version"}],
                "packages": {"pkgs": {}},
            },
            {
                "release-type": "simple",
                "extra-files": [{"path": "a/package.json", "jsonpath": "$.version"}],
                "packages": {"pkgs": {"extra-files": []}},
            },
            {"release-type": "node", "packages": {"pkgs/a": {"release-type": None}}},
            {"release-type": ["node"], "packages": {"pkgs/a": "not a dict"}},
            {
                "packages": {
                    "pkgs": {
                        "extra-files": [
                            {"path": "./a/../a/package.json", "jsonpath": "$.version"},
                            {"path": "b/pyproject.toml"},
                            7,
                            None,
                        ]
                    }
                }
            },
            {"packages": {"pkgs": {"extra-files": {"a/package.json": 1}}}},
            {"packages": ["pkgs"]},
            {"release-type": "node"},
            [],
        ]
        for index, config in enumerate(configs):
            fixture_repo.write(
                root, "pkgs/release-please-config.json", json.dumps(config)
            )
            self.both_ways(root, code=None)
        # Two configs naming one file: it is counted once.
        fixture_repo.write(
            root, "pkgs/release-please-config.json", json.dumps(configs[0])
        )
        fixture_repo.write(
            root,
            "pkgs/a/release-please-config.json",
            json.dumps({"release-type": "node", "packages": {"pkgs/a": {}}}),
        )
        self.both_ways(root, code=0)

    def test_folders_the_walk_must_not_enter(self):
        root = self.fixture()
        for folder in (
            ".git",
            "dist",
            "target",
            "scratchpad",
            "bazel-out",
            "bazel-bin/x",
        ):
            fixture_repo.node_package(
                root, f"packages/lib/{folder}/p", "@example/hidden", "1.0.0"
            )
        fixture_repo.node_package(
            root, "packages/lib/dists/p", "@example/shown", "1.0.0"
        )
        os.symlink(
            os.path.join(root, "packages/lib/ts"),
            os.path.join(root, "packages/lib/linked"),
        )
        os.symlink(
            os.path.join(root, "nowhere"),
            os.path.join(root, "packages/lib/release-please-config.json"),
        )
        self.both_ways(root, code=None)

    def test_config_files_that_are_not_json(self):
        root = self.fixture()
        path = os.path.join(root, "packages/sdk/release-please-config.json")
        with open(path, encoding="utf-8") as handle:
            good = handle.read()
        texts = [good[:cut] for cut in range(0, len(good), 7)]
        texts += [
            '{"packages": {"x": {},}}',
            '{"packages": [1,]}',
            "\ufeff{}",
            '{"a": "\\x"}',
            '{"a": "\\u12"}',
            '{"a": "line\nbreak"}',
            "{}\r\n{}",
            "{'single': 1}",
            '{"a" 1}',
            '{"a": 1 "b": 2}',
            "[1, 2] x",
            "NaN",
            '{"a": -Infinity, "b": 1e400, "c": 01}',
            '{"a": "\\ud83d\\ude00", "b": "\\ud800\\u0041"}',
        ]
        for text in texts:
            with open(path, "w", encoding="utf-8", newline="") as handle:
                handle.write(text)
            self.both_ways(root, code=None)
        for raw in (
            b"\xff{}",
            b'{"a": "\xe2\x28"}',
            b'{"a": "\xe2\x82',
            b"\xef\xbb\xbf{}",
        ):
            with open(path, "wb") as handle:
                handle.write(raw)
            self.both_ways(root, code=2)

    def test_package_files_cut_short_at_every_character(self):
        cases = [
            (
                "package.json",
                json.dumps(
                    {"name": "@example/cut", "version": "1.0.0", "private": False}
                ),
            ),
            (
                "pyproject.toml",
                '[project]\nname = "cut"  # the name\nversion = "1.0.0"\nclassifiers = [\n  "A :: B",\n]\n',
            ),
            (
                "Cargo.toml",
                '[package]\nname = \'cut\'\nversion = "1.0.0"\npublish = false\n[dependencies]\nx = { version = "1", features = ["a"] }\n',
            ),
        ]
        for file, text in cases:
            root = one_package_repo(self.fresh(), file, text)
            for cut in range(len(text) + 1):
                fixture_repo.write(root, f"pkgs/p/{file}", text[:cut])
                self.both("inventory", ("--all",), root=root, code=None)

    def test_toml_that_tomllib_refuses(self):
        broken = [
            '[package]\nname = "x\nversion = 1',
            '[package]\nname = "x"\nname = "y"',
            "[package]\n[package]",
            '[package\nname = "x"',
            "[[package]]\nname = 'x'\n[package]",
            "package = 1\n[package]",
            '[package]\nname = "x" version = "1"',
            '[package]\nname "x"',
            "[package]\nname = [1 2]",
            "[package]\nname = {a = 1 b = 2}",
            "[package]\nname = {a = 1, a = 2}",
            "[package]\nname = 'x",
            '[package]\nname = "\\q"',
            '[package]\nname = "\\uD800"',
            '[package]\nname = "\\u12"',
            "[package]\nversion = 2021-02-30",
            "[package]\nversion = 2021-02-28T25:00:00",
            "\ufeff[package]",
            "[package]\n# comment \x01\n",
            "[package]\nname = \"\"\"a\nb\"\"\"\nversion = '''c\nd'''''",
            "[package]\nname = 0x\n",
            "[package]\nname = 1__0\n",
            "[package]\nname = +inf\nversion = nan\n",
            "[package]\na.b = 1\n[package.a]\n",
            "[package]\na = [1]\n[[package.a]]\n",
            "[package]\na = {b = 1}\na.c = 2\n",
            "[package.x]\n[package]\nx.y = 1\n",
            "[a]\nb.c = 1\n[a.b]\n",
            '[package]\nname = "x"\r\nversion = "1"\r\n',
            '[package]\nname = "x"\rversion = "1"\n',
            '[package]\nname = "x"\t\nversion\t=\t"1"\n',
            "[ package . 'x' . \"y\" ]\nname = 1\n",
            '[package]\nname = "tab\there"\nversion = "1"\n',
            '[package]\nname = "ctrl\x7f"\n',
            '[package]\nname = """\\\n   x\\  \n  y"""\nversion = "1"\n',
            "[package]\nname = 1979-05-27 07:32:00.999999999-07:00\nversion = 07:32:00\n",
            "[package]\nname = 3.14e+2_0\nversion = -0.0\n",
        ]
        root = one_package_repo(self.fresh(), "Cargo.toml", "")
        for text in broken:
            fixture_repo.write(root, "pkgs/p/Cargo.toml", text)
            self.both("inventory", ("--all",), root=root, code=None)

    def test_workflows_written_every_way_the_parser_meets(self):
        root = one_package_repo(
            self.fresh(), "Cargo.toml", '[package]\nname = "w"\nversion = "1"\n'
        )
        workflows = [
            "jobs:\n  a:\n    steps:\n      - run: cargo publish\n    environment: 'crates-io'\n",
            'jobs:\n  a:\n    environment: "quoted"\n    steps:\n      - run: cargo publish\n',
            "jobs:\n  a:\n    environment:\n      name: mapped\n    steps:\n      - run: cargo publish\n",
            "jobs:\n  a:\n    environment:\n      url: x\n    steps:\n      - run: cargo publish\n",
            "jobs:\n  a:\n    environment:\n    steps:\n      - run: cargo publish\n",
            "jobs:\n  a:\n    environment:\n      name:\n    steps:\n      - run: cargo publish\n",
            "jobs:   \n    a:\n        steps:\n            - run: cargo publish\n        environment: deep\n",
            "jobs:\n\n  # cargo publish in a comment\n  a:\n    steps:\n      - run: echo\n",
            "jobs:\n  a:\n    steps:\n      - run: echo cargo publish\nother:\n  b:\n    run: cargo publish\n",
            "on: push\njobs:\n  a:\n    steps:\n      - run: |\n          cargo publish --dry-run\n",
            "jobs:\n  a :\n    steps:\n      - run: cargo publish\n",
            "jobs:\n\ta:\n\t\tsteps: cargo publish\n",
            "jobs:\n  a:\n    steps:\n      - run: cargo  publish\n  b:\n    steps:\n      - run: cargo publish\n",
            "jobs:\n  a:\n    steps:\n      - run: xcargo publish\n  b:\n    steps:\n      - run: cargo publisher\n",
            "jobs:\n  a:\r\n    steps:\r\n      - run: cargo publish\r\n    environment: crlf\r\n",
            "jobs:\n  a:\n    steps:\n      - run: cargo\u00a0publish\n    environment:\u00a0nbsp\u00a0\n",
            "jobs:\n  a-b_c9:\n    environment: x # a comment\n    steps:\n      - run: cargo publish\n",
            "jobs:\n  a:\n      environment: two-deep\n    steps:\n      - run: cargo publish\n",
            "jobs:\n  a:\n    steps:\n      - run: cargo publish\n  environment: not-a-job\n",
            "jobs: {}\n",
            "",
            "jobs:\n  a: {steps: [run: cargo publish]}\n",
        ]
        for text in workflows:
            fixture_repo.write(root, "pkgs/.github/workflows/release.yml", text)
            self.both("inventory", ("--json", "--all"), root=root, code=None)
        fixture_repo.write(root, "pkgs/.github/workflows/release.yml", workflows[0])
        fixture_repo.write(
            root,
            "pkgs/.github/workflows/b.yaml",
            "jobs:\n  b:\n    steps:\n      - run: npm publish\n",
        )
        fixture_repo.write(
            root,
            "pkgs/.github/workflows/c.txt",
            "jobs:\n  c:\n    steps:\n      - run: cargo publish\n",
        )
        self.both("inventory", ("--json", "--all"), root=root, code=0)

    def test_publish_commands_generated_from_their_pieces(self):
        """Lines built at random from what the patterns look for, around a
        word boundary or not, in each registry's job."""
        rng = random.Random(20261024)
        pieces = [
            "npm",
            "publish",
            "uv",
            "twine",
            "upload",
            "cargo",
            "gh-action-pypi-publish@v1",
            " ",
            "  ",
            "\t",
            '"',
            "'",
            ",",
            "_",
            "x",
            "-",
            "(",
            ")",
            "é",
            "\u00a0",
            "p",
        ]
        root = one_package_repo(
            self.fresh(), "package.json", '{"name": "g", "version": "1"}'
        )
        for file, text in (
            ("pyproject.toml", '[project]\nname = "g"\nversion = "1"\n'),
            ("Cargo.toml", '[package]\nname = "g"\nversion = "1"\n'),
        ):
            fixture_repo.write(root, f"pkgs/q/{file}", text)
        config = {
            "packages": {
                "pkgs": {
                    "extra-files": [
                        {"path": "p/package.json", "jsonpath": "$.version"},
                        {"path": "q/pyproject.toml", "jsonpath": "$.project.version"},
                        {"path": "q/Cargo.toml", "jsonpath": "$.package.version"},
                    ]
                }
            }
        }
        fixture_repo.write(root, "pkgs/release-please-config.json", json.dumps(config))
        for _ in range(60):
            lines = [
                "".join(rng.choice(pieces) for _ in range(rng.randint(1, 6)))
                for _ in range(3)
            ]
            text = "jobs:\n" + "".join(
                f"  j{i}:\n    steps:\n      - run: {line}\n"
                for i, line in enumerate(lines)
            )
            fixture_repo.write(root, "pkgs/.github/workflows/release.yml", text)
            self.both("inventory", ("--json", "--all"), root=root, code=None)


# --- check ------------------------------------------------------------------------


def registry_repo(
    root,
    packages,
    owner="VitruvianSoftware",
    repo="vitruvian-sdk",
    rows=(),
    ledger=None,
):
    """A repository whose inventory is `packages`, [(registry, name)], all
    from owner/repo's release.yml, with bootstrap.tsv holding `rows`."""
    files = {"npm": "package.json", "pypi": "pyproject.toml", "crates": "Cargo.toml"}
    fixture_repo.write(
        root,
        inventory.COPYBARA,
        f'STANDALONE_SSH_PREFIX = "git@github.com:{owner}/"\n\nCOMPONENTS = [\n'
        f'    {{\n        "name": "{repo}",\n        "subtree": "pkgs",\n    }},\n]\n',
    )
    extra = []
    for index, (registry, name) in enumerate(packages):
        file = files[registry]
        path = f"p{index}/{file}"
        if registry == "npm":
            text = json.dumps({"name": name, "version": "1.1.0"})
        elif registry == "pypi":
            text = f'[project]\nname = "{name}"\nversion = "1.1.0"\n'
        else:
            text = f'[package]\nname = "{name}"\nversion = "1.1.0"\n'
        fixture_repo.write(root, f"pkgs/{path}", text)
        extra.append({"path": path, "jsonpath": inventory.FILES[file][1]})
    fixture_repo.write(
        root,
        "pkgs/release-please-config.json",
        json.dumps(
            {"release-type": "simple", "packages": {"pkgs": {"extra-files": extra}}}
        ),
    )
    fixture_repo.write(root, "pkgs/.github/workflows/release.yml", PUBLISH_ALL)
    if ledger is None:
        ledger = "".join(
            f"{r}\t{p}\t{v}\t2026-10-13\tthe first publish\n" for r, p, v in rows
        )
    fixture_repo.write(root, check.LEDGER, ledger)
    return root


class CheckParity(Parity):
    def npm_world(self):
        world = World()
        world.put(
            NPM + "@vitruviansoftware%2Ffoundation-pubsub",
            recorded("npm-foundation-pubsub.json"),
        )
        world.put(NPM + "@vitruviansoftware%2Ftool-kit", recorded("npm-tool-kit.json"))
        return world

    def run_check(self, packages, rows, world, code, **repo):
        root = registry_repo(self.fresh(), packages, rows=rows, **repo)
        return self.both("check", root=root, world=world, code=code)

    # NpmTest

    def test_npm_scenarios(self):
        pubsub = [("npm", PUBSUB)]
        self.run_check(pubsub, [("npm", PUBSUB, "0.2.0")], self.npm_world(), 0)
        self.run_check(pubsub, [], self.npm_world(), 1)
        self.run_check(pubsub, [("npm", PUBSUB, "0.1.0")], self.npm_world(), 1)
        self.run_check([("npm", KIT)], [("npm", KIT, "1.1.0")], self.npm_world(), 0)
        for path in (("dist", "attestations"), ("_npmUser", "trustedPublisher")):
            world = self.npm_world()
            answer = recorded("npm-foundation-pubsub.json")
            del answer["versions"]["0.4.1"][path[0]][path[1]]
            world.put(NPM + "@vitruviansoftware%2Ffoundation-pubsub", answer)
            self.run_check(pubsub, [("npm", PUBSUB, "0.2.0")], world, 1)
        self.run_check(pubsub, [("npm", PUBSUB, "0.3.0")], self.npm_world(), 1)
        self.run_check(pubsub, [("npm", PUBSUB, "0.4.1")], self.npm_world(), 1)
        new = [("npm", "@vitruviansoftware/new")]
        world = self.npm_world()
        world.put(NPM + "@vitruviansoftware%2Fnew", {"error": "Not found"}, 404)
        run = self.run_check(new, [], world, 0)
        self.assertIn("not yet on the registry", run.out)
        world.put(NPM + "@vitruviansoftware%2Fnew", {}, 503)
        run = self.run_check(new, [], world, 2)
        self.assertIn("503", run.err)

    # CratesTest

    def bon(self, next_page=None):
        page = recorded("crates-bon-page1.json")
        page["meta"]["next_page"] = next_page
        return page

    def test_crates_scenarios(self):
        world = World()
        world.put(
            CRATES + "vitruvian-tool-kit/versions?per_page=100",
            recorded("crates-vitruvian-tool-kit.json"),
        )
        self.run_check([("crates", CRATE)], [("crates", CRATE, "1.1.0")], world, 0)
        self.run_check([("crates", CRATE)], [], world, 1)
        world = World()
        world.put(CRATES + "bon/versions?per_page=100", self.bon())
        self.run_check([("crates", "bon")], [], world, 0, owner="elastio", repo="bon")
        run = self.run_check(
            [("crates", "bon")], [], world, 1, owner="elastio", repo="other"
        )
        self.assertIn("elastio/bon", run.out)
        first = recorded("crates-bon-page1.json")
        second = self.bon()
        second["versions"] = [
            dict(
                second["versions"][0],
                num="3.10.0",
                trustpub_data=None,
                published_by={"login": "someone"},
            )
        ]
        world = World()
        world.put(CRATES + "bon/versions?per_page=100", first)
        world.put(CRATES + "bon/versions" + first["meta"]["next_page"], second)
        run = self.run_check(
            [("crates", "bon")], [], world, 1, owner="elastio", repo="bon"
        )
        self.assertIn("someone", run.out)

    def test_crates_answers_of_every_shape(self):
        base = self.bon()
        variants = []
        for change in (
            {"trustpub_data": {}},
            {"trustpub_data": {"provider": "gitlab", "project_path": "g/bon"}},
            {"trustpub_data": {"provider": "github", "repository": "ELASTIO/BON"}},
            {"trustpub_data": None, "published_by": None},
            {"trustpub_data": None, "published_by": {"login": None}},
            {"created_at": "2026-10-02T21:52:43+02:00"},
            {"created_at": "2026-10-02T21:52:43.9Z"},
        ):
            page = copy.deepcopy(base)
            page["versions"][0].update(change)
            variants.append(page)
        page = copy.deepcopy(base)
        page["versions"] = []
        variants.append(page)
        for page in variants:
            world = World()
            world.put(CRATES + "bon/versions?per_page=100", page)
            self.run_check(
                [("crates", "bon")],
                [("crates", "bon", "3.10.1")],
                world,
                None,
                owner="elastio",
                repo="bon",
            )
        for status, body in (
            (404, {}),
            (500, {}),
            (200, "not json"),
            (200, '{"versions": [], }'),
            (429, ""),
        ):
            world = World()
            world.put(CRATES + "bon/versions?per_page=100", body, status)
            self.run_check(
                [("crates", "bon")], [], world, None, owner="elastio", repo="bon"
            )

    # PyPITest

    def pypi_world(self):
        world = World()
        world.put(
            PYPI + "pypi/vitruvian-tool-kit/json",
            recorded("pypi-vitruvian-tool-kit.json"),
        )
        for name in PYPI_FILES:
            world.put(provenance(name), {"message": "No provenance available"}, 404)
        return world

    def attest(
        self,
        world,
        version,
        repository="VitruvianSoftware/vitruvian-sdk",
        workflow="release.yml",
    ):
        answer = recorded("pypi-provenance-sampleproject.json")
        publisher = answer["attestation_bundles"][0]["publisher"]
        publisher["repository"], publisher["workflow"] = repository, workflow
        for name in PYPI_FILES:
            if f"-{version}" in name:
                world.put(provenance(name), copy.deepcopy(answer))

    def test_pypi_scenarios(self):
        kit = [("pypi", CRATE)]
        self.run_check(kit, [("pypi", CRATE, "1.1.0")], self.pypi_world(), 0)
        self.run_check(kit, [], self.pypi_world(), 1)
        self.run_check(kit, [("pypi", CRATE, "1.0.0")], self.pypi_world(), 1)
        world = self.pypi_world()
        self.attest(world, "1.1.0")
        self.run_check(kit, [("pypi", CRATE, "1.0.0")], world, 0)
        world.put(provenance(PYPI_FILES[5]), {"message": "none"}, 404)
        self.run_check(kit, [("pypi", CRATE, "1.0.0")], world, 1)
        world = self.pypi_world()
        self.attest(world, "1.1.0", repository="someone/else")
        self.run_check(kit, [("pypi", CRATE, "1.1.0")], world, 1)
        world = self.pypi_world()
        self.attest(world, "1.1.0", workflow="other.yml")
        self.run_check(kit, [("pypi", CRATE, "1.1.0")], world, 1)

    def test_pypi_answers_of_every_shape(self):
        kit = [("pypi", CRATE)]
        for proof in (
            {"attestation_bundles": []},
            {"attestation_bundles": [{"publisher": None}]},
            {
                "attestation_bundles": [
                    {
                        "publisher": {
                            "kind": "GitLab",
                            "repository": "x/y",
                            "workflow": "w",
                        }
                    }
                ]
            },
            {
                "attestation_bundles": [
                    {
                        "publisher": {
                            "kind": "GitHub",
                            "repository": "vitruviansoftware/VITRUVIAN-SDK",
                            "workflow": "release.yml",
                        }
                    }
                ]
            },
            {"attestation_bundles": [{"publisher": {"kind": "GitHub"}}]},
            {},
        ):
            world = self.pypi_world()
            for name in PYPI_FILES[4:]:
                world.put(provenance(name), proof)
            self.run_check(kit, [("pypi", CRATE, "1.0.0")], world, None)
        answer = recorded("pypi-vitruvian-tool-kit.json")
        answer["releases"]["2.0.0"] = []
        answer["releases"]["1.1.0"][0]["upload_time_iso_8601"] = "2026-10-14T00:00:00Z"
        world = self.pypi_world()
        world.put(PYPI + "pypi/vitruvian-tool-kit/json", answer)
        self.run_check(kit, [("pypi", CRATE, "1.1.0")], world, None)
        world = self.pypi_world()
        world.put(provenance(PYPI_FILES[0]), {}, 500)
        self.run_check(kit, [("pypi", CRATE, "1.1.0")], world, 2)

    # SummaryTest

    def test_the_summary_counts_each_kind_apart(self):
        world = self.npm_world()
        world.put(
            PYPI + "pypi/vitruvian-tool-kit/json",
            recorded("pypi-vitruvian-tool-kit.json"),
        )
        for name in PYPI_FILES:
            world.put(provenance(name), {}, 404)
        run = self.run_check(
            [("npm", PUBSUB), ("pypi", CRATE)],
            [("npm", PUBSUB, "0.2.0"), ("pypi", CRATE, "1.1.0")],
            world,
            0,
        )
        self.assertIn("3 not publicly verifiable", run.out.strip().split("\n")[-1])

    # LedgerTest, through the command

    GOOD = "npm\t@x/a\t1.0.0\t2026-10-13\tthe registry refuses a trusted publisher for a package that does not exist\n"

    def ledger_world(self):
        world = World()
        world.put(NPM + "@x%2Fa", recorded("npm-tool-kit.json"))
        world.put(
            CRATES + "@x/a/versions?per_page=100",
            recorded("crates-vitruvian-tool-kit.json"),
        )
        return world

    def test_ledgers_right_and_wrong(self):
        packages = [("npm", "@x/a"), ("crates", "@x/a")]
        good_crates = self.GOOD.replace("npm", "crates")
        for ledger, code in (
            ("# registry\tpackage\n\n" + self.GOOD + good_crates, None),
            (self.GOOD + self.GOOD.replace("1.0.0", "1.1.0"), 2),
            (
                self.GOOD.replace("1.0.0", "1.1.0")
                + good_crates.replace("1.0.0", "1.1.0"),
                0,
            ),
            ("npm\t@x/a\t1.0.0\t2026-10-13\n", 2),
            ("npm\t@x/a\t1.0.0\t2026-10-13\t \n", 2),
            ("gems\t@x/a\t1.0.0\t2026-10-13\twhy\n", 2),
            ("npm\t@x/a\t1.0.0\tyesterday\twhy\n", 2),
            ("npm @x/a 1.0.0 2026-10-13 why\n", 2),
            ("npm\t@x/b\t1.0.0\t2026-10-13\twhy\n", 2),
            ("it's\t@x/a\t1.0.0\t2026-10-13\twhy\n", 2),
            ("npm\t@x/a\t1.0.0\t2026-1O-13\twhy\n", 2),
            ("npm\t@x/a\t1.0.0\t2026-10-13 \twhy\t\n", 2),
            ("  npm  \t @x/a \t 1.1.0 \t 2026-10-13 \t why \n", None),
            (" # not a comment\n", 2),
            ("\ufeff# a byte order mark\n" + self.GOOD, 2),
            (
                "npm\t@x/a\t1.1.0\t2026-10-13\twhy\r\ncrates\t@x/a\t1.1.0\t2026-10-13\twhy\r\n",
                0,
            ),
            ("", 1),
        ):
            root = registry_repo(self.fresh(), packages, ledger=ledger)
            self.both("check", root=root, world=self.ledger_world(), code=code)

    def test_the_real_ledger_against_a_repository_without_its_packages(self):
        root = fixture_repo.make(self.fresh())
        with open(os.path.join(HERE, "bootstrap.tsv"), encoding="utf-8") as handle:
            fixture_repo.write(root, check.LEDGER, handle.read())
        run = self.both("check", root=root, code=2)
        self.assertGreater(run.err.count("has a row and is not in the inventory"), 30)

    # MainTest

    ROW = "{}\t{}\t1.1.0\t2026-10-13\tthe first publish\n"

    def main_repo(self):
        root = fixture_repo.make(self.fresh())
        world = World()
        for name in ("@example%2Fa", "@example%2Fb", "@example%2Fkit"):
            world.put(NPM + name, recorded("npm-tool-kit.json"))
        world.put(
            CRATES + "example-kit/versions?per_page=100",
            recorded("crates-vitruvian-tool-kit.json"),
        )
        world.put(PYPI + "pypi/example-kit/json", {"releases": {}})
        ledger = "".join(
            self.ROW.format("npm", n)
            for n in ("@example/a", "@example/b", "@example/kit")
        )
        fixture_repo.write(
            root, check.LEDGER, ledger + self.ROW.format("crates", "example-kit")
        )
        return root, world

    def test_the_command(self):
        root, world = self.main_repo()
        run = self.both("check", root=root, world=world, code=0)
        self.assertEqual(len([e for e in run.log if e[0] == "fetch"]), 5)
        self.both("check", ("--fix",), root=root, world=world, code=2)
        self.both("check", ("--fix", "more"), root=root, world=world, code=2)

        fixture_repo.write(root, check.LEDGER, self.ROW.format("crates", "example-kit"))
        self.both("check", root=root, world=world, code=1)
        fixture_repo.write(root, check.LEDGER, self.ROW.format("npm", "@example/a") * 2)
        run = self.both("check", root=root, world=world, code=2)
        self.assertEqual(run.log, [])
        fixture_repo.write(root, check.LEDGER, self.ROW.format("npm", "@example/gone"))
        self.both("check", root=root, world=world, code=2)
        os.remove(os.path.join(root, check.LEDGER))
        run = self.both("check", root=root, world=world, code=2)
        self.assertIn("bootstrap.tsv is missing", run.err)

    def test_a_registry_that_cannot_be_read_and_a_broken_inventory(self):
        root, world = self.main_repo()
        world.put(NPM + "@example%2Fb", {}, 502)
        run = self.both("check", root=root, world=world, code=2)
        self.assertNotIn("registry-trust:", run.out)
        world.put(NPM + "@example%2Fb", "<html>", 200)
        self.both("check", root=root, world=world, code=2)
        world.put(NPM + "@example%2Fb", "", 200)
        self.both("check", root=root, world=world, code=2)
        root, world = self.main_repo()
        os.remove(os.path.join(root, inventory.COPYBARA))
        run = self.both("check", root=root, world=world, code=2)
        self.assertEqual(run.log, [])
        root = self.fresh()
        fixture_repo.write(root, inventory.COPYBARA, fixture_repo.COPYBARA)
        fixture_repo.write(root, check.LEDGER, "")
        self.both("check", root=root, code=2)

    def test_the_name_it_is_run_as_chooses_the_command(self):
        root, world = self.main_repo()
        link = os.path.join(self.tmp, "check")
        os.symlink(RS, link)
        py = self.python("check", (), root, world, {})
        rs = self.rust("check", (), root, world, {}, argv0=link)
        self.assertEqual(rs.triple(), py.triple())


# --- setup ------------------------------------------------------------------------


class SetupParity(Parity):
    def setUp(self):
        super().setUp()
        self.root = fixture_repo.make(self.fresh())
        self.npm_stand_in(self.root)
        self.home = os.path.join(self.tmp, "home")
        os.makedirs(os.path.join(self.home, ".cargo"))
        self.env = {"HOME": self.home, "CARGO_REGISTRY_TOKEN": TOKEN}
        self.public = {
            "https://crates.io/api/v1/crates/example-kit": 200,
            "https://pypi.org/pypi/example-kit/json": 200,
            "https://registry.npmjs.org/@example%2Fkit": 200,
            "https://registry.npmjs.org/@example%2Fa": 200,
            "https://registry.npmjs.org/@example%2Fb": 200,
        }
        self.configs = []
        self.list_status = 200
        self.create_status = 200

    def world(self):
        world = World()
        for url, status in self.public.items():
            world.put(url, "{}", status)
        if self.list_status == 200:
            world.answer(
                "GET",
                LIST,
                {
                    "github_configs": self.configs,
                    "meta": {"total": len(self.configs), "next_page": None},
                },
            )
        else:
            world.answer(
                "GET",
                LIST,
                {"errors": [{"detail": "this token cannot do that"}]},
                self.list_status,
            )
        if self.create_status == 200:
            world.answer("POST", CREATE, {"github_config": dict(WANTED, id=1)})
        else:
            world.answer(
                "POST",
                CREATE,
                {"errors": [{"detail": "crates.io said no"}]},
                self.create_status,
            )
        return world

    def setup(self, *argv, code=None):
        run = self.both(
            "setup", argv, root=self.root, world=self.world(), env=self.env, code=code
        )
        self.assertNotIn(TOKEN, run.out + run.err)
        return run

    def posts(self, run):
        return [e for e in run.log if e[0] == "send" and e[1] == "POST"]

    # crates.io

    def test_a_missing_config_is_created_from_what_the_code_says(self):
        run = self.setup("--only", "crates", code=0)
        (post,) = self.posts(run)
        self.assertEqual(
            post, ["send", "POST", CREATE, True, {"github_config": WANTED}]
        )

    def test_configs_there_and_not_there(self):
        self.configs = [dict(WANTED, id=7, repository_owner="example")]
        run = self.setup("--only", "crates", code=0)
        self.assertEqual(self.posts(run), [])
        self.configs = [dict(WANTED, id=7, workflow_filename="other.yml")]
        run = self.setup("--only", "crates", code=0)
        self.assertEqual(len(self.posts(run)), 1)
        self.configs = [dict(WANTED, id=7, environment=None)]
        run = self.setup("--only", "crates", code=0)
        self.assertEqual(len(self.posts(run)), 1)
        self.configs = [{"id": 1}, dict(WANTED, environment="")]
        self.setup("--only", "crates", code=0)

    def test_dry_run_needs_no_token(self):
        self.env = {"HOME": self.home}
        run = self.setup("--dry-run", "--only", "crates", code=0)
        self.assertEqual([e for e in run.log if e[0] == "send"], [])

    def test_a_crate_that_is_not_published_yet(self):
        self.public["https://crates.io/api/v1/crates/example-kit"] = 404
        self.setup("--only", "crates", code=0)
        self.public["https://crates.io/api/v1/crates/example-kit"] = 500
        self.setup("--only", "crates", code=2)

    def test_the_token_from_cargo_s_files(self):
        self.env = {"HOME": self.home}
        credentials = os.path.join(self.home, ".cargo", "credentials.toml")
        with open(credentials, "w") as handle:
            handle.write(f'[registry]\ntoken = "{TOKEN}"\n')
        run = self.setup("--only", "crates", code=0)
        self.assertTrue(self.posts(run)[0][3])
        with open(credentials, "w") as handle:
            handle.write(f'[registry]\ntoken = "{TOKEN}\n')
        self.setup("--only", "crates", code=2)
        os.remove(credentials)
        self.setup("--only", "crates", code=2)
        with open(os.path.join(self.home, ".cargo", "credentials"), "w") as handle:
            handle.write(f'[registry]\ntoken = "{TOKEN}"\n')
        self.setup("--only", "crates", code=0)
        elsewhere = os.path.join(self.tmp, "elsewhere")
        os.makedirs(elsewhere)
        with open(os.path.join(elsewhere, "credentials.toml"), "w") as handle:
            handle.write(f'[registry]\ntoken = "{TOKEN}"\n')
        self.env = {"HOME": self.home, "CARGO_HOME": elsewhere}
        self.setup("--only", "crates", code=0)
        self.env = {
            "HOME": self.home,
            "CARGO_HOME": elsewhere,
            "CARGO_REGISTRY_TOKEN": "",
        }
        self.setup("--only", "crates", code=0)

    def test_refusals_say_what_the_registry_said(self):
        self.create_status = 403
        run = self.setup("--only", "crates", code=1)
        self.assertIn("crates.io said no", run.err)
        self.create_status = 200
        self.list_status = 403
        run = self.setup("--only", "crates", code=1)
        self.assertEqual(self.posts(run), [])

    # PyPI

    def test_pypi(self):
        self.setup("--only", "pypi", code=0)
        self.public["https://pypi.org/pypi/example-kit/json"] = 404
        self.setup("--only", "pypi", code=0)
        self.public["https://pypi.org/pypi/example-kit/json"] = 503
        self.setup("--only", "pypi", code=2)

    # npm

    def test_npm_is_handed_to_the_npm_tool(self):
        run = self.setup("--only", "npm", code=0)
        self.assertEqual(
            run.npm.split("\n")[1:],
            [
                "packages/lib/ts/packages/a/package.json\tExample/lib-mirror\trelease.yml",
                "packages/lib/ts/packages/b/package.json\tExample/lib-mirror\trelease.yml",
                "packages/sdk/kits/ts/package.json\tExample/sdk-mirror\trelease.yml",
                "",
            ],
        )

    def test_npm_dry_run_and_the_npm_tool_s_failure(self):
        self.public["https://registry.npmjs.org/@example%2Fb"] = 404
        run = self.setup("--dry-run", "--only", "npm", code=0)
        self.assertIsNone(run.npm)
        self.public["https://registry.npmjs.org/@example%2Fb"] = 418
        self.setup("--dry-run", "--only", "npm", code=2)
        self.npm_stand_in(self.root, exit_code=1)
        self.setup("--only", "npm", code=1)

    # all of it

    def test_every_registry_and_every_flag(self):
        self.setup("--dry-run", code=0)
        self.setup(code=0)
        self.create_status = 422
        self.setup(code=1)
        for argv in (
            ("--force",),
            ("--only",),
            ("--only", "gems"),
            ("--dry-run", "--dry-run", "--only", "pypi", "--only", "npm"),
        ):
            self.setup(*argv)

    def test_a_broken_inventory(self):
        os.remove(os.path.join(self.root, "packages/sdk/kits/rs/Cargo.toml"))
        run = self.setup("--dry-run", code=2)
        self.assertEqual(run.log, [])
        root = self.fresh("empty")
        fixture_repo.write(root, inventory.COPYBARA, fixture_repo.COPYBARA)
        self.root = root
        self.setup("--dry-run", code=2)


if __name__ == "__main__":
    unittest.main()
