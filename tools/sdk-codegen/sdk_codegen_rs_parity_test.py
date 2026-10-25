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
"""sdk-codegen, the Rust port, against sdk_codegen.py: the same exit status,
stdout, stderr and files written, on every input here.

    bazel test //tools/sdk-codegen:sdk_codegen_rs_parity_test

Each case gets two copies of a repository: one with sdk_codegen.py and its
emitters in tools/sdk-codegen, one with the Rust binary there under the
same name, so both print the same program name and find the same default
package from where they sit. The same command runs in each, and then every
file in the two copies is compared, byte for byte.

The inputs:
  * every scenario of sdk_codegen_test.py, as a command line (a test there
    with no scenario here fails this one);
  * the real protocol in packages/vitruvian-sdk: written to --out, in place,
    and checked, by --package, BUILD_WORKSPACE_DIRECTORY and the default;
  * the real schemas mutated: new fields of every kind, texts that wrap
    every way, methods of every shape, and each problem model.py names;
  * schemas the meta-schema refuses, JSON that does not parse, files that
    are not UTF-8 or not there, committed files gone stale in each way;
  * command lines argparse treats specially, at several terminal widths;
  * a few hundred random mutations of the real schemas.

When Python crashes, its traceback names its own files and lines, which
the port cannot have: there the port prints the traceback's header, a line
saying the frames are left out, and Python's exception text, which is
compared byte for byte.
"""

import copy
import json
import os
import random
import re
import shutil
import subprocess
import sys
import tempfile
import unittest
from typing import Any, Dict, List, Optional
import multiprocessing

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import sdk_codegen_test  # noqa: E402

PACKAGE = os.path.join("packages", "vitruvian-sdk")
TRACEBACK = b"Traceback (most recent call last):\n"
NOTE = b"  (sdk-codegen-rs: Python's stack frames are not reproduced)\n"
PROGRAM = os.path.join("tools", "sdk-codegen", "sdk_codegen.py")
CHAINED = b"\nThe above exception was the direct cause of the following exception:\n\n"


def _binary():
    path = os.environ.get("SDK_CODEGEN_RS", "")
    if not path:
        raise unittest.SkipTest("SDK_CODEGEN_RS is not set; run this under bazel test")
    return os.path.abspath(path)


def read_json(name):
    with open(os.path.join(PACKAGE, "protocol", name), encoding="utf-8") as handle:
        return json.load(handle)


SCHEMAS = {
    name: read_json(name)
    for name in ("messages.schema.json", "manifest.schema.json", "methods.json")
}


def exception_text(stderr):
    """What follows the frames of a Python traceback: the exception."""
    lines = stderr[len(TRACEBACK) :].split(b"\n")
    for i, line in enumerate(lines):
        if line and not line.startswith(b" "):
            return b"\n".join(lines[i:])
    return b""


def snapshot(root):
    """Every file under root, but the program, by path: its bytes."""
    found = {}
    for top, folders, names in os.walk(root):
        rel_top = os.path.relpath(top, root)
        if rel_top == "tools" or rel_top.startswith("tools" + os.sep):
            folders[:] = []
            continue
        for name in names:
            path = os.path.join(top, name)
            rel = os.path.relpath(path, root)
            if os.path.islink(path) and not os.path.exists(path):
                found[rel] = b"<broken link>"
                continue
            with open(path, "rb") as handle:
                found[rel] = handle.read()
        for folder in folders:
            found[os.path.relpath(os.path.join(top, folder), root) + "/"] = b"<dir>"
    return found


class Case:
    """One command line in one repository, and what it is set up with."""

    def __init__(self, name, args, setup=None, env=None, keep=()):
        self.name = name
        self.args = list(args)
        self.setup = setup or (lambda pkg: None)
        self.env = env or {}
        # Files Python wrote that the test reads afterwards.
        self.keep = tuple(keep)


def base_package(root):
    """The real package's protocol and generated files, under root."""
    package = os.path.join(root, PACKAGE)
    for folder in ("protocol", "kits", "go"):
        shutil.copytree(
            os.path.join(PACKAGE, folder),
            os.path.join(package, folder),
            copy_function=shutil.copyfile,
        )
    return package


def write(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    if isinstance(data, bytes):
        with open(path, "wb") as handle:
            handle.write(data)
    else:
        with open(path, "w", encoding="utf-8", newline="") as handle:
            handle.write(data)


def schemas_setup(mutate):
    """A setup that rewrites the three protocol files after `mutate` edits
    copies of them (messages, manifest, methods); it may return raw texts."""

    def setup(package):
        docs = copy.deepcopy(SCHEMAS)
        result = mutate(
            docs["messages.schema.json"],
            docs["manifest.schema.json"],
            docs["methods.json"],
        )
        if isinstance(result, dict):
            docs.update(result)
        for name, doc in docs.items():
            path = os.path.join(package, "protocol", name)
            if isinstance(doc, (str, bytes)):
                write(path, doc)
            else:
                write(path, json.dumps(doc, indent=2, ensure_ascii=False) + "\n")

    return setup


def raw(name, text):
    def setup(package):
        write(os.path.join(package, "protocol", name), text)

    return setup


class Harness:
    def __init__(self):
        self.tmp = tempfile.mkdtemp(prefix="sdk-codegen-parity-")
        self.binary = _binary()

    def close(self):
        for top, folders, _ in os.walk(self.tmp):
            for folder in folders:
                try:
                    os.chmod(os.path.join(top, folder), 0o755)
                except OSError:
                    pass
        shutil.rmtree(self.tmp, ignore_errors=True)

    def tree(self, kind, number):
        root = os.path.join(self.tmp, str(number), kind)
        tools = os.path.join(root, "tools", "sdk-codegen")
        os.makedirs(os.path.join(tools, "emitters"))
        if kind == "py":
            for name in ("sdk_codegen.py", "model.py"):
                shutil.copyfile(os.path.join(HERE, name), os.path.join(tools, name))
            for name in os.listdir(os.path.join(HERE, "emitters")):
                if name.endswith(".py"):
                    shutil.copyfile(
                        os.path.join(HERE, "emitters", name),
                        os.path.join(tools, "emitters", name),
                    )
        else:
            program = os.path.join(tools, "sdk_codegen.py")
            shutil.copyfile(self.binary, program)
            os.chmod(program, 0o755)
        return root

    def run_case(self, case, number):
        results = {}
        for kind in ("py", "rs"):
            root = self.tree(kind, number)
            package = base_package(root)
            case.setup(package)
            env = {
                k: v
                for k, v in os.environ.items()
                if k not in ("COLUMNS", "LINES", "BUILD_WORKSPACE_DIRECTORY")
            }
            env["PYTHONDONTWRITEBYTECODE"] = "1"
            env.update({k: v.replace("{root}", root) for k, v in case.env.items()})
            argv = ([sys.executable, PROGRAM] if kind == "py" else [PROGRAM]) + [
                a.replace("{root}", root) for a in case.args
            ]
            proc = subprocess.run(
                argv, cwd=root, env=env, capture_output=True, timeout=120
            )
            out, err = proc.stdout, proc.stderr
            for path in (os.path.realpath(root), root):
                out = out.replace(path.encode(), b"<ROOT>")
                err = err.replace(path.encode(), b"<ROOT>")
            results[kind] = (proc.returncode, out, err, snapshot(root))
        return results

    @staticmethod
    def differs(results):
        py, rs = results["py"], results["rs"]
        if py[0] != rs[0]:
            return f"exit {py[0]} (python) != {rs[0]} (rust)\npython stderr: {py[2][-3000:]!r}\nrust stderr: {rs[2][-3000:]!r}"
        if py[1] != rs[1]:
            return f"stdout differs:\n--- python\n{py[1][-3000:]!r}\n--- rust\n{rs[1][-3000:]!r}"
        if py[2].startswith(TRACEBACK):
            # A chain of exceptions is a traceback each, the frames of each
            # left out.
            want = CHAINED.join(
                TRACEBACK + NOTE + exception_text(part) for part in py[2].split(CHAINED)
            )
            if rs[2] != want:
                return f"crash differs:\n--- python\n{py[2][-3000:]!r}\n--- rust\n{rs[2][-3000:]!r}"
        elif py[2] != rs[2]:
            return f"stderr differs:\n--- python\n{py[2][-3000:]!r}\n--- rust\n{rs[2][-3000:]!r}"
        if py[3] != rs[3]:
            names = sorted(set(py[3]) ^ set(rs[3])) or sorted(
                p for p in py[3] if py[3][p] != rs[3].get(p)
            )
            return f"files differ: {names[:10]}"
        return None


# --- Mutations of the real schemas --------------------------------------


def add_field(name, node, required=False, where="notifyHUDParams"):
    def mutate(messages, manifest, methods):
        target = messages["$defs"][where]
        target.setdefault("properties", {})[name] = node
        if required:
            target.setdefault("required", []).append(name)

    return mutate


def edit(fn):
    """A mutation that runs fn on the three documents."""

    def mutate(messages, manifest, methods):
        return fn(messages, manifest, methods)

    return mutate


LONG = (
    "A very long description that goes on well past the width of a comment, "
    "with well-known hyphenated-words, an em--dash between words, a "
    "supercalifragilisticexpialidociouslylongwordthatcannotbebrokenatahyphen, "
    "tabs\tand\nnew lines, and some unicode: café, Σσ, — and   non-breaking."
)


def schema_cases():
    """The real schemas, changed one way at a time."""
    cases = []
    kinds = {
        "number": {"type": "number", "description": "How long the message stays."},
        "integer": {"type": "integer"},
        "boolean": {"type": "boolean", "description": "Whether."},
        "string": {"type": "string", "description": LONG},
        "array_of_strings": {"type": "array", "items": {"type": "string"}},
        "array_of_arrays": {
            "type": "array",
            "items": {"type": "array", "items": {"type": "number"}},
        },
        "map_of_integers": {
            "type": "object",
            "additionalProperties": {"type": "integer"},
        },
        "map_of_refs": {
            "type": "object",
            "additionalProperties": {"$ref": "#/$defs/uiTree"},
        },
        "plain_object": {"type": "object"},
        "any": {"description": "Anything."},
        "const": {"const": "fixed"},
        "const_number": {"const": 2.5},
        "const_true": {"const": True},
        "scalar": {"type": ["string", "number", "boolean"]},
        "ref": {"$ref": "#/$defs/uiTree"},
        "text_ref": {"$ref": "#/$defs/uiText"},
        "array_of_refs": {"type": "array", "items": {"$ref": "#/$defs/uiBlock"}},
        "array_any": {"type": "array"},
    }
    for label, node in kinds.items():
        for required in (False, True):
            cases.append(
                (
                    f"field-{label}-{'required' if required else 'optional'}",
                    add_field("addedField", node, required),
                )
            )
    for where in ("uiOpenParams", "uiTree", "uiStatusParams"):
        cases.append(
            (
                f"field-in-{where}",
                add_field(
                    "dataFolder", {"type": "string", "description": LONG}, True, where
                ),
            )
        )
    cases.append(
        (
            "keyword-field-names",
            edit(
                lambda m, n, t: m["$defs"]["notifyHUDParams"]["properties"].update(
                    {
                        "class": {"type": "string"},
                        "type": {"type": "integer"},
                        "lambda": {"type": "boolean"},
                        "URLField": {"type": "string"},
                        "pid": {"type": "integer"},
                    }
                )
            ),
        )
    )
    cases.append(
        (
            "unicode-names",
            edit(
                lambda m, n, t: m["$defs"]["notifyHUDParams"]["properties"].update(
                    {
                        "caféName": {"type": "string"},
                        "Σigma": {"type": "string"},
                        "ßStraße": {"type": "string"},
                    }
                )
            ),
        )
    )
    cases.append(
        (
            "no-descriptions",
            edit(
                lambda m, n, t: [
                    d.pop("description", None)
                    for d in list(m["$defs"].values()) + list(n["$defs"].values())
                    if isinstance(d, dict)
                ]
            ),
        )
    )
    cases.append(
        (
            "long-descriptions",
            edit(
                lambda m, n, t: [
                    d.__setitem__("description", LONG)
                    for d in list(m["$defs"].values()) + list(n["$defs"].values())
                    if isinstance(d, dict)
                ]
            ),
        )
    )
    cases.append(
        (
            "enum-values-not-text",
            edit(
                lambda m, n, t: n["properties"]["protocol"].__setitem__(
                    "enum", [1, 2.0, True]
                )
            ),
        )
    )
    cases.append(
        (
            "enum-in-array-not-text",
            edit(
                lambda m, n, t: (
                    n["properties"]["uses"]["items"].__setitem__(
                        "enum", ["notify", None]
                    )
                    if "items" in n["properties"]["uses"]
                    else None
                )
            ),
        )
    )
    cases.append(
        (
            "enum-empty",
            edit(lambda m, n, t: n["properties"]["protocol"].__setitem__("enum", [])),
        )
    )
    cases.append(
        (
            "enum-named-twice-differently",
            edit(
                lambda m, n, t: m["$defs"].__setitem__(
                    "command",
                    {"type": "object", "properties": {"surfaces": {"enum": ["x"]}}},
                )
            ),
        )
    )
    cases.append(
        (
            "enum-named-twice-alike",
            edit(
                lambda m, n, t: m["$defs"].__setitem__(
                    "command",
                    {
                        "type": "object",
                        "properties": {
                            "surfaces": copy.deepcopy(
                                n["$defs"]["command"]["properties"]["surfaces"]
                            )
                        },
                    },
                )
            ),
        )
    )
    cases.append(("enum-with-no-name", add_field("color", {"enum": ["red", "blue"]})))
    cases.append(("type-with-null", add_field("maybe", {"type": ["string", "null"]})))
    cases.append(("type-null", add_field("nothing", {"type": "null"})))
    cases.append(
        (
            "object-with-fields-in-a-field",
            add_field(
                "inner", {"type": "object", "properties": {"a": {"type": "string"}}}
            ),
        )
    )
    cases.append(
        (
            "definition-not-an-object",
            edit(
                lambda m, n, t: m["$defs"].__setitem__("plainText", {"type": "string"})
            ),
        )
    )
    cases.append(
        (
            "definition-map",
            edit(
                lambda m, n, t: m["$defs"].__setitem__(
                    "counts",
                    {
                        "type": "object",
                        "additionalProperties": {"type": "integer"},
                        "description": "Counts.",
                    },
                )
            ),
        )
    )
    cases.append(
        (
            "definition-empty-object",
            edit(
                lambda m, n, t: m["$defs"].__setitem__(
                    "nothingAtAll", {"type": "object"}
                )
            ),
        )
    )
    cases.append(
        (
            "definition-unknown-choice",
            edit(
                lambda m, n, t: m["$defs"].__setitem__(
                    "either", {"oneOf": [{"type": "string"}, {"type": "number"}]}
                )
            ),
        )
    )
    cases.append(
        (
            "definition-true",
            edit(lambda m, n, t: m["$defs"].__setitem__("anything", True)),
        )
    )
    cases.append(("field-true", add_field("whatever", True)))
    cases.append(("items-true", add_field("list", {"type": "array", "items": True})))
    cases.append(("ref-missing", add_field("gone", {"$ref": "#/$defs/noSuchThing"})))
    cases.append(
        (
            "ref-missing-two-deep",
            add_field(
                "gone",
                {
                    "type": "array",
                    "items": {
                        "type": "array",
                        "items": {"$ref": "#/$defs/noSuchThing"},
                    },
                },
            ),
        )
    )
    cases.append(
        (
            "map-ref-missing-two-deep",
            add_field(
                "gone",
                {
                    "type": "object",
                    "additionalProperties": {
                        "type": "array",
                        "items": {"$ref": "#/$defs/noSuchThing"},
                    },
                },
            ),
        )
    )

    def variant(fn):
        def mutate(m, n, t):
            fn(m["$defs"]["uiBlock"])

        return mutate

    cases.append(
        (
            "variant-undefined-kind",
            variant(
                lambda b: b["allOf"].append(
                    {
                        "if": {"properties": {"type": {"const": "chart"}}},
                        "then": {"$ref": "#/$defs/chartBlock"},
                    }
                )
            ),
        )
    )
    cases.append(
        (
            "variant-two-tags",
            variant(
                lambda b: b["allOf"].append(
                    {
                        "if": {"properties": {"kind": {"const": "x"}}},
                        "then": {"$ref": "#/$defs/textBlock"},
                    }
                )
            ),
        )
    )
    cases.append(
        (
            "variant-tag-not-a-field",
            variant(
                lambda b: [
                    r["if"]["properties"].__setitem__(
                        "shape", r["if"]["properties"].pop("type")
                    )
                    for r in b["allOf"]
                    if "if" in r
                ]
            ),
        )
    )
    cases.append(
        (
            "variant-kind-is-text",
            variant(
                lambda b: b["allOf"].append(
                    {
                        "if": {"properties": {"type": {"const": "words"}}},
                        "then": {"$ref": "#/$defs/uiText"},
                    }
                )
            ),
        )
    )
    cases.append(("variant-rule-true", variant(lambda b: b["allOf"].append(True))))
    cases.append(
        (
            "variant-if-true",
            variant(
                lambda b: b["allOf"].append(
                    {"if": True, "then": {"$ref": "#/$defs/textBlock"}}
                )
            ),
        )
    )
    cases.append(
        (
            "variant-then-true",
            variant(
                lambda b: b["allOf"].append(
                    {"if": {"properties": {"type": {"const": "y"}}}, "then": True}
                )
            ),
        )
    )
    cases.append(
        (
            "variant-value-true",
            variant(
                lambda b: b["allOf"].append(
                    {
                        "if": {"properties": {"type": True}},
                        "then": {"$ref": "#/$defs/textBlock"},
                    }
                )
            ),
        )
    )
    cases.append(
        (
            "variant-other-rules",
            variant(lambda b: b["allOf"].append({"required": ["type"]})),
        )
    )
    cases.append(
        (
            "variant-const-number",
            variant(
                lambda b: b["allOf"].append(
                    {
                        "if": {"properties": {"type": {"const": 7}}},
                        "then": {"$ref": "#/$defs/textBlock"},
                    }
                )
            ),
        )
    )

    def twin(m, n, t):
        n["$defs"]["localizedText"] = {
            "type": "object",
            "additionalProperties": {"type": "integer"},
        }

    cases.append(("twin-defined-differently", edit(twin)))
    cases.append(
        (
            "twin-same",
            edit(
                lambda m, n, t: n["$defs"].__setitem__(
                    "uiTree", copy.deepcopy(m["$defs"]["uiTree"])
                )
            ),
        )
    )
    cases.append(
        ("messages-true", edit(lambda m, n, t: {"messages.schema.json": True}))
    )
    cases.append(
        ("manifest-true", edit(lambda m, n, t: {"manifest.schema.json": True}))
    )
    cases.append(("messages-no-defs", edit(lambda m, n, t: m.pop("$defs"))))
    cases.append(("manifest-no-defs", edit(lambda m, n, t: n.pop("$defs"))))
    cases.append(
        (
            "manifest-with-text-field",
            edit(
                lambda m, n, t: n["properties"].__setitem__(
                    "tagline", {"$ref": "#/$defs/localizedText"}
                )
            ),
        )
    )
    cases.append(
        (
            "manifest-boolean-and-number",
            edit(
                lambda m, n, t: n["properties"].update(
                    {"flag": {"type": "boolean"}, "weight": {"type": "number"}}
                )
            ),
        )
    )

    # methods.json
    def methods(fn):
        def mutate(m, n, t):
            return fn(t)

        return mutate

    tool_request = {
        "method": "extra/thing",
        "sender": "tool",
        "kind": "request",
        "uses": "notify",
        "params": "notifyHUDParams",
        "result": "empty",
    }
    cases.append(
        ("method-added", methods(lambda t: t["methods"].append(dict(tool_request))))
    )
    cases.append(
        (
            "method-one-part",
            methods(lambda t: t["methods"].append(dict(tool_request, method="ping"))),
        )
    )
    cases.append(
        (
            "method-one-part-notice",
            methods(
                lambda t: t["methods"].append(
                    dict(tool_request, method="pong", kind="notice", uses=None)
                )
            ),
        )
    )
    cases.append(
        (
            "method-three-parts",
            methods(lambda t: t["methods"].append(dict(tool_request, method="a/b/c"))),
        )
    )
    cases.append(
        (
            "method-no-result",
            methods(lambda t: t["methods"].append(dict(tool_request, result=None))),
        )
    )
    cases.append(
        (
            "method-no-params",
            methods(
                lambda t: t["methods"].append(
                    dict(tool_request, params=None, uses=None)
                )
            ),
        )
    )
    cases.append(
        (
            "method-app-sender",
            methods(lambda t: t["methods"].append(dict(tool_request, sender="app"))),
        )
    )
    cases.append(
        (
            "method-unknown-params",
            methods(lambda t: t["methods"].append(dict(tool_request, params="nope"))),
        )
    )
    cases.append(
        (
            "method-params-number",
            methods(lambda t: t["methods"].append(dict(tool_request, params=5))),
        )
    )
    cases.append(
        (
            "method-params-list",
            methods(lambda t: t["methods"].append(dict(tool_request, params=["x"]))),
        )
    )
    cases.append(
        (
            "method-name-number",
            methods(lambda t: t["methods"].append(dict(tool_request, method=12))),
        )
    )
    cases.append(
        (
            "method-name-quote",
            methods(
                lambda t: t["methods"].append(dict(tool_request, method="it's/fine"))
            ),
        )
    )
    cases.append(
        (
            "method-sender-number",
            methods(
                lambda t: t["methods"].append(dict(tool_request, sender=3, uses=False))
            ),
        )
    )
    cases.append(
        (
            "method-missing-key",
            methods(lambda t: t["methods"].append({"method": "x/y", "sender": "tool"})),
        )
    )
    cases.append(("methods-empty", methods(lambda t: t.__setitem__("methods", []))))
    cases.append(("methods-not-a-list", methods(lambda t: t.__setitem__("methods", 3))))
    cases.append(
        ("methods-a-dict", methods(lambda t: t.__setitem__("methods", {"a": 1})))
    )
    cases.append(
        ("methods-a-string", methods(lambda t: t.__setitem__("methods", "ab")))
    )
    cases.append(
        ("methods-row-list", methods(lambda t: t.__setitem__("methods", [[1]])))
    )
    cases.append(
        ("methods-row-number", methods(lambda t: t.__setitem__("methods", [1])))
    )
    cases.append(("methods-missing", methods(lambda t: t.pop("methods"))))
    cases.append(("protocol-missing", methods(lambda t: t.pop("protocol"))))
    cases.append(("protocol-number", methods(lambda t: t.__setitem__("protocol", 3))))
    cases.append(("methods-table-a-list", edit(lambda m, n, t: {"methods.json": []})))
    cases.append(("no-service-enum", edit(lambda m, n, t: n["properties"].pop("uses"))))
    cases.append(
        ("no-protocol-enum", edit(lambda m, n, t: n["properties"].pop("protocol")))
    )
    return cases


# Patterns for the "regex" format: some Python's re takes, most it refuses,
# each refusal a different message of re/_parser.py.
REGEXES = (
    [
        "",
        "^[a-z]+$",
        "a{2,3}",
        "a{,}",
        "{",
        "a{x}",
        "x{}",
        "(?P<n>a)(?P=n)",
        "(a)\\1",
        "(?<=ab)c",
        "(?<!a|b)c",
        "(?i)abc",
        "(?x) a b # c",
        "(?:)*",
        "[]a]",
        "[^]]",
        "[a-]",
        "\\x41\\u0041\\U00000041",
        "(?>a+)b",
        "a*+",
        "(a)(?(1)b|c)",
        "\\d\\w\\s\\b",
        "\\0",
        "[\\d-]",
        "(?s:a.)",
        "(?-i:a)",
        "\\N{DASH}",
        "(",
        ")",
        "[",
        "a**",
        "*",
        "^*",
        "a{3,2}",
        "\\",
        "\\q",
        "[z-a]",
        "[\\d-z]",
        "(?<=a|bc)d",
        "(?P<1>a)",
        "(?P=x)",
        "\\1",
        "(a\\1)",
        "(?L)a",
        "(?au:a)",
        "a(?i)",
        "(?P<a>x)(?P<a>y)",
        "(?(2)a)",
        "\\x4",
        "\\U00110000",
        "[\\400]",
        "\\400",
        "(?#x",
        "(?z)",
        "(?P",
        "(?P>",
        "(?<x",
        "(?",
        "(?i",
        "(?i-",
        "(?-x",
        "(?t:a)",
        "(?i-i:a)",
        "(?-a:a)",
        "(?ix-z:a)",
        "(?(a)x)",
        "(?(0)x)",
        "(?(1a)x)",
        "(a)(?(1)x|y|z)",
        "(?P<a",
        "(?P<>a)",
        "(?P=)",
        "\\N",
        "\\N{",
        "[a",
        "[a-",
        "[\\",
        "a{1,2",
        "a\n(",
        "(?<=(a)\\1)",
        "(?<=a{2})b",
        "(a)(?<=\\1)",
        "(?<=(?P<x>a)(?P=x))b",
        "\\u12",
        "\\U1234567",
        "x{2}{3}",
        "a??+",
        "\\Z*",
        "(?:a|b)|*",
        "(?x)a #*\n*",
    ]
    + [
        "\\N{" + name + "}"
        for name in (
            "LATIN SMALL LETTER A",
            "latin small letter a",
            "NUL",
            "LINE FEED",
            "BYTE ORDER MARK",
            "HANGUL SYLLABLE GA",
            "HANGUL SYLLABLE GAG",
            "HANGUL SYLLABLE A",
            "HANGUL SYLLABLE ga",
            "hangul syllable GA",
            "HANGUL SYLLABLE G",
            "CJK UNIFIED IDEOGRAPH-4E00",
            "CJK UNIFIED IDEOGRAPH-4e00",
            "CJK UNIFIED IDEOGRAPH-2A6E0",
            "cjk unified ideograph-4E00",
            "TANGUT IDEOGRAPH-17000",
            "LATIN CAPITAL LETTER A WITH MACRON AND GRAVE",
            "SNOWMAN",
            "snowman",
            "PILE OF POO",
            "DASH",
            "caf\u00e9",
        )
    ]
    + ["[\\N{SNOWMAN}-\\N{COMET}]", "[\\N{COMET}-\\N{SNOWMAN}]", "(?<=\\N{SNOWMAN})x"]
)


def broken_schema_cases():
    """Schemas the 2020-12 meta-schema refuses, one way at a time."""
    bad = {
        "type-foo": {"type": "foo"},
        "type-number": {"type": 5},
        "type-empty-list": {"type": []},
        "type-duplicate": {"type": ["string", "string"]},
        "pattern-unclosed": {"type": "string", "pattern": "("},
        "pattern-overflow": {"type": "string", "pattern": "a{99999999999}"},
        "pattern-flags": {"type": "string", "pattern": "(?a)(?u)x"},
        "pattern-lookbehind": {"type": "string", "pattern": "(?<=a+)b"},
        "pattern-fine": {"type": "string", "pattern": "^[a-z]+(?:-[a-z]+)*$"},
        "pattern-not-text": {"type": "string", "pattern": 5},
        "min-items-negative": {"type": "array", "minItems": -1},
        "min-items-float": {"type": "array", "minItems": 1.5},
        "min-items-whole-float": {"type": "array", "minItems": 2.0},
        "multiple-of-zero": {"type": "number", "multipleOf": 0},
        "required-duplicate": {"type": "object", "required": ["a", "a"]},
        "required-not-text": {"type": "object", "required": [1]},
        "description-number": {"type": "string", "description": 5},
        "enum-not-list": {"enum": "abc"},
        "all-of-empty": {"allOf": []},
        "any-of-not-list": {"anyOf": {}},
        "properties-not-object": {"type": "object", "properties": []},
        "additional-not-schema": {"type": "object", "additionalProperties": 3},
        "id-fragment": {"$id": "a#b", "type": "string"},
        "anchor-bad": {"$anchor": "1a", "type": "string"},
        "anchor-newline": {"$anchor": "a\n", "type": "string"},
        "vocabulary-not-boolean": {"$vocabulary": {"x": 1}},
        "pattern-properties-bad": {"type": "object", "patternProperties": {"(": {}}},
        "ref-not-text": {"$ref": 3},
        "deprecated-text": {"type": "string", "deprecated": "yes"},
        "dependencies-bad": {"type": "object", "dependencies": {"a": 3}},
        "long-instance": {"type": "string", "description": ["x" * 30] * 6},
        "long-string-instance": {
            "type": "string",
            "description": False,
            "title": "word " * 40,
        },
        "long-title": {
            "type": "string",
            "title": {"nested": {"deeply": ["word " * 20, 1, None, 2.5]}},
        },
    }
    for number, pattern in enumerate(REGEXES):
        bad[f"regex-{number}"] = {"type": "string", "pattern": pattern}
    cases = []
    for label, node in bad.items():
        cases.append((f"meta-{label}", add_field("broken", node)))
    cases.append(
        ("meta-top-level-number", edit(lambda m, n, t: {"messages.schema.json": 3}))
    )
    cases.append(
        ("meta-manifest-top", edit(lambda m, n, t: n.__setitem__("minProperties", -2)))
    )
    cases.append(
        ("meta-defs-not-object", edit(lambda m, n, t: m.__setitem__("$defs", [1])))
    )
    return cases


def text_cases():
    """Files that are not JSON, not UTF-8, or not there."""
    cases = []
    for name in ("messages.schema.json", "manifest.schema.json", "methods.json"):
        short = name.split(".")[0]
        for label, text in {
            "empty": "",
            "trailing-comma-array": "[1,]",
            "trailing-comma-object": '{"a": 1,}',
            "extra-data": "{} x",
            "bom": "﻿{}",
            "bad-escape": '{"a": "\\q"}',
            "bad-unicode-escape": '{"a": "\\u12"}',
            "control-character": '{"a": "x\ny"}',
            "unterminated": '{"a": "x',
            "missing-colon": '{"a" 1}',
            "missing-comma": "[1 2]",
            "nan": '{"a": NaN}',
            "multi-line": '{\n  "a": [\n    1,\n    ]\n}',
            "crlf-broken": '{\r\n  "a": [\r\n  1,]\r\n}',
            "not-utf8": b'{"a": "\xff"}',
            "truncated-utf8": b'{"a": "\xe2\x82',
        }.items():
            cases.append((f"text-{short}-{label}", raw(name, text)))
        cases.append(
            (
                f"text-{short}-missing",
                lambda pkg, name=name: os.remove(os.path.join(pkg, "protocol", name)),
            )
        )
        cases.append(
            (
                f"text-{short}-a-folder",
                lambda pkg, name=name: (
                    os.remove(os.path.join(pkg, "protocol", name)),
                    os.makedirs(os.path.join(pkg, "protocol", name)),
                ),
            )
        )

    def crlf(pkg):
        for name in ("messages.schema.json", "manifest.schema.json", "methods.json"):
            path = os.path.join(pkg, "protocol", name)
            with open(path, "rb") as h:
                data = h.read()
            with open(path, "wb") as h:
                h.write(data.replace(b"\n", b"\r\n"))

    cases.append(("text-crlf-everywhere", crlf))
    cases.append(
        ("text-no-protocol", lambda pkg: shutil.rmtree(os.path.join(pkg, "protocol")))
    )
    return cases


GENERATED = {
    "py": "kits/python/vitruvian_tool_kit/generated/messages.py",
    "ts": "kits/typescript/src/generated/messages.ts",
    "go": "go/toolkit/protocol_gen.go",
    "rs": "kits/rust/src/generated/mod.rs",
}


def committed_cases():
    """The committed files, gone stale in each way --check reports."""

    def change(rel, fn):
        def setup(pkg):
            path = os.path.join(pkg, rel)
            with open(path, "rb") as h:
                data = h.read()
            write(path, fn(data))

        return setup

    cases = []
    for label, rel in GENERATED.items():
        cases.append(
            (
                f"stale-{label}-one-line",
                change(rel, lambda d: d.replace(b"\n", b"\nchanged line\n", 1)),
            )
        )
        cases.append(
            (
                f"stale-{label}-many-lines",
                change(
                    rel,
                    lambda d: b"\n".join(
                        x + b" //" if i % 7 == 0 else x
                        for i, x in enumerate(d.split(b"\n"))
                    ),
                ),
            )
        )
        cases.append(
            (f"stale-{label}-truncated", change(rel, lambda d: d[: len(d) // 2]))
        )
        cases.append((f"stale-{label}-emptied", change(rel, lambda d: b"")))
        cases.append(
            (f"stale-{label}-crlf", change(rel, lambda d: d.replace(b"\n", b"\r\n")))
        )
        cases.append(
            (f"stale-{label}-old-mac", change(rel, lambda d: d.replace(b"\n", b"\r")))
        )
        cases.append(
            (f"stale-{label}-no-final-newline", change(rel, lambda d: d.rstrip(b"\n")))
        )
        cases.append(
            (
                f"stale-{label}-form-feed",
                change(rel, lambda d: d.replace(b"\n", b"\x0c", 3)),
            )
        )
        cases.append((f"stale-{label}-not-utf8", change(rel, lambda d: b"\xff" + d)))
        cases.append(
            (
                f"stale-{label}-missing",
                lambda pkg, rel=rel: os.remove(os.path.join(pkg, rel)),
            )
        )
        cases.append(
            (f"stale-{label}-repeated-lines", change(rel, lambda d: d + b"}\n" * 300))
        )
    cases.append(
        (
            "stale-stray-file",
            lambda pkg: write(
                os.path.join(pkg, "kits/python/vitruvian_tool_kit/generated/old.py"),
                "# left behind\n",
            ),
        )
    )
    cases.append(
        (
            "stale-stray-go",
            lambda pkg: write(
                os.path.join(pkg, "go/toolkit/extra_gen.go"), "package toolkit\n"
            ),
        )
    )
    cases.append(
        (
            "stale-ignored-folders",
            lambda pkg: [
                write(os.path.join(pkg, f"kits/typescript/{d}/generated/x.ts"), "x")
                for d in ("node_modules", "__pycache__", "dist")
            ],
        )
    )
    cases.append(
        (
            "stale-hand-written-ignored",
            lambda pkg: write(os.path.join(pkg, "kits/typescript/src/index2.ts"), "x"),
        )
    )
    cases.append(
        ("stale-no-kits", lambda pkg: shutil.rmtree(os.path.join(pkg, "kits")))
    )
    return cases


def cli_cases():
    pkg = PACKAGE
    cases = [
        Case("cli-help", ["-h"]),
        Case("cli-help-long", ["--help"]),
        Case("cli-help-prefix", ["--he"]),
        Case("cli-help-joined", ["-hx"]),
        Case("cli-help-dash", ["-h-x"]),
        Case("cli-help-value", ["--help=1"]),
        Case("cli-help-equals-empty", ["-h="]),
        Case("cli-help-after-check", ["--check", "-h"]),
        Case("cli-unknown", ["--frobnicate"]),
        Case("cli-unknown-value", ["--frob=1", "x"]),
        Case("cli-positional", ["extra"]),
        Case("cli-single-dash", ["-"]),
        Case("cli-short-unknown", ["-c"]),
        Case("cli-separator", ["--", "x", "y"]),
        Case("cli-separator-alone", ["--"]),
        Case("cli-out-missing", ["--out"]),
        Case("cli-out-then-option", ["--out", "--check"]),
        Case("cli-out-then-separator", ["--out", "--", "x"]),
        Case("cli-ambiguous", ["--=x"]),
        Case("cli-ambiguous-single", ["-=x"]),
        Case("cli-check-value", ["--check=1", "a", "-x"]),
        Case("cli-check-empty-value", ["--check="]),
        Case("cli-negative-number", ["--package", pkg, "--out", "-1"]),
        Case("cli-negative-alone", ["-5"]),
        Case("cli-space-arg", ["-a b"]),
        Case("cli-empty-arg", [""]),
        Case("cli-prefixes", ["--ch", "--pa", pkg]),
        Case("cli-package-equals", ["--check", f"--package={pkg}"]),
        Case("cli-package-empty", ["--check", "--package="]),
        Case("cli-out-empty", ["--out="]),
        Case("cli-out-twice", ["--out", "a", "--out", "b"]),
        Case("cli-unknown-and-missing", ["zzz", "--out"]),
    ]
    for columns in (
        "200",
        "80",
        "60",
        "40",
        "30",
        "20",
        "11",
        "1",
        "0",
        "abc",
        " 50 ",
        "-5",
    ):
        cases.append(
            Case(
                f"cli-help-columns-{columns.strip() or 'blank'}",
                ["-h"],
                env={"COLUMNS": columns},
            )
        )
        cases.append(
            Case(
                f"cli-error-columns-{columns.strip() or 'blank'}",
                ["--nope"],
                env={"COLUMNS": columns},
            )
        )
    return cases


def real_cases():
    pkg = PACKAGE
    return [
        Case("real-check", ["--check", "--package", pkg]),
        Case("real-check-default", ["--check"]),
        Case("real-write-default", []),
        Case("real-write-out", ["--out", "made"]),
        Case("real-write-out-absolute", ["--out", "{root}/made-abs"]),
        Case("real-write-out-nested", ["--package", pkg, "--out", "a/b/../c/"]),
        Case("real-write-in-place", ["--package", pkg]),
        Case(
            "real-workspace-env",
            ["--check"],
            env={"BUILD_WORKSPACE_DIRECTORY": "{root}"},
        ),
        Case(
            "real-workspace-env-empty",
            ["--check"],
            env={"BUILD_WORKSPACE_DIRECTORY": ""},
        ),
        Case(
            "real-workspace-env-elsewhere",
            ["--check"],
            env={"BUILD_WORKSPACE_DIRECTORY": "{root}/nowhere"},
        ),
        Case("real-package-missing", ["--check", "--package", "nope"]),
        Case(
            "real-out-is-a-file",
            ["--package", pkg, "--out", "afile"],
            setup=lambda p: write(
                os.path.join(os.path.dirname(os.path.dirname(p)), "afile"), "x"
            ),
        ),
        Case(
            "real-out-target-is-a-folder",
            ["--package", pkg, "--out", "made"],
            setup=lambda p: os.makedirs(
                os.path.join(
                    os.path.dirname(os.path.dirname(p)),
                    "made",
                    "go",
                    "toolkit",
                    "protocol_gen.go",
                )
            ),
        ),
    ]


def random_cases(count, seed=20261024):
    """Random changes to the real schemas: descriptions, names and fields."""
    rng = random.Random(seed)
    words = [
        "tool",
        "panel",
        "HUD",
        "URL",
        "id",
        "the",
        "a-b",
        "x",
        "été",
        "Σ",
        "--",
        "long" * 9,
        "\t",
        "two words",
        "ui",
        "Ui",
        "9lives",
        "",
    ]
    types = [
        {"type": "string"},
        {"type": "integer"},
        {"type": "number"},
        {"type": "boolean"},
        {"type": "object"},
        {"type": "array", "items": {"type": "string"}},
        {"type": "object", "additionalProperties": {"type": "number"}},
        {"$ref": "#/$defs/uiTree"},
        {"$ref": "#/$defs/uiText"},
        {"const": "k"},
        {},
        {"type": ["boolean", "number", "string"]},
        {"type": "array", "items": {"$ref": "#/$defs/uiBlock"}},
    ]

    def text():
        return " ".join(rng.choice(words) for _ in range(rng.randint(0, 40)))

    def name():
        first = rng.choice(["a", "ui", "url", "x", "data", "é", "N"])
        return first + "".join(
            rng.choice(["Folder", "HUD", "Id", "2", "Url", "Block", "s", "X"])
            for _ in range(rng.randint(0, 3))
        )

    cases = []
    for i in range(count):
        state = rng.random()
        edits: List[Dict[str, Any]] = []
        for _ in range(rng.randint(1, 4)):
            choice = rng.randrange(4)
            if choice == 0:
                edits.append(
                    {
                        "do": "describe",
                        "doc": rng.choice(["messages", "manifest"]),
                        "at": rng.random(),
                        "text": text(),
                    }
                )
            elif choice == 1:
                edits.append(
                    {
                        "do": "field",
                        "at": rng.random(),
                        "name": name(),
                        "node": rng.choice(types),
                        "required": rng.random() < 0.5,
                        "text": text(),
                    }
                )
            elif choice == 2:
                edits.append(
                    {
                        "do": "method",
                        "row": {
                            "method": name() + "/" + name(),
                            "sender": rng.choice(["tool", "app"]),
                            "kind": rng.choice(["request", "notice"]),
                            "uses": rng.choice([None, "notify", "storage"]),
                            "params": rng.choice(
                                [None, "notifyHUDParams", "uiOpenParams"]
                            ),
                            "result": rng.choice([None, "empty", "uiTree"]),
                        },
                    }
                )
            else:
                edits.append({"do": "drop", "at": rng.random()})

        def mutate(m, n, t, edits=edits):
            for e in edits:
                if e["do"] == "describe":
                    doc = m if e["doc"] == "messages" else n
                    keys = sorted(doc["$defs"])
                    node = doc["$defs"][keys[int(e["at"] * len(keys))]]
                    if isinstance(node, dict):
                        node["description"] = e["text"]
                elif e["do"] == "field":
                    keys = sorted(
                        k
                        for k, v in m["$defs"].items()
                        if isinstance(v, dict) and "properties" in v
                    )
                    node = m["$defs"][keys[int(e["at"] * len(keys))]]
                    field = dict(e["node"])
                    if e["text"]:
                        field["description"] = e["text"]
                    node["properties"][e["name"]] = field
                    if e["required"]:
                        node.setdefault("required", [])
                        if e["name"] not in node["required"]:
                            node["required"].append(e["name"])
                elif e["do"] == "method":
                    t["methods"].append(dict(e["row"]))
                elif t["methods"]:
                    del t["methods"][int(e["at"] * len(t["methods"]))]

        args = ["--check"] if state < 0.5 else ["--out", "made"]
        cases.append(Case(f"random-{i}", args, setup=schemas_setup(mutate)))
    return cases


# Each test in sdk_codegen_test.py, by the cases here that run its scenario
# through both programs.
SCENARIOS = {
    "test_every_method_of_the_table_is_in_the_model": [
        "real-check",
        "real-write-out",
        "method-added",
    ],
    "test_every_field_of_the_manifest_is_in_the_model": [
        "real-write-out",
        "manifest-with-text-field",
    ],
    "test_every_payload_of_the_messages_is_in_the_model": [
        "real-write-out",
        "field-string-optional",
    ],
    "test_protocol_2_is_in_the_model": ["real-write-out", "variant-other-rules"],
    "test_a_variant_whose_kind_is_not_defined_stops_the_generator": [
        "variant-undefined-kind"
    ],
    "test_a_list_of_names_with_no_name_stops_the_generator": ["enum-with-no-name"],
    "test_the_committed_files_are_what_it_writes": ["real-check", "real-check-default"],
    "test_a_change_to_a_schema_changes_what_it_writes": [
        "test-seconds-write",
        "test-seconds-check",
    ],
    "test_a_file_no_emitter_writes_is_caught": ["stale-stray-file"],
    "test_the_python_it_writes_is_python_3_9": ["real-write-out", "random-0"],
    "test_every_reader_the_manifest_files_call_is_imported": [
        "real-write-out",
        "manifest-boolean-and-number",
    ],
    "test_every_name_a_python_call_uses_is_imported": [
        "real-write-out",
        "method-added",
    ],
    "test_every_emitter_is_found": ["real-write-out"],
}


def seconds(m, n, t):
    """sdk_codegen_test's planted change: notifyHUDParams gains `seconds`."""
    m["$defs"]["notifyHUDParams"]["properties"]["seconds"] = {
        "description": "How long the message stays.",
        "type": "number",
    }


def all_cases():
    cases = [
        Case(
            "test-seconds-write",
            ["--out", "made"],
            setup=schemas_setup(seconds),
            keep=["made/go/toolkit/protocol_gen.go"],
        ),
        Case("test-seconds-check", ["--check"], setup=schemas_setup(seconds)),
    ]
    cases += real_cases()
    cases += cli_cases()
    for name, mutate in schema_cases() + broken_schema_cases():
        setup = schemas_setup(mutate)
        cases.append(Case(name, ["--out", "made"], setup=setup))
    for name in (
        "field-number-optional",
        "method-added",
        "variant-undefined-kind",
        "meta-type-foo",
    ):
        mutate = dict(schema_cases() + broken_schema_cases())[name]
        cases.append(Case(name + "-check", ["--check"], setup=schemas_setup(mutate)))
    for name, setup in text_cases():
        cases.append(Case(name, ["--check"], setup=setup))
    for name, setup in committed_cases():
        cases.append(Case(name, ["--check"], setup=setup))
    cases += random_cases(150)
    return cases


# Set before the workers fork, so each finds the cases by their number.
HARNESS: Optional["Harness"] = None
CASES: List["Case"] = []


def run_numbered(number):
    """One case in a worker: what differs, and what Python did."""
    case = CASES[number]
    assert HARNESS is not None
    results = HARNESS.run_case(case, number)
    py = results["py"]
    kept = {path: py[3].get(path) for path in case.keep}
    return case.name, Harness.differs(results), (py[0], py[1], py[2], kept)


class ParityTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        global HARNESS, CASES
        HARNESS = cls.harness = Harness()
        CASES = cls.cases = all_cases()
        names = [c.name for c in cls.cases]
        assert len(names) == len(set(names)), "case names repeat"
        # Processes, not threads: copying trees and reading them back is
        # Python work, which the GIL would run one at a time.
        workers = max(2, min(32, (os.cpu_count() or 2) * 2))
        with multiprocessing.get_context("fork").Pool(workers) as pool:
            done = pool.map(run_numbered, range(len(cls.cases)), chunksize=2)
        cls.problems = {name: problem for name, problem, _ in done}
        cls.outcomes = {name: py for name, _, py in done}

    @classmethod
    def tearDownClass(cls):
        cls.harness.close()

    def test_every_case_agrees(self):
        failures = [
            f"{name}: {problem}" for name, problem in self.problems.items() if problem
        ]
        self.assertEqual(failures, [], "\n\n".join(failures[:15]))

    def test_the_cases_reach_what_they_are_for(self):
        """The cases are only evidence if they reach the paths they name:
        each kind of outcome happens in Python, not just in the port."""
        outcomes = self.outcomes

        def crash(name):
            return (
                exception_text(outcomes[name][2].split(CHAINED)[-1])
                .split(b":")[0]
                .strip()
                .decode()
            )

        self.assertEqual(
            outcomes["real-check"][:2], (0, b"sdk-codegen: 9 files, in sync\n")
        )
        self.assertEqual(outcomes["test-seconds-check"][0], 1)
        self.assertIn(b"out of date", outcomes["test-seconds-check"][2])
        self.assertIn(
            b"Seconds *float64",
            outcomes["test-seconds-write"][3]["made/go/toolkit/protocol_gen.go"],
        )
        self.assertIn(b"no emitter writes it", outcomes["stale-stray-file"][2])
        self.assertEqual(crash("variant-undefined-kind"), "model.SchemaProblem")
        self.assertIn(
            b"add ('notifyHUDParams', 'color') to ENUMS",
            outcomes["enum-with-no-name"][2],
        )
        self.assertEqual(crash("meta-type-foo"), "jsonschema.exceptions.SchemaError")
        self.assertEqual(crash("meta-pattern-overflow"), "OverflowError")
        self.assertEqual(crash("meta-pattern-flags"), "ValueError")
        self.assertFalse(outcomes["meta-pattern-fine"][2].startswith(TRACEBACK))
        self.assertIn(
            b"re.error: missing ), unterminated subpattern at position 0",
            outcomes["meta-pattern-unclosed"][2],
        )
        self.assertEqual(
            crash("text-messages-trailing-comma-array"), "json.decoder.JSONDecodeError"
        )
        self.assertEqual(crash("text-messages-not-utf8"), "UnicodeDecodeError")
        self.assertEqual(crash("text-methods-missing"), "FileNotFoundError")
        self.assertEqual(crash("text-methods-a-folder"), "IsADirectoryError")
        self.assertEqual(crash("methods-empty"), "ValueError")
        self.assertEqual(crash("no-service-enum"), "StopIteration")
        self.assertEqual(crash("method-no-result"), "KeyError")
        self.assertEqual(crash("method-name-number"), "AttributeError")
        self.assertEqual(crash("methods-row-list"), "TypeError")
        self.assertEqual(crash("real-out-is-a-file"), "NotADirectoryError")
        self.assertEqual(outcomes["cli-help"][0], 0)
        self.assertEqual(outcomes["cli-unknown"][0], 2)
        self.assertEqual(outcomes["text-crlf-everywhere"][0], 0)
        self.assertEqual(outcomes["stale-py-crlf"][0], 0, "Python reads CRLF as LF")
        self.assertIn(
            b"wrote <ROOT>/packages/vitruvian-sdk/go/toolkit/protocol_gen.go",
            outcomes["real-write-default"][1],
        )
        # Help that wraps, and random cases that both pass and fail.
        self.assertNotEqual(
            outcomes["cli-help-columns-40"][1], outcomes["cli-help-columns-200"][1]
        )
        randoms = [outcomes[n][0] for n in outcomes if n.startswith("random-")]
        self.assertIn(0, randoms)
        self.assertIn(1, randoms)

    def test_every_scenario_of_the_python_tests_is_here(self):
        loader = unittest.TestLoader()
        tests = set()
        for cls in (sdk_codegen_test.ModelTests, sdk_codegen_test.OutputTests):
            tests |= set(loader.getTestCaseNames(cls))
        self.assertEqual(sorted(tests), sorted(SCENARIOS))
        known = {c.name for c in self.cases}
        for test, names in SCENARIOS.items():
            for name in names:
                self.assertIn(name, known, f"{test} names {name}, which is no case")


class TablesTest(unittest.TestCase):
    def test_the_unicode_tables_are_this_pythons(self):
        import gen_unicode_tables

        with open(
            os.path.join(HERE, "src", "unicode_tables.rs"), encoding="utf-8"
        ) as handle:
            self.assertEqual(handle.read(), gen_unicode_tables.render())

    def test_the_metaschemas_are_jsonschemas(self):
        from importlib import resources

        with open(
            os.path.join(HERE, "src", "metaschema.rs"), encoding="utf-8"
        ) as handle:
            text = handle.read()
        embedded = re.findall(
            r'\(\n        "([^"]+)",\n        r##"(.*?)"##,\n    \),', text, re.S
        )
        folder = (
            resources.files("jsonschema_specifications") / "schemas" / "draft202012"
        )
        files = {
            "https://json-schema.org/draft/2020-12/schema": folder / "metaschema.json"
        }
        for vocab in (
            "core",
            "applicator",
            "unevaluated",
            "validation",
            "meta-data",
            "format-annotation",
            "content",
        ):
            files[f"https://json-schema.org/draft/2020-12/meta/{vocab}"] = (
                folder / "vocabularies" / vocab
            )
        self.assertEqual([uri for uri, _ in embedded], list(files))
        for uri, body in embedded:
            self.assertEqual(body, files[uri].read_text(encoding="utf-8"), uri)


if __name__ == "__main__":
    unittest.main()
