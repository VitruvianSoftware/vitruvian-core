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

"""//tools/landed (Rust) against landed.sh, side by side.

Each case builds a scratch repository with a real squash-merge topology (a
topic commit that is not an ancestor of main, and a squashed commit that is),
puts a fake `gh` on PATH that answers as configured and records every call,
then runs landed.sh and the Rust binary with the same arguments and
environment. The exit code, stdout, stderr and the recorded gh calls must be
identical.
"""

import os
import shutil
import subprocess
import tempfile
import unittest

HERE = os.getcwd()
SH = os.path.join(HERE, os.environ["LANDED_SH"])
RS = os.path.join(HERE, os.environ["LANDED_RS"])
BASH = shutil.which("bash")
GIT = shutil.which("git")

GIT_ENV = {
    "GIT_AUTHOR_NAME": "t",
    "GIT_AUTHOR_EMAIL": "t@t",
    "GIT_COMMITTER_NAME": "t",
    "GIT_COMMITTER_EMAIL": "t@t",
    "GIT_CONFIG_NOSYSTEM": "1",
}


def git(repo, *args):
    env = dict(os.environ, **GIT_ENV)
    return subprocess.run(
        [GIT, "-C", repo] + list(args),
        env=env,
        capture_output=True,
        text=True,
        check=True,
    ).stdout.strip()


def commit(repo, msg, files=None, allow_empty=False):
    for name, content in (files or {}).items():
        with open(os.path.join(repo, name), "w") as f:
            f.write(content)
    git(repo, "add", "-A")
    git(repo, "commit", "-q", "-m", msg, *(["--allow-empty"] if allow_empty else []))
    return git(repo, "rev-parse", "HEAD")


def new_repo(tmp):
    """main: base -> squashed (#42); topic: base -> the change."""
    r = os.path.join(tmp, "repo")
    os.makedirs(r)
    git(r, "init", "-q", "-b", "main")
    commit(r, "base", {"f.txt": "base\n"})
    git(r, "checkout", "-q", "-b", "topic")
    commit(r, "the change (topic)", {"f.txt": "change\n"})
    git(r, "checkout", "-q", "main")
    commit(r, "the change (#42)", {"f.txt": "change\n"})
    git(r, "update-ref", "refs/remotes/origin/main", "refs/heads/main")
    return r


FAKE_GH = r"""#!/usr/bin/env bash
{ printf '%s\x1f' "$@"; printf '\n'; } >> "${FAKE_GH_LOG}"
key="$1 $2"
case "$key" in
  "pr list") out="${FAKE_GH_LIST-}" ;;
  "pr view") out="${FAKE_GH_VIEW-}" ;;
  api*) out="${FAKE_GH_API-}" ;;
  *) out="" ;;
esac
[ -n "$out" ] && printf '%s\n' "$out"
exit "${FAKE_GH_RC:-0}"
"""


class Parity(unittest.TestCase):
    maxDiff = None

    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.bin = os.path.join(self.tmp, "bin")
        os.makedirs(self.bin)
        with open(os.path.join(self.bin, "gh"), "w") as f:
            f.write(FAKE_GH)
        os.chmod(os.path.join(self.bin, "gh"), 0o755)
        # A PATH with no gh at all: just what the script itself runs.
        self.nogh = os.path.join(self.tmp, "nogh")
        os.makedirs(self.nogh)
        for tool in ("git", "head", "grep", "bash", "env", "cat"):
            src = shutil.which(tool)
            if src:
                os.symlink(src, os.path.join(self.nogh, tool))

    def tearDown(self):
        shutil.rmtree(self.tmp)

    def both(self, repo, args, gh=None, env=None, with_gh=True, cwd=None, label=""):
        results = []
        for impl in ("sh", "rs"):
            log = os.path.join(self.tmp, f"gh-{impl}.log")
            open(log, "w").close()
            e = {
                k: v
                for k, v in os.environ.items()
                if not k.startswith(("LANDED_", "FAKE_GH", "BUILD_WORKSPACE"))
            }
            e.update(GIT_ENV)
            e["FAKE_GH_LOG"] = log
            e["PATH"] = (self.bin + ":" + os.environ["PATH"]) if with_gh else self.nogh
            e["BUILD_WORKSPACE_DIRECTORY"] = repo
            e.update(gh or {})
            e.update(env or {})
            cmd = [BASH, SH] + args if impl == "sh" else [RS] + args
            p = subprocess.run(
                cmd, cwd=cwd or repo, env=e, capture_output=True, timeout=120
            )
            with open(log, "rb") as f:
                calls = f.read()
            results.append((p.returncode, p.stdout, p.stderr, calls))
        self.assertEqual(
            results[0], results[1], f"{label} args={args} gh={gh} env={env}"
        )
        return results[0]

    def gh(self, view="", lst="", api="", rc="0"):
        return {
            "FAKE_GH_VIEW": view,
            "FAKE_GH_LIST": lst,
            "FAKE_GH_API": api,
            "FAKE_GH_RC": rc,
        }

    # ---- plain mode: did PR #N land? ----------------------------------------

    def test_pr_resolution(self):
        r = new_repo(self.tmp)
        main = git(r, "rev-parse", "main")
        topic = git(r, "rev-parse", "topic")
        nf = {"LANDED_NO_FETCH": "1"}
        for ref in ["42", "#42", "topic", "deadbeef", "#", "##7", "0042", "a b"]:
            for gh in [
                self.gh(view=f"MERGED {main}", lst="42", api="42"),
                self.gh(view="OPEN -", lst="42"),
                self.gh(view="CLOSED -", lst="null", api="7"),
                self.gh(view=f"MERGED {topic}", lst="42"),
                self.gh(view="MERGED -", lst="42"),
                self.gh(view="MERGED " + "f" * 40, lst="42"),
                self.gh(view=f"  MERGED   {main}  extra ", lst="42"),
                self.gh(view="", lst="", api=""),
                self.gh(view="", lst="null", api="null"),
                self.gh(rc="1"),
            ]:
                for env in (nf, {}):
                    self.both(r, [ref], gh=gh, env=env)

    def test_commit_log_fallback(self):
        r = new_repo(self.tmp)
        for env in (
            {"LANDED_NO_FETCH": "1"},
            {"LANDED_BASE": "main"},
            {"LANDED_BASE": "origin/nope"},
        ):
            self.both(r, ["42"], gh=self.gh(rc="1"), env=env)
            self.both(r, ["43"], gh=self.gh(rc="1"), env=env)

    def test_usage_and_no_gh(self):
        r = new_repo(self.tmp)
        self.both(r, [], gh=self.gh(view="MERGED x"))
        self.both(r, [""], gh=self.gh())
        self.both(r, ["42"], with_gh=False)
        self.both(r, [], with_gh=False)
        self.both(
            r,
            ["42", "extra"],
            gh=self.gh(view="OPEN -"),
            env={"LANDED_REPO": "o/r", "LANDED_BASE": "main"},
        )

    def test_workspace_resolution(self):
        r = new_repo(self.tmp)
        sub = os.path.join(r, "sub")
        os.makedirs(sub)
        main = git(r, "rev-parse", "main")
        res = []
        for impl in (lambda: [BASH, SH], lambda: [RS]):
            e = {
                k: v
                for k, v in os.environ.items()
                if not k.startswith(("LANDED_", "BUILD_WORKSPACE"))
            }
            e.update(
                GIT_ENV,
                PATH=self.bin + ":" + os.environ["PATH"],
                FAKE_GH_LOG=os.path.join(self.tmp, "x.log"),
                FAKE_GH_VIEW=f"MERGED {main}",
                LANDED_NO_FETCH="1",
            )
            p = subprocess.run(
                impl() + ["42"], cwd=sub, env=e, capture_output=True, timeout=60
            )
            res.append((p.returncode, p.stdout, p.stderr))
        self.assertEqual(res[0], res[1])
        self.assertEqual(res[0][0], 0)

    # ---- --branch / --remote-branch ------------------------------------------

    def test_branch_gate(self):
        r = new_repo(self.tmp)
        nf = {"LANDED_NO_FETCH": "1"}
        main = git(r, "rev-parse", "main")
        topic = git(r, "rev-parse", "topic")
        fails = self.gh(rc="1")
        # content check, no gh
        self.both(r, ["--branch", "topic"], gh=fails, env=nf)
        self.both(r, ["--branch", "topic"], with_gh=False, env=nf)
        # extra local commit after the merge
        git(r, "checkout", "-q", "topic")
        commit(r, "after the merge", {"g.txt": "more\n"})
        git(r, "checkout", "-q", "main")
        for line in [
            f"42 MERGED {topic} {main}",
            f"42 OPEN {topic} -",
            "42 MERGED",
            "",
            "null",
            f"42 MERGED {topic} -",
            f"42 MERGED {'e' * 40} {main}",
            f"42  CLOSED  {topic}  {main} trailing",
        ]:
            self.both(
                r, ["--branch", "topic"], gh=self.gh(lst=line), env=nf, label=line
            )
        # never landed, no commits of its own, unknown, usage
        git(r, "checkout", "-q", "-b", "wip", "main")
        commit(r, "wip", {"w.txt": "wip\n"})
        git(r, "checkout", "-q", "main")
        git(r, "branch", "-q", "empty", "main")
        for br in ["wip", "empty", "nope"]:
            self.both(r, ["--branch", br], gh=fails, env=nf)
            self.both(
                r,
                ["--branch", br],
                gh=self.gh(lst=f"9 OPEN {git(r, 'rev-parse', 'wip')} -"),
                env=nf,
            )
        self.both(r, ["--branch"], gh=fails, env=nf)
        self.both(r, ["--branch", ""], gh=fails, env=nf)
        self.both(
            r,
            ["--branch", "topic"],
            gh=fails,
            env={"LANDED_NO_FETCH": "1", "LANDED_BASE": "origin/missing"},
        )
        self.both(
            r, ["--branch", "topic"], gh=fails, env={}
        )  # fetch fails quietly: no origin remote

    def test_branch_gate_main_moved_on(self):
        r = new_repo(self.tmp)
        squashed = git(r, "rev-parse", "main")
        commit(r, "later edit", {"f.txt": "later\n"})
        git(r, "update-ref", "refs/remotes/origin/main", "refs/heads/main")
        topic = git(r, "rev-parse", "topic")
        for line in [
            f"42 MERGED {topic} {squashed}",
            f"42 MERGED {git(r, 'rev-parse', 'topic~1')} {squashed}",
        ]:
            self.both(
                r,
                ["--branch", "topic"],
                gh=self.gh(lst=line),
                env={"LANDED_NO_FETCH": "1"},
            )

    def grown_repo(self, g_content):
        r = new_repo(self.tmp)
        commit(r, "add g (#43)", {"g.txt": "g\n"})
        commit(r, "change g (#44)", {"g.txt": "g2\n"})
        git(r, "update-ref", "refs/remotes/origin/main", "refs/heads/main")
        git(r, "checkout", "-q", "topic")
        commit(r, "trigger release", allow_empty=True)
        env = dict(os.environ, **GIT_ENV)
        subprocess.run(
            [GIT, "-C", r, "merge", "-q", "--no-edit", git(r, "rev-parse", "main~2")],
            env=env,
            check=True,
            capture_output=True,
        )
        commit(r, "add g", {"g.txt": g_content})
        git(r, "update-ref", "refs/remotes/origin/topic", "HEAD")
        git(r, "checkout", "-q", "main")
        return r

    def test_remote_branch_gate(self):
        nf = {"LANDED_NO_FETCH": "1"}
        for content in ["g\n", "g, but mine\n"]:
            r = self.grown_repo(content)
            line = f"42 MERGED {git(r, 'rev-parse', 'topic~3')} {git(r, 'rev-parse', 'main~2')}"
            self.both(
                r,
                ["--remote-branch", "topic"],
                gh=self.gh(lst=line),
                env=nf,
                label=content,
            )
            self.both(
                r, ["--branch", "topic"], gh=self.gh(lst=line), env=nf, label=content
            )
            git(r, "branch", "-qf", "topic", git(r, "rev-parse", "topic~3"))
            self.both(
                r,
                ["--remote-branch", "topic"],
                gh=self.gh(lst=line),
                env=nf,
                label=content,
            )
            self.both(
                r, ["--branch", "topic"], gh=self.gh(lst=line), env=nf, label=content
            )
            self.both(r, ["--remote-branch", "nope"], gh=self.gh(lst=line), env=nf)
            self.both(
                r, ["--remote-branch", "topic"], gh=self.gh(lst=line), env={}
            )  # fetch fails: no origin
            self.both(r, ["--remote-branch"], gh=self.gh(lst=line), env=nf)
            shutil.rmtree(r)

    def test_remote_branch_fetches_from_origin(self):
        r = new_repo(self.tmp)
        origin = os.path.join(self.tmp, "origin.git")
        subprocess.run([GIT, "init", "-q", "--bare", origin], check=True)
        git(r, "remote", "add", "origin", origin)
        git(r, "push", "-q", "origin", "main", "topic")
        topic = git(r, "rev-parse", "topic")
        main = git(r, "rev-parse", "main")
        for line in [f"42 MERGED {topic} {main}", ""]:
            self.both(r, ["--remote-branch", "topic"], gh=self.gh(lst=line))
            self.both(r, ["--branch", "topic"], gh=self.gh(lst=line))
            self.both(r, ["42"], gh=self.gh(view=f"MERGED {main}"))
        self.both(r, ["--remote-branch", "gone"], gh=self.gh())


if __name__ == "__main__":
    unittest.main()
