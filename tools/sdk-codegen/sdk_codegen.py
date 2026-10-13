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
"""Writes each kit's generated types from the protocol's schemas.

    sdk_codegen.py                 writes the files into packages/vitruvian-sdk
    sdk_codegen.py --check         fails when a committed file is not what
                                   would be written, or is one no emitter writes
    sdk_codegen.py --out FOLDER    writes them under FOLDER instead

It reads protocol/messages.schema.json, protocol/manifest.schema.json and
protocol/methods.json, builds one model of them (model.py), and hands that to
every module in emitters/. Each emitter returns its files, by their path in
the package. A language is added by adding its emitter, and nothing else here
changes: this finds the emitters by looking.

Each emitter writes only inside folders named `generated`, or, for Go, whose
packages are folders, a file named `*_gen.go` beside the kit's own; --check
reads every such file under kits/ and go/, so a file an emitter stopped
writing is caught as well as one that changed.
"""

import argparse
import difflib
import importlib
import os
import pkgutil
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import model  # noqa: E402

PACKAGE = os.path.join("packages", "vitruvian-sdk")


def emitters():
    """Every emitter module, by name, in a fixed order."""
    found = []
    for info in sorted(
        pkgutil.iter_modules([os.path.join(HERE, "emitters")]), key=lambda i: i.name
    ):
        module = importlib.import_module(f"emitters.{info.name}")
        if hasattr(module, "emit"):
            found.append(module)
    return found


def is_generated(path):
    """Whether a path is one an emitter may write: inside a folder named
    `generated`, or a Go file named `*_gen.go` (a Go package is a folder, so
    the Go kit's types sit beside its hand-written files, under Go's own name
    for a made file)."""
    parts = path.replace(os.sep, "/").split("/")
    return "generated" in parts[:-1] or parts[-1].endswith("_gen.go")


def generate(package):
    """Every generated file, by its path under `package`, and its text."""
    built = model.load(os.path.join(package, "protocol"))
    files = {}
    for emitter in emitters():
        for path, text in emitter.emit(built).items():
            if not is_generated(path):
                raise SystemExit(
                    f"{emitter.NAME} writes {path}, which is not inside a folder named generated"
                )
            if path in files:
                raise SystemExit(f"{path} is written by two emitters")
            files[path] = text
    return files


def committed(package):
    """Every generated file in the package's kits and its Go module."""
    found = {}
    for folder in ("kits", "go"):
        for root, folders, names in os.walk(os.path.join(package, folder)):
            folders[:] = [
                f for f in folders if f not in ("node_modules", "__pycache__", "dist")
            ]
            for name in names:
                path = os.path.join(root, name)
                relative = os.path.relpath(path, package).replace(os.sep, "/")
                if not is_generated(relative):
                    continue
                with open(path, encoding="utf-8") as handle:
                    found[relative] = handle.read()
    return found


def check(package):
    wanted = generate(package)
    have = committed(package)
    problems = []
    for path in sorted(set(wanted) | set(have)):
        if path not in have:
            problems.append(f"{path}: missing")
        elif path not in wanted:
            problems.append(f"{path}: no emitter writes it")
        elif have[path] != wanted[path]:
            diff = difflib.unified_diff(
                have[path].splitlines(),
                wanted[path].splitlines(),
                "committed/" + path,
                "generated/" + path,
                lineterm="",
                n=1,
            )
            problems.append(f"{path}: out of date\n" + "\n".join(list(diff)[:40]))
    for problem in problems:
        print(problem, file=sys.stderr)
    print(
        f"sdk-codegen: {len(wanted)} files, "
        + (
            "in sync"
            if not problems
            else "OUT OF SYNC, run: bazel run //tools/sdk-codegen"
        )
    )
    return 1 if problems else 0


def write(package, out):
    files = generate(package)
    for path, text in sorted(files.items()):
        target = os.path.join(out, path)
        os.makedirs(os.path.dirname(target), exist_ok=True)
        with open(target, "w", encoding="utf-8") as handle:
            handle.write(text)
        print(f"wrote {target}")
    return 0


def main(arguments):
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--out")
    parser.add_argument(
        "--package", help="the SDK's folder; found from the repository when left out"
    )
    options = parser.parse_args(arguments)
    # `bazel run` starts a program in its own folder; this is the repository.
    root = os.environ.get("BUILD_WORKSPACE_DIRECTORY")
    package = options.package or os.path.join(
        root or os.path.dirname(os.path.dirname(HERE)), PACKAGE
    )
    if options.check:
        return check(package)
    return write(package, options.out or package)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
