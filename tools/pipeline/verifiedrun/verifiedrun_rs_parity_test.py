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

"""Runs the Go verified-run (:verifiedrun-go) and the Rust one (:verifiedrun)
side by side.

Each case builds the same world for both: a scratch repo with an origin, a
user.bazelrc key, pipeline units, tools/ci scripts that call `bazel`; a fake
`bazel` first on PATH whose output and exit code the case sets per lane; a
fake planner and agent-app.sh in RUNFILES_DIR. Both binaries then run with
the same arguments, and the test requires the same exit code, stdout,
stderr, every command line the fake bazel, planner, scripts and token
minter saw, the repo's commits and status, and no temp dir left behind.

The record is never actually written: that would post to GitHub. The cases
stop it at each refusal before the post (no key, no token, bad recorder.tsv);
the post itself is covered by the Rust unit tests against a local server.
"""

import os
import re
import shutil
import subprocess
import tempfile
import unittest

HERE = os.getcwd()
VR_GO = os.path.join(HERE, os.environ["VERIFIEDRUN_GO"])
VR_RS = os.path.join(HERE, os.environ["VERIFIEDRUN_RS"])
PLAN_GO = os.path.join(HERE, os.environ["PLAN_GO"])
PLAN_RS = os.path.join(HERE, os.environ["PLAN_RS"])

GIT_ENV = {
    "GIT_CONFIG_GLOBAL": "/dev/null",
    "GIT_CONFIG_NOSYSTEM": "1",
    "GIT_AUTHOR_NAME": "t",
    "GIT_AUTHOR_EMAIL": "t@example.com",
    "GIT_COMMITTER_NAME": "t",
    "GIT_COMMITTER_EMAIL": "t@example.com",
    "GIT_AUTHOR_DATE": "2026-01-01T00:00:00Z",
    "GIT_COMMITTER_DATE": "2026-01-01T00:00:00Z",
}

FAKE_BAZEL = r"""#!/bin/bash
printf 'lane=%s | %s\n' "$VERIFIED_RUN_LANE" "$*" >> "$FAKE_LOG/bazel.log"
cmd=""
for a in "$@"; do case "$a" in -*) ;; *) cmd="$a"; break ;; esac; done
lane="${VERIFIED_RUN_LANE//:/_}"
d="$FAKE_DIR"
pick() { if [ -f "$d/$lane.$cmd.$1" ]; then echo "$d/$lane.$cmd.$1"; elif [ -f "$d/default.$cmd.$1" ]; then echo "$d/default.$cmd.$1"; fi; }
e="$(pick err)"; [ -n "$e" ] && cat "$e" >&2
o="$(pick out)"; [ -n "$o" ] && cat "$o"
r="$(pick rc)"; if [ -n "$r" ]; then exit "$(cat "$r")"; fi
exit 0
"""

FAKE_PLANNER = r"""#!/bin/bash
printf '%s\n' "$*" >> "$FAKE_LOG/planner.log"
if [[ "$PATH" == */bin:* ]]; then echo "PATH-has-shim=yes"; else echo "PATH-has-shim=no"; fi >> "$FAKE_LOG/planner.log"
[ -f "$FAKE_DIR/plan.query" ] && bazel query 'attr(tags, pipeline, //...)' --output=label >&2
[ -f "$FAKE_DIR/plan.err" ] && cat "$FAKE_DIR/plan.err" >&2
[ -f "$FAKE_DIR/plan.json" ] && cat "$FAKE_DIR/plan.json"
exit "$(cat "$FAKE_DIR/plan.rc" 2>/dev/null || echo 0)"
"""

FAKE_AGENT_APP = r"""#!/bin/bash
printf '%s\n' "$*" >> "$FAKE_LOG/agent-app.log"
printf 'GH_TOKEN=%s GITHUB_TOKEN=%s\n' "${GH_TOKEN-unset}" "${GITHUB_TOKEN-unset}" >> "$FAKE_LOG/agent-app.log"
[ -f "$FAKE_DIR/token.err" ] && cat "$FAKE_DIR/token.err" >&2
[ -f "$FAKE_DIR/token.out" ] && cat "$FAKE_DIR/token.out"
exit "$(cat "$FAKE_DIR/token.rc" 2>/dev/null || echo 1)"
"""

RDEPS_REF = r"""#!/bin/bash
printf '%s\n' "$*" >> "$FAKE_LOG/rdeps.log"
exit "$(cat "$FAKE_DIR/rdeps.rc" 2>/dev/null || echo 0)"
"""

AFFECTED = r"""#!/bin/bash
printf 'BASE_REF=%s RDEPS_MAP=%s PLAN_BIN=%s KEY=%s LANE=%s RUNFILES_DIR=%s GH_TOKEN=%s\n' \
  "$BASE_REF" "$RDEPS_MAP" "$PLAN_BIN" "$BUILDBUDDY_API_KEY" "$VERIFIED_RUN_LANE" "${RUNFILES_DIR-unset}" "${GH_TOKEN-unset}" >> "$FAKE_LOG/affected.log"
mode="$(cat "$FAKE_DIR/affected.mode" 2>/dev/null || echo test)"
case "$mode" in
  none) exit 0 ;;
  ignore) bazel test --remote_header=x-buildbuddy-api-key="$BUILDBUDDY_API_KEY" //api:lib_test; exit 0 ;;
  *) bazel test --config=remote --remote_header=x-buildbuddy-api-key="$BUILDBUDDY_API_KEY" //api:lib_test -- -//api:skip; exit $? ;;
esac
"""

UNITS = {
    "api/BUILD": 'pipeline_unit(name = "api", test_targets = [":test", ":other_test"], build_flags = ["--test_arg=x"])\n',
    "mac/BUILD": 'pipeline_unit(name = "mac", runner = "xcode-27", test_targets = [":test"])\n',
    "emu/BUILD": 'pipeline_unit(name = "emu", needs_emulator = True, test_targets = [":test"])\n',
    "files/BUILD": 'pipeline_unit(name = "files", artifacts = {"apk": "x.apk"}, test_targets = [":test"])\n',
    "zed/BUILD": 'pipeline_unit(name = "zed", test_targets = ["//zed:t"])\n',
}

PASS_ERR = (
    "\x1b[32mINFO: \x1b[0mStreaming build results to: https://app.buildbuddy.io/invocation/LANE\r\n"
    "INFO: 3 processes: 2 remote, 1 internal.\n"
)


def git(repo, *args):
    env = dict(os.environ, **GIT_ENV)
    out = subprocess.run(
        ["git", "-c", "commit.gpgsign=false", *args],
        cwd=repo,
        env=env,
        capture_output=True,
        text=True,
    )
    if out.returncode != 0:
        raise AssertionError(f"git {args}: {out.stderr}")
    return out.stdout.strip()


def write(root, rel, content, mode=0o644):
    p = os.path.join(root, rel)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    with open(p, "w") as f:
        f.write(content)
    os.chmod(p, mode)


def plan_json(names, degraded=False, files=("api/x.go",)):
    entries = ",".join('{"name":"%s","runner":"r"}' % n for n in names)
    return (
        '{"is_degraded":%s,"sweep_reason":"query failed","changed_files":[%s],"matrix":[%s]}'
        % (
            "true" if degraded else "false",
            ",".join('"%s"' % f for f in files),
            entries,
        )
    )


class VerifiedRunParityTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = os.path.realpath(tempfile.mkdtemp(prefix="vr-parity-"))
        cls.bin = os.path.join(cls.tmp, "fakebin")
        write(cls.bin, "bazel", FAKE_BAZEL, 0o755)
        cls.n = 0

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.tmp, ignore_errors=True)

    # ---- the world ----------------------------------------------------------

    def make_repo(self, name, extra=None, recorder="scout\t314429511\n", key=True):
        origin = os.path.join(self.tmp, name + "-origin.git")
        git(self.tmp, "init", "-q", "--bare", "-b", "main", origin)
        root = os.path.join(self.tmp, name)
        os.makedirs(root)
        git(root, "init", "-q", "-b", "main")
        files = dict(UNITS)
        files.update(
            {
                ".gitignore": "user.bazelrc\n",
                "tools/ci/rdeps-map-ref.sh": RDEPS_REF,
                "tools/ci/affected-targets.sh": AFFECTED,
                "tools/pipeline/verifiedrun/recorder.tsv": "# agent\tbot\n" + recorder,
                "tools/agent-app/agents.tsv": "# agent\tapp\tinst\tbot\nscout\t4521103\t152054588\t314429511\n",
            }
        )
        files.update(extra or {})
        for rel, content in files.items():
            write(root, rel, content)
        git(root, "add", "-A")
        git(root, "commit", "-q", "-m", "base")
        git(root, "remote", "add", "origin", origin)
        git(root, "push", "-q", "origin", "main")
        write(root, "api/x.go", "package api\n")
        git(root, "add", "-A")
        git(root, "commit", "-q", "-m", "change")
        if key:
            write(
                root,
                "user.bazelrc",
                "common --remote_header=x-buildbuddy-api-key=SECRET\n",
            )
        return root

    def setUp(self):
        self.repo = getattr(type(self), "_repo", None)
        if self.repo is None:
            type(self)._repo = self.repo = self.make_repo("repo")

    def norm(self, text, binary, side):
        text = text.replace(binary, "PROG").replace(side, "SIDE")
        text = re.sub(r"verified-run-\d+", "verified-run-N", text)
        return text

    def snapshot(self, repo):
        try:
            return (
                git(repo, "log", "--format=%H %T %s", "-n", "5"),
                git(repo, "status", "--porcelain"),
            )
        except AssertionError:
            return None

    @staticmethod
    def read(p):
        if not os.path.exists(p):
            return None
        with open(p) as f:
            return f.read()

    def run_one(
        self, binary, args, case_dir, env_extra, repo, runfiles_planner, use_runfiles
    ):
        side = os.path.join(case_dir, "go" if binary == VR_GO else "rs")
        logs = os.path.join(side, "logs")
        tmpd = os.path.join(side, "tmp")
        os.makedirs(logs)
        os.makedirs(tmpd)
        rf = os.path.join(side, "runfiles")
        write(rf, "planner", FAKE_PLANNER, 0o755)
        write(rf, "agent-app.sh", FAKE_AGENT_APP, 0o755)
        if runfiles_planner:
            os.remove(os.path.join(rf, "planner"))
            os.symlink(
                PLAN_GO if binary == VR_GO else PLAN_RS, os.path.join(rf, "planner")
            )
        keys = os.path.join(side, "keys")
        os.makedirs(keys, exist_ok=True)
        env = {
            "PATH": self.bin + ":/usr/bin:/bin:/usr/sbin:/sbin",
            "HOME": self.tmp,
            "TMPDIR": tmpd,
            "FAKE_DIR": os.path.join(case_dir, "fake"),
            "FAKE_LOG": logs,
            "BUILD_WORKSPACE_DIRECTORY": repo,
            "AGENT_KEY_DIR": keys,
            "GH_TOKEN": "someone-elses",
            "GITHUB_TOKEN": "someone-elses",
            "GITHUB_OUTPUT": "/dev/null",
        }
        if use_runfiles:
            env["RUNFILES_DIR"] = rf
        env.update(GIT_ENV)
        for k, v in env_extra.items():
            if v is None:
                env.pop(k, None)
            else:
                env[k] = v.replace("{SIDE}", side)
        before = self.snapshot(repo)
        p = subprocess.run(
            [binary, *[a.replace("{SIDE}", side) for a in args]],
            cwd=self.tmp,
            env=env,
            capture_output=True,
        )
        after = self.snapshot(repo)
        result = {
            "rc": p.returncode,
            "stdout": self.norm(p.stdout.decode(errors="replace"), binary, side),
            "stderr": self.norm(p.stderr.decode(errors="replace"), binary, side),
            "repo_unchanged": before == after,
            "temp_left": sorted(os.listdir(tmpd)),
        }
        for name in sorted(os.listdir(logs)):
            with open(os.path.join(logs, name)) as f:
                result["log:" + name] = self.norm(f.read(), binary, side)
        return result

    def check(
        self,
        args=("--planner=planner", "--agent-app=agent-app.sh"),
        *,
        fake=None,
        env=None,
        repo=None,
        real_planner=False,
        use_runfiles=True,
        setup=None,
        expect_rc=None,
        expect_in=None,
    ):
        type(self).n += 1
        case_dir = os.path.join(self.tmp, f"case{self.n}")
        fd = os.path.join(case_dir, "fake")
        os.makedirs(fd)
        defaults = {
            "plan.json": plan_json(["api", "mac", "emu", "files"]),
            "default.test.err": PASS_ERR,
            "default.build.err": PASS_ERR,
        }
        defaults.update(fake or {})
        for name, content in defaults.items():
            if content is not None:
                write(fd, name, content)
        if setup:
            setup(case_dir)
        repo = repo or self.repo
        go = self.run_one(
            VR_GO, list(args), case_dir, env or {}, repo, real_planner, use_runfiles
        )
        rs = self.run_one(
            VR_RS, list(args), case_dir, env or {}, repo, real_planner, use_runfiles
        )
        self.maxDiff = None
        self.assertEqual(go, rs, f"args {args} fake {fake}")
        if expect_rc is not None:
            self.assertEqual(go["rc"], expect_rc, go)
        if expect_in is not None:
            self.assertIn(expect_in, go["stdout"] + go["stderr"], go)
        self.assertTrue(go["repo_unchanged"], go)
        self.assertEqual(go["temp_left"], [], go)
        return go

    NO_RECORD = ("--planner=planner", "--agent-app=agent-app.sh", "--no-record")

    # ---- runs that pass --------------------------------------------------------

    def test_pass_without_record(self):
        self.check(self.NO_RECORD, expect_rc=0, expect_in="Not recorded (--no-record).")
        # The planner also calls bazel, through the shim, untouched.
        self.check(
            self.NO_RECORD,
            fake={"plan.query": "1", "default.query.out": "//api:test\n"},
            expect_rc=0,
        )
        # One BuildBuddy run for everything links that run.
        self.check(
            self.NO_RECORD,
            fake={"plan.json": plan_json([])},
            expect_rc=0,
            expect_in="invocation/LANE",
        )
        # Units in another order, a unit twice.
        self.check(
            self.NO_RECORD,
            fake={"plan.json": plan_json(["zed", "api", "api"])},
            expect_rc=0,
        )

    def test_record_refusals_before_the_post(self):
        # No key in AGENT_KEY_DIR.
        self.check(expect_rc=3, expect_in="its private key is not at")

        # The key, but the token command fails / prints nothing.
        def key(case_dir):
            for side in ("go", "rs"):
                write(os.path.join(case_dir, side, "keys"), "scout.pem", "fake")

        self.check(
            setup=key,
            fake={"token.err": "openssl: bad key\n", "token.rc": "1"},
            expect_rc=3,
        )
        self.check(
            setup=key,
            fake={"token.out": "  \n", "token.rc": "0"},
            expect_rc=3,
            expect_in="empty token",
        )
        self.check(setup=key, fake={"token.rc": "2"}, expect_rc=3)
        # The default key folder: the main checkout's agent-keys.
        self.check(env={"AGENT_KEY_DIR": None}, expect_rc=3)
        self.check(env={"AGENT_KEY_DIR": ""}, expect_rc=3)
        # recorder.tsv problems.
        for name, rec in [
            ("nobody", ""),
            ("two", "scout\t314429511\nwren\t1\n"),
            ("mismatch", "scout\t1\n"),
            ("ghost", "ghost\t314429511\n"),
            ("bad", "scout\n"),
        ]:
            repo = self.make_repo("rec-" + name, recorder=rec)
            self.check(repo=repo, expect_rc=3)
        repo = self.make_repo(
            "rec-missing", extra={"tools/agent-app/agents.tsv": "# none\n"}
        )
        self.check(repo=repo, expect_rc=3)

    def test_runs_that_must_not_count(self):
        no_link = "INFO: 3 processes: 2 remote, 1 internal.\n"
        cases = [
            {"build-test.test.rc": "3"},
            {"unit_api.test.rc": "3"},
            {
                "unit_api.test.rc": "4",
                "unit_api.test.err": "ERROR: No test targets were found\n"
                + PASS_ERR.splitlines()[0]
                + "\n",
            },
            {"unit_api.test.rc": "4", "unit_api.build.rc": "1"},
            {
                "default.test.err": PASS_ERR.replace(
                    "2 remote, 1 internal", "2 darwin-sandbox, 1 remote"
                )
            },
            {
                "default.test.err": PASS_ERR.replace(
                    "2 remote, 1 internal", "1 disk cache hit"
                )
            },
            {"default.test.err": PASS_ERR.replace("2 remote, 1 internal", "lots")},
            {"default.test.err": no_link},
            {"default.test.err": PASS_ERR.splitlines()[0] + "\n"},
            {
                "default.test.err": "INFO: 0 processes.\n"
                + PASS_ERR.splitlines()[0]
                + "\n"
            },
            {"affected.mode": "ignore", "build-test.test.rc": "1"},
            {"affected.mode": "none", "plan.json": plan_json(["mac"])},
            {"plan.json": None, "plan.rc": "1", "plan.err": "planner exploded\n"},
            {"plan.json": "not json"},
            {"plan.json": ""},
            {"plan.json": '{"matrix":[{"name":5}]}'},
            {"plan.json": '{"matrix":"x"}'},
            {"plan.json": plan_json(["api"], degraded=True)},
            {"plan.json": plan_json(["ghost"])},
            {"rdeps.rc": "1"},
            {
                "default.test.err": PASS_ERR
                + ("x" * 70000)
                + "\n"
                + "no newline at the end"
            },
        ]
        for fake in cases:
            self.check(self.NO_RECORD, fake=fake)

    def test_setup_refusals(self):
        self.check(env={"BUILD_WORKSPACE_DIRECTORY": None}, expect_rc=2)
        self.check(("--planner=nope", "--agent-app=agent-app.sh"), expect_rc=2)
        self.check(("--planner=planner", "--agent-app=nope"), expect_rc=2)
        self.check(
            ("--planner=planner", "--agent-app=agent-app.sh"),
            use_runfiles=False,
            expect_rc=2,
        )
        self.check(
            ("--agent-app=agent-app.sh", "--no-record")
        )  # the planner is the runfiles dir itself
        self.check(
            env={"PATH": "/usr/bin:/bin"}, expect_rc=2, expect_in="bazel is not on PATH"
        )
        dirty = self.make_repo("dirty")
        write(dirty, "untracked.txt", "x\n")
        self.check(repo=dirty, expect_rc=2)
        nokey = self.make_repo("nokey", key=False)
        self.check(repo=nokey, expect_rc=2, expect_in="no BuildBuddy key")
        broken = self.make_repo(
            "broken",
            extra={
                "bad/BUILD": 'pipeline_unit(name = "bad", test_targets = TARGETS)\n'
            },
        )
        self.check(repo=broken, expect_rc=2)
        # No origin at all: the fetch warns, then there is no merge base.
        lone = os.path.join(self.tmp, "lone")
        os.makedirs(lone)
        git(lone, "init", "-q", "-b", "main")
        write(lone, "a.txt", "x\n")
        write(
            lone, "user.bazelrc", "common --remote_header=x-buildbuddy-api-key=SECRET\n"
        )
        write(lone, ".gitignore", "user.bazelrc\n")
        git(lone, "add", "-A")
        git(lone, "commit", "-q", "-m", "one")
        self.check(repo=lone, expect_rc=2)
        # An origin that cannot be fetched, but origin/main is already here.
        stale = self.make_repo("stale")
        git(stale, "remote", "set-url", "origin", os.path.join(self.tmp, "gone.git"))
        self.check(
            self.NO_RECORD,
            repo=stale,
            expect_rc=0,
            expect_in="could not fetch origin/main",
        )
        # Not a repository.
        plain = os.path.join(self.tmp, "plainrepo")
        os.makedirs(plain)
        self.check(repo=plain, expect_rc=2)

    def test_worktree_uses_the_main_checkouts_key(self):
        wt = os.path.join(self.tmp, "wt")
        git(self.repo, "worktree", "add", "-q", "--detach", wt)
        self.check(self.NO_RECORD, repo=wt, expect_rc=0, expect_in="")
        r = self.check(self.NO_RECORD, repo=wt)
        self.assertIn(
            "--bazelrc=" + os.path.join(self.repo, "user.bazelrc"), r["log:bazel.log"]
        )

    def test_with_the_real_planners(self):
        # Each tool with its own planner: the Go pair against the Rust pair.
        self.check(
            self.NO_RECORD,
            real_planner=True,
            fake={"default.query.out": "//api:test\n"},
        )
        self.check(
            self.NO_RECORD,
            real_planner=True,
            fake={"default.query.rc": "1", "default.query.err": "boom\n"},
        )

    def test_flags(self):
        for args in (
            ["-h"],
            ["-help"],
            ["-nope"],
            ["--no-record=maybe"],
            ["--planner"],
            ["---x"],
            [
                "--planner=planner",
                "--agent-app=agent-app.sh",
                "--no-record=false",
                "x",
                "--no-record",
            ],
        ):
            self.check(args)

    # ---- the shim, called directly ----------------------------------------------

    def shim(self, args, env, case_name):
        type(self).n += 1
        out = {}
        for binary in (VR_GO, VR_RS):
            side = os.path.join(
                self.tmp, f"shim{self.n}", "go" if binary == VR_GO else "rs"
            )
            os.makedirs(os.path.join(side, "logs"))
            e = {
                "PATH": self.bin + ":/usr/bin:/bin",
                "FAKE_DIR": os.path.join(self.tmp, f"shim{self.n}", "fake"),
                "FAKE_LOG": os.path.join(side, "logs"),
            }
            for k, v in env.items():
                e[k] = v.replace("{SIDE}", side)
            p = subprocess.run(
                [binary, "__shim", *args],
                env=e,
                capture_output=True,
                input=b"stdin data\n",
            )
            res = {
                "rc": p.returncode,
                "stdout": p.stdout.decode(),
                "stderr": self.norm(p.stderr.decode(), binary, side),
            }
            log = self.read(os.path.join(side, "logs", "bazel.log"))
            res["bazel.log"] = self.norm(log, binary, side) if log is not None else None
            res["inv"] = self.read(os.path.join(side, "inv.jsonl"))
            out[binary] = res
        self.assertEqual(out[VR_GO], out[VR_RS], case_name)
        return out[VR_GO]

    def test_shim_directly(self):
        os.makedirs(os.path.join(self.tmp, "shimfake"), exist_ok=True)
        base = {
            "VERIFIED_RUN_REAL_BAZEL": os.path.join(self.bin, "bazel"),
            "VERIFIED_RUN_LOG": "{SIDE}/inv.jsonl",
            "VERIFIED_RUN_STARTUP": "--bazelrc=/main/user.bazelrc",
            "VERIFIED_RUN_STRICT": "--config=remote\n--spawn_strategy=remote",
            "VERIFIED_RUN_LANE": "unit:a<b>&c",
        }
        self.shim(["version"], {}, "no real bazel")
        self.shim(["query", "//..."], base, "passthrough")
        self.shim(["--nohome_rc"], base, "startup only")
        self.shim(
            [
                "test",
                "--config=remote",
                "--remote_header=x-buildbuddy-api-key=S",
                "//a:t",
                "--",
                "-//b:t",
            ],
            base,
            "test",
        )
        self.shim(["build"], base, "no targets")
        self.shim(
            ["test", "//a:t"],
            dict(base, VERIFIED_RUN_LOG="{SIDE}/no/dir/inv.jsonl"),
            "unwritable log",
        )
        self.shim(["test", "//a:t"], dict(base, VERIFIED_RUN_LOG=""), "no log")
        self.shim(
            ["test", "//a:t"],
            dict(base, VERIFIED_RUN_REAL_BAZEL="no-such-bazel"),
            "bare name not found",
        )
        self.shim(
            ["query"],
            dict(base, VERIFIED_RUN_REAL_BAZEL="no-such-bazel"),
            "bare name not found, query",
        )
        self.shim(
            ["test", "//a:t"],
            dict(base, VERIFIED_RUN_REAL_BAZEL="bazel"),
            "bare name found",
        )


if __name__ == "__main__":
    unittest.main()
