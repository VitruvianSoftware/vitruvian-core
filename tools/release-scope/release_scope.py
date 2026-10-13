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
"""Does this pull request release a product its title does not name?

    python3 tools/release-scope/release_scope.py \\
        --pr-json pr.json --commits-json commits.json --files files.txt

release-please proposes a release of a product whenever a commit on main of a
releasing type (`feat`, `fix`, ...) changes a file in that product's folder.
main is squash-merged, so one pull request is one commit. A pull request for
one product that also changes a file in another's folder therefore releases
both, and the second release has nothing in it: the same code published again
under a new version, or an update offered to every user that changes nothing.
On 13 October 2026 that happened three times (#3193, #3211, #3217).

This fails such a pull request before it merges, and says what to do.

THE RULES ARE RELEASE-PLEASE'S, read from its source at the version the
workflows pin (17.6.0, release-please-action v5.0.0), and the products are
whatever the release-please-config.json files in this tree say. Nothing here
lists a product.

  What lands on main (GitHub's squash settings for this repository,
  COMMIT_OR_PR_TITLE and COMMIT_MESSAGES): one commit lands under that
  commit's own message, more than one under the pull request's title with the
  commits as `* ` bullets. A BEGIN_COMMIT_OVERRIDE block in the description
  replaces the message (src/commit.ts, preprocessCommitMessage).

  Which commits it holds (src/commit.ts, splitMessages and the footers): the
  subject, and any later line that reads as a commit, `fix(scope): ...`.
  This check takes every such line; release-please takes most of them. It
  errs towards saying so.

  Which of them release (src/strategies/base.ts, changelogEmpty): one whose
  type has a visible changelog section. Those are feat, feature, fix, perf
  and revert, unless the config's `changelog-sections` says otherwise. A `!`
  or a BREAKING CHANGE footer releases whatever the type, and so does a
  Release-As footer.

  Which products (src/util/commit-split.ts, commit-exclude.ts): each config is
  run on its own. In it a file belongs to the longest package path that holds
  it, `file.indexOf(path + "/") === 0`, and a commit is dropped for a package
  when every file of the package's that it changes is under one of the
  package's `exclude-paths`, by the same test. So exclude-paths names folders,
  never a file.

A PULL REQUEST NAMES A PRODUCT when the scope of a releasing commit is the
product's `component` or `package-name` in its config, or an alias for it in
aliases.json beside this file, or when the description has a line

    Releases: vitruvian-sdk, vitruvian-tool-github

which is how a pull request that truly changes two products says so.

Left alone, for what they are: release-please's own pull requests (their
branch starts `release-please--`) and the dependency bots' (a Bot account on a
`dependabot/` or `renovate/` branch), which nobody can retitle.

Exit 0 when every product it would release is named, 1 when one is not, 2
when it could not tell (no config found, a config that does not parse).
"""

import argparse
import dataclasses
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
CONFIG_NAME = "release-please-config.json"
ROOT_PATH = "."

# conventional-changelog-conventionalcommits 6, which release-please 17 uses
# when a config has no `changelog-sections`: the types with a visible section.
VISIBLE_BY_DEFAULT = frozenset(["feat", "feature", "fix", "perf", "revert"])
# What to write instead when nothing a user gets changes.
QUIET_TYPES = "chore, ci, test, docs, refactor, build, style"

# release-please's own split of one message into several (src/commit.ts).
SPLIT = re.compile(
    r"\r?\n\r?\n(?=(?:feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert)(?:\(.*?\))?: )"
)
HEADER = re.compile(r"^(?P<type>\w+)(?:\((?P<scope>[^()]*)\))?(?P<bang>!)?:\s*\S")
BREAKING = re.compile(r"^BREAKING[ -]CHANGE:\s*\S", re.M)
RELEASE_AS = re.compile(r"^release-as:\s*\S", re.M | re.I)
RELEASES_LINE = re.compile(r"^[ \t]*Releases:[ \t]*(\S.*?)[ \t]*\r?$", re.M)
SKIP_DIRS = {".git", "node_modules"}


class Misconfigured(Exception):
    """The check cannot tell. Never a pass."""


@dataclasses.dataclass
class PullRequest:
    title: str
    body: str
    files: list
    commits: list  # each commit's whole message, oldest first
    author: str
    author_type: str
    head_ref: str


@dataclasses.dataclass(frozen=True)
class Message:
    type: str
    scope: object
    breaking: bool
    release_as: bool
    header: str


@dataclasses.dataclass(frozen=True)
class Component:
    name: str
    package_name: object
    path: str
    excludes: tuple
    visible: frozenset
    siblings: tuple  # every package path in the same config
    config: str


@dataclasses.dataclass
class Verdict:
    ok: bool = True
    exempt: str = ""
    subject: str = ""
    one_commit: bool = False
    released: dict = dataclasses.field(default_factory=dict)  # name -> files
    named: list = dataclasses.field(default_factory=list)
    unnamed: list = dataclasses.field(default_factory=list)
    unknown: list = dataclasses.field(default_factory=list)  # on a Releases line
    idle: list = dataclasses.field(default_factory=list)  # named there, not released
    why: dict = dataclasses.field(default_factory=dict)  # name -> the commit line
    paths: dict = dataclasses.field(default_factory=dict)  # name -> its folder
    scopes: list = dataclasses.field(default_factory=list)


def _clean(path):
    """release-please's normalizePaths."""
    path = path.strip()
    while path.startswith("./"):
        path = path[2:]
    return path.strip("/") or ROOT_PATH


def _under(file, path):
    return path == ROOT_PATH or file.startswith(path + "/")


def load_components(configs):
    """Every product, from {config's path: the config}."""
    components = []
    for where in sorted(configs):
        config = configs[where]
        packages = config.get("packages")
        if not isinstance(packages, dict) or not packages:
            raise Misconfigured(f"{where} has no packages")
        siblings = tuple(_clean(path) for path in packages)
        for raw, package in packages.items():
            path = _clean(raw)
            sections = package.get("changelog-sections") or config.get(
                "changelog-sections"
            )
            visible = (
                frozenset(s["type"] for s in sections if not s.get("hidden"))
                if sections
                else VISIBLE_BY_DEFAULT
            )
            folder = os.path.dirname(where) if path == ROOT_PATH else path
            name = (
                package.get("component")
                or package.get("package-name")
                or os.path.basename(folder)
            )
            if not name:
                raise Misconfigured(f"{where}: the package {raw} has no name")
            components.append(
                Component(
                    name=name,
                    package_name=package.get("package-name"),
                    path=path,
                    excludes=tuple(_clean(e) for e in package.get("exclude-paths", [])),
                    visible=visible,
                    siblings=siblings,
                    config=where,
                )
            )
    names = [c.name for c in components]
    twice = sorted({n for n in names if names.count(n) > 1})
    if twice:
        raise Misconfigured(
            f"two release-please packages share a name: {', '.join(twice)}"
        )
    return components


def load_aliases(raw):
    """aliases.json as {scope: [component, ...]}."""
    try:
        return {
            scope: list(entry["components"]) for scope, entry in raw["aliases"].items()
        }
    except (KeyError, TypeError) as error:
        raise Misconfigured(
            f"aliases.json is not {{aliases: {{scope: {{components: [...]}}}}}}: {error!r}"
        )


def pull_request(pr, commits, files):
    """From GitHub's pull request object, its commits' messages and its files."""
    return PullRequest(
        title=pr.get("title") or "",
        body=pr.get("body") or "",
        files=list(files),
        commits=list(commits),
        author=(pr.get("user") or {}).get("login") or "",
        author_type=(pr.get("user") or {}).get("type") or "",
        head_ref=(pr.get("head") or {}).get("ref") or "",
    )


def squash_message(pull):
    """The commit message this pull request lands on main under."""
    override = (
        (pull.body.split("BEGIN_COMMIT_OVERRIDE", 1) + [""])[1]
        .split("END_COMMIT_OVERRIDE")[0]
        .strip()
    )
    if override:
        return override
    if len(pull.commits) == 1:
        return pull.commits[0].strip()
    if not pull.commits:
        return pull.title
    return pull.title + "\n\n" + "\n\n".join("* " + c.strip() for c in pull.commits)


def messages(message):
    """The conventional commits release-please would read in one message."""
    parts = message.split("BEGIN_NESTED_COMMIT")
    texts = [parts[0]]
    for part in parts[1:]:
        nested, *rest = part.split("END_NESTED_COMMIT")
        texts.append(nested)
        texts[0] += "END_NESTED_COMMIT".join(rest)
    texts = [t for t in SPLIT.split(texts[0]) if t] + texts[1:]
    found = []
    for text in texts:
        lines = text.strip().split("\n")
        first = HEADER.match(lines[0])
        if not first:
            continue  # release-please cannot parse it, and skips it whole
        breaking = bool(BREAKING.search(text)) or "BREAKING-CHANGE:" in text
        found.append(
            Message(
                type=first["type"],
                scope=first["scope"],
                breaking=bool(first["bang"]) or breaking,
                release_as=bool(RELEASE_AS.search(text)),
                header=lines[0].strip(),
            )
        )
        for line in lines[1:]:
            more = HEADER.match(line)
            if more:
                found.append(
                    Message(
                        more["type"],
                        more["scope"],
                        bool(more["bang"]),
                        False,
                        line.strip(),
                    )
                )
    return found


def _exempt(pull):
    if pull.head_ref.startswith("release-please--"):
        return f"release-please's own pull request (its branch is {pull.head_ref})"
    if pull.author_type == "Bot" and pull.head_ref.startswith(
        ("dependabot/", "renovate/")
    ):
        return f"a dependency bot's pull request ({pull.author} on {pull.head_ref}), which nobody can retitle"
    return ""


def _files_released(component, files):
    """The files that make release-please keep this commit for the component."""
    if component.path == ROOT_PATH:
        owned = list(files)
    else:
        longest_first = sorted(
            (p for p in component.siblings if p != ROOT_PATH), key=len, reverse=True
        )
        owned = [
            f
            for f in files
            if "/" in f
            and next((p for p in longest_first if f.startswith(p + "/")), None)
            == component.path
        ]
    if not owned:
        return []
    if not component.excludes:
        return owned
    relevant = [f for f in files if _under(f, component.path)]
    kept = [f for f in relevant if not any(_under(f, e) for e in component.excludes)]
    return kept


def judge(pull, components, aliases):
    by_name = {c.name: c for c in components}
    for scope, targets in aliases.items():
        missing = [t for t in targets if t not in by_name]
        if missing:
            raise Misconfigured(
                f"aliases.json: {scope} means {', '.join(missing)}, which no release-please config has"
            )
    exempt = _exempt(pull)
    if exempt:
        return Verdict(ok=True, exempt=exempt)

    message = squash_message(pull)
    found = messages(message)
    verdict = Verdict(
        subject=message.split("\n")[0],
        one_commit=len(pull.commits) == 1 and "BEGIN_COMMIT_OVERRIDE" not in pull.body,
        scopes=sorted({m.scope for m in found if m.scope}),
    )

    declared = []
    for line in RELEASES_LINE.findall(pull.body):
        declared += [n for n in re.split(r"[,\s]+", line.replace("`", "")) if n]
    by_package = {c.package_name: c.name for c in components if c.package_name}
    declared_names = set()
    for name in declared:
        if name in by_name:
            declared_names.add(name)
        elif name in by_package:
            declared_names.add(by_package[name])
        elif name not in verdict.unknown:
            verdict.unknown.append(name)

    for component in sorted(components, key=lambda c: c.name):
        releasing = [
            m
            for m in found
            if m.breaking or m.release_as or m.type in component.visible
        ]
        if not releasing:
            continue
        files = _files_released(component, pull.files)
        if not files:
            continue
        verdict.released[component.name] = files
        verdict.paths[component.name] = component.path
        verdict.why[component.name] = releasing[0].header
        scopes = {m.scope for m in releasing if m.scope}
        named = (
            component.name in declared_names
            or component.name in scopes
            or (component.package_name and component.package_name in scopes)
            or any(component.name in aliases.get(scope, []) for scope in scopes)
        )
        (verdict.named if named else verdict.unnamed).append(component.name)

    verdict.idle = sorted(declared_names - set(verdict.released))
    verdict.ok = not verdict.unnamed and not verdict.unknown
    return verdict


def _listing(verdict, names, limit=8):
    lines = []
    for name in names:
        files = verdict.released[name]
        lines.append(f"  {name}   (its folder is {verdict.paths[name]})")
        lines += [f"      {f}" for f in files[:limit]]
        if len(files) > limit:
            lines.append(f"      ... and {len(files) - limit} more")
    return lines


def report(verdict):
    if verdict.exempt:
        return f"release-scope: not judged. This is {verdict.exempt}."
    out = []
    if verdict.ok:
        if verdict.released:
            out.append(
                "release-scope: OK. Merging this proposes a release of: "
                + ", ".join(verdict.released)
                + ". Each is named by the title's scope or a Releases: line."
            )
        else:
            out.append("release-scope: OK. Merging this releases nothing.")
        out.append(f"  It lands on main as: {verdict.subject}")
        if verdict.idle:
            out.append(
                "  Note: the Releases: line names "
                + ", ".join(verdict.idle)
                + ", which this pull request would not release."
            )
        return "\n".join(out)

    out.append("release-scope: FAILED.")
    if verdict.unnamed:
        out += [
            "",
            "Merging this pull request would release a product it does not name.",
            "",
            f"It lands on main as:  {verdict.subject}",
        ]
        if verdict.one_commit:
            out.append(
                "(It has one commit, so GitHub lands it under that commit's message, not the pull request's title.)"
            )
        out += [
            "",
            "release-please proposes a release of every product that has a changed file in its",
            "folder when the commit's type is one that releases. This one's is: "
            + verdict.why[verdict.unnamed[0]],
            "",
            "Would be released, and NOT named:",
        ]
        out += _listing(verdict, verdict.unnamed)
        if verdict.named:
            out += ["", "Would be released, and named (fine):"]
            out += _listing(verdict, verdict.named, limit=3)
        out += [
            "",
            "A release with nothing in it publishes the same code again under a new version, or",
            "offers every user an update that changes nothing. Three ways out:",
            "",
            "  1. Split it. Move the files listed above into a pull request of their own, titled",
            "     for that product (or with a type that does not release, if that is what it is).",
            "",
            "  2. If nothing a user of any product gets changes, use a type that does not release:",
            f"     {QUIET_TYPES}.",
            "",
            "  3. If it truly changes each of these products, say so. Put this line, on its own, in",
            "     the pull request's description:",
            "",
            "         Releases: " + ", ".join(sorted(verdict.released)),
            "",
        ]
        if verdict.one_commit:
            out += [
                "For 1 or 2 with one commit, change the commit's message (the title alone is not",
                "what lands), or push a second commit and the title is used. This check runs again",
                "when the title or the description is edited and when commits are pushed.",
            ]
        else:
            out.append(
                "This check runs again when the title or the description is edited and when commits are pushed."
            )
    if verdict.unknown:
        out += [
            "",
            "The Releases: line names "
            + ", ".join(verdict.unknown)
            + ", which no release-please config has.",
            "Use a product's component name, as in its release-please-config.json.",
        ]
    return "\n".join(out)


def find_configs(root):
    """Every release-please-config.json under root, parsed."""
    configs = {}
    for folder, dirs, files in os.walk(root):
        dirs[:] = sorted(
            d for d in dirs if d not in SKIP_DIRS and not d.startswith("bazel-")
        )
        if CONFIG_NAME in files:
            where = os.path.relpath(os.path.join(folder, CONFIG_NAME), root)
            try:
                with open(
                    os.path.join(folder, CONFIG_NAME), encoding="utf-8"
                ) as handle:
                    configs[where.replace(os.sep, "/")] = json.load(handle)
            except ValueError as error:
                raise Misconfigured(f"{where} does not parse: {error}")
    if not configs:
        raise Misconfigured(f"no {CONFIG_NAME} under {root}")
    return configs


def _read_json(path):
    with open(path, encoding="utf-8") as handle:
        return json.load(handle)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--pr-json", required=True, help="GitHub's pull request object")
    parser.add_argument(
        "--commits-json", required=True, help="a JSON list of the commits' messages"
    )
    parser.add_argument("--files", required=True, help="the changed files, one a line")
    parser.add_argument("--repo-root", default=".")
    parser.add_argument("--aliases", default=os.path.join(HERE, "aliases.json"))
    args = parser.parse_args(argv)
    try:
        with open(args.files, encoding="utf-8") as handle:
            files = [line.strip() for line in handle if line.strip()]
        pull = pull_request(
            _read_json(args.pr_json), _read_json(args.commits_json), files
        )
        components = load_components(find_configs(args.repo_root))
        verdict = judge(pull, components, load_aliases(_read_json(args.aliases)))
    except (Misconfigured, OSError, ValueError) as error:
        print(
            f"release-scope: COULD NOT TELL, which is not a pass. {error}",
            file=sys.stderr,
        )
        return 2
    print(report(verdict))
    return 0 if verdict.ok else 1


if __name__ == "__main__":
    sys.exit(main())
