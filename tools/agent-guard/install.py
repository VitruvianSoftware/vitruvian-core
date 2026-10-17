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

"""Install agent-guard as a user-level Claude Code PreToolUse hook.

  bazel run //tools/agent-guard:install                       # install or update
  bazel run //tools/agent-guard:install -- --dry-run          # show what would change
  bazel run //tools/agent-guard:install -- --check            # is the installed copy current and working?
  bazel run //tools/agent-guard:install -- --mode git-push=warn   # per-category mode
  bazel run //tools/agent-guard:install -- --uninstall

ORDER. It refuses to install from a checkout that does not have the targets the
guard sends agents to (tools/git/BUILD and tools/secret-scan): installing first
would leave agents with no sanctioned way to commit or push.

WHERE IT GOES. The guard and its policy are COPIED to ~/.local/share/agent-guard
with a version stamp, plus a two-line launcher (hook.py) that imports the guard
so Python caches its bytecode. ~/.claude/settings.json points at the launcher,
not at a checkout, because:
  - a worktree can be removed, and the hook would point at nothing;
  - the main checkout changes under the hook on every pull or branch switch, so
    a half-finished edit to the guard would govern every agent at once;
  - an agent could weaken the policy just by editing tools/agent-guard/policy.json.
The copy changes only when James reinstalls. Agents may not write to it.

TWO ENTRIES. Command tools (Bash, the terminal panel, Monitor, Desktop
Commander's processes, auto-merge, kubernetes) get `onFailure: block`, so a hook
that cannot run refuses the call instead of letting it through. File tools
(Edit, Write, ...) are checked only to protect the guard's own folders, so they
get no onFailure: a broken hook must never stop an agent editing code.

SAFETY NET. After writing, the installer runs the installed hook on two sample
calls (one harmless, one that must be refused). If either fails, it puts the
settings file and the old copy back and says why.

Antigravity is not wired: its hook format is described in the design but not
yet tested live, so the installer prints the snippet instead of guessing.
"""

from __future__ import annotations

import argparse
import datetime
import difflib
import glob
import hashlib
import json
import os
import re
import shlex
import shutil
import subprocess
import sys
import tempfile
from typing import Any, Dict, List, Optional, Tuple

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import agent_guard  # noqa: E402

# Recognises our handlers, old and new.
MARKER_RE = re.compile(r"agent-guard/(agent_guard\.py|hook\.py|hook\.sh)")
FILES = ("agent_guard.py", "policy.json")
RUNNER = "hook.sh"
LAUNCHER = "hook.py"
LAUNCHER_TEXT = (
    'import sys; sys.path.insert(0, __file__.rpartition("/")[0])\n'
    "import agent_guard; sys.exit(agent_guard.main())\n"
)

_DC = "mcp__plugin_desktop-commander_desktop-commander__"
# Matchers with any non-word character are JavaScript regexes; anchor them.
COMMAND_MATCHER = (
    "^(Bash|Monitor"
    "|mcp__terminal__run_in_terminal"
    "|" + _DC + "(start_process|interact_with_process)"
    "|mcp__ccd_pr__set_auto_merge"
    "|mcp__(kubernetes|Kubernetes_MCP_Server)__(kubectl_(apply|create|delete|patch|scale|rollout|generic)"
    "|exec_in_pod|(install|upgrade|uninstall)_helm_chart|node_management)"
    ")$"
)
FILE_MATCHER = (
    "^(Edit|Write|MultiEdit|NotebookEdit"
    "|" + _DC + "(write_file|edit_block|move_file|create_directory|write_pdf)"
    ")$"
)
HOOK_TIMEOUT = 10
ON_FAILURE_MIN = (2, 1, 295)  # Claude Code first accepting "onFailure"

# The targets the guard sends agents to. Installing without them strands
# agents: (file, regexes that must all match it, label for the refusal).
PREREQUISITES = (
    ("tools/git/BUILD", (r'name\s*=\s*"commit"',), "//tools/git:commit"),
    ("tools/git/BUILD", (r'name\s*=\s*"push"',), "//tools/git:push"),
    ("tools/git/BUILD", (r'name\s*=\s*"sync"',), "//tools/git:sync"),
    ("tools/secret-scan/BUILD", (), "//tools/secret-scan"),
    (
        "tools/agent-app/agent-app.sh",
        (r"pr-enqueue",),
        "//tools/agent-app -- pr-enqueue",
    ),
)
SYSTEM_PYTHONS = (
    "/Library/Developer/CommandLineTools/usr/bin/python3",
    "/usr/bin/python3",
)

# Environment markers that mean "this is an agent's shell, not James's".
AGENT_MARKERS = ("CLAUDECODE", "ANTIGRAVITY_AGENT", "GEMINI_CLI")


def sources_dir() -> str:
    return HERE


def install_dir(home: str) -> str:
    return os.path.join(home, agent_guard.INSTALL_DIR_REL)


def settings_path(home: str) -> str:
    return os.path.join(home, ".claude", "settings.json")


def sha256_files(directory: str) -> str:
    h = hashlib.sha256()
    for name in FILES + (LAUNCHER, RUNNER):
        with open(os.path.join(directory, name), "rb") as fh:
            h.update(name.encode() + b"\0" + fh.read() + b"\0")
    return h.hexdigest()


def agent_marker(env: Dict[str, str]) -> Optional[str]:
    """The environment variable that shows this is an agent session, if any."""
    for name in AGENT_MARKERS:
        if env.get(name):
            return name
    for name in sorted(env):
        if name.startswith("ANTIGRAVITY_") and env[name]:
            return name
    return None


def git_rev(workspace: Optional[str]) -> str:
    if not workspace:
        return "unknown"
    try:
        rev = (
            subprocess.run(
                ["git", "-C", workspace, "rev-parse", "--short=12", "HEAD"],
                stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL,
                timeout=5,
            )
            .stdout.decode()
            .strip()
        )
        dirty = (
            subprocess.run(
                [
                    "git",
                    "-C",
                    workspace,
                    "status",
                    "--porcelain",
                    "--",
                    "tools/agent-guard",
                ],
                stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL,
                timeout=5,
            )
            .stdout.decode()
            .strip()
        )
    except (OSError, subprocess.SubprocessError):
        return "unknown"
    return (rev or "unknown") + ("-dirty" if dirty else "")


def missing_prerequisites(workspace: Optional[str]) -> List[str]:
    """The targets this checkout does not have yet (empty: fine to install)."""
    if not workspace:
        return ["the checkout (run this through `bazel run`)"]
    missing = []
    for rel, patterns, label in PREREQUISITES:
        try:
            with open(
                os.path.join(workspace, rel), "r", encoding="utf-8", errors="replace"
            ) as fh:
                text = fh.read()
        except OSError:
            missing.append(label)
            continue
        if not all(re.search(p, text) for p in patterns):
            missing.append(label)
    return missing


def python_candidates() -> List[str]:
    """Interpreters in order of how well their PATH survives updates.

    1. Homebrew's versioned opt links (/opt/homebrew/opt/python@3.N/bin/python3.N):
       independent of Xcode and the Command Line Tools, and stable across patch
       upgrades. Gone only if that python@3.N formula is uninstalled.
    2. The Command Line Tools' own python3: not tied to which Xcode is selected.
       Replaced in place by CLT updates.
    3. /usr/bin/python3: Apple's shim, resolved through xcode-select on every
       call, so it fails while Xcode is being replaced or if the selected Xcode
       has gone.
    """
    out = []
    for prefix in ("/opt/homebrew/opt", "/usr/local/opt"):
        found = []
        for d in glob.glob(os.path.join(prefix, "python@3.*")):
            m = re.search(r"python@3\.(\d+)$", d)
            if m:
                found.append(
                    (int(m.group(1)), os.path.join(d, "bin", "python3.%s" % m.group(1)))
                )
        out.extend(p for _v, p in sorted(found, reverse=True))
    out.append("/Library/Developer/CommandLineTools/usr/bin/python3")
    out.append("/usr/bin/python3")
    return out


def _python_ok(path: str) -> bool:
    if not os.access(path, os.X_OK):
        return False
    try:
        return (
            subprocess.run(
                [
                    path,
                    "-I",
                    "-c",
                    "import sys; sys.exit(0 if sys.version_info >= (3, 9) else 1)",
                ],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                timeout=20,
            ).returncode
            == 0
        )
    except (OSError, subprocess.SubprocessError):
        return False


def pick_python(explicit: Optional[str]) -> str:
    """An absolute python3 >= 3.9 outside Bazel's caches."""
    if explicit:
        return explicit
    for c in python_candidates():
        if _python_ok(c):
            return c
    raise SystemExit(
        "agent-guard install: no python3 >= 3.9 found outside Bazel's caches"
    )


def claude_version() -> Optional[Tuple[int, ...]]:
    exe = shutil.which("claude")
    if not exe:
        return None
    try:
        out = subprocess.run(
            [exe, "--version"],
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            timeout=15,
        ).stdout.decode()
    except (OSError, subprocess.SubprocessError):
        return None
    m = re.search(r"(\d+)\.(\d+)\.(\d+)", out)
    return tuple(int(x) for x in m.groups()) if m else None


def brew_on_request_pythons() -> List[str]:
    """python@3.N formulae James installed himself, newest first.

    A python@3.N pulled in only as another formula's dependency can be removed
    by Homebrew's automatic cleanup; one installed on request stays.
    """
    brew = shutil.which("brew") or next(
        (
            b
            for b in ("/opt/homebrew/bin/brew", "/usr/local/bin/brew")
            if os.access(b, os.X_OK)
        ),
        None,
    )
    if not brew:
        return []
    try:
        out = subprocess.run(
            [brew, "list", "--formula", "--installed-on-request"],
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            timeout=30,
        ).stdout.decode()
    except (OSError, subprocess.SubprocessError):
        return []
    prefix = os.path.dirname(os.path.dirname(os.path.realpath(brew)))
    found = []
    for name in out.split():
        m = re.match(r"^python@3\.(\d+)$", name)
        if m:
            found.append(
                (
                    int(m.group(1)),
                    os.path.join(prefix, "opt", name, "bin", "python3.%s" % m.group(1)),
                )
            )
    return [path for _v, path in sorted(found, reverse=True)]


def interpreter_chain(primary: str, fallbacks: Optional[List[str]] = None) -> List[str]:
    """The interpreters the launcher tries, in order, without duplicates."""
    middle = brew_on_request_pythons() if fallbacks is None else fallbacks
    chain: List[str] = []
    for p in [primary] + list(middle) + list(SYSTEM_PYTHONS):
        if p not in chain:
            chain.append(p)
    return chain


def runner_text(chain: List[str], idir: str) -> str:
    """hook.sh: run hook.py on the first interpreter that exists AND works.

    The tool call's JSON is read once and handed to each candidate in turn;
    the first one that exits 0 wins. Exit 1 only if none does, which the
    command-tool entry (onFailure: block) turns into a refusal.
    """
    hook = shlex.quote(os.path.join(idir, LAUNCHER))
    return (
        "#!/bin/sh\n"
        "# agent-guard launcher, written by bazel run //tools/agent-guard:install.\n"
        "# Tries each python3 in turn, so losing one (a Homebrew cleanup, an Xcode\n"
        "# switch) does not wedge every agent.\n"
        "in=$(cat)\n"
        "for py in %s; do\n"
        '  [ -x "$py" ] || continue\n'
        '  if out=$(printf \'%%s\' "$in" | "$py" -I %s); then\n'
        '    [ -n "$out" ] && printf \'%%s\\n\' "$out"\n'
        "    exit 0\n"
        "  fi\n"
        "done\n"
        'echo "agent-guard: no working python3 (tried: %s); reinstall with bazel run //tools/agent-guard:install" >&2\n'
        "exit 1\n"
    ) % (" ".join(shlex.quote(p) for p in chain), hook, " ".join(chain))


def hook_command(home: str) -> str:
    return "/bin/sh %s" % shlex.quote(os.path.join(install_dir(home), RUNNER))


def _is_ours(handler: object) -> bool:
    return isinstance(handler, dict) and bool(
        MARKER_RE.search(str(handler.get("command", "")))
    )


def strip_ours(settings: Dict[str, Any]) -> Dict[str, Any]:
    """settings without any agent-guard handler; every other hook is kept as is."""
    out = json.loads(json.dumps(settings))
    hooks = out.get("hooks")
    if not isinstance(hooks, dict):
        return out
    for event in list(hooks.keys()):
        entries = hooks[event]
        if not isinstance(entries, list):
            continue
        kept = []
        for entry in entries:
            if isinstance(entry, dict) and isinstance(entry.get("hooks"), list):
                handlers = [h for h in entry["hooks"] if not _is_ours(h)]
                if not handlers and any(_is_ours(h) for h in entry["hooks"]):
                    continue
                entry = dict(entry)
                entry["hooks"] = handlers
            kept.append(entry)
        if kept:
            hooks[event] = kept
        elif entries:
            del hooks[event]
    if not hooks and settings.get("hooks"):
        del out["hooks"]
    return out


def with_ours(
    settings: Dict[str, Any], command: str, on_failure: bool
) -> Dict[str, Any]:
    out = strip_ours(settings)
    hooks = out.setdefault("hooks", {})
    command_handler: Dict[str, Any] = {
        "type": "command",
        "command": command,
        "timeout": HOOK_TIMEOUT,
    }
    if on_failure:
        command_handler["onFailure"] = "block"
    file_handler = {"type": "command", "command": command, "timeout": HOOK_TIMEOUT}
    pre = hooks.setdefault("PreToolUse", [])
    pre.append({"matcher": COMMAND_MATCHER, "hooks": [command_handler]})
    pre.append({"matcher": FILE_MATCHER, "hooks": [file_handler]})
    return out


def dump(settings: Dict[str, Any], like: str = "") -> str:
    """Serialise in the style the file already uses, so the diff is only our change.

    The Claude desktop app writes `"key" : value` with escaped slashes (Apple's
    JSONSerialization); the CLI writes `"key": value`. Keep whichever is there.
    """
    sep = (",", " : ") if re.search(r'"\s:\s', like) else (",", ": ")
    text = json.dumps(settings, indent=2, ensure_ascii=False, separators=sep)
    if "\\/" in like:
        text = text.replace("/", "\\/")
    return text if like and not like.endswith("\n") else text + "\n"


def read_settings(path: str) -> Tuple[Dict[str, Any], str]:
    if not os.path.exists(path):
        return {}, ""
    with open(path, "r", encoding="utf-8") as fh:
        text = fh.read()
    if not text.strip():
        return {}, text
    try:
        data = json.loads(text)
    except ValueError as exc:
        raise SystemExit(
            "agent-guard install: %s is not valid JSON (%s); fix it first, nothing was changed"
            % (path, exc)
        )
    if not isinstance(data, dict):
        raise SystemExit(
            "agent-guard install: %s is not a JSON object; nothing was changed" % path
        )
    return data, text


def write_atomic(path: str, text: str, mode: Optional[int] = None) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + ".agent-guard.tmp"
    if mode is None and os.path.exists(path):
        mode = os.stat(path).st_mode & 0o777
    with open(tmp, "w", encoding="utf-8") as fh:
        fh.write(text)
    if mode is not None:
        os.chmod(tmp, mode)
    os.replace(tmp, path)


def backup(path: str, now: str) -> Optional[str]:
    if not os.path.exists(path):
        return None
    dest = "%s.agent-guard-%s.bak" % (path, now)
    shutil.copy2(path, dest)
    return dest


def policy_with_modes(policy_text: str, overrides: Dict[str, str]) -> str:
    data = json.loads(policy_text)
    cats = data.setdefault("categories", {})
    for cat, mode in overrides.items():
        cats.setdefault(cat, {})["mode"] = mode
    return json.dumps(data, indent=2) + "\n"


def parse_modes(values: List[str]) -> Dict[str, str]:
    out: Dict[str, str] = {}
    for v in values:
        if "=" not in v:
            raise SystemExit(
                "agent-guard install: --mode wants CATEGORY=MODE, got %r" % v
            )
        cat, mode = v.split("=", 1)
        if cat not in agent_guard.CATEGORIES and cat != "all":
            raise SystemExit(
                "agent-guard install: unknown category %r (one of: %s)"
                % (cat, ", ".join(sorted(agent_guard.CATEGORIES)))
            )
        if mode not in agent_guard.MODES:
            raise SystemExit(
                "agent-guard install: unknown mode %r (one of: %s)"
                % (mode, ", ".join(agent_guard.MODES))
            )
        for c in agent_guard.CATEGORIES if cat == "all" else [cat]:
            out[c] = mode
    return out


def _diff(old: str, new: str, name: str) -> str:
    return "".join(
        difflib.unified_diff(
            old.splitlines(True),
            new.splitlines(True),
            name + " (now)",
            name + " (after)",
        )
    )


def precompile(python: str, path: str) -> Optional[str]:
    """Cache the guard's bytecode with the hook's own interpreter.

    The launcher imports agent_guard, so Python reads the cached bytecode instead
    of compiling 2,000+ lines on every tool call. Apple's python3 never writes
    the cache itself (it is built that way), but it reads one, so write it here.
    """
    code = "import importlib.util, py_compile, sys; p = sys.argv[1]; py_compile.compile(p, cfile=importlib.util.cache_from_source(p), doraise=True)"
    try:
        r = subprocess.run(
            [python, "-I", "-c", code, path],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=60,
        )
    except (OSError, subprocess.SubprocessError) as exc:
        return "%s could not compile the guard (%s)" % (python, exc)
    if r.returncode != 0:
        return "%s could not compile the guard: %s" % (
            python,
            r.stderr.decode("utf-8", "replace").strip()[-300:],
        )
    return None


def self_test(command: str, home: str) -> Optional[str]:
    """Run the installed hook on two sample calls. None if it works, else why not."""
    scratch = tempfile.mkdtemp(prefix="agent-guard-selftest-")
    try:
        with open(os.path.join(scratch, "MODULE.bazel"), "w") as fh:
            fh.write('module(name = "vitruvian_core")\n')
        # A harmless command must pass, and one the guard always refuses must not.
        cases = [("git status", "allow"), ("git stash", "deny")]
        env = dict(os.environ, HOME=home)
        for sample, want in cases:
            payload = {
                "tool_name": "Bash",
                "cwd": scratch,
                "session_id": "agent-guard-install-selftest",
                "tool_input": {"command": sample},
            }
            try:
                r = subprocess.run(
                    command,
                    shell=True,
                    input=json.dumps(payload).encode(),
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    env=env,
                    timeout=HOOK_TIMEOUT,
                )
            except subprocess.TimeoutExpired:
                return "the hook took longer than %ds" % HOOK_TIMEOUT
            except OSError as exc:
                return "the hook could not start (%s)" % exc
            if r.returncode != 0:
                return "the hook exited %d: %s" % (
                    r.returncode,
                    r.stderr.decode("utf-8", "replace").strip()[-400:],
                )
            out = r.stdout.decode("utf-8", "replace").strip()
            try:
                got = (
                    json.loads(out)["hookSpecificOutput"]["permissionDecision"]
                    if out
                    else "allow"
                )
            except (ValueError, KeyError, TypeError):
                return (
                    "the hook printed something that is not hook JSON: %r" % out[:200]
                )
            if got != want:
                return "the hook said %s to `%s`, expected %s" % (
                    got,
                    sample,
                    want,
                )
        return None
    finally:
        shutil.rmtree(scratch, ignore_errors=True)


ANTIGRAVITY_SNIPPET = """\
Antigravity (agy) is NOT wired by this installer. Its PreToolUse hook is
described in the design (event PreToolUse, matcher run_command, command line in
toolCall.args.CommandLine, reply {"decision":"deny","reason":...}) but has not
been tested live. agent-guard already understands that format. To try it, add
this entry to ~/.gemini/config/hooks.json beside "response-contract", then
confirm a blocked command (for example `git stash`) is refused:

  "agent-guard": {
    "enabled": true,
    "PreToolUse": [
      {"matcher": "run_command", "type": "command", "command": %s, "timeout": %d}
    ]
  }
"""


def main(argv: Optional[List[str]] = None) -> int:
    ap = argparse.ArgumentParser(
        prog="bazel run //tools/agent-guard:install --",
        description=(__doc__ or "").split("\n\n")[0],
    )
    ap.add_argument(
        "--dry-run", action="store_true", help="print what would change, write nothing"
    )
    ap.add_argument(
        "--uninstall",
        action="store_true",
        help="remove the hook and the installed copy (the log is kept)",
    )
    ap.add_argument(
        "--check",
        action="store_true",
        help="exit 1 if the installed copy or hook entries are missing, out of date or not working",
    )
    ap.add_argument(
        "--mode",
        action="append",
        default=[],
        metavar="CATEGORY=MODE",
        help="enforce | warn | off for one category (or all); repeatable",
    )
    ap.add_argument("--home", default=None, help=argparse.SUPPRESS)
    ap.add_argument("--workspace", default=None, help=argparse.SUPPRESS)
    ap.add_argument(
        "--python",
        default=None,
        help="absolute python3 the hook tries first (default: see python_candidates)",
    )
    ap.add_argument(
        "--fallback-python", action="append", default=None, help=argparse.SUPPRESS
    )
    ap.add_argument(
        "--on-failure",
        choices=("auto", "block", "allow"),
        default="auto",
        help="block command-tool calls if the hook itself fails (default: block when Claude Code supports it)",
    )
    args = ap.parse_args(argv)

    home = args.home or os.path.expanduser("~")
    workspace = args.workspace or os.environ.get("BUILD_WORKSPACE_DIRECTORY")
    read_only = args.dry_run or args.check
    marker = agent_marker(dict(os.environ))
    if marker and not read_only:
        sys.stderr.write(
            "agent-guard install: refusing to run inside an agent session (%s is set).\n"
            "Installing, changing or removing agent-guard is James's job, from his own terminal.\n"
            "--dry-run and --check are allowed.\n" % marker
        )
        return 2

    overrides = parse_modes(args.mode)
    sp = settings_path(home)
    idir = install_dir(home)
    settings, old_text = read_settings(sp)
    now = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%SZ")

    if args.check:
        return check(home, settings)
    if args.uninstall:
        return uninstall(sp, idir, settings, old_text, now, args.dry_run)

    missing = missing_prerequisites(workspace)
    if missing and not args.dry_run:
        sys.stderr.write(
            "agent-guard install: refusing to install from %s. It is missing:\n%s\n"
            "The guard sends agents to these targets instead of raw git and gh, so installing\n"
            "before they are on main would leave agents with no way to commit, push or merge.\n"
            "Pull main once they have landed and run this again.\n"
            % (workspace or "here", "".join("  - %s\n" % m for m in missing))
        )
        return 3

    python = pick_python(args.python)
    if args.on_failure == "auto":
        v = claude_version()
        on_failure = v is not None and v >= ON_FAILURE_MIN
    else:
        on_failure = args.on_failure == "block"
    chain = interpreter_chain(python, args.fallback_python)
    command = hook_command(home)
    new = with_ours(settings, command, on_failure)
    new_text = dump(new, old_text)

    with open(os.path.join(sources_dir(), "policy.json"), "r", encoding="utf-8") as fh:
        src_policy = fh.read()
    installed_policy_path = os.path.join(idir, "policy.json")
    if os.path.exists(installed_policy_path) and not overrides:
        # Keep modes James set earlier; take any new categories from the source.
        try:
            with open(installed_policy_path, "r", encoding="utf-8") as fh:
                prev = json.load(fh).get("categories", {})
        except ValueError:
            prev = {}
        carried = {
            c: e.get("mode")
            for c, e in prev.items()
            if isinstance(e, dict)
            and e.get("mode") in agent_guard.MODES
            and c in agent_guard.CATEGORIES
        }
        policy_text = policy_with_modes(src_policy, carried)
    else:
        policy_text = policy_with_modes(src_policy, overrides)
    with open(
        os.path.join(sources_dir(), "agent_guard.py"), "r", encoding="utf-8"
    ) as fh:
        guard_text = fh.read()
    planned = {
        "agent_guard.py": guard_text,
        "policy.json": policy_text,
        LAUNCHER: LAUNCHER_TEXT,
        RUNNER: runner_text(chain, idir),
    }

    file_changes = []
    for name, text in planned.items():
        dest = os.path.join(idir, name)
        cur = None
        if os.path.exists(dest):
            with open(dest, "r", encoding="utf-8") as fh:
                cur = fh.read()
        if cur != text:
            file_changes.append((name, cur, text))
    settings_changed = new_text != old_text

    if args.dry_run:
        if missing:
            print(
                "NOTE: a real install would be REFUSED: %s does not have %s yet.\n"
                % (workspace or "this checkout", " or ".join(missing))
            )
        print("hook command: %s" % command)
        print("python, tried in order: %s" % " -> ".join(chain))
        print(
            "command tools onFailure block: %s; file tools: never"
            % ("yes" if on_failure else "no")
        )
        print(
            _diff(old_text, new_text, sp)
            if settings_changed
            else "settings: already up to date"
        )
        for name, cur, text in file_changes:
            print(
                "would %s %s"
                % ("update" if cur is not None else "write", os.path.join(idir, name))
            )
            if name == "policy.json" and cur is not None:
                print(_diff(cur, text, os.path.join(idir, name)))
        if not file_changes:
            print("installed copy: already up to date")
        print("\n" + ANTIGRAVITY_SNIPPET % (json.dumps(command), HOOK_TIMEOUT))
        return 0

    if not settings_changed and not file_changes:
        print("agent-guard is already installed and up to date (%s)" % idir)
        return 0

    # Keep what was there, so a failed self-test can put it all back.
    previous = idir + ".previous-" + now
    had_copy = os.path.isdir(idir)
    had_settings = os.path.exists(sp)
    if had_copy:
        shutil.copytree(idir, previous)
    settings_backup = None
    stamp: Dict[str, Any] = {}
    try:
        os.makedirs(idir, exist_ok=True)
        for name, text in planned.items():
            write_atomic(os.path.join(idir, name), text, 0o644)
        stamp = {
            "version": agent_guard.VERSION,
            "source_rev": git_rev(workspace),
            "sha256": sha256_files(idir),
            "installed_at": now,
            "python": chain,
        }
        write_atomic(
            os.path.join(idir, "VERSION.json"),
            json.dumps(stamp, indent=2) + "\n",
            0o644,
        )
        # Cache bytecode for every interpreter the launcher may fall back to;
        # only the first one has to succeed.
        problem = precompile(python, os.path.join(idir, "agent_guard.py"))
        for other in chain[1:]:
            if _python_ok(other):
                precompile(other, os.path.join(idir, "agent_guard.py"))
        if settings_changed and not problem:
            settings_backup = backup(sp, now)
            write_atomic(sp, new_text)
        problem = problem or self_test(command, home)
    except OSError as exc:
        problem = "writing failed (%s)" % exc
    if problem:
        if settings_changed:
            if had_settings:
                write_atomic(sp, old_text)
            elif os.path.exists(sp):
                os.remove(sp)
        shutil.rmtree(idir, ignore_errors=True)
        if had_copy:
            os.replace(previous, idir)
        sys.stderr.write(
            "agent-guard install: the installed hook failed its self-test: %s.\n"
            "Everything was put back as it was; nothing is installed or changed.\n"
            % problem
        )
        return 4
    if had_copy:
        shutil.rmtree(previous, ignore_errors=True)
    if settings_changed:
        print(
            "hook written to %s%s"
            % (sp, " (backup: %s)" % settings_backup if settings_backup else "")
        )
    print(
        "guard installed at %s (version %s, source %s, python %s)"
        % (idir, stamp["version"], stamp["source_rev"], python)
    )
    print(
        "self-test passed: the installed hook allows `git status` and refuses `git stash`"
    )
    print("log: %s" % agent_guard.log_path(home))
    print("\n" + ANTIGRAVITY_SNIPPET % (json.dumps(command), HOOK_TIMEOUT))
    return 0


def uninstall(
    sp: str, idir: str, settings: Dict[str, Any], old_text: str, now: str, dry_run: bool
) -> int:
    new = strip_ours(settings)
    new_text = dump(new, old_text) if (new or old_text) else ""
    changed = new != settings
    if dry_run:
        print(
            _diff(old_text, new_text, sp)
            if changed
            else "settings: no agent-guard hook to remove"
        )
        print(
            "would remove %s" % idir
            if os.path.isdir(idir)
            else "no installed copy at %s" % idir
        )
        return 0
    if changed:
        b = backup(sp, now)
        write_atomic(sp, new_text)
        print("removed the agent-guard hooks from %s (backup: %s)" % (sp, b))
    else:
        print("settings: no agent-guard hook to remove")
    if os.path.isdir(idir):
        shutil.rmtree(idir)
        print(
            "removed %s (the log in ~/%s is kept)" % (idir, agent_guard.STATE_DIR_REL)
        )
    return 0


def check(home: str, settings: Dict[str, Any]) -> int:
    idir = install_dir(home)
    problems = []
    command = None
    if not os.path.isfile(os.path.join(idir, LAUNCHER)):
        problems.append("no installed copy at %s" % idir)
    else:
        with (
            open(os.path.join(idir, "agent_guard.py"), "rb") as a,
            open(os.path.join(sources_dir(), "agent_guard.py"), "rb") as b,
        ):
            if a.read() != b.read():
                problems.append(
                    "installed agent_guard.py differs from this checkout's (reinstall to update)"
                )
    matchers = []
    hooks = settings.get("hooks")
    entries = hooks.get("PreToolUse", []) if isinstance(hooks, dict) else []
    for entry in entries if isinstance(entries, list) else []:
        if isinstance(entry, dict):
            for h in entry.get("hooks", []):
                if _is_ours(h):
                    matchers.append(entry.get("matcher"))
                    command = h.get("command")
    if sorted(m for m in matchers if m) != sorted([COMMAND_MATCHER, FILE_MATCHER]):
        problems.append(
            "the agent-guard PreToolUse entries in %s are missing or differ from this checkout's (reinstall)"
            % settings_path(home)
        )
    if command and not problems:
        problem = self_test(command, home)
        if problem:
            problems.append("the installed hook does not work: %s" % problem)
    if problems:
        for p in problems:
            print("DRIFT: " + p)
        return 1
    print("agent-guard is installed, matches this checkout, and passed its self-test")
    return 0


if __name__ == "__main__":
    sys.exit(main())
