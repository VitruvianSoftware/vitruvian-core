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

"""agent-guard: stop AI agents running repo and dev operations outside Bazel.

A PreToolUse hook for Claude Code and for Antigravity (agy). It reads
the tool call on stdin, works out every program the command would run, and
refuses the ones that, inside vitruvian-core, must go through a Bazel target:
`git commit` -> `bazel run //tools/git:commit`, `go test` -> `bazel test`, and
so on. The refusal names the replacement.

It is a guardrail against habits, not a security boundary: it reads the
command TEXT, so a script that calls git internally is not seen. James's own
terminal is never affected; hooks only run inside agent loops.

Standard library only, and Python 3.9 compatible: the hook runs on whichever
python3 the machine has (tools/agent-guard/hook.sh picks it), not on Bazel's.
The hook runs THIS file as it is on origin/main, so an edit here governs agents
only once it is merged.

See README.md beside this file for the rules, the limits and the log.
"""

from __future__ import annotations

import datetime
import fnmatch
import json
import os
import re
import subprocess
import sys
from typing import Any, Callable, Dict, List, Optional, Sequence, Tuple

VERSION = "1.0.0"

MODES = ("enforce", "warn", "off")

# The Bazel module name that marks a vitruvian-core checkout or worktree.
MODULE_NAME_RE = re.compile(r'module\(\s*name\s*=\s*"vitruvian_core"')

# Where the old per-user installer copied the guard, and where the guard logs
# and hook.sh caches origin/main's copy. Agents may not write to either
# (category guard-config). The old copy stays protected while anyone still has
# it: `bazel run //tools/agent-guard:install` migrates it to the backstop and
# deletes it.
INSTALL_DIR_REL = ".local/share/agent-guard"
STATE_DIR_REL = ".local/state/agent-guard"

# Files in a checkout that wire the hook up, could switch it off, or run as
# hooks themselves, and that take effect the moment they change, before anyone
# reviews them. Agents may not write, move or delete them (category
# guard-config); changing them is James's call. The guard's own source and
# policy are NOT here: hook.sh runs them from origin/main, so an agent's edit to
# them governs nothing until it is merged. `*` matches within one folder.
#
# tools/remote/setup.sh drives session start from the working copy, with the
# session's credentials: cloud-bootstrap.sh runs it to configure the build
# cache (with BUILDBUDDY_API_KEY).
#
# tools/cloud-bootstrap/cloud-bootstrap.sh and profiles.tsv are deliberately NOT
# here: they also run at session start with the session's credentials, but an
# agent has to be able to change them (for example to move credentials from
# environment variables into Secret Manager). They are still gated by review:
# the agent-guard-review ruleset (guard_review.go) requires the guard owner's
# approval on any PR that touches them, so such a change cannot merge unreviewed.
# What this local guard no longer prevents is an agent editing them on a branch
# that a session then starts from before review.
PROTECTED_REPO_FILES = (
    ".claude/settings.json",
    ".claude/settings.local.json",
    ".claude/*.sh",
    ".agents/hooks.json",
    "tools/agent-guard/hook.sh",
    "tools/remote/setup.sh",
)

LOG_MAX_BYTES = 10 * 1024 * 1024
LOG_COMMAND_MAX = 1000

# ---------------------------------------------------------------------------
# Categories. Each has a mode in policy.json; the default for all is enforce.
# ---------------------------------------------------------------------------
CATEGORIES = {
    "git-commit": "git add / rm / mv / commit",
    "git-push": "git push",
    "git-history": "git rebase, merge, pull (except ff-only on the primary checkout), reset, cherry-pick, revert, am, bisect, tag",
    "git-stash": "git stash (anything but list/show)",
    "git-branch": "creating, switching, renaming or deleting branches",
    "git-worktree": "git worktree add/remove/prune/lock/unlock/move, and rm -r of a worktree",
    "git-other": "every other git verb that writes (config, remote, apply, clean, gc, clone, ...)",
    "gh-pr": "gh pr create/edit/comment/merge/ready/close/review, and the auto-merge MCP tool",
    "gh-run": "gh workflow run/enable/disable, gh run rerun/cancel/delete",
    "gh-api": "gh api writes and GraphQL mutations",
    "gh-other": "every other gh command that writes (release, secret, repo, label, ...)",
    "go": "go build/test/vet/run/install/generate/mod/get/fmt",
    "swift": "swift build/test/run/package, swiftc",
    "xcode": "xcodebuild, xcrun notarytool/stapler/altool/swift",
    "node": "npm/pnpm/npx/yarn/bun installs and runs",
    "cargo": "cargo build/test/run/publish/...",
    "gradle": "gradle and gradlew",
    "pytest": "pytest, python -m pytest",
    "lint": "linters and formatters run directly (gofmt, golangci-lint, ruff, eslint, prettier, ...)",
    "actionlint": "actionlint run directly",
    "secret-scan": "gitleaks run directly",
    "iac": "pulumi and terraform run directly",
    "kubectl": "kubectl writes (apply, delete, patch, edit, exec, rollout, scale, ...) and the kubernetes MCP write tools",
    "helm": "helm install/upgrade/uninstall/rollback",
    "bazel-cache": "deleting Bazel output bases (rm -r, bazel clean --expunge, --output_user_root/--output_base overrides)",
    "guard-config": "agents changing agent-guard itself, or the files that drive session start",
    "oversize": "a command too large to check in time (over 20,000 commands); split it up",
}

# Categories that apply wherever the agent is, because what they protect is
# not inside the checkout (the Bazel caches, the guard itself).
GLOBAL_CATEGORIES = {"bazel-cache", "guard-config"}

GUARDRAIL = (
    "agent-guard is a guardrail, not a security boundary: do not route around it "
    "(no aliases, wrapper scripts, eval, other shells, other tools or absolute paths)."
)


# ---------------------------------------------------------------------------
# Verdicts
# ---------------------------------------------------------------------------
class Verdict(object):
    """One refused operation: what it was, its category, and what to use instead."""

    def __init__(
        self,
        category: str,
        op: str,
        use: Optional[str] = None,
        pending: Optional[Tuple[str, Optional[str]]] = None,
        note: str = "",
    ):
        self.category = category
        self.op = op
        self.use = use  # None means: there is no Bazel target for this yet.
        self.pending = pending  # (repo-relative file, needle) the target lives in.
        self.note = note

    def message(self, repo_root: Optional[str]) -> str:
        if self.use:
            text = (
                "Blocked by agent-guard: `%s` must go through Bazel in vitruvian-core. Use `%s`."
                % (
                    self.op,
                    self.use,
                )
            )
            if self.pending and not _target_present(repo_root, self.pending):
                text += (
                    " That target is being built and is not in this checkout yet: if `bazel run` "
                    "cannot find it, stop and tell James."
                )
        elif self.category == "guard-config":
            # Protecting the guard is not a missing target: say what is refused.
            text = "Blocked by agent-guard: `%s` is not for agents." % self.op
        else:
            text = (
                "Blocked by agent-guard: `%s` must go through a Bazel target in vitruvian-core, "
                "and there is no target for it yet. Stop and tell James that `%s` needs one."
                % (self.op, self.op)
            )
        if self.note:
            text += " " + self.note
        text += " " + GUARDRAIL
        if self.use:
            text += " If no target fits, stop and tell James which one is missing."
        return text

    def __repr__(self) -> str:  # pragma: no cover - debugging aid
        return "Verdict(%s, %r)" % (self.category, self.op)


def _target_present(
    repo_root: Optional[str], pending: Tuple[str, Optional[str]]
) -> bool:
    if not repo_root:
        return True
    rel, needle = pending
    path = os.path.join(repo_root, rel)
    try:
        if needle is None:
            return os.path.exists(path)
        with open(path, "r", encoding="utf-8", errors="replace") as fh:
            return needle in fh.read()
    except OSError:
        return False


# Replacement targets. The (file, needle) pairs say where each target will
# live; while it is missing the refusal says so and points to James. Every
# file named here must exist on main (PendingTargetsTest checks), or every
# refusal naming that target wrongly says it is not built yet.
T_COMMIT = ("bazel run //tools/git:commit", ("tools/git/BUILD", "commit"))
T_PUSH = ("bazel run //tools/git:push", ("tools/git/BUILD", "push"))
T_SYNC = ("bazel run //tools/git:sync", ("tools/git/BUILD", "sync"))
T_WT_NEW = ("bazel run //tools/worktree -- <branch> [base-ref]", None)
T_WT_DETACH = ("bazel run //tools/worktree -- --detach <ref>", None)
T_WT_REMOVE = ("bazel run //tools/worktree -- --remove <branch>", None)
T_WT_PRUNE = ("bazel run //tools/worktree -- --prune (then --prune --execute)", None)
T_WT_LOCK = ("bazel run //tools/worktree -- --lock / --unlock", None)
T_WT_DELETE_BRANCH = (
    "bazel run //tools/worktree -- --remove <branch> --delete-branch (or --prune --execute)",
    None,
)
T_PR_CREATE = (
    "bazel run //tools/agent-app -- pr-create",
    None,
)
T_PR_ENQUEUE = (
    "bazel run //tools/agent-app -- pr-enqueue <pr>",
    None,
)
# Actions writes: wren's App is the only one with Actions write
# (tools/agent-app/permissions.tsv), so the other agents' Apps are refused.
T_RUN_RERUN = (
    "bazel run //tools/agent-app -- run-rerun <run-id> [--failed] [--job <id>]",
    None,
)
T_RUN_CANCEL = (
    "bazel run //tools/agent-app -- run-cancel <run-id>",
    None,
)
T_WORKFLOW_RUN = (
    "bazel run //tools/agent-app -- workflow-run <file.yaml> [-f k=v ...] [--ref main]",
    None,
)
RUN_NOTE = "Only wren's App has Actions write; any other agent: tell James."
RUN_NO_TARGET_NOTE = (
    "//tools/agent-app has run-rerun, run-cancel and workflow-run, but nothing "
    "that deletes runs or enables or disables workflows."
)
T_SECRET_SCAN = ("bazel run //tools/secret-scan", ("tools/secret-scan/BUILD", None))
T_ACTIONLINT = ("bazel run //tools/ci:actionlint", ("tools/ci/BUILD", '"actionlint"'))
T_CACHE_GC = (
    "bazel run //tools/bazel-cache:gc (dry run; add -- --execute to delete)",
    None,
)
T_FORMAT = ("bazel run //tools/format (or bazel run //:tidy)", None)
T_LINT = ("aspect lint //<package>/...", None)
T_BAZEL_TEST = ("bazel test //<package>/...", None)
T_BAZEL_BUILD = ("bazel build //<package>:<target> (or bazel run for a binary)", None)
T_PULUMI = (
    "bazel run //infrastructure/pulumi/<project>:preview (and :up only as AGENTS.md allows)",
    None,
)
T_GITOPS = (
    "bazel run //tools/gitops:{apply,delete,patch} (or change the manifest in git and let Argo CD sync)",
    None,
)
T_HELM = (
    "bazel run //tools/gitops:helm -- <args> (or change the chart values in git)",
    None,
)


def V(
    category: str,
    op: str,
    target: Optional[Tuple[str, Optional[Tuple[str, Optional[str]]]]] = None,
    note: str = "",
) -> Verdict:
    if target is None:
        return Verdict(category, op, None, None, note)
    return Verdict(category, op, target[0], target[1], note)


# ---------------------------------------------------------------------------
# Shell parsing. A small tokenizer that understands enough of sh/bash/zsh to
# find every simple command: operators, quotes, $(...), backticks, process
# substitution, subshells, braces, heredocs and redirections.
# ---------------------------------------------------------------------------
class SimpleCommand(object):
    def __init__(self) -> None:
        self.words: List[str] = []
        self.redirects: List[Tuple[str, str]] = []
        self.heredocs: List[str] = []
        self.herestrings: List[str] = []

    def __repr__(self) -> str:  # pragma: no cover - debugging aid
        return "SimpleCommand(%r)" % (self.words,)


class ParseError(Exception):
    pass


class TooComplex(Exception):
    """More commands than the guard will check within its time budget."""


# The most simple commands (plus nested parses) one tool call may contain.
# Real commands have tens; the hook must answer well inside its 10 s timeout
# whatever it is given, and the command tools fail closed.
MAX_COMMANDS = 20000


def _spend(budget: List[int]) -> None:
    budget[0] -= 1
    if budget[0] < 0:
        raise TooComplex()


_OPERATORS = ("&&", "||", ";;", "|&", ";", "|", "&", "\n", "(", ")")
_OPERATOR_RE = re.compile(r"&&|\|\||;;|\|&|[;|&\n()]")
# Operators and blanks after an operator: no command between them, so one step.
# Stops at a newline (heredoc bodies start there) and at &> (a redirection).
_OPERATOR_RUN = re.compile(r"(?:[();| \t]|&(?!>))+")
_KEYWORDS_DROP = {
    "then",
    "do",
    "else",
    "elif",
    "if",
    "while",
    "until",
    "!",
    "{",
    "}",
    "fi",
    "done",
    "esac",
}


_HEREDOC_DELIM_RE = re.compile(
    r"""-?[ \t]*(?:'([^'\n]*)'|"([^"\n]*)"|\\?([^\s;|&<>()'"]+))"""
)


def _heredoc_at(text: str, i: int) -> Optional[Tuple[str, bool, int]]:
    """If a heredoc operator (<< or <<-, not <<<) starts at i: (delimiter, strip tabs, end)."""
    if not text.startswith("<<", i) or text.startswith("<<<", i):
        return None
    m = _HEREDOC_DELIM_RE.match(text, i + 2)
    if not m:
        return None
    delim = next(g for g in m.groups() if g is not None)
    if delim.isdigit():
        return None  # $(( 1 << 2 )): a shift, not a heredoc
    return delim, text[i + 2 : i + 3] == "-", m.end()


def _skip_heredoc_bodies(text: str, pos: int, pending: List[Tuple[str, bool]]) -> int:
    """pos is just after a newline: skip each pending heredoc body and its delimiter line."""
    n = len(text)
    while pending:
        delim, strip_tabs = pending.pop(0)
        while pos < n:
            nl = text.find("\n", pos)
            line = text[pos:] if nl < 0 else text[pos:nl]
            pos = n if nl < 0 else nl + 1
            if (line.lstrip("\t") if strip_tabs else line) == delim:
                break
    return pos


# Runs of characters with no meaning to the scanners, consumed in one regex
# step so a megabyte-long word costs milliseconds, not a Python loop per char.
_WORD_RUN = re.compile(r"[^\s'\"\\$`<>&|;()]+")
_DQ_RUN = re.compile(r'[^"\\$`]+')
_ANSI_RUN = re.compile(r"[^'\\]+")
_MATCH_RUN = re.compile(r"[^\\\n<#'\"`(){}]+")
_BACKTICK_STOP = re.compile(r"[\\`]")
_BODY_STOP = re.compile(r"[\\`]|\$\(")
_FD_DUP = re.compile(r"\d+-?|-")


def _find_matching(text: str, start: int, open_ch: str, close_ch: str) -> int:
    """Index of the close char matching text[start-1]==open_ch, quote and heredoc aware.

    A heredoc body is data: an apostrophe or backtick in it must not open a quote.
    """
    depth = 1
    i = start
    n = len(text)
    pending: List[Tuple[str, bool]] = []
    while i < n:
        m = _MATCH_RUN.match(text, i)
        if m:
            i = m.end()
            if i >= n:
                break
        c = text[i]
        if c == "\\":
            i += 2
            continue
        if c == "\n" and pending:
            i = _skip_heredoc_bodies(text, i + 1, pending)
            continue
        if c == "<":
            hd = _heredoc_at(text, i)
            if hd is not None:
                pending.append((hd[0], hd[1]))
                i = hd[2]
                continue
        if c == "#" and (i == start or text[i - 1] in " \t\n;(|&"):
            nl = text.find("\n", i)
            i = n if nl < 0 else nl
            continue
        if c == "'":
            j = text.find("'", i + 1)
            if j < 0:
                raise ParseError("unterminated single quote")
            i = j + 1
            continue
        if c == '"':
            i = _skip_double(text, i + 1)
            continue
        if c == "`":
            j = _find_backtick(text, i + 1)
            i = j + 1
            continue
        if c == open_ch:
            depth += 1
        elif c == close_ch:
            depth -= 1
            if depth == 0:
                return i
        i += 1
    raise ParseError("unbalanced %s" % open_ch)


def _skip_double(text: str, i: int) -> int:
    n = len(text)
    while i < n:
        m = _DQ_RUN.match(text, i)
        if m:
            i = m.end()
            if i >= n:
                break
        c = text[i]
        if c == "\\":
            i += 2
            continue
        if c == '"':
            return i + 1
        if c == "$" and i + 1 < n and text[i + 1] == "(":
            i = _find_matching(text, i + 2, "(", ")") + 1
            continue
        if c == "`":
            i = _find_backtick(text, i + 1) + 1
            continue
        i += 1
    raise ParseError("unterminated double quote")


def _find_backtick(text: str, i: int) -> int:
    while True:
        m = _BACKTICK_STOP.search(text, i)
        if m is None:
            break
        if text[m.start()] == "\\":
            i = m.start() + 2
            continue
        return m.start()
    raise ParseError("unterminated backtick")


_ANSI_ESCAPES = {
    "n": "\n",
    "t": "\t",
    "r": "\r",
    "\\": "\\",
    "'": "'",
    '"': '"',
    "a": "\a",
    "e": "\x1b",
    "0": "\0",
}


def body_substitutions(body: str) -> List[str]:
    """The $(...) and `...` commands an UNQUOTED heredoc body would run.

    Quotes are plain text in a heredoc body, so only backslashes, $( ) and
    backticks matter. An unbalanced one is text (the shell would fail anyway).
    """
    out: List[str] = []
    i = 0
    n = len(body)
    while i < n:
        m = _BODY_STOP.search(body, i)
        if m is None:
            break
        i = m.start()
        c = body[i]
        if c == "\\":
            i += 2
            continue
        try:
            if body.startswith("$((", i):
                i = _find_matching(body, i + 3, "(", ")") + 2
                continue
            if body.startswith("$(", i):
                k = _find_matching(body, i + 2, "(", ")")
                out.append(body[i + 2 : k])
                i = k + 1
                continue
            if c == "`":
                k = _find_backtick(body, i + 1)
                out.append(body[i + 1 : k])
                i = k + 1
                continue
        except ParseError:
            break
        i += 1
    return out


def parse_script(
    text: str, depth: int = 0, budget: Optional[List[int]] = None
) -> List[SimpleCommand]:
    """Split a shell script into simple commands, nested ones included.

    Raises TooComplex past MAX_COMMANDS (shared across nested parses via budget).
    """
    if budget is None:
        budget = [MAX_COMMANDS]
    _spend(budget)
    if depth > 8:
        raise ParseError("nesting too deep")
    commands: List[SimpleCommand] = []
    nested: List[SimpleCommand] = []
    cur = SimpleCommand()
    word: List[str] = []
    in_word = False
    quoted = False
    pending_redirect: Optional[str] = None
    pending_heredocs: List[Tuple[str, bool, SimpleCommand, bool]] = []
    i = 0
    n = len(text)

    def end_word() -> None:
        nonlocal word, in_word, quoted, pending_redirect
        if not in_word:
            return
        w = "".join(word)
        if pending_redirect is not None:
            op = pending_redirect
            pending_redirect = None
            if op in ("<<", "<<-"):
                # A quoted delimiter ('EOF', "EOF", \EOF) makes the body
                # literal; an unquoted one lets the shell run $(...) in it.
                pending_heredocs.append((w, op == "<<-", cur, quoted))
            elif op == "<<<":
                cur.herestrings.append(w)
            else:
                cur.redirects.append((op, w))
        else:
            cur.words.append(w)
        word = []
        in_word = False
        quoted = False

    def end_command() -> None:
        nonlocal cur
        end_word()
        if cur.words or cur.redirects or cur.heredocs or cur.herestrings:
            _spend(budget)
            commands.append(cur)
        cur = SimpleCommand()

    def read_heredocs(pos: int) -> int:
        # Called right after a newline: consume the bodies of pending heredocs.
        while pending_heredocs:
            delim, strip_tabs, owner, literal = pending_heredocs.pop(0)
            body_lines = []
            while pos <= n:
                nl = text.find("\n", pos)
                line = text[pos:] if nl < 0 else text[pos:nl]
                pos = n + 1 if nl < 0 else nl + 1
                check = line.lstrip("\t") if strip_tabs else line
                if check == delim:
                    break
                body_lines.append(line)
                if nl < 0:
                    break
            body = "\n".join(body_lines)
            owner.heredocs.append(body)
            if not literal:
                # Each distinct command once: a body repeating `x` 300,000
                # times is one parse, not 300,000.
                for sub in dict.fromkeys(body_substitutions(body)):
                    try:
                        nested.extend(parse_script(sub, depth + 1, budget))
                    except ParseError:
                        nested.extend(fallback_split(sub, budget))
        return min(pos, n)

    while i < n:
        c = text[i]
        # Comments start only at the beginning of a word.
        if c == "#" and not in_word:
            nl = text.find("\n", i)
            i = n if nl < 0 else nl
            continue
        if c in " \t":
            end_word()
            i += 1
            while i < n and text[i] in " \t":
                i += 1
            continue
        if c == "\\":
            if i + 1 < n and text[i + 1] == "\n":
                i += 2
                continue
            if i + 1 < n:
                word.append(text[i + 1])
                in_word = True
                quoted = True
            i += 2
            continue
        if c == "'":
            j = text.find("'", i + 1)
            if j < 0:
                raise ParseError("unterminated single quote")
            word.append(text[i + 1 : j])
            in_word = True
            quoted = True
            i = j + 1
            continue
        if c == "$" and i + 1 < n and text[i + 1] == "'":
            # ANSI-C quoting.
            j = i + 2
            out = []
            while j < n and text[j] != "'":
                m = _ANSI_RUN.match(text, j)
                if m:
                    out.append(m.group())
                    j = m.end()
                    continue
                if text[j] == "\\" and j + 1 < n:
                    out.append(_ANSI_ESCAPES.get(text[j + 1], text[j + 1]))
                    j += 2
                    continue
                out.append(text[j])
                j += 1
            if j >= n:
                raise ParseError("unterminated $'")
            word.append("".join(out))
            in_word = True
            quoted = True
            i = j + 1
            continue
        if c == '"':
            j = i + 1
            out = []
            while True:
                if j >= n:
                    raise ParseError("unterminated double quote")
                m = _DQ_RUN.match(text, j)
                if m:
                    out.append(m.group())
                    j = m.end()
                    continue
                ch = text[j]
                if ch == '"':
                    break
                if ch == "\\" and j + 1 < n and text[j + 1] in '"\\$`\n':
                    if text[j + 1] != "\n":
                        out.append(text[j + 1])
                    j += 2
                    continue
                if ch == "$" and j + 1 < n and text[j + 1] == "(":
                    if j + 2 < n and text[j + 2] == "(":
                        k = _find_matching(text, j + 3, "(", ")")
                        end = k + 2 if k + 1 < n and text[k + 1] == ")" else k + 1
                        out.append(text[j:end])
                        j = end
                        continue
                    k = _find_matching(text, j + 2, "(", ")")
                    nested.extend(parse_script(text[j + 2 : k], depth + 1, budget))
                    out.append(text[j : k + 1])
                    j = k + 1
                    continue
                if ch == "`":
                    k = _find_backtick(text, j + 1)
                    nested.extend(parse_script(text[j + 1 : k], depth + 1, budget))
                    out.append(text[j : k + 1])
                    j = k + 1
                    continue
                out.append(ch)
                j += 1
            word.append("".join(out))
            in_word = True
            quoted = True
            i = j + 1
            continue
        if c == "$" and i + 1 < n and text[i + 1] == "(":
            if i + 2 < n and text[i + 2] == "(":
                # Arithmetic $(( ... )): data, not a command.
                k = _find_matching(text, i + 3, "(", ")")
                end = k + 2 if k + 1 < n and text[k + 1] == ")" else k + 1
                word.append(text[i:end])
                in_word = True
                i = end
                continue
            k = _find_matching(text, i + 2, "(", ")")
            nested.extend(parse_script(text[i + 2 : k], depth + 1, budget))
            word.append(text[i : k + 1])
            in_word = True
            i = k + 1
            continue
        if c == "$" and i + 1 < n and text[i + 1] == "{":
            k = _find_matching(text, i + 2, "{", "}")
            word.append(text[i : k + 1])
            in_word = True
            i = k + 1
            continue
        if c == "`":
            k = _find_backtick(text, i + 1)
            nested.extend(parse_script(text[i + 1 : k], depth + 1, budget))
            word.append(text[i : k + 1])
            in_word = True
            i = k + 1
            continue
        if c in "<>" and i + 1 < n and text[i + 1] == "(":
            # Process substitution <( ... ) / >( ... ).
            k = _find_matching(text, i + 2, "(", ")")
            nested.extend(parse_script(text[i + 2 : k], depth + 1, budget))
            word.append(text[i : k + 1])
            in_word = True
            i = k + 1
            continue
        if c in "<>" or (c == "&" and i + 1 < n and text[i + 1] == ">"):
            # Redirection. A bare number right before it is the fd, not a word.
            if in_word and not quoted and "".join(word).isdigit():
                word = []
                in_word = False
            else:
                end_word()
            op = None
            for cand in (
                "<<<",
                "<<-",
                "&>>",
                "<<",
                ">>",
                ">|",
                "<>",
                ">&",
                "<&",
                "&>",
                ">",
                "<",
            ):
                if text.startswith(cand, i):
                    op = cand
                    break
            assert op is not None
            i += len(op)
            if op in (">&", "<&"):
                # >&2, >&- : fd duplication, no file.
                m = _FD_DUP.match(text, i)
                if m:
                    i = m.end()
                    continue
            pending_redirect = op
            # Heredoc delimiters may be quoted; the word reader strips quotes.
            continue
        if c == "\n":
            end_command()
            i = read_heredocs(i + 1)
            continue
        mo = _OPERATOR_RE.match(text, i)
        if mo is not None:
            end_command()
            # (Newlines never get here: they are handled above, with heredocs.)
            more = _OPERATOR_RUN.match(text, mo.end())
            i = more.end() if more else mo.end()
            continue
        if c in "{}" and not in_word:
            # A brace group opener/closer only when it stands alone as a word.
            if i + 1 >= n or text[i + 1] in " \t\n;":
                if c == "}":
                    end_command()
                else:
                    end_word()
                i += 1
                continue
        m = _WORD_RUN.match(text, i)
        end = m.end() if m and m.end() > i else i + 1
        word.append(text[i:end])
        in_word = True
        i = end
    end_command()

    # Drop shell keywords that lead a command (if/then/do/...); keep the rest.
    out: List[SimpleCommand] = []
    for cmd in commands + nested:
        while cmd.words and cmd.words[0] in _KEYWORDS_DROP:
            cmd.words.pop(0)
        if cmd.words and cmd.words[0] in ("for", "select", "case", "function"):
            continue
        if cmd.words and re.match(r"^[A-Za-z_][A-Za-z0-9_]*\(\)$", cmd.words[0]):
            continue
        if cmd.words or cmd.heredocs or cmd.herestrings or cmd.redirects:
            out.append(cmd)
    return out


def strip_heredoc_bodies(text: str) -> str:
    """Drop heredoc bodies (they are data) so the crude fallback never splits them."""
    out = []
    pending: List[Tuple[str, bool]] = []
    for line in text.split("\n"):
        if pending:
            delim, strip_tabs = pending[0]
            if (line.lstrip("\t") if strip_tabs else line) == delim:
                pending.pop(0)
            continue
        out.append(line)
        i = line.find("<<")
        while i >= 0:
            hd = _heredoc_at(line, i)
            if hd is not None:
                pending.append((hd[0], hd[1]))
                i = line.find("<<", hd[2])
            else:
                i = line.find("<<", i + 3)
    return "\n".join(out)


def fallback_split(
    text: str, budget: Optional[List[int]] = None
) -> List[SimpleCommand]:
    """When the parser gives up (unbalanced quotes), split crudely on operators."""
    out = []
    for seg in re.split(r"&&|\|\||[;|&\n()`]|\$\(", strip_heredoc_bodies(text)):
        words = [w.strip("'\"") for w in seg.split()]
        if words:
            if budget is not None:
                _spend(budget)
            c = SimpleCommand()
            c.words = words
            out.append(c)
    return out


# ---------------------------------------------------------------------------
# Unwrapping: env/nice/time/timeout/xargs/sudo/... and shells/eval.
# ---------------------------------------------------------------------------
ASSIGN_RE = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=")
SHELLS = {"bash", "sh", "zsh", "dash", "ksh", "fish"}


class Invocation(object):
    """A program the command would run, with the directory it runs in."""

    def __init__(
        self,
        argv: List[str],
        cwd: str,
        redirects: List[Tuple[str, str]],
        hides_marker: bool = False,
    ):
        self.argv = argv
        self.cwd = cwd
        self.redirects = redirects
        # Run with an agent marker (CLAUDECODE, ...) unset or blanked.
        self.hides_marker = hides_marker

    @property
    def prog(self) -> str:
        return os.path.basename(self.argv[0]) if self.argv else ""

    def __repr__(self) -> str:  # pragma: no cover - debugging aid
        return "Invocation(%r @ %s)" % (self.argv, self.cwd)


def _skip_opts(
    args: List[str], with_arg: Sequence[str], long_with_arg: Sequence[str] = ()
) -> List[str]:
    """Drop leading options; those in with_arg consume the next word."""
    i = 0
    while i < len(args):
        a = args[i]
        if a == "--":
            return args[i + 1 :]
        if not a.startswith("-") or a == "-":
            break
        if a in with_arg or a in long_with_arg:
            i += 2
            continue
        i += 1
    return args[i:]


def _unwrap(
    words: List[str], cmd: SimpleCommand, depth: int
) -> Tuple[List[str], List[str]]:
    """Strip wrappers. Returns (argv, scripts) where scripts are nested shell text."""
    scripts: List[str] = []
    for _ in range(20):
        while words and ASSIGN_RE.match(words[0]):
            words = words[1:]
        if not words:
            return [], scripts
        prog = os.path.basename(words[0])
        args = words[1:]
        if prog == "env":
            rest = []
            i = 0
            while i < len(args):
                a = args[i]
                if a in ("-u", "-C", "--unset", "--chdir"):
                    i += 2
                    continue
                if a in ("-S", "--split-string") and i + 1 < len(args):
                    scripts.append(" ".join(args[i + 1 :]))
                    return [], scripts
                if a.startswith("-S") and len(a) > 2:
                    scripts.append(" ".join([a[2:]] + args[i + 1 :]))
                    return [], scripts
                if a.startswith("-") and a != "-" or ASSIGN_RE.match(a) or a == "-":
                    i += 1
                    continue
                rest = args[i:]
                break
            words = rest
            continue
        if prog in ("command", "builtin"):
            if args and args[0] in ("-v", "-V"):
                return [], scripts  # a lookup, not a run
            words = _skip_opts(args, ())
            continue
        if prog in ("exec", "nohup", "noglob", "chronic", "unbuffer", "nocorrect"):
            words = _skip_opts(args, ("-a",))
            continue
        if prog in ("sudo", "doas"):
            words = _skip_opts(
                args, ("-u", "-g", "-h", "-p", "-C", "-D", "-r", "-t", "-U", "-T")
            )
            continue
        if prog == "nice":
            words = _skip_opts(args, ("-n",))
            continue
        if prog == "ionice":
            words = _skip_opts(args, ("-c", "-n", "-p", "-P", "-u"))
            continue
        if prog == "time":
            words = _skip_opts(args, ("-f", "-o", "--format", "--output"))
            continue
        if prog in ("timeout", "gtimeout"):
            rest = _skip_opts(args, ("-s", "-k", "--signal", "--kill-after"))
            words = rest[1:] if rest else []
            continue
        if prog in ("stdbuf",):
            words = _skip_opts(args, ("-i", "-o", "-e"))
            continue
        if prog == "caffeinate":
            words = _skip_opts(args, ("-t", "-w"))
            continue
        if prog == "watch":
            rest = _skip_opts(args, ("-n", "--interval", "-d"))
            if rest:
                scripts.append(" ".join(rest))
            return [], scripts
        if prog == "xargs":
            words = _skip_opts(
                args,
                ("-I", "-L", "-n", "-P", "-s", "-E", "-d", "-a", "-J", "-R", "-S"),
            )
            if not words:
                return [], scripts  # xargs with no command runs echo
            continue
        if prog in ("direnv",) and args[:1] == ["exec"]:
            words = args[2:]
            continue
        if prog in ("mise", "asdf", "rtx") and args[:1] == ["exec"]:
            rest = args[1:]
            words = rest[rest.index("--") + 1 :] if "--" in rest else rest[1:]
            continue
        if prog in ("uv", "poetry", "pdm", "hatch", "pipenv") and args[:1] == ["run"]:
            words = _skip_opts(
                args[1:],
                (
                    "--with",
                    "--python",
                    "-p",
                    "--directory",
                    "--project",
                    "--group",
                    "--extra",
                    "--env-file",
                ),
            )
            continue
        if prog == "uvx" or (prog == "pipx" and args[:1] == ["run"]):
            words = _skip_opts(
                args if prog == "uvx" else args[1:],
                ("--from", "--with", "--python", "-p", "--spec"),
            )
            continue
        if prog in ("python", "python3") or re.match(r"^python3(\.\d+)?$", prog):
            rest = args
            # python -m <module> ... -> treat the module as the program.
            j = 0
            while (
                j < len(rest)
                and rest[j].startswith("-")
                and rest[j] not in ("-m", "-c")
            ):
                j += 1
            if j < len(rest) and rest[j] == "-m" and j + 1 < len(rest):
                words = [rest[j + 1]] + rest[j + 2 :]
                continue
            return words, scripts
        if prog in SHELLS:
            i = 0
            script = None
            has_c = False
            positional = None
            while i < len(args):
                a = args[i]
                if a == "--":
                    i += 1
                    break
                if a in ("-o", "+o", "-O", "+O", "--rcfile", "--init-file"):
                    i += 2
                    continue
                if a.startswith("-") and not a.startswith("--") and "c" in a[1:]:
                    has_c = True
                    i += 1
                    continue
                if a.startswith("-") or a.startswith("+"):
                    i += 1
                    continue
                break
            if has_c:
                if i < len(args):
                    script = args[i]
            elif i < len(args):
                positional = args[i]
            if script is not None:
                scripts.append(script)
                return [], scripts
            if positional is None:
                scripts.extend(cmd.heredocs)
                scripts.extend(cmd.herestrings)
                return [], scripts
            # bash some-script.sh: the script's contents are not seen (a limit).
            return words, scripts
        if prog == "eval":
            scripts.append(" ".join(args))
            return [], scripts
        if prog == "find":
            # find ... -exec cmd {} ; -> cmd. find itself is otherwise ungoverned.
            j = 0
            while j < len(args):
                if args[j] in ("-exec", "-execdir", "-ok", "-okdir"):
                    k = j + 1
                    sub = []
                    while k < len(args) and args[k] not in (";", "+", "\\;"):
                        sub.append(args[k])
                        k += 1
                    if sub:
                        scripts.append(_quote_join(sub))
                    j = k + 1
                    continue
                j += 1
            return words, scripts
        return words, scripts
    return words, scripts


def _quote_join(words: List[str]) -> str:
    return " ".join("'" + w.replace("'", "'\\''") + "'" for w in words)


def expand_path(path: str, cwd: str, home: str) -> str:
    p = path
    if p == "~" or p.startswith("~/"):
        p = home + p[1:]
    p = re.sub(r"^\$\{?HOME\}?", lambda _m: home, p)
    if not os.path.isabs(p):
        p = os.path.join(cwd, p)
    return os.path.normpath(p)


def _is_marker(name: str) -> bool:
    return name in ("CLAUDECODE", "GEMINI_CLI") or name.startswith("ANTIGRAVITY_")


def hides_agent_marker(words: List[str]) -> bool:
    """Does this simple command unset or blank an agent marker for what it runs?

    Looks at the parsed words, not the text, so `grep 'unset CLAUDECODE'` is
    just a grep. Catches `CLAUDECODE= cmd`, `env -u CLAUDECODE cmd`,
    `env --unset=CLAUDECODE`, `env -i cmd`, `unset CLAUDECODE` and
    `export -n CLAUDECODE`.
    """
    i = 0
    while i < len(words) and ASSIGN_RE.match(words[i]):
        if _is_marker(words[i].split("=", 1)[0]):
            return True
        i += 1
    if i >= len(words):
        return False
    prog = os.path.basename(words[i])
    args = words[i + 1 :]
    if prog == "env":
        j = 0
        while j < len(args):
            a = args[j]
            if a in ("-u", "--unset") and j + 1 < len(args) and _is_marker(args[j + 1]):
                return True
            if a.startswith("--unset=") and _is_marker(a.split("=", 1)[1]):
                return True
            if a.startswith("-u") and len(a) > 2 and _is_marker(a[2:]):
                return True
            if a in ("-i", "--ignore-environment", "-"):
                return True
            if ASSIGN_RE.match(a):
                if _is_marker(a.split("=", 1)[0]):
                    return True
            elif not a.startswith("-"):
                break
            j += 1
        return False
    if prog == "unset":
        return any(_is_marker(a) for a in args if not a.startswith("-"))
    if prog == "export" and "-n" in args:
        return any(_is_marker(a) for a in args if not a.startswith("-"))
    return False


def invocations(text: str, cwd: str, home: str) -> List[Invocation]:
    """Every program the command text would run, in order, with its directory."""
    out: List[Invocation] = []
    state = {"cwd": cwd}
    budget = [MAX_COMMANDS]

    def walk(script: str, depth: int) -> None:
        if depth > 6:
            return
        try:
            cmds = parse_script(script, 0, budget)
        except ParseError:
            cmds = fallback_split(script, budget)
        for cmd in cmds:
            hidden = hides_agent_marker(cmd.words)
            argv, scripts = _unwrap(list(cmd.words), cmd, depth)
            if argv:
                prog = os.path.basename(argv[0])
                if prog in ("cd", "pushd") and len(argv) >= 2:
                    target = [a for a in argv[1:] if not a.startswith("-")]
                    if target:
                        state["cwd"] = expand_path(target[0], state["cwd"], home)
                    continue
                out.append(Invocation(argv, state["cwd"], cmd.redirects, hidden))
            elif cmd.redirects or hidden:
                out.append(Invocation([":"], state["cwd"], cmd.redirects, hidden))
            for s in scripts:
                walk(s, depth + 1)

    walk(text, 0)
    return out


# ---------------------------------------------------------------------------
# Scope: is a directory inside a vitruvian-core checkout or worktree?
# ---------------------------------------------------------------------------
_scope_cache: Dict[str, Optional[str]] = {}


_root_cache: Dict[str, Optional[str]] = {}


def repo_root_of(path: str) -> Optional[str]:
    """The vitruvian-core root containing path (the path need not exist)."""
    if path in _root_cache:
        return _root_cache[path]
    root = _repo_root_of(path)
    _root_cache[path] = root
    return root


def _repo_root_of(path: str) -> Optional[str]:
    p = os.path.abspath(path)
    while not os.path.isdir(p):
        parent = os.path.dirname(p)
        if parent == p:
            return None
        p = parent
    probe = p
    seen = []
    while True:
        if probe in _scope_cache:
            res = _scope_cache[probe]
            for s in seen:
                _scope_cache[s] = res
            return res
        seen.append(probe)
        module = os.path.join(probe, "MODULE.bazel")
        if os.path.isfile(module):
            try:
                with open(module, "r", encoding="utf-8", errors="replace") as fh:
                    head = fh.read(8192)
            except OSError:
                head = ""
            if MODULE_NAME_RE.search(head):
                for s in seen:
                    _scope_cache[s] = probe
                return probe
        parent = os.path.dirname(probe)
        if parent == probe:
            for s in seen:
                _scope_cache[s] = None
            return None
        probe = parent


# ---------------------------------------------------------------------------
# Git state (for in-progress merges, rebases and cherry-picks).
# ---------------------------------------------------------------------------
class GitState(object):
    def __init__(
        self,
        merge: bool = False,
        rebase: bool = False,
        cherry_pick: bool = False,
        unmerged: Optional[List[str]] = None,
        primary: bool = True,
    ):
        self.merge = merge
        self.rebase = rebase
        self.cherry_pick = cherry_pick
        self.unmerged = unmerged or []  # absolute paths of conflicted files
        self.primary = primary

    @property
    def in_progress(self) -> bool:
        return self.merge or self.rebase or self.cherry_pick


def _git(cwd: str, args: List[str]) -> Optional[str]:
    env = dict(os.environ)
    env["GIT_OPTIONAL_LOCKS"] = "0"
    try:
        r = subprocess.run(
            ["git", "-C", cwd] + args,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            env=env,
            timeout=3,
        )
    except (OSError, subprocess.SubprocessError):
        return None
    if r.returncode != 0:
        return None
    return r.stdout.decode("utf-8", "replace")


def probe_git_state(cwd: str) -> GitState:
    """Ask git where its state files live (worktree aware) and which exist."""
    names = [
        "MERGE_HEAD",
        "REBASE_HEAD",
        "rebase-merge",
        "rebase-apply",
        "CHERRY_PICK_HEAD",
    ]
    args = [
        "rev-parse",
        "--path-format=absolute",
        "--show-toplevel",
        "--git-dir",
        "--git-common-dir",
    ]
    for name in names:
        args += ["--git-path", name]
    out = _git(cwd, args)
    if out is None:
        return GitState()
    lines = out.splitlines()
    if len(lines) < 3 + len(names):
        return GitState()
    top, git_dir, common = lines[0], lines[1], lines[2]
    paths = dict(zip(names, lines[3:]))
    st = GitState(
        merge=os.path.exists(paths["MERGE_HEAD"]),
        rebase=any(
            os.path.exists(paths[k])
            for k in ("REBASE_HEAD", "rebase-merge", "rebase-apply")
        ),
        cherry_pick=os.path.exists(paths["CHERRY_PICK_HEAD"]),
        primary=os.path.normpath(git_dir) == os.path.normpath(common),
    )
    if st.in_progress:
        listing = _git(top, ["ls-files", "-u", "-z"])
        if listing:
            files = set()
            for rec in listing.split("\0"):
                if "\t" in rec:
                    files.add(
                        os.path.realpath(os.path.join(top, rec.split("\t", 1)[1]))
                    )
            st.unmerged = sorted(files)
    return st


# ---------------------------------------------------------------------------
# Classifiers. Each returns a Verdict (blocked) or None (allowed).
# ---------------------------------------------------------------------------
class Context(object):
    def __init__(self, home: str, git_state: Callable[[str], GitState]):
        self.home = home
        self.git_state = git_state
        self._cache: Dict[str, GitState] = {}

    def state(self, cwd: str) -> GitState:
        if cwd not in self._cache:
            self._cache[cwd] = self.git_state(cwd)
        return self._cache[cwd]


GIT_READ_ONLY = {
    "status",
    "log",
    "diff",
    "show",
    "fetch",
    "rev-parse",
    "ls-files",
    "ls-tree",
    "ls-remote",
    "grep",
    "blame",
    "annotate",
    "shortlog",
    "describe",
    "rev-list",
    "merge-base",
    "cat-file",
    "for-each-ref",
    "show-ref",
    "name-rev",
    "whatchanged",
    "range-diff",
    "diff-tree",
    "diff-files",
    "diff-index",
    "check-ignore",
    "check-attr",
    "check-ref-format",
    "count-objects",
    "var",
    "version",
    "help",
    "format-patch",
    "archive",
    "verify-commit",
    "verify-tag",
    "show-branch",
    "cherry",
    "merge-tree",
    "fsck",
    "column",
    "difftool",
    "restore",
    "get-tar-commit-id",
    "check-mailmap",
    "show-index",
    "unpack-file",
}
GIT_GLOBAL_WITH_ARG = {
    "-C",
    "-c",
    "--git-dir",
    "--work-tree",
    "--namespace",
    "--super-prefix",
    "--config-env",
    "--exec-path",
    "--list-cmds",
}


def _has(args: Sequence[str], *flags: str) -> bool:
    for a in args:
        for f in flags:
            if a == f or (f.startswith("--") and a.startswith(f + "=")):
                return True
    return False


def _short_cluster_has(args: Sequence[str], letters: str) -> bool:
    for a in args:
        if a.startswith("-") and not a.startswith("--") and len(a) > 1:
            if any(ch in letters for ch in a[1:]):
                return True
    return False


def _positionals(args: Sequence[str], with_arg: Sequence[str] = ()) -> List[str]:
    out = []
    i = 0
    while i < len(args):
        a = args[i]
        if a == "--":
            out.extend(args[i + 1 :])
            break
        if a.startswith("-") and a != "-":
            if a in with_arg:
                i += 2
                continue
            i += 1
            continue
        out.append(a)
        i += 1
    return out


# git fetch options that take a separate value.
_FETCH_WITH_ARG = (
    "--depth",
    "--deepen",
    "--shallow-since",
    "--shallow-exclude",
    "--negotiation-tip",
    "--refmap",
    "--upload-pack",
    "-j",
    "--jobs",
    "-o",
    "--server-option",
    "--recurse-submodules-default",
    "--submodule-prefix",
    "--filter",
    "-s",
    "--strategy",
    "-X",
    "--strategy-option",
)


def _fetch_into_named_ref(verb: str, vargs: List[str], config: List[str]) -> str:
    """What makes this fetch (or pull) write a ref it names, or "" if nothing does.

    hook.sh runs the guard from origin/main, so a fetch that can point
    refs/remotes/origin/main (or a branch) at other code must not slip through
    as a read: an explicit `src:dst` refspec, `--refmap`, or a config override
    of a remote or of URL rewriting. The remote's own refspec only ever writes
    its own refs/remotes/<name>/, so plain fetches stay allowed.
    """
    for c in config:
        key = c.split("=", 1)[0].lower()
        if key.startswith("remote.") or key.startswith("url."):
            return "-c %s" % key
    for i, a in enumerate(vargs):
        if a == "--refmap" and i + 1 < len(vargs) and vargs[i + 1]:
            return "--refmap"
        if a.startswith("--refmap=") and a.split("=", 1)[1]:
            return "--refmap"
    if _has(vargs, "--multiple", "--all"):
        return ""  # every argument is a remote or group, none is a refspec
    pos = _positionals(vargs, _FETCH_WITH_ARG)
    for spec in pos[1:]:
        dst = spec.lstrip("+").split(":", 1)
        if len(dst) == 2 and dst[1]:
            return spec
    return ""


def classify_git(inv: Invocation, ctx: Context) -> Tuple[Optional[Verdict], str]:
    """Returns (verdict, effective cwd)."""
    args = inv.argv[1:]
    cwd = inv.cwd
    config: List[str] = []  # -c / --config-env settings, for fetch and pull
    i = 0
    while i < len(args):
        a = args[i]
        if not a.startswith("-"):
            break
        name = a.split("=", 1)[0]
        val = (
            a.split("=", 1)[1]
            if "=" in a
            else (args[i + 1] if i + 1 < len(args) else "")
        )
        if name in ("-c", "--config-env"):
            config.append(val)
        if name in ("-C",):
            cwd = expand_path(val, cwd, ctx.home)
        elif name == "--work-tree":
            cwd = expand_path(val, cwd, ctx.home)
        elif name == "--git-dir":
            gd = expand_path(val, cwd, ctx.home)
            cwd = os.path.dirname(gd) if os.path.basename(gd) == ".git" else gd
        if name in GIT_GLOBAL_WITH_ARG and "=" not in a:
            i += 2
        else:
            i += 1
    rest = args[i:]
    if not rest:
        return None, cwd
    verb, vargs = rest[0], rest[1:]
    op = "git " + verb
    if (
        verb in ("--version", "--help", "-h", "version", "help")
        or "--help" in vargs
        or vargs == ["-h"]
    ):
        return None, cwd
    if verb in ("fetch", "pull"):
        hijack = _fetch_into_named_ref(verb, vargs, config)
        if hijack:
            return V(
                "git-other",
                "git %s %s" % (verb, hijack),
                None,
                "A fetch that names where it writes (a `src:dst` refspec, `--refmap`, or a "
                "`-c remote.*`/`url.*` override) can move origin/main, and agent-guard's hook "
                "runs the guard from origin/main. `git fetch`, `git fetch origin` and "
                "`git fetch origin main` are fine.",
            ), cwd
    if verb in GIT_READ_ONLY:
        return None, cwd

    if verb in ("add", "rm", "mv"):
        if verb == "add":
            st = ctx.state(cwd)
            if st.in_progress:
                paths = _positionals(vargs, ("--chmod", "--pathspec-from-file"))
                bulk = _has(
                    vargs,
                    "-A",
                    "--all",
                    "-u",
                    "--update",
                    "--pathspec-from-file",
                    "-p",
                    "--patch",
                    "-i",
                    "--interactive",
                )
                if paths and not bulk:
                    absolute = [os.path.realpath(os.path.join(cwd, p)) for p in paths]
                    conflicted = {os.path.realpath(p) for p in st.unmerged}
                    if all(p in conflicted for p in absolute):
                        return None, cwd
                return V(
                    "git-commit",
                    op,
                    T_COMMIT,
                    "While a merge, rebase or cherry-pick is in progress you may `git add` the conflicted files by name; that is all.",
                ), cwd
        return V("git-commit", op, T_COMMIT), cwd
    if verb == "commit":
        st = ctx.state(cwd)
        if st.merge:
            return V(
                "git-commit",
                "git commit",
                T_COMMIT,
                "A merge is in progress (MERGE_HEAD): //tools/git:commit concludes it once the conflicts are resolved and added.",
            ), cwd
        return V("git-commit", op, T_COMMIT), cwd
    if verb == "push":
        return V("git-push", op, T_PUSH), cwd
    if verb == "pull":
        if (
            _has(vargs, "--ff-only")
            and not _has(vargs, "--rebase", "-r", "--no-ff")
            and ctx.state(cwd).primary
        ):
            return None, cwd
        return V(
            "git-history",
            op,
            T_SYNC,
            "Only `git pull --ff-only` in the primary checkout is allowed directly.",
        ), cwd
    if verb == "rebase":
        if _has(vargs, "--show-current-patch"):
            return None, cwd
        if (
            vargs
            and vargs[0] in ("--continue", "--abort", "--skip")
            and ctx.state(cwd).rebase
        ):
            return None, cwd
        return V("git-history", op, T_SYNC), cwd
    if verb == "merge":
        if vargs and vargs[0] in ("--continue", "--abort") and ctx.state(cwd).merge:
            return None, cwd
        return V("git-history", op, T_SYNC), cwd
    if verb == "cherry-pick":
        if (
            vargs
            and vargs[0] in ("--continue", "--abort")
            and ctx.state(cwd).cherry_pick
        ):
            return None, cwd
        return V("git-history", op), cwd
    if verb in (
        "reset",
        "revert",
        "am",
        "bisect",
        "replace",
        "filter-branch",
        "filter-repo",
    ):
        return V("git-history", op), cwd
    if verb == "stash":
        if vargs and vargs[0] in ("list", "show"):
            return None, cwd
        return V(
            "git-stash",
            "git stash",
            None,
            "git stash is shared by every worktree, so it is banned outright: commit work in progress with "
            "`bazel run //tools/git:commit` on your branch, or work in a separate worktree.",
        ), cwd
    if verb == "tag":
        write = _has(
            vargs,
            "-d",
            "--delete",
            "-a",
            "--annotate",
            "-s",
            "--sign",
            "-m",
            "--message",
            "-F",
            "--file",
            "-f",
            "--force",
            "-u",
            "--local-user",
        )
        listing = _has(
            vargs,
            "-l",
            "--list",
            "-n",
            "--contains",
            "--no-contains",
            "--points-at",
            "--merged",
            "--no-merged",
            "-v",
            "--verify",
        )
        pos = _positionals(
            vargs,
            (
                "--contains",
                "--no-contains",
                "--points-at",
                "--merged",
                "--no-merged",
                "--sort",
                "--format",
                "-n",
                "-m",
                "-F",
                "-u",
            ),
        )
        if not write and (listing or not pos):
            return None, cwd
        return V(
            "git-history",
            "git tag",
            None,
            "Releases are tagged by release-please, not by hand.",
        ), cwd
    if verb == "branch":
        write_long = _has(
            vargs,
            "--delete",
            "--move",
            "--copy",
            "--force",
            "--set-upstream-to",
            "--unset-upstream",
            "--edit-description",
            "--track",
            "--no-track",
            "--create-reflog",
            "--recurse-submodules",
        )
        write_short = _short_cluster_has(vargs, "dDmMcCfut")
        if write_long or write_short:
            if _has(vargs, "-d", "-D", "--delete") or _short_cluster_has(vargs, "dD"):
                return V("git-branch", "git branch -d", T_WT_DELETE_BRANCH), cwd
            return V("git-branch", op, T_WT_NEW), cwd
        listing = _has(
            vargs, "-l", "--list", "-a", "--all", "-r", "--remotes", "--show-current"
        ) or _short_cluster_has(vargs, "lar")
        pos = _positionals(
            vargs,
            (
                "--contains",
                "--no-contains",
                "--merged",
                "--no-merged",
                "--points-at",
                "--sort",
                "--format",
                "--abbrev",
                "--color",
            ),
        )
        if pos and not listing:
            return V("git-branch", "git branch <name>", T_WT_NEW), cwd
        return None, cwd
    if verb == "checkout":
        if _has(vargs, "-b", "-B", "--orphan") or _short_cluster_has(
            [a for a in vargs if a not in ("-p",)], "bB"
        ):
            return V("git-branch", "git checkout -b", T_WT_NEW), cwd
        if _has(vargs, "--detach"):
            return V("git-branch", "git checkout --detach", T_WT_DETACH), cwd
        if "--" in vargs or _has(vargs, "-p", "--patch", "--pathspec-from-file"):
            return None, cwd
        pos = _positionals(vargs, ("--conflict",))
        if not pos:
            return None, cwd
        for p in pos:
            if os.path.lexists(os.path.join(cwd, p)):
                return None, cwd  # restoring a file
        return V(
            "git-branch",
            "git checkout <branch>",
            T_WT_NEW,
            "Switching branches in a shared checkout breaks other sessions; each branch gets its own worktree. "
            "To restore files, use `git checkout -- <path>` or `git restore <path>`.",
        ), cwd
    if verb == "switch":
        return V(
            "git-branch",
            "git switch",
            T_WT_NEW,
            "Switching branches in a shared checkout breaks other sessions; each branch gets its own worktree.",
        ), cwd
    if verb == "worktree":
        sub = vargs[0] if vargs else ""
        if sub in ("list", ""):
            return None, cwd
        if sub == "add":
            if _has(vargs, "--detach", "-d"):
                return V("git-worktree", "git worktree add --detach", T_WT_DETACH), cwd
            return V("git-worktree", "git worktree add", T_WT_NEW), cwd
        if sub == "remove":
            return V("git-worktree", "git worktree remove", T_WT_REMOVE), cwd
        if sub == "prune":
            return V("git-worktree", "git worktree prune", T_WT_PRUNE), cwd
        if sub in ("lock", "unlock"):
            return V("git-worktree", "git worktree " + sub, T_WT_LOCK), cwd
        return V("git-worktree", "git worktree " + sub), cwd
    if verb == "config":
        sub = vargs[0] if vargs else ""
        if sub in ("get", "list"):
            return None, cwd
        if _has(
            vargs,
            "--get",
            "--get-all",
            "--get-regexp",
            "--get-urlmatch",
            "-l",
            "--list",
            "--get-color",
            "--get-colorbool",
        ):
            return None, cwd
        write = _has(
            vargs,
            "--unset",
            "--unset-all",
            "--add",
            "--replace-all",
            "--edit",
            "-e",
            "--rename-section",
            "--remove-section",
        ) or sub in ("set", "unset", "edit", "rename-section", "remove-section")
        pos = _positionals(
            vargs, ("--file", "-f", "--blob", "--type", "--default", "--comment")
        )
        if not write and len(pos) == 1:
            return None, cwd
        return V("git-other", "git config (write)"), cwd
    if verb == "remote":
        sub = vargs[0] if vargs else ""
        if sub in ("", "-v", "--verbose", "show", "get-url"):
            return None, cwd
        return V("git-other", "git remote " + sub), cwd
    if verb == "apply":
        # Applying a patch to the working tree is like editing files: allowed.
        # Applying it to the index is staging, which //tools/git:commit owns.
        if _has(vargs, "--index", "--cached", "-3", "--3way"):
            return V("git-commit", "git apply --index", T_COMMIT), cwd
        return None, cwd
    if verb == "clean":
        if (
            _has(vargs, "-n", "--dry-run") or _short_cluster_has(vargs, "n")
        ) and not _has(vargs, "-i", "--interactive"):
            return None, cwd
        return V(
            "git-other", "git clean", None, "`git clean -n` (dry run) is allowed."
        ), cwd
    if verb == "reflog":
        sub = vargs[0] if vargs else ""
        if sub in ("", "show", "exists", "list") or sub.startswith("-"):
            return None, cwd
        return V("git-other", "git reflog " + sub), cwd
    if verb == "notes":
        if vargs[:1] in (["list"], ["show"], []):
            return None, cwd
        return V("git-other", "git notes"), cwd
    if verb == "submodule":
        if vargs[:1] in (["status"], ["summary"], []):
            return None, cwd
        return V("git-other", "git submodule " + vargs[0]), cwd
    if verb == "lfs":
        if vargs[:1] in (["ls-files"], ["status"], ["env"], ["version"], []):
            return None, cwd
        return V("git-other", "git lfs " + vargs[0]), cwd
    if verb == "sparse-checkout":
        if vargs[:1] == ["list"]:
            return None, cwd
        return V("git-other", "git sparse-checkout"), cwd
    if verb == "symbolic-ref":
        if len(_positionals(vargs)) <= 1 and not _has(vargs, "-d", "--delete"):
            return None, cwd
        return V("git-other", "git symbolic-ref (write)"), cwd
    if verb == "hash-object":
        if not _has(vargs, "-w"):
            return None, cwd
    return V("git-other", op), cwd


GH_READ_SUBS = {
    "view",
    "list",
    "status",
    "diff",
    "checks",
    "get",
    "check",
    "verify",
    "item-list",
    "field-list",
    "token",
    "watch",
    "download",
    "search",
}


def _gh_strip(args: List[str]) -> Tuple[List[str], Optional[str]]:
    out = []
    repo = None
    i = 0
    while i < len(args):
        a = args[i]
        if a in ("-R", "--repo") and i + 1 < len(args):
            repo = args[i + 1]
            i += 2
            continue
        if a.startswith("--repo="):
            repo = a.split("=", 1)[1]
            i += 1
            continue
        if a.startswith("-R") and len(a) > 2:
            repo = a[2:]
            i += 1
            continue
        out.append(a)
        i += 1
    return out, repo


_GH_URL_RE = re.compile(r"(?i)github\.com[/:]([^/\s]+)/([^/\s#?]+)")
_GH_API_REPO_RE = re.compile(r"^/?repos/([^/\s]+)/([^/\s?]+)")


def gh_target_repo(args: List[str]) -> Optional[str]:
    """The owner/name a gh command explicitly targets, or None if it names none."""
    rest, repo = _gh_strip(args)
    if repo:
        m = _GH_URL_RE.search(repo)
        if m:
            return "%s/%s" % (m.group(1), re.sub(r"\.git$", "", m.group(2)))
        parts = [p for p in repo.split("/") if p]
        if len(parts) >= 2:
            return "%s/%s" % (parts[-2], parts[-1])
        return repo
    for a in rest:
        m = _GH_URL_RE.search(a)
        if m:
            return "%s/%s" % (m.group(1), re.sub(r"\.git$", "", m.group(2)))
    if rest[:1] == ["api"]:
        for a in rest[1:]:
            m = _GH_API_REPO_RE.match(a)
            if m:
                owner, name = m.group(1), m.group(2)
                if owner.startswith(("{", ":")) or name.startswith(("{", ":")):
                    return None  # {owner}/{repo}: the current directory's repo
                return "%s/%s" % (owner, name)
    return None


def is_vitruvian_core_slug(slug: str) -> bool:
    return slug.lower() == "vitruviansoftware/vitruvian-core"


_MUTATION_RE = re.compile(r"(^|[\s{}])mutation(\s|\(|\{|$)")


def _graphql_query_text(args: List[str], cwd: str) -> Optional[str]:
    """The query text of `gh api graphql`, or None if it cannot be read."""
    texts = []
    i = 0
    found = False
    while i < len(args):
        a = args[i]
        val = None
        if a in ("-f", "-F", "--field", "--raw-field") and i + 1 < len(args):
            val = args[i + 1]
            i += 2
        elif a.startswith("--field=") or a.startswith("--raw-field="):
            val = a.split("=", 1)[1]
            i += 1
        elif a.startswith("-f") or a.startswith("-F"):
            val = a[2:] if len(a) > 2 else None
            i += 1
        elif a == "--input":
            return None
        else:
            i += 1
        if val and val.startswith("query="):
            found = True
            q = val[len("query=") :]
            if q.startswith("@"):
                src = q[1:]
                if src == "-":
                    return None
                try:
                    with open(
                        os.path.join(cwd, src), "r", encoding="utf-8", errors="replace"
                    ) as fh:
                        q = fh.read()
                except OSError:
                    return None
            texts.append(q)
    if not found:
        return ""
    return "\n".join(texts)


def classify_gh_api(args: List[str], cwd: str) -> Optional[Verdict]:
    method = None
    fields = False
    has_input = False
    i = 0
    while i < len(args):
        a = args[i]
        if a in ("-X", "--method") and i + 1 < len(args):
            method = args[i + 1].upper()
            i += 2
            continue
        if a.startswith("--method="):
            method = a.split("=", 1)[1].upper()
        elif a.startswith("-X") and len(a) > 2:
            method = a[2:].upper()
        elif (
            a in ("-f", "-F", "--field", "--raw-field")
            or a.startswith("--field=")
            or a.startswith("--raw-field=")
            or re.match(r"^-[fF].", a)
        ):
            fields = True
        elif a == "--input" or a.startswith("--input="):
            has_input = True
        i += 1
    pos = _positionals(
        args,
        (
            "-X",
            "--method",
            "-f",
            "-F",
            "--field",
            "--raw-field",
            "-H",
            "--header",
            "--input",
            "-q",
            "--jq",
            "-t",
            "--template",
            "--cache",
            "--hostname",
            "-p",
            "--preview",
        ),
    )
    endpoint = pos[0] if pos else ""
    if endpoint == "graphql":
        q = _graphql_query_text(args, cwd)
        if q is None:
            return V(
                "gh-api",
                "gh api graphql",
                None,
                "agent-guard could not read the query (stdin or --input), so it cannot tell a read from a mutation; "
                "pass the query inline with -f query=... to run a read.",
            )
        if _MUTATION_RE.search(q):
            return V("gh-api", "gh api graphql mutation")
        return None
    if method in (None, "GET", "HEAD"):
        # gh switches to POST when fields or --input are given, unless -X GET.
        if method is None and (fields or has_input):
            return V("gh-api", "gh api (POST)")
        return None
    return V("gh-api", "gh api -X " + method)


def classify_gh(inv: Invocation) -> Optional[Verdict]:
    args, _repo = _gh_strip(inv.argv[1:])
    if (
        not args
        or args[0] in ("--version", "version", "help", "--help", "-h")
        or "--help" in args
    ):
        return None
    group = args[0]
    sub = args[1] if len(args) > 1 else ""
    if group == "api":
        return classify_gh_api(args[1:], inv.cwd)
    if group == "pr":
        if sub in ("view", "list", "checks", "diff", "status", ""):
            return None
        if sub == "create":
            return V("gh-pr", "gh pr create", T_PR_CREATE)
        if sub == "merge":
            note = "It arms auto-merge through the merge queue; never --admin."
            return V("gh-pr", "gh pr merge", T_PR_ENQUEUE, note)
        if sub in ("edit", "comment", "ready"):
            return V(
                "gh-pr",
                "gh pr " + sub,
                None,
                "`bazel run //tools/agent-app -- pr-%s` is planned but not built yet."
                % sub,
            )
        if sub == "checkout":
            return V("git-branch", "gh pr checkout", T_WT_NEW)
        return V("gh-pr", "gh pr " + sub)
    if group == "issue":
        # Issues are allowed (and logged): they are notes, not repo changes.
        if sub in ("delete", "transfer"):
            return V("gh-other", "gh issue " + sub)
        return None
    if group == "run":
        if sub in ("view", "list", "watch", "download", ""):
            return None
        if sub == "rerun":
            return V("gh-run", "gh run rerun", T_RUN_RERUN, RUN_NOTE)
        if sub == "cancel":
            return V("gh-run", "gh run cancel", T_RUN_CANCEL, RUN_NOTE)
        return V("gh-run", "gh run " + sub, None, RUN_NO_TARGET_NOTE)
    if group == "workflow":
        if sub in ("view", "list", ""):
            return None
        if sub == "run":
            return V(
                "gh-run",
                "gh workflow run",
                T_WORKFLOW_RUN,
                "It starts only workflows in tools/agent-app/workflow-allowlist.txt, "
                "in this repository. " + RUN_NOTE,
            )
        return V("gh-run", "gh workflow " + sub, None, RUN_NO_TARGET_NOTE)
    if group in ("search", "browse", "status", "completion"):
        return None
    if group == "auth":
        if sub in ("status", "token"):
            return None
        return V("gh-other", "gh auth " + sub)
    if group == "repo" and sub in ("view", "list"):
        return None
    if group == "release" and sub in ("view", "list", "download"):
        return None
    if group in ("config", "variable") and sub in ("get", "list"):
        return None
    if sub in GH_READ_SUBS or sub == "":
        return None
    return V("gh-other", "gh %s %s" % (group, sub))


def _first_sub(args: List[str], with_arg: Sequence[str] = ()) -> str:
    pos = _positionals(args, with_arg)
    return pos[0] if pos else ""


def _version_only(args: List[str]) -> bool:
    return any(
        a in ("--version", "-version", "-V", "version", "--help", "-h", "help")
        for a in args[:1]
    ) or (len(args) == 1 and args[0] in ("-v",))


GO_READ = {"version", "env", "list", "doc", "help", "tool"}
NODE_PROGS = {"npm", "pnpm", "npx", "yarn", "bun", "bunx", "corepack", "pnpx"}
NODE_READ = {
    "view",
    "info",
    "show",
    "v",
    "ls",
    "list",
    "la",
    "ll",
    "why",
    "outdated",
    "help",
    "config",
    "get",
    "root",
    "bin",
    "prefix",
    "search",
    "explain",
    "audit",
    "docs",
    "repo",
    "bugs",
    "licenses",
    "store",
    "whoami",
    "ping",
    "doctor",
    "query",
    "pkg",
}
LINTERS = {
    "gofmt",
    "goimports",
    "golangci-lint",
    "ruff",
    "black",
    "isort",
    "flake8",
    "pylint",
    "mypy",
    "eslint",
    "prettier",
    "biome",
    "oxlint",
    "stylelint",
    "markdownlint",
    "markdownlint-cli2",
    "yamllint",
    "swiftformat",
    "swift-format",
    "swiftlint",
    "ktlint",
    "ktfmt",
    "shfmt",
    "buildifier",
    "buildozer",
    "clang-format",
    "rustfmt",
    "taplo",
    "shellcheck",
}
FORMATTERS = {
    "gofmt",
    "goimports",
    "black",
    "isort",
    "prettier",
    "swiftformat",
    "swift-format",
    "ktfmt",
    "shfmt",
    "buildifier",
    "clang-format",
    "rustfmt",
    "taplo",
}
KUBECTL_READ = {
    "get",
    "describe",
    "logs",
    "log",
    "top",
    "explain",
    "api-resources",
    "api-versions",
    "version",
    "auth",
    "events",
    "wait",
    "diff",
    "cluster-info",
    "kustomize",
    "port-forward",
    "completion",
    "plugin",
    "options",
    "help",
    "",
}
HELM_READ = {
    "template",
    "lint",
    "list",
    "ls",
    "status",
    "get",
    "history",
    "show",
    "inspect",
    "search",
    "version",
    "env",
    "repo",
    "dependency",
    "dep",
    "help",
    "verify",
    "completion",
    "",
}
PULUMI_READ = {"version", "whoami", "about", "help", "logs", "plugin", ""}


def classify_tool(inv: Invocation, ctx: Context) -> Tuple[Optional[Verdict], str]:
    """Classify one invocation. Returns (verdict, the directory that sets its scope)."""
    prog = inv.prog
    args = inv.argv[1:]
    cwd = inv.cwd

    if prog == "git":
        return classify_git(inv, ctx)
    if prog == "gh":
        return classify_gh(inv), cwd

    if prog in ("bazel", "bazelisk", "aspect", "ibazel"):
        return classify_bazel(args, cwd, ctx.home), cwd

    if prog == "go":
        sub = args[0] if args else ""
        if _version_only(args) or sub in GO_READ:
            return None, cwd
        if (
            sub == "mod"
            and len(args) > 1
            and args[1] in ("why", "graph", "verify", "help")
        ):
            return None, cwd
        if sub in ("test", "vet"):
            return V("go", "go " + sub, T_BAZEL_TEST), cwd
        if sub in ("build", "run", "install"):
            return V("go", "go " + sub, T_BAZEL_BUILD), cwd
        if sub == "fmt":
            return V("go", "go fmt", T_FORMAT), cwd
        if sub in ("mod", "get", "work"):
            return V(
                "go",
                "go " + " ".join(args[:2]),
                (
                    "bazel run //tools/gomod:tidy (and bazel run //:gazelle for BUILD files)",
                    None,
                ),
            ), cwd
        return V("go", "go " + sub), cwd

    if prog in ("swift", "swiftc"):
        sub = args[0] if args else ""
        if _version_only(args):
            return None, cwd
        if (
            prog == "swift"
            and sub == "package"
            and len(args) > 1
            and args[1] in ("describe", "dump-package", "show-dependencies", "--help")
        ):
            return None, cwd
        if sub == "test":
            return V(
                "swift",
                "swift test",
                (
                    "bazel test //apps/desktop/<app>:<Tests> (macOS-only targets are tagged manual)",
                    None,
                ),
            ), cwd
        if sub in ("build", "run", "package") or prog == "swiftc":
            return V("swift", (prog + " " + sub).strip(), T_BAZEL_BUILD), cwd
        if sub in ("format", "lint"):
            return V("lint", "swift " + sub, T_FORMAT), cwd
        return V("swift", (prog + " " + sub).strip()), cwd

    if prog == "xcodebuild":
        if any(
            a
            in (
                "-version",
                "-showsdks",
                "-list",
                "-help",
                "-usage",
                "-showBuildSettings",
                "-showdestinations",
            )
            for a in args
        ):
            return None, cwd
        return V(
            "xcode",
            "xcodebuild",
            (
                "bazel build / bazel test the app's targets (--config=macos-app for .app bundles)",
                None,
            ),
        ), cwd
    if prog == "xcrun":
        tool_args = _skip_opts(args, ("--sdk", "-sdk", "--toolchain", "-toolchain"))
        tool = tool_args[0] if tool_args else ""
        if tool in ("notarytool", "stapler", "altool"):
            return V(
                "xcode",
                "xcrun " + tool,
                (
                    "bazel run //tools/desktop-package (packaging and notarization targets)",
                    None,
                ),
            ), cwd
        if tool in ("xcodebuild", "swift", "swiftc"):
            sub = Invocation([tool] + tool_args[1:], cwd, inv.redirects)
            return classify_tool(sub, ctx)
        return None, cwd

    if prog in NODE_PROGS:
        sub = _first_sub(
            args,
            ("--prefix", "-C", "--dir", "--filter", "-F", "--workspace", "-w", "--cwd"),
        )
        if _version_only(args) or (
            prog not in ("npx", "bunx", "pnpx") and sub in NODE_READ
        ):
            return None, cwd
        if prog in ("npx", "bunx", "pnpx") or sub in ("exec", "dlx", "x", "create"):
            return V(
                "node",
                prog + (" " + sub if prog not in ("npx", "bunx", "pnpx") else ""),
                (
                    "a Bazel target (bazel run //<package>:<binary>); tools on PATH come from bazel run //tools:bazel_env",
                    None,
                ),
            ), cwd
        if sub in (
            "test",
            "t",
            "tst",
            "run",
            "run-script",
            "rum",
            "urn",
            "start",
            "build",
            "lint",
            "typecheck",
            "dev",
        ) or (
            prog in ("yarn", "bun")
            and sub not in NODE_READ
            and sub not in ("install", "add", "remove", "upgrade", "up", "i")
        ):
            return V(
                "node",
                "%s %s" % (prog, sub),
                (
                    "bazel test //<package>:<test> or bazel run //<package>:<binary>",
                    None,
                ),
            ), cwd
        if sub in (
            "install",
            "i",
            "ci",
            "add",
            "remove",
            "rm",
            "uninstall",
            "un",
            "update",
            "up",
            "upgrade",
            "dedupe",
            "prune",
            "rebuild",
            "link",
            "unlink",
            "import",
            "patch",
            "patch-commit",
            "install-test",
            "it",
            "",
        ):
            return V(
                "node",
                "%s %s" % (prog, sub or "install"),
                None,
                "Bazel (rules_js) installs node_modules itself when you bazel build or bazel test.",
            ), cwd
        if sub in (
            "publish",
            "pack",
            "version",
            "deprecate",
            "dist-tag",
            "unpublish",
            "owner",
            "access",
            "token",
            "login",
            "logout",
            "adduser",
        ):
            return V(
                "node",
                "%s %s" % (prog, sub),
                None,
                "Packages are published by the release pipeline.",
            ), cwd
        return V("node", "%s %s" % (prog, sub)), cwd

    if prog == "cargo":
        sub = _first_sub(
            args, ("--manifest-path", "-p", "--package", "-Z", "--config", "-C")
        )
        if _version_only(args) or sub in (
            "metadata",
            "tree",
            "search",
            "help",
            "locate-project",
            "pkgid",
            "read-manifest",
            "verify-project",
        ):
            return None, cwd
        if sub in ("test", "t", "bench", "check", "c", "clippy"):
            return V("cargo", "cargo " + sub, T_BAZEL_TEST), cwd
        if sub in ("build", "b", "run", "r", "install", "doc", "d"):
            return V("cargo", "cargo " + sub, T_BAZEL_BUILD), cwd
        if sub == "fmt":
            return V("lint", "cargo fmt", T_FORMAT), cwd
        if sub == "publish":
            return V(
                "cargo",
                "cargo publish",
                None,
                "Crates are published by release-please and the release pipeline.",
            ), cwd
        return V("cargo", "cargo " + sub), cwd

    if prog in ("gradle", "gradlew"):
        if _version_only(args):
            return None, cwd
        return V(
            "gradle",
            prog,
            ("bazel build //apps/mobile/<app>:app (Android is built with Bazel)", None),
        ), cwd

    if prog in ("pytest", "py.test"):
        if _version_only(args):
            return None, cwd
        return V("pytest", "pytest", T_BAZEL_TEST), cwd
    if prog in LINTERS:
        if _version_only(args):
            return None, cwd
        if prog in FORMATTERS:
            return V("lint", prog, T_FORMAT), cwd
        return V("lint", prog, T_LINT), cwd
    if prog == "actionlint":
        if _version_only(args):
            return None, cwd
        return V("actionlint", "actionlint", T_ACTIONLINT), cwd
    if prog == "gitleaks":
        if _version_only(args):
            return None, cwd
        return V("secret-scan", "gitleaks", T_SECRET_SCAN), cwd

    if prog == "pulumi":
        sub = _first_sub(args, ("-C", "--cwd", "-s", "--stack"))
        if _version_only(args) or sub in PULUMI_READ:
            return None, cwd
        pos = _positionals(args, ("-C", "--cwd", "-s", "--stack"))
        if sub == "stack" and (
            len(pos) < 2
            or pos[1] in ("ls", "output", "history", "export", "graph", "tag")
        ):
            if len(pos) < 3 or pos[1] != "tag" or pos[2] in ("ls", "get"):
                return None, cwd
        if sub == "config" and (len(pos) < 2 or pos[1] in ("get",)):
            return None, cwd
        return V(
            "iac",
            "pulumi " + sub,
            T_PULUMI,
            "Pulumi runs only through the wrappers, which inject the right identity.",
        ), cwd
    if prog in ("terraform", "tofu"):
        sub = _first_sub(args, ("-chdir",))
        if _version_only(args) or sub in (
            "version",
            "show",
            "output",
            "validate",
            "fmt",
            "providers",
            "graph",
            "help",
            "",
        ):
            return None, cwd
        if sub in ("plan", "init"):
            return None, cwd
        return V("iac", "%s %s" % (prog, sub)), cwd

    if prog in ("kubectl", "kubecolor", "oc"):
        sub = _first_sub(
            args,
            (
                "-n",
                "--namespace",
                "--context",
                "--kubeconfig",
                "-l",
                "--selector",
                "-o",
                "--output",
                "-c",
                "--container",
                "--cluster",
                "--user",
                "-f",
                "--filename",
            ),
        )
        if sub in KUBECTL_READ or _version_only(args):
            return None, cwd
        if sub == "rollout":
            pos = _positionals(args, ("-n", "--namespace", "--context", "--kubeconfig"))
            if len(pos) > 1 and pos[1] in ("status", "history"):
                return None, cwd
        if sub == "config":
            pos = _positionals(args, ("--kubeconfig",))
            if len(pos) < 2 or pos[1] in (
                "view",
                "get-contexts",
                "current-context",
                "get-clusters",
                "get-users",
                "use-context",
                "use",
            ):
                return None, cwd
        if sub in ("apply", "delete", "patch", "replace", "create"):
            return V("kubectl", "kubectl " + sub, T_GITOPS), cwd
        return V(
            "kubectl",
            "kubectl " + sub,
            None,
            "The cluster is changed through git (GitOps); there is no target for `kubectl %s`."
            % sub,
        ), cwd
    if prog == "helm":
        sub = _first_sub(args, ("-n", "--namespace", "--kube-context", "--kubeconfig"))
        if _version_only(args) or sub in HELM_READ:
            if sub in ("repo", "dependency", "dep"):
                pos = _positionals(args, ("-n", "--namespace"))
                if len(pos) > 1 and pos[1] in (
                    "update",
                    "build",
                    "add",
                    "remove",
                    "rm",
                ):
                    return V("helm", "helm %s %s" % (sub, pos[1]), T_HELM), cwd
            return None, cwd
        return V("helm", "helm " + sub, T_HELM), cwd

    if prog == "rm":
        return classify_rm(inv, ctx)
    if prog == "find" and "-delete" in args:
        for r in [a for a in args if not a.startswith("-")][:1]:
            p = expand_path(r, cwd, ctx.home)
            if is_bazel_cache_path(p, ctx.home):
                return V("bazel-cache", "find -delete on a Bazel cache", T_CACHE_GC), p
    return None, cwd


def classify_bazel(args: List[str], cwd: str = "", home: str = "") -> Optional[Verdict]:
    for a in args:
        if a.startswith("--output_user_root") or a.startswith("--output_base"):
            return V(
                "bazel-cache",
                "bazel --output_user_root/--output_base",
                (
                    "bazel run //tools/worktree -- <branch> (it pins a per-worktree output root in user.bazelrc)",
                    None,
                ),
                "A one-off output root leaves an orphaned 5-10 GB cache behind.",
            )
    cmd = _first_sub(args)
    if cmd == "clean" and any(a in ("--expunge", "--expunge_async") for a in args):
        return V("bazel-cache", "bazel clean --expunge", T_CACHE_GC)
    if cmd == "run":
        return classify_installer_run(args, cwd, home)
    return None


# What an agent may pass to //tools/agent-guard:install: nothing (install or
# refresh the backstop, which install.py then checks itself), or only these.
# `--uninstall` only with `--dry-run`, to show James the change.
AGENT_INSTALL_FLAGS = ("--check", "--dry-run", "--help", "-h")
_INSTALL_LABEL_RE = re.compile(r"(^|/)tools/agent-guard:install(_rs)?$")


def _is_install_label(word: str, cwd: str) -> bool:
    if _INSTALL_LABEL_RE.search(word):
        return True
    # A label relative to the package, run from tools/agent-guard itself.
    return word in (":install", "install", ":install_rs", "install_rs") and bool(
        re.search(r"/tools/agent-guard/?$", cwd or "")
    )


def installer_args_ok(args: List[str]) -> bool:
    """Only --check/--dry-run/--help, plus --uninstall alongside --dry-run."""
    if any(a not in AGENT_INSTALL_FLAGS + ("--uninstall",) for a in args):
        return False
    return "--uninstall" not in args or "--dry-run" in args


# The files `bazel run //tools/agent-guard:install` builds and runs. An agent
# may run it only from a checkout where they are origin/main's, byte for byte:
# otherwise an agent's own edit to install.py (or to BUILD's `main`) would run
# with James's HOME, whatever install.py claims to check.
INSTALLER_SOURCES = (
    "tools/agent-guard/install.py",
    "tools/agent-guard/agent_guard.py",
    "tools/agent-guard/BUILD",
)
# The Rust installer (:install_rs) is built from every file in these folders,
# by glob: each file on origin/main and each file in the checkout must match,
# so an added file counts as an edit too.
INSTALLER_SOURCE_DIRS = ("tools/agent-guard/src", "tools/agent-guard/install")
_RC_RUN_UNDER = re.compile(r"(run_under|script_path)")
_RC_IMPORT = re.compile(r"^\s*(try-)?import\s+(\S+)")


def _git_env() -> Dict[str, str]:
    env = dict(os.environ)
    for k in list(env):
        if k.startswith("GIT_") and k not in (
            "GIT_CONFIG_NOSYSTEM",
            "GIT_CONFIG_GLOBAL",
        ):
            del env[k]
    return env


def origin_main_files(
    root: str, rels: Sequence[str]
) -> Optional[Dict[str, Optional[bytes]]]:
    """{rel: origin/main's bytes, or None if main has no such file}, or None if git cannot say."""
    request = "".join("origin/main:%s\n" % r for r in rels).encode()
    try:
        r = subprocess.run(
            ["git", "-C", root, "cat-file", "--batch"],
            input=request,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env=_git_env(),
            timeout=5,
        )
    except (OSError, subprocess.SubprocessError):
        return None
    if r.returncode != 0:
        return None
    out, pos, found = r.stdout, 0, {}
    for rel in rels:
        nl = out.find(b"\n", pos)
        if nl < 0:
            return None
        header = out[pos:nl].split()
        pos = nl + 1
        if len(header) == 3 and header[1] == b"blob":
            size = int(header[2])
            found[rel] = out[pos : pos + size]
            pos += size + 1
        elif header[-1:] == [b"missing"]:
            found[rel] = None
        else:
            return None
    return found


def _bazelrc_files(root: str, home: str) -> List[str]:
    """Every bazelrc a `bazel run` in root reads: system, workspace (and its imports), user."""
    out: List[str] = []

    def visit(path: str, depth: int) -> None:
        path = os.path.normpath(path)
        if depth > 8 or path in out or not os.path.isfile(path):
            return
        out.append(path)
        try:
            with open(path, "r", encoding="utf-8", errors="replace") as fh:
                lines = fh.read().splitlines()
        except OSError:
            return
        for line in lines:
            m = _RC_IMPORT.match(line)
            if m:
                target = m.group(2).replace("%workspace%", root)
                visit(
                    target if os.path.isabs(target) else os.path.join(root, target),
                    depth + 1,
                )

    visit("/etc/bazel.bazelrc", 0)
    visit(os.path.join(root, ".bazelrc"), 0)
    if home:
        visit(os.path.join(home, ".bazelrc"), 0)
    return out


def installer_sources(root: str) -> Optional[List[str]]:
    """INSTALLER_SOURCES plus every file under INSTALLER_SOURCE_DIRS on origin/main
    or in root's checkout, sorted; None if git cannot list origin/main's."""
    try:
        r = subprocess.run(
            [
                "git",
                "-C",
                root,
                "ls-tree",
                "-r",
                "-z",
                "--name-only",
                "origin/main",
                "--",
            ]
            + list(INSTALLER_SOURCE_DIRS),
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env=_git_env(),
            timeout=5,
        )
    except (OSError, subprocess.SubprocessError):
        return None
    if r.returncode != 0:
        return None
    found = {p.decode("utf-8", "surrogateescape") for p in r.stdout.split(b"\0") if p}
    for rel_dir in INSTALLER_SOURCE_DIRS:
        for dirpath, _dirs, files in os.walk(os.path.join(root, rel_dir)):
            for name in files:
                found.add(os.path.relpath(os.path.join(dirpath, name), root))
    return list(INSTALLER_SOURCES) + sorted(found - set(INSTALLER_SOURCES))


def installer_problem(cwd: str, home: str) -> str:
    """Why an agent may not run the installer from cwd's checkout ("" if it may)."""
    root = repo_root_of(cwd)
    if root is None:
        return "it is not run from inside a vitruvian-core checkout"
    sources = installer_sources(root)
    main = origin_main_files(root, sources) if sources is not None else None
    if main is None or all(v is None for v in main.values()):
        return "origin/main or its installer cannot be read in %s (fetch first)" % root
    for rel in sources:
        try:
            with open(os.path.join(root, rel), "rb") as fh:
                have: Optional[bytes] = fh.read()
        except OSError:
            have = None
        if have != main[rel]:
            return (
                "%s in %s differs from origin/main's, so an unreviewed installer would run; "
                "run it from a checkout that is up to date with main" % (rel, root)
            )
    for rc in _bazelrc_files(root, home):
        try:
            with open(rc, "r", encoding="utf-8", errors="replace") as fh:
                for line in fh:
                    if not line.lstrip().startswith("#") and _RC_RUN_UNDER.search(line):
                        return (
                            "%s sets run_under or script_path, which would run the installer as "
                            "something else" % rc
                        )
        except OSError:
            continue
    return ""


def classify_installer_run(
    args: List[str], cwd: str = "", home: str = ""
) -> Optional[Verdict]:
    """`bazel run //tools/agent-guard:install`: agents may install, check and dry-run.

    Allowed: the label alone, or with only --check/--dry-run/--help (and
    --uninstall with --dry-run) after `--`, from a checkout whose installer is
    origin/main's (installer_problem). Refused: a real --uninstall, --mode,
    any other flag or argument, and any Bazel option at all (--run_under or
    --script_path could run it without the agent marker, or as something
    else). install.py makes its own checks before an agent's install writes.
    """
    stop = args.index("--") if "--" in args else len(args)
    label = next(
        (i for i, a in enumerate(args[:stop]) if _is_install_label(a, cwd)), None
    )
    if label is None:
        return None
    target_args = [a for a in args[label + 1 :] if a != "--"]
    bazel_opts = [a for a in args[:label] if a.startswith("-")]
    shown = " ".join(
        bazel_opts + [args[label]] + (["--"] if target_args else []) + target_args
    )
    if installer_args_ok(target_args) and not bazel_opts:
        why = installer_problem(cwd, home)
        if not why:
            return None
        return V(
            "guard-config",
            "bazel run %s" % shown,
            None,
            "Agents may run the installer only as origin/main has it: %s." % why,
        )
    if any(a == "--uninstall" or a.startswith("--mode") for a in target_args):
        return V(
            "guard-config",
            "bazel run %s" % shown,
            None,
            "Removing the backstop (--uninstall) and changing modes are James's, from his own "
            "terminal. Agents may install, check and dry-run it (`-- --uninstall --dry-run` "
            "shows him the change).",
        )
    return V(
        "guard-config",
        "bazel run %s" % shown,
        ("bazel run //tools/agent-guard:install", None),
        "Run it exactly so, or with `-- --check` or `-- --dry-run`: no other flags or Bazel "
        "options (--run_under or --script_path could run it as something else, or without "
        "the agent marker).",
    )


CACHE_RES = [
    re.compile(r"(^|/)\.cache/bazel(/|$)"),
    re.compile(r"(^|/)Library/Caches/bazel(/|$)"),
    re.compile(r"/_bazel_[^/]+(/|$)"),
    re.compile(r"^/(private/)?var/tmp/_bazel"),
]


def is_bazel_cache_path(path: str, home: str) -> bool:
    return any(r.search(path) for r in CACHE_RES)


def _is_worktree_dir(path: str) -> bool:
    # A linked worktree has a .git FILE; the primary has a .git directory.
    if re.search(r"-worktrees/?$", path) or re.search(r"-worktrees/[^/]+/?$", path):
        return True
    return os.path.isfile(os.path.join(path, ".git"))


def classify_rm(inv: Invocation, ctx: Context) -> Tuple[Optional[Verdict], str]:
    args = inv.argv[1:]
    recursive = _has(args, "-r", "-R", "--recursive") or _short_cluster_has(args, "rR")
    targets = _positionals(args)
    for t in targets:
        p = expand_path(t, inv.cwd, ctx.home)
        if guard_path(p, ctx.home):
            if protected_repo_file(p):
                return V(
                    "guard-config",
                    "rm of agent-guard's hook files",
                    None,
                    HOOK_FILES_NOTE,
                ), p
            return V(
                "guard-config",
                "rm of agent-guard files",
                None,
                "Changing agent-guard is James's job, from his own terminal.",
            ), p
        if not recursive:
            continue
        if is_bazel_cache_path(p, ctx.home):
            return V("bazel-cache", "rm -r of a Bazel cache", T_CACHE_GC), p
        if _is_worktree_dir(p) and repo_root_of(p) is not None:
            return V(
                "git-worktree",
                "rm -r of a worktree",
                T_WT_REMOVE,
                "Or `bazel run //tools/worktree -- --prune`.",
            ), p
    return None, inv.cwd


# ---------------------------------------------------------------------------
# Self-protection: agents may not edit the installed guard, its policy or log.
# ---------------------------------------------------------------------------
READERS = {
    "cat",
    "head",
    "tail",
    "less",
    "more",
    "jq",
    "grep",
    "egrep",
    "fgrep",
    "rg",
    "ls",
    "wc",
    "stat",
    "file",
    "diff",
    "cmp",
    "shasum",
    "sha256sum",
    "md5",
    "md5sum",
    "tree",
    "bat",
    "sort",
    "uniq",
    "cut",
    "column",
    "awk",
    "realpath",
    "readlink",
    "test",
    "[",
    "echo",
    "printf",
    "python3",
    "python",
}


def guard_path(path: str, home: str) -> bool:
    """Is path one agents may not write: the guard's folders in HOME, or a hook file in a checkout?"""
    p = os.path.normpath(path)
    for rel in (INSTALL_DIR_REL, STATE_DIR_REL):
        base = os.path.normpath(os.path.join(home, rel))
        if p == base or p.startswith(base + os.sep):
            return True
    return protected_repo_file(p) is not None


# The per-user files that hold the backstop. Agents may edit them for other
# settings with Claude Code's Edit/MultiEdit/Write, which the guard checks
# keep agent-guard's entries (user_file_change_problem); shell, Desktop
# Commander and agy writes to them are refused.
USER_HOOK_FILES_REL = (".claude/settings.json", ".gemini/config/hooks.json")
_USER_HOOK_MARK = re.compile(
    r"agent-guard/(agent_guard\.py|hook\.py|hook\.sh)|agent-guard-backstop"
)
USER_FILES_NOTE = (
    "Shell, Desktop Commander and Antigravity writes to ~/.claude/settings.json and "
    "~/.gemini/config/hooks.json are refused because they hold agent-guard's backstop. "
    "Change other settings there with the Edit tool (it may not touch agent-guard's entries "
    "or set disableAllHooks to true); the backstop itself changes only through "
    "`bazel run //tools/agent-guard:install`."
)


def user_hook_file(path: str, home: str, folders: bool = False) -> Optional[str]:
    """The backstop file that path is (with folders: or holds), else None."""
    p = os.path.normpath(path)
    if ".claude" not in p and ".gemini" not in p:
        return None
    for rel in USER_HOOK_FILES_REL:
        f = os.path.normpath(os.path.join(home, rel))
        if p == f or (
            folders and p != os.path.normpath(home) and f.startswith(p + os.sep)
        ):
            return f
    return None


def _guard_entries(path: str, data: Any) -> Any:
    """agent-guard's part of a backstop file: what an edit must leave unchanged."""
    if not isinstance(data, dict):
        return None
    if path.endswith("hooks.json"):
        return {
            name: spec
            for name, spec in data.items()
            if name == "agent-guard" or _USER_HOOK_MARK.search(json.dumps(spec))
        }
    hooks = data.get("hooks")
    if not isinstance(hooks, dict):
        return {}
    return {
        event: [e for e in entries if _USER_HOOK_MARK.search(json.dumps(e))]
        for event, entries in hooks.items()
        if isinstance(entries, list)
        and any(_USER_HOOK_MARK.search(json.dumps(e)) for e in entries)
    }


# `"disableAllHooks": true` in an edit's new text; false is fine.
_DISABLE_ALL_TRUE = re.compile(r'"disableAllHooks"\s*:\s*true\b')


def user_file_change_problem(path: str, before: Optional[str], after: str) -> str:
    """Why writing `after` over `before` would break the backstop in path ("" if it would not)."""
    try:
        new = json.loads(after) if after.strip() else {}
    except ValueError:
        new = None
    if isinstance(new, dict) and new.get("disableAllHooks") is True:
        return 'it sets "disableAllHooks": true'
    try:
        old = json.loads(before) if before and before.strip() else {}
    except ValueError:
        old = None
    want = _guard_entries(path, old)
    if not want:
        return ""  # nothing of agent-guard's there to keep
    if new is None:
        return "the result is not valid JSON, so agent-guard's entries cannot be kept"
    if _guard_entries(path, new) != want:
        return "it removes or changes agent-guard's entries"
    return ""


def protected_repo_file(path: str, folders: bool = True) -> Optional[str]:
    """The PROTECTED_REPO_FILES entry that path is, or holds, inside a vitruvian-core checkout.

    With folders, a folder holding one counts too (`rm -r .claude`,
    `mv tools/agent-guard x`); the checkout's root never does (removing a
    worktree is git-worktree's).
    """
    p = os.path.normpath(path)
    if not any(
        part in p for part in (".claude", ".agents", "tools", "agent-guard", "hook")
    ):
        return None  # fast path: most paths name none of them
    root = repo_root_of(p)
    if root is None or p == root:
        return None
    rel = os.path.relpath(p, root).replace(os.sep, "/")
    for f in PROTECTED_REPO_FILES:
        if _protected_match(rel, f) or (folders and f.startswith(rel + "/")):
            return f
    return None


def _protected_match(rel: str, pattern: str) -> bool:
    if "*" not in pattern:
        return rel == pattern
    folder, _, name = pattern.rpartition("/")
    rfolder, _, rname = rel.rpartition("/")
    return rfolder == folder and fnmatch.fnmatchcase(rname, name)


def _mentions_guard(word: str, cwd: str, home: str) -> bool:
    if "agent-guard" not in word:
        return False
    for m in re.finditer(r"(~|\$\{?HOME\}?|/)[^\s'\"=]*agent-guard[^\s'\"]*", word):
        if guard_path(expand_path(m.group(0), cwd, home), home):
            return True
    return False


_PYTHON_RE = re.compile(r"^python(3(\.\d+)?)?$")
_PY_LITERAL = re.compile(r"(['\"])((?:(?!\1).){1,500}?)\1")
# Where a path literal sits when Python code writes, moves or deletes it: the
# first argument of these calls...
_PY_WRITE_FIRST = re.compile(
    r"\b(rmtree|remove|unlink|rmdir|removedirs|rename|renames|replace|move|chmod|chown|"
    r"truncate|makedirs|mkdir|symlink|link|utime|chflags)\(\s*$"
)
# ...the second argument of these (the first is what is read or moved from)...
_PY_WRITE_SECOND = re.compile(
    r"\b(copy\w*|move|rename|renames|replace|symlink|link)\(\s*(['\"])[^'\"]*\2\s*,\s*$"
)
# ...and Path(<path>) followed by a writing method.
_PY_PATH_WRITE = re.compile(
    r"^\s*\)\s*\.\s*(write_text|write_bytes|unlink|rmdir|mkdir|touch|rename|replace|"
    r"chmod|symlink_to|hardlink_to|open\(\s*['\"][wax])"
)


def _python_writes(text: str, protected: Callable[[str], bool]) -> str:
    """The protected path literal that Python code writes, moves or deletes, or "".

    Reads a `python -c` text the way the rest of the guard reads shell: by its
    shape. A protected path counts only where it is written: `open(p, "w")`,
    the first argument of rmtree/remove/rename/..., the destination of
    copy/move, or `Path(p).write_text(...)`. As a read or copy source it is fine.
    """
    for m in _PY_LITERAL.finditer(text):
        lit = m.group(2)
        if not protected(lit):
            continue
        before, after = (
            text[max(0, m.start() - 120) : m.start()],
            text[m.end() : m.end() + 40],
        )
        if re.search(r"\bopen\(\s*$", before) and re.match(
            r"^\s*,\s*(mode\s*=\s*)?['\"][^'\"]*[wax+]", after
        ):
            return lit
        if _PY_WRITE_FIRST.search(before) or _PY_WRITE_SECOND.search(before):
            return lit
        if re.search(r"\bPath\(\s*$", before) and _PY_PATH_WRITE.match(after):
            return lit
    return ""


_HOOK_FILE_HINT = re.compile(r"\.claude|\.agents|settings|hooks\.json|hook\.sh|tools")
_PATHISH = re.compile(r"[^\s'\"=,;:()<>|&`]+")


def _mentions_hook_file(word: str, cwd: str, home: str, folders: bool = False) -> bool:
    """Does word name a PROTECTED_REPO_FILES file (with folders, or a folder holding one)?"""
    if not _HOOK_FILE_HINT.search(word):
        return False
    for m in _PATHISH.finditer(word):
        if protected_repo_file(expand_path(m.group(0), cwd, home), folders):
            return True
    return False


# Programs that remove or move what they are given, so naming a folder that
# holds a hook file counts (`mv .claude x`, `chmod -R a-w tools`). For any
# other program only the files themselves do (`pytest tools/` is fine).
_REMOVERS = {
    "rm",
    "rmdir",
    "mv",
    "unlink",
    "trash",
    "srm",
    "chmod",
    "chown",
    "chflags",
    "find",
}


# Programs that take a hook file as an argument without writing it: running
# the launcher to try it, git and gh (judged by their own rules), and Bazel.
_BAZELS = {"bazel", "bazelisk", "aspect", "ibazel"}
_HOOK_FILE_NONWRITERS = SHELLS | _BAZELS | {"git", "gh", "source", "."}

# Copiers read their sources: only where they write counts.
_COPIERS = {"cp", "rsync", "scp", "ditto", "install"}


def _written_words(argv: List[str]) -> List[str]:
    """The paths a program may write: all its arguments, except a copier's sources.

    For a copier that is the destination, plus destination/<source name> for
    each source in case the destination is a folder (`cp x/hooks.json .agents/`).
    """
    if os.path.basename(argv[0]) not in _COPIERS:
        return argv[1:]
    dests: List[str] = []
    plain = []
    i = 1
    while i < len(argv):
        a = argv[i]
        if a in ("-t", "--target-directory") and i + 1 < len(argv):
            dests.append(argv[i + 1])
            i += 2
            continue
        if a.startswith("--target-directory="):
            dests.append(a.split("=", 1)[1])
        elif not a.startswith("-"):
            plain.append(a)
        i += 1
    if not dests and plain:
        dests.append(plain.pop())
    out = list(dests)
    for d in dests:
        out += [
            d.rstrip("/") + "/" + os.path.basename(src.rstrip("/")) for src in plain
        ]
    return out


HOOK_FILES_NOTE = (
    "Agents may not change agent-guard's wiring or the files that drive session "
    "start (%s): those files take effect before review. Changing them is James's "
    "call: ask him." % ", ".join(PROTECTED_REPO_FILES)
)


_INSTALLER_RE = re.compile(
    r"(^|/)(tools/)?agent-guard/install(\.py|_rs)?$|(^|/)agent-guard/install(\.py|_rs)?$"
)


def _installer_run(inv: Invocation) -> Optional[Tuple[bool, str]]:
    """The installer run directly (not via bazel): (does it write, its path), or None."""
    argv = inv.argv
    for i, w in enumerate(argv):
        if not _INSTALLER_RE.search(w):
            continue
        direct = i == 0
        via_python = (
            i > 0
            and re.match(r"^python(3(\.\d+)?)?$", os.path.basename(argv[0])) is not None
            and all(a.startswith("-") for a in argv[1:i])
        )
        if direct or via_python:
            rest = argv[i + 1 :]
            return (not rest or not installer_args_ok(rest)), w
    return None


def classify_guard_tamper(inv: Invocation, ctx: Context) -> Optional[Verdict]:
    run = _installer_run(inv)
    if run and not run[0]:
        why = installer_problem(
            os.path.dirname(expand_path(run[1], inv.cwd, ctx.home)), ctx.home
        )
        if why:
            return V(
                "guard-config",
                "running the agent-guard installer directly",
                None,
                "Agents may run the installer only as origin/main has it: %s." % why,
            )
    if run and run[0]:
        return V(
            "guard-config",
            "running the agent-guard installer directly",
            ("bazel run //tools/agent-guard:install", None),
            "Agents install the backstop only through that target, which checks the main "
            "checkout first; `--dry-run` and `--check` are fine directly. Removing it "
            "(--uninstall) is James's, from his own terminal.",
        )
    for op, target in inv.redirects:
        path = expand_path(target, inv.cwd, ctx.home)
        if op not in ("<",) and user_hook_file(path, ctx.home):
            return V(
                "guard-config",
                "writing the backstop's user files",
                None,
                USER_FILES_NOTE,
            )
        if op not in ("<",) and guard_path(path, ctx.home):
            if protected_repo_file(path):
                return V(
                    "guard-config",
                    "writing agent-guard's hook files",
                    None,
                    HOOK_FILES_NOTE,
                )
            return V(
                "guard-config",
                "writing agent-guard files",
                None,
                "Changing agent-guard is James's job, from his own terminal.",
            )
    prog = inv.prog
    if prog in READERS or _PYTHON_RE.match(prog):
        if _PYTHON_RE.match(prog):
            # python -c that WRITES one of the guard's files: refuse. Naming one
            # only as something to read or copy from is fine.
            text = " ".join(inv.argv[1:])
            hit = _python_writes(
                text,
                lambda p: guard_path(expand_path(p, inv.cwd, ctx.home), ctx.home),
            )
            if not hit and _python_writes(
                text,
                lambda p: (
                    user_hook_file(expand_path(p, inv.cwd, ctx.home), ctx.home)
                    is not None
                ),
            ):
                return V(
                    "guard-config",
                    "writing the backstop's user files",
                    None,
                    USER_FILES_NOTE,
                )
            if hit:
                hook = protected_repo_file(expand_path(hit, inv.cwd, ctx.home))
                return V(
                    "guard-config",
                    "writing agent-guard's hook files"
                    if hook
                    else "writing agent-guard files",
                    None,
                    HOOK_FILES_NOTE
                    if hook
                    else "Changing agent-guard is James's job, from his own terminal.",
                )
        return None
    if (
        prog in ("sed",)
        and not _has(inv.argv[1:], "-i", "--in-place")
        and not any(a.startswith("-i") for a in inv.argv[1:])
    ):
        return None
    if prog == "find" and not ("-delete" in inv.argv or "-exec" in inv.argv):
        return None
    if prog in _BAZELS:
        # Its arguments are labels and the target's own arguments (a commit
        # message that names the guard's folder, say). What a target does is
        # out of sight by design; the installer is judged in classify_bazel.
        return None
    if any(_mentions_guard(w, inv.cwd, ctx.home) for w in _written_words(inv.argv)):
        return V(
            "guard-config",
            "%s on agent-guard files" % prog,
            None,
            "Changing agent-guard is James's job, from his own terminal.",
        )
    if prog not in _HOOK_FILE_NONWRITERS and any(
        _mentions_hook_file(w, inv.cwd, ctx.home, prog in _REMOVERS)
        for w in _written_words(inv.argv)
    ):
        return V(
            "guard-config",
            "%s on agent-guard's hook files" % prog,
            None,
            HOOK_FILES_NOTE,
        )
    in_place = prog not in ("perl", "ruby") or any(
        a.startswith("-i")
        or (a.startswith("-") and "i" in a[1:] and not a.startswith("--"))
        for a in inv.argv[1:]
    )
    if (
        prog in _USER_FILE_WRITERS
        and in_place
        and any(
            user_hook_file(
                expand_path(m.group(0), inv.cwd, ctx.home), ctx.home, prog in _REMOVERS
            )
            for w in _written_words(inv.argv)
            for m in _PATHISH.finditer(w)
            if ".claude" in w or ".gemini" in w or "settings" in w or "hooks.json" in w
        )
    ):
        return V(
            "guard-config",
            "%s on the backstop's user files" % prog,
            None,
            USER_FILES_NOTE,
        )
    return None


# Programs that write, move or delete the paths they are given. Only these are
# checked against the backstop's user files, so reading them stays free.
_USER_FILE_WRITERS = (
    _REMOVERS
    | _COPIERS
    | {
        "tee",
        "ln",
        "touch",
        "truncate",
        "sed",
        "perl",
        "ruby",
        "sponge",
        "patch",
        "ed",
        "ex",
    }
)


# ---------------------------------------------------------------------------
# Policy and modes
# ---------------------------------------------------------------------------
def load_policy(path: Optional[str]) -> Dict[str, str]:
    modes = {c: "enforce" for c in CATEGORIES}
    if not path:
        return modes
    try:
        with open(path, "r", encoding="utf-8") as fh:
            data = json.load(fh)
    except (OSError, ValueError):
        return modes  # a missing or broken policy means: enforce everything
    default = data.get("default_mode", "enforce")
    if default not in MODES:
        default = "enforce"
    cats = data.get("categories", {}) or {}
    for c in CATEGORIES:
        entry = cats.get(c, {})
        mode = entry.get("mode") if isinstance(entry, dict) else entry
        modes[c] = mode if mode in MODES else default
    return modes


def default_policy_path() -> str:
    return os.path.join(os.path.dirname(os.path.abspath(__file__)), "policy.json")


# ---------------------------------------------------------------------------
# Redaction and logging
# ---------------------------------------------------------------------------
# Every quantifier is bounded, and the hook only ever redacts the first
# LOG_COMMAND_MAX + 200 characters (redact_for_log), so redaction is linear and
# small whatever the command. The bounds sit above that window, so a value is
# never half-redacted.
_V = r"{1,1400}"  # a value: anything up to the whole window
_REDACTIONS = [
    # Header values: Authorization, X-Api-Key, any *-Key / *Token* / *Secret* header.
    (
        re.compile(r"(?i)(authorization\s{0,8}:\s{0,8})([^'\"\n]{0,1400})"),
        r"\1[REDACTED]",
    ),
    (
        re.compile(
            r"(?i)(\b[A-Za-z0-9-]{0,64}(?:-key|token|secret|cookie|api-?key)[A-Za-z0-9-]{0,64}\s{0,8}:\s{0,8})"
            r"([^'\"\n]" + _V + r")"
        ),
        r"\1[REDACTED]",
    ),
    (
        re.compile(r"(?i)\b(bearer|basic)\s{1,8}([A-Za-z0-9._~+/=-]{8,1400})"),
        r"\1 [REDACTED]",
    ),
    # --password VALUE, --token=VALUE, ...
    (
        re.compile(
            r"(?<!\S)(--password|--passwd|--token|--secret|--api-key|--apikey|--auth-token|--access-token|--client-secret)"
            r"(=|\s{1,8})(\S" + _V + r")"
        ),
        r"\1\2[REDACTED]",
    ),
    # -pSECRET attached (mysql style). Not `-p 5` (git log -p), not -p1 (patch),
    # not find's -print/-prune/-perm/-path.
    (
        re.compile(
            r"(?<!\S)-p(?!(?:rint\w{0,8}|rune|erm|ath|ipe|lain|retty|aginate|ush|ull)\b)(?!\d{1,2}\b)([^\s-]\S{0,1400})"
        ),
        r"-p[REDACTED]",
    ),
    # curl -u user:pass / --user user:pass
    (
        re.compile(r"(?<!\S)(-u|--user)(=|\s{0,8})([^\s:]{1,128}):(\S" + _V + r")"),
        r"\1\2\3:[REDACTED]",
    ),
    # gh secret set NAME --body VALUE / -b VALUE
    (
        re.compile(
            r"""(\bsecret\s{1,8}set\b[^\n]{0,256}?(?<!\S)(?:-b|--body)(?:=|\s{1,8}))("[^"]{0,1400}"|'[^']{0,1400}'|\S"""
            + _V
            + ")"
        ),
        r"\1[REDACTED]",
    ),
    # NAME_TOKEN=..., password=..., api_key=...
    (
        re.compile(
            r"(?i)([A-Za-z0-9_.-]{0,64}(?:token|secret|password|passwd|api[_-]?key|access[_-]?key|credential)[A-Za-z0-9_.-]{0,64})"
            r"=(\S" + _V + r")"
        ),
        r"\1=[REDACTED]",
    ),
    # scheme://user:pass@host, any scheme
    (
        re.compile(
            r"(?i)\b([a-z][a-z0-9+.-]{0,31}://)[^/\s:@]{1,256}:[^/\s@]{1,1400}@"
        ),
        r"\1[REDACTED]@",
    ),
    # Well-known token shapes.
    (
        re.compile(
            r"\b(gh[pousr]_[A-Za-z0-9]{20,255}|github_pat_[A-Za-z0-9_]{20,255}|xox[abprs]-[A-Za-z0-9-]{10,255}|"
            r"sk-[A-Za-z0-9_-]{20,255}|AKIA[0-9A-Z]{16}|AIza[0-9A-Za-z_-]{35}|glpat-[A-Za-z0-9_-]{20,255})"
        ),
        "[REDACTED]",
    ),
]


def redact_for_log(text: str) -> str:
    """Redact, then cut to LOG_COMMAND_MAX. Only the head is ever scanned."""
    return _truncate(redact(text[: LOG_COMMAND_MAX + 200]), len(text))


def redact(text: str) -> str:
    for rx, repl in _REDACTIONS:
        text = rx.sub(repl, text)
    return text


def log_path(home: str) -> str:
    return os.path.join(home, STATE_DIR_REL, "log.jsonl")


def write_log(home: str, record: Dict[str, Any]) -> None:
    path = log_path(home)
    directory = os.path.dirname(path)
    try:
        os.makedirs(directory, mode=0o700, exist_ok=True)
        if os.stat(directory).st_mode & 0o077:
            os.chmod(directory, 0o700)
        try:
            if os.path.getsize(path) > LOG_MAX_BYTES:
                os.replace(path, path + ".1")
        except OSError:
            pass
        fd = os.open(path, os.O_WRONLY | os.O_APPEND | os.O_CREAT, 0o600)
        try:
            if os.fstat(fd).st_mode & 0o077:
                os.fchmod(fd, 0o600)
            os.write(fd, (json.dumps(record, sort_keys=True) + "\n").encode("utf-8"))
        finally:
            os.close(fd)
    except OSError:
        pass  # logging must never break the agent


def _truncate(text: str, original_len: Optional[int] = None) -> str:
    total = len(text) if original_len is None else original_len
    if len(text) <= LOG_COMMAND_MAX and total <= LOG_COMMAND_MAX + 200:
        return text
    return text[:LOG_COMMAND_MAX] + "...[truncated, %d characters]" % total


# ---------------------------------------------------------------------------
# The decision
# ---------------------------------------------------------------------------
class Decision(object):
    def __init__(
        self,
        decision: str,
        category: Optional[str] = None,
        message: str = "",
        scope: str = "outside",
        op: str = "",
    ):
        self.decision = decision  # allow | deny | warn
        self.category = category
        self.message = message
        self.scope = scope  # inside | outside
        self.op = op

    def __repr__(self) -> str:  # pragma: no cover - debugging aid
        return "Decision(%s, %s)" % (self.decision, self.category)


def evaluate(
    command: str,
    cwd: str,
    modes: Optional[Dict[str, str]] = None,
    home: Optional[str] = None,
    git_state: Optional[Callable[[str], GitState]] = None,
    cwd_known: bool = True,
) -> Decision:
    """Decide on one shell command. The first refused invocation wins.

    cwd_known=False means the caller could not tell where the command runs (an
    Antigravity call with neither Cwd nor workspacePaths). Then every command
    counts as inside vitruvian-core: a missing location must never mean allowed.
    """
    modes = modes or {c: "enforce" for c in CATEGORIES}
    home = home or os.path.expanduser("~")
    ctx = Context(home, git_state or probe_git_state)
    # With no known location, a root that counts as inside but names no checkout.
    unknown = None if cwd_known else ""
    any_inside = (repo_root_of(cwd) is not None) or not cwd_known
    warned: Optional[Decision] = None
    try:
        invs = invocations(command, cwd, home)
    except TooComplex:
        mode = modes.get("oversize", "enforce")
        if not any_inside or mode == "off":
            return Decision("allow", None, "", _scope_name(any_inside, cwd_known))
        msg = (
            "Blocked by agent-guard: this command runs more than %d commands, too many to check "
            "within the hook's time limit. Split it into smaller commands. %s"
            % (MAX_COMMANDS, GUARDRAIL)
        )
        return Decision(
            "deny" if mode == "enforce" else "warn",
            "oversize",
            msg,
            _scope_name(True, cwd_known),
            "oversized command",
        )
    if any(inv.hides_marker for inv in invs) and any(
        "agent-guard" in w for inv in invs for w in inv.argv
    ):
        mode = modes.get("guard-config", "enforce")
        if mode != "off":
            v = V(
                "guard-config",
                "hiding the agent session from agent-guard",
                None,
                "Unsetting CLAUDECODE (or an Antigravity/Gemini marker) around agent-guard is routing around it.",
            )
            return Decision(
                "deny" if mode == "enforce" else "warn",
                "guard-config",
                v.message(None),
                "outside",
                v.op,
            )
    seen = set()
    for inv in invs:
        # The same command repeated is checked once.
        key = (tuple(inv.argv), inv.cwd, tuple(inv.redirects))
        if key in seen:
            continue
        seen.add(key)
        verdict = classify_guard_tamper(inv, ctx)
        scope_dir = inv.cwd
        if verdict is None:
            verdict, scope_dir = classify_tool(inv, ctx)
        root = repo_root_of(scope_dir)
        if inv.prog == "gh":
            # A gh command names its repo with -R, a PR/issue URL or an API path.
            # Another repo is out of scope wherever it runs; vitruvian-core is in
            # scope wherever it runs; no repo named means the directory decides.
            target = gh_target_repo(inv.argv[1:])
            if target is not None:
                root = (
                    (repo_root_of(scope_dir) or "")
                    if is_vitruvian_core_slug(target)
                    else None
                )
            elif root is None:
                root = unknown
        elif root is None:
            root = unknown
        if root is not None:
            any_inside = True
        if verdict is None:
            continue
        if root is None and verdict.category not in GLOBAL_CATEGORIES:
            continue
        mode = modes.get(verdict.category, "enforce")
        if mode == "off":
            continue
        msg = verdict.message(root or repo_root_of(cwd))
        scope = _scope_name(root is not None, cwd_known)
        if mode == "warn":
            if warned is None:
                warned = Decision("warn", verdict.category, msg, scope, verdict.op)
            continue
        return Decision("deny", verdict.category, msg, scope, verdict.op)
    if warned is not None:
        return warned
    return Decision("allow", None, "", _scope_name(any_inside, cwd_known))


def _scope_name(inside: bool, cwd_known: bool = True) -> str:
    """The log's scope: inside, outside, or unknown (no location given, so enforced)."""
    if not cwd_known:
        return "unknown"
    return "inside" if inside else "outside"


# Tools whose input carries a shell command, and the fields that may hold it
# (the first one present wins).
COMMAND_FIELDS: Dict[str, Tuple[str, ...]] = {
    "Bash": ("command",),
    "Monitor": ("command",),
    "mcp__terminal__run_in_terminal": ("command",),
    "mcp__plugin_desktop-commander_desktop-commander__start_process": ("command",),
    "mcp__plugin_desktop-commander_desktop-commander__interact_with_process": (
        "input",
    ),
    # Antigravity. run_command's CommandLine and Cwd were captured live (agy
    # 1.4.0). shell_exec and send_command_input exist in the agy binary (step
    # types SHELL_EXEC, with a `command` field, and SEND_COMMAND_INPUT, with
    # `input`), but agy 1.4.2 does not offer them to the model (checked live on
    # 2026-10-17, default and --sandbox: asked for each by name, it had none and
    # used run_command and manage_task instead), so their argument names are
    # assumed: every likely spelling is read.
    "run_command": ("CommandLine",),
    "shell_exec": ("Command", "command", "CommandLine"),
    "send_command_input": ("Input", "input"),
}
# Tools that write files, and the fields naming the files. Checked only to keep
# agents out of the guard's folders in HOME and the checkout's hook files.
DC = "mcp__plugin_desktop-commander_desktop-commander__"
FILE_TOOLS = {
    "Edit": ("file_path",),
    "Write": ("file_path",),
    "MultiEdit": ("file_path",),
    "NotebookEdit": ("notebook_path",),
    DC + "write_file": ("path",),
    DC + "edit_block": ("file_path",),
    DC + "move_file": ("source", "destination"),
    DC + "create_directory": ("path",),
    DC + "write_pdf": ("path", "outputPath"),
    # Antigravity. write_to_file and replace_file_content were captured live;
    # multi_replace_file_content and notebook_edit are from agy's own tool
    # declarations (the same TargetFile field; NotebookPath).
    "write_to_file": ("TargetFile",),
    "replace_file_content": ("TargetFile",),
    "multi_replace_file_content": ("TargetFile",),
    "notebook_edit": ("NotebookPath",),
}
# Antigravity's manage_task: Action "send_input" delivers Input to a running
# command, which is a command. Captured live from agy 1.4.2 (Action, Input,
# TaskId; no Cwd).
AGY_MANAGE_TASK = "manage_task"
# Antigravity's git_commit step (CortexStepGitCommit in the binary; not offered
# to the model in agy 1.4.2, checked live on 2026-10-17, so its arguments are
# unknown). Any call is a commit.
AGY_GIT_COMMIT = "git_commit"
K8S_MCP_RE = re.compile(r"^mcp__(kubernetes|Kubernetes_MCP_Server)__(.+)$")

# Where a command runs when the hook payload does not say. Never a real
# directory: evaluate() is told the location is unknown and enforces.
UNKNOWN_CWD = "/nonexistent/agent-guard-unknown-cwd"


def _as_dict(value: Any) -> Dict[str, Any]:
    return value if isinstance(value, dict) else {}


def _first_text(tin: Dict[str, Any], fields: Sequence[str]) -> str:
    for f in fields:
        v = tin.get(f)
        if v:
            return str(v)
    return ""


def tool_call(payload: Dict[str, Any]) -> Tuple[bool, str, Dict[str, Any]]:
    """(is Antigravity, tool name, tool arguments) from either hook format."""
    if "toolCall" in payload:
        call = _as_dict(payload.get("toolCall"))
        tool = str(call.get("name") or call.get("toolName") or "")
        return True, tool, _as_dict(call.get("args") or call.get("arguments"))
    return (
        False,
        str(payload.get("tool_name") or ""),
        _as_dict(payload.get("tool_input")),
    )


def resolve_cwd(payload: Dict[str, Any], home: str) -> Tuple[str, bool]:
    """(directory the tool call runs in, whether the payload said so).

    Claude Code runs the hook in the agent's own directory and sends `cwd`.
    Antigravity runs it in the folder holding hooks.json (the checkout's
    .agents/, or ~/.gemini/config for the retired per-user hook), sends no
    top-level cwd, and puts the directory in args.Cwd; the hook's own
    directory is therefore never a fallback for it. Without Cwd the workspace
    paths stand in: the first one inside vitruvian-core if any is, else the
    first one. Without those, the location is unknown.
    """
    antigravity, tool, tin = tool_call(payload)
    if antigravity:
        raw = str(tin.get("Cwd") or tin.get("cwd") or "")
        if not raw:
            paths = payload.get("workspacePaths")
            spaces = [
                expand_path(p, "", home)
                for p in (paths if isinstance(paths, list) else [])
                if isinstance(p, str) and p
            ]
            spaces = [p for p in spaces if os.path.isabs(p)]
            raw = next(
                (p for p in spaces if repo_root_of(p) is not None),
                spaces[0] if spaces else "",
            )
        path = expand_path(raw, "", home) if raw else ""
        if not os.path.isabs(path):
            # Missing, or relative to a directory nobody named: unknown.
            return UNKNOWN_CWD, False
        return path, True
    if tool == "mcp__terminal__run_in_terminal":
        raw = str(tin.get("cwd") or payload.get("cwd") or os.getcwd())
    else:
        raw = str(payload.get("cwd") or os.getcwd())
    return expand_path(raw, os.getcwd(), home), True


def _edited(text: str, edits: List[Dict[str, Any]]) -> Optional[str]:
    """text after Claude Code's Edit/MultiEdit edits, or None if one would not apply."""
    for e in edits:
        old = str(e.get("old_string") or "")
        new = str(e.get("new_string") or "")
        if not old or old not in text:
            return None
        text = (
            text.replace(old, new)
            if e.get("replace_all")
            else text.replace(old, new, 1)
        )
    return text


def user_file_tool_decision(
    tool: str, tin: Dict[str, Any], cwd: str, home: str, modes: Dict[str, str]
) -> Optional[Tuple["Decision", str, str]]:
    """The decision on a file tool that touches a backstop user file, or None if it touches none."""
    mode = modes.get("guard-config", "enforce")
    if mode == "off":
        return None
    hit = ""
    for f in FILE_TOOLS[tool]:
        raw = str(tin.get(f) or "")
        if raw and user_hook_file(
            expand_path(raw, cwd, home), home, tool == DC + "move_file"
        ):
            hit = expand_path(raw, cwd, home)
            break
    if not hit:
        return None
    why = ""
    if tool in ("Edit", "MultiEdit", "Write"):
        try:
            with open(hit, "r", encoding="utf-8") as fh:
                before: Optional[str] = fh.read()
        except OSError:
            before = None
        if tool == "Write":
            why = user_file_change_problem(hit, before, str(tin.get("content") or ""))
        else:
            edits = tin.get("edits") if tool == "MultiEdit" else [tin]
            edits = [e for e in (edits or []) if isinstance(e, dict)]
            if any(
                _DISABLE_ALL_TRUE.search(str(e.get("new_string") or "")) for e in edits
            ):
                why = 'it sets "disableAllHooks": true'
            else:
                after = _edited(before, edits) if before is not None else None
                if after is not None:
                    why = user_file_change_problem(hit, before, after)
                elif any(
                    _USER_HOOK_MARK.search(str(e.get("old_string") or ""))
                    or "agent-guard" in str(e.get("old_string") or "")
                    for e in edits
                ):
                    why = "it edits agent-guard's entries"
        if not why:
            return Decision("allow", None, "", "outside"), tool, ""
        note = (
            "This %s of %s is refused: %s. Other settings there are yours to change; "
            "agent-guard's entries change only through `bazel run //tools/agent-guard:install`, "
            "and removing them is James's." % (tool, hit, why)
        )
    else:
        note = USER_FILES_NOTE
    v = V("guard-config", "%s of the backstop's user files" % tool, None, note)
    d = Decision(
        "deny" if mode == "enforce" else "warn",
        "guard-config",
        v.message(None),
        "outside",
        v.op,
    )
    return d, tool, hit


def evaluate_tool(
    payload: Dict[str, Any], modes: Dict[str, str], home: str, git_state=None
) -> Tuple[Decision, str, str]:
    """Decide on a hook payload. Returns (decision, tool name, command text for the log)."""
    _antigravity, tool, tin = tool_call(payload)
    cwd, cwd_known = resolve_cwd(payload, home)

    fields = COMMAND_FIELDS.get(tool)
    if tool == AGY_MANAGE_TASK:
        fields = ("Input", "input") if str(tin.get("Action")) == "send_input" else None
        if fields is None:
            return Decision("allow", None, "", _scope_name(False, cwd_known)), tool, ""
    if fields is not None:
        text = _first_text(tin, fields)
        return (
            evaluate(text, cwd, modes, home, git_state, cwd_known=cwd_known),
            tool,
            text,
        )

    if tool in FILE_TOOLS:
        user = user_file_tool_decision(tool, tin, cwd, home, modes)
        if user is not None:
            return user
        paths = [str(tin.get(f) or "") for f in FILE_TOOLS[tool]]
        path = next(
            (p for p in paths if p and guard_path(expand_path(p, cwd, home), home)), ""
        )
        if path and modes.get("guard-config") != "off":
            if protected_repo_file(expand_path(path, cwd, home)):
                v = V(
                    "guard-config",
                    "%s of agent-guard's hook files" % tool,
                    None,
                    HOOK_FILES_NOTE,
                )
            else:
                v = V(
                    "guard-config",
                    "%s of agent-guard files" % tool,
                    None,
                    "Changing agent-guard is James's job, from his own terminal.",
                )
            d = Decision(
                "deny" if modes.get("guard-config") == "enforce" else "warn",
                "guard-config",
                v.message(None),
                "outside",
                v.op,
            )
            return d, tool, path
        return Decision("allow", None, "", "outside"), tool, ""

    if tool == AGY_GIT_COMMIT:
        in_scope = repo_root_of(cwd) is not None or not cwd_known
        v = V("git-commit", "git commit (Antigravity git_commit tool)", T_COMMIT)
        d = _apply_mode(v, modes, in_scope, repo_root_of(cwd))
        if not cwd_known:
            d.scope = "unknown"
        text = "git_commit " + json.dumps(
            {
                k: val
                for k, val in tin.items()
                if k not in ("toolAction", "toolSummary")
            },
            sort_keys=True,
        )
        return d, tool, text

    in_scope = repo_root_of(cwd) is not None
    if tool == "mcp__ccd_pr__set_auto_merge":
        url = str(tin.get("url") or "")
        m = _GH_URL_RE.search(url)
        if m:
            in_scope = is_vitruvian_core_slug("%s/%s" % (m.group(1), m.group(2)))
        if not tin.get("enabled"):
            return (
                Decision("allow", None, "", "inside" if in_scope else "outside"),
                tool,
                "set_auto_merge enabled=false " + url,
            )
        v = V(
            "gh-pr",
            "auto-merge (ccd_pr set_auto_merge)",
            T_PR_ENQUEUE,
            "It arms auto-merge through the merge queue.",
        )
        return (
            _apply_mode(v, modes, in_scope, repo_root_of(cwd)),
            tool,
            "set_auto_merge enabled=true " + url,
        )

    m = K8S_MCP_RE.match(tool)
    if m:
        name = m.group(2)
        text = "%s %s" % (name, json.dumps(tin, sort_keys=True))
        if name == "kubectl_generic":
            argv = ["kubectl", str(tin.get("command") or "")]
            if tin.get("subCommand"):
                argv.append(str(tin.get("subCommand")))
            v, _ = classify_tool(
                Invocation(argv, cwd, []), Context(home, git_state or probe_git_state)
            )
        elif name == "kubectl_rollout" and str(tin.get("subCommand") or "") in (
            "status",
            "history",
        ):
            v = None
        elif name in (
            "kubectl_apply",
            "kubectl_delete",
            "kubectl_patch",
            "kubectl_create",
            "kubectl_scale",
            "kubectl_rollout",
            "exec_in_pod",
            "node_management",
        ):
            verb = name.replace("kubectl_", "").replace("_in_pod", "")
            v = V(
                "kubectl",
                "kubectl %s (MCP)" % verb,
                T_GITOPS if verb in ("apply", "delete", "patch", "create") else None,
            )
        elif name.endswith("_helm_chart"):
            v = V("helm", "helm %s (MCP)" % name.split("_")[0], T_HELM)
        else:
            v = None
        if v is None or not in_scope:
            return (
                Decision("allow", None, "", "inside" if in_scope else "outside"),
                tool,
                text,
            )
        return _apply_mode(v, modes, in_scope), tool, text

    return Decision("allow", None, "", "inside" if in_scope else "outside"), tool, ""


def _apply_mode(
    v: Verdict, modes: Dict[str, str], in_scope: bool, root: Optional[str] = None
) -> Decision:
    scope = "inside" if in_scope else "outside"
    if not in_scope:
        return Decision("allow", None, "", scope)
    mode = modes.get(v.category, "enforce")
    if mode == "off":
        return Decision("allow", None, "", scope)
    return Decision(
        "deny" if mode == "enforce" else "warn",
        v.category,
        v.message(root),
        scope,
        v.op,
    )


def render(decision: Decision, antigravity: bool) -> Optional[Dict[str, Any]]:
    """The hook's stdout JSON, or None to print nothing (allow)."""
    if decision.decision == "deny":
        if antigravity:
            return {"decision": "deny", "reason": decision.message}
        return {
            "hookSpecificOutput": {
                "hookEventName": "PreToolUse",
                "permissionDecision": "deny",
                "permissionDecisionReason": decision.message,
            }
        }
    if decision.decision == "warn":
        warning = (
            "agent-guard warning (this category is in warn mode, so the command runs): "
            + decision.message
        )
        if antigravity:
            return None
        return {
            "hookSpecificOutput": {
                "hookEventName": "PreToolUse",
                "additionalContext": warning,
            }
        }
    return None


def main(argv: Optional[List[str]] = None, stdin=None, stdout=None) -> int:
    argv = sys.argv[1:] if argv is None else argv
    stdin = stdin or sys.stdin
    stdout = stdout or sys.stdout
    if argv and argv[0] in ("--version", "-V"):
        stdout.write("agent-guard %s\n" % VERSION)
        return 0
    home = os.environ.get("AGENT_GUARD_HOME") or os.path.expanduser("~")
    policy = os.environ.get("AGENT_GUARD_POLICY") or default_policy_path()
    raw = stdin.read()
    try:
        payload = json.loads(raw) if raw.strip() else {}
    except ValueError:
        payload = {}
    if not isinstance(payload, dict):
        payload = {}
    modes = load_policy(policy)
    antigravity = "toolCall" in payload
    try:
        decision, tool, text = evaluate_tool(payload, modes, home)
    except Exception as exc:  # never crash the agent loop on a guard bug
        decision, tool, text = (
            Decision("allow", None, "", "unknown"),
            tool_call(payload)[1],
            "",
        )
        write_log(home, {"ts": _now(), "event": "error", "error": repr(exc)[:500]})
    if text or decision.decision != "allow":
        if antigravity:
            # agy sends no cwd or session_id: log the directory the guard
            # judged by ("" if none was given) and the conversation id.
            try:
                where, known = resolve_cwd(payload, home)
            except Exception:  # the decision is made; the log must not fail it
                where, known = "", False
            cwd_text = where if known else ""
            session = payload.get("conversationId")
        else:
            cwd_text = str(payload.get("cwd") or "")
            session = payload.get("session_id")
        write_log(
            home,
            {
                "ts": _now(),
                "agent": "antigravity" if antigravity else "claude-code",
                "tool": tool,
                "cwd": cwd_text,
                "scope": decision.scope,
                "category": decision.category,
                "op": decision.op,
                "decision": decision.decision,
                "command": redact_for_log(text),
                "session": str(session or "")[:64],
                # Which copy decided: "origin/main:<blob>" or "working-copy (why)"
                # from hook.sh; "" when run some other way. The retired
                # per-user install writes no source at all.
                "source": os.environ.get("AGENT_GUARD_SOURCE", "")[:200],
            },
        )
    out = render(decision, antigravity)
    if out is not None:
        stdout.write(json.dumps(out) + "\n")
    return 0


def _now() -> str:
    return datetime.datetime.now(datetime.timezone.utc).strftime(
        "%Y-%m-%dT%H:%M:%S.%fZ"
    )


if __name__ == "__main__":
    sys.exit(main())
