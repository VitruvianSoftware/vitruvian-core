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

"""Track upstream gods-eye-view and merge its changes into this copy.

apps/web/gods-eye-view is upstream bilawalsidhu/gods-eye-view at one upstream
commit (the base), plus this repository's license headers, plus the local
changes `upstream/local-changes.tsv` lists, each with why. Nothing else may
differ. See upstream/README.md for the process this tool serves.

    bazel run //apps/web/gods-eye-view:track_upstream -- status  # how far behind, and any unlisted change
    bazel run //apps/web/gods-eye-view:track_upstream -- check   # this copy is the base plus the listed changes
    bazel run //apps/web/gods-eye-view:track_upstream -- sync    # merge upstream's latest into this copy
    bazel test //apps/web/gods-eye-view:upstream_test            # the tool, and the list's format

Unlike apps/desktop/vitruvian, which was refactored and ports upstream one
commit at a time, this copy keeps upstream's layout, so `sync` merges the whole
tree at once: for every file upstream changed since the base, a three-way merge
of this copy's file (license header set aside) with the base and the new
upstream version. Files this copy never changed simply take upstream's version.

Upstream rewrites its history now and then. The base records a tree as well as
a commit, so a base that is no longer on upstream's branch is found again by
its tree.
"""

import argparse
import hashlib
import os
import re
import stat
import subprocess
import sys
import tempfile
from dataclasses import dataclass, field
from pathlib import Path

APP_DIR = "apps/web/gods-eye-view"
CHANGES = APP_DIR + "/upstream/local-changes.tsv"
UPSTREAM_URL = "https://github.com/bilawalsidhu/gods-eye-view"
UPSTREAM_BRANCH = "main"
KINDS = ("added", "modified", "deleted")
# Upstream's server side: its /api routes run inside its Vite dev server. The
# production image runs this copy's server.mjs instead, which re-implements them.
SERVER_PATHS = ("server/", "build/")
COLUMNS = ("path", "change", "why")

# The MIT header //tools/license:add writes: an optional opening comment line,
# the copyright line, the permission text down to "SOFTWARE.", an optional
# closing comment line, and one blank line.
HEADER_RE = re.compile(rb"Copyright \(c\) \d{4} VitruvianSoftware")
OPENERS = (b"/**", b"/*", b"<!--")
CLOSERS = (b"*/", b"-->")
HEADER_MAX_LINES = 25


class ToolError(Exception):
    pass


def git(args, cwd=None, git_dir=None, check=True, input=None):
    cmd = ["git"]
    if git_dir is not None:
        cmd += ["--git-dir", str(git_dir)]
    cmd += list(args)
    proc = subprocess.run(cmd, cwd=cwd, input=input, capture_output=True, check=False)
    if check and proc.returncode != 0:
        raise ToolError(
            f"git {' '.join(args)} failed ({proc.returncode}): "
            f"{proc.stderr.decode(errors='replace').strip()}"
        )
    return proc


def out(args, **kw):
    return git(args, **kw).stdout.decode()


# --- License headers -------------------------------------------------------------


def split_header(data):
    """(body, header, line): data without this repository's license header.

    `line` is the line the header started on (after a shebang or doctype), so
    `join_header` can put it back after a merge. A file without the header
    comes back unchanged, with an empty header.
    """
    lines = data.splitlines(keepends=True)
    for k, line in enumerate(lines[:4]):
        if HEADER_RE.search(line):
            break
    else:
        return data, b"", 0
    start = k - 1 if k > 0 and lines[k - 1].strip() in OPENERS else k
    end = k + 1
    while (
        end < min(len(lines), k + HEADER_MAX_LINES) and b"SOFTWARE." not in lines[end]
    ):
        end += 1
    if end >= min(len(lines), k + HEADER_MAX_LINES):
        return data, b"", 0
    end += 1
    if end < len(lines) and lines[end].strip() in CLOSERS:
        end += 1
    if end < len(lines) and lines[end].strip() == b"":
        end += 1
    return b"".join(lines[:start] + lines[end:]), b"".join(lines[start:end]), start


def join_header(body, header, line):
    if not header:
        return body
    lines = body.splitlines(keepends=True)
    return b"".join(lines[:line]) + header + b"".join(lines[line:])


def blob_id(data):
    return hashlib.sha1(b"blob %d\0" % len(data) + data).hexdigest()


def is_binary(data):
    return b"\0" in data[:8000]


# --- The list of local changes ------------------------------------------------------


@dataclass
class Row:
    path: str
    change: str
    why: str
    line: int = 0

    @property
    def is_prefix(self):
        return self.path.endswith("/")

    def covers(self, path):
        return path.startswith(self.path) if self.is_prefix else path == self.path


@dataclass
class Changes:
    path: Path
    base: str
    tree: str
    rows: list = field(default_factory=list)

    @classmethod
    def load(cls, path):
        base = tree = None
        rows = []
        for n, raw in enumerate(Path(path).read_text().splitlines(), 1):
            if raw.startswith("# base\t"):
                fields = raw[2:].split("\t")
                if len(fields) != 4 or fields[2] != "tree":
                    raise ToolError(
                        f"{path}:{n}: base line is `# base<TAB>sha<TAB>tree<TAB>tree`"
                    )
                base, tree = fields[1], fields[3]
                continue
            if not raw.strip() or raw.startswith("#"):
                continue
            fields = raw.split("\t")
            if len(fields) != len(COLUMNS):
                raise ToolError(
                    f"{path}:{n}: expected {len(COLUMNS)} tab-separated columns, got {len(fields)}"
                )
            rows.append(Row(*fields, line=n))
        if base is None:
            raise ToolError(f"{path}: no `# base` line")
        return cls(Path(path), base, tree, rows)

    def errors(self):
        errs = []
        for name, value in (("base", self.base), ("tree", self.tree)):
            if not re.fullmatch(r"[0-9a-f]{40}", value or ""):
                errs.append(f"the base line's {name} is not a full object id")
        seen = {}
        for row in self.rows:
            where = f"line {row.line} ({row.path})"
            if row.path in seen:
                errs.append(f"{where}: duplicate of line {seen[row.path]}")
            seen[row.path] = row.line
            if row.change not in KINDS:
                errs.append(
                    f"{where}: change {row.change!r} is not one of {', '.join(KINDS)}"
                )
            elif row.is_prefix and row.change != "added":
                errs.append(f"{where}: only an `added` row may name a directory")
            if row.path.startswith("/") or ".." in row.path.split("/") or not row.path:
                errs.append(f"{where}: path is not relative to {APP_DIR}")
            if row.why.strip() in ("", "-"):
                errs.append(f"{where}: say why this copy differs")
        return errs

    def row_for(self, path):
        exact = [r for r in self.rows if not r.is_prefix and r.covers(path)]
        if exact:
            return exact[0]
        prefixes = [r for r in self.rows if r.is_prefix and r.covers(path)]
        return max(prefixes, key=lambda r: len(r.path)) if prefixes else None

    def set_base(self, base, tree):
        text = self.path.read_text()
        new = re.sub(
            r"^# base\t.*$",
            f"# base\t{base}\ttree\t{tree}",
            text,
            count=1,
            flags=re.MULTILINE,
        )
        self.path.write_text(new)
        self.base, self.tree = base, tree


# --- Upstream -------------------------------------------------------------------------


class Upstream:
    """A bare clone of upstream, kept in a cache directory."""

    def __init__(self, url, cache_dir, fetch=True):
        self.url = url
        self.dir = Path(cache_dir) / "gods-eye-view.git"
        self.ref = "refs/heads/" + UPSTREAM_BRANCH
        if not fetch:
            if not self.dir.exists():
                raise ToolError(
                    f"no upstream clone at {self.dir}; run without --no-fetch once"
                )
            return
        if not self.dir.exists():
            self.dir.parent.mkdir(parents=True, exist_ok=True)
            # Blobs are fetched when a merge needs them: `check` reads only trees.
            git(
                ["clone", "--quiet", "--bare", "--filter=blob:none", url, str(self.dir)]
            )
        git(["remote", "set-url", "origin", url], git_dir=self.dir)
        git(
            ["fetch", "--quiet", "--force", "origin", f"+{self.ref}:{self.ref}"],
            git_dir=self.dir,
        )

    def run(self, args, **kw):
        return out(args, git_dir=self.dir, **kw)

    def head(self):
        return self.run(["rev-parse", self.ref]).strip()

    def resolve(self, rev):
        return self.run(["rev-parse", "--verify", rev + "^{commit}"]).strip()

    def tree_of(self, commit):
        return self.run(["rev-parse", commit + "^{tree}"]).strip()

    def resolve_base(self, changes):
        """The base on upstream's current history, found by tree if rewritten."""
        reachable = (
            git(
                ["merge-base", "--is-ancestor", changes.base, self.ref],
                git_dir=self.dir,
                check=False,
            ).returncode
            == 0
        )
        if reachable:
            return changes.base, False
        for line in self.run(
            ["log", "--reverse", "--format=%H %T", self.ref]
        ).splitlines():
            commit, tree = line.split()
            if tree == changes.tree:
                return commit, True
        raise ToolError(
            f"base {changes.base[:10]} is not on upstream {UPSTREAM_BRANCH} and no commit there has "
            f"its tree {changes.tree[:10]}; upstream rewrote history past it. Find the matching "
            "commit by hand and set the `# base` line."
        )

    def commits_between(self, base, target):
        """(all commits, the first-parent line): each (sha, date, subject), oldest first.

        Upstream lands most changes as merged pull requests, so the first-parent
        line reads as the list of what landed.
        """
        fmt = "--format=%H%x00%as%x00%s"
        rng = f"{base}..{target}"
        every = self.run(["rev-list", "--count", rng]).strip()
        line = [
            tuple(raw.split("\x00", 2))
            for raw in self.run(
                ["log", "--reverse", "--first-parent", fmt, rng]
            ).splitlines()
        ]
        return int(every), line

    def entries(self, commit):
        """path -> (mode, sha) for every file in commit."""
        result = {}
        raw = self.run(["ls-tree", "-r", "-z", "--full-tree", commit])
        for item in raw.split("\0"):
            if not item:
                continue
            meta, path = item.split("\t", 1)
            mode, kind, sha = meta.split()
            if kind == "blob":
                result[path] = (mode, sha)
        return result

    def changes(self, base, target):
        """(status, path, old (mode, sha), new (mode, sha)) for each file changed."""
        raw = self.run(["diff-tree", "-r", "-z", "--no-renames", base, target])
        parts = raw.split("\0")
        result = []
        i = 0
        while i < len(parts) - 1:
            meta = parts[i]
            if not meta.startswith(":"):
                i += 1
                continue
            old_mode, new_mode, old_sha, new_sha, status = meta[1:].split()
            path = parts[i + 1]
            result.append((status[0], path, (old_mode, old_sha), (new_mode, new_sha)))
            i += 2
        return result

    def blob(self, sha):
        return git(["cat-file", "blob", sha], git_dir=self.dir).stdout


# --- This copy ------------------------------------------------------------------------------


@dataclass
class Local:
    mode: str
    sha: str  # blob id with the license header set aside
    data: bytes  # the file as it is, header included


def app_dir(root):
    return Path(root) / APP_DIR


def local_files(root):
    """path -> Local for every file of this copy git tracks or would track."""
    raw = out(
        ["ls-files", "-z", "--cached", "--others", "--exclude-standard", "--", APP_DIR],
        cwd=root,
    )
    result = {}
    prefix = APP_DIR + "/"
    for rel in sorted(set(raw.split("\0"))):
        if not rel.startswith(prefix):
            continue
        full = Path(root) / rel
        if full.is_symlink():
            data = os.readlink(full).encode()
            result[rel[len(prefix) :]] = Local("120000", blob_id(data), data)
            continue
        if not full.is_file():
            continue  # deleted from the working tree but still in the index
        data = full.read_bytes()
        mode = "100755" if full.stat().st_mode & stat.S_IXUSR else "100644"
        body = data if is_binary(data) else split_header(data)[0]
        result[rel[len(prefix) :]] = Local(mode, blob_id(body), data)
    return result


def differences(local, base_entries):
    """path -> kind for every file that is not as the base has it."""
    result = {}
    for path in sorted(set(local) | set(base_entries)):
        mine, theirs = local.get(path), base_entries.get(path)
        if mine is None:
            result[path] = "deleted"
        elif theirs is None:
            result[path] = "added"
        elif (mine.mode, mine.sha) != theirs:
            result[path] = "modified"
    return result


def check_drift(changes, local, base_entries):
    """What is wrong with the list, given how this copy differs from the base."""
    found = differences(local, base_entries)
    problems = []
    for path, kind in found.items():
        row = changes.row_for(path)
        if row is None:
            problems.append(
                f"{path}: {kind} here, but local-changes.tsv does not list it. "
                "List it with why, or make it match upstream."
            )
        elif row.change != kind:
            problems.append(
                f"{path}: listed as {row.change} on line {row.line}, but is {kind}"
            )
    for row in changes.rows:
        if not any(row.covers(p) for p in found):
            problems.append(
                f"line {row.line} ({row.path}): listed as {row.change}, but matches upstream; remove the row"
            )
    return problems


# --- Sync -------------------------------------------------------------------------------------


@dataclass
class SyncReport:
    base: str
    target: str
    taken: list = field(default_factory=list)  # upstream's version, no local change
    merged: list = field(
        default_factory=list
    )  # (path, why): merged into a local change
    added: list = field(default_factory=list)
    deleted: list = field(default_factory=list)
    dropped: list = field(
        default_factory=list
    )  # (path, why): upstream changed what this copy drops
    conflicts: list = field(default_factory=list)  # (path, what to do)
    new_top_level: list = field(default_factory=list)
    ignored: list = field(default_factory=list)
    server: list = field(
        default_factory=list
    )  # upstream's server code, which production does not run
    package_json: bool = False
    commits: int = 0
    line: list = field(default_factory=list)


def merge3(ours, base, theirs, labels):
    """(merged, conflicts) from git merge-file."""
    with tempfile.TemporaryDirectory() as tmp:
        paths = []
        for name, data in (("ours", ours), ("base", base), ("theirs", theirs)):
            p = Path(tmp) / name
            p.write_bytes(data)
            paths.append(str(p))
        proc = git(
            [
                "merge-file",
                "-p",
                "-L",
                labels[0],
                "-L",
                labels[1],
                "-L",
                labels[2],
                *paths,
            ],
            check=False,
        )
        if proc.returncode < 0 or proc.returncode > 127:
            raise ToolError(
                f"git merge-file failed: {proc.stderr.decode(errors='replace')}"
            )
        return proc.stdout, proc.returncode


def write_file(path, data, mode):
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.is_symlink() or mode == "120000":
        if path.exists() or path.is_symlink():
            path.unlink()
        if mode == "120000":
            os.symlink(data.decode(), path)
            return
    path.write_bytes(data)
    current = path.stat().st_mode
    if mode == "100755":
        path.chmod(current | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
    else:
        path.chmod(current & ~(stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH))


def sync(root, changes, upstream, target, dry_run=False):
    base, _ = upstream.resolve_base(changes)
    target = upstream.resolve(target)
    report = SyncReport(base=base, target=target)
    report.commits, report.line = upstream.commits_between(base, target)
    if base == target:
        return report
    local = local_files(root)
    labels = ("this copy", f"upstream {base[:10]}", f"upstream {target[:10]}")
    app = app_dir(root)
    written = []
    for status, path, old, new in upstream.changes(base, target):
        row = changes.row_for(path)
        why = row.why if row else ""
        mine = local.get(path)
        dest = app / path
        if path == "package.json":
            report.package_json = True
        if path.startswith(SERVER_PATHS):
            report.server.append(path)
        if status == "A":
            if mine is None:
                if not dry_run:
                    write_file(dest, upstream.blob(new[1]), new[0])
                    written.append(path)
                report.added.append(path)
            elif (mine.mode, mine.sha) != new:
                report.conflicts.append(
                    (
                        path,
                        f"upstream added it, and this copy has its own ({why or 'unlisted'}): keep one",
                    )
                )
            continue
        if status == "D":
            if mine is None:
                continue
            if (mine.mode, mine.sha) == old:
                if not dry_run:
                    dest.unlink()
                report.deleted.append(path)
            else:
                report.conflicts.append(
                    (
                        path,
                        f"upstream deleted it, and this copy changes it ({why or 'unlisted'}): "
                        "drop the change or keep the file as `added`",
                    )
                )
            continue
        # Modified, or its type changed.
        if mine is None:
            if row is not None and row.change == "deleted":
                report.dropped.append((path, why))
            else:
                report.conflicts.append(
                    (path, "upstream changed it, and it is missing here")
                )
            continue
        mode = new[0] if mine.mode == old[0] else mine.mode
        if mine.sha == old[1]:
            if not dry_run:
                body, header, line = split_header(mine.data)
                data = upstream.blob(new[1])
                write_file(
                    dest,
                    data if is_binary(data) else join_header(data, header, line),
                    mode,
                )
                written.append(path)
            report.taken.append(path)
            continue
        theirs = upstream.blob(new[1])
        older = upstream.blob(old[1])
        if is_binary(mine.data) or is_binary(theirs) or is_binary(older):
            report.conflicts.append(
                (path, "binary, changed both here and upstream: pick one by hand")
            )
            continue
        body, header, line = split_header(mine.data)
        merged, conflicts = merge3(body, older, theirs, labels)
        if not dry_run:
            write_file(dest, join_header(merged, header, line), mode)
            written.append(path)
        if conflicts:
            report.conflicts.append(
                (path, f"{conflicts} conflict(s) marked in the file")
            )
        else:
            report.merged.append((path, why or "unlisted"))
    old_top = {p.split("/", 1)[0] for p in upstream.entries(base)}
    report.new_top_level = sorted(
        {p.split("/", 1)[0] for p in upstream.entries(target)} - old_top
    )
    if written:
        proc = git(
            ["check-ignore", "--stdin", "-z"],
            cwd=root,
            input=b"\0".join(f"{APP_DIR}/{p}".encode() for p in written) + b"\0",
            check=False,
        )
        report.ignored = [p for p in proc.stdout.decode().split("\0") if p]
    if not dry_run:
        changes.set_base(target, upstream.tree_of(target))
    return report


def link(sha):
    return f"[`{sha[:10]}`]({UPSTREAM_URL}/commit/{sha})"


def report_markdown(r, dry_run=False):
    lines = [
        f"## Upstream {link(r.base)} → {link(r.target)}"
        + (" (dry run)" if dry_run else ""),
        "",
        (
            f"{r.commits} upstream commit(s); {len(r.line)} on the first-parent line, listed below. "
            f"{len(r.taken)} file(s) took upstream's version, {len(r.added)} added, "
            f"{len(r.deleted)} deleted, {len(r.merged)} merged into a local change, "
            f"{len(r.conflicts)} conflict(s)."
        ),
        "",
    ]

    def section(title, items):
        if items:
            lines.extend([f"### {title}", ""] + [f"- {i}" for i in items] + [""])

    section(
        "Conflicts: resolve each before committing",
        [f"`{p}`: {what}" for p, what in r.conflicts],
    )
    section(
        "Merged into a file this copy changes: check the change still does its job",
        [f"`{p}`: {why}" for p, why in r.merged],
    )
    section(
        "Upstream changed a file this copy drops",
        [f"`{p}`: {why}" for p, why in r.dropped],
    )
    follow = []
    if r.added:
        follow.append(
            f"{len(r.added)} new file(s): run `bazel run //tools/license:add` to give them the header"
        )
    if r.package_json:
        follow.append(
            "`package.json` changed: run `pnpm install` at the repository root to update "
            "`pnpm-lock.yaml`, and keep one version of each dependency (One Version Rule)"
        )
    if r.new_top_level:
        follow.append(
            "new top-level entries "
            + ", ".join(f"`{p}`" for p in r.new_top_level)
            + ": BUILD.bazel lists directories by name in its globs"
        )
    if r.server:
        follow.append(
            f"{len(r.server)} file(s) of upstream's server changed (under "
            + " and ".join(f"`{p}`" for p in SERVER_PATHS)
            + "): production runs `server.mjs`, not upstream's dev server, so port any "
            "new or changed `/api` route there: "
            + ", ".join(f"`{p}`" for p in r.server)
        )
    if r.ignored:
        follow.append(
            "written but ignored by git here, so not committed unless forced: "
            + ", ".join(f"`{p}`" for p in r.ignored)
        )
    section("Follow-ups", follow)
    if r.line:
        lines += ["### What landed upstream", ""]
        lines += [f"- {link(sha)} {date} {subject}" for sha, date, subject in r.line]
        lines.append("")
    return "\n".join(lines)


# --- Commands ---------------------------------------------------------------------------------


def repo_root(arg):
    if arg:
        return Path(arg)
    env = os.environ.get("BUILD_WORKSPACE_DIRECTORY")
    if env:
        return Path(env)
    return Path(out(["rev-parse", "--show-toplevel"]).strip())


def cache_dir(arg):
    if arg:
        return Path(arg)
    base = os.environ.get("XDG_CACHE_HOME") or os.path.join(
        os.path.expanduser("~"), ".cache"
    )
    return Path(base) / "gods-eye-view-upstream"


def load_changes(args):
    changes = Changes.load(args.changes_path)
    errs = changes.errors()
    if errs:
        raise ToolError("; ".join(f"{args.changes_path}: {e}" for e in errs))
    return changes


def cmd_check_changes(args):
    changes = Changes.load(args.changes_path)
    errs = changes.errors()
    for e in errs:
        print(f"{args.changes_path}: {e}", file=sys.stderr)
    if errs:
        return 1
    print(f"local-changes ok: base {changes.base[:10]}, {len(changes.rows)} row(s)")
    return 0


@dataclass
class Status:
    head: str
    base: str
    reanchored: bool
    commits: int
    line: list
    drift: list


def status(args):
    changes = load_changes(args)
    upstream = Upstream(args.upstream_url, args.cache, fetch=not args.no_fetch)
    base, reanchored = upstream.resolve_base(changes)
    head = upstream.head()
    commits, line = upstream.commits_between(base, head)
    drift = check_drift(changes, local_files(args.root), upstream.entries(base))
    return Status(head, base, reanchored, commits, line, drift)


def cmd_check(args):
    s = status(args)
    for p in s.drift:
        print(p, file=sys.stderr)
    if s.drift:
        print(
            f'{len(s.drift)} problem(s); see upstream/README.md, "Local changes"',
            file=sys.stderr,
        )
        return 1
    print(
        f"ok: this copy is upstream {s.base[:10]} plus the changes local-changes.tsv lists"
    )
    return 0


def cmd_status(args):
    s = status(args)
    if args.markdown:
        print(status_markdown(s, args.previous_body))
    else:
        print(
            f"upstream {UPSTREAM_BRANCH} at {s.head[:10]}; base {s.base[:10]}"
            + (
                " (re-anchored by tree after an upstream history rewrite)"
                if s.reanchored
                else ""
            )
        )
        print(f"{s.commits} commit(s) behind, {len(s.line)} on the first-parent line")
        for sha, date, subject in s.line:
            print(f"  {sha[:10]} {date} {subject}")
        if s.drift:
            print(f"{len(s.drift)} problem(s) with local-changes.tsv:")
            for p in s.drift:
                print(f"  {p}")
    if args.check and (s.commits or s.drift):
        return 1
    return 0


def status_markdown(s, previous_body=None):
    seen = set()
    if previous_body:
        m = re.search(
            r"<!-- behind-shas: ([0-9a-f ]*) -->", Path(previous_body).read_text()
        )
        if m:
            seen = set(m.group(1).split())
    new = [c for c in s.line if c[0][:12] not in seen]
    lines = [
        f"<!-- upstream-watch behind: {s.commits} drift: {len(s.drift)} new: {len(new)} -->",
        f"<!-- behind-shas: {' '.join(c[0][:12] for c in s.line)} -->",
        (
            f"Upstream [gods-eye-view]({UPSTREAM_URL}) `{UPSTREAM_BRANCH}` is at {link(s.head)}. "
            f"`{APP_DIR}` matches {link(s.base)}, **{s.commits}** commit(s) behind."
        ),
        "",
        (
            "Sync: follow `apps/web/gods-eye-view/upstream/SYNC.md`; the merge itself is "
            "`bazel run //apps/web/gods-eye-view:track_upstream -- sync`."
        ),
        "",
    ]
    if s.reanchored:
        lines += [
            f"Upstream rewrote its history: the base is now {link(s.base)} (same tree).",
            "",
        ]
    if s.drift:
        lines += [
            "### This copy differs from upstream in ways the list does not say",
            "",
        ]
        lines += [f"- {p}" for p in s.drift] + [""]
    if s.line:
        lines += [f"### Landed upstream since the base ({len(s.line)})", ""]
        lines += [
            f"- {link(sha)} {date} {subject}" for sha, date, subject in s.line[:200]
        ]
        if len(s.line) > 200:
            lines.append(f"- … and {len(s.line) - 200} more")
    return "\n".join(lines)


def cmd_sync(args):
    changes = load_changes(args)
    if not args.allow_dirty and not args.dry_run:
        dirty = out(["status", "--porcelain", "--", APP_DIR], cwd=args.root)
        if dirty.strip():
            raise ToolError(
                f"{APP_DIR} has uncommitted changes; commit them first, or pass --allow-dirty"
            )
    upstream = Upstream(args.upstream_url, args.cache, fetch=not args.no_fetch)
    target = args.to or upstream.ref
    report = sync(args.root, changes, upstream, target, dry_run=args.dry_run)
    text = report_markdown(report, dry_run=args.dry_run)
    if args.report:
        Path(args.report).write_text(text + "\n")
    print(text)
    return 1 if report.conflicts else 0


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument(
        "--root",
        help="monorepo checkout (default: the workspace `bazel run` was started in)",
    )
    parser.add_argument(
        "--changes",
        dest="changes_path",
        help=f"the list of local changes (default: <root>/{CHANGES})",
    )
    parser.add_argument("--upstream-url", default=UPSTREAM_URL)
    parser.add_argument(
        "--cache",
        help="where to keep the upstream clone (default: ~/.cache/gods-eye-view-upstream)",
    )
    parser.add_argument(
        "--no-fetch", action="store_true", help="use the cached upstream clone as it is"
    )
    sub = parser.add_subparsers(dest="command", required=True)

    sub.add_parser(
        "check-changes", help="validate local-changes.tsv (offline)"
    ).set_defaults(func=cmd_check_changes)
    sub.add_parser(
        "check", help="exit 1 unless this copy is the base plus the listed changes"
    ).set_defaults(func=cmd_check)
    p = sub.add_parser(
        "status", help="how far behind upstream, and any unlisted change"
    )
    p.add_argument(
        "--check", action="store_true", help="exit 1 if behind, or if the list is wrong"
    )
    p.add_argument(
        "--markdown", action="store_true", help="print the tracking issue's body"
    )
    p.add_argument(
        "--previous-body",
        help="the issue's current body, to count commits it did not list",
    )
    p.set_defaults(func=cmd_status)
    p = sub.add_parser("sync", help="merge upstream into this copy and move the base")
    p.add_argument(
        "--to", help=f"upstream commit to sync to (default: {UPSTREAM_BRANCH})"
    )
    p.add_argument(
        "--dry-run",
        action="store_true",
        help="report what would happen, change nothing",
    )
    p.add_argument("--report", help="also write the report (markdown) to this file")
    p.add_argument(
        "--allow-dirty",
        action="store_true",
        help=f"sync into uncommitted changes in {APP_DIR}",
    )
    p.set_defaults(func=cmd_sync)

    args = parser.parse_args(argv)
    args.root = repo_root(args.root)
    args.changes_path = (
        Path(args.changes_path) if args.changes_path else args.root / CHANGES
    )
    args.cache = cache_dir(args.cache)
    try:
        return args.func(args)
    except ToolError as e:
        print(f"upstream: {e}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
