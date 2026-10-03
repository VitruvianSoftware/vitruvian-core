#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 VitruvianSoftware

"""Hold the app's folders to one dependency direction until Bazel can.

REFACTOR.md step 3.2 splits `Sources/Vitruvian` into modules whose direction the
compiler enforces:

    Core  <-  Design  <-  Services  <-  UI  <-  App (with Support and main.swift)

`Design` holds the shared AppKit and SwiftUI building blocks (panels, backdrops,
editors) that services and views both draw with; it knows no feature.

Until that split lands, nothing stops a file from naming a type that a later
layer declares. This check does: it lists every such wrong-way reference and
compares the list with `bazel/layering_baseline.txt`.

- A reference missing from the baseline fails the check. Cut it instead of
  adding it: move the type to the layer it belongs in, or put an interface in
  front of it.
- A baseline line that no longer occurs also fails, so the baseline only ever
  shrinks and stays exact. Run with `--update` to rewrite it after a cut.

    bazel test //apps/desktop/vitruvian:layering_test               # check
    bazel run //apps/desktop/vitruvian:update_layering_baseline     # rewrite

It matches names, not semantics, after comments and string literals are
blanked. It sees a top-level type named in another file, a top-level function
called (`name(`), and a top-level constant or variable named. It skips
`main.swift`'s script variables (`app`, `delegate`), whose names collide with
everything. It does not see an extension member declared in a later layer
(Bazel catches those once the modules exist), and a name that happens to match
an unrelated nested type can show up as a false edge, which the baseline then
carries until the split.
"""

import argparse
import collections
import os
import re
import sys
from pathlib import Path

# Lower rank = lower layer. A file may name types of its own rank or lower.
RANKS = {
    "Core": 0,
    "FanControlKit": 0,
    "Design": 1,
    "Services": 2,
    "UI": 3,
    "App": 4,
    "Support": 4,
}
TOP_LEVEL_RANK = 4  # main.swift

TOP_LEVEL_DECL = re.compile(
    r"^(?:@[\w.]+(?:\([^)\n]*\))?\s+)*"
    r"(?P<mods>(?:(?:public|private|fileprivate|internal|package|final|indirect|nonisolated|open)\s+)*)"
    r"(?:enum|struct|class|protocol|typealias|actor)\s+(?P<name>[A-Z]\w*)",
    re.M,
)
TOP_LEVEL_VALUE = re.compile(
    r"^(?:@[\w.]+(?:\([^)\n]*\))?\s+)*"
    r"(?P<mods>(?:(?:public|private|fileprivate|internal|package|nonisolated)\s+)*)"
    r"(?P<kind>func|let|var)\s+(?P<name>[a-z_]\w*)",
    re.M,
)
IDENTIFIER = re.compile(r"\b([A-Z]\w*)\b")


def blank_comments_and_strings(text):
    """Replace comments and string literals with spaces, keeping newlines."""
    out = list(text)
    i, n = 0, len(text)

    def blank(a, b):
        for k in range(a, b):
            if out[k] != "\n":
                out[k] = " "

    while i < n:
        if text.startswith("//", i):
            j = text.find("\n", i)
            j = n if j < 0 else j
            blank(i, j)
            i = j
        elif text.startswith("/*", i):
            depth, j = 1, i + 2
            while j < n and depth:
                if text.startswith("/*", j):
                    depth, j = depth + 1, j + 2
                elif text.startswith("*/", j):
                    depth, j = depth - 1, j + 2
                else:
                    j += 1
            blank(i, j)
            i = j
        elif text[i] == '"' or (text[i] == "#" and re.match(r'#+"', text[i:])):
            hashes = 0
            while text[i + hashes] == "#":
                hashes += 1
            start, j = i, i + hashes
            triple = text.startswith('"""', j)
            close = ('"""' if triple else '"') + "#" * hashes
            j += 3 if triple else 1
            while j < n:
                if text[j] == "\\" and hashes == 0:
                    if j + 1 < n and text[j + 1] == "(":
                        # Interpolation: skip to its closing parenthesis, past
                        # any simple string literal inside it.
                        depth, k = 1, j + 2
                        while k < n and depth:
                            if text[k] == "(":
                                depth += 1
                            elif text[k] == ")":
                                depth -= 1
                            elif text[k] == '"':
                                k += 1
                                while k < n and text[k] != '"':
                                    k += 2 if text[k] == "\\" else 1
                            k += 1
                        j = k
                        continue
                    j += 2
                    continue
                if text.startswith(close, j):
                    j += len(close)
                    break
                if not triple and text[j] == "\n":
                    break
                j += 1
            blank(start, j)
            i = j
        else:
            i += 1
    return "".join(out)


def rank_of(path):
    head = path.split("/", 1)[0]
    if "/" not in path:
        return TOP_LEVEL_RANK
    if head not in RANKS:
        raise SystemExit(
            f"{path}: folder {head!r} has no layer; add it to RANKS in bazel/layering.py"
        )
    return RANKS[head]


def wrong_way_references(source_root):
    """Sorted lines `from -> Type (declared in)` for every wrong-way reference."""
    texts = {}
    for path in sorted(source_root.rglob("*.swift")):
        rel = path.relative_to(source_root).as_posix()
        texts[rel] = blank_comments_and_strings(path.read_text(encoding="utf-8"))

    declared_in = collections.defaultdict(set)  # type name -> files
    own = collections.defaultdict(set)  # file -> type names it declares
    for rel, text in texts.items():
        for match in TOP_LEVEL_DECL.finditer(text):
            name = match.group("name")
            own[rel].add(name)
            if re.search(r"\b(?:private|fileprivate)\b", match.group("mods")):
                continue  # invisible outside its own file
            declared_in[name].add(rel)

    # Top-level functions and globals: name -> (files, how a use looks).
    values = collections.defaultdict(set)
    use_pattern = {}
    for rel, text in texts.items():
        if "/" not in rel:
            continue  # main.swift's script variables
        for match in TOP_LEVEL_VALUE.finditer(text):
            if re.search(r"\b(?:private|fileprivate)\b", match.group("mods")):
                continue
            name = match.group("name")
            is_func = match.group("kind") == "func"
            values[name].add(rel)
            use_pattern[name] = (
                re.compile(
                    r"(?<![\w.])" + re.escape(name) + (r"\s*\(" if is_func else r"\b")
                ),
                f"{name}()" if is_func else name,
            )

    lines = set()
    for rel, text in texts.items():
        rank = rank_of(rel)
        for name in set(IDENTIFIER.findall(text)) - own[rel]:
            for target in declared_in.get(name, ()):
                if rank_of(target) > rank:
                    lines.add(f"{rel} -> {name} ({target})")
        for name, targets in values.items():
            pattern, label = use_pattern[name]
            later = [target for target in targets if rank_of(target) > rank]
            if later and pattern.search(text):
                for target in later:
                    lines.add(f"{rel} -> {label} ({target})")
    return sorted(lines)


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument(
        "--app-dir", type=Path, help="app root (defaults to the workspace copy)"
    )
    parser.add_argument(
        "--update",
        action="store_true",
        help="rewrite the baseline instead of checking it",
    )
    args = parser.parse_args()

    app = args.app_dir
    if app is None:
        workspace = os.environ.get("BUILD_WORKSPACE_DIRECTORY")
        app = (
            Path(workspace, "apps/desktop/vitruvian")
            if workspace
            else Path(__file__).resolve().parents[1]
        )
    baseline_path = app / "bazel" / "layering_baseline.txt"
    found = wrong_way_references(app / "Sources" / "Vitruvian")

    if args.update:
        header = (
            [
                line
                for line in baseline_path.read_text().splitlines()
                if line.startswith("#")
            ]
            if baseline_path.exists()
            else []
        )
        baseline_path.write_text("\n".join(header + found) + "\n")
        print(f"wrote {baseline_path}: {len(found)} wrong-way references")
        return 0

    expected = [
        line
        for line in baseline_path.read_text().splitlines()
        if line.strip() and not line.startswith("#")
    ]
    new = sorted(set(found) - set(expected))
    gone = sorted(set(expected) - set(found))
    for line in new:
        print(f"NEW wrong-way reference: {line}")
    for line in gone:
        print(f"CUT, remove from the baseline: {line}")
    if new or gone:
        print(
            "\nCore <- Design <- Services <- UI <- App. A new reference must be cut, not baselined "
            "(see bazel/layering.py). After a cut, run "
            "`bazel run //apps/desktop/vitruvian:update_layering_baseline`."
        )
        return 1
    print(f"layering OK: {len(found)} wrong-way references, all in the baseline")
    return 0


if __name__ == "__main__":
    sys.exit(main())
