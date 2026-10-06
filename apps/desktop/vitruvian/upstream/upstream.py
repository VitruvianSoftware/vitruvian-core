#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 VitruvianSoftware

"""Track upstream vorssaint-utils and port its changes into this fork.

The ledger (`upstream/ledger.tsv`) lists every upstream commit since the
import, oldest first, with what this fork did with it: `pending`, `ported`
(ref = the PR that ported it) or `skipped` (ref = why). See UPSTREAM.md,
"Tracking and porting upstream", for the process this tool serves.

    bazel run //apps/desktop/vitruvian:track_upstream -- status         # what's new
    bazel run //apps/desktop/vitruvian:track_upstream -- triage         # add it to the ledger
    bazel run //apps/desktop/vitruvian:track_upstream -- show <sha>     # where its files live here
    bazel run //apps/desktop/vitruvian:track_upstream -- port <sha>...  # apply it to this tree
    bazel test //apps/desktop/vitruvian:upstream_test                   # the tool, and the ledger's format

Upstream rewrites its history now and then (the import commit aa6ddcb9 was
replaced by e80abdb1, with an identical tree, days after the import). So the
ledger's base records a tree as well as a commit, and every row records its
`git patch-id`: when a commit id disappears, the base is found again by its
tree and rows by their patch ids.

`port` is a mechanical first pass, not a finished port. For each file the
upstream commit changed, it finds where that file lives in this tree (the
refactor renamed and split most of them), rewrites upstream's brand names to
this fork's, and three-way merges the upstream change into this fork's copy.
What it cannot place, binary files, and lines that still name upstream (its
domains, repository and services are never rewritten, because what replaces
them is a decision) are reported for a person to finish.
"""

import argparse
import collections
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

UPSTREAM_URL = "https://github.com/vorssaint/vorssaint-utils"
UPSTREAM_BRANCH = "main"
APP_DIR = "apps/desktop/vitruvian"
LEDGER = APP_DIR + "/upstream/ledger.tsv"
# The monorepo commit that imported upstream byte for byte (#2639). Path
# mapping diffs this against HEAD to follow the renames since.
IMPORT_COMMIT = "05ee8be1f69849d0f219d44f32de932bba1a3454"

# Upstream paths the import left out (UPSTREAM.md, "What the import left out"),
# plus upstream's own changelog: release-please writes this fork's entries, and
# upstream's release notes describe releases this fork never shipped. A commit
# that touches nothing else is skipped at triage.
UPSTREAM_ONLY = (
    ".github/",
    "README.md",
    "CONTRIBUTING.md",
    "SECURITY.md",
    "SUPPORT.md",
    "CHANGELOG.md",
    "docs/AI-CONTRIBUTIONS.md",
    "docs/assets/",
    "docs/demo.gif",
    "ReleaseAssets/",
    "Resources/Brand/",
)

STATUSES = ("pending", "ported", "skipped")
COLUMNS = ("sha", "patch_id", "date", "status", "ref", "subject")
LEDGER_PREAMBLE = """\
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 VitruvianSoftware
#
# Upstream vorssaint-utils commits since the import, oldest first, and what this
# fork did with each. `bazel run //apps/desktop/vitruvian:track_upstream -- triage`
# adds new commits; set status and ref by hand when you port or skip one.
#   status: pending | ported | skipped
#   ref:    ported -> the PR that ported it (#1234); skipped -> why; pending -> -
# See UPSTREAM.md, "Tracking and porting upstream".
"""

# Lines that are legal notices: upstream's copyright stays as it is (GPL-3.0 §5).
NOTICE_RE = re.compile(r"SPDX-License-Identifier|Copyright \(C\)|Copyright ©")
# Tokens that name upstream's repository, domains or servers. They are left as
# they are and reported, because what replaces each one is a decision (most
# point at reserved `.invalid` hosts or at this fork's repository).
PROTECTED_RE = re.compile(
    r"[\w.:/-]*(?:"
    r"vorssaint-utils"
    r"|github(?:usercontent)?\.com/vorssaint"
    r"|vorssaint\.(?:com|net|org|io|dev)\b"
    r")[\w./-]*",
    re.IGNORECASE,
)
BRAND_SUBSTITUTIONS = (
    ("com.vorssaint.utils", "com.vitruviansoftware.vitruvian"),
    ("Vorssaint", "Vitruvian"),
    ("vorssaint", "vitruvian"),
    ("VORSSAINT", "VITRUVIAN"),
)
BRAND_RE = re.compile("vorssaint", re.IGNORECASE)
# The module split made upstream's internal declarations `package` (REFACTOR.md,
# step 3). Merging with that modifier stripped from all three sides, then
# putting it back on the lines this fork had it on, keeps it from turning every
# changed declaration into a conflict.
PACKAGE_RE = re.compile(
    r"^([ \t]*(?:@[\w.]+(?:\([^)\n]*\))?[ \t]+)*)package[ \t]+(?=\S)", re.MULTILINE
)
ATTRIBUTES_RE = re.compile(r"[ \t]*(?:@[\w.]+(?:\([^)\n]*\))?[ \t]+)*")
# A declaration's identity, so a line upstream changed still gets this fork's
# `package` back: (indent, kind, name).
DECL_RE = re.compile(
    r"([ \t]*)(?:@[\w.]+(?:\([^)\n]*\))?[ \t]+)*"
    r"(?:(?:static|class|final|override|private\(set\)|fileprivate\(set\)|mutating|nonmutating"
    r"|nonisolated(?:\(unsafe\))?|convenience|required|lazy|weak|unowned|indirect|dynamic)[ \t]+)*"
    r"(func|var|let|struct|class|enum|protocol|typealias|init|subscript|extension|actor)\b[ \t]*([A-Za-z_`][\w`]*)?"
)


class ToolError(Exception):
    pass


def git(args, cwd=None, git_dir=None, check=True, input=None):
    cmd = ["git"]
    if git_dir is not None:
        cmd += ["--git-dir", str(git_dir)]
    cmd += list(args)
    proc = subprocess.run(
        cmd,
        cwd=cwd,
        input=input,
        capture_output=True,
        check=False,
    )
    if check and proc.returncode != 0:
        raise ToolError(
            f"git {' '.join(args)} failed ({proc.returncode}): "
            f"{proc.stderr.decode(errors='replace').strip()}"
        )
    return proc


def out(args, **kw):
    return git(args, **kw).stdout.decode()


# --- Brand ----------------------------------------------------------------------


def to_fork_line(line):
    """Upstream's names to this fork's, leaving notices and upstream URLs."""
    if NOTICE_RE.search(line):
        return line
    parts = []
    last = 0
    for m in PROTECTED_RE.finditer(line):
        parts.append(_substitute(line[last : m.start()]))
        parts.append(m.group(0))
        last = m.end()
    parts.append(_substitute(line[last:]))
    return "".join(parts)


def _substitute(text):
    for old, new in BRAND_SUBSTITUTIONS:
        text = text.replace(old, new)
    return text


def to_fork(text):
    return "".join(to_fork_line(line) for line in text.splitlines(keepends=True))


def to_fork_bytes(data):
    return to_fork((data or b"").decode("utf-8", "surrogateescape")).encode(
        "utf-8", "surrogateescape"
    )


def brand_review(text):
    """Lines that still name upstream, other than legal notices."""
    return [
        (n, line.rstrip("\n"))
        for n, line in enumerate(text.splitlines(keepends=True), 1)
        if BRAND_RE.search(line) and not NOTICE_RE.search(line)
    ]


# --- Ledger ---------------------------------------------------------------------


class Ledger:
    def __init__(self, base, tree, rows):
        self.base = base
        self.tree = tree
        self.rows = rows  # list of dicts keyed by COLUMNS

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
            rows.append(dict(zip(COLUMNS, fields), line=n))
        if base is None:
            raise ToolError(f"{path}: no `# base` line")
        return cls(base, tree, rows)

    def errors(self):
        errs = []
        seen = {}
        for row in self.rows:
            where = f"line {row.get('line', 'new')} ({row['sha'][:10]})"
            if not re.fullmatch(r"[0-9a-f]{40}", row["sha"]):
                errs.append(f"{where}: sha is not a full commit id")
            if row["sha"] in seen:
                errs.append(f"{where}: duplicate of line {seen[row['sha']]}")
            seen[row["sha"]] = row.get("line", "new")
            if row["status"] not in STATUSES:
                errs.append(
                    f"{where}: status {row['status']!r} is not one of {', '.join(STATUSES)}"
                )
            elif row["status"] == "ported" and not re.fullmatch(
                r"#\d+(,#\d+)*", row["ref"]
            ):
                errs.append(
                    f"{where}: a ported commit's ref is the PR that ported it, like #1234"
                )
            elif row["status"] == "skipped" and row["ref"].strip() in ("", "-"):
                errs.append(f"{where}: a skipped commit's ref says why")
        return errs

    def dump(self):
        lines = [
            LEDGER_PREAMBLE,
            f"# base\t{self.base}\ttree\t{self.tree}\n",
            "# " + "\t".join(COLUMNS) + "\n",
        ]
        for row in self.rows:
            lines.append("\t".join(_clean(row[c]) for c in COLUMNS) + "\n")
        return "".join(lines)


def _clean(value):
    return value.replace("\t", " ").replace("\n", " ")


# --- Upstream -------------------------------------------------------------------


class Upstream:
    """A bare clone of upstream, kept in a cache directory."""

    def __init__(self, url, cache_dir, fetch=True):
        self.url = url
        self.dir = Path(cache_dir) / "vorssaint-utils.git"
        self.ref = "refs/heads/" + UPSTREAM_BRANCH
        if not fetch:
            if not self.dir.exists():
                raise ToolError(
                    f"no upstream clone at {self.dir}; run without --no-fetch once"
                )
            return
        if not self.dir.exists():
            self.dir.parent.mkdir(parents=True, exist_ok=True)
            # Blobs over 512 KiB (release videos, artwork) are fetched only if a
            # diff needs them.
            git(
                [
                    "clone",
                    "--quiet",
                    "--bare",
                    "--filter=blob:limit=512k",
                    url,
                    str(self.dir),
                ]
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

    def tree_of(self, commit):
        return self.run(["rev-parse", commit + "^{tree}"]).strip()

    def resolve_base(self, ledger):
        """The ledger's base on upstream's current history, found by tree if rewritten."""
        reachable = (
            git(
                ["merge-base", "--is-ancestor", ledger.base, self.ref],
                git_dir=self.dir,
                check=False,
            ).returncode
            == 0
        )
        if reachable:
            return ledger.base, False
        for line in self.run(
            ["log", "--reverse", "--format=%H %T", self.ref]
        ).splitlines():
            commit, tree = line.split()
            if tree == ledger.tree:
                return commit, True
        raise ToolError(
            f"base {ledger.base[:10]} is not on upstream {UPSTREAM_BRANCH} and no commit there has its "
            f"tree {ledger.tree[:10]}; upstream rewrote history past it. Find the matching commit by hand "
            "and set the `# base` line."
        )

    def commits_since(self, base):
        """Non-merge commits after base, oldest first: (sha, date, subject)."""
        fmt = "%H%x00%as%x00%s"
        result = []
        for line in self.run(
            [
                "log",
                "--no-merges",
                "--reverse",
                "--topo-order",
                f"--format={fmt}",
                f"{base}..{self.ref}",
            ]
        ).splitlines():
            sha, date, subject = line.split("\x00", 2)
            result.append((sha, date, subject))
        return result

    def patch_ids(self, base):
        diff = git(
            ["log", "--no-merges", "--format=%H", "-p", f"{base}..{self.ref}"],
            git_dir=self.dir,
        ).stdout
        ids = {}
        for line in (
            git(["patch-id", "--stable"], git_dir=self.dir, input=diff)
            .stdout.decode()
            .splitlines()
        ):
            patch_id, sha = line.split()
            ids[sha] = patch_id
        return ids

    def paths(self, commit):
        return [
            p
            for p in self.run(
                [
                    "diff-tree",
                    "--no-commit-id",
                    "--name-only",
                    "-r",
                    "-z",
                    "--root",
                    commit,
                ]
            ).split("\0")
            if p
        ]

    def changes(self, commit):
        """(status, old_path, new_path) for each file the commit changed."""
        raw = self.run(
            [
                "diff-tree",
                "--no-commit-id",
                "-r",
                "-M",
                "-z",
                "--root",
                "--name-status",
                commit,
            ]
        ).split("\0")
        raw = [x for x in raw if x != ""]
        changes = []
        i = 0
        while i < len(raw):
            status = raw[i]
            if status[0] in "RC":
                changes.append((status[0], raw[i + 1], raw[i + 2]))
                i += 3
            else:
                changes.append((status[0], raw[i + 1], raw[i + 1]))
                i += 2
        return changes

    def blob(self, commit, path):
        proc = git(
            ["cat-file", "-p", f"{commit}:{path}"], git_dir=self.dir, check=False
        )
        return proc.stdout if proc.returncode == 0 else None

    def is_binary(self, commit, path):
        stat = self.run(
            [
                "diff-tree",
                "--no-commit-id",
                "-r",
                "--numstat",
                "--root",
                commit,
                "--",
                path,
            ]
        )
        return stat.startswith("-\t-\t")


def upstream_only(path):
    return any(
        path == p or (p.endswith("/") and path.startswith(p)) for p in UPSTREAM_ONLY
    )


class Triage:
    """Upstream's commits since the base, matched against the ledger."""

    def __init__(self, upstream, ledger):
        self.ledger = ledger
        self.base, self.reanchored = upstream.resolve_base(ledger)
        self.head = upstream.head()
        commits = upstream.commits_since(self.base)
        ids = upstream.patch_ids(self.base)
        by_sha = {r["sha"]: r for r in ledger.rows}
        by_patch = {r["patch_id"]: r for r in ledger.rows if r["patch_id"] != "-"}
        self.untriaged = []
        self.rekeyed = []  # (row, new_sha)
        live = set()
        for sha, date, subject in commits:
            patch_id = ids.get(sha, "-")
            row = by_sha.get(sha)
            if row is None and patch_id != "-":
                row = by_patch.get(patch_id)
                if row is not None:
                    self.rekeyed.append((row, sha))
            if row is not None:
                live.add(id(row))
                continue
            paths = upstream.paths(sha)
            auto_skip = bool(paths) and all(upstream_only(p) for p in paths)
            self.untriaged.append(
                dict(
                    sha=sha,
                    patch_id=patch_id,
                    date=date,
                    subject=subject,
                    auto_skip=auto_skip,
                )
            )
        self.pending = [r for r in ledger.rows if r["status"] == "pending"]
        # Rows no longer on upstream at all (dropped by a rewrite, not re-keyable).
        self.orphaned = [r for r in ledger.rows if id(r) not in live]

    def apply(self):
        """Fold the findings into the ledger: re-key, re-anchor, append."""
        for row, sha in self.rekeyed:
            row["sha"] = sha
        if self.reanchored:
            self.ledger.base = self.base
        for c in self.untriaged:
            status, ref = (
                ("skipped", "touches only upstream-only paths")
                if c["auto_skip"]
                else ("pending", "-")
            )
            self.ledger.rows.append(
                dict(
                    sha=c["sha"],
                    patch_id=c["patch_id"],
                    date=c["date"],
                    status=status,
                    ref=ref,
                    subject=c["subject"],
                )
            )


# --- Path mapping ---------------------------------------------------------------


class PathMap:
    """Where an upstream path lives in this tree now.

    Upstream path p was `APP_DIR/p` at the import. Renames since are read from
    git (similarity >= 50%). A file the refactor rewrote past that, or split,
    shows up as removed; a file with the same name elsewhere is offered as a
    guess. New upstream files go where most of their upstream siblings went.
    """

    def __init__(self, root, import_commit=IMPORT_COMMIT):
        self.root = Path(root)
        prefix = APP_DIR + "/"
        self.renamed = {}
        self.deleted = set()
        raw = out(
            [
                "diff",
                "-M50%",
                "--name-status",
                "-z",
                import_commit,
                "HEAD",
                "--",
                APP_DIR,
            ],
            cwd=root,
        ).split("\0")
        raw = [x for x in raw if x != ""]
        i = 0
        while i < len(raw):
            status = raw[i]
            if status[0] == "R":
                self.renamed[raw[i + 1][len(prefix) :]] = raw[i + 2][len(prefix) :]
                i += 3
            else:
                if status[0] == "D":
                    self.deleted.add(raw[i + 1][len(prefix) :])
                i += 2
        self.at_import = {
            p[len(prefix) :]
            for p in out(
                ["ls-tree", "-r", "--name-only", import_commit, "--", APP_DIR], cwd=root
            ).splitlines()
        }
        self.current = {
            p[len(prefix) :]
            for p in out(["ls-files", "--", APP_DIR], cwd=root).splitlines()
        }
        self.by_name = collections.defaultdict(list)
        for p in self.current:
            self.by_name[os.path.basename(p)].append(p)
        moves = collections.defaultdict(collections.Counter)
        for old, new in self.renamed.items():
            moves[os.path.dirname(old)][os.path.dirname(new)] += 1
        self.dir_moves = {d: c.most_common(1)[0][0] for d, c in moves.items()}

    def map(self, upath):
        """(path relative to APP_DIR or None, how it was found)."""
        if upath in self.renamed:
            return self.renamed[upath], "renamed"
        if upath in self.at_import and upath in self.current:
            return upath, "same path"
        if upath in self.at_import or upath in self.deleted:
            matches = self.by_name.get(os.path.basename(upath), [])
            if len(matches) == 1:
                return matches[0], "guess: same file name"
            return None, "removed or split by the refactor"
        return self._new_path(upath), "new upstream file, placed beside its siblings"

    def _new_path(self, upath):
        d = os.path.dirname(upath)
        tail = [to_fork_line(os.path.basename(upath))]
        while True:
            if d in self.dir_moves:
                return os.path.join(self.dir_moves[d], *tail)
            if d == "" or any(p.startswith(d + "/") for p in self.current):
                return os.path.join(d, *tail)
            tail.insert(0, to_fork_line(os.path.basename(d)))
            d = os.path.dirname(d)


# --- Port -----------------------------------------------------------------------


def strip_package(data):
    return PACKAGE_RE.sub(r"\1", data.decode("utf-8", "surrogateescape")).encode(
        "utf-8", "surrogateescape"
    )


def merge3(ours, base, theirs, labels):
    """Three-way merge, blind to the `package` modifiers this fork added."""
    merged, conflicts = _merge_file(
        strip_package(ours), strip_package(base), strip_package(theirs), labels
    )
    return restore_package(merged, ours), conflicts


def _decl_key(line):
    m = DECL_RE.match(line)
    return (m.group(1), m.group(2), m.group(3)) if m else None


ACCESS_RE = re.compile(r"\b(?:private|fileprivate|internal|public|open|package)\b")


def _indent(line):
    return len(line) - len(line.lstrip(" \t"))


def _in_protocol(lines, i):
    """Whether line i sits directly in a protocol body (no modifiers there)."""
    depth = _indent(lines[i])
    for j in range(i - 1, -1, -1):
        if lines[j].strip() and _indent(lines[j]) < depth:
            key = _decl_key(lines[j])
            return bool(key) and key[1] == "protocol"
    return False


def restore_package(merged, ours):
    """Put back `package` on the lines, and declarations, that had it in ours,
    and give a new declaration `package` where this fork's declarations of that
    kind at that depth are `package` (what other modules use must be)."""
    exact = {}
    by_decl = collections.defaultdict(set)
    by_level = collections.defaultdict(collections.Counter)
    ours_bare = set()
    for raw in ours.decode("utf-8", "surrogateescape").splitlines(keepends=True):
        bare = PACKAGE_RE.sub(r"\1", raw)
        ours_bare.add(bare)
        if bare != raw:
            exact.setdefault(bare, raw)
        key = _decl_key(bare)
        if key:
            by_decl[key].add(bare != raw)
            by_level[(key[0], key[1])][bare != raw] += 1
    lines = merged.decode("utf-8", "surrogateescape").splitlines(keepends=True)
    result = []
    for i, line in enumerate(lines):
        key = _decl_key(line)
        if line in exact:
            line = exact[line]
        elif key and not PACKAGE_RE.match(line):
            known = by_decl.get(key)
            level = by_level.get((key[0], key[1]), collections.Counter())
            new_here = line not in ours_bare and known is None
            if known == {True} or (
                new_here
                and key[1] != "extension"
                and not ACCESS_RE.search(line[: line.find(key[1])])
                and level[True] > level[False]
                and not _in_protocol(lines, i)
            ):
                at = ATTRIBUTES_RE.match(line).end()
                line = line[:at] + "package " + line[at:]
        result.append(line)
    return "".join(result).encode("utf-8", "surrogateescape")


def _merge_file(ours, base, theirs, labels):
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
                "--diff3",
                "-L",
                labels[0],
                "-L",
                labels[1],
                "-L",
                labels[2],
            ]
            + paths,
            check=False,
        )
        if proc.returncode < 0:
            raise ToolError(
                f"git merge-file failed: {proc.stderr.decode(errors='replace')}"
            )
        return proc.stdout, proc.returncode


def port_commit(
    upstream, pathmap, root, sha, report_dir, allow_dirty=False, dry_run=False
):
    """Apply one upstream commit to the tree. Returns a list of report lines and
    whether everything applied cleanly."""
    root = Path(root)
    app = root / APP_DIR
    short = sha[:10]
    lines = [
        f"## {short} {upstream.run(['log', '-1', '--format=%s', sha]).strip()}",
        "",
    ]
    clean = True
    parent = upstream.run(["rev-list", "--parents", "-n", "1", sha]).split()
    parent = parent[1] if len(parent) > 1 else None
    labels = ("vitruvian", f"upstream {short}^", f"upstream {short}")

    for status, old, new in upstream.changes(sha):
        if upstream_only(new) and upstream_only(old):
            lines.append(f"- `{new}`: upstream-only path, not ported")
            continue
        target_rel, how = pathmap.map(old)
        if status == "A":
            target_rel, how = pathmap.map(new)
        if target_rel is None:
            clean = False
            patch = (
                upstream.run(["diff", f"{parent or sha}", sha, "--", old, new])
                if parent
                else ""
            )
            saved = report_dir / (new.replace("/", "__") + ".patch")
            saved.write_text(patch)
            lines.append(f"- `{old}`: {how}; port by hand from `{saved}`")
            continue
        target = app / target_rel
        rel = f"{APP_DIR}/{target_rel}"
        if (
            not (allow_dirty or dry_run)
            and target.exists()
            and out(["status", "--porcelain", "--", rel], cwd=root).strip()
        ):
            raise ToolError(
                f"{rel} has uncommitted changes; commit or stash them, or pass --allow-dirty"
            )
        if upstream.is_binary(sha, new if status != "D" else old):
            clean = False
            lines.append(
                f"- `{new}` -> `{rel}`: binary, not applied; check it for upstream's brand, then copy it by hand"
            )
            continue

        if status == "D":
            base = to_fork_bytes(upstream.blob(parent, old))
            if target.exists() and target.read_bytes() == base:
                if not dry_run:
                    target.unlink()
                lines.append(f"- `{old}` -> `{rel}`: deleted, as upstream did")
            elif target.exists():
                clean = False
                lines.append(
                    f"- `{old}` -> `{rel}`: upstream deleted it, but this fork's copy has diverged; decide by hand"
                )
            continue

        theirs = to_fork_bytes(upstream.blob(sha, new))
        if status == "A" and not target.exists():
            result = theirs
            before = set()
            lines.append(f"- `{new}` -> `{rel}` ({how}): added")
        else:
            base = to_fork_bytes(upstream.blob(parent, old) if parent else b"")
            ours = target.read_bytes() if target.exists() else b""
            before = set(ours.decode("utf-8", "replace").splitlines())
            result, conflicts = merge3(ours, base, theirs, labels)
            note = (
                f" (upstream renamed it to `{new}`; the rename is not applied)"
                if status == "R"
                else ""
            )
            if conflicts:
                clean = False
                lines.append(
                    f"- `{old}` -> `{rel}` ({how}): {conflicts} conflict(s) to resolve{note}"
                )
            else:
                lines.append(f"- `{old}` -> `{rel}` ({how}): merged{note}")
        if not dry_run:
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(result)
        # Only lines the port brings in: this fork's own lines that name
        # upstream (tests asserting its links are gone) are not the port's.
        for n, l in brand_review(result.decode("utf-8", "replace")):
            if l in before:
                continue
            clean = False
            lines.append(f"  - brand review `{rel}:{n}`: `{l.strip()}`")
    lines.append("")
    return lines, clean


# --- Commands -------------------------------------------------------------------


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
    return Path(base) / "vitruvian-upstream"


def cmd_check_ledger(args):
    ledger = Ledger.load(args.ledger_path)
    errs = ledger.errors()
    for e in errs:
        print(f"{args.ledger_path}: {e}", file=sys.stderr)
    if errs:
        return 1
    counts = collections.Counter(r["status"] for r in ledger.rows)
    print(
        f"ledger ok: {len(ledger.rows)} commits ({', '.join(f'{counts[s]} {s}' for s in STATUSES)})"
    )
    return 0


def _triage(args):
    ledger = Ledger.load(args.ledger_path)
    upstream = Upstream(args.upstream_url, args.cache, fetch=not args.no_fetch)
    return ledger, upstream, Triage(upstream, ledger)


def cmd_status(args):
    ledger, upstream, t = _triage(args)
    if args.markdown:
        print(status_markdown(t, args.previous_body))
    else:
        print(
            f"upstream {UPSTREAM_BRANCH} at {t.head[:10]}; base {t.base[:10]}"
            + (
                f" (re-anchored by tree from {ledger.base[:10]})"
                if t.reanchored
                else ""
            )
        )
        if t.rekeyed:
            print(
                f"{len(t.rekeyed)} ledger row(s) re-keyed by patch id after an upstream history rewrite"
            )
        if t.orphaned:
            print(
                f"{len(t.orphaned)} ledger row(s) no longer on upstream: "
                + ", ".join(r["sha"][:10] for r in t.orphaned)
            )
        print(f"{len(t.untriaged)} untriaged, {len(t.pending)} pending")
        for c in t.untriaged:
            mark = " (auto-skip: upstream-only paths)" if c["auto_skip"] else ""
            print(f"  {c['sha'][:10]} {c['date']} {c['subject']}{mark}")
    if args.check and t.untriaged:
        return 1
    return 0


def status_markdown(t, previous_body=None):
    seen = set()
    if previous_body:
        m = re.search(
            r"<!-- untriaged-shas: ([0-9a-f ]*) -->", Path(previous_body).read_text()
        )
        if m:
            seen = set(m.group(1).split())
    new = [c for c in t.untriaged if c["sha"][:12] not in seen]
    shas = " ".join(c["sha"][:12] for c in t.untriaged)
    lines = [
        f"<!-- upstream-watch untriaged: {len(t.untriaged)} pending: {len(t.pending)} new: {len(new)} -->",
        f"<!-- untriaged-shas: {shas} -->",
        f"Upstream [vorssaint-utils]({UPSTREAM_URL}) `{UPSTREAM_BRANCH}` is at "
        f"[`{t.head[:10]}`]({UPSTREAM_URL}/commit/{t.head}). The ledger "
        f"(`{LEDGER}`) has **{len(t.untriaged)}** commit(s) to triage and "
        f"**{len(t.pending)}** pending port.",
        "",
        "Triage: `bazel run //apps/desktop/vitruvian:track_upstream -- triage`, then decide each pending row "
        '(UPSTREAM.md, "Tracking and porting upstream").',
        "",
    ]
    if t.reanchored:
        lines += [
            f"Upstream rewrote its history: the base moved to `{t.base[:10]}` (same tree).",
            "",
        ]
    if t.untriaged:
        lines += ["### Not yet in the ledger", ""]
        for c in t.untriaged:
            mark = " — upstream-only paths, will be skipped" if c["auto_skip"] else ""
            lines.append(
                f"- [`{c['sha'][:10]}`]({UPSTREAM_URL}/commit/{c['sha']}) {c['date']} {c['subject']}{mark}"
            )
        lines.append("")
    if t.pending:
        lines += [f"### Pending port ({len(t.pending)})", ""]
        for r in t.pending[:200]:
            lines.append(
                f"- [`{r['sha'][:10]}`]({UPSTREAM_URL}/commit/{r['sha']}) {r['date']} {r['subject']}"
            )
        if len(t.pending) > 200:
            lines.append(f"- … and {len(t.pending) - 200} more in the ledger")
    return "\n".join(lines)


def cmd_triage(args):
    ledger, upstream, t = _triage(args)
    t.apply()
    errs = ledger.errors()
    if errs:
        raise ToolError("ledger would be invalid: " + "; ".join(errs))
    added = len(t.untriaged)
    skipped = sum(1 for c in t.untriaged if c["auto_skip"])
    if args.dry_run:
        print(ledger.dump(), end="")
    else:
        Path(args.ledger_path).write_text(ledger.dump())
    print(
        f"triage: {added} added ({skipped} skipped as upstream-only, {added - skipped} pending), "
        f"{len(t.rekeyed)} re-keyed" + (", base re-anchored" if t.reanchored else ""),
        file=sys.stderr,
    )
    return 0


def cmd_show(args):
    upstream = Upstream(args.upstream_url, args.cache, fetch=not args.no_fetch)
    pathmap = PathMap(args.root, args.import_commit)
    for sha in args.commits:
        sha = upstream.run(["rev-parse", sha + "^{commit}"]).strip()
        print(
            upstream.run(
                ["log", "-1", "--format=%H%n%an <%ae>%n%ad%n%n%B", sha]
            ).rstrip()
        )
        print()
        for status, old, new in upstream.changes(sha):
            if upstream_only(new) and upstream_only(old):
                print(f"  {status} {new}  (upstream-only)")
                continue
            target, how = pathmap.map(new if status == "A" else old)
            where = f"{APP_DIR}/{target}" if target else "-"
            print(f"  {status} {new}\n      -> {where}  ({how})")
        print()
    return 0


def cmd_port(args):
    upstream = Upstream(args.upstream_url, args.cache, fetch=not args.no_fetch)
    pathmap = PathMap(args.root, args.import_commit)
    report_dir = Path(
        args.report_dir or tempfile.mkdtemp(prefix="vitruvian-upstream-port-")
    )
    report_dir.mkdir(parents=True, exist_ok=True)
    report = ["# Upstream port report", ""]
    all_clean = True
    for sha in args.commits:
        sha = upstream.run(["rev-parse", sha + "^{commit}"]).strip()
        lines, clean = port_commit(
            upstream,
            pathmap,
            args.root,
            sha,
            report_dir,
            args.allow_dirty,
            args.dry_run,
        )
        report += lines
        all_clean = all_clean and clean
    text = "\n".join(report)
    (report_dir / "report.md").write_text(text)
    print(text)
    print(f"report: {report_dir / 'report.md'}")
    if not all_clean:
        print(
            "Not clean: resolve the conflicts and the items above, then build and test.",
            file=sys.stderr,
        )
        return 1
    return 0


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument(
        "--root",
        help="monorepo checkout (default: the workspace `bazel run` was started in)",
    )
    parser.add_argument(
        "--ledger", dest="ledger_path", help=f"ledger file (default: <root>/{LEDGER})"
    )
    parser.add_argument("--upstream-url", default=UPSTREAM_URL)
    parser.add_argument(
        "--cache",
        help="where to keep the upstream clone (default: ~/.cache/vitruvian-upstream)",
    )
    parser.add_argument(
        "--no-fetch", action="store_true", help="use the cached upstream clone as it is"
    )
    parser.add_argument(
        "--import-commit", default=IMPORT_COMMIT, help=argparse.SUPPRESS
    )
    sub = parser.add_subparsers(dest="command", required=True)

    sub.add_parser("check-ledger", help="validate the ledger (offline)").set_defaults(
        func=cmd_check_ledger
    )
    p = sub.add_parser("status", help="list upstream commits not yet triaged")
    p.add_argument(
        "--check", action="store_true", help="exit 1 if any commit is untriaged"
    )
    p.add_argument(
        "--markdown", action="store_true", help="print the tracking issue's body"
    )
    p.add_argument(
        "--previous-body",
        help="the issue's current body, to count commits it did not list",
    )
    p.set_defaults(func=cmd_status)
    p = sub.add_parser("triage", help="add untriaged commits to the ledger")
    p.add_argument(
        "--dry-run", action="store_true", help="print the ledger instead of writing it"
    )
    p.set_defaults(func=cmd_triage)
    p = sub.add_parser(
        "show", help="an upstream commit, with where each of its files lives here"
    )
    p.add_argument("commits", nargs="+")
    p.set_defaults(func=cmd_show)
    p = sub.add_parser(
        "port",
        help="apply upstream commits to this tree (a first pass to finish by hand)",
    )
    p.add_argument(
        "commits", nargs="+", help="upstream commits, applied in the order given"
    )
    p.add_argument("--report-dir", help="where to write report.md and unplaced patches")
    p.add_argument(
        "--allow-dirty",
        action="store_true",
        help="merge into files with uncommitted changes",
    )
    p.add_argument(
        "--dry-run",
        action="store_true",
        help="report what would happen, change nothing",
    )
    p.set_defaults(func=cmd_port)

    args = parser.parse_args(argv)
    args.root = repo_root(args.root)
    args.ledger_path = (
        Path(args.ledger_path) if args.ledger_path else args.root / LEDGER
    )
    args.cache = cache_dir(args.cache)
    try:
        return args.func(args)
    except ToolError as e:
        print(f"upstream: {e}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
