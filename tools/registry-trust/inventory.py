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

"""Which packages this repository publishes, to which registry, from where.

    bazel run //tools/registry-trust:inventory

Nothing here is a list somebody keeps. Every answer is read from a file that
already has to be right for a release to happen:

  what is released    every release-please-config.json in the repository: a
                      `node` package is its package.json, and an entry of
                      `extra-files` that writes a file's own version
                      ($.version, $.project.version, $.package.version) is a
                      package.json, pyproject.toml or Cargo.toml that is
                      released with it. An extra-file that writes a
                      dependency's version is a sample, not a package.
  what is public      the package file: `"private": true`, `publish = false`
                      and a `Private ::` classifier mean it is not published.
  which mirror        COMPONENTS in tools/copybara/copy.bara.sky: the mirror
                      is the component whose subtree holds the package.
  which workflow      the mirror's own workflows, under the subtree's
                      .github/workflows: the job that runs the registry's
                      publish command, and that job's `environment:`.

A package release-please releases that no workflow publishes (a desktop app
with a package.json, say) is not in the inventory, and `--all` says why. So a
package added to release-please later is covered with no edit here.

Standard library only, so the scheduled workflow runs it with plain python3.
"""

import collections
import json
import os
import re
import sys
import tomllib

COPYBARA = "tools/copybara/copy.bara.sky"
CONFIG = "release-please-config.json"
MANIFEST = ".release-please-manifest.json"
# Folders that hold other people's packages or build output, never ours.
PRUNED = {".git", "node_modules", "scratchpad", "target", "dist"}

REGISTRIES = ("npm", "pypi", "crates")
# The file a registry's package is described by, and where its own version is.
FILES = {
    "package.json": ("npm", "$.version"),
    "pyproject.toml": ("pypi", "$.project.version"),
    "Cargo.toml": ("crates", "$.package.version"),
}
# The release-types whose version file is implied, not listed in extra-files.
IMPLIED = {"node": "package.json", "python": "pyproject.toml", "rust": "Cargo.toml"}
# What a job runs to publish. `"npm", "publish"` is how a script spells it.
PUBLISHES = {
    "npm": re.compile(r"""\bnpm(?:\s+|["']\s*,\s*["'])publish\b"""),
    "pypi": re.compile(r"\buv\s+publish\b|\btwine\s+upload\b|gh-action-pypi-publish@"),
    "crates": re.compile(r"\bcargo\s+publish\b"),
}

Package = collections.namedtuple(
    "Package",
    "registry name version file path config owner repo workflow job environment",
)
Package.repository = property(lambda self: f"{self.owner}/{self.repo}")
Inventory = collections.namedtuple("Inventory", "packages skipped problems")


def _read(root, path):
    with open(os.path.join(root, path), encoding="utf-8") as handle:
        return handle.read()


def _configs(root):
    found = []
    for folder, folders, files in os.walk(root):
        folders[:] = sorted(
            d for d in folders if d not in PRUNED and not d.startswith("bazel-")
        )
        if CONFIG in files:
            found.append(os.path.relpath(os.path.join(folder, CONFIG), root))
    return sorted(found)


def mirrors(root):
    """[(subtree, owner, repo)] from copy.bara.sky, longest subtree first."""
    text = "\n".join(
        line
        for line in _read(root, COPYBARA).split("\n")
        if not line.lstrip().startswith("#")
    )
    owner = re.search(
        r'^STANDALONE_SSH_PREFIX = "git@github\.com:([^/"]+)/"', text, re.M
    )
    block = re.search(r"^COMPONENTS = \[\n(.*?)^\]", text, re.M | re.S)
    if not owner or not block:
        raise ValueError(
            f"{COPYBARA} has no STANDALONE_SSH_PREFIX or no COMPONENTS list"
        )
    found = []
    for component in re.findall(r"^    \{\n(.*?)^    \}", block.group(1), re.M | re.S):
        keys = dict(
            re.findall(r'^        "(name|repo|subtree)": "([^"]*)"', component, re.M)
        )
        if "name" not in keys:
            raise ValueError(f"{COPYBARA} has a component with no name")
        found.append(
            (
                keys.get("subtree", keys["name"]),
                owner.group(1),
                keys.get("repo", keys["name"]),
            )
        )
    if not found:
        raise ValueError(f"{COPYBARA} has an empty COMPONENTS list")
    return sorted(found, key=lambda m: -len(m[0]))


def publishing_jobs(text, registry):
    """[(job, environment)] of the jobs in one workflow that publish."""
    lines = [line for line in text.split("\n") if not line.lstrip().startswith("#")]
    jobs = []  # (name, indent, [lines])
    inside = False
    indent = None
    for line in lines:
        if re.match(r"^jobs:\s*$", line):
            inside = True
            continue
        if not inside or not line.strip():
            continue
        if not line.startswith(" "):
            break
        key = re.match(r"^( +)([A-Za-z0-9_-]+):\s*$", line)
        if indent is None and key:
            indent = len(key.group(1))
        if key and len(key.group(1)) == indent:
            jobs.append((key.group(2), []))
        elif jobs:
            jobs[-1][1].append(line)
    found = []
    for name, body in jobs:
        if not any(PUBLISHES[registry].search(line) for line in body):
            continue
        found.append((name, _environment(body)))
    return found


def _environment(body):
    """A job's `environment:`, written as a name or as a mapping with one."""
    depth = min((len(line) - len(line.lstrip()) for line in body), default=0)
    for index, line in enumerate(body):
        key = re.match(r"^( *)environment:\s*(.*?)\s*$", line)
        if not key or len(key.group(1)) != depth:
            continue
        if key.group(2):
            return key.group(2).strip("\"'")
        for inner in body[index + 1 :]:
            if len(inner) - len(inner.lstrip()) <= depth:
                break
            name = re.match(r"^\s+name:\s*(.*?)\s*$", inner)
            if name:
                return name.group(1).strip("\"'")
    return ""


def _describe(root, path):
    """(registry, name, version, why it is not published or None)."""
    registry = FILES[os.path.basename(path)][0]
    text = _read(root, path)
    if registry == "npm":
        data = json.loads(text)
        why = '"private": true' if data.get("private") else None
        return registry, data.get("name"), data.get("version"), why
    data = tomllib.loads(text)
    if registry == "crates":
        package = data.get("package", {})
        publish = package.get("publish", True)
        why = "publish = false" if publish is False or publish == [] else None
        return registry, package.get("name"), package.get("version"), why
    project = data.get("project", {})
    private = any(c.startswith("Private ::") for c in project.get("classifiers", []))
    why = "a Private :: classifier" if private else None
    return registry, project.get("name"), project.get("version"), why


def _version_files(config_path, config):
    """[(release-please path, version file)] one config names."""
    found = []
    for path, package in config.get("packages", {}).items():
        base = os.path.dirname(config_path) if path == "." else path
        kind = package.get("release-type", config.get("release-type"))
        if kind in IMPLIED:
            found.append((base, os.path.normpath(os.path.join(base, IMPLIED[kind]))))
        for extra in package.get("extra-files", config.get("extra-files", [])):
            if not isinstance(extra, dict):
                continue
            name = os.path.basename(extra.get("path", ""))
            if name in FILES and extra.get("jsonpath") == FILES[name][1]:
                found.append(
                    (base, os.path.normpath(os.path.join(base, extra["path"])))
                )
    return found


def load(root):
    packages, skipped, problems = [], [], []
    try:
        components = mirrors(root)
    except (OSError, ValueError) as error:
        return Inventory([], [], [str(error)])
    workflows = {}  # subtree -> {file name: text}

    def workflows_of(subtree):
        if subtree not in workflows:
            folder = os.path.join(root, subtree, ".github", "workflows")
            names = sorted(os.listdir(folder)) if os.path.isdir(folder) else []
            workflows[subtree] = {
                name: _read(root, os.path.join(subtree, ".github", "workflows", name))
                for name in names
                if name.endswith((".yml", ".yaml"))
            }
        return workflows[subtree]

    seen = set()
    for config_path in _configs(root):
        try:
            config = json.loads(_read(root, config_path))
        except ValueError as error:
            problems.append(f"{config_path} is not JSON: {error}")
            continue
        for path, file in _version_files(config_path, config):
            if file in seen:
                continue
            seen.add(file)
            try:
                registry, name, version, why = _describe(root, file)
            except OSError:
                problems.append(f"{config_path} releases {file}, which is not there")
                continue
            except ValueError as error:
                problems.append(f"{file} cannot be read: {error}")
                continue
            if why:
                skipped.append((file, f"not published: {why}"))
                continue
            if not name or not version:
                problems.append(f"{file} has no name or no version")
                continue
            mirror = next((m for m in components if file.startswith(m[0] + "/")), None)
            if mirror is None:
                skipped.append((file, f"no mirror in {COPYBARA} carries it"))
                continue
            subtree, owner, repo = mirror
            jobs = [
                (workflow, job, environment)
                for workflow, text in workflows_of(subtree).items()
                for job, environment in publishing_jobs(text, registry)
            ]
            if not jobs:
                skipped.append(
                    (
                        file,
                        f"no job in {owner}/{repo}'s workflows publishes to {registry}",
                    )
                )
                continue
            if len(jobs) > 1:
                where = ", ".join(f"{w} ({j})" for w, j, _ in jobs)
                problems.append(
                    f"{name} ({file}): more than one job publishes to {registry}: "
                    f"{where}. A registry trusts one workflow; which one is it?"
                )
                continue
            workflow, job, environment = jobs[0]
            packages.append(
                Package(
                    registry,
                    name,
                    version,
                    file,
                    path,
                    config_path,
                    owner,
                    repo,
                    workflow,
                    job,
                    environment,
                )
            )
    packages.sort(key=lambda p: (REGISTRIES.index(p.registry), p.name))
    return Inventory(packages, sorted(skipped), problems)


def root_folder():
    return os.environ.get("BUILD_WORKSPACE_DIRECTORY") or os.getcwd()


def main(argv, out=sys.stdout):
    found = load(root_folder())
    for problem in found.problems:
        print(f"registry-trust: {problem}", file=sys.stderr)
    if found.problems:
        return 2
    if "--json" in argv:
        json.dump([p._asdict() for p in found.packages], out, indent=2)
        out.write("\n")
        return 0
    for registry in REGISTRIES:
        mine = [p for p in found.packages if p.registry == registry]
        print(f"{registry}: {len(mine)} package(s)", file=out)
        for p in mine:
            environment = f" environment {p.environment}" if p.environment else ""
            print(
                f"  {p.name} {p.version}  <- {p.file}\n"
                f"      published by {p.repository} {p.workflow} (job {p.job}){environment}",
                file=out,
            )
    if "--all" in argv:
        print(f"left out: {len(found.skipped)} released file(s)", file=out)
        for file, why in found.skipped:
            print(f"  {file}: {why}", file=out)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
