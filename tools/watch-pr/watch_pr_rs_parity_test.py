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

"""watch-pr.sh and its Rust port, side by side.

The script classifies checks with python3 (its first choice); here that is
the pinned interpreter, put on PATH as python3, so the answer is the same on
every host. Two layers:

  parse_checks_json   the script's function (sourced) against the port's
                      probe over a few thousand checks answers: exit code,
                      stdout and stderr must match. Malformed JSON is the
                      exception: Python's json and serde_json word their
                      errors differently, so those compare exit code and the
                      PARSE_ERROR marker.

  end to end          both programs through every phase against a mock gh,
                      a mock bazel and scratch git repositories, with
                      scripted and real pipeline-status.sh. Exit code,
                      stdout, stderr and the gh/bazel calls (with the
                      GH_TOKEN each saw) must match once the clock and
                      elapsed seconds are masked. Scenarios that spin until
                      a timeout compare with repeated lines collapsed.
"""

import concurrent.futures
import json
import os
import random
import re
import shutil
import stat
import subprocess
import sys
import tempfile
import unittest

HOST_TOOLS = [
    "bash",
    "sh",
    "git",
    "cat",
    "env",
    "head",
    "tail",
    "grep",
    "cut",
    "date",
    "sleep",
    "mkdir",
    "rm",
    "mktemp",
    "dirname",
    "basename",
    "tr",
    "sed",
    "expr",
    "uname",
    "ls",
    "printf",
    "xcrun",
    "seq",
    "awk",
]

MOCK = r"""#!/bin/sh
d="$MOCK_DIR"
tool="$(basename "$0")"
{ printf '%s' "$tool"; printf '\037token=%s' "${GH_TOKEN-<unset>}"; for a in "$@"; do printf '\037%s' "$a"; done; printf '\036\n'; } >> "$d/calls.log"
case "$tool $*" in
  "gh api repos/"*"/actions/runs"*) key=runs ;;
  "gh api repos/"*"/pulls"*) key=pulls ;;
  "gh pr view "*"mergeCommit -q"*) key=merge ;;
  "gh pr view "*) key=view ;;
  "gh pr checks "*) key=checks ;;
  "gh pr list "*) key=list ;;
  "gh run view "*) key=runlog ;;
  "bazel run //tools/agent-app"*) key=agentapp ;;
  "bazel run //tools/pipeline-status"*) key=pstatus ;;
  *) key=other ;;
esac
n=$(cat "$d/$key.count" 2>/dev/null || echo 0); n=$((n + 1)); echo "$n" > "$d/$key.count"
i=$n
while [ "$i" -gt 1 ] && [ ! -e "$d/$key.$i.out" ]; do i=$((i - 1)); done
if [ ! -e "$d/$key.$i.out" ]; then exit 1; fi
cat "$d/$key.$i.out"
[ -e "$d/$key.$i.err" ] && cat "$d/$key.$i.err" >&2
exit "$(cat "$d/$key.$i.rc" 2>/dev/null || echo 0)"
"""

# A pipeline-status.sh stand-in: answers from a sequence, like the mocks.
SCRIPTED_PIPELINE = r"""#!/usr/bin/env bash
d="$MOCK_DIR"
n=$(cat "$d/script.count" 2>/dev/null || echo 0); n=$((n + 1)); echo "$n" > "$d/script.count"
i=$n
while [ "$i" -gt 1 ] && [ ! -e "$d/script.$i.out" ]; do i=$((i - 1)); done
echo "pipeline-status called with: $*"
cat "$d/script.$i.out"
echo "to stderr" >&2
exit "$(cat "$d/script.$i.rc")"
"""

SHA = "0123456789abcdef0123456789abcdef01234567"


def runfile(name):
    return os.path.abspath(os.environ[name])


def write(path, text, executable=False):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        f.write(text)
    if executable:
        os.chmod(
            path, os.stat(path).st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH
        )


def git(repo, *args):
    subprocess.run(
        ["git", "-C", repo, *args],
        check=True,
        capture_output=True,
        env={
            "PATH": os.environ.get("PATH", "") + ":/usr/bin:/bin",
            "HOME": repo,
            "GIT_CONFIG_NOSYSTEM": "1",
            # Fixed dates: both programs' repositories get the same SHAs.
            "GIT_AUTHOR_DATE": "2026-10-25T00:00:00Z",
            "GIT_COMMITTER_DATE": "2026-10-25T00:00:00Z",
        },
    )


def scratch_repo(parent, titles=("feat: other (#7)",)):
    repo = tempfile.mkdtemp(dir=parent)
    git(repo, "init", "-q", "-b", "main")
    git(repo, "config", "user.email", "t@t")
    git(repo, "config", "user.name", "t")
    for i, msg in enumerate(("base",) + tuple(titles)):
        write(os.path.join(repo, "f.txt"), str(i))
        git(repo, "add", "-A")
        git(repo, "commit", "-qm", msg)
    git(repo, "update-ref", "refs/remotes/origin/main", "refs/heads/main")
    return repo


def seq(mock_dir, key, items):
    """items: list of (stdout, rc)."""
    for i, (out, rc) in enumerate(items, 1):
        write(os.path.join(mock_dir, "%s.%d.out" % (key, i)), out)
        write(os.path.join(mock_dir, "%s.%d.rc" % (key, i)), str(rc))


# --- checks answers -----------------------------------------------------------

STATES = [
    "SUCCESS",
    "FAILURE",
    "IN_PROGRESS",
    "QUEUED",
    "PENDING",
    "SKIPPED",
    "NEUTRAL",
    "CANCELLED",
    "TIMED_OUT",
    "ERROR",
    "STARTUP_FAILURE",
    "WAITING",
    "FAILED",
    "ACTION_REQUIRED",
    "STALE",
    "",
    "success",
    "failure",
    "ſuccess",
    "ﬁled",
    "ﬀ",
]
BUCKETS = ["pass", "fail", "pending", "skipping", "cancel", "", "PASS"]
NAMES = [
    "CI",
    "lint",
    "unit-test",
    "na|me",
    "with:colon",
    "é ✓",
    "tab\there",
    "new\nline",
    "quote's",
    'dq"',
    "back\\slash",
    "\u00a0nbsp",
    "\u200bzw",
    "\x7fdel",
    "\U000e0001tag",
]
ODD = [
    None,
    True,
    False,
    0,
    1,
    -7,
    2.5,
    1e16,
    1e-5,
    0.1,
    "",
    [],
    {},
    ["a", 1, None, 1.0],
    {"k": "v'", "n": [True]},
    "it's",
    ["\u00a0", "\u200b", "\x01", "é"],
    12345678901234,
]


def odd(rng, choices):
    return rng.choice(ODD) if rng.random() < 0.2 else rng.choice(choices)


def check(rng):
    if rng.random() < 0.02:
        return rng.choice([None, 1, "s", [], True])
    fields = {
        "name": lambda: odd(rng, NAMES),
        "state": lambda: odd(rng, STATES),
        "bucket": lambda: odd(rng, BUCKETS),
        "workflow": lambda: odd(rng, ["ci", "delivery", "", "w|f"]),
        "link": lambda: odd(
            rng,
            ["https://github.com/o/r/actions/runs/123/job/4", "", "https://ci.run/1"],
        ),
        "url": lambda: odd(rng, ["https://u/runs/9", ""]),
    }
    c = {}
    keys = list(fields)
    rng.shuffle(keys)
    for k in keys:
        if rng.random() < 0.8:
            c[k] = fields[k]()
    return c


def realistic(rng):
    out = []
    for i in range(rng.randint(1, 30)):
        state = rng.choice(
            ["SUCCESS"] * 6 + ["IN_PROGRESS", "QUEUED", "SKIPPED", "FAILURE", "NEUTRAL"]
        )
        bucket = {
            "SUCCESS": "pass",
            "NEUTRAL": "pass",
            "SKIPPED": "skipping",
            "FAILURE": "fail",
        }.get(state, "pending")
        out.append(
            {
                "bucket": bucket,
                "link": "https://github.com/VitruvianSoftware/vitruvian-core/"
                "actions/runs/%d/job/%d" % (rng.randint(1, 10**10), i),
                "name": rng.choice(
                    ["build-test", "lint", "gate/all-required", "tidy-check"]
                )
                + str(i),
                "state": state,
                "workflow": rng.choice(["ci", "presubmit", ""]),
            }
        )
    return json.dumps(out, separators=(",", ":"))


def answers():
    rng = random.Random(20261025)
    out = [
        '[{"name":"CI","state":"SUCCESS","bucket":"pass","workflow":"ci","link":"https://ci.run/1"}]',
        '[{"name":"unit-test","state":"FAILURE","bucket":"fail","workflow":"ci","link":"https://ci.run/99"}]',
        '[{"name":"delivery","state":"SKIPPED","bucket":"skipping","workflow":"delivery","link":""},'
        '{"name":"integration","state":"IN_PROGRESS","bucket":"pending","workflow":"ci","link":""}]',
        '[{"a":1,"name":"x","a":2,"state":"FAILURE","name":"y"}]',
        "{}",
        '""',
        "[]",
        '{"a":1}',
        '"ab"',
        "5",
        "true",
        "null",
        " [ ] ",
        "1.5",
    ]
    out += [realistic(rng) for _ in range(600)]
    for _ in range(2400):
        items = [check(rng) for _ in range(rng.randint(0, 8))]
        out.append(json.dumps(items, ensure_ascii=rng.random() < 0.5))
    out += [
        "not json",
        "[",
        "[1,]",
        "{'a':1}",
        '["unterminated',
        "[] []",
        "\ufeff[]",
        "[01]",
    ]
    return out


def last_line(text):
    return text.strip().split(b"\n")[-1]


# --- normalisation -----------------------------------------------------------

CLOCK = re.compile(rb"\[\d\d:\d\d:\d\d\]")
ELAPSED = [
    (re.compile(rb"\(\d+s elapsed\)"), b"(Ns elapsed)"),
    (re.compile(rb" in \d+s!"), b" in Ns!"),
    (re.compile(rb"Total time: \d+s\)"), b"Total time: Ns)"),
    (re.compile(rb"\(\d+s/60s grace period\)"), b"(Ns/60s grace period)"),
]


def normalise(text, progs, collapse):
    text = CLOCK.sub(b"[T]", text)
    for pat, rep in ELAPSED:
        text = pat.sub(rep, text)
    for prog in progs:
        text = text.replace(prog.encode(), b"PROG")
    if collapse:
        # A loop that spins until a deadline runs a different number of times
        # in each program: keep each distinct line once, in first-seen order.
        kept = []
        for line in text.split(b"\n"):
            if line not in kept:
                kept.append(line)
        text = b"\n".join(kept)
    return text


def calls_of(mock_dir, collapse):
    path = os.path.join(mock_dir, "calls.log")
    if not os.path.exists(path):
        return []
    with open(path, "rb") as f:
        records = f.read().split(b"\x1e\n")[:-1]
    if collapse:
        seen = []
        for r in records:
            if r not in seen:
                seen.append(r)
        return seen
    return records


class Parity(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.mkdtemp()
        cls.sh = runfile("WATCH_PR_SH")
        cls.rs = runfile("WATCH_PR_RS")
        cls.probe = runfile("WATCH_PR_RS_PROBE")
        cls.pipeline_sh = runfile("PIPELINE_STATUS_SH")
        cls.tools = os.path.join(cls.tmp, "tools")
        cls.py = os.path.join(cls.tmp, "py")
        os.makedirs(cls.tools)
        os.makedirs(cls.py)
        host_path = os.environ.get("PATH", "") + ":/usr/bin:/bin"
        for tool in HOST_TOOLS:
            found = shutil.which(tool, path=host_path)
            if found:
                os.symlink(found, os.path.join(cls.tools, tool))
        write(
            os.path.join(cls.py, "python3"),
            '#!/bin/sh\nexec "%s" -I "$@"\n' % sys.executable,
            True,
        )
        cls.home = os.path.join(cls.tmp, "home")
        os.makedirs(cls.home)
        cls.pool = concurrent.futures.ThreadPoolExecutor(
            max_workers=max(8, (os.cpu_count() or 4) * 2)
        )

    @classmethod
    def tearDownClass(cls):
        cls.pool.shutdown()
        shutil.rmtree(cls.tmp, ignore_errors=True)

    def env(self, mock_bin, mock_dir, extra=None, with_bazel=True):
        env = {
            "PATH": ":".join([mock_bin, self.py, self.tools]),
            "HOME": self.home,
            "GIT_CONFIG_NOSYSTEM": "1",
            "TZ": "UTC",
            "MOCK_DIR": mock_dir,
            "GH_TOKEN": "test-token",
        }
        for k, v in (extra or {}).items():
            if v is None:
                env.pop(k, None)
            else:
                env[k] = v
        return env

    # -- the pinned Python's printable table --------------------------------------

    def test_printable_table_is_current(self):
        here = os.path.dirname(self.sh)
        got = subprocess.run(
            [sys.executable, "-I", os.path.join(here, "gen_unicode_tables.py")],
            capture_output=True,
            text=True,
            check=True,
        ).stdout
        with open(os.path.join(here, "src", "pyprint.rs")) as f:
            self.assertEqual(
                got, f.read(), "regenerate src/pyprint.rs with gen_unicode_tables.py"
            )

    # -- parse_checks_json -------------------------------------------------------

    def parse(self, impl, text):
        env = {"PATH": ":".join([self.py, self.tools]), "HOME": self.home}
        if impl == "rs":
            cmd = [self.probe, "parse-checks-json", text]
        else:
            cmd = [
                "bash",
                "-c",
                'source "$1"; parse_checks_json "$2"',
                "_",
                self.sh,
                text,
            ]
        p = subprocess.run(cmd, env=env, capture_output=True, timeout=60)
        return p.returncode, p.stdout, p.stderr

    def test_parse_checks_json(self):
        corpus = answers()
        results = self.pool.map(
            lambda t: (t, self.parse("rs", t), self.parse("sh", t)), corpus
        )
        stats = {"exact": 0, "parse-error": 0, "traceback": 0}
        problems = []
        for text, rs, sh in results:
            if sh[1].startswith(b"PARSE_ERROR: "):
                stats["parse-error"] += 1
                if rs[0] != sh[0] or not rs[1].startswith(b"PARSE_ERROR: "):
                    problems.append(
                        "%r: parse error handled differently\n rs=%r\n sh=%r"
                        % (text, rs, sh)
                    )
            elif sh[0] == 1 and b"Traceback" in sh[2]:
                stats["traceback"] += 1
                if (rs[0], rs[1], last_line(rs[2])) != (sh[0], sh[1], last_line(sh[2])):
                    problems.append(
                        "%r: exception differs\n rs=%r\n sh=%r" % (text, rs, sh)
                    )
            elif rs != sh:
                problems.append("%r:\n rs=%r\n sh=%r" % (text, rs, sh))
            else:
                stats["exact"] += 1
        print("parse_checks_json:", len(corpus), "answers", stats)
        self.assertEqual(problems, [], "\n".join(problems[:15]))
        self.assertGreater(stats["exact"], 2800)

    # -- end to end ------------------------------------------------------------------

    def program(self, impl, sc):
        mock_dir = tempfile.mkdtemp(dir=self.tmp)
        mock_bin = os.path.join(mock_dir, "bin")
        os.makedirs(mock_bin)
        for tool in sc.get("tools", ["gh", "bazel"]):
            write(os.path.join(mock_bin, tool), MOCK, True)
        for key, items in sc.get("mock", {}).items():
            seq(mock_dir, key, items)
        repo = scratch_repo(self.tmp, sc.get("titles", ("feat: other (#7)",)))
        pipeline = sc.get("pipeline")
        target = os.path.join(repo, "tools", "pipeline-status", "pipeline-status.sh")
        if pipeline == "real":
            os.makedirs(os.path.dirname(target), exist_ok=True)
            shutil.copy(self.pipeline_sh, target)
        elif pipeline is not None:
            write(target, SCRIPTED_PIPELINE, True)
            seq(mock_dir, "script", pipeline)
        if sc.get("agent_app"):
            write(os.path.join(repo, "tools", "agent-app", "BUILD"), "# agent-app\n")
        extra = {"BUILD_WORKSPACE_DIRECTORY": repo}
        extra.update(sc.get("env", {}))
        if extra.get("BUILD_WORKSPACE_DIRECTORY") == "<subdir>":
            extra["BUILD_WORKSPACE_DIRECTORY"] = None
        cwd = repo
        if sc.get("cwd") == "subdir":
            cwd = os.path.join(repo, "tools")
            os.makedirs(cwd, exist_ok=True)
        cmd = ([self.rs] if impl == "rs" else ["bash", self.sh]) + sc["args"]
        p = subprocess.run(
            cmd,
            env=self.env(mock_bin, mock_dir, extra),
            cwd=cwd,
            capture_output=True,
            timeout=240,
        )
        collapse = sc.get("spins", False)
        progs = [self.sh, self.rs, repo]
        return (
            p.returncode,
            normalise(p.stdout, progs, collapse),
            normalise(p.stderr, progs, collapse),
            [normalise(c, progs, False) for c in calls_of(mock_dir, collapse)],
        )

    def scenarios(self):
        merged = (
            '{"state":"MERGED","mergeStateStatus":"CLEAN","mergeCommit":{"oid":"%s"}}'
            % SHA,
            0,
        )
        open_ = ('{"state":"OPEN","mergeStateStatus":"BLOCKED","mergeCommit":null}', 0)
        queued = ('{"state":"OPEN","mergeCommit":null}', 0)
        closed = ('{"state":"CLOSED","mergeStateStatus":"DIRTY","mergeCommit":null}', 0)
        passing = (
            '[{"name":"CI","state":"SUCCESS","bucket":"pass","workflow":"ci","link":"https://ci.run/1"}]',
            0,
        )
        pending = (
            '[{"name":"CI","state":"IN_PROGRESS","bucket":"pending","workflow":"ci","link":""}]',
            8,
        )
        skipped = (
            '[{"name":"CI","state":"SKIPPED","bucket":"skipping","workflow":"ci","link":""}]',
            0,
        )
        failing = (
            '[{"name":"integration-test","state":"FAILURE","bucket":"fail","workflow":"ci",'
            '"link":"https://github.com/o/r/actions/runs/999/job/1"},'
            '{"name":"lint|x","state":"FAILURE","bucket":"fail","workflow":"lint","link":"https://ci.run/2"},'
            '{"name":"ok","state":"SUCCESS","bucket":"pass","workflow":"ci","link":""}]',
            1,
        )
        runlog = ("".join("log line %d\n" % i for i in range(40)), 0)
        q = ["--interval", "0"]
        S = []

        def add(name, args, **kw):
            kw["args"] = args
            kw["name"] = name
            S.append(kw)

        # Arguments.
        for args in [
            [],
            ["--bogus"],
            ["-"],
            ["--help"],
            ["-h"],
            ["42", "43"],
            ["--timeout"],
            ["--interval"],
            ["42", "--bogus"],
            ["--help", "--bogus"],
            ["--bogus", "--help"],
            [""],
            ["", "42"],
            ["42", "--timeout"],
            ["--", "42"],
        ]:
            # Those that get past the arguments land on a merged PR, fast.
            add(
                "args %r" % args,
                args,
                mock={"view": [merged]},
                env={
                    "WATCH_PR_SKIP_POST_MERGE": "true",
                    "WATCH_PR_INTERVAL": "0",
                    "WATCH_PR_TIMEOUT": "5",
                },
            )
        # --timeout values, through bash arithmetic.
        for t in [
            "0",
            "-5",
            "",
            " 7 ",
            "010",
            "0x10",
            "08",
            "1.5",
            "abc",
            "5abc",
            "1 2",
            "x+1",
            "TIMEOUT",
            "2#101",
            "64#z",
            "2*3",
            "(1+2)",
            "10/0",
            "--5",
            "REPO",
            "1e3",
            "3%0",
        ]:
            add(
                "timeout %r" % t,
                ["42", "--skip-post-merge", "--timeout", t] + q,
                mock={"view": [merged]},
            )
        add(
            "timeout env",
            ["42", "--skip-post-merge"] + q,
            mock={"view": [merged]},
            env={"WATCH_PR_TIMEOUT": "0"},
        )
        add(
            "timeout names an env var",
            ["42", "--skip-post-merge", "--timeout", "MY_T"] + q,
            mock={"view": [merged]},
            env={"MY_T": "30"},
        )
        # Resolving the target.
        for target, mock in [
            ("#42", {"view": [merged]}),
            ("feature/x", {"list": [("42", 0)], "view": [merged]}),
            (
                "feature/x",
                {"list": [("null", 0)], "pulls": [("42", 0)], "view": [merged]},
            ),
            ("feature/x", {"list": [("", 1)], "pulls": [("", 1)]}),
            (SHA, {"list": [("", 0)], "pulls": [("43", 0)], "view": [merged]}),
            ("#", {}),
            ("#7", {"view": [merged]}),
            ("abc", {}),
        ]:
            add(
                "target %r %s" % (target, sorted(mock)),
                [target, "--skip-post-merge"] + q,
                mock=mock,
            )
        add(
            "target found only in main's log",
            ["landed", "--skip-post-merge"] + q,
            mock={"view": [merged]},
            titles=("feat: x (#landed)",),
        )
        # Phase 1.
        add("already merged", ["42", "--skip-post-merge"] + q, mock={"view": [merged]})
        add(
            "pending then passing then merge queue",
            ["42", "--skip-post-merge"] + q,
            mock={
                "view": [open_, open_, open_, open_, queued, merged],
                "checks": [pending, pending, passing],
            },
        )
        add(
            "checks fail with logs",
            ["42"] + q,
            mock={"view": [open_], "checks": [failing], "runlog": [runlog]},
        )
        add(
            "checks fail, gh run view fails",
            ["42"] + q,
            mock={
                "view": [open_],
                "checks": [failing],
                "runlog": [("partial\nno newline", 1)],
            },
        )
        add(
            "no checks yet, then squash on main",
            ["7", "--skip-post-merge"] + q,
            mock={"view": [open_], "checks": [("[]", 0)]},
        )
        add(
            "no checks yet (null), then passing",
            ["42", "--skip-post-merge"] + q,
            mock={
                "view": [open_, open_, open_, merged],
                "checks": [("null", 0), ("", 1), passing],
            },
        )
        add(
            "all skipped waits for the merge",
            ["42", "--skip-post-merge"] + q,
            mock={"view": [open_, open_, merged], "checks": [skipped]},
        )
        add(
            "malformed checks",
            ["42", "--skip-post-merge"] + q,
            mock={"view": [open_, merged], "checks": [("5", 0)]},
        )
        add(
            "checks forever: timeout",
            ["42", "--timeout", "2"] + q,
            mock={"view": [open_], "checks": [pending]},
            spins=True,
        )
        add(
            "no checks forever: timeout",
            ["42", "--timeout", "2"] + q,
            mock={"view": [open_], "checks": [("[]", 0)]},
            spins=True,
        )
        add(
            "bad interval goes to sleep",
            ["42", "--timeout", "2", "--interval", "abc"],
            mock={"view": [open_], "checks": [pending]},
            spins=True,
        )
        add(
            "fractional interval",
            ["42", "--skip-post-merge", "--interval", "0.01"],
            mock={"view": [open_, open_, merged], "checks": [pending]},
        )
        # Phase 2.
        add(
            "merge queue then MERGED",
            ["42", "--skip-post-merge"] + q,
            mock={"view": [open_, queued, open_, merged], "checks": [passing]},
        )
        add(
            "closed unmerged",
            ["42"] + q,
            mock={"view": [open_, closed], "checks": [passing]},
        )
        add(
            "squash appears on main in phase 2",
            ["7", "--skip-post-merge"] + q,
            mock={"view": [open_], "checks": [passing]},
        )
        add(
            "phase 2 timeout",
            ["42", "--timeout", "3"] + q,
            mock={"view": [open_], "checks": [passing]},
            spins=True,
        )
        # Phase 3.
        for name, pipeline in [
            ("green", [("ok ✓ passed\nnoise", 0)]),
            ("red", [("FAILED: details", 1)]),
            ("in flight then green", [("", 2), ("", 2), ("All passed", 0)]),
            ("unexpected code then green", [("", 5), ("", 0)]),
            ("no runs: timeout in the grace period", [("", 3)]),
        ]:
            add(
                "post-merge %s" % name,
                ["42", "--timeout", "3"] + q,
                mock={"view": [merged], "merge": [(SHA, 0)]},
                pipeline=pipeline,
                spins=name.startswith("no runs"),
            )
        add(
            "post-merge grace period ends green",
            ["42", "--timeout", "200", "--interval", "1"],
            mock={"view": [merged], "merge": [(SHA, 0)]},
            pipeline=[("", 3)],
            spins=True,
        )
        add(
            "post-merge real pipeline-status green",
            ["42"] + q,
            mock={
                "view": [merged],
                "merge": [(SHA, 0)],
                "runs": [
                    (
                        '{"workflow_runs":[{"name":"CI","status":"completed","conclusion":"success"}]}',
                        0,
                    )
                ],
            },
            pipeline="real",
        )
        add(
            "post-merge real pipeline-status red",
            ["42"] + q,
            mock={
                "view": [merged],
                "merge": [(SHA, 0)],
                "runs": [
                    (
                        '{"workflow_runs":[{"name":"CI","status":"completed","conclusion":"failure","html_url":"u"}]}',
                        0,
                    )
                ],
            },
            pipeline="real",
        )
        add(
            "merge sha from main's log",
            ["7"] + q,
            mock={"view": [merged], "merge": [("", 0)]},
            pipeline=[("green ✓", 0)],
        )
        add(
            "no merge sha anywhere",
            ["42"] + q,
            mock={"view": [merged], "merge": [("", 1)]},
        )
        add(
            "merge sha is whatever gh says",
            ["42"] + q,
            mock={"view": [merged], "merge": [("{}", 0)]},
            pipeline=[("x", 0)],
        )
        add(
            "post-merge through bazel",
            ["42"] + q,
            mock={
                "view": [merged],
                "merge": [(SHA, 0)],
                "pstatus": [("", 2), ("ok ✓", 0)],
            },
        )
        add(
            "post-merge through bazel, red",
            ["42"] + q,
            mock={"view": [merged], "merge": [(SHA, 0)], "pstatus": [("boom", 1)]},
        )
        add(
            "post-merge with neither",
            ["42"] + q,
            mock={"view": [merged], "merge": [(SHA, 0)]},
            tools=["gh"],
        )
        add(
            "skip post-merge from the environment",
            ["42"] + q,
            mock={"view": [merged]},
            env={"WATCH_PR_SKIP_POST_MERGE": "true"},
        )
        # Setup.
        add("no gh", ["42"], tools=["bazel"])
        add(
            "other repo",
            ["42", "--skip-post-merge"] + q,
            mock={"view": [merged]},
            env={"WATCH_PR_REPO": "o/r"},
        )
        add(
            "workspace from git",
            ["42", "--skip-post-merge"] + q,
            mock={"view": [merged]},
            env={"BUILD_WORKSPACE_DIRECTORY": "<subdir>"},
            cwd="subdir",
        )
        add(
            "workspace missing",
            ["42"],
            env={"BUILD_WORKSPACE_DIRECTORY": "/nonexistent/dir"},
        )
        exports = (
            "export GH_TOKEN=ghs_minted\nexport GIT_AUTHOR_NAME='scout[bot]'\n"
            'export WATCH_PR_X="a b"\n'
        )
        add(
            "token minted by agent-app",
            ["42", "--skip-post-merge"] + q,
            mock={"view": [merged], "agentapp": [(exports, 0)]},
            agent_app=True,
            env={"GH_TOKEN": None},
        )
        add(
            "agent-app changes REPO",
            ["42", "--skip-post-merge"] + q,
            mock={"view": [merged], "agentapp": [("export REPO=other/repo\n", 0)]},
            agent_app=True,
            env={"GH_TOKEN": ""},
        )
        add(
            "agent-app sets TIMEOUT",
            ["42"] + q,
            mock={"view": [merged], "agentapp": [("TIMEOUT=0\n", 0)]},
            agent_app=True,
            env={"GH_TOKEN": None},
        )
        add(
            "agent-app fails",
            ["42", "--skip-post-merge"] + q,
            mock={"view": [merged], "agentapp": [("", 1)]},
            agent_app=True,
            env={"GH_TOKEN": None},
        )
        add(
            "no agent-app BUILD",
            ["42", "--skip-post-merge"] + q,
            mock={"view": [merged]},
            env={"GH_TOKEN": None},
        )
        return S

    def test_programs_end_to_end(self):
        scenarios = self.scenarios()
        results = self.pool.map(
            lambda sc: (sc, self.program("rs", sc), self.program("sh", sc)), scenarios
        )
        # bash 3.2 exits 0 after "unbound variable" in $(( )); bash 5 and the
        # port exit 1 (see arith.rs). Ask this host's bash which it does.
        bash3_script = os.path.join(self.tmp, "unbound.sh")
        write(bash3_script, "set -u\nf(){ local d=$((1 + nope)); }\nf\n")
        quirk = (
            subprocess.run(["bash", bash3_script], capture_output=True).returncode == 0
        )
        print("this bash exits", 0 if quirk else 1, "after an unbound name in $(( ))")
        problems = []
        host_bound = 0
        for sc, rs, sh in results:
            unbound = b"unbound variable" in sh[2] and b"line 209:" in sh[2]
            if quirk and unbound and rs[0] == 1 and sh[0] == 0:
                host_bound += 1
                rs = (sh[0],) + rs[1:]
            for what, a, b in zip(["exit code", "stdout", "stderr", "calls"], rs, sh):
                if a != b:
                    problems.append(
                        "%s: %s differs\n rs=%r\n sh=%r" % (sc["name"], what, a, b)
                    )
        print(
            "end to end:",
            len(scenarios),
            "scenarios,",
            len(problems),
            "differences,",
            host_bound,
            "exit codes left to the host's bash",
        )
        self.assertEqual(problems, [], "\n".join(problems[:15]))


if __name__ == "__main__":
    unittest.main(verbosity=2)
