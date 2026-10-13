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

"""Did every released version come from the workflow, and not from a person?

    bazel run //tools/registry-trust:check
    python3 tools/registry-trust/check.py        # the same, with no Bazel

WHY THIS EXISTS. Publishing is keyless: release-please moves a version,
Copybara exports it, and the mirror's release.yml publishes with the runner's
identity. Nothing proved that is what happened. On 2026-10-13 two packages
were first published by a person, because npm and crates.io refuse to attach
a trusted publisher to a package that does not exist yet. That one publish is
allowed, once, and written down; this fails on any other.

It asks the registries, in public, with no token:

  npm        registry.npmjs.org/<package>: a version the workflow published
             has `_npmUser.trustedPublisher` and `dist.attestations`. A
             person's has their login and neither.
  crates.io  /api/v1/crates/<crate>/versions: `trustpub_data` names the
             repository that published by trusted publishing. A person's
             upload has null there and `published_by.login`.
  PyPI       /integrity/<project>/<version>/<file>/provenance: the workflow
             and repository that attested the file. A file with none says
             nothing public about who uploaded it, so it is reported as
             "not publicly verifiable" and never counted as the workflow's.

THE ONE EXCEPTION is a row of bootstrap.tsv: the last version of a package
published before the workflow could prove itself. That version, and any the
registry got before it, are history. Every version after it must be the
workflow's. One row a package at most; a row cannot name a version the
registry lacks or one the workflow published.

The packages come from //tools/registry-trust:inventory, so from
release-please. Standard library only.

Exit: 0 every version is the workflow's or recorded · 1 one or more are not
      · 2 a registry could not be read, or bootstrap.tsv is wrong
"""

import collections
import datetime
import json
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import inventory  # noqa: E402

LEDGER = "tools/registry-trust/bootstrap.tsv"
# crates.io refuses a request that does not say who is asking.
USER_AGENT = (
    "VitruvianSoftware/vitruvian-core registry-trust "
    "(github.com/VitruvianSoftware/vitruvian-core)"
)
HOSTS = ("registry.npmjs.org", "crates.io", "pypi.org")
CALLED = {"npm": "npm", "pypi": "PyPI", "crates": "crates.io"}
ATTEMPTS = 4

Row = collections.namedtuple("Row", "registry package version date why")
# kind: workflow | person | silent (the registry says nothing) | foreign
Version = collections.namedtuple("Version", "number when kind who")
# state: ok | absent ; lines are what went wrong, each naming package and version
Result = collections.namedtuple(
    "Result", "package state workflow history silent upto offending"
)


class RegistryError(Exception):
    """A registry gave no usable answer. Never read as "nothing is wrong"."""


# --- the ledger ---------------------------------------------------------------


def parse_ledger(text):
    rows, problems, seen = [], [], {}
    for number, line in enumerate(text.split("\n"), 1):
        if not line.strip() or line.startswith("#"):
            continue
        fields = line.split("\t")
        if len(fields) != 5 or not all(f.strip() for f in fields):
            problems.append(
                f"line {number}: want 5 fields with tabs between "
                "(registry, package, version, date, why), each filled in"
            )
            continue
        row = Row(*(f.strip() for f in fields))
        if row.registry not in inventory.REGISTRIES:
            problems.append(
                f"line {number}: {row.registry!r} is not one of "
                + ", ".join(inventory.REGISTRIES)
            )
            continue
        if not re.fullmatch(r"\d{4}-\d{2}-\d{2}", row.date):
            problems.append(f"line {number}: the date {row.date!r} is not YYYY-MM-DD")
            continue
        key = (row.registry, row.package)
        if key in seen:
            problems.append(
                f"line {number}: more than one row for {row.registry} {row.package} "
                f"(the other is line {seen[key]}). A package is bootstrapped once."
            )
            continue
        seen[key] = number
        rows.append(row)
    return rows, problems


def unknown_rows(rows, packages):
    known = {(p.registry, p.name) for p in packages}
    return [
        f"{row.registry} {row.package} has a row and is not in the inventory: "
        "take the row out, or put the package back under release-please"
        for row in rows
        if (row.registry, row.package) not in known
    ]


# --- asking a registry ----------------------------------------------------------


def request_for(url):
    if urllib.parse.urlsplit(url).hostname not in HOSTS:
        raise ValueError(f"{url} is not one of the three registries")
    return urllib.request.Request(
        url, headers={"User-Agent": USER_AGENT, "Accept": "application/json"}
    )


def http_fetch(url, opener=urllib.request.urlopen, sleep=time.sleep):
    """(status, body). Asks again when the registry is briefly down, so one
    blip is not a red run; an answer of "not there" is an answer."""
    status, body = None, b""
    for attempt in range(ATTEMPTS):
        if attempt:
            sleep(2 * attempt)
        try:
            with opener(request_for(url), timeout=30) as answer:
                return answer.status, answer.read()
        except urllib.error.HTTPError as error:
            status, body = error.code, error.read()
            error.close()
            if status < 500 and status != 429:
                return status, body
        except (urllib.error.URLError, TimeoutError) as error:
            status, body = None, str(error).encode()
    if status is None:
        raise RegistryError(f"{url} could not be reached: {body.decode()}")
    return status, body


def _get(fetch, url, absent_ok=False):
    status, body = fetch(url)
    if status == 404 and absent_ok:
        return None
    if status != 200:
        raise RegistryError(
            f"{url} answered HTTP {status}; refusing to guess what is published"
        )
    try:
        return json.loads(body)
    except ValueError as error:
        raise RegistryError(f"{url} did not answer with JSON: {error}") from error


def _when(text):
    return datetime.datetime.fromisoformat(text.replace("Z", "+00:00"))


def npm_versions(package, fetch):
    name = urllib.parse.quote(package.name, safe="@")
    data = _get(fetch, f"https://registry.npmjs.org/{name}", absent_ok=True)
    if data is None:
        return None
    found = []
    for number, version in data.get("versions", {}).items():
        user = version.get("_npmUser") or {}
        trusted = (user.get("trustedPublisher") or {}).get("id") == "github"
        attested = bool((version.get("dist") or {}).get("attestations"))
        kind = "workflow" if trusted and attested else "person"
        found.append(
            Version(number, _when(data["time"][number]), kind, user.get("name", "?"))
        )
    return found


def crates_versions(package, fetch):
    base = f"https://crates.io/api/v1/crates/{package.name}/versions"
    page, found = "?per_page=100", []
    while page:
        data = _get(fetch, base + page, absent_ok=not found)
        if data is None:
            return None
        for version in data["versions"]:
            trusted = version.get("trustpub_data")
            if not trusted:
                kind = "person"
                who = (version.get("published_by") or {}).get("login", "?")
            else:
                who = trusted.get("repository") or trusted.get("project_path", "?")
                mine = (
                    trusted.get("provider") == "github"
                    and who.lower() == package.repository.lower()
                )
                kind = "workflow" if mine else "foreign"
            found.append(
                Version(version["num"], _when(version["created_at"]), kind, who)
            )
        page = data.get("meta", {}).get("next_page")
    return found


def pypi_versions(package, fetch):
    data = _get(fetch, f"https://pypi.org/pypi/{package.name}/json", absent_ok=True)
    if data is None:
        return None
    found = []
    for number, files in data.get("releases", {}).items():
        if not files:
            continue
        kinds, who = [], ""
        for file in files:
            proof = _get(
                fetch,
                f"https://pypi.org/integrity/{package.name}/{number}/"
                f"{file['filename']}/provenance",
                absent_ok=True,
            )
            publishers = [
                bundle.get("publisher") or {}
                for bundle in (proof or {}).get("attestation_bundles", [])
            ]
            if not publishers:
                kinds.append("silent")
                continue
            for publisher in publishers:
                mine = (
                    publisher.get("kind") == "GitHub"
                    and publisher.get("repository", "").lower()
                    == package.repository.lower()
                    and publisher.get("workflow") == package.workflow
                )
                kinds.append("workflow" if mine else "foreign")
                if not mine:
                    who = f"{publisher.get('repository')} {publisher.get('workflow')}"
        if "foreign" in kinds:
            kind = "foreign"
        elif all(k == "workflow" for k in kinds):
            kind = "workflow"
        else:
            kind = "silent"
        when = max(_when(file["upload_time_iso_8601"]) for file in files)
        found.append(Version(number, when, kind, who))
    return found


VERSIONS = {"npm": npm_versions, "crates": crates_versions, "pypi": pypi_versions}

# --- the rule -------------------------------------------------------------------


def _said(package, version):
    where = f"{package.registry} {package.name} {version.number}"
    if version.kind == "person":
        return f"{where}: published by a person ({version.who}), not by the workflow"
    if version.kind == "foreign":
        return (
            f"{where}: published from {version.who}, not from "
            f"{package.repository} {package.workflow}"
        )
    return (
        f"{where}: {CALLED[package.registry]} has no provenance for it, so nothing "
        "public says the workflow published it"
    )


def check_one(package, row, fetch):
    versions = VERSIONS[package.registry](package, fetch)
    if versions is None:
        return Result(package, "absent", 0, 0, 0, None, [])
    offending, cutoff = [], None
    if row:
        recorded = next((v for v in versions if v.number == row.version), None)
        if recorded is None:
            offending.append(
                f"{package.registry} {package.name}: bootstrap.tsv records "
                f"{row.version}, which {CALLED[package.registry]} does not have"
            )
        elif recorded.kind == "workflow":
            offending.append(
                f"{package.registry} {package.name}: bootstrap.tsv records "
                f"{row.version}, which the workflow published: the row excuses "
                "nothing and must go"
            )
        else:
            cutoff = recorded.when
    workflow = history = silent = 0
    for version in sorted(versions, key=lambda v: v.when):
        if version.kind == "workflow":
            workflow += 1
        elif version.kind != "foreign" and cutoff and version.when <= cutoff:
            if version.kind == "silent":
                silent += 1
            else:
                history += 1
        else:
            offending.append(_said(package, version))
    return Result(
        package,
        "ok",
        workflow,
        history,
        silent,
        row.version if cutoff else None,
        offending,
    )


def check(packages, rows, fetch):
    by_package = {(row.registry, row.package): row for row in rows}
    return [
        check_one(package, by_package.get((package.registry, package.name)), fetch)
        for package in packages
    ]


def report(results, out):
    offending = [line for result in results for line in result.offending]
    for result in results:
        package = result.package
        label = f"{package.registry} {package.name}"
        if result.state == "absent":
            print(f"  --  {label}: not yet on the registry", file=out)
            continue
        parts = [f"{result.workflow} by the workflow"]
        if result.history:
            parts.append(
                f"{result.history} before the workflow took over "
                f"(to {result.upto}, recorded)"
            )
        if result.silent:
            parts.append(
                f"{result.silent} not publicly verifiable (to {result.upto}, recorded): "
                f"{CALLED[package.registry]} says nothing public about who published "
                "a file with no provenance"
            )
        mark = "✗ " if result.offending else ("?? " if result.silent else "ok ")
        print(f"  {mark} {label}: " + "; ".join(parts), file=out)
    total = (
        f"{len(results)} package(s): "
        f"{sum(r.workflow for r in results)} version(s) by the workflow, "
        f"{sum(r.history for r in results)} before the workflow took over, "
        f"{sum(r.silent for r in results)} not publicly verifiable, "
        f"{sum(1 for r in results if r.state == 'absent')} not yet on a registry"
    )
    if offending:
        print(
            f"registry-trust: {len(offending)} thing(s) the workflow did not publish:",
            file=out,
        )
        for line in offending:
            print(f"  ✗ {line}", file=out)
        print(f"registry-trust: {total}.", file=out)
        print(
            "  A version a person published is not what the code built. See "
            "docs/engineering/registry-trust.md.",
            file=out,
        )
        return 1
    print(f"registry-trust: {total}.", file=out)
    return 0


def main(argv, fetch=http_fetch, out=sys.stdout, err=sys.stderr, root=None):
    if argv:
        print(f"registry-trust: unknown argument: {argv[0]}", file=err)
        return 2
    root = root or inventory.root_folder()
    found = inventory.load(root)
    problems = list(found.problems)
    try:
        with open(os.path.join(root, LEDGER), encoding="utf-8") as handle:
            rows, wrong = parse_ledger(handle.read())
    except OSError:
        rows, wrong = [], [f"{LEDGER} is missing"]
    problems += [f"{LEDGER}: {problem}" for problem in wrong]
    problems += [f"{LEDGER}: {p}" for p in unknown_rows(rows, found.packages)]
    if not found.packages and not problems:
        problems.append("the inventory is empty: release-please or the layout moved")
    if problems:
        for problem in problems:
            print(f"registry-trust: {problem}", file=err)
        return 2
    try:
        return report(check(found.packages, rows, fetch), out)
    except RegistryError as error:
        print(f"registry-trust: {error}", file=err)
        return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
