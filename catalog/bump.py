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

"""Updates one tool's catalog entry from one of its releases.

    bazel run //catalog:bump -- --id dev.vitruvian.homespeaker --tag home-speaker-v1.20.0
    bazel run //catalog:bump -- --id ... --tag ... --release-dir <folder>
    python3 catalog/bump.py plan --out plan.json

`bump` reads the release through `gh` (or, with --release-dir, from a folder
holding release.json and the files, which is how the tests run it). It
refuses, and writes nothing, unless the zip's size and SHA-256 are the ones
GitHub records for the file, its SHA-256 is the one the release's .sha256
says, the zip is safe to unpack, and its manifest has the entry's id and the
tag's version. Then it writes the new version, download, size and SHA-256,
copies what the README says an entry copies from the manifest (the summary,
the name, what it uses, its commands...), sets `generated`, and rewrites
the website's _data/tools.yml as //tools/sync-site-tools:sync does. It never
touches minimumAppVersion: when the manifest declares something only newer
apps draw, it says so in the pull request's text for a person to decide. It
never touches the signed copy the website serves; catalog-publish writes that
after the merge.

`plan` asks GitHub for the newest release of each row of sources.json and
prints the ones that are newer than the catalog: what the hourly workflow
bumps. Standard library and `gh` only, so it runs without Bazel.

Exit status: 0 done (or nothing to do), 1 refused, 2 the release has no zip
yet, 3 the tool is not listed yet.
"""

import argparse
import copy
import hashlib
import json
import os
import re
import subprocess
import sys
import tempfile
import zipfile
from datetime import datetime, timedelta, timezone
from pathlib import Path

import catalog_rules

OK, REFUSED, NOT_READY, NOT_LISTED = 0, 1, 2, 3

CATALOG = "catalog/tools.json"
SCHEMA = "catalog/catalog.schema.json"
SOURCES = "catalog/sources.json"
HOME_REPO = "VitruvianSoftware/vitruvian-core"

# What a manifest may declare that an app older than the version given does
# not draw, from packages/vitruvian-sdk/protocol/README.md and the app's
# CHANGELOG. Each is a note for a person, never a change to the floor.
FEATURES = [
    (
        "protocol 2",
        lambda m: m.get("protocol") == "2",
        "3.45.0",
        "an older app refuses the tool",
    ),
    (
        "a status mark on the closed island (`contributes.status`)",
        lambda m: "status" in m.get("contributes", {}),
        "3.48.0",
        "an older app ignores it and shows no mark",
    ),
    (
        "a preference drawn as a menu (`options`)",
        lambda m: any("options" in p for p in m.get("preferences", [])),
        "3.48.0",
        "an older app draws a text field",
    ),
    (
        "a few words beside the status (`contributes.status.activity`)",
        lambda m: bool(m.get("contributes", {}).get("status", {}).get("activity")),
        "3.50.0",
        "an older app leaves the words out",
    ),
]


class Refused(Exception):
    """A release that must not be listed: each reason, said plainly."""

    def __init__(self, reasons):
        super().__init__("; ".join(reasons))
        self.reasons = list(reasons)


class NotReady(Exception):
    """A release that is not ready to list yet, which is not a failure."""


class NotListed(Exception):
    """A tool the catalog does not list: the first listing is by hand."""


def notice(message):
    """A line the run's summary shows when it runs in GitHub Actions."""
    prefix = "::notice::" if os.environ.get("GITHUB_ACTIONS") else ""
    print(prefix + message)


# --- The table of sources -----------------------------------------------------


def load_sources(path):
    data = json.loads(Path(path).read_text(encoding="utf-8"))
    rows = data.get("sources", [])
    for row in rows:
        for key in ("id", "repo", "tagPrefix", "asset"):
            if not isinstance(row.get(key), str) or not row[key]:
                raise SystemExit(f"sources.json: a row has no {key}: {row}")
        if "{version}" not in row["asset"]:
            raise SystemExit(f"sources.json: {row['id']}'s asset has no {{version}}")
    return data


def row_for(sources, tool_id):
    for row in sources["sources"]:
        if row["id"] == tool_id:
            return row
    raise Refused(
        [f"{tool_id} has no row in catalog/sources.json, so no release updates it"]
    )


def version_of(row, tag):
    """The version a tag names, or None when it is not this row's tag."""
    if not tag.startswith(row["tagPrefix"]):
        return None
    version = tag[len(row["tagPrefix"]) :]
    return version if catalog_rules.semver(version) else None


def asset_name(row, version):
    return row["asset"].replace("{version}", version)


def download_url(row, tag, version):
    return f"https://github.com/{row['repo']}/releases/download/{tag}/{asset_name(row, version)}"


def branch_for(tool_id, version):
    return f"catalog/bump-{tool_id}-{version}"


# --- Where a release is read from ---------------------------------------------


def gh(args, run=subprocess.run):
    """`gh` with these arguments: its output as bytes, or None when it fails."""
    done = run(["gh", *args], capture_output=True)
    if done.returncode != 0:
        sys.stderr.write(done.stderr.decode("utf-8", "replace"))
        return None
    return done.stdout


class GhRelease:
    """A release on GitHub, read through `gh`."""

    def __init__(self, repo, tag):
        self.repo, self.tag = repo, tag

    def metadata(self):
        out = gh(["api", f"repos/{self.repo}/releases/tags/{self.tag}"])
        return json.loads(out) if out else None

    def fetch(self, asset):
        """The bytes of one asset, by its id, so no name is read as a pattern."""
        return gh(
            [
                "api",
                "-H",
                "Accept: application/octet-stream",
                f"repos/{self.repo}/releases/assets/{asset['id']}",
            ]
        )


class FolderRelease:
    """A release kept in a folder: release.json, shaped like GitHub's answer,
    and each asset's file beside it."""

    def __init__(self, folder):
        self.folder = Path(folder)

    def metadata(self):
        path = self.folder / "release.json"
        if not path.exists():
            return None
        return json.loads(path.read_text(encoding="utf-8"))

    def fetch(self, asset):
        path = self.folder / asset["name"]
        return path.read_bytes() if path.exists() else None


# --- The checks ---------------------------------------------------------------

SIDECAR = re.compile(r"^([0-9a-f]{64})\s+\*?(\S.*?)\s*$")


def checked_zip(row, tag, version, release, work):
    """The release's zip, written into `work`, once every check passed: its
    path, SHA-256, size and manifest. Raises NotReady or Refused."""
    meta = release.metadata()
    if meta is None:
        raise NotReady(f"{row['repo']} has no release tagged {tag}")
    if meta.get("draft") or meta.get("prerelease"):
        raise NotReady(f"{tag} is a draft or a pre-release")
    assets = {a.get("name"): a for a in meta.get("assets", [])}
    name = asset_name(row, version)
    asset = assets.get(name)
    if asset is None:
        raise NotReady(f"{tag} has no {name} yet")
    reasons = []
    sidecar = assets.get(name + ".sha256")
    if sidecar is None:
        reasons.append(f"{tag} has {name} but no {name}.sha256 to check it against")
    digest = asset.get("digest") or ""
    if not digest.startswith("sha256:"):
        reasons.append(f"GitHub records no SHA-256 for {name} ({digest or 'none'})")
    if reasons:
        raise Refused(reasons)

    data = release.fetch(asset)
    if data is None:
        raise Refused([f"{name} could not be downloaded"])
    sha = hashlib.sha256(data).hexdigest()
    if len(data) != asset.get("size"):
        reasons.append(f"{name} is {len(data)} bytes, GitHub says {asset.get('size')}")
    if sha != digest[len("sha256:") :]:
        reasons.append(f"{name}'s SHA-256 is {sha}, GitHub says {digest}")
    side = release.fetch(sidecar)
    match = SIDECAR.match((side or b"").decode("utf-8", "replace").split("\n")[0])
    if not match:
        reasons.append(f"{name}.sha256 is not `<sha256>  <file name>`")
    else:
        if match.group(1) != sha:
            reasons.append(f"{name}.sha256 says {match.group(1)}, the zip's is {sha}")
        if os.path.basename(match.group(2)) != name:
            reasons.append(f"{name}.sha256 is the checksum of {match.group(2)}")
    if reasons:
        raise Refused(reasons)

    path = Path(work) / name
    path.write_bytes(data)
    problems = catalog_rules.zip_problems(path)
    if problems:
        raise Refused([f"{name}: {p}" for p in problems])
    with zipfile.ZipFile(path) as archive:
        try:
            manifest = json.loads(archive.read("vitruvian-tool.json"))
        except (KeyError, ValueError) as error:
            raise Refused([f"{name}'s vitruvian-tool.json cannot be read: {error}"])
    if manifest.get("id") != row["id"]:
        reasons.append(f"the manifest's id is {manifest.get('id')}, not {row['id']}")
    if manifest.get("version") != version:
        reasons.append(
            f"the manifest's version is {manifest.get('version')}, the tag's is {version}"
        )
    if reasons:
        raise Refused(reasons)
    return path, sha, len(data), manifest


# --- The entry ----------------------------------------------------------------


def from_manifest(entry, manifest):
    """The fields an entry copies from its manifest (catalog/README.md), set
    to what the manifest says. Returns the names of the fields that changed.
    `uses` keeps the entry's order when only the order differs."""
    contributes = manifest.get("contributes", {})
    wanted = [
        ("name", manifest.get("name")),
        ("publisher", manifest.get("publisher")),
        ("protocol", manifest.get("protocol")),
        ("summary", manifest.get("description")),
        ("uses", list(manifest.get("uses", []))),
        (
            "commands",
            [
                {"id": c.get("id"), "title": c.get("title")}
                for c in contributes.get("commands", [])
            ],
        ),
    ]
    if "panels" in entry:
        wanted.append(
            ("panels", [p.get("placement") for p in contributes.get("panels", [])])
        )
    changed = []
    for field, value in wanted:
        same = (
            sorted(entry.get(field, [])) == sorted(value)
            if field == "uses"
            else entry.get(field) == value
        )
        if not same:
            entry[field] = value
            changed.append(field)
    return changed


def floor_notes(manifest, floor):
    """What the manifest declares that apps from before the current floor do
    not have, each with the version that has it."""
    notes = []
    for what, declared, since, older in FEATURES:
        if declared(manifest) and catalog_rules.semver(since) > catalog_rules.semver(
            floor
        ):
            notes.append(f"It declares {what}, which Vitruvian {since} draws; {older}.")
    return notes


def next_generated(previous, now):
    """Now, in UTC to the second, and always later than the list it replaces:
    the app refuses a list older than one it has seen."""
    stamp = now.astimezone(timezone.utc).replace(microsecond=0)
    before = catalog_rules.generated({"generated": previous})
    if before is not None and stamp <= before:
        stamp = before + timedelta(seconds=1)
    return stamp.strftime("%Y-%m-%dT%H:%M:%SZ")


# --- tools.json, written the way it is written by hand -------------------------


def dumps(value, indent=0):
    """JSON as tools.json is kept: two spaces, a list of plain values on one
    line, everything else one item a line, and every language as itself."""
    pad, inner = "  " * indent, "  " * (indent + 1)
    if isinstance(value, dict):
        if not value:
            return "{}"
        items = [
            f"{inner}{json.dumps(k, ensure_ascii=False)}: {dumps(v, indent + 1)}"
            for k, v in value.items()
        ]
        return "{\n" + ",\n".join(items) + "\n" + pad + "}"
    if isinstance(value, list):
        if all(not isinstance(v, (dict, list)) for v in value):
            return (
                "[" + ", ".join(json.dumps(v, ensure_ascii=False) for v in value) + "]"
            )
        items = [inner + dumps(v, indent + 1) for v in value]
        return "[\n" + ",\n".join(items) + "\n" + pad + "]"
    return json.dumps(value, ensure_ascii=False)


def schema_problems(root, catalog):
    from jsonschema import Draft202012Validator

    schema = json.loads((root / SCHEMA).read_text(encoding="utf-8"))
    return [
        f"schema: {'/'.join(map(str, e.path))}: {e.message}"
        for e in Draft202012Validator(schema).iter_errors(catalog)
    ]


def write_site(root):
    """_data/tools.yml, as //tools/sync-site-tools:sync writes it."""
    try:
        import catalogue
    except ImportError:
        sys.path.insert(0, str(root / "tools" / "sync-site-tools"))
        import catalogue
    for path, data in catalogue.outputs(root).items():
        (root / path).parent.mkdir(parents=True, exist_ok=True)
        (root / path).write_bytes(data)
        print(f"wrote {path}")


# --- bump ---------------------------------------------------------------------


def short(sha):
    return f"{sha[:8]}…{sha[-4:]}"


def body_for(row, tag, entry, previous, size, sha, changed, notes, added_uses):
    name = entry["name"]["en"]
    where = "" if row["repo"] == HOME_REPO else f" in {row['repo']}"
    lines = [
        f"The tool catalog now offers {name} {entry['version']}, released as "
        f"`{tag}`{where}. It offered {previous}.",
        "",
        f"- **The download:** `{asset_name(row, entry['version'])}`, {size} bytes, "
        f"SHA-256 `{short(sha)}`.",
    ]
    if changed:
        lines.append(
            "- **Also copied from the tool's manifest**, as an entry says what its "
            f"manifest says: {', '.join(f'`{f}`' for f in changed)}."
        )
    if added_uses:
        lines.append(
            "- **Please read:** the tool now asks for "
            + ", ".join(f"`{u}`" for u in added_uses)
            + ". Check its source uses it for what the release says."
        )
    floor = entry["minimumAppVersion"]
    if notes:
        lines.append(
            f"- **Oldest app version stays {floor}; a person decides whether to "
            "raise it.** " + " ".join(notes)
        )
    else:
        lines.append(
            f"- **Oldest app version stays {floor}:** the manifest declares nothing "
            "an app that old lacks."
        )
    lines += [
        "- **Website data:** `_data/tools.yml` is regenerated, as "
        "`bazel run //tools/sync-site-tools:sync` writes it.",
        "",
        "**Checked before this pull request opened** (`bazel run //catalog:bump`): "
        "the zip's size and SHA-256 are the ones GitHub records for the file, and "
        "the SHA-256 is the one in the release's `.sha256`; the zip unpacks safely "
        "(no links, nothing outside its folder, within the size limits); its "
        f"manifest's id is `{entry['id']}` and its version is the tag's; the "
        "catalog passes its schema and rules. **catalog-check** downloads it again "
        "here and runs `vitruvian-tool validate` on it.",
        "",
        "After the merge, catalog-publish signs the list and opens the pull request "
        "for the website.",
        "",
        "Opened by the catalog-bump workflow. It does not merge itself.",
    ]
    return "\n".join(lines) + "\n"


def bump(root, sources, tool_id, tag, release, now):
    """Updates the entry in root's tools.json and tools.yml. Returns what the
    pull request needs; raises Refused, NotReady or NotListed."""
    row = row_for(sources, tool_id)
    version = version_of(row, tag)
    if version is None:
        raise Refused(
            [
                f"{tag} is not a tag of {tool_id}: its tags are {row['tagPrefix']}<version>"
            ]
        )
    _, catalog = catalog_rules.load(root / CATALOG)
    index = next(
        (i for i, t in enumerate(catalog["tools"]) if t["id"] == tool_id), None
    )
    if index is None:
        raise NotListed(
            f"{tool_id} is not in the catalog yet; listing it the first time is a "
            "pull request by hand (catalog/README.md)"
        )
    entry = catalog["tools"][index]
    previous = entry["version"]
    if catalog_rules.semver(version) < catalog_rules.semver(previous):
        raise Refused([f"the catalog lists {previous}, newer than {version}"])

    with tempfile.TemporaryDirectory() as work:
        _, sha, size, manifest = checked_zip(row, tag, version, release, work)

    url = download_url(row, tag, version)
    if version == previous:
        if entry["download"] == {"url": url, "sha256": sha, "size": size}:
            return {"status": "current", "id": tool_id, "version": version}
        raise Refused(
            [
                f"the catalog lists {version} with another download; the release's "
                "zip changed after it was listed, or the entry was edited by hand"
            ]
        )

    new = copy.deepcopy(entry)
    new["version"] = version
    new["download"] = {"url": url, "sha256": sha, "size": size}
    changed = from_manifest(new, manifest)
    added_uses = sorted(set(new.get("uses", [])) - set(entry.get("uses", [])))
    catalog["tools"][index] = new
    catalog["generated"] = next_generated(catalog["generated"], now)

    problems = (
        schema_problems(root, catalog)
        + catalog_rules.problems(catalog)
        + catalog_rules.manifest_problems(new, manifest)
    )
    if problems:
        raise Refused(problems)

    (root / CATALOG).write_text(dumps(catalog) + "\n", encoding="utf-8")
    print(f"wrote {CATALOG}: {tool_id} {previous} -> {version}")
    write_site(root)
    notes = floor_notes(manifest, new["minimumAppVersion"])
    return {
        "status": "bumped",
        "id": tool_id,
        "version": version,
        "previous": previous,
        "tag": tag,
        "branch": branch_for(tool_id, version),
        "title": f"feat(catalog): {new['name']['en']} {version}",
        "body": body_for(
            row, tag, new, previous, size, sha, changed, notes, added_uses
        ),
    }


# --- plan ---------------------------------------------------------------------


def newest_release(row, releases):
    """The newest published release of a row: (tag, version), or None."""
    best = None
    for release in releases:
        if release.get("draft") or release.get("prerelease"):
            continue
        version = version_of(row, release.get("tag_name", ""))
        if version and (
            best is None
            or catalog_rules.semver(version) > catalog_rules.semver(best[1])
        ):
            best = (release["tag_name"], version)
    return best


def plan(catalog, sources, list_releases, open_pull):
    """The rows whose newest release is newer than their entry and that have
    no pull request open for it (one that no longer merges is redone)."""
    listed = {t["id"]: t for t in catalog["tools"]}
    asked = {}
    found = []
    for row in sources["sources"]:
        entry = listed.get(row["id"])
        if entry is None:
            notice(
                f"{row['id']} is not in the catalog yet: the first listing is by hand."
            )
            continue
        if row["repo"] not in asked:
            asked[row["repo"]] = list_releases(row["repo"])
        newest = newest_release(row, asked[row["repo"]])
        if newest is None:
            notice(
                f"{row['id']}: {row['repo']} has no release tagged {row['tagPrefix']}<version>."
            )
            continue
        tag, version = newest
        if catalog_rules.semver(version) <= catalog_rules.semver(entry["version"]):
            print(
                f"{row['id']}: the catalog lists {entry['version']}, the newest release."
            )
            continue
        pull = open_pull(branch_for(row["id"], version))
        if pull and pull.get("mergeable") != "CONFLICTING":
            print(f"{row['id']} {version}: pull request #{pull['number']} is open.")
            continue
        print(f"{row['id']}: {tag} is newer than the catalog's {entry['version']}.")
        found.append({"id": row["id"], "tag": tag})
    return found


def gh_releases(repo):
    out = gh(["api", f"repos/{repo}/releases?per_page=100"])
    if out is None:
        raise SystemExit(f"could not list the releases of {repo}")
    return json.loads(out)


def gh_open_pull(branch):
    repo = os.environ.get("GITHUB_REPOSITORY", HOME_REPO)
    out = gh(
        [
            "pr",
            "list",
            "--repo",
            repo,
            "--head",
            branch,
            "--state",
            "open",
            "--json",
            "number,mergeable",
        ]
    )
    if out is None:
        raise SystemExit(f"could not list the pull requests of {repo}")
    pulls = json.loads(out)
    return pulls[0] if pulls else None


# --- The command --------------------------------------------------------------


def workspace(given):
    if given:
        return Path(given)
    if os.environ.get("BUILD_WORKSPACE_DIRECTORY"):
        return Path(os.environ["BUILD_WORKSPACE_DIRECTORY"])
    return Path(__file__).resolve().parent.parent


def main(argv=None, list_releases=gh_releases, open_pull=gh_open_pull):
    argv = list(sys.argv[1:] if argv is None else argv)
    if not argv or argv[0] not in ("bump", "plan"):
        argv.insert(0, "bump")
    parser = argparse.ArgumentParser(
        description="Updates one tool's catalog entry from one of its releases."
    )
    commands = parser.add_subparsers(dest="command", required=True)
    one = commands.add_parser("bump", help="update one entry from one release")
    one.add_argument(
        "--id", required=True, help="the catalog entry, e.g. dev.vitruvian.homespeaker"
    )
    one.add_argument(
        "--tag", required=True, help="the release, e.g. home-speaker-v1.20.0"
    )
    one.add_argument(
        "--release-dir", help="read the release from this folder, not GitHub"
    )
    one.add_argument(
        "--result-out", help="write what the pull request needs here, as JSON"
    )
    one.add_argument("--now", help="the time to set generated to (tests)")
    one.add_argument("--root", help="the repository (default: where bazel run started)")
    many = commands.add_parser("plan", help="which releases are newer than the catalog")
    many.add_argument("--out", help="write the list here, as JSON")
    many.add_argument("--root", help="the repository (default: this file's)")
    args = parser.parse_args(argv)

    root = workspace(args.root)
    sources = load_sources(root / SOURCES)

    if args.command == "plan":
        _, catalog = catalog_rules.load(root / CATALOG)
        found = plan(catalog, sources, list_releases, open_pull)
        if args.out:
            Path(args.out).write_text(json.dumps(found) + "\n", encoding="utf-8")
        print(json.dumps(found))
        return OK

    release = (
        FolderRelease(args.release_dir)
        if args.release_dir
        else GhRelease(row_for_or_exit(sources, args.id)["repo"], args.tag)
    )
    now = (
        datetime.strptime(args.now, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)
        if args.now
        else datetime.now(timezone.utc)
    )
    try:
        result = bump(root, sources, args.id, args.tag, release, now)
        status = OK
    except NotReady as why:
        notice(f"{args.id} {args.tag}: skipped, {why}.")
        result, status = {"status": "not-ready", "message": str(why)}, NOT_READY
    except NotListed as why:
        notice(f"{args.id}: skipped, {why}.")
        result, status = {"status": "not-listed", "message": str(why)}, NOT_LISTED
    except Refused as why:
        for reason in why.reasons:
            print(f"NOT OK   {args.id} {args.tag}: {reason}", file=sys.stderr)
        print("Nothing was written.", file=sys.stderr)
        result, status = {"status": "refused", "message": str(why)}, REFUSED
    if result.get("status") == "current":
        print(f"{args.id}: the catalog already lists {args.tag}. Nothing to do.")
    if args.result_out:
        Path(args.result_out).write_text(
            json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
        )
    return status


def row_for_or_exit(sources, tool_id):
    try:
        return row_for(sources, tool_id)
    except Refused as why:
        raise SystemExit(str(why))


if __name__ == "__main__":
    sys.exit(main())
