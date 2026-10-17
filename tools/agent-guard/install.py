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

"""agent-guard: the per-user backstop, and checking the repo's own wiring.

  bazel run //tools/agent-guard:install                   # install or update the backstop
  bazel run //tools/agent-guard:install -- --dry-run      # show exactly what would change
  bazel run //tools/agent-guard:install -- --check        # repo wiring, backstop, and the launcher answering
  bazel run //tools/agent-guard:install -- --uninstall    # remove the backstop (and any old copy)

The repo wires the hook up itself: .claude/settings.json for Claude Code and
.agents/hooks.json for Antigravity (agy) run tools/agent-guard/hook.sh, which
runs the guard as it is on origin/main. But project hooks load only in a
session STARTED inside vitruvian-core: a session started in ~, in another repo
or in Cowork that then works here would be unguarded (checked live for agy).

So this installs a thin per-user BACKSTOP: the same entries in
~/.claude/settings.json and ~/.gemini/config/hooks.json, running the MAIN
checkout's tools/agent-guard/hook.sh by absolute path (found from the checkout
you run this from, even a worktree). Nothing is copied. Because hook.sh loads
the guard from origin/main, guard changes arrive with a pull or fetch; there is
no reinstall. Only moving or deleting the main checkout needs one, and until
then every agent's commands are refused (the backstop fails closed), so run
this again or `--uninstall` from your own terminal.

In a session started inside the repo both the backstop and the project hook
run. That is harmless: they run the same guard from the same origin/main and
give the same answer; Claude Code runs them in parallel, agy one after the other.

Installing also migrates the old per-user install: its entries, which point at
~/.local/share/agent-guard, are replaced, and that copy is deleted once the new
entries pass a self-test. If the self-test fails, both files are put back.
Every other hook is kept; each file is backed up beside itself before a write.

`--check` reads the two repo files and fails if agent-guard's entries are
missing or differ from what this file expects, checks the backstop points at a
working hook.sh, then runs the launchers on sample tool calls in Claude Code's
and agy's real payload shapes, from the folder each runs them in: `git status`
must be allowed, `git stash` (Claude Code) and `go vet` (agy) refused.
"""

from __future__ import annotations

import argparse
import datetime
import difflib
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

# Recognises an agent-guard handler in a user hook file, old or new.
MARKER_RE = re.compile(r"agent-guard/(agent_guard\.py|hook\.py|hook\.sh)")

# --- What the repo's hook files must say -------------------------------------
# Claude Code: shell form, with the placeholder in double quotes as the hooks
# docs ask. $CLAUDE_PROJECT_DIR is the checkout the session started in.
CLAUDE_COMMAND = '/bin/sh "$CLAUDE_PROJECT_DIR/tools/agent-guard/hook.sh"'
# agy runs a hook from the folder holding its hooks.json: <checkout>/.agents.
AGY_COMMAND = "/bin/sh ../tools/agent-guard/hook.sh"
CLAUDE_SETTINGS_REL = ".claude/settings.json"
AGY_HOOKS_REL = ".agents/hooks.json"
LAUNCHER_REL = "tools/agent-guard/hook.sh"

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
# Antigravity (agy 1.4.0). Its matcher is a Go regex tested against the tool
# name; plain `|` alternation was verified live. run_command, write_to_file and
# replace_file_content were seen live; multi_replace_file_content, manage_task
# and notebook_edit are in agy's tool declarations; shell_exec,
# send_command_input and git_commit exist in the binary but were never seen
# offered to the model. Every name here is one agent_guard reads.
AGY_HOOK_NAME = "agent-guard"
AGY_MATCHER = (
    "run_command|shell_exec|send_command_input|manage_task|git_commit"
    "|write_to_file|replace_file_content|multi_replace_file_content|notebook_edit"
)
HOOK_TIMEOUT = 10

# Environment markers that mean "this is an agent's shell, not James's".
AGENT_MARKERS = ("CLAUDECODE", "ANTIGRAVITY_AGENT", "GEMINI_CLI")


def claude_entries(command: str = CLAUDE_COMMAND) -> List[Dict[str, Any]]:
    """agent-guard's two PreToolUse entries (.claude/settings.json, or the backstop's).

    Command tools get onFailure "block", so a hook that cannot run refuses the
    call instead of letting it through. File tools are checked only to protect
    the guard's own files, so a broken hook must never stop code edits: no
    onFailure there.
    """
    return [
        {
            "matcher": COMMAND_MATCHER,
            "hooks": [
                {
                    "type": "command",
                    "command": command,
                    "timeout": HOOK_TIMEOUT,
                    "onFailure": "block",
                }
            ],
        },
        {
            "matcher": FILE_MATCHER,
            "hooks": [{"type": "command", "command": command, "timeout": HOOK_TIMEOUT}],
        },
    ]


def agy_entry(command: str = AGY_COMMAND) -> Dict[str, Any]:
    """agent-guard's named hook for agy, in the grouped shape PreToolUse needs.

    agy loads a flat PreToolUse entry but silently ignores it. agy fails
    closed on a broken hook (tested live), so there is no setting to add.
    """
    return {
        "enabled": True,
        "PreToolUse": [
            {
                "matcher": AGY_MATCHER,
                "hooks": [
                    {"type": "command", "command": command, "timeout": HOOK_TIMEOUT}
                ],
            }
        ],
    }


# --- The per-user backstop ---------------------------------------------------
def install_dir(home: str) -> str:
    return os.path.join(home, agent_guard.INSTALL_DIR_REL)


def settings_path(home: str) -> str:
    return os.path.join(home, ".claude", "settings.json")


def gemini_hooks_path(home: str) -> str:
    return os.path.join(home, ".gemini", "config", "hooks.json")


def agent_marker(env: Dict[str, str]) -> Optional[str]:
    """The environment variable that shows this is an agent session, if any."""
    for name in AGENT_MARKERS:
        if env.get(name):
            return name
    for name in sorted(env):
        if name.startswith("ANTIGRAVITY_") and env[name]:
            return name
    return None


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


def strip_ours_gemini(hooks: Dict[str, Any]) -> Dict[str, Any]:
    """hooks.json without any agent-guard handler, grouped or flat.

    A named hook left with no handlers by that is dropped; every other named
    hook, and every handler that is not ours, is kept as is.
    """
    out = json.loads(json.dumps(hooks))
    for name in list(out.keys()):
        spec = out[name]
        if not isinstance(spec, dict):
            continue
        removed = False
        for event in list(spec.keys()):
            entries = spec[event]
            if not isinstance(entries, list):
                continue
            kept = []
            changed = False
            for entry in entries:
                if isinstance(entry, dict) and isinstance(entry.get("hooks"), list):
                    handlers = [h for h in entry["hooks"] if not _is_ours(h)]
                    if len(handlers) != len(entry["hooks"]):
                        changed = True
                        if not handlers:
                            continue
                        entry = dict(entry)
                        entry["hooks"] = handlers
                elif _is_ours(entry):  # the flat shape agy ignores for PreToolUse
                    changed = True
                    continue
                kept.append(entry)
            if changed:
                # Write the trimmed groups back even when none disappeared: a
                # group shared with someone else's handler loses only ours.
                removed = True
                if kept:
                    spec[event] = kept
                else:
                    del spec[event]
        if removed and not any(isinstance(v, list) and v for v in spec.values()):
            del out[name]
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
            "agent-guard: %s is not valid JSON (%s); fix it first, nothing was changed"
            % (path, exc)
        )
    if not isinstance(data, dict):
        raise SystemExit(
            "agent-guard: %s is not a JSON object; nothing was changed" % path
        )
    return data, text


def write_atomic(path: str, text: str) -> None:
    tmp = path + ".agent-guard.tmp"
    mode = os.stat(path).st_mode & 0o777 if os.path.exists(path) else None
    with open(tmp, "w", encoding="utf-8") as fh:
        fh.write(text)
    if mode is not None:
        os.chmod(tmp, mode)
    os.replace(tmp, path)


def backup(path: str, now: str) -> str:
    dest = "%s.agent-guard-%s.bak" % (path, now)
    shutil.copy2(path, dest)
    return dest


def _diff(old: str, new: str, name: str) -> str:
    return "".join(
        difflib.unified_diff(
            old.splitlines(True),
            new.splitlines(True),
            name + " (now)",
            name + " (after)",
        )
    )


def main_checkout(workspace: str) -> str:
    """The main (primary) checkout of the repo `workspace` belongs to, even from a worktree."""
    try:
        common = (
            subprocess.run(
                [
                    "git",
                    "-C",
                    workspace,
                    "rev-parse",
                    "--path-format=absolute",
                    "--git-common-dir",
                ],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=True,
                timeout=30,
            )
            .stdout.decode()
            .strip()
        )
    except (OSError, subprocess.SubprocessError) as exc:
        raise SystemExit(
            "agent-guard: %s is not a git checkout (%s)" % (workspace, exc)
        )
    if os.path.basename(common) != ".git":
        raise SystemExit(
            "agent-guard: %s has no main checkout (git dir %s)" % (workspace, common)
        )
    main = os.path.dirname(common)
    if not os.path.isfile(os.path.join(main, LAUNCHER_REL)):
        raise SystemExit(
            "agent-guard: the main checkout %s has no %s yet; pull main there first"
            % (main, LAUNCHER_REL)
        )
    return main


def backstop_command(main: str) -> str:
    return "/bin/sh %s" % shlex.quote(os.path.join(main, LAUNCHER_REL))


def with_ours(settings: Dict[str, Any], command: str) -> Dict[str, Any]:
    """settings with the backstop's two entries in place of any agent-guard entry."""
    out = strip_ours(settings)
    out.setdefault("hooks", {}).setdefault("PreToolUse", []).extend(
        claude_entries(command)
    )
    return out


def gemini_with_ours(hooks: Dict[str, Any], command: str) -> Dict[str, Any]:
    """hooks.json with the backstop's named hook, kept where it already was."""
    stripped = strip_ours_gemini(hooks)
    out: Dict[str, Any] = {}
    for name in hooks:
        if name == AGY_HOOK_NAME:
            out[name] = agy_entry(command)
        elif name in stripped:
            out[name] = stripped[name]
    out.setdefault(AGY_HOOK_NAME, agy_entry(command))
    return out


def backstop_commands(home: str) -> Tuple[List[str], List[str]]:
    """The agent-guard commands in the two user files: (Claude Code's, agy's)."""
    found: Tuple[List[str], List[str]] = ([], [])
    for i, path in enumerate((settings_path(home), gemini_hooks_path(home))):
        try:
            data, _ = read_settings(path)
        except SystemExit:
            continue
        for h in _handlers(data):
            if _is_ours(h) and h.get("command") not in found[i]:
                found[i].append(str(h.get("command")))
    return found


def _handlers(data: Any):
    """Every hook handler in a settings or hooks.json object, grouped or flat."""
    if isinstance(data, dict):
        if "command" in data and "type" in data:
            yield data
        for v in data.values():
            yield from _handlers(v)
    elif isinstance(data, list):
        for v in data:
            yield from _handlers(v)


def install(home: str, workspace: str, now: str, dry_run: bool) -> int:
    """Write (or update) the backstop; migrate and delete the old per-user copy."""
    main = main_checkout(workspace)
    command = backstop_command(main)
    sp, gp = settings_path(home), gemini_hooks_path(home)
    settings, old_text = read_settings(sp)
    new_text = dump(with_ours(settings, command), old_text)
    agy = os.path.isdir(os.path.join(home, ".gemini"))
    g_old = g_new = ""
    if agy:
        gemini, g_old = read_settings(gp)
        g_new = dump(gemini_with_ours(gemini, command), g_old)
    idir = install_dir(home)
    changes = [(sp, old_text, new_text)] + ([(gp, g_old, g_new)] if agy else [])
    changes = [c for c in changes if c[1] != c[2]]
    if dry_run:
        print("backstop command: %s" % command)
        for path, old, new in changes:
            print(_diff(old, new, path))
        if not agy:
            print("Antigravity: ~/.gemini not found, so its hooks are left alone")
        if os.path.isdir(idir):
            print("would remove the old per-user copy %s" % idir)
        if not changes and not os.path.isdir(idir):
            print("the backstop is already installed and up to date")
        return 0
    if not changes and not os.path.isdir(idir):
        print("the backstop is already installed and up to date (%s)" % command)
        return 0
    backups = []
    for path, old, new in changes:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        if os.path.exists(path):
            backups.append(backup(path, now))
        write_atomic(path, new)
    problems = self_test_command(command, home, agy)
    if problems:
        for path, old, _new in changes:
            if old:
                write_atomic(path, old)
            elif os.path.exists(path):
                os.remove(path)
        for p in problems:
            sys.stderr.write("PROBLEM: %s\n" % p)
        sys.stderr.write(
            "agent-guard: the backstop failed its self-test; both files were put back as "
            "they were and nothing was removed.\n"
        )
        return 4
    for path, _old, _new in changes:
        print("backstop written to %s" % path)
    if backups:
        print("backups: %s" % ", ".join(backups))
    if os.path.isdir(idir):
        shutil.rmtree(idir)
        print("removed the old per-user copy %s (the log is kept)" % idir)
    print(
        "backstop runs %s, which loads the guard from origin/main:"
        % os.path.join(main, LAUNCHER_REL)
    )
    print("guard updates arrive with a pull; reinstall only if you move %s." % main)
    return 0


def self_test_command(command: str, home: str, agy: bool) -> List[str]:
    """Run a backstop command on sample calls, from folders outside any checkout."""
    problems = []
    scratch = tempfile.mkdtemp(prefix="agent-guard-check-")
    hook_dir = tempfile.mkdtemp(prefix="agent-guard-check-hookdir-")
    try:
        with open(os.path.join(scratch, "MODULE.bazel"), "w") as fh:
            fh.write('module(name = "vitruvian_core")\n')
        env = dict(os.environ, HOME=home)
        env.pop("AGENT_GUARD_POLICY", None)
        env.pop("CLAUDE_PROJECT_DIR", None)
        cases = [
            ("claude-code", "git status", "allow"),
            ("claude-code", "git stash", "deny"),
        ]
        if agy:
            cases += [
                ("antigravity", "git status", "allow"),
                ("antigravity", "go vet ./...", "deny"),
            ]
        for agent, sample, want in cases:
            payload = (
                agy_payload(sample, scratch)
                if agent == "antigravity"
                else claude_payload(sample, scratch)
            )
            got, _out, err = run_hook(command, payload, hook_dir, env)
            if got != want:
                problems.append(
                    "the backstop (%s) said %s to `%s` (%s format), expected %s%s"
                    % (
                        command,
                        got or "nothing (it failed)",
                        sample,
                        agent,
                        want,
                        ": " + err if err else "",
                    )
                )
    finally:
        shutil.rmtree(scratch, ignore_errors=True)
        shutil.rmtree(hook_dir, ignore_errors=True)
    return problems


def check_backstop(home: str) -> List[str]:
    """Problems with the per-user backstop (empty: fine)."""
    problems = []
    claude_cmds, agy_cmds = backstop_commands(home)
    agy = os.path.isdir(os.path.join(home, ".gemini"))
    fix = "run `bazel run //tools/agent-guard:install` from your own terminal"
    if os.path.isdir(install_dir(home)) or any(
        agent_guard.INSTALL_DIR_REL in c for c in claude_cmds + agy_cmds
    ):
        problems.append(
            "the old per-user copy (%s) is still installed: %s to migrate"
            % (install_dir(home), fix)
        )
        return problems
    if not claude_cmds or (agy and not agy_cmds):
        problems.append(
            "no per-user backstop in %s: sessions started outside vitruvian-core are unguarded; %s"
            % (settings_path(home) if not claude_cmds else gemini_hooks_path(home), fix)
        )
        return problems
    for cmd in set(claude_cmds + agy_cmds):
        parts = shlex.split(cmd)
        launcher = parts[-1] if parts else ""
        if not os.path.isfile(launcher):
            problems.append(
                "the backstop runs %s, which is gone (did the main checkout move?): %s again"
                % (launcher, fix)
            )
    try:
        settings, _ = read_settings(settings_path(home))
        if [
            e
            for e in settings.get("hooks", {}).get("PreToolUse", [])
            if any(_is_ours(h) for h in e.get("hooks", []))
        ] != claude_entries(claude_cmds[0]):
            problems.append(
                "the backstop's entries in %s differ from install.py's: %s"
                % (settings_path(home), fix)
            )
        if agy:
            hooks, _ = read_settings(gemini_hooks_path(home))
            if hooks.get(AGY_HOOK_NAME) != agy_entry(agy_cmds[0]):
                problems.append(
                    "the backstop's hook in %s differs from install.py's: %s"
                    % (gemini_hooks_path(home), fix)
                )
    except (SystemExit, AttributeError) as exc:
        problems.append(str(exc))
    if not problems:
        problems += self_test_command(claude_cmds[0], home, agy)
    return problems


def uninstall(home: str, now: str, dry_run: bool) -> int:
    """Remove the backstop (or the old copy) and only agent-guard's entries from both user files."""
    sp = settings_path(home)
    settings, old_text = read_settings(sp)
    new = strip_ours(settings)
    changed = new != settings
    new_text = dump(new, old_text) if changed else old_text
    gp = gemini_hooks_path(home)
    gemini: Optional[Tuple[Dict[str, Any], str]] = None
    try:
        gemini = read_settings(gp)
    except SystemExit as exc:
        # A broken hooks.json must not block removing the Claude Code hook.
        sys.stderr.write("%s; leaving it alone\n" % exc)
    g_changed = False
    g_new_text = ""
    if gemini is not None:
        g_data, g_old = gemini
        g_new = strip_ours_gemini(g_data)
        g_changed = g_new != g_data
        g_new_text = dump(g_new, g_old) if g_changed else g_old
    idir = install_dir(home)
    if dry_run:
        print(
            _diff(old_text, new_text, sp)
            if changed
            else "%s: no agent-guard hook to remove" % sp
        )
        if gemini is not None:
            print(
                _diff(gemini[1], g_new_text, gp)
                if g_changed
                else "%s: no agent-guard hook to remove" % gp
            )
        print(
            "would remove %s" % idir
            if os.path.isdir(idir)
            else "no per-user copy at %s" % idir
        )
        return 0
    if changed:
        b = backup(sp, now)
        write_atomic(sp, new_text)
        print(
            "removed the agent-guard hooks from %s, other hooks kept (backup: %s)"
            % (sp, b)
        )
    else:
        print("%s: no agent-guard hook to remove" % sp)
    if gemini is not None:
        if g_changed:
            b = backup(gp, now)
            write_atomic(gp, g_new_text)
            print(
                "removed the agent-guard hook from %s, other hooks kept (backup: %s)"
                % (gp, b)
            )
        else:
            print("%s: no agent-guard hook to remove" % gp)
    if os.path.isdir(idir):
        shutil.rmtree(idir)
        print(
            "removed %s (the log in ~/%s is kept)" % (idir, agent_guard.STATE_DIR_REL)
        )
    else:
        print("no per-user copy at %s" % idir)
    print(
        "the backstop is gone: sessions started inside vitruvian-core are still guarded by its own "
        "hook files, sessions started anywhere else are not."
    )
    return 0


# --- --check ------------------------------------------------------------------
def check_wiring(workspace: str) -> List[str]:
    """Problems with agent-guard's entries in the checkout's two hook files (empty: fine)."""
    problems = []
    path = os.path.join(workspace, CLAUDE_SETTINGS_REL)
    try:
        settings, _ = read_settings(path)
    except SystemExit as exc:
        settings = {}
        problems.append(str(exc))
    if settings.get("disableAllHooks") is not False:
        # Project settings outrank user settings, so this keeps a user-level
        # `disableAllHooks: true` from switching the guard off here.
        problems.append('%s: "disableAllHooks": false is missing' % path)
    hooks = settings.get("hooks") if isinstance(settings.get("hooks"), dict) else {}
    entries = (
        hooks.get("PreToolUse") if isinstance(hooks.get("PreToolUse"), list) else []
    )
    ours = [
        e
        for e in entries
        if isinstance(e, dict) and any(_is_ours(h) for h in e.get("hooks", []))
    ]
    if ours != claude_entries():
        problems.append(
            "%s: agent-guard's two PreToolUse entries are missing or differ from install.py's "
            "claude_entries() (want %s)" % (path, json.dumps(claude_entries()))
        )
    path = os.path.join(workspace, AGY_HOOKS_REL)
    try:
        hooks_json, _ = read_settings(path)
    except SystemExit as exc:
        hooks_json = {}
        problems.append(str(exc))
    if not os.path.exists(path):
        problems.append("%s is missing" % path)
    elif hooks_json.get(AGY_HOOK_NAME) != agy_entry():
        problems.append(
            "%s: the %r hook is missing or differs from install.py's agy_entry() (want %s)"
            % (path, AGY_HOOK_NAME, json.dumps(agy_entry()))
        )
    if not os.path.isfile(os.path.join(workspace, LAUNCHER_REL)):
        problems.append("%s is missing" % os.path.join(workspace, LAUNCHER_REL))
    return problems


def agy_payload(command: str, cwd: str) -> Dict[str, Any]:
    """agy 1.4.0's real PreToolUse payload shape: no top-level cwd or session_id."""
    return {
        "toolCall": {
            "name": "run_command",
            "args": {
                "CommandLine": command,
                "Cwd": cwd,
                "WaitMsBeforeAsync": 5000,
                "toolAction": "Running command",
                "toolSummary": "agent-guard check",
            },
        },
        "stepIdx": 0,
        "conversationId": "agent-guard-check",
        "workspacePaths": [cwd],
        "transcriptPath": os.path.join(cwd, "transcript.jsonl"),
        "artifactDirectoryPath": cwd,
        "modelName": "auto",
    }


def claude_payload(command: str, cwd: str) -> Dict[str, Any]:
    return {
        "session_id": "agent-guard-check",
        "transcript_path": os.path.join(cwd, "transcript.jsonl"),
        "cwd": cwd,
        "permission_mode": "default",
        "hook_event_name": "PreToolUse",
        "tool_name": "Bash",
        "tool_input": {"command": command, "description": "agent-guard check"},
        "tool_use_id": "toolu_agent_guard_check",
    }


def run_hook(
    command: str, payload: Dict[str, Any], cwd: str, env: Dict[str, str]
) -> Tuple[Optional[str], str, str]:
    """(decision or None if the hook failed, raw stdout, stderr), run as the agent runs it."""
    try:
        r = subprocess.run(
            command,
            shell=True,
            input=json.dumps(payload).encode(),
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            cwd=cwd,
            env=env,
            timeout=HOOK_TIMEOUT,
        )
    except subprocess.TimeoutExpired:
        return None, "", "timed out after %ds" % HOOK_TIMEOUT
    out = r.stdout.decode("utf-8", "replace").strip()
    err = r.stderr.decode("utf-8", "replace").strip()
    if r.returncode != 0:
        return None, out, "exit %d: %s" % (r.returncode, err[-400:])
    if not out:
        return "allow", out, err
    try:
        data = json.loads(out)
        if "toolCall" in payload:
            return str(data["decision"]), out, err
        return str(data["hookSpecificOutput"]["permissionDecision"]), out, err
    except (ValueError, KeyError, TypeError):
        return None, out, "printed something that is not hook JSON: %r" % out[:200]


def self_test(workspace: str, home: str) -> Tuple[List[str], List[str]]:
    """Run the checkout's launcher on real payloads. (problems, the sources that answered)."""
    problems: List[str] = []
    sources: List[str] = []
    scratch = tempfile.mkdtemp(prefix="agent-guard-check-")
    try:
        # A stand-in checkout to aim the sample commands at.
        with open(os.path.join(scratch, "MODULE.bazel"), "w") as fh:
            fh.write('module(name = "vitruvian_core")\n')
        env = dict(
            os.environ,
            HOME=home,
            CLAUDE_PROJECT_DIR=workspace,
            AGENT_GUARD_ANNOUNCE="1",
        )
        env.pop("AGENT_GUARD_POLICY", None)
        agy_dir = os.path.join(workspace, ".agents")
        cases = [
            ("claude-code", CLAUDE_COMMAND, workspace, "git status", "allow"),
            ("claude-code", CLAUDE_COMMAND, workspace, "git stash", "deny"),
            ("antigravity", AGY_COMMAND, agy_dir, "git status", "allow"),
            ("antigravity", AGY_COMMAND, agy_dir, "go vet ./...", "deny"),
        ]
        for agent, command, cwd, sample, want in cases:
            payload = (
                agy_payload(sample, scratch)
                if agent == "antigravity"
                else claude_payload(sample, scratch)
            )
            got, _out, err = run_hook(command, payload, cwd, env)
            m = re.search(
                r"not origin/main's copy: (.*)|agent-guard: running (origin/main:\S+)",
                err,
            )
            if m and (m.group(1) or m.group(2)) not in sources:
                sources.append(m.group(1) or m.group(2))
            if got is None:
                problems.append(
                    "the launcher failed on `%s` (%s format): %s" % (sample, agent, err)
                )
            elif got != want:
                problems.append(
                    "the launcher said %s to `%s` (%s format), expected %s "
                    "(is that category in warn or off mode in policy.json?)"
                    % (got, sample, agent, want)
                )
    finally:
        shutil.rmtree(scratch, ignore_errors=True)
    return problems, sources


def check(workspace: str, home: str) -> int:
    problems = check_wiring(workspace)
    sources: List[str] = []
    if not problems:
        more, sources = self_test(workspace, home)
        problems += more
    problems += check_backstop(home)
    if problems:
        for p in problems:
            print("PROBLEM: " + p)
        return 1
    print(
        "agent-guard is wired into %s and %s, and the per-user backstop runs %s. Both allow "
        "`git status` and refuse `git stash` (Claude Code's payload) and `go vet` (agy's)."
        % (CLAUDE_SETTINGS_REL, AGY_HOOKS_REL, backstop_commands(home)[0][0])
    )
    print("guard that answered: %s" % (", ".join(sources) or "unknown"))
    return 0


def main(argv: Optional[List[str]] = None) -> int:
    ap = argparse.ArgumentParser(
        prog="bazel run //tools/agent-guard:install --",
        description=(__doc__ or "").split("\n\n")[0],
    )
    ap.add_argument(
        "--check",
        action="store_true",
        help="exit 1 unless the repo hooks and the backstop are wired and answer",
    )
    ap.add_argument(
        "--uninstall",
        action="store_true",
        help="remove the backstop (and any old per-user copy) from ~/.claude and ~/.gemini (the log is kept)",
    )
    ap.add_argument(
        "--dry-run",
        action="store_true",
        help="print what would change, write nothing",
    )
    ap.add_argument("--mode", action="append", default=[], help=argparse.SUPPRESS)
    ap.add_argument("--home", default=None, help=argparse.SUPPRESS)
    ap.add_argument("--workspace", default=None, help=argparse.SUPPRESS)
    args = ap.parse_args(argv)

    home = args.home or os.path.expanduser("~")
    workspace = args.workspace or os.environ.get("BUILD_WORKSPACE_DIRECTORY") or ""
    if args.mode:
        sys.stderr.write(
            "agent-guard: --mode is gone. Modes live in tools/agent-guard/policy.json and take "
            "effect when a change to it merges to main.\n"
        )
        return 2
    if args.check:
        if not workspace:
            sys.stderr.write(
                "agent-guard: run this through `bazel run` (no checkout given)\n"
            )
            return 2
        return check(workspace, home)
    marker = agent_marker(dict(os.environ))
    if marker and not args.dry_run:
        sys.stderr.write(
            "agent-guard: refusing to %s inside an agent session (%s is set).\n"
            "Installing or removing the backstop is James's job, from his own terminal. "
            "--dry-run and --check are allowed.\n"
            % ("uninstall" if args.uninstall else "install", marker)
        )
        return 2
    now = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    if args.uninstall:
        return uninstall(home, now, args.dry_run)
    if not workspace:
        sys.stderr.write(
            "agent-guard: run this through `bazel run` (no checkout given)\n"
        )
        return 2
    return install(home, workspace, now, args.dry_run)


if __name__ == "__main__":
    sys.exit(main())
