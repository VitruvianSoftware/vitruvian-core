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
"""The guide's examples are true: docs/writing-a-tool.md cannot rot unseen.

The kit samples' README.md files, which the website shows as worked examples,
are held to the same rules for each kind of block below.

Every fenced block in the guide says what it is, and each kind is checked:

  json message    each line is a message the schema accepts. A result is also
                  held to the result of the request above it with its id.
  json manifest   a manifest the schema accepts.
  swift file=P    these lines are in the file P, together and in this order.
  python file=P   the same.
  javascript file=P   the same.
  go file=P       the same.
  rust file=P     the same.
  sh file=P       the same: lines of the shell script P.
  sh              every `vitruvian-tool` verb and flag, every template named
                  after --template, and every target of this package, is one
                  that exists.
  text said=P     each line is something the command says: it is in the file
                  P, once the line breaks Swift allows inside a text are joined.
  text            not checked. The guide has none.

A block of any other kind fails. So does a message of the protocol the guide
never shows, a field of the manifest it never names, a field in a manifest
example that the schema does not have, and a row of a table of the kits'
calls that names a call a kit does not have or the wrong message for it.
"""

import json
import os
import re
import sys

from jsonschema import Draft202012Validator

HERE = os.path.dirname(os.path.abspath(__file__))
PACKAGE = os.path.dirname(HERE)
GUIDE = os.path.join(HERE, "writing-a-tool.md")

# The worked examples the website shows beside the guide, one per kit sample.
EXAMPLES = ["samples/hello-typescript/README.md", "samples/hello-python-kit/README.md"]

# What `vitruvian-tool` takes. Words.swift holds the same list as its usage.
VERBS = {"init", "validate", "run"}
# What is typed after `vitruvian-tool` alone, in place of a verb.
ALONE = {"--version"}
FLAGS = {
    "--id",
    "--name",
    "--publisher",
    "--template",
    "--sdk",
    "--command",
    "--refuse",
    "--app-path",
    "--wait",
}


def read(path):
    with open(os.path.join(PACKAGE, path), encoding="utf-8") as handle:
        return handle.read()


def blocks(text):
    """Each fenced block: its info line, its lines, and the line it starts on.
    A block inside a list is indented, and is read without its indent."""
    found, info, lines, start, indent = [], None, [], 0, 0
    for number, line in enumerate(text.split("\n"), 1):
        if line.lstrip(" ").startswith("```"):
            if info is None:
                indent = len(line) - len(line.lstrip(" "))
                info, lines, start = line.strip()[3:].strip(), [], number
            else:
                found.append((info, lines, start))
                info = None
        elif info is not None:
            lines.append(line[indent:] if line[:indent].strip() == "" else line)
    return found


def message_problems(lines, where, schema, table, shown):
    problems, asked = [], {}
    whole = Draft202012Validator(schema)
    for line in lines:
        try:
            message = json.loads(line)
        except ValueError:
            problems.append(f"{where}: not JSON: {line[:60]}")
            continue
        if not whole.is_valid(message):
            problems.append(f"{where}: not a message of the protocol: {line[:80]}")
            continue
        if "method" in message:
            shown.add(message["method"])
            if message["method"] not in table:
                problems.append(
                    f"{where}: {message['method']} is no message of version 1"
                )
                # Its answer, below, then has no request above it.
                continue
            if "id" in message:
                asked[json.dumps(message["id"])] = message["method"]
        elif "result" in message:
            method = asked.get(json.dumps(message["id"]))
            if method is None:
                problems.append(f"{where}: a result with no request above it")
                continue
            part = {
                "$ref": f"#/$defs/{table[method]['result']}",
                "$defs": schema["$defs"],
            }
            if not Draft202012Validator(part).is_valid(message["result"]):
                problems.append(f"{where}: not the result of {method}: {line[:80]}")
    return problems


def excerpt_problems(lines, where, path):
    try:
        source = read(path)
    except OSError:
        return [f"{where}: there is no file {path}"]
    if "\n".join(lines) not in source:
        return [f"{where}: these lines are not in {path}, together and in this order"]
    return []


def said_problems(lines, where, path):
    try:
        source = read(path)
    except OSError:
        return [f"{where}: there is no file {path}"]
    # A Swift text may break a line with a backslash at its end.
    source = re.sub(r" ?\\\n\s*", " ", source)
    return [
        f"{where}: the command does not say this, by {path}: {line.strip()[:60]}"
        for line in lines
        if line.strip() and line.strip() not in source
    ]


def unknown_fields(value, schema, defs, path=""):
    """The fields of an example that the schema does not name."""
    while "$ref" in schema:
        schema = defs[schema["$ref"].split("/")[-1]]
    found = []
    if isinstance(value, dict) and "properties" in schema:
        for key, inner in value.items():
            if key not in schema["properties"]:
                found.append(path + key)
            else:
                found += unknown_fields(
                    inner, schema["properties"][key], defs, f"{path}{key}."
                )
    elif isinstance(value, list) and "items" in schema:
        for inner in value:
            found += unknown_fields(inner, schema["items"], defs, path)
    return found


def kit_problems(guide, table, kit):
    """The table of the kit's calls: each call is the kit's, each message is
    the protocol's, and each service is the one the message needs."""
    problems, rows, inside = [], 0, False
    for number, line in enumerate(guide.split("\n"), 1):
        cells = [cell.strip() for cell in line.split("|")[1:-1]]
        if cells[:2] == ["Call on `app`", "Message"]:
            inside = True
        elif not line.startswith("|"):
            inside = False
        if not inside or len(cells) != 3 or not re.match(r"`\w+(\(|`)", cells[0]):
            continue
        where = f"writing-a-tool.md:{number}"
        calls = re.findall(r"`(\w+)", cells[0])
        methods = re.findall(r"`([\w/]+)`", cells[1])
        rows += 1
        for method in methods:
            if method not in table:
                problems.append(f"{where}: {method} is no message of version 1")
        methods = [method for method in methods if method in table]
        for call in calls:
            if not re.search(rf"public (func|var) {call}\b", kit):
                problems.append(f"{where}: the kit has no call `{call}`")
        for method in methods:
            if table[method]["sender"] != "tool":
                continue
            uses = table[method]["uses"]
            if cells[2] != (f"`{uses}`" if uses else ""):
                problems.append(
                    f"{where}: {method} needs {uses or 'nothing'} in uses, not {cells[2] or 'nothing'}"
                )
    if rows < 10:
        problems.append(
            f"the table of the kit's calls has {rows} rows this test can read"
        )
    return problems


def native_kit_problems(guide, table, go, rust):
    """The table of the Go and Rust kits' calls: each is the kit's, and each
    message is the protocol's and needs the service the row says."""
    problems, rows, inside = [], 0, False
    for number, line in enumerate(guide.split("\n"), 1):
        cells = [cell.strip() for cell in line.split("|")[1:-1]]
        if cells[:3] == ["In Go", "In Rust", "Message"]:
            inside = True
            continue
        if not line.startswith("|"):
            inside = False
        if not inside or len(cells) != 4 or not cells[0].startswith("`"):
            continue
        where = f"writing-a-tool.md:{number}"
        rows += 1
        for call in re.findall(r"`app\.(?:(\w+)\.)?(\w+)`", cells[0]):
            group, name = call
            owner = group or "App"
            if not re.search(rf"func \(\w+ \*?{owner}\) {name}\(", go):
                problems.append(
                    f"{where}: the Go kit has no call app.{group + '.' if group else ''}{name}"
                )
        for call in re.findall(r"`app\.(?:(\w+)\(\)\.)?(\w+)`", cells[1]):
            group, name = call
            if group and not re.search(rf"pub fn {group}\(", rust):
                problems.append(f"{where}: the Rust kit has no app.{group}()")
            if not re.search(rf"pub fn {name}\(", rust):
                problems.append(f"{where}: the Rust kit has no call {name}")
        for method in re.findall(r"`([\w/]+)`", cells[2]):
            if method not in table:
                problems.append(f"{where}: {method} is no message of version 1")
                continue
            uses = table[method]["uses"]
            if table[method]["sender"] == "tool" and cells[3] != (
                f"`{uses}`" if uses else ""
            ):
                problems.append(f"{where}: {method} needs {uses or 'nothing'} in uses")
    if rows < 11:
        problems.append(
            f"the table of the Go and Rust calls has {rows} rows this test can read"
        )
    return problems


def templates():
    """The names `init --template` takes: ToolTemplate's cases in NewTool.swift."""
    source = read("Sources/VitruvianToolCLI/NewTool.swift")
    body = source[source.index("public enum ToolTemplate") :].split("}", 1)[0]
    return {
        raw or name for name, raw in re.findall(r'case (\w+)(?: = "([\w-]+)")?', body)
    }


def shell_problems(lines, where, build):
    problems = []
    for line in lines:
        words = line.split()
        if words[:1] == ["vitruvian-tool"]:
            if words[1] in ALONE:
                if len(words) > 2:
                    problems.append(
                        f"{where}: vitruvian-tool {words[1]} takes nothing after it"
                    )
                continue
            if words[1] not in VERBS:
                problems.append(f"{where}: vitruvian-tool has no `{words[1]}`")
            for word in words:
                if word.startswith("--") and word not in FLAGS:
                    problems.append(f"{where}: vitruvian-tool has no flag {word}")
            for named in re.findall(r"--template (\S+)", line):
                if named not in templates():
                    problems.append(f"{where}: init has no template {named}")
        for target in re.findall(r"//packages/vitruvian-sdk:([\w.-]+)", line):
            if f'name = "{target}"' not in build:
                problems.append(f"{where}: this package has no target {target}")
    return problems


def main():
    guide = read("docs/writing-a-tool.md")
    messages = json.loads(read("protocol/messages.schema.json"))
    manifest = json.loads(read("protocol/manifest.schema.json"))
    table = {
        row["method"]: row
        for row in json.loads(read("protocol/methods.json"))["methods"]
    }
    build = read("BUILD")
    problems, shown, kinds = [], set(), {}

    for info, lines, start in blocks(guide):
        where = f"writing-a-tool.md:{start}"
        kind = info.split(" file=")[0].split(" said=")[0]
        kinds[kind] = kinds.get(kind, 0) + 1
        if info == "json message":
            problems += message_problems(lines, where, messages, table, shown)
        elif info == "json manifest":
            example = json.loads("\n".join(lines))
            for error in Draft202012Validator(manifest).iter_errors(example):
                problems.append(f"{where}: {error.message}")
            for field in unknown_fields(example, manifest, manifest["$defs"]):
                problems.append(f"{where}: the manifest has no field `{field}`")
        elif (
            kind in ("swift", "python", "javascript", "go", "rust") and " file=" in info
        ):
            problems += excerpt_problems(lines, where, info.split(" file=")[1])
        elif info == "sh":
            problems += shell_problems(lines, where, build)
        elif info.startswith("sh file="):
            problems += excerpt_problems(lines, where, info.split(" file=")[1])
        elif info.startswith("text said="):
            problems += said_problems(lines, where, info.split("said=")[1])
        elif info != "text":
            problems.append(
                f"{where}: a block of a kind this test does not know: `{info}`"
            )

    for example in EXAMPLES:
        for info, lines, start in blocks(read(example)):
            where = f"{example}:{start}"
            if info == "sh":
                problems += shell_problems(lines, where, build)
            elif " file=" in info and info.split(" file=")[0] in (
                "sh",
                "javascript",
                "python",
            ):
                problems += excerpt_problems(lines, where, info.split(" file=")[1])
            else:
                problems.append(
                    f"{where}: a block of a kind this test does not know: `{info}`"
                )

    for method in table:
        if method not in shown:
            problems.append(f"the guide shows no example of {method}")
    for field in manifest["properties"]:
        if f"| `{field}` |" not in guide:
            problems.append(
                f"the guide's table of the manifest has no row for `{field}`"
            )
    problems += kit_problems(guide, table, read("Sources/VitruvianToolKit/Tool.swift"))
    problems += native_kit_problems(
        guide, table, read("go/toolkit/app.go"), read("kits/rust/src/app.rs")
    )
    for flag in FLAGS | VERBS | ALONE:
        if flag not in read("Sources/VitruvianToolCLI/Words.swift"):
            problems.append(f"the command's usage does not name {flag}")

    for problem in problems:
        print(problem, file=sys.stderr)
    print(
        "guide: "
        + ", ".join(f"{count} {kind}" for kind, count in sorted(kinds.items()))
    )
    print("guide: " + ("FAILED" if problems else "OK"))
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
