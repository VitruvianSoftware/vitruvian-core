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

"""Shared by hook_test and install_test: a throwaway vitruvian-core checkout,
with a real git history and an origin/main ref, wired the way the repo is."""

import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from typing import Any, Dict, List, Optional, Tuple

HERE = os.path.dirname(os.path.abspath(__file__))
# The runfiles (or source) root: .claude/settings.json and .agents/hooks.json
# sit there, exported from the root package.
REPO_FILES_ROOT = os.path.dirname(os.path.dirname(HERE))
PYTHONS_BLOCK = re.compile(
    r"# --- pythons: begin.*?# --- pythons: end ---\n", re.DOTALL
)

GIT_ENV = {
    "GIT_AUTHOR_NAME": "t",
    "GIT_AUTHOR_EMAIL": "t@example.com",
    "GIT_COMMITTER_NAME": "t",
    "GIT_COMMITTER_EMAIL": "t@example.com",
    "GIT_CONFIG_NOSYSTEM": "1",
    "GIT_CONFIG_GLOBAL": os.devnull,
}


def launcher_text(pythons: Optional[List[str]] = None) -> str:
    """hook.sh, with its list of pythons replaced (default: this test's own)."""
    with open(os.path.join(HERE, "hook.sh")) as fh:
        text = fh.read()
    chain = pythons if pythons is not None else [sys.executable]
    new, n = PYTHONS_BLOCK.subn(lambda _m: 'pythons="%s"\n' % " ".join(chain), text)
    assert n == 1, "hook.sh lost its pythons block markers"
    return new


def git(cwd: str, *args: str) -> str:
    return subprocess.run(
        ["git", "-C", cwd] + list(args),
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        env=dict(os.environ, **GIT_ENV),
    ).stdout.decode()


class Checkout(object):
    """A fake checkout: MODULE.bazel, tools/agent-guard and both hook files,
    committed, with refs/remotes/origin/main pointing at that commit."""

    def __init__(self, pythons: Optional[List[str]] = None, with_git: bool = True):
        # Not under TEST_TMPDIR: inside Bazel that sits below an execroot whose
        # MODULE.bazel would make the "outside" folders look inside.
        self.tmp = tempfile.mkdtemp(
            prefix="agent-guard-checkout-",
            dir="/tmp" if os.access("/tmp", os.W_OK) else None,
        )
        self.tmp = os.path.realpath(self.tmp)
        self.root = os.path.join(self.tmp, "vitruvian-core")
        self.home = os.path.join(self.tmp, "home")
        self.out = os.path.join(self.tmp, "elsewhere")
        self.guard_dir = os.path.join(self.root, "tools", "agent-guard")
        for d in (
            self.guard_dir,
            self.home,
            self.out,
            os.path.join(self.root, ".claude"),
            os.path.join(self.root, ".agents"),
        ):
            os.makedirs(d, exist_ok=True)
        self.write("MODULE.bazel", 'module(name = "vitruvian_core")\n')
        self.write("tools/agent-guard/hook.sh", launcher_text(pythons))
        for name in ("agent_guard.py", "policy.json"):
            shutil.copy(os.path.join(HERE, name), os.path.join(self.guard_dir, name))
        for rel in (".claude/settings.json", ".agents/hooks.json"):
            shutil.copy(
                os.path.join(REPO_FILES_ROOT, rel), os.path.join(self.root, rel)
            )
        if with_git:
            git(self.root, "init", "-q", "-b", "main")
            git(self.root, "add", "-A")
            git(self.root, "commit", "-q", "-m", "init", "--no-gpg-sign")
            git(self.root, "update-ref", "refs/remotes/origin/main", "HEAD")

    def write(self, rel: str, text: str) -> None:
        path = os.path.join(self.root, rel)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w") as fh:
            fh.write(text)

    def set_policy(self, modes: Dict[str, str], commit: bool = False) -> None:
        with open(os.path.join(HERE, "policy.json")) as fh:
            data = json.load(fh)
        for cat, mode in modes.items():
            data["categories"][cat]["mode"] = mode
        self.write("tools/agent-guard/policy.json", json.dumps(data, indent=2) + "\n")
        if commit:
            self.commit_to_main("policy")

    def commit_to_main(self, message: str) -> None:
        git(self.root, "add", "-A")
        git(self.root, "commit", "-q", "-m", message, "--no-gpg-sign")
        git(self.root, "update-ref", "refs/remotes/origin/main", "HEAD")

    def run(
        self,
        payload: Dict[str, Any],
        cwd: Optional[str] = None,
        command: Optional[str] = None,
        env: Optional[Dict[str, str]] = None,
    ) -> Tuple[int, str, str]:
        """Run the launcher the way Claude Code does (default) or as `command` from `cwd`."""
        full_env = dict(os.environ, HOME=self.home, CLAUDE_PROJECT_DIR=self.root)
        for k in ("AGENT_GUARD_HOME", "AGENT_GUARD_POLICY", "AGENT_GUARD_SOURCE"):
            full_env.pop(k, None)
        full_env.update(env or {})
        r = subprocess.run(
            command or '/bin/sh "$CLAUDE_PROJECT_DIR/tools/agent-guard/hook.sh"',
            shell=True,
            input=json.dumps(payload).encode(),
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            cwd=cwd or self.out,
            env=full_env,
            timeout=60,
        )
        return r.returncode, r.stdout.decode().strip(), r.stderr.decode().strip()

    def log(self) -> List[Dict[str, Any]]:
        path = os.path.join(self.home, ".local", "state", "agent-guard", "log.jsonl")
        if not os.path.exists(path):
            return []
        with open(path) as fh:
            return [json.loads(line) for line in fh]

    def close(self) -> None:
        shutil.rmtree(self.tmp, ignore_errors=True)


def claude(command: str, cwd: str) -> Dict[str, Any]:
    """Claude Code's PreToolUse payload for Bash."""
    return {
        "session_id": "test",
        "cwd": cwd,
        "hook_event_name": "PreToolUse",
        "tool_name": "Bash",
        "tool_input": {"command": command},
    }


def agy(command: str, cwd: str) -> Dict[str, Any]:
    """agy 1.4.0's real PreToolUse payload for run_command (no top-level cwd)."""
    return {
        "toolCall": {
            "name": "run_command",
            "args": {"CommandLine": command, "Cwd": cwd, "WaitMsBeforeAsync": 5000},
        },
        "stepIdx": 0,
        "conversationId": "test",
        "workspacePaths": [cwd],
    }


def decision(out: str, antigravity: bool = False) -> str:
    if not out:
        return "allow"
    data = json.loads(out)
    if antigravity:
        return data["decision"]
    return data["hookSpecificOutput"]["permissionDecision"]
